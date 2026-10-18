import SwiftUI
import SwiftData

/// What the reports on the Reports page share: the last year of transactions, and the transactions of the period picked
/// at the top. Loaded once by the page, so each report doesn't go back to the database.
struct ReportInputs {
    /// The last thirteen months (this month and twelve before it).
    var year: [Transaction] = []
    /// The chosen period and the one before it.
    var period: [Transaction] = []
    var range = ReportRange(start: .now, end: .now)
    var previous = ReportRange(start: .now, end: .now)
    var periodName = ""

    /// Transactions in the chosen period that are real income or spending (transfers, such as loan payments, are neither).
    var inPeriod: [Transaction] {
        period.filter { $0.date >= range.start && $0.date < range.end && !$0.isTransfer }
    }

    /// Start of each of the last twelve months, oldest first.
    static func months(now: Date = .now, calendar: Calendar = .current) -> [Date] {
        Summary.monthStarts(count: 12, now: now, calendar: calendar)
    }

    /// Income and spending by month for the last twelve months, transfers left out.
    func monthlyTotals(calendar: Calendar = .current) -> [(date: Date, income: Double, spending: Double)] {
        let starts = Self.months(calendar: calendar)
        var income = Array(repeating: 0.0, count: starts.count)
        var spending = Array(repeating: 0.0, count: starts.count)
        for transaction in year where !transaction.isTransfer {
            guard let index = starts.lastIndex(where: { $0 <= transaction.date }), transaction.date >= starts[0] else { continue }
            let amount = transaction.amount.doubleValue
            if amount > 0 { income[index] += amount } else { spending[index] -= amount }
        }
        return starts.indices.map { (starts[$0], income[$0], spending[$0]) }
    }
}

private struct ReportInputsKey: EnvironmentKey {
    static let defaultValue = ReportInputs()
}

extension EnvironmentValues {
    var reportInputs: ReportInputs {
        get { self[ReportInputsKey.self] }
        set { self[ReportInputsKey.self] = newValue }
    }
}
