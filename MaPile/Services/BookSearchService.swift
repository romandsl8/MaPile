import Foundation
import UIKit

/// Résultat de recherche en ligne (pas encore enregistré dans la bibliothèque).
struct BookResult: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        case google = "Google Books"
        case openLibrary = "Open Library"
        case appleBooks = "Apple Books"
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
    /// Couvertures possibles : la plus grande est choisie au téléchargement.
    var coverCandidates: [URL] = []
    /// Déjà complété avec Apple Books.
    var appleMerged = false
    /// Identifiant du livre sur Apple Books (pour lire les avis des lecteurs).
    var appleBooksID: String?
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
        // Apple Books ne se cherche pas par ISBN papier : seulement par titre/auteur.
        async let apple = appleBooksSearch(isbn == nil ? query : "")
        var g = await googleLocal
        for item in await googleAll where !g.contains(where: { $0.id == item.id }) {
            g.append(item)
        }
        let o = await openLib
        let a = await apple
        var results = merge(g, o)
        if isbn != nil, let first = results.first {
            // Recherche par ISBN : on complète l'édition trouvée avec Apple Books (note, résumé, couverture).
            let extra = await appleBooksSearch("\(first.title) \(first.authors.first ?? "")")
            results = mergeApple(results, extra, appendUnmatched: false)
        } else {
            results = mergeApple(results, a, appendUnmatched: true)
        }
        return preferUserLanguage(results)
    }

    /// Complète les résultats avec Apple Books : note (si plus fiable), résumé, couverture HD, lien vers les avis.
    static func mergeApple(_ results: [BookResult], _ apple: [BookResult], appendUnmatched: Bool) -> [BookResult] {
        var merged = results
        var used = Set<String>()
        for i in merged.indices {
            guard let match = apple.first(where: { matches(merged[i], $0) }) else { continue }
            used.insert(match.id)
            fill(&merged[i], from: match)
        }
        if appendUnmatched {
            for item in apple where !used.contains(item.id) && !merged.contains(where: { matches($0, item) }) {
                merged.append(item)
            }
        }
        return merged
    }

    /// Recopie ce qui manque (ou ce qui est meilleur) d'un résultat Apple Books.
    private static func fill(_ r: inout BookResult, from apple: BookResult) {
        r.appleMerged = true
        if r.appleBooksID == nil { r.appleBooksID = apple.appleBooksID }
        offerRating(&r, apple.averageRating, apple.ratingsCount, .appleBooks, apple.infoLink)
        if r.summary.isEmpty { r.summary = apple.summary }
        // La couverture Apple est en haute définition : candidate prioritaire.
        if let cover = apple.coverURL { r.coverCandidates.insert(cover, at: 0) }
        if r.coverURL == nil { r.coverURL = apple.coverURL }
        if r.categories.isEmpty { r.categories = apple.categories }
        if r.publishedDate == nil { r.publishedDate = apple.publishedDate }
        if r.infoLink == nil { r.infoLink = apple.infoLink }
    }

    /// Garde la note qui repose sur le plus grand nombre d'avis.
    static func offerRating(_ r: inout BookResult, _ average: Double?, _ count: Int?, _ source: BookResult.Source, _ link: URL?) {
        guard let average, average > 0 else { return }
        let current = r.averageRating == nil ? -1 : (r.ratingsCount ?? 0)
        guard (count ?? 0) > current else { return }
        r.averageRating = average
        r.ratingsCount = count
        r.ratingSource = source
        if let link { r.infoLink = link }
    }

    // MARK: - Apple Books (API publique iTunes Search, sans clé)

    static func appleBooksSearch(_ term: String) async -> [BookResult] {
        let q = term.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        let country = (Locale.current.region?.identifier ?? "FR").lowercased()
        c.queryItems = [
            .init(name: "term", value: q),
            .init(name: "media", value: "ebook"),
            .init(name: "country", value: country),
            .init(name: "limit", value: "15"),
        ]
        guard let url = c.url, let response = await fetch(url, as: ABResponse.self) else { return [] }
        return response.results.compactMap { item -> BookResult? in
            guard let title = item.trackName, !title.isEmpty else { return nil }
            let authors = (item.artistName ?? "")
                .replacingOccurrences(of: " & ", with: ", ")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let cover = item.artworkUrl100
                .map { $0.replacingOccurrences(of: "100x100bb", with: "1400x1400bb") }
                .flatMap(URL.init(string:))
            return BookResult(
                id: "ab-\(item.trackId ?? 0)-\(title)",
                title: title,
                authors: authors,
                summary: cleanDescription(item.description ?? ""),
                coverURL: cover,
                publishedDate: item.releaseDate.map { String($0.prefix(4)) },
                categories: (item.genres ?? []).filter { $0 != "Livres" && $0 != "Books" }.prefix(3).map { $0 },
                averageRating: item.averageUserRating,
                ratingsCount: item.userRatingCount,
                ratingSource: item.averageUserRating == nil ? nil : .appleBooks,
                infoLink: item.trackViewUrl.flatMap(URL.init(string:)),
                source: .appleBooks,
                appleBooksID: item.trackId.map { String($0) }
            )
        }
    }

    // MARK: - Avis des lecteurs (flux public Apple Books)

    struct ReaderReview: Identifiable, Hashable, Sendable {
        let id: String
        let author: String
        let title: String
        let content: String
        let rating: Int
        let date: Date?
    }

    enum ReviewSort: String, CaseIterable, Identifiable, Sendable {
        case helpful = "mosthelpful"
        case recent = "mostrecent"
        var id: String { rawValue }
        var label: String { self == .helpful ? "Les plus utiles" : "Les plus récents" }
    }

    /// Avis publiés par les lecteurs sur Apple Books (jusqu'à 50 par page).
    static func appleBooksReviews(id: String, sort: ReviewSort = .helpful) async -> [ReaderReview] {
        let country = (Locale.current.region?.identifier ?? "FR").lowercased()
        guard let url = URL(string: "https://itunes.apple.com/\(country)/rss/customerreviews/page=1/id=\(id)/sortby=\(sort.rawValue)/json"),
              let data = await fetchData(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [String: Any] else { return [] }
        // Le flux renvoie un tableau, ou un objet seul quand il n'y a qu'un avis.
        let entries: [[String: Any]]
        if let list = feed["entry"] as? [[String: Any]] {
            entries = list
        } else if let single = feed["entry"] as? [String: Any] {
            entries = [single]
        } else {
            return []
        }
        func label(_ entry: [String: Any], _ key: String) -> String? {
            (entry[key] as? [String: Any])?["label"] as? String
        }
        let iso = ISO8601DateFormatter()
        return entries.compactMap { entry -> ReaderReview? in
            guard let ratingText = label(entry, "im:rating"), let rating = Int(ratingText) else { return nil }
            let content = (label(entry, "content") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (label(entry, "title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty || !title.isEmpty else { return nil }
            let author = ((entry["author"] as? [String: Any])?["name"] as? [String: Any])?["label"] as? String
            return ReaderReview(id: label(entry, "id") ?? UUID().uuidString,
                                author: author ?? "Lecteur",
                                title: title,
                                content: content,
                                rating: rating,
                                date: label(entry, "updated").flatMap { iso.date(from: $0) })
        }
    }

    /// Retrouve l'identifiant Apple Books d'un livre (titre + auteur), si le livre y est vendu.
    static func findAppleBooksID(title: String, authors: String) async -> String? {
        let author = authors.split(separator: ",").first.map(String.init) ?? ""
        let reference = BookResult(id: "ref", title: title,
                                   authors: author.isEmpty ? [] : [author.trimmingCharacters(in: .whitespaces)],
                                   source: .google)
        let candidates = await appleBooksSearch("\(title) \(author)")
        return candidates.first(where: { matches(reference, $0) })?.appleBooksID
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

    /// Complète un résultat en interrogeant toutes les sources : résumé, pages, couvertures candidates,
    /// et note des lecteurs de la plateforme qui compte le plus d'avis.
    static func enrich(_ result: BookResult) async -> BookResult {
        var r = result
        let titleQuery = "\(r.title) \(r.authors.first ?? "")"
        let needsOpenLibrary = r.openLibraryKey == nil
        let olQuery = needsOpenLibrary && r.isbn == nil ? titleQuery : ""
        let olISBN = needsOpenLibrary ? r.isbn : nil
        let appleQuery = r.appleMerged || r.source == .appleBooks ? "" : titleQuery
        async let olCandidates = openLibrarySearch(query: olQuery, isbn: olISBN)
        async let appleCandidates = appleBooksSearch(appleQuery)

        let ol = await olCandidates
        if let match = ol.first(where: { matches(r, $0) }) ?? (r.isbn != nil ? ol.first : nil) {
            if r.openLibraryKey == nil { r.openLibraryKey = match.openLibraryKey }
            if r.openLibraryEditionKey == nil { r.openLibraryEditionKey = match.openLibraryEditionKey }
            offerRating(&r, match.averageRating, match.ratingsCount, .openLibrary, match.infoLink)
            if let cover = match.coverURL { r.coverCandidates.append(cover) }
            if r.coverURL == nil { r.coverURL = match.coverURL }
            if r.pageCount == nil { r.pageCount = match.pageCount }
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
            if let url = URL(string: "https://openlibrary.org\(key)/ratings.json"),
               let ratings = await fetch(url, as: OLRatings.self) {
                offerRating(&r, ratings.summary?.average, ratings.summary?.count, .openLibrary,
                            URL(string: "https://openlibrary.org\(key)"))
            }
        }
        let apple = await appleCandidates
        if let match = apple.first(where: { matches(r, $0) }) {
            fill(&r, from: match)
        }
        return r
    }

    /// Cherche le meilleur résultat pour un livre déjà enregistré (bouton « Vérifier la fiche »).
    /// `strict` : n'accepte qu'un résultat qui correspond vraiment (titre + auteur ou ISBN),
    /// pour compléter une fiche sans risque de la confondre avec un autre livre.
    static func bestMatch(title: String, authors: String, isbn: String?, strict: Bool = false) async -> BookResult? {
        let query = isbn ?? "\(title) \(authors.split(separator: ",").first ?? "")"
        let results = await search(query)
        let reference = BookResult(id: "ref", title: title,
                                   authors: authors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                   isbn: isbn, source: .google)
        let matched = results.first(where: { matches(reference, $0) })
        guard let best = matched ?? (strict ? nil : results.first) else { return nil }
        return await enrich(best)
    }

    static func downloadImage(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        return await loadCover(url, strict: false)?.data
    }

    // MARK: - Couvertures : on garde la plus grande

    struct CoverImage: Sendable {
        let data: Data
        let url: URL
        let pixels: Int
    }

    /// Toutes les adresses de couverture possibles pour un résultat, de la plus prometteuse à la moins bonne.
    static func coverCandidates(for r: BookResult) -> [URL] {
        var urls = r.coverCandidates
        if r.id.hasPrefix("g-") {
            let googleID = String(r.id.dropFirst(2))
            if let hd = URL(string: "https://books.google.com/books/publisher/content/images/frontcover/\(googleID)?fife=w1000-h1500&source=gbs_api") {
                urls.append(hd)
            }
        }
        if let cover = r.coverURL { urls.append(cover) }
        for isbn in ([r.isbn].compactMap { $0 } + r.allISBNs).prefix(3) {
            if let u = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false") { urls.append(u) }
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    /// Télécharge les candidates en parallèle et renvoie la plus grande image valide.
    static func bestCover(_ urls: [URL]) async -> CoverImage? {
        await withTaskGroup(of: CoverImage?.self) { group in
            for url in urls.prefix(8) {
                group.addTask { await loadCover(url, strict: true) }
            }
            var best: CoverImage?
            for await cover in group {
                if let cover, cover.pixels > (best?.pixels ?? 0) { best = cover }
            }
            return best
        }
    }

    private static func loadCover(_ url: URL, strict: Bool) async -> CoverImage? {
        guard let data = await fetchData(url), let image = UIImage(data: data) else { return nil }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width > 10, height > 10 else { return nil }
        if strict {
            // Écarte les vignettes minuscules et les images « pas de couverture » (souvent carrées ou grises).
            let ratio = height / width
            guard width >= 120, height >= 180, ratio > 1.05, ratio < 2.0 else { return nil }
        }
        let maxHeight: CGFloat = 1500
        var output = image
        if height > maxHeight {
            let scale = maxHeight / height
            let size = CGSize(width: (width * scale).rounded(), height: maxHeight)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let jpeg = output.jpegData(compressionQuality: 0.85) else { return nil }
        // Taille de l'image enregistrée (après réduction éventuelle), pour comparer avec la couverture actuelle.
        let stored = Int(output.size.width * output.scale * output.size.height * output.scale)
        return CoverImage(data: jpeg, url: url, pixels: stored)
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
            if result[i].openLibraryEditionKey == nil { result[i].openLibraryEditionKey = match.openLibraryEditionKey }
            offerRating(&result[i], match.averageRating, match.ratingsCount, .openLibrary, match.infoLink)
            if let cover = match.coverURL { result[i].coverCandidates.append(cover) }
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
        let aTitle = normalize(a.title)
        let bTitle = normalize(b.title)
        guard !aTitle.isEmpty, !bTitle.isEmpty else { return false }
        let aAuthor = normalize(a.authors.first ?? "")
        let bAuthor = normalize(b.authors.first ?? "")
        let sameAuthor = aAuthor == bAuthor
        if aTitle == bTitle {
            return sameAuthor || aAuthor.isEmpty || bAuthor.isEmpty
        }
        // Titre avec sous-titre (« La Psy » / « La Psy : roman ») : seulement si l'auteur est le même.
        let shorter = aTitle.count < bTitle.count ? aTitle : bTitle
        let longer = aTitle.count < bTitle.count ? bTitle : aTitle
        return sameAuthor && !aAuthor.isEmpty && shorter.count >= 4 && longer.hasPrefix(shorter)
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

    /// Remplace les entités HTML numériques (« &#xa0; », « &#233; ») par leur caractère.
    private static func decodeNumericEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let isHex = m.range(at: 1).length > 0
            let digits = ns.substring(with: m.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result += code == 0xA0 ? " " : String(Character(scalar))
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
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
        s = decodeNumericEntities(s)
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

private struct ABResponse: Decodable { let results: [ABItem] }
private struct ABItem: Decodable {
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let description: String?
    let artworkUrl100: String?
    let releaseDate: String?
    let genres: [String]?
    let averageUserRating: Double?
    let userRatingCount: Int?
    let trackViewUrl: String?
}
