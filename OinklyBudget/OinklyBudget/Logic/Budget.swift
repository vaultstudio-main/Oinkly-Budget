import Foundation
import SwiftData

/// How much was spent in each category in a month. Build it once per refresh with `Budget.spentTable`.
struct SpentTable {
    fileprivate let sums: [PersistentIdentifier: Decimal]
    subscript(category: Category) -> Decimal { sums[category.persistentModelID] ?? 0 }
}

/// Per-category monthly budget figures.
enum Budget {
    /// Total spent (as a positive number) in `category` during the month containing `month`.
    static func spent(in category: Category, transactions: [Transaction], month: Date = .now, calendar: Calendar = .current) -> Decimal {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
        var total: Decimal = 0
        for transaction in transactions where transaction.amount < 0 && interval.contains(transaction.date) {
            for part in transaction.categoryParts where part.category?.persistentModelID == category.persistentModelID { total -= part.amount }
        }
        return total
    }

    /// Spending for every category in `interval` (a week, say), in one pass over the transactions.
    static func spentTable(_ transactions: [Transaction], interval: DateInterval) -> SpentTable {
        var sums: [PersistentIdentifier: Decimal] = [:]
        for transaction in transactions {
            guard transaction.amount < 0, interval.contains(transaction.date) else { continue }
            for part in transaction.categoryParts {
                guard let category = part.category else { continue }
                sums[category.persistentModelID, default: 0] -= part.amount
            }
        }
        return SpentTable(sums: sums)
    }

    /// Spending for every category in one pass over the transactions. Looking each category up one at a time
    /// meant scanning every transaction once per category, hundreds of times per screen refresh.
    static func spentTable(_ transactions: [Transaction], month: Date = .now, calendar: Calendar = .current) -> SpentTable {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return SpentTable(sums: [:]) }
        var sums: [PersistentIdentifier: Decimal] = [:]
        for transaction in transactions {
            let amount = transaction.amount
            guard amount < 0, interval.contains(transaction.date) else { continue }
            for part in transaction.categoryParts {
                guard let category = part.category else { continue }
                sums[category.persistentModelID, default: 0] -= part.amount
            }
        }
        return SpentTable(sums: sums)
    }

    /// Fraction of the limit used, clamped to 0...1. A limit of zero or less counts as 0.
    static func progress(spent: Decimal, limit: Decimal) -> Double {
        guard limit > 0 else { return 0 }
        return min(max((spent / limit).doubleValue, 0), 1)
    }
}

extension Budget {
}
