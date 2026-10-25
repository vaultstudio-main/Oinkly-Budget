import SwiftUI
import Charts

/// The Strategy Plan's pull from the Debt War Plan and the Savings War Plan: your net position over time, each debt's payoff and each savings
/// account's growth, with and without the war plans' extra money. All of it is worked out from the plans as they are set on their own tabs.
struct StrategyPlanCards: View {
    let summary: WarPlanSummary.Summary

    private func date(_ months: Int) -> Date { Calendar.current.date(byAdding: .month, value: months, to: .now) ?? .now }

    var body: some View {
        VStack(spacing: 10) {
            if !summary.debt.debts.isEmpty || !summary.savings.accounts.isEmpty { netCard }
            if !summary.debt.debts.isEmpty || !summary.savings.accounts.isEmpty { impactCard }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { debtCard; savingsCard }
                VStack(spacing: 10) { debtCard; savingsCard }
            }
        }
    }

    // MARK: Net position

    private struct Point: Identifiable {
        let month: Int
        let value: Double
        let series: String
        var id: String { "\(series)\(month)" }
    }

    /// What you save less what you owe, month by month. A plan that has finished stays where it ended.
    private func net(saved: [Double], owed: [Double], months: Int, series: String) -> [Point] {
        (0...months).map { month in
            let s = saved.isEmpty ? 0 : saved[min(month, saved.count - 1)]
            let o = owed.isEmpty ? 0 : owed[min(month, owed.count - 1)]
            return Point(month: month, value: s - o, series: series)
        }
    }

    @ViewBuilder
    private var netCard: some View {
        let debt = summary.debt, savings = summary.savings
        let horizon = min(max(debt.plan.balances.count, savings.plan.totals.count, 61) - 1, 240)
        let hasExtra = debt.hasExtra || savings.hasExtra
        let now = net(saved: savings.base.totals, owed: debt.base.balances, months: horizon, series: "Current payments and deposits")
        let with = net(saved: savings.plan.totals, owed: debt.plan.balances, months: horizon, series: "With the war plans")
        let start = now.first?.value ?? 0
        let end = (hasExtra ? with : now).last?.value ?? 0
        ReportCard(title: "Net Position Over Time") {
            VStack(alignment: .leading, spacing: 10) {
                Text("What you have saved less what you owe on your debts, month by month. It starts at \(ReportFormat.money(start)) and reaches \(ReportFormat.money(end)) in \(horizon / 12) year\(horizon / 12 == 1 ? "" : "s")\(hasExtra ? " with your war plans" : "").")
                    .font(.callout).foregroundStyle(.secondary)
                Chart {
                    ForEach(now) { point in
                        LineMark(x: .value("Date", date(point.month)), y: .value("Net", point.value), series: .value("Plan", point.series))
                            .foregroundStyle(by: .value("Plan", point.series)).interpolationMethod(.monotone)
                    }
                    if hasExtra {
                        ForEach(with) { point in
                            LineMark(x: .value("Date", date(point.month)), y: .value("Net", point.value), series: .value("Plan", point.series))
                                .foregroundStyle(by: .value("Plan", point.series)).interpolationMethod(.monotone)
                        }
                    }
                    RuleMark(y: .value("Zero", 0)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.secondary.opacity(0.6))
                }
                .chartForegroundStyleScale(["Current payments and deposits": Color.secondary, "With the war plans": Theme.green])
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .chartLegend(position: .bottom)
                .frame(height: 220)
            }
        }
    }

    // MARK: What extra money does

    private struct Curve: Identifiable {
        let extra: Double
        let value: Double
        var id: Double { extra }
    }

    private static let extras: [Double] = Array(stride(from: 0.0, through: 2000.0, by: 50.0))

    /// Years until the debts are gone for each extra amount, so you can see where more money stops paying off so fast.
    private var debtCurve: [Curve] {
        let debt = summary.debt
        return Self.extras.map { extra in
            let result = DebtWarPlan.simulate(debt.debts, extra: extra, lump: debt.lump, strategy: debt.strategy, target: debt.target)
            return Curve(extra: extra, value: result.finishes ? Double(result.months) / 12 : 50)
        }
    }

    /// Everything saved after five years for each extra amount, ignoring targets so the plan runs the whole time.
    private var savingsCurve: [Curve] {
        let savings = summary.savings
        let open = savings.accounts.map { account -> SavingsWarPlan.Account in var copy = account; copy.target = nil; return copy }
        return Self.extras.map { extra in
            let totals = SavingsWarPlan.simulate(open, extra: extra, lump: savings.lump, goal: nil, strategy: savings.strategy, laserTarget: savings.target).totals
            return Curve(extra: extra, value: totals[min(60, max(totals.count - 1, 0))])
        }
    }

    private func years(_ value: Double) -> String {
        let months = Int((value * 12).rounded())
        let y = months / 12, m = months % 12
        if y == 0 { return "\(m) month\(m == 1 ? "" : "s")" }
        return m == 0 ? "\(y) year\(y == 1 ? "" : "s")" : "\(y) yr \(m) mo"
    }

    private func curveChart(_ curve: [Curve], color: Color, now: Double, valueLabel: @escaping (Double) -> String, axis: @escaping (Double) -> String) -> some View {
        let nowValue = curve.min { abs($0.extra - now) < abs($1.extra - now) }?.value ?? curve.first?.value ?? 0
        return Chart {
            ForEach(curve) { point in
                AreaMark(x: .value("Extra", point.extra), y: .value("Value", point.value)).foregroundStyle(color.opacity(0.12)).interpolationMethod(.monotone)
                LineMark(x: .value("Extra", point.extra), y: .value("Value", point.value)).foregroundStyle(color).interpolationMethod(.monotone)
            }
            PointMark(x: .value("Extra", min(now, 2000)), y: .value("Value", nowValue))
                .foregroundStyle(Color.orange).symbolSize(90)
                .annotation(position: .top, alignment: now > 1000 ? .trailing : .leading, spacing: 4) {
                    Text(now > 0 ? "Your plan: \(valueLabel(nowValue))" : "No extra: \(valueLabel(nowValue))")
                        .font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
        }
        .chartXScale(domain: 0...2000)
        .chartXAxis { AxisMarks(values: [0, 500, 1000, 1500, 2000]) { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(n == 0 ? "$0" : "+" + ReportFormat.compact(n).replacingOccurrences(of: "$", with: "")) } } } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(axis(n)) } } } }
        .frame(height: 200)
    }

    /// How the time to be debt-free and the savings in five years change as the extra each month grows, with where your plan sits on each.
    @ViewBuilder
    private var impactCard: some View {
        let debt = summary.debt, savings = summary.savings
        let showDebt = !debt.debts.isEmpty, showSavings = !savings.accounts.isEmpty
        let dCurve = showDebt ? debtCurve : [], sCurve = showSavings ? savingsCurve : []
        ReportCard(title: "What Extra Money Does") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Each line shows what happens as the extra you put in each month grows from $0 to $2,000. The dot is where your plan is now.")
                    .font(.callout).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { debtPart(dCurve, debt); savingsPart(sCurve, savings) }
                    VStack(alignment: .leading, spacing: 16) { debtPart(dCurve, debt); savingsPart(sCurve, savings) }
                }
            }
        }
    }

    @ViewBuilder
    private func debtPart(_ curve: [Curve], _ debt: WarPlanSummary.Debt) -> some View {
        if !curve.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Time to Be Debt-Free", systemImage: "scope").font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
                if let first = curve.first, let last = curve.last, let half = curve.first(where: { $0.extra == 500 }) {
                    Text("\(years(first.value)) now, \(years(half.value)) with $500 extra, \(years(last.value)) with $2,000 extra.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                curveChart(curve, color: Theme.red, now: debt.extra, valueLabel: { years($0) }, axis: { "\(Int($0))y" })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func savingsPart(_ curve: [Curve], _ savings: WarPlanSummary.Savings) -> some View {
        if !curve.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Saved in Five Years", systemImage: "banknote.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
                if let first = curve.first, let last = curve.last, let half = curve.first(where: { $0.extra == 500 }) {
                    Text("\(ReportFormat.money(first.value)) now, \(ReportFormat.money(half.value)) with $500 extra, \(ReportFormat.money(last.value)) with $2,000 extra.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                curveChart(curve, color: Theme.green, now: savings.extra, valueLabel: { ReportFormat.money($0) }, axis: { ReportFormat.compact($0) })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Debts

    private struct Pair: Identifiable {
        let name: String
        let series: String
        let value: Double
        let label: String
        var id: String { name + series }
    }

    private var debtCard: some View {
        let debt = summary.debt
        let limit = 360
        func months(_ result: DebtWarPlan.DebtResult?) -> (value: Double, label: String) {
            guard let m = result?.payoffMonth else { return (Double(limit), "Never") }
            return (Double(min(m, limit)), m == 0 ? "Paid off" : ReportFormat.month(date(m)))
        }
        let pairs: [Pair] = debt.debts.flatMap { item -> [Pair] in
            let now = months(debt.base.byDebt[item.id]), with = months(debt.plan.byDebt[item.id])
            var list = [Pair(name: item.name, series: "Current payments", value: now.value, label: now.label)]
            if debt.hasExtra { list.append(Pair(name: item.name, series: "With the war plan", value: with.value, label: with.label)) }
            return list
        }
        return ReportCard(title: "When Each Debt Is Paid Off") {
            if debt.debts.isEmpty {
                Text("No debt to pay off.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Months until each debt is gone. Shorter is better.").font(.caption).foregroundStyle(.secondary)
                    Chart(pairs) { pair in
                        BarMark(x: .value("Months", pair.value), y: .value("Debt", pair.name))
                            .foregroundStyle(by: .value("Plan", pair.series))
                            .position(by: .value("Plan", pair.series))
                            .cornerRadius(3)
                            .annotation(position: .trailing) { Text(pair.label).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .chartForegroundStyleScale(["Current payments": Color.secondary, "With the war plan": Theme.green])
                    .chartXScale(range: .plotDimension(endPadding: 70))
                    .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text("\(Int(n / 12))y") } } } }
                    .chartLegend(position: .bottom)
                    .frame(height: CGFloat(debt.debts.count) * (debt.hasExtra ? 64 : 40) + 50)
                }
            }
        }
    }

    // MARK: Savings

    private var savingsCard: some View {
        let savings = summary.savings
        let pairs: [Pair] = savings.accounts.flatMap { account -> [Pair] in
            var list = [Pair(name: account.name, series: "Saved now", value: account.balance, label: ReportFormat.money(account.balance))]
            let end = savings.plan.byAccount[account.id]?.balanceAtEnd ?? account.balance
            list.append(Pair(name: account.name, series: savings.hasExtra ? "At the end with the war plan" : "At the end of the plan", value: end, label: ReportFormat.money(end)))
            return list
        }
        let endName = savings.hasExtra ? "At the end with the war plan" : "At the end of the plan"
        return ReportCard(title: "How Each Savings Account Grows") {
            if savings.accounts.isEmpty {
                Text("No savings accounts.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(savings.hasStop ? "What each account holds now and when the plan ends." : "What each account holds now and in five years.")
                        .font(.caption).foregroundStyle(.secondary)
                    Chart(pairs) { pair in
                        BarMark(x: .value("Saved", pair.value), y: .value("Account", pair.name))
                            .foregroundStyle(by: .value("When", pair.series))
                            .position(by: .value("When", pair.series))
                            .cornerRadius(3)
                            .annotation(position: .trailing) { Text(pair.label).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .chartForegroundStyleScale(["Saved now": Color.secondary, endName: Theme.green])
                    .chartXScale(range: .plotDimension(endPadding: 80))
                    .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                    .chartLegend(position: .bottom)
                    .frame(height: CGFloat(savings.accounts.count) * 64 + 50)
                }
            }
        }
    }
}
