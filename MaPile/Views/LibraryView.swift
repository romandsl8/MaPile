import SwiftUI
import SwiftData

/// Onglet « Lus » ou « PAL » : galerie de couvertures plein écran, comme l'app Livres.
/// Toucher une couverture ouvre la fiche en plein écran (avec un effet de zoom).
struct LibraryView: View {
    let status: ReadingStatus

    @Environment(\.modelContext) private var context
    @Query private var books: [Book]
    @State private var path: [Book] = []
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var bookToFinish: Book?
    @Query private var allBooks: [Book]
    @State private var updateTask: Task<Void, Never>?
    @State private var updateDone = 0
    @State private var updateTotal = 0
    @State private var updateImproved = 0
    @State private var updateSummary: String?
    @Namespace private var zoom
    @AppStorage private var sortRaw: String
    @AppStorage private var gridLayout: Bool

    init(status: ReadingStatus) {
        self.status = status
        let raw = status.rawValue
        _books = Query(filter: #Predicate<Book> { $0.statusRaw == raw }, sort: \Book.dateAdded, order: .reverse)
        _sortRaw = AppStorage(wrappedValue: status == .read ? LibrarySort.finished.rawValue : LibrarySort.added.rawValue,
                              "sort-\(raw)")
        _gridLayout = AppStorage(wrappedValue: true, "gallery-\(raw)")
    }

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .added }

    private var displayed: [Book] {
        let filtered: [Book]
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            filtered = books
        } else {
            filtered = books.filter {
                $0.title.localizedStandardContains(q) || $0.authors.localizedStandardContains(q)
            }
        }
        return sort.sorted(filtered)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(status.longTitle)
                .searchable(text: $searchText, prompt: "Titre ou auteur")
                .toolbar { toolbar }
                .navigationDestination(for: Book.self) { book in
                    BookDetailView(book: book) {
                        if !path.isEmpty { path.removeLast() }
                    }
                    .navigationTransition(.zoom(sourceID: book.uuid, in: zoom))
                }
        }
        .onAppear {
            // Argument de lancement « -openFirst YES » : ouvre le premier livre (captures d'écran).
            if path.isEmpty, UserDefaults.standard.bool(forKey: "openFirst"), let first = displayed.first {
                path = [first]
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddBookView(defaultStatus: status)
        }
        .sheet(item: $bookToFinish) { book in
            FinishBookSheet(book: book)
        }
        .overlay(alignment: .bottom) {
            if updateTask != nil {
                HStack(spacing: 12) {
                    ProgressView(value: Double(updateDone), total: Double(max(updateTotal, 1)))
                        .frame(width: 110)
                    Text("Vérification \(updateDone)/\(updateTotal)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Button("Arrêter", systemImage: "xmark") {
                        updateTask?.cancel()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect()
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert(updateSummary ?? "", isPresented: Binding(get: { updateSummary != nil }, set: { if !$0 { updateSummary = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Vérifie tous les livres un par un : note avec le plus d'avis, infos manquantes, meilleure couverture.
    private func startBulkUpdate() {
        let books = allBooks
        updateDone = 0
        updateTotal = books.count
        updateImproved = 0
        updateTask = Task {
            for book in books {
                if Task.isCancelled { break }
                if case .updated = await BookUpdater.check(book) { updateImproved += 1 }
                updateDone += 1
                // Petite pause : les services gratuits limitent le nombre de requêtes par minute.
                try? await Task.sleep(for: .seconds(2))
            }
            try? context.save()
            let improved: Int = updateImproved
            if improved == 0 {
                updateSummary = "Toutes les fiches vérifiées sont déjà à jour."
            } else if improved == 1 {
                updateSummary = "1 fiche mise à jour (note, résumé ou couverture)."
            } else {
                updateSummary = "\(improved) fiches mises à jour (note, résumé ou couverture)."
            }
            withAnimation { updateTask = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            emptyState
        } else if displayed.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if gridLayout {
            gallery
        } else {
            list
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(status == .read ? "Aucun livre lu" : "Votre pile est vide", systemImage: status.systemImage)
        } description: {
            Text(status == .read
                 ? "Ajoutez les livres que vous avez terminés pour suivre vos lectures."
                 : "Ajoutez les livres que vous avez envie de lire.")
        } actions: {
            Button {
                showingAdd = true
            } label: {
                Label("Ajouter un livre", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(displayed) { book in
                    NavigationLink(value: book) {
                        BookRow(book: book)
                    }
                    .matchedTransitionSource(id: book.uuid, in: zoom)
                    .swipeActions(edge: .leading) { statusSwipe(for: book) }
                    .contextMenu { contextActions(for: book) }
                }
                .onDelete { offsets in
                    let items = offsets.map { displayed[$0] }
                    delete(items)
                }
            } footer: {
                Text(countText)
            }
        }
    }

    /// Galerie plein écran : 2 colonnes sur l'iPhone plié, davantage une fois déplié.
    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 210), spacing: 22, alignment: .bottom)],
                      alignment: .center, spacing: 30) {
                ForEach(displayed) { book in
                    BookGridCell(book: book) { contextActions(for: book) }
                        .matchedTransitionSource(id: book.uuid, in: zoom)
                        .contentShape(.rect)
                        .onTapGesture { path.append(book) }
                        .contextMenu { contextActions(for: book) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Text(countText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
        }
    }

    private var countText: String {
        let n = displayed.count
        return "\(n) livre\(n > 1 ? "s" : "")"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Trier par", selection: $sortRaw) {
                    ForEach(LibrarySort.allCases.filter { status == .read || ($0 != .finished && $0 != .rating) }) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                Divider()
                Picker("Affichage", selection: $gridLayout) {
                    Label("Liste", systemImage: "list.bullet").tag(false)
                    Label("Galerie", systemImage: "square.grid.2x2").tag(true)
                }
                Divider()
                Button("Mettre à jour toute la bibliothèque", systemImage: "arrow.triangle.2.circlepath") {
                    startBulkUpdate()
                }
                .disabled(updateTask != nil || allBooks.isEmpty)
            } label: {
                Label("Options", systemImage: "line.3.horizontal.decrease")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingAdd = true
            } label: {
                Label("Ajouter", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func statusSwipe(for book: Book) -> some View {
        if book.status == .toRead {
            Button {
                bookToFinish = book
            } label: {
                Label("Lu !", systemImage: "checkmark")
            }
            .tint(.green)
        } else {
            Button {
                withAnimation { book.moveToPile() }
            } label: {
                Label("PAL", systemImage: "books.vertical")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func contextActions(for book: Book) -> some View {
        if book.status == .toRead {
            Button("J'ai fini ce livre", systemImage: "checkmark.seal") { bookToFinish = book }
        } else {
            Button("Remettre dans la PAL", systemImage: "books.vertical") {
                withAnimation { book.moveToPile() }
            }
        }
        Button("Supprimer", systemImage: "trash", role: .destructive) { delete([book]) }
    }

    private func delete(_ items: [Book]) {
        withAnimation {
            for book in items {
                context.delete(book)
            }
        }
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 14) {
            CoverView(book: book, cornerRadius: 5)
                .frame(width: 48)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.displayAuthors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if book.status == .read {
                        if book.myRating > 0 {
                            StarRatingDisplay(rating: Double(book.myRating), size: 11)
                        }
                        Text(book.finishedOn, format: .dateTime.day().month(.abbreviated).year())
                    } else if let rating = book.communityRating {
                        Image(systemName: "person.2.fill")
                        Text(rating.frenchDecimal)
                    }
                    if book.pageCount > 0 {
                        Text("\(book.pageCount) p.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Case de la galerie, à la manière de l'app Livres : la couverture seule,
/// puis une petite ligne d'infos et le bouton « … ».
struct BookGridCell<MenuContent: View>: View {
    let book: Book
    @ViewBuilder var menu: () -> MenuContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(book: book, cornerRadius: 6)
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 5)
            HStack(spacing: 6) {
                info
                Spacer(minLength: 0)
                Menu {
                    menu()
                } label: {
                    Label("Options", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 24)
                        .contentShape(.rect)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(book.title), \(book.displayAuthors)")
    }

    @ViewBuilder
    private var info: some View {
        if book.status == .read {
            if book.myRating > 0 {
                StarRatingDisplay(rating: Double(book.myRating), size: 10)
            } else {
                Text("LU")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else if let rating = book.communityRating {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text(rating.frenchDecimal)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        } else {
            Text("NOUVEAU")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
