import Foundation

/// Month selection for account pages. A "month" is always represented by its first instant.
enum MonthFilter {
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    static func contains(_ month: Date, _ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: month, toGranularity: .month)
    }

    static func transactions(_ transactions: [Transaction], in month: Date, calendar: Calendar = .current) -> [Transaction] {
        transactions.filter { contains(month, $0.date, calendar: calendar) }
    }

    /// The months you can step through: from the earliest transaction (or this month) to the latest (or this month).
    static func range(for transactions: [Transaction], now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date> {
        let current = start(of: now, calendar: calendar)
        let dates = transactions.map(\.date)
        let lower = dates.min().map { min(start(of: $0, calendar: calendar), current) } ?? current
        let upper = dates.max().map { max(start(of: $0, calendar: calendar), current) } ?? current
        return lower...upper
    }

    static func isCurrent(_ month: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        contains(month, now, calendar: calendar)
    }

    /// "This Month" for the current month, otherwise "Sep 2026".
    static func shortLabel(_ month: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        isCurrent(month, now: now, calendar: calendar) ? "This Month" : month.formatted(.dateTime.month(.abbreviated).year())
    }
}
