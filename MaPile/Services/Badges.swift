import Foundation

/// Défis et badges, calculés à partir de la bibliothèque (rien n'est envoyé en ligne).
struct Badge: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
    let detail: String
    let progress: Int
    let goal: Int

    var unlocked: Bool { progress >= goal }
    var fraction: Double { goal > 0 ? min(Double(progress) / Double(goal), 1) : 0 }
}

enum BadgeCatalog {
    static func badges(books: [Book], sessions: [ReadingSession], quotes: Int, yearlyGoal: Int) -> [Badge] {
        let calendar = Calendar.current
        let read = books.filter { $0.status == .read }
        let year = calendar.component(.year, from: .now)
        let readThisYear = read.filter { calendar.component(.year, from: $0.finishedOn) == year }
        let days = ReadingStreak.readingDays(sessions: sessions, finished: read)
        let bestStreak = ReadingStreak.best(days: days)
        let genresThisYear = Set(readThisYear.compactMap { $0.genreList.first.map(BookSearchService.normalize) }).count
        var authorCounts: [String: Int] = [:]
        for book in read { for author in book.authorList { authorCounts[author, default: 0] += 1 } }
        let favoriteAuthorCount = authorCounts.values.max() ?? 0
        let longest = read.map(\.pageCount).max() ?? 0
        let reviews = read.filter { !$0.myReview.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let nightOwl = sessions.contains { !$0.isManual && ( calendar.component(.hour, from: $0.start) >= 23 || calendar.component(.hour, from: $0.start) < 4) }
        let earlyBird = sessions.contains { !$0.isManual &&  (5..<8).contains(calendar.component(.hour, from: $0.start)) }
        let totalHours = Int(sessions.reduce(0.0) { $0 + $1.duration } / 3600)
        let pagesTotal = read.reduce(0) { $0 + $1.pageCount }
        let seriesDone = Set(read.filter { !$0.seriesName.isEmpty }.map { BookSearchService.normalize($0.seriesName) })
        var maxSeries = 0
        for series in seriesDone {
            maxSeries = max(maxSeries, read.filter { BookSearchService.normalize($0.seriesName) == series }.count)
        }

        return [
            Badge(id: "first", emoji: "📖", title: "Premier chapitre", detail: "Terminer un premier livre", progress: read.count, goal: 1),
            Badge(id: "ten", emoji: "📚", title: "Belle pile", detail: "Lire 10 livres", progress: read.count, goal: 10),
            Badge(id: "fifty", emoji: "🏛️", title: "Bibliothèque vivante", detail: "Lire 50 livres", progress: read.count, goal: 50),
            Badge(id: "hundred", emoji: "👑", title: "Centenaire", detail: "Lire 100 livres", progress: read.count, goal: 100),
            Badge(id: "goal", emoji: "🎯", title: "Objectif \(year)", detail: "Atteindre votre objectif annuel", progress: readThisYear.count, goal: max(yearlyGoal, 1)),
            Badge(id: "genres", emoji: "🧭", title: "Explorateur", detail: "5 genres différents cette année", progress: genresThisYear, goal: 5),
            Badge(id: "brick", emoji: "🧱", title: "Pavé", detail: "Finir un livre de 700 pages ou plus", progress: longest >= 700 ? 1 : 0, goal: 1),
            Badge(id: "pages", emoji: "📄", title: "10 000 pages", detail: "Cumuler 10 000 pages lues", progress: pagesTotal, goal: 10_000),
            Badge(id: "streak7", emoji: "🔥", title: "Une semaine", detail: "7 jours de lecture d'affilée", progress: bestStreak, goal: 7),
            Badge(id: "streak30", emoji: "🌋", title: "Un mois", detail: "30 jours de lecture d'affilée", progress: bestStreak, goal: 30),
            Badge(id: "hours", emoji: "⏳", title: "Lecteur assidu", detail: "10 heures chronométrées", progress: totalHours, goal: 10),
            Badge(id: "fan", emoji: "💛", title: "Fan inconditionnel", detail: "3 livres du même auteur", progress: favoriteAuthorCount, goal: 3),
            Badge(id: "series", emoji: "🧩", title: "Saga", detail: "Lire 3 tomes d'une même série", progress: maxSeries, goal: 3),
            Badge(id: "critic", emoji: "✍️", title: "Critique", detail: "Écrire 10 avis", progress: reviews, goal: 10),
            Badge(id: "quotes", emoji: "❝", title: "Collectionneur de mots", detail: "Garder 5 citations", progress: quotes, goal: 5),
            Badge(id: "night", emoji: "🌙", title: "Oiseau de nuit", detail: "Lire après 23 h", progress: nightOwl ? 1 : 0, goal: 1),
            Badge(id: "early", emoji: "🌅", title: "Lève-tôt", detail: "Lire avant 8 h du matin", progress: earlyBird ? 1 : 0, goal: 1),
        ]
    }
}
