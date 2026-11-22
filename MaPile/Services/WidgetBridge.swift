import Foundation
import SwiftData
import UIKit
import WidgetKit
import ActivityKit

/// Met à jour les widgets et pilote la Live Activity de la séance de lecture.
@MainActor
enum WidgetBridge {

    /// Recalcule le résumé lu par les widgets et les rafraîchit.
    static func refresh(_ context: ModelContext) {
        let reading = (try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.statusRaw == "reading" }))) ?? []
        let read = (try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.statusRaw == "read" }))) ?? []
        let pile = (try? context.fetchCount(FetchDescriptor<Book>(predicate: #Predicate { $0.statusRaw == "toRead" }))) ?? 0
        let sessions = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let year = Calendar.current.component(.year, from: .now)

        var snapshot = WidgetSnapshot()
        snapshot.reading = reading.prefix(3).map { book in
            WidgetSnapshot.ReadingBook(title: book.title, author: book.authorList.first ?? "",
                                       page: book.currentPage, pageCount: book.pageCount,
                                       cover: thumbnail(book.coverData))
        }
        snapshot.streak = ReadingStreak.current(days: ReadingStreak.readingDays(sessions: sessions, finished: read))
        snapshot.yearCount = read.filter { Calendar.current.component(.year, from: $0.finishedOn) == year }.count
        let goal = UserDefaults.standard.integer(forKey: "yearlyGoal")
        snapshot.goal = goal > 0 ? goal : 20
        snapshot.pileCount = pile
        snapshot.updatedAt = .now
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Petite vignette JPEG pour les widgets (la taille des données partagées est limitée).
    private static func thumbnail(_ data: Data?) -> Data? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let height: CGFloat = 240
        let scale = height / max(image.size.height, 1)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.7)
    }

    // MARK: - Live Activity

    static func startActivity(for book: Book) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endActivity()
        let attributes = ReadingActivityAttributes(bookTitle: book.title, author: book.authorList.first ?? "")
        let state = ReadingActivityAttributes.ContentState(startDate: .now, page: book.currentPage, pageCount: book.pageCount)
        _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
    }

    static func endActivity() {
        for activity in Activity<ReadingActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
