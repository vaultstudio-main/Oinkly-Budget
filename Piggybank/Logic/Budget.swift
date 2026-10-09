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
        return transactions
            .filter { $0.amount < 0 && interval.contains($0.date) && $0.category?.persistentModelID == category.persistentModelID }
            .reduce(0) { $0 - $1.amount }
    }

    /// Spending for every category in one pass over the transactions. Looking each category up one at a time
    /// meant scanning every transaction once per category, hundreds of times per screen refresh.
    static func spentTable(_ transactions: [Transaction], month: Date = .now, calendar: Calendar = .current) -> SpentTable {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return SpentTable(sums: [:]) }
        var sums: [PersistentIdentifier: Decimal] = [:]
        for transaction in transactions {
            let amount = transaction.amount
            guard amount < 0, interval.contains(transaction.date), let category = transaction.category else { continue }
            sums[category.persistentModelID, default: 0] -= amount
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
    /// A budget counts as "set" once it has an amount above zero.
    static func isSet(_ category: Category) -> Bool { !category.isIncome && category.monthlyLimit > 0 }

    /// Budgets to show on Home, the Budgets tab and the Summary: only ones with an amount set and
    /// visibility turned on in Settings. Nothing is ever deleted; hidden budgets stay in Settings.
    static func visibleBudgets(_ categories: [Category]) -> [Category] {
        categories.filter { isSet($0) && $0.showOnBudgets }
    }
}
