import SwiftUI
import SwiftData

// MARK: General

struct GeneralSettingsView: View {
    private let settings = AppSettings.shared

    private var currencyBinding: Binding<String> {
        Binding(get: { settings.currencyCode }, set: { settings.setCurrencyCode($0) })
    }

    var body: some View {
        Form {
            Section("Currency") {
                Picker("Currency", selection: currencyBinding) {
                    Text("Device default (\(AppSettings.deviceCurrencyCode))").tag("")
                    Section("Common") {
                        ForEach(AppSettings.commonCurrencyCodes, id: \.self) { code in
                            Text(AppSettings.currencyName(code)).tag(code)
                        }
                    }
                    Section("All Currencies") {
                        ForEach(AppSettings.allCurrencyCodes, id: \.self) { code in
                            Text(AppSettings.currencyName(code)).tag(code)
                        }
                    }
                }
                LabeledContent("Preview") {
                    Text(Decimal(string: "1234.56") ?? 0, format: .appCurrency)
                }
                Text("Changes how amounts are shown. Existing amounts aren't converted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Accounts

/// Where accounts are created and deleted, on every platform.
struct AccountsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var isAdding = false
    @State private var editing: Account?
    @State private var pendingDelete: Account?

    var body: some View {
        Form {
            Section {
                Button { isAdding = true } label: { Label("Add Account…", systemImage: "plus.circle.fill") }
            }

            Section {
                if accounts.isEmpty {
                    Text("No accounts yet.").foregroundStyle(.secondary)
                }
                ForEach(accounts) { account in
                    if account.isLive {
                    HStack(spacing: 12) {
                        Button { editing = account } label: {
                            HStack(spacing: 12) {
                                Image(systemName: account.type.symbol)
                                    .foregroundStyle(account.isDebt ? Color.red : Color.green)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name)
                                    Text("\(account.type.title)\(account.isLoan && !account.loanPurpose.isEmpty ? " · \(account.loanPurpose)" : "") · \(account.isDebt ? "Debt" : "Asset")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(account.balance, format: .appCurrency).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) { pendingDelete = account } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Delete \(account.name)")
                    }
                    }
                }
            } header: {
                Text("Your Accounts (\(accounts.count))")
            } footer: {
                Text("Tap an account to edit it. Deleting an account also deletes all of its transactions, and can't be undone.")
            }
        }
        .formStyle(.grouped)
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

    private func delete(_ account: Account) {
        pendingDelete = nil
        DataDeletion.afterLeavingAccountPages {
            modelContext.delete(account)
            try? modelContext.save()
        }
    }
}

// MARK: Categories

struct CategoriesSettingsView: View {
    @Query(sort: \Category.name) private var allCategories: [Category]
    private var categories: [Category] { allCategories.live }
    @State private var editing: Category?

    private var expenses: [Category] { categories.filter { !$0.isIncome } }
    private var income: [Category] { categories.filter { $0.isIncome } }

    var body: some View {
        Form {
            Section {
                ForEach(expenses) { category in
                    HStack(spacing: 12) {
                        Button { editing = category } label: {
                            HStack(spacing: 12) {
                                CategoryBadge(category: category, size: 30)
                                Text(category.name)
                                Spacer()
                                if category.monthlyLimit > 0 {
                                    Text(category.monthlyLimit, format: .appCurrency).foregroundStyle(.secondary)
                                } else {
                                    Text("Not set").foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Toggle("Show on budget screens", isOn: Binding(
                            get: { category.showOnBudgets },
                            set: { category.showOnBudgets = $0 }
                        ))
                        .labelsHidden()
                        .help("Show this budget on Home, Budgets and the Summary")
                    }
                }
            } header: {
                Text("Expense Categories (\(expenses.count))")
            } footer: {
                Text("Tap a category to set its monthly budget. The switch shows or hides it on Home, Budgets and the Summary. A budget that isn't set never shows there.")
            }

            Section("Income Categories (\(income.count))") {
                ForEach(income) { category in
                    HStack(spacing: 12) {
                        CategoryBadge(category: category, size: 30)
                        Text(category.name)
                    }
                }
            }

            Section {
                Text("Categories are built in and identical on every device, so they can't be renamed or deleted. Only budgets can be changed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { BudgetEditView(category: $0) }
    }
}

// MARK: Payment methods

struct PaymentMethodsSettingsView: View {
    var body: some View {
        Form {
            ForEach(PaymentGroup.allCases) { group in
                Section(group.title) {
                    ForEach(group.types) { type in
                        Label(type.title, systemImage: type.symbol)
                    }
                }
            }
            Section {
                Text("\(PaymentType.allCases.count) payment methods are available when you add or edit a transaction.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Data & about

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }
    @Query private var allTransactions: [Transaction]
    private var transactions: [Transaction] { allTransactions.live }
    @Query private var allPayees: [Payee]
    private var payees: [Payee] { allPayees.live }

    @State private var confirmingErase = false
    @State private var eraseError: String?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("Your Data") {
                LabeledContent("Accounts", value: "\(accounts.count)")
                LabeledContent("Transactions", value: "\(transactions.count)")
                LabeledContent("Memorized payees", value: "\(payees.count)")
            }

            Section {
                Button("Erase All Data…", role: .destructive) { confirmingErase = true }
                Text("Deletes every account, transaction and memorized payee on this device. Categories and budgets are kept. This can't be undone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Erase all accounts, transactions and payees?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive, action: erase)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't erase your data", isPresented: Binding(get: { eraseError != nil }, set: { if !$0 { eraseError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(eraseError ?? "")
        }
    }

    /// Deletes objects one by one. A batch delete fails on the account/transaction links.
    private func erase() {
        DataDeletion.afterLeavingAccountPages { performErase() }
    }

    private func performErase() {
        do {
            for transaction in try modelContext.fetch(FetchDescriptor<Transaction>()) { modelContext.delete(transaction) }
            for account in try modelContext.fetch(FetchDescriptor<Account>()) { modelContext.delete(account) }
            for payee in try modelContext.fetch(FetchDescriptor<Payee>()) { modelContext.delete(payee) }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            eraseError = error.localizedDescription
        }
    }
}

// MARK: Containers

#if os(macOS)
/// The Mac Settings window (Piggybank ▸ Settings…, ⌘,).
struct MacSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "building.columns") }
            CategoriesSettingsView()
                .tabItem { Label("Categories", systemImage: "tag") }
            PaymentMethodsSettingsView()
                .tabItem { Label("Payment Methods", systemImage: "creditcard") }
            DataSettingsView()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 600, height: 560)
    }
}
#endif

#if os(iOS)
/// The Settings tab on iPhone and iPad.
struct PhoneSettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { GeneralSettingsView().navigationTitle("General") } label: {
                    Label("General", systemImage: "gearshape")
                }
                NavigationLink { AccountsSettingsView().navigationTitle("Accounts") } label: {
                    Label("Accounts", systemImage: "building.columns")
                }
                NavigationLink { CategoriesSettingsView().navigationTitle("Categories") } label: {
                    Label("Categories & Budgets", systemImage: "tag")
                }
                NavigationLink { PaymentMethodsSettingsView().navigationTitle("Payment Methods") } label: {
                    Label("Payment Methods", systemImage: "creditcard")
                }
                NavigationLink { DataSettingsView().navigationTitle("Data") } label: {
                    Label("Data & About", systemImage: "externaldrive")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
#endif
