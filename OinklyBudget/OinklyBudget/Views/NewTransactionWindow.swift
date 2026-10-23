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
    @State private var isSplitting = false
    @State private var tagNames: [String] = []
    @State private var parts: [SplitDraft] = []

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

    private var canSave: Bool {
        guard (amount ?? 0) > 0, account != nil else { return false }
        return !isSplitting || Splits.isValid(parts, total: amount ?? 0)
    }

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
            // The parts' categories have to fit the new direction too.
            for index in parts.indices where parts[index].category?.isIncome == new { parts[index].category = nil }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            guard let action = note.userInfo?["action"] as? String else { return }
            if action == "splitOn" { isSplitting = true }
            if action == "splitDemo" {
                amount = 120
                payee = "Big Box Store"
                isSplitting = true
                func cat(_ name: String) -> Category? { categories.first { $0.name == name } }
                // Turning the split on starts it with two empty parts, so fill them in a moment later.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    parts = [SplitDraft(category: cat("Groceries"), amount: 70), SplitDraft(category: cat("Shopping"), amount: 30), SplitDraft(category: cat("Pets"), amount: 20)]
                }
            }
            if action.hasPrefix("payee:") { payee = String(action.dropFirst("payee:".count)) }
            if action.hasPrefix("account:"), let match = accounts.first(where: { $0.name == String(action.dropFirst("account:".count)) }) { account = match }
        }
        #endif
        .onChange(of: isSplitting) { _, on in
            if on {
                parts = Splits.starting(category: category, total: amount)
            } else {
                category = parts.first?.category ?? category
                parts = []
            }
        }
        // Typing a payee you've used before fills in the rest the way you left it, as long as nothing else is filled in yet.
        .onChange(of: payee) { _, new in
            guard !isInvestment, amount == nil, category == nil, let known = PayeeMemory.exactMatch(for: new, in: payees) else { return }
            apply(known)
        }
        .alert("Exceeds Credit Limit", isPresented: Binding(get: { limitMessage != nil }, set: { if !$0 { limitMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(limitMessage ?? "")
        }
        .transactionWindowFrame()
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
            HStack(alignment: .top, spacing: 0) {
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
                        Label("This would go over the credit limit on \(account.name).", systemImage: "exclamationmark.triangle.fill")
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
                        if !isSplitting {
                            Picker("Category", selection: $category) {
                                CategoryOptions(categories: categories, only: isPayment ? .expense : .income, keeping: category)
                            }
                        }
                        Toggle("Split across categories", isOn: $isSplitting)
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
                    TagField(names: $tagNames)
                    Picker("Status", selection: $state) {
                        ForEach(ReconcileState.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }

                if isSplitting && !isInvestment {
                    Section("Split") {
                        SplitEditor(parts: $parts, total: amount ?? 0, categories: categories, isPayment: isPayment)
                    }
                }

            }
            .formStyle(.grouped)
            Divider()
            ReceiptColumn(supported: account?.supportsReceipts == true, data: $receipt, noReceipt: $noReceipt)
            }

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
        // The memo and payment method from the last time, unless already filled in or locked by the account.
        if memo.isEmpty, !suggestion.lastMemo.isEmpty { memo = suggestion.lastMemo }
        if paymentChoice == nil, account?.lockedPaymentType == nil, let type = PayeeMemory.builtInMethod(suggestion.lastMethodRaw) {
            paymentChoice = .type(type)
        } else if memo.isEmpty || (paymentChoice == nil && account?.lockedPaymentType == nil),
                  let previous = PayeeMemory.lastTransaction(for: suggestion.name, in: modelContext) {
            // Older entries (and your own methods) are found from the last transaction instead.
            if memo.isEmpty { memo = previous.memo }
            if paymentChoice == nil, account?.lockedPaymentType == nil { paymentChoice = previous.paymentChoice }
        }
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
            Tags.apply(tagNames, to: transaction, in: modelContext)
        } else {
            if let locked = account.lockedPaymentType {
                paymentChoice = .type(locked)
                checkNumber = ""
            }
            let signed = isPayment ? -amount : amount
            PayeeMemory.record(name: payee, category: category, amount: signed, memo: memo, method: paymentChoice, in: modelContext)
            let transaction = Transaction(account: account, date: date, payee: payee, category: isSplitting ? nil : category, memo: memo, amount: signed)
            transaction.state = state
            transaction.paymentChoice = paymentChoice
            transaction.checkNumber = paymentChoice?.isCheck == true ? checkNumber : ""
            transaction.receiptData = account.supportsReceipts ? receipt : nil
            transaction.noReceipt = account.supportsReceipts && receipt == nil && noReceipt
            modelContext.insert(transaction)
            if isSplitting { Splits.apply(parts, to: transaction, isPayment: isPayment, in: modelContext) }
            Tags.apply(tagNames, to: transaction, in: modelContext)
        }

        modelContext.saveNow()

        if keepOpen {
            self.amount = nil
            payee = ""
            category = nil
            isSplitting = false
            parts = []
            tagNames = []
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
