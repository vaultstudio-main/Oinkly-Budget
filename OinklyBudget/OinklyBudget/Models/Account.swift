import Foundation
import SwiftData

enum AccountGroup: String, CaseIterable, Identifiable {
    case assets, investments, creditCards, checkingSavings, loans

    var id: Self { self }

    var title: String {
        switch self {
        case .assets: "Assets"
        case .investments: "Investments"
        case .creditCards: "Credit Cards"
        case .checkingSavings: "Checking & Savings"
        case .loans: "Mortgages & Loans"
        }
    }

    var isLiability: Bool { self == .creditCards || self == .loans }
}

/// Every kind of account. Stored by raw value, so existing cases must never be renamed.
enum AccountType: String, Codable, CaseIterable, Identifiable {
    // Checking, savings & cash
    case checking, savings, cash, moneyMarket, certificateOfDeposit, healthSavings, flexSpending, prepaidCard, paymentApp
    // Credit cards
    case creditCard, storeCard
    // Loans & debt
    case loan, mortgage, autoLoan, studentLoan, personalLoan, homeEquity, lineOfCredit, businessLoan, vehicleLoan, medicalDebt, otherDebt
    // Investments & retirement
    case investment, brokerage, retirement401k, traditionalIRA, rothIRA, pension, education529, annuity, crypto
    // Property & other assets
    case asset, realEstate, vehicle, valuables, businessAsset

    var id: Self { self }

    var title: String {
        switch self {
        case .checking: "Checking"
        case .savings: "Savings"
        case .cash: "Cash on Hand"
        case .moneyMarket: "Money Market"
        case .certificateOfDeposit: "Certificate of Deposit (CD)"
        case .healthSavings: "Health Savings (HSA)"
        case .flexSpending: "Flexible Spending (FSA)"
        case .prepaidCard: "Prepaid / Debit Card"
        case .paymentApp: "Payment App Balance"
        case .creditCard: "Credit Card"
        case .storeCard: "Store Card"
        case .loan: "Other Loan"
        case .mortgage: "Mortgage"
        case .autoLoan: "Auto Loan"
        case .studentLoan: "Student Loan"
        case .personalLoan: "Personal Loan"
        case .homeEquity: "Home Equity Loan / HELOC"
        case .lineOfCredit: "Line of Credit"
        case .businessLoan: "Business Loan"
        case .vehicleLoan: "Boat / RV / Motorcycle Loan"
        case .medicalDebt: "Medical Debt"
        case .otherDebt: "Other Debt"
        case .investment: "Other Investment"
        case .brokerage: "Brokerage"
        case .retirement401k: "401(k) / 403(b)"
        case .traditionalIRA: "Traditional IRA"
        case .rothIRA: "Roth IRA"
        case .pension: "Pension"
        case .education529: "529 / Education Savings"
        case .annuity: "Annuity"
        case .crypto: "Cryptocurrency"
        case .asset: "Other Asset"
        case .realEstate: "Real Estate"
        case .vehicle: "Vehicle"
        case .valuables: "Collectibles & Valuables"
        case .businessAsset: "Business Asset"
        }
    }

    var symbol: String {
        switch self {
        case .checking: "building.columns"
        case .savings: "banknote"
        case .cash: "dollarsign.circle"
        case .moneyMarket: "percent"
        case .certificateOfDeposit: "lock.doc"
        case .healthSavings: "cross.case"
        case .flexSpending: "heart.text.square"
        case .prepaidCard: "creditcard.and.123"
        case .paymentApp: "iphone"
        case .creditCard: "creditcard"
        case .storeCard: "bag"
        case .loan: "doc.plaintext"
        case .mortgage: "house.and.flag"
        case .autoLoan: "car"
        case .studentLoan: "graduationcap"
        case .personalLoan: "person.crop.circle"
        case .homeEquity: "house"
        case .lineOfCredit: "arrow.triangle.2.circlepath"
        case .businessLoan: "briefcase"
        case .vehicleLoan: "sailboat"
        case .medicalDebt: "cross.circle"
        case .otherDebt: "exclamationmark.circle"
        case .investment: "chart.line.uptrend.xyaxis"
        case .brokerage: "chart.xyaxis.line"
        case .retirement401k: "hourglass"
        case .traditionalIRA: "clock"
        case .rothIRA: "clock.arrow.circlepath"
        case .pension: "figure.stand"
        case .education529: "book"
        case .annuity: "calendar.badge.clock"
        case .crypto: "bitcoinsign.circle"
        case .asset: "shippingbox"
        case .realEstate: "building.2"
        case .vehicle: "car.fill"
        case .valuables: "diamond"
        case .businessAsset: "storefront"
        }
    }

    var blurb: String {
        switch self {
        case .checking: "Everyday spending and bills"
        case .savings: "Money you're setting aside"
        case .cash: "Cash on hand"
        case .moneyMarket: "Higher-interest savings"
        case .certificateOfDeposit: "Fixed-term deposit"
        case .healthSavings: "Tax-free health savings"
        case .flexSpending: "Pre-tax health or dependent care"
        case .prepaidCard: "Prepaid or reloadable card"
        case .paymentApp: "PayPal, Venmo, Cash App, Apple Cash"
        case .creditCard: "Cards you pay off each month"
        case .storeCard: "Retail or store-branded card"
        case .loan: "Any other loan you owe"
        case .mortgage: "Home loan"
        case .autoLoan: "Auto loan or lease"
        case .studentLoan: "Federal or private student debt"
        case .personalLoan: "Unsecured personal loan"
        case .homeEquity: "Borrowing against your home"
        case .lineOfCredit: "Revolving credit line"
        case .businessLoan: "Loan for a business"
        case .vehicleLoan: "Boat, RV, motorcycle or ATV loan"
        case .medicalDebt: "Medical bills and payment plans"
        case .otherDebt: "Money you owe that isn't a loan"
        case .investment: "Any other investment"
        case .brokerage: "Stocks, ETFs and funds"
        case .retirement401k: "Employer retirement plan"
        case .traditionalIRA: "Pre-tax individual retirement"
        case .rothIRA: "After-tax individual retirement"
        case .pension: "Defined-benefit pension"
        case .education529: "College savings plan"
        case .annuity: "Insurance annuity"
        case .crypto: "Bitcoin, Ethereum and others"
        case .asset: "Anything else you own"
        case .realEstate: "Home or other property"
        case .vehicle: "Car, truck, boat or RV value"
        case .valuables: "Jewelry, art, collectibles"
        case .businessAsset: "Equipment or business value"
        }
    }

    var group: AccountGroup {
        switch self {
        case .checking, .savings, .cash, .moneyMarket, .certificateOfDeposit, .healthSavings, .flexSpending, .prepaidCard, .paymentApp:
            .checkingSavings
        case .creditCard, .storeCard:
            .creditCards
        case .loan, .mortgage, .autoLoan, .studentLoan, .personalLoan, .homeEquity, .lineOfCredit, .businessLoan, .vehicleLoan, .medicalDebt, .otherDebt:
            .loans
        case .investment, .brokerage, .retirement401k, .traditionalIRA, .rothIRA, .pension, .education529, .annuity, .crypto:
            .investments
        case .asset, .realEstate, .vehicle, .valuables, .businessAsset:
            .assets
        }
    }
}

extension AccountGroup {
    /// The order groups are listed when choosing an account type.
    static let setupOrder: [AccountGroup] = [.checkingSavings, .creditCards, .loans, .investments, .assets]

    var accountTypes: [AccountType] { AccountType.allCases.filter { $0.group == self } }
}

@Model
final class Account {
    var name: String = ""
    var type: AccountType = AccountType.checking
    var openingBalance: Decimal = 0
    var isClosed: Bool = false
    /// The built-in Cash on Hand. There is exactly one, and it can't be deleted.
    var isDefault: Bool = false
    var institution: String = ""
    var accountNumber: String = ""
    /// Checking accounts only: the ordinary (ACH) routing number. The wire and digital numbers have their own fields
    /// further down.
    var routingNumber: String = ""
    /// For loan accounts: what the loan is for, such as "2021 Honda Civic" or "123 Main St".
    var loanPurpose: String = ""
    /// For loans: the amount originally borrowed.
    var originalLoanAmount: Decimal = 0
    /// For loans: the regular payment each month.
    var monthlyPayment: Decimal = 0
    /// For loans: the date the loan matures, when the last payment is due. Chosen by you.
    var payoffDate: Date?
    /// For loans: the day the loan started.
    var loanStartDate: Date?
    /// For loans: the yearly interest rate as a percent, such as 6.5.
    var interestRate: Double = 0
    /// For credit cards: the most you can charge. Zero means not set.
    var creditLimit: Decimal = 0
    /// For auto accounts: a lease instead of a loan. Only counts for the auto type, so use `isLeased`.
    var isLease: Bool = false
    /// Vehicle identification number, for car, boat/RV and vehicle accounts.
    var vin: String = ""
    /// A picture of the car, house or other item. Kept out of the main database file.
    @Attribute(.externalStorage) var photoData: Data?
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    /// The bill a loan adds to Bills when you give it a payment due date. At most one. Deleted with the loan.
    @Relationship(deleteRule: .cascade, inverse: \Bill.loan)
    var loanBills: [Bill] = []

    /// Goals that track this account's balance.
    @Relationship(deleteRule: .nullify, inverse: \Goal.account)
    var goals: [Goal] = []

    /// What an investment account holds. Empty for every other kind of account.
    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    var holdings: [Holding] = []

    /// The account pinned under Cash on Hand and labelled Primary Checking. Only a checking account, and at most one.
    var isPrimaryChecking: Bool = false
    /// Checking accounts only: the wire transfer number (it may contain letters) and the digital bank's number.
    /// `routingNumber` is the ordinary (ACH) one.
    var wireRoutingNumber: String = ""
    var digitalRoutingNumber: String = ""

    /// Repeating transactions that add to this account. Deleted with it.
    @Relationship(deleteRule: .cascade, inverse: \RecurringTransaction.account)
    var recurringRules: [RecurringTransaction] = []

    init(name: String, type: AccountType, openingBalance: Decimal = 0) {
        self.name = name
        self.type = type
        self.openingBalance = openingBalance
    }

    /// Credit cards and loans are debts; everything else is an asset.
    var isDebt: Bool { type.group.isLiability }

    /// Real US account numbers are at most 17 digits and routing numbers are exactly 9.
    static let maxAccountNumberLength = 17
    /// Keeps names short enough for the sidebar and menu.
    static let maxNameLength = 30
    static let routingNumberLength = 9

    /// Letters and digits only (some wire numbers contain letters), cut to nine characters.
    static func routingCharacters(_ text: String) -> String {
        String(text.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(routingNumberLength))
    }

    /// Only checking accounts have routing numbers.
    var hasRoutingNumbers: Bool { type == .checking }

    /// The ordinary (ACH) routing number, the wire transfer number and the digital bank's number.
    var achRouting: String {
        get { routingNumber }
        set { routingNumber = Account.digits(newValue, limit: Account.routingNumberLength) }
    }
    /// The wire number can contain letters, so it is kept to letters and digits.
    var wireRouting: String {
        get { wireRoutingNumber }
        set { wireRoutingNumber = Account.routingCharacters(newValue) }
    }
    var digitalRouting: String {
        get { digitalRoutingNumber }
        set { digitalRoutingNumber = Account.digits(newValue, limit: Account.routingNumberLength) }
    }
    /// Card numbers run 15 digits (Amex) to 16 (most cards), and up to 19 on some.
    static let maxCardNumberLength = 19

    /// The most digits the stored number may have for an account type.
    static func numberLimit(for type: AccountType) -> Int {
        type.group == .creditCards ? maxCardNumberLength : maxAccountNumberLength
    }

    /// Digits only, cut to `limit`.
    static func digits(_ text: String, limit: Int) -> String { String(text.filter(\.isNumber).prefix(limit)) }

    /// Only investment accounts (401(k), IRA, brokerage, crypto and so on) have holdings.
    var supportsHoldings: Bool { type.group == .investments }

    /// An auto account set up as a lease rather than a loan.
    var isLeased: Bool { type == .autoLoan && isLease }

    /// "Auto Lease" for a leased car, otherwise the account type's own name.
    var typeTitle: String { isLeased ? "Auto Lease" : type.title }

    /// Who you owe: the lender, or the leasing company for a lease.
    var lenderLabel: String { isLeased ? "Leasing Company" : "Lender" }

    /// "Loan", or "Lease" for a leased car.
    var financingWord: String { isLeased ? "Lease" : "Loan" }

    /// Checking accounts, cash on hand and credit cards keep receipt photos and PDF bills. A card's payments never have one.
    var supportsReceipts: Bool { type == .checking || type == .cash || type.group == .creditCards }

    /// The physical cash you carry. It has no bank details, and every transaction in it is a cash transaction.
    var isCashOnHand: Bool { type == .cash }

    /// The payment method every ordinary transaction in this account has, when it can't be anything else:
    /// Credit Card on a card, Cash on cash on hand. Nil for accounts where you choose.
    var lockedPaymentType: PaymentType? {
        if isCreditCard { return .creditCard }
        if isCashOnHand { return .cash }
        return nil
    }

    /// Credit and store cards keep a card number, where other accounts keep an account number and routing number.
    var isCreditCard: Bool { type.group == .creditCards }

    /// For a card with a limit set: what is left to spend. Never negative.
    var availableCredit: Decimal { max(creditLimit + balance, 0) }

    /// True when a card has a limit and adding `change` (negative for a charge) would take what you owe past the limit.
    /// Owing exactly the limit is the most a card can hold. Payments and deposits never count, so a card already over its
    /// limit can still be paid down.
    func wouldExceedLimit(adding change: Decimal) -> Bool {
        isCreditCard && creditLimit > 0 && change < 0 && -(balance + change) > creditLimit
    }

    /// What to say when a charge is refused.
    var limitMessage: String { "Invalid transaction: it exceeds the credit limit on \(name)." }

    /// "Card Number" for cards, otherwise "Account Number".
    var numberLabel: String { isCreditCard ? "Card Number" : "Account Number" }

    /// Loans are the only accounts that say what they are for.
    var isLoan: Bool { type.group == .loans }

    /// "•••• 1234", or an empty string if no account number is stored.
    var maskedAccountNumber: String {
        let digits = accountNumber.filter { !$0.isWhitespace }
        guard !digits.isEmpty else { return "" }
        return "•••• " + digits.suffix(4)
    }

    var balance: Decimal { balance(asOf: .distantFuture) }

    /// The balance at the end of `date`. With thousands of transactions this would be slow to add up every time a
    /// page asks, so a sorted running total is kept per account and reused until something is saved.
    func balance(asOf date: Date) -> Decimal {
        guard isLive else { return 0 }
        if LedgerIndex.shared.preferLatest, let snapshot = LedgerIndex.shared.latest {
            return openingBalance + snapshot.total(for: persistentModelID, asOf: date)
        }
        // Unsaved edits are not in the cache, so while there are any, add everything up directly.
        guard let context = modelContext, !context.hasChanges else {
            return transactions.live.reduce(openingBalance) { $1.date <= date ? $0 + $1.amount : $0 }
        }
        if let snapshot = LedgerIndex.shared.fresh {
            return openingBalance + snapshot.total(for: persistentModelID, asOf: date)
        }
        return openingBalance + BalanceCache.total(for: self, asOf: date)
    }
}
