import SwiftUI
import SwiftData
import Charts

/// Spending per budgeted category for each of the last twelve months.
private struct BudgetHistory {
    let categories: [Category]
    let months: [Date]
    /// spent[category][month index]
    let spent: [PersistentIdentifier: [Double]]

    init(categories all: [Category], inputs: ReportInputs) {
        categories = all.live.filter { !$0.isIncome && $0.showOnBudgets && $0.monthlyLimit > 0 }
            .sorted { $0.monthlyLimit > $1.monthlyLimit }
        months = ReportInputs.months()
        var table: [PersistentIdentifier: [Double]] = [:]
        let ids = Set(categories.map(\.persistentModelID))
        for category in categories { table[category.persistentModelID] = Array(repeating: 0, count: months.count) }
        for transaction in inputs.year where !transaction.isTransfer && transaction.amount < 0 {
            guard let id = transaction.category?.persistentModelID, ids.contains(id),
                  transaction.date >= months[0], let index = months.lastIndex(where: { $0 <= transaction.date }) else { continue }
            table[id]?[index] -= transaction.amount.doubleValue
        }
        spent = table
    }

    var currentIndex: Int { months.count - 1 }
}

private func barColor(_ ratio: Double) -> Color { ratio > 1 ? Theme.red : (ratio > 0.85 ? .orange : Theme.green) }

// MARK: Budget vs actual

struct BudgetVsActualReport: View {
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Environment(\.reportInputs) private var inputs

    private struct Row: Identifiable {
        let name: String
        let percent: Double
        let spent: Double
        let limit: Double
        var id: String { name }
    }

    var body: some View {
        let history = BudgetHistory(categories: allCategories, inputs: inputs)
        let all = history.categories.map { category -> Row in
            let spent = history.spent[category.persistentModelID]?[history.currentIndex] ?? 0
            let limit = category.monthlyLimit.doubleValue
            return Row(name: category.name, percent: spent / max(limit, 1) * 100, spent: spent, limit: limit)
        }
        // Most used first, so what needs attention is at the top. The rest are one line each.
        let rows = Array(all.sorted { $0.percent > $1.percent }.prefix(12))
        let budgeted = history.categories.reduce(0.0) { $0 + $1.monthlyLimit.doubleValue }
        let spent = all.reduce(0.0) { $0 + $1.spent }

        return ReportPanel(title: "Budget vs Actual", summary: "How much of each budget is used so far this month. The line is 100%.",
                           headline: history.categories.isEmpty ? nil : "\(ReportFormat.money(spent)) of \(ReportFormat.money(budgeted))",
                           headlineNote: history.categories.isEmpty ? nil : "\(ReportFormat.money(max(budgeted - spent, 0))) left · showing \(rows.count) of \(all.count)") {
            if history.categories.isEmpty {
                ReportEmpty(message: "No budgets are set. Add some in Settings ▸ Categories.", height: 190)
            } else {
                Chart(rows) { row in
                    BarMark(x: .value("Used", min(row.percent, 150)), y: .value("Category", row.name))
                        .foregroundStyle(barColor(row.percent / 100))
                        .cornerRadius(3)
                        .annotation(position: .trailing) {
                            Text("\(ReportFormat.money(row.spent)) of \(ReportFormat.money(row.limit))").font(.caption2).foregroundStyle(.secondary)
                        }
                    RuleMark(x: .value("Budget", 100)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXScale(domain: 0...190)
                .chartXAxis { AxisMarks(values: [0, 50, 100, 150]) { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text("\(Int(n))%") } } } }
                .frame(height: CGFloat(rows.count) * 28 + 20)
            }
        }
    }
}

// MARK: Over and under

struct BudgetOverUnderReport: View {
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let history = BudgetHistory(categories: allCategories, inputs: inputs)
        // The last six full months.
        let window = Array((history.currentIndex - 6)..<history.currentIndex)
        let rows = history.categories.map { category -> (Category, Int, Double, Double) in
            let values = window.map { history.spent[category.persistentModelID]?[$0] ?? 0 }
            let limit = category.monthlyLimit.doubleValue
            let over = values.filter { $0 > limit }.count
            let average = values.reduce(0, +) / Double(max(values.count, 1))
            return (category, over, average, average - limit)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.3 > $1.3 }

        ReportPanel(title: "Over and Under", summary: "Months you went over each budget in the last six full months, and your average against it.") {
            if history.categories.isEmpty {
                ReportEmpty(message: "No budgets are set.", height: 170)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("CATEGORY")
                        Text("MONTHS OVER").gridColumnAlignment(.trailing)
                        Text("AVERAGE").gridColumnAlignment(.trailing)
                        Text("VS BUDGET").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(4)
                    ForEach(rows.prefix(8), id: \.0.persistentModelID) { category, over, average, difference in
                        GridRow {
                            Label(category.name, systemImage: category.symbol).lineLimit(1)
                            Text("\(over) of 6").foregroundStyle(over >= 3 ? Theme.red : (over > 0 ? .orange : .secondary))
                            Text(ReportFormat.money(average))
                            Text(difference > 0 ? "+\(ReportFormat.money(difference))" : "−\(ReportFormat.money(-difference))")
                                .foregroundStyle(difference > 0 ? Theme.red : Theme.green)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: Budget trend

struct BudgetTrendReport: View {
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Environment(\.reportInputs) private var inputs

    private struct Point: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        let projected: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(kind)-\(projected)" }
    }

    var body: some View {
        let history = BudgetHistory(categories: allCategories, inputs: inputs)
        let budget = history.categories.reduce(0.0) { $0 + $1.monthlyLimit.doubleValue }
        let totals = history.months.indices.map { index in
            history.categories.reduce(0.0) { $0 + (history.spent[$1.persistentModelID]?[index] ?? 0) }
        }

        ReportPanel(title: "Budget Trend", summary: "Total spent in your budgeted categories against total budget, and the next six months at your recent average.") {
            if history.categories.isEmpty {
                ReportEmpty(message: "No budgets are set.", height: 190)
            } else {
                let recent = totals.suffix(4).dropLast()
                let average = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
                let calendar = Calendar.current
                let future: [Point] = (0...ReportTrends.futureMonths).compactMap { month in
                    guard let date = calendar.date(byAdding: .month, value: month, to: history.months[history.currentIndex]) else { return nil }
                    return Point(date: date, kind: "Spent", value: month == 0 ? totals[history.currentIndex] : average, projected: true)
                }
                let past = history.months.indices.map { Point(date: history.months[$0], kind: "Spent", value: totals[$0], projected: false) }
                let limit = (history.months + future.dropFirst().map(\.date)).map { Point(date: $0, kind: "Budget", value: budget, projected: false) }
                Chart {
                    ForEach(limit) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Amount", point.value), series: .value("Series", "Budget"))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 3]))
                    }
                    ForEach(past) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Amount", point.value), series: .value("Series", "Spent"))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(future) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Amount", point.value), series: .value("Series", "Projected"))
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 190)
                ReportKey(items: [.init(color: .accentColor, text: "Spent"), .init(color: .accentColor, text: "Next 6 months", dashed: true),
                                  .init(color: .secondary, text: "Total budget", dashed: true)])
            }
        }
    }
}

// MARK: Projected month end

struct ProjectedMonthEndReport: View {
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let history = BudgetHistory(categories: allCategories, inputs: inputs)
        let calendar = Calendar.current
        let day = Double(calendar.component(.day, from: .now))
        let length = Double(calendar.range(of: .day, in: .month, for: .now)?.count ?? 30)
        // Closest to (or over) its budget first.
        let rows = history.categories.map { category -> (Category, Double, Double) in
            let spent = history.spent[category.persistentModelID]?[history.currentIndex] ?? 0
            return (category, spent, spent / max(day, 1) * length)
        }
        .sorted { $0.2 / max($0.0.monthlyLimit.doubleValue, 1) > $1.2 / max($1.0.monthlyLimit.doubleValue, 1) }
        let over = rows.filter { $0.2 > $0.0.monthlyLimit.doubleValue }

        ReportPanel(title: "Projected Month End", summary: "Where each budget lands by the end of the month if you keep spending at today's pace.",
                    headline: history.categories.isEmpty ? nil : "\(over.count) over", headlineNote: history.categories.isEmpty ? nil : "of \(rows.count) budgets") {
            if history.categories.isEmpty {
                ReportEmpty(message: "No budgets are set.", height: 190)
            } else {
                VStack(spacing: 10) {
                    ForEach(rows.prefix(8), id: \.0.persistentModelID) { category, spent, projected in
                        let limit = category.monthlyLimit.doubleValue
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(category.name, systemImage: category.symbol).lineLimit(1)
                                Spacer()
                                Text("\(ReportFormat.money(projected)) of \(ReportFormat.money(limit))")
                                    .foregroundStyle(projected > limit ? Theme.red : .secondary)
                            }
                            .font(.callout)
                            GeometryReader { geo in
                                let width = geo.size.width
                                let scale = max(limit, projected, 1)
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                    Capsule().fill(barColor(projected / max(limit, 1)).opacity(0.35)).frame(width: width * projected / scale)
                                    Capsule().fill(barColor(spent / max(limit, 1))).frame(width: width * spent / scale)
                                    Rectangle().fill(Color.primary.opacity(0.6)).frame(width: 2).offset(x: width * limit / scale - 1)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
        }
    }
}
