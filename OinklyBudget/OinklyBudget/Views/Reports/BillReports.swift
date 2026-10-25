import SwiftUI
import SwiftData
import Charts

// MARK: By month

struct BillsByMonthReport: View {
    @Query private var allBills: [Bill]

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    var body: some View {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let months = (-5...6).compactMap { calendar.date(byAdding: .month, value: $0, to: thisMonth) }
        let bills = allBills.live
        var bars: [Bar] = []
        var upcoming = 0.0
        for month in months {
            let end = (calendar.date(byAdding: .month, value: 1, to: month) ?? month).addingTimeInterval(-1)
            let found = Bills.occurrences(bills, from: month, through: end)
            let paid = found.filter(\.isPaid).reduce(0.0) { $0 + $1.bill.amount.doubleValue }
            let due = found.filter { !$0.isPaid }.reduce(0.0) { $0 + $1.bill.amount.doubleValue }
            bars.append(Bar(date: month, kind: "Paid", value: paid))
            bars.append(Bar(date: month, kind: month < thisMonth ? "Not marked paid" : "Due", value: due))
            if month > thisMonth { upcoming += due }
        }

        return ReportPanel(title: "Bills by Month", summary: "What you pay in bills each month: the last five months, this one and the next six.",
                           headline: bills.isEmpty ? nil : ReportFormat.money(upcoming), headlineNote: bills.isEmpty ? nil : "due over the next 6 months") {
            if bills.isEmpty {
                ReportEmpty(message: "No bills yet. Add some on the Bills page.", height: ReportSize.h(190))
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                        .foregroundStyle(by: .value("Kind", bar.kind))
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale(["Paid": Theme.green, "Not marked paid": Color.orange, "Due": Color.accentColor.opacity(0.55)])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: ReportSize.h(190))
            }
        }
    }
}

// MARK: Paid vs due

struct BillsPaidVsDueReport: View {
    @Query private var allBills: [Bill]

    private struct Slice: Identifiable {
        let name: String
        let count: Int
        let color: Color
        var id: String { name }
    }

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -3, to: .now) ?? .now
        let end = calendar.date(byAdding: .day, value: 30, to: .now) ?? .now
        let found = Bills.occurrences(allBills.live, from: start, through: end)
        let paid = found.filter(\.isPaid)
        let overdue = found.filter(\.isOverdue)
        let upcoming = found.filter { !$0.isPaid && !$0.isOverdue }
        let slices = [Slice(name: "Paid", count: paid.count, color: Theme.green), Slice(name: "Overdue", count: overdue.count, color: Theme.red),
                      Slice(name: "Coming up", count: upcoming.count, color: .accentColor)].filter { $0.count > 0 }

        ReportPanel(title: "Paid vs Due", summary: "Bills in the last three months and the next 30 days: paid, overdue and still to come.") {
            if slices.isEmpty {
                ReportEmpty(message: "No bills in this window.", height: ReportSize.h(170))
            } else {
                ShareBarChart(bars: slices.map { ShareBar(name: $0.name, value: Double($0.count), label: "\($0.count)", color: $0.color) })
                if !overdue.isEmpty {
                    Divider()
                    ForEach(overdue.prefix(3)) { item in
                        HStack {
                            Label(item.bill.name, systemImage: "exclamationmark.circle").foregroundStyle(Theme.red).lineLimit(1)
                            Spacer()
                            Text("due \(item.date.formatted(.dateTime.month(.abbreviated).day()))").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: Next six months

struct NextSixMonthsBillsReport: View {
    @Query private var allBills: [Bill]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .month, value: ReportTrends.futureMonths, to: today) ?? today
        let found = Bills.occurrences(allBills.live, from: today, through: end).filter { !$0.isPaid }
        let grouped = Dictionary(grouping: found) { $0.bill.persistentModelID }
        let rows = grouped.values.map { list -> (Bill, Int, Double, Date) in
            (list[0].bill, list.count, list.reduce(0.0) { $0 + $1.bill.amount.doubleValue }, list.map(\.date).min() ?? today)
        }.sorted { $0.2 > $1.2 }
        let total = rows.reduce(0.0) { $0 + $1.2 }

        return ReportPanel(title: "Next 6 Months of Bills", summary: "Every bill still to pay over the next six months, and what it adds up to.",
                           headline: rows.isEmpty ? nil : ReportFormat.money(total), headlineNote: rows.isEmpty ? nil : "\(ReportFormat.money(total / 6)) a month on average") {
            if rows.isEmpty {
                ReportEmpty(message: "Nothing due in the next six months.", height: ReportSize.h(170))
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow {
                        Text("BILL"); Text("AMOUNT").gridColumnAlignment(.trailing); Text("REPEATS"); Text("NEXT DUE").gridColumnAlignment(.trailing)
                        Text("TIMES").gridColumnAlignment(.trailing); Text("6-MONTH TOTAL").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(6)
                    ForEach(rows, id: \.0.persistentModelID) { bill, count, sum, next in
                        GridRow {
                            HStack(spacing: 6) {
                                if bill.isImportant { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                                Text(bill.name).lineLimit(1)
                            }
                            Text(bill.amount, format: .appCurrency)
                            Text(bill.frequency.title).foregroundStyle(.secondary)
                            Text(next, format: .dateTime.month(.abbreviated).day())
                            Text("\(count)")
                            Text(ReportFormat.money(sum)).fontWeight(.medium)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: By category

struct BillsByCategoryReport: View {
    @Query private var allBills: [Bill]

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .year, value: 1, to: today) ?? today
        // A year of due dates, spread over twelve months, so a yearly bill counts for its monthly share.
        var table: [String: Double] = [:]
        for item in Bills.occurrences(allBills.live, from: today, through: end) {
            table[item.bill.category?.name ?? "Uncategorized", default: 0] += item.bill.amount.doubleValue / 12
        }
        let slices = table.map { Slice(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
        let total = slices.reduce(0) { $0 + $1.value }

        return ReportPanel(title: "Bills by Category", summary: "Which categories your bills fall in, as a monthly amount.",
                           headline: slices.isEmpty ? nil : ReportFormat.money(total), headlineNote: slices.isEmpty ? nil : "a month in bills") {
            if slices.isEmpty {
                ReportEmpty(message: "No bills yet.", height: ReportSize.h(170))
            } else {
                ShareBarChart(bars: ShareBarChart.money(slices.map { ($0.name, $0.value, nil) }, limit: 6))
            }
        }
    }
}
