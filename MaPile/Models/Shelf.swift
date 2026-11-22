import Foundation
import SwiftData
import SwiftUI

/// Type de pile : choisie à la main, ou remplie automatiquement par auteur ou par genre.
enum ShelfKind: String, CaseIterable, Identifiable {
    case custom, author, genre, series

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom: "Personnalisée"
        case .author: "Par auteur"
        case .genre: "Par genre"
        case .series: "Par série"
        }
    }

    var systemImage: String {
        switch self {
        case .custom: "hand.point.up.left"
        case .author: "person"
        case .genre: "theatermasks"
        case .series: "books.vertical.circle"
        }
    }
}

/// Une pile de livres (collection). Les piles « auteur » et « genre » se remplissent toutes seules.
@Model
final class Shelf {
    var uuid: UUID = UUID()
    var name: String = ""
    var emoji: String = "📚"
    var colorIndex: Int = 0
    var kindRaw: String = ShelfKind.custom.rawValue
    /// Nom de l'auteur ou du genre pour les piles automatiques.
    var criterion: String = ""
    /// Identifiants des livres d'une pile personnalisée, dans l'ordre d'ajout.
    var bookIDs: [String] = []
    var createdAt: Date = Date()

    init(name: String, emoji: String = "📚", colorIndex: Int = 0, kind: ShelfKind = .custom, criterion: String = "") {
        self.name = name
        self.emoji = emoji
        self.colorIndex = colorIndex
        self.kindRaw = kind.rawValue
        self.criterion = criterion
    }
}

extension Shelf {
    static let palette: [Color] = [.orange, .red, .pink, .purple, .indigo, .blue, .teal, .green, .brown]

    var kind: ShelfKind {
        get { ShelfKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var color: Color { Self.palette[abs(colorIndex) % Self.palette.count] }

    /// Livres de la pile, parmi tous les livres de la bibliothèque.
    func books(from all: [Book]) -> [Book] {
        switch kind {
        case .custom:
            var byID: [String: Book] = [:]
            for book in all { byID[book.uuid.uuidString] = book }
            return bookIDs.compactMap { byID[$0] }
        case .author:
            let key = BookSearchService.normalize(criterion)
            return all.filter { book in book.authorList.contains { BookSearchService.normalize($0) == key } }
        case .genre:
            let key = BookSearchService.normalize(criterion)
            return all.filter { book in book.genreList.contains { BookSearchService.normalize($0) == key } }
        case .series:
            let key = BookSearchService.normalize(criterion)
            return all.filter { BookSearchService.normalize($0.seriesName) == key }
                .sorted { $0.seriesIndex < $1.seriesIndex }
        }
    }

    func contains(_ book: Book) -> Bool {
        bookIDs.contains(book.uuid.uuidString)
    }

    func toggle(_ book: Book) {
        let id = book.uuid.uuidString
        if let index = bookIDs.firstIndex(of: id) {
            bookIDs.remove(at: index)
        } else {
            bookIDs.append(id)
        }
    }
}
