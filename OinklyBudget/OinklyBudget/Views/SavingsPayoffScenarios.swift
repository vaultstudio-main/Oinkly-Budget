import SwiftUI

/// What extra saving would do: what you would have in five years for a few extra amounts, and the extra each month it takes to reach your
/// goals in a few set times. It works from the same accounts, rates and strategy as the Savings War Plan, and only works things out.
struct SavingsPayoffScenarios: View {
    let accounts: [SavingsWarPlan.Account]
    let goal: Double?
    let strategy: SavingsWarPlan.Strategy
    let laserTarget: String?
    let lump: Double
    /// Called with an amount when the person taps Use. Nil where the amounts can only be read.
    var use: ((Double) -> Void)?

    private static let amounts: [Double] = [100, 250, 500, 1000, 1500]
    private static let years = [1, 2, 3, 5, 10]
    private static let horizon = 60

    private var hasStop: Bool { goal != nil || accounts.contains(where: \.hasTarget) }

    private func run(_ extra: Double) -> SavingsWarPlan.Result {
        SavingsWarPlan.simulate(accounts, extra: extra, lump: lump, goal: goal, strategy: strategy, laserTarget: laserTarget)
    }

    /// Everything saved after five years, ignoring targets and the goal so the plan runs the whole time.
    private func fiveYears(_ extra: Double) -> Double {
        let open = accounts.map { account -> SavingsWarPlan.Account in var copy = account; copy.target = nil; return copy }
        let totals = SavingsWarPlan.simulate(open, extra: extra, lump: lump, goal: nil, strategy: strategy, laserTarget: laserTarget).totals
        return totals[min(Self.horizon, max(totals.count - 1, 0))]
    }

    private func date(_ months: Int) -> String { ReportFormat.month(Calendar.current.date(byAdding: .month, value: months, to: .now) ?? .now) }

    private func span(_ months: Int) -> String {
        let y = months / 12, m = months % 12
        if y == 0 { return "\(m) month\(m == 1 ? "" : "s")" }
        if m == 0 { return "\(y) year\(y == 1 ? "" : "s")" }
        return "\(y) yr \(m) mo"
    }

    /// The least extra each month that reaches every target and the goal within `months`, found by narrowing in on it.
    private func extraNeeded(within months: Int) -> Double? {
        let remaining = max(goal.map { $0 - accounts.reduce(0) { $0 + $1.balance } } ?? 0,
                            accounts.filter(\.hasTarget).reduce(0) { $0 + max(($1.target ?? 0) - $1.balance, 0) }, 1)
        var high = remaining
        guard run(high).finishes, run(high).months <= months else { return nil }
        var low = 0.0
        for _ in 0..<28 {
            let mid = (low + high) / 2
            let result = run(mid)
            if result.finishes && result.months <= months { high = mid } else { low = mid }
        }
        return high.rounded(.up)
    }

    private func useButton(_ amount: Double) -> some View {
        Group {
            if let use { Button("Use") { use(amount) }.buttonStyle(.bordered).controlSize(.small) }
        }
    }

    @ViewBuilder var body: some View {
        let base = run(0)
        let baseFive = fiveYears(0)
        let amountsColumn = VStack(alignment: .leading, spacing: 6) {
            Text("If you save more each month").font(.callout.weight(.semibold))
            ForEach(Self.amounts, id: \.self) { amount in
                let five = fiveYears(amount)
                HStack(spacing: 8) {
                    Text("+\(ReportFormat.money(amount))").fontWeight(.semibold).frame(width: 70, alignment: .leading)
                    Text("\(ReportFormat.money(five)) in 5 years").frame(width: 170, alignment: .leading)
                    Text("\(ReportFormat.money(max(five - baseFive, 0))) more").foregroundStyle(Theme.green)
                    if hasStop {
                        let result = run(amount)
                        if result.finishes { Text("goals \(date(result.months))").foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    useButton(amount)
                }
                .font(.callout)
            }
        }
        let goalsColumn = VStack(alignment: .leading, spacing: 6) {
            Text("To reach your goals sooner").font(.callout.weight(.semibold))
            if hasStop {
                ForEach(Self.years.filter { !base.finishes || $0 * 12 < base.months }, id: \.self) { years in
                    let needed = extraNeeded(within: years * 12)
                    HStack(spacing: 8) {
                        Text("In \(years) year\(years == 1 ? "" : "s")").frame(width: 90, alignment: .leading)
                        if let needed {
                            Text("save \(ReportFormat.money(needed)) extra a month").fontWeight(.semibold)
                            Text("(\(date(years * 12)))").foregroundStyle(.secondary)
                        } else {
                            Text("not possible with these accounts").foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let needed { useButton(needed) }
                    }
                    .font(.callout)
                }
                if base.finishes, Self.years.allSatisfy({ $0 * 12 >= base.months }) {
                    Text("Your own deposits already reach everything in \(span(base.months)).").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Text("Set a total goal, or a target on an account, and this shows the extra each month it takes to reach it in 1, 2, 3, 5 or 10 years.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 36) { amountsColumn.frame(maxWidth: .infinity, alignment: .leading); goalsColumn.frame(maxWidth: .infinity, alignment: .leading) }
            VStack(alignment: .leading, spacing: 14) { amountsColumn; goalsColumn }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
