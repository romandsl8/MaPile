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

@Generable
struct NextReadChoices {
    @Guide(description: "Trois livres différents de la liste, du plus adapté au moins adapté", .count(3))
    var picks: [NextReadSuggestion]
}

@Generable
struct DiscoveryIdea {
    @Guide(description: "Le titre exact du livre, tel qu'il est publié")
    var title: String
    @Guide(description: "Le prénom et le nom de l'auteur")
    var author: String
    @Guide(description: "Une phrase chaleureuse, en français, qui relie ce livre aux lectures du lecteur")
    var reason: String
}

@Generable
struct DiscoveryIdeas {
    @Guide(description: "Six livres différents, absents de la liste du lecteur", .count(6))
    var ideas: [DiscoveryIdea]
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

    /// Jusqu'à `count` suggestions différentes tirées de la PAL.
    static func suggest(from pile: [Book], mood: ReadingMood, length: ReadingLength, excluding: Set<UUID>, count: Int = 3) async -> [Suggestion] {
        let candidates = pile.filter { !excluding.contains($0.uuid) && length.accepts($0.pageCount) }
        let pool = candidates.isEmpty ? pile.filter { !excluding.contains($0.uuid) } : candidates
        guard !pool.isEmpty else { return [] }

        var picks: [Suggestion] = []
        if aiAvailable {
            picks = await suggestWithAI(pool: Array(pool.prefix(40)), mood: mood, length: length)
        }
        // Complète avec les règles simples si l'IA n'en a pas donné assez.
        var remaining = pool.filter { book in !picks.contains { $0.book.uuid == book.uuid } }
        while picks.count < count, let next = suggestWithRules(pool: remaining, mood: mood) {
            picks.append(next)
            remaining.removeAll { $0.uuid == next.book.uuid }
        }
        return Array(picks.prefix(count))
    }

    private static func suggestWithAI(pool: [Book], mood: ReadingMood, length: ReadingLength) async -> [Suggestion] {
        var list = ""
        for (index, book) in pool.enumerated() {
            let summary = book.summary.prefix(220).replacingOccurrences(of: "\n", with: " ")
            let pages = book.pageCount > 0 ? "\(book.pageCount) p." : "pages inconnues"
            list += "[\(index)] « \(book.title) » de \(book.displayAuthors) — \(book.categories) — \(pages) — \(summary)\n"
        }
        let instructions = """
        Tu es un libraire chaleureux qui conseille en français. Tu choisis TROIS livres différents dans la pile à lire \
        du lecteur, ceux qui correspondent le mieux à son envie du moment. Tu ne proposes jamais un livre absent de la liste.
        """
        let prompt = """
        Envie du lecteur : \(mood.label) ; longueur souhaitée : \(length.label).
        Voici sa pile à lire :
        \(list)
        Choisis les trois meilleurs livres et explique chaque choix en une ou deux phrases.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: NextReadChoices.self)
            var result: [Suggestion] = []
            for choice in response.content.picks where pool.indices.contains(choice.index) {
                let book = pool[choice.index]
                guard !result.contains(where: { $0.book.uuid == book.uuid }) else { continue }
                result.append(Suggestion(book: book, reason: choice.reason, byAI: true))
            }
            return result
        } catch {
            return []
        }
    }

    // MARK: - Découverte de nouveaux livres (hors bibliothèque)

    struct Discovery: Identifiable {
        let id = UUID()
        let result: BookResult
        let reason: String
        let byAI: Bool
    }

    static func key(title: String) -> String { BookSearchService.normalize(title) }

    /// Livres aimés (les mieux notés et les plus récents), puis la PAL : ce qui définit les goûts du lecteur.
    private static func tasteBooks(read: [Book], pile: [Book]) -> [Book] {
        let liked = read.sorted {
            if $0.myRating != $1.myRating { return $0.myRating > $1.myRating }
            return $0.finishedOn > $1.finishedOn
        }
        return Array(liked.prefix(20)) + Array(pile.prefix(10))
    }

    /// Propose des livres absents de la bibliothèque, vérifiés en ligne (titre, auteur, couverture).
    static func discover(read: [Book], pile: [Book], mood: ReadingMood, length: ReadingLength,
                         excluding shown: Set<String>) async -> [Discovery] {
        var known = shown
        for book in read + pile { known.insert(key(title: book.title)) }
        let taste = tasteBooks(read: read, pile: pile)
        var found: [Discovery] = []
        if aiAvailable, !taste.isEmpty {
            found = await discoverWithAI(taste: taste, mood: mood, length: length, known: known)
        }
        if found.count < 2 {
            for item in await discoverWithRules(read: read, pile: pile, mood: mood, length: length, known: known)
            where !found.contains(where: { key(title: $0.result.title) == key(title: item.result.title) }) {
                found.append(item)
            }
        }
        return found
    }

    private static func discoverWithAI(taste: [Book], mood: ReadingMood, length: ReadingLength, known: Set<String>) async -> [Discovery] {
        var list = ""
        for book in taste {
            let note = book.myRating > 0 ? " — ma note \(book.myRating)/5" : (book.status == .toRead ? " — dans ma PAL" : "")
            list += "« \(book.title) » de \(book.displayAuthors) (\(book.categories))\(note)\n"
        }
        let instructions = """
        Tu es un libraire passionné qui conseille en français. À partir des goûts du lecteur, tu proposes \
        des livres qui existent vraiment, connus et faciles à trouver, de préférence disponibles en français. \
        Tu ne proposes jamais un livre de la liste du lecteur.
        """
        let prompt = """
        Livres lus et aimés, ou en attente dans la pile à lire :
        \(list)
        Envie du moment : \(mood.label) ; longueur souhaitée : \(length.label).
        Propose six livres différents qui ne sont pas dans cette liste, avec leur titre exact, leur auteur \
        et une phrase chaleureuse qui explique le lien avec ses lectures.
        """
        let ideas: [DiscoveryIdea]
        do {
            let session = LanguageModelSession(instructions: instructions)
            ideas = try await session.respond(to: prompt, generating: DiscoveryIdeas.self).content.ideas
        } catch {
            return []
        }
        // Chaque idée est vérifiée en ligne : on ne garde que les livres réels, hors bibliothèque.
        return await withTaskGroup(of: (Int, Discovery?).self) { group in
            for (index, idea) in ideas.enumerated() {
                let title = idea.title
                let author = idea.author
                let reason = idea.reason
                group.addTask {
                    let results = await BookSearchService.search("\(title) \(author)")
                    guard let match = results.first(where: { verify($0, title: title, author: author) }) else {
                        return (index, nil)
                    }
                    return (index, Discovery(result: match, reason: reason, byAI: true))
                }
            }
            var ordered: [(Int, Discovery)] = []
            for await (index, item) in group {
                guard let item else { continue }
                let k = key(title: item.result.title)
                guard !known.contains(k), length.accepts(item.result.pageCount ?? 0),
                      !ordered.contains(where: { key(title: $0.1.result.title) == k }) else { continue }
                ordered.append((index, item))
            }
            return ordered.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Le résultat correspond-il bien au livre imaginé par l'IA (même titre, même auteur) ?
    nonisolated private static func verify(_ result: BookResult, title: String, author: String) -> Bool {
        let wanted = BookSearchService.normalize(title)
        let got = BookSearchService.normalize(result.title)
        guard wanted.count >= 3, !got.isEmpty else { return false }
        let titleOK = got == wanted || (wanted.count >= 5 && (got.hasPrefix(wanted) || wanted.hasPrefix(got) && got.count >= 5))
        guard titleOK else { return false }
        let surname = BookSearchService.normalize(author.split(separator: " ").last.map(String.init) ?? author)
        guard !surname.isEmpty else { return true }
        return result.authors.contains { BookSearchService.normalize($0).contains(surname) }
    }

    /// Sans IA : d'autres livres des auteurs préférés, puis les livres appréciés des genres lus.
    private static func discoverWithRules(read: [Book], pile: [Book], mood: ReadingMood, length: ReadingLength,
                                          known: Set<String>) async -> [Discovery] {
        var authorScore: [String: (name: String, score: Int, book: String)] = [:]
        for book in read + pile {
            let weight = book.status == .read ? max(book.myRating, 2) : 1
            for author in book.authorList {
                let k = BookSearchService.normalize(author)
                let current = authorScore[k] ?? (author, 0, book.title)
                authorScore[k] = (current.name, current.score + weight, current.book)
            }
        }
        let topAuthors = authorScore.values.sorted { $0.score > $1.score }.prefix(3)

        var genreCount: [String: (name: String, count: Int)] = [:]
        for book in read + pile {
            for genre in book.genreList {
                let k = BookSearchService.normalize(genre)
                genreCount[k] = (genre, (genreCount[k]?.count ?? 0) + 1)
            }
        }
        let moodGenre = genreCount.filter { entry in mood.keywords.contains { entry.key.contains($0) } }
            .max { $0.value.count < $1.value.count }?.value.name
        let topGenre = moodGenre ?? genreCount.values.max { $0.count < $1.count }?.name

        var found: [Discovery] = []
        var seen = known
        for author in topAuthors {
            let results = await BookSearchService.search(author.name)
            let key = BookSearchService.normalize(author.name)
            let candidates = results.filter { result in
                result.authors.contains { BookSearchService.normalize($0) == key }
                    && !seen.contains(Self.key(title: result.title))
                    && length.accepts(result.pageCount ?? 0)
            }
            if let pick = candidates.max(by: { ($0.ratingsCount ?? 0) < ($1.ratingsCount ?? 0) }) {
                seen.insert(Self.key(title: pick.title))
                found.append(Discovery(result: pick,
                                       reason: "Vous avez lu « \(author.book) » : voici un autre livre de \(author.name).",
                                       byAI: false))
            }
        }
        if let genre = topGenre {
            let results = await BookSearchService.search("subject:\(genre)")
            let candidates = results.filter { !seen.contains(Self.key(title: $0.title)) && length.accepts($0.pageCount ?? 0) }
                .sorted { ($0.ratingsCount ?? 0) > ($1.ratingsCount ?? 0) }
            for pick in candidates.prefix(3) {
                seen.insert(Self.key(title: pick.title))
                found.append(Discovery(result: pick,
                                       reason: "Un livre apprécié en « \(genre) », un genre que vous lisez souvent.",
                                       byAI: false))
            }
        }
        return found.shuffled()
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
