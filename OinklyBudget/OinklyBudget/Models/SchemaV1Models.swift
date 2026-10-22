import Foundation
import SwiftData

/// The ten models exactly as the 1.0 release stored them. They are only here so an existing 1.0 database can be
/// opened and moved to the current shape. Never change them, and never use them in the app. Everything else works with
/// the models in `OinklyBudgetSchemaV2`.
extension OinklyBudgetSchemaV1 {
    @Model
    final class Account {
        var name: String = ""
        var type: AccountType = AccountType.checking
        var openingBalance: Decimal = 0
        var isClosed: Bool = false
        var isDefault: Bool = false
        var institution: String = ""
        var accountNumber: String = ""
        var routingNumber: String = ""
        var loanPurpose: String = ""
        var originalLoanAmount: Decimal = 0
        var monthlyPayment: Decimal = 0
        var payoffDate: Date?
        var loanStartDate: Date?
        var interestRate: Double = 0
        var creditLimit: Decimal = 0
        var isLease: Bool = false
        var vin: String = ""
        @Attribute(.externalStorage) var photoData: Data?
        var notes: String = ""

        @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
        var transactions: [Transaction] = []
        @Relationship(deleteRule: .cascade, inverse: \Bill.loan)
        var loanBills: [Bill] = []
        @Relationship(deleteRule: .nullify, inverse: \Goal.account)
        var goals: [Goal] = []
        @Relationship(deleteRule: .cascade, inverse: \Holding.account)
        var holdings: [Holding] = []

        init() {}
    }

    @Model
    final class Category {
        var name: String = ""
        var colorHex: String = "8E8E93"
        var symbol: String = "tag"
        var monthlyLimit: Decimal = 0
        var isIncome: Bool = false
        var showOnBudgets: Bool = true
        var systemKey: String?

        @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
        var transactions: [Transaction] = []
        @Relationship(deleteRule: .nullify, inverse: \Payee.lastCategory)
        var payees: [Payee] = []
        @Relationship(deleteRule: .nullify, inverse: \Bill.category)
        var bills: [Bill] = []

        init() {}
    }

    @Model
    final class Transaction {
        var account: Account?
        var date: Date = Date.now
        var payee: String = ""
        var category: Category?
        var memo: String = ""
        var amount: Decimal = 0
        var status: ClearedStatus = ClearedStatus.uncleared
        var transferID: UUID?
        var paymentType: PaymentType?
        var customMethod: CustomPaymentMethod?
        var checkNumber: String = ""
        @Attribute(.externalStorage) var receiptData: Data?
        var noReceipt: Bool = false
        var isBillPayment: Bool = false
        var isAtmWithdrawal: Bool = false
        var paidBill: Bill?
        var paidDueDate: Date?
        var createdAt: Date = Date.now

        init() {}
    }

    @Model
    final class Payee {
        var name: String = ""
        var lastCategory: Category?
        var lastAmount: Decimal = 0

        init() {}
    }

    @Model
    final class Holding {
        var account: Account?
        var name: String = ""
        var symbol: String = ""
        var shares: Decimal = 0
        var price: Decimal = 0
        var costBasis: Decimal = 0
        var priceDate: Date = Date.now
        var createdAt: Date = Date.now

        @Relationship(deleteRule: .cascade, inverse: \HoldingEvent.holding)
        var events: [HoldingEvent] = []

        init() {}
    }

    @Model
    final class HoldingEvent {
        var holding: Holding?
        var date: Date = Date.now
        var shares: Decimal = 0
        var price: Decimal = 0
        var createdAt: Date = Date.now

        init() {}
    }

    @Model
    final class Bill {
        var name: String = ""
        var amount: Decimal = 0
        var frequencyRaw: String = BillFrequency.monthly.rawValue
        var dueDate: Date = Date.now
        var remindDaysBefore: Int = 3
        var remindersOn: Bool = true
        var isImportant: Bool = false
        var notes: String = ""
        var paidDates: [Date] = []
        var category: Category?
        var loan: Account?
        @Attribute(.externalStorage) var photoData: Data?

        @Relationship(deleteRule: .nullify, inverse: \Transaction.paidBill)
        var payments: [Transaction] = []
        var createdAt: Date = Date.now

        init() {}
    }

    @Model
    final class Goal {
        var name: String = ""
        var kindRaw: String = GoalKind.save.rawValue
        var targetAmount: Decimal = 0
        var startingAmount: Decimal = 0
        var goalBalance: Decimal = 0
        var targetDate: Date?
        var symbol: String = "target"
        var colorHex: String = "007AFF"
        var categoryName: String = ""
        var notes: String = ""
        var createdAt: Date = Date.now
        var completedAt: Date?
        var finalAmount: Decimal?
        var account: Account?

        @Relationship(deleteRule: .cascade, inverse: \GoalContribution.goal)
        var contributions: [GoalContribution] = []

        init() {}
    }

    @Model
    final class GoalContribution {
        var goal: Goal?
        var amount: Decimal = 0
        var date: Date = Date.now
        var note: String = ""
        var createdAt: Date = Date.now

        init() {}
    }

    @Model
    final class CustomPaymentMethod {
        var name: String = ""
        var symbol: String = "creditcard"
        var createdAt: Date = Date.now

        @Relationship(deleteRule: .nullify, inverse: \Transaction.customMethod)
        var transactions: [Transaction] = []

        init() {}
    }
}
