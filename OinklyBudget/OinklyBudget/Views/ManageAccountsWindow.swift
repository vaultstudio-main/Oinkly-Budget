import SwiftUI
import SwiftData

/// Every account in one window of its own, sorted into its category: Checking & Savings, Credit Cards, Mortgages & Loans,
/// Investments and Assets. Each row says what the account is, who it is with and what it holds. Clicking a row edits it.
struct ManageAccountsWindow: View {
    static let id = "manage-accounts"

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]

    @State private var isAdding = false
    @State private var editing: Account?
    @State private var pendingDelete: Account?

    private var accounts: [Account] { allAccounts.live }

    private func members(of group: AccountGroup) -> [Account] {
        accounts.filter { $0.type.group == group }
    }

    var body: some View {
        SettingsWindowLayout(title: "Manage Accounts") {
            if accounts.isEmpty {
                Text("No accounts yet. Use Add Account to make the first one.").foregroundStyle(.secondary)
            }
            ForEach(AccountGroup.setupOrder) { group in
                let list = members(of: group)
                if !list.isEmpty {
                    SettingsSection(title: group.title, note: summary(of: list, in: group)) {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.persistentModelID) { index, account in
                                if index > 0 { Divider() }
                                row(account, in: group)
                            }
                        }
                    }
                    Divider()
                }
            }
            Text("Click an account to edit it. Deleting an account also deletes all of its transactions, and can't be undone. Cash on Hand is built in and stays.")
                .font(.caption).foregroundStyle(.secondary)
        } footer: {
            Button { isAdding = true } label: { Label("Add Account", systemImage: "plus.circle.fill") }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 560, minHeight: 520)
        .sheet(isPresented: $isAdding) { AccountEditView(account: nil) }
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
