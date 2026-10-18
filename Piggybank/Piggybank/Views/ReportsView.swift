import SwiftUI
import SwiftData
import Charts

/// Monthly, quarterly, 6-month and yearly reports.
struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    // Opens on the current year. The tabs still go down to a single month.
    @State private var period: ReportPeriod = .yearly
    @State private var anchor = Date.now
    @State private var section = ReportSection.overview

    /// The date of the oldest transaction: one row, not a pass over everything.
    private var earliest: Date? {
        var oldest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        oldest.fetchLimit = 1
        return (try? modelContext.fetch(oldest))?.first?.date
    }

    var body: some View {
        ReportsContent(period: $period, anchor: $anchor, section: $section, earliest: earliest)
    }
}

/// The report itself. It only loads the transactions of the period being shown and the one before it (for the
/// "vs previous" changes), so it stays quick with a lot of history.
private struct ReportsContent: View {
    @Query private var allTransactions: [Transaction]
    private var transactions: [Transaction] { allTransactions.live }
    /// The last thirteen months, shared with the reports through the environment.
    @Query private var yearTransactions: [Transaction]

    @Binding var period: ReportPeriod
    @Binding var anchor: Date
    @Binding var section: ReportSection
    let earliest: Date?
    @State private var pageWidth: CGFloat = 1000

    init(period: Binding<ReportPeriod>, anchor: Binding<Date>, section: Binding<ReportSection>, earliest: Date?) {
        _period = period
        _anchor = anchor
        _section = section
        self.earliest = earliest
        let range = Reports.range(period.wrappedValue, anchor: anchor.wrappedValue)
        let from = Reports.previous(of: range, period: period.wrappedValue).start
        let to = range.end
        _allTransactions = Query(filter: #Predicate<Transaction> { $0.date >= from && $0.date < to })
        let thisMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let yearStart = Calendar.current.date(byAdding: .month, value: -13, to: thisMonth) ?? thisMonth
        _yearTransactions = Query(filter: #Predicate<Transaction> { $0.date >= yearStart })
    }

    var body: some View {
        let range = Reports.range(period, anchor: anchor)

        ScrollView {
            VStack(spacing: 14) {
                PageTitle("Reports")
                sectionPicker
                if section.usesPeriod { controls(range: range) }
                placeholders
            }
            .padding(16)
        }
        .environment(\.reportInputs, ReportInputs(year: yearTransactions.live, period: transactions, range: range,
                                                  previous: Reports.previous(of: range, period: period),
                                                  periodName: Reports.label(period, range: range)))
        .background(Theme.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .animation(.smooth, value: period)
    }

    // MARK: Sections and placeholders

    /// The reports on the Overview that are built from the chosen period.
    @ViewBuilder
    private var overviewReports: some View {
        let range = Reports.range(period, anchor: anchor)
        let report = Reports.build(transactions, period: period, range: range)
        VStack(spacing: 14) {
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
    }

    private var sectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportSection.allCases) { item in
                        Button { section = item } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.callout.weight(section == item ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(section == item ? Color.accentColor.opacity(0.22) : Theme.panel, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(section.blurb).font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Reports laid out in rows: wide ones alone, the rest packed `columns` across. Any card left over stretches to
    /// fill its row, so no space is wasted.
    private func rows(of items: [ReportItem], columns: Int) -> [[ReportItem]] {
        var rows: [[ReportItem]] = []
        var buffer: [ReportItem] = []
        for item in items {
            if item.isWide {
                if !buffer.isEmpty { rows.append(buffer); buffer = [] }
                rows.append([item])
            } else {
                buffer.append(item)
                if buffer.count == columns { rows.append(buffer); buffer = [] }
            }
        }
        if !buffer.isEmpty { rows.append(buffer) }
        return rows
    }

    @ViewBuilder
    private func card(_ item: ReportItem) -> some View {
        if let kind = item.trend {
            TrendChartCard(kind: kind, height: item.isWide ? 220 : 190)
        } else if let built = ReportCards.view(section: section, title: item.title) {
            built
        } else {
            ReportPlaceholderCard(report: item)
        }
    }

    private func grid(_ items: [ReportItem]) -> some View {
        // Three across when the page is wide enough.
        let columns = pageWidth >= 1000 ? 3 : 2
        return VStack(spacing: 14) {
            ForEach(Array(rows(of: items, columns: columns).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(row) { card($0) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Everything in this section except the real reports the Overview draws itself.
    private var placeholders: some View {
        let all = section.reports.filter { !$0.isBuilt }
        let charts = section == .overview ? all.filter { $0.trend != nil } : []
        let rest = section == .overview ? all.filter { $0.trend == nil } : all
        return VStack(spacing: 14) {
            if !charts.isEmpty { grid(charts) }
            if section == .overview { overviewReports }
            if !rest.isEmpty {
                if section == .overview {
                    HStack {
                        Text("MORE REPORTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 6)
                }
                grid(rest)
            }
        }
    }

    // MARK: Controls

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
