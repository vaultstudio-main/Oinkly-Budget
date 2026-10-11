import SwiftData
import SwiftUI

/// SwiftData writes changes to disk, and refreshes every screen that reads them, on its own schedule.
/// That left a gap of a few seconds where a posted, edited or deleted transaction wasn't reflected everywhere.
/// These make it immediate.
extension ModelContext {
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
