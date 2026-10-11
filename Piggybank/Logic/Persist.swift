import SwiftData
import SwiftUI

/// SwiftData writes changes to disk, and refreshes every screen that reads them, on its own schedule.
/// That left a gap of a few seconds where a posted, edited or deleted transaction wasn't reflected everywhere.
/// These make it immediate.
extension ModelContext {
    /// The date of the oldest transaction. One row from the database, not a pass over every transaction.
    func earliestTransactionDate() -> Date? {
        var oldest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        oldest.fetchLimit = 1
        return (try? fetch(oldest))?.first?.date
    }

    /// The oldest transaction among the given accounts, one single-row lookup per account.
    func earliestTransactionDate(in accounts: [Account]) -> Date? {
        accounts.compactMap { account -> Date? in
            guard account.isLive else { return nil }
            let id = account.persistentModelID
            var oldest = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { $0.account?.persistentModelID == id },
                sortBy: [SortDescriptor(\.date)])
            oldest.fetchLimit = 1
            return (try? fetch(oldest))?.first?.date
        }.min()
    }

    /// The first and last transaction dates of one account, two single-row lookups.
    func transactionDateRange(of account: Account) -> (first: Date?, last: Date?) {
        let id = account.persistentModelID
        let match = #Predicate<Transaction> { $0.account?.persistentModelID == id }
        var oldest = FetchDescriptor<Transaction>(predicate: match, sortBy: [SortDescriptor(\.date)])
        oldest.fetchLimit = 1
        var newest = FetchDescriptor<Transaction>(predicate: match, sortBy: [SortDescriptor(\.date, order: .reverse)])
        newest.fetchLimit = 1
        return ((try? fetch(oldest))?.first?.date, (try? fetch(newest))?.first?.date)
    }

    /// How many transactions an account has, counted by the database.
    func transactionCount(of account: Account) -> Int {
        let id = account.persistentModelID
        let match = #Predicate<Transaction> { $0.account?.persistentModelID == id }
        return (try? fetchCount(FetchDescriptor<Transaction>(predicate: match))) ?? 0
    }

    /// Removes every transaction as quickly as possible. Tens of thousands of them make deleting one by one very slow,
    /// so this asks the store to do it in one go and only falls back to deleting in chunks if that is refused.
    func deleteAllTransactions() throws {
        do {
            try delete(model: Transaction.self)
            try save()
        } catch {
            rollback()
            while true {
                var chunk = FetchDescriptor<Transaction>()
                chunk.fetchLimit = 2_000
                let batch = try fetch(chunk)
                if batch.isEmpty { break }
                for transaction in batch { delete(transaction) }
                try save()
            }
        }
    }

    /// Saves right now if anything changed.
    func saveNow() {
        guard hasChanges else { return }
        try? save()
    }
}

/// Saves pending changes within a fraction of a second, even for edits made in place (such as typing in the
/// register), so every window and the "last 15 transactions" always show the latest.
struct AutoSaveModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                modelContext.saveNow()
            }
        }
    }
}

extension View {
    func savesChangesImmediately() -> some View { modifier(AutoSaveModifier()) }
}
