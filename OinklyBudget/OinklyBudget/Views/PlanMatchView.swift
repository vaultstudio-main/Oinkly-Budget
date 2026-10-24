import SwiftUI
import SwiftData

/// The window the Link Transactions button on the Monthly Outlook opens, for whichever month the page is showing.
struct PlanMatchWindow: View {
    static let id = "plan-match"

    @AppStorage(OutlookSettings.monthKey) private var monthStamp = 0.0

    var body: some View {
        PlanMatchView(month: OutlookSettings.month(from: monthStamp))
            .id(monthStamp)
            .frame(minWidth: 760, minHeight: 520)
            .background(Theme.background)
    }
}

/// Every transaction in the month, from every account, to search and tag to a line of the plan.
/// A tag only remembers which transaction a line turned out to be, so the sheet can show the line as matched. It never changes the
/// transaction, the account or the plan's amounts.
struct PlanMatchView: View {
    let month: Date

    @Query private var transactions: [Transaction]
    @State private var plan = WarPlanData()
    @State private var search = ""
    /// Every account, or one kind of them: checking and savings, credit cards, loans, investments or assets.
    @State private var kind = KindTab.all
    /// One account under the kind, or every account in it.
    @State private var accountKey: String?
    @Query(sort: \Account.name) private var allAccounts: [Account]

    /// A tab for one account, or for every account of the kind. Only the key decides which one it is.
    private struct AccountTab: Hashable, Identifiable {
        let key: String?
        let name: String
        var id: String { key ?? "" }
        static func == (lhs: AccountTab, rhs: AccountTab) -> Bool { lhs.key == rhs.key }
        func hash(into hasher: inout Hasher) { hasher.combine(key) }
    }

    private enum KindTab: Hashable, Identifiable {
        case all
        case group(AccountGroup)
        var id: Self { self }
        func includes(_ transaction: Transaction) -> Bool {
            if case .group(let group) = self { return transaction.account?.type.group == group }
            return true
        }
    }

    init(month: Date) {
        self.month = month
        let start = MonthFilter.start(of: month)
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        _transactions = Query(filter: #Predicate<Transaction> { $0.date >= start && $0.date < end }, sort: \Transaction.date, order: .reverse)
    }

    private static func stamp(_ transaction: Transaction) -> Double { transaction.createdAt.timeIntervalSinceReferenceDate }

    /// The transactions that match the search: by payee, account, memo, category or amount.
    private var shown: [Transaction] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        return transactions.live.filter { !$0.isOpeningDeposit }.filter { kind.includes($0) }.filter { accountKey == nil || $0.account.map(MonthOutlook.accountKey) == accountKey }.filter { transaction in
            guard !words.isEmpty else { return true }
            let text = [transaction.payee, transaction.account?.name ?? "", transaction.memo, transaction.category?.name ?? "",
                        "\(abs(transaction.amount))"].joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    private func line(for transaction: Transaction) -> WarPlanItem? {
        plan.items.first { $0.transactionStamp == Self.stamp(transaction) }
    }

    /// The lines a transaction could be: money in for a deposit, money out for a payment, and not one already matched.
    private func candidates(for transaction: Transaction) -> [WarPlanItem] {
        plan.items.filter { $0.isIncome == (transaction.amount > 0) && $0.transactionStamp == nil }
            .sorted { ($0.date, $0.title) < ($1.date, $1.title) }
    }

    /// The plan line a transaction most likely is, for a one-click link: the same kind and amount, nearest in date within a week, or one
    /// named like its payee. Nil when nothing fits.
    private func suggestion(for transaction: Transaction) -> WarPlanItem? {
        let calendar = Calendar.current
        let payee = transaction.payee.lowercased()
        let scored: [(WarPlanItem, Int)] = candidates(for: transaction).compactMap { item in
            let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: item.date), to: calendar.startOfDay(for: transaction.date)).day ?? 99)
            let sameAmount = item.amount == abs(transaction.amount)
            let name = item.title.lowercased()
            let similar = !payee.isEmpty && (name.contains(payee) || payee.contains(name))
            guard (sameAmount && days <= 7) || similar else { return nil }
            return (item, (sameAmount ? 0 : 20) + (similar ? 0 : 10) + days)
        }
        return scored.min { $0.1 < $1.1 }?.0
    }

    private func attach(_ item: WarPlanItem, to transaction: Transaction) {
        guard let index = plan.items.firstIndex(where: { $0.id == item.id }) else { return }
        plan.items[index].transactionStamp = Self.stamp(transaction)
        plan.save(for: month)
    }

    private func detach(_ item: WarPlanItem) {
        guard let index = plan.items.firstIndex(where: { $0.id == item.id }) else { return }
        plan.items[index].transactionStamp = nil
        plan.save(for: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Match Transactions").font(.headline)
            Text("Search every account for \(month.formatted(.dateTime.month(.wide).year())) and tag a transaction to the plan line it turned out to be. The line shows as matched on the sheet. Nothing in the transaction changes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            FolderTabs(tabs: [KindTab.all] + AccountGroup.setupOrder.map { KindTab.group($0) }, selection: $kind, title: { tab in
                let count = transactions.live.filter { !$0.isOpeningDeposit && tab.includes($0) }.count
                if case .group(let group) = tab { return "\(group.title) (\(count))" }
                return "All Accounts (\(count))"
            }, leading: 0)
            // A second row of tabs, one for each account of the kind, so a payment between two accounts is found on either.
            let accounts = allAccounts.live.filter { account in
                if case .group(let group) = kind { return account.type.group == group }
                return true
            }
            FolderTabs(tabs: [AccountTab(key: nil, name: "Every account")] + accounts.map { AccountTab(key: MonthOutlook.accountKey($0), name: $0.name) },
                       selection: Binding(get: { AccountTab(key: accountKey, name: "") }, set: { accountKey = $0.key }),
                       title: { tab in
                let count = transactions.live.filter { !$0.isOpeningDeposit && kind.includes($0) && (tab.key == nil || $0.account.map(MonthOutlook.accountKey) == tab.key) }.count
                return "\(tab.name) (\(count))"
            }, leading: 0)
            .onChange(of: kind) { _, _ in accountKey = nil }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search payee, account, memo or amount", text: $search).textFieldStyle(.plain)
            }
            .padding(8)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            if plan.items.isEmpty {
                Text("This month's plan has no lines yet. Add some on the War Plan tab, then come back to match them.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }
            List(shown) { transaction in
                row(transaction)
            }
            .listStyle(.plain)
            .overlay { if shown.isEmpty { Text("No transactions found.").foregroundStyle(.secondary) } }
        }
        .padding(20)
        .onAppear { plan = WarPlanData.load(for: month) }
        .onChange(of: month) { _, new in plan = WarPlanData.load(for: new) }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let loaded = WarPlanData.load(for: month)
            if loaded != plan { plan = loaded }
        }
    }

    private func row(_ transaction: Transaction) -> some View {
        let matched = line(for: transaction)
        let options = candidates(for: transaction)
        return HStack(spacing: 10) {
            Text(transaction.date.formatted(.dateTime.month(.abbreviated).day())).frame(width: 52, alignment: .leading).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.payee.isEmpty ? "(no payee)" : transaction.payee).lineLimit(1)
                Text(transaction.account?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(transaction.amount, format: .appCurrency)
                .foregroundStyle(transaction.amount < 0 ? Color.primary : Theme.green)
            if let matched {
                Menu {
                    Button("Take it off “\(matched.title)”", systemImage: "link.badge.minus") { detach(matched) }
                } label: {
                    Label(matched.title, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).lineLimit(1)
                }
                .fixedSize()
            } else {
                if let best = suggestion(for: transaction) {
                    Button {
                        attach(best, to: transaction)
                    } label: {
                        Label("Link to \(best.title)", systemImage: "link.badge.plus").lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("This looks like the plan line “\(best.title)”: the same amount, close to the same date")
                }
                Menu {
                    if options.isEmpty {
                        Text("No open plan lines of this kind")
                    }
                    ForEach(options) { item in
                        Button("\(item.title) · \(item.amount.formatted(.appCurrency))") { attach(item, to: transaction) }
                    }
                } label: {
                    Label("Tag to Plan", systemImage: "link")
                }
                .fixedSize()
                .disabled(plan.items.isEmpty)
            }
        }
        .padding(.vertical, 2)
    }
}
