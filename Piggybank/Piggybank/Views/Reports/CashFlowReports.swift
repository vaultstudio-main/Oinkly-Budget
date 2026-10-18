import SwiftUI
import SwiftData
import Charts

// MARK: Monthly cash flow

struct MonthlyCashFlowReport: View {
    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let months = snapshot.map { ReportMath.monthlyFlow(snapshot: $0) } ?? []
        let past = months.filter { !$0.projected }
        let netYear = past.reduce(0) { $0 + $1.net }

        ReportPanel(title: "Monthly Cash Flow", summary: "Money in, money out and what's left, month by month, with the next six months at your recent average.",
                    headline: past.isEmpty ? nil : ReportFormat.money(netYear), headlineNote: past.isEmpty ? nil : "net over 12 months") {
            if snapshot == nil {
                ReportCalculating(height: 230)
            } else if past.allSatisfy({ $0.income == 0 && $0.spending == 0 }) {
                ReportEmpty(message: "No income or spending yet. Add some transactions to see your cash flow.", height: 230)
            } else {
                Chart {
                    ForEach(months) { month in
                        BarMark(x: .value("Month", month.date, unit: .month), y: .value("Amount", month.income))
                            .foregroundStyle(Theme.green)
                            .position(by: .value("Kind", "Income"))
                            .opacity(month.projected ? 0.4 : 1)
                            .cornerRadius(2)
                        BarMark(x: .value("Month", month.date, unit: .month), y: .value("Amount", month.spending))
                            .foregroundStyle(Theme.red)
                            .position(by: .value("Kind", "Spending"))
                            .opacity(month.projected ? 0.4 : 1)
                            .cornerRadius(2)
                        LineMark(x: .value("Month", month.date, unit: .month), y: .value("Net", month.net), series: .value("Part", "Net"))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 230)
                ReportKey(items: [.init(color: Theme.green, text: "In"), .init(color: Theme.red, text: "Out"),
                                  .init(color: .primary.opacity(0.7), text: "Net"), .init(color: .secondary, text: "Faded: next 6 months", dashed: true)])
            }
        }
    }
}

// MARK: Balances over time

struct AccountBalancesReport: View {
    @Query private var allAccounts: [Account]

    private struct Line: Identifiable {
        let name: String
        let date: Date
        let value: Double
        var id: String { "\(name)-\(date.timeIntervalSince1970)" }
    }

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let accounts = allAccounts.live.filter { $0.type.group == .checkingSavings && !$0.isClosed }
        ReportPanel(title: "Account Balances Over Time", summary: "Every checking, savings and cash balance, month by month.") {
            if let snapshot {
                let lines = accounts.flatMap { account in
                    ReportMath.history(of: account, snapshot: snapshot).map { Line(name: account.name, date: $0.date, value: $0.value) }
                }
                if accounts.isEmpty {
                    ReportEmpty(message: "Add a checking or savings account to see its balance here.", height: 190)
                } else {
                    Chart(lines) { line in
                        LineMark(x: .value("Month", line.date, unit: .month), y: .value("Balance", line.value))
                            .foregroundStyle(by: .value("Account", line.name))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 210)
                }
            } else {
                ReportCalculating(height: 190)
            }
        }
    }
}

// MARK: Forecast

/// Looks up everything the forecast needs. Shared by the forecast chart and the lowest balance tiles.
@MainActor
private func cashForecast(accounts: [Account], bills: [Bill], context: ModelContext, snapshot: LedgerSnapshot) -> ReportMath.Forecast {
    let calendar = Calendar.current
    let since = calendar.date(byAdding: .month, value: -3, to: calendar.dateInterval(of: .month, for: .now)?.start ?? .now) ?? .now
    let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.paidBill != nil && $0.date >= since && $0.amount < 0 })
    let paid = ((try? context.fetch(descriptor)) ?? []).live.reduce(Decimal(0)) { $0 - $1.amount }
    return ReportMath.forecast(accounts: accounts, bills: bills.live, snapshot: snapshot, billPayments: paid)
}

struct CashFlowForecastReport: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAccounts: [Account]
    @Query private var allBills: [Bill]

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let forecast = snapshot.map { cashForecast(accounts: allAccounts.live, bills: allBills, context: modelContext, snapshot: $0) }
        let end = forecast?.weeks.last

        ReportPanel(title: "Cash Flow Forecast", summary: "Your checking and savings, week by week for six months. Bills land on their due dates; income and everyday spending follow the last three months.",
                    headline: end.map { ReportFormat.money($0.balance) }, headlineNote: end == nil ? nil : "in 6 months") {
            if let forecast, forecast.weeks.count > 2 {
                Chart {
                    ForEach(forecast.weeks) { week in
                        AreaMark(x: .value("Week", week.date), y: .value("Balance", week.balance))
                            .foregroundStyle(Color.accentColor.opacity(0.12))
                        LineMark(x: .value("Week", week.date), y: .value("Balance", week.balance))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.red.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    if let low = forecast.lowest {
                        PointMark(x: .value("Week", low.date), y: .value("Balance", low.balance))
                            .foregroundStyle(low.balance < 0 ? Theme.red : Color.orange)
                            .annotation(position: .bottom) { Text("Lowest").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: 220)
                ReportKey(items: [.init(color: .accentColor, text: "Expected balance"), .init(color: Theme.red.opacity(0.6), text: "Zero", dashed: true)])
            } else if snapshot == nil {
                ReportCalculating(height: 220)
            } else {
                ReportEmpty(message: "A forecast needs at least four months of history and a checking or savings account.", height: 220)
            }
        }
    }
}

struct LowestBalanceReport: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAccounts: [Account]
    @Query private var allBills: [Bill]

    var body: some View {
        let snapshot = LedgerIndex.shared.latest
        let forecast = snapshot.map { cashForecast(accounts: allAccounts.live, bills: allBills, context: modelContext, snapshot: $0) }
        ReportPanel(title: "Lowest Balance Ahead", summary: "The tightest point in the next six months, and what's due before then.") {
            if let forecast, let low = forecast.lowest, forecast.weeks.count > 2 {
                let tight = low.balance < 0 ? ("Goes negative", Theme.red) : (low.balance < forecast.weeklyOtherSpending * 2 ? ("Tight", Color.orange) : ("Comfortable", Theme.green))
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ReportFigure(label: "Lowest balance", value: ReportFormat.money(low.balance), note: "week of \(low.date.formatted(.dateTime.month(.abbreviated).day()))", color: tight.1)
                        ReportFigure(label: "Outlook", value: tight.0, color: tight.1)
                    }
                    HStack(spacing: 10) {
                        ReportFigure(label: "Bills, next 30 days", value: ReportFormat.money(forecast.billsNext30))
                        ReportFigure(label: "Income, next 30 days", value: ReportFormat.money(forecast.incomeNext30), color: Theme.green)
                    }
                    HStack(spacing: 10) {
                        ReportFigure(label: "Balance today", value: ReportFormat.money(forecast.startBalance))
                        ReportFigure(label: "Everyday spending / week", value: ReportFormat.money(forecast.weeklyOtherSpending))
                    }
                }
            } else if snapshot == nil {
                ReportCalculating(height: 200)
            } else {
                ReportEmpty(message: "Needs at least four months of history and a checking or savings account.", height: 200)
            }
        }
    }
}

// MARK: Transfers

struct TransfersReport: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAccounts: [Account]

    private var transfers: [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.transferID != nil && $0.amount < 0 },
                                                      sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 40
        return ((try? modelContext.fetch(descriptor)) ?? []).live
    }

    var body: some View {
        // Paying a card or loan is stored as a transfer too, but it is a payment, so those are left out.
        let list = transfers.filter { $0.account?.isDebt == false }.prefix(8)
        ReportPanel(title: "Transfers Between Accounts", summary: "Money you moved between your own accounts, newest first.") {
            if list.isEmpty {
                ReportEmpty(message: "No transfers yet.", height: 170)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("DATE"); Text("FROM"); Text("DESCRIPTION"); Text("AMOUNT").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(4)
                    ForEach(Array(list)) { transfer in
                        GridRow {
                            Text(transfer.date, format: .dateTime.month(.abbreviated).day())
                            Text(transfer.account?.name ?? "").lineLimit(1)
                            Text(transfer.payee).lineLimit(1).foregroundStyle(.secondary)
                            Text(-transfer.amount, format: .appCurrency)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}
