import Foundation
import SwiftData

/// One thing an investment account holds: a fund, a stock, a coin. The account's own balance still comes from its
/// transactions; holdings are the breakdown, and changing a price records the difference as a gain or loss.
@Model
final class Holding {
    var account: Account?
    var name: String = ""
    /// Ticker or short label, such as "VTSAX". Optional.
    var symbol: String = ""
    var shares: Decimal = 0
    /// The price of one share as of `priceDate`.
    var price: Decimal = 0
    /// What was paid in total for these shares.
    var costBasis: Decimal = 0
    var priceDate: Date = Date.now
    var createdAt: Date = Date.now

    /// Past shares and prices, used to work out returns over a quarter, six months or a year.
    @Relationship(deleteRule: .cascade, inverse: \HoldingEvent.holding)
    var events: [HoldingEvent] = []

    init(account: Account?, name: String, symbol: String = "", shares: Decimal, price: Decimal, costBasis: Decimal) {
        self.account = account
        self.name = name
        self.symbol = symbol
        self.shares = shares
        self.price = price
        self.costBasis = costBasis
    }

    var marketValue: Decimal { shares * price }

    /// Market value minus what was paid. Not yet realized by selling.
    var gain: Decimal { marketValue - costBasis }

    /// Gain as a fraction of cost. Nil when no cost is recorded.
    var gainFraction: Double? { costBasis > 0 ? (gain / costBasis).doubleValue : nil }

    /// The history in order. A holding with none recorded is treated as starting today's position when it was created.
    var timeline: [(date: Date, shares: Decimal, price: Decimal)] {
        let recorded = events.live.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        if recorded.isEmpty { return [(createdAt, shares, price)] }
        return recorded.map { ($0.date, $0.shares, $0.price) }
    }

    /// "VTSAX" if there is a ticker, otherwise the name.
    var label: String { symbol.isEmpty ? name : symbol }
}
