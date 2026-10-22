import Foundation
import SwiftData

/// A memorized payee: remembers the category and amount of its last use.
@Model
final class Payee {
    var name: String = ""
    var lastCategory: Category?
    /// Signed like `Transaction.amount`: payments are negative.
    var lastAmount: Decimal = 0
    /// The memo and payment method of the last transaction, so the next one can be filled in the same way. The method
    /// is a `PaymentType` raw value, or "custom:" and the name of one of your own methods.
    var lastMemo: String = ""
    var lastMethodRaw: String = ""

    init(name: String, lastCategory: Category? = nil, lastAmount: Decimal = 0) {
        self.name = name
        self.lastCategory = lastCategory
        self.lastAmount = lastAmount
    }
}
