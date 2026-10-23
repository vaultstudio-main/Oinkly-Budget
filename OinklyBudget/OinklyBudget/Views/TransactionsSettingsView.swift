import SwiftUI
import SwiftData

/// The Transactions page's settings, in a window of their own so the page stays open and in view behind them: which month it
/// shows and which accounts. The page only displays the month; it is chosen here. Any number of accounts can be ticked.
struct TransactionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @AppStorage(TransactionsSettings.monthKey) private var monthStamp = 0.0
    @AppStorage(TransactionsSettings.accountsKey) private var accountsStored = ""

    private var accounts: [Account] { allAccounts.live }
    private var ticked: Set<String> { TransactionsSettings.keys(from: accountsStored) }

    private var monthBinding: Binding<Date> {
        Binding(get: { TransactionsSettings.month(from: monthStamp) }, set: { monthStamp = $0.timeIntervalSinceReferenceDate })
    }

    private func binding(for account: Account) -> Binding<Bool> {
        let key = MonthOutlook.accountKey(account)
        return Binding(
            get: { ticked.contains(key) },
            set: { on in
                var keys = ticked
                if on { keys.insert(key) } else { keys.remove(key) }
                accountsStored = TransactionsSettings.stored(keys)
            })
    }

    var body: some View {
        SettingsWindowLayout(title: "Transactions Settings") {
            SettingsSection(title: "Month", note: "The month the Transactions page is showing. Searching looks through every month.") {
                MonthSelector(month: monthBinding, range: TransactionsSettings.range(in: modelContext))
            }
            Divider()
            SettingsSection(title: "Accounts", note: "Tick the accounts to show together, one or several. With none ticked, every account is shown.") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(accounts) { account in
                        Toggle(isOn: binding(for: account)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.name)
                                Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        } footer: {
            Button("Select All") { accountsStored = TransactionsSettings.stored(Set(accounts.map(MonthOutlook.accountKey))) }
                .disabled(ticked.count == accounts.count)
            Button("Clear") { accountsStored = "" }
                .disabled(ticked.isEmpty)
            Spacer()
            Button("This Month, All Accounts") {
                monthStamp = 0
                accountsStored = ""
            }
            .disabled(monthStamp == 0 && ticked.isEmpty)
        }
    }
}
