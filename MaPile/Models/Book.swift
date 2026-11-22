import Foundation
import SwiftData

/// Où se trouve le livre : dans la pile à lire, en cours de lecture ou déjà lu.
enum ReadingStatus: String, CaseIterable, Identifiable, Codable {
    case toRead
    case reading
    case read

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toRead: "PAL"
        case .reading: "En cours"
        case .read: "Lus"
        }
    }

    var longTitle: String {
        switch self {
        case .toRead: "Pile à lire"
        case .reading: "En cours de lecture"
        case .read: "Livres lus"
        }
    }

    var systemImage: String {
        switch self {
        case .toRead: "books.vertical"
        case .reading: "book"
        case .read: "checkmark.seal"
        }
    }
}

/// Un livre de la bibliothèque. Toutes les propriétés ont une valeur par défaut
/// (et aucune contrainte d'unicité) pour rester compatible avec une future synchro iCloud.
@Model
final class Book {
    var uuid: UUID = UUID()
    var title: String = ""
    var authors: String = ""
    var summary: String = ""
    var coverURLString: String?
    @Attribute(.externalStorage) var coverData: Data?
    var isbn: String?
    var pageCount: Int = 0
    var publisher: String?
    var publishedDate: String?
    var categories: String = ""
    var language: String?
    var communityRating: Double?
    var communityRatingsCount: Int?
    var ratingSource: String?
    var infoLink: String?
    var openLibraryKey: String?
    var statusRaw: String = ReadingStatus.toRead.rawValue
    var myRating: Int = 0
    var myReview: String = ""
    var dateAdded: Date = Date()
    var dateFinished: Date?
    /// Dernière vérification en ligne (note, couverture) ; nil = jamais vérifié.
    var lastCheckedAt: Date?
    /// Identifiant Apple Books, pour afficher les avis des lecteurs.
    var appleBooksID: String?
    /// Date de publication de ma note/mon avis dans « Les avis MaPile » (nil = non partagé).
    var sharedReviewAt: Date?
    /// Lecture en cours : page atteinte et date de début.
    var currentPage: Int = 0
    var dateStarted: Date?
    /// Livre prêté : à qui et depuis quand (nil = pas prêté).
    var lentTo: String?
    var lentAt: Date?
    /// Série ou saga : nom et numéro du tome (0 = pas de série).
    var seriesName: String = ""
    var seriesIndex: Int = 0

    init(title: String, authors: String = "", status: ReadingStatus = .toRead) {
        self.title = title
        self.authors = authors
        self.statusRaw = status.rawValue
        if status == .read { self.dateFinished = Date() }
    }
}

extension Book {
    var status: ReadingStatus {
        get { ReadingStatus(rawValue: statusRaw) ?? .toRead }
        set { statusRaw = newValue.rawValue }
    }

    var coverURL: URL? { coverURLString.flatMap(URL.init(string:)) }

    var infoURL: URL? { infoLink.flatMap(URL.init(string:)) }

    var authorList: [String] {
        authors.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var genreList: [String] {
        categories.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Date utilisée pour les statistiques : date de fin, sinon date d'ajout.
    var finishedOn: Date { dateFinished ?? dateAdded }

    var displayAuthors: String { authors.isEmpty ? "Auteur inconnu" : authors }

    func markAsRead(on date: Date = .now) {
        status = .read
        dateFinished = date
        if pageCount > 0 { currentPage = pageCount }
    }

    func moveToPile() {
        status = .toRead
        dateFinished = nil
    }

    /// Passe le livre dans « En cours ».
    func startReading(on date: Date = .now) {
        status = .reading
        dateFinished = nil
        if dateStarted == nil || currentPage == 0 { dateStarted = date }
    }

    /// Progression de 0 à 1 (nil si le nombre de pages est inconnu).
    var progress: Double? {
        guard pageCount > 0 else { return nil }
        return min(max(Double(currentPage) / Double(pageCount), 0), 1)
    }

    /// Pages lues par jour depuis le début de la lecture (au moins un jour).
    var pagesPerDay: Double? {
        guard let start = dateStarted, currentPage > 0 else { return nil }
        let days = max(Date.now.timeIntervalSince(start) / 86_400, 1)
        return Double(currentPage) / days
    }

    /// Date de fin estimée au rythme actuel.
    var estimatedFinish: Date? {
        guard pageCount > currentPage, let pace = pagesPerDay, pace > 0 else { return nil }
        let remainingDays = Double(pageCount - currentPage) / pace
        return Date.now.addingTimeInterval(remainingDays * 86_400)
    }

    /// Recopie les infos trouvées en ligne. `onlyMissing` évite d'écraser ce que l'utilisateur a saisi.
    func apply(_ r: BookResult, onlyMissing: Bool) {
        if !onlyMissing || title.isEmpty { title = r.title }
        if (!onlyMissing || authors.isEmpty), !r.authors.isEmpty { authors = r.authors.joined(separator: ", ") }
        if (!onlyMissing || summary.isEmpty), !r.summary.isEmpty { summary = r.summary }
        if (!onlyMissing || coverURLString == nil), let url = r.coverURL { coverURLString = url.absoluteString }
        if (!onlyMissing || isbn == nil), let v = r.isbn { isbn = v }
        if (!onlyMissing || pageCount == 0), let v = r.pageCount, v > 0 { pageCount = v }
        if (!onlyMissing || publisher == nil), let v = r.publisher { publisher = v }
        if (!onlyMissing || publishedDate == nil), let v = r.publishedDate { publishedDate = v }
        if (!onlyMissing || categories.isEmpty), !r.categories.isEmpty { categories = r.categories.joined(separator: ", ") }
        if (!onlyMissing || language == nil), let v = r.language { language = v }
        if (!onlyMissing || infoLink == nil), let v = r.infoLink { infoLink = v.absoluteString }
        if let key = r.openLibraryKey { openLibraryKey = key }
        if let id = r.appleBooksID { appleBooksID = id }
        // La note des lecteurs est toujours mise à jour : elle évolue avec le temps.
        if let rating = r.averageRating {
            communityRating = rating
            communityRatingsCount = r.ratingsCount
            ratingSource = (r.ratingSource ?? r.source).rawValue
            // « Avis en ligne » ouvre la page qui contient ces avis (ex. Apple Books).
            if r.ratingSource == .appleBooks, let link = r.infoLink { infoLink = link.absoluteString }
        }
    }

    convenience init(result: BookResult, status: ReadingStatus) {
        self.init(title: result.title, status: status)
        apply(result, onlyMissing: false)
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case added, finished, title, author, rating, community

    var id: String { rawValue }

    var label: String {
        switch self {
        case .added: "Date d'ajout"
        case .finished: "Date de lecture"
        case .title: "Titre"
        case .author: "Auteur"
        case .rating: "Ma note"
        case .community: "Note des lecteurs"
        }
    }

    func sorted(_ books: [Book]) -> [Book] {
        switch self {
        case .added: books.sorted { $0.dateAdded > $1.dateAdded }
        case .finished: books.sorted { $0.finishedOn > $1.finishedOn }
        case .title: books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author: books.sorted { $0.authors.localizedStandardCompare($1.authors) == .orderedAscending }
        case .rating: books.sorted { $0.myRating > $1.myRating }
        case .community: books.sorted(by: Self.byCommunityRating)
        }
    }
}

extension LibrarySort {
    /// Meilleure note des lecteurs d'abord ; à note égale, celle qui a le plus d'avis. Les livres sans note à la fin.
    static func byCommunityRating(_ a: Book, _ b: Book) -> Bool {
        let ra: Double = a.communityRating ?? -1
        let rb: Double = b.communityRating ?? -1
        if ra != rb { return ra > rb }
        let ca: Int = a.communityRatingsCount ?? 0
        let cb: Int = b.communityRatingsCount ?? 0
        return ca > cb
    }
}
