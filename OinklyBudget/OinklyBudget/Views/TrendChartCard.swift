import SwiftUI
import SwiftData
import Charts

enum TrendKind {
    case netWorth, debt, debtToIncome

    var title: String {
        switch self {
        case .netWorth: "Net Worth Over Time"
        case .debt: "Total Debt Over Time"
        case .debtToIncome: "Debt-to-Income Ratio"
        }
    }

    var summary: String {
        switch self {
        case .netWorth: "What you own minus what you owe, month by month, and where it's heading."
        case .debt: "Every loan and card together, and where it's heading at the monthly payments."
        case .debtToIncome: "Monthly debt payments as a share of monthly income, and where it's heading."
        }
    }

    var color: Color {
        switch self {
        case .netWorth: Theme.green
        case .debt: Theme.red
        case .debtToIncome: .orange
        }
    }

    var isPercent: Bool { self == .debtToIncome }
}

/// A real line chart: twelve months of history in solid, six months of projection dashed.
struct TrendChartCard: View {
    let kind: TrendKind
    var height: CGFloat = 200

    @Query private var allAccounts: [Account]
    @Environment(\.reportCardMinHeight) private var minHeight

    private var points: [TrendPoint]? {
        guard let snapshot = LedgerIndex.shared.latest else { return nil }
        let accounts = allAccounts.live
        switch kind {
        case .netWorth: return ReportTrends.netWorth(accounts: accounts, snapshot: snapshot)
        case .debt: return ReportTrends.debt(accounts: accounts, snapshot: snapshot)
        case .debtToIncome: return ReportTrends.debtToIncome(accounts: accounts, snapshot: snapshot)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.headline)
                    Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let points, points.filter({ !$0.projected }).count >= 2, let now = points.last(where: { !$0.projected }), let end = points.last, end.projected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(format(now.value)).font(.title3.bold())
                        Text("\(format(end.value)) in 6 months").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.title)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .panelBackground(cornerRadius: 12, continuous: true)
    }

    private var emptyMessage: String {
        guard kind == .debtToIncome else { return "Not enough history yet. This fills in as you add months of transactions." }
        let hasPayment = allAccounts.live.contains { ($0.isLoan || $0.isCreditCard) && $0.monthlyPayment > 0 }
        return hasPayment ? "Needs income recorded in at least two months to show a ratio."
                          : "Set a monthly payment on a loan or card, and add some income, to see this ratio."
    }

    @ViewBuilder
    private var content: some View {
        if let points {
            if points.filter({ !$0.projected }).count < 2 {
                ReportEmpty(message: emptyMessage, height: height + 22, shape: .line)
            } else {
                chart(points)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Calculating…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: height)
        }
    }

    private func chart(_ points: [TrendPoint]) -> some View {
        let history = points.filter { !$0.projected }
        let future = points.filter(\.projected)
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(history) { point in
                    AreaMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value))
                        .foregroundStyle(kind.color.opacity(0.12))
                    LineMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value), series: .value("Part", "History"))
                        .foregroundStyle(kind.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                ForEach(future) { point in
                    LineMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value), series: .value("Part", "Projection"))
                        .foregroundStyle(kind.color.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                }
                if let first = future.first {
                    RuleMark(x: .value("Today", first.date, unit: .month))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) { Text(axis(number)) }
                    }
                }
            }
            .frame(height: height)

            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1).fill(kind.color).frame(width: 14, height: 3)
                    Text("Last 12 months")
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(kind.color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 14, height: 3)
                    Text("Next 6 months")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func format(_ value: Double) -> String {
        kind.isPercent ? "\(value.formatted(.number.precision(.fractionLength(1))))%" : Decimal(value).formatted(.appCurrency)
    }

    private func axis(_ value: Double) -> String {
        kind.isPercent ? "\(Int(value.rounded()))%" : value.formatted(.number.notation(.compactName))
    }
}
