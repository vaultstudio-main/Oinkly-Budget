import Foundation
import SwiftData

/// The pending entry a bill makes in the account it comes out of. A bill with a "Pays from" account gets a pending entry on
/// each due date, linked to that due date. Ticking the bill off reconciles the entry (or makes one, already reconciled, when
/// it is ticked before its date); ticking it again puts the entry back to pending. Paying the bill with Pay a Bill replaces
/// the pending entry with the real payment, which is made reconciled.
enum BillEntries {
    /// How far back a missed due date still gets an entry, so setting an account on an old bill doesn't fill the register.
    static let lookBackDays = 30

    /// Makes a linked entry for one due date in the account the bill comes out of. Never makes a second one for the same date.
    @MainActor
    @discardableResult
    static func makeEntry(for bill: Bill, on due: Date, in account: Account, state: ReconcileState, context: ModelContext, calendar: Calendar = .current) -> Transaction? {
        let day = calendar.startOfDay(for: due)
        guard bill.isLive, account.isLive, BillLink.payments(of: bill, on: day, calendar: calendar).isEmpty else { return nil }
        let entry = Transaction(account: account, date: day, payee: bill.name,
                                category: bill.category?.isLive == true ? bill.category : nil, memo: "", amount: -abs(bill.amount))
        entry.state = state
        entry.paidBill = bill
        entry.paidDueDate = day
        if let locked = account.lockedPaymentType { entry.paymentChoice = .type(locked) }
        else if let usual = BillMethods.choice(for: bill, in: context) { entry.paymentChoice = usual }
        context.insert(entry)
        return entry
    }

    /// Adds a pending entry for every unpaid due date, up to today, of each bill that has an account, if it has none yet.
    /// Running it again straight away changes nothing. Returns how many were made.
    @MainActor
    @discardableResult
    static func run(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -lookBackDays, to: today) ?? today
        var made = 0
        var changed = false
        for bill in ((try? context.fetch(FetchDescriptor<Bill>())) ?? []).live {
            guard let account = BillPaySources.account(for: bill, in: context), let source = BillPaySources.source(for: bill, in: context) else { continue }
            // Dates already given their entry are not looked at again, so an entry that was deleted stays deleted.
            var start = from
            if let done = source.madeThrough, let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: done)) { start = max(from, next) }
            for item in Bills.occurrences([bill], from: start, through: today, now: now, calendar: calendar) where !item.isPaid {
                if makeEntry(for: bill, on: item.date, in: account, state: .pending, context: context, calendar: calendar) != nil { made += 1 }
            }
            if source.madeThrough != today { source.madeThrough = today; changed = true }
        }
        if made > 0 || changed { context.saveNow() }
        return made
    }

    /// Ticks a due date off. With an account on the bill, its entry is reconciled; with none, the bill is only marked paid, as before.
    @MainActor
    static func markPaid(_ bill: Bill, on due: Date, in context: ModelContext, calendar: Calendar = .current) {
        bill.setPaid(true, on: due, calendar: calendar)
        guard let account = BillPaySources.account(for: bill, in: context) else { return }
        let linked = BillLink.payments(of: bill, on: due, calendar: calendar)
        if linked.isEmpty {
            makeEntry(for: bill, on: due, in: account, state: .reconciled, context: context, calendar: calendar)
        } else {
            for entry in linked {
                if entry.state != .reconciled { entry.state = .reconciled }
                // Ticking also fills in the usual payment method, if the entry has none yet and the account doesn't set one.
                if entry.paymentChoice == nil, account.lockedPaymentType == nil, let usual = BillMethods.choice(for: bill, in: context) { entry.paymentChoice = usual }
            }
        }
    }

    /// Unticks a due date. With an account on the bill, its entry goes back to pending, unless Pay a Bill made it (that is a
    /// real payment, which stays put).
    @MainActor
    static func markUnpaid(_ bill: Bill, on due: Date, in context: ModelContext, calendar: Calendar = .current) {
        bill.setPaid(false, on: due, calendar: calendar)
        guard BillPaySources.account(for: bill, in: context) != nil else { return }
        for entry in BillLink.payments(of: bill, on: due, calendar: calendar) where !entry.isBillPayment && entry.state == .reconciled {
            entry.state = .pending
        }
    }
}
