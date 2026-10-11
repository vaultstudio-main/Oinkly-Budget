import Foundation
import SwiftData

/// How retirement, brokerage and other investment accounts did over a quarter, six months or a year.
///
/// Growth is what you record as a Gain, Loss, Dividend or Fee (the Investment Gains, Interest & Dividends and
/// Investment Fees categories). Every other deposit or withdrawal counts as a contribution, so adding money never
/// looks like a gain. The return is time-weighted by when each contribution arrived (the Modified Dietz method).
enum Investments {
    static let growthKeys: Set<String> = ["interest-dividends", "investment-gains", "investment-fees"]

    struct Line: Identifiable {
        let id: Account.ID
        let name: String
        let typeTitle: String
        let symbol: String
        let start: Decimal
        let end: Decimal
        let contributions: Decimal
        let growth: Decimal
        let returnRate: Double?

        var change: Decimal { end - start }
    }

    /// One holding's results over the period, from its recorded price and share history.
    struct HoldingLine: Identifiable {
        let id: Holding.ID
        let name: String
        let label: String
        let accountName: String
        let start: Decimal
        let end: Decimal
        /// What the price moving did to the value.
        let growth: Decimal
        /// Money put in or taken out by buying or selling shares.
        let contributions: Decimal
        let returnRate: Double?

        var change: Decimal { end - start }
    }

    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    struct Report {
        let range: ReportRange
        let lines: [Line]
        let holdings: [HoldingLine]
        let points: [Point]
        let start: Decimal
        let end: Decimal
        let contributions: Decimal
        let growth: Decimal
        let returnRate: Double?

        var change: Decimal { end - start }
    }

    static func isGrowth(_ transaction: Transaction) -> Bool {
        !transaction.isTransfer && transaction.category?.systemKey.map(growthKeys.contains) == true
    }

    /// Modified Dietz: growth divided by the starting value plus each contribution weighted by how long it was invested.
    private static func rate(growth: Decimal, start: Decimal, weightedFlows: Double) -> Double? {
        let base = start.doubleValue + weightedFlows
        return base > 0 ? growth.doubleValue / base : nil
    }

    static func build(_ accounts: [Account], range: ReportRange, now: Date = .now, calendar: Calendar = .current) -> Report {
        let end = Trend.endDate(range, now: now)
        let before = Trend.startDate(range)
        let length = max(end.timeIntervalSince(range.start), 1)

        var lines: [Line] = []
        var totalWeighted = 0.0
        var totals = (start: Decimal(0), end: Decimal(0), contributions: Decimal(0), growth: Decimal(0))

        let investments = accounts.live.filter { $0.type.group == .investments }
        for account in investments {
            var contributions: Decimal = 0
            var growth: Decimal = 0
            var weighted = 0.0
            for transaction in account.transactions where transaction.isLive && transaction.date >= range.start && transaction.date <= end {
                if isGrowth(transaction) {
                    growth += transaction.amount
                } else {
                    contributions += transaction.amount
                    weighted += transaction.amount.doubleValue * max(end.timeIntervalSince(transaction.date), 0) / length
                }
            }
            let start = account.balance(asOf: before)
            lines.append(Line(
                id: account.id, name: account.name, typeTitle: account.type.title, symbol: account.type.symbol,
                start: start, end: account.balance(asOf: end), contributions: contributions, growth: growth,
                returnRate: rate(growth: growth, start: start, weightedFlows: weighted)
            ))
            totalWeighted += weighted
            totals.start += start
            totals.end += account.balance(asOf: end)
            totals.contributions += contributions
            totals.growth += growth
        }

        let points = Trend.monthEnds(range, now: now, calendar: calendar).map { date in
            Point(date: date, value: investments.reduce(Decimal(0)) { $0 + $1.balance(asOf: date) }.doubleValue)
        }

        return Report(
            range: range,
            lines: lines.sorted { $0.end != $1.end ? $0.end > $1.end : $0.name < $1.name },
            holdings: holdingLines(investments, range: range, end: end, length: length),
            points: points,
            start: totals.start, end: totals.end, contributions: totals.contributions, growth: totals.growth,
            returnRate: rate(growth: totals.growth, start: totals.start, weightedFlows: totalWeighted)
        )
    }

    /// Each holding's start value, end value, growth and return. Growth is the price change on the shares held at the
    /// time; buying or selling shares counts as a contribution, weighted by how long it was held.
    private static func holdingLines(_ accounts: [Account], range: ReportRange, end: Date, length: TimeInterval) -> [HoldingLine] {
        let before = Trend.startDate(range)
        var result: [HoldingLine] = []
        for account in accounts {
            for holding in account.holdings.live {
                var shares: Decimal = 0
                var price: Decimal = 0
                var growth: Decimal = 0
                var flows: Decimal = 0
                var weighted = 0.0
                var touched = false
                let timeline = holding.timeline

                for entry in timeline where entry.date <= before {
                    shares = entry.shares
                    price = entry.price
                }
                let start = shares * price
                for entry in timeline where entry.date > before && entry.date <= end {
                    growth += shares * (entry.price - price)
                    let flow = (entry.shares - shares) * entry.price
                    flows += flow
                    weighted += flow.doubleValue * max(end.timeIntervalSince(entry.date), 0) / length
                    shares = entry.shares
                    price = entry.price
                    touched = true
                }
                let value = shares * price
                guard start != 0 || value != 0 || touched else { continue }
                result.append(HoldingLine(
                    id: holding.id, name: holding.name, label: holding.label, accountName: account.name,
                    start: start, end: value, growth: growth, contributions: flows,
                    returnRate: rate(growth: growth, start: start, weightedFlows: weighted)
                ))
            }
        }
        return result.sorted { $0.end != $1.end ? $0.end > $1.end : $0.name < $1.name }
    }
}
