import SwiftUI
import SwiftData
import Charts

struct SummaryView: View {
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }
    @Query private var allTransactions: [Transaction]
    private var transactions: [Transaction] { allTransactions.live }
    @Query(sort: \Category.name) private var allCategories: [Category]
    private var categories: [Category] { allCategories.live }

    private static let groupColors: KeyValuePairs<String, Color> = [
        AccountGroup.checkingSavings.title: Theme.green,
        AccountGroup.investments.title: Color(red: 0.66, green: 0.65, blue: 0.95),
        AccountGroup.assets.title: Color(red: 0.97, green: 0.78, blue: 0.61),
        AccountGroup.creditCards.title: Theme.red,
        AccountGroup.loans.title: Color(red: 0.80, green: 0.35, blue: 0.40),
    ]

    var body: some View {
        let spentTable = Budget.spentTable(transactions)
        ScrollView {
            VStack(spacing: 12) {
                header
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "Net Worth") { netWorthChart }
                    Panel(title: "Summary") { summaryTable }
                        .frame(width: 280)
                }
                Panel(title: "Last 15 Transactions (All Accounts)") { RecentTransactionsPanel(transactions: transactions) }
                Panel(title: "Income / Spending Summary") {
                    HStack(alignment: .top, spacing: 24) {
                        flowChart
                        flowTable.frame(width: 260)
                    }
                }
                Panel(title: "Top Spending Categories (Last 3 Months)") { TopSpendingView(transactions: transactions) }
                Panel(title: "Category Spending This Month") { categorySpending(spentTable) }
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Summary").font(.largeTitle.bold())
            Spacer()
            Text("CURRENT WORTH").font(.caption).foregroundStyle(.secondary)
            Text(Summary.currentWorth(accounts), format: .appCurrency)
                .font(.system(size: 28, weight: .bold))
        }
    }

    // MARK: Category spending


    /// Budgets that are set and switched on in Settings, most used first.
    private func spendingCategories(_ table: SpentTable) -> [Category] {
        Budget.visibleBudgets(categories)
            .sorted {
                let a = Budget.progress(spent: table[$0], limit: $0.monthlyLimit)
                let b = Budget.progress(spent: table[$1], limit: $1.monthlyLimit)
                return a == b ? $0.name < $1.name : a > b
            }
    }

    private func categorySpending(_ table: SpentTable) -> some View {
        let rows = spendingCategories(table)
        let totalSpent = rows.reduce(Decimal(0)) { $0 + table[$1] }
        let totalBudget = rows.reduce(Decimal(0)) { $0 + $1.monthlyLimit }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(totalSpent, format: .appCurrency).font(.title2.bold())
                Text("of \(totalBudget.formatted(.appCurrency)) budgeted").foregroundStyle(.secondary)
                Spacer()
            }

            if rows.isEmpty {
                Text("No budgets to show. Set budgets, and choose which appear here, in Settings ▸ Categories & Budgets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 32), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                    ForEach(rows) { category in
                        BudgetProgressRow(category: category, spent: table[category])
                    }
                }
                Text("Set budgets, and choose which show here, in Settings ▸ Categories & Budgets.").font(.caption).foregroundStyle(.secondary)
            }
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
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
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
