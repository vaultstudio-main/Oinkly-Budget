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

    private let months = 3

    private static let palette = ChartPalette.colors
    private static let otherColor = ChartPalette.other

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        let color: Color
        var id: String { name }
    }

    private var totals: [SpendingReport.CategoryTotal] { SpendingReport.totals(transactions, months: months) }
    private var hasData: Bool { SpendingReport.hasEnoughData(transactions, months: months) }

    private var slices: [Slice] {
        let top = totals.prefix(Self.palette.count)
        var result = top.enumerated().map { index, item in
            Slice(name: item.category.name, value: item.total.doubleValue, color: Self.palette[index])
        }
        let rest = totals.dropFirst(Self.palette.count).reduce(Decimal(0)) { $0 + $1.total }
        if rest > 0 { result.append(Slice(name: "Other", value: rest.doubleValue, color: Self.otherColor)) }
        return result
    }

    private let placeholderSlices: [Slice] = [
        Slice(name: "A", value: 38, color: palette[0]),
        Slice(name: "B", value: 24, color: palette[1]),
        Slice(name: "C", value: 16, color: palette[2]),
        Slice(name: "D", value: 12, color: palette[3]),
        Slice(name: "E", value: 10, color: palette[4]),
    ]

    var body: some View {
        Group {
            #if os(iOS)
            VStack(spacing: 24) {
                donut
                details
            }
            #else
            HStack(alignment: .top, spacing: 40) {
                donut
                details
            }
            #endif
        }
        .animation(.smooth, value: hasData)
    }

    // MARK: Chart

    private var donut: some View {
        let data = hasData ? slices : placeholderSlices
        return Chart(data) { slice in
            SectorMark(angle: .value("Spent", slice.value), innerRadius: .ratio(0.62), angularInset: 2)
                .cornerRadius(4)
                .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .opacity(hasData ? 1 : 0.28)
        .frame(width: 200, height: 200)
        .overlay { centerLabel }
    }

    @ViewBuilder
    private var centerLabel: some View {
        if hasData, let top = totals.first {
            VStack(spacing: 2) {
                Text("TOP CATEGORY").font(.caption2).foregroundStyle(.secondary)
                Text(top.category.name).font(.headline).multilineTextAlignment(.center)
                Text(top.total, format: .appCurrency).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(width: 110)
        } else {
            VStack(spacing: 2) {
                Text("PLACEHOLDER").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                Text("No data yet").font(.headline)
            }
        }
    }

    // MARK: Details

    @ViewBuilder
    private var details: some View {
        if hasData { realDetails } else { placeholderDetails }
    }

    private var realDetails: some View {
        let grand = totals.reduce(Decimal(0)) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(totals.prefix(Self.palette.count).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Circle().fill(Self.palette[index]).frame(width: 10, height: 10)
                        Text(item.category.name)
                        Spacer(minLength: 12)
                        Text(item.total, format: .appCurrency)
                        Text(grand > 0 ? (item.total / grand).formatted(.percent.precision(.fractionLength(0))) : "")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("TOP CATEGORY BY MONTH").font(.caption).foregroundStyle(.secondary)
                ForEach(SpendingReport.topByMonth(transactions, months: months)) { entry in
                    HStack(spacing: 10) {
                        Text(entry.month.formatted(.dateTime.month(.wide)))
                            .foregroundStyle(.secondary)
                            .frame(width: 84, alignment: .leading)
                        if let top = entry.top {
                            CategoryBadge(category: top.category, size: 24)
                            Text(top.category.name)
                            Spacer(minLength: 12)
                            Text(top.total, format: .appCurrency)
                        } else {
                            Text("No spending").foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                    .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholderDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([0.9, 0.7, 0.55, 0.4], id: \.self) { fraction in
                HStack(spacing: 10) {
                    Circle().fill(.secondary.opacity(0.2)).frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.15))
                        .frame(height: 12)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: fraction, anchor: .leading)
                }
            }
            Text("Your biggest spending categories for the last \(months) months will appear here once you've entered a few expenses with a category.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
