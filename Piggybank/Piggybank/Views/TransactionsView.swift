import SwiftUI
import SwiftData

/// Every account's transactions together, a month at a time, so you can look at them as a whole.
/// Searching looks through every month. The Mac shows a table.
///
/// Only the transactions being shown are loaded: the database is asked for one month (or the search matches) at a
/// time, so the page stays quick however many transactions there are.
struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var month = MonthFilter.start(of: .now)
    @State private var accountID: Account.ID?
    @State private var search = ""

    /// The months you can step through: from the earliest transaction to the latest, always including this month.
    /// Two one-row lookups, not a pass over every transaction.
    private var range: ClosedRange<Date> {
        var oldest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        oldest.fetchLimit = 1
        var newest = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        newest.fetchLimit = 1
        let current = MonthFilter.start(of: .now)
        let first = (try? modelContext.fetch(oldest))?.first?.date
        let last = (try? modelContext.fetch(newest))?.first?.date
        let lower = first.map { min(MonthFilter.start(of: $0), current) } ?? current
        let upper = last.map { max(MonthFilter.start(of: $0), current) } ?? current
        return lower...upper
    }

    private var accountPicker: some View {
        Picker("Account", selection: $accountID) {
            Text("All Accounts").tag(Account.ID?.none)
            ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var heading: String { search.isEmpty ? "" : "Results for “\(search)”" }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transactions").font(.largeTitle.bold())
                Spacer()
                if search.isEmpty {
                    MonthSelector(month: $month, range: range, showsThisMonthButton: false)
                    Spacer()
                } else {
                    Text(heading).font(.headline).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack {
                searchField
                Spacer()
                if search.isEmpty { ThisMonthButton(month: $month) }
                accountPicker
            }
            TransactionsTable(month: month, accountID: accountID, search: search)
        }
        .padding(16)
        .background(Theme.background)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            if let action = note.userInfo?["action"] as? String, action.hasPrefix("search:") { search = String(action.dropFirst("search:".count)) }
        }
        #endif
    }

    /// A small search box under the title. It lives in the page, not the window toolbar, so the window chrome never moves.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search all transactions", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 240)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The table and totals for one month, or for a search. Its query is built from what is being looked at, so the
/// database does the filtering.
private struct TransactionsTable: View {
    @Query private var rows: [Transaction]
    @Environment(\.openWindow) private var openWindow
    private let isSearching: Bool
    private let periodLabel: String

    init(month: Date, accountID: Account.ID?, search: String) {
        let text = search.trimmingCharacters(in: .whitespaces)
        isSearching = !text.isEmpty
        periodLabel = text.isEmpty ? month.formatted(.dateTime.month(.wide).year()) : "Search results"
        let start = month
        let end = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
        let predicate: Predicate<Transaction>
        switch (text.isEmpty, accountID) {
        case (true, nil):
            predicate = #Predicate<Transaction> { $0.date >= start && $0.date < end }
        case (true, let id?):
            predicate = #Predicate<Transaction> { $0.date >= start && $0.date < end && $0.account?.persistentModelID == id }
        case (false, nil):
            predicate = #Predicate<Transaction> {
                $0.payee.localizedStandardContains(text) || $0.memo.localizedStandardContains(text)
                    || ($0.category?.name.localizedStandardContains(text) ?? false)
                    || ($0.account?.name.localizedStandardContains(text) ?? false)
            }
        case (false, let id?):
            predicate = #Predicate<Transaction> {
                $0.account?.persistentModelID == id
                    && ($0.payee.localizedStandardContains(text) || $0.memo.localizedStandardContains(text)
                        || ($0.category?.name.localizedStandardContains(text) ?? false)
                        || ($0.account?.name.localizedStandardContains(text) ?? false))
            }
        }
        _rows = Query(filter: predicate, sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    }

    private func totals(_ list: [Transaction]) -> (income: Decimal, spending: Decimal) {
        var income: Decimal = 0
        var spending: Decimal = 0
        for transaction in list where !transaction.isTransfer {
            if transaction.amount > 0 { income += transaction.amount } else if transaction.amount < 0 { spending -= transaction.amount }
        }
        return (income, spending)
    }

    private func investmentType(_ transaction: Transaction) -> InvestmentType? {
        transaction.account?.supportsHoldings == true ? InvestmentType.of(transaction) : nil
    }

    private func openDetails(_ id: Transaction.ID) {
        openWindow(id: "transaction-detail", value: TransactionDetailRequest(id: id))
    }

    var body: some View {
        let list = rows.filter { $0.isLive && $0.account?.isLive == true }
        let sums = totals(list)
        VStack(spacing: 12) {
            Table(list) {
                TableColumn("Date") { Text($0.date, format: .dateTime.month(.abbreviated).day().year()) }
                    .width(min: 100, ideal: 110)
                TableColumn("Account") { Text($0.account?.name ?? "") }
                    .width(min: 100, ideal: 140)
                TableColumn("Payee") { Text($0.payee) }
                TableColumn("Category") { transaction in
                    if let type = investmentType(transaction) {
                        Text(type.title)
                    } else {
                        Text(transaction.categoryTitle)
                    }
                }
                TableColumn("Method") { Text($0.paymentTitle) }
                    .width(min: 90, ideal: 110)
                TableColumn("Memo") { Text($0.memo) }
                TableColumn("Amount") { transaction in
                    Text(transaction.amount, format: .appCurrency)
                        .foregroundStyle(transaction.amount > 0 ? Theme.green : (transaction.amount < 0 ? Theme.red : Color.secondary))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 100, ideal: 120)
                TableColumn("Status") { ReconcileBadge(state: $0.state) }
                    .width(min: 110, ideal: 120)
            }
            .contextMenu(forSelectionType: Transaction.ID.self) { ids in
                if ids.count == 1, let id = ids.first {
                    Button("View Details", systemImage: "doc.text.magnifyingglass") { openDetails(id) }
                }
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first { openDetails(id) }
            }
            .overlay {
                if list.isEmpty {
                    ContentUnavailableView(isSearching ? "No Matches" : "No Transactions", systemImage: "list.bullet.rectangle",
                                           description: Text(isSearching ? "Try a different search." : "Nothing was recorded this month."))
                }
            }
            HStack(spacing: 16) {
                Text("\(list.count.formatted()) transaction\(list.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                Text("In").foregroundStyle(.secondary)
                Text(sums.income, format: .appCurrency).foregroundStyle(Theme.green)
                Text("Out").foregroundStyle(.secondary)
                Text(sums.spending, format: .appCurrency).foregroundStyle(Theme.red)
            }
            .font(.callout)
        }
        .statusBarText("\(list.count.formatted()) transaction\(list.count == 1 ? "" : "s") · \(periodLabel) · All accounts")
    }
}
