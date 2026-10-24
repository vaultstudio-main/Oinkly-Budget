import Foundation

/// The Debt War Plan's arithmetic: every loan and card paid down month by month, with extra money added, and what that does to when each
/// is paid off and how much interest is paid. Nothing here changes any account; it only works out what would happen.
enum DebtWarPlan {
    struct Debt: Identifiable, Equatable {
        let id: String
        var name: String
        var kind: String
        var symbol: String
        var owed: Double
        /// Yearly interest rate in percent.
        var rate: Double
        /// What is paid on it each month. Zero when none is set, so only extra money pays it.
        var payment: Double
    }

    /// Which debt the extra money goes to first.
    enum Strategy: String, CaseIterable, Identifiable {
        /// The highest rate first: it costs the least interest overall.
        case avalanche
        /// The smallest balance first: debts are cleared sooner, which many people find easier to stick with.
        case snowball

        var id: String { rawValue }
        var title: String { self == .avalanche ? "Highest interest first" : "Smallest balance first" }
        var blurb: String {
            self == .avalanche ? "The extra goes to the debt with the highest rate, which costs the least interest in all."
                               : "The extra goes to the smallest balance, so debts are cleared sooner, one by one."
        }
    }

    struct DebtResult: Equatable {
        /// The month it is paid off in, counting from now (1 is next month). Nil when it never is.
        var payoffMonth: Int?
        var interest: Double
    }

    struct Result {
        /// Months until everything is paid. Meaningful only when `finishes`.
        var months: Int
        var interest: Double
        /// False when the payments never clear the debt, usually because they don't cover the interest.
        var finishes: Bool
        var byDebt: [String: DebtResult]
        /// What is owed in total, now and at the end of each month, so the two plans can be drawn together.
        var balances: [Double]
    }

    /// Pays every debt its own monthly payment each month, and adds `extra` each month plus a one-time `lump` now. The extra, and every payment
    /// freed up by a debt that is finished, goes to one debt at a time in the order of the `strategy`.
    static func simulate(_ debts: [Debt], extra: Double, lump: Double = 0, strategy: Strategy = .avalanche, limit: Int = 600) -> Result {
        var owed = debts.map(\.owed)
        let rates = debts.map(\.rate)
        let payments = debts.map(\.payment)
        var byDebt: [String: DebtResult] = [:]
        for debt in debts { byDebt[debt.id] = DebtResult(payoffMonth: debt.owed > 0.005 ? nil : 0, interest: 0) }

        /// The order to hand out extra money in, among the debts still owing.
        func order() -> [Int] {
            owed.indices.filter { owed[$0] > 0.005 }.sorted {
                switch strategy {
                case .avalanche: rates[$0] != rates[$1] ? rates[$0] > rates[$1] : owed[$0] < owed[$1]
                case .snowball: owed[$0] != owed[$1] ? owed[$0] < owed[$1] : rates[$0] > rates[$1]
                }
            }
        }
        func pay(_ amount: Double, on index: Int) -> Double {
            let used = min(amount, owed[index])
            owed[index] -= used
            return amount - used
        }

        var balances = [owed.reduce(0, +)]
        var interest = 0.0
        var months = 0

        // The one-time amount goes in first.
        var left = max(lump, 0)
        for index in order() where left > 0 { left = pay(left, on: index) }
        for index in owed.indices where owed[index] <= 0.005 && byDebt[debts[index].id]?.payoffMonth == nil { byDebt[debts[index].id]?.payoffMonth = 0 }
        balances[0] = owed.reduce(0, +)

        // Payments that finished debts no longer need, which keep going to the rest.
        var freed = 0.0
        while owed.contains(where: { $0 > 0.005 }) && months < limit {
            months += 1
            for index in owed.indices where owed[index] > 0.005 {
                let charge = owed[index] * rates[index] / 1200
                owed[index] += charge
                interest += charge
                byDebt[debts[index].id]?.interest += charge
            }
            for index in owed.indices where owed[index] > 0.005 { _ = pay(payments[index], on: index) }
            var budget = max(extra, 0) + freed
            for index in order() where budget > 0.005 { budget = pay(budget, on: index) }
            for index in owed.indices where owed[index] <= 0.005 && byDebt[debts[index].id]?.payoffMonth == nil {
                byDebt[debts[index].id]?.payoffMonth = months
                freed += payments[index]
            }
            balances.append(owed.reduce(0, +))
        }
        return Result(months: months, interest: interest, finishes: !owed.contains(where: { $0 > 0.005 }), byDebt: byDebt, balances: balances)
    }
}
