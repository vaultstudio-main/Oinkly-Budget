import SwiftUI
import SwiftData
import Charts

// MARK: Cash balance

struct CashBalanceProjectionReport: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAccounts: [Account]
    @Query private var allBills: [Bill]

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let calendar = Calendar.current
        let weeks = snapshot.map { cashForecastWeeks(accounts: allAccounts.live, bills: allBills, context: modelContext, snapshot: $0) } ?? []
        // One point a month: the first week of each month, plus today.
        var points: [Point] = []
        var seen = Set<Int>()
        for week in weeks {
            let key = calendar.component(.month, from: week.date) + 100 * calendar.component(.year, from: week.date)
            if points.isEmpty || !seen.contains(key) { points.append(Point(date: week.date, value: week.balance)) }
            seen.insert(key)
        }
        if let last = weeks.last, points.last?.date != last.date { points.append(Point(date: last.date, value: last.balance)) }
        let first = points.first, end = points.last

        return ReportPanel(title: "Cash Balance", summary: "Your checking and savings at the start of each of the next six months, with bills and your usual income and spending.",
                           headline: end.map { ReportFormat.money($0.value) }, headlineNote: first == nil ? nil : "from \(ReportFormat.money(first?.value ?? 0)) today") {
            if points.count < 3 {
                ReportEmpty(message: snapshot == nil ? "Calculating…" : "Needs at least four months of history and a checking or savings account.", height: ReportSize.h(190))
            } else {
                Chart(points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Balance", point.value)).foregroundStyle(Color.accentColor.opacity(0.12))
                    LineMark(x: .value("Date", point.date), y: .value("Balance", point.value))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [5, 4]))
                    PointMark(x: .value("Date", point.date), y: .value("Balance", point.value)).foregroundStyle(Color.accentColor)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: ReportSize.h(190))
            }
        }
    }
}

@MainActor
func cashForecastWeeks(accounts: [Account], bills: [Bill], context: ModelContext, snapshot: LedgerSnapshot) -> [ReportMath.ForecastWeek] {
    let calendar = Calendar.current
    let since = calendar.date(byAdding: .month, value: -3, to: calendar.dateInterval(of: .month, for: .now)?.start ?? .now) ?? .now
    let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.paidBill != nil && $0.date >= since && $0.amount < 0 })
    let paid = ((try? context.fetch(descriptor)) ?? []).live.reduce(Decimal(0)) { $0 - $1.amount }
    return ReportMath.forecast(accounts: accounts, bills: bills.live, snapshot: snapshot, billPayments: paid).weeks
}

// MARK: Spending and income

struct SpendingProjectionReport: View {
    var body: some View { FlowProjection(title: "Spending", summary: "Spending for the last six months and the next six, at your average over the last three full months.", income: false) }
}

struct IncomeProjectionReport: View {
    var body: some View { FlowProjection(title: "Income", summary: "Income for the last six months and the next six, at your average over the last three full months.", income: true) }
}

private struct FlowProjection: View {
    let title: String
    let summary: String
    let income: Bool
    @Environment(\.reportInputs) private var inputs

    private struct Bar: Identifiable {
        let date: Date
        let value: Double
        let projected: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(projected)" }
    }

    var body: some View {
        let totals = inputs.monthlyTotals()
        let calendar = Calendar.current
        let values = totals.map { income ? $0.income : $0.spending }
        let recent = values.suffix(4).dropLast()
        let average = recent.reduce(0, +) / Double(max(recent.count, 1))
        let past = totals.indices.suffix(6).map { Bar(date: totals[$0].date, value: values[$0], projected: false) }
        let future = (1...ReportTrends.futureMonths).compactMap { month in
            calendar.date(byAdding: .month, value: month, to: totals[totals.count - 1].date).map { Bar(date: $0, value: average, projected: true) }
        }
        let color: Color = income ? Theme.green : Theme.red

        return ReportPanel(title: title, summary: summary, headline: average > 0 ? ReportFormat.money(average) : nil, headlineNote: average > 0 ? "expected per month" : nil) {
            if average == 0 && past.allSatisfy({ $0.value == 0 }) {
                ReportEmpty(message: "Nothing recorded yet.", height: ReportSize.h(170))
            } else {
                Chart(past + future) { bar in
                    BarMark(x: .value("Month", bar.date, unit: .month), y: .value(title, bar.value))
                        .foregroundStyle(color)
                        .opacity(bar.projected ? 0.4 : 1)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: ReportSize.h(170))
            }
        }
    }
}

// MARK: Loan and card balances

private struct BalanceLines: View {
    let title: String
    let summary: String
    let accounts: [Account]
    let empty: String

    private struct Point: Identifiable {
        let name: String
        let date: Date
        let value: Double
        var id: String { "\(name)-\(date.timeIntervalSince1970)" }
    }

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let points = accounts.flatMap { account -> [Point] in
            let path = ReportTrends.debtPath(for: account).owed
            return path.indices.compactMap { index in
                calendar.date(byAdding: .month, value: index, to: start).map { Point(name: account.name, date: $0, value: path[index]) }
            }
        }
        let now = accounts.reduce(0.0) { $0 + Goal.owed(on: $1).doubleValue }
        let later = points.filter { $0.date == (calendar.date(byAdding: .month, value: ReportTrends.futureMonths, to: start) ?? start) }.reduce(0.0) { $0 + $1.value }

        return ReportPanel(title: title, summary: summary, headline: accounts.isEmpty ? nil : ReportFormat.money(later), headlineNote: accounts.isEmpty ? nil : "in 6 months, from \(ReportFormat.money(now))") {
            if accounts.isEmpty {
                ReportEmpty(message: empty, height: ReportSize.h(170))
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Month", point.date, unit: .month), y: .value("Owed", point.value))
                        .foregroundStyle(by: .value("Account", point.name))
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: ReportSize.h(180))
            }
        }
    }
}

struct LoanBalancesProjectionReport: View {
    @Query private var allAccounts: [Account]
    var body: some View {
        BalanceLines(title: "Loan Balances", summary: "What each loan will owe after each of the next six payments, with interest.",
                     accounts: allAccounts.live.filter { $0.isLoan && !$0.isClosed && Goal.owed(on: $0) > 0 }, empty: "No loans with a balance.")
    }
}

struct CardBalancesProjectionReport: View {
    @Query private var allAccounts: [Account]
    var body: some View {
        BalanceLines(title: "Credit Card Balances", summary: "What each card will owe after six months of paying the minimum, with interest and no new charges.",
                     accounts: allAccounts.live.filter { $0.isCreditCard && !$0.isClosed && Goal.owed(on: $0) > 0 }, empty: "No credit cards with a balance.")
    }
}

// MARK: Goal finish dates

struct GoalFinishDatesReport: View {
    @Query(sort: \Goal.createdAt) private var allGoals: [Goal]

    var body: some View {
        let goals = allGoals.live.filter { !$0.isArchived }
        let calendar = Calendar.current

        ReportPanel(title: "Goal Finish Dates", summary: "When each goal lands at your current pace, against the date you set.") {
            if goals.isEmpty {
                ReportEmpty(message: "No goals yet. Set one up in Planning.", height: ReportSize.h(140))
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    GridRow {
                        Text("GOAL"); Text("TARGET DATE").gridColumnAlignment(.trailing); Text("AT THIS PACE").gridColumnAlignment(.trailing); Text("DIFFERENCE").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(4)
                    ForEach(goals) { goal in
                        let progress = goal.progress()
                        let estimate = progress.projectedDate
                        let months = goal.targetDate.flatMap { target in estimate.map { calendar.dateComponents([.month], from: $0, to: target).month ?? 0 } }
                        GridRow {
                            Label(goal.name, systemImage: goal.symbol).lineLimit(1)
                            Text(goal.targetDate.map(ReportFormat.month) ?? "—")
                            Text(estimate.map(ReportFormat.month) ?? (progress.isAchieved ? "Reached" : "No pace yet"))
                            if let months {
                                Text(months >= 0 ? "\(months) mo early" : "\(-months) mo late").foregroundStyle(months >= 0 ? Theme.green : .orange)
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}
