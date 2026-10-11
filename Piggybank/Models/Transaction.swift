import Foundation
import SwiftData

/// Stored by raw value, so existing cases must never be renamed.
/// `uncleared` is shown as Unreconciled, and the older `cleared` is shown as Reconciled.
enum ClearedStatus: String, Codable {
    case uncleared, cleared, reconciled, pending
}

/// What you see and choose: still pending at the bank, not yet checked off, or matched to a statement.
enum ReconcileState: String, CaseIterable, Identifiable {
    case pending, unreconciled, reconciled

    var id: Self { self }

    var title: String {
        switch self {
        case .pending: "Pending"
        case .unreconciled: "Unreconciled"
        case .reconciled: "Reconciled"
        }
    }

    var symbol: String {
        switch self {
        case .pending: "clock.fill"
        case .unreconciled: "circle"
        case .reconciled: "checkmark.circle.fill"
        }
    }
}

enum PaymentGroup: String, CaseIterable, Identifiable {
    case cash, cards, bank, digital, credit, other

    var id: Self { self }

    var title: String {
        switch self {
        case .cash: "Cash & Checks"
        case .cards: "Cards"
        case .bank: "Bank"
        case .digital: "Digital & Mobile"
        case .credit: "Credit & Rewards"
        case .other: "Other"
        }
    }

    var types: [PaymentType] { PaymentType.allCases.filter { $0.group == self } }
}

/// Every way money can move. Stored by raw value, so existing cases must never be renamed.
enum PaymentType: String, Codable, CaseIterable, Identifiable {
    // Cash & checks
    case cash, atm, atmDeposit, check, cashiersCheck, moneyOrder, travelersCheck, mobileCheckDeposit
    // Cards
    case debitCard, creditCard, prepaidCard, giftCard, storeCard
    // Bank
    case bankTransfer, wire, directDeposit, directDebit, billPay, autoPay, payrollDeduction
    // Digital & mobile
    case onlinePayment, mobilePay, applePay, googlePay, samsungPay, paypal, venmo, cashApp, zelle, appleCash, alipay, wechatPay, crypto
    // Credit & rewards
    case buyNowPayLater, installmentPlan, storeCredit, rewardsPoints
    // Other
    case barter, other

    var id: Self { self }

    var group: PaymentGroup {
        switch self {
        case .cash, .atm, .atmDeposit, .check, .cashiersCheck, .moneyOrder, .travelersCheck, .mobileCheckDeposit: .cash
        case .debitCard, .creditCard, .prepaidCard, .giftCard, .storeCard: .cards
        case .bankTransfer, .wire, .directDeposit, .directDebit, .billPay, .autoPay, .payrollDeduction: .bank
        case .onlinePayment, .mobilePay, .applePay, .googlePay, .samsungPay, .paypal, .venmo, .cashApp, .zelle, .appleCash, .alipay, .wechatPay, .crypto: .digital
        case .buyNowPayLater, .installmentPlan, .storeCredit, .rewardsPoints: .credit
        case .barter, .other: .other
        }
    }

    var title: String {
        switch self {
        case .cash: "Cash"
        case .atm: "ATM Withdrawal"
        case .atmDeposit: "ATM Deposit"
        case .check: "Check"
        case .cashiersCheck: "Cashier's Check"
        case .moneyOrder: "Money Order"
        case .travelersCheck: "Traveler's Check"
        case .mobileCheckDeposit: "Mobile Check Deposit"
        case .debitCard: "Debit Card"
        case .creditCard: "Credit Card"
        case .prepaidCard: "Prepaid Card"
        case .giftCard: "Gift Card"
        case .storeCard: "Store Card"
        case .bankTransfer: "Bank Transfer (ACH)"
        case .wire: "Wire Transfer"
        case .directDeposit: "Direct Deposit"
        case .directDebit: "Direct Debit"
        case .billPay: "Bill Pay"
        case .autoPay: "Auto-Pay"
        case .payrollDeduction: "Payroll Deduction"
        case .onlinePayment: "Online Payment"
        case .mobilePay: "Mobile Pay"
        case .applePay: "Apple Pay"
        case .googlePay: "Google Pay"
        case .samsungPay: "Samsung Pay"
        case .paypal: "PayPal"
        case .venmo: "Venmo"
        case .cashApp: "Cash App"
        case .zelle: "Zelle"
        case .appleCash: "Apple Cash"
        case .alipay: "Alipay"
        case .wechatPay: "WeChat Pay"
        case .crypto: "Cryptocurrency"
        case .buyNowPayLater: "Buy Now, Pay Later"
        case .installmentPlan: "Installment Plan"
        case .storeCredit: "Store Credit"
        case .rewardsPoints: "Rewards Points"
        case .barter: "Barter / Trade"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .cash: "dollarsign.circle"
        case .atm: "banknote"
        case .atmDeposit: "arrow.down.to.line"
        case .check: "doc.text"
        case .cashiersCheck: "doc.text.fill"
        case .moneyOrder: "envelope"
        case .travelersCheck: "airplane.departure"
        case .mobileCheckDeposit: "camera"
        case .debitCard: "creditcard"
        case .creditCard: "creditcard.fill"
        case .prepaidCard: "creditcard.and.123"
        case .giftCard: "giftcard"
        case .storeCard: "bag"
        case .bankTransfer: "arrow.left.arrow.right"
        case .wire: "bolt.horizontal"
        case .directDeposit: "tray.and.arrow.down"
        case .directDebit: "tray.and.arrow.up"
        case .billPay: "calendar.badge.clock"
        case .autoPay: "repeat"
        case .payrollDeduction: "minus.circle"
        case .onlinePayment: "globe"
        case .mobilePay: "iphone"
        case .applePay: "apple.logo"
        case .googlePay: "g.circle"
        case .samsungPay: "s.circle"
        case .paypal: "p.circle"
        case .venmo: "v.circle"
        case .cashApp: "dollarsign.square"
        case .zelle: "z.circle"
        case .appleCash: "applelogo"
        case .alipay: "a.circle"
        case .wechatPay: "message"
        case .crypto: "bitcoinsign.circle"
        case .buyNowPayLater: "clock.arrow.circlepath"
        case .installmentPlan: "calendar"
        case .storeCredit: "tag"
        case .rewardsPoints: "star.circle"
        case .barter: "arrow.triangle.swap"
        case .other: "ellipsis.circle"
        }
    }
}

@Model
final class Transaction {
    var account: Account?
    var date: Date = Date.now
    var payee: String = ""
    var category: Category?
    var memo: String = ""
    /// Signed: deposits are positive, payments are negative.
    var amount: Decimal = 0
    var status: ClearedStatus = ClearedStatus.uncleared
    /// Both halves of a transfer, such as a loan payment, share one ID. Nil for ordinary transactions.
    var transferID: UUID?
    var paymentType: PaymentType?
    /// One of your own payment methods. Used instead of `paymentType`, never together with it.
    var customMethod: CustomPaymentMethod?
    var checkNumber: String = ""
    /// A photo or PDF of the receipt or bill. Kept out of the main database file.
    @Attribute(.externalStorage) var receiptData: Data?
    /// Marked as having no receipt, so the register stops offering to add one.
    var noReceipt: Bool = false
    /// Paid with Pay a Bill. These always use the Payment category.
    var isBillPayment: Bool = false
    /// Either half of an ATM withdrawal. These use the Payment category, like bill and debt payments.
    var isAtmWithdrawal: Bool = false
    /// The bill this payment settled, and the due date it settled. Deleting the payment marks that due date unpaid again.
    var paidBill: Bill?
    var paidDueDate: Date?
    /// Breaks ties between transactions on the same date.
    var createdAt: Date = Date.now

    init(account: Account?, date: Date = .now, payee: String = "", category: Category? = nil, memo: String = "", amount: Decimal, paymentType: PaymentType? = nil) {
        self.account = account
        self.date = date
        self.payee = payee
        self.category = category
        self.memo = memo
        self.amount = amount
        self.paymentType = paymentType
    }
}

extension Transaction {
    var state: ReconcileState {
        get {
            // A transaction deleted a moment ago can still be on screen. Reading a deleted object is fatal.
            guard isLive else { return .unreconciled }
            switch status {
            case .pending: return .pending
            case .uncleared: return .unreconciled
            case .cleared, .reconciled: return .reconciled
            }
        }
        set {
            switch newValue {
            case .pending: status = .pending
            case .unreconciled: status = .uncleared
            case .reconciled: status = .reconciled
            }
        }
    }

    /// Matched to a statement.
    var isReconciled: Bool { state == .reconciled }

    var isTransfer: Bool { isLive && transferID != nil }

    /// A payment toward a loan, mortgage or card: either side of the pair a payment creates.
    var isDebtPayment: Bool {
        isLive && isTransfer && (account?.isDebt == true || payee.hasPrefix("Payment to ") || payee.hasPrefix("Payment from "))
    }

    /// The category a transfer shows. Payments to loans and cards are always "Payment", and other transfers "Transfer".
    /// Neither can be changed. Nil for ordinary transactions, which have a category you choose.
    var fixedCategoryTitle: String? {
        guard isLive else { return nil }
        if isAtmWithdrawal { return "ATM" }
        if isDebtPayment { return "Payment" }
        // A bill's payment is always locked to its category, or to Payment when the bill has none.
        if isBillPayment { return category?.isLive == true ? category?.name : "Payment" }
        return isTransfer ? "Transfer" : nil
    }

    /// A payment made toward a credit card, as seen on the card. These never have a receipt, and it can't be added.
    var receiptLocked: Bool {
        guard isLive else { return false }
        // ATM withdrawals never have a receipt, on either side. Card payments never do either.
        if isAtmWithdrawal { return true }
        return isDebtPayment && account?.isLive == true && account?.isDebt == true
    }

    /// The attachment is a PDF rather than a photo.
    var receiptIsPDF: Bool {
        guard isLive, let data = receiptData else { return false }
        return data.prefix(4) == Data("%PDF".utf8)
    }
}
