import Foundation
import ActivityKit

/// Live Activity de la séance de lecture (écran verrouillé et île dynamique).
struct ReadingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        var page: Int
        var pageCount: Int
    }

    var bookTitle: String
    var author: String
}
