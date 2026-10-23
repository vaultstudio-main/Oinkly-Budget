import SwiftUI
import SwiftData

/// Every budget, a tab at a time: Housing, Food, Transport and the rest, then Income and the ones you made yourself. Click a
/// category to set its budget, and use the switch to show or hide it on Home, Budgets and the Summary. Shared by the Budget
/// Settings window and the setup page a new user starts on; what goes at the right end of the bottom bar is up to each.
struct BudgetTabsView<Trailing: View>: View {
    /// On the setup page the amount is a box to type in; in the settings window you click a category to set it.
    var inlineAmounts = false
    @ViewBuilder let trailing: Trailing

    @Query(sort: \Category.name) private var allCategories: [Category]
    @Query private var periods: [BudgetPeriod]
    @Query private var marks: [CashBudgetMark]
    @State private var tab = CategoryGroup.housing
    @State private var editing: Category?
    @State private var isAddingCustom = false

    private var categories: [Category] { allCategories.live }

    private func members(of group: CategoryGroup) -> [Category] {
        let picked = CashBudgets.groups(from: marks.live.map(\.key))
        let list = categories.filter { CategoryGroup.of($0, picked: picked) == group }
        // Built-in ones keep their usual order, which is the order of the built-in list.
        let order = Dictionary(uniqueKeysWithValues: Category.definitions.enumerated().map { ($1.key, $0) })
        return list.sorted {
            if $0.isCustom != $1.isCustom { return $0.isCustom }
            return (order[$0.systemKey ?? ""] ?? .max, $0.name) < (order[$1.systemKey ?? ""] ?? .max, $1.name)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FolderTabs(tabs: CategoryGroup.allCases, selection: $tab, title: { "\($0.title) (\(members(of: $0).count))" }, leading: 20)
                .padding(.top, 12)
            let list = members(of: tab)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.title).font(.headline)
                        Text(summary(of: list, in: tab)).font(.caption).foregroundStyle(.secondary)
                    }
                    if list.isEmpty {
                        Text(tab == .custom
                             ? "No budgets of your own yet. Use Add Custom Category below to make one."
                             : "Nothing in this group.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 0) {
                            ForEach(list) { category in
                                row(category)
                                    .padding(.vertical, 8)
                                    .overlay(alignment: .bottom) { Divider() }
                            }
                        }
                    }
                    Text(footnote)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Button { isAddingCustom = true } label: { Label("Add Custom Category", systemImage: "plus.circle.fill") }
                        .help("Make your own, either an expense with a monthly budget or an income category")
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .background(Theme.background)
        .sheet(item: $editing) { category in
            if category.isCustom { CustomBudgetEditView(category: category) } else { BudgetEditView(category: category) }
        }
        .sheet(isPresented: $isAddingCustom) { CustomBudgetEditView(category: nil, group: CategoryGroup.choosable.contains(tab) ? tab : .custom) }
    }

    private var footnote: String {
        if tab == .income {
            return "Income categories don't have budgets. Built-in categories are the same on every device and can't be renamed or deleted. Custom ones can be changed or deleted any time."
        }
        return inlineAmounts
            ? "Type a monthly amount for each category, or leave it blank for no budget."
            : "Click one to set its monthly budget. The switch shows or hides it on Home, Budgets and the Summary. A budget that isn't set never shows there."
    }

    /// "5 categories · $1,200.00 a month", or just the count for income.
    private func summary(of list: [Category], in group: CategoryGroup) -> String {
        let count = "\(list.count) categor\(list.count == 1 ? "y" : "ies")"
        guard group != .income else { return count }
        let budgeted = list.filter { $0.monthlyLimit > 0 }
        let total = budgeted.reduce(Decimal(0)) { $0 + $1.monthlyLimit }
        return budgeted.isEmpty ? "\(count) · no budgets set" : "\(count) · \(total.formatted(.appCurrency)) a month across \(budgeted.count)"
    }

    @ViewBuilder
    private func row(_ category: Category) -> some View {
        if category.isIncome {
            incomeRow(category)
        } else if inlineAmounts {
            HStack(spacing: 12) {
                CategoryBadge(category: category, size: 30)
                Text(category.name).lineLimit(1)
                if category.isCustom { Text("Custom").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                BudgetAmountField(category: category).frame(width: 120)
            }
        } else {
            HStack(spacing: 12) {
                Button { editing = category } label: {
                    HStack(spacing: 12) {
                        CategoryBadge(category: category, size: 30)
                        Text(category.name)
                        if category.isCustom { Text("Custom").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        if category.monthlyLimit > 0 {
                            if let weekly = periods.live.first(where: { $0.key == BudgetPeriods.key(for: category) })?.weeklyAmount {
                                Text("\(weekly.formatted(.appCurrency)) a week").foregroundStyle(.secondary)
                            } else {
                                Text(category.monthlyLimit, format: .appCurrency).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Not set").foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle("Show on budget screens", isOn: Binding(get: { category.showOnBudgets }, set: { category.showOnBudgets = $0 }))
                    .labelsHidden()
                    .help("Show this budget on Home, Budgets and the Summary")
            }
        }
    }

    @ViewBuilder
    private func incomeRow(_ category: Category) -> some View {
        if category.isCustom {
            Button { editing = category } label: {
                HStack(spacing: 12) {
                    CategoryBadge(category: category, size: 30)
                    Text(category.name)
                    Text("Custom").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 12) {
                CategoryBadge(category: category, size: 30)
                Text(category.name)
                Spacer()
            }
        }
    }
}
