import SwiftUI
import SwiftData

/// The Transactions page's settings, in a window of their own so the page stays open and in view behind them: which month it
/// shows and which account. The page only displays the month; it is chosen here.
struct TransactionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @AppStorage(TransactionsSettings.monthKey) private var monthStamp = 0.0
    @AppStorage(TransactionsSettings.accountKey) private var accountKey = ""

    private var accounts: [Account] { allAccounts.live }

    private var monthBinding: Binding<Date> {
        Binding(get: { TransactionsSettings.month(from: monthStamp) }, set: { monthStamp = $0.timeIntervalSinceReferenceDate })
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transactions Settings").font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Month").font(.subheadline.weight(.semibold))
                    MonthSelector(month: monthBinding, range: TransactionsSettings.range(in: modelContext))
                    note("The month the Transactions page is showing. Searching looks through every month.")
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Account").font(.subheadline.weight(.semibold))
                    note("Show every account together, or just one.")
                    Picker("Account", selection: $accountKey) {
                        Text("All Accounts").tag("")
                        ForEach(accounts) { account in
                            Text(account.name).tag(MonthOutlook.accountKey(account))
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Show This Month and All Accounts") {
                        monthStamp = 0
                        accountKey = ""
                    }
                    .disabled(monthStamp == 0 && accountKey.isEmpty)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 360)
    }
}
