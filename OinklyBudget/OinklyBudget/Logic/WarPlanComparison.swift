import Foundation

/// The War Plan set against the Month Outlook: what was planned for the month, and what the outlook now says.
/// Lines are matched by name. The plan is only read; nothing here changes the outlook, budgets or bills.
struct WarPlanComparison {
    struct Row: Identifiable {
        let id: String
        let title: String
        let isIncome: Bool
        /// Nil for something in the outlook that the plan doesn't have.
        let planned: Decimal?
        /// Nil for a planned line the outlook has nothing like.
        let actual: Decimal?
        /// Positive means more came in or more went out than planned.
        var difference: Decimal? { planned.flatMap { planned in actual.map { $0 - planned } } }
    }

    let rows: [Row]
    let plannedIn: Decimal
    let plannedOut: Decimal
    let actualIn: Decimal
    let actualOut: Decimal

    var plannedExtra: Decimal { plannedIn - plannedOut }
    var actualExtra: Decimal { actualIn - actualOut }

    /// One thing the outlook knows about, which a planned line can be matched to.
    private struct Known {
        let title: String
        let amount: Decimal
        let isIncome: Bool
        /// Titles of lines counted inside this one, so they aren't listed again once it is matched.
        var inside: [String] = []
    }

    private static func normal(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces).lowercased() }

    static func build(items: [MonthWarPlanView.PlanItem], outlook: MonthOutlook) -> WarPlanComparison {
        var known: [Known] = []
        for line in outlook.income { known.append(Known(title: line.title, amount: line.counted, isIncome: true)) }
        if outlook.otherIncome > 0 { known.append(Known(title: "Other income so far", amount: outlook.otherIncome, isIncome: true)) }
        for line in outlook.bills { known.append(Known(title: line.title, amount: line.counted, isIncome: false)) }
        for budget in outlook.budgets {
            let name = budget.category.name
            known.append(Known(title: name + " budget", amount: budget.counted, isIncome: false, inside: budget.inside.map(\.title)))
            for line in budget.inside { known.append(Known(title: line.title, amount: line.counted, isIncome: false)) }
        }
        if outlook.otherSpending > 0 { known.append(Known(title: "Everything else", amount: outlook.otherSpending, isIncome: false)) }

        var used = Set<Int>()
        var rows: [Row] = []
        for item in items.sorted(by: { $0.date < $1.date }) {
            let wanted = normal(item.title)
            let index = known.indices.first { i in
                !used.contains(i) && known[i].isIncome == item.isIncome
                    && (normal(known[i].title) == wanted || normal(known[i].title) == wanted + " budget")
            }
            if let index {
                used.insert(index)
                for inner in known[index].inside {
                    if let hidden = known.indices.first(where: { !used.contains($0) && normal(known[$0].title) == normal(inner) && !known[$0].isIncome }) { used.insert(hidden) }
                }
            }
            rows.append(Row(id: item.id.uuidString, title: item.title, isIncome: item.isIncome, planned: item.amount, actual: index.map { known[$0].amount }))
        }
        for (i, entry) in known.enumerated() where !used.contains(i) && entry.amount > 0 {
            rows.append(Row(id: "outlook-\(i)", title: entry.title, isIncome: entry.isIncome, planned: nil, actual: entry.amount))
        }
        return WarPlanComparison(
            rows: rows,
            plannedIn: items.filter(\.isIncome).reduce(0) { $0 + $1.amount },
            plannedOut: items.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount },
            actualIn: outlook.incomeTotal, actualOut: outlook.outTotal)
    }
}
