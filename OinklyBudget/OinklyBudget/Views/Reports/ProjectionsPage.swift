import SwiftUI
import SwiftData
import Charts

/// The Projections tab of Reports, in three areas: the next quarter, the next year, and the long run. Each works from your income
/// and spending over the last three full months, your bills, and what you are worth now. It is an estimate to plan with.
struct ProjectionsPage: View {
    private enum Area: String, CaseIterable, Identifiable {
        case quarter = "Quarter", year = "Year", longRange = "Long Range"
        var id: Self { self }

        var blurb: String {
            switch self {
            case .quarter: "The next three months."
            case .year: "The next twelve months."
            case .longRange: "One to ten years out."
            }
        }
    }

    @State private var area = Area.quarter
    @Environment(\.reportInputs) private var inputs
    @Query private var allAccounts: [Account]
    @Query private var allBills: [Bill]

    /// What you are worth now, from the ledger. Nil while it is still being worked out.
    private var netWorthNow: Double? {
        guard let snapshot = LedgerIndex.shared.latest else { return nil }
        return ReportTrends.netWorth(accounts: allAccounts, snapshot: snapshot).last { !$0.projected }?.value
    }

    var body: some View {
        content
        #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
                guard let action = note.userInfo?["action"] as? String, action.hasPrefix("projectionsArea:") else { return }
                switch action.dropFirst("projectionsArea:".count) {
                case "year": area = .year
                case "longrange": area = .longRange
                default: area = .quarter
                }
            }
        #endif
    }

    private var content: some View {
        let history = inputs.monthlyTotals()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Picker("Area", selection: $area) {
                    ForEach(Area.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                Text(area.blurb).foregroundStyle(.secondary)
                Spacer()
            }
            switch area {
            case .quarter: horizon(months: 3, history: history)
            case .year: horizon(months: 12, history: history)
            case .longRange: longRange(history: history)
            }
            Text("These projections assume your income and spending stay at the average of your last three full months, and that what you own holds its value. They are estimates to plan with, not promises.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Four tiles across, filling the page.
    private static let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 4)

    // MARK: Quarter and year

    @ViewBuilder
    private func horizon(months: Int, history: [(date: Date, income: Double, spending: Double)]) -> some View {
        let projection = Projection.make(history: history, netWorthNow: netWorthNow ?? 0, bills: allBills, months: months)
        let label = months == 3 ? "quarter" : "year"
        if !projection.hasData {
            ReportPanel(title: "Not enough history yet", summary: "A projection needs a few full months of income and spending to go on.") {
                ReportEmpty(message: "Add a few months of transactions and this page fills in.", height: 220, title: "Nothing to project", clean: true, symbol: "scope")
            }
        } else {
            tiles(projection, months: months)
            ReportPanel(title: "Month by Month", summary: "Income and spending for each of the next \(months) months, at your recent average.",
                        headline: ReportFormat.money(projection.totalSaved), headlineNote: "kept over the \(label)") {
                monthBars(projection)
            }
            .environment(\.reportCardMinHeight, 310)
            HStack(alignment: .top, spacing: 14) {
                ReportPanel(title: "Net Worth Path", summary: "What you would be worth at the start of each month.",
                            headline: projection.netWorth.last.map { ReportFormat.money($0.value) },
                            headlineNote: netWorthNow.map { "from \(ReportFormat.money($0)) today" }) {
                    if netWorthNow == nil { ReportCalculating(height: 190) } else { netWorthLine(projection.netWorth, height: 190) }
                }
                .environment(\.reportCardMinHeight, 300)
                ReportPanel(title: "Bills Due", summary: "The bills on your Bills page that fall due in each month. They are already part of spending.",
                            headline: ReportFormat.money(projection.totalBills), headlineNote: "due over the \(label)") {
                    billBars(projection)
                }
                .environment(\.reportCardMinHeight, 300)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tiles(_ projection: Projection, months: Int) -> some View {
        return LazyVGrid(columns: Self.tileColumns, spacing: 14) {
            tile("Expected Income", projection.totalIncome, note: "\(ReportFormat.money(projection.monthlyIncome)) a month, \(months) months", color: Theme.green)
            tile("Expected Spending", projection.totalSpending, note: "\(ReportFormat.money(projection.monthlySpending)) a month", color: .primary)
            tile("Expected to Keep", projection.totalSaved, note: "\(ReportFormat.money(projection.monthlySaved)) a month", color: projection.totalSaved < 0 ? Theme.red : Theme.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("SAVINGS RATE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(projection.savingsRate.map { ReportFormat.percent($0) } ?? "–").font(.system(size: 30, weight: .bold))
                    .foregroundStyle((projection.savingsRate ?? 0) < 0 ? Theme.red : Color.primary)
                Text("of what comes in").font(.caption).foregroundStyle(.secondary)
            }
            .tileCard()
        }
    }

    private func tile(_ title: String, _ value: Double, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(ReportFormat.money(value)).font(.system(size: 30, weight: .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .tileCard()
    }

    private func monthBars(_ projection: Projection) -> some View {
        struct Bar: Identifiable {
            let date: Date
            let source: String
            let value: Double
            var id: String { "\(date.timeIntervalSince1970)-\(source)" }
        }
        let bars = projection.months.flatMap { [Bar(date: $0.date, source: "Income", value: $0.income), Bar(date: $0.date, source: "Spending", value: $0.spending)] }
        return Chart(bars) { bar in
            BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                .position(by: .value("Source", bar.source))
                .foregroundStyle(by: .value("Source", bar.source))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(["Income": Theme.green, "Spending": Theme.red])
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
        .frame(height: 220)
    }

    private func billBars(_ projection: Projection) -> some View {
        Group {
            if projection.totalBills == 0 {
                ReportEmpty(message: "No bills fall due in this stretch. Add them on the Bills page.", height: 190, title: "No bills due", clean: true, symbol: "calendar")
            } else {
                Chart(projection.months) { month in
                    BarMark(x: .value("Month", month.date, unit: .month), y: .value("Bills", month.bills))
                        .foregroundStyle(Color.orange)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 190)
            }
        }
    }

    private func netWorthLine(_ points: [Projection.NetPoint], height: CGFloat) -> some View {
        Chart(points) { point in
            AreaMark(x: .value("Month", point.date, unit: .month), y: .value("Net worth", point.value)).foregroundStyle(Color.accentColor.opacity(0.12))
            LineMark(x: .value("Month", point.date, unit: .month), y: .value("Net worth", point.value))
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [5, 4]))
            PointMark(x: .value("Month", point.date, unit: .month), y: .value("Net worth", point.value)).foregroundStyle(Color.accentColor)
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month, count: points.count > 8 ? 2 : 1)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
        .frame(height: height)
    }

    // MARK: Long range

    @ViewBuilder
    private func longRange(history: [(date: Date, income: Double, spending: Double)]) -> some View {
        let average = Projection.averages(history: history)
        let now = netWorthNow
        let years = Projection.years(10, monthlyIncome: average.income, monthlySpending: average.spending, netWorthNow: now ?? 0)
        if average.income == 0 && average.spending == 0 {
            ReportPanel(title: "Not enough history yet", summary: "A projection needs a few full months of income and spending to go on.") {
                ReportEmpty(message: "Add a few months of transactions and this page fills in.", height: 220, title: "Nothing to project", clean: true, symbol: "scope")
            }
        } else {
            LazyVGrid(columns: Self.tileColumns, spacing: 14) {
                ForEach([1, 5, 10], id: \.self) { year in
                    let entry = years[year - 1]
                    tile("In \(year) Year\(year == 1 ? "" : "s")", entry.netWorth, note: "\(ReportFormat.money(entry.saved)) kept by then",
                         color: entry.netWorth < 0 ? Theme.red : Theme.green)
                }
                tile("Kept Each Year", average.income * 12 - average.spending * 12, note: "\(ReportFormat.money(average.income - average.spending)) a month",
                     color: average.income < average.spending ? Theme.red : Theme.green)
            }
            ReportPanel(title: "Net Worth, Year by Year", summary: "What you would be worth after each of the next ten years, at your recent pace.",
                        headline: years.last.map { ReportFormat.money($0.netWorth) }, headlineNote: "in 10 years") {
                if now == nil {
                    ReportCalculating(height: 220)
                } else {
                    // Year zero is today, so the line starts from what you are worth now.
                    let line = [Projection.Year(year: 0, saved: 0, netWorth: now ?? 0)] + years
                    Chart(line) { entry in
                        AreaMark(x: .value("Year", entry.year), y: .value("Net worth", entry.netWorth)).foregroundStyle(Color.accentColor.opacity(0.12))
                        LineMark(x: .value("Year", entry.year), y: .value("Net worth", entry.netWorth))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [5, 4]))
                        PointMark(x: .value("Year", entry.year), y: .value("Net worth", entry.netWorth)).foregroundStyle(Color.accentColor)
                    }
                    .chartXScale(domain: -0.4...10.4)
                    .chartXAxis { AxisMarks(values: Array(0...10)) { v in AxisValueLabel { if let n = v.as(Int.self) { Text(n == 0 ? "Now" : "\(n)y") } } } }
                    .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                    .frame(height: 220)
                }
            }
            .environment(\.reportCardMinHeight, 330)
            ReportPanel(title: "Year by Year", summary: "What is kept in total and what you would be worth at the end of each year.") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("YEAR"); Text("KEPT SO FAR").gridColumnAlignment(.trailing); Text("NET WORTH").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    Divider().gridCellColumns(3)
                    ForEach(years) { entry in
                        GridRow {
                            Text("Year \(entry.year)")
                            Text(ReportFormat.money(entry.saved)).foregroundStyle(entry.saved < 0 ? Theme.red : Color.primary)
                            Text(ReportFormat.money(entry.netWorth)).fontWeight(.semibold).foregroundStyle(entry.netWorth < 0 ? Theme.red : Color.primary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

private extension View {
    /// A figure on its own small card, the size every tile on the page shares.
    func tileCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .panelBackground(cornerRadius: 12, continuous: true)
    }
}
