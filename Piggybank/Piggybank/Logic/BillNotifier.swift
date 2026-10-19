import Foundation
import SwiftData
import UserNotifications

/// Turns each bill's reminder into a real system notification, so it arrives even when the app isn't open.
/// Notifications are planned about 45 days ahead and re-planned whenever the app starts, comes forward, or a bill changes.
enum BillNotifier {
    /// UserDefaults key for the Settings switch. On unless turned off.
    static let enabledKey = "billRemindersOn"
    private static let idPrefix = "piggybank.bill."
    /// The system keeps at most 64 pending notifications per app, so stay under that.
    private static let limit = 60

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Asks the system for permission if it hasn't been asked yet. Returns whether notifications are allowed.
    @discardableResult
    static func requestAccess() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default: return false
        }
    }

    enum Status { case notAsked, allowed, denied }

    /// Whether macOS will let OinklyBudget show notifications.
    static func status() async -> Status {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        default: .notAsked
        }
    }

    /// Shows a notification a couple of seconds from now, so you can see that they work. Returns false when
    /// notifications aren't allowed.
    static func sendTest() async -> Bool {
        guard await requestAccess() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Oinkly Budget"
        content.body = "Bill reminders will look like this."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "piggybank.test", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        do { try await UNUserNotificationCenter.current().add(request); return true } catch { return false }
    }

    /// Replaces the planned notifications with the current set. Cheap enough to call often.
    @MainActor
    static func refresh(in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()

        // Clear out only our own notifications.
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard isEnabled, let bills = try? context.fetch(FetchDescriptor<Bill>()) else { return }

        let reminders = Bills.reminders(bills, horizonDays: 45)
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)

        // Only ask for permission once there is actually something to remind about, not on a first launch with no bills.
        guard !reminders.isEmpty, await requestAccess() else { return }

        let calendar = Calendar.current
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            let due = reminder.dueDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            if reminder.isDueDay {
                content.title = reminder.isImportant ? "Important bill due today: \(reminder.name)" : "\(reminder.name) is due today"
                content.body = "\(reminder.amount.formatted(.appCurrency)) is due today."
            } else {
                content.title = reminder.isImportant ? "Important bill: \(reminder.name)" : "\(reminder.name) is due soon"
                content.body = "\(reminder.amount.formatted(.appCurrency)) due \(due)."
            }
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: idPrefix + reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
