import SwiftUI
import SwiftData
import Charts

// Each report below is a thin wrapper: it asks for the investment numbers (yours, or a sample portfolio when you have
// no investment account yet) and hands them to the card that draws them.

struct PortfolioValueReport: View {
    var body: some View { WithInvestmentsData { PortfolioValueCard(data: $0) } }
}
struct InvestmentAllocationReport: View {
    var body: some View { WithInvestmentsData { InvestmentAllocationCard(data: $0) } }
}
struct InvestmentBucketsReport: View {
    var body: some View { WithInvestmentsData { InvestmentBucketsCard(data: $0) } }
}
struct InvestmentGainsReport: View {
    var body: some View { WithInvestmentsData { InvestmentGainsCard(data: $0) } }
}
struct InvestmentContributionsReport: View {
    var body: some View { WithInvestmentsData { InvestmentContributionsCard(data: $0) } }
}
struct InvestmentGrowthReport: View {
    var body: some View { WithInvestmentsData { InvestmentGrowthCard(data: $0) } }
}

// MARK: Portfolio value

struct PortfolioValueCard: View {
    let data: InvestmentsData

    var body: some View {
        let history = data.history.filter { !$0.projected }
        let future = data.history.filter(\.projected)
        let last = history.last
        let end = future.last
        let change = (end?.value ?? 0) - (last?.value ?? 0)

        ReportPanel(title: "Portfolio Value", summary: "Your investments together over the last year, and six months ahead at your recent pace of growth and contributions.",
                    headline: last.map { ReportFormat.money($0.value) }, headlineNote: end == nil ? nil : "\(ReportFormat.money(end?.value ?? 0)) in 6 months", sample: data.isSample) {
            if history.isEmpty {
                ReportCalculating(height: 210)
            } else {
                Chart {
                    ForEach(history) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value), series: .value("Series", "History"))
                            .foregroundStyle(Theme.green).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)).interpolationMethod(.monotone)
                    }
                    ForEach(future) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value), series: .value("Series", "Projection"))
                            .foregroundStyle(Theme.green.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                    }
                    if let first = future.first {
                        RuleMark(x: .value("Today", first.date, unit: .month)).foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 210)
                HStack(spacing: 10) {
                    ReportFigure(label: "Today", value: ReportFormat.money(last?.value ?? 0))
                    ReportFigure(label: "In 6 months", value: ReportFormat.money(end?.value ?? 0), color: change >= 0 ? Theme.green : Theme.red)
                    ReportFigure(label: "Per month", value: ReportFormat.money(change / 6), note: "average of the last 3 months")
                    ReportFigure(label: "Growth, 12 months", value: ReportFormat.signed(Decimal(data.growth12)), color: data.growth12 >= 0 ? Theme.green : Theme.red)
                }
            }
        }
    }
}

// MARK: Allocation

struct InvestmentAllocationCard: View {
    let data: InvestmentsData

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    var body: some View {
        let byHolding = data.holdings.filter { $0.value > 0 }
        let slices = (byHolding.isEmpty ? data.accounts.filter { $0.value > 0 }.map { Slice(name: $0.name, value: $0.value) }
                                        : byHolding.map { Slice(name: $0.label, value: $0.value) }).sorted { $0.value > $1.value }
        let total = slices.reduce(0) { $0 + $1.value }

        ReportPanel(title: "Allocation", summary: byHolding.isEmpty ? "How your investments are split between accounts." : "How your investments are spread across your holdings.",
                    headline: slices.first.map { "\(Int($0.value / max(total, 1) * 100))% \($0.name)" }, headlineNote: slices.isEmpty ? nil : "largest position", sample: data.isSample) {
            if slices.isEmpty {
                ReportEmpty(message: "Nothing invested yet. Holdings and balances show here.", height: 190)
            } else {
                HStack(spacing: 18) {
                    Chart(slices) { slice in
                        SectorMark(angle: .value("Value", slice.value), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(by: .value("Holding", slice.name))
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 140, height: 140)
                    VStack(spacing: 7) {
                        ForEach(slices.prefix(7)) { slice in
                            HStack {
                                Text(slice.name).lineLimit(1)
                                Spacer()
                                Text(ReportFormat.money(slice.value))
                                Text((slice.value / max(total, 1)).formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Where it is

struct InvestmentBucketsCard: View {
    let data: InvestmentsData

    private static let colors: [String: Color] = ["Retirement": .purple, "Brokerage": .blue, "Education": .teal, "Crypto": .orange]

    var body: some View {
        let buckets = data.buckets
        let total = buckets.reduce(0) { $0 + $1.value }

        ReportPanel(title: "Where It Is", summary: "Retirement, brokerage, education and crypto: what share of your investments sits in each.", sample: data.isSample) {
            if buckets.isEmpty {
                ReportEmpty(message: "No investment accounts yet.", height: 190)
            } else {
                VStack(spacing: 12) {
                    ForEach(buckets, id: \.name) { bucket in
                        let share = total > 0 ? bucket.value / total : 0
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle().fill(Self.colors[bucket.name] ?? .gray).frame(width: 9, height: 9)
                                Text(bucket.name)
                                Spacer()
                                Text(ReportFormat.money(bucket.value))
                                Text(share.formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                            }
                            .font(.callout)
                            ProgressView(value: share).tint(Self.colors[bucket.name] ?? .gray)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Contributions

struct InvestmentContributionsCard: View {
    let data: InvestmentsData

    var body: some View {
        let total = data.contributed12
        ReportPanel(title: "Contributions", summary: "Money you've put in (or taken out), month by month. Growth isn't counted.",
                    headline: data.accounts.isEmpty ? nil : ReportFormat.money(total), headlineNote: data.accounts.isEmpty ? nil : "net over 12 months", sample: data.isSample) {
            if data.accounts.isEmpty {
                ReportEmpty(message: "No investment accounts yet.", height: 170)
            } else if data.contributions.allSatisfy({ $0.value == 0 }) {
                ReportEmpty(message: "No contributions in the last 12 months.", height: 170)
            } else {
                Chart(data.contributions) { month in
                    BarMark(x: .value("Month", month.date, unit: .month), y: .value("Contributed", month.value))
                        .foregroundStyle(month.value >= 0 ? Theme.green : Theme.red)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 170)
            }
        }
    }
}

// MARK: Growth by account

struct InvestmentGrowthCard: View {
    let data: InvestmentsData

    var body: some View {
        ReportPanel(title: "Growth by Account", summary: "What each account grew (or lost) over the last twelve months, as an amount and a return.",
                    headline: data.accounts.isEmpty ? nil : ReportFormat.signed(Decimal(data.growth12)), headlineNote: data.accounts.isEmpty ? nil : "in total", sample: data.isSample) {
            if data.accounts.isEmpty {
                ReportEmpty(message: "No investment accounts yet.", height: 170)
            } else {
                Chart(data.accounts) { account in
                    BarMark(x: .value("Growth", account.growth), y: .value("Account", account.name))
                        .foregroundStyle(account.growth >= 0 ? Theme.green : Theme.red)
                        .cornerRadius(3)
                        .annotation(position: account.growth >= 0 ? .trailing : .leading) {
                            Text("\(ReportFormat.signed(Decimal(account.growth)))\(account.growthRate.map { " · \(ReportFormat.percent($0 * 100, digits: 1))" } ?? "")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    RuleMark(x: .value("Zero", 0)).foregroundStyle(.secondary.opacity(0.5))
                }
                .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: max(CGFloat(data.accounts.count) * 40, 150))
            }
        }
    }
}

// MARK: Gains and losses

struct InvestmentGainsCard: View {
    let data: InvestmentsData

    var body: some View {
        let holdings = data.holdings.sorted { $0.gain > $1.gain }
        ReportPanel(title: "Gains and Losses", summary: "What each holding is worth against what you paid. Not realized until you sell.",
                    headline: holdings.isEmpty ? nil : ReportFormat.signed(Decimal(data.unrealizedGain)),
                    headlineNote: holdings.isEmpty || data.costBasis == 0 ? nil : "\(ReportFormat.percent(data.unrealizedGain / data.costBasis * 100, digits: 1)) on cost", sample: data.isSample) {
            if holdings.isEmpty {
                ReportEmpty(message: "No holdings yet. Add shares to an investment account to see gains and losses.", height: 170)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow {
                        Text("HOLDING"); Text("ACCOUNT"); Text("VALUE").gridColumnAlignment(.trailing); Text("COST").gridColumnAlignment(.trailing)
                        Text("GAIN").gridColumnAlignment(.trailing); Text("RETURN").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(6)
                    ForEach(holdings.prefix(10)) { holding in
                        GridRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(holding.label).fontWeight(.medium).lineLimit(1)
                                if holding.label != holding.name { Text(holding.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Text(holding.accountName).foregroundStyle(.secondary).lineLimit(1)
                            Text(ReportFormat.money(holding.value))
                            Text(ReportFormat.money(holding.cost)).foregroundStyle(.secondary)
                            Text(ReportFormat.signed(Decimal(holding.gain))).foregroundStyle(holding.gain >= 0 ? Theme.green : Theme.red)
                            Text(holding.gainRate.map { ReportFormat.percent($0 * 100, digits: 1) } ?? "—").foregroundStyle(holding.gain >= 0 ? Theme.green : Theme.red)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}
