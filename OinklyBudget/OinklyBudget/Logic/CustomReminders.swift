import Foundation
import SwiftData
import UserNotifications

extension Notification.Name {
    /// Posted when a reminder is clicked. `userInfo["page"]` is a `ReminderPage` raw value.
    static let piggybankOpenPage = Notification.Name("piggybank.openPage")
}

/// Where a reminder takes you when you click it.
enum ReminderPage: String, Codable, CaseIterable, Identifiable {
    case none, summary, transactions, reports, bills, planning, liabilities, investments

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "Just open Oinkly Budget"
        case .summary: "Summary"
        case .transactions: "Transactions"
        case .reports: "Reports"
        case .bills: "Bills & Recurring"
        case .planning: "Planning"
        case .liabilities: "Liabilities"
        case .investments: "Investments"
        }
    }
}

/// A reminder the user makes themselves: "Review my budget" on the 1st, "Enter receipts" every Sunday, and so on.
struct CustomReminder: Codable, Identifiable, Equatable {
    enum Repeat: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly, once
        var id: Self { self }
        var title: String {
            switch self {
            case .daily: "Every day"
            case .weekly: "Every week"
            case .monthly: "Every month"
            case .once: "Once"
            }
        }
    }

    var id = UUID()
    var title = ""
    var note = ""
    var repeats: Repeat = .monthly
    /// 1 = Sunday … 7 = Saturday, for weekly reminders.
    var weekday = 1
    /// 1…28, for monthly reminders. Capped at 28 so it exists in every month.
    var dayOfMonth = 1
    var onceDate = Date.now.addingTimeInterval(86_400)
    /// Only the hour and minute are used (except for "once", which uses the whole date).
    var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    var page: ReminderPage = .none
    var isOn = true

    var summary: String {
        let clock = time.formatted(date: .omitted, time: .shortened)
        switch repeats {
        case .daily: return "Every day at \(clock)"
        case .weekly: return "Every \(Calendar.current.weekdaySymbols[(weekday - 1) % 7]) at \(clock)"
        case .monthly: return "Day \(dayOfMonth) of every month at \(clock)"
        case .once: return onceDate.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// A one-time reminder whose moment has already gone by.
    var hasPassed: Bool { repeats == .once && onceDate <= .now }

    static let presets: [(title: String, reminder: CustomReminder)] = {
        func make(_ title: String, _ note: String, _ repeats: Repeat, weekday: Int = 1, day: Int = 1, page: ReminderPage) -> CustomReminder {
            var r = CustomReminder()
            r.title = title; r.note = note; r.repeats = repeats; r.weekday = weekday; r.dayOfMonth = day; r.page = page
            return r
        }
        return [
            ("Review my budget", make("Review my budget", "Take a few minutes to see how this month's spending compares with your budget.", .monthly, page: .reports)),
            ("Check my bills", make("Check my bills", "See what's due this week.", .weekly, weekday: 2, page: .bills)),
            ("Enter receipts", make("Enter receipts", "Add this week's receipts and transactions so nothing piles up.", .weekly, weekday: 1, page: .transactions)),
            ("Check my goals", make("Check my goals", "See how your goals are coming along.", .monthly, day: 15, page: .planning)),
            ("Back up my data", make("Back up my data", "Make a backup in Settings ▸ Data & Backup.", .monthly, day: 1, page: .none)),
        ]
    }()
}

/// The user's custom reminders. Kept in the database, so everyone who shares the data sees the same ones, and turned
/// into repeating system notifications on each Mac, so they arrive even when OinklyBudget isn't open.
@MainActor
@Observable
final class CustomReminders {
    static let shared = CustomReminders()

    private static let idPrefix = "piggybank.reminder."

    var items: [CustomReminder] {
        didSet {
            guard items != oldValue else { return }
            persist()
            Task { await apply() }
        }
    }

    private init() {
        if ScreenshotMode.isOn {
            // Screenshots show ready-made reminders, never the person's own.
            items = CustomReminder.presets.prefix(3).map(\.reminder)
        } else {
            items = Self.stored()
        }
    }

    private static var context: ModelContext? { OinklyBudgetAppDelegate.container?.mainContext }

    private static func stored() -> [CustomReminder] {
        context.map { SettingsRecords.reminders(in: $0) } ?? []
    }

    private func persist() {
        guard !ScreenshotMode.isOn, let context = Self.context else { return }
        SettingsRecords.setReminders(items, in: context)
        context.saveNow()
    }

    /// Reads the reminders again from the database, after the data was replaced (a restored backup).
    func reload() {
        guard !ScreenshotMode.isOn else { return }
        items = Self.stored()
        Task { await apply() }
    }

    /// Replaces the scheduled notifications with the current set.
    func apply() async {
        guard !ScreenshotMode.isOn, !StartupState.isHoldingPlace else { return }
        WidgetSnapshotWriter.refreshSoon()
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) })

        let active = items.filter { $0.isOn && !$0.hasPassed }
        guard !active.isEmpty, await BillNotifier.requestAccess() else { return }

        let calendar = Calendar.current
        for reminder in active {
            let clock = calendar.dateComponents([.hour, .minute], from: reminder.time)
            var parts = DateComponents()
            var repeating = true
            switch reminder.repeats {
            case .daily:
                parts = clock
            case .weekly:
                parts = clock
                parts.weekday = reminder.weekday
            case .monthly:
                parts = clock
                parts.day = reminder.dayOfMonth
            case .once:
                parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.onceDate)
                repeating = false
            }
            let content = UNMutableNotificationContent()
            content.title = reminder.title.isEmpty ? "Oinkly Budget" : reminder.title
            content.body = reminder.note.isEmpty ? "A reminder from Oinkly Budget." : reminder.note
            content.sound = .default
            content.userInfo = ["page": reminder.page.rawValue]
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: repeating)
            try? await center.add(UNNotificationRequest(identifier: Self.idPrefix + reminder.id.uuidString, content: content, trigger: trigger))
        }
    }
}
