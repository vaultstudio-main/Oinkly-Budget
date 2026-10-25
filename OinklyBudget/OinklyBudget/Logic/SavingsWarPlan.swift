import Foundation

/// The Savings War Plan's arithmetic: every savings account grown month by month, with its own deposits, interest and any extra money
/// added, and how long each takes to reach its target. Nothing here changes any account; it only works out what would happen.
enum SavingsWarPlan {
    struct Account: Identifiable, Equatable {
        let id: String
        var name: String
        var kind: String
        var symbol: String
        var balance: Double
        /// Yearly rate (APY) in percent.
        var rate: Double
        /// What is put in each month, by you, before any extra money.
        var deposit: Double
        /// The balance this account is meant to reach. Nil or zero means it has no target.
        var target: Double?

        var hasTarget: Bool { (target ?? 0) > 0 }
    }

    /// Where the extra money goes.
    enum Strategy: String, CaseIterable, Identifiable {
        /// Shared equally among the accounts that are still short of their target.
        case even
        /// The account that pays the highest rate first, so the money earns the most.
        case highestRate
        /// One account you pick gets every extra dollar until it reaches its target. Then it rolls on to the rest, highest rate first.
        case laser

        var id: String { rawValue }
        var title: String {
            switch self {
            case .even: "Spread evenly"
            case .highestRate: "Highest rate first"
            case .laser: "Laser Focus Annihilation"
            }
        }
        var blurb: String {
            switch self {
            case .even: "The extra is shared equally between the accounts that are still short of their target."
            case .highestRate: "The extra goes to the account paying the highest rate first, so your money earns the most."
            case .laser: "Target locked. Every extra dollar goes to the one account you pick, until it reaches its target. Then it rolls on to the next one."
            }
        }
    }

    struct AccountResult: Equatable {
        /// The month the target was reached, counting from now (0 is already there, 1 is next month). Nil when it never is, or has no target.
        var reachedMonth: Int?
        var interest: Double
        /// The balance when the plan ends: when every target is reached, or after five years when there is none.
        var balanceAtEnd: Double
    }

    struct Result {
        /// Months simulated.
        var months: Int
        var interest: Double
        /// The month the overall goal was reached. Nil when there is no goal, or it is not reached.
        var goalMonth: Int?
        /// True when every target and the goal were reached.
        var finishes: Bool
        var byAccount: [String: AccountResult]
        /// Everything saved in total, now and at the end of each month.
        var totals: [Double]
    }

    /// Months simulated when there is no goal and no target to stop at: five years.
    static let defaultHorizon = 60

    /// Grows every account month by month. Each gets its interest, then its own deposit, then its share of `extra` (and of `lump` once, now).
    /// It stops when every target and the overall `goal` are reached, or after `limit` months. With nothing to reach it runs five years.
    static func simulate(_ accounts: [Account], extra: Double, lump: Double = 0, goal: Double? = nil, strategy: Strategy = .even,
                         laserTarget: String? = nil, limit: Int = 600) -> Result {
        var balance = accounts.map(\.balance)
        let monthlyRate = accounts.map { pow(1 + max($0.rate, 0) / 100, 1.0 / 12) - 1 }
        let targets = accounts.map { $0.hasTarget ? $0.target! : 0 }
        var byAccount: [String: AccountResult] = [:]
        for (index, account) in accounts.enumerated() {
            byAccount[account.id] = AccountResult(reachedMonth: account.hasTarget && balance[index] >= targets[index] ? 0 : nil, interest: 0, balanceAtEnd: balance[index])
        }
        let goalTotal = (goal ?? 0) > 0 ? goal! : nil
        let hasStop = goalTotal != nil || accounts.contains(where: \.hasTarget)

        /// Shares `amount` among the accounts in `indices`, each up to what it can still take (nil capacity means any amount).
        func share(_ amount: Double, among indices: [Int], evenly: Bool) {
            var left = amount
            var open = indices
            while left > 0.005 && !open.isEmpty {
                if evenly {
                    let part = left / Double(open.count)
                    var spent = 0.0
                    var stillOpen: [Int] = []
                    for index in open {
                        let room = targets[index] > 0 ? max(targets[index] - balance[index], 0) : .infinity
                        let put = min(part, room)
                        balance[index] += put
                        spent += put
                        if room - put > 0.005 { stillOpen.append(index) }
                    }
                    left -= spent
                    if spent < 0.005 { break }
                    open = stillOpen
                } else {
                    let index = open.removeFirst()
                    let room = targets[index] > 0 ? max(targets[index] - balance[index], 0) : .infinity
                    let put = min(left, room)
                    balance[index] += put
                    left -= put
                }
            }
            // Whatever the targets could not take keeps building the first account in the list, so no money is lost.
            if left > 0.005, let first = indices.first { balance[first] += left }
        }

        /// Accounts still short of their target, in the order the strategy hands money out.
        func order() -> [Int] {
            let short = accounts.indices.filter { targets[$0] > 0 && balance[$0] < targets[$0] - 0.005 }
            let pool = short.isEmpty ? Array(accounts.indices) : short
            switch strategy {
            case .even: return pool
            case .highestRate, .laser:
                return pool.sorted {
                    if strategy == .laser, let laserTarget {
                        let first = accounts[$0].id == laserTarget, second = accounts[$1].id == laserTarget
                        if first != second { return first }
                    }
                    return accounts[$0].rate != accounts[$1].rate ? accounts[$0].rate > accounts[$1].rate : balance[$0] < balance[$1]
                }
            }
        }

        func record(month: Int, interestThisMonth: [Double]) {
            for (index, account) in accounts.enumerated() {
                byAccount[account.id]?.interest += interestThisMonth[index]
                if account.hasTarget, byAccount[account.id]?.reachedMonth == nil, balance[index] >= targets[index] - 0.005 { byAccount[account.id]?.reachedMonth = month }
            }
        }

        if lump > 0 && !accounts.isEmpty { share(lump, among: order(), evenly: strategy == .even) }
        var totals = [balance.reduce(0, +)]
        var interest = 0.0
        var goalMonth: Int? = goalTotal.flatMap { totals[0] >= $0 ? 0 : nil }
        var months = 0
        record(month: 0, interestThisMonth: Array(repeating: 0, count: accounts.count))
        if accounts.isEmpty { return Result(months: 0, interest: 0, goalMonth: nil, finishes: false, byAccount: byAccount, totals: totals) }

        func done() -> Bool {
            guard hasStop else { return months >= defaultHorizon }
            let targetsMet = accounts.indices.allSatisfy { targets[$0] <= 0 || balance[$0] >= targets[$0] - 0.005 }
            let goalMet = goalTotal == nil || goalMonth != nil
            return targetsMet && goalMet
        }

        while !done() && months < limit {
            months += 1
            var thisMonth = Array(repeating: 0.0, count: accounts.count)
            for index in balance.indices {
                let gain = balance[index] * monthlyRate[index]
                balance[index] += gain
                thisMonth[index] = gain
                interest += gain
            }
            for index in balance.indices where accounts[index].deposit > 0 { balance[index] += accounts[index].deposit }
            if extra > 0 { share(extra, among: order(), evenly: strategy == .even) }
            let total = balance.reduce(0, +)
            totals.append(total)
            if goalMonth == nil, let goalTotal, total >= goalTotal { goalMonth = months }
            record(month: months, interestThisMonth: thisMonth)
        }
        for (index, account) in accounts.enumerated() { byAccount[account.id]?.balanceAtEnd = balance[index] }
        let targetsMet = accounts.indices.allSatisfy { targets[$0] <= 0 || balance[$0] >= targets[$0] - 0.005 }
        return Result(months: months, interest: interest, goalMonth: goalMonth, finishes: hasStop && targetsMet && (goalTotal == nil || goalMonth != nil),
                      byAccount: byAccount, totals: totals)
    }
}
