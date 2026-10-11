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
    /// Loans are paid with Pay a Bill, credit cards take charges through New Credit Card Charge, and Cash on Hand is
    /// filled by withdrawals rather than ordinary transactions.
    private var choosableAccounts: [Account] { accounts.filter { !$0.isLoan && !$0.isCreditCard && !$0.isCashOnHand } }
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
    @State private var paymentChoice: PaymentChoice?
    @State private var checkNumber = ""
    @State private var investmentType = InvestmentType.contribution

    private var suggestions: [Payee] {
        let matches = PayeeMemory.matches(for: payee, in: payees)
        if matches.count == 1, PayeeMemory.normalized(matches[0].name) == PayeeMemory.normalized(payee) { return [] }
        return matches
    }

    @State private var limitMessage: String?
    @State private var receipt: Data?
    @State private var noReceipt = false

    /// The change this would make to the chosen account's balance. A payment is a charge on a card.
    private var accountChange: Decimal {
        let value = amount ?? 0
        if account?.supportsHoldings == true { return investmentType.isOutflow ? -value : value }
        return isPayment ? -value : value
    }

    private var exceedsLimit: Bool { account?.wouldExceedLimit(adding: accountChange) == true }

    private var canSave: Bool { (amount ?? 0) > 0 && account != nil }

    /// Investment accounts take a Type (contribution, gain, fee…) instead of a category and payment method.
    private var isInvestment: Bool { account?.supportsHoldings == true }

    var body: some View {
        Group {
            if choosableAccounts.isEmpty {
                ContentUnavailableView("No Accounts", systemImage: "building.columns", description: Text("Add an account in Settings ▸ Accounts first."))
            } else {
                form
            }
        }
        .onChange(of: isPayment) { _, new in
            if let category, category.isIncome == new { self.category = nil }
        }
        .alert("Exceeds Credit Limit", isPresented: Binding(get: { limitMessage != nil }, set: { if !$0 { limitMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(limitMessage ?? "")
        }
        .frame(width: 480, height: 700)
        .background(Theme.background)
        .onAppear {
            if account == nil {
                let opened = accounts.first { $0.id == accountID } ?? accounts.first
                account = Transfers.startingAccount(opening: opened, accounts: accounts)
            }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            Form {
                Section("Transaction") {
                    Picker("Account", selection: $account) {
                        ForEach(choosableAccounts) { account in if account.isLive { Text(account.name).tag(Optional(account)) } }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if isInvestment {
                        Picker("Type", selection: $investmentType) {
                            ForEach(InvestmentType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } else {
                        Picker("Type", selection: $isPayment) {
                            Text("Payment (money out)").tag(true)
                            Text("Deposit (money in)").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    CurrencyField("Amount", value: $amount)
                    if exceedsLimit, let account {
                        Label("This would reach the credit limit on \(account.name).", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Details") {
                    FormTextField(isInvestment ? "Description" : "Payee", text: $payee)
                    if !suggestions.isEmpty && !isInvestment {
                        HStack {
                            ForEach(suggestions) { suggestion in
                                Button(suggestion.name) { apply(suggestion) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                    if !isInvestment {
                        Picker("Category", selection: $category) {
                            CategoryOptions(categories: categories, only: isPayment ? .expense : .income, keeping: category)
                        }
                    }
                    if !isInvestment {
                        if let locked = account?.lockedPaymentType {
                            LabeledContent("Payment method") {
                                Label(locked.title, systemImage: "lock.fill").foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Payment method", selection: $paymentChoice) {
                                PaymentTypeOptions()
                            }
                            if paymentChoice?.isCheck == true {
                                FormTextField("Check number", text: $checkNumber)
                            }
                        }
                    }
                    FormTextField("Memo", text: $memo)
                    Picker("Status", selection: $state) {
                        ForEach(ReconcileState.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }

                if account?.supportsReceipts == true {
                    Section("Receipt") {
                        ReceiptPicker(data: $receipt, noReceipt: $noReceipt)
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
        if suggestion.lastAmount != 0 {
            amount = abs(suggestion.lastAmount)
            isPayment = suggestion.lastAmount < 0
        }
        // Only a category that fits the direction is filled in.
        let last = suggestion.lastCategory
        category = last?.isIncome == !isPayment ? last : nil
    }

    private func save(keepOpen: Bool) {
        guard let amount, let account else { return }
        if account.wouldExceedLimit(adding: accountChange) {
            limitMessage = account.limitMessage
            return
        }
        if account.supportsHoldings {
            let transaction = Transaction(
                account: account, date: date,
                payee: payee.isEmpty ? investmentType.title : payee,
                category: investmentType.category(in: categories), memo: memo,
                amount: investmentType.isOutflow ? -amount : amount
            )
            transaction.state = state
            transaction.receiptData = account.supportsReceipts ? receipt : nil
            transaction.noReceipt = account.supportsReceipts && receipt == nil && noReceipt
            modelContext.insert(transaction)
        } else {
            if let locked = account.lockedPaymentType {
                paymentChoice = .type(locked)
                checkNumber = ""
            }
            let signed = isPayment ? -amount : amount
            PayeeMemory.record(name: payee, category: category, amount: signed, in: modelContext)
            let transaction = Transaction(account: account, date: date, payee: payee, category: category, memo: memo, amount: signed)
            transaction.state = state
            transaction.paymentChoice = paymentChoice
            transaction.checkNumber = paymentChoice?.isCheck == true ? checkNumber : ""
            transaction.receiptData = account.supportsReceipts ? receipt : nil
            transaction.noReceipt = account.supportsReceipts && receipt == nil && noReceipt
            modelContext.insert(transaction)
        }

        modelContext.saveNow()

        if keepOpen {
            self.amount = nil
            payee = ""
            category = nil
            memo = ""
            state = .unreconciled
            checkNumber = ""
            receipt = nil
            noReceipt = false
        } else {
            dismiss()
        }
    }
}
#endif
