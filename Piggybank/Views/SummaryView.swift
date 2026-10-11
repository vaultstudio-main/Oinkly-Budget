import SwiftUI
import SwiftData
import Charts

struct SummaryView: View {
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }
    @Query private var allTransactions: [Transaction]
    private var transactions: [Transaction] { allTransactions.live }

    private static let groupColors: KeyValuePairs<String, Color> = [
        AccountGroup.checkingSavings.title: Theme.green,
        AccountGroup.investments.title: Color(red: 0.66, green: 0.65, blue: 0.95),
        AccountGroup.assets.title: Color(red: 0.97, green: 0.78, blue: 0.61),
        AccountGroup.creditCards.title: Theme.red,
        AccountGroup.loans.title: Color(red: 0.80, green: 0.35, blue: 0.40),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                BillAlertBanner()
                GlanceCards(accounts: accounts, transactions: transactions)
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "Net Worth", fillsHeight: true) { netWorthChart }
                    Panel(title: "Summary", fillsHeight: true) { summaryTable }
                        .frame(width: 280)
                }
                .fixedSize(horizontal: false, vertical: true)
                LoansProgressCard(accounts: accounts)
                GoalsProgressCard()
                Panel(title: "Last 15 Transactions (All Accounts)") { RecentTransactionsPanel(transactions: transactions) }
                Panel(title: "Income / Spending Summary") {
                    HStack(alignment: .top, spacing: 24) {
                        flowChart
                        flowTable.frame(width: 260)
                    }
                }
                Panel(title: "Top Spending Categories (Last 3 Months)") { TopSpendingView(transactions: transactions) }
                Panel(title: "Top Income Categories (Last 3 Months)") { TopSpendingView(transactions: transactions, income: true) }
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack {
            Text("Summary").font(.largeTitle.bold())
            Spacer()
        }
    }

    // MARK: Net worth

    private var netWorthChart: some View {
        Chart(Summary.netWorthSeries(accounts: accounts)) { point in
            BarMark(
                x: .value("Month", point.month, unit: .month),
                y: .value("Value", point.value)
            )
            .foregroundStyle(by: .value("Group", point.group.title))
        }
        .chartForegroundStyleScale(Self.groupColors)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .frame(height: 220)
    }

    private var summaryTable: some View {
        let cash = Summary.total(of: accounts, in: [.checkingSavings])
        let investments = Summary.total(of: accounts, in: [.investments])
        let assets = Summary.total(of: accounts, in: [.assets])
        let cards = Summary.total(of: accounts, in: [.creditCards])
        let loans = Summary.total(of: accounts, in: [.loans])

        return Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Cash", cash)
            row("+ Investments", investments)
            row("+ Assets", assets)
            Divider()
            row("Total Assets", cash + investments + assets, bold: true)
            Color.clear.frame(height: 8)
            row("Credit Cards", cards)
            row("+ Mortgages & Loans", loans)
            Divider()
            row("Total Liabilities", cards + loans, bold: true)
        }
    }

    private func row(_ title: String, _ value: Decimal, bold: Bool = false) -> some View {
        GridRow {
            Text(title).foregroundStyle(bold ? .primary : .secondary).gridColumnAlignment(.trailing)
            Text(value, format: .appCurrency).fontWeight(bold ? .semibold : .regular)
        }
        .font(.callout)
    }

    // MARK: Income / spending

    private var flowChart: some View {
        Chart(Summary.flowSeries(transactions: transactions)) { point in
            BarMark(
                x: .value("Month", point.month, unit: .month),
                y: .value("Amount", point.value)
            )
            .foregroundStyle(by: .value("Kind", point.kind))
        }
        .chartForegroundStyleScale(["Income": Theme.green, "Spending": Theme.red])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .frame(height: 160)
    }

    private var flowTable: some View {
        let year = Summary.lastDays(365, transactions: transactions)
        let month = Summary.lastDays(30, transactions: transactions)

        return Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Last 365 Days").foregroundStyle(.secondary)
                Text("Last 30 Days").foregroundStyle(.secondary)
            }
            GridRow {
                Text("Spending").foregroundStyle(.secondary)
                Text(year.spending, format: .appCurrency)
                Text(month.spending, format: .appCurrency)
            }
            GridRow {
                Text("Income").foregroundStyle(.secondary)
                Text(year.income, format: .appCurrency)
                Text(month.income, format: .appCurrency)
            }
            GridRow {
                Text("Savings Rate").foregroundStyle(.secondary)
                rate(year.savingsRate)
                rate(month.savingsRate)
            }
        }
        .font(.caption)
    }

    private func rate(_ value: Decimal?) -> some View {
        Text(value.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
    }
}
