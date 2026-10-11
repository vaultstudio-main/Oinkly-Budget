import SwiftUI

/// The choices in a category dropdown: None, then Expenses and Income as groups so they are easy to tell apart.
/// Use inside a `Picker` whose selection is a `Category?`.
struct CategoryOptions: View {
    enum Direction { case expense, income }

    let expenses: [Category]
    let income: [Category]
    /// List income first, for a transaction that is money coming in. Only matters when both groups are shown.
    var incomeFirst = false
    /// A category already chosen. It stays in the list even if it doesn't fit, so an existing choice never goes blank.
    var keeping: Category?

    /// Pass `only` to offer just the categories that fit: expenses for money going out, income for money coming in.
    init(categories: [Category], only direction: Direction? = nil, incomeFirst: Bool = false, keeping: Category? = nil) {
        self.init(expenses: categories.filter { !$0.isIncome }, income: categories.filter(\.isIncome),
                  only: direction, incomeFirst: incomeFirst, keeping: keeping)
    }

    /// For a long list that is drawn many times: split once, then pass the two halves.
    init(expenses: [Category], income: [Category], only direction: Direction? = nil, incomeFirst: Bool = false, keeping: Category? = nil) {
        switch direction {
        case .expense: self.expenses = expenses; self.income = []
        case .income: self.expenses = []; self.income = income
        case nil: self.expenses = expenses; self.income = income
        }
        self.incomeFirst = incomeFirst
        self.keeping = keeping
    }

    private var stray: Category? {
        guard let keeping, keeping.isLive else { return nil }
        return (expenses + income).contains(keeping) ? nil : keeping
    }

    var body: some View {
        Text("None").tag(Category?.none)
        if let stray {
            Section("Current") { Text(stray.name).tag(Optional(stray)) }
        }
        if incomeFirst {
            group("Income", income)
            group("Expenses", expenses)
        } else {
            group("Expenses", expenses)
            group("Income", income)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [Category]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { Text($0.name).tag(Optional($0)) }
            }
        }
    }
}
