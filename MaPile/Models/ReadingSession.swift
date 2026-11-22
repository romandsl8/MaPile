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
    /// Progression saisie à la main, sans chrono (une entrée par livre et par jour).
    var isManual: Bool { end == start }
}

/// Journal des pages lues sans chrono : pour que les statistiques et l'historique en tiennent compte.
@MainActor
enum ReadingLog {
    /// Enregistre le passage de la page `from` à la page `to`, en regroupant les saisies d'un même jour.
    static func recordManualProgress(book: Book, from: Int, to: Int, context: ModelContext) {
        guard from != to else { return }
        // Pendant une séance chronométrée, c'est la fin de séance qui comptera ces pages.
        if ActiveSession.bookID == book.uuid.uuidString, ActiveSession.start != nil { return }
        let id = book.uuid.uuidString
        let today = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.bookID == id && $0.end >= today })
        let existing = ((try? context.fetch(descriptor)) ?? []).first { $0.isManual }
        let now = Date.now
        if let entry = existing {
            entry.endPage = to
            entry.start = now
            entry.end = now
            if entry.endPage <= entry.startPage { context.delete(entry) }
        } else if to > from {
            let entry = ReadingSession(book: book, start: now, end: now, startPage: from, endPage: to)
            context.insert(entry)
        }
        try? context.save()
    }

    /// Le nombre total de pages a changé (taille du texte, orientation…) : on convertit les pages de départ.
    static func rescale(book: Book, from oldTotal: Int, to newTotal: Int, context: ModelContext) {
        guard oldTotal > 0, newTotal > 0, oldTotal != newTotal else { return }
        let ratio = Double(newTotal) / Double(oldTotal)
        let id = book.uuid.uuidString
        let today = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.bookID == id && $0.end >= today })
        for entry in (try? context.fetch(descriptor)) ?? [] where entry.isManual {
            entry.startPage = Int((Double(entry.startPage) * ratio).rounded())
        }
        if ActiveSession.bookID == id, ActiveSession.start != nil {
            UserDefaults.standard.set(Int((Double(ActiveSession.startPage) * ratio).rounded()), forKey: ActiveSession.pageKey)
        }
    }
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
