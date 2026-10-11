import SwiftUI
import SwiftData

/// Every account's transactions together, a month at a time, so you can look at them as a whole.
/// Searching looks through every month. The Mac shows a table.
struct TransactionsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var month = MonthFilter.start(of: .now)
    @State private var accountID: Account.ID?
    @State private var search = ""


    /// Live transactions of live accounts only, filtered by account, month and search text.
    private var shown: [Transaction] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return allTransactions.live.filter { transaction in
            guard let account = transaction.account, account.isLive else { return false }
            if let accountID, account.id != accountID { return false }
            if query.isEmpty { return MonthFilter.contains(month, transaction.date) }
            return transaction.payee.localizedCaseInsensitiveContains(query)
                || transaction.memo.localizedCaseInsensitiveContains(query)
                || ((transaction.fixedCategoryTitle ?? transaction.category?.name)?.localizedCaseInsensitiveContains(query) ?? false)
                || account.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var range: ClosedRange<Date> {
        MonthFilter.range(for: allTransactions.live.filter { $0.account?.isLive == true })
    }

    private var accountPicker: some View {
        Picker("Account", selection: $accountID) {
            Text("All Accounts").tag(Account.ID?.none)
            ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func totals(_ list: [Transaction]) -> (income: Decimal, spending: Decimal) {
        let real = list.filter { !$0.isTransfer }
        return (real.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount },
                real.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount })
    }

    private var heading: String { search.isEmpty ? "" : "Results for “\(search)”" }

    var body: some View {
        let list = shown
        let sums = totals(list)
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
                        Text(transaction.fixedCategoryTitle ?? transaction.category?.name ?? "")
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
            .overlay {
                if list.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No Transactions" : "No Matches", systemImage: "list.bullet.rectangle",
                                           description: Text(search.isEmpty ? "Nothing was recorded this month." : "Try a different search."))
                }
            }
            HStack(spacing: 16) {
                Text("\(list.count) transaction\(list.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                Text("In").foregroundStyle(.secondary)
                Text(sums.income, format: .appCurrency).foregroundStyle(Theme.green)
                Text("Out").foregroundStyle(.secondary)
                Text(sums.spending, format: .appCurrency).foregroundStyle(Theme.red)
            }
            .font(.callout)
        }
        .padding(16)
        .background(Theme.background)
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
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 240)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
    }

    private func investmentType(_ transaction: Transaction) -> InvestmentType? {
        transaction.account?.supportsHoldings == true ? InvestmentType.of(transaction) : nil
    }
}
