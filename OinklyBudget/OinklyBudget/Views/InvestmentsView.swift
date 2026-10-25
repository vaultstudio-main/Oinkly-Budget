import SwiftUI
import SwiftData
import Charts

/// Retirement, brokerage and other investment accounts: value, growth, contributions and where they are heading.
struct InvestmentsView: View {
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    private var investmentAccounts: [Account] { accounts.filter { $0.type.group == .investments } }

    /// Investments as they stood the given number of months ago, up to now.
    private func window(_ months: Int) -> Investments.Report {
        let start = Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .now
        return Investments.build(accounts, range: ReportRange(start: start, end: Date.now.addingTimeInterval(1)))
    }

    var body: some View {
        let hasAccounts = !investmentAccounts.isEmpty
        let windows = hasAccounts ? [(3, window(3)), (6, window(6)), (12, window(12))] : []
        let year = windows.last?.1

        VStack(spacing: 0) {
        PinnedHeader("Investments")
        ScrollView {
            VStack(spacing: 14) {
                if let year {
                    tiles(year)
                } else {
                    PlaceholderTiles(titles: ["Value", "Growth", "Contributions", "Change"])
                }
                growthWindows(windows)
                PortfolioValueReport()
                InvestmentProjectionReport()
                HStack(alignment: .top, spacing: 14) {
                    InvestmentAllocationReport()
                    InvestmentBucketsReport()
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 14) {
                    InvestmentContributionsReport()
                    InvestmentGrowthReport()
                }
                .fixedSize(horizontal: false, vertical: true)
                ReportPanel(title: "Returns by Holding", summary: "How each holding's price has moved over the last year.") {
                    if let year, !year.holdings.isEmpty {
                        holdingReturns(year)
                    } else {
                        ReportEmpty(message: "Holdings you add to an investment account are listed here.", height: 220, shape: .table)
                    }
                }
                InvestmentGainsReport()
                ReportPanel(title: "Accounts (\(year?.lines.count ?? 0))", summary: "Every investment account with its value, growth and share.") {
                    if let year, !year.lines.isEmpty {
                        list(year)
                    } else {
                        ReportEmpty(message: "No investment accounts yet.", height: 220, shape: .table)
                    }
                }
                Text("Growth is what you record with the Interest & Dividends or Investment Gains categories (a loss is a negative amount). Every other deposit or withdrawal counts as a contribution. Return is weighted by when each contribution arrived.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .environment(\.reportCardMinHeight, 290)
            .padding(16)
        }
        }
        .background(Theme.background)
    }

    // MARK: Growth over time

    /// How the investments did over the last three months, six months and year, side by side.
    private func growthWindows(_ windows: [(Int, Investments.Report)]) -> some View {
        ReportPanel(title: "Growth", summary: "What your investments grew, what you added and the return, over the last three months, six months and year.") {
            if windows.isEmpty {
                ReportEmpty(message: "Add an investment account to see its growth over time.", height: 190, shape: .tiles)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(windows, id: \.0) { months, report in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(months == 12 ? "LAST YEAR" : "LAST \(months) MONTHS").font(.caption2).foregroundStyle(.secondary)
                            windowRow("Value then", report.start)
                            windowRow("Added", report.contributions)
                            windowRow("Growth", report.growth, colored: true)
                            windowRow("Value now", report.end, bold: true)
                            returnPill(report.returnRate)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func windowRow(_ title: String, _ value: Decimal, bold: Bool = false, colored: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(value, format: .appCurrency)
                .fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(colored ? (value >= 0 ? Theme.green : Theme.red) : .primary)
        }
        .font(.callout)
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
        ShareBarChart(bars: ShareBarChart.money(report.lines.filter { $0.end > 0 }.map { ($0.name, $0.end.doubleValue, nil) }, limit: 10))
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
