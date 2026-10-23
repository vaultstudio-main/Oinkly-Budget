import SwiftUI
import SwiftData
import Charts

// MARK: Assets vs liabilities

struct AssetsVsLiabilitiesReport: View {
    @Query private var allAccounts: [Account]

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        let projected: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(kind)-\(projected)" }
    }

    private func bars(_ points: [TrendPoint], _ kind: String) -> [Bar] {
        var seenProjection = false
        return points.compactMap { point in
            if point.projected && !seenProjection { seenProjection = true; return nil }
            return Bar(date: point.date, kind: kind, value: point.value, projected: point.projected)
        }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let accounts = allAccounts.live
        let assets = snapshot.map { ReportMath.assets(accounts: accounts, snapshot: $0) } ?? []
        let debt = snapshot.map { ReportTrends.debt(accounts: accounts, snapshot: $0) } ?? []
        let nowAssets = assets.last { !$0.projected }?.value ?? 0
        let nowDebt = debt.last { !$0.projected }?.value ?? 0

        ReportPanel(title: "Assets vs Liabilities", summary: "What you own against what you owe, month by month, and the next six months.",
                    headline: nowDebt > 0 ? "\((nowAssets / nowDebt).formatted(.number.precision(.fractionLength(1)))) : 1" : nil,
                    headlineNote: nowDebt > 0 ? "assets for every $1 owed" : nil) {
            if snapshot == nil {
                ReportCalculating(height: ReportSize.h(190))
            } else {
                // The first projected point repeats the last real month (it joins lines), so bars skip it.
                let bars = bars(assets, "Assets") + bars(debt, "Liabilities")
                Chart(bars) { bar in
                    BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                        .foregroundStyle(by: .value("Kind", bar.kind))
                        .position(by: .value("Kind", bar.kind))
                        .opacity(bar.projected ? 0.4 : 1)
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale(["Assets": Theme.green, "Liabilities": Theme.red])
                .chartLegend(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: ReportSize.h(190))
                ReportKey(items: [.init(color: Theme.green, text: "Assets"), .init(color: Theme.red, text: "Liabilities"),
                                  .init(color: .secondary, text: "Faded: next 6 months", dashed: true)])
            }
        }
    }
}

// MARK: By account type

struct NetWorthByTypeReport: View {
    @Query private var allAccounts: [Account]

    private struct Slice: Identifiable {
        let group: AccountGroup
        let value: Double
        var id: AccountGroup { group }
    }

    private static let colors: KeyValuePairs<String, Color> = [
        AccountGroup.checkingSavings.title: Theme.green,
        AccountGroup.investments.title: .purple,
        AccountGroup.assets.title: .teal,
    ]

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        ReportPanel(title: "Net Worth by Account Type", summary: "Where what you own is held, and what you owe.") {
            if let snapshot {
                let accounts = allAccounts.live
                let owned: [Slice] = [AccountGroup.checkingSavings, .investments, .assets].map {
                    Slice(group: $0, value: max(Summary.total(of: accounts, in: [$0], snapshot: snapshot).doubleValue, 0))
                }.filter { $0.value > 0 }
                let totalOwned = owned.reduce(0) { $0 + $1.value }
                let cards = -Summary.total(of: accounts, in: [.creditCards], snapshot: snapshot).doubleValue
                let loans = -Summary.total(of: accounts, in: [.loans], snapshot: snapshot).doubleValue
                if owned.isEmpty && cards <= 0 && loans <= 0 {
                    ReportEmpty(message: "Add accounts and transactions to see where your net worth sits.", height: ReportSize.h(190))
                } else {
                    HStack(alignment: .center, spacing: 20) {
                        Chart(owned) { slice in
                            SectorMark(angle: .value("Amount", slice.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                                .foregroundStyle(by: .value("Type", slice.group.title))
                                .cornerRadius(3)
                        }
                        .chartForegroundStyleScale(Self.colors)
                        .chartLegend(.hidden)
                        .frame(width: 150, height: 150)
                        VStack(spacing: 8) {
                            ForEach(owned) { slice in
                                row(color: Self.colors.first { $0.key == slice.group.title }?.value ?? .gray, name: slice.group.title,
                                    amount: slice.value, share: totalOwned > 0 ? slice.value / totalOwned : 0)
                            }
                            if cards > 0 { row(color: .orange, name: "Credit Cards owed", amount: -cards, share: nil) }
                            if loans > 0 { row(color: Theme.red, name: "Mortgages & Loans owed", amount: -loans, share: nil) }
                        }
                    }
                    .frame(minHeight: 170)
                }
            } else {
                ReportCalculating(height: ReportSize.h(170))
            }
        }
    }

    private func row(color: Color, name: String, amount: Double, share: Double?) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(name).font(.callout).lineLimit(1)
            Spacer(minLength: 6)
            Text(ReportFormat.money(amount)).font(.callout.weight(.medium)).foregroundStyle(amount < 0 ? Theme.red : .primary)
            if let share { Text(share.formatted(.percent.precision(.fractionLength(0)))).font(.caption).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing) }
        }
    }
}

// MARK: Biggest movers

struct BiggestMoversReport: View {
    @Query private var allAccounts: [Account]

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        ReportPanel(title: "Biggest Movers", summary: "The accounts that moved your net worth most over the last three months.") {
            if let snapshot {
                let movers = ReportMath.movers(accounts: allAccounts.live, snapshot: snapshot).filter { $0.threeMonths != 0 || $0.twelveMonths != 0 }.prefix(7)
                if movers.isEmpty {
                    ReportEmpty(message: "Nothing has moved yet. This fills in as your balances change.", height: ReportSize.h(170))
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow {
                            Text("ACCOUNT").gridColumnAlignment(.leading)
                            Text("BALANCE").gridColumnAlignment(.trailing)
                            Text("3 MONTHS").gridColumnAlignment(.trailing)
                            Text("12 MONTHS").gridColumnAlignment(.trailing)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Divider().gridCellColumns(4)
                        ForEach(Array(movers)) { mover in
                            GridRow {
                                Label(mover.name, systemImage: mover.symbol).lineLimit(1)
                                Text(mover.now, format: .appCurrency).foregroundStyle(mover.isDebt ? Theme.red : .primary)
                                change(mover.threeMonths)
                                change(mover.twelveMonths)
                            }
                            .font(.callout)
                        }
                    }
                }
            } else {
                ReportCalculating(height: ReportSize.h(170))
            }
        }
    }

    /// Up is good for money you own and for a debt that is coming down, so a rise in the balance is always green.
    private func change(_ value: Decimal) -> some View {
        Text(value == 0 ? "—" : ReportFormat.signed(value))
            .foregroundStyle(value == 0 ? Color.secondary : (value > 0 ? Theme.green : Theme.red))
    }
}

// MARK: Net worth range

struct NetWorthRangeReport: View {
    @Query private var allAccounts: [Account]

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let all = snapshot.map { ReportTrends.netWorth(accounts: allAccounts.live, snapshot: $0) } ?? []
        let range = ReportMath.netWorthRange(from: all)
        let history = all.filter { !$0.projected }
        let end = range.last

        ReportPanel(title: "Net Worth Range", summary: "A low, expected and high path for the next six months, from how much your net worth has varied.",
                    headline: end.map { ReportFormat.money($0.expected) }, headlineNote: end == nil ? nil : "expected in 6 months") {
            if snapshot == nil {
                ReportCalculating(height: ReportSize.h(210))
            } else if range.isEmpty {
                ReportEmpty(message: "Not enough history yet. This needs a few months of transactions.", height: ReportSize.h(210))
            } else {
                Chart {
                    ForEach(history) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Net worth", point.value), series: .value("Part", "History"))
                            .foregroundStyle(Theme.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(range) { point in
                        AreaMark(x: .value("Month", point.date, unit: .month), yStart: .value("Low", point.low), yEnd: .value("High", point.high))
                            .foregroundStyle(Theme.green.opacity(0.16))
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Expected", point.expected), series: .value("Part", "Expected"))
                            .foregroundStyle(Theme.green.opacity(0.9))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: ReportSize.h(210))
                HStack(spacing: 10) {
                    if let end {
                        ReportFigure(label: "Low", value: ReportFormat.money(end.low), color: Theme.red)
                        ReportFigure(label: "Expected", value: ReportFormat.money(end.expected))
                        ReportFigure(label: "High", value: ReportFormat.money(end.high), color: Theme.green)
                    }
                }
            }
        }
    }
}
