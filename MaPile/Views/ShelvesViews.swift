import SwiftUI
import SwiftData

// MARK: - Rangée « Mes piles » (en haut de la PAL et des Lus)

struct ShelvesRow: View {
    @Query(sort: \Shelf.createdAt) private var shelves: [Shelf]
    @Query private var allBooks: [Book]
    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mes piles")
                .font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(shelves) { shelf in
                        NavigationLink(value: shelf) {
                            ShelfCard(shelf: shelf, books: shelf.books(from: allBooks))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showingEditor = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .frame(width: 110, height: 120)
                                .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 14))
                            Text("Nouvelle pile")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .sheet(isPresented: $showingEditor) { ShelfEditorSheet(shelf: nil) }
    }
}

/// Vignette d'une pile : jusqu'à trois couvertures empilées.
struct ShelfCard: View {
    let shelf: Shelf
    let books: [Book]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(shelf.color.opacity(0.18).gradient)
                if books.isEmpty {
                    Text(shelf.emoji).font(.system(size: 40))
                } else {
                    ForEach(Array(books.prefix(3).enumerated().reversed()), id: \.offset) { index, book in
                        CoverView(book: book, cornerRadius: 4)
                            .frame(width: 58)
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                            .rotationEffect(.degrees(Double(index) * 7 - 7))
                            .offset(x: CGFloat(index) * 14 - 14)
                    }
                }
            }
            .frame(width: 110, height: 120)
            HStack(spacing: 4) {
                Text(shelf.emoji)
                Text(shelf.name).lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .frame(width: 110, alignment: .leading)
            Text(books.count > 1 ? "\(books.count) livres" : "\(books.count) livre")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Détail d'une pile

struct ShelfDetailView: View {
    @Bindable var shelf: Shelf
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Book]
    @State private var showingEditor = false
    @State private var showingPicker = false
    @State private var confirmDelete = false
    @State private var shareImage: Image?

    private var books: [Book] { shelf.books(from: allBooks) }

    private var payload: ShelfPayload {
        ShelfSharing.payload(name: shelf.name, emoji: shelf.emoji, colorIndex: shelf.colorIndex, books: books)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if books.isEmpty {
                    ContentUnavailableView {
                        Label("Pile vide", systemImage: "square.stack")
                    } description: {
                        Text(shelf.kind == .custom
                             ? "Ajoutez des livres de votre bibliothèque à cette pile."
                             : "Aucun livre de votre bibliothèque ne correspond pour l'instant.")
                    } actions: {
                        if shelf.kind == .custom {
                            Button("Ajouter des livres", systemImage: "plus") { showingPicker = true }
                                .buttonStyle(.glassProminent)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 18, alignment: .bottom)],
                              spacing: 24) {
                        ForEach(books) { book in
                            NavigationLink(value: book) {
                                BookGridCell(book: book) {
                                    if shelf.kind == .custom {
                                        Button("Retirer de la pile", systemImage: "minus.circle") {
                                            withAnimation { shelf.toggle(book) }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(shelf.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showingEditor) { ShelfEditorSheet(shelf: shelf) }
        .sheet(isPresented: $showingPicker) { ShelfBookPicker(shelf: shelf) }
        .confirmationDialog("Supprimer la pile « \(shelf.name) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer la pile", role: .destructive) {
                context.delete(shelf)
                dismiss()
            }
        } message: {
            Text("Les livres restent dans votre bibliothèque.")
        }
        .task(id: books.count) { shareImage = ShelfImageRenderer.image(shelf: shelf, books: books) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(shelf.emoji)
                .font(.system(size: 36))
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(shelf.color.opacity(0.35)), in: .rect(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text(shelf.name)
                    .font(.system(.title2, design: .serif).weight(.bold))
                HStack(spacing: 6) {
                    Label(shelf.kind.label, systemImage: shelf.kind.systemImage)
                    if shelf.kind != .custom { Text("· \(shelf.criterion)") }
                    Text("· \(books.count) livre\(books.count > 1 ? "s" : "")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let url = ShelfSharing.webURL(for: payload) {
                ShareLink(item: url,
                          subject: Text("Ma pile « \(shelf.name) »"),
                          message: Text("\(shelf.emoji) Ma pile « \(shelf.name) » sur MaPile\nPas encore l'app ? Téléchargez MaPile gratuitement : \(ShelfSharing.appStoreURL.absoluteString)")) {
                    Label("Partager le lien", systemImage: "square.and.arrow.up")
                }
                .disabled(books.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let shareImage {
                    ShareLink(item: shareImage,
                              preview: SharePreview("Ma pile « \(shelf.name) »", image: shareImage)) {
                        Label("Partager en image", systemImage: "photo")
                    }
                }
                if shelf.kind == .custom {
                    Button("Ajouter ou retirer des livres", systemImage: "checklist") { showingPicker = true }
                }
                Button("Modifier la pile", systemImage: "pencil") { showingEditor = true }
                Divider()
                Button("Supprimer la pile", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Label("Plus", systemImage: "ellipsis")
            }
        }
    }
}

// MARK: - Création / modification d'une pile

struct ShelfEditorSheet: View {
    let shelf: Shelf?
    var addingBook: Book? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Book]
    @State private var name = ""
    @State private var emoji = "📚"
    @State private var colorIndex = 0
    @State private var kind: ShelfKind = .custom
    @State private var criterion = ""

    private let emojis = ["📚", "❤️", "⭐️", "🔥", "🌙", "☀️", "🏖️", "🎄", "🧠", "🕵️", "🐉", "🚀", "💼", "🎁", "🌿", "☕️"]

    private var authors: [String] {
        Array(Set(allBooks.flatMap { $0.authorList })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var seriesNames: [String] {
        Array(Set(allBooks.map { $0.seriesName }.filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var criterionTitle: String {
        switch kind {
        case .author: "Auteur"
        case .genre: "Genre"
        case .series: "Série"
        case .custom: ""
        }
    }

    private var criterionOptions: [String] {
        switch kind {
        case .author: authors
        case .genre: genres
        case .series: seriesNames
        case .custom: []
        }
    }

    private var genres: [String] {
        Array(Set(allBooks.flatMap { $0.genreList })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        return kind == .custom ? hasName : !criterion.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type de pile", selection: $kind) {
                        ForEach(ShelfKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind == .custom
                         ? "Vous choisissez les livres vous-même."
                         : "La pile se remplit toute seule avec les livres correspondants de votre bibliothèque.")
                }

                if kind != .custom {
                    Section(criterionTitle) {
                        let options = criterionOptions
                        if !options.isEmpty {
                            Picker("Choisir", selection: $criterion) {
                                Text("—").tag("")
                                ForEach(options, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        TextField("Nom : " + criterionTitle.lowercased(), text: $criterion)
                    }
                }

                Section("Nom") {
                    TextField(kind == .custom ? "Ex. Été 2027, Coups de cœur…" : "Facultatif (sinon : \(criterion))", text: $name)
                }

                Section("Émoji") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(emojis, id: \.self) { item in
                            Text(item)
                                .font(.title2)
                                .frame(width: 38, height: 38)
                                .background(emoji == item ? Color.accentColor.opacity(0.2) : .clear, in: .circle)
                                .onTapGesture { emoji = item }
                        }
                    }
                }

                Section("Couleur") {
                    HStack(spacing: 10) {
                        ForEach(Shelf.palette.indices, id: \.self) { index in
                            Circle()
                                .fill(Shelf.palette[index].gradient)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if colorIndex == index {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { colorIndex = index }
                        }
                    }
                }
            }
            .navigationTitle(shelf == nil ? "Nouvelle pile" : "Modifier la pile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", systemImage: "checkmark") { save() }
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let shelf {
                    name = shelf.name
                    emoji = shelf.emoji
                    colorIndex = shelf.colorIndex
                    kind = shelf.kind
                    criterion = shelf.criterion
                } else {
                    colorIndex = Int.random(in: 0..<Shelf.palette.count)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCriterion = criterion.trimmingCharacters(in: .whitespaces)
        let finalName = trimmedName.isEmpty ? trimmedCriterion : trimmedName
        let target = shelf ?? Shelf(name: finalName)
        target.name = finalName
        target.emoji = emoji
        target.colorIndex = colorIndex
        target.kind = kind
        target.criterion = kind == .custom ? "" : trimmedCriterion
        if let addingBook, kind == .custom, !target.contains(addingBook) { target.toggle(addingBook) }
        if shelf == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}

// MARK: - Choix des livres d'une pile personnalisée

struct ShelfBookPicker: View {
    @Bindable var shelf: Shelf
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Book.title) private var allBooks: [Book]
    @State private var search = ""

    private var filtered: [Book] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allBooks }
        return allBooks.filter { $0.title.localizedStandardContains(q) || $0.authors.localizedStandardContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { book in
                Button {
                    withAnimation { shelf.toggle(book) }
                } label: {
                    HStack {
                        BookRow(book: book)
                        Spacer()
                        Image(systemName: shelf.contains(book) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(shelf.contains(book) ? Color.accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Titre ou auteur")
            .navigationTitle(shelf.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

// MARK: - « Ajouter à une pile » depuis la fiche d'un livre

struct AddToShelfSheet: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Shelf.createdAt) private var shelves: [Shelf]
    @State private var showingEditor = false

    private var customShelves: [Shelf] { shelves.filter { $0.kind == .custom } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(customShelves) { shelf in
                        Button {
                            withAnimation { shelf.toggle(book) }
                        } label: {
                            HStack {
                                Text(shelf.emoji)
                                Text(shelf.name)
                                Spacer()
                                Image(systemName: shelf.contains(book) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(shelf.contains(book) ? Color.accentColor : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Nouvelle pile", systemImage: "plus") { showingEditor = true }
                } footer: {
                    Text("Les piles par auteur ou par genre se remplissent toutes seules.")
                }
            }
            .navigationTitle("Ajouter à une pile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditor) { ShelfEditorSheet(shelf: nil, addingBook: book) }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Image de partage

/// Carte « Ma pile » rendue en image (couvertures + titre), à partager sur les réseaux.
struct ShelfShareCard: View {
    let name: String
    let emoji: String
    let color: Color
    let books: [Book]

    /// Couvertures par rangées de 4 (12 au maximum).
    private var rows: [[Book]] {
        let shown = Array(books.prefix(12))
        var result: [[Book]] = []
        var index = 0
        while index < shown.count {
            result.append(Array(shown[index..<min(index + 4, shown.count)]))
            index += 4
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(emoji).font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .lineLimit(2)
                    Text(books.count > 1 ? "\(books.count) livres" : "\(books.count) livre")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            // Grille non « lazy » : ImageRenderer n'affiche pas les grilles lazy.
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(rows[row]) { book in
                            CoverView(data: book.coverData, url: nil, title: book.title, cornerRadius: 6)
                                .frame(width: 150)
                                .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Text("📚 MaPile")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(36)
        .frame(width: 720)
        .background(
            LinearGradient(colors: [color.opacity(0.25), Color(white: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .light)
    }
}

@MainActor
enum ShelfImageRenderer {
    static func image(shelf: Shelf, books: [Book]) -> Image? {
        guard !books.isEmpty else { return nil }
        let renderer = ImageRenderer(content: ShelfShareCard(name: shelf.name, emoji: shelf.emoji, color: shelf.color, books: books))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }
}

// MARK: - Import d'une pile reçue par lien

struct ShelfImportRequest: Identifiable {
    let id = UUID()
    let payload: ShelfPayload
}

struct ImportShelfSheet: View {
    let payload: ShelfPayload
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var library: [Book]
    @State private var addMissing = true
    @State private var importing = false

    private func existing(_ entry: ShelfPayload.Entry) -> Book? {
        library.first { book in
            if !entry.isbn.isEmpty, book.isbn == entry.isbn { return true }
            return BookSearchService.normalize(book.title) == BookSearchService.normalize(entry.title)
                && BookSearchService.normalize(book.authorList.first ?? "") == BookSearchService.normalize(entry.author)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Text(payload.e).font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text(payload.n).font(.title3.weight(.bold))
                            Text("\(payload.b.count) livre\(payload.b.count > 1 ? "s" : "")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Livres") {
                    ForEach(payload.entries, id: \.self) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.title).font(.headline)
                                Text(entry.author).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if existing(entry) != nil {
                                Text("Déjà chez vous").font(.caption).foregroundStyle(.green)
                            }
                        }
                    }
                }
                Section {
                    Toggle("Ajouter les livres absents à ma PAL", isOn: $addMissing)
                }
            }
            .navigationTitle("Pile partagée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importer", systemImage: "square.and.arrow.down") { importShelf() }
                        .buttonStyle(.glassProminent)
                        .disabled(importing)
                }
            }
        }
    }

    private func importShelf() {
        importing = true
        let shelf = Shelf(name: payload.n, emoji: payload.e, colorIndex: payload.c, kind: .custom)
        var created: [Book] = []
        for entry in payload.entries {
            if let book = existing(entry) {
                shelf.bookIDs.append(book.uuid.uuidString)
            } else if addMissing, !entry.title.isEmpty {
                let book = Book(title: entry.title, authors: entry.author, status: .toRead)
                if !entry.isbn.isEmpty { book.isbn = entry.isbn }
                context.insert(book)
                shelf.bookIDs.append(book.uuid.uuidString)
                created.append(book)
            }
        }
        context.insert(shelf)
        try? context.save()
        // Les livres ajoutés récupèrent couverture, résumé et note en arrière-plan.
        Task { @MainActor in
            for book in created {
                await BookUpdater.check(book)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        dismiss()
    }
}
