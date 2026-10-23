import SwiftUI
import SwiftData

/// The Monthly Outlook's settings, in a window of their own so the page stays open and in view behind them. Changes apply as
/// they are made: what a month starts with, the buffer to keep, and which accounts count.
struct OutlookSettingsView: View {
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @AppStorage(OutlookSettings.startAccountKey) private var startAccount = ""
    @AppStorage(OutlookSettings.startAmountKey) private var startAmount = ""
    @AppStorage(OutlookSettings.bufferKey) private var bufferText = ""
    @AppStorage(MonthOutlook.excludedKey) private var excludedStored = ""

    /// Everything except investments, which hold no bills or budgets.
    private var countable: [Account] { allAccounts.live.filter { !$0.supportsHoldings } }
    private var chosen: Account? { countable.first { MonthOutlook.accountKey($0) == startAccount } }

    private var startBinding: Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(startAmount) }, set: { startAmount = OutlookSettings.text($0) })
    }

    private var bufferBinding: Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(bufferText) }, set: { bufferText = OutlookSettings.text($0) })
    }

    var body: some View {
        Form {
            Section {
                Picker("Starting with", selection: $startAccount) {
                    Text("A number I type").tag("")
                    ForEach(countable) { account in
                        Text("\(account.name): \(account.balance(asOf: .now).formatted(.appCurrency))").tag(MonthOutlook.accountKey(account))
                    }
                }
                if let chosen {
                    LabeledContent("Balance now") { Text(chosen.balance(asOf: .now), format: .appCurrency).fontWeight(.semibold) }
                } else {
                    CurrencyField("Starting amount", value: startBinding)
                }
            } header: {
                Text("What the month starts with")
            } footer: {
                Text("The money already there when the month begins, from an account's balance now or a number you type. The War Plan and the Above the Buffer card start from it.")
            }

            Section {
                CurrencyField("Buffer", value: bufferBinding)
            } header: {
                Text("Buffer")
            } footer: {
                Text("Money to keep untouched. Only what is above it counts as spare, and the War Plan turns orange when a line takes you under it.")
            }

            Section {
                ForEach(countable) { account in
                    Toggle(isOn: Binding(
                        get: { !MonthOutlook.excluded(from: excludedStored).contains(MonthOutlook.accountKey(account)) },
                        set: { counted in
                            var keys = MonthOutlook.excluded(from: excludedStored)
                            if counted { keys.remove(MonthOutlook.accountKey(account)) } else { keys.insert(MonthOutlook.accountKey(account)) }
                            excludedStored = MonthOutlook.stored(keys)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.name)
                            Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Count All Accounts") { excludedStored = "" }
                    .disabled(MonthOutlook.excluded(from: excludedStored).isEmpty)
            } header: {
                Text("Accounts to count")
            } footer: {
                Text("Only ticked accounts count toward the Outlook: their income, spending and repeating transactions. A bill is left out when the payment linked to it came from an account that is unticked.")
            }

            Section {
                Button("Reset Settings", role: .destructive) {
                    startAccount = ""
                    startAmount = ""
                    bufferText = ""
                    excludedStored = ""
                }
            } footer: {
                Text("Clears the starting amount and the buffer and counts every account again. Your War Plan lines are not touched.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 480)
    }
}
