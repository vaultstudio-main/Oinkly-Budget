import Foundation
import SwiftData

/// One entry in a holding's history: how many shares it had and at what price, from this date on.
/// A new one is recorded when a holding is added, when its price changes and when its share count changes.
@Model
final class HoldingEvent {
    var holding: Holding?
    var date: Date = Date.now
    var shares: Decimal = 0
    var price: Decimal = 0
    /// Breaks ties between events on the same date.
    var createdAt: Date = Date.now

    init(holding: Holding?, date: Date, shares: Decimal, price: Decimal) {
        self.holding = holding
        self.date = date
        self.shares = shares
        self.price = price
    }
}
