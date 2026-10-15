import SwiftUI
import SwiftData

// MARK: General

struct GeneralSettingsView: View {
    private let settings = AppSettings.shared

    private var currencyBinding: Binding<String> {
        Binding(get: { settings.currencyCode }, set: { settings.setCurrencyCode($0) })
    }

    private var appearanceBinding: Binding<Appearance> {
        Binding(get: { settings.appearance }, set: { settings.setAppearance($0) })
    }

    var body: some View {
        Form {
            BackgroundSettingsSection()

            Section {
                Picker("Interface", selection: appearanceBinding) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your device's light or dark setting.")
            }

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
                                    Text("\(account.typeTitle)\(account.isLoan && !account.loanPurpose.isEmpty ? " · \(account.loanPurpose)" : "") · \(account.isDebt ? "Debt" : "Asset")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if account.isDefault {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .help("Cash on Hand is built in and can't be deleted.")
                                .accessibilityLabel("Built in. Can't be deleted.")
                        } else {
                            Button(role: .destructive) { pendingDelete = account } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Delete \(account.name)")
                        }
                    }
                    }
                }
            } header: {
                Text("Your Accounts (\(accounts.count))")
            } footer: {
                Text("Tap an account to edit it. Deleting an account also deletes all of its transactions, and can't be undone. Cash on Hand is built in and stays.")
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
    @State private var isAddingCustom = false

    /// Spending categories, with the ones you made yourself first.
    private var expenses: [Category] {
        let list = categories.filter { !$0.isIncome }
        return list.filter(\.isCustom) + list.filter { !$0.isCustom }
    }

    /// Money-in categories, with the ones you made yourself first.
    private var income: [Category] {
        let list = categories.filter(\.isIncome)
        return list.filter(\.isCustom) + list.filter { !$0.isCustom }
    }

    private func expenseRow(_ category: Category) -> some View {
        HStack(spacing: 12) {
            Button { editing = category } label: {
                HStack(spacing: 12) {
                    CategoryBadge(category: category, size: 30)
                    Text(category.name)
                    if category.isCustom {
                        Text("Custom").font(.caption2).foregroundStyle(.secondary)
                    }
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

    @ViewBuilder
    private func incomeRow(_ category: Category) -> some View {
        if category.isCustom {
            Button { editing = category } label: {
                HStack(spacing: 12) {
                    CategoryBadge(category: category, size: 30)
                    Text(category.name)
                    Text("Custom").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 12) {
                CategoryBadge(category: category, size: 30)
                Text(category.name)
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Button("Add Custom Category", systemImage: "plus.circle") { isAddingCustom = true }
            } footer: {
                Text("Make your own, either an expense with a monthly budget or an income category. You can pick it when you record a transaction or set up a bill.")
            }

            Section {
                ForEach(expenses) { expenseRow($0) }
            } header: {
                Text("Expenses & Budgets (\(expenses.count))")
            } footer: {
                Text("Tap one to set its monthly budget. The switch shows or hides it on Home, Budgets and the Summary. A budget that isn't set never shows there.")
            }

            Section {
                ForEach(income) { incomeRow($0) }
            } header: {
                Text("Income (\(income.count))")
            } footer: {
                Text("Income categories don't have budgets. Built-in categories are the same on every device and can't be renamed or deleted. Custom ones can be changed or deleted any time.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { category in
            if category.isCustom { CustomBudgetEditView(category: category) } else { BudgetEditView(category: category) }
        }
        .sheet(isPresented: $isAddingCustom) { CustomBudgetEditView(category: nil) }
    }
}

// MARK: Payment methods

struct PaymentMethodsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomPaymentMethod.name) private var allCustom: [CustomPaymentMethod]
    private var custom: [CustomPaymentMethod] { allCustom.live }

    @State private var isAdding = false
    @State private var editing: CustomPaymentMethod?
    @State private var pendingDelete: CustomPaymentMethod?

    var body: some View {
        Form {
            Section {
                Button("Add Payment Method…", systemImage: "plus.circle.fill") { isAdding = true }
                ForEach(custom) { method in
                    if method.isLive {
                        HStack {
                            Button { editing = method } label: {
                                HStack(spacing: 12) {
                                    Label(method.name, systemImage: method.symbol)
                                    Spacer()
                                    let uses = method.transactions.live.count
                                    Text(uses == 0 ? "Unused" : "\(uses) transaction\(uses == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { pendingDelete = method } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Delete \(method.name)")
                        }
                    }
                }
            } header: {
                Text("My Payment Methods (\(custom.count))")
            } footer: {
                Text("Add your own, such as a shared card or a store account. They show up first in every payment method list.")
            }

            ForEach(PaymentGroup.allCases) { group in
                Section(group.title) {
                    ForEach(group.types) { type in
                        Label(type.title, systemImage: type.symbol)
                    }
                }
            }
            Section {
                Text("\(PaymentType.allCases.count) built-in payment methods are available when you add or edit a transaction, plus any you add above.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isAdding) { CustomPaymentMethodEditView(method: nil) }
        .sheet(item: $editing) { CustomPaymentMethodEditView(method: $0) }
        .confirmationDialog(
            "Delete this payment method?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { method in
            Button("Delete \"\(method.name)\"", role: .destructive) {
                modelContext.delete(method)
                modelContext.saveNow()
                pendingDelete = nil
            }
        } message: { _ in
            Text("Transactions that used it keep their amounts and just show no payment method.")
        }
    }
}

struct CustomPaymentMethodEditView: View {
    let method: CustomPaymentMethod?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String

    private static let symbols: [(String, String)] = [
        ("creditcard", "Card"), ("creditcard.fill", "Card (solid)"), ("banknote", "Cash"), ("building.columns", "Bank"),
        ("iphone", "Phone"), ("qrcode", "QR code"), ("bag", "Store"), ("gift", "Gift"), ("star", "Rewards"),
        ("person.2", "Shared"), ("briefcase", "Business"), ("arrow.left.arrow.right", "Transfer"), ("tag", "Other"),
    ]

    init(method: CustomPaymentMethod?) {
        self.method = method
        _name = State(initialValue: method?.name ?? "")
        _symbol = State(initialValue: method?.symbol ?? "creditcard")
    }

    private var duplicate: Bool {
        let clean = name.trimmingCharacters(in: .whitespaces).lowercased()
        return PaymentType.allCases.contains { $0.title.lowercased() == clean }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormTextField("Name", text: $name, hint: "e.g. Work Card")
                        .onChange(of: name) { _, new in if new.count > 30 { name = String(new.prefix(30)) } }
                    Picker("Icon", selection: $symbol) {
                        ForEach(Self.symbols, id: \.0) { Label($0.1, systemImage: $0.0).tag($0.0) }
                    }
                } footer: {
                    if duplicate { Text("There is already a built-in method with this name. You can still add yours.").foregroundStyle(.orange) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(method == nil ? "New Payment Method" : "Edit Payment Method")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let clean = name.trimmingCharacters(in: .whitespaces)
                        if let method { method.name = clean; method.symbol = symbol }
                        else { modelContext.insert(CustomPaymentMethod(name: clean, symbol: symbol)) }
                        modelContext.saveNow()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .macSheetFrame(minHeight: 260)
    }
}

// MARK: Data & about

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }
    @Query private var allPayees: [Payee]
    private var payees: [Payee] { allPayees.live }

    @State private var confirmingErase = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    @AppStorage(BackupExporter.lastBackupKey) private var lastBackupInterval: Double = 0
    @AppStorage(BackupReminder.snoozeKey) private var snoozedInterval: Double = 0

    private var transactionCount: Int { (try? modelContext.fetchCount(FetchDescriptor<Transaction>())) ?? 0 }

    var body: some View {
        let count = transactionCount
        Form {
            // Only shows once there are a great many transactions.
            if BackupReminder.prompt(
                transactionCount: count,
                lastBackup: lastBackupInterval > 0 ? Date(timeIntervalSinceReferenceDate: lastBackupInterval) : nil,
                snoozedUntil: snoozedInterval > 0 ? Date(timeIntervalSinceReferenceDate: snoozedInterval) : nil) != nil {
                Section { BackupReminderBanner(transactionCount: count) }
            }

            Section("Your Data") {
                LabeledContent("Accounts", value: "\(accounts.count)")
                LabeledContent("Transactions", value: count.formatted())
                LabeledContent("Memorized payees", value: "\(payees.count)")
            }

            Section {
                Button("Erase All Data…", role: .destructive) { confirmingErase = true }
                Text("Deletes every account, transaction, bill, goal and memorized payee on this device, plus any custom categories and custom payment methods you added, then quits. Open Piggybank Financial Budget again afterwards to start fresh. Built-in categories and your budget amounts are kept. This can't be undone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Erase everything and quit?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase Everything and Quit", role: .destructive, action: erase)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every account, transaction, bill, goal, custom category and payment method is deleted, and the app quits. This can't be undone.")
        }
    }

    /// Removes the whole database at the next launch, which takes no time however much data there is, then quits.
    /// Deleting thousands of transactions one by one would tie the app up for minutes.
    private func erase() {
        DataDeletion.afterLeavingAccountPages { StoreReset.requestAndQuit(keepingBudgets: modelContext) }
    }
}

// MARK: Containers

/// The Mac Settings window (Piggybank ▸ Settings…, ⌘,).
struct MacSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RemindersSettingsView()
                .tabItem { Label("Reminders", systemImage: "bell") }
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "building.columns") }
            CategoriesSettingsView()
                .tabItem { Label("Categories", systemImage: "tag") }
            PaymentMethodsSettingsView()
                .tabItem { Label("Payment Methods", systemImage: "creditcard") }
            DataSettingsView()
                .tabItem { Label("Data", systemImage: "externaldrive") }
            ImportExportSettingsView()
                .tabItem { Label("Import & Export", systemImage: "square.and.arrow.up.on.square") }
        }
        .frame(width: 640, height: 560)
    }
}

