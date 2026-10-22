import Foundation

/// One line in the widget: a bill, a repeating transaction or one of the person's own reminders. Names and dates only.
/// This file is compiled into both the app and the widget extension, so the app's checks can test what the widget lists.
nonisolated struct WidgetLine: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case bill, repeating, reminder

        var title: String {
            switch self {
            case .bill: "Bill"
            case .repeating: "Repeating"
            case .reminder: "Reminder"
            }
        }
    }

    let id: String
    let name: String
    let date: Date
    let kind: Kind
    let isImportant: Bool
    let isOverdue: Bool
}

/// Builds the one list the widget shows from the snapshot the app wrote: overdue first, then everything due through the
/// end of the chosen range, soonest first. It matches what the menu bar item lists, without amounts.
nonisolated enum WidgetLines {
    struct Options: Equatable, Sendable {
        var onlyImportant = false
        var includeRepeating = true
        var includeReminders = true
        /// Nil for "this month"; otherwise how many days ahead, counting today.
        var lookAheadDays: Int?
    }

    /// The first moment that is no longer in range.
    static func end(for options: Options, now: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: now)
        if let days = options.lookAheadDays { return calendar.date(byAdding: .day, value: days + 1, to: day) ?? day }
        let month = calendar.dateInterval(of: .month, for: now)
        return month?.end ?? calendar.date(byAdding: .day, value: 31, to: day) ?? day
    }

    static func make(_ snapshot: WidgetSnapshot?, now: Date, options: Options = Options(), calendar: Calendar = .current) -> [WidgetLine] {
        guard let snapshot else { return [] }
        let day = calendar.startOfDay(for: now)
        let end = end(for: options, now: now, calendar: calendar)
        var result: [WidgetLine] = []

        for bill in snapshot.bills where (bill.due >= day || bill.isOverdue) && bill.due < end && (!options.onlyImportant || bill.isImportant) {
            result.append(WidgetLine(id: "bill-" + bill.id, name: bill.name, date: bill.due, kind: .bill, isImportant: bill.isImportant, isOverdue: bill.isOverdue))
        }
        if options.includeRepeating && !options.onlyImportant {
            for item in snapshot.repeating where (item.due >= day || item.isOverdue) && item.due < end {
                result.append(WidgetLine(id: "repeat-" + item.id, name: item.name, date: item.due, kind: .repeating, isImportant: false, isOverdue: item.isOverdue))
            }
        }
        if options.includeReminders {
            for reminder in snapshot.reminders where reminder.next >= now && reminder.next < end {
                result.append(WidgetLine(id: "reminder-" + reminder.id, name: reminder.title, date: reminder.next, kind: .reminder, isImportant: false, isOverdue: false))
            }
        }
        return result.sorted {
            if $0.isOverdue != $1.isOverdue { return $0.isOverdue }
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.name < $1.name
        }
    }
}
