import SwiftUI
import SwiftData

/// « Que lire ensuite ? » : trois suggestions, dans la PAL ou parmi de nouveaux livres,
/// selon l'humeur et le temps disponible.
struct NextReadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Book> { $0.statusRaw == "toRead" }) private var pile: [Book]
    @Query(filter: #Predicate<Book> { $0.statusRaw == "read" }) private var read: [Book]
    @State private var mood: ReadingMood = .escape
    @State private var length: ReadingLength = .any
    @State private var thinking = false
    @State private var noMore = false
    @State private var discoverMode = false
    // Mode « Dans ma PAL »
    @State private var suggestions: [NextReadAdvisor.Suggestion] = []
    @State private var excluded: Set<UUID> = []
    // Mode « Nouveaux livres »
    @State private var queue: [NextReadAdvisor.Discovery] = []
    @State private var discoveries: [NextReadAdvisor.Discovery] = []
    @State private var shown: Set<String> = []
    @State private var added: Set<String> = []
    @State private var adding: Set<String> = []

    private static let count = 3

    private var canSearch: Bool { discoverMode ? !(read.isEmpty && pile.isEmpty) : !pile.isEmpty }
    private var hasResults: Bool { discoverMode ? !discoveries.isEmpty : !suggestions.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Chercher", selection: $discoverMode) {
                        Text("Dans ma PAL").tag(false)
                        Text("Nouveaux livres").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: discoverMode) { _, _ in
                        suggestions = []
                        discoveries = []
                        noMore = false
                    }
                    if discoverMode {
                        Text("Des livres que vous n'avez pas encore, choisis d'après vos lectures et votre PAL.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("Quelle est votre envie ?")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(ReadingMood.allCases) { item in
                            Button {
                                mood = item
                            } label: {
                                Text(item.label)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(mood == item ? .regular.tint(Color.accentColor.opacity(0.35)) : .regular,
                                         in: .capsule)
                        }
                    }

                    Text("Combien de temps devant vous ?")
                        .font(.headline)
                    Picker("Longueur", selection: $length) {
                        ForEach(ReadingLength.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        Task { await search(fresh: true) }
                    } label: {
                        Label(discoverMode ? "Trouver de nouveaux livres" : "Trouver mes prochains livres", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(thinking || !canSearch)

                    if !canSearch {
                        Text(discoverMode
                             ? "Ajoutez d'abord quelques livres lus ou à lire : les idées partent de vos goûts."
                             : "Votre PAL est vide : ajoutez d'abord des livres à lire.")
                            .foregroundStyle(.secondary)
                    }

                    if thinking {
                        HStack {
                            ProgressView()
                            Text(thinkingText)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else if hasResults {
                        VStack(spacing: 14) {
                            Color.clear.frame(height: 0).id("results")
                            if discoverMode {
                                ForEach(discoveries) { discoveryCard($0) }
                            } else {
                                ForEach(suggestions, id: \.book.uuid) { suggestionCard($0) }
                            }
                            Button {
                                Task { await search(fresh: false) }
                            } label: {
                                Label("3 autres idées", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                        }
                    } else if noMore {
                        Text(discoverMode
                             ? "Pas d'autre idée pour ces critères. Essayez une autre envie !"
                             : "Plus d'autre idée dans votre PAL pour ces critères.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            // Les idées apparaissent sous les envies : on y descend automatiquement.
            .onChange(of: hasResults) { _, found in
                guard found else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation { proxy.scrollTo("results", anchor: .top) }
                }
            }
            .task {
                // Captures d'écran : recherche lancée toute seule (une fois la PAL chargée).
                guard UserDefaults.standard.bool(forKey: "openNextRead"), !hasResults else { return }
                mood = .fantasy
                for _ in 0..<20 where pile.isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                await search(fresh: true)
            }
            }
            .navigationTitle("Que lire ensuite ?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var thinkingText: String {
        if discoverMode {
            return NextReadAdvisor.aiAvailable ? "L'IA d'Apple cherche des livres pour vous…" : "Je cherche des livres pour vous…"
        }
        return NextReadAdvisor.aiAvailable ? "L'IA d'Apple parcourt votre PAL…" : "Je regarde votre PAL…"
    }

    private func sourceLabel(byAI: Bool) -> some View {
        Label(byAI ? "Idée de l'IA d'Apple, sur votre iPhone" : "Suggestion MaPile",
              systemImage: byAI ? "apple.intelligence" : "sparkles")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Cartes

    private func suggestionCard(_ suggestion: NextReadAdvisor.Suggestion) -> some View {
        let book = suggestion.book
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CoverView(book: book, cornerRadius: 7)
                    .frame(width: 84)
                    .shadow(radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.system(.headline, design: .serif).weight(.bold))
                    Text(book.displayAuthors)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if book.pageCount > 0 {
                        Text("\(book.pageCount) p.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(suggestion.reason)
                        .font(.subheadline)
                        .padding(.top, 2)
                    sourceLabel(byAI: suggestion.byAI)
                }
                Spacer(minLength: 0)
            }
            Button {
                withAnimation { book.startReading() }
                dismiss()
            } label: {
                Label("Commencer", systemImage: "book.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .transition(.scale.combined(with: .opacity))
    }

    private func discoveryCard(_ item: NextReadAdvisor.Discovery) -> some View {
        let book = item.result
        let key = NextReadAdvisor.key(title: book.title)
        let isAdded = added.contains(key)
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CoverView(data: nil, url: book.coverURL, title: book.title, cornerRadius: 7)
                    .frame(width: 84)
                    .shadow(radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.system(.headline, design: .serif).weight(.bold))
                    Text(book.authors.isEmpty ? "Auteur inconnu" : book.authors.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if let rating = book.averageRating {
                            Label(rating.frenchDecimal, systemImage: "star.fill")
                        }
                        if let pages = book.pageCount, pages > 0 {
                            Text("\(pages) p.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(item.reason)
                        .font(.subheadline)
                        .padding(.top, 2)
                    if !book.summary.isEmpty {
                        Text(BookSearchService.cleanDescription(book.summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    sourceLabel(byAI: item.byAI)
                }
                Spacer(minLength: 0)
            }
            Button {
                Task { await add(book) }
            } label: {
                if adding.contains(key) {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label(isAdded ? "Dans ma PAL" : "Ajouter à ma PAL",
                          systemImage: isAdded ? "checkmark" : "plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isAdded || adding.contains(key))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Recherche

    /// `fresh` : nouvelle recherche ; sinon, les trois idées suivantes.
    private func search(fresh: Bool) async {
        noMore = false
        thinking = true
        if discoverMode {
            if fresh { queue = [] }
            if queue.count < Self.count {
                let more = await NextReadAdvisor.discover(read: read, pile: pile, mood: mood, length: length,
                                                          excluding: shown.union(queue.map { NextReadAdvisor.key(title: $0.result.title) }))
                queue.append(contentsOf: more)
            }
            let next = Array(queue.prefix(Self.count))
            queue.removeFirst(next.count)
            for item in next { shown.insert(NextReadAdvisor.key(title: item.result.title)) }
            withAnimation(.spring) {
                discoveries = next
                noMore = next.isEmpty
                thinking = false
            }
        } else {
            if fresh {
                excluded = []
            } else {
                for item in suggestions { excluded.insert(item.book.uuid) }
            }
            let found = await NextReadAdvisor.suggest(from: pile, mood: mood, length: length, excluding: excluded, count: Self.count)
            withAnimation(.spring) {
                suggestions = found
                noMore = found.isEmpty
                thinking = false
            }
        }
    }

    private func add(_ result: BookResult) async {
        let key = NextReadAdvisor.key(title: result.title)
        adding.insert(key)
        let full = await BookSearchService.enrich(result)
        let book = Book(result: full, status: .toRead)
        if let best = await BookSearchService.bestCover(BookSearchService.coverCandidates(for: full)) {
            book.coverData = best.data
            book.coverURLString = best.url.absoluteString
        }
        book.lastCheckedAt = .now
        context.insert(book)
        try? context.save()
        added.insert(key)
        adding.remove(key)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
