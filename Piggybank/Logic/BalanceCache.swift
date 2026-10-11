import Foundation
import SwiftData

/// A sorted running total of each account's transactions, so a balance at any date is a lookup, not a pass over
/// every transaction. Every save throws the totals away and they are rebuilt on demand.
enum BalanceCache {
    private struct Entry {
        var revision: Int
        var dates: [Date]
        /// cumulative[i] is the sum of the amounts of every transaction up to and including dates[i].
        var cumulative: [Decimal]
    }

    private static var revision = 0
    static var currentRevision: Int { revision }
    private static var entries: [PersistentIdentifier: Entry] = [:]
    private static var isObserving = false

    /// Starts watching for saves. Safe to call more than once.
    static func install() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { invalidate() }
        }
    }

    /// Forget every total. Also called when a whole database is replaced.
    static func invalidate() {
        revision += 1
        if entries.count > 64 { entries.removeAll() }
        LedgerIndex.shared.schedule()
    }

    /// The sum of the account's transactions dated on or before `date`, not counting the opening balance.
    static func total(for account: Account, asOf date: Date) -> Decimal {
        let id = account.persistentModelID
        var entry = entries[id]
        if entry == nil || entry!.revision != revision {
            let sorted = account.transactions
                .filter(\.isLive)
                .map { ($0.date, $0.amount) }
                .sorted { $0.0 < $1.0 }
            var running: Decimal = 0
            var cumulative: [Decimal] = []
            cumulative.reserveCapacity(sorted.count)
            for item in sorted {
                running += item.1
                cumulative.append(running)
            }
            entry = Entry(revision: revision, dates: sorted.map(\.0), cumulative: cumulative)
            entries[id] = entry
        }
        guard let entry else { return 0 }
        // Binary search for the last transaction on or before `date`.
        var low = 0, high = entry.dates.count
        while low < high {
            let mid = (low + high) / 2
            if entry.dates[mid] <= date { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? 0 : entry.cumulative[low - 1]
    }
}
