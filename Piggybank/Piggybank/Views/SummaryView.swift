import SwiftUI
import SwiftData
import Charts

struct SummaryView: View {
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }
    /// Only the last few months. Everything longer comes from the ledger snapshot.
    @Query private var allTransactions: [Transaction]
    private var transactions: [Transaction] { allTransactions.live }
    /// The newest few, however old, for the "Last 15 Transactions" panel.
    @Query private var newest: [Transaction]

    init() {
        // Three months covers the spending lists and the month's cards. The yearly charts come from the ledger snapshot.
        let cutoff = Calendar.current.date(byAdding: .month, value: -3, to: Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now) ?? .distantPast
        _allTransactions = Query(filter: #Predicate<Transaction> { $0.date >= cutoff })
        var latest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 60
        _newest = Query(latest)
    }

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
                Panel(title: "Last 15 Transactions (All Accounts)") { RecentTransactionsPanel(transactions: newest) }
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

    private var snapshot: LedgerSnapshot? { LedgerIndex.shared.latest }

    private var calculating: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Calculating…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    @ViewBuilder
    private var netWorthChart: some View {
        if let snapshot {
            netWorthChart(Summary.netWorthSeries(accounts: accounts, snapshot: snapshot))
        } else {
            calculating
        }
    }

    private func netWorthChart(_ series: [Summary.NetWorthPoint]) -> some View {
        Chart(series) { point in
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

    @ViewBuilder
    private var summaryTable: some View {
        if let snapshot { summaryTable(snapshot) } else { calculating }
    }

    private func summaryTable(_ snapshot: LedgerSnapshot) -> some View {
        let cash = Summary.total(of: accounts, in: [.checkingSavings], snapshot: snapshot)
        let investments = Summary.total(of: accounts, in: [.investments], snapshot: snapshot)
        let assets = Summary.total(of: accounts, in: [.assets], snapshot: snapshot)
        let cards = Summary.total(of: accounts, in: [.creditCards], snapshot: snapshot)
        let loans = Summary.total(of: accounts, in: [.loans], snapshot: snapshot)

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

    @ViewBuilder
    private var flowChart: some View {
        if let snapshot {
            flowChart(snapshot.monthStarts.indices.flatMap { index -> [Summary.FlowPoint] in
                [
                    Summary.FlowPoint(month: snapshot.monthStarts[index], kind: "Income", value: snapshot.income[index].doubleValue),
                    Summary.FlowPoint(month: snapshot.monthStarts[index], kind: "Spending", value: -snapshot.spending[index].doubleValue),
                ]
            })
        } else {
            calculating
        }
    }

    private func flowChart(_ series: [Summary.FlowPoint]) -> some View {
        Chart(series) { point in
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

    @ViewBuilder
    private var flowTable: some View {
        if let snapshot { flowTable(year: snapshot.year, month: snapshot.thirtyDays) } else { calculating }
    }

    private func flowTable(year: LedgerSnapshot.Flow, month: LedgerSnapshot.Flow) -> some View {

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
