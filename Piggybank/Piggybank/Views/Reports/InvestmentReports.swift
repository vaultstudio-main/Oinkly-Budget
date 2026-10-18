import SwiftUI
import SwiftData
import Charts

private func investmentAccounts(_ accounts: [Account]) -> [Account] {
    accounts.live.filter { $0.type.group == .investments && !$0.isClosed }
}

// MARK: Portfolio value

struct PortfolioValueReport: View {
    @Query private var allAccounts: [Account]

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let projected: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(projected)" }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let accounts = investmentAccounts(allAccounts)
        return ReportPanel(title: "Portfolio Value", summary: "Your investment accounts together over the last year, and six months ahead at your recent pace of growth and contributions.") {
            if accounts.isEmpty {
                ReportEmpty(message: "Add a 401(k), IRA, brokerage or other investment account in Settings ▸ Accounts.", height: 200)
            } else if let snapshot {
                let months = Summary.monthStarts(count: 12)
                let history = months.indices.map { index -> Point in
                    let total = accounts.reduce(0.0) { $0 + ReportMath.history(of: $1, snapshot: snapshot)[index].value }
                    return Point(date: months[index], value: total, projected: false)
                }
                let change = history.count >= 4 ? (history[history.count - 1].value - history[history.count - 4].value) / 3 : 0
                let last = history[history.count - 1]
                let future = (0...ReportTrends.futureMonths).compactMap { month -> Point? in
                    Calendar.current.date(byAdding: .month, value: month, to: last.date).map { Point(date: $0, value: last.value + change * Double(month), projected: true) }
                }
                Chart {
                    ForEach(history) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value), series: .value("Series", "History"))
                            .foregroundStyle(Theme.green).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)).interpolationMethod(.monotone)
                    }
                    ForEach(future) { point in
                        LineMark(x: .value("Month", point.date, unit: .month), y: .value("Value", point.value), series: .value("Series", "Projection"))
                            .foregroundStyle(Theme.green.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 200)
                HStack(spacing: 10) {
                    ReportFigure(label: "Today", value: ReportFormat.money(last.value))
                    ReportFigure(label: "In 6 months", value: ReportFormat.money(future.last?.value ?? last.value), color: change >= 0 ? Theme.green : Theme.red)
                    ReportFigure(label: "Per month", value: ReportFormat.money(change), note: "average of the last 3 months")
                }
            } else {
                ReportCalculating(height: 200)
            }
        }
    }
}

// MARK: Allocation

struct InvestmentAllocationReport: View {
    @Query private var allAccounts: [Account]

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    var body: some View {
        let accounts = investmentAccounts(allAccounts)
        let holdings = accounts.flatMap { $0.holdings.live }.filter { $0.marketValue > 0 }
        // By holding when there are holdings, otherwise by account.
        let slices = holdings.isEmpty
            ? accounts.filter { $0.balance > 0 }.map { Slice(name: $0.name, value: $0.balance.doubleValue) }
            : holdings.map { Slice(name: $0.label, value: $0.marketValue.doubleValue) }
        let sorted = slices.sorted { $0.value > $1.value }
        let total = sorted.reduce(0) { $0 + $1.value }

        return ReportPanel(title: "Allocation", summary: holdings.isEmpty ? "How your investments are split between accounts." : "How your investments are spread across your holdings.",
                           headline: sorted.first.map { "\(Int(($0.value / max(total, 1)) * 100))% \($0.name)" }, headlineNote: sorted.isEmpty ? nil : "largest position") {
            if sorted.isEmpty {
                ReportEmpty(message: "Nothing invested yet. Holdings and balances show here.", height: 190)
            } else {
                HStack(spacing: 18) {
                    Chart(sorted) { slice in
                        SectorMark(angle: .value("Value", slice.value), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(by: .value("Holding", slice.name))
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 140, height: 140)
                    VStack(spacing: 7) {
                        ForEach(sorted.prefix(7)) { slice in
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

// MARK: Gains and losses

struct InvestmentGainsReport: View {
    @Query private var allAccounts: [Account]

    var body: some View {
        let holdings = investmentAccounts(allAccounts).flatMap { $0.holdings.live }.sorted { $0.gain > $1.gain }
        let value = holdings.reduce(Decimal(0)) { $0 + $1.marketValue }
        let cost = holdings.reduce(Decimal(0)) { $0 + $1.costBasis }
        let gain = value - cost

        return ReportPanel(title: "Gains and Losses", summary: "What each holding is worth against what you paid. Not realized until you sell.",
                           headline: holdings.isEmpty ? nil : gain.formatted(.appCurrency), headlineNote: holdings.isEmpty ? nil : (cost > 0 ? "\(ReportFormat.percent((gain / cost).doubleValue * 100, digits: 1)) on cost" : nil)) {
            if holdings.isEmpty {
                ReportEmpty(message: "No holdings yet. Add shares to an investment account to see gains and losses.", height: 170)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow {
                        Text("HOLDING"); Text("VALUE").gridColumnAlignment(.trailing); Text("COST").gridColumnAlignment(.trailing)
                        Text("GAIN").gridColumnAlignment(.trailing); Text("RETURN").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(5)
                    ForEach(holdings.prefix(10)) { holding in
                        GridRow {
                            Text(holding.label).lineLimit(1)
                            Text(holding.marketValue, format: .appCurrency)
                            Text(holding.costBasis, format: .appCurrency).foregroundStyle(.secondary)
                            Text(ReportFormat.signed(holding.gain)).foregroundStyle(holding.gain >= 0 ? Theme.green : Theme.red)
                            Text(holding.gainFraction.map { ReportFormat.percent($0 * 100, digits: 1) } ?? "—")
                                .foregroundStyle(holding.gain >= 0 ? Theme.green : Theme.red)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

// MARK: Contributions

struct InvestmentContributionsReport: View {
    @Query private var allAccounts: [Account]
    /// The last thirteen months. Loaded here so the card also works on the Investments page.
    @Query private var yearTransactions: [Transaction]

    init() {
        let thisMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let start = Calendar.current.date(byAdding: .month, value: -13, to: thisMonth) ?? thisMonth
        _yearTransactions = Query(filter: #Predicate<Transaction> { $0.date >= start })
    }

    private struct Bar: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var body: some View {
        let ids = Set(investmentAccounts(allAccounts).map(\.persistentModelID))
        let months = ReportInputs.months()
        var totals = Array(repeating: 0.0, count: months.count)
        for transaction in yearTransactions.live {
            guard let id = transaction.account?.persistentModelID, ids.contains(id), !Investments.isGrowth(transaction),
                  transaction.date >= months[0], let index = months.lastIndex(where: { $0 <= transaction.date }) else { continue }
            totals[index] += transaction.amount.doubleValue
        }
        let bars = months.indices.map { Bar(date: months[$0], value: totals[$0]) }
        let total = totals.reduce(0, +)

        return ReportPanel(title: "Contributions", summary: "Money you've put in (or taken out), month by month. Growth isn't counted.",
                           headline: ids.isEmpty ? nil : ReportFormat.money(total), headlineNote: ids.isEmpty ? nil : "net over 12 months") {
            if ids.isEmpty {
                ReportEmpty(message: "No investment accounts yet.", height: 170)
            } else if totals.allSatisfy({ $0 == 0 }) {
                ReportEmpty(message: "No contributions in the last 12 months.", height: 170)
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Month", bar.date, unit: .month), y: .value("Contributed", bar.value))
                        .foregroundStyle(bar.value >= 0 ? Theme.green : Theme.red)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 170)
            }
        }
    }
}
