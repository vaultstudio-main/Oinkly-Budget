import Foundation

/// One line of the War Plan. Money out and money in are both stored as a positive amount.
struct WarPlanItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var amount: Decimal
    var isIncome: Bool
    /// Where the line came from, for its icon: "bill", "budget", "income" or nil for one typed in.
    var origin: String?

    var symbol: String {
        switch origin {
        case "bill": "calendar"
        case "budget": "chart.pie"
        case "income": "banknote"
        default: isIncome ? "arrow.down.circle" : "arrow.up.circle"
        }
    }
}

/// Everything about one month's War Plan: its lines, what it starts with and the buffer to keep.
/// It is a what-if sheet. It is kept on this Mac, in preferences, a month at a time, and nothing else in the app writes to it
/// or changes because of it.
struct WarPlanData: Codable, Equatable {
    /// A typed starting amount, used when no account is chosen.
    var start: Decimal?
    /// An account whose balance is the starting amount, as `MonthOutlook.accountKey`.
    var startAccount: String?
    /// Money to keep out of reach: only what is above it counts as spare.
    var buffer: Decimal?
    var items: [WarPlanItem] = []

    var isEmpty: Bool { items.isEmpty && (start ?? 0) == 0 && startAccount == nil && (buffer ?? 0) == 0 }
    var kept: Decimal { buffer ?? 0 }

    /// What the month starts with: the chosen account's balance now, otherwise the typed amount.
    func opening(accounts: [Account], now: Date = .now) -> Decimal {
        if let key = startAccount, let account = accounts.first(where: { MonthOutlook.accountKey($0) == key }) { return account.balance(asOf: now) }
        return start ?? 0
    }

    static func key(for month: Date) -> String { "warPlan." + OutlookSnapshots.key(for: month) }

    static func load(for month: Date, defaults: UserDefaults = .standard) -> WarPlanData {
        guard let data = defaults.data(forKey: key(for: month)), let plan = try? JSONDecoder().decode(WarPlanData.self, from: data) else { return WarPlanData() }
        return plan
    }

    func save(for month: Date, defaults: UserDefaults = .standard) {
        if isEmpty {
            defaults.removeObject(forKey: Self.key(for: month))
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key(for: month))
        }
    }
}
