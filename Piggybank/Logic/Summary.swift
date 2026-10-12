import Foundation
import SwiftData

/// Pure calculations behind the Summary screen.
enum Summary {
    struct NetWorthPoint: Identifiable {
        let month: Date
        let group: AccountGroup
        let value: Double
        var id: String { "\(month.timeIntervalSince1970)-\(group.rawValue)" }
    }

    struct FlowPoint: Identifiable {
        let month: Date
        let kind: String
        let value: Double
        var id: String { "\(month.timeIntervalSince1970)-\(kind)" }
    }

    /// Start of each of the last `count` months, oldest first.
    static func monthStarts(count: Int, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
    }

    /// The same chart, read from a ledger snapshot: a lookup per account per month.
    static func netWorthSeries(accounts: [Account], snapshot: LedgerSnapshot, months: Int = 12, now: Date = .now,
                               calendar: Calendar = .current) -> [NetWorthPoint] {
        let starts = monthStarts(count: months, now: now, calendar: calendar)
        let cutoffs = starts.map { min(calendar.dateInterval(of: .month, for: $0)?.end ?? $0, now) }
        let live = accounts.live
        return starts.indices.flatMap { month in
            AccountGroup.allCases.map { group in
                let value = live.filter { $0.type.group == group }.reduce(Decimal(0)) {
                    $0 + $1.openingBalance + snapshot.total(for: $1.persistentModelID, asOf: cutoffs[month])
                }
                return NetWorthPoint(month: starts[month], group: group, value: value.doubleValue)
            }
        }
    }

    /// A group's total as of `date`, read from a ledger snapshot.
    static func total(of accounts: [Account], in groups: [AccountGroup], snapshot: LedgerSnapshot, asOf date: Date = .distantFuture) -> Decimal {
        accounts.live.filter { groups.contains($0.type.group) }.reduce(0) {
            $0 + $1.openingBalance + snapshot.total(for: $1.persistentModelID, asOf: date)
        }
    }

}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
