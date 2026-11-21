import Foundation
import CloudKit
import CryptoKit

/// « Les avis MaPile » : notes et avis publiés anonymement par les utilisateurs de l'app,
/// stockés dans la base publique iCloud (CloudKit) de MaPile.
/// Rien n'est publié sans action explicite de l'utilisateur.
@MainActor
enum CommunityService {
    static let containerID = "iCloud.com.romandsl8.mapile"
    static let reviewType = "Review"
    static let reportType = "Report"
    static let maxLength = 1000

    struct Review: Identifiable, Hashable {
        let id: String          // nom de l'enregistrement
        let rating: Int
        let text: String
        let date: Date
        let authorKey: String   // identifiant anonyme de l'auteur (sert à masquer un utilisateur)
        let isMine: Bool
    }

    enum CommunityError: LocalizedError {
        case notSignedIn
        case rejected(String)
        case unavailable

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                "Connectez-vous à iCloud dans Réglages pour partager votre avis."
            case .rejected(let reason):
                reason
            case .unavailable:
                "Les avis MaPile sont momentanément indisponibles. Réessayez plus tard."
            }
        }
    }

    private static var container: CKContainer { CKContainer(identifier: containerID) }
    private static var database: CKDatabase { container.publicCloudDatabase }
    private static var cachedUserKey: String?

    // MARK: - Identité du livre

    /// Clé commune à tous les utilisateurs pour un même livre : titre + premier auteur, normalisés.
    static func bookKey(for book: Book) -> String {
        let title = BookSearchService.normalize(book.title)
        let author = BookSearchService.normalize(book.authorList.first ?? "")
        return "\(title)|\(author)"
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Identifiant anonyme de l'utilisateur iCloud pour cette app (jamais affiché).
    private static func userKey() async throws -> String {
        if let cachedUserKey { return cachedUserKey }
        guard try await container.accountStatus() == .available else { throw CommunityError.notSignedIn }
        let id = try await container.userRecordID().recordName
        cachedUserKey = id
        return id
    }

    private static func myRecordID(for book: Book, userKey: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "rev-\(hash(bookKey(for: book)))-\(hash(userKey))")
    }

    // MARK: - Lecture

    static func reviews(for book: Book) async throws -> [Review] {
        let me = try? await userKey()
        let hidden = HiddenAuthors.all
        let query = CKQuery(recordType: reviewType, predicate: NSPredicate(format: "bookKey == %@", bookKey(for: book)))
        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 200)
            let reviews = results.compactMap { _, result -> Review? in
                guard let record = try? result.get(),
                      let rating = record["rating"] as? Int64 else { return nil }
                let authorKey = record.creatorUserRecordID?.recordName ?? ""
                let isMine = me != nil && (authorKey == me || authorKey == CKCurrentUserDefaultName)
                if !isMine, hidden.contains(authorKey) { return nil }
                return Review(id: record.recordID.recordName,
                              rating: Int(rating),
                              text: (record["text"] as? String) ?? "",
                              date: (record["createdAt"] as? Date) ?? record.creationDate ?? .now,
                              authorKey: authorKey,
                              isMine: isMine)
            }
            return reviews.sorted { a, b in
                if a.isMine != b.isMine { return a.isMine }
                return a.date > b.date
            }
        } catch let error as CKError where error.code == .unknownItem || error.code == .invalidArguments {
            return [] // aucun avis encore publié (type d'enregistrement pas encore créé)
        } catch {
            throw CommunityError.unavailable
        }
    }

    // MARK: - Publication

    /// Publie (ou met à jour) ma note et mon avis pour ce livre.
    static func publish(book: Book) async throws {
        guard book.myRating > 0 else { throw CommunityError.rejected("Donnez d'abord une note (étoiles) au livre.") }
        let text = book.myReview.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = ContentFilter.problem(in: text) { throw CommunityError.rejected(problem) }
        let me = try await userKey()
        let record = CKRecord(recordType: reviewType, recordID: myRecordID(for: book, userKey: me))
        record["bookKey"] = bookKey(for: book) as CKRecordValue
        record["bookTitle"] = book.title as CKRecordValue
        record["bookAuthor"] = (book.authorList.first ?? "") as CKRecordValue
        record["rating"] = Int64(book.myRating) as CKRecordValue
        record["text"] = String(text.prefix(maxLength)) as CKRecordValue
        record["createdAt"] = Date.now as CKRecordValue
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            book.sharedReviewAt = .now
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CommunityError.notSignedIn
        } catch {
            throw CommunityError.unavailable
        }
    }

    /// Retire ma note et mon avis de « Les avis MaPile ».
    static func unpublish(book: Book) async throws {
        let me = try await userKey()
        do {
            _ = try await database.modifyRecords(saving: [], deleting: [myRecordID(for: book, userKey: me)])
        } catch let error as CKError where error.code == .unknownItem {
            // déjà supprimé
        } catch {
            throw CommunityError.unavailable
        }
        book.sharedReviewAt = nil
    }

    // MARK: - Modération

    /// Signale un avis : il est enregistré pour être examiné par l'éditeur de l'app.
    static func report(_ review: Review, reason: String) async throws {
        _ = try await userKey()
        let record = CKRecord(recordType: reportType)
        record["reviewID"] = review.id as CKRecordValue
        record["reason"] = reason as CKRecordValue
        record["createdAt"] = Date.now as CKRecordValue
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [])
        } catch {
            throw CommunityError.unavailable
        }
    }
}

/// Utilisateurs masqués par l'utilisateur de cet iPhone.
enum HiddenAuthors {
    private static let key = "hiddenCommunityAuthors"

    static var all: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func hide(_ authorKey: String) {
        guard !authorKey.isEmpty else { return }
        var set = all
        set.insert(authorKey)
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}

/// Filtre simple avant publication : insultes, liens, coordonnées.
enum ContentFilter {
    /// Mots entiers interdits (comparés mot à mot, pour ne pas bloquer « dispute » ou « en retard »).
    private static let bannedWords: Set<String> = [
        "connard", "connards", "connasse", "salope", "salopes", "encule", "encules", "enculer",
        "ntm", "fdp", "pute", "putes", "batard", "batards", "tapette", "bougnoul", "youpin",
        "fuck", "fucking", "bitch", "cunt", "asshole",
    ]
    private static let bannedPhrases = ["nique ta", "fils de pute", "ta gueule"]

    static func problem(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = Set(folded.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
        if !words.isDisjoint(with: bannedWords) || bannedPhrases.contains(where: { folded.contains($0) }) {
            return "Votre avis contient des mots qui ne respectent pas les règles de la communauté. Modifiez-le avant de le partager."
        }
        if folded.contains("http") || folded.contains("www.") || folded.contains("@") {
            return "Les liens et adresses e-mail ne sont pas autorisés dans les avis partagés."
        }
        return nil
    }
}
