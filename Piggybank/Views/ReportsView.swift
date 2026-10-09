import SwiftUI
import SwiftData
import Charts

/// Monthly, quarterly, 6-month and yearly reports. The same screen on Mac, iPhone and iPad.
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
                controls(range: range)
                if report.totals.count == 0 {
                    ReportCard(title: "No Activity") {
                        Text("No transactions in \(Reports.label(period, range: range)). Pick another period, or add some transactions.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    tiles(report)
                    ReportCard(title: "Income vs Spending") { chart(report) }
                    ReportCard(title: "Spending by Category") { categories(report) }
                }
            }
            #if os(macOS)
            .padding(16)
            #else
            .padding(.horizontal, 16)
            #endif
        }
        #if os(macOS)
        .background(Theme.background)
        #else
        .background(Color(.systemGroupedBackground))
        #endif
        .animation(.smooth, value: period)
    }

    // MARK: Controls

    private var earliest: Date? { transactions.map(\.date).min() }

    private func controls(range: ReportRange) -> some View {
        VStack(spacing: 12) {
            Picker("Period", selection: $period) {
                ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: period) { _, _ in anchor = Date.now }

            HStack(spacing: 14) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(earliest.map { range.start <= $0 } ?? true)
                Text(Reports.label(period, range: range))
                    .font(.headline)
                    .frame(minWidth: 150)
                    .contentTransition(.numericText())
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(range.end > .now)
                if !(range.start <= .now && range.end > .now) {
                    Button("Current") { withAnimation(.smooth) { anchor = .now } }
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.top, 4)
    }

    private func step(_ direction: Int) {
        withAnimation(.smooth) { anchor = Reports.shifted(anchor, period: period, by: direction) }
    }

    // MARK: Summary tiles

    private func tiles(_ report: Reports.Report) -> some View {
        let totals = report.totals
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            tile("Income", totals.income, color: Theme.green, change: Reports.change(from: report.previous.income, to: totals.income), higherIsGood: true)
            tile("Spending", totals.spending, color: Theme.red, change: Reports.change(from: report.previous.spending, to: totals.spending), higherIsGood: false)
            tile("Net", totals.net, color: totals.net >= 0 ? Theme.green : Theme.red, change: nil, higherIsGood: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("SAVINGS RATE").font(.caption).foregroundStyle(.secondary)
                Text(totals.savingsRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                    .font(.title2.bold())
                    .foregroundStyle(totals.savingsRate.map { $0 >= 0 ? Theme.green : Theme.red } ?? .secondary)
                Text("of income kept").font(.caption2).foregroundStyle(.secondary)
            }
            .tileStyle()
        }
    }

    private func tile(_ title: String, _ amount: Decimal, color: Color, change: Double?, higherIsGood: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(amount, format: .appCurrency)
                .font(.title2.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let change {
                let good = (change >= 0) == higherIsGood
                HStack(spacing: 3) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(abs(change).formatted(.percent.precision(.fractionLength(0)))) vs previous")
                }
                .font(.caption2)
                .foregroundStyle(good ? Theme.green : Theme.red)
            } else {
                Text("no earlier period").font(.caption2).foregroundStyle(.secondary).opacity(title == "Net" ? 0 : 1)
            }
        }
        .tileStyle()
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

private extension View {
    func tileStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tileBackground: some ShapeStyle {
        #if os(macOS)
        AnyShapeStyle(Theme.panel)
        #else
        AnyShapeStyle(.regularMaterial)
        #endif
    }
}

/// A titled card: the dark panel on the Mac, a material card on iPhone and iPad.
struct ReportCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        #if os(macOS)
        Panel(title: title) { content }
        #else
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        #endif
    }
}
