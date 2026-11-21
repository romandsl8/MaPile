import SwiftUI
import SwiftData

/// Onglet « En cours » : le ou les livres en train d'être lus, avec la page atteinte.
struct ReadingView: View {
    @Query(filter: #Predicate<Book> { $0.statusRaw == "reading" }, sort: \Book.dateAdded, order: .reverse)
    private var reading: [Book]
    @Query(filter: #Predicate<Book> { $0.statusRaw == "toRead" }, sort: \Book.dateAdded, order: .reverse)
    private var pile: [Book]

    @State private var path: [Book] = []
    @State private var showingPicker = false
    @State private var bookToFinish: Book?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if reading.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune lecture en cours", systemImage: "book")
                    } description: {
                        Text("Choisissez un livre de votre PAL pour suivre la page à laquelle vous en êtes.")
                    } actions: {
                        Button {
                            showingPicker = true
                        } label: {
                            Label("Commencer un livre", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(pile.isEmpty)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 20, alignment: .top)], spacing: 20) {
                            ForEach(reading) { book in
                                ReadingCard(book: book,
                                            onOpen: { path.append(book) },
                                            onFinish: { bookToFinish = book })
                            }
                        }
                        .padding()
                        .frame(maxWidth: 1100)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("En cours")
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book) {
                    if !path.isEmpty { path.removeLast() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Commencer un livre", systemImage: "plus") { showingPicker = true }
                        .disabled(pile.isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                StartReadingPicker(books: pile)
            }
            .sheet(item: $bookToFinish) { book in
                FinishBookSheet(book: book)
            }
        }
    }
}

/// Carte d'un livre en cours : couverture, progression et saisie de la page.
struct ReadingCard: View {
    @Bindable var book: Book
    var onOpen: () -> Void
    var onFinish: () -> Void

    @State private var pageText = ""
    @FocusState private var editingPage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CoverView(book: book, cornerRadius: 8)
                    .frame(width: 100)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
                    .onTapGesture(perform: onOpen)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .lineLimit(3)
                    Text(book.displayAuthors)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let start = book.dateStarted {
                        Text("Commencé le \(start.formatted(.dateTime.day().month(.wide)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    progressSummary
                }
            }

            if let progress = book.progress {
                ProgressView(value: progress)
                    .tint(Color.accentColor)
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)
                    .animation(.smooth, value: progress)
            }

            pageControls

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: onFinish) {
                        Label("J'ai fini !", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        withAnimation { book.moveToPile() }
                    } label: {
                        Label("Remettre en PAL", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.regular)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        .onAppear { pageText = String(book.currentPage) }
        .onChange(of: book.currentPage) { _, newValue in
            if !editingPage { pageText = String(newValue) }
        }
        .sensoryFeedback(.selection, trigger: book.currentPage)
    }

    @ViewBuilder
    private var progressSummary: some View {
        if let progress = book.progress {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int((progress * 100).rounded())) %")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("\(max(book.pageCount - book.currentPage, 0)) pages restantes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let finish = book.estimatedFinish {
                    Text("Fin estimée : \(finish.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Indiquez le nombre de pages du livre pour voir votre progression.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pageControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Page")
                    .font(.headline)
                TextField("0", text: $pageText)
                    .keyboardType(.numberPad)
                    .focused($editingPage)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                    .onSubmit(commitPage)
                    .onChange(of: editingPage) { _, focused in if !focused { commitPage() } }
                if book.pageCount > 0 {
                    Text("sur \(book.pageCount)")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("total", value: $book.pageCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 70)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                }
                Spacer()
                if editingPage {
                    Button("OK") { editingPage = false }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                quickButton(-10)
                quickButton(-1)
                quickButton(+1)
                quickButton(+10)
                quickButton(+25)
            }
        }
    }

    private func quickButton(_ delta: Int) -> some View {
        Button(delta > 0 ? "+\(delta)" : "\(delta)") {
            setPage(book.currentPage + delta)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .frame(maxWidth: .infinity)
    }

    private func commitPage() {
        let value = Int(pageText.filter(\.isNumber)) ?? book.currentPage
        setPage(value)
    }

    private func setPage(_ value: Int) {
        var page = max(value, 0)
        if book.pageCount > 0 { page = min(page, book.pageCount) }
        if book.dateStarted == nil { book.dateStarted = .now }
        withAnimation(.snappy) { book.currentPage = page }
        pageText = String(page)
    }
}

/// Choix d'un livre de la PAL à commencer.
struct StartReadingPicker: View {
    let books: [Book]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Book] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return books }
        return books.filter { $0.title.localizedStandardContains(q) || $0.authors.localizedStandardContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { book in
                Button {
                    withAnimation { book.startReading() }
                    dismiss()
                } label: {
                    BookRow(book: book)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Titre ou auteur")
            .navigationTitle("Commencer un livre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView("Votre PAL est vide", systemImage: "books.vertical",
                                           description: Text("Ajoutez d'abord des livres à votre pile à lire."))
                }
            }
        }
    }
}
