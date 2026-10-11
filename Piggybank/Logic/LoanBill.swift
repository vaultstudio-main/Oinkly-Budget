import Foundation
import SwiftData

/// A loan or credit card with a payment due date puts itself on the Bills page: named after the account, for the monthly
/// (or minimum) payment, repeating every month on that date. Ticking it paid there shows on the loan's own page too, since it is one bill.
extension Account {
    /// The bill this loan added to Bills, if it has a due date.
    var loanBill: Bill? { loanBills.live.first }
}

enum LoanBill {
    /// Makes, updates or removes the loan's bill so it matches the loan. Pass nil for `dueDate` to take it off Bills.
    static func sync(_ account: Account, dueDate: Date?, in context: ModelContext, calendar: Calendar = .current) {
        guard account.isLoan || account.isCreditCard, let dueDate else {
            for bill in account.loanBills.live { context.delete(bill) }
            return
        }
        let day = calendar.startOfDay(for: dueDate)
        let bill: Bill
        let isNew: Bool
        if let existing = account.loanBill {
            bill = existing
            isNew = existing.dueDate != day
        } else {
            bill = Bill(name: account.name, amount: account.monthlyPayment, frequency: .monthly, dueDate: day)
            bill.loan = account
            context.insert(bill)
            isNew = true
        }
        bill.name = account.name
        bill.amount = account.monthlyPayment
        bill.frequency = .monthly
        bill.dueDate = day

        // Payments from before this month are history, not something to nag about. This month's stays open.
        if isNew, let month = calendar.dateInterval(of: .month, for: .now) {
            for date in Bills.dates(of: bill, from: .distantPast, through: month.start.addingTimeInterval(-1), calendar: calendar) {
                bill.setPaid(true, on: date, calendar: calendar)
            }
        }
    }

    /// This month's payment for the loan: its date and whether it has been paid. Nil when the loan has no due date.
    static func thisMonth(_ account: Account, calendar: Calendar = .current) -> Bills.Occurrence? {
        guard let bill = account.loanBill, let month = calendar.dateInterval(of: .month, for: .now) else { return nil }
        let end = calendar.date(byAdding: .day, value: -1, to: month.end)!
        return Bills.occurrences([bill], from: month.start, through: end).first
    }

    /// Payments still to make before the loan matures, counted on its due date each month when it has one.
    /// Nil without a maturity date. Zero once the date has passed.
    static func paymentsToMaturity(_ account: Account, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let maturity = account.payoffDate else { return nil }
        let today = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: maturity)
        guard end >= today else { return 0 }
        if let bill = account.loanBill {
            return Bills.dates(of: bill, from: today, through: end, calendar: calendar)
                .filter { !bill.isPaid(on: $0, calendar: calendar) }
                .count
        }
        return calendar.dateComponents([.month], from: today, to: end).month ?? 0
    }

    /// "the 15th of every month"
    static func dueText(_ bill: Bill, calendar: Calendar = .current) -> String {
        let day = calendar.component(.day, from: bill.dueDate)
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return "the \(formatter.string(from: NSNumber(value: day)) ?? "\(day)") of every month"
    }
}
