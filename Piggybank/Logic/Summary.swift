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

    /// Each group's total at the end of each of the last `months` months. One pass over each account's transactions,
    /// not one per month, so it stays quick with years of history.
    static func netWorthSeries(accounts: [Account], months: Int = 12, now: Date = .now, calendar: Calendar = .current) -> [NetWorthPoint] {
        let starts = monthStarts(count: months, now: now, calendar: calendar)
        let cutoffs = starts.map { min(calendar.dateInterval(of: .month, for: $0)?.end ?? $0, now) }
        let groups = AccountGroup.allCases
        // totals[group][month]
        var totals = Array(repeating: Array(repeating: Decimal(0), count: cutoffs.count), count: groups.count)

        for account in accounts.live {
            guard let groupIndex = groups.firstIndex(of: account.type.group) else { continue }
            // Money landing in each month's slot: everything up to the first cutoff, then each month after it.
            var slots = Array(repeating: Decimal(0), count: cutoffs.count)
            for transaction in account.transactions where transaction.isLive {
                let date = transaction.date
                guard let slot = cutoffs.firstIndex(where: { date <= $0 }) else { continue }   // after the last cutoff
                slots[slot] += transaction.amount
            }
            var running = account.openingBalance
            for index in cutoffs.indices {
                running += slots[index]
                totals[groupIndex][index] += running
            }
        }

        return starts.indices.flatMap { month in
            groups.indices.map { group in
                NetWorthPoint(month: starts[month], group: groups[group], value: totals[group][month].doubleValue)
            }
        }
    }

    static func flowSeries(transactions: [Transaction], months: Int = 12, now: Date = .now, calendar: Calendar = .current) -> [FlowPoint] {
        let starts = monthStarts(count: months, now: now, calendar: calendar)
        let ends = starts.map { calendar.dateInterval(of: .month, for: $0)?.end ?? $0 }
        var flows = Array(repeating: Flow(), count: starts.count)
        guard let first = starts.first else { return [] }
        for transaction in transactions where !transaction.isTransfer {
            let date = transaction.date
            guard date >= first, let index = ends.firstIndex(where: { date < $0 }) else { continue }
            if transaction.amount > 0 { flows[index].income += transaction.amount } else { flows[index].spending -= transaction.amount }
        }
        return starts.indices.flatMap { index in
            [
                FlowPoint(month: starts[index], kind: "Income", value: flows[index].income.doubleValue),
                FlowPoint(month: starts[index], kind: "Spending", value: -flows[index].spending.doubleValue),
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
