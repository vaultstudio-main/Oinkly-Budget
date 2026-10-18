import Foundation
import SwiftData
import SwiftUI

/// Everything the investment reports draw, in one place: real numbers from your investment accounts, or a made-up
/// portfolio when you have none yet, so the page shows what it will look like.
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

    var isSample = false
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
        guard !accounts.isEmpty else { return sample() }

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
            let history = months.indices.map { index -> TrendPoint in
                let total = accounts.reduce(0.0) { $0 + ReportMath.history(of: $1, snapshot: snapshot)[index].value }
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

    // MARK: Sample

    /// A made-up portfolio, shown until you add an investment account.
    static func sample(now: Date = .now) -> InvestmentsData {
        var data = InvestmentsData()
        data.isSample = true
        data.accounts = [
            AccountRow(id: "s1", name: "Workplace 401(k)", typeTitle: "401(k)", symbol: "building.2", bucket: "Retirement", value: 84_200, growth: 9_120),
            AccountRow(id: "s2", name: "Roth IRA", typeTitle: "Roth IRA", symbol: "leaf", bucket: "Retirement", value: 31_450, growth: 3_310),
            AccountRow(id: "s3", name: "Brokerage", typeTitle: "Brokerage", symbol: "chart.line.uptrend.xyaxis", bucket: "Brokerage", value: 22_870, growth: 2_740),
            AccountRow(id: "s4", name: "College 529", typeTitle: "529 Plan", symbol: "graduationcap", bucket: "Education", value: 14_300, growth: 1_160),
            AccountRow(id: "s5", name: "Crypto", typeTitle: "Crypto", symbol: "bitcoinsign.circle", bucket: "Crypto", value: 3_180, growth: -420),
        ]
        data.holdings = [
            HoldingRow(id: "h1", label: "VTSAX", name: "Total Stock Market", accountName: "Workplace 401(k)", value: 68_400, cost: 52_000),
            HoldingRow(id: "h2", label: "VXUS", name: "International Stock", accountName: "Roth IRA", value: 27_900, cost: 25_100),
            HoldingRow(id: "h3", label: "BND", name: "Total Bond Market", accountName: "Workplace 401(k)", value: 19_300, cost: 20_400),
            HoldingRow(id: "h4", label: "AAPL", name: "Apple", accountName: "Brokerage", value: 12_200, cost: 7_800),
            HoldingRow(id: "h5", label: "NVDA", name: "NVIDIA", accountName: "Brokerage", value: 9_600, cost: 4_100),
            HoldingRow(id: "h6", label: "QQQ", name: "Nasdaq 100", accountName: "College 529", value: 8_950, cost: 7_000),
            HoldingRow(id: "h7", label: "BTC", name: "Bitcoin", accountName: "Crypto", value: 3_180, cost: 3_600),
        ]
        let calendar = Calendar.current
        let months = Summary.monthStarts(count: 12, now: now, calendar: calendar)
        let wobble: [Double] = [0, 0.012, -0.008, 0.018, 0.004, -0.014, 0.02, 0.006, -0.01, 0.016, 0.002, 0]
        let history = months.indices.map { index -> TrendPoint in
            let base = 156_000 * (0.82 + 0.18 * Double(index) / 11)
            return TrendPoint(date: months[index], value: index == 11 ? 156_000 : base * (1 + wobble[index]), projected: false)
        }
        data.history = history + projection(of: history)
        let flows: [Double] = [1_500, 1_500, 1_800, 1_500, 1_500, 2_200, 1_500, 1_500, 1_500, 1_900, 1_500, 1_500]
        data.contributions = months.indices.map { Month(date: months[$0], value: flows[$0]) }
        return data
    }
}

/// Builds `InvestmentsData` from the database (or the sample) and hands it to `content`.
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

    var body: some View {
        content(InvestmentsData.make(accounts: allAccounts, transactions: yearTransactions.live, snapshot: LedgerIndex.shared.latest))
    }
}
