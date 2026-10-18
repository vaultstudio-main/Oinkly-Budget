import SwiftUI
import SwiftData

/// What the reports on the Reports page share: the last year of transactions, and the transactions of the period picked
/// at the top. Loaded once by the page, so each report doesn't go back to the database.
struct ReportInputs {
    /// The last thirteen months (this month and twelve before it).
    var year: [Transaction] = []

    /// A stretch of time reports are totalled over, ending now.
    struct Window: Identifiable {
        let title: String
        let start: Date
        var id: String { title }
    }

    /// This month, the last three months, the last six months and the last year. Reports show these side by side, so
    /// there is no period to pick.
    static func windows(now: Date = .now, calendar: Calendar = .current) -> [Window] {
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        func back(_ months: Int) -> Date { calendar.startOfDay(for: calendar.date(byAdding: .month, value: -months, to: now) ?? now) }
        return [Window(title: "This month", start: month), Window(title: "Last 3 months", start: back(3)),
                Window(title: "Last 6 months", start: back(6)), Window(title: "Last year", start: back(12))]
    }

    /// Real income and spending since `start`: transfers, such as loan payments, are neither.
    func real(since start: Date, before end: Date = .distantFuture) -> [Transaction] {
        year.filter { !$0.isTransfer && $0.date >= start && $0.date < end }
    }

    struct CategoryLine: Identifiable {
        let name: String
        let symbol: String
        let colorHex: String
        var amount: Double
        var id: String { name }
    }

    /// Spending (or income) by category over the transactions given, biggest first.
    static func categories(_ transactions: [Transaction], income: Bool) -> [CategoryLine] {
        var table: [String: CategoryLine] = [:]
        for transaction in transactions where income ? transaction.amount > 0 : transaction.amount < 0 {
            let name = transaction.category?.name ?? "Uncategorized"
            var line = table[name] ?? CategoryLine(name: name, symbol: transaction.category?.symbol ?? "questionmark.circle",
                                                  colorHex: transaction.category?.colorHex ?? "8E8E93", amount: 0)
            line.amount += abs(transaction.amount.doubleValue)
            table[name] = line
        }
        return table.values.sorted { $0.amount > $1.amount }
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
