import AppIntents
import SwiftData

// Actions disponibles avec Siri, Spotlight et l'app Raccourcis.

/// « Dis Siri, mettre à jour ma page dans MaPile » → « À quelle page en êtes-vous ? »
struct UpdatePageIntent: AppIntent {
    static let title: LocalizedStringResource = "Indiquer ma page"
    static let description = IntentDescription("Enregistre la page atteinte dans le livre en cours de lecture.")

    @Parameter(title: "Page", requestValueDialog: "À quelle page en êtes-vous ?")
    var page: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Je suis à la page \(\.$page)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = MaPileStore.container.mainContext
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.statusRaw == "reading" })
        guard let book = try context.fetch(descriptor).first else {
            return .result(dialog: "Vous n'avez pas de livre en cours dans MaPile.")
        }
        let value = max(page, 0)
        book.currentPage = book.pageCount > 0 ? min(value, book.pageCount) : value
        if book.dateStarted == nil { book.dateStarted = .now }
        try? context.save()
        if let progress = book.progress {
            let percent = Int((progress * 100).rounded())
            return .result(dialog: "C'est noté : page \(book.currentPage) de « \(book.title) », soit \(percent) %.")
        }
        return .result(dialog: "C'est noté : page \(book.currentPage) de « \(book.title) ».")
    }
}

/// « Dis Siri, où en suis-je dans MaPile ? »
struct ReadingProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Où en suis-je ?"
    static let description = IntentDescription("Donne la progression du livre en cours et votre série de lecture.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = MaPileStore.container.mainContext
        let reading = try context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.statusRaw == "reading" }))
        let finished = try context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.statusRaw == "read" }))
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        let streak = ReadingStreak.current(days: ReadingStreak.readingDays(sessions: sessions, finished: finished))
        let streakText = streak > 1 ? " Vous lisez depuis \(streak) jours d'affilée !" : ""
        guard let book = reading.first else {
            return .result(dialog: "Aucun livre en cours. Choisissez-en un dans votre PAL !\(streakText)")
        }
        if let progress = book.progress {
            let percent = Int((progress * 100).rounded())
            let remaining = max(book.pageCount - book.currentPage, 0)
            return .result(dialog: "Vous êtes à la page \(book.currentPage) de « \(book.title) » (\(percent) %), encore \(remaining) pages.\(streakText)")
        }
        return .result(dialog: "Vous lisez « \(book.title) », page \(book.currentPage).\(streakText)")
    }
}

/// « Dis Siri, ajouter un livre à ma PAL dans MaPile » → « Quel livre ? »
struct AddToPileIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter un livre à ma PAL"
    static let description = IntentDescription("Cherche un livre par son titre (et son auteur) et l'ajoute à votre pile à lire.")

    @Parameter(title: "Livre", requestValueDialog: "Quel livre voulez-vous ajouter ?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ajouter \(\.$query) à ma PAL")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let results = await BookSearchService.search(query)
        guard let first = results.first else {
            return .result(dialog: "Je n'ai trouvé aucun livre pour « \(query) ».")
        }
        let full = await BookSearchService.enrich(first)
        let context = MaPileStore.container.mainContext
        let book = Book(result: full, status: .toRead)
        if let best = await BookSearchService.bestCover(BookSearchService.coverCandidates(for: full)) {
            book.coverData = best.data
            book.coverURLString = best.url.absoluteString
        }
        book.lastCheckedAt = .now
        context.insert(book)
        try? context.save()
        let author = full.authors.first.map { " de \($0)" } ?? ""
        return .result(dialog: "« \(full.title) »\(author) a été ajouté à votre PAL.")
    }
}

/// « Dis Siri, je commence à lire dans MaPile » : lance le chrono sur le livre en cours.
struct StartReadingSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Lancer une séance de lecture"
    static let description = IntentDescription("Démarre le chrono de lecture sur le livre en cours.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = MaPileStore.container.mainContext
        guard let book = try context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.statusRaw == "reading" })).first else {
            return .result(dialog: "Vous n'avez pas de livre en cours dans MaPile.")
        }
        ActiveSession.begin(for: book)
        WidgetBridge.startActivity(for: book)
        return .result(dialog: "Bonne lecture ! Le chrono est lancé pour « \(book.title) ».")
    }
}

struct MaPileShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: UpdatePageIntent(),
                    phrases: ["Mettre à jour ma page dans \(.applicationName)",
                              "Indiquer ma page dans \(.applicationName)"],
                    shortTitle: "Indiquer ma page",
                    systemImageName: "book")
        AppShortcut(intent: ReadingProgressIntent(),
                    phrases: ["Où en suis-je dans \(.applicationName)",
                              "Ma progression dans \(.applicationName)"],
                    shortTitle: "Où en suis-je ?",
                    systemImageName: "chart.bar")
        AppShortcut(intent: AddToPileIntent(),
                    phrases: ["Ajouter un livre à ma PAL dans \(.applicationName)",
                              "Ajouter un livre dans \(.applicationName)"],
                    shortTitle: "Ajouter à ma PAL",
                    systemImageName: "books.vertical")
        AppShortcut(intent: StartReadingSessionIntent(),
                    phrases: ["Je commence à lire dans \(.applicationName)",
                              "Lancer une séance de lecture dans \(.applicationName)"],
                    shortTitle: "Lancer la lecture",
                    systemImageName: "timer")
    }
}
