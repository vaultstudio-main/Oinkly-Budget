import Foundation
import SwiftData

@Model
final class Category {
    var name: String = ""
    var colorHex: String = "8E8E93"
    var symbol: String = "tag"
    var monthlyLimit: Decimal = 0
    var isIncome: Bool = false
    /// Whether this budget appears on Home, the Budgets tab and the Summary. Changed in Settings.
    var showOnBudgets: Bool = true
    /// Stable identifier for built-in categories. The same on every device and every launch.
    var systemKey: String?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .nullify, inverse: \Payee.lastCategory)
    var payees: [Payee] = []

    /// Bills that are tracked under this category.
    @Relationship(deleteRule: .nullify, inverse: \Bill.category)
    var bills: [Bill] = []

    /// Spending here counts toward the tax-related report. Set by you.
    var isTaxRelated: Bool = false

    /// Parts of split transactions that went to this category.
    @Relationship(deleteRule: .nullify, inverse: \TransactionSplit.category)
    var splits: [TransactionSplit] = []

    /// Repeating transactions that use this category.
    @Relationship(deleteRule: .nullify, inverse: \RecurringTransaction.category)
    var recurringRules: [RecurringTransaction] = []

    init(name: String, colorHex: String, symbol: String, monthlyLimit: Decimal, isIncome: Bool = false, systemKey: String? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.monthlyLimit = monthlyLimit
        self.isIncome = isIncome
        self.systemKey = systemKey
    }

    static let customKeyPrefix = "custom-"

    /// A budget the user made themselves, such as "Civic Fuel". It keeps a key so the launch-time cleanup of
    /// stray categories leaves it alone, but unlike built-in categories it can be renamed and deleted.
    var isCustom: Bool { systemKey?.hasPrefix(Category.customKeyPrefix) == true }
}
