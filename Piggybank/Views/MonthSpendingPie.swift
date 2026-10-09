import SwiftUI
import SwiftData
import Charts

/// Donut chart of one month's spending by category. Every month starts from zero and has its own chart.
struct MonthSpendingPie: View {
    let transactions: [Transaction]
    let month: Date

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        let color: Color
        let amount: Decimal
        var id: String { name }
    }

    private var totals: [SpendingReport.CategoryTotal] { SpendingReport.totals(transactions, month: month) }
    private var grandTotal: Decimal { totals.reduce(Decimal(0)) { $0 + $1.total } }

    private var slices: [Slice] {
        let palette = ChartPalette.colors
        var result = totals.prefix(palette.count).enumerated().map { index, item in
            Slice(name: item.category.name, value: item.total.doubleValue, color: palette[index], amount: item.total)
        }
        let rest = totals.dropFirst(palette.count).reduce(Decimal(0)) { $0 + $1.total }
        if rest > 0 { result.append(Slice(name: "Other", value: rest.doubleValue, color: ChartPalette.other, amount: rest)) }
        return result
    }

    private let placeholder: [Slice] = [
        Slice(name: "A", value: 38, color: ChartPalette.colors[0], amount: 0),
        Slice(name: "B", value: 24, color: ChartPalette.colors[1], amount: 0),
        Slice(name: "C", value: 16, color: ChartPalette.colors[2], amount: 0),
        Slice(name: "D", value: 12, color: ChartPalette.colors[3], amount: 0),
        Slice(name: "E", value: 10, color: ChartPalette.colors[4], amount: 0),
    ]

    var body: some View {
        let hasSpending = !totals.isEmpty
        VStack(spacing: 16) {
            Chart(hasSpending ? slices : placeholder) { slice in
                SectorMark(angle: .value("Spent", slice.value), innerRadius: .ratio(0.62), angularInset: 2)
                    .cornerRadius(4)
                    .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .opacity(hasSpending ? 1 : 0.25)
            .frame(width: 190, height: 190)
            .overlay { center(hasSpending) }
            .animation(.smooth, value: month)

            if hasSpending {
                VStack(spacing: 6) {
                    ForEach(slices) { slice in
                        HStack(spacing: 10) {
                            Circle().fill(slice.color).frame(width: 10, height: 10)
                            Text(slice.name)
                            Spacer(minLength: 12)
                            Text(slice.amount, format: .appCurrency)
                            Text(grandTotal > 0 ? (slice.amount / grandTotal).formatted(.percent.precision(.fractionLength(0))) : "")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
            } else {
                Text("Nothing spent in \(month.formatted(.dateTime.month(.wide).year())) yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func center(_ hasSpending: Bool) -> some View {
        VStack(spacing: 2) {
            Text(hasSpending ? "SPENT" : "NO SPENDING").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            if hasSpending {
                Text(grandTotal, format: .appCurrency)
                    .font(.title3.bold())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: 110)
    }
}
