import Foundation
import SwiftData

/// Bibliothèque d'exemple, chargée uniquement avec l'argument de lancement « -demoData »
/// (captures d'écran automatiques). Jamais utilisée dans l'app normale.
enum DemoData {
    private struct Sample {
        let title: String
        let author: String
        let isbn: String
        let pages: Int
        let genre: String
        let community: Double
        let votes: Int
        let myRating: Int
        let monthsAgo: Int?   // nil = dans la PAL
    }

    // Titres et auteurs fictifs (captures d'écran de l'App Store : aucun contenu protégé).
    private static let samples: [Sample] = [
        Sample(title: "Les Jardins de Sel", author: "Claire Vasseur", isbn: "", pages: 342, genre: "Roman", community: 4.3, votes: 1520, myRating: 5, monthsAgo: 0),
        Sample(title: "Nuit sur Orbe", author: "Malik Renaud", isbn: "", pages: 512, genre: "Science-fiction", community: 4.5, votes: 3210, myRating: 5, monthsAgo: 1),
        Sample(title: "Le Cartographe d'hiver", author: "Inès Moreau", isbn: "", pages: 288, genre: "Aventure", community: 4.1, votes: 870, myRating: 4, monthsAgo: 1),
        Sample(title: "Ce que la mer garde", author: "Claire Vasseur", isbn: "", pages: 264, genre: "Roman", community: 4.0, votes: 990, myRating: 4, monthsAgo: 2),
        Sample(title: "L'Affaire du quai Lune", author: "Paul Ardent", isbn: "", pages: 416, genre: "Policier", community: 4.2, votes: 1650, myRating: 4, monthsAgo: 3),
        Sample(title: "Petite histoire du temps lent", author: "Jeanne Albrecht", isbn: "", pages: 224, genre: "Essai", community: 4.4, votes: 4100, myRating: 5, monthsAgo: 4),
        Sample(title: "La Forêt des neuf portes", author: "Hugo Larcher", isbn: "", pages: 736, genre: "Fantasy", community: 4.6, votes: 5230, myRating: 5, monthsAgo: 5),
        Sample(title: "Les Heures pâles", author: "Inès Moreau", isbn: "", pages: 198, genre: "Roman", community: 3.8, votes: 760, myRating: 3, monthsAgo: 6),
        Sample(title: "Signal faible", author: "Malik Renaud", isbn: "", pages: 448, genre: "Science-fiction", community: 4.2, votes: 2870, myRating: 4, monthsAgo: 8),
        Sample(title: "Le Dernier Été à Valmont", author: "Sophie Garnier", isbn: "", pages: 312, genre: "Roman", community: 4.0, votes: 980, myRating: 3, monthsAgo: 13),
        Sample(title: "L'Archipel suspendu", author: "Hugo Larcher", isbn: "", pages: 640, genre: "Fantasy", community: 4.7, votes: 2410, myRating: 0, monthsAgo: nil),
        Sample(title: "Mémoires d'un phare", author: "Sophie Garnier", isbn: "", pages: 256, genre: "Roman", community: 4.3, votes: 1340, myRating: 0, monthsAgo: nil),
        Sample(title: "Le Code des abeilles", author: "Paul Ardent", isbn: "", pages: 384, genre: "Policier", community: 4.1, votes: 1120, myRating: 0, monthsAgo: nil),
        Sample(title: "Vers les étoiles froides", author: "Malik Renaud", isbn: "", pages: 528, genre: "Science-fiction", community: 4.4, votes: 900, myRating: 0, monthsAgo: nil),
        Sample(title: "Le Goût des oranges amères", author: "Jeanne Albrecht", isbn: "", pages: 296, genre: "Roman", community: 3.9, votes: 650, myRating: 0, monthsAgo: nil),
    ]

    static func insert(into context: ModelContext) {
        let calendar = Calendar.current
        for (index, s) in samples.enumerated() {
            let status: ReadingStatus = s.monthsAgo == nil ? .toRead : .read
            let book = Book(title: s.title, authors: s.author, status: status)
            book.pageCount = s.pages
            book.categories = s.genre
            book.communityRating = s.community
            book.communityRatingsCount = s.votes
            book.myRating = s.myRating
            book.summary = "Une histoire lumineuse et pleine de suspense, portée par des personnages attachants. Un roman qu'on referme à regret."
            book.dateAdded = calendar.date(byAdding: .day, value: -index * 9, to: .now) ?? .now
            if let months = s.monthsAgo {
                book.dateFinished = calendar.date(byAdding: .month, value: -months, to: .now)
                if s.myRating >= 4 {
                    book.myReview = "Coup de cœur ! Je le recommande sans hésiter."
                }
            }
            context.insert(book)
        }
        try? context.save()
    }
}
