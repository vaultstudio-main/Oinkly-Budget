import SwiftUI
import SwiftData
import Charts

/// What a transaction's category reads as in a list: "Split (3)" for a split, else the category name.
private func categoryName(_ transaction: Transaction) -> String { transaction.splitTitle ?? transaction.category?.name ?? "Uncategorized" }
/// One category's name for totals, so each part of a split counts under its own category.
private func partName(_ category: Category?) -> String { category?.name ?? "Uncategorized" }
private func payeeName(_ transaction: Transaction) -> String {
    let name = transaction.payee.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? "No payee" : name
}

// MARK: Trend by category

struct SpendingTrendReport: View {
    @Environment(\.reportInputs) private var inputs

    private struct Point: Identifiable {
        let name: String
        let date: Date
        let value: Double
        let projected: Bool
        var id: String { "\(name)-\(date.timeIntervalSince1970)-\(projected)" }
    }

    var body: some View {
        let months = ReportInputs.months()
        var table: [String: [Double]] = [:]
        for transaction in inputs.year where !transaction.isTransfer && transaction.amount < 0 {
            guard transaction.date >= months[0], let index = months.lastIndex(where: { $0 <= transaction.date }) else { continue }
            for part in transaction.categoryParts {
                table[partName(part.category), default: Array(repeating: 0, count: months.count)][index] -= part.amount.doubleValue
            }
        }
        let top = table.sorted { $0.value.reduce(0, +) > $1.value.reduce(0, +) }.prefix(5)
        let calendar = Calendar.current
        let points: [Point] = top.flatMap { name, values -> [Point] in
            let recent = values.suffix(4).dropLast()
            let average = recent.reduce(0, +) / Double(max(recent.count, 1))
            let past = months.indices.map { Point(name: name, date: months[$0], value: values[$0], projected: false) }
            let future = (0...ReportTrends.futureMonths).compactMap { month -> Point? in
                guard let date = calendar.date(byAdding: .month, value: month, to: months[months.count - 1]) else { return nil }
                return Point(name: name, date: date, value: month == 0 ? values[values.count - 1] : average, projected: true)
            }
            return past + future
        }

        return ReportPanel(title: "Spending Trend by Category", summary: "Your five biggest spending categories month by month, with the next six months at their recent average.") {
            if top.isEmpty {
                ReportEmpty(message: "No spending yet. Categories appear here as you spend.", height: ReportSize.h(220))
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Month", point.date, unit: .month), y: .value("Spent", point.value),
                             series: .value("Series", "\(point.name)-\(point.projected)"))
                        .foregroundStyle(by: .value("Category", point.name))
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: point.projected ? [5, 4] : []))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: ReportSize.h(230))
            }
        }
    }
}

// MARK: Payees

struct SpendingByPayeeReport: View {
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let windows = Array(ReportInputs.windows().enumerated()).filter { [0, 1, 3].contains($0.offset) }.map(\.element)
        func totals(_ start: Date) -> [String: (count: Int, amount: Decimal)] {
            var table: [String: (count: Int, amount: Decimal)] = [:]
            for transaction in inputs.real(since: start) where transaction.amount < 0 {
                var entry = table[payeeName(transaction)] ?? (0, 0)
                entry.count += 1
                entry.amount -= transaction.amount
                table[payeeName(transaction)] = entry
            }
            return table
        }
        let tables = windows.map { totals($0.start) }
        let year = tables.last ?? [:]
        let rows = year.sorted { $0.value.amount > $1.value.amount }.prefix(8)

        return ReportPanel(title: "Spending by Payee", summary: "Who you pay the most: this month, the last three months and the last year.") {
            if rows.isEmpty {
                ReportEmpty(message: "Payees appear here once you record some spending.", height: ReportSize.h(220), shape: .table)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("PAYEE")
                        ForEach(windows) { Text($0.title.uppercased()).gridColumnAlignment(.trailing) }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(windows.count + 1)
                    ForEach(Array(rows), id: \.key) { name, entry in
                        GridRow {
                            HStack(spacing: 5) {
                                Text(name).lineLimit(1)
                                Text("\(entry.count)×").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(tables.indices, id: \.self) { index in
                                let amount = tables[index][name]?.amount ?? 0
                                Text(amount > 0 ? amount.formatted(.appCurrency) : "—").foregroundStyle(amount > 0 ? .primary : .tertiary)
                            }
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: Top spending

struct TopSpendingReport: View {
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let biggest = inputs.real(since: ReportInputs.windows()[1].start).filter { $0.amount < 0 }.sorted { $0.amount < $1.amount }.prefix(8)
        return ReportPanel(title: "Top Spending", summary: "The biggest single transactions in the last three months.") {
            if biggest.isEmpty {
                ReportEmpty(message: "No spending in this period.", height: ReportSize.h(170))
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("DATE"); Text("PAYEE"); Text("CATEGORY"); Text("AMOUNT").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(4)
                    ForEach(Array(biggest)) { transaction in
                        GridRow {
                            Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                            Text(payeeName(transaction)).lineLimit(1)
                            Text(categoryName(transaction)).lineLimit(1).foregroundStyle(.secondary)
                            Text(-transaction.amount, format: .appCurrency).foregroundStyle(Theme.red)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: Payment method

struct PaymentMethodReport: View {
    @Environment(\.reportInputs) private var inputs

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    var body: some View {
        let spending = inputs.real(since: ReportInputs.windows()[1].start).filter { $0.amount < 0 }
        var table: [String: Double] = [:]
        for transaction in spending {
            let name = transaction.customMethod?.name ?? transaction.paymentType?.group.title ?? "Not recorded"
            table[name, default: 0] -= transaction.amount.doubleValue
        }
        let slices = table.map { Slice(name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
        let total = slices.reduce(0) { $0 + $1.value }

        return ReportPanel(title: "Spending by Payment Method", summary: "How you paid over the last three months: cards, bank, cash, digital and your own methods.") {
            if slices.isEmpty {
                ReportEmpty(message: "No spending in this period.", height: ReportSize.h(170))
            } else {
                ShareBarChart(bars: ShareBarChart.money(slices.map { ($0.name, $0.value, nil) }, limit: 6))
            }
        }
    }
}

// MARK: Cash

struct CashSpendingReport: View {
    @Environment(\.reportInputs) private var inputs
    @Query private var allAccounts: [Account]

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    var body: some View {
        let months = ReportInputs.months()
        let cash = allAccounts.live.first(where: \.isCashOnHand)
        var spent = Array(repeating: 0.0, count: months.count)
        var taken = Array(repeating: 0.0, count: months.count)
        for transaction in inputs.year {
            guard transaction.account?.isCashOnHand == true, transaction.date >= months[0],
                  let index = months.lastIndex(where: { $0 <= transaction.date }) else { continue }
            if transaction.isAtmWithdrawal { if transaction.amount > 0 { taken[index] += transaction.amount.doubleValue } }
            else if !transaction.isTransfer && transaction.amount < 0 { spent[index] -= transaction.amount.doubleValue }
        }
        let bars = months.indices.flatMap { [Bar(date: months[$0], kind: "Cash spent", value: spent[$0]), Bar(date: months[$0], kind: "Taken from ATM", value: taken[$0])] }

        return ReportPanel(title: "Cash Spending", summary: "Cash on Hand: what you took out and what you spent, month by month.",
                    headline: cash.map { ReportFormat.money($0.balance.doubleValue) }, headlineNote: cash == nil ? nil : "cash on hand now") {
            if bars.allSatisfy({ $0.value == 0 }) {
                ReportEmpty(message: "No cash transactions yet. ATM withdrawals and cash spending show here.", height: ReportSize.h(170))
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                        .foregroundStyle(by: .value("Kind", bar.kind))
                        .position(by: .value("Kind", bar.kind))
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale(["Cash spent": Theme.red, "Taken from ATM": Color.teal])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: ReportSize.h(170))
            }
        }
    }
}

// MARK: Month against month

struct MonthAgainstMonthReport: View {
    @Environment(\.reportInputs) private var inputs

    private struct Bar: Identifiable {
        let label: String
        let kind: String
        let value: Double
        var id: String { "\(label)-\(kind)" }
    }

    var body: some View {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let starts = [calendar.date(byAdding: .month, value: -12, to: thisMonth) ?? thisMonth,
                      calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth, thisMonth]
        let labels = ["Same month last year", "Last month", "This month"]
        // Same slice of each month, so a month that isn't over yet isn't compared with a whole one.
        let day = calendar.component(.day, from: .now)
        func sums(_ start: Date) -> (income: Double, spending: Double, byCategory: [String: Double]) {
            let end = calendar.date(byAdding: .day, value: day, to: start) ?? start
            var income = 0.0, spending = 0.0
            var byCategory: [String: Double] = [:]
            for transaction in inputs.year where !transaction.isTransfer && transaction.date >= start && transaction.date < end {
                let amount = transaction.amount.doubleValue
                if amount > 0 { income += amount } else {
                    spending -= amount
                    for part in transaction.categoryParts { byCategory[partName(part.category), default: 0] -= part.amount.doubleValue }
                }
            }
            return (income, spending, byCategory)
        }
        let results = starts.map(sums)
        let bars = results.indices.flatMap { [Bar(label: labels[$0], kind: "Income", value: results[$0].income), Bar(label: labels[$0], kind: "Spending", value: results[$0].spending)] }
        let names = Set(results[2].byCategory.keys).union(results[1].byCategory.keys)
        let changes = names.map { ($0, results[2].byCategory[$0, default: 0] - results[1].byCategory[$0, default: 0]) }
            .sorted { abs($0.1) > abs($1.1) }.prefix(4)

        return ReportPanel(title: "Month Against Month", summary: "The first \(day) days of this month against the same days of last month and of this month last year.") {
            if bars.allSatisfy({ $0.value == 0 }) {
                ReportEmpty(message: "Needs a few months of transactions.", height: ReportSize.h(190))
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Period", bar.label), y: .value("Amount", bar.value))
                        .foregroundStyle(by: .value("Kind", bar.kind))
                        .position(by: .value("Kind", bar.kind))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(["Income": Theme.green, "Spending": Theme.red])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: ReportSize.h(170))
                if !changes.isEmpty {
                    Divider()
                    Text("BIGGEST CHANGES VS LAST MONTH").font(.caption2).foregroundStyle(.secondary)
                    ForEach(Array(changes), id: \.0) { name, change in
                        HStack {
                            Text(name).lineLimit(1)
                            Spacer()
                            Text(change >= 0 ? "+\(ReportFormat.money(change))" : "−\(ReportFormat.money(-change))")
                                .foregroundStyle(change > 0 ? Theme.red : Theme.green)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: Tax related

struct TaxRelatedReport: View {
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let months = ReportInputs.months()
        let start = months[0]
        var table: [String: (count: Int, amount: Decimal)] = [:]
        for transaction in inputs.year where !transaction.isTransfer && transaction.amount < 0 && transaction.date >= start {
            for part in transaction.categoryParts where part.category?.isTaxRelated == true {
                let name = partName(part.category)
                var entry = table[name] ?? (0, 0)
                entry.count += 1
                entry.amount -= part.amount
                table[name] = entry
            }
        }
        let rows = table.sorted { $0.value.amount > $1.value.amount }
        let total = rows.reduce(Decimal(0)) { $0 + $1.value.amount }

        return ReportPanel(title: "Tax-Related Spending", summary: "Over the last 12 months, spending in the categories you flag as tax-related in Settings ▸ Categories.",
                    headline: rows.isEmpty ? nil : total.formatted(.appCurrency), headlineNote: rows.isEmpty ? nil : "across \(rows.count) categories") {
            if rows.isEmpty {
                ReportEmpty(message: "No spending in categories flagged as tax-related yet. Flag them in Settings ▸ Categories.", height: ReportSize.h(170))
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow { Text("CATEGORY"); Text("TRANSACTIONS").gridColumnAlignment(.trailing); Text("TOTAL").gridColumnAlignment(.trailing) }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Divider().gridCellColumns(3)
                    ForEach(rows, id: \.key) { name, entry in
                        GridRow { Text(name); Text("\(entry.count)"); Text(entry.amount, format: .appCurrency) }.font(.callout)
                    }
                }
                Text("Charity, medical, dental, taxes and education are flagged to start with. Change them in Settings ▸ Categories.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
