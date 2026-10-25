import Foundation
import SwiftData
import SwiftUI

/// Everything the investment reports draw, in one place. Empty when you have no investment account yet.
struct InvestmentsData {
    struct AccountRow: Identifiable {
        let id: String
        let name: String
        let typeTitle: String
        let symbol: String
        /// A group for the "Where it is" chart: Retirement, Brokerage, Education or Crypto.
        let bucket: String
        let value: Double
        /// Growth recorded over the last twelve months.
        let growth: Double
        var growthRate: Double? { value - growth > 0 ? growth / (value - growth) : nil }
    }

    struct HoldingRow: Identifiable {
        let id: String
        let label: String
        let name: String
        let accountName: String
        let value: Double
        let cost: Double
        var gain: Double { value - cost }
        var gainRate: Double? { cost > 0 ? gain / cost : nil }
    }

    struct Month: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var accounts: [AccountRow] = []
    var holdings: [HoldingRow] = []
    /// Twelve months of total value, then six projected.
    var history: [TrendPoint] = []
    /// Money put in (negative for taken out), month by month for the last twelve months.
    var contributions: [Month] = []

    var totalValue: Double { accounts.reduce(0) { $0 + $1.value } }
    var growth12: Double { accounts.reduce(0) { $0 + $1.growth } }
    var contributed12: Double { contributions.reduce(0) { $0 + $1.value } }
    var unrealizedGain: Double { holdings.reduce(0) { $0 + $1.gain } }
    var costBasis: Double { holdings.reduce(0) { $0 + $1.cost } }
    var buckets: [(name: String, value: Double)] {
        Dictionary(grouping: accounts, by: \.bucket).map { ($0.key, $0.value.reduce(0) { $0 + $1.value }) }.sorted { $0.1 > $1.1 }
    }

    // MARK: Real

    static func bucket(for type: AccountType) -> String {
        switch type {
        case .retirement401k, .traditionalIRA, .rothIRA, .pension, .annuity: "Retirement"
        case .education529: "Education"
        case .crypto: "Crypto"
        default: "Brokerage"
        }
    }

    static func make(accounts all: [Account], transactions: [Transaction], snapshot: LedgerSnapshot?) -> InvestmentsData {
        let accounts = all.live.filter { $0.type.group == .investments && !$0.isClosed }
        guard !accounts.isEmpty else { return InvestmentsData() }

        let months = Summary.monthStarts(count: 12)
        var growth: [PersistentIdentifier: Double] = [:]
        var flow = Array(repeating: 0.0, count: months.count)
        let ids = Set(accounts.map(\.persistentModelID))
        for transaction in transactions {
            guard let id = transaction.account?.persistentModelID, ids.contains(id), transaction.date >= months[0] else { continue }
            if Investments.isGrowth(transaction) {
                growth[id, default: 0] += transaction.amount.doubleValue
            } else if let index = months.lastIndex(where: { $0 <= transaction.date }) {
                flow[index] += transaction.amount.doubleValue
            }
        }

        var data = InvestmentsData()
        data.accounts = accounts.map { account in
            AccountRow(id: "\(account.persistentModelID.hashValue)", name: account.name, typeTitle: account.type.title, symbol: account.type.symbol,
                       bucket: bucket(for: account.type), value: max(account.balance.doubleValue, 0), growth: growth[account.persistentModelID] ?? 0)
        }.sorted { $0.value > $1.value }
        data.holdings = accounts.flatMap { account in
            account.holdings.live.map { HoldingRow(id: "\($0.persistentModelID.hashValue)", label: $0.label, name: $0.name, accountName: account.name,
                                                   value: $0.marketValue.doubleValue, cost: $0.costBasis.doubleValue) }
        }.sorted { $0.value > $1.value }
        data.contributions = months.indices.map { Month(date: months[$0], value: flow[$0]) }

        if let snapshot {
            // Each account's history is worked out once, not again for every month.
            let histories = accounts.map { ReportMath.history(of: $0, snapshot: snapshot) }
            let history = months.indices.map { index -> TrendPoint in
                let total = histories.reduce(0.0) { $0 + $1[index].value }
                return TrendPoint(date: months[index], value: total, projected: false)
            }
            data.history = history + projection(of: history)
        }
        return data
    }

    /// Six months after the last point, continuing at the average monthly change of the last three months.
    private static func projection(of history: [TrendPoint]) -> [TrendPoint] {
        guard history.count >= 4, let last = history.last else { return [] }
        let change = (last.value - history[history.count - 4].value) / 3
        return ReportMath.future(from: last) { last.value + change * Double($0) }
    }
}

/// The seven investment reports all ask for the same numbers, so they are worked out once and kept. Whether they are still good is told by
/// the data's revision, which goes up on every save (a changed price, a new transaction), so nothing has to be read from the database
/// just to check. They are also worked out shortly after the app starts and after a save, so opening the reports finds them ready.
@MainActor
enum InvestmentsDataCache {
    static var cached: (key: Int, data: InvestmentsData)?
    /// Set once the investment reports have been opened, which is when keeping them warm after saves starts to be worth it.
    private static var opened = false
    private static var warming: Task<Void, Never>?
    private static var isObserving = false

    private static var key: Int {
        var hasher = Hasher()
        hasher.combine(BalanceCache.currentRevision)
        hasher.combine(LedgerIndex.shared.latest?.revision)
        return hasher.finalize()
    }

    /// The numbers for the current data: the kept ones when nothing has changed since, otherwise worked out again, from the last thirteen months of
    /// transactions, and kept.
    static func data(in context: ModelContext) -> InvestmentsData {
        let key = key
        if let cached, cached.key == key { return cached.data }
        let thisMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let start = Calendar.current.date(byAdding: .month, value: -13, to: thisMonth) ?? thisMonth
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        // Without an investment account there is nothing to total, so the transactions are not even read.
        let hasInvestments = accounts.live.contains { $0.type.group == .investments && !$0.isClosed }
        let transactions = hasInvestments ? ((try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.date >= start }))) ?? []) : []
        let data = InvestmentsData.make(accounts: accounts, transactions: transactions.live, snapshot: LedgerIndex.shared.latest)
        cached = (key, data)
        return data
    }

    /// Works the numbers out now if they are out of date, a few seconds after launch and again, once the reports have been opened, shortly
    /// after each save. The start-up snapshot of the ledger is waited for so the history is complete.
    static func install(container: ModelContainer) {
        guard !isObserving else { return }
        isObserving = true
        warm(container, after: 5)
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if opened { warm(container, after: 2) } }
        }
    }

    static func noteOpened() { opened = true }

    private static func warm(_ container: ModelContainer, after seconds: Double) {
        warming?.cancel()
        warming = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            // The ledger snapshot is built in the background after each save; wait a little for it so the kept numbers include it.
            for _ in 0..<10 where LedgerIndex.shared.latest == nil || LedgerIndex.shared.isBuilding {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled else { return }
            _ = data(in: container.mainContext)
        }
    }
}

/// Builds `InvestmentsData` from the database and hands it to `content`.
struct WithInvestmentsData<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @ViewBuilder let content: (InvestmentsData) -> Content

    init(@ViewBuilder content: @escaping (InvestmentsData) -> Content) {
        self.content = content
    }

    var body: some View {
        // Reading the ledger's snapshot makes this redraw when a newer one arrives.
        _ = LedgerIndex.shared.latest
        InvestmentsDataCache.noteOpened()
        return content(InvestmentsDataCache.data(in: modelContext))
    }
}
