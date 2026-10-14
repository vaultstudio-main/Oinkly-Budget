import Foundation

/// Dates shared by the reports that look at balances over time.
enum Trend {
    /// The last moment a report counts: the end of the period, or now if the period is still running.
    static func endDate(_ range: ReportRange, now: Date = .now) -> Date {
        min(range.end.addingTimeInterval(-1), now)
    }

    /// Just before the period begins, so a transaction dated on the first day counts inside the period.
    static func startDate(_ range: ReportRange) -> Date {
        range.start.addingTimeInterval(-1)
    }

    /// The close of each month in the period, up to now.
    static func monthEnds(_ range: ReportRange, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var monthStart = range.start
        while monthStart < range.end && monthStart <= now {
            let next = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? range.end
            result.append(min(next.addingTimeInterval(-1), now))
            monthStart = next
        }
        return result
    }
}
