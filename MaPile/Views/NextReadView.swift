import SwiftUI
import SwiftData

/// « Que lire ensuite ? » : une suggestion tirée de la PAL selon l'humeur et le temps disponible.
struct NextReadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Book> { $0.statusRaw == "toRead" }) private var pile: [Book]
    @State private var mood: ReadingMood = .escape
    @State private var length: ReadingLength = .any
    @State private var suggestion: NextReadAdvisor.Suggestion?
    @State private var thinking = false
    @State private var excluded: Set<UUID> = []
    @State private var noMore = false
    @Query(filter: #Predicate<Book> { $0.statusRaw == "read" }) private var read: [Book]
    @Environment(\.modelContext) private var context
    @State private var discoverMode = false
    @State private var queue: [NextReadAdvisor.Discovery] = []
    @State private var discovery: NextReadAdvisor.Discovery?
    @State private var shown: Set<String> = []
    @State private var added: Set<String> = []
    @State private var adding = false

    private var canSearch: Bool { discoverMode ? !(read.isEmpty && pile.isEmpty) : !pile.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Chercher", selection: $discoverMode) {
                        Text("Dans ma PAL").tag(false)
                        Text("Nouveaux livres").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: discoverMode) { _, _ in
                        suggestion = nil
                        discovery = nil
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
                        if discoverMode {
                            queue = []
                            Task { await nextDiscovery() }
                        } else {
                            excluded = []
                            Task { await findSuggestion() }
                        }
                    } label: {
                        Label(discoverMode ? "Trouver de nouveaux livres" : "Trouver mon prochain livre", systemImage: "sparkles")
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
                    } else if discoverMode, let discovery {
                        discoveryCard(discovery)
                    } else if !discoverMode, let suggestion {
                        result(suggestion)
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
            .navigationTitle("Que lire ensuite ?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func result(_ suggestion: NextReadAdvisor.Suggestion) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CoverView(book: suggestion.book, cornerRadius: 8)
                    .frame(width: 110)
                    .shadow(radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(suggestion.book.title)
                        .font(.system(.title3, design: .serif).weight(.bold))
                    Text(suggestion.book.displayAuthors)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(suggestion.reason)
                        .font(.subheadline)
                        .padding(.top, 4)
                    Label(suggestion.byAI ? "Suggestion de l'IA d'Apple, sur votre iPhone" : "Suggestion MaPile",
                          systemImage: suggestion.byAI ? "apple.intelligence" : "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation { suggestion.book.startReading() }
                        dismiss()
                    } label: {
                        Label("Commencer", systemImage: "book.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        excluded.insert(suggestion.book.uuid)
                        Task { await findSuggestion() }
                    } label: {
                        Label("Autre idée", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .transition(.scale.combined(with: .opacity))
    }

    private var thinkingText: String {
        if discoverMode {
            return NextReadAdvisor.aiAvailable ? "L'IA d'Apple cherche des livres pour vous…" : "Je cherche des livres pour vous…"
        }
        return NextReadAdvisor.aiAvailable ? "L'IA d'Apple parcourt votre PAL…" : "Je regarde votre PAL…"
    }

    private func discoveryCard(_ item: NextReadAdvisor.Discovery) -> some View {
        let book = item.result
        let isAdded = added.contains(NextReadAdvisor.key(title: book.title))
        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CoverView(data: nil, url: book.coverURL, title: book.title, cornerRadius: 8)
                    .frame(width: 110)
                    .shadow(radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.system(.title3, design: .serif).weight(.bold))
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
                        .padding(.top, 4)
                    if !book.summary.isEmpty {
                        Text(BookSearchService.cleanDescription(book.summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }
                    Label(item.byAI ? "Idée de l'IA d'Apple, sur votre iPhone" : "Suggestion MaPile",
                          systemImage: item.byAI ? "apple.intelligence" : "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await add(book) }
                    } label: {
                        Label(isAdded ? "Dans ma PAL" : "Ajouter à ma PAL",
                              systemImage: isAdded ? "checkmark" : "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isAdded || adding)
                    Button {
                        Task { await nextDiscovery() }
                    } label: {
                        Label("Autre idée", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .transition(.scale.combined(with: .opacity))
    }

    /// Affiche l'idée suivante ; quand la liste est vide, en cherche de nouvelles.
    private func nextDiscovery() async {
        noMore = false
        if queue.isEmpty {
            thinking = true
            queue = await NextReadAdvisor.discover(read: read, pile: pile, mood: mood, length: length, excluding: shown)
        }
        let next = queue.isEmpty ? nil : queue.removeFirst()
        if let next { shown.insert(NextReadAdvisor.key(title: next.result.title)) }
        withAnimation(.spring) {
            discovery = next
            noMore = next == nil
            thinking = false
        }
    }

    private func add(_ result: BookResult) async {
        adding = true
        let full = await BookSearchService.enrich(result)
        let book = Book(result: full, status: .toRead)
        if let best = await BookSearchService.bestCover(BookSearchService.coverCandidates(for: full)) {
            book.coverData = best.data
            book.coverURLString = best.url.absoluteString
        }
        book.lastCheckedAt = .now
        context.insert(book)
        try? context.save()
        added.insert(NextReadAdvisor.key(title: result.title))
        adding = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func findSuggestion() async {
        thinking = true
        noMore = false
        let found = await NextReadAdvisor.suggest(from: pile, mood: mood, length: length, excluding: excluded)
        withAnimation(.spring) {
            suggestion = found
            noMore = found == nil
            thinking = false
        }
    }
}
