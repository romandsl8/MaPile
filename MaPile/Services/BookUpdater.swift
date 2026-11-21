import Foundation
import UIKit

/// Vérifie une fiche en ligne : note de la plateforme qui a le plus d'avis,
/// informations manquantes et couverture de meilleure qualité.
@MainActor
enum BookUpdater {
    enum Outcome {
        case updated(String)
        case unchanged
        case notFound
    }

    /// Délai conseillé entre deux vérifications automatiques d'un même livre.
    static let autoCheckInterval: TimeInterval = 30 * 24 * 3600

    static func needsAutoCheck(_ book: Book) -> Bool {
        guard let last = book.lastCheckedAt else { return true }
        return Date.now.timeIntervalSince(last) > autoCheckInterval
            || book.communityRating == nil || book.summary.isEmpty || book.coverData == nil
    }

    @discardableResult
    static func check(_ book: Book) async -> Outcome {
        defer { book.lastCheckedAt = .now }
        guard let result = await BookSearchService.bestMatch(title: book.title, authors: book.authors,
                                                            isbn: book.isbn, strict: true) else {
            // Même sans correspondance exacte, on tente d'améliorer la couverture actuelle.
            return await improveCover(book, candidates: []) ? .updated("Couverture améliorée") : .notFound
        }
        var changes: [String] = []
        let oldRating = book.communityRating
        let oldCount = book.communityRatingsCount
        let hadSummary = !book.summary.isEmpty

        book.apply(result, onlyMissing: true)

        if let rating = book.communityRating,
           oldRating != rating || oldCount != book.communityRatingsCount {
            let count = book.communityRatingsCount.map { " (\($0) avis)" } ?? ""
            changes.append("Note \(rating.frenchDecimal)/5\(count) – \(book.ratingSource ?? "")")
        }
        if !hadSummary && !book.summary.isEmpty { changes.append("Résumé ajouté") }
        if await improveCover(book, candidates: BookSearchService.coverCandidates(for: result)) {
            changes.append("Couverture en meilleure qualité")
        }
        return changes.isEmpty ? .unchanged : .updated(changes.joined(separator: "\n"))
    }

    /// Remplace la couverture si une version nettement plus grande existe.
    private static func improveCover(_ book: Book, candidates: [URL]) async -> Bool {
        var urls = candidates
        if let current = book.coverURL { urls.append(current) }
        guard !urls.isEmpty, let best = await BookSearchService.bestCover(urls) else { return false }
        let currentPixels: Int = {
            guard let data = book.coverData, let image = UIImage(data: data) else { return 0 }
            return Int(image.size.width * image.scale * image.size.height * image.scale)
        }()
        guard best.pixels > Int(Double(currentPixels) * 1.2) else { return false }
        book.coverData = best.data
        book.coverURLString = best.url.absoluteString
        return true
    }
}
