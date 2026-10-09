#if os(iOS)
import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }
    @Query(sort: \Category.name) private var allCategories: [Category]
    private var categories: [Category] { allCategories.live }
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    private var transactions: [Transaction] { allTransactions.live }

    @State private var isAddingTransaction = false

    private var budgets: [Category] { Budget.visibleBudgets(categories) }

    private var monthLimit: Decimal { budgets.reduce(0) { $0 + $1.monthlyLimit } }

    /// The budgets closest to (or past) their limit.
    private func busiestBudgets(_ table: SpentTable) -> [Category] {
        budgets
            .filter { table[$0] > 0 }
            .sorted { Budget.progress(spent: table[$0], limit: $0.monthlyLimit) > Budget.progress(spent: table[$1], limit: $1.monthlyLimit) }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        let table = Budget.spentTable(transactions)
        let monthSpent = budgets.reduce(Decimal(0)) { $0 + table[$1] }
        let busiest = busiestBudgets(table)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if accounts.isEmpty {
                        welcomeCard
                    } else {
                        netWorth
                        monthCard(monthSpent)
                        Card {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Top spending, last 3 months").font(.headline)
                                TopSpendingView(transactions: transactions)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        if !busiest.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Budgets").font(.headline)
                                    ForEach(busiest) { BudgetProgressRow(category: $0, spent: table[$0]) }
                                }
                            }
                        }
                        recentCard
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Transaction", systemImage: "plus") { isAddingTransaction = true }
                        .disabled(accounts.isEmpty)
                }
            }
            .sheet(isPresented: $isAddingTransaction) { PhoneTransactionForm(transaction: nil) }
        }
    }

    private var welcomeCard: some View {
        Card {
            VStack(spacing: 16) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.pink)
                Text("Welcome to Piggybank").font(.title2.bold())
                Text("Add your first account in Settings ▸ Accounts to start tracking your money. Your categories and budgets are already set up.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var netWorth: some View {
        VStack(spacing: 4) {
            Text("Net worth").font(.subheadline).foregroundStyle(.secondary)
            Text(Summary.currentWorth(accounts), format: .appCurrency)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.smooth, value: Summary.currentWorth(accounts))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func monthCard(_ monthSpent: Decimal) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("This month").font(.headline)
                if monthLimit > 0 {
                    Text(monthLimit > monthSpent ? "\(monthLimit - monthSpent, format: .appCurrency) left to spend" : "Over budget by \(monthSpent - monthLimit, format: .appCurrency)")
                        .font(.title2.bold())
                    ProgressView(value: Budget.progress(spent: monthSpent, limit: monthLimit))
                        .tint(monthSpent > monthLimit ? .red : .green)
                        .animation(.smooth, value: monthSpent)
                    Text("\(monthSpent, format: .appCurrency) of \(monthLimit, format: .appCurrency) budgeted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set a monthly budget on a category to track it here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last 15 transactions").font(.headline)
                if transactions.isEmpty {
                    Text("No transactions yet. Tap + to add one.").foregroundStyle(.secondary)
                }
                ForEach(RecentActivity.latest(transactions)) { TransactionRowView(transaction: $0, showAccount: true) }
            }
        }
    }
}
#endif
