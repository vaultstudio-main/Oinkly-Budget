import SwiftUI
import SwiftData
import Charts

// Each report below is a thin wrapper: it asks for the investment numbers and hands them to the card that draws them.
// With no investment account the cards keep their size and show an empty outline.

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
struct InvestmentProjectionReport: View {
    var body: some View { WithInvestmentsData { InvestmentProjectionCard(data: $0) } }
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
                    headline: last.map { ReportFormat.money($0.value) }, headlineNote: end == nil ? nil : "\(ReportFormat.money(end?.value ?? 0)) in 6 months") {
            if data.accounts.isEmpty {
                ReportEmpty(message: "Add an investment account to see its value and projection.", height: ReportSize.h(290), shape: .line)
            } else if history.isEmpty {
                ReportCalculating(height: ReportSize.h(290))
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
                .frame(height: ReportSize.h(210))
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
                    headline: slices.first.map { "\(Int($0.value / max(total, 1) * 100))% \($0.name)" }, headlineNote: slices.isEmpty ? nil : "largest position") {
            if slices.isEmpty {
                ReportEmpty(message: "Nothing invested yet. Holdings and balances show here.", height: ReportSize.h(150), shape: .ring)
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

        ReportPanel(title: "Where It Is", summary: "Retirement, brokerage, education and crypto: what share of your investments sits in each.") {
            if buckets.isEmpty {
                ReportEmpty(message: "No investment accounts yet.", height: ReportSize.h(170), shape: .table)
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
                    headline: data.accounts.isEmpty ? nil : ReportFormat.money(total), headlineNote: data.accounts.isEmpty ? nil : "net over 12 months") {
            if data.accounts.isEmpty {
                ReportEmpty(message: "No investment accounts yet.", height: ReportSize.h(170), shape: .bars)
            } else if data.contributions.allSatisfy({ $0.value == 0 }) {
                ReportEmpty(message: "No contributions in the last 12 months.", height: ReportSize.h(170), shape: .bars)
            } else {
                Chart(data.contributions) { month in
                    BarMark(x: .value("Month", month.date, unit: .month), y: .value("Contributed", month.value))
                        .foregroundStyle(month.value >= 0 ? Theme.green : Theme.red)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: ReportSize.h(170))
            }
        }
    }
}

// MARK: Growth by account

struct InvestmentGrowthCard: View {
    let data: InvestmentsData

    var body: some View {
        ReportPanel(title: "Growth by Account", summary: "What each account grew (or lost) over the last twelve months, as an amount and a return.",
                    headline: data.accounts.isEmpty ? nil : ReportFormat.signed(Decimal(data.growth12)), headlineNote: data.accounts.isEmpty ? nil : "in total") {
            if data.accounts.isEmpty {
                ReportEmpty(message: "No investment accounts yet.", height: ReportSize.h(200), shape: .bars)
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
                    headlineNote: holdings.isEmpty || data.costBasis == 0 ? nil : "\(ReportFormat.percent(data.unrealizedGain / data.costBasis * 100, digits: 1)) on cost") {
            if holdings.isEmpty {
                ReportEmpty(message: "No holdings yet. Add shares to an investment account to see gains and losses.", height: ReportSize.h(300), shape: .table)
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

// MARK: Projection of growth

struct InvestmentProjectionCard: View {
    let data: InvestmentsData

    /// The yearly return used. It comes from the last twelve months of recorded growth; with none recorded, 6% is assumed.
    private var rate: (value: Double, assumed: Bool) {
        let before = data.totalValue - data.growth12 - data.contributed12
        if data.growth12 != 0 && before > 0 { return (min(max(data.growth12 / before, -0.2), 0.3), false) }
        return (0.06, true)
    }

    /// The value after `months` months at a yearly `annual` return, adding `monthly` each month.
    private func value(after months: Int, annual: Double, monthly: Double) -> Double {
        let step = annual / 12
        var total = data.totalValue
        for _ in 0..<months { total = total * (1 + step) + monthly }
        return total
    }

    private struct Point: Identifiable {
        let years: Double
        let scenario: String
        let value: Double
        var id: String { "\(scenario)-\(years)" }
    }

    var body: some View {
        let (annual, assumed) = rate
        let monthly = data.contributed12 / 12
        let scenarios: [(String, Double, Color)] = [("Cautious", annual - 0.03, .orange), ("Expected", annual, Theme.green), ("Optimistic", annual + 0.03, .teal)]
        let horizons: [(String, Int)] = [("6 months", 6), ("1 year", 12), ("5 years", 60), ("10 years", 120)]
        let points = scenarios.flatMap { name, rate, _ in
            stride(from: 0, through: 120, by: 6).map { Point(years: Double($0) / 12, scenario: name, value: value(after: $0, annual: rate, monthly: monthly)) }
        }

        ReportPanel(title: "Projection of Growth", summary: "Where your investments could be in six months, a year, five and ten years, adding what you add now each month.",
                    headline: data.accounts.isEmpty ? nil : ReportFormat.money(value(after: 120, annual: annual, monthly: monthly)),
                    headlineNote: data.accounts.isEmpty ? nil : "expected in 10 years") {
            if data.accounts.isEmpty {
                ReportEmpty(message: "Add an investment account to see how it could grow.", height: ReportSize.h(340), shape: .line)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Years", point.years), y: .value("Value", point.value), series: .value("Scenario", point.scenario))
                        .foregroundStyle(by: .value("Scenario", point.scenario))
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: point.scenario == "Expected" ? [] : [5, 4]))
                        .interpolationMethod(.monotone)
                }
                .chartForegroundStyleScale(["Cautious": Color.orange, "Expected": Theme.green, "Optimistic": Color.teal])
                .chartXAxis { AxisMarks(values: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) { v in AxisValueLabel { if let n = v.as(Double.self) { Text(n == 0 ? "Now" : "\(Int(n))y") } } } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: ReportSize.h(200))

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("IN")
                        ForEach(scenarios, id: \.0) { Text($0.0.uppercased()).gridColumnAlignment(.trailing) }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(4)
                    ForEach(horizons, id: \.1) { label, months in
                        GridRow {
                            Text(label)
                            ForEach(scenarios, id: \.0) { _, rate, color in
                                Text(ReportFormat.money(value(after: months, annual: rate, monthly: monthly))).foregroundStyle(color)
                            }
                        }
                        .font(.callout)
                    }
                }
                Text(assumed
                     ? "Assumes 6% a year, with the cautious and optimistic paths 3 points either side, until you've recorded some growth. Adding \(ReportFormat.money(monthly)) a month."
                     : "Based on \(ReportFormat.percent(annual * 100, digits: 1)) a year, your return over the last 12 months, with the cautious and optimistic paths 3 points either side. Adding \(ReportFormat.money(monthly)) a month. A projection, not a promise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
