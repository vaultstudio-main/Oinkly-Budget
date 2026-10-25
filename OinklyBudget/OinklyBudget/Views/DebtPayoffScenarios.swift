import SwiftUI

/// What extra money would do to the debts: the date you would be debt-free for a few amounts, and the extra each month it takes to be debt-free
/// in a few set times. It works from the same payments and strategy as the Debt War Plan, and only works things out: it changes nothing.
struct DebtPayoffScenarios: View {
    let debts: [DebtWarPlan.Debt]
    let strategy: DebtWarPlan.Strategy
    let target: String?
    let lump: Double
    /// Called with an amount when the person taps Use. Nil where the amounts can only be read.
    var use: ((Double) -> Void)?

    private static let amounts: [Double] = [100, 250, 500, 1000, 1500]
    private static let years = [1, 2, 3, 5]

    private func run(_ extra: Double) -> DebtWarPlan.Result {
        DebtWarPlan.simulate(debts, extra: extra, lump: lump, strategy: strategy, target: target)
    }

    private func date(_ months: Int) -> String { ReportFormat.month(Calendar.current.date(byAdding: .month, value: months, to: .now) ?? .now) }

    private func span(_ months: Int) -> String {
        let y = months / 12, m = months % 12
        if y == 0 { return "\(m) month\(m == 1 ? "" : "s")" }
        if m == 0 { return "\(y) year\(y == 1 ? "" : "s")" }
        return "\(y) yr \(m) mo"
    }

    /// The least extra each month that clears everything within `months`, found by narrowing in on it. Nil when no amount can.
    private func extraNeeded(within months: Int) -> Double? {
        let owed = debts.reduce(0) { $0 + $1.owed }
        var high = max(owed, 1)
        guard run(high).finishes, run(high).months <= months else { return nil }
        var low = 0.0
        for _ in 0..<28 {
            let mid = (low + high) / 2
            let result = run(mid)
            if result.finishes && result.months <= months { high = mid } else { low = mid }
        }
        return high.rounded(.up)
    }

    @ViewBuilder var body: some View {
        let base = run(0)
        let amountsColumn = VStack(alignment: .leading, spacing: 6) {
                Text("If you pay more each month").font(.callout.weight(.semibold))
                ForEach(Self.amounts, id: \.self) { amount in
                    let result = run(amount)
                    HStack(spacing: 8) {
                        Text("+\(ReportFormat.money(amount))").fontWeight(.semibold).frame(width: 70, alignment: .leading)
                        if result.finishes {
                            Text("debt-free \(date(result.months))").frame(width: 150, alignment: .leading)
                            Text(base.finishes ? "\(span(max(base.months - result.months, 0))) sooner" : "instead of never").foregroundStyle(Theme.green)
                            if base.finishes, base.interest > result.interest {
                                Text("saves \(ReportFormat.money(base.interest - result.interest))").foregroundStyle(.secondary)
                            }
                        } else {
                            Text("still not debt-free in 50 years").foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let use { Button("Use") { use(amount) }.buttonStyle(.borderless).controlSize(.small) }
                    }
                    .font(.callout)
                }
            }
        let goalsColumn = VStack(alignment: .leading, spacing: 6) {
                Text("To be debt-free sooner").font(.callout.weight(.semibold))
                ForEach(Self.years.filter { !base.finishes || $0 * 12 < base.months }, id: \.self) { years in
                    HStack(spacing: 8) {
                        Text("In \(years) year\(years == 1 ? "" : "s")").frame(width: 90, alignment: .leading)
                        if let needed = extraNeeded(within: years * 12) {
                            Text("pay \(ReportFormat.money(needed)) extra a month").fontWeight(.semibold)
                            Text("(\(date(years * 12)))").foregroundStyle(.secondary)
                        } else {
                            Text("not possible with these debts").foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let use, let needed = extraNeeded(within: years * 12) { Button("Use") { use(needed) }.buttonStyle(.borderless).controlSize(.small) }
                    }
                    .font(.callout)
                }
                if base.finishes, Self.years.allSatisfy({ $0 * 12 >= base.months }) {
                    Text("Your current payments already clear everything in \(span(base.months)).").font(.callout).foregroundStyle(.secondary)
                }
            }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 36) { amountsColumn.frame(maxWidth: .infinity, alignment: .leading); goalsColumn.frame(maxWidth: .infinity, alignment: .leading) }
            VStack(alignment: .leading, spacing: 14) { amountsColumn; goalsColumn }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
