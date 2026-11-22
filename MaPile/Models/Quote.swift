import Foundation
import SwiftData

/// Une citation (passage) enregistrée pour un livre.
@Model
final class Quote {
    var uuid: UUID = UUID()
    var bookID: String = ""
    var text: String = ""
    var page: Int = 0
    var note: String = ""
    var createdAt: Date = Date()

    init(book: Book, text: String, page: Int = 0) {
        self.bookID = book.uuid.uuidString
        self.text = text
        self.page = page
    }
}
