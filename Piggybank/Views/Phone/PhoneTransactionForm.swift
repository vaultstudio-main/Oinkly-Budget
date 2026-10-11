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
    /// Loans are paid with Pay a Bill, and credit cards take charges through New Credit Card Charge, so a new
    /// transaction can't go on either. An existing transaction on one can still be opened and edited.
    private var choosableAccounts: [Account] {
        accounts.filter {
            ($0.isLoan == false && $0.isCreditCard == false && $0.isCashOnHand == false)
                || $0.persistentModelID == transaction?.account?.persistentModelID
        }
    }
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
    @State private var paymentChoice: PaymentChoice?
    @State private var checkNumber: String
    @State private var state: ReconcileState
    @State private var investmentType: InvestmentType

    init(transaction: Transaction?, defaultAccount: Account? = nil) {
        self.transaction = transaction
        _isExpense = State(initialValue: (transaction?.amount ?? -1) <= 0)
        _amount = State(initialValue: transaction.map { abs($0.amount) })
        _payee = State(initialValue: transaction?.payee ?? "")
        _category = State(initialValue: transaction?.category)
        _date = State(initialValue: transaction?.date ?? .now)
        _memo = State(initialValue: transaction?.memo ?? "")
        _account = State(initialValue: transaction?.account ?? defaultAccount)
        _paymentChoice = State(initialValue: transaction?.paymentChoice)
        _checkNumber = State(initialValue: transaction?.checkNumber ?? "")
        _state = State(initialValue: transaction?.state ?? .unreconciled)
        _receipt = State(initialValue: transaction?.receiptData)
        _noReceipt = State(initialValue: transaction?.noReceipt ?? false)
        _investmentType = State(initialValue: transaction.map { InvestmentType.of($0) } ?? .contribution)
    }

    @State private var limitMessage: String?
    @State private var receipt: Data?
    @State private var noReceipt: Bool

    /// How much this changes the chosen account: a new charge, or the difference when editing one on the same account.
    private var accountChange: Decimal {
        let value = amount ?? 0
        let signed = isInvestment ? (investmentType.isOutflow ? -value : value) : (isExpense ? -value : value)
        if let transaction, transaction.account?.persistentModelID == account?.persistentModelID {
            return signed - transaction.amount
        }
        return signed
    }

    private var exceedsLimit: Bool { account?.wouldExceedLimit(adding: accountChange) == true }

    private var isTransfer: Bool { transaction?.isTransfer == true }

    /// Investment accounts take a Type (contribution, gain, fee…) instead of a category and payment method.
    private var isInvestment: Bool { account?.supportsHoldings == true }

    private var isInflow: Bool { isInvestment ? !investmentType.isOutflow : !isExpense }

    private var suggestions: [Payee] {
        let matches = PayeeMemory.matches(for: payee, in: payees)
        if matches.count == 1, PayeeMemory.normalized(matches[0].name) == PayeeMemory.normalized(payee) { return [] }
        return matches
    }

    var body: some View {
        // Deleting from inside the form (or from a list behind it) leaves this on screen for a moment.
        if transaction?.isLive ?? true { content }
    }

    private var content: some View {
        NavigationStack {
            Form {
                Section {
                    if isInvestment {
                        Picker("Type", selection: $investmentType) {
                            ForEach(InvestmentType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .disabled(isTransfer)
                    } else {
                        Picker("Type", selection: $isExpense) {
                            Text("Expense").tag(true)
                            Text("Income").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .disabled(isTransfer)
                    }

                    CurrencyField("$0.00", value: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isInflow ? Color.green : Color.primary)
                        .padding(.vertical, 8)
                }

                if exceedsLimit, let account {
                    Section {
                        Label("This would reach the credit limit on \(account.name).", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if !isTransfer {
                Section(isInvestment ? "Description" : "Payee") {
                    TextField(isInvestment ? "What was it?" : "Who was it?", text: $payee)
                    if !suggestions.isEmpty && !isInvestment {
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

                if !isTransfer && !isInvestment && transaction?.isBillPayment != true {
                Section {
                    Picker("Category", selection: $category) {
                        CategoryOptions(categories: categories, only: isExpense ? .expense : .income, keeping: category)
                    }
                }

                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if choosableAccounts.count != 1 {
                        Picker("Account", selection: $account) {
                            ForEach(choosableAccounts) { account in if account.isLive { Text(account.name).tag(Optional(account)) } }
                        }
                    }
                    if !isInvestment && transaction?.isAtmWithdrawal != true {
                        if let locked = account?.lockedPaymentType, !isTransfer {
                            LabeledContent("Payment method") {
                                Label(locked.title, systemImage: "lock.fill").foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Payment method", selection: $paymentChoice) {
                                PaymentTypeOptions()
                            }
                            if paymentChoice?.isCheck == true {
                                TextField("Check number", text: $checkNumber)
                            }
                        }
                    }
                    if transaction?.isAtmWithdrawal == true {
                        LabeledContent("Memo") { Label(memo, systemImage: "lock.fill").foregroundStyle(.secondary) }
                    } else {
                        TextField("Memo", text: $memo)
                    }
                    if transaction?.isAtmWithdrawal == true {
                        LabeledContent("Status") {
                            Label(ReconcileState.reconciled.title, systemImage: "lock.fill").foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Status", selection: $state) {
                            ForEach(ReconcileState.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    }
                }

                if account?.supportsReceipts == true && transaction?.receiptLocked != true {
                    Section("Receipt") {
                        ReceiptPicker(data: $receipt, noReceipt: $noReceipt)
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
            .alert("Exceeds Credit Limit", isPresented: Binding(get: { limitMessage != nil }, set: { if !$0 { limitMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(limitMessage ?? "")
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
            .onChange(of: isExpense) { _, new in
                // A category only fits one direction, so a change of direction clears one that no longer fits.
                if let category, category.isIncome == new { self.category = nil }
            }
            .onAppear {
                guard transaction == nil else { return }
                let opened = account ?? accounts.first { $0.type == .checking } ?? accounts.first
                account = Transfers.startingAccount(opening: opened, accounts: accounts)
            }
        }
    }

    private func apply(_ suggestion: Payee) {
        payee = suggestion.name
        if suggestion.lastAmount != 0 {
            amount = abs(suggestion.lastAmount)
            isExpense = suggestion.lastAmount < 0
        }
        // Only a category that fits the direction is filled in.
        let last = suggestion.lastCategory
        category = last?.isIncome == !isExpense ? last : nil
    }

    private func save() {
        guard let amount, let account else { return }
        if account.wouldExceedLimit(adding: accountChange) {
            limitMessage = account.limitMessage
            return
        }
        if account.supportsHoldings && !isTransfer {
            saveInvestment(amount: amount, account: account)
            return
        }
        if transaction?.isAtmWithdrawal == true { state = .reconciled }
        // Charges on a credit card are always credit card charges, and cash on hand is always cash.
        if let locked = account.lockedPaymentType, !isTransfer {
            paymentChoice = .type(locked)
            checkNumber = ""
        }
        let signed = isExpense ? -amount : amount
        if !isTransfer { PayeeMemory.record(name: payee, category: category, amount: signed, in: modelContext) }
        if let transaction {
            transaction.account = account
            transaction.date = date
            transaction.payee = payee
            transaction.category = category
            transaction.memo = memo
            transaction.amount = signed
            transaction.paymentChoice = paymentChoice
            transaction.checkNumber = paymentChoice?.isCheck == true ? checkNumber : ""
            transaction.state = state
            if account.supportsReceipts {
                transaction.receiptData = receipt
                transaction.noReceipt = receipt == nil && noReceipt
            }
            if transaction.isTransfer { Transfers.syncPeer(of: transaction, in: modelContext) }
        } else {
            let created = Transaction(account: account, date: date, payee: payee, category: category, memo: memo, amount: signed)
            created.paymentChoice = paymentChoice
            created.checkNumber = paymentChoice?.isCheck == true ? checkNumber : ""
            created.state = state
            created.receiptData = account.supportsReceipts ? receipt : nil
            created.noReceipt = account.supportsReceipts && receipt == nil && noReceipt
            modelContext.insert(created)
        }
        modelContext.saveNow()
        dismiss()
    }

    /// An investment transaction: the Type sets the sign and the category.
    private func saveInvestment(amount: Decimal, account: Account) {
        let signed = investmentType.isOutflow ? -amount : amount
        let name = payee.isEmpty ? investmentType.title : payee
        let category = investmentType.category(in: categories)
        if let transaction {
            transaction.account = account
            transaction.date = date
            transaction.payee = name
            transaction.category = category
            transaction.memo = memo
            transaction.amount = signed
            transaction.paymentChoice = nil
            transaction.checkNumber = ""
            transaction.state = state
            if account.supportsReceipts {
                transaction.receiptData = receipt
                transaction.noReceipt = receipt == nil && noReceipt
            }
        } else {
            let created = Transaction(account: account, date: date, payee: name, category: category, memo: memo, amount: signed)
            created.state = state
            created.receiptData = account.supportsReceipts ? receipt : nil
            created.noReceipt = account.supportsReceipts && receipt == nil && noReceipt
            modelContext.insert(created)
        }
        modelContext.saveNow()
        dismiss()
    }
}
#endif
