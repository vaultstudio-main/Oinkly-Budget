import Foundation
import SwiftData

/// One savings account's own settings in the Savings War Plan: its rate, what is added each month and the balance it should reach.
struct SavingsPlanRow: Codable, Equatable {
    var rate: Double = 0
    var deposit: Double = 0
    var target: Double?
}

/// What the Debt War Plan and the Savings War Plan have worked out, read from the amounts saved on this Mac, so the Outlook can count the
/// extra money they set aside and show statistics on both. Nothing here changes an account.
enum WarPlanSummary {
    // MARK: Building the plans' inputs (shared with the two tabs)

    /// Every loan and card that still owes something, biggest first.
    static func debts(from accounts: [Account]) -> [DebtWarPlan.Debt] {
        accounts.filter { ($0.isLoan || $0.isCreditCard) && !$0.isClosed && Goal.owed(on: $0) > 0 }
            .sorted { Goal.owed(on: $0) > Goal.owed(on: $1) }
            .map {
                DebtWarPlan.Debt(id: String(describing: $0.persistentModelID), name: $0.name, kind: $0.typeTitle, symbol: $0.type.symbol,
                                 owed: Goal.owed(on: $0).doubleValue, rate: $0.interestRate, payment: $0.monthlyPayment.doubleValue)
            }
    }

    static let savingsTypes: [AccountType] = [.savings, .moneyMarket, .certificateOfDeposit, .healthSavings]

    /// Every open savings account with what the plan knows about it. Its target is the one typed, or else that of the open saving goal that
    /// follows it.
    static func savings(from accounts: [Account], rows: [String: SavingsPlanRow]) -> [SavingsWarPlan.Account] {
        accounts.filter { savingsTypes.contains($0.type) && !$0.isClosed }
            .sorted { $0.balance > $1.balance }
            .map { account in
                let id = String(describing: account.persistentModelID)
                let row = rows[id] ?? SavingsPlanRow()
                let goalTarget = account.goals.first { $0.isLive && $0.kind == .save && $0.completedAt == nil && $0.targetAmount > 0 }?.targetAmount.doubleValue
                return SavingsWarPlan.Account(id: id, name: account.name, kind: account.typeTitle, symbol: account.type.symbol,
                                              balance: max(account.balance.doubleValue, 0), rate: row.rate, deposit: row.deposit, target: row.target ?? goalTarget)
            }
    }

    static func decodeRows(_ text: String) -> [String: SavingsPlanRow] {
        (try? JSONDecoder().decode([String: SavingsPlanRow].self, from: Data(text.utf8))) ?? [:]
    }

    static func encodeRows(_ rows: [String: SavingsPlanRow]) -> String {
        (try? JSONEncoder().encode(rows)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // MARK: The amounts saved on this Mac

    private static func amount(_ key: String, _ defaults: UserDefaults) -> Double {
        max((OutlookSettings.decimal(defaults.string(forKey: key) ?? "") ?? 0).doubleValue, 0)
    }

    struct Debt {
        var debts: [DebtWarPlan.Debt]
        var extra: Double
        var lump: Double
        var strategy: DebtWarPlan.Strategy
        /// The debt Laser Focus Annihilation is aimed at, when that is the strategy.
        var target: String?
        var base: DebtWarPlan.Result
        var plan: DebtWarPlan.Result
        var totalOwed: Double { debts.reduce(0) { $0 + $1.owed } }
        var hasExtra: Bool { extra > 0 || lump > 0 }
    }

    struct Savings {
        var accounts: [SavingsWarPlan.Account]
        var extra: Double
        var lump: Double
        var goal: Double?
        var strategy: SavingsWarPlan.Strategy
        var base: SavingsWarPlan.Result
        var plan: SavingsWarPlan.Result
        var totalSaved: Double { accounts.reduce(0) { $0 + $1.balance } }
        var hasExtra: Bool { extra > 0 || lump > 0 }
        var hasStop: Bool { goal != nil || accounts.contains(where: \.hasTarget) }
    }

    struct Summary {
        var debt: Debt
        var savings: Savings
        /// The extra money the two plans set aside every month.
        var monthlyExtra: Double { debt.extra + savings.extra }
        /// The one-time amounts the two plans put in right now.
        var oneTimeNow: Double { debt.lump + savings.lump }
        var isActive: Bool { monthlyExtra > 0 || oneTimeNow > 0 }
        var hasAnything: Bool { !debt.debts.isEmpty || !savings.accounts.isEmpty }
    }

    /// Runs both plans as the two tabs have them set.
    static func build(accounts: [Account], defaults: UserDefaults = .standard) -> Summary {
        let debts = debts(from: accounts)
        let debtStrategy = DebtWarPlan.Strategy(rawValue: defaults.string(forKey: "debtWarPlanStrategy") ?? "") ?? .avalanche
        let debtTarget = debtStrategy == .laser
            ? (debts.first { $0.id == defaults.string(forKey: "debtWarPlanTarget") } ?? debts.min { $0.owed < $1.owed })?.id : nil
        let debtExtra = amount("debtWarPlanExtra", defaults), debtLump = amount("debtWarPlanLump", defaults)
        let debt = Debt(debts: debts, extra: debtExtra, lump: debtLump, strategy: debtStrategy, target: debtTarget,
                        base: DebtWarPlan.simulate(debts, extra: 0, strategy: debtStrategy, target: debtTarget),
                        plan: DebtWarPlan.simulate(debts, extra: debtExtra, lump: debtLump, strategy: debtStrategy, target: debtTarget))

        let saved = savings(from: accounts, rows: decodeRows(defaults.string(forKey: "savingsWarPlanRows") ?? ""))
        let savingsStrategy = SavingsWarPlan.Strategy(rawValue: defaults.string(forKey: "savingsWarPlanStrategy") ?? "") ?? .even
        let savingsTarget = savingsStrategy == .laser
            ? (saved.first { $0.id == defaults.string(forKey: "savingsWarPlanTarget") }
               ?? saved.first { $0.hasTarget && ($0.target ?? 0) > $0.balance } ?? saved.first)?.id : nil
        let savingsExtra = amount("savingsWarPlanExtra", defaults), savingsLump = amount("savingsWarPlanLump", defaults)
        let goalValue = amount("savingsWarPlanGoal", defaults)
        let goal: Double? = goalValue > 0 ? goalValue : nil
        let savings = Savings(accounts: saved, extra: savingsExtra, lump: savingsLump, goal: goal, strategy: savingsStrategy,
                              base: SavingsWarPlan.simulate(saved, extra: 0, goal: goal, strategy: savingsStrategy, laserTarget: savingsTarget),
                              plan: SavingsWarPlan.simulate(saved, extra: savingsExtra, lump: savingsLump, goal: goal, strategy: savingsStrategy, laserTarget: savingsTarget))
        return Summary(debt: debt, savings: savings)
    }
}
