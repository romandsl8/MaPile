import Foundation
import UIKit

/// Résultat de recherche en ligne (pas encore enregistré dans la bibliothèque).
struct BookResult: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        case google = "Google Books"
        case openLibrary = "Open Library"
    }

    var id: String
    var title: String
    var authors: [String] = []
    var summary: String = ""
    var coverURL: URL?
    var isbn: String?
    var allISBNs: [String] = []
    var pageCount: Int?
    var publisher: String?
    var publishedDate: String?
    var categories: [String] = []
    var language: String?
    var averageRating: Double?
    var ratingsCount: Int?
    var ratingSource: Source?
    var infoLink: URL?
    var source: Source
    var openLibraryKey: String?
}

/// Recherche de livres via Google Books (principal) et Open Library (secours et notes).
/// Les deux services sont gratuits et sans clé pour un usage personnel.
enum BookSearchService {

    // MARK: - Recherche

    static func search(_ raw: String) async -> [BookResult] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        let isbn = normalizedISBN(query)
        async let google = googleSearch(isbn.map { "isbn:\($0)" } ?? query)
        async let openLib = openLibrarySearch(query: query, isbn: isbn)
        let g = await google
        let o = await openLib
        return merge(g, o)
    }

    /// Complète un résultat : résumé et note des lecteurs via Open Library si Google ne les donne pas.
    static func enrich(_ result: BookResult) async -> BookResult {
        var r = result
        if r.openLibraryKey == nil, r.summary.isEmpty || r.averageRating == nil {
            let q = r.isbn == nil ? "\(r.title) \(r.authors.first ?? "")" : ""
            let candidates = await openLibrarySearch(query: q, isbn: r.isbn)
            if let match = candidates.first(where: { matches(r, $0) }) ?? (r.isbn != nil ? candidates.first : nil) {
                r.openLibraryKey = match.openLibraryKey
                if r.averageRating == nil, let avg = match.averageRating {
                    r.averageRating = avg
                    r.ratingsCount = match.ratingsCount
                    r.ratingSource = .openLibrary
                }
                if r.coverURL == nil { r.coverURL = match.coverURL }
                if r.pageCount == nil { r.pageCount = match.pageCount }
            }
        }
        if let key = r.openLibraryKey {
            if r.summary.isEmpty,
               let url = URL(string: "https://openlibrary.org\(key).json"),
               let work = await fetch(url, as: OLWork.self),
               let text = work.description?.text {
                r.summary = cleanDescription(text)
            }
            if r.averageRating == nil,
               let url = URL(string: "https://openlibrary.org\(key)/ratings.json"),
               let ratings = await fetch(url, as: OLRatings.self),
               let avg = ratings.summary?.average {
                r.averageRating = avg
                r.ratingsCount = ratings.summary?.count
                r.ratingSource = .openLibrary
            }
        }
        return r
    }

    /// Cherche le meilleur résultat pour un livre déjà enregistré (bouton « Actualiser »).
    static func bestMatch(title: String, authors: String, isbn: String?) async -> BookResult? {
        let query = isbn ?? "\(title) \(authors.split(separator: ",").first ?? "")"
        let results = await search(query)
        let reference = BookResult(id: "ref", title: title,
                                   authors: authors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                   isbn: isbn, source: .google)
        guard let best = results.first(where: { matches(reference, $0) }) ?? results.first else { return nil }
        return await enrich(best)
    }

    static func downloadImage(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        guard let data = await fetchData(url),
              let image = UIImage(data: data),
              image.size.width > 10 else { return nil }
        // On recompresse pour garder une base de données légère.
        return image.jpegData(compressionQuality: 0.85)
    }

    // MARK: - Google Books

    static func googleSearch(_ q: String) async -> [BookResult] {
        var c = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        c.queryItems = [
            .init(name: "q", value: q),
            .init(name: "maxResults", value: "20"),
            .init(name: "printType", value: "books"),
        ]
        guard let url = c.url, let response = await fetch(url, as: GBResponse.self) else { return [] }
        return (response.items ?? []).compactMap { item -> BookResult? in
            let v = item.volumeInfo
            guard let title = v.title, !title.isEmpty else { return nil }
            let ids = v.industryIdentifiers ?? []
            let isbn13 = ids.first { $0.type == "ISBN_13" }?.identifier
            let isbn10 = ids.first { $0.type == "ISBN_10" }?.identifier
            let links = v.imageLinks
            let cover = (links?.medium ?? links?.small ?? links?.thumbnail ?? links?.smallThumbnail)
                .flatMap(secureGoogleImage)
            return BookResult(
                id: "g-\(item.id)",
                title: title,
                authors: v.authors ?? [],
                summary: cleanDescription(v.description ?? ""),
                coverURL: cover,
                isbn: isbn13 ?? isbn10,
                allISBNs: [isbn13, isbn10].compactMap { $0 },
                pageCount: v.pageCount,
                publisher: v.publisher,
                publishedDate: v.publishedDate,
                categories: v.categories ?? [],
                language: v.language,
                averageRating: v.averageRating,
                ratingsCount: v.ratingsCount,
                ratingSource: v.averageRating == nil ? nil : .google,
                infoLink: (v.canonicalVolumeLink ?? v.infoLink).flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) },
                source: .google
            )
        }
    }

    private static func secureGoogleImage(_ s: String) -> URL? {
        let fixed = s
            .replacingOccurrences(of: "http://", with: "https://")
            .replacingOccurrences(of: "&edge=curl", with: "")
        return URL(string: fixed)
    }

    // MARK: - Open Library

    static func openLibrarySearch(query: String, isbn: String?) async -> [BookResult] {
        var c = URLComponents(string: "https://openlibrary.org/search.json")!
        let q = isbn.map { "isbn:\($0)" } ?? query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        c.queryItems = [
            .init(name: "q", value: q),
            .init(name: "limit", value: "10"),
            .init(name: "lang", value: "fr"),
            .init(name: "fields", value: "key,title,author_name,first_publish_year,isbn,cover_i,number_of_pages_median,subject,ratings_average,ratings_count,publisher"),
        ]
        guard let url = c.url, let response = await fetch(url, as: OLSearch.self) else { return [] }
        return response.docs.compactMap { doc -> BookResult? in
            guard let title = doc.title, !title.isEmpty else { return nil }
            let isbns = doc.isbn ?? []
            let chosenISBN = isbn ?? isbns.first { $0.count == 13 } ?? isbns.first
            var cover: URL?
            if let id = doc.cover_i { cover = URL(string: "https://covers.openlibrary.org/b/id/\(id)-L.jpg") }
            return BookResult(
                id: "ol-\(doc.key)",
                title: title,
                authors: doc.author_name ?? [],
                coverURL: cover,
                isbn: chosenISBN,
                allISBNs: isbns,
                pageCount: doc.number_of_pages_median,
                publisher: doc.publisher?.first,
                publishedDate: doc.first_publish_year.map(String.init),
                categories: Array((doc.subject ?? []).prefix(3)),
                averageRating: doc.ratings_average,
                ratingsCount: doc.ratings_count,
                ratingSource: doc.ratings_average == nil ? nil : .openLibrary,
                infoLink: URL(string: "https://openlibrary.org\(doc.key)"),
                source: .openLibrary,
                openLibraryKey: doc.key
            )
        }
    }

    // MARK: - Fusion des deux sources

    static func merge(_ google: [BookResult], _ openLibrary: [BookResult]) -> [BookResult] {
        var result = google
        for i in result.indices {
            guard let match = openLibrary.first(where: { matches(result[i], $0) }) else { continue }
            result[i].openLibraryKey = match.openLibraryKey
            if result[i].averageRating == nil, let avg = match.averageRating {
                result[i].averageRating = avg
                result[i].ratingsCount = match.ratingsCount
                result[i].ratingSource = .openLibrary
            }
            if result[i].coverURL == nil { result[i].coverURL = match.coverURL }
        }
        for item in openLibrary where !result.contains(where: { matches($0, item) }) {
            result.append(item)
        }
        return result
    }

    static func matches(_ a: BookResult, _ b: BookResult) -> Bool {
        let aISBNs = Set(a.allISBNs + [a.isbn].compactMap { $0 })
        let bISBNs = Set(b.allISBNs + [b.isbn].compactMap { $0 })
        if !aISBNs.isDisjoint(with: bISBNs) { return true }
        let sameTitle = normalize(a.title) == normalize(b.title)
        let aAuthor = normalize(a.authors.first ?? "")
        let bAuthor = normalize(b.authors.first ?? "")
        return sameTitle && (aAuthor == bAuthor || aAuthor.isEmpty || bAuthor.isEmpty)
    }

    // MARK: - Outils

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Renvoie un ISBN propre si la saisie en est un (10 ou 13 caractères).
    static func normalizedISBN(_ s: String) -> String? {
        let cleaned = s.uppercased().filter { $0.isNumber || $0 == "X" }
        let onlyISBNChars = s.allSatisfy { $0.isNumber || $0 == "-" || $0 == " " || $0 == "X" || $0 == "x" }
        guard onlyISBNChars else { return nil }
        if cleaned.count == 13, cleaned.hasPrefix("978") || cleaned.hasPrefix("979") { return cleaned }
        if cleaned.count == 10 { return cleaned }
        return nil
    }

    static func cleanDescription(_ text: String) -> String {
        var s = text
        if let cut = s.range(of: "----------") { s = String(s[..<cut.lowerBound]) }
        for tag in ["<br>", "<br/>", "<br />", "</p>", "<p>"] {
            s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&lt;": "<", "&gt;": ">"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetchData(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("MaPile/1.0 (iOS reading tracker)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func fetch<T: Decodable>(_ url: URL, as type: T.Type) async -> T? {
        guard let data = await fetchData(url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Formats JSON

private struct GBResponse: Decodable { let items: [GBItem]? }
private struct GBItem: Decodable { let id: String; let volumeInfo: GBVolume }
private struct GBVolume: Decodable {
    let title: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
    let description: String?
    let industryIdentifiers: [GBIdentifier]?
    let pageCount: Int?
    let categories: [String]?
    let averageRating: Double?
    let ratingsCount: Int?
    let imageLinks: GBImageLinks?
    let language: String?
    let infoLink: String?
    let canonicalVolumeLink: String?
}
private struct GBIdentifier: Decodable { let type: String; let identifier: String }
private struct GBImageLinks: Decodable {
    let smallThumbnail: String?
    let thumbnail: String?
    let small: String?
    let medium: String?
}

private struct OLSearch: Decodable { let docs: [OLDoc] }
private struct OLDoc: Decodable {
    let key: String
    let title: String?
    let author_name: [String]?
    let first_publish_year: Int?
    let isbn: [String]?
    let cover_i: Int?
    let number_of_pages_median: Int?
    let subject: [String]?
    let ratings_average: Double?
    let ratings_count: Int?
    let publisher: [String]?
}
private struct OLWork: Decodable { let description: OLText? }
private struct OLText: Decodable {
    let text: String
    private struct Wrapped: Decodable { let value: String }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            text = s
        } else {
            text = try c.decode(Wrapped.self).value
        }
    }
}
private struct OLRatings: Decodable {
    struct Summary: Decodable { let average: Double?; let count: Int? }
    let summary: Summary?
}
