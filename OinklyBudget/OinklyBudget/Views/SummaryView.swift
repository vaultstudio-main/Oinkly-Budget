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

    var body: some View {
        VStack(spacing: 0) {
        PinnedHeader("Summary")
        ScrollView {
            VStack(spacing: 12) {
                GlanceCards(accounts: accounts, transactions: transactions)
                HStack(alignment: .top, spacing: 12) {
                    PriorityBillsCard(kind: .upcoming)
                    PriorityBillsCard(kind: .overdue)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 12) {
                    TrendChartCard(kind: .netWorth, height: 240)
                    SummaryBalanceCard(accounts: accounts)
                        .frame(width: 340)
                }
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.reportCardMinHeight, 380)
                LoansProgressCard(accounts: accounts)
                GoalsProgressCard()
                ReportPanel(title: "Last 15 Transactions", summary: "The newest across all accounts. A payment or transfer shows once.") { RecentTransactionsPanel(transactions: newest) }
                SummaryFlowCard()
                    .environment(\.reportCardMinHeight, 330)
                ReportPanel(title: "Top Spending Categories", summary: "Where the money went over the last three months.") {
                    TopSpendingView(transactions: transactions)
                }
            }
            .padding(16)
        }
        }
        .background(Theme.background)
    }
}
