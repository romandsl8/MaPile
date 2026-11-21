import Foundation

/// Liens pour acheter un livre, en papier ou en numérique (ePub).
/// Tous les liens passent par ici : c'est le seul endroit à modifier pour ajouter
/// plus tard un identifiant d'affiliation (programme partenaire d'un libraire).
struct PurchaseLink: Identifiable {
    enum Format { case paper, ebook }

    let store: String
    let format: Format
    let url: URL
    var id: String { "\(store)-\(format)" }
}

enum PurchaseLinks {
    static func links(for book: Book) -> [PurchaseLink] {
        let author = book.authorList.first ?? ""
        let titleQuery = "\(book.title) \(author)".trimmingCharacters(in: .whitespaces)
        // En papier, l'ISBN désigne l'édition exacte ; sinon titre + auteur.
        let paperQuery = book.isbn ?? titleQuery
        var links: [PurchaseLink] = []

        func add(_ store: String, _ format: PurchaseLink.Format, _ base: String, _ items: [String: String]) {
            guard var c = URLComponents(string: base) else { return }
            c.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let url = c.url { links.append(PurchaseLink(store: store, format: format, url: url)) }
        }

        // Papier
        add("Librairies indépendantes", .paper, "https://www.leslibraires.fr/recherche/", ["q": paperQuery])
        add("Fnac", .paper, "https://www.fnac.com/SearchResult/ResultList.aspx", ["Search": paperQuery])
        add("Amazon", .paper, "https://www.amazon.fr/s", ["k": paperQuery, "i": "stripbooks"])

        // Numérique (ePub)
        if book.ratingSource == BookResult.Source.appleBooks.rawValue,
           let link = book.infoURL, link.host?.contains("apple.com") == true {
            links.append(PurchaseLink(store: "Apple Books", format: .ebook, url: link))
        }
        add("Kobo", .ebook, "https://www.kobo.com/fr/fr/search", ["query": titleQuery])
        add("Google Play Livres", .ebook, "https://play.google.com/store/search", ["q": titleQuery, "c": "books"])
        return links
    }
}
