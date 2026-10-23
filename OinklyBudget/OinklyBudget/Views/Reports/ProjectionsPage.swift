import SwiftUI
import SwiftData
import Charts

/// The Projections tab of Reports, in three areas. Quarter and Year are calendar stretches: what has happened so far in them, and
/// the rest of them at your recent pace, through to the last day of the quarter or the year. Long Range looks one to ten
/// calendar years out, starting with next year. Every card is always there, with a set size, and says what it needs until there is
/// history to project from. It is an estimate to plan with.
struct ProjectionsPage: View {
    private enum Area: String, CaseIterable, Identifiable {
        case quarter = "Quarter", year = "Year", longRange = "Long Range"
        var id: Self { self }
    }

    @State private var area = Area.quarter
    @Environment(\.reportInputs) private var inputs
    @Query private var allAccounts: [Account]
    @Query private var allBills: [Bill]

    /// What you were worth at the end of each past month, and now. Nil while the ledger is still being worked out.
    private var netHistory: [TrendPoint]? {
        guard let snapshot = LedgerIndex.shared.latest else { return nil }
        return ReportTrends.netWorth(accounts: allAccounts, snapshot: snapshot).filter { !$0.projected }
    }

    private static let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 4)
    private static let monthsHeight: CGFloat = 220
    private static let lowerHeight: CGFloat = 190

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
            FolderTabs(tabs: Area.allCases, selection: $area, title: { $0.rawValue }, leading: 0)
            switch area {
            case .quarter: period(Projection.calendarQuarter(), kind: "quarter", history: history)
            case .year: period(Projection.calendarYear(), kind: "year", history: history)
            case .longRange: longRange(history: history)
            }
            Text("These projections assume your income and spending stay at the average of your last three full months, and that what you own holds its value. They are estimates to plan with, not promises.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// What a card says in its place until there is something to show.
    private func placeholder(_ message: String, symbol: String, height: CGFloat) -> some View {
        ReportEmpty(message: message, height: height, title: "Nothing to project yet", clean: true, symbol: symbol)
            .frame(height: height)
    }

    // MARK: Quarter and year

    @ViewBuilder
    private func period(_ span: (start: Date, end: Date), kind: String, history: [(date: Date, income: Double, spending: Double)]) -> some View {
        let net = netHistory
        let nowWorth = net?.last?.value
        let projection = Projection.period(history: history, netWorthHistory: (net ?? []).map { ($0.date, $0.value) }, netWorthNow: nowWorth ?? 0,
                                           bills: allBills, from: span.start, through: span.end)
        let has = projection.totalIncome > 0 || projection.totalSpending > 0
        let name = kind == "year" ? span.start.formatted(.dateTime.year()) : "Q\((Calendar.current.component(.month, from: span.start) - 1) / 3 + 1) \(span.start.formatted(.dateTime.year()))"
        let range = "\(span.start.formatted(.dateTime.month(.abbreviated).day())) – \(span.end.formatted(.dateTime.month(.abbreviated).day()))"
        let waiting = "Add a few months of transactions and this fills in."

        LazyVGrid(columns: Self.tileColumns, spacing: 14) {
            tile("Income, \(name)", has ? projection.totalIncome : nil, note: has ? "\(ReportFormat.money(projection.incomeSoFar)) so far" : "No history yet", color: Theme.green)
            tile("Spending, \(name)", has ? projection.totalSpending : nil, note: has ? "\(ReportFormat.money(projection.spendingSoFar)) so far" : "No history yet", color: .primary)
            tile("Kept, \(name)", has ? projection.totalSaved : nil, note: has ? "\(ReportFormat.money(projection.monthlySaved)) a month from here" : "No history yet",
                 color: projection.totalSaved < 0 ? Theme.red : Theme.green)
            tile("Savings Rate", has ? projection.savingsRate : nil, note: "of what comes in", isPercent: true, color: .primary)
        }
        ReportPanel(title: "Month by Month", summary: "\(range): the months that have happened, then the rest at your recent average.",
                    headline: has ? ReportFormat.money(projection.totalSaved) : nil, headlineNote: has ? "kept over the \(kind)" : nil) {
            if has { monthBars(projection).frame(height: Self.monthsHeight) } else { placeholder(waiting, symbol: "chart.bar", height: Self.monthsHeight) }
        }
        HStack(alignment: .top, spacing: 14) {
            ReportPanel(title: "Net Worth Path", summary: "What you were worth, and where you would be, at the end of each month.",
                        headline: has ? projection.netWorth.last.map { ReportFormat.money($0.value) } : nil, headlineNote: has ? "at the end of the \(kind)" : nil) {
                if net == nil { ReportCalculating(height: Self.lowerHeight).frame(height: Self.lowerHeight) }
                else if has { netWorthLine(projection.netWorth).frame(height: Self.lowerHeight) }
                else { placeholder(waiting, symbol: "scalemass", height: Self.lowerHeight) }
            }
            ReportPanel(title: "Bills Due", summary: "The bills on your Bills page that fall due in each month. They are already part of spending.",
                        headline: projection.totalBills > 0 ? ReportFormat.money(projection.totalBills) : nil, headlineNote: projection.totalBills > 0 ? "due in the \(kind)" : nil) {
                if projection.totalBills > 0 { billBars(projection).frame(height: Self.lowerHeight) }
                else { placeholder("No bills fall due in this stretch. Add them on the Bills page.", symbol: "calendar", height: Self.lowerHeight) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ title: String, _ value: Double?, note: String, isPercent: Bool = false, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value.map { isPercent ? ReportFormat.percent($0) : ReportFormat.money($0) } ?? "–")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(value == nil ? Color.secondary : color)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .panelBackground(cornerRadius: 12, continuous: true)
    }

    /// Faded for what is still to come, a little faded for the month in progress.
    private func opacity(_ kind: Projection.Kind) -> Double {
        switch kind {
        case .actual: 1
        case .current: 0.75
        case .projected: 0.4
        }
    }

    private func monthBars(_ projection: Projection) -> some View {
        struct Bar: Identifiable {
            let date: Date
            let source: String
            let value: Double
            let kind: Projection.Kind
            var id: String { "\(date.timeIntervalSince1970)-\(source)" }
        }
        let bars = projection.months.flatMap {
            [Bar(date: $0.date, source: "Income", value: $0.income, kind: $0.kind), Bar(date: $0.date, source: "Spending", value: $0.spending, kind: $0.kind)]
        }
        return VStack(spacing: 6) {
            Chart(bars) { bar in
                BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                    .position(by: .value("Source", bar.source))
                    .foregroundStyle(by: .value("Source", bar.source))
                    .opacity(opacity(bar.kind))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Income": Theme.green, "Spending": Theme.red])
            .chartLegend(.hidden)
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
            ReportKey(items: [.init(color: Theme.green, text: "Income"), .init(color: Theme.red, text: "Spending"), .init(color: .secondary, text: "Faded: still to come", dashed: true)])
        }
    }

    private func billBars(_ projection: Projection) -> some View {
        Chart(projection.months) { month in
            BarMark(x: .value("Month", month.date, unit: .month), y: .value("Bills", month.bills))
                .foregroundStyle(Color.orange)
                .opacity(opacity(month.kind))
                .cornerRadius(3)
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
    }

    private func netWorthLine(_ points: [Projection.NetPoint]) -> some View {
        let happened = points.filter { !$0.projected }
        // The dashed part starts where the solid one stops, so the line is one line.
        let ahead = (happened.last.map { [$0] } ?? []) + points.filter(\.projected)
        return Chart {
            ForEach(happened) { point in
                LineMark(x: .value("Date", point.date), y: .value("Net worth", point.value), series: .value("Part", "Happened"))
                    .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2.4))
                PointMark(x: .value("Date", point.date), y: .value("Net worth", point.value)).foregroundStyle(Color.accentColor)
            }
            ForEach(ahead) { point in
                LineMark(x: .value("Date", point.date), y: .value("Net worth", point.value), series: .value("Part", "Ahead"))
                    .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2.4, dash: [5, 4]))
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
    }

    // MARK: Long range

    @ViewBuilder
    private func longRange(history: [(date: Date, income: Double, spending: Double)]) -> some View {
        let average = Projection.averages(history: history)
        let has = average.income > 0 || average.spending > 0
        let nowWorth = netHistory?.last?.value
        let years = Projection.years(10, monthlyIncome: average.income, monthlySpending: average.spending, netWorthNow: nowWorth ?? 0)
        let thisYear = Calendar.current.component(.year, from: .now)
        let waiting = "Add a few months of transactions and this fills in."

        LazyVGrid(columns: Self.tileColumns, spacing: 14) {
            ForEach([0, 4, 9], id: \.self) { index in
                let entry = years[index]
                tile("End of \(entry.year)", has && nowWorth != nil ? entry.netWorth : nil, note: has ? "\(ReportFormat.money(entry.saved)) kept by then" : "No history yet",
                     color: entry.netWorth < 0 ? Theme.red : Theme.green)
            }
            tile("Kept Each Year", has ? years[0].keptInYear : nil, note: has ? "\(ReportFormat.money(average.income - average.spending)) a month" : "No history yet",
                 color: average.income < average.spending ? Theme.red : Theme.green)
        }
        ReportPanel(title: "Net Worth, Year by Year", summary: "What you would be worth on December 31 of each of the next ten years, starting with next year.",
                    headline: has && nowWorth != nil ? years.last.map { ReportFormat.money($0.netWorth) } : nil, headlineNote: has ? "at the end of \(thisYear + 10)" : nil) {
            if nowWorth == nil && LedgerIndex.shared.latest == nil {
                ReportCalculating(height: 220).frame(height: 220)
            } else if has {
                // This year is today, so the line starts from what you are worth now.
                let line = [Projection.Year(year: thisYear, keptInYear: 0, saved: 0, netWorth: nowWorth ?? 0)] + years
                Chart(line) { entry in
                    AreaMark(x: .value("Year", entry.year), y: .value("Net worth", entry.netWorth)).foregroundStyle(Color.accentColor.opacity(0.12))
                    LineMark(x: .value("Year", entry.year), y: .value("Net worth", entry.netWorth))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, dash: [5, 4]))
                    PointMark(x: .value("Year", entry.year), y: .value("Net worth", entry.netWorth)).foregroundStyle(Color.accentColor)
                }
                .chartXScale(domain: (Double(thisYear) - 0.4)...(Double(thisYear) + 10.4))
                .chartXAxis { AxisMarks(values: Array(thisYear...(thisYear + 10))) { v in AxisValueLabel { if let n = v.as(Int.self) { Text(n == thisYear ? "Now" : "’\(String(n).suffix(2))") } } } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 220)
            } else {
                placeholder(waiting, symbol: "chart.line.uptrend.xyaxis", height: 220)
            }
        }
        ReportPanel(title: "Year by Year", summary: "What is kept in each calendar year, in total from now, and what you would be worth at the end of it.") {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("YEAR"); Text("KEPT IN THE YEAR").gridColumnAlignment(.trailing); Text("KEPT FROM NOW").gridColumnAlignment(.trailing); Text("NET WORTH AT DEC 31").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    Divider().gridCellColumns(4)
                    ForEach(years) { entry in
                        GridRow {
                            Text(String(entry.year))
                            Text(has ? ReportFormat.money(entry.keptInYear) : "–").foregroundStyle(entry.keptInYear < 0 && has ? Theme.red : Color.primary)
                            Text(has ? ReportFormat.money(entry.saved) : "–")
                            Text(has && nowWorth != nil ? ReportFormat.money(entry.netWorth) : "–").fontWeight(.semibold)
                        }
                        .font(.callout)
                        .foregroundStyle(has ? Color.primary : Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 290)
        }
    }
}
