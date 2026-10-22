import Foundation
import SwiftData

/// Keeps an investment account's balance in step with its holdings. Price changes and manual value updates
/// become gain or loss transactions in the Investment Gains category, so the Investments report counts them as growth.
enum HoldingsLedger {
    enum Funding: String, CaseIterable, Identifiable {
        case alreadyInAccount, fromAccount, outside
        var id: Self { self }
        var title: String {
            switch self {
            case .alreadyInAccount: "Already in this account"
            case .fromAccount: "Moved from another account"
            case .outside: "Deposited from outside"
            }
        }
    }

    struct Summary {
        var marketValue: Decimal = 0
        var costBasis: Decimal = 0
        var accountValue: Decimal = 0

        var gain: Decimal { marketValue - costBasis }
        var gainFraction: Double? { costBasis > 0 ? (gain / costBasis).doubleValue : nil }
        /// Account balance not accounted for by a holding: cash, or value you haven't broken out yet.
        var unallocated: Decimal { accountValue - marketValue }
    }

    static func summary(for account: Account) -> Summary {
        var result = Summary(accountValue: account.balance)
        for holding in account.holdings.live {
            result.marketValue += holding.marketValue
            result.costBasis += holding.costBasis
        }
        return result
    }

    static let growthKey = "investment-gains"

    private static func growthCategory(in context: ModelContext) -> Category? {
        let key = growthKey
        return try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.systemKey == key })).first
    }

    /// A gain (positive) or loss (negative) on the account's balance.
    @discardableResult
    static func recordGrowth(_ amount: Decimal, payee: String, account: Account, date: Date = .now, in context: ModelContext) -> Transaction? {
        guard amount != 0 else { return nil }
        let transaction = Transaction(account: account, date: date, payee: payee, category: growthCategory(in: context), amount: amount)
        context.insert(transaction)
        return transaction
    }

    /// Sets a holding's price. The change in its market value is recorded as growth on the account.
    static func updatePrice(_ holding: Holding, to newPrice: Decimal, date: Date = .now, in context: ModelContext) {
        guard let account = holding.account else { return }
        let change = holding.shares * (newPrice - holding.price)
        holding.price = newPrice
        holding.priceDate = date
        recordEvent(holding, date: date, in: context)
        recordGrowth(change, payee: "Price update: \(holding.label)", account: account, date: date, in: context)
    }

    /// Notes the holding's current shares and price in its history.
    private static func recordEvent(_ holding: Holding, date: Date, in context: ModelContext) {
        context.insert(HoldingEvent(holding: holding, date: date, shares: holding.shares, price: holding.price))
    }

    /// Sets the whole account's value by hand. The difference is recorded as growth.
    static func setAccountValue(_ account: Account, to value: Decimal, date: Date = .now, in context: ModelContext) {
        recordGrowth(value - account.balance, payee: "Value update", account: account, date: date, in: context)
    }

    /// Adds a holding. `.fromAccount` moves its value in from `source` as a transfer, so it isn't counted as income
    /// or spending. `.outside` deposits it as a contribution. `.alreadyInAccount` changes no balance.
    @discardableResult
    static func add(
        to account: Account, name: String, symbol: String, shares: Decimal, price: Decimal, costBasis: Decimal?,
        funding: Funding, source: Account? = nil, date: Date = .now, in context: ModelContext
    ) -> Holding {
        let holding = Holding(account: account, name: name, symbol: symbol, shares: shares, price: price,
                              costBasis: costBasis ?? shares * price)
        holding.priceDate = date
        context.insert(holding)
        recordEvent(holding, date: date, in: context)
        let value = holding.marketValue
        if value > 0 {
            switch funding {
            case .alreadyInAccount:
                break
            case .fromAccount:
                if let source, source.persistentModelID != account.persistentModelID {
                    Transfers.move(from: source, to: account, amount: value, date: date,
                                   payeeOut: "Transfer to \(account.name)", payeeIn: "Bought \(holding.label)", in: context)
                }
            case .outside:
                context.insert(Transaction(account: account, date: date, payee: "Added \(holding.label)", amount: value))
            }
        }
        return holding
    }

    /// Edits the details. A new price goes through `updatePrice`, so the account value follows it.
    static func edit(
        _ holding: Holding, name: String, symbol: String, shares: Decimal, price: Decimal, costBasis: Decimal,
        date: Date = .now, in context: ModelContext
    ) {
        if price != holding.price { updatePrice(holding, to: price, date: date, in: context) }
        let sharesChanged = shares != holding.shares
        holding.name = name
        holding.symbol = symbol
        holding.shares = shares
        holding.costBasis = costBasis
        if sharesChanged { recordEvent(holding, date: date, in: context) }
    }
}
