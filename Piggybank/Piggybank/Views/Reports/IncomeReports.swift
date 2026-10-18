import SwiftUI
import SwiftData
import Charts

// MARK: By category

struct IncomeByCategoryReport: View {
    @Environment(\.reportInputs) private var inputs

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    var body: some View {
        let income = inputs.inPeriod.filter { $0.amount > 0 }
        var table: [String: Double] = [:]
        for transaction in income { table[transaction.category?.name ?? "Uncategorized", default: 0] += transaction.amount.doubleValue }
        let slices = table.map { Slice(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
        let total = slices.reduce(0) { $0 + $1.value }

        return ReportPanel(title: "Income by Category", summary: "Each source of income in \(inputs.periodName) and its share.",
                    headline: slices.isEmpty ? nil : ReportFormat.money(total), headlineNote: slices.isEmpty ? nil : "in this period") {
            if slices.isEmpty {
                ReportEmpty(message: "No income in this period.", height: 170)
            } else {
                HStack(spacing: 18) {
                    Chart(slices) { slice in
                        SectorMark(angle: .value("Income", slice.value), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(by: .value("Category", slice.name))
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 130, height: 130)
                    VStack(spacing: 7) {
                        ForEach(slices.prefix(6)) { slice in
                            HStack {
                                Text(slice.name).lineLimit(1)
                                Spacer()
                                Text(ReportFormat.money(slice.value))
                                Text((slice.value / max(total, 1)).formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }
}

// MARK: By payer

struct IncomeByPayerReport: View {
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let calendar = Calendar.current
        let months = ReportInputs.months()
        let income = inputs.inPeriod.filter { $0.amount > 0 }
        let groups = Dictionary(grouping: income) { $0.payee.trimmingCharacters(in: .whitespaces).isEmpty ? "No payer" : $0.payee.trimmingCharacters(in: .whitespaces) }
            .map { name, list in (name, list.count, list.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.2 > $1.2 }
        // How many of the last twelve months each payer paid you in: a sign of how steady it is.
        func monthsPaid(_ name: String) -> Int {
            Set(inputs.year.filter { $0.amount > 0 && !$0.isTransfer && $0.date >= months[0] && ($0.payee.trimmingCharacters(in: .whitespaces).isEmpty ? "No payer" : $0.payee.trimmingCharacters(in: .whitespaces)) == name }
                .map { calendar.component(.month, from: $0.date) + 100 * calendar.component(.year, from: $0.date) }).count
        }

        return ReportPanel(title: "Income by Payer", summary: "Who pays you in \(inputs.periodName), and how steady each source has been over the last year.") {
            if groups.isEmpty {
                ReportEmpty(message: "No income in this period.", height: 170)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("PAYER"); Text("DEPOSITS").gridColumnAlignment(.trailing); Text("TOTAL").gridColumnAlignment(.trailing); Text("MONTHS PAID").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(4)
                    ForEach(groups.prefix(8), id: \.0) { name, count, total in
                        let paid = monthsPaid(name)
                        GridRow {
                            Text(name).lineLimit(1)
                            Text("\(count)")
                            Text(total, format: .appCurrency).foregroundStyle(Theme.green)
                            Text("\(paid) of 12").foregroundStyle(paid >= 10 ? Theme.green : (paid >= 6 ? .primary : .secondary))
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: Trend

struct IncomeTrendReport: View {
    @Environment(\.reportInputs) private var inputs

    private struct Bar: Identifiable {
        let date: Date
        let value: Double
        let projected: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(projected)" }
    }

    var body: some View {
        let totals = inputs.monthlyTotals()
        let calendar = Calendar.current
        let recent = totals.suffix(4).dropLast()
        let average = recent.reduce(0) { $0 + $1.income } / Double(max(recent.count, 1))
        let past = totals.map { Bar(date: $0.date, value: $0.income, projected: false) }
        let future = (1...ReportTrends.futureMonths).compactMap { month -> Bar? in
            calendar.date(byAdding: .month, value: month, to: totals[totals.count - 1].date).map { Bar(date: $0, value: average, projected: true) }
        }

        return ReportPanel(title: "Income Trend", summary: "Income month by month, with the next six months at your average over the last three full months.",
                    headline: past.allSatisfy({ $0.value == 0 }) ? nil : ReportFormat.money(average), headlineNote: "expected per month") {
            if past.allSatisfy({ $0.value == 0 }) {
                ReportEmpty(message: "No income yet.", height: 210)
            } else {
                Chart(past + future) { bar in
                    BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Income", bar.value))
                        .foregroundStyle(Theme.green)
                        .opacity(bar.projected ? 0.4 : 1)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 210)
                ReportKey(items: [.init(color: Theme.green, text: "Income"), .init(color: Theme.green.opacity(0.4), text: "Next 6 months")])
            }
        }
    }
}

// MARK: Savings rate

struct SavingsRateReport: View {
    @Environment(\.reportInputs) private var inputs

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let projected: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(projected)" }
    }

    var body: some View {
        let calendar = Calendar.current
        let totals = inputs.monthlyTotals()
        let past = totals.filter { $0.income > 0 }.map { Point(date: $0.date, value: ($0.income - $0.spending) / $0.income * 100, projected: false) }
        let recent = past.suffix(3)
        let average = recent.reduce(0) { $0 + $1.value } / Double(max(recent.count, 1))

        return ReportPanel(title: "Savings Rate", summary: "The share of income you keep each month, and the next six months at your recent average.",
                    headline: past.isEmpty ? nil : ReportFormat.percent(average), headlineNote: past.isEmpty ? nil : "recent average") {
            if past.count < 2 {
                ReportEmpty(message: "Needs income in at least two months.", height: 190)
            } else if let last = past.last {
                let future = [Point(date: last.date, value: last.value, projected: true)]
                    + (1...ReportTrends.futureMonths).compactMap { month in
                        calendar.date(byAdding: .month, value: month, to: last.date).map { Point(date: $0, value: average, projected: true) }
                    }
                Chart {
                    ForEach(past) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Rate", point.value), series: .value("Series", "History"))
                            .foregroundStyle(Theme.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(future) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Rate", point.value), series: .value("Series", "Projection"))
                            .foregroundStyle(Theme.green.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                    }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.red.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text("\(Int(n))%") } } } }
                .frame(height: 190)
            }
        }
    }
}
