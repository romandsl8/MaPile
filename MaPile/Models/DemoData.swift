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

    private static let samples: [Sample] = [
        Sample(title: "L'Étranger", author: "Albert Camus", isbn: "9782070360024", pages: 186, genre: "Roman", community: 4.0, votes: 1520, myRating: 5, monthsAgo: 0),
        Sample(title: "Le Petit Prince", author: "Antoine de Saint-Exupéry", isbn: "9782070612758", pages: 104, genre: "Conte", community: 4.4, votes: 3210, myRating: 4, monthsAgo: 1),
        Sample(title: "Dune", author: "Frank Herbert", isbn: "9782266320481", pages: 928, genre: "Science-fiction", community: 4.3, votes: 2870, myRating: 5, monthsAgo: 2),
        Sample(title: "Les Misérables", author: "Victor Hugo", isbn: "9782253096337", pages: 1664, genre: "Roman", community: 4.2, votes: 1980, myRating: 4, monthsAgo: 3),
        Sample(title: "Fondation", author: "Isaac Asimov", isbn: "9782070360536", pages: 416, genre: "Science-fiction", community: 4.2, votes: 1650, myRating: 4, monthsAgo: 4),
        Sample(title: "La Peste", author: "Albert Camus", isbn: "9782070360420", pages: 352, genre: "Roman", community: 4.0, votes: 980, myRating: 3, monthsAgo: 5),
        Sample(title: "Sapiens", author: "Yuval Noah Harari", isbn: "9782226257017", pages: 512, genre: "Essai", community: 4.4, votes: 4100, myRating: 5, monthsAgo: 6),
        Sample(title: "Le Seigneur des anneaux", author: "J.R.R. Tolkien", isbn: "9782266282369", pages: 1216, genre: "Fantasy", community: 4.5, votes: 5230, myRating: 5, monthsAgo: 8),
        Sample(title: "1984", author: "George Orwell", isbn: "9782070368228", pages: 438, genre: "Science-fiction", community: 4.2, votes: 3900, myRating: 4, monthsAgo: 13),
        Sample(title: "Madame Bovary", author: "Gustave Flaubert", isbn: "9782070413119", pages: 512, genre: "Roman", community: 3.7, votes: 760, myRating: 3, monthsAgo: 15),
        Sample(title: "Le Comte de Monte-Cristo", author: "Alexandre Dumas", isbn: "9782253098058", pages: 1504, genre: "Aventure", community: 4.6, votes: 2410, myRating: 0, monthsAgo: nil),
        Sample(title: "Projet Dernière Chance", author: "Andy Weir", isbn: "9782809845570", pages: 480, genre: "Science-fiction", community: 4.5, votes: 1340, myRating: 0, monthsAgo: nil),
        Sample(title: "L'Anomalie", author: "Hervé Le Tellier", isbn: "9782072895098", pages: 336, genre: "Roman", community: 3.9, votes: 870, myRating: 0, monthsAgo: nil),
        Sample(title: "Le Nom de la rose", author: "Umberto Eco", isbn: "9782253033134", pages: 640, genre: "Policier", community: 4.1, votes: 1120, myRating: 0, monthsAgo: nil),
        Sample(title: "Germinal", author: "Émile Zola", isbn: "9782253004226", pages: 592, genre: "Roman", community: 4.0, votes: 990, myRating: 0, monthsAgo: nil),
    ]

    static func insert(into context: ModelContext) {
        let calendar = Calendar.current
        for (index, s) in samples.enumerated() {
            let status: ReadingStatus = s.monthsAgo == nil ? .toRead : .read
            let book = Book(title: s.title, authors: s.author, status: status)
            book.isbn = s.isbn
            book.pageCount = s.pages
            book.categories = s.genre
            book.communityRating = s.community
            book.communityRatingsCount = s.votes
            book.ratingSource = "Google Books"
            book.myRating = s.myRating
            book.coverURLString = "https://covers.openlibrary.org/b/isbn/\(s.isbn)-L.jpg?default=false"
            book.infoLink = "https://openlibrary.org/isbn/\(s.isbn)"
            book.summary = "Un classique incontournable : une histoire marquante, des personnages inoubliables et une écriture qui a traversé les époques. (Texte d'exemple pour l'aperçu de l'application.)"
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
