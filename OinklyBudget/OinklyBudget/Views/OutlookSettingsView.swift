import SwiftUI
import SwiftData

/// The Monthly Outlook's settings, in a window of their own so the page stays open and in view behind them. Changes apply as
/// they are made. The window follows the tab: the Outlook tab's settings are the month and which accounts count, laid out in columns
/// so a long list of accounts doesn't scroll; the War Plan tab's are the month, what the month starts with and the buffer, with no
/// accounts to tick. Only checking, savings and cash accounts are listed, because nothing owed and nothing invested is part of the outlook.
struct OutlookSettingsView: View {
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @AppStorage(OutlookSettings.startAccountKey) private var startAccount = ""
    @AppStorage(OutlookSettings.startAmountKey) private var startAmount = ""
    @AppStorage(OutlookSettings.bufferKey) private var bufferText = ""
    @AppStorage(MonthOutlook.excludedKey) private var excludedStored = ""
    @AppStorage(OutlookSettings.tabKey) private var tab = "outlook"
    @AppStorage(OutlookSettings.monthKey) private var monthStamp = 0.0

    private var countable: [Account] { allAccounts.live.filter(MonthOutlook.isEligible) }
    private var chosen: Account? { countable.first { MonthOutlook.accountKey($0) == startAccount } }
    private var excluded: Set<String> { MonthOutlook.excluded(from: excludedStored) }
    private var counted: Int { countable.filter { !excluded.contains(MonthOutlook.accountKey($0)) }.count }

    private var startBinding: Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(startAmount) }, set: { startAmount = OutlookSettings.text($0) })
    }

    private var bufferBinding: Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(bufferText) }, set: { bufferText = OutlookSettings.text($0) })
    }

    private var monthBinding: Binding<Date> {
        Binding(get: { OutlookSettings.month(from: monthStamp) }, set: { monthStamp = $0.timeIntervalSinceReferenceDate })
    }

    private func toggle(for account: Account) -> Binding<Bool> {
        let key = MonthOutlook.accountKey(account)
        return Binding(
            get: { !excluded.contains(key) },
            set: { on in
                var keys = excluded
                if on { keys.remove(key) } else { keys.insert(key) }
                excludedStored = MonthOutlook.stored(keys)
            })
    }

    // MARK: Sections

    private var monthSection: some View {
        SettingsSection(title: "Month", note: "The month the Outlook and the War Plan are showing. Each start of the app begins on this month.") {
            MonthSelector(month: monthBinding, range: OutlookSettings.monthRange)
        }
    }

    private var startingSection: some View {
        SettingsSection(title: "Starting with", note: "The money already there when the month begins, from an account's balance now or a number you type. The War Plan and the Above the Buffer card start from it.") {
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
        }
    }

    private var bufferSection: some View {
        SettingsSection(title: "Buffer", note: "Money to keep untouched. Only what is above it counts as spare, and the War Plan turns orange when a line takes you under it.") {
            CurrencyField("Buffer", value: bufferBinding)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        }
    }

    /// The smaller tabs for the accounts: every one, then checking, savings and cash on their own.
    private enum AccountTab: String, CaseIterable, Identifiable {
        case all = "All", checking = "Checking", savings = "Savings", cash = "Cash", other = "Other"
        var id: Self { self }

        func includes(_ account: Account) -> Bool {
            switch self {
            case .all: true
            case .checking: account.type == .checking
            case .savings: account.type == .savings
            case .cash: account.type == .cash
            case .other: ![.checking, .savings, .cash].contains(account.type)
            }
        }
    }

    @State private var accountTab = AccountTab.all

    /// The checking, savings and cash accounts, a tab for each kind with a tick box on every account, three to a row.
    private var accountsSection: some View {
        let tabs = AccountTab.allCases.filter { $0 == .all || countable.contains(where: $0.includes) }
        let shown = countable.filter(accountTab.includes)
        return SettingsSection(title: "Accounts to count",
                               note: "Tick the checking, savings and cash accounts the Outlook counts: their income, spending and repeating transactions. Credit cards, loans, investments and property never count. A bill is left out when the payment linked to it came from an account that is unticked.") {
            VStack(alignment: .leading, spacing: 12) {
                FolderTabs(tabs: tabs, selection: $accountTab, title: { tab in
                    tab == .all ? "All (\(countable.count))" : "\(tab.rawValue) (\(countable.filter(tab.includes).count))"
                }, leading: 0)
                if countable.isEmpty {
                    Text("You have no checking, savings or cash accounts yet.").font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading), count: 3), alignment: .leading, spacing: 10) {
                        ForEach(shown) { account in
                            Toggle(isOn: toggle(for: account)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name).lineLimit(1)
                                    Text(account.typeTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Tabs

    var body: some View {
        if tab == "warPlan" { warPlanSettings } else { outlookSettings }
    }

    private var outlookSettings: some View {
        SettingsWindowLayout(title: "Outlook Settings") {
            monthSection
            Divider()
            accountsSection
            Text("What the month starts with and your buffer are in the War Plan tab's settings.").font(.caption).foregroundStyle(.secondary)
        } footer: {
            Button("Select All") { excludedStored = "" }.disabled(excluded.isEmpty)
            Button("Select None") { excludedStored = MonthOutlook.stored(Set(countable.map(MonthOutlook.accountKey))) }.disabled(counted == 0)
            Spacer()
            Text("\(counted) of \(countable.count) counted").font(.caption).foregroundStyle(.secondary)
        }
        .background(Theme.background)
    }

    private var warPlanSettings: some View {
        SettingsWindowLayout(title: "War Plan Settings") {
            monthSection
            Divider()
            startingSection
            bufferSection
        } footer: {
            Spacer()
            Button("Reset Settings", role: .destructive) {
                startAccount = ""
                startAmount = ""
                bufferText = ""
            }
            .help("Clears the starting amount and the buffer. Your War Plan lines are not touched.")
        }
    }
}
