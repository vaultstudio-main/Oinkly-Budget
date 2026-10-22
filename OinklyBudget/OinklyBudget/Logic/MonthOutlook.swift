import Foundation
import SwiftData

/// The Month Outlook: for one calendar month, what comes in, what is committed to go out, and what is left over to save.
///
/// It is built from what is already in the app. Income and repeating expenses come from Recurring, bills from Bills,
/// and each budget counts at the larger of its limit and what has actually been spent in it. A bill that was paid
/// counts at the amount that really came out when its payment is linked, so a bill that ran over or under changes the
/// result. Spending that belongs to no bill and no budget is added as it happens.
struct MonthOutlook {
    /// Where a line stands.
    enum Status {
        /// Nothing has happened yet.
        case expected
        /// Past its date and not paid.
        case overdue
        /// Ticked off as paid, with no payment linked, so the expected amount is used.
        case paid
        /// Paid, and the amount that really came out is more than expected.
        case over
        /// Paid, and less than expected.
        case under
        /// Already in an account, such as a paycheque that has been added.
        case received
    }

    /// One bill, repeating transaction or paycheque.
    struct Line: Identifiable {
        let id: String
        let title: String
        let date: Date
        let kind: String
        let expected: Decimal
        /// What really came out or came in, when it is known.
        let actual: Decimal?
        let status: Status
        /// What the line counts as in the totals.
        var counted: Decimal { actual ?? expected }
        var difference: Decimal { counted - expected }
    }

    /// One budget: its limit, what has been spent, and what is still on its way from bills and repeating expenses.
    struct BudgetLine: Identifiable {
        let category: Category
        let limit: Decimal
        let spent: Decimal
        /// Bills and repeating expenses in this category that haven't come out yet, plus ones ticked off with no payment.
        let planned: Decimal
        /// The bills and repeating expenses counted inside this budget.
        let inside: [Line]
        var id: PersistentIdentifier { category.persistentModelID }
        /// What it counts as: the limit, or more when it has run over.
        var counted: Decimal { max(limit, spent + planned) }
        var over: Decimal { max(spent + planned - limit, 0) }
        var remaining: Decimal { max(limit - spent - planned, 0) }
    }

    let month: Date
    let income: [Line]
    let bills: [Line]
    let budgets: [BudgetLine]
    /// Money that came in with nothing behind it: a gift, interest, a refund from a store.
    let otherIncome: Decimal
    /// Money spent that belongs to no bill and no budget.
    let otherSpending: Decimal

    var incomeTotal: Decimal { income.reduce(0) { $0 + $1.counted } + otherIncome }
    var billsTotal: Decimal { bills.reduce(0) { $0 + $1.counted } }
    var budgetsTotal: Decimal { budgets.reduce(0) { $0 + $1.counted } }
    var outTotal: Decimal { billsTotal + budgetsTotal + otherSpending }
    var leftToSave: Decimal { incomeTotal - outTotal }

    /// How much more (positive) or less (negative) than expected the bills came to, from linked payments.
    var billDifference: Decimal {
        (bills + budgets.flatMap(\.inside)).reduce(0) { $0 + ($1.actual == nil ? 0 : $1.difference) }
    }
    /// Budgets that have run past their limit, added up.
    var budgetOverspend: Decimal { budgets.reduce(0) { $0 + $1.over } }

    // MARK: Which accounts count

    /// Accounts the person left out of the outlook, kept in preferences by a key of account type and name.
    static let excludedKey = "outlookExcludedAccounts"

    static func accountKey(_ account: Account) -> String { "\(account.type.rawValue)|\(account.name)" }

    /// The keys of the accounts left out, stored as one line each.
    static func excluded(from stored: String) -> Set<String> {
        Set(stored.split(separator: "\n").map(String.init))
    }

    static func stored(_ keys: Set<String>) -> String { keys.sorted().joined(separator: "\n") }

    /// An account was renamed or changed type: its choice follows it.
    static func accountChanged(from oldKey: String, to newKey: String, defaults: UserDefaults = .standard) {
        var keys = excluded(from: defaults.string(forKey: excludedKey) ?? "")
        guard oldKey != newKey, keys.remove(oldKey) != nil else { return }
        keys.insert(newKey)
        defaults.set(stored(keys), forKey: excludedKey)
    }

    // MARK: Building

    /// Works out the outlook for the month containing `month`. `monthTransactions` is every transaction dated in it.
    static func build(
        month: Date, bills: [Bill], rules: [RecurringTransaction], categories: [Category], monthTransactions: [Transaction],
        excludedAccounts: Set<String> = [], cashBudgetKeys: Set<String> = [], weeklyAmounts: [String: Decimal] = [:], now: Date = .now, calendar: Calendar = .current
    ) -> MonthOutlook {
        func counts(_ account: Account?) -> Bool { account.map { !excludedAccounts.contains(accountKey($0)) } ?? true }
        let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 86400 * 30)
        let start = interval.start
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let live = monthTransactions.filter { $0.isLive && $0.account?.isLive == true && counts($0.account) }

        // Cash budgets are paid for in cash, so they are not part of the outlook: not their budget, not their bills, not their spending.
        func isCash(_ category: Category?) -> Bool { category.map { cashBudgetKeys.contains(CashBudgets.key(for: $0)) } ?? false }
        let budgeted = categories.live.filter { !$0.isIncome && $0.showOnBudgets && $0.monthlyLimit > 0 && !isCash($0) }
        let budgetIDs = Set(budgeted.map(\.persistentModelID))
        // A budget set as a weekly amount is worth that many days of it in this month: the days the month has over seven.
        func monthLimit(_ category: Category) -> Decimal {
            guard let weekly = weeklyAmounts[BudgetPeriods.key(for: category)] else { return category.monthlyLimit }
            return BudgetPeriods.monthlyMaximum(weekly: weekly, inMonthOf: start, calendar: calendar)
        }
        let spent = Budget.spentTable(live, month: start, calendar: calendar)
        var planned: [PersistentIdentifier: Decimal] = [:]
        var inside: [PersistentIdentifier: [Line]] = [:]
        var billLines: [Line] = []
        var incomeLines: [Line] = []

        /// A line goes inside its budget when its category has one, otherwise it stands alone.
        func place(_ line: Line, category: Category?, plannedAmount: Decimal) {
            if isCash(category) { return }
            if let id = category?.persistentModelID, budgetIDs.contains(id) {
                planned[id, default: 0] += plannedAmount
                inside[id, default: []].append(line)
            } else {
                billLines.append(line)
            }
        }

        // Bills.
        for item in Bills.occurrences(bills, from: start, through: last, now: now, calendar: calendar) {
            let bill = item.bill
            let linked = BillLink.payments(of: bill, on: item.date, calendar: calendar)
            // Paid from an account that is left out: not part of this outlook.
            if !linked.isEmpty, !linked.contains(where: { counts($0.account) }) { continue }
            let actual = BillLink.actual(of: bill, on: item.date, calendar: calendar)
            let status: Status
            if let actual, item.isPaid {
                status = actual > bill.amount ? .over : (actual < bill.amount ? .under : .paid)
            } else if actual != nil {
                // Not ticked off yet, but its pending entry is already in the account: it counts at that amount, still waiting.
                status = item.isOverdue ? .overdue : .expected
            } else {
                status = item.isPaid ? .paid : (item.isOverdue ? .overdue : .expected)
            }
            let line = Line(id: "bill-" + item.id, title: bill.name, date: item.date, kind: "Bill", expected: bill.amount, actual: actual, status: status)
            // What a budget still has to count for this bill: nothing if its payment is already in the budget's spending.
            var pending: Decimal = 0
            if actual == nil {
                pending = bill.amount
            } else if let category = bill.category {
                for payment in linked where !payment.categoryParts.contains(where: { $0.category?.persistentModelID == category.persistentModelID }) {
                    pending += abs(payment.amount)
                }
            }
            place(line, category: bill.category, plannedAmount: pending)
        }

        // Paycheques and other repeating transactions.
        for item in Recurring.occurrences(rules.filter { counts($0.account) }, from: start, through: last, now: now, calendar: calendar) {
            let rule = item.rule
            let entered = item.kind == .added
            if rule.amount > 0 {
                let amount = entered ? (item.entry?.amount ?? rule.amount) : rule.amount
                incomeLines.append(Line(id: "income-" + item.id, title: rule.payee, date: item.date, kind: "Income", expected: rule.amount,
                                        actual: entered ? amount : nil, status: entered ? .received : (item.isOverdue ? .overdue : .expected)))
            } else if rule.amount < 0 {
                let expected = abs(rule.amount)
                let actual = entered ? item.entry.map { abs($0.amount) } : nil
                let status: Status = entered ? .received : (item.isOverdue ? .overdue : .expected)
                let line = Line(id: "repeat-" + item.id, title: rule.payee, date: item.date, kind: "Repeating", expected: expected, actual: actual, status: status)
                // An entry that was added is a real transaction, already in the budget's spending.
                place(line, category: rule.category, plannedAmount: entered ? 0 : expected)
            }
        }

        // Everything else that actually happened: spending in no budget and not a bill or repeating entry, and income with no rule.
        var otherSpending: Decimal = 0
        var otherIncome: Decimal = 0
        for transaction in live where !transaction.isTransfer && !transaction.isOpeningDeposit && transaction.account?.supportsHoldings != true {
            if transaction.paidBill != nil || transaction.recurring != nil { continue }
            for part in transaction.categoryParts {
                if let id = part.category?.persistentModelID, budgetIDs.contains(id) { continue }
                if isCash(part.category) { continue }
                if part.amount < 0 {
                    otherSpending -= part.amount
                } else if part.category?.isIncome == true || part.category == nil {
                    otherIncome += part.amount
                } else {
                    // A refund in an expense category takes something off spending.
                    otherSpending -= part.amount
                }
            }
        }

        let budgetLines = budgeted.map {
            BudgetLine(category: $0, limit: monthLimit($0), spent: spent[$0], planned: planned[$0.persistentModelID] ?? 0,
                       inside: (inside[$0.persistentModelID] ?? []).sorted { $0.date < $1.date })
        }.sorted { $0.category.name.localizedCaseInsensitiveCompare($1.category.name) == .orderedAscending }

        return MonthOutlook(month: start, income: incomeLines.sorted { $0.date < $1.date }, bills: billLines.sorted { $0.date < $1.date },
                            budgets: budgetLines, otherIncome: otherIncome, otherSpending: max(otherSpending, 0))
    }
}
