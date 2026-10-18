import Foundation
import SwiftData

/// One part of a split transaction: how much of it went to which category. The parts of a transaction add up to its
/// amount. A transaction with no splits has just its own category.
@Model
final class TransactionSplit {
    var transaction: Transaction?
    var category: Category?
    /// Signed like the transaction: a payment's parts are negative.
    var amount: Decimal = 0
    var memo: String = ""
    /// Keeps the parts in the order they were entered.
    var order: Int = 0
    var createdAt: Date = Date.now

    init(transaction: Transaction?, category: Category?, amount: Decimal, memo: String = "", order: Int = 0) {
        self.transaction = transaction
        self.category = category
        self.amount = amount
        self.memo = memo
        self.order = order
    }
}
