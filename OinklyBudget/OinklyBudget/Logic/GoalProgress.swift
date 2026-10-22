import Foundation
import SwiftData

/// How far along a goal is, and whether it is on pace for its date.
struct GoalProgress {
    enum Status { case achieved, onTrack, behind, pastDue, noDate }

    let target: Decimal
    let saved: Decimal
    let targetDate: Date?
    /// Average amount put in per month over the last three months. Nil when it can't be known (a linked account).
    let monthlyPace: Decimal?
    let now: Date
    let calendar: Calendar

    var remaining: Decimal { max(target - saved, 0) }
    var isAchieved: Bool { target > 0 && saved >= target }
    var fraction: Double { target > 0 ? min(max((saved / target).doubleValue, 0), 1) : 0 }

    /// Whole months from now to the target date, at least 1 while the date is still ahead. Nil with no date.
    var monthsLeft: Int? {
        guard let targetDate else { return nil }
        let start = calendar.startOfDay(for: now), end = calendar.startOfDay(for: targetDate)
        guard end > start else { return 0 }
        let months = calendar.dateComponents([.month], from: start, to: end).month ?? 0
        return max(months, 1)
    }

    /// What has to go in each month to finish by the date.
    var neededPerMonth: Decimal? {
        guard !isAchieved, let months = monthsLeft, months > 0 else { return nil }
        return remaining / Decimal(months)
    }

    /// When the goal finishes if you keep your recent pace.
    var projectedDate: Date? {
        guard !isAchieved, let pace = monthlyPace, pace > 0 else { return nil }
        let months = Int((remaining / pace).doubleValue.rounded(.up))
        return calendar.date(byAdding: .month, value: months, to: now)
    }

    var status: Status {
        if isAchieved { return .achieved }
        guard let targetDate else { return .noDate }
        if calendar.startOfDay(for: targetDate) <= calendar.startOfDay(for: now) { return .pastDue }
        guard let needed = neededPerMonth, let pace = monthlyPace else { return .onTrack }
        return pace >= needed ? .onTrack : .behind
    }
}

extension Goal {
    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .save }
        set { kindRaw = newValue.rawValue }
    }

    var isPayoff: Bool { kind == .payoff }

    /// Reached and put away. It stays on record but no longer changes.
    var isArchived: Bool { completedAt != nil }

    /// Everything you have put toward the goal so far.
    private var contributed: Decimal { contributions.live.reduce(0) { $0 + $1.amount } }

    /// The account this goal follows, if it is linked to one that still exists and the goal is still open.
    /// A reached goal is frozen, so it stops following.
    var followedAccount: Account? {
        guard completedAt == nil, let account, account.isLive else { return nil }
        return account
    }

    /// True while the goal's progress comes from an account's balance instead of amounts you add by hand.
    var isLinked: Bool { followedAccount != nil }

    /// How much is owed on a debt account right now (its balance is negative while money is owed).
    static func owed(on account: Account) -> Decimal { max(-account.balance, 0) }

    /// Progress so far. A linked goal reads it from the account: a saving goal is the balance above where it started,
    /// a debt goal is how far the balance has come down since the goal was made. Otherwise, for saving, what you
    /// started with plus everything added, and for a debt, what you've paid toward it.
    var saved: Decimal {
        if completedAt != nil, let finalAmount { return finalAmount }
        if let account = followedAccount {
            return isPayoff ? max(startingAmount - Goal.owed(on: account), 0) : max(account.balance - startingAmount, 0)
        }
        return isPayoff ? max(contributed, 0) : startingAmount + contributed
    }

    /// What is still owed on a debt goal, counting down from what it started at.
    var owedNow: Decimal {
        if let account = followedAccount { return Goal.owed(on: account) }
        return max(startingAmount - saved, 0)
    }

    func progress(now: Date = .now, calendar: Calendar = .current) -> GoalProgress {
        var pace: Decimal?
        if let account = followedAccount {
            // A linked goal's pace is how far the account's balance has moved in the last three months.
            let since = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            pace = (account.balance - account.balance(asOf: since)) / 3
        } else if !isArchived {
            let since = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            let recent = contributions.live.filter { $0.date >= since && $0.date <= now }.reduce(Decimal(0)) { $0 + $1.amount }
            pace = recent / 3
        }
        return GoalProgress(target: targetAmount, saved: saved, targetDate: targetDate, monthlyPace: pace, now: now, calendar: calendar)
    }
}

/// Puts goals away once they are reached, so they stop taking in data.
enum GoalArchiver {
    /// Archives every open goal that has reached its target. Returns how many were archived.
    @MainActor
    @discardableResult
    static func archiveReached(in context: ModelContext, now: Date = .now) -> Int {
        guard let goals = try? context.fetch(FetchDescriptor<Goal>()) else { return 0 }
        var count = 0
        for goal in goals.live where goal.completedAt == nil && goal.progress(now: now).isAchieved {
            goal.finalAmount = goal.saved
            goal.completedAt = now
            count += 1
        }
        if count > 0 { context.saveNow() }
        return count
    }
}
