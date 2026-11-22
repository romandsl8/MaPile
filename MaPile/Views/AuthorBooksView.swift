import SwiftUI
import SwiftData

/// Identifiant d'un auteur pour ouvrir la feuille de ses livres.
struct AuthorRef: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

/// Les livres d'un auteur : ceux déjà dans la bibliothèque, puis ses autres œuvres trouvées en ligne.
struct AuthorBooksView: View {
    let author: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var library: [Book]
    @State private var results: [BookResult] = []
    @State private var loading = true
    @State private var adding: Set<String> = []

    private var authorKey: String { BookSearchService.normalize(author) }

    private var mine: [Book] {
        library.filter { book in book.authorList.contains { BookSearchService.normalize($0) == authorKey } }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func inLibrary(_ result: BookResult) -> Bool {
        let title = BookSearchService.normalize(result.title)
        return library.contains { book in
            if let isbn = result.isbn, let other = book.isbn, isbn == other { return true }
            return BookSearchService.normalize(book.title) == title
        }
    }

    private var others: [BookResult] {
        results.filter { !inLibrary($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !mine.isEmpty {
                    Section("Dans votre bibliothèque") {
                        ForEach(mine) { book in
                            HStack(spacing: 12) {
                                BookRow(book: book)
                                Spacer(minLength: 0)
                                Image(systemName: book.status.systemImage)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(book.status.longTitle)
                            }
                        }
                    }
                }
                Section {
                    if loading {
                        HStack {
                            ProgressView()
                            Text("Recherche des livres de \(author)…")
                                .foregroundStyle(.secondary)
                        }
                    } else if others.isEmpty {
                        Text("Aucun autre livre trouvé pour cet auteur.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(others) { result in
                            HStack(spacing: 10) {
                                NavigationLink {
                                    BookPreviewView(result: result, defaultStatus: .toRead, onAdded: {})
                                } label: {
                                    ResultRow(result: result)
                                }
                                quickAdd(result)
                            }
                        }
                    }
                } header: {
                    Text("Ses autres livres")
                } footer: {
                    if !loading, !others.isEmpty {
                        Text("Touchez + pour ajouter un livre à votre PAL, ou touchez le livre pour voir sa fiche.")
                    }
                }
            }
            .navigationTitle(author)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func quickAdd(_ result: BookResult) -> some View {
        let isAdding = adding.contains(result.id)
        return Button {
            Task { await add(result) }
        } label: {
            if isAdding {
                ProgressView()
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.borderless)
        .disabled(isAdding)
        .accessibilityLabel("Ajouter « \(result.title) » à ma PAL")
    }

    private func load() async {
        let found = await BookSearchService.search(author)
        // Seulement les livres de cet auteur, une seule édition par titre (celle qui a le plus d'avis).
        var byTitle: [String: BookResult] = [:]
        var order: [String] = []
        for result in found where result.authors.contains(where: { BookSearchService.normalize($0) == authorKey }) {
            let key = BookSearchService.normalize(result.title)
            guard !key.isEmpty else { continue }
            if let existing = byTitle[key] {
                let better = (result.ratingsCount ?? 0) > (existing.ratingsCount ?? 0)
                    || (existing.coverURL == nil && result.coverURL != nil)
                if better { byTitle[key] = result }
            } else {
                byTitle[key] = result
                order.append(key)
            }
        }
        let list = order.compactMap { byTitle[$0] }
            .sorted { ($0.ratingsCount ?? 0) > ($1.ratingsCount ?? 0) }
        withAnimation {
            results = list
            loading = false
        }
    }

    private func add(_ result: BookResult) async {
        adding.insert(result.id)
        let full = await BookSearchService.enrich(result)
        let book = Book(result: full, status: .toRead)
        if let best = await BookSearchService.bestCover(BookSearchService.coverCandidates(for: full)) {
            book.coverData = best.data
            book.coverURLString = best.url.absoluteString
        }
        book.lastCheckedAt = .now
        withAnimation { context.insert(book) }
        try? context.save()
        adding.remove(result.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Nom(s) d'auteur cliquable(s) : ouvre la liste de ses livres.
struct AuthorLinks: View {
    let authors: [String]
    let fallback: String
    @State private var selected: AuthorRef?

    var body: some View {
        Group {
            if authors.isEmpty {
                Text(fallback)
            } else if authors.count == 1, let name = authors.first {
                Button {
                    selected = AuthorRef(name: name)
                } label: {
                    label(name)
                }
            } else {
                Menu {
                    ForEach(authors, id: \.self) { name in
                        Button(name, systemImage: "person") { selected = AuthorRef(name: name) }
                    }
                } label: {
                    label(authors.joined(separator: ", "))
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $selected) { ref in
            AuthorBooksView(author: ref.name)
        }
    }

    private func label(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.accentColor)
    }
}
