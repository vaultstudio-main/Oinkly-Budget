import Foundation

/// The groups the built-in categories sort into, so a long list of budgets can be read a tab at a time: Housing, Food, Transport and
/// so on, then Income, and Custom for the ones you made yourself. A built-in category's group is where it sits in the built-in list.
enum CategoryGroup: String, CaseIterable, Identifiable {
    case housing, food, transport, insurance, health, personal, fun, family, giving, financial, income, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .housing: "Housing"
        case .food: "Food"
        case .transport: "Transport"
        case .insurance: "Insurance"
        case .health: "Health"
        case .personal: "Personal"
        case .fun: "Fun & Travel"
        case .family: "Family & Pets"
        case .giving: "Giving"
        case .financial: "Financial"
        case .income: "Income"
        case .custom: "Custom"
        }
    }

    /// Each group starts at its first category in the built-in list, and runs until the next group's first.
    private static let starts: [(key: String, group: CategoryGroup)] = [
        ("housing", .housing), ("groceries", .food), ("gas-fuel", .transport), ("insurance", .insurance), ("healthcare", .health),
        ("personal-care", .personal), ("entertainment", .fun), ("kids-family", .family), ("gifts-donations", .giving),
        ("fees-charges", .financial),
    ]

    /// Every built-in category's group, by its key.
    private static let byKey: [String: CategoryGroup] = {
        var result: [String: CategoryGroup] = [:]
        var current = CategoryGroup.housing
        for definition in Category.definitions {
            if definition.isIncome {
                current = .income
            } else if let start = starts.first(where: { $0.key == definition.key }) {
                current = start.group
            }
            result[definition.key] = current
        }
        return result
    }()

    /// The groups a budget of your own can be put in: every spending group, or Custom for none in particular.
    static var choosable: [CategoryGroup] { allCases.filter { $0 != .income } }

    /// The group a category belongs to. One you made yourself is in the group you picked for it, or Custom when you picked none,
    /// and an income one stays with Income. `picked` is what you chose, by category key (see `CashBudgets.groups`).
    static func of(_ category: Category, picked: [String: CategoryGroup] = [:]) -> CategoryGroup {
        if category.isCustom {
            if category.isIncome { return .income }
            return category.systemKey.flatMap { picked[$0] } ?? .custom
        }
        return category.systemKey.flatMap { byKey[$0] } ?? (category.isIncome ? .income : .financial)
    }
}
