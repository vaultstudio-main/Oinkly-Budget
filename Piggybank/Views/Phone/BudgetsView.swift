#if os(iOS)
import SwiftUI
import SwiftData

/// Read-only. A pie chart of the month's spending, then every budget. Each month has its own spending;
/// step through months with the selector. Budgets are changed in Settings ▸ Categories & Budgets.
struct BudgetsView: View {
    @Query(sort: \Category.name) private var allCategories: [Category]
    private var categories: [Category] { allCategories.live }
    @Query private var allTransactions: [Transaction]
    private var transactions: [Transaction] { allTransactions.live }

    @State private var month = MonthFilter.start(of: .now)

    /// Categories with spending first (most used on top), then the rest by name.
    private func rows(_ table: SpentTable) -> [Category] {
        Budget.visibleBudgets(categories)
            .sorted {
                let a = Budget.progress(spent: table[$0], limit: $0.monthlyLimit)
                let b = Budget.progress(spent: table[$1], limit: $1.monthlyLimit)
                return a == b ? $0.name < $1.name : a > b
            }
    }

    var body: some View {
        let table = Budget.spentTable(transactions, month: month)
        let rows = rows(table)
        NavigationStack {
            List {
                Section {
                    MonthSelector(month: $month, range: MonthFilter.range(for: transactions))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section("Spending") {
                    MonthSpendingPie(transactions: transactions, month: month)
                        .padding(.vertical, 8)
                }

                Section("Budgets") {
                    if rows.isEmpty {
                        Text("No budgets to show. Set budgets, and choose which appear, in Settings ▸ Categories & Budgets.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { category in
                        BudgetProgressRow(category: category, spent: table[category])
                            .padding(.vertical, 4)
                    }
                }

                Section {
                    Label("To set a budget, or choose which ones show here, go to Settings ▸ Categories & Budgets.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Budgets")
            .menuButton()
        }
    }
}
#endif
