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
    var openLibraryEditionKey: String?
}

/// Recherche de livres via Google Books (principal) et Open Library (secours et notes).
/// Les deux services sont gratuits et sans clé pour un usage personnel.
enum BookSearchService {

    // MARK: - Recherche

    static func search(_ raw: String) async -> [BookResult] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        let isbn = normalizedISBN(query)
        let googleQuery = isbn.map { "isbn:\($0)" } ?? query
        // Avec un ISBN, une seule recherche suffit ; sinon on demande aussi les éditions dans la langue de l'iPhone.
        async let googleLocal = googleSearch(googleQuery, language: userLanguage, enabled: isbn == nil)
        async let googleAll = googleSearch(googleQuery, language: nil)
        async let openLib = openLibrarySearch(query: query, isbn: isbn)
        var g = await googleLocal
        for item in await googleAll where !g.contains(where: { $0.id == item.id }) {
            g.append(item)
        }
        let o = await openLib
        return preferUserLanguage(merge(g, o))
    }

    /// Clé Google Books, injectée à la compilation depuis le secret GitHub GOOGLE_BOOKS_API_KEY.
    static let googleAPIKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GoogleBooksAPIKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }()

    /// Code langue de l'iPhone (« fr »), utilisé pour privilégier les éditions traduites.
    static var userLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "fr"
    }

    /// Code ISO 639-2 utilisé par Open Library (« fre » pour le français).
    private static var openLibraryLanguage: String {
        let map = ["fr": "fre", "en": "eng", "de": "ger", "es": "spa", "it": "ita", "pt": "por", "nl": "dut"]
        return map[userLanguage] ?? "fre"
    }

    /// Place en tête les résultats dans la langue de l'iPhone, sans changer l'ordre du reste.
    static func preferUserLanguage(_ results: [BookResult]) -> [BookResult] {
        let lang = userLanguage
        var preferred: [BookResult] = []
        var others: [BookResult] = []
        for item in results {
            if let l = item.language, l.hasPrefix(lang) || l == openLibraryLanguage {
                preferred.append(item)
            } else {
                others.append(item)
            }
        }
        return preferred + others
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
        // Résumé de l'édition (souvent dans la bonne langue) avant celui de l'œuvre.
        if r.summary.isEmpty,
           let editionKey = r.openLibraryEditionKey,
           let url = URL(string: "https://openlibrary.org\(editionKey).json"),
           let edition = await fetch(url, as: OLWork.self),
           let text = edition.description?.text {
            r.summary = cleanDescription(text)
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

    static func googleSearch(_ q: String, language: String?, enabled: Bool = true) async -> [BookResult] {
        guard enabled else { return [] }
        var c = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        var items: [URLQueryItem] = [
            .init(name: "q", value: q),
            .init(name: "maxResults", value: "20"),
            .init(name: "printType", value: "books"),
        ]
        if let language { items.append(.init(name: "langRestrict", value: language)) }
        if let key = googleAPIKey { items.append(.init(name: "key", value: key)) }
        c.queryItems = items
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
        let olLang = openLibraryLanguage
        c.queryItems = [
            .init(name: "q", value: q),
            .init(name: "limit", value: "10"),
            // « lang » : Open Library choisit l'édition dans cette langue (ex. « La Psy » plutôt que « Never Lie »).
            .init(name: "lang", value: userLanguage),
            .init(name: "fields", value: "key,title,author_name,first_publish_year,isbn,cover_i,number_of_pages_median,subject,ratings_average,ratings_count,publisher,language,editions,editions.key,editions.title,editions.isbn,editions.cover_i,editions.language,editions.publisher,editions.publish_date,editions.number_of_pages"),
        ]
        guard let url = c.url, let response = await fetch(url, as: OLSearch.self) else { return [] }
        return response.docs.compactMap { doc -> BookResult? in
            // L'édition renvoyée est celle qui correspond le mieux à la recherche et à la langue.
            let edition = doc.editions?.docs.first
            guard let title = edition?.title ?? doc.title, !title.isEmpty else { return nil }
            let editionISBNs = edition?.isbn ?? []
            let isbns = editionISBNs + (doc.isbn ?? [])
            let chosenISBN = isbn
                ?? editionISBNs.first { $0.count == 13 } ?? editionISBNs.first
                ?? isbns.first { $0.count == 13 } ?? isbns.first
            var cover: URL?
            if let id = edition?.cover_i ?? doc.cover_i {
                cover = URL(string: "https://covers.openlibrary.org/b/id/\(id)-L.jpg")
            }
            var language: String?
            if let editionLanguage = edition?.language?.first {
                language = editionLanguage == olLang ? userLanguage : editionLanguage
            } else if let workLanguages = doc.language, workLanguages.contains(olLang), edition == nil {
                language = userLanguage
            }
            return BookResult(
                id: "ol-\(edition?.key ?? doc.key)",
                title: title,
                authors: doc.author_name ?? [],
                coverURL: cover,
                isbn: chosenISBN,
                allISBNs: isbns,
                pageCount: edition?.number_of_pages ?? doc.number_of_pages_median,
                publisher: edition?.publisher?.first ?? doc.publisher?.first,
                publishedDate: edition?.publish_date?.first ?? doc.first_publish_year.map { String($0) },
                categories: Array((doc.subject ?? []).prefix(3)),
                language: language,
                averageRating: doc.ratings_average,
                ratingsCount: doc.ratings_count,
                ratingSource: doc.ratings_average == nil ? nil : .openLibrary,
                infoLink: URL(string: "https://openlibrary.org\(doc.key)"),
                source: .openLibrary,
                openLibraryKey: doc.key,
                openLibraryEditionKey: edition?.key
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
        // Permet de restreindre la clé Google à cette app (restriction « Applications iOS »).
        if url.host == "www.googleapis.com", let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
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
    let language: [String]?
    let editions: OLEditions?
}
private struct OLEditions: Decodable { let docs: [OLEdition] }
private struct OLEdition: Decodable {
    let key: String
    let title: String?
    let isbn: [String]?
    let cover_i: Int?
    let language: [String]?
    let publisher: [String]?
    let publish_date: [String]?
    let number_of_pages: Int?
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
