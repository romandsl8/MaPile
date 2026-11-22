import Foundation

/// Résumé de la bibliothèque partagé entre l'app et ses widgets (groupe d'apps).
/// L'app l'écrit, les widgets le lisent : les widgets n'ouvrent jamais la base de données.
struct WidgetSnapshot: Codable {
    struct ReadingBook: Codable, Hashable {
        var title: String
        var author: String
        var page: Int
        var pageCount: Int
        var cover: Data?

        var progress: Double? {
            guard pageCount > 0 else { return nil }
            return min(max(Double(page) / Double(pageCount), 0), 1)
        }
    }

    var reading: [ReadingBook] = []
    var streak: Int = 0
    var yearCount: Int = 0
    var goal: Int = 20
    var pileCount: Int = 0
    var updatedAt: Date = .now

    static let groupID = "group.com.romandsl8.mapile"
    private static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: groupID),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snapshot
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.groupID),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static let example = WidgetSnapshot(
        reading: [ReadingBook(title: "Les Jardins de Sel", author: "Claire Vasseur", page: 142, pageCount: 342, cover: nil)],
        streak: 6, yearCount: 14, goal: 20, pileCount: 23)
}
