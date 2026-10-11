import SwiftUI
import SwiftData
import Charts

/// Retirement, brokerage and other investment accounts: value, growth and contributions over a quarter,
/// six months or a year.
struct InvestmentsView: View {
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var period: ReportPeriod = .quarterly
    @State private var anchor = Date.now

    private var investmentAccounts: [Account] { accounts.filter { $0.type.group == .investments } }

    private var earliest: Date? {
        investmentAccounts.flatMap(\.transactions).filter(\.isLive).map(\.date).min()
    }

    var body: some View {
        let range = Reports.range(period, anchor: anchor)
        let report = Investments.build(accounts, range: range)

        ScrollView {
            VStack(spacing: 14) {
                PageTitle("Investments")
                PeriodControls(periods: ReportPeriod.longTerm, period: $period, anchor: $anchor, earliest: earliest)
                if investmentAccounts.isEmpty {
                    PlaceholderTiles(titles: ["Value", "Growth", "Contributions", "Change"])
                    ReportCard(title: "Value") {
                        NoDataNote(message: "No data yet. Add a 401(k), IRA, brokerage, 529, crypto or other investment account in Settings ▸ Accounts and it shows up here.")
                    }
                    ReportCard(title: "Returns by Holding") {
                        NoDataNote(message: "No data yet. Holdings you add to an investment account are listed here.")
                    }
                    ReportCard(title: "Where It Is") {
                        NoDataNote(message: "No data yet. This shows how your investments are split up.")
                    }
                    ReportCard(title: "Accounts (0)") {
                        NoDataNote(message: "No investment accounts yet.")
                    }
                } else {
                    tiles(report)
                    if report.points.count > 1 { ReportCard(title: "Value") { chart(report) } }
                    if !report.holdings.isEmpty { ReportCard(title: "Returns by Holding") { holdingReturns(report) } }
                    if report.end > 0 { ReportCard(title: "Where It Is") { allocation(report) } }
                    ReportCard(title: "Accounts (\(report.lines.count))") { list(report) }
                    Text("Growth is what you record with the Interest & Dividends or Investment Gains categories (a loss is a negative amount). Every other deposit or withdrawal counts as a contribution. Return is weighted by when each contribution arrived.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    // MARK: Tiles

    private func tiles(_ report: Investments.Report) -> some View {
        StatGrid {
            tile("Value", report.end, color: .primary, note: "started at \(report.start.formatted(.appCurrency))")
            tile("Growth", report.growth, color: report.growth >= 0 ? Theme.green : Theme.red,
                 note: report.returnRate.map { "\(signed($0)) return" } ?? "no return yet")
            tile("Contributions", report.contributions, color: .primary, note: "net money in or out")
            tile("Change", report.change, color: report.change >= 0 ? Theme.green : Theme.red,
                 note: "growth plus contributions")
        }
    }

    private func tile(_ title: String, _ amount: Decimal, color: Color, note: String) -> some View {
        StatTile(title: title) {
            Text(amount, format: .appCurrency).foregroundStyle(color)
        } note: {
            Text(note)
        }
    }

    private func signed(_ rate: Double) -> String {
        (rate >= 0 ? "+" : "") + rate.formatted(.percent.precision(.fractionLength(1)))
    }

    // MARK: Chart

    private func chart(_ report: Investments.Report) -> some View {
        Chart(report.points) { point in
            LineMark(x: .value("Month", point.date), y: .value("Value", point.value))
                .foregroundStyle(Theme.green)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Month", point.date), y: .value("Value", point.value))
                .foregroundStyle(Theme.green)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(range: .plotDimension(padding: 24))
        .chartXAxis { AxisMarks(values: report.points.map(\.date)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .frame(height: 200)
    }

    // MARK: Returns by holding

    private func holdingReturns(_ report: Investments.Report) -> some View {
        let lines = report.holdings.sorted { ($0.returnRate ?? -.infinity) > ($1.returnRate ?? -.infinity) }
        return VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 0) {
                GridRow {
                    Text("Holding").gridColumnAlignment(.leading)
                    Text("Value")
                    Text("Growth")
                    Text("Return")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

                ForEach(lines) { line in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name).fontWeight(.medium).lineLimit(1)
                            Text(holdingDetail(line))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(line.end, format: .appCurrency).fontWeight(.semibold)

                        Text(line.growth, format: .appCurrency)
                            .foregroundStyle(line.growth == 0 ? Color.secondary : (line.growth > 0 ? Theme.green : Theme.red))

                        returnPill(line.returnRate)
                    }
                    .padding(.vertical, 9)
                }
            }
            Text("Growth is the price change on the shares you held. Buying or selling shares counts as a contribution, so adding to a holding never looks like a gain.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func holdingDetail(_ line: Investments.HoldingLine) -> String {
        var parts: [String] = []
        if line.label != line.name { parts.append(line.label) }
        parts.append(line.accountName)
        if line.contributions != 0 {
            parts.append("\(line.contributions > 0 ? "bought" : "sold") \(abs(line.contributions).formatted(.appCurrency))")
        }
        return parts.joined(separator: " · ")
    }

    private func returnPill(_ rate: Double?) -> some View {
        let color: Color = rate.map { $0 > 0 ? Theme.green : ($0 < 0 ? Theme.red : Color.secondary) } ?? Color.secondary
        return Text(rate.map(signed) ?? "–")
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: Allocation

    private func allocation(_ report: Investments.Report) -> some View {
        Chart(report.lines.filter { $0.end > 0 }) { line in
            SectorMark(angle: .value("Value", line.end.doubleValue), innerRadius: .ratio(0.6), angularInset: 1.5)
                .foregroundStyle(by: .value("Account", line.name))
                .cornerRadius(3)
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
        .frame(height: 240)
    }

    // MARK: List

    private func list(_ report: Investments.Report) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(report.lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 { Divider() }
                lineRow(line, total: report.end)
            }
        }
    }

    private func lineRow(_ line: Investments.Line, total: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: line.symbol).foregroundStyle(Theme.green).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.name).fontWeight(.medium)
                    Text(line.typeTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(line.end, format: .appCurrency).fontWeight(.semibold)
            }
            HStack {
                Text("Growth \(line.growth.formatted(.appCurrency))")
                    .foregroundStyle(line.growth >= 0 ? Theme.green : Theme.red)
                if let rate = line.returnRate { Text(signed(rate)).foregroundStyle(line.growth >= 0 ? Theme.green : Theme.red) }
                Spacer()
                Text("Contributions \(line.contributions.formatted(.appCurrency))").foregroundStyle(.secondary)
            }
            .font(.caption)
            if total > 0, line.end > 0 {
                ProgressView(value: min(max((line.end / total).doubleValue, 0), 1)).tint(Theme.green)
                Text("\((line.end / total).doubleValue.formatted(.percent.precision(.fractionLength(0)))) of your investments")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
