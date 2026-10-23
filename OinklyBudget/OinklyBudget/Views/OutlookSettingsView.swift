import SwiftUI
import SwiftData

/// The Monthly Outlook's settings, in a window of their own so the page stays open and in view behind them. Changes apply as
/// they are made: what a month starts with, the buffer to keep, and which accounts count. Only checking, savings and cash
/// accounts are listed, because nothing owed and nothing invested is part of the outlook.
struct OutlookSettingsView: View {
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @AppStorage(OutlookSettings.startAccountKey) private var startAccount = ""
    @AppStorage(OutlookSettings.startAmountKey) private var startAmount = ""
    @AppStorage(OutlookSettings.bufferKey) private var bufferText = ""
    @AppStorage(MonthOutlook.excludedKey) private var excludedStored = ""
    @AppStorage(OutlookSettings.tabKey) private var tab = "outlook"

    private var countable: [Account] { allAccounts.live.filter(MonthOutlook.isEligible) }
    private var chosen: Account? { countable.first { MonthOutlook.accountKey($0) == startAccount } }

    private var startBinding: Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(startAmount) }, set: { startAmount = OutlookSettings.text($0) })
    }

    private var bufferBinding: Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(bufferText) }, set: { bufferText = OutlookSettings.text($0) })
    }

    @AppStorage(OutlookSettings.monthKey) private var monthStamp = 0.0

    private var monthBinding: Binding<Date> {
        Binding(get: { OutlookSettings.month(from: monthStamp) }, set: { monthStamp = $0.timeIntervalSinceReferenceDate })
    }

    /// Which month the page shows, for both tabs. The page itself only displays it.
    private var monthPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Month").font(.subheadline.weight(.semibold))
            MonthSelector(month: monthBinding, range: OutlookSettings.monthRange)
            note("The month the Outlook and the War Plan are showing. Each start of the app begins on this month.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        if tab == "warPlan" { warPlanSettings } else { outlookSettings }
    }

    // MARK: Outlook tab: which accounts count

    /// The Outlook's settings are only which accounts it counts, picked from the checking, savings and cash accounts.
    private var outlookSettings: some View {
        let groups: [(title: String, accounts: [Account])] = [
            ("Checking", countable.filter { $0.type == .checking }),
            ("Savings", countable.filter { $0.type == .savings }),
            ("Cash", countable.filter { $0.type == .cash }),
            ("Other cash accounts", countable.filter { ![.checking, .savings, .cash].contains($0.type) }),
        ].filter { !$0.accounts.isEmpty }
        let excluded = MonthOutlook.excluded(from: excludedStored)
        let counted = countable.filter { !excluded.contains(MonthOutlook.accountKey($0)) }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Outlook Settings").font(.headline)
                monthPicker
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accounts to count").font(.subheadline.weight(.semibold))
                    note("Pick the checking, savings and cash accounts the Outlook counts: their income, spending and repeating transactions. Credit cards, loans, investments and property never count. A bill is left out when the payment linked to it came from an account that is unticked.")
                }
                HStack {
                    Button("Select All") { excludedStored = "" }.disabled(excluded.isEmpty)
                    Button("Select None") { excludedStored = MonthOutlook.stored(Set(countable.map(MonthOutlook.accountKey))) }.disabled(counted == 0)
                    Spacer()
                    Text("\(counted) of \(countable.count) counted").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(group.accounts) { account in
                            accountToggle(account)
                        }
                    }
                    Divider()
                }
                if countable.isEmpty { note("You have no checking, savings or cash accounts yet.") }
                note("What the month starts with and your buffer are in the War Plan tab's settings.")
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 460)
    }

    private func accountToggle(_ account: Account) -> some View {
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

    // MARK: War Plan tab: everything

    private var warPlanSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("War Plan Settings").font(.headline)
                monthPicker
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Starting with").font(.subheadline.weight(.semibold))
                    HStack {
                        Menu {
                            Button("A number I type") { startAccount = "" }
                            Divider()
                            ForEach(countable) { account in
                                Button("\(account.name): \(account.balance(asOf: .now).formatted(.appCurrency))") { startAccount = MonthOutlook.accountKey(account) }
                            }
                        } label: {
                            Text(chosen.map { "\($0.name)'s balance" } ?? "A number I type")
                        }
                        .fixedSize()
                        if let chosen {
                            Spacer()
                            Text(chosen.balance(asOf: .now), format: .appCurrency).fontWeight(.semibold)
                        } else {
                            CurrencyField("Starting amount", value: startBinding)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    note("The money already there when the month begins, from an account's balance now or a number you type. The War Plan and the Above the Buffer card start from it.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Buffer").font(.subheadline.weight(.semibold))
                    CurrencyField("Buffer", value: bufferBinding)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                    note("Money to keep untouched. Only what is above it counts as spare, and the War Plan turns orange when a line takes you under it.")
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Accounts to count").font(.subheadline.weight(.semibold))
                    note("Only checking, savings and cash accounts can count. Credit cards, loans, investments and property never do. Untick one to leave out its income, spending and repeating transactions. A bill is left out when the payment linked to it came from an account that is unticked.")
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
                    if countable.isEmpty { note("You have no checking, savings or cash accounts yet.") }
                }

                Divider()

                HStack {
                    Button("Count All Accounts") { excludedStored = "" }
                        .disabled(MonthOutlook.excluded(from: excludedStored).isEmpty)
                    Spacer()
                    Button("Reset Settings", role: .destructive) {
                        startAccount = ""
                        startAmount = ""
                        bufferText = ""
                        excludedStored = ""
                    }
                    .help("Clears the starting amount and the buffer and counts every account again. Your War Plan lines are not touched.")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 460)
    }
}
