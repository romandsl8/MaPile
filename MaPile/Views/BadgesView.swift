import SwiftUI
import SwiftData

/// Carte « Défis et badges » de l'onglet Statistiques.
struct BadgesCard: View {
    @Query private var books: [Book]
    @Query private var sessions: [ReadingSession]
    @Query private var quotes: [Quote]
    @AppStorage("yearlyGoal") private var goal = 20
    @AppStorage("unlockedBadges") private var unlockedRaw = ""
    @AppStorage("badgesInitialized") private var badgesInitialized = false
    @State private var newlyUnlocked: [Badge] = []
    @State private var selected: Badge?

    private var badges: [Badge] {
        BadgeCatalog.badges(books: books, sessions: sessions, quotes: quotes.count, yearlyGoal: goal)
    }

    var body: some View {
        let list = badges
        let unlockedCount = list.filter(\.unlocked).count
        SectionCard(title: "Défis et badges · \(unlockedCount)/\(list.count)", systemImage: "medal") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 12)], spacing: 14) {
                ForEach(list) { badge in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(badge.unlocked ? Color.accentColor.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                            Circle()
                                .trim(from: 0, to: badge.fraction)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(badge.emoji)
                                .font(.system(size: 28))
                                .grayscale(badge.unlocked ? 0 : 1)
                                .opacity(badge.unlocked ? 1 : 0.45)
                        }
                        .frame(width: 58, height: 58)
                        Text(badge.title)
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .onTapGesture { selected = badge }
                }
            }
        }
        .task(id: unlockedCount) { checkNewBadges(list) }
        .alert(selected?.title ?? "", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let badge = selected {
                Text(badge.unlocked
                     ? "\(badge.detail) : débloqué ✅"
                     : "\(badge.detail).\nProgression : \(min(badge.progress, badge.goal)) / \(badge.goal)")
            }
        }
        .alert("Nouveau badge ! 🎉", isPresented: Binding(get: { !newlyUnlocked.isEmpty }, set: { if !$0 { newlyUnlocked = [] } })) {
            Button("Super !", role: .cancel) {}
        } message: {
            Text(newlyUnlocked.map { "\($0.emoji) \($0.title)" }.joined(separator: "\n"))
        }
    }

    /// Fête les badges débloqués depuis la dernière visite.
    private func checkNewBadges(_ list: [Badge]) {
        let known = Set(unlockedRaw.split(separator: ",").map(String.init))
        let unlocked = list.filter(\.unlocked)
        let fresh = unlocked.filter { !known.contains($0.id) }
        unlockedRaw = unlocked.map(\.id).joined(separator: ",")
        // Première visite : on enregistre sans fêter les badges déjà acquis.
        guard badgesInitialized else {
            badgesInitialized = true
            return
        }
        guard !fresh.isEmpty else { return }
        newlyUnlocked = fresh
        NotificationCenter.default.post(name: .bookFinished, object: nil)
    }
}
