import SwiftUI
import SwiftData

/// Progress on every budget for a month. Budgets are changed in Settings, not here.
struct BudgetsView: View {
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Category.name) private var allCategories: [Category]
    @State private var month = MonthFilter.start(of: .now)

    private var range: ClosedRange<Date> {
        let current = MonthFilter.start(of: .now)
        return (Calendar.current.date(byAdding: .month, value: -24, to: current) ?? current)...current
    }

    private var monthTransactions: [Transaction] {
        let start = month
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.date >= start && $0.date < end })
        return ((try? modelContext.fetch(descriptor)) ?? []).live
    }

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let table = Budget.spentTable(monthTransactions, month: month)
        let budgets = allCategories.live.filter { !$0.isIncome && $0.showOnBudgets && $0.monthlyLimit > 0 }
        let budgeted = budgets.reduce(Decimal(0)) { $0 + $1.monthlyLimit }
        let spent = budgets.reduce(Decimal(0)) { $0 + table[$1] }

        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Budgets").font(.largeTitle.bold())
                    Spacer()
                    MonthSelector(month: $month, range: range)
                    Spacer()
                }

                HStack(spacing: 12) {
                    total("Budgeted", budgeted, note: "\(budgets.count) budget\(budgets.count == 1 ? "" : "s")")
                    total("Spent", spent, note: "this month")
                    total(budgeted - spent < 0 ? "Over" : "Left", abs(budgeted - spent), note: "across all budgets",
                          color: budgeted - spent < 0 ? Theme.red : Theme.green)
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("To change these budgets, go to Settings.")
                    Spacer()
                    Button("Open Categories in Settings") {
                        UserDefaults.standard.set("categories", forKey: MacSettingsView.tabKey)
                        openSettings()
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if budgets.isEmpty {
                    Text("No budgets are set. Add some in Settings ▸ Categories.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                        ForEach(budgets) { category in
                            card(category, spent: table[category])
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    /// A centred total, the same width as its neighbours.
    private func total(_ title: String, _ amount: Decimal, note: String, color: Color = .primary) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(amount, format: .appCurrency)
                .font(.title2.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func card(_ category: Category, spent: Decimal) -> some View {
        let limit = category.monthlyLimit
        let over = spent > limit
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CategoryBadge(category: category, size: 26)
                Text(category.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            ProgressView(value: Budget.progress(spent: spent, limit: limit))
                .tint(over ? Theme.red : (spent >= limit * Decimal(0.85) ? .orange : Theme.green))
            HStack {
                Text(spent, format: .appCurrency).font(.callout.weight(.semibold))
                Text("of \(limit.formatted(.appCurrency))").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(over ? "Over by \((spent - limit).formatted(.appCurrency))" : "\((limit - spent).formatted(.appCurrency)) left")
                    .font(.caption)
                    .foregroundStyle(over ? Theme.red : .secondary)
            }
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}
