import SwiftUI
import SwiftData
import Charts

/// Small versions of the three reports, for the top of the Summary and Home screens.
struct GlanceCards: View {
    let accounts: [Account]
    let transactions: [Transaction]

    var body: some View {
        HStack(alignment: .top, spacing: 12) { cards }
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var cards: some View {
        SpendingGlance(transactions: transactions)
        LiabilitiesGlance(accounts: accounts)
        InvestmentsGlance(accounts: accounts)
    }
}

private func percent(_ value: Double, signed: Bool = false, digits: Int = 0) -> String {
    (signed && value >= 0 ? "+" : "") + value.formatted(.percent.precision(.fractionLength(digits)))
}

private struct GlancePlaceholder: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tertiary)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct GlanceRow: View {
    let title: String
    let amount: Decimal
    var color: Color?

    init(_ title: String, _ amount: Decimal, color: Color? = nil) {
        self.title = title
        self.amount = amount
        self.color = color
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(amount, format: .appCurrency).foregroundStyle(color ?? .primary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Sparkline

/// A small line with no axes: twelve months in solid and six projected, dashed.
struct Sparkline: View {
    let points: [TrendPoint]
    let color: Color
    var height: CGFloat = 70

    var body: some View {
        let history = points.filter { !$0.projected }
        let future = points.filter(\.projected)
        Chart {
            ForEach(history) { point in
                AreaMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value)).foregroundStyle(color.opacity(0.12))
                LineMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value), series: .value("Part", "History"))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round)).interpolationMethod(.monotone)
            }
            ForEach(future) { point in
                LineMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value), series: .value("Part", "Projection"))
                    .foregroundStyle(color.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 2.2, dash: [4, 3])).interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: height)
    }
}

// MARK: Income and spending

struct SpendingGlance: View {
    let transactions: [Transaction]

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let count = snapshot?.income.count ?? 0
        let income = snapshot.map { $0.income.map(\.doubleValue) } ?? []
        let spending = snapshot.map { $0.spending.map(\.doubleValue) } ?? []
        let monthIncome = income.last ?? 0, monthSpending = spending.last ?? 0
        let net = monthIncome - monthSpending
        let empty = snapshot != nil && income.allSatisfy { $0 == 0 } && spending.allSatisfy { $0 == 0 }

        ReportPanel(title: "Income & Spending", summary: "This month and the last six.",
                    headline: snapshot == nil || empty ? nil : ReportFormat.money(net), headlineNote: snapshot == nil || empty ? nil : "kept this month") {
            if snapshot == nil {
                ReportCalculating(height: 150)
            } else if empty {
                ReportEmpty(message: "Income and spending appear here once you record some transactions.", height: 160, shape: .bars)
            } else if let snapshot {
                let starts = Array(snapshot.monthStarts.suffix(6))
                let bars = starts.indices.flatMap { index -> [Bar] in
                    let source = count - starts.count + index
                    return [Bar(date: starts[index], kind: "Income", value: income[source]), Bar(date: starts[index], kind: "Spending", value: spending[source])]
                }
                Chart(bars) { bar in
                    BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                        .foregroundStyle(by: .value("Kind", bar.kind))
                        .position(by: .value("Kind", bar.kind))
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale(["Income": Theme.green, "Spending": Theme.red])
                .chartLegend(.hidden)
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
                .frame(height: 70)
                VStack(spacing: 5) {
                    GlanceRow("Income", Decimal(monthIncome), color: Theme.green)
                    GlanceRow("Spending", Decimal(monthSpending), color: Theme.red)
                }
                if count >= 2, spending[count - 2] > 0 {
                    let change = (monthSpending - spending[count - 2]) / spending[count - 2]
                    Text("Spending \(change >= 0 ? "up" : "down") \(percent(abs(change))) vs last month")
                        .font(.caption)
                        .foregroundStyle(change <= 0 ? Theme.green : Theme.red)
                } else if monthIncome > 0 {
                    Text("\(percent(net / monthIncome)) of income kept").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .environment(\.reportCardMinHeight, 250)
    }
}

// MARK: Liabilities

struct LiabilitiesGlance: View {
    let accounts: [Account]

    var body: some View {
        let report = LedgerIndex.shared.whileStale { Liabilities.build(accounts) }
        let snapshot = LedgerIndex.shared.latest
        let none = report?.lines.isEmpty == true

        ReportPanel(title: "Liabilities", summary: "What you owe, and where it's heading.",
                    headline: report == nil || none ? nil : ReportFormat.money(report?.totalOwed.doubleValue ?? 0),
                    headlineNote: report == nil || none ? nil : "\(report?.outstanding ?? 0) of \(report?.lines.count ?? 0) outstanding") {
            if report == nil {
                ReportCalculating(height: 150)
            } else if none {
                ReportEmpty(message: "Add a credit card, mortgage or loan in Settings ▸ Accounts to track what you owe.", height: 160, shape: .line)
            } else if let report {
                if let snapshot {
                    Sparkline(points: ReportTrends.debt(accounts: accounts, snapshot: snapshot), color: Theme.red)
                }
                if let fraction = report.payoffFraction {
                    ProgressView(value: fraction).tint(Theme.green)
                    Text("\(percent(fraction)) of borrowed loans paid off").font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 5) {
                    if let ratio = report.debtToAssets {
                        HStack {
                            Text("Leverage").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(percent(ratio)) of assets").foregroundStyle(ratio < 0.3 ? Theme.green : ratio < 0.6 ? .orange : Theme.red)
                        }
                        .font(.callout)
                    }
                    if report.monthlyPayments > 0 { GlanceRow("Monthly payments", report.monthlyPayments) }
                    if let date = report.debtFreeDate {
                        HStack {
                            Text("Debt-free").foregroundStyle(.secondary)
                            Spacer()
                            Text(date.formatted(.dateTime.month(.abbreviated).year()))
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .environment(\.reportCardMinHeight, 250)
    }
}

// MARK: Investments

struct InvestmentsGlance: View {
    let accounts: [Account]

    var body: some View {
        let range = ReportRange(start: Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now, end: Date.now.addingTimeInterval(1))
        let report = LedgerIndex.shared.whileStale { Investments.build(accounts, range: range) }
        let snapshot = LedgerIndex.shared.latest
        let none = report?.lines.isEmpty == true

        ReportPanel(title: "Investments", summary: "Value over the last year and six months ahead.",
                    headline: report == nil || none ? nil : ReportFormat.money(report?.end.doubleValue ?? 0),
                    headlineNote: report == nil || none ? nil : report?.returnRate.map { "\(percent($0, signed: true, digits: 1)) return, 3 months" }) {
            if report == nil {
                ReportCalculating(height: 150)
            } else if none {
                ReportEmpty(message: "Add a 401(k), IRA or brokerage in Settings ▸ Accounts to see how it grows.", height: 160, shape: .line)
            } else if let report {
                if let snapshot { Sparkline(points: history(snapshot), color: Theme.green) }
                VStack(spacing: 5) {
                    GlanceRow("Growth, 3 months", report.growth, color: report.growth >= 0 ? Theme.green : Theme.red)
                    GlanceRow("Contributions, 3 months", report.contributions)
                }
                Text("\(report.lines.count) account\(report.lines.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
        }
        .environment(\.reportCardMinHeight, 250)
    }

    /// Twelve months of total value and six projected at the pace of the last three.
    private func history(_ snapshot: LedgerSnapshot) -> [TrendPoint] {
        let owned = accounts.live.filter { $0.type.group == .investments && !$0.isClosed }
        guard let first = owned.first else { return [] }
        let months = ReportMath.history(of: first, snapshot: snapshot).count
        let past = (0..<months).map { index -> TrendPoint in
            let date = ReportMath.history(of: first, snapshot: snapshot)[index].date
            let total = owned.reduce(0.0) { $0 + ReportMath.history(of: $1, snapshot: snapshot)[index].value }
            return TrendPoint(date: date, value: total, projected: false)
        }
        guard past.count >= 4, let last = past.last else { return past }
        let change = (last.value - past[past.count - 4].value) / 3
        return past + ReportMath.future(from: last) { last.value + change * Double($0) }
    }
}

// MARK: Loans

/// Every mortgage and loan with a progress bar: what's still owed and how much has been paid off.
struct LoansProgressCard: View {
    let accounts: [Account]

    var body: some View {
        let loans = LedgerIndex.shared.whileStale { Liabilities.build(accounts).lines.filter(\.isLoan) }
        ReportCard(title: "Loans · Progress") {
            if loans == nil {
                Text("Calculating…").font(.callout).foregroundStyle(.secondary)
            } else if let loans, loans.isEmpty {
                GlancePlaceholder(symbol: "banknote", text: "No mortgages or loans yet. Add one in Settings ▸ Accounts to watch it get paid off.")
            } else if let loans {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 28, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(loans) { row($0) }
                }
            }
        }
    }

    private func row(_ line: Liabilities.Line) -> some View {
        let progress = line.progress
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.name).fontWeight(.medium)
                    Text(line.purpose.isEmpty ? line.typeTitle : "\(line.typeTitle) · \(line.purpose)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if line.isPaidOff {
                    Label("Paid off", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.callout)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(line.owed, format: .appCurrency).fontWeight(.semibold)
                        Text("still owed").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if line.hasProgress {
                ProgressView(value: progress.fraction).tint(Theme.green)
                HStack {
                    Text("\(percent(progress.fraction)) paid off")
                    Spacer()
                    Text("\(progress.paidOff.formatted(.appCurrency)) of \(progress.original.formatted(.appCurrency))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !line.isPaidOff {
                Text("Add the original loan amount in Settings ▸ Accounts to track payoff.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A read-only look at where each open goal stands. There is nothing to add or edit here: progress is made from Planning.
struct GoalsProgressCard: View {
    @Query(sort: \Goal.createdAt) private var allGoals: [Goal]

    private var goals: [Goal] {
        // A debt goal that follows a loan or card is already shown with the loans, so it is left out here.
        let open = allGoals.live.filter { !$0.isArchived && !($0.isPayoff && $0.isLinked) }
        let dated = open.filter { $0.targetDate != nil }.sorted { $0.targetDate! < $1.targetDate! }
        return dated + open.filter { $0.targetDate == nil }.sorted { $0.name < $1.name }
    }

    var body: some View {
        let list = goals
        ReportCard(title: "Goals · Progress") {
            if list.isEmpty {
                GlancePlaceholder(symbol: "target", text: "No goals yet. Set one up in Planning to watch your progress here.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 28, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(list) { row($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ goal: Goal) -> some View {
        if goal.isLive {
            let progress = goal.progress()
            let color = Color(hex: goal.colorHex)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        Image(systemName: goal.symbol).foregroundStyle(color).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(goal.name).fontWeight(.medium)
                            Text(subtitle(goal, progress)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    status(progress)
                }
                ProgressView(value: progress.fraction).tint(progress.isAchieved ? Theme.green : color)
                HStack {
                    Text("\(progress.fraction.formatted(.percent.precision(.fractionLength(0)))) \(goal.isPayoff ? "paid" : "saved")")
                    Spacer()
                    Text("\(goal.saved.formatted(.appCurrency)) of \(goal.targetAmount.formatted(.appCurrency))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(_ goal: Goal, _ p: GoalProgress) -> String {
        var parts: [String] = []
        if goal.isPayoff { parts.append("\(goal.owedNow.formatted(.appCurrency)) still owed") }
        if let date = goal.targetDate { parts.append("by \(date.formatted(.dateTime.month(.abbreviated).year()))") }
        if let needed = p.neededPerMonth { parts.append("\(needed.formatted(.appCurrency))/mo") }
        return parts.isEmpty ? (goal.categoryName.isEmpty ? "No date set" : goal.categoryName) : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func status(_ p: GoalProgress) -> some View {
        switch p.status {
        case .achieved: Label("Reached", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.callout)
        case .onTrack: Label("On track", systemImage: "checkmark.circle").foregroundStyle(Theme.green).font(.callout)
        case .behind: Label("Behind", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
        case .pastDue: Label("Past date", systemImage: "exclamationmark.octagon.fill").foregroundStyle(Theme.red).font(.callout)
        case .noDate: EmptyView()
        }
    }
}
