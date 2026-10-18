import SwiftUI
import SwiftData
import Charts

// MARK: Year-end summary

struct YearEndSummaryReport: View {
    @Query private var allAccounts: [Account]
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let totals = inputs.monthlyTotals()
        let income = totals.reduce(0) { $0 + $1.income }
        let spending = totals.reduce(0) { $0 + $1.spending }
        let saved = income - spending
        let rate = income > 0 ? saved / income : nil
        let accounts = allAccounts.live
        let worth = snapshot.map { ReportTrends.netWorth(accounts: accounts, snapshot: $0).filter { !$0.projected } } ?? []
        let worthChange = (worth.last?.value ?? 0) - (worth.first?.value ?? 0)
        let debt = snapshot.map { ReportTrends.debt(accounts: accounts, snapshot: $0).filter { !$0.projected } } ?? []
        let debtPaid = (debt.first?.value ?? 0) - (debt.last?.value ?? 0)
        var byCategory: [String: Double] = [:]
        for transaction in inputs.year where !transaction.isTransfer && transaction.amount < 0 {
            byCategory[transaction.category?.name ?? "Uncategorized", default: 0] -= transaction.amount.doubleValue
        }
        let topCategory = byCategory.max { $0.value < $1.value }
        let bestMonth = totals.max { $0.income - $0.spending < $1.income - $1.spending }
        let busiest = totals.max { $0.spending < $1.spending }
        let empty = income == 0 && spending == 0

        return ReportPanel(title: "Year-End Summary", summary: "The last twelve months on one page: what came in, what went out, what you kept and how your net worth and debt moved.",
                           headline: empty ? nil : ReportFormat.money(saved), headlineNote: empty ? nil : "kept over 12 months") {
            if empty {
                ReportEmpty(message: "A summary appears once you've recorded some income and spending.", height: 200)
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ReportFigure(label: "Income", value: ReportFormat.money(income), color: Theme.green)
                        ReportFigure(label: "Spending", value: ReportFormat.money(spending), color: Theme.red)
                        ReportFigure(label: "Kept", value: ReportFormat.money(saved), color: saved >= 0 ? Theme.green : Theme.red)
                        ReportFigure(label: "Savings rate", value: rate.map { ReportFormat.percent($0 * 100) } ?? "—")
                    }
                    HStack(spacing: 10) {
                        ReportFigure(label: "Net worth change", value: ReportFormat.signed(Decimal(worthChange)), color: worthChange >= 0 ? Theme.green : Theme.red)
                        ReportFigure(label: "Debt paid down", value: ReportFormat.signed(Decimal(debtPaid)), color: debtPaid >= 0 ? Theme.green : Theme.red)
                        ReportFigure(label: "Biggest category", value: topCategory?.key ?? "—", note: topCategory.map { ReportFormat.money($0.value) })
                        ReportFigure(label: "Best month", value: bestMonth.map { $0.date.formatted(.dateTime.month(.wide)) } ?? "—",
                                     note: bestMonth.map { "kept \(ReportFormat.money($0.income - $0.spending))" })
                    }
                    if let busiest, busiest.spending > 0 {
                        Text("Your highest-spending month was \(busiest.date.formatted(.dateTime.month(.wide).year())) at \(ReportFormat.money(busiest.spending)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: Report card

struct ReportCardReport: View {
    @Query private var allAccounts: [Account]
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Environment(\.reportInputs) private var inputs

    private struct Grade: Identifiable {
        let title: String
        let value: String
        let note: String
        /// 0...1 score.
        let score: Double
        var id: String { title }

        var letter: String { score >= 0.9 ? "A" : (score >= 0.75 ? "B" : (score >= 0.6 ? "C" : (score >= 0.4 ? "D" : "F"))) }
        var color: Color { score >= 0.75 ? Theme.green : (score >= 0.5 ? .orange : Theme.red) }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let accounts = allAccounts.live
        let totals = inputs.monthlyTotals()
        let income = totals.reduce(0) { $0 + $1.income }
        let spending = totals.reduce(0) { $0 + $1.spending }
        var grades: [Grade] = []

        if income > 0 {
            let rate = (income - spending) / income
            grades.append(Grade(title: "Savings rate", value: ReportFormat.percent(rate * 100), note: "aim for 20% or more", score: max(min(rate / 0.2, 1), 0)))
        }
        if let snapshot, let dti = ReportTrends.debtToIncome(accounts: accounts, snapshot: snapshot).last(where: { !$0.projected }) {
            grades.append(Grade(title: "Debt-to-income", value: ReportFormat.percent(dti.value, digits: 1), note: "under 36% is healthy", score: max(min((50 - dti.value) / 14, 1), 0)))
        }
        let savings = accounts.filter { ($0.type == .savings || $0.type == .moneyMarket) && !$0.isClosed }.reduce(Decimal(0)) { $0 + max($1.balance, 0) }.doubleValue
        let recent = totals.suffix(4).dropLast()
        let monthly = recent.isEmpty ? 0 : recent.reduce(0) { $0 + $1.spending } / Double(recent.count)
        if monthly > 0 {
            let months = savings / monthly
            grades.append(Grade(title: "Emergency fund", value: "\(months.formatted(.number.precision(.fractionLength(1)))) months", note: "aim for 3 to 6", score: max(min(months / 6, 1), 0)))
        }
        let budgets = allCategories.live.filter { !$0.isIncome && $0.showOnBudgets && $0.monthlyLimit > 0 }
        if !budgets.isEmpty {
            let start = ReportInputs.months().last ?? .now
            var spent: [PersistentIdentifier: Decimal] = [:]
            for transaction in inputs.year where !transaction.isTransfer && transaction.amount < 0 && transaction.date >= start {
                if let id = transaction.category?.persistentModelID { spent[id, default: 0] -= transaction.amount }
            }
            let within = budgets.filter { (spent[$0.persistentModelID] ?? 0) <= $0.monthlyLimit }.count
            grades.append(Grade(title: "Budgets", value: "\(within) of \(budgets.count)", note: "within budget this month", score: Double(within) / Double(budgets.count)))
        }
        let overall = grades.isEmpty ? nil : grades.reduce(0) { $0 + $1.score } / Double(grades.count)

        return ReportPanel(title: "Report Card", summary: "Four checks on your money: how much you keep, how heavy your debt is, how long your savings would last, and how your budgets are doing.",
                           headline: overall.map { Grade(title: "", value: "", note: "", score: $0).letter }, headlineNote: overall == nil ? nil : "overall") {
            if grades.isEmpty {
                ReportEmpty(message: "Needs some income, spending and savings to grade.", height: 190)
            } else {
                HStack(spacing: 10) {
                    ForEach(grades) { grade in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 9)
                                Circle().trim(from: 0, to: max(grade.score, 0.02)).stroke(grade.color, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                                Text(grade.letter).font(.title2.bold()).foregroundStyle(grade.color)
                            }
                            .frame(width: 70, height: 70)
                            Text(grade.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(grade.value).font(.callout)
                            Text(grade.note).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: What changed

struct WhatChangedReport: View {
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let calendar = Calendar.current
        let windows = ReportInputs.windows()
        let recentStart = windows[1].start
        let earlierStart = windows[2].start
        func sums(_ list: [Transaction]) -> (income: Double, spending: Double, byCategory: [String: Double]) {
            var income = 0.0, spending = 0.0
            var byCategory: [String: Double] = [:]
            for transaction in list {
                let amount = transaction.amount.doubleValue
                if amount > 0 { income += amount } else { spending -= amount; byCategory[transaction.category?.name ?? "Uncategorized", default: 0] -= amount }
            }
            return (income, spending, byCategory)
        }
        let now = sums(inputs.real(since: recentStart))
        let before = sums(inputs.real(since: earlierStart, before: recentStart))
        let names = Set(now.byCategory.keys).union(before.byCategory.keys)
        let changes = names.map { ($0, now.byCategory[$0, default: 0] - before.byCategory[$0, default: 0]) }
            .filter { abs($0.1) > 0.005 }
            .sorted { abs($0.1) > abs($1.1) }
        let hasData = now.income + now.spending + before.income + before.spending > 0
        _ = calendar

        return ReportPanel(title: "What Changed", summary: "The last three months against the three before: the biggest moves in income and spending.") {
            if !hasData {
                ReportEmpty(message: "Needs transactions in the last six months to compare.", height: 190)
            } else {
                HStack(spacing: 10) {
                    delta("Income", now.income, before.income, goodWhenUp: true)
                    delta("Spending", now.spending, before.spending, goodWhenUp: false)
                }
                if !changes.isEmpty {
                    Divider()
                    ForEach(changes.prefix(5), id: \.0) { name, change in
                        HStack {
                            Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right").foregroundStyle(change > 0 ? Theme.red : Theme.green).frame(width: 18)
                            Text(name).lineLimit(1)
                            Spacer()
                            Text(change > 0 ? "+\(ReportFormat.money(change))" : "−\(ReportFormat.money(-change))").foregroundStyle(change > 0 ? Theme.red : Theme.green)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func delta(_ title: String, _ now: Double, _ before: Double, goodWhenUp: Bool) -> some View {
        let change = now - before
        let good = (change >= 0) == goodWhenUp
        return ReportFigure(label: title, value: ReportFormat.money(now),
                            note: before == 0 ? "nothing in the 3 months before"
                                              : "\(change >= 0 ? "▲" : "▼") \(ReportFormat.money(abs(change))) (\(ReportFormat.percent(abs(change) / before * 100))) vs before",
                            color: change == 0 ? .primary : (good ? Theme.green : Theme.red))
    }
}

// MARK: Income and spending across the windows

struct IncomeSpendingWindowsReport: View {
    @Environment(\.reportInputs) private var inputs

    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        let projected: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(kind)-\(projected)" }
    }

    var body: some View {
        let windows = ReportInputs.windows()
        let figures = windows.map { window -> (String, Double, Double) in
            let list = inputs.real(since: window.start)
            return (window.title, list.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount.doubleValue }, list.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount.doubleValue })
        }
        let totals = inputs.monthlyTotals()
        let empty = totals.allSatisfy { $0.income == 0 && $0.spending == 0 }
        let calendar = Calendar.current
        let recent = totals.suffix(4).dropLast()
        let income = recent.reduce(0) { $0 + $1.income } / Double(max(recent.count, 1))
        let spending = recent.reduce(0) { $0 + $1.spending } / Double(max(recent.count, 1))
        var bars: [Bar] = totals.flatMap { [Bar(date: $0.date, kind: "Income", value: $0.income, projected: false), Bar(date: $0.date, kind: "Spending", value: $0.spending, projected: false)] }
        if let last = totals.last {
            for month in 1...ReportTrends.futureMonths {
                guard let date = calendar.date(byAdding: .month, value: month, to: last.date) else { continue }
                bars.append(Bar(date: date, kind: "Income", value: income, projected: true))
                bars.append(Bar(date: date, kind: "Spending", value: spending, projected: true))
            }
        }

        return ReportPanel(title: "Income & Spending", summary: "What came in and went out this month, over the last three and six months and over the last year, with twelve months of bars and the next six projected.") {
            if empty {
                ReportEmpty(message: "Income and spending appear here once you record some transactions.", height: 300, shape: .bars)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(figures, id: \.0) { title, income, spending in
                        let net = income - spending
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
                            figure("Income", income, Theme.green)
                            figure("Spending", spending, Theme.red)
                            figure("Kept", net, net >= 0 ? Theme.green : Theme.red, bold: true)
                            Text(income > 0 ? "\(ReportFormat.percent(net / income * 100)) savings rate" : "no income").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Chart(bars) { bar in
                    BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                        .foregroundStyle(by: .value("Kind", bar.kind))
                        .position(by: .value("Kind", bar.kind))
                        .opacity(bar.projected ? 0.4 : 1)
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale(["Income": Theme.green, "Spending": Theme.red])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 190)
                ReportKey(items: [.init(color: .secondary, text: "Faded: next 6 months", dashed: true)])
            }
        }
    }

    private func figure(_ title: String, _ value: Double, _ color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(ReportFormat.money(value)).fontWeight(bold ? .semibold : .regular).foregroundStyle(color)
        }
        .font(.callout)
    }
}

// MARK: Spending by category across the windows

struct SpendingByCategoryWindowsReport: View {
    @Environment(\.reportInputs) private var inputs

    var body: some View {
        let windows = ReportInputs.windows()
        let tables = windows.map { window in
            Dictionary(uniqueKeysWithValues: ReportInputs.categories(inputs.real(since: window.start), income: false).map { ($0.name, $0) })
        }
        let year = ReportInputs.categories(inputs.real(since: windows[3].start), income: false)
        let total = year.reduce(0) { $0 + $1.amount }

        ReportPanel(title: "Spending by Category", summary: "Every category's spending this month, over three and six months and over the last year, and its share of the year.",
                    headline: year.isEmpty ? nil : ReportFormat.money(total), headlineNote: year.isEmpty ? nil : "spent in the last year") {
            if year.isEmpty {
                ReportEmpty(message: "Spending by category appears here once you record some spending.", height: 300, shape: .table)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow {
                        Text("CATEGORY")
                        ForEach(windows) { Text($0.title.uppercased()).gridColumnAlignment(.trailing) }
                        Text("SHARE OF YEAR").gridColumnAlignment(.leading)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(windows.count + 2)
                    ForEach(year.prefix(10)) { line in
                        GridRow {
                            Label { Text(line.name).lineLimit(1) } icon: { Image(systemName: line.symbol).foregroundStyle(Color(hex: line.colorHex)) }
                            ForEach(tables.indices, id: \.self) { index in
                                let amount = tables[index][line.name]?.amount ?? 0
                                Text(amount > 0 ? ReportFormat.money(amount) : "—").foregroundStyle(amount > 0 ? .primary : .tertiary)
                            }
                            HStack(spacing: 6) {
                                ProgressView(value: total > 0 ? line.amount / total : 0).tint(Color(hex: line.colorHex)).frame(width: 70)
                                Text(ReportFormat.percent(total > 0 ? line.amount / total * 100 : 0)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}
