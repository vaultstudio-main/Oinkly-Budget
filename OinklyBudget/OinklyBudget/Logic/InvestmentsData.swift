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

/// The seven investment reports all ask for the same numbers, so they are worked out once and reused until something they depend on
/// changes.
@MainActor
enum InvestmentsDataCache {
    static var cached: (key: Int, data: InvestmentsData)?
}

/// Builds `InvestmentsData` from the database and hands it to `content`.
struct WithInvestmentsData<Content: View>: View {
    @Query private var allAccounts: [Account]
    @Query private var yearTransactions: [Transaction]
    @ViewBuilder let content: (InvestmentsData) -> Content

    init(@ViewBuilder content: @escaping (InvestmentsData) -> Content) {
        self.content = content
        let thisMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let start = Calendar.current.date(byAdding: .month, value: -13, to: thisMonth) ?? thisMonth
        _yearTransactions = Query(filter: #Predicate<Transaction> { $0.date >= start })
    }

    private var key: Int {
        var hasher = Hasher()
        for account in allAccounts where account.isLive && account.type.group == .investments {
            hasher.combine(account.persistentModelID)
            hasher.combine(account.balance)
            hasher.combine(account.isClosed)
            for holding in account.holdings.live { hasher.combine(holding.marketValue); hasher.combine(holding.costBasis) }
        }
        hasher.combine(yearTransactions.count)
        hasher.combine(yearTransactions.reduce(Decimal(0)) { $0 + $1.amount })
        hasher.combine(LedgerIndex.shared.latest != nil)
        return hasher.finalize()
    }

    var body: some View {
        let key = key
        let data: InvestmentsData
        if let cached = InvestmentsDataCache.cached, cached.key == key {
            data = cached.data
        } else {
            data = InvestmentsData.make(accounts: allAccounts, transactions: yearTransactions.live, snapshot: LedgerIndex.shared.latest)
            InvestmentsDataCache.cached = (key, data)
        }
        return content(data)
    }
}
