import Foundation
import SwiftData

/// Une séance de lecture chronométrée (bouton « Je lis » de l'onglet En cours).
@Model
final class ReadingSession {
    var uuid: UUID = UUID()
    var bookID: String = ""
    var bookTitle: String = ""
    var start: Date = Date()
    var end: Date = Date()
    var startPage: Int = 0
    var endPage: Int = 0

    init(book: Book, start: Date, end: Date, startPage: Int, endPage: Int) {
        self.bookID = book.uuid.uuidString
        self.bookTitle = book.title
        self.start = start
        self.end = end
        self.startPage = startPage
        self.endPage = endPage
    }

    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
    var pagesRead: Int { max(endPage - startPage, 0) }
}

/// Séance en cours (une seule à la fois), gardée dans les préférences pour survivre à la fermeture de l'app.
enum ActiveSession {
    static let bookKey = "activeSessionBook"
    static let startKey = "activeSessionStart"
    static let pageKey = "activeSessionStartPage"
    private static var defaults: UserDefaults { .standard }

    static var bookID: String? { defaults.string(forKey: bookKey) }

    static var start: Date? {
        let value = defaults.double(forKey: startKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    static var startPage: Int { defaults.integer(forKey: pageKey) }

    static func begin(for book: Book) {
        defaults.set(book.uuid.uuidString, forKey: bookKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: startKey)
        defaults.set(book.currentPage, forKey: pageKey)
    }

    static func clear() {
        defaults.removeObject(forKey: bookKey)
        defaults.set(0.0, forKey: startKey)
        defaults.set(0, forKey: pageKey)
    }
}

/// Calculs sur les jours de lecture : série en cours et record.
enum ReadingStreak {
    /// Jours où l'utilisateur a lu (séance chronométrée ou livre terminé).
    static func readingDays(sessions: [ReadingSession], finished: [Book]) -> Set<Date> {
        let calendar = Calendar.current
        var days = Set<Date>()
        for session in sessions { days.insert(calendar.startOfDay(for: session.end)) }
        for book in finished { days.insert(calendar.startOfDay(for: book.finishedOn)) }
        return days
    }

    /// Nombre de jours consécutifs jusqu'à aujourd'hui (ou hier, si on n'a pas encore lu aujourd'hui).
    static func current(days: Set<Date>) -> Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Plus longue série de jours consécutifs.
    static func best(days: Set<Date>) -> Int {
        let calendar = Calendar.current
        var best = 0
        for day in days {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day), !days.contains(previous) else { continue }
            var length = 1
            var next = calendar.date(byAdding: .day, value: 1, to: day)
            while let n = next, days.contains(n) {
                length += 1
                next = calendar.date(byAdding: .day, value: 1, to: n)
            }
            best = max(best, length)
        }
        return best
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest)"
    }
}
