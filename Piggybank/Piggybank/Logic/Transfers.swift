import Foundation
import SwiftData

/// Paying a loan, mortgage or card from another account. That is one event with two sides:
/// money leaves the paying account and the same amount comes off what you owe.
enum Transfers {
    /// Accounts money can be moved between: anything you own, open and live. Debts are left out, because paying a card or
    /// loan is a payment, not a transfer.
    static func transferable(_ accounts: [Account]) -> [Account] {
        accounts.live.filter { !$0.isDebt && !$0.isClosed }
    }

    /// Accounts a bill can be paid from. Money is never taken from an investment account to pay a bill.
    static func billPayable(_ accounts: [Account]) -> [Account] {
        transferable(accounts).filter { !$0.supportsHoldings }
    }

    /// The account a new transaction starts on. Loans take payments and credit cards take charges through their own
    /// forms, so opening one of those starts on your first ordinary account (checking preferred).
    static func startingAccount(opening account: Account?, accounts: [Account]) -> Account? {
        let live = accounts.live
        guard let account, account.isLive else { return live.first }
        guard account.isLoan || account.isCreditCard || account.isCashOnHand else { return account }
        let ordinary = live.filter { !$0.isDebt && !$0.isCashOnHand }
        return ordinary.first { $0.type == .checking } ?? ordinary.first ?? account
    }

    /// Creates both halves and returns them as (paying side, liability side).
    @discardableResult
    static func pay(
        from source: Account,
        toward liability: Account,
        amount: Decimal,
        date: Date,
        memo: String,
        state: ReconcileState,
        paymentType: PaymentType?,
        checkNumber: String,
        in context: ModelContext
    ) -> (out: Transaction, into: Transaction) {
        move(from: source, to: liability, amount: amount, date: date, memo: memo, state: state,
             paymentType: paymentType, checkNumber: checkNumber,
             payeeOut: "Payment to \(liability.name)", payeeIn: "Payment from \(source.name)", in: context)
    }

    /// Moves money between two of your accounts: one event, two sides, left out of income and spending.
    @discardableResult
    static func move(
        from source: Account,
        to destination: Account,
        amount: Decimal,
        date: Date,
        memo: String = "",
        state: ReconcileState = .unreconciled,
        paymentType: PaymentType? = nil,
        checkNumber: String = "",
        payeeOut: String,
        payeeIn: String,
        in context: ModelContext
    ) -> (out: Transaction, into: Transaction) {
        let id = UUID()
        let out = Transaction(account: source, date: date, payee: payeeOut, memo: memo, amount: -abs(amount), paymentType: paymentType)
        out.checkNumber = paymentType == .check ? checkNumber : ""
        let into = Transaction(account: destination, date: date, payee: payeeIn, memo: memo, amount: abs(amount))
        for leg in [out, into] {
            leg.transferID = id
            leg.state = state
            context.insert(leg)
        }
        return (out, into)
    }

    /// The other half of a transfer, if there is one.
    static func peer(of transaction: Transaction, in context: ModelContext) -> Transaction? {
        guard let id = transaction.transferID else { return nil }
        let matches = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.transferID == id }))) ?? []
        return matches.first { $0.persistentModelID != transaction.persistentModelID }
    }

    /// Deletes a transaction, and the other half of its transfer so the loan balance stays honest.
    static func delete(_ transaction: Transaction, in context: ModelContext) {
        // A bill this payment settled goes back to unpaid. The link is on the paying side, so look at both halves.
        let other = peer(of: transaction, in: context)
        var reopened = BillPayment.release(transaction)
        if let other, BillPayment.release(other) { reopened = true }
        if reopened { Task { await BillNotifier.refresh(in: context) } }
        if let other { context.delete(other) }
        context.delete(transaction)
    }

    /// Carries date, memo and state from one half to the other. Amounts stay mirrored.
    static func syncPeer(of transaction: Transaction, in context: ModelContext) {
        guard let other = peer(of: transaction, in: context) else { return }
        other.date = transaction.date
        other.memo = transaction.memo
        other.state = transaction.state
        other.amount = -transaction.amount
    }
}

enum RecentActivity {
    /// The newest transactions across every account. A payment or transfer is one event with two entries, so only the
    /// paying side (money out) is listed, and each event shows once. Each account's register still has both sides.
    static func latest(_ transactions: [Transaction], limit: Int = 15) -> [Transaction] {
        // Read each transaction's sort keys once, instead of inside every comparison.
        let keyed = transactions.compactMap { transaction -> (Date, Date, Transaction)? in
            guard transaction.isLive else { return nil }
            // The receiving half of a payment or transfer is the same event as the paying half.
            if transaction.isTransfer && transaction.amount > 0 { return nil }
            return (transaction.date, transaction.createdAt, transaction)
        }
        return keyed
            .sorted { ($0.0, $0.1) > ($1.0, $1.1) }
            .prefix(limit)
            .map(\.2)
    }
}
