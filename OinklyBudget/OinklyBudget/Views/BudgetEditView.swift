import SwiftUI
import SwiftData

/// Edits a category's monthly budget, and which icon and colour it has. Everything else about a built-in category is fixed.
struct BudgetEditView: View {
    let category: Category

    @Environment(\.dismiss) private var dismiss
    @State private var limit: Decimal
    @State private var isWeekly: Bool
    @State private var isTaxRelated: Bool
    @State private var isCashBudget: Bool
    /// The icon and colour chosen, or nil and 0 for the category's own.
    @State private var iconSymbol: String?
    @State private var iconTheme = 0

    init(category: Category) {
        self.category = category
        let weekly = BudgetPeriods.weeklyAmount(for: category)
        _isWeekly = State(initialValue: weekly != nil)
        _limit = State(initialValue: weekly ?? category.monthlyLimit)
        _isTaxRelated = State(initialValue: category.isTaxRelated)
        _isCashBudget = State(initialValue: CashBudgets.isCash(category))
        let picked = category.modelContext.map { CashBudgets.groups(in: $0) } ?? [:]
        if let context = category.modelContext {
            let key = ItemIcons.key(for: category)
            _iconSymbol = State(initialValue: ItemIcons.symbol(of: key, in: context))
            _iconTheme = State(initialValue: ((try? context.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).live.first { $0.key == key }?.theme ?? 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Budget").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            ArtworkTile(symbol: iconSymbol ?? category.symbol, theme: ArtworkTheme.resolved(iconTheme, seed: ItemIcons.seed(for: category)), color: Color(hex: category.colorHex))
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(category.name).font(.headline)
                        }
                        if !category.isIncome {
                            Picker("Budget is", selection: $isWeekly) {
                                Text("Monthly").tag(false)
                                Text("Weekly").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                        HStack {
                            Text(isWeekly ? "Weekly budget" : "Monthly budget")
                            Spacer()
                            CurrencyField(isWeekly ? "Weekly budget" : "Monthly budget", amount: $limit)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                        }
                        if isWeekly && limit > 0 {
                            Text("The Weekly tab and the Planning War Room work out each month from its real days: \(limit.formatted(.appCurrency)) over 7, times 30 days is \(BudgetPeriods.monthlyMaximum(weekly: limit, inMonthOf: DateComponents(calendar: .current, year: 2026, month: 4, day: 1).date ?? .now).formatted(.appCurrency)). Reports and the Summary use an average month, about \(BudgetPeriods.monthly(fromWeekly: limit).formatted(.appCurrency)).")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if !category.isIncome {
                            Toggle("Counts as tax-related", isOn: $isTaxRelated)
                            Toggle("Counts as a cash budget", isOn: $isCashBudget)
                            Text("A cash budget is paid for in cash, so the Planning War Room leaves it out.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Text("Categories are built in and the same on every device. The budget amount, the tax and cash flags, and the icon and colour can be changed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                Divider()
                Form {
                    Section("Icon") {
                        IconPicker(symbol: $iconSymbol, theme: $iconTheme, category: category,
                                   rainbowSeed: ItemIcons.seed(for: category),
                                   fitting: category.systemKey.flatMap { SymbolChoices.symbols(forCategoryKey: $0) } ?? SymbolChoices.offer(for: category).symbols)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(width: 400)
            }
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save", action: save).keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .background(Theme.background)
        .screenFitted(width: 880, height: 540)
    }

    private func save() {
        category.isTaxRelated = isTaxRelated
        if let context = category.modelContext {
            BudgetPeriods.set(amount: limit, weekly: isWeekly && !category.isIncome, for: category, in: context)
            CashBudgets.set(isCashBudget && !category.isIncome, for: category, in: context)
            ItemIcons.set(iconSymbol, owner: ItemIcons.key(for: category), in: context)
            ArtworkChoices.apply(iconTheme, key: ItemIcons.key(for: category), in: context)
        } else {
            category.monthlyLimit = max(limit, 0)
        }
        dismiss()
    }
}

/// Makes or edits a budget of your own, such as "Civic Fuel". Unlike the built-in ones it can be renamed and deleted.
struct CustomBudgetEditView: View {
    /// Nil when making a new one.
    let category: Category?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var limit: Decimal?
    @State private var isWeekly: Bool
    @State private var isIncome: Bool
    @State private var isTaxRelated: Bool
    @State private var isCashBudget: Bool
    /// Which tab of the budget lists it goes on. Custom means none in particular.
    @State private var group: CategoryGroup
    @State private var confirmingDelete = false
    /// The icon and colour chosen, or nil and 0 for the plain one.
    @State private var iconSymbol: String?
    @State private var iconTheme = 0
    /// The key a new category will be saved under, so its icon can be remembered before it exists.
    private let newKey = Category.customKeyPrefix + UUID().uuidString

    init(category: Category?, group initialGroup: CategoryGroup = .custom) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        let weekly = category.flatMap { BudgetPeriods.weeklyAmount(for: $0) }
        _isWeekly = State(initialValue: weekly != nil)
        _limit = State(initialValue: weekly ?? category.map(\.monthlyLimit))
        _isIncome = State(initialValue: category?.isIncome ?? false)
        _isTaxRelated = State(initialValue: category?.isTaxRelated ?? false)
        _isCashBudget = State(initialValue: category.map { CashBudgets.isCash($0) } ?? false)
        let picked = category.flatMap { found in found.modelContext.map { CashBudgets.groups(in: $0) } } ?? [:]
        let startGroup = category.map { CategoryGroup.of($0, picked: picked) } ?? initialGroup
        _group = State(initialValue: startGroup)
        if let category, let context = category.modelContext {
            let key = ItemIcons.key(for: category)
            _iconSymbol = State(initialValue: ItemIcons.symbol(of: key, in: context))
            _iconTheme = State(initialValue: ((try? context.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).live.first { $0.key == key }?.theme ?? 0)
        }
    }

    private var ownKey: String { category.map { ItemIcons.key(for: $0) } ?? "cat|" + newKey }
    private var plainSymbol: String { isIncome ? "arrow.down.circle" : "tag" }
    private var plainColor: Color { Color(hex: isIncome ? "34C759" : "007AFF") }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(category == nil ? "New Category" : "Edit Category").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section {
                        Picker("Kind", selection: $isIncome) {
                            Text("Expense").tag(false)
                            Text("Income").tag(true)
                        }
                        .pickerStyle(.segmented)
                        FormTextField("Name", text: $name)
                            .onChange(of: name) { _, new in
                                if new.count > Account.maxNameLength { name = String(new.prefix(Account.maxNameLength)) }
                            }
                        if !isIncome {
                            Picker("Budget is", selection: $isWeekly) {
                                Text("Monthly").tag(false)
                                Text("Weekly").tag(true)
                            }
                            .pickerStyle(.segmented)
                            CurrencyField(isWeekly ? "Weekly budget" : "Monthly budget", value: $limit)
                            Picker("Group", selection: $group) {
                                ForEach(CategoryGroup.choosable) { Text($0.title).tag($0) }
                            }
                            Toggle("Counts as tax-related", isOn: $isTaxRelated)
                            Toggle("Counts as a cash budget", isOn: $isCashBudget)
                        }
                    } footer: {
                        Text(isIncome ? "This also adds a new income category you can pick when you record a transaction."
                             : "The group is the tab it is listed on in the budget lists. This also adds a new category with the same name. Pick it as the category when you record a transaction or set up a bill, and what you spend in it counts toward this budget.")
                    }
                    if category != nil {
                        Section {
                            Button("Delete Category", role: .destructive) { confirmingDelete = true }
                        } footer: {
                            Text("Transactions that used it keep their amounts but lose this category.")
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                Divider()
                Form {
                    Section("Icon") {
                        IconPicker(symbol: $iconSymbol, theme: $iconTheme, category: nil, automaticSymbol: plainSymbol,
                                   automaticColor: plainColor,
                                   rainbowSeed: category.map { ItemIcons.seed(for: $0) } ?? ArtworkTheme.seed(name),
                                   fitting: isIncome ? SymbolChoices.offer(for: .income).symbols : SymbolChoices.offer(for: group).symbols)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(width: 400)
            }
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!canSave)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .background(Theme.background)
        .screenFitted(width: 880, height: 600)
        .confirmationDialog("Delete this category?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Category", role: .destructive) {
                if let category { modelContext.delete(category) }
                modelContext.saveNow()
                dismiss()
            }
        }
    }

    private func save() {
        let clean = String(name.trimmingCharacters(in: .whitespaces).prefix(Account.maxNameLength))
        // Income categories have no budget.
        let amount = isIncome ? 0 : max(limit ?? 0, 0)
        let colorHex = isIncome ? "34C759" : "007AFF"
        let symbol = isIncome ? "arrow.down.circle" : "tag"
        if let category {
            let kindChanged = category.isIncome != isIncome
            category.name = clean
            category.monthlyLimit = amount
            BudgetPeriods.set(amount: amount, weekly: isWeekly && !isIncome, for: category, in: modelContext)
            category.isTaxRelated = isIncome ? false : isTaxRelated
            category.isIncome = isIncome
            CashBudgets.set(isCashBudget && !isIncome, for: category, in: modelContext)
            CashBudgets.setGroup(isIncome ? nil : group, for: category, in: modelContext)
            if kindChanged {
                category.colorHex = colorHex
                category.symbol = symbol
            }
        } else {
            let made = Category(name: clean, colorHex: colorHex, symbol: symbol, monthlyLimit: amount, isIncome: isIncome,
                                systemKey: newKey)
            made.isTaxRelated = isIncome ? false : isTaxRelated
            modelContext.insert(made)
            BudgetPeriods.set(amount: amount, weekly: isWeekly && !isIncome, for: made, in: modelContext)
            CashBudgets.set(isCashBudget && !isIncome, for: made, in: modelContext)
            CashBudgets.setGroup(isIncome ? nil : group, for: made, in: modelContext)
        }
        ItemIcons.set(iconSymbol, owner: ownKey, in: modelContext)
        ArtworkChoices.apply(iconTheme, key: ownKey, in: modelContext)
        modelContext.saveNow()
        dismiss()
    }
}
