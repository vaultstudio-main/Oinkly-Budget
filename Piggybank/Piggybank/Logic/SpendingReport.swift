import Foundation
import SwiftData

/// Where the money went, or came from, over the last few months, by category.
/// Only categorized transactions count: transactions with no category (such as card payments) are left out.
/// Pass `income: true` for money coming in; the default is spending.
enum SpendingReport {
    /// Expenses needed before the chart shows real data instead of the placeholder.
    static let minimumTransactions = 3

    struct CategoryTotal: Identifiable {
        let category: Category
        let total: Decimal
        var id: PersistentIdentifier { category.persistentModelID }
    }

    struct MonthTop: Identifiable {
        let month: Date
        let top: CategoryTotal?
        var id: Date { month }
    }

    /// Categorized expenses dated in the last `months` calendar months, including the current one.
    static func expenses(in transactions: [Transaction], months: Int = 3, income: Bool = false, now: Date = .now, calendar: Calendar = .current) -> [Transaction] {
        guard let first = Summary.monthStarts(count: months, now: now, calendar: calendar).first,
              let end = calendar.dateInterval(of: .month, for: now)?.end else { return [] }
        return transactions.filter { transaction in
            guard fits(transaction, income: income) else { return false }
            return transaction.date >= first && transaction.date < end
        }
    }

    /// Money out in an expense category, or money in under an income category.
    private static func fits(_ transaction: Transaction, income: Bool) -> Bool {
        transaction.categoryParts.contains { fits($0.category, $0.amount, income: income) }
    }

    private static func fits(_ category: Category?, _ amount: Decimal, income: Bool) -> Bool {
        guard let category else { return false }
        return income ? (amount > 0 && category.isIncome) : (amount < 0 && !category.isIncome)
    }

    /// Categorized expenses dated in one calendar month.
    static func expenses(in transactions: [Transaction], month: Date, calendar: Calendar = .current) -> [Transaction] {
        transactions.filter { transaction in
            guard fits(transaction, income: false) else { return false }
            return MonthFilter.contains(month, transaction.date, calendar: calendar)
        }
    }

    /// Spending per category in one calendar month, biggest first. Each month starts from zero.
    static func totals(_ transactions: [Transaction], month: Date, calendar: Calendar = .current) -> [CategoryTotal] {
        totals(of: expenses(in: transactions, month: month, calendar: calendar), income: false)
    }

    static func hasEnoughData(_ transactions: [Transaction], months: Int = 3, income: Bool = false, now: Date = .now, calendar: Calendar = .current) -> Bool {
        expenses(in: transactions, months: months, income: income, now: now, calendar: calendar).count >= minimumTransactions
    }

    /// Spending per category over the window, biggest first.
    static func totals(_ transactions: [Transaction], months: Int = 3, income: Bool = false, now: Date = .now, calendar: Calendar = .current) -> [CategoryTotal] {
        totals(of: expenses(in: transactions, months: months, income: income, now: now, calendar: calendar), income: income)
    }

    /// The biggest category in each month of the window, oldest month first.
    static func topByMonth(_ transactions: [Transaction], months: Int = 3, income: Bool = false, now: Date = .now, calendar: Calendar = .current) -> [MonthTop] {
        let all = expenses(in: transactions, months: months, income: income, now: now, calendar: calendar)
        return Summary.monthStarts(count: months, now: now, calendar: calendar).map { start in
            let end = calendar.dateInterval(of: .month, for: start)?.end ?? start
            let inMonth = all.filter { $0.date >= start && $0.date < end }
            return MonthTop(month: start, top: totals(of: inMonth, income: income).first)
        }
    }

    private static func totals(of expenses: [Transaction], income: Bool) -> [CategoryTotal] {
        var sums: [PersistentIdentifier: (Category, Decimal)] = [:]
        for transaction in expenses {
            // Each part of a split counts under its own category.
            for part in transaction.categoryParts where fits(part.category, part.amount, income: income) {
                guard let category = part.category else { continue }
                let id = category.persistentModelID
                // Spending is stored negative; income positive. Both are reported as positive totals.
                sums[id] = (category, (sums[id]?.1 ?? 0) + (income ? part.amount : -part.amount))
            }
        }
        return sums.values
            .map { CategoryTotal(category: $0.0, total: $0.1) }
            .sorted { $0.total == $1.total ? $0.category.name < $1.category.name : $0.total > $1.total }
    }
}
