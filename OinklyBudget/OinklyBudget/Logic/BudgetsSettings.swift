import Foundation

/// What the Budgets page is showing, chosen in its Settings window and read by the page: the month for the Monthly tab and the
/// week for the Weekly tab. They are kept in preferences, so the window and the page agree as soon as either changes.
enum BudgetsSettings {
    /// The month, as a time since the reference date. Zero means this month.
    static let monthKey = "budgetsMonth"
    /// The week, as a time since the reference date. Zero means this week.
    static let weekKey = "budgetsWeek"

    /// Which tab of the page the Settings window is for, so it shows that tab's choice: "monthly" or "weekly".
    static let tabKey = "budgetsSettingsTab"

    /// Each start of the app begins on this month and this week, whatever was chosen last time.
    static var resetThisLaunch = false

    static func weekStart(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func month(from stamp: Double, calendar: Calendar = .current) -> Date {
        stamp == 0 ? MonthFilter.start(of: .now, calendar: calendar) : MonthFilter.start(of: Date(timeIntervalSinceReferenceDate: stamp), calendar: calendar)
    }

    static func week(from stamp: Double, calendar: Calendar = .current) -> Date {
        stamp == 0 ? weekStart(of: .now, calendar: calendar) : weekStart(of: Date(timeIntervalSinceReferenceDate: stamp), calendar: calendar)
    }

    /// The months that can be chosen: two years back up to this month.
    static var monthRange: ClosedRange<Date> {
        let current = MonthFilter.start(of: .now)
        return (Calendar.current.date(byAdding: .month, value: -24, to: current) ?? current)...current
    }

    /// The weeks that can be chosen: two years back up to this week.
    static var weekRange: ClosedRange<Date> {
        let current = weekStart(of: .now)
        return (Calendar.current.date(byAdding: .weekOfYear, value: -104, to: current) ?? current)...current
    }

    /// A week as words, such as "Oct 19 – 25, 2026".
    static func weekLabel(_ week: Date, calendar: Calendar = .current) -> String {
        let interval = calendar.dateInterval(of: .weekOfYear, for: week) ?? DateInterval(start: week, duration: 7 * 86_400)
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let first = interval.start.formatted(.dateTime.month(.abbreviated).day())
        let end = calendar.isDate(interval.start, equalTo: last, toGranularity: .month)
            ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        return "\(first) – \(end), \(last.formatted(.dateTime.year()))"
    }
}
