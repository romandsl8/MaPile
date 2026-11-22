import Foundation
import FoundationModels

/// Humeur choisie par l'utilisateur pour « Que lire ensuite ? ».
enum ReadingMood: String, CaseIterable, Identifiable {
    case light, intense, escape, learn, thrill, moving

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "😌 Léger"
        case .intense: "🔥 Intense"
        case .escape: "🌍 Évasion"
        case .learn: "🧠 Apprendre"
        case .thrill: "🕵️ Frissons"
        case .moving: "💧 Émouvant"
        }
    }

    /// Mots-clés de genres utilisés si l'IA n'est pas disponible.
    var keywords: [String] {
        switch self {
        case .light: ["humour", "comedie", "romance", "feelgood", "jeunesse", "comics", "bd"]
        case .intense: ["drame", "litterature", "roman", "classique", "fiction"]
        case .escape: ["fantasy", "fantastique", "sciencefiction", "aventure", "voyage"]
        case .learn: ["essai", "histoire", "science", "biographie", "documentaire", "philosophie", "nonfiction"]
        case .thrill: ["thriller", "policier", "polar", "suspense", "horreur", "crime", "mystery"]
        case .moving: ["drame", "romance", "biographie", "temoignage", "poesie"]
        }
    }
}

/// Durée de lecture souhaitée.
enum ReadingLength: String, CaseIterable, Identifiable {
    case short, medium, long, any

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short: "Court"
        case .medium: "Moyen"
        case .long: "Long"
        case .any: "Peu importe"
        }
    }

    func accepts(_ pages: Int) -> Bool {
        guard pages > 0 else { return true }
        switch self {
        case .short: return pages <= 250
        case .medium: return pages > 200 && pages <= 450
        case .long: return pages > 400
        case .any: return true
        }
    }
}

@Generable
struct NextReadSuggestion {
    @Guide(description: "Le numéro du livre choisi dans la liste, tel qu'indiqué entre crochets")
    var index: Int
    @Guide(description: "Une ou deux phrases chaleureuses, en français, qui expliquent pourquoi ce livre correspond à l'envie du lecteur")
    var reason: String
}

/// Suggère le prochain livre à lire parmi la PAL : IA d'Apple sur l'iPhone si disponible, sinon règles simples.
@MainActor
enum NextReadAdvisor {
    struct Suggestion {
        let book: Book
        let reason: String
        let byAI: Bool
    }

    static var aiAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func suggest(from pile: [Book], mood: ReadingMood, length: ReadingLength, excluding: Set<UUID>) async -> Suggestion? {
        let candidates = pile.filter { !excluding.contains($0.uuid) && length.accepts($0.pageCount) }
        let pool = candidates.isEmpty ? pile.filter { !excluding.contains($0.uuid) } : candidates
        guard !pool.isEmpty else { return nil }

        if aiAvailable, let ai = await suggestWithAI(pool: Array(pool.prefix(40)), mood: mood, length: length) {
            return ai
        }
        return suggestWithRules(pool: pool, mood: mood)
    }

    private static func suggestWithAI(pool: [Book], mood: ReadingMood, length: ReadingLength) async -> Suggestion? {
        var list = ""
        for (index, book) in pool.enumerated() {
            let summary = book.summary.prefix(220).replacingOccurrences(of: "\n", with: " ")
            let pages = book.pageCount > 0 ? "\(book.pageCount) p." : "pages inconnues"
            list += "[\(index)] « \(book.title) » de \(book.displayAuthors) — \(book.categories) — \(pages) — \(summary)\n"
        }
        let instructions = """
        Tu es un libraire chaleureux qui conseille en français. Tu choisis UN seul livre dans la pile à lire \
        du lecteur, celui qui correspond le mieux à son envie du moment. Tu ne proposes jamais un livre absent de la liste.
        """
        let prompt = """
        Envie du lecteur : \(mood.label) ; longueur souhaitée : \(length.label).
        Voici sa pile à lire :
        \(list)
        Choisis le meilleur livre et explique pourquoi en une ou deux phrases.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: NextReadSuggestion.self)
            let choice = response.content
            guard pool.indices.contains(choice.index) else { return nil }
            return Suggestion(book: pool[choice.index], reason: choice.reason, byAI: true)
        } catch {
            return nil
        }
    }

    private static func suggestWithRules(pool: [Book], mood: ReadingMood) -> Suggestion? {
        func score(_ book: Book) -> Double {
            let genres = book.genreList.map(BookSearchService.normalize).joined(separator: " ")
            let match = mood.keywords.contains { genres.contains($0) } ? 2.0 : 0
            return match + (book.communityRating ?? 3) / 2 + Double.random(in: 0...0.8)
        }
        guard let best = pool.max(by: { score($0) < score($1) }) else { return nil }
        var reason = "Un bon choix dans votre PAL pour une envie « \(mood.label) »."
        if let rating = best.communityRating {
            reason += " Les lecteurs lui donnent \(rating.frenchDecimal)/5."
        }
        return Suggestion(book: best, reason: reason, byAI: false)
    }
}
