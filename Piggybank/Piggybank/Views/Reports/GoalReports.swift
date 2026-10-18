import SwiftUI
import SwiftData
import Charts

private func statusLabel(_ progress: GoalProgress) -> (text: String, symbol: String, color: Color) {
    switch progress.status {
    case .achieved: ("Reached", "checkmark.seal.fill", Theme.green)
    case .onTrack: ("On track", "checkmark.circle.fill", Theme.green)
    case .behind: ("Behind", "exclamationmark.triangle.fill", .orange)
    case .pastDue: ("Past date", "exclamationmark.octagon.fill", Theme.red)
    case .noDate: ("No date", "minus.circle", .secondary)
    }
}

// MARK: Goal progress

struct GoalProgressReport: View {
    @Query(sort: \Goal.createdAt) private var allGoals: [Goal]

    var body: some View {
        let goals = allGoals.live.filter { !$0.isArchived }
        let saved = goals.filter { !$0.isPayoff }.reduce(Decimal(0)) { $0 + min($1.saved, $1.targetAmount) }
        let target = goals.filter { !$0.isPayoff }.reduce(Decimal(0)) { $0 + $1.targetAmount }

        ReportPanel(title: "Goal Progress", summary: "Every open goal against its target, with the estimated finish and whether it will make its date.",
                    headline: goals.isEmpty ? nil : saved.formatted(.appCurrency), headlineNote: goals.isEmpty ? nil : "saved of \(target.formatted(.appCurrency))") {
            if goals.isEmpty {
                ReportEmpty(message: "No goals yet. Set one up in Planning.", height: 170)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 11) {
                    GridRow {
                        Text("GOAL").gridColumnAlignment(.leading)
                        Text("PROGRESS").gridColumnAlignment(.leading)
                        Text("DONE").gridColumnAlignment(.trailing)
                        Text("LEFT").gridColumnAlignment(.trailing)
                        Text("TARGET DATE").gridColumnAlignment(.trailing)
                        Text("EST. FINISH").gridColumnAlignment(.trailing)
                        Text("STATUS").gridColumnAlignment(.leading)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(7)
                    ForEach(goals) { goal in
                        let progress = goal.progress()
                        let status = statusLabel(progress)
                        GridRow {
                            Label(goal.name, systemImage: goal.symbol).foregroundStyle(.primary).lineLimit(1)
                            ProgressView(value: progress.fraction).tint(Color(hex: goal.colorHex)).frame(minWidth: 90)
                            Text("\(goal.saved.formatted(.appCurrency)) of \(goal.targetAmount.formatted(.appCurrency))")
                            Text(progress.remaining, format: .appCurrency)
                            Text(goal.targetDate.map(ReportFormat.month) ?? "—")
                            Text(progress.projectedDate.map(ReportFormat.month) ?? "—")
                            Label(status.text, systemImage: status.symbol).foregroundStyle(status.color).font(.caption)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: On track or behind

struct GoalStatusReport: View {
    @Query(sort: \Goal.createdAt) private var allGoals: [Goal]

    private struct Slice: Identifiable {
        let name: String
        let count: Int
        let color: Color
        var id: String { name }
    }

    var body: some View {
        let goals = allGoals.live.filter { !$0.isArchived }
        let reached = allGoals.live.filter(\.isArchived).count
        let groups = Dictionary(grouping: goals) { statusLabel($0.progress()).text }
        let slices = [("On track", Theme.green), ("Behind", Color.orange), ("Past date", Theme.red), ("No date", Color.secondary)]
            .compactMap { name, color in groups[name].map { Slice(name: name, count: $0.count, color: color) } }
            + (reached > 0 ? [Slice(name: "Reached", count: reached, color: .teal)] : [])
        let behind = goals.filter { $0.progress().status == .behind || $0.progress().status == .pastDue }

        ReportPanel(title: "On Track or Behind", summary: "Which goals will make their date and which need more.") {
            if goals.isEmpty && reached == 0 {
                ReportEmpty(message: "No goals yet.", height: 170)
            } else {
                HStack(spacing: 18) {
                    Chart(slices) { slice in
                        SectorMark(angle: .value("Goals", slice.count), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(slice.color)
                            .cornerRadius(3)
                    }
                    .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: 9, height: 9)
                                Text(slice.name)
                                Spacer()
                                Text("\(slice.count)").foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
                if !behind.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NEEDS CATCHING UP").font(.caption2).foregroundStyle(.secondary)
                        ForEach(behind.prefix(4)) { goal in
                            let progress = goal.progress()
                            let extra = (progress.neededPerMonth ?? 0) - max(progress.monthlyPace ?? 0, 0)
                            HStack {
                                Text(goal.name).lineLimit(1)
                                Spacer()
                                Text(progress.status == .pastDue ? "Past its date" : "+\(max(extra, 0).formatted(.appCurrency))/mo")
                                    .foregroundStyle(.orange)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Needed per month

struct GoalNeededReport: View {
    @Query(sort: \Goal.createdAt) private var allGoals: [Goal]

    private struct Row: Identifiable {
        let name: String
        let kind: String
        let amount: Double
        var id: String { "\(name)-\(kind)" }
    }

    var body: some View {
        let goals = allGoals.live.filter { !$0.isArchived && $0.progress().neededPerMonth != nil }
        let rows = goals.flatMap { goal -> [Row] in
            let progress = goal.progress()
            return [Row(name: goal.name, kind: "Needed", amount: (progress.neededPerMonth ?? 0).doubleValue),
                    Row(name: goal.name, kind: "Your pace", amount: max((progress.monthlyPace ?? 0).doubleValue, 0))]
        }
        let needed = goals.reduce(Decimal(0)) { $0 + ($1.progress().neededPerMonth ?? 0) }

        ReportPanel(title: "Needed Per Month", summary: "What each goal needs every month to finish on time, against the pace you're on.",
                    headline: goals.isEmpty ? nil : needed.formatted(.appCurrency), headlineNote: goals.isEmpty ? nil : "needed in all, per month") {
            if goals.isEmpty {
                ReportEmpty(message: "Needs a goal with a target date.", height: 170)
            } else {
                Chart(rows) { row in
                    BarMark(x: .value("Per month", row.amount), y: .value("Goal", row.name))
                        .foregroundStyle(by: .value("Kind", row.kind))
                        .position(by: .value("Kind", row.kind))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(["Needed": Color.orange, "Your pace": Theme.green])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: max(CGFloat(goals.count) * 54, 150))
            }
        }
    }
}

// MARK: Savings growth

struct SavingsGrowthReport: View {
    @Query private var allAccounts: [Account]

    private struct Line: Identifiable {
        let name: String
        let date: Date
        let value: Double
        let projected: Bool
        var id: String { "\(name)-\(date.timeIntervalSince1970)-\(projected)" }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let savings = allAccounts.live.filter { ($0.type == .savings || $0.type == .moneyMarket) && !$0.isClosed }

        ReportPanel(title: "Savings Growth", summary: "Your savings accounts over the last year, and six months ahead at their recent pace.") {
            if savings.isEmpty {
                ReportEmpty(message: "Add a savings account to see its growth.", height: 190)
            } else if let snapshot {
                let lines = savings.flatMap { account -> [Line] in
                    let history = ReportMath.history(of: account, snapshot: snapshot)
                    guard history.count >= 4, let last = history.last else { return [] }
                    let change = (last.value - history[history.count - 4].value) / 3
                    let future = ReportMath.future(from: last) { last.value + change * Double($0) }
                    return history.map { Line(name: account.name, date: $0.date, value: $0.value, projected: false) }
                        + future.map { Line(name: account.name, date: $0.date, value: $0.value, projected: true) }
                }
                Chart(lines) { line in
                    LineMark(x: .value("Month", line.date, unit: .month), y: .value("Balance", line.value),
                             series: .value("Series", "\(line.name)-\(line.projected)"))
                        .foregroundStyle(by: .value("Account", line.name))
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: line.projected ? [5, 4] : []))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 200)
                ReportKey(items: [.init(color: .secondary, text: "Last 12 months"), .init(color: .secondary, text: "Next 6 months", dashed: true)])
            } else {
                ReportCalculating(height: 190)
            }
        }
    }
}

// MARK: Emergency fund

struct EmergencyFundReport: View {
    @Query private var allAccounts: [Account]
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let savings = allAccounts.live.filter { ($0.type == .savings || $0.type == .moneyMarket) && !$0.isClosed }
        let balance = savings.reduce(Decimal(0)) { $0 + max($1.balance, 0) }.doubleValue
        let months = ReportInputs.months()
        let totals = inputs.monthlyTotals()
        // Average of the last three full months of spending.
        let recent = totals.suffix(4).dropLast()
        let monthlySpending = recent.isEmpty ? 0 : recent.reduce(0) { $0 + $1.spending } / Double(recent.count)
        let coverage = monthlySpending > 0 ? balance / monthlySpending : nil
        let goal = 6.0

        ReportPanel(title: "Emergency Fund Coverage", summary: "How many months of spending your savings would cover. Three to six months is a common aim.",
                    headline: coverage.map { "\($0.formatted(.number.precision(.fractionLength(1)))) months" }, headlineNote: coverage == nil ? nil : "of spending covered") {
            if savings.isEmpty || months.isEmpty {
                ReportEmpty(message: "Add a savings account to see how many months it covers.", height: 170)
            } else if let coverage {
                HStack(spacing: 22) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 16)
                        Circle().trim(from: 0, to: min(coverage / goal, 1))
                            .stroke(coverage >= 3 ? Theme.green : (coverage >= 1 ? Color.orange : Theme.red), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(coverage.formatted(.number.precision(.fractionLength(1)))).font(.title2.bold())
                            Text("of \(Int(goal)) months").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 120, height: 120)
                    VStack(spacing: 8) {
                        ReportFigure(label: "Savings", value: ReportFormat.money(balance))
                        ReportFigure(label: "Spending per month", value: ReportFormat.money(monthlySpending), note: "average of the last 3 full months")
                        ReportFigure(label: "To reach \(Int(goal)) months", value: ReportFormat.money(max(monthlySpending * goal - balance, 0)))
                    }
                }
            } else {
                ReportEmpty(message: "Needs a few months of spending to work out coverage.", height: 170)
            }
        }
    }
}
