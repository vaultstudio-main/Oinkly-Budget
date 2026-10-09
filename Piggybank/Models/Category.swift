import Foundation
import SwiftData

@Model
final class Category {
    var name: String
    var colorHex: String
    var symbol: String
    var monthlyLimit: Decimal
    var isIncome: Bool = false
    /// Whether this budget appears on Home, the Budgets tab and the Summary. Changed in Settings.
    var showOnBudgets: Bool = true
    /// Stable identifier for built-in categories. The same on every device and every launch.
    var systemKey: String?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .nullify, inverse: \Payee.lastCategory)
    var payees: [Payee] = []

    init(name: String, colorHex: String, symbol: String, monthlyLimit: Decimal, isIncome: Bool = false, systemKey: String? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.monthlyLimit = monthlyLimit
        self.isIncome = isIncome
        self.systemKey = systemKey
    }

    /// Built-in categories can't be renamed, restyled or deleted. Only their budget amount changes.
    var isSystem: Bool { systemKey != nil }
}

extension Array where Element == Category {
    /// Expense categories first, then income categories, each in the existing order.
    var expensesFirst: [Category] { filter { !$0.isIncome } + filter { $0.isIncome } }
}
