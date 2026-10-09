#if os(macOS)
import SwiftUI
import SwiftData

/// The full New Transaction form, shown in its own window.
struct NewTransactionWindow: View {
    let accountID: PersistentIdentifier?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }
    @Query(sort: \Category.name) private var allCategories: [Category]
    private var categories: [Category] { allCategories.live }
    @Query(sort: \Payee.name) private var allPayees: [Payee]
    private var payees: [Payee] { allPayees.live }

    @State private var account: Account?
    @State private var isPayment = true
    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var payee = ""
    @State private var category: Category?
    @State private var memo = ""
    @State private var state: ReconcileState = .unreconciled
    @State private var liability: Account?
    @State private var paymentType: PaymentType?
    @State private var checkNumber = ""

    private var suggestions: [Payee] {
        let matches = PayeeMemory.matches(for: payee, in: payees)
        if matches.count == 1, PayeeMemory.normalized(matches[0].name) == PayeeMemory.normalized(payee) { return [] }
        return matches
    }

    private var canSave: Bool { (amount ?? 0) > 0 && account != nil }

    /// Debts you can pay toward from the chosen account.
    private var payableAccounts: [Account] { Transfers.payableAccounts(accounts, excluding: account) }

    private var isPayingLiability: Bool { isPayment && liability != nil }

    var body: some View {
        Group {
            if accounts.isEmpty {
                ContentUnavailableView("No Accounts", systemImage: "building.columns", description: Text("Add an account in Settings ▸ Accounts first."))
            } else {
                form
            }
        }
        .onChange(of: isPayment) { _, new in if !new { liability = nil } }
        .onChange(of: account) { _, new in if liability?.persistentModelID == new?.persistentModelID { liability = nil } }
        .frame(width: 480, height: 700)
        .background(Theme.background)
        .onAppear {
            if account == nil {
                let opened = accounts.first { $0.id == accountID } ?? accounts.first
                let start = Transfers.defaults(opening: opened, accounts: accounts)
                account = start.source
                liability = start.liability
            }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            Form {
                Section("Transaction") {
                    Picker("Account", selection: $account) {
                        ForEach(accounts) { account in if account.isLive { Text(account.name).tag(Optional(account)) } }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $isPayment) {
                        Text("Payment (money out)").tag(true)
                        Text("Deposit (money in)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    TextField("Amount", value: $amount, format: .appCurrency)
                    if isPayment && !payableAccounts.isEmpty {
                        Picker("Pay toward", selection: $liability) {
                            Text("Not a debt payment").tag(Account?.none)
                            ForEach(AccountGroup.setupOrder.filter(\.isLiability)) { group in
                                let members = payableAccounts.filter { $0.type.group == group }
                                if !members.isEmpty {
                                    Section(group.title) {
                                        ForEach(members) { Text($0.name).tag(Optional($0)) }
                                    }
                                }
                            }
                        }
                        if let liability {
                            Text("This also lowers what you owe on \(liability.name) by the same amount.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Details") {
                    if !isPayingLiability { TextField("Payee", text: $payee) }
                    if !suggestions.isEmpty && !isPayingLiability {
                        HStack {
                            ForEach(suggestions) { suggestion in
                                Button(suggestion.name) { apply(suggestion) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                    if !isPayingLiability {
                        Picker("Category", selection: $category) {
                            Text("None").tag(Category?.none)
                            ForEach(categories.expensesFirst) { Text($0.name).tag(Optional($0)) }
                        }
                    }
                    Picker("Payment method", selection: $paymentType) {
                        PaymentTypeOptions()
                    }
                    if paymentType == .check {
                        TextField("Check number", text: $checkNumber)
                    }
                    TextField("Memo", text: $memo)
                    Picker("Status", selection: $state) {
                        ForEach(ReconcileState.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save & New") { save(keepOpen: true) }
                    .disabled(!canSave)
                Button("Save") { save(keepOpen: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
    }

    private func apply(_ suggestion: Payee) {
        payee = suggestion.name
        category = suggestion.lastCategory
        if suggestion.lastAmount != 0 {
            amount = abs(suggestion.lastAmount)
            isPayment = suggestion.lastAmount < 0
        }
    }

    private func save(keepOpen: Bool) {
        guard let amount, let account else { return }
        if isPayment, let liability, liability.isLive {
            // One payment, two sides: money leaves this account and the debt shrinks.
            Transfers.pay(from: account, toward: liability, amount: amount, date: date, memo: memo, state: state,
                          paymentType: paymentType, checkNumber: checkNumber, in: modelContext)
        } else {
            let signed = isPayment ? -amount : amount
            PayeeMemory.record(name: payee, category: category, amount: signed, in: modelContext)
            let transaction = Transaction(account: account, date: date, payee: payee, category: category, memo: memo, amount: signed)
            transaction.state = state
            transaction.paymentType = paymentType
            transaction.checkNumber = paymentType == .check ? checkNumber : ""
            modelContext.insert(transaction)
        }

        modelContext.saveNow()

        if keepOpen {
            self.amount = nil
            payee = ""
            category = nil
            memo = ""
            state = .unreconciled
            liability = nil
            checkNumber = ""
        } else {
            dismiss()
        }
    }
}
#endif
