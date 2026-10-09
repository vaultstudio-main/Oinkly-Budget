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
        case .cash: "Cash"
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
        case .autoLoan: "Car Loan"
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
        case .autoLoan: "Car or truck loan or lease"
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
    var name: String
    var type: AccountType
    var openingBalance: Decimal
    var isClosed: Bool = false
    var institution: String = ""
    var accountNumber: String = ""
    var routingNumber: String = ""
    /// For loan accounts: what the loan is for, such as "2021 Honda Civic" or "123 Main St".
    var loanPurpose: String = ""
    /// For loans: the amount originally borrowed.
    var originalLoanAmount: Decimal = 0
    /// For loans: the regular payment each month.
    var monthlyPayment: Decimal = 0
    /// For loans: the date you plan to have it paid off, chosen by you.
    var payoffDate: Date?
    /// Vehicle identification number, for car, boat/RV and vehicle accounts.
    var vin: String = ""
    /// A picture of the car, house or other item. Kept out of the main database file.
    @Attribute(.externalStorage) var photoData: Data?
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    init(name: String, type: AccountType, openingBalance: Decimal = 0) {
        self.name = name
        self.type = type
        self.openingBalance = openingBalance
    }

    /// Credit cards and loans are debts; everything else is an asset.
    var isDebt: Bool { type.group.isLiability }

    /// Real US account numbers are at most 17 digits and routing numbers are exactly 9.
    static let maxAccountNumberLength = 17
    static let routingNumberLength = 9

    /// Digits only, cut to `limit`.
    static func digits(_ text: String, limit: Int) -> String { String(text.filter(\.isNumber).prefix(limit)) }

    /// Loans are the only accounts that say what they are for.
    var isLoan: Bool { type.group == .loans }

    /// "•••• 1234", or an empty string if no account number is stored.
    var maskedAccountNumber: String {
        let digits = accountNumber.filter { !$0.isWhitespace }
        guard !digits.isEmpty else { return "" }
        return "•••• " + digits.suffix(4)
    }

    var balance: Decimal { balance(asOf: .distantFuture) }

    func balance(asOf date: Date) -> Decimal {
        transactions.reduce(openingBalance) { $1.date <= date ? $0 + $1.amount : $0 }
    }
}
