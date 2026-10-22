import Foundation
import Observation
import SwiftData

/// A compact copy of the money side of the database, built in the background: for every account a date-sorted
/// running total, plus income and spending per month. Balances, the net worth chart and the income/spending chart
/// read from it, so they stay instant however many transactions there are.
nonisolated struct LedgerSnapshot: Sendable {
    /// Income and spending over some stretch, both positive.
    struct Flow: Sendable {
        var income: Decimal = 0
        var spending: Decimal = 0

        var savingsRate: Decimal? { income > 0 ? (income - spending) / income : nil }
    }

    struct Series: Sendable {
        var dates: [Date]
        /// cumulative[i] is the sum of the amounts of every transaction up to and including dates[i].
        var cumulative: [Decimal]
        /// Everything matched to a statement, not counting the opening balance.
        var reconciledSum: Decimal = 0
        var unreconciledCount = 0
        var unreconciledSum: Decimal = 0
        var pendingCount = 0
        var pendingSum: Decimal = 0
    }

    /// Which save this was built after. A snapshot from an older save may be a little behind.
    var revision: Int
    var accounts: [PersistentIdentifier: Series]
    var monthStarts: [Date]
    var income: [Decimal]
    var spending: [Decimal]
    var year: Flow
    var thirtyDays: Flow

    /// The sum of an account's transactions dated on or before `date`, not counting its opening balance.
    func total(for id: PersistentIdentifier, asOf date: Date) -> Decimal {
        guard let series = accounts[id] else { return 0 }
        var low = 0, high = series.dates.count
        while low < high {
            let mid = (low + high) / 2
            if series.dates[mid] <= date { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? 0 : series.cumulative[low - 1]
    }
}

@ModelActor
actor LedgerIndexer {
    func build(revision: Int, now: Date = .now) -> LedgerSnapshot {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let starts = (0..<12).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        let ends = starts.map { calendar.dateInterval(of: .month, for: $0)?.end ?? $0 }
        var income = Array(repeating: Decimal(0), count: starts.count)
        var spending = Array(repeating: Decimal(0), count: starts.count)
        var year = LedgerSnapshot.Flow()
        var thirty = LedgerSnapshot.Flow()
        let yearStart = calendar.date(byAdding: .day, value: -365, to: now) ?? now
        let thirtyStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let upper = now.addingTimeInterval(1)
        let first = starts.first ?? now

        var series: [PersistentIdentifier: LedgerSnapshot.Series] = [:]
        let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        for account in accounts {
            let id = account.persistentModelID
            var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.account?.persistentModelID == id })
            descriptor.propertiesToFetch = [\.date, \.amount, \.transferID, \.status]
            let transactions = (try? modelContext.fetch(descriptor)) ?? []

            var rows: [(Date, Decimal)] = []
            rows.reserveCapacity(transactions.count)
            var reconciledSum: Decimal = 0
            var unreconciledCount = 0, pendingCount = 0
            var unreconciledSum: Decimal = 0, pendingSum: Decimal = 0
            for transaction in transactions {
                let date = transaction.date
                let amount = transaction.amount
                rows.append((date, amount))
                switch transaction.status {
                case .pending: pendingCount += 1; pendingSum += amount
                case .uncleared: unreconciledCount += 1; unreconciledSum += amount
                case .cleared, .reconciled: reconciledSum += amount
                }
                guard transaction.transferID == nil else { continue }
                if date >= yearStart && date < upper {
                    if amount > 0 { year.income += amount } else { year.spending -= amount }
                    if date >= thirtyStart {
                        if amount > 0 { thirty.income += amount } else { thirty.spending -= amount }
                    }
                }
                if date >= first, let index = ends.firstIndex(where: { date < $0 }) {
                    if amount > 0 { income[index] += amount } else { spending[index] -= amount }
                }
            }
            rows.sort { $0.0 < $1.0 }
            var running: Decimal = 0
            var cumulative: [Decimal] = []
            cumulative.reserveCapacity(rows.count)
            for row in rows { running += row.1; cumulative.append(running) }
            series[id] = LedgerSnapshot.Series(
                dates: rows.map(\.0), cumulative: cumulative, reconciledSum: reconciledSum,
                unreconciledCount: unreconciledCount, unreconciledSum: unreconciledSum,
                pendingCount: pendingCount, pendingSum: pendingSum)
        }
        return LedgerSnapshot(revision: revision, accounts: series, monthStarts: starts, income: income,
                              spending: spending, year: year, thirtyDays: thirty)
    }
}

/// Owns the snapshot. Rebuilt in the background shortly after anything is saved.
@Observable
final class LedgerIndex {
    static let shared = LedgerIndex()

    /// The newest snapshot that finished. Can be slightly behind the latest save.
    private(set) var latest: LedgerSnapshot?
    private(set) var isBuilding = false

    /// While true, balances come from the latest snapshot even if a save has happened since. For read-only displays
    /// such as the Summary, where being a moment behind is better than waiting.
    @ObservationIgnored private(set) var preferLatest = false

    /// Runs `work` with balances read from the latest snapshot. Nil, without running it, when there is no snapshot yet.
    func whileStale<T>(_ work: () -> T) -> T? {
        guard latest != nil else { return nil }
        let before = preferLatest
        preferLatest = true
        defer { preferLatest = before }
        return work()
    }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var pending: Task<Void, Never>?

    func start(container: ModelContainer) {
        self.container = container
        schedule(after: 0)
    }

    /// Asks for a rebuild once things have been quiet for a moment, so a burst of saves makes one pass.
    func schedule(after delay: Double = 0.6) {
        guard let container else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.isBuilding = true
            let revision = BalanceCache.currentRevision
            let snapshot = await LedgerIndexer(modelContainer: container).build(revision: revision)
            guard !Task.isCancelled else { return }
            self.latest = snapshot
            self.isBuilding = false
        }
    }

    /// The snapshot, but only when nothing has been saved since it was built.
    var fresh: LedgerSnapshot? {
        guard let latest, latest.revision == BalanceCache.currentRevision else { return nil }
        return latest
    }
}
