import Foundation

/// A short report under the Outlook's comparison: what could be better this month, worked out from the outlook, the War Plan
/// and the safe days. It only reads; nothing here changes anything.
enum OutlookAdvice {
    /// How much it matters, most pressing first.
    enum Level: Int {
        case problem, watch, tip, good
    }

    struct Item: Identifiable {
        let id: String
        let level: Level
        let title: String
        let detail: String
    }

    private static func money(_ value: Decimal) -> String { value.formatted(.appCurrency) }

    private static func names(_ list: [String], limit: Int = 3) -> String {
        let shown = list.prefix(limit).joined(separator: ", ")
        return list.count > limit ? "\(shown) and \(list.count - limit) more" : shown
    }

    static func make(outlook: MonthOutlook, compare: WarPlanComparison?, plannedPull: SafePull?, actualPull: SafePull,
                     buffer: Decimal, startingSet: Bool, calendar: Calendar = .current, limit: Int = 7) -> [Item] {
        var items: [Item] = []
        let hasPlan = compare != nil

        // Things already late.
        let overdue = (outlook.bills + outlook.income + outlook.budgets.flatMap(\.inside)).filter { $0.status == .overdue }
        if !overdue.isEmpty {
            items.append(Item(id: "overdue", level: .problem, title: "\(overdue.count) overdue: \(names(overdue.map(\.title)))",
                              detail: "Tick them off when they are paid, or link the payment, so the outlook counts what really came out."))
        }

        // Budgets past their limits.
        let over = outlook.budgets.filter { $0.over > 0 }
        if !over.isEmpty {
            let total = over.reduce(Decimal(0)) { $0 + $1.over }
            items.append(Item(id: "budgets-over", level: .problem, title: "\(names(over.map(\.category.name))) \(over.count == 1 ? "is" : "are") over by \(money(total))",
                              detail: "Spending plus what is still to come is past the limit. Trim the rest of the month or raise the budget on purpose."))
        }

        // How the month ends.
        if actualPull.ending < 0 {
            items.append(Item(id: "short", level: .problem, title: "The month ends \(money(-actualPull.ending)) short",
                              detail: "More goes out than comes in. Look at the lines over plan in Line by Line, or trim a budget."))
        } else if actualPull.spare < 0 {
            items.append(Item(id: "under-buffer", level: .watch, title: "The month ends \(money(-actualPull.spare)) under your buffer",
                              detail: "You would still be above zero, but into the money you meant to keep."))
        } else if let low = actualPull.lowest, low.balance < buffer {
            items.append(Item(id: "dip", level: .watch,
                              title: "The balance dips to \(money(low.balance)) on \(low.date.formatted(.dateTime.month(.abbreviated).day()))",
                              detail: "That is under your buffer. A bill lands before the money comes in; moving a due date or a paycheque would smooth it."))
        }

        if let compare {
            // Lines over plan, biggest first.
            let overPlan = compare.rows.filter { !$0.isIncome && ($0.difference ?? 0) > 0 }.sorted { ($0.difference ?? 0) > ($1.difference ?? 0) }
            if !overPlan.isEmpty {
                let first = overPlan[0]
                items.append(Item(id: "over-plan", level: .watch,
                                  title: "\(names(overPlan.map(\.title))) \(overPlan.count == 1 ? "is" : "are") over plan",
                                  detail: "\(first.title) is \(money(first.difference ?? 0)) more than you planned. Raise the plan if that is the new normal, or find the difference elsewhere."))
            }
            // Planned money in that is not in the outlook.
            let missing = compare.rows.filter { $0.planned != nil && $0.actual == nil }
            if !missing.isEmpty {
                let income = missing.contains { $0.isIncome }
                items.append(Item(id: "missing", level: .tip, title: "\(names(missing.map(\.title))) \(missing.count == 1 ? "is" : "are") planned but not in the outlook",
                                  detail: income ? "Add the paycheque in Bills & Recurring ▸ Recurring so the outlook counts it. Until then the real figures run low."
                                                 : "If it is a bill, add it in Bills & Recurring. If it is spending, give it a budget so the outlook can see it."))
            }
            // The outlook knows things the plan doesn't.
            let unplanned = compare.rows.filter { $0.planned == nil && ($0.actual ?? 0) > 0 }
            if !unplanned.isEmpty {
                items.append(Item(id: "unplanned", level: .tip, title: "In the outlook but not in your plan: \(names(unplanned.map(\.title)))",
                                  detail: "Use Pull In on the Monthly War Plan tab to add them, so the plan covers the whole month."))
            }
            // Safe day moved.
            if let planned = plannedPull?.best, let actual = actualPull.best {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: planned.date), to: calendar.startOfDay(for: actual.date)).day ?? 0
                if days > 0 {
                    items.append(Item(id: "day-later", level: .watch, title: "The safe day slipped \(days) day\(days == 1 ? "" : "s") later than planned",
                                      detail: "Money is arriving later or going out sooner than the plan. Pull the spare out on \(actual.date.formatted(.dateTime.month(.abbreviated).day())), not earlier."))
                } else if days < 0 {
                    items.append(Item(id: "day-earlier", level: .good, title: "The safe day came \(-days) day\(days == -1 ? "" : "s") earlier than planned",
                                      detail: "You can move the spare money from \(actual.date.formatted(.dateTime.month(.abbreviated).day()))."))
                }
            }
        } else {
            items.append(Item(id: "no-plan", level: .tip, title: "Make a plan for this month",
                              detail: "On the Monthly War Plan tab, Pull In your paycheques, bills and budgets, then change them to what you intend. The cards and charts will then show where you are against it."))
        }

        // Missing basics.
        let incomeMissing = compare?.rows.contains { $0.planned != nil && $0.actual == nil && $0.isIncome } ?? false
        if outlook.income.isEmpty && outlook.otherIncome == 0 && !incomeMissing {
            items.append(Item(id: "no-income", level: .tip, title: "No paycheque is in the outlook",
                              detail: "Add it in Bills & Recurring ▸ Recurring with a positive amount, so Left Over means something."))
        }
        if buffer == 0 {
            items.append(Item(id: "no-buffer", level: .tip, title: "Set a buffer",
                              detail: "In Settings, choose money to keep untouched. The safe day then leaves you a cushion."))
        }
        if !startingSet {
            items.append(Item(id: "no-start", level: .tip, title: "Set what the month starts with",
                              detail: "In Settings, pick an account's balance or type a number, so Above the Buffer is a real figure."))
        }

        items.sort { $0.level.rawValue < $1.level.rawValue }
        if !items.contains(where: { $0.level == .problem || $0.level == .watch }) {
            items.insert(Item(id: "on-track", level: .good, title: "On track",
                              detail: "Nothing is late or over, and the month ends \(money(actualPull.spare)) above your buffer."), at: 0)
        }
        return Array(items.prefix(limit))
    }
}
