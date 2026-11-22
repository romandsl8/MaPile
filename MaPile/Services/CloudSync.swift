import Foundation
import CloudKit
import SwiftData
import CryptoKit

/// Synchronisation de la bibliothèque dans l'iCloud privé de l'utilisateur (CKSyncEngine).
///
/// Chaque livre, pile, séance et citation devient un enregistrement « Item » dans la zone
/// « MaPile » de la base privée : `kind` (type), `payload` (JSON) et `cover` (couverture).
/// Les modifications locales sont repérées par une empreinte : ce qui a changé depuis la
/// dernière synchro est envoyé, ce qui a disparu est supprimé. En cas de conflit, la version
/// de l'appareil l'emporte. Les données locales ne sont jamais effacées par un changement de compte.
@MainActor
final class CloudSync: CKSyncEngineDelegate {
    static let shared = CloudSync()
    static let enabledKey = "iCloudSyncEnabled"
    static let lastSyncKey = "iCloudLastSync"
    static let errorKey = "iCloudSyncError"

    private let container = CKContainer(identifier: "iCloud.com.romandsl8.mapile")
    private let zoneID = CKRecordZone.ID(zoneName: "MaPile", ownerName: CKCurrentUserDefaultName)
    private var engine: CKSyncEngine?
    /// recordName → empreinte du dernier état connu des deux côtés.
    private var index: [String: String] = [:]
    /// recordName → champs système du dernier enregistrement serveur (évite les conflits).
    private var systemFields: [String: Data] = [:]
    /// Empreintes des enregistrements en cours d'envoi.
    private var sending: [String: String] = [:]
    private var saveObserver: NSObjectProtocol?
    private var debounce: Task<Void, Never>?

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    private var context: ModelContext { MaPileStore.container.mainContext }

    // MARK: - Démarrage et arrêt

    func start() {
        guard Self.isEnabled, engine == nil,
              !ProcessInfo.processInfo.arguments.contains("-demoData") else { return }
        loadFiles()
        let state = loadState()
        var config = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                stateSerialization: state,
                                                delegate: self)
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.engine = engine
        if state == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleQueue() }
        }
        Task { await checkAccount() }
        syncNow()
    }

    func stop() {
        engine = nil
        debounce?.cancel()
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
    }

    /// Récupère les nouveautés d'iCloud puis envoie les modifications de l'appareil.
    func syncNow() {
        guard let engine else { return }
        queueLocalChanges()
        Task {
            do {
                try await engine.fetchChanges()
                queueLocalChanges()
                try await engine.sendChanges()
                markSynced()
            } catch {
                report(error)
            }
        }
    }

    private func scheduleQueue() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            queueLocalChanges()
        }
    }

    private func checkAccount() async {
        do {
            let status = try await container.accountStatus()
            if status != .available {
                UserDefaults.standard.set("Connectez-vous à iCloud (Réglages de l'iPhone › votre nom) et activez iCloud Drive.", forKey: Self.errorKey)
            }
        } catch {
            report(error)
        }
    }

    private func markSynced() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.lastSyncKey)
        UserDefaults.standard.removeObject(forKey: Self.errorKey)
    }

    private func report(_ error: Error) {
        let message: String
        switch (error as? CKError)?.code {
        case .notAuthenticated: message = "Connectez-vous à iCloud (Réglages de l'iPhone › votre nom)."
        case .quotaExceeded: message = "Votre espace iCloud est plein."
        case .networkUnavailable, .networkFailure: message = "Pas de connexion internet. La synchro reprendra toute seule."
        default: message = error.localizedDescription
        }
        UserDefaults.standard.set(message, forKey: Self.errorKey)
    }

    // MARK: - Modifications locales

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    private func queueLocalChanges() {
        guard let engine else { return }
        let hashes = localHashes()
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for (name, hash) in hashes where index[name] != hash {
            changes.append(.saveRecord(recordID(name)))
        }
        for name in index.keys where hashes[name] == nil {
            changes.append(.deleteRecord(recordID(name)))
        }
        let pending = Set(engine.state.pendingRecordZoneChanges)
        let fresh = changes.filter { !pending.contains($0) }
        if !fresh.isEmpty { engine.state.add(pendingRecordZoneChanges: fresh) }
    }

    private func localHashes() -> [String: String] {
        var result: [String: String] = [:]
        for item in allItems() { result[item.name] = item.hash }
        return result
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                queueLocalChanges()
            case .signOut, .switchAccounts:
                resetSyncData()
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                // Données iCloud effacées : on garde la bibliothèque locale et on la renverra.
                index = [:]
                systemFields = [:]
                saveFiles()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                queueLocalChanges()
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                apply(modification.record)
            }
            for deletion in changes.deletions {
                applyDeletion(deletion.recordID.recordName)
            }
            try? context.save()
            saveFiles()
            markSynced()

        case .sentDatabaseChanges(let sent):
            if sent.failedZoneSaves.contains(where: { $0.zone.zoneID == zoneID }) {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            }

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                let name = record.recordID.recordName
                systemFields[name] = encode(record)
                index[name] = sending.removeValue(forKey: name) ?? index[name]
            }
            for id in sent.deletedRecordIDs {
                index.removeValue(forKey: id.recordName)
                systemFields.removeValue(forKey: id.recordName)
            }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            for failure in sent.failedRecordSaves {
                let name = failure.record.recordID.recordName
                sending.removeValue(forKey: name)
                switch failure.error.code {
                case .serverRecordChanged:
                    // Conflit : la version de cet appareil l'emporte.
                    if let server = failure.error.serverRecord { systemFields[name] = encode(server) }
                    retry.append(.saveRecord(failure.record.recordID))
                case .zoneNotFound:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    systemFields.removeValue(forKey: name)
                    retry.append(.saveRecord(failure.record.recordID))
                case .unknownItem:
                    systemFields.removeValue(forKey: name)
                    retry.append(.saveRecord(failure.record.recordID))
                case .quotaExceeded:
                    report(failure.error)
                default:
                    break
                }
            }
            for (id, _) in sent.failedRecordDeletes {
                index.removeValue(forKey: id.recordName)
                systemFields.removeValue(forKey: id.recordName)
            }
            if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }
            saveFiles()
            if sent.failedRecordSaves.isEmpty { markSynced() }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] id in
            await self?.record(for: id)
        }
    }

    // MARK: - Enregistrements

    private func record(for id: CKRecord.ID) -> CKRecord? {
        let name = id.recordName
        guard let item = item(named: name) else { return nil }
        var record = CKRecord(recordType: "Item", recordID: id)
        if let data = systemFields[name], let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            if let existing = CKRecord(coder: coder) { record = existing }
            coder.finishDecoding()
        }
        record["kind"] = item.kind as CKRecordValue
        record["payload"] = item.payload as CKRecordValue
        if let cover = item.cover {
            let url = Self.assetsDirectory.appendingPathComponent(name + ".jpg")
            try? cover.write(to: url)
            record["cover"] = CKAsset(fileURL: url)
        } else {
            record["cover"] = nil
        }
        sending[name] = item.hash
        return record
    }

    private func encode(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private func apply(_ record: CKRecord) {
        let name = record.recordID.recordName
        systemFields[name] = encode(record)
        let local = item(named: name)?.hash
        if let known = index[name] {
            // Modifié (ou supprimé) sur cet appareil depuis la dernière synchro : la version locale l'emporte.
            if local != known { return }
        } else if local != nil, sending[name] != nil {
            return
        }
        guard let kind = record["kind"] as? String, let payload = record["payload"] as? Data else { return }
        var cover: Data?
        if let asset = record["cover"] as? CKAsset, let url = asset.fileURL {
            cover = try? Data(contentsOf: url)
        }
        let decoder = JSONDecoder()
        switch kind {
        case "book":
            guard let dto = try? decoder.decode(BookRecord.self, from: payload) else { return }
            let book = fetchBook(dto.uuid) ?? {
                let created = Book(title: dto.title)
                created.uuid = dto.uuid
                context.insert(created)
                return created
            }()
            dto.apply(to: book)
            if book.coverData != cover { book.coverData = cover }
        case "shelf":
            guard let dto = try? decoder.decode(ShelfRecord.self, from: payload) else { return }
            let shelf = fetchShelf(dto.uuid) ?? {
                let created = Shelf(name: dto.name)
                created.uuid = dto.uuid
                context.insert(created)
                return created
            }()
            dto.apply(to: shelf)
        case "session":
            guard let dto = try? decoder.decode(SessionRecord.self, from: payload) else { return }
            if let session = fetchSession(dto.uuid) {
                dto.apply(to: session)
            } else {
                context.insert(dto.makeSession())
            }
        case "quote":
            guard let dto = try? decoder.decode(QuoteRecord.self, from: payload) else { return }
            if let quote = fetchQuote(dto.uuid) {
                dto.apply(to: quote)
            } else {
                context.insert(dto.makeQuote())
            }
        default:
            return
        }
        index[name] = item(named: name)?.hash
    }

    private func applyDeletion(_ name: String) {
        defer {
            index.removeValue(forKey: name)
            systemFields.removeValue(forKey: name)
        }
        guard let current = item(named: name) else { return }
        // Modifié sur cet appareil depuis : on le garde (il sera renvoyé).
        if let known = index[name], current.hash != known { return }
        let (kind, uuid) = split(name)
        guard let uuid else { return }
        switch kind {
        case "book": if let object = fetchBook(uuid) { context.delete(object) }
        case "shelf": if let object = fetchShelf(uuid) { context.delete(object) }
        case "session": if let object = fetchSession(uuid) { context.delete(object) }
        case "quote": if let object = fetchQuote(uuid) { context.delete(object) }
        default: break
        }
    }

    // MARK: - Éléments locaux

    private struct Item {
        let name: String
        let kind: String
        let payload: Data
        let cover: Data?
        let hash: String

        init(kind: String, uuid: UUID, payload: Data, cover: Data? = nil) {
            self.name = "\(kind)-\(uuid.uuidString)"
            self.kind = kind
            self.payload = payload
            self.cover = cover
            var hasher = SHA256()
            hasher.update(data: payload)
            if let cover { hasher.update(data: cover) }
            self.hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private func makeItem(_ book: Book) -> Item? {
        guard let data = try? Self.encoder.encode(BookRecord(book)) else { return nil }
        return Item(kind: "book", uuid: book.uuid, payload: data, cover: book.coverData)
    }

    private func makeItem(_ shelf: Shelf) -> Item? {
        guard let data = try? Self.encoder.encode(ShelfRecord(shelf)) else { return nil }
        return Item(kind: "shelf", uuid: shelf.uuid, payload: data)
    }

    private func makeItem(_ session: ReadingSession) -> Item? {
        guard let data = try? Self.encoder.encode(SessionRecord(session)) else { return nil }
        return Item(kind: "session", uuid: session.uuid, payload: data)
    }

    private func makeItem(_ quote: Quote) -> Item? {
        guard let data = try? Self.encoder.encode(QuoteRecord(quote)) else { return nil }
        return Item(kind: "quote", uuid: quote.uuid, payload: data)
    }

    private func allItems() -> [Item] {
        var items: [Item] = []
        for book in (try? context.fetch(FetchDescriptor<Book>())) ?? [] { if let item = makeItem(book) { items.append(item) } }
        for shelf in (try? context.fetch(FetchDescriptor<Shelf>())) ?? [] { if let item = makeItem(shelf) { items.append(item) } }
        for session in (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? [] { if let item = makeItem(session) { items.append(item) } }
        for quote in (try? context.fetch(FetchDescriptor<Quote>())) ?? [] { if let item = makeItem(quote) { items.append(item) } }
        return items
    }

    private func split(_ name: String) -> (String, UUID?) {
        guard let dash = name.firstIndex(of: "-") else { return (name, nil) }
        return (String(name[..<dash]), UUID(uuidString: String(name[name.index(after: dash)...])))
    }

    private func item(named name: String) -> Item? {
        let (kind, uuid) = split(name)
        guard let uuid else { return nil }
        switch kind {
        case "book": return fetchBook(uuid).flatMap(makeItem)
        case "shelf": return fetchShelf(uuid).flatMap(makeItem)
        case "session": return fetchSession(uuid).flatMap(makeItem)
        case "quote": return fetchQuote(uuid).flatMap(makeItem)
        default: return nil
        }
    }

    private func fetchBook(_ id: UUID) -> Book? {
        try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.uuid == id })).first
    }

    private func fetchShelf(_ id: UUID) -> Shelf? {
        try? context.fetch(FetchDescriptor<Shelf>(predicate: #Predicate { $0.uuid == id })).first
    }

    private func fetchSession(_ id: UUID) -> ReadingSession? {
        try? context.fetch(FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.uuid == id })).first
    }

    private func fetchQuote(_ id: UUID) -> Quote? {
        try? context.fetch(FetchDescriptor<Quote>(predicate: #Predicate { $0.uuid == id })).first
    }

    // MARK: - Fichiers de suivi

    private static var directory: URL {
        let url = URL.applicationSupportDirectory.appendingPathComponent("CloudSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var assetsDirectory: URL {
        let url = URL.cachesDirectory.appendingPathComponent("CloudSyncAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var stateURL: URL { Self.directory.appendingPathComponent("state.json") }
    private var indexURL: URL { Self.directory.appendingPathComponent("index.json") }
    private var fieldsURL: URL { Self.directory.appendingPathComponent("fields.json") }

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    private func loadFiles() {
        if let data = try? Data(contentsOf: indexURL),
           let value = try? JSONDecoder().decode([String: String].self, from: data) { index = value }
        if let data = try? Data(contentsOf: fieldsURL),
           let value = try? JSONDecoder().decode([String: Data].self, from: data) { systemFields = value }
    }

    private func saveFiles() {
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(systemFields) { try? data.write(to: fieldsURL, options: .atomic) }
    }

    /// Oublie l'état de synchro (changement de compte iCloud) sans toucher à la bibliothèque.
    private func resetSyncData() {
        stop()
        index = [:]
        systemFields = [:]
        sending = [:]
        try? FileManager.default.removeItem(at: Self.directory)
        UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
        Task { @MainActor in self.start() }
    }
}

// MARK: - Contenu des enregistrements

private struct BookRecord: Codable {
    var uuid: UUID
    var title: String
    var authors: String
    var summary: String
    var coverURLString: String?
    var isbn: String?
    var pageCount: Int
    var publisher: String?
    var publishedDate: String?
    var categories: String
    var language: String?
    var communityRating: Double?
    var communityRatingsCount: Int?
    var ratingSource: String?
    var infoLink: String?
    var openLibraryKey: String?
    var statusRaw: String
    var myRating: Int
    var myReview: String
    var dateAdded: Date
    var dateFinished: Date?
    var lastCheckedAt: Date?
    var appleBooksID: String?
    var sharedReviewAt: Date?
    var currentPage: Int
    var dateStarted: Date?
    var lentTo: String?
    var lentAt: Date?
    var seriesName: String
    var seriesIndex: Int
    var currentChapter: Int?
    var chapterCount: Int?

    init(_ b: Book) {
        uuid = b.uuid; title = b.title; authors = b.authors; summary = b.summary
        coverURLString = b.coverURLString; isbn = b.isbn; pageCount = b.pageCount
        publisher = b.publisher; publishedDate = b.publishedDate; categories = b.categories
        language = b.language; communityRating = b.communityRating
        communityRatingsCount = b.communityRatingsCount; ratingSource = b.ratingSource
        infoLink = b.infoLink; openLibraryKey = b.openLibraryKey; statusRaw = b.statusRaw
        myRating = b.myRating; myReview = b.myReview; dateAdded = b.dateAdded
        dateFinished = b.dateFinished; lastCheckedAt = b.lastCheckedAt
        appleBooksID = b.appleBooksID; sharedReviewAt = b.sharedReviewAt
        currentPage = b.currentPage; dateStarted = b.dateStarted
        lentTo = b.lentTo; lentAt = b.lentAt
        seriesName = b.seriesName; seriesIndex = b.seriesIndex
        currentChapter = b.currentChapter; chapterCount = b.chapterCount
    }

    func apply(to b: Book) {
        b.title = title; b.authors = authors; b.summary = summary
        b.coverURLString = coverURLString; b.isbn = isbn; b.pageCount = pageCount
        b.publisher = publisher; b.publishedDate = publishedDate; b.categories = categories
        b.language = language; b.communityRating = communityRating
        b.communityRatingsCount = communityRatingsCount; b.ratingSource = ratingSource
        b.infoLink = infoLink; b.openLibraryKey = openLibraryKey; b.statusRaw = statusRaw
        b.myRating = myRating; b.myReview = myReview; b.dateAdded = dateAdded
        b.dateFinished = dateFinished; b.lastCheckedAt = lastCheckedAt
        b.appleBooksID = appleBooksID; b.sharedReviewAt = sharedReviewAt
        b.currentPage = currentPage; b.dateStarted = dateStarted
        b.lentTo = lentTo; b.lentAt = lentAt
        b.seriesName = seriesName; b.seriesIndex = seriesIndex
        b.currentChapter = currentChapter ?? 0; b.chapterCount = chapterCount ?? 0
    }
}

private struct ShelfRecord: Codable {
    var uuid: UUID
    var name: String
    var emoji: String
    var colorIndex: Int
    var kindRaw: String
    var criterion: String
    var bookIDs: [String]
    var createdAt: Date

    init(_ s: Shelf) {
        uuid = s.uuid; name = s.name; emoji = s.emoji; colorIndex = s.colorIndex
        kindRaw = s.kindRaw; criterion = s.criterion; bookIDs = s.bookIDs; createdAt = s.createdAt
    }

    func apply(to s: Shelf) {
        s.name = name; s.emoji = emoji; s.colorIndex = colorIndex
        s.kindRaw = kindRaw; s.criterion = criterion; s.bookIDs = bookIDs; s.createdAt = createdAt
    }
}

private struct SessionRecord: Codable {
    var uuid: UUID
    var bookID: String
    var bookTitle: String
    var start: Date
    var end: Date
    var startPage: Int
    var endPage: Int

    init(_ s: ReadingSession) {
        uuid = s.uuid; bookID = s.bookID; bookTitle = s.bookTitle
        start = s.start; end = s.end; startPage = s.startPage; endPage = s.endPage
    }

    func apply(to s: ReadingSession) {
        s.bookID = bookID; s.bookTitle = bookTitle
        s.start = start; s.end = end; s.startPage = startPage; s.endPage = endPage
    }

    func makeSession() -> ReadingSession {
        let placeholder = Book(title: bookTitle)
        let session = ReadingSession(book: placeholder, start: start, end: end, startPage: startPage, endPage: endPage)
        session.uuid = uuid
        session.bookID = bookID
        return session
    }
}

private struct QuoteRecord: Codable {
    var uuid: UUID
    var bookID: String
    var text: String
    var page: Int
    var note: String
    var createdAt: Date

    init(_ q: Quote) {
        uuid = q.uuid; bookID = q.bookID; text = q.text; page = q.page; note = q.note; createdAt = q.createdAt
    }

    func apply(to q: Quote) {
        q.bookID = bookID; q.text = text; q.page = page; q.note = note; q.createdAt = createdAt
    }

    func makeQuote() -> Quote {
        let quote = Quote(book: Book(title: ""), text: text, page: page)
        quote.uuid = uuid
        quote.bookID = bookID
        quote.note = note
        quote.createdAt = createdAt
        return quote
    }
}
