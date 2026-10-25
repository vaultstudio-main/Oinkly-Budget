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
            if !summary.debt.debts.isEmpty {
                ReportCard(title: "What It Would Take to Be Debt-Free") {
                    DebtPayoffScenarios(debts: summary.debt.debts, strategy: summary.debt.strategy, target: summary.debt.target, lump: summary.debt.lump)
                }
            }
            if !summary.savings.accounts.isEmpty {
                ReportCard(title: "What It Would Take to Save More") {
                    SavingsPayoffScenarios(accounts: summary.savings.accounts, goal: summary.savings.goal, strategy: summary.savings.strategy,
                                           laserTarget: summary.savings.target, lump: summary.savings.lump)
                }
            }
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
