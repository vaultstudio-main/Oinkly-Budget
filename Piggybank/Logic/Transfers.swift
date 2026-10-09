import Foundation
import SwiftData

/// Paying a loan, mortgage or card from another account. That is one event with two sides:
/// money leaves the paying account and the same amount comes off what you owe.
enum Transfers {
    /// Accounts you can pay toward: anything you owe, except the account the money comes from.
    static func payableAccounts(_ accounts: [Account], excluding source: Account?) -> [Account] {
        accounts.live.filter { $0.isDebt && $0.persistentModelID != source?.persistentModelID }
    }

    /// Where a new payment starts. Opened from a loan or card page, the likely intent is a payment *to* it,
    /// paid from your first ordinary account (checking preferred).
    static func defaults(opening account: Account?, accounts: [Account]) -> (source: Account?, liability: Account?) {
        let live = accounts.live
        guard let account, account.isLive, account.isDebt else { return (account ?? live.first, nil) }
        let sources = live.filter { !$0.isDebt }
        let source = sources.first { $0.type == .checking } ?? sources.first
        return source == nil ? (account, nil) : (source, account)
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
        let id = UUID()
        let out = Transaction(account: source, date: date, payee: "Payment to \(liability.name)", memo: memo, amount: -abs(amount), paymentType: paymentType)
        out.checkNumber = paymentType == .check ? checkNumber : ""
        let into = Transaction(account: liability, date: date, payee: "Payment from \(source.name)", memo: memo, amount: abs(amount))
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
        if let other = peer(of: transaction, in: context) { context.delete(other) }
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
    /// The newest transactions across every account. Both sides of a transfer are included, so each account's
    /// activity is complete.
    static func latest(_ transactions: [Transaction], limit: Int = 15) -> [Transaction] {
        // Read each transaction's sort keys once, instead of inside every comparison.
        let keyed = transactions.compactMap { transaction -> (Date, Date, Transaction)? in
            guard transaction.isLive else { return nil }
            return (transaction.date, transaction.createdAt, transaction)
        }
        return keyed
            .sorted { ($0.0, $0.1) > ($1.0, $1.1) }
            .prefix(limit)
            .map(\.2)
    }
}
