import Foundation
import SwiftData

/// A memorized payee: remembers the category and amount of its last use.
@Model
final class Payee {
    var name: String = ""
    var lastCategory: Category?
    /// Signed like `Transaction.amount`: payments are negative.
    var lastAmount: Decimal = 0

    init(name: String, lastCategory: Category? = nil, lastAmount: Decimal = 0) {
        self.name = name
        self.lastCategory = lastCategory
        self.lastAmount = lastAmount
    }
}
