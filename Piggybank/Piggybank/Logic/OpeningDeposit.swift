import Foundation
import SwiftData

/// The money an account starts with, kept as a real deposit: payee Deposit, category Deposit, method Bank Deposit,
/// all three locked. An account never gets an empty one, so a deposit exists only while it has an amount above zero.
@MainActor
enum OpeningDeposit {
    /// The built-in Deposit category, made first if it isn't there yet.
    static func category(in context: ModelContext) -> Category? {
        let key = Transaction.depositCategoryKey
        func find() -> Category? {
            ((try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate<Category> { $0.systemKey == key }))) ?? []).first { $0.isLive }
        }
        if let found = find() { return found }
        Category.ensureSystemCategories(in: context)
        return find()
    }

    /// The opening deposit already on an account, if it has one.
    static func existing(in account: Account) -> Transaction? {
        account.transactions.live.first { $0.isOpeningDeposit }
    }

    /// Whether an account of this kind starts with a deposit: bank accounts and investments. Loans and cards start with
    /// what is owed, and property is worth something rather than deposited, so those stay a starting balance.
    static func applies(to type: AccountType) -> Bool {
        (type.group == .checkingSavings && type != .cash) || type.group == .investments
    }

    /// Gives an account its opening deposit, or changes or removes the one it has. An amount of zero or less leaves
    /// no deposit at all.
    @discardableResult
    static func set(_ amount: Decimal, for account: Account, date: Date = .now, in context: ModelContext) -> Transaction? {
        if let current = existing(in: account) {
            if amount > 0 {
                current.amount = amount
                return current
            }
            context.delete(current)
            return nil
        }
        guard amount > 0 else { return nil }
        let deposit = Transaction(account: account, date: date, payee: Transaction.depositName, category: category(in: context),
                                  memo: "Opening balance", amount: amount, paymentType: .bankDeposit)
        deposit.state = .reconciled
        context.insert(deposit)
        return deposit
    }
}
