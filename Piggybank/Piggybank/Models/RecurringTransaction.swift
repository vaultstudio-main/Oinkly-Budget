import Foundation
import SwiftData

/// A transaction that repeats, such as a paycheque or rent. On each due date it can add a pending transaction for you
/// to confirm. The transactions it made are kept with it.
@Model
final class RecurringTransaction {
    var payee: String = ""
    var account: Account?
    var category: Category?
    var memo: String = ""
    /// Signed: money going out is negative.
    var amount: Decimal = 0
    /// A `PaymentType` raw value, or empty.
    var paymentTypeRaw: String = ""
    /// A `BillFrequency` raw value. Never rename those cases.
    var frequencyRaw: String = BillFrequency.monthly.rawValue
    /// The first due date. Later ones are worked out from it.
    var startDate: Date = Date.now
    var endDate: Date?
    /// The next date nothing has been added for yet.
    var nextDate: Date = Date.now
    /// Add a pending transaction automatically on each due date. When false it is only a reminder.
    var autoEnter: Bool = true
    var isActive: Bool = true
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurring)
    var transactions: [Transaction] = []

    init(payee: String, account: Account?, category: Category?, amount: Decimal, frequency: BillFrequency, startDate: Date) {
        self.payee = payee
        self.account = account
        self.category = category
        self.amount = amount
        self.frequencyRaw = frequency.rawValue
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.nextDate = Calendar.current.startOfDay(for: startDate)
    }

    var frequency: BillFrequency {
        get { BillFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }
}
