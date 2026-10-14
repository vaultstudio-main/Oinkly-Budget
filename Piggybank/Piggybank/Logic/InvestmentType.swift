import Foundation

/// What a transaction in an investment account is. It is worked out from the amount and category, and choosing
/// one sets the sign and category for you, so the Investments report always counts it the right way.
enum InvestmentType: String, CaseIterable, Identifiable {
    case contribution, withdrawal, gain, loss, dividend, fee

    var id: Self { self }

    var title: String {
        switch self {
        case .contribution: "Contribution"
        case .withdrawal: "Withdrawal"
        case .gain: "Gain"
        case .loss: "Loss"
        case .dividend: "Dividend / Interest"
        case .fee: "Fee"
        }
    }

    var symbol: String {
        switch self {
        case .contribution: "arrow.down.circle"
        case .withdrawal: "arrow.up.circle"
        case .gain: "chart.line.uptrend.xyaxis"
        case .loss: "chart.line.downtrend.xyaxis"
        case .dividend: "percent"
        case .fee: "minus.circle"
        }
    }

    var colorHex: String {
        switch self {
        case .contribution: "007AFF"
        case .withdrawal: "FF9500"
        case .gain: "34C759"
        case .loss: "FF3B30"
        case .dividend: "5AC8FA"
        case .fee: "8E8E93"
        }
    }

    /// Money (or value) leaves the account.
    var isOutflow: Bool { self == .withdrawal || self == .loss || self == .fee }

    /// The built-in category behind this type. Contributions and withdrawals have none.
    var categoryKey: String? {
        switch self {
        case .contribution, .withdrawal: nil
        case .gain, .loss: "investment-gains"
        case .dividend: "interest-dividends"
        case .fee: "investment-fees"
        }
    }

    /// Whether this counts as growth in the Investments report, as opposed to money moved in or out.
    var isGrowth: Bool { categoryKey != nil }

    static func of(_ transaction: Transaction) -> InvestmentType {
        let inflow = transaction.amount >= 0
        if transaction.isTransfer { return inflow ? .contribution : .withdrawal }
        switch transaction.category?.systemKey {
        case "investment-gains": return inflow ? .gain : .loss
        case "interest-dividends": return inflow ? .dividend : .fee
        case "investment-fees": return inflow ? .gain : .fee
        default: return inflow ? .contribution : .withdrawal
        }
    }

    func category(in categories: [Category]) -> Category? {
        categoryKey.flatMap { key in categories.first { $0.systemKey == key } }
    }

    /// Sets the transaction's category and the sign of its amount. The size of the amount is kept.
    func apply(to transaction: Transaction, categories: [Category]) {
        let size = abs(transaction.amount)
        transaction.amount = isOutflow ? -size : size
        transaction.category = category(in: categories)
    }
}
