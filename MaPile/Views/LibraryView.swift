import SwiftUI
import SwiftData

/// Onglet « Lus » ou « PAL ». Plié : liste puis fiche. Déplié : liste et fiche côte à côte.
struct LibraryView: View {
    let status: ReadingStatus

    @Environment(\.modelContext) private var context
    @Query private var books: [Book]
    @State private var selection: Book?
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var bookToFinish: Book?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage private var sortRaw: String
    @AppStorage private var gridLayout: Bool

    init(status: ReadingStatus) {
        self.status = status
        let raw = status.rawValue
        _books = Query(filter: #Predicate<Book> { $0.statusRaw == raw }, sort: \Book.dateAdded, order: .reverse)
        _sortRaw = AppStorage(wrappedValue: status == .read ? LibrarySort.finished.rawValue : LibrarySort.added.rawValue,
                              "sort-\(raw)")
        _gridLayout = AppStorage(wrappedValue: false, "grid-\(raw)")
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            content
                .navigationTitle(status.longTitle)
                .searchable(text: $searchText, prompt: "Titre ou auteur")
                .toolbar { toolbar }
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            if let selection {
                BookDetailView(book: selection) { self.selection = nil }
                    .id(selection.uuid)
            } else {
                ContentUnavailableView("Choisissez un livre",
                                       systemImage: "book",
                                       description: Text("Sa fiche s'affichera ici."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // Argument de lancement « -openFirst YES » : ouvre le premier livre (captures d'écran).
            if selection == nil, UserDefaults.standard.bool(forKey: "openFirst") { selection = displayed.first }
        }
        .sheet(isPresented: $showingAdd) {
            AddBookView(defaultStatus: status)
        }
        .sheet(item: $bookToFinish) { book in
            FinishBookSheet(book: book)
        }
    }

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            emptyState
        } else if displayed.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if gridLayout {
            grid
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
        List(selection: $selection) {
            Section {
                ForEach(displayed) { book in
                    NavigationLink(value: book) {
                        BookRow(book: book)
                    }
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

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 16)],
                      alignment: .leading, spacing: 20) {
                ForEach(displayed) { book in
                    Button {
                        selection = book
                    } label: {
                        BookGridCell(book: book, isSelected: selection == book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextActions(for: book) }
                }
            }
            .padding()
            Text(countText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom)
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
                    ForEach(LibrarySort.allCases.filter { status == .read || $0 != .finished }) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                Divider()
                Picker("Affichage", selection: $gridLayout) {
                    Label("Liste", systemImage: "list.bullet").tag(false)
                    Label("Couvertures", systemImage: "square.grid.2x2").tag(true)
                }
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
                if selection == book { selection = nil }
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

struct BookGridCell: View {
    let book: Book
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(book: book, cornerRadius: 8)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
            Text(book.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text(book.displayAuthors)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if book.myRating > 0 {
                StarRatingDisplay(rating: Double(book.myRating), size: 9)
            }
        }
        .contentShape(.rect)
    }
}
