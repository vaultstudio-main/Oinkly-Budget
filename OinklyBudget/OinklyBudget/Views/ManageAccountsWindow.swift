import SwiftUI
import SwiftData

/// Every account in one window of its own, on a tab for each kind: Checking & Savings, Credit Cards, Mortgages & Loans,
/// Investments and Assets. Each row says what the account is, who it is with and what it holds. Clicking a row edits it, and
/// Add Account adds to the tab you are on.
struct ManageAccountsWindow: View {
    static let id = "manage-accounts"

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]

    @State private var tab = AccountGroup.checkingSavings
    @State private var isAdding = false
    @State private var editing: Account?
    @State private var pendingDelete: Account?

    private var accounts: [Account] { allAccounts.live }

    private func members(of group: AccountGroup) -> [Account] {
        accounts.filter { $0.type.group == group }
    }

    var body: some View {
        VStack(spacing: 0) {
            FolderTabs(tabs: AccountGroup.setupOrder, selection: $tab, title: { "\($0.title) (\(members(of: $0).count))" }, leading: 20)
                .padding(.top, 12)
            SettingsWindowLayout(title: tab.title) {
                let list = members(of: tab)
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
            } footer: {
                Button { isAdding = true } label: { Label("Add \(singular(tab))", systemImage: "plus.circle.fill") }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .background(Theme.background)
        .frame(minWidth: 760, minHeight: 520)
        .sheet(isPresented: $isAdding) { AccountEditView(account: nil, initialType: tab.accountTypes.first ?? .checking) }
        .sheet(item: $editing) { AccountEditView(account: $0) }
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

    private var emptyMessage: String {
        switch tab {
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
