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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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
                        excluded = []
                        Task { await findSuggestion() }
                    } label: {
                        Label("Trouver mon prochain livre", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(thinking || pile.isEmpty)

                    if pile.isEmpty {
                        Text("Votre PAL est vide : ajoutez d'abord des livres à lire.")
                            .foregroundStyle(.secondary)
                    }
                    if thinking {
                        HStack {
                            ProgressView()
                            Text(NextReadAdvisor.aiAvailable ? "L'IA d'Apple parcourt votre PAL…" : "Je regarde votre PAL…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else if let suggestion {
                        result(suggestion)
                    } else if noMore {
                        Text("Plus d'autre idée dans votre PAL pour ces critères.")
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
