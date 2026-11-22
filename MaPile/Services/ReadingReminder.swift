import Foundation
import UserNotifications

/// Notifications locales : rappel de lecture quotidien (facultatif) et rappel de livre prêté.
/// Tout est programmé sur l'iPhone, rien n'est envoyé à un serveur.
@MainActor
enum ReadingReminder {
    static let enabledKey = "reminderEnabled"
    static let hourKey = "reminderHour"
    static let minuteKey = "reminderMinute"
    private static let dailyID = "mapile-daily-reading"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Demande l'autorisation d'afficher des notifications (une seule fois).
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// Programme (ou reprogramme) le rappel quotidien à l'heure choisie.
    @discardableResult
    static func scheduleDaily() async -> Bool {
        guard await requestAuthorization() else { return false }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])
        let defaults = UserDefaults.standard
        var components = DateComponents()
        components.hour = defaults.object(forKey: hourKey) as? Int ?? 21
        components.minute = defaults.object(forKey: minuteKey) as? Int ?? 0
        let content = UNMutableNotificationContent()
        content.title = "C'est l'heure de lire 📖"
        content.body = "Quelques pages ce soir ? Votre série de lecture vous attend."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger))
        return true
    }

    static func cancelDaily() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyID])
    }

    /// Au lancement : reprogramme le rappel s'il est activé (après une mise à jour, par exemple).
    static func refreshIfNeeded() {
        guard isEnabled else { return }
        Task { await scheduleDaily() }
    }

    // MARK: - Livres prêtés

    private static func loanID(_ book: Book) -> String { "mapile-loan-\(book.uuid.uuidString)" }

    /// Rappel « pensez à récupérer votre livre » au bout de 30 jours.
    static func scheduleLoanReminder(for book: Book, days: Int = 30) async {
        guard let person = book.lentTo, await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Livre prêté 📚"
        content.body = "Pensez à récupérer « \(book.title) », prêté à \(person) il y a \(days) jours."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(days * 86_400), repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: loanID(book), content: content, trigger: trigger))
    }

    static func cancelLoanReminder(for book: Book) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [loanID(book)])
    }
}
