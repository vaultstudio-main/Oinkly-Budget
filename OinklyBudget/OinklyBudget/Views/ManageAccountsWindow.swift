import SwiftUI
import SwiftData

/// Every account in one window of its own, on a tab for each group: Checking & Savings, Credit Cards, Mortgages & Loans,
/// Investments and Assets. Under each tab's title a second row of folder tabs narrows it to one type, such as Savings or Store
/// Card, all on one line so nothing scrolls. Each row says what the account is, who it is with and what it holds. Clicking a
/// row edits it, and Add adds the type you are on.
struct ManageAccountsWindow: View {
    static let id = "manage-accounts"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AccountTabsView {
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 1180, minHeight: 600)
    }
}

/// The tabbed list of accounts, shared by the Manage Accounts window and the setup page a new user starts on. What goes at the
/// right end of the bottom bar, after Add Account, is up to the page that shows it.
struct AccountTabsView<Trailing: View>: View {
    @ViewBuilder let trailing: Trailing

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var allAccounts: [Account]

    @State private var tab = AccountGroup.checkingSavings
    /// The sub-tab picked under the tab: every type in it, or one type.
    @State private var sub = KindTab.all
    @State private var isAdding = false
    @State private var editing: Account?
    @State private var pendingDelete: Account?

    private enum KindTab: Hashable, Identifiable {
        case all
        case type(AccountType)
        var id: Self { self }
    }

    /// The tabs along the top: one for each group, and Archived at the end.
    private enum TopTab: Hashable, Identifiable {
        case group(AccountGroup)
        case archived
        var id: Self { self }
    }

    /// Archived accounts, such as paid-off loans, are on their own tab, not in their group.
    @State private var showsArchived = false
    @State private var reviewingArchive = false

    private var accounts: [Account] { allAccounts.live.filter { !$0.isClosed } }
    private var archivedAccounts: [Account] { allAccounts.live.filter(\.isClosed) }

    private var topTabs: [TopTab] { AccountGroup.setupOrder.map { TopTab.group($0) } + [.archived] }
    private var topSelection: Binding<TopTab> {
        Binding(get: { showsArchived ? .archived : .group(tab) },
                set: { new in
                    switch new {
                    case .group(let group): showsArchived = false; tab = group
                    case .archived: showsArchived = true
                    }
                })
    }
    private func topTitle(_ item: TopTab) -> String {
        switch item {
        case .group(let group): "\(group.title) (\(members(of: group).count))"
        case .archived: "Archived (\(archivedAccounts.count))"
        }
    }

    /// The one type picked under the tab, or nil on All.
    private var kind: AccountType? {
        if case .type(let type) = sub { type } else { nil }
    }

    private func members(of group: AccountGroup) -> [Account] {
        accounts.filter { $0.type.group == group }
    }

    /// What the page shows: the whole tab, or only the type picked under it.
    private func shown(in group: AccountGroup) -> [Account] {
        members(of: group).filter { kind == nil || $0.type == kind }
    }

    var body: some View {
        VStack(spacing: 0) {
            FolderTabs(tabs: topTabs, selection: topSelection, title: topTitle, leading: 20)
                .padding(.top, 12)
                .onChange(of: tab) { _, _ in sub = .all }
            if showsArchived {
                archivedPage
            } else {
            // The group's name, as a title for the folder tabs under it.
            Text(tab.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            FolderTabs(tabs: [KindTab.all] + tab.accountTypes.map { KindTab.type($0) }, selection: $sub, title: subTitle, leading: 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let list = shown(in: tab)
                    SettingsSection(title: summary(of: list, in: tab), note: nil) {
                        if list.isEmpty {
                            Text(emptyMessage).font(.callout).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(list.enumerated()), id: \.element.persistentModelID) { index, account in
                                    if index > 0 { Divider() }
                                    row(account, in: tab)
                                }
                            }
                        }
                    }
                    Text("Click an account to edit it. Deleting an account also deletes all of its transactions, and can't be undone. Cash on Hand is built in and stays.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            }
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    if showsArchived {
                        Button { reviewingArchive = true } label: { Label("Review Archive…", systemImage: "archivebox") }
                            .disabled(archivedAccounts.isEmpty)
                    } else {
                        Button { isAdding = true } label: { Label("Add Account", systemImage: "plus.circle.fill") }
                    }
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .background(Theme.background)
        .sheet(isPresented: $isAdding) { AccountEditView(account: nil, initialType: kind ?? tab.accountTypes.first ?? .checking) }
        .sheet(item: $editing) { AccountEditView(account: $0) }
        .sheet(isPresented: $reviewingArchive) { ArchiveReviewSheet() }
        .confirmationDialog(
            "Delete this account?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { account in
            Button("Delete \"\(account.name)\"", role: .destructive) { delete(account) }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text("This also deletes its \(account.transactions.count) transaction\(account.transactions.count == 1 ? "" : "s"). This can't be undone.")
        }
    }

    // MARK: Archived

    /// The archived accounts, for looking at only: what they were and how many transactions they keep. They can't be opened or brought back,
    /// because they are kept so the history behind net worth, debts and interest stays right. Once a year the app asks whether to keep or delete them.
    private var archivedPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "\(archivedAccounts.count) archived account\(archivedAccounts.count == 1 ? "" : "s")", note: nil) {
                    if archivedAccounts.isEmpty {
                        Text("Nothing is archived. When a loan is paid off, or a lease ends and the car is returned, it is archived here and kept out of sight. An auto loan or mortgage can become an asset, and a student loan or other loan archives itself.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(archivedAccounts.enumerated()), id: \.element.persistentModelID) { index, account in
                                if index > 0 { Divider() }
                                archivedRow(account)
                            }
                        }
                    }
                }
                Text("Archived accounts are kept out of the side panel and the reports' lists, but their transactions stay so the history behind your net worth, debts and interest remains right. At the end of each year you are asked whether to keep them or delete them, and Review Archive… below does the same at any time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func archivedRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.symbol).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                Text("\(detail(account)) · \(account.transactions.count) transaction\(account.transactions.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    /// What one account of a tab is called, for the Add button.
    private func singular(_ group: AccountGroup) -> String {
        switch group {
        case .checkingSavings: "Checking or Savings Account"
        case .creditCards: "Credit Card"
        case .loans: "Loan"
        case .investments: "Investment Account"
        case .assets: "Asset"
        }
    }

    /// A sub-tab's label: a short name for the type and how many accounts it holds, so every tab fits on the one row.
    private func subTitle(_ item: KindTab) -> String {
        switch item {
        case .all: return "All (\(members(of: tab).count))"
        case .type(let type):
            let count = members(of: tab).filter { $0.type == type }.count
            return count > 0 ? "\(shortName(type)) (\(count))" : shortName(type)
        }
    }

    private func shortName(_ type: AccountType) -> String {
        switch type {
        case .certificateOfDeposit: "CD"
        case .healthSavings: "HSA"
        case .flexSpending: "FSA"
        case .prepaidCard: "Prepaid / Debit"
        case .paymentApp: "Payment App"
        case .loan: "Other Loan"
        case .personalLoan: "Personal"
        case .businessLoan: "Business"
        case .studentLoan: "Student"
        case .autoLoan: "Auto"
        case .medicalDebt: "Medical"
        case .homeEquity: "HELOC"
        case .vehicleLoan: "Boat / RV"
        case .retirement401k: "401(k)"
        case .education529: "529"
        case .valuables: "Collectibles"
        default: type.title
        }
    }

    private var emptyMessage: String {
        if let kind { return "No \(kind.title) accounts yet. \(kind.blurb). Use Add Account below to add one." }
        return switch tab {
        case .checkingSavings: "No checking or savings accounts yet. Use the button below to add one."
        case .creditCards: "No credit cards yet. Use the button below to add one, with its limit and payment due date."
        case .loans: "No loans yet. Use the button below to add one. Every loan needs a monthly payment and a due date."
        case .investments: "No investment accounts yet. Use the button below to add one."
        case .assets: "No assets yet. Add property, a vehicle or anything else you own."
        }
    }

    /// "3 accounts · $12,400.00" for what you own, "2 accounts · $5,200.00 owed" for what you owe.
    private func summary(of list: [Account], in group: AccountGroup) -> String {
        let total = list.reduce(Decimal(0)) { $0 + $1.balance }
        let count = "\(list.count) account\(list.count == 1 ? "" : "s")"
        guard group.isLiability else { return "\(count) · \(total.formatted(.appCurrency))" }
        return "\(count) · \(balanceText(total, isDebt: true))"
    }

    private func row(_ account: Account, in group: AccountGroup) -> some View {
        HStack(spacing: 12) {
            Button { editing = account } label: {
                HStack(spacing: 12) {
                    Image(systemName: account.type.symbol)
                        .foregroundStyle(account.isDebt ? Theme.red : Theme.green)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                        Text(detail(account))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(balanceText(account.balance, isDebt: account.isDebt))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(account.isDebt ? Theme.red : Color.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if account.isDefault {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .help("Cash on Hand is built in and can't be deleted.")
                    .accessibilityLabel("Built in. Can't be deleted.")
            } else {
                Button(role: .destructive) { pendingDelete = account } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .frame(width: 22)
                    .accessibilityLabel("Delete \(account.name)")
            }
        }
        .padding(.vertical, 8)
    }

    /// What an account holds: money owed on a debt ("$5,200.00 owed", or "$40.00 credit" when it has been overpaid), or the balance.
    private func balanceText(_ balance: Decimal, isDebt: Bool) -> String {
        guard isDebt else { return balance.formatted(.appCurrency) }
        return balance > 0 ? "\(balance.formatted(.appCurrency)) credit" : "\((-balance).formatted(.appCurrency)) owed"
    }

    /// The type, then what else says which account it is: the lender or bank, or what a loan is for.
    private func detail(_ account: Account) -> String {
        var parts = [account.typeTitle]
        if account.isLoan, !account.loanPurpose.isEmpty { parts.append(account.loanPurpose) }
        if !account.institution.isEmpty { parts.append(account.institution) }
        if PrimaryChecking.isPrimary(account) { parts.append("Primary") }
        return parts.joined(separator: " · ")
    }

    private func delete(_ account: Account) {
        pendingDelete = nil
        DataDeletion.afterLeavingAccountPages {
            modelContext.delete(account)
            try? modelContext.save()
        }
    }
}
