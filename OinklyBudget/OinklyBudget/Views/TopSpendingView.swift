import SwiftUI
import SwiftData
import Charts

/// Colors shared by the spending charts.
enum ChartPalette {
    static let colors: [Color] = [
        Color(red: 0.62, green: 0.89, blue: 0.40),
        Color(red: 0.97, green: 0.64, blue: 0.30),
        Color(red: 0.66, green: 0.65, blue: 0.95),
        Color(red: 0.35, green: 0.65, blue: 0.98),
        Color(red: 0.94, green: 0.47, blue: 0.49),
        Color(red: 0.98, green: 0.84, blue: 0.35),
    ]
    static let other = Color.gray
}

/// Donut chart and ranked list of the top spending categories over the last three months.
/// Until there are enough expenses to say anything useful, it shows a clearly labeled placeholder.
struct TopSpendingView: View {
    let transactions: [Transaction]
    /// Show money coming in instead of money going out.
    var income = false

    private let months = 3

    private static let palette = ChartPalette.colors
    private static let otherColor = ChartPalette.other

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        let color: Color
        var id: String { name }
    }

    private var totals: [SpendingReport.CategoryTotal] { SpendingReport.totals(transactions, months: months, income: income) }
    private var hasData: Bool { SpendingReport.hasEnoughData(transactions, months: months, income: income) }

    private var slices: [Slice] {
        let top = totals.prefix(Self.palette.count)
        var result = top.enumerated().map { index, item in
            Slice(name: item.category.name, value: item.total.doubleValue, color: Self.palette[index])
        }
        let rest = totals.dropFirst(Self.palette.count).reduce(Decimal(0)) { $0 + $1.total }
        if rest > 0 { result.append(Slice(name: "Other", value: rest.doubleValue, color: Self.otherColor)) }
        return result
    }

    var body: some View {
        // One set height: the figures scroll inside it, and a plain note holds its place until there is enough to show.
        if hasData {
            ScrollView {
                HStack(alignment: .top, spacing: 30) {
                    donut
                    details
                }
            }
            .frame(height: SummaryCardSize.spending)
        } else {
            ReportEmpty(message: income
                        ? "Your biggest income categories show up here once you've entered a few deposits with a category."
                        : "Your biggest spending categories show up here once you've entered a few expenses with a category.",
                        height: SummaryCardSize.spending, title: "Not enough yet", clean: true, symbol: "chart.pie").frame(height: SummaryCardSize.spending)
        }
    }

    // MARK: Chart

    private var donut: some View {
        let grand = totals.reduce(Decimal(0)) { $0 + $1.total }
        return Chart(slices) { slice in
            SectorMark(angle: .value(income ? "Earned" : "Spent", slice.value), innerRadius: .ratio(0.64), angularInset: 2)
                .cornerRadius(4)
                .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .frame(width: 210, height: 210)
        .overlay {
            VStack(spacing: 2) {
                Text(income ? "EARNED" : "SPENT").font(.caption2).foregroundStyle(.secondary)
                Text(grand, format: .appCurrency).font(.title3.bold())
                Text("last \(months) months").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Details

    private var details: some View {
        let grand = totals.reduce(Decimal(0)) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(totals.prefix(Self.palette.count).enumerated()), id: \.element.id) { index, item in
                    let share = grand > 0 ? (item.total / grand).doubleValue : 0
                    HStack(spacing: 10) {
                        CategoryBadge(category: item.category, size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.category.name)
                                Spacer(minLength: 12)
                                Text(item.total, format: .appCurrency).fontWeight(.medium)
                                Text(share.formatted(.percent.precision(.fractionLength(0))))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .font(.callout)
                            ProgressView(value: share).tint(Self.palette[index])
                        }
                    }
                }
            }

            Text("TOP CATEGORY BY MONTH").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(SpendingReport.topByMonth(transactions, months: months, income: income)) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.month.formatted(.dateTime.month(.wide))).font(.caption).foregroundStyle(.secondary)
                        if let top = entry.top {
                            HStack(spacing: 6) {
                                CategoryBadge(category: top.category, size: 22)
                                Text(top.category.name).font(.callout).lineLimit(1)
                            }
                            Text(top.total, format: .appCurrency).font(.callout.weight(.semibold))
                        } else {
                            Text(income ? "No income" : "No spending").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
