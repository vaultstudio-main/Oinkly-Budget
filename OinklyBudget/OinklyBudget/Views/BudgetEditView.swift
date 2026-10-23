import SwiftUI
import SwiftData

/// Edits a category's monthly budget. Everything else about a built-in category is fixed.
struct BudgetEditView: View {
    let category: Category

    @Environment(\.dismiss) private var dismiss
    @State private var limit: Decimal
    @State private var isWeekly: Bool
    @State private var isTaxRelated: Bool
    @State private var isCashBudget: Bool

    init(category: Category) {
        self.category = category
        let weekly = BudgetPeriods.weeklyAmount(for: category)
        _isWeekly = State(initialValue: weekly != nil)
        _limit = State(initialValue: weekly ?? category.monthlyLimit)
        _isTaxRelated = State(initialValue: category.isTaxRelated)
        _isCashBudget = State(initialValue: CashBudgets.isCash(category))
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack(spacing: 12) {
                    CategoryBadge(category: category)
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
                    Text("The Weekly tab and the Monthly War Plan work out each month from its real days: \(limit.formatted(.appCurrency)) over 7, times 30 days is \(BudgetPeriods.monthlyMaximum(weekly: limit, inMonthOf: DateComponents(calendar: .current, year: 2026, month: 4, day: 1).date ?? .now).formatted(.appCurrency)). Reports and the Summary use an average month, about \(BudgetPeriods.monthly(fromWeekly: limit).formatted(.appCurrency)).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !category.isIncome {
                    Toggle("Counts as tax-related", isOn: $isTaxRelated)
                    Toggle("Counts as a cash budget", isOn: $isCashBudget)
                    Text("A cash budget is paid for in cash, so the Monthly War Plan leaves it out.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("Categories are built in and the same on every device. Only the budget amount (monthly or weekly), the tax flag and the cash budget flag can be changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        category.isTaxRelated = isTaxRelated
                        if let context = category.modelContext {
                            BudgetPeriods.set(amount: limit, weekly: isWeekly && !category.isIncome, for: category, in: context)
                            CashBudgets.set(isCashBudget && !category.isIncome, for: category, in: context)
                        } else {
                            category.monthlyLimit = max(limit, 0)
                        }
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 280)
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
    @State private var confirmingDelete = false

    init(category: Category?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        let weekly = category.flatMap { BudgetPeriods.weeklyAmount(for: $0) }
        _isWeekly = State(initialValue: weekly != nil)
        _limit = State(initialValue: weekly ?? category.map(\.monthlyLimit))
        _isIncome = State(initialValue: category?.isIncome ?? false)
        _isTaxRelated = State(initialValue: category?.isTaxRelated ?? false)
        _isCashBudget = State(initialValue: category.map { CashBudgets.isCash($0) } ?? false)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
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
                        Toggle("Counts as tax-related", isOn: $isTaxRelated)
                        Toggle("Counts as a cash budget", isOn: $isCashBudget)
                    }
                } footer: {
                    Text(isIncome ? "This also adds a new income category you can pick when you record a transaction."
                         : "This also adds a new category with the same name. Pick it as the category when you record a transaction or set up a bill, and what you spend in it counts toward this budget.")
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
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .confirmationDialog("Delete this category?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Category", role: .destructive) {
                    if let category { modelContext.delete(category) }
                    modelContext.saveNow()
                    dismiss()
                }
            }
        }
        .macSheetFrame(minHeight: 280)
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
            if kindChanged {
                category.colorHex = colorHex
                category.symbol = symbol
            }
        } else {
            let made = Category(name: clean, colorHex: colorHex, symbol: symbol, monthlyLimit: amount, isIncome: isIncome,
                                systemKey: Category.customKeyPrefix + UUID().uuidString)
            made.isTaxRelated = isIncome ? false : isTaxRelated
            modelContext.insert(made)
            BudgetPeriods.set(amount: amount, weekly: isWeekly && !isIncome, for: made, in: modelContext)
            CashBudgets.set(isCashBudget && !isIncome, for: made, in: modelContext)
        }
        modelContext.saveNow()
        dismiss()
    }
}
