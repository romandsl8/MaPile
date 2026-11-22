import Foundation

/// Un tome d'une saga.
struct SeriesVolume: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let order: Double?
    let year: Int?
}

/// Une saga et ses tomes, dans l'ordre de lecture.
struct SeriesInfo: Sendable {
    let name: String
    let volumes: [SeriesVolume]
    /// Identifiant Wikidata du livre consulté.
    let currentID: String

    /// Position du livre dans la saga (1 = premier tome).
    var position: Int? {
        volumes.firstIndex { $0.id == currentID }.map { $0 + 1 }
    }
}

/// Retrouve la saga d'un livre et l'ordre de ses tomes grâce à Wikidata (base libre et gratuite).
enum SeriesService {
    private static let userAgent = "MaPile/1.1 (iOS reading tracker)"
    @MainActor private static var cache: [String: SeriesInfo?] = [:]

    @MainActor
    static func lookup(title: String, author: String) async -> SeriesInfo? {
        let key = BookSearchService.normalize(title) + "|" + BookSearchService.normalize(author)
        if let cached = cache[key] { return cached }
        let info = await fetch(title: title, author: author)
        cache[key] = info
        return info
    }

    private static func fetch(title: String, author: String) async -> SeriesInfo? {
        // Titre sans sous-titre (« Dune : tome 1 » → « Dune »).
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: ":(")).first?
            .trimmingCharacters(in: .whitespaces) ?? title
        var ids = await searchEntities(cleaned, language: "fr")
        if ids.isEmpty { ids = await searchEntities(cleaned, language: "en") }
        guard !ids.isEmpty else { return nil }
        return await seriesQuery(candidates: ids, author: author)
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func searchEntities(_ text: String, language: String) async -> [String] {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbsearchentities"),
            URLQueryItem(name: "search", value: text),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "uselang", value: language),
            URLQueryItem(name: "type", value: "item"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(for: request(url)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["search"] as? [[String: Any]] else { return [] }
        return results.compactMap { $0["id"] as? String }.filter { $0.hasPrefix("Q") }
    }

    private static func seriesQuery(candidates: [String], author: String) async -> SeriesInfo? {
        let values = candidates.map { "wd:\($0)" }.joined(separator: " ")
        let sparql = """
        SELECT ?book ?authorLabel ?series ?seriesLabel ?item ?itemLabel ?ord ?date WHERE {
          VALUES ?book { \(values) }
          ?book wdt:P179 ?series .
          ?book wdt:P50 ?author .
          ?item p:P179 ?st . ?st ps:P179 ?series .
          OPTIONAL { ?st pq:P1545 ?ord . }
          OPTIONAL { ?item wdt:P577 ?date . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "fr,en". }
        } LIMIT 600
        """
        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [URLQueryItem(name: "query", value: sparql), URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { return nil }
        var req = request(url)
        req.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let bindings = results["bindings"] as? [[String: Any]] else { return nil }

        func value(_ row: [String: Any], _ name: String) -> String? {
            (row[name] as? [String: Any])?["value"] as? String
        }
        func qid(_ uri: String?) -> String? { uri?.components(separatedBy: "/").last }

        // Le livre retenu : le premier candidat dont l'auteur correspond.
        let surname = BookSearchService.normalize(author.split(separator: " ").last.map(String.init) ?? "")
        var chosen: (book: String, series: String)?
        for candidate in candidates {
            let rows = bindings.filter { qid(value($0, "book")) == candidate }
            guard let first = rows.first, let series = qid(value(first, "series")) else { continue }
            let authors = Set(rows.compactMap { value($0, "authorLabel") }.map(BookSearchService.normalize))
            if surname.isEmpty || authors.contains(where: { $0.contains(surname) }) {
                chosen = (candidate, series)
                break
            }
        }
        guard let chosen else { return nil }

        let rows = bindings.filter { qid(value($0, "book")) == chosen.book && qid(value($0, "series")) == chosen.series }
        guard let seriesName = rows.first.flatMap({ value($0, "seriesLabel") }) else { return nil }

        var volumes: [String: SeriesVolume] = [:]
        for row in rows {
            guard let id = qid(value(row, "item")), let label = value(row, "itemLabel") else { continue }
            // Sans libellé, Wikidata renvoie l'identifiant (« Q12345 ») : on l'ignore.
            if label.first == "Q", label.dropFirst().allSatisfy(\.isNumber) { continue }
            let order = value(row, "ord").flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            let year = value(row, "date").flatMap { Int($0.prefix(4)) }
            if let existing = volumes[id] {
                let earliest = [existing.year, year].compactMap { $0 }.min()
                volumes[id] = SeriesVolume(id: id, title: existing.title, order: existing.order ?? order, year: earliest)
            } else {
                volumes[id] = SeriesVolume(id: id, title: label, order: order, year: year)
            }
        }
        var list = Array(volumes.values)
        let numbered = list.filter { $0.order != nil }
        if numbered.count >= 2 {
            // Les éléments sans numéro (coffrets, hors-séries) sont écartés quand la saga est numérotée.
            list = numbered.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        } else {
            list.sort { ($0.year ?? 9999, $0.title) < ($1.year ?? 9999, $1.title) }
        }
        guard list.count >= 2 else { return nil }
        if !list.contains(where: { $0.id == chosen.book }) {
            list.append(SeriesVolume(id: chosen.book, title: "", order: nil, year: nil))
        }
        return SeriesInfo(name: seriesName, volumes: list.filter { !$0.title.isEmpty || $0.id == chosen.book }, currentID: chosen.book)
    }
}
