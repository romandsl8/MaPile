import Foundation

/// Contenu d'une pile partagée : nom, émoji, couleur et livres (titre, auteur, ISBN).
/// Tout est contenu dans le lien lui-même (après le « # »), rien n'est stocké sur un serveur.
struct ShelfPayload: Codable, Hashable {
    var n: String            // nom
    var e: String            // émoji
    var c: Int               // couleur
    var b: [[String]]        // livres : [titre, auteur, isbn]

    struct Entry: Hashable {
        let title: String
        let author: String
        let isbn: String
    }

    var entries: [Entry] {
        b.map { Entry(title: $0.first ?? "", author: $0.count > 1 ? $0[1] : "", isbn: $0.count > 2 ? $0[2] : "") }
    }
}

enum ShelfSharing {
    static let webPage = "https://romandsl8.github.io/mapile-site/pile.html"
    static let maxBooks = 120

    static func payload(name: String, emoji: String, colorIndex: Int, books: [Book]) -> ShelfPayload {
        let list = books.prefix(maxBooks).map { [$0.title, $0.authorList.first ?? "", $0.isbn ?? ""] }
        return ShelfPayload(n: name, e: emoji, c: colorIndex, b: Array(list))
    }

    static func code(for payload: ShelfPayload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Lien web lisible par tout le monde (avec bouton « Ouvrir dans MaPile »).
    static func webURL(for payload: ShelfPayload) -> URL? {
        guard let code = code(for: payload) else { return nil }
        return URL(string: "\(webPage)#p=\(code)")
    }

    /// Lit un lien de pile : « mapile://pile#p=… » ou « https://…/pile.html#p=… ».
    static func decode(_ url: URL) -> ShelfPayload? {
        guard let fragment = url.fragment, fragment.hasPrefix("p=") else { return nil }
        var base64 = String(fragment.dropFirst(2))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(ShelfPayload.self, from: data)
    }
}
