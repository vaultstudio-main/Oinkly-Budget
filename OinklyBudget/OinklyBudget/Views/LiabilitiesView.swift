import SwiftUI
import SwiftData
import Charts

/// Every credit card, mortgage and loan in one place: what is owed, how much is paid off, and how
/// leveraged you are.
struct LiabilitiesView: View {
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    /// Debt as it stood the given number of months ago, up to now.
    private func window(_ months: Int) -> Liabilities.Report {
        let start = Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .now
        return Liabilities.build(accounts, range: ReportRange(start: start, end: Date.now.addingTimeInterval(1)))
    }

    var body: some View {
        let report = window(3)
        let windows = [(3, report), (6, window(6)), (12, window(12))]

        VStack(spacing: 0) {
        PinnedHeader("Liabilities")
        ScrollView {
            VStack(spacing: 14) {
                if report.lines.isEmpty {
                    PlaceholderTiles(titles: ["Owed", "Outstanding", "Paid Off", "Monthly Payments"])
                    ReportCard(title: "Paid Down") {
                        NoDataNote(message: "No data yet. Add a credit card, mortgage or loan in Settings ▸ Accounts and it shows up here.")
                    }
                    ReportCard(title: "Leverage") {
                        NoDataNote(message: "No data yet. Leverage compares what you owe with what you own.")
                    }
                    ReportCard(title: "Where the Debt Is") {
                        NoDataNote(message: "No data yet. This breaks your debt down by type.")
                    }
                    ReportCard(title: "All Liabilities (0)") {
                        NoDataNote(message: "No credit cards, mortgages or loans yet.")
                    }
                } else {
                    tiles(report)
                    ReportCard(title: "Paid Down") { paidDown(windows) }
                    ReportCard(title: "Leverage") { leverage(report) }
                    if report.totalOwed > 0 {
                        ReportCard(title: "Where the Debt Is") { breakdown(report) }
                    }
                    ReportCard(title: "All Liabilities (\(report.lines.count))") { list(report) }
                    deepDive
                }
            }
            .padding(16)
        }
        }
        .background(Theme.background)
    }

    // MARK: Deep dive

    /// How the debt pays off: the line of what's owed, the payoff schedule, interest and what extra payments would do.
    private var deepDive: some View {
        VStack(spacing: 14) {
            HStack {
                Text("PAYOFF DEEP DIVE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("last 12 months and the next 6").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 8)
            HStack(alignment: .top, spacing: 14) {
                TrendChartCard(kind: .debt, height: 190)
                TrendChartCard(kind: .debtToIncome, height: 190)
            }
            .fixedSize(horizontal: false, vertical: true)
            LoanPayoffScheduleReport()
            HStack(alignment: .top, spacing: 14) {
                AheadOrBehindReport()
                InterestPaidReport()
            }
            .fixedSize(horizontal: false, vertical: true)
            CreditCardUseReport()
            DebtPayoffPlanReport()
        }
        .environment(\.reportCardMinHeight, 290)
    }

    // MARK: Tiles

    private func tiles(_ report: Liabilities.Report) -> some View {
        StatGrid {
            StatTile(title: "Owed") {
                Text(report.totalOwed, format: .appCurrency).foregroundStyle(Theme.red)
            } note: {
                Text("across \(report.lines.count) account\(report.lines.count == 1 ? "" : "s")")
            }
            StatTile(title: "Outstanding") {
                Text("\(report.outstanding) of \(report.lines.count)")
            } note: {
                Text("\(report.paidOff) paid off")
            }
            StatTile(title: "Paid Off") {
                Text(report.payoffFraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                    .foregroundStyle(Theme.green)
            } note: {
                Text(report.payoffFraction == nil
                     ? "set loan amounts or card limits to track"
                     : "\(report.paidSoFar.formatted(.appCurrency)) of \(report.originalBorrowed.formatted(.appCurrency))")
            }
            StatTile(title: "Monthly Payments") {
                Text(report.monthlyPayments, format: .appCurrency)
            } note: {
                Text(report.debtFreeDate.map { "debt-free about \($0.formatted(.dateTime.month(.abbreviated).year()))" }
                     ?? (report.monthlyPayments > 0 ? "add a payment to each for a date" : "none set"))
            }
        }
    }

    // MARK: Paid down

    /// How the debt moved over the last three months, six months and year, side by side.
    private func paidDown(_ windows: [(Int, Liabilities.Report)]) -> some View {
        let year = windows.last?.1
        return VStack(alignment: .leading, spacing: 14) {
            if let trend = year?.trend, trend.count > 1 {
                Chart(trend) { point in
                    LineMark(x: .value("Month", point.date), y: .value("Owed", point.owed))
                        .foregroundStyle(Theme.red)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Month", point.date), y: .value("Owed", point.owed))
                        .foregroundStyle(Theme.red)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXScale(range: .plotDimension(padding: 24))
                .chartXAxis { AxisMarks(values: trend.map(\.date)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(height: 160)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(windows, id: \.0) { months, report in
                    let start = report.startOwed ?? 0
                    let net = report.totalOwed - start
                    VStack(alignment: .leading, spacing: 8) {
                        Text(months == 12 ? "LAST YEAR" : "LAST \(months) MONTHS").font(.caption2).foregroundStyle(.secondary)
                        row("Owed then", start)
                        row("Paid down", report.paidDown)
                        if report.borrowed > 0 { row("Borrowed", report.borrowed) }
                        row("Owed now", report.totalOwed, bold: true)
                        Text(net == 0 ? "No change." : net < 0 ? "Down \((-net).formatted(.appCurrency))" : "Up \(net.formatted(.appCurrency))")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(net <= 0 ? Theme.green : Theme.red)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: Leverage

    private func leverage(_ report: Liabilities.Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ratio = report.debtToAssets {
                HStack(alignment: .firstTextBaseline) {
                    Text(ratio, format: .percent.precision(.fractionLength(0))).font(.largeTitle.bold()).foregroundStyle(color(for: ratio))
                    Text("of what you own is owed").foregroundStyle(.secondary)
                }
                ProgressView(value: min(ratio, 1)).tint(color(for: ratio))
                Text("You owe \((report.totalOwed / report.totalAssets).formatted(.appCurrency)) for every \(Decimal(1).formatted(.appCurrency)) you own.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Leverage appears once your asset accounts have a balance.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Divider()
            row("Total assets", report.totalAssets)
            row("Total owed", report.totalOwed)
            row("Net worth", report.netWorth, bold: true)
        }
    }

    private func color(for ratio: Double) -> Color {
        ratio < 0.3 ? Theme.green : ratio < 0.6 ? .orange : Theme.red
    }

    private func row(_ title: String, _ value: Decimal, bold: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(value, format: .appCurrency).fontWeight(bold ? .semibold : .regular)
        }
        .font(.callout)
    }

    // MARK: Breakdown

    private func breakdown(_ report: Liabilities.Report) -> some View {
        let owing = report.lines.filter { !$0.isPaidOff }
        return VStack(alignment: .leading, spacing: 12) {
            ShareBarChart(bars: ShareBarChart.money(owing.map { ($0.name, $0.owed.doubleValue, nil) }, limit: 10))
            Divider()
            row("Mortgages & loans", report.loanOwed)
            row("Credit cards", report.cardOwed)
        }
    }

    // MARK: List

    private func list(_ report: Liabilities.Report) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(report.lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 { Divider() }
                lineRow(line)
            }
        }
    }

    private func lineRow(_ line: Liabilities.Line) -> some View {
        let progress = line.progress
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: line.symbol).foregroundStyle(Theme.red).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.name).fontWeight(.medium)
                    Text(line.purpose.isEmpty ? line.typeTitle : "\(line.typeTitle) · \(line.purpose)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if line.isPaidOff {
                    Label("Paid off", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.callout)
                } else {
                    Text(line.owed, format: .appCurrency).fontWeight(.semibold)
                }
            }

            if line.hasProgress {
                ProgressView(value: progress.fraction).tint(Theme.green)
                HStack {
                    Text("\(progress.fraction.formatted(.percent.precision(.fractionLength(0)))) paid off")
                    Spacer()
                    Text("\(progress.paidOff.formatted(.appCurrency)) of \(progress.original.formatted(.appCurrency))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if line.hasLimitBar {
                ProgressView(value: line.limitFraction).tint(Theme.green)
                HStack {
                    Text("\(line.limitFraction.formatted(.percent.precision(.fractionLength(0)))) paid off")
                    Spacer()
                    Text("\(max(line.creditLimit - line.owed, 0).formatted(.appCurrency)) of \(line.creditLimit.formatted(.appCurrency))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if line.isLoan && !line.isPaidOff {
                Text("Add the original loan amount in Settings ▸ Accounts to track payoff.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let paid = line.paidDown, paid != 0 {
                Text(paid > 0 ? "Paid down \(paid.formatted(.appCurrency)) in the last 3 months" : "Up \(abs(paid).formatted(.appCurrency)) in the last 3 months")
                    .font(.caption)
                    .foregroundStyle(paid > 0 ? Theme.green : Theme.red)
            }
            if !line.isPaidOff {
                details(line)
            }
        }
    }

    @ViewBuilder
    private func details(_ line: Liabilities.Line) -> some View {
        let progress = line.progress
        if !line.isLoan {
            // A card has no schedule, so this is a guess: the balance spread over the months left in the year.
            Text("Pay about \(progress.monthlyPayment.formatted(.appCurrency)) a month and it is paid off by \(line.yearEnd.formatted(.dateTime.month(.wide).year())), before any interest.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
        let parts = [
            progress.monthlyPayment > 0 ? "\(progress.monthlyPayment.formatted(.appCurrency))/mo" : nil,
            progress.paymentsLeft.map { "\($0) payment\($0 == 1 ? "" : "s") left" },
            progress.targetDate.map { date in
                let when = date.formatted(.dateTime.month(.abbreviated).year())
                switch progress.targetStatus() {
                case .onTrack: return "on track for \(when)"
                case .behind: return "behind for \(when)"
                case .pastDue: return "past due \(when)"
                case nil: return "goal \(when)"
                }
            },
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
        }
    }
}
