import Foundation
import SwiftData

/// Tying a bill's due date to the transaction that actually paid it, so the Month Outlook can use what really came out of
/// the account, not just what the bill was expected to cost. A payment made with Pay a Bill is linked as it is made;
/// this is for a payment that came in some other way, such as an automatic draft or an import.
enum BillLink {
    /// What really came out for one due date of a bill, as a positive number: the linked payments added up. Nil when
    /// nothing is linked, such as a due date that was only ticked off.
    static func actual(of bill: Bill, on due: Date, calendar: Calendar = .current) -> Decimal? {
        let linked = payments(of: bill, on: due, calendar: calendar)
        guard !linked.isEmpty else { return nil }
        return linked.reduce(Decimal(0)) { $0 + abs($1.amount) }
    }

    /// The live payments linked to one due date.
    static func payments(of bill: Bill, on due: Date, calendar: Calendar = .current) -> [Transaction] {
        bill.payments.filter { $0.isLive && $0.paidDueDate.map { calendar.isDate($0, inSameDayAs: due) } == true }
    }

    /// Links `transaction` to the due date `due` of `bill`, and ticks that date off. A payment linked somewhere else
    /// first is let go of.
    static func link(_ transaction: Transaction, to bill: Bill, due: Date, calendar: Calendar = .current) {
        if transaction.paidBill != nil { unlink(transaction, calendar: calendar) }
        let day = calendar.startOfDay(for: due)
        transaction.paidBill = bill
        transaction.paidDueDate = day
        bill.setPaid(true, on: day, calendar: calendar)
    }

    /// Lets go of a link. The due date goes back to unpaid unless another payment is still linked to it.
    static func unlink(_ transaction: Transaction, calendar: Calendar = .current) {
        guard let bill = transaction.paidBill, bill.isLive, let due = transaction.paidDueDate else {
            transaction.paidBill = nil
            transaction.paidDueDate = nil
            return
        }
        transaction.paidBill = nil
        transaction.paidDueDate = nil
        if payments(of: bill, on: due, calendar: calendar).filter({ $0 !== transaction }).isEmpty {
            bill.setPaid(false, on: due, calendar: calendar)
        }
    }

    /// A transaction that might be the payment for a due date.
    struct Candidate: Identifiable {
        let transaction: Transaction
        /// The payee looks like the bill, or the amount is nearly the same.
        let isLikely: Bool
        var id: Transaction.ID { transaction.id }
    }

    /// How far either side of a due date a payment can land and still be offered.
    static let windowDays = 20

    /// Transactions that could be the payment for `due`, from `pool` (money that went out and isn't linked to a bill),
    /// likely ones first, then the closest in date.
    static func candidates(for bill: Bill, due: Date, in pool: [Transaction], calendar: Calendar = .current) -> [Candidate] {
        let day = calendar.startOfDay(for: due)
        let from = calendar.date(byAdding: .day, value: -windowDays, to: day) ?? day
        let through = calendar.date(byAdding: .day, value: windowDays + 1, to: day) ?? day
        let found = pool.filter {
            $0.isLive && $0.paidBill == nil && $0.amount < 0 && $0.account?.isLive == true && $0.date >= from && $0.date < through
        }
        let name = normalised(bill.name)
        let ranked = found.map { transaction -> (Candidate, TimeInterval) in
            let payee = normalised(transaction.payee)
            let sameName = !name.isEmpty && !payee.isEmpty && (payee.contains(name) || name.contains(payee))
            let near = bill.amount > 0 && abs(abs(transaction.amount) - bill.amount) <= bill.amount / 50
            return (Candidate(transaction: transaction, isLikely: sameName || near), abs(transaction.date.timeIntervalSince(day)))
        }
        return ranked.sorted { a, b in
            if a.0.isLikely != b.0.isLikely { return a.0.isLikely }
            return a.1 < b.1
        }.map(\.0)
    }

    /// The one transaction worth offering with a single click: the closest likely match.
    static func suggestion(for bill: Bill, due: Date, in pool: [Transaction], calendar: Calendar = .current) -> Transaction? {
        candidates(for: bill, due: due, in: pool, calendar: calendar).first { $0.isLikely }?.transaction
    }

    private static func normalised(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
