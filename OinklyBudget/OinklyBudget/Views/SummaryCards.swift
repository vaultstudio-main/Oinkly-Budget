import SwiftUI
import SwiftData
import Charts

// MARK: Balance sheet

/// What you own and what you owe, with net worth and how it moved over the last three months.
struct SummaryBalanceCard: View {
    let accounts: [Account]

    private struct Row: Identifiable {
        let title: String
        let value: Double
        let color: Color
        var id: String { title }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest

        ReportPanel(title: "Summary", summary: "What you own and what you owe.") {
            if let snapshot {
                let cash = Summary.total(of: accounts, in: [.checkingSavings], snapshot: snapshot).doubleValue
                let investments = Summary.total(of: accounts, in: [.investments], snapshot: snapshot).doubleValue
                let property = Summary.total(of: accounts, in: [.assets], snapshot: snapshot).doubleValue
                let cards = -Summary.total(of: accounts, in: [.creditCards], snapshot: snapshot).doubleValue
                let loans = -Summary.total(of: accounts, in: [.loans], snapshot: snapshot).doubleValue
                let assets = cash + investments + property
                let debts = cards + loans
                let worth = assets - debts
                let history = ReportTrends.netWorth(accounts: accounts, snapshot: snapshot).filter { !$0.projected }
                let change = history.count >= 4 ? worth - history[history.count - 4].value : nil

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NET WORTH").font(.caption2).foregroundStyle(.secondary)
                        Text(ReportFormat.money(worth)).font(.largeTitle.bold()).foregroundStyle(worth >= 0 ? Theme.green : Theme.red)
                        if let change {
                            Text("\(change >= 0 ? "▲" : "▼") \(ReportFormat.money(abs(change))) in 3 months")
                                .font(.caption)
                                .foregroundStyle(change >= 0 ? Theme.green : Theme.red)
                        }
                    }
                    section("Assets", total: assets, color: Theme.green, rows: [
                        Row(title: "Cash & savings", value: cash, color: Theme.green),
                        Row(title: "Investments", value: investments, color: .purple),
                        Row(title: "Property & other", value: property, color: .teal),
                    ])
                    section("Liabilities", total: debts, color: Theme.red, rows: [
                        Row(title: "Credit cards", value: cards, color: .orange),
                        Row(title: "Mortgages & loans", value: loans, color: Theme.red),
                    ])
                }
            } else {
                ReportCalculating(height: 240)
            }
        }
    }

    private func section(_ title: String, total: Double, color: Color, rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(ReportFormat.money(total)).font(.callout.weight(.semibold)).foregroundStyle(color)
            }
            // One bar split by what each row is of what the bar covers, so the mix reads at a glance. Only rows with something
            // in them are drawn, and the widths are shares of those rows, so a card that is in credit (a negative amount owed)
            // can't push the bar past the edge of the card.
            let shown = rows.filter { $0.value > 0 }
            let covered = shown.reduce(0) { $0 + $1.value }
            GeometryReader { geo in
                let gaps = CGFloat(max(shown.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(shown) { row in
                        RoundedRectangle(cornerRadius: 3).fill(row.color)
                            .frame(width: max((geo.size.width - gaps) * row.value / max(covered, 1), 2))
                    }
                    if shown.isEmpty { RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2)) }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
            }
            .frame(height: 8)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Circle().fill(row.color).frame(width: 8, height: 8)
                    Text(row.title).foregroundStyle(.secondary)
                    Spacer()
                    Text(ReportFormat.money(row.value))
                }
                .font(.callout)
            }
        }
    }
}

// MARK: Income and spending, across the windows

/// This month, the last three and six months and the last year side by side, with twelve months of bars and the
/// next six projected. Read from the ledger snapshot, so the Summary doesn't load a year of transactions.
struct SummaryFlowCard: View {
    private struct Bar: Identifiable {
        let date: Date
        let kind: String
        let value: Double
        let projected: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(kind)-\(projected)" }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest

        ReportPanel(title: "Income & Spending", summary: "This month, the last three and six months and the last year, with the next six months projected.") {
            if let snapshot {
                let income = snapshot.income.map(\.doubleValue)
                let spending = snapshot.spending.map(\.doubleValue)
                let count = income.count
                if income.allSatisfy({ $0 == 0 }) && spending.allSatisfy({ $0 == 0 }) {
                    ReportEmpty(message: "Income and spending appear here once you record some transactions.", height: 280, shape: .bars)
                } else {
                    let windows: [(String, Int)] = [("This month", 1), ("Last 3 months", 3), ("Last 6 months", 6), ("Last year", 12)]
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(windows, id: \.0) { title, months in
                            let earned = income.suffix(months).reduce(0, +)
                            let spent = spending.suffix(months).reduce(0, +)
                            let net = earned - spent
                            VStack(alignment: .leading, spacing: 6) {
                                Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
                                row("Income", earned, Theme.green)
                                row("Spending", spent, Theme.red)
                                row("Kept", net, net >= 0 ? Theme.green : Theme.red, bold: true)
                                Text(earned > 0 ? "\(ReportFormat.percent(net / earned * 100)) kept" : "no income").font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    chart(snapshot: snapshot, income: income, spending: spending, count: count)
                }
            } else {
                ReportCalculating(height: 280)
            }
        }
    }

    private func chart(snapshot: LedgerSnapshot, income: [Double], spending: [Double], count: Int) -> some View {
        let calendar = Calendar.current
        let recent = 1...3
        let averageIncome = recent.reduce(0.0) { $0 + income[max(count - 1 - $1, 0)] } / 3
        let averageSpending = recent.reduce(0.0) { $0 + spending[max(count - 1 - $1, 0)] } / 3
        var bars = snapshot.monthStarts.indices.flatMap { index in
            [Bar(date: snapshot.monthStarts[index], kind: "Income", value: income[index], projected: false),
             Bar(date: snapshot.monthStarts[index], kind: "Spending", value: spending[index], projected: false)]
        }
        if let last = snapshot.monthStarts.last {
            for month in 1...ReportTrends.futureMonths {
                guard let date = calendar.date(byAdding: .month, value: month, to: last) else { continue }
                bars.append(Bar(date: date, kind: "Income", value: averageIncome, projected: true))
                bars.append(Bar(date: date, kind: "Spending", value: averageSpending, projected: true))
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            Chart(bars) { bar in
                BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Amount", bar.value))
                    .foregroundStyle(by: .value("Kind", bar.kind))
                    .position(by: .value("Kind", bar.kind))
                    .opacity(bar.projected ? 0.4 : 1)
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale(["Income": Theme.green, "Spending": Theme.red])
            .chartLegend(.hidden)
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
            .frame(height: 170)
            ReportKey(items: [.init(color: Theme.green, text: "Income"), .init(color: Theme.red, text: "Spending"),
                              .init(color: .secondary, text: "Faded: next 6 months", dashed: true)])
        }
    }

    private func row(_ title: String, _ value: Double, _ color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(ReportFormat.money(value)).fontWeight(bold ? .semibold : .regular).foregroundStyle(color)
        }
        .font(.callout)
    }
}
