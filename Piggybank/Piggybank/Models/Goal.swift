import Foundation
import SwiftData

/// Something you are saving toward: an emergency fund, a trip, a down payment.
/// A goal either tracks the balance of one of your accounts, or counts the contributions you record on it.
@Model
final class Goal {
    var name: String = ""
    /// "save" to build a balance up, or "payoff" to bring a debt down. Never rename these.
    var kindRaw: String = GoalKind.save.rawValue
    /// For saving goals, the balance to reach. For payoff goals, how much has to be paid down (owed at the start minus `goalBalance`).
    var targetAmount: Decimal = 0
    /// Saving goals: already saved when the goal was made (used when no account is tracked).
    /// Payoff goals: what was owed when the goal was made.
    var startingAmount: Decimal = 0
    /// Payoff goals only: the balance still owed that counts as done. Zero means paid off.
    var goalBalance: Decimal = 0
    var targetDate: Date?
    var symbol: String = "target"
    var colorHex: String = "007AFF"
    /// What kind of saving or debt this is, such as "Emergency Fund" or "Student Loan". See `GoalCategory`.
    var categoryName: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    /// Set automatically when the goal is reached. A goal with a date here is archived: it keeps its final amount
    /// and no longer follows the account or takes new money.
    var completedAt: Date?
    /// The amount the goal ended at, frozen when it was archived.
    var finalAmount: Decimal?

    /// No longer used: goals stand on their own and are not linked to accounts. Kept so existing data still loads.
    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \GoalContribution.goal)
    var contributions: [GoalContribution] = []

    init(name: String, targetAmount: Decimal, startingAmount: Decimal = 0, targetDate: Date? = nil,
         symbol: String = "target", colorHex: String = "007AFF", notes: String = "", account: Account? = nil,
         kind: GoalKind = .save, goalBalance: Decimal = 0, categoryName: String = "") {
        self.name = name
        self.categoryName = categoryName
        self.kindRaw = kind.rawValue
        self.goalBalance = goalBalance
        self.targetAmount = targetAmount
        self.startingAmount = startingAmount
        self.targetDate = targetDate
        self.symbol = symbol
        self.colorHex = colorHex
        self.notes = notes
        self.account = account
    }
}

enum GoalKind: String, CaseIterable, Identifiable {
    case save, payoff

    var id: Self { self }

    var title: String { self == .save ? "Save up" : "Pay off a debt" }
}

/// The choices when making a goal. Saving goals and debt goals each have their own full list.
struct GoalCategory: Identifiable, Hashable {
    let title: String
    let symbol: String
    let colorHex: String
    var id: String { title }

    static let savings: [GoalCategory] = [
        .init(title: "Emergency Fund", symbol: "shield.lefthalf.filled", colorHex: "34C759"),
        .init(title: "Vacation & Travel", symbol: "airplane", colorHex: "FF9500"),
        .init(title: "Home Down Payment", symbol: "house", colorHex: "AF52DE"),
        .init(title: "Car", symbol: "car", colorHex: "007AFF"),
        .init(title: "Wedding", symbol: "heart", colorHex: "FF2D55"),
        .init(title: "Education", symbol: "graduationcap", colorHex: "5AC8FA"),
        .init(title: "Retirement", symbol: "figure.walk", colorHex: "8E8E93"),
        .init(title: "Investing", symbol: "chart.line.uptrend.xyaxis", colorHex: "34C759"),
        .init(title: "Home Improvement", symbol: "hammer", colorHex: "FFCC00"),
        .init(title: "Medical & Health", symbol: "cross.case", colorHex: "FF2D55"),
        .init(title: "New Baby & Family", symbol: "figure.and.child.holdinghands", colorHex: "FF9500"),
        .init(title: "Holidays & Gifts", symbol: "gift", colorHex: "FF2D55"),
        .init(title: "Gadgets & Tech", symbol: "laptopcomputer", colorHex: "5AC8FA"),
        .init(title: "Big Purchase", symbol: "bag", colorHex: "AF52DE"),
        .init(title: "Rainy Day Cushion", symbol: "umbrella", colorHex: "007AFF"),
        .init(title: "Other Savings", symbol: "banknote", colorHex: "34C759"),
    ]

    static let debts: [GoalCategory] = [
        .init(title: "Credit Card", symbol: "creditcard", colorHex: "FF2D55"),
        .init(title: "Store Card", symbol: "bag", colorHex: "FF9500"),
        .init(title: "Auto Loan", symbol: "car", colorHex: "007AFF"),
        .init(title: "Mortgage", symbol: "house", colorHex: "AF52DE"),
        .init(title: "Home Equity / HELOC", symbol: "building.2", colorHex: "AF52DE"),
        .init(title: "Student Loan", symbol: "graduationcap", colorHex: "5AC8FA"),
        .init(title: "Personal Loan", symbol: "person.crop.circle", colorHex: "FF9500"),
        .init(title: "Line of Credit", symbol: "arrow.triangle.2.circlepath", colorHex: "FFCC00"),
        .init(title: "Business Loan", symbol: "briefcase", colorHex: "8E8E93"),
        .init(title: "Medical Debt", symbol: "cross.case", colorHex: "FF2D55"),
        .init(title: "Tax Debt", symbol: "doc.text", colorHex: "8E8E93"),
        .init(title: "Buy Now Pay Later", symbol: "calendar", colorHex: "FF9500"),
        .init(title: "Boat / RV / Motorcycle Loan", symbol: "sailboat", colorHex: "007AFF"),
        .init(title: "Loan from Family or Friend", symbol: "person.2", colorHex: "34C759"),
        .init(title: "Other Debt", symbol: "arrow.down.circle", colorHex: "FF2D55"),
    ]

    static func list(for kind: GoalKind) -> [GoalCategory] { kind == .save ? savings : debts }
}

/// Money put toward (or taken back out of) a goal. Negative for a withdrawal.
@Model
final class GoalContribution {
    var goal: Goal?
    var amount: Decimal = 0
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now

    init(goal: Goal?, amount: Decimal, date: Date = .now, note: String = "") {
        self.goal = goal
        self.amount = amount
        self.date = date
        self.note = note
    }
}
