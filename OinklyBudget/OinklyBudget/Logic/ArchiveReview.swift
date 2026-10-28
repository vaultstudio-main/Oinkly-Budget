import Foundation
import SwiftData

/// Archived accounts (paid-off loans and ended leases) are kept out of sight but not deleted, because their transactions are part of the
/// history behind net worth, debts and interest. Once a year, at year end, the app asks whether to keep them or flush them out.
@MainActor
enum ArchiveReview {
    private static let reviewedKey = "archiveReviewedYear"

    /// The year being closed out: the new year's first month still counts as the end of the last one, and December counts as the end of this one.
    /// Nil the rest of the year.
    static func reviewYear(now: Date = .now, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard let year = parts.year, let month = parts.month else { return nil }
        if month == 12 { return year }
        if month == 1 { return year - 1 }
        return nil
    }

    /// Whether to ask now: it is year end, there is something archived, and this year's review has not been done yet.
    static func shouldAsk(archivedCount: Int, lastReviewed: Int?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard archivedCount > 0, let year = reviewYear(now: now, calendar: calendar) else { return false }
        return (lastReviewed ?? 0) < year
    }

    static var lastReviewed: Int? {
        let value = UserDefaults.standard.integer(forKey: reviewedKey)
        return value == 0 ? nil : value
    }

    /// Notes that this year's review is done, however it was answered, so it isn't asked again until next year end.
    static func markReviewed(now: Date = .now, calendar: Calendar = .current) {
        UserDefaults.standard.set(reviewYear(now: now, calendar: calendar) ?? calendar.component(.year, from: now), forKey: reviewedKey)
    }

    static func forgetReviewed() { UserDefaults.standard.removeObject(forKey: reviewedKey) }

    /// Every archived account.
    static func archivedAccounts(in context: ModelContext) -> [Account] {
        ((try? context.fetch(FetchDescriptor<Account>())) ?? []).live.filter(\.isClosed)
    }
}
