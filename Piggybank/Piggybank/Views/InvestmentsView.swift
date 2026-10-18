import SwiftUI
import SwiftData
import Charts

/// Retirement, brokerage and other investment accounts: value, growth and contributions over a quarter,
/// six months or a year.
struct InvestmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var period: ReportPeriod = .quarterly
    @State private var anchor = Date.now

    private var investmentAccounts: [Account] { accounts.filter { $0.type.group == .investments } }

    private var earliest: Date? { modelContext.earliestTransactionDate(in: investmentAccounts) }

    var body: some View {
        let range = Reports.range(period, anchor: anchor)
        let report = Investments.build(accounts, range: range)

        ScrollView {
            VStack(spacing: 14) {
                PageTitle("Investments")
                if !investmentAccounts.isEmpty {
                    PeriodControls(periods: ReportPeriod.longTerm, period: $period, anchor: $anchor, earliest: earliest)
                }
                if investmentAccounts.isEmpty {
                    sampleBanner
                    WithInvestmentsData { sampleTiles($0) }
                    deepDive
                    WithInvestmentsData { sampleAccounts($0) }
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

                    deepDive
                }
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    // MARK: Deep dive

    /// The year behind the numbers above and six months ahead. These ignore the period picked at the top.
    private var deepDive: some View {
        VStack(spacing: 14) {
            HStack {
                Text("DEEP DIVE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("last 12 months and the next 6").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 8)
            PortfolioValueReport()
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
            InvestmentGainsReport()
        }
    }

    // MARK: Sample

    private var sampleBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("This is sample data").font(.headline)
                Text("Add a 401(k), IRA, brokerage, 529 or crypto account and this page fills in with your own investments.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add an Account") {
                UserDefaults.standard.set("accounts", forKey: MacSettingsView.tabKey)
                openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sampleTiles(_ data: InvestmentsData) -> some View {
        StatGrid {
            tile("Value", Decimal(data.totalValue), color: .primary, note: "sample portfolio")
            tile("Growth", Decimal(data.growth12), color: Theme.green, note: "over 12 months")
            tile("Contributions", Decimal(data.contributed12), color: .primary, note: "net money in, 12 months")
            tile("Unrealized Gain", Decimal(data.unrealizedGain), color: data.unrealizedGain >= 0 ? Theme.green : Theme.red, note: "on what you paid")
        }
    }

    private func sampleAccounts(_ data: InvestmentsData) -> some View {
        ReportPanel(title: "Accounts (\(data.accounts.count))", summary: "Every investment account with its value, growth and share.", sample: true) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(data.accounts) { account in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: account.symbol).foregroundStyle(Theme.green).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.name).fontWeight(.medium)
                                Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ReportFormat.money(account.value)).fontWeight(.semibold)
                        }
                        HStack {
                            Text("Growth \(ReportFormat.signed(Decimal(account.growth)))\(account.growthRate.map { " · \(ReportFormat.percent($0 * 100, digits: 1))" } ?? "")")
                                .foregroundStyle(account.growth >= 0 ? Theme.green : Theme.red)
                            Spacer()
                            Text("\(ReportFormat.percent(account.value / max(data.totalValue, 1) * 100)) of your investments").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        ProgressView(value: account.value / max(data.totalValue, 1)).tint(Theme.green)
                    }
                }
            }
        }
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
