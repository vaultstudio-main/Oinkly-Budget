import SwiftUI
import SwiftData

/// Small versions of the three reports, for the top of the Summary and Home screens.
struct GlanceCards: View {
    let accounts: [Account]
    let transactions: [Transaction]

    var body: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 12) { cards }
            .fixedSize(horizontal: false, vertical: true)
        #else
        VStack(spacing: 16) { cards }
        #endif
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
    }
}

// MARK: Spending

struct SpendingGlance: View {
    let transactions: [Transaction]

    var body: some View {
        let range = Reports.range(.monthly, anchor: .now)
        let report = Reports.build(transactions, period: .monthly, range: range)
        let totals = report.totals
        ReportCard(title: "\(Reports.label(.monthly, range: range)) · Income & Spending", fillsHeight: true) {
            VStack(alignment: .leading, spacing: 8) {
                if totals.count == 0 {
                    Text("No transactions yet this month.").font(.callout).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(totals.net, format: .appCurrency)
                            .font(.title2.bold())
                            .foregroundStyle(totals.net >= 0 ? Theme.green : Theme.red)
                        Text("net").foregroundStyle(.secondary)
                        Spacer()
                        if let rate = totals.savingsRate {
                            Text("\(percent(Double(truncating: rate as NSDecimalNumber))) kept").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GlanceRow("Income", totals.income, color: Theme.green)
                    GlanceRow("Spending", totals.spending, color: Theme.red)
                    if let change = Reports.change(from: report.previous.spending, to: totals.spending) {
                        Text("Spending \(change >= 0 ? "up" : "down") \(percent(abs(change))) vs last month")
                            .font(.caption)
                            .foregroundStyle((change <= 0) ? Theme.green : Theme.red)
                    }
                }
            }
        }
    }
}

// MARK: Liabilities

struct LiabilitiesGlance: View {
    let accounts: [Account]

    var body: some View {
        let report = Liabilities.build(accounts)
        ReportCard(title: "Liabilities", fillsHeight: true) {
            VStack(alignment: .leading, spacing: 8) {
                if report.lines.isEmpty {
                    GlancePlaceholder(symbol: "scalemass", text: "No credit cards, mortgages or loans yet. Add one in Settings ▸ Accounts to track what you owe.")
                } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(report.totalOwed, format: .appCurrency).font(.title2.bold()).foregroundStyle(Theme.red)
                    Text("owed").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(report.outstanding) of \(report.lines.count) outstanding").font(.caption).foregroundStyle(.secondary)
                }
                if let fraction = report.payoffFraction {
                    ProgressView(value: fraction).tint(Theme.green)
                    Text("\(percent(fraction)) of borrowed loans paid off").font(.caption).foregroundStyle(.secondary)
                }
                if let ratio = report.debtToAssets {
                    HStack {
                        Text("Leverage").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(percent(ratio)) of assets").foregroundStyle(ratio < 0.3 ? Theme.green : ratio < 0.6 ? .orange : Theme.red)
                    }
                    .font(.callout)
                }
                if report.monthlyPayments > 0 { GlanceRow("Monthly payments", report.monthlyPayments) }
                }
            }
        }
    }
}

// MARK: Investments

struct InvestmentsGlance: View {
    let accounts: [Account]

    var body: some View {
        let range = Reports.range(.quarterly, anchor: .now)
        let report = Investments.build(accounts, range: range)
        ReportCard(title: "\(Reports.label(.quarterly, range: range)) · Investments", fillsHeight: true) {
            VStack(alignment: .leading, spacing: 8) {
                if report.lines.isEmpty {
                    GlancePlaceholder(symbol: "chart.line.uptrend.xyaxis", text: "No investment accounts yet. Add a 401(k), IRA or brokerage in Settings ▸ Accounts to see how it grows.")
                } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(report.end, format: .appCurrency).font(.title2.bold())
                    Spacer()
                    if let rate = report.returnRate {
                        Text("\(percent(rate, signed: true, digits: 1)) return")
                            .font(.caption)
                            .foregroundStyle(rate >= 0 ? Theme.green : Theme.red)
                    }
                }
                GlanceRow("Growth", report.growth, color: report.growth >= 0 ? Theme.green : Theme.red)
                GlanceRow("Contributions", report.contributions)
                Text("\(report.lines.count) account\(report.lines.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: Loans

/// Every mortgage and loan with a progress bar: what's still owed and how much has been paid off.
struct LoansProgressCard: View {
    let accounts: [Account]

    var body: some View {
        let loans = Liabilities.build(accounts).lines.filter(\.isLoan)
        ReportCard(title: "Loans · Progress") {
            if loans.isEmpty {
                GlancePlaceholder(symbol: "banknote", text: "No mortgages or loans yet. Add one in Settings ▸ Accounts to watch it get paid off.")
            } else {
                #if os(macOS)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 28, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(loans) { row($0) }
                }
                #else
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(loans) { row($0) }
                }
                #endif
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
        let open = allGoals.live.filter { !$0.isArchived }
        let dated = open.filter { $0.targetDate != nil }.sorted { $0.targetDate! < $1.targetDate! }
        return dated + open.filter { $0.targetDate == nil }.sorted { $0.name < $1.name }
    }

    var body: some View {
        let list = goals
        ReportCard(title: "Goals · Progress") {
            if list.isEmpty {
                GlancePlaceholder(symbol: "target", text: "No goals yet. Set one up in Planning to watch your progress here.")
            } else {
                #if os(macOS)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 28, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(list) { row($0) }
                }
                #else
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(list) { row($0) }
                }
                #endif
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
