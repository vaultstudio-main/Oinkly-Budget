import SwiftUI

/// Edits a category's monthly budget. Everything else about a built-in category is fixed.
struct BudgetEditView: View {
    let category: Category

    @Environment(\.dismiss) private var dismiss
    @State private var limit: Decimal

    init(category: Category) {
        self.category = category
        _limit = State(initialValue: category.monthlyLimit)
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
                    TextField("Monthly budget", value: $limit, format: .appCurrency)
                        .multilineTextAlignment(.trailing)
                }
                Section {
                    Text("Categories are built in and the same on every device. Only the budget amount can be changed.")
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
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 280)
        #endif
    }
}
