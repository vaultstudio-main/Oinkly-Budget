import Foundation
import SwiftData

enum ReportPeriod: String, CaseIterable, Identifiable {
    case monthly, quarterly, sixMonths, yearly

    var id: Self { self }

    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .sixMonths: "6 Months"
        case .yearly: "Yearly"
        }
    }

    /// How many months one report covers, and how far the previous/next arrows move.
    var months: Int {
        switch self {
        case .monthly: 1
        case .quarterly: 3
        case .sixMonths: 6
        case .yearly: 12
        }
    }
}

/// The dates a report covers. `end` is exclusive.
struct ReportRange: Equatable {
    let start: Date
    let end: Date
}

enum Reports {
    struct Bucket: Identifiable {
        let start: Date
        let label: String
        var income: Decimal = 0
        var spending: Decimal = 0
        var id: Date { start }
    }

    struct CategoryLine: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let colorHex: String
        let amount: Decimal
    }

    struct Totals: Equatable {
        var income: Decimal = 0
        var spending: Decimal = 0
        var count = 0

        var net: Decimal { income - spending }
        var savingsRate: Decimal? { income > 0 ? net / income : nil }
    }

    struct Report {
        let range: ReportRange
        let totals: Totals
        let previous: Totals
        let buckets: [Bucket]
        let spending: [CategoryLine]
    }

    /// Dates are labeled in the same time zone the report's calendar uses.
    private static func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: calendar.timeZone)
    }

    // MARK: Ranges

    /// The calendar month, quarter or year containing `anchor`; or, for 6 Months, the six months ending with `anchor`'s month.
    static func range(_ period: ReportPeriod, anchor: Date, calendar: Calendar = .current) -> ReportRange {
        let monthStart = calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor
        func add(_ months: Int, to date: Date) -> Date { calendar.date(byAdding: .month, value: months, to: date) ?? date }

        switch period {
        case .monthly:
            return ReportRange(start: monthStart, end: add(1, to: monthStart))
        case .quarterly:
            let month = calendar.component(.month, from: monthStart)
            let start = add(-((month - 1) % 3), to: monthStart)
            return ReportRange(start: start, end: add(3, to: start))
        case .sixMonths:
            let end = add(1, to: monthStart)
            return ReportRange(start: add(-6, to: end), end: end)
        case .yearly:
            let year = calendar.dateInterval(of: .year, for: anchor)
            return ReportRange(start: year?.start ?? monthStart, end: year?.end ?? add(12, to: monthStart))
        }
    }

    /// Moves the anchor forward or back by whole reports.
    static func shifted(_ anchor: Date, period: ReportPeriod, by steps: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: steps * period.months, to: anchor) ?? anchor
    }

    /// The report of the same length right before this one.
    static func previous(of range: ReportRange, period: ReportPeriod, calendar: Calendar = .current) -> ReportRange {
        let start = calendar.date(byAdding: .month, value: -period.months, to: range.start) ?? range.start
        return ReportRange(start: start, end: range.start)
    }

    /// "October 2026", "Q4 2026", "May – Oct 2026", "2026".
    static func label(_ period: ReportPeriod, range: ReportRange, calendar: Calendar = .current) -> String {
        switch period {
        case .monthly:
            return range.start.formatted(style(calendar).month(.wide).year())
        case .quarterly:
            let quarter = (calendar.component(.month, from: range.start) - 1) / 3 + 1
            return "Q\(quarter) \(calendar.component(.year, from: range.start))"
        case .sixMonths:
            let last = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            let from = range.start.formatted(style(calendar).month(.abbreviated))
            let to = last.formatted(style(calendar).month(.abbreviated).year())
            return "\(from) – \(to)"
        case .yearly:
            return range.start.formatted(style(calendar).year())
        }
    }

    // MARK: Numbers

    /// Income and spending for transactions in `range`. Transfers, such as loan payments, are neither.
    static func totals(_ transactions: [Transaction], in range: ReportRange) -> Totals {
        var totals = Totals()
        for transaction in transactions {
            let date = transaction.date
            guard date >= range.start, date < range.end, !transaction.isTransfer else { continue }
            let amount = transaction.amount
            if amount > 0 { totals.income += amount } else { totals.spending -= amount }
            totals.count += 1
        }
        return totals
    }

    /// The whole report, in one pass over the transactions.
    static func build(_ transactions: [Transaction], period: ReportPeriod, range: ReportRange, calendar: Calendar = .current) -> Report {
        var buckets = makeBuckets(period: period, range: range, calendar: calendar)
        var totals = Totals()
        var spending: [String: (name: String, symbol: String, color: String, amount: Decimal)] = [:]

        for transaction in transactions {
            let date = transaction.date
            guard date >= range.start, date < range.end, !transaction.isTransfer else { continue }
            let amount = transaction.amount
            let index = bucketIndex(for: date, in: buckets)

            if amount > 0 {
                totals.income += amount
                if let index { buckets[index].income += amount }
            } else {
                totals.spending -= amount
                if let index { buckets[index].spending -= amount }
                if let category = transaction.category {
                    let key = category.systemKey ?? category.name
                    var line = spending[key] ?? (category.name, category.symbol, category.colorHex, 0)
                    line.amount -= amount
                    spending[key] = line
                } else {
                    var line = spending["uncategorized"] ?? ("Uncategorized", "questionmark.circle", "8E8E93", 0)
                    line.amount -= amount
                    spending["uncategorized"] = line
                }
            }
            totals.count += 1
        }

        var lines: [CategoryLine] = []
        for (key, value) in spending {
            lines.append(CategoryLine(id: key, name: value.name, symbol: value.symbol, colorHex: value.color, amount: value.amount))
        }
        lines.sort { first, second in
            first.amount == second.amount ? first.name < second.name : first.amount > second.amount
        }

        return Report(
            range: range,
            totals: totals,
            previous: self.totals(transactions, in: previous(of: range, period: period, calendar: calendar)),
            buckets: buckets,
            spending: lines
        )
    }

    // MARK: Buckets

    /// A month is shown week by week; longer reports are shown month by month.
    private static func makeBuckets(period: ReportPeriod, range: ReportRange, calendar: Calendar) -> [Bucket] {
        var buckets: [Bucket] = []
        var cursor = range.start
        while cursor < range.end {
            switch period {
            case .monthly:
                buckets.append(Bucket(start: cursor, label: cursor.formatted(style(calendar).month(.abbreviated).day())))
                cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? range.end
            default:
                buckets.append(Bucket(start: cursor, label: cursor.formatted(style(calendar).month(.abbreviated))))
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? range.end
            }
        }
        return buckets
    }

    private static func bucketIndex(for date: Date, in buckets: [Bucket]) -> Int? {
        var low = 0, high = buckets.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if buckets[mid].start <= date { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }

    /// Percent change from `previous` to `current`, or nil when there is nothing to compare with.
    static func change(from previous: Decimal, to current: Decimal) -> Double? {
        guard previous > 0 else { return nil }
        return ((current - previous) / previous).doubleValue
    }
}
