#if os(iOS)
import SwiftUI
import SwiftData

struct PhoneTransactionForm: View {
    /// Pass nil to create a new transaction.
    let transaction: Transaction?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }
    @Query(sort: \Category.name) private var allCategories: [Category]
    private var categories: [Category] { allCategories.live }
    @Query(sort: \Payee.name) private var allPayees: [Payee]
    private var payees: [Payee] { allPayees.live }

    @State private var isExpense: Bool
    @State private var amount: Decimal?
    @State private var payee: String
    @State private var category: Category?
    @State private var date: Date
    @State private var memo: String
    @State private var account: Account?
    @State private var confirmingDelete = false
    @State private var paymentType: PaymentType?
    @State private var checkNumber: String
    @State private var state: ReconcileState
    @State private var liability: Account?

    init(transaction: Transaction?, defaultAccount: Account? = nil) {
        self.transaction = transaction
        _isExpense = State(initialValue: (transaction?.amount ?? -1) <= 0)
        _amount = State(initialValue: transaction.map { abs($0.amount) })
        _payee = State(initialValue: transaction?.payee ?? "")
        _category = State(initialValue: transaction?.category)
        _date = State(initialValue: transaction?.date ?? .now)
        _memo = State(initialValue: transaction?.memo ?? "")
        _account = State(initialValue: transaction?.account ?? defaultAccount)
        _paymentType = State(initialValue: transaction?.paymentType)
        _checkNumber = State(initialValue: transaction?.checkNumber ?? "")
        _state = State(initialValue: transaction?.state ?? .unreconciled)
    }

    private var isTransfer: Bool { transaction?.isTransfer == true }

    /// Debts you can pay toward from the chosen account. Only when adding a new expense.
    private var payableAccounts: [Account] {
        transaction == nil && isExpense ? Transfers.payableAccounts(accounts, excluding: account) : []
    }

    private var isPayingLiability: Bool { transaction == nil && isExpense && liability != nil }

    private var suggestions: [Payee] {
        let matches = PayeeMemory.matches(for: payee, in: payees)
        if matches.count == 1, PayeeMemory.normalized(matches[0].name) == PayeeMemory.normalized(payee) { return [] }
        return matches
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isTransfer)

                    TextField("$0.00", value: $amount, format: .appCurrency)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isExpense ? Color.primary : Color.green)
                        .padding(.vertical, 8)
                }

                if !payableAccounts.isEmpty {
                    Section {
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
                    } footer: {
                        if let liability {
                            Text("This also lowers what you owe on \(liability.name) by the same amount.")
                        }
                    }
                }

                if !isPayingLiability && !isTransfer {
                Section("Payee") {
                    TextField("Who was it?", text: $payee)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions) { suggestion in
                                    Button(suggestion.name) { apply(suggestion) }
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                }
                            }
                        }
                    }
                }

                }

                if !isPayingLiability && !isTransfer {
                Section("Category") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 12) {
                        ForEach(categories.expensesFirst) { item in
                            Button {
                                withAnimation(.snappy) { category = category == item ? nil : item }
                            } label: {
                                VStack(spacing: 4) {
                                    CategoryBadge(category: item)
                                    Text(item.name).font(.caption).lineLimit(1)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background {
                                    if category == item {
                                        RoundedRectangle(cornerRadius: 12).fill(Color(hex: item.colorHex).opacity(0.15))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if accounts.count != 1 {
                        Picker("Account", selection: $account) {
                            ForEach(accounts) { account in if account.isLive { Text(account.name).tag(Optional(account)) } }
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

                if transaction != nil {
                    Section {
                        Button("Delete Transaction", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let transaction { Transfers.delete(transaction, in: modelContext) }
                    modelContext.saveNow()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled((amount ?? 0) <= 0 || account == nil)
                }
            }
            .onChange(of: isExpense) { _, new in if !new { liability = nil } }
            .onChange(of: account) { _, new in if liability?.persistentModelID == new?.persistentModelID { liability = nil } }
            .onAppear {
                guard transaction == nil else { return }
                let opened = account ?? accounts.first { $0.type == .checking } ?? accounts.first
                let start = Transfers.defaults(opening: opened, accounts: accounts)
                account = start.source
                liability = start.liability
            }
        }
    }

    private func apply(_ suggestion: Payee) {
        payee = suggestion.name
        category = suggestion.lastCategory
        if suggestion.lastAmount != 0 {
            amount = abs(suggestion.lastAmount)
            isExpense = suggestion.lastAmount < 0
        }
    }

    private func save() {
        guard let amount, let account else { return }
        let signed = isExpense ? -amount : amount
        if transaction == nil, isExpense, let liability, liability.isLive {
            // One payment, two sides: money leaves this account and the debt shrinks.
            Transfers.pay(from: account, toward: liability, amount: amount, date: date, memo: memo, state: state,
                          paymentType: paymentType, checkNumber: checkNumber, in: modelContext)
            modelContext.saveNow()
            dismiss()
            return
        }
        if !isTransfer { PayeeMemory.record(name: payee, category: category, amount: signed, in: modelContext) }
        if let transaction {
            transaction.account = account
            transaction.date = date
            transaction.payee = payee
            transaction.category = category
            transaction.memo = memo
            transaction.amount = signed
            transaction.paymentType = paymentType
            transaction.checkNumber = paymentType == .check ? checkNumber : ""
            transaction.state = state
            if transaction.isTransfer { Transfers.syncPeer(of: transaction, in: modelContext) }
        } else {
            let created = Transaction(account: account, date: date, payee: payee, category: category, memo: memo, amount: signed, paymentType: paymentType)
            created.checkNumber = paymentType == .check ? checkNumber : ""
            created.state = state
            modelContext.insert(created)
        }
        modelContext.saveNow()
        dismiss()
    }
}
#endif
