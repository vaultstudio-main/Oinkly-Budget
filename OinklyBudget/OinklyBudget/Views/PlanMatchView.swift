import SwiftUI
import SwiftData

/// The War Plan settings' second tab: every transaction in the month, from every account, to search and tag to a line of the plan.
/// A tag only remembers which transaction a line turned out to be, so the sheet can show the line as matched. It never changes the
/// transaction, the account or the plan's amounts.
struct PlanMatchView: View {
    let month: Date

    @Query private var transactions: [Transaction]
    @State private var plan = WarPlanData()
    @State private var search = ""

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
        return transactions.live.filter { !$0.isOpeningDeposit }.filter { transaction in
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
