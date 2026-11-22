import SwiftUI
import SwiftData

/// Ajout d'un livre : recherche par titre/auteur/ISBN, scan du code-barres ou saisie manuelle.
/// `embedded` : affiché comme onglet de recherche (pas de bouton Fermer, on reste sur place après l'ajout).
struct AddBookView: View {
    let defaultStatus: ReadingStatus
    var embedded = false
    /// Recherche lancée à l'ouverture (ex. « Harry Potter tome 4 »).
    var initialQuery: String = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var library: [Book]
    @State private var query = ""
    @State private var results: [BookResult] = []
    @State private var searching = false
    @State private var searchedOnce = false
    @State private var showingScanner = false
    @State private var path = NavigationPath()
    @State private var toast: String?
    // Sélection multiple (conservée d'une recherche à l'autre).
    @State private var selection: [BookResult] = []
    @State private var showingBulkDate = false
    @State private var bulkDate = Date.now
    @State private var bulkAdding = false
    @State private var bulkDone = 0
    @State private var bulkTotal = 0

    private func isSelected(_ result: BookResult) -> Bool {
        selection.contains { $0.id == result.id }
    }

    private func toggleSelection(_ result: BookResult) {
        if let index = selection.firstIndex(where: { $0.id == result.id }) {
            selection.remove(at: index)
        } else {
            selection.append(result)
        }
    }

    private func isInLibrary(_ result: BookResult) -> Bool {
        library.contains { book in
            if let isbn = result.isbn, let other = book.isbn, isbn == other { return true }
            return BookSearchService.normalize(book.title) == BookSearchService.normalize(result.title)
                && BookSearchService.normalize(book.authorList.first ?? "") == BookSearchService.normalize(result.authors.first ?? "")
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    introSection
                } else if searching && results.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Recherche…")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if results.isEmpty && searchedOnce {
                    ContentUnavailableView {
                        Label("Aucun résultat", systemImage: "magnifyingglass")
                    } description: {
                        Text("Essayez avec un autre titre, le nom de l'auteur ou l'ISBN.")
                    } actions: {
                        NavigationLink("Saisir le livre à la main", value: AddRoute.manual)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(results) { result in
                            // Rond à cocher toujours visible : sélection multiple sans mode à activer.
                            HStack(spacing: 12) {
                                Button {
                                    withAnimation(.snappy) { toggleSelection(result) }
                                } label: {
                                    Image(systemName: isSelected(result) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(isSelected(result) ? Color.accentColor : Color.secondary)
                                        .frame(width: 34, height: 44)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(isSelected(result) ? "Désélectionner" : "Sélectionner")
                                .sensoryFeedback(.selection, trigger: isSelected(result))
                                NavigationLink(value: AddRoute.preview(result)) {
                                    HStack(spacing: 8) {
                                        ResultRow(result: result)
                                        Spacer(minLength: 0)
                                        if isInLibrary(result) {
                                            Text("Déjà ajouté").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Label("Cochez ◯ pour ajouter plusieurs livres d'un coup", systemImage: "checklist")
                            .font(.footnote)
                            .textCase(nil)
                    } footer: {
                        Text("Sources : Google Books, Open Library et Apple Books.")
                    }
                }
            }
            .navigationTitle(embedded ? "Ajouter un livre" : (defaultStatus == .read ? "Ajouter un livre lu" : "Ajouter à ma PAL"))
            .navigationBarTitleDisplayMode(embedded ? .large : .inline)
            .searchable(text: $query, prompt: "Titre, auteur ou ISBN")
            .onAppear { if query.isEmpty, !initialQuery.isEmpty { query = initialQuery } }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                await runSearch()
            }
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Scanner", systemImage: "barcode.viewfinder") { showingScanner = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selection.isEmpty {
                    bulkBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingBulkDate) {
                BulkFinishDateSheet(date: $bulkDate, count: selection.count) {
                    Task { await addSelection(as: .read, finishedOn: bulkDate) }
                }
            }
            .navigationDestination(for: AddRoute.self) { route in
                switch route {
                case .preview(let result):
                    BookPreviewView(result: result, defaultStatus: defaultStatus) { finished() }
                case .manual:
                    ManualBookView(defaultStatus: defaultStatus, initialTitle: query) { finished() }
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerSheet { isbn in
                    showingScanner = false
                    query = isbn
                }
            }
        }
        .overlay {
            if bulkAdding {
                VStack(spacing: 10) {
                    ProgressView(value: Double(bulkDone), total: Double(max(bulkTotal, 1)))
                        .frame(width: 180)
                    Text("Ajout de \(bulkDone)/\(bulkTotal) livres…")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
                .padding(22)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.tint(.green.opacity(0.3)))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: toast)
    }

    /// Après un ajout : on ferme la feuille, ou (en onglet) on revient à la recherche avec un message.
    private func finished() {
        guard embedded else {
            dismiss()
            return
        }
        path = NavigationPath()
        query = ""
        showToast("Livre ajouté à votre bibliothèque")
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.snappy) { toast = nil }
        }
    }

    /// Barre du bas en mode sélection : ajouter toute la sélection à la PAL ou aux livres lus.
    private var bulkBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text(selection.count > 1 ? "\(selection.count) livres sélectionnés" : "1 livre sélectionné")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Tout désélectionner") {
                    withAnimation(.snappy) { selection = [] }
                }
                .font(.subheadline)
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await addSelection(as: .toRead, finishedOn: nil) }
                    } label: {
                        Label("Ajouter à ma PAL", systemImage: "books.vertical.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        bulkDate = .now
                        showingBulkDate = true
                    } label: {
                        Label("Déjà lus", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
                .disabled(bulkAdding)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Ajoute tous les livres sélectionnés (sauf ceux déjà présents), avec leurs infos complètes et la meilleure couverture.
    private func addSelection(as status: ReadingStatus, finishedOn: Date?) async {
        let items = selection
        bulkTotal = items.count
        bulkDone = 0
        bulkAdding = true
        var added = 0
        for result in items {
            if isInLibrary(result) {
                bulkDone += 1
                continue
            }
            let full = await BookSearchService.enrich(result)
            let book = Book(result: full, status: status)
            if status == .read, let finishedOn { book.dateFinished = finishedOn }
            if let best = await BookSearchService.bestCover(BookSearchService.coverCandidates(for: full)) {
                book.coverData = best.data
                book.coverURLString = best.url.absoluteString
            }
            book.lastCheckedAt = .now
            context.insert(book)
            added += 1
            bulkDone += 1
        }
        try? context.save()
        bulkAdding = false
        withAnimation(.snappy) {
            selection = []
        }
        let destination = status == .read ? "vos livres lus" : "votre PAL"
        if added == 0 {
            showToast("Ces livres sont déjà dans votre bibliothèque")
        } else if added == 1 {
            showToast("1 livre ajouté à " + destination)
        } else {
            showToast("\(added) livres ajoutés à " + destination)
        }
        if !embedded {
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        }
    }

    private var introSection: some View {
        Section {
            Button {
                showingScanner = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scanner le code-barres")
                        Text("Le code ISBN au dos du livre").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "barcode.viewfinder")
                }
            }
            NavigationLink(value: AddRoute.manual) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saisir à la main")
                        Text("Si le livre est introuvable").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
            }
        } footer: {
            Text("Ou tapez un titre, un auteur ou un ISBN dans la barre de recherche.")
        }
    }

    private func runSearch() async {
        let q = query
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else {
            results = []
            searchedOnce = false
            return
        }
        searching = true
        let found = await BookSearchService.search(q)
        guard q == query else { return }
        results = found
        searching = false
        searchedOnce = true
    }
}

enum AddRoute: Hashable {
    case preview(BookResult)
    case manual
}

private struct ResultRow: View {
    let result: BookResult

    var body: some View {
        HStack(spacing: 14) {
            CoverView(data: nil, url: result.coverURL, title: result.title, cornerRadius: 5)
                .frame(width: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title).font(.headline).lineLimit(2)
                if !result.authors.isEmpty {
                    Text(result.authors.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let rating = result.averageRating {
                        StarRatingDisplay(rating: rating, size: 10)
                        Text(rating.frenchDecimal)
                    }
                    if let date = result.publishedDate { Text(String(date.prefix(4))) }
                    if let pages = result.pageCount, pages > 0 { Text("\(pages) p.") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Aperçu d'un résultat avant de l'ajouter.
struct BookPreviewView: View {
    @State var result: BookResult
    let defaultStatus: ReadingStatus
    var onAdded: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var library: [Book]
    @State private var loadingDetails = true
    @State private var adding = false
    @State private var justFinished: Book?

    private var alreadyInLibrary: Book? {
        library.first { book in
            if let isbn = result.isbn, let other = book.isbn, isbn == other { return true }
            return BookSearchService.normalize(book.title) == BookSearchService.normalize(result.title)
                && BookSearchService.normalize(book.authorList.first ?? "") == BookSearchService.normalize(result.authors.first ?? "")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                CoverView(data: nil, url: result.coverURL, title: result.title, cornerRadius: 10)
                    .frame(width: 150)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                    .padding(.top)
                VStack(spacing: 6) {
                    Text(result.title)
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(result.authors.joined(separator: ", "))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let existing = alreadyInLibrary {
                    Label("Déjà dans « \(existing.status.longTitle) »", systemImage: "info.circle")
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.tint(.yellow.opacity(0.3)))
                }

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        addButton(.toRead, label: "Ajouter à ma PAL", icon: "books.vertical.fill",
                                  prominent: defaultStatus == .toRead)
                        addButton(.read, label: "Je l'ai déjà lu", icon: "checkmark.seal.fill",
                                  prominent: defaultStatus == .read)
                    }
                    .controlSize(.large)
                }

                SectionCard(title: "Note des lecteurs", systemImage: "person.2") {
                    if let rating = result.averageRating {
                        HStack(spacing: 10) {
                            Text(rating.frenchDecimal).font(.title.bold())
                            StarRatingDisplay(rating: rating, size: 14)
                            if let count = result.ratingsCount {
                                Text("(\(count) avis)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else if loadingDetails {
                        ProgressView()
                    } else {
                        Text("Pas de note disponible.").foregroundStyle(.secondary)
                    }
                }

                if !result.summary.isEmpty {
                    SectionCard(title: "Résumé", systemImage: "text.alignleft") {
                        Text(result.summary)
                    }
                } else if loadingDetails {
                    ProgressView("Recherche du résumé…")
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            result = await BookSearchService.enrich(result)
            loadingDetails = false
        }
        // « Je l'ai déjà lu » : on demande la date de fin (et la note) avant de terminer.
        .sheet(item: $justFinished, onDismiss: { onAdded() }) { book in
            FinishBookSheet(book: book)
        }
    }

    @ViewBuilder
    private func addButton(_ status: ReadingStatus, label: String, icon: String, prominent: Bool) -> some View {
        let button = Button {
            Task { await add(as: status) }
        } label: {
            Label(label, systemImage: icon).frame(maxWidth: .infinity)
        }
        .disabled(adding)
        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func add(as status: ReadingStatus) async {
        adding = true
        let book = Book(result: result, status: status)
        // On télécharge toutes les couvertures possibles et on garde la plus grande.
        if let best = await BookSearchService.bestCover(BookSearchService.coverCandidates(for: result)) {
            book.coverData = best.data
            book.coverURLString = best.url.absoluteString
        } else {
            book.coverData = await BookSearchService.downloadImage(result.coverURL)
        }
        book.lastCheckedAt = .now
        context.insert(book)
        try? context.save()
        adding = false
        if status == .read {
            justFinished = book
        } else {
            onAdded()
        }
    }
}

/// Saisie manuelle quand le livre est introuvable en ligne.
struct ManualBookView: View {
    let defaultStatus: ReadingStatus
    var initialTitle: String = ""
    var onAdded: () -> Void

    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var authors = ""
    @State private var pages: Int?
    @State private var status: ReadingStatus = .toRead
    @State private var rating = 0
    @State private var finishedOn = Date.now

    var body: some View {
        Form {
            Section("Livre") {
                TextField("Titre", text: $title)
                TextField("Auteur(s)", text: $authors)
                TextField("Nombre de pages", value: $pages, format: .number)
                    .keyboardType(.numberPad)
            }
            Section {
                Picker("Ajouter à", selection: $status) {
                    ForEach(ReadingStatus.allCases) { Text($0.longTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                if status == .read {
                    DatePicker("Terminé le", selection: $finishedOn, in: ...Date.now, displayedComponents: .date)
                    StarRatingPicker(rating: $rating)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Saisie manuelle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Ajouter", systemImage: "checkmark") {
                    let book = Book(title: title.trimmingCharacters(in: .whitespaces),
                                    authors: authors.trimmingCharacters(in: .whitespaces),
                                    status: status)
                    book.pageCount = pages ?? 0
                    book.myRating = status == .read ? rating : 0
                    if status == .read { book.dateFinished = finishedOn }
                    context.insert(book)
                    try? context.save()
                    onAdded()
                }
                .buttonStyle(.glassProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            status = defaultStatus
            if title.isEmpty, BookSearchService.normalizedISBN(initialTitle) == nil { title = initialTitle }
        }
    }
}

/// Date de fin commune quand on ajoute plusieurs livres déjà lus d'un coup.
struct BulkFinishDateSheet: View {
    @Binding var date: Date
    let count: Int
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Terminés le", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Cette date sera appliquée aux \(count) livres. Vous pourrez la changer ensuite livre par livre, depuis leur fiche (« Terminé le »).")
                }
            }
            .navigationTitle(count > 1 ? "\(count) livres lus" : "1 livre lu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter", systemImage: "checkmark") {
                        dismiss()
                        onConfirm()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
