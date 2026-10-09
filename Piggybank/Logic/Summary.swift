import Foundation

/// Pure calculations behind the Summary screen.
enum Summary {
    struct NetWorthPoint: Identifiable {
        let month: Date
        let group: AccountGroup
        let value: Double
        var id: String { "\(month.timeIntervalSince1970)-\(group.rawValue)" }
    }

    struct FlowPoint: Identifiable {
        let month: Date
        let kind: String
        let value: Double
        var id: String { "\(month.timeIntervalSince1970)-\(kind)" }
    }

    struct Flow {
        var income: Decimal = 0
        var spending: Decimal = 0

        var savingsRate: Decimal? { income > 0 ? (income - spending) / income : nil }
    }

    /// Start of each of the last `count` months, oldest first.
    static func monthStarts(count: Int, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
    }

    static func total(of accounts: [Account], in groups: [AccountGroup], asOf date: Date = .distantFuture) -> Decimal {
        accounts.live.filter { groups.contains($0.type.group) }.reduce(0) { $0 + $1.balance(asOf: date) }
    }

    static func currentWorth(_ accounts: [Account]) -> Decimal {
        accounts.live.reduce(0) { $0 + $1.balance }
    }

    static func netWorthSeries(accounts: [Account], months: Int = 12, now: Date = .now, calendar: Calendar = .current) -> [NetWorthPoint] {
        monthStarts(count: months, now: now, calendar: calendar).flatMap { start -> [NetWorthPoint] in
            let monthEnd = calendar.dateInterval(of: .month, for: start)?.end ?? start
            let cutoff = min(monthEnd, now)
            return AccountGroup.allCases.map { group in
                NetWorthPoint(month: start, group: group, value: total(of: accounts, in: [group], asOf: cutoff).doubleValue)
            }
        }
    }

    static func flowSeries(transactions: [Transaction], months: Int = 12, now: Date = .now, calendar: Calendar = .current) -> [FlowPoint] {
        monthStarts(count: months, now: now, calendar: calendar).flatMap { start -> [FlowPoint] in
            let end = calendar.dateInterval(of: .month, for: start)?.end ?? start
            let flow = flow(transactions, from: start, to: end)
            return [
                FlowPoint(month: start, kind: "Income", value: flow.income.doubleValue),
                FlowPoint(month: start, kind: "Spending", value: -flow.spending.doubleValue),
            ]
        }
    }

    /// Income and spending for transactions dated in [start, end).
    static func flow(_ transactions: [Transaction], from start: Date, to end: Date) -> Flow {
        var result = Flow()
        for transaction in transactions where transaction.date >= start && transaction.date < end && !transaction.isTransfer {
            if transaction.amount > 0 {
                result.income += transaction.amount
            } else {
                result.spending -= transaction.amount
            }
        }
        return result
    }

    static func lastDays(_ days: Int, transactions: [Transaction], now: Date = .now, calendar: Calendar = .current) -> Flow {
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        return flow(transactions, from: start, to: now.addingTimeInterval(1))
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
