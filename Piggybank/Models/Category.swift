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
