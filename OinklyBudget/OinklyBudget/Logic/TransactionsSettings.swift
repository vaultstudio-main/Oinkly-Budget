import Foundation
import SwiftData

/// What the Transactions page is showing, chosen in its Settings window and read by the page: the month and the account.
/// They are kept in preferences, so the window and the page agree as soon as either changes.
enum TransactionsSettings {
    /// The month, as a time since the reference date. Zero means this month.
    static let monthKey = "transactionsMonth"
    /// The account, as `MonthOutlook.accountKey`. Empty means every account.
    static let accountKey = "transactionsAccount"
    static let windowID = "transactions-settings"

    /// Each start of the app begins on this month and every account, whatever was chosen last time.
    static var resetThisLaunch = false

    /// The month a stored stamp means: the first day of it, or this month when nothing was chosen.
    static func month(from stamp: Double, calendar: Calendar = .current) -> Date {
        stamp == 0 ? MonthFilter.start(of: .now, calendar: calendar) : MonthFilter.start(of: Date(timeIntervalSinceReferenceDate: stamp), calendar: calendar)
    }

    /// The months you can step through: from the earliest transaction to the latest, always including this month.
    /// Two one-row lookups, not a pass over every transaction.
    static func range(in context: ModelContext) -> ClosedRange<Date> {
        var oldest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        oldest.fetchLimit = 1
        var newest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        newest.fetchLimit = 1
        let current = MonthFilter.start(of: .now)
        let first = (try? context.fetch(oldest))?.first?.date
        let last = (try? context.fetch(newest))?.first?.date
        let lower = first.map { min(MonthFilter.start(of: $0), current) } ?? current
        let upper = last.map { max(MonthFilter.start(of: $0), current) } ?? current
        return lower...upper
    }
}
