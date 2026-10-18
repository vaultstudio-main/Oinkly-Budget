import Foundation
import SwiftData
import WidgetKit

/// Keeps the widgets' snapshot up to date. Called when the app opens, when anything is saved, when reminders change
/// and now and then while it runs. Changes are gathered for a moment so a burst of saves writes the file once.
@MainActor
enum WidgetSnapshotWriter {
    private static var pending: Task<Void, Never>?

    static func refreshSoon() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    static func refresh(now: Date = .now) {
        guard let container = PiggybankAppDelegate.container else { return }
        // A fresh context always reads what has been saved.
        let context = ModelContext(container)
        let bills = ((try? context.fetch(FetchDescriptor<Bill>())) ?? []).live

        let items: [WidgetSnapshot.Bill] = Bills.upcoming(bills, days: 30, now: now)
            .filter { !$0.isPaid && $0.bill.isLive }
            .map { WidgetSnapshot.Bill(id: $0.id, name: $0.bill.name, due: $0.date, isImportant: $0.bill.isImportant, isOverdue: $0.isOverdue) }
            .sorted { $0.due < $1.due }

        let reminders: [WidgetSnapshot.Reminder] = CustomReminders.shared.items
            .filter { $0.isOn && !$0.hasPassed }
            .compactMap { reminder in
                reminder.nextDate(after: now).map {
                    WidgetSnapshot.Reminder(id: reminder.id.uuidString, title: reminder.title.isEmpty ? "Reminder" : reminder.title, next: $0)
                }
            }
            .sorted { $0.next < $1.next }

        let snapshot = WidgetSnapshot(updated: now, bills: items, reminders: Array(reminders.prefix(12)))
        if snapshot.write() { WidgetCenter.shared.reloadAllTimelines() }
    }
}

extension CustomReminder {
    /// The next time this reminder goes off after `date`.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        var parts = clock
        switch repeats {
        case .daily:
            break
        case .weekly:
            parts.weekday = weekday
        case .monthly:
            parts.day = dayOfMonth
        case .once:
            return onceDate > date ? onceDate : nil
        }
        return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime)
    }
}
