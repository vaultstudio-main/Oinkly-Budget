import SwiftUI
import SwiftData

/// Edits a category's monthly budget. Everything else about a built-in category is fixed.
struct BudgetEditView: View {
    let category: Category

    @Environment(\.dismiss) private var dismiss
    @State private var limit: Decimal
    @State private var isTaxRelated: Bool

    init(category: Category) {
        self.category = category
        _limit = State(initialValue: category.monthlyLimit)
        _isTaxRelated = State(initialValue: category.isTaxRelated)
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack(spacing: 12) {
                    CategoryBadge(category: category)
                    Text(category.name).font(.headline)
                }
                HStack {
                    Text("Monthly budget")
                    Spacer()
                    CurrencyField("Monthly budget", amount: $limit)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                if !category.isIncome {
                    Toggle("Counts as tax-related", isOn: $isTaxRelated)
                }
                Section {
                    Text("Categories are built in and the same on every device. Only the budget amount and the tax flag can be changed.")
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
                        category.monthlyLimit = max(limit, 0)
                        category.isTaxRelated = isTaxRelated
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
    @State private var isIncome: Bool
    @State private var isTaxRelated: Bool
    @State private var confirmingDelete = false

    init(category: Category?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _limit = State(initialValue: category.map(\.monthlyLimit))
        _isIncome = State(initialValue: category?.isIncome ?? false)
        _isTaxRelated = State(initialValue: category?.isTaxRelated ?? false)
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
                        CurrencyField("Monthly budget", value: $limit)
                        Toggle("Counts as tax-related", isOn: $isTaxRelated)
                    }
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
            category.isTaxRelated = isIncome ? false : isTaxRelated
            category.isIncome = isIncome
            if kindChanged {
                category.colorHex = colorHex
                category.symbol = symbol
            }
        } else {
            let made = Category(name: clean, colorHex: colorHex, symbol: symbol, monthlyLimit: amount, isIncome: isIncome,
                                systemKey: Category.customKeyPrefix + UUID().uuidString)
            made.isTaxRelated = isIncome ? false : isTaxRelated
            modelContext.insert(made)
        }
        modelContext.saveNow()
        dismiss()
    }
}
