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

    /// The group a category belongs to. Ones you made yourself are Custom, except income ones, which stay with Income.
    static func of(_ category: Category) -> CategoryGroup {
        if category.isCustom { return category.isIncome ? .income : .custom }
        return category.systemKey.flatMap { byKey[$0] } ?? (category.isIncome ? .income : .financial)
    }
}
