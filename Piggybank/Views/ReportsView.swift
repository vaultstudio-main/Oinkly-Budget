import SwiftUI
import SwiftData
import Charts

/// Monthly, quarterly, 6-month and yearly reports.
struct ReportsView: View {
    @Query private var allTransactions: [Transaction]
    private var transactions: [Transaction] { allTransactions.live }

    @State private var period: ReportPeriod = .monthly
    @State private var anchor = Date.now

    var body: some View {
        let range = Reports.range(period, anchor: anchor)
        let report = Reports.build(transactions, period: period, range: range)

        ScrollView {
            VStack(spacing: 14) {
                PageTitle("Reports")
                controls(range: range)
                if report.totals.count == 0 {
                    PlaceholderTiles(titles: ["Income", "Spending", "Net", "Savings Rate"])
                    ReportCard(title: "Income vs Spending") {
                        NoDataNote(message: "No data for \(Reports.label(period, range: range)). Pick another period, or add some transactions.")
                    }
                    ReportCard(title: "Spending by Category") {
                        NoDataNote(message: "No data yet. Spending by category shows up here once you add transactions.")
                    }
                } else {
                    tiles(report)
                    ReportCard(title: "Income vs Spending") { chart(report) }
                    ReportCard(title: "Spending by Category") { categories(report) }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .animation(.smooth, value: period)
    }

    // MARK: Controls

    private var earliest: Date? { transactions.map(\.date).min() }

    private func controls(range: ReportRange) -> some View {
        PeriodControls(periods: ReportPeriod.allCases, period: $period, anchor: $anchor, earliest: earliest)
    }

    // MARK: Summary tiles

    private func tiles(_ report: Reports.Report) -> some View {
        let totals = report.totals
        return StatGrid {
            tile("Income", totals.income, color: Theme.green, change: Reports.change(from: report.previous.income, to: totals.income), higherIsGood: true)
            tile("Spending", totals.spending, color: Theme.red, change: Reports.change(from: report.previous.spending, to: totals.spending), higherIsGood: false)
            tile("Net", totals.net, color: totals.net >= 0 ? Theme.green : Theme.red, change: nil, higherIsGood: true)
            StatTile(title: "Savings Rate") {
                Text(totals.savingsRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                    .foregroundStyle(totals.savingsRate.map { $0 >= 0 ? Theme.green : Theme.red } ?? .secondary)
            } note: {
                Text("of income kept")
            }
        }
    }

    private func tile(_ title: String, _ amount: Decimal, color: Color, change: Double?, higherIsGood: Bool) -> some View {
        StatTile(title: title) {
            Text(amount, format: .appCurrency).foregroundStyle(color)
        } note: {
            if let change {
                let good = (change >= 0) == higherIsGood
                HStack(spacing: 3) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(abs(change).formatted(.percent.precision(.fractionLength(0)))) vs previous")
                }
                .foregroundStyle(good ? Theme.green : Theme.red)
            } else {
                Text(title == "Net" ? "income minus spending" : "no earlier period")
            }
        }
    }

    // MARK: Chart

    private struct Point: Identifiable {
        let label: String
        let kind: String
        let value: Double
        var id: String { "\(label)-\(kind)" }
    }

    private func chart(_ report: Reports.Report) -> some View {
        var points: [Point] = []
        for bucket in report.buckets {
            points.append(Point(label: bucket.label, kind: "Income", value: bucket.income.doubleValue))
            points.append(Point(label: bucket.label, kind: "Spending", value: bucket.spending.doubleValue))
        }
        return Chart(points) { point in
            BarMark(x: .value("Period", point.label), y: .value("Amount", point.value))
                .foregroundStyle(by: .value("Kind", point.kind))
                .position(by: .value("Kind", point.kind))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(["Income": Theme.green, "Spending": Theme.red])
        .chartLegend(position: .top, alignment: .trailing)
        .frame(height: 220)
    }

    // MARK: Categories

    private func categories(_ report: Reports.Report) -> some View {
        let total = report.totals.spending
        let lines = report.spending
        let shown = Array(lines.prefix(12))
        let otherAmount = lines.dropFirst(12).reduce(Decimal(0)) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 14) {
            if lines.isEmpty {
                Text("No spending in this period.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(shown) { line in
                row(symbol: line.symbol, color: Color(hex: line.colorHex), name: line.name, amount: line.amount, total: total)
            }
            if otherAmount > 0 {
                row(symbol: "ellipsis.circle", color: .gray, name: "Everything else", amount: otherAmount, total: total)
            }
        }
    }

    private func row(symbol: String, color: Color, name: String, amount: Decimal, total: Decimal) -> some View {
        let share = total > 0 ? (amount / total).doubleValue : 0
        return HStack(spacing: 12) {
            CategoryBadge(symbol: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(name)
                    Spacer()
                    Text(amount, format: .appCurrency)
                    Text(share.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.callout)
                ProgressView(value: share).tint(color)
            }
        }
    }
}

// MARK: Shared styling

extension View {
    func tileStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    fileprivate var tileBackground: some ShapeStyle {
        AnyShapeStyle(Theme.panel)
    }
}

/// A titled card: the dark panel on the Mac.
struct ReportCard<Content: View>: View {
    let title: String
    var fillsHeight = false
    @ViewBuilder let content: Content

    var body: some View {
        Panel(title: title, fillsHeight: fillsHeight) { content }
    }
}
