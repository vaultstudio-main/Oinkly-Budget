import Foundation
import SwiftData

/// Where the money went over the last few months, by category.
/// Only categorized expenses count: income, and transactions with no category (such as card payments), are left out.
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
    static func expenses(in transactions: [Transaction], months: Int = 3, now: Date = .now, calendar: Calendar = .current) -> [Transaction] {
        guard let first = Summary.monthStarts(count: months, now: now, calendar: calendar).first,
              let end = calendar.dateInterval(of: .month, for: now)?.end else { return [] }
        return transactions.filter { transaction in
            guard transaction.amount < 0, let category = transaction.category, !category.isIncome else { return false }
            return transaction.date >= first && transaction.date < end
        }
    }

    /// Categorized expenses dated in one calendar month.
    static func expenses(in transactions: [Transaction], month: Date, calendar: Calendar = .current) -> [Transaction] {
        transactions.filter { transaction in
            guard transaction.amount < 0, let category = transaction.category, !category.isIncome else { return false }
            return MonthFilter.contains(month, transaction.date, calendar: calendar)
        }
    }

    /// Spending per category in one calendar month, biggest first. Each month starts from zero.
    static func totals(_ transactions: [Transaction], month: Date, calendar: Calendar = .current) -> [CategoryTotal] {
        totals(of: expenses(in: transactions, month: month, calendar: calendar))
    }

    static func hasEnoughData(_ transactions: [Transaction], months: Int = 3, now: Date = .now, calendar: Calendar = .current) -> Bool {
        expenses(in: transactions, months: months, now: now, calendar: calendar).count >= minimumTransactions
    }

    /// Spending per category over the window, biggest first.
    static func totals(_ transactions: [Transaction], months: Int = 3, now: Date = .now, calendar: Calendar = .current) -> [CategoryTotal] {
        totals(of: expenses(in: transactions, months: months, now: now, calendar: calendar))
    }

    /// The biggest category in each month of the window, oldest month first.
    static func topByMonth(_ transactions: [Transaction], months: Int = 3, now: Date = .now, calendar: Calendar = .current) -> [MonthTop] {
        let all = expenses(in: transactions, months: months, now: now, calendar: calendar)
        return Summary.monthStarts(count: months, now: now, calendar: calendar).map { start in
            let end = calendar.dateInterval(of: .month, for: start)?.end ?? start
            let inMonth = all.filter { $0.date >= start && $0.date < end }
            return MonthTop(month: start, top: totals(of: inMonth).first)
        }
    }

    private static func totals(of expenses: [Transaction]) -> [CategoryTotal] {
        var sums: [PersistentIdentifier: (Category, Decimal)] = [:]
        for transaction in expenses {
            guard let category = transaction.category else { continue }
            let id = category.persistentModelID
            sums[id] = (category, (sums[id]?.1 ?? 0) - transaction.amount)
        }
        return sums.values
            .map { CategoryTotal(category: $0.0, total: $0.1) }
            .sorted { $0.total == $1.total ? $0.category.name < $1.category.name : $0.total > $1.total }
    }
}
