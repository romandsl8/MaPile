import Foundation
import SwiftData
import SwiftUI

/// Bibliothèque d'exemple, chargée uniquement avec l'argument de lancement « -demoData »
/// (captures d'écran automatiques). Jamais utilisée dans l'app normale.
enum DemoData {
    private enum Place { case read(monthsAgo: Int), pile, reading(page: Int) }

    private struct Sample {
        let title: String
        let author: String
        let pages: Int
        let genre: String
        let community: Double
        let votes: Int
        let myRating: Int
        let place: Place
        let style: DemoCoverStyle
        var series: (String, Int)? = nil
    }

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    // Titres et auteurs fictifs, couvertures dessinées par l'app : aucun contenu protégé.
    private static let samples: [Sample] = [
        Sample(title: "Le Silence des glaciers", author: "Inès Moreau", pages: 380, genre: "Aventure", community: 4.4, votes: 2140, myRating: 0,
               place: .reading(page: 214),
               style: .init(symbol: "snowflake", colors: [c(64, 120, 170), c(18, 40, 78)], accent: c(220, 238, 255), layout: .sky)),
        Sample(title: "Les Jardins de Sel", author: "Claire Vasseur", pages: 342, genre: "Roman", community: 4.3, votes: 1520, myRating: 5,
               place: .read(monthsAgo: 0),
               style: .init(symbol: "leaf.fill", colors: [c(233, 214, 178), c(196, 160, 112)], accent: c(42, 110, 96), layout: .band)),
        Sample(title: "Nuit sur Orbe", author: "Malik Renaud", pages: 512, genre: "Science-fiction", community: 4.5, votes: 3210, myRating: 5,
               place: .read(monthsAgo: 1),
               style: .init(symbol: "moon.stars.fill", colors: [c(44, 30, 92), c(12, 8, 34)], accent: c(255, 196, 92), layout: .sun)),
        Sample(title: "Le Cartographe d'hiver", author: "Inès Moreau", pages: 288, genre: "Aventure", community: 4.1, votes: 870, myRating: 4,
               place: .read(monthsAgo: 1),
               style: .init(symbol: "map.fill", colors: [c(26, 52, 64), c(10, 24, 32)], accent: c(214, 182, 112), layout: .frame)),
        Sample(title: "Ce que la mer garde", author: "Claire Vasseur", pages: 264, genre: "Roman", community: 4.0, votes: 990, myRating: 4,
               place: .read(monthsAgo: 2),
               style: .init(symbol: "water.waves", colors: [c(120, 190, 210), c(30, 86, 128)], accent: c(14, 52, 92), layout: .band)),
        Sample(title: "L'Affaire du quai Lune", author: "Paul Ardent", pages: 416, genre: "Policier", community: 4.2, votes: 1650, myRating: 4,
               place: .read(monthsAgo: 3),
               style: .init(symbol: "magnifyingglass", colors: [c(30, 30, 34), c(8, 8, 10)], accent: c(246, 200, 62), layout: .frame)),
        Sample(title: "Petite histoire du temps lent", author: "Jeanne Albrecht", pages: 224, genre: "Essai", community: 4.4, votes: 4100, myRating: 5,
               place: .read(monthsAgo: 4),
               style: .init(symbol: "hourglass", colors: [c(246, 228, 200), c(240, 170, 110)], accent: c(176, 74, 40), layout: .split)),
        Sample(title: "La Forêt des neuf portes", author: "Hugo Larcher", pages: 736, genre: "Fantasy", community: 4.6, votes: 5230, myRating: 5,
               place: .read(monthsAgo: 5),
               style: .init(symbol: "tree.fill", colors: [c(24, 70, 48), c(6, 26, 18)], accent: c(226, 190, 104), layout: .frame),
               series: ("Les Neuf Portes", 1)),
        Sample(title: "Les Heures pâles", author: "Inès Moreau", pages: 198, genre: "Roman", community: 3.8, votes: 760, myRating: 3,
               place: .read(monthsAgo: 6),
               style: .init(symbol: "clock.fill", colors: [c(190, 172, 222), c(98, 80, 150)], accent: c(255, 255, 255), layout: .sky)),
        Sample(title: "Signal faible", author: "Malik Renaud", pages: 448, genre: "Science-fiction", community: 4.2, votes: 2870, myRating: 4,
               place: .read(monthsAgo: 8),
               style: .init(symbol: "antenna.radiowaves.left.and.right", colors: [c(16, 84, 92), c(4, 30, 36)], accent: c(96, 236, 208), layout: .sun)),
        Sample(title: "Le Dernier Été à Valmont", author: "Sophie Garnier", pages: 312, genre: "Roman", community: 4.0, votes: 980, myRating: 3,
               place: .read(monthsAgo: 13),
               style: .init(symbol: "sun.max.fill", colors: [c(255, 160, 110), c(214, 78, 110)], accent: c(255, 236, 160), layout: .sun)),
        Sample(title: "L'Archipel suspendu", author: "Hugo Larcher", pages: 640, genre: "Fantasy", community: 4.7, votes: 2410, myRating: 0,
               place: .pile,
               style: .init(symbol: "mountain.2.fill", colors: [c(170, 120, 200), c(64, 36, 110)], accent: c(255, 214, 240), layout: .sky),
               series: ("Les Neuf Portes", 2)),
        Sample(title: "Mémoires d'un phare", author: "Sophie Garnier", pages: 256, genre: "Roman", community: 4.3, votes: 1340, myRating: 0,
               place: .pile,
               style: .init(symbol: "sailboat.fill", colors: [c(250, 240, 222), c(242, 214, 170)], accent: c(198, 58, 52), layout: .band)),
        Sample(title: "Le Code des abeilles", author: "Paul Ardent", pages: 384, genre: "Policier", community: 4.1, votes: 1120, myRating: 0,
               place: .pile,
               style: .init(symbol: "hexagon.fill", colors: [c(36, 30, 20), c(14, 10, 6)], accent: c(250, 186, 40), layout: .frame)),
        Sample(title: "Vers les étoiles froides", author: "Malik Renaud", pages: 528, genre: "Science-fiction", community: 4.4, votes: 900, myRating: 0,
               place: .pile,
               style: .init(symbol: "sparkles", colors: [c(20, 40, 90), c(4, 6, 24)], accent: c(150, 200, 255), layout: .sky)),
        Sample(title: "Le Goût des oranges amères", author: "Jeanne Albrecht", pages: 296, genre: "Roman", community: 3.9, votes: 650, myRating: 0,
               place: .pile,
               style: .init(symbol: "sun.haze.fill", colors: [c(255, 190, 120), c(232, 110, 60)], accent: c(120, 40, 20), layout: .split)),
        Sample(title: "La Reine des brumes", author: "Hugo Larcher", pages: 690, genre: "Fantasy", community: 4.5, votes: 1880, myRating: 0,
               place: .pile,
               style: .init(symbol: "crown.fill", colors: [c(120, 130, 150), c(40, 44, 60)], accent: c(232, 214, 160), layout: .frame),
               series: ("Les Neuf Portes", 3)),
    ]

    @MainActor
    static func insert(into context: ModelContext) {
        let calendar = Calendar.current
        var readingBook: Book?
        for (index, s) in samples.enumerated() {
            let status: ReadingStatus
            switch s.place {
            case .read: status = .read
            case .pile: status = .toRead
            case .reading: status = .reading
            }
            let book = Book(title: s.title, authors: s.author, status: status)
            book.pageCount = s.pages
            book.categories = s.genre
            book.communityRating = s.community
            book.communityRatingsCount = s.votes
            book.myRating = s.myRating
            book.coverData = DemoCovers.render(title: s.title, author: s.author, style: s.style)
            book.summary = "Une histoire lumineuse et pleine de suspense, portée par des personnages attachants. Un roman qu'on referme à regret."
            book.dateAdded = calendar.date(byAdding: .day, value: -index * 9, to: .now) ?? .now
            if let series = s.series {
                book.seriesName = series.0
                book.seriesIndex = series.1
            }
            switch s.place {
            case .read(let months):
                book.dateFinished = calendar.date(byAdding: .month, value: -months, to: .now)
                book.currentPage = s.pages
                if s.myRating >= 4 { book.myReview = "Coup de cœur ! Je le recommande sans hésiter." }
            case .reading(let page):
                book.currentPage = page
                book.dateStarted = calendar.date(byAdding: .day, value: -9, to: .now)
                readingBook = book
            case .pile:
                break
            }
            context.insert(book)
        }

        // Séances de lecture des 12 derniers jours (série, temps de lecture, historique).
        if let book = readingBook {
            let durations = [24, 38, 31, 45, 27, 52, 33, 40, 29, 36, 44]
            var page = book.currentPage - durations.reduce(0) { $0 + $1 / 2 + 4 }
            for day in stride(from: 11, through: 1, by: -1) {
                guard let date = calendar.date(byAdding: .day, value: -day, to: .now),
                      let start = calendar.date(bySettingHour: 21, minute: 10, second: 0, of: date) else { continue }
                let minutes = durations[day % 11]
                let pages = minutes / 2 + 4
                let session = ReadingSession(book: book, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                                             startPage: page, endPage: page + pages)
                context.insert(session)
                page += pages
            }
            // Chrono en cours, lancé il y a 23 minutes.
            UserDefaults.standard.set(book.uuid.uuidString, forKey: ActiveSession.bookKey)
            UserDefaults.standard.set(Date.now.addingTimeInterval(-23 * 60).timeIntervalSince1970, forKey: ActiveSession.startKey)
            UserDefaults.standard.set(book.currentPage, forKey: ActiveSession.pageKey)
        }
        try? context.save()
    }
}
