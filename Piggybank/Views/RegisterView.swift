import SwiftUI
import SwiftData

private struct RegisterRow: Identifiable {
    let transaction: Transaction
    let balance: Decimal
    var id: PersistentIdentifier { transaction.persistentModelID }
}

/// The register for one account. It owns the month being looked at; the table itself loads only that month.
struct RegisterView: View {
    let account: Account

    @State private var month = MonthFilter.start(of: .now)

    var body: some View {
        // The account can be deleted from Settings while its register is still on screen.
        if account.isLive { RegisterContent(account: account, month: $month) }
    }
}

private struct RegisterContent: View {
    let account: Account
    @Binding var month: Date

    @Environment(\.modelContext) private var modelContext
    @Query private var monthTransactions: [Transaction]
    @Query(sort: \Category.name) private var allCategories: [Category]
    private var categories: [Category] { allCategories.live }
    @State private var selection = Set<PersistentIdentifier>()
    @State private var isEditingDetails = false
    @State private var confirmingDelete = false
    @State private var limitMessage: String?
    @State private var editingDate: Transaction?

    init(account: Account, month: Binding<Date>) {
        self.account = account
        _month = month
        let id = account.persistentModelID
        let start = month.wrappedValue
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        if account.isLoan {
            // A loan shows its whole history, which is short.
            _monthTransactions = Query(filter: #Predicate<Transaction> { $0.account?.persistentModelID == id })
        } else {
            _monthTransactions = Query(filter: #Predicate<Transaction> {
                $0.account?.persistentModelID == id && $0.date >= start && $0.date < end
            })
        }
    }

    /// The running balance counts every transaction before the month too, so it stays correct when only one month is
    /// shown: it starts from the balance at the start of the month.
    private var rows: [RegisterRow] {
        var balance = account.isLoan ? account.openingBalance : account.balance(asOf: month.addingTimeInterval(-0.001))
        return monthTransactions.filter(\.isLive)
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
            .map { transaction in
                balance += transaction.amount
                return RegisterRow(transaction: transaction, balance: balance)
            }
    }

    private func amountColor(_ amount: Decimal) -> Color {
        amount > 0 ? Theme.green : (amount < 0 ? Theme.red : .secondary)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(account.name).font(.largeTitle.bold())
            Spacer()
            if !account.isLoan {
                MonthSelector(month: $month, range: MonthFilter.range(first: dateRange.first, last: dateRange.last))
                Spacer()
            }
        }
    }

    private var dateRange: (first: Date?, last: Date?) { modelContext.transactionDateRange(of: account) }

    var body: some View {
        if account.isLive { content }
    }

    private var content: some View {
        // Work these out once per redraw. Doing it inside every row and every check made big registers crawl.
        let rows = rows
        let hasAny = modelContext.transactionCount(of: account) > 0
        return VStack(spacing: 12) {
            header
            AccountDetailsPanel(account: account, month: month) { isEditingDetails = true }
            if account.supportsHoldings { HoldingsPanel(account: account) }
            Table(rows, selection: $selection) {
                // Read-only here, so a stray click can't move a transaction to another day.
                // Right-click a transaction and choose Edit Transaction… to change the date.
                TableColumn("Date") { row in
                    Text(row.transaction.date, format: .dateTime.month(.abbreviated).day().year())
                        .monospacedDigit()
                }
                .width(min: 110, ideal: 120)

                // Everything below is read-only in the register. Right-click ▸ Edit Transaction… changes it, so
                // a click or a scroll-wheel can't alter a transaction by accident.
                TableColumn(account.supportsHoldings ? "Description" : "Payee") { row in
                    Text(row.transaction.payee)
                }

                if account.supportsHoldings {
                    TableColumn("Type") { row in
                        if row.transaction.isTransfer {
                            Label(InvestmentType.of(row.transaction).title, systemImage: "arrow.left.arrow.right")
                                .foregroundStyle(.secondary)
                        } else {
                            Label(InvestmentType.of(row.transaction).title, systemImage: InvestmentType.of(row.transaction).symbol)
                        }
                    }
                    .width(min: 150, ideal: 170)
                } else {
                    TableColumn("Category") { row in
                        if let fixed = row.transaction.fixedCategoryTitle {
                            Label(fixed, systemImage: "lock.fill")
                                .foregroundStyle(.secondary)
                                .help("Payments and transfers always use this category, and it can't be changed.")
                        } else {
                            Text(row.transaction.category?.name ?? "")
                        }
                    }

                    TableColumn("Method") { row in
                        if let locked = account.lockedPaymentType, !row.transaction.isTransfer {
                            // Charges on a card are always credit card charges, and cash on hand is always cash.
                            Label(locked.title, systemImage: "lock.fill").foregroundStyle(.secondary)
                        } else {
                            Text(row.transaction.paymentTitle)
                        }
                    }
                    .width(min: 110, ideal: 130)
                }

                TableColumn("Memo") { row in
                    Text(row.transaction.memo)
                }

                TableColumn("Amount") { row in
                    Text(row.transaction.amount, format: .appCurrency)
                        .foregroundStyle(amountColor(row.transaction.amount))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(row.transaction.isTransfer
                              ? "Part of a transfer, so the amount is shared with the other account. Delete it and enter it again to change it."
                              : "Positive for deposits, negative for payments")
                }
                .width(min: 100, ideal: 120)

                TableColumn("Status") { row in
                    ReconcileMenu(transaction: row.transaction)
                }
                .width(min: 120, ideal: 130)

                TableColumn("Balance") { row in
                    Text(row.balance, format: .appCurrency)
                        .foregroundStyle(row.balance < 0 ? Theme.red : .primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 90, ideal: 110)

                if account.supportsReceipts {
                    TableColumn("Receipt") { row in
                        ReceiptButton(transaction: row.transaction)
                    }
                    .width(min: 100, ideal: 110)
                }
            }
            .overlay {
                if !hasAny {
                    ContentUnavailableView("No Transactions", systemImage: "list.bullet.rectangle", description: Text(account.isCreditCard ? "Use File ▸ New Credit Card Charge to add a charge, or Pay a Bill to pay the card." : (account.isLoan ? "Use File ▸ Pay a Bill to make a payment." : (account.isCashOnHand ? "Use File ▸ New Cash Transaction to record cash, or ATM Withdrawal to put cash here." : "Use File ▸ New Transaction to add one."))))
                } else if rows.isEmpty {
                    ContentUnavailableView("No Transactions in \(month.formatted(.dateTime.month(.wide).year()))", systemImage: "calendar")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                if ids.count == 1, let id = ids.first, let transaction = monthTransactions.first(where: { $0.persistentModelID == id }) {
                    Button("Edit Transaction…", systemImage: "pencil") { editingDate = transaction }
                }
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Delete Transaction…" : "Delete \(ids.count) Transactions…", role: .destructive) {
                        selection = ids
                        confirmingDelete = true
                    }
                }
            }
            .alternatingRowBackgrounds(.disabled)
            .onDeleteCommand(perform: requestDelete)
        }
        .padding(16)
        .background(Theme.background)
        .sheet(isPresented: $isEditingDetails) { AccountEditView(account: account) }
        .sheet(item: $editingDate) { transaction in
            if transaction.isLive { EditTransactionSheet(transaction: transaction, account: account, categories: categories) }
        }
        .alert("Exceeds Credit Limit", isPresented: Binding(get: { limitMessage != nil }, set: { if !$0 { limitMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(limitMessage ?? "")
        }
        .confirmationDialog(
            selection.count == 1 ? "Delete this transaction?" : "Delete \(selection.count) transactions?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func requestDelete() {
        if !selection.isEmpty { confirmingDelete = true }
    }

    private func deleteSelected() {
        for transaction in monthTransactions.filter(\.isLive) where selection.contains(transaction.persistentModelID) {
            Transfers.delete(transaction, in: modelContext)
        }
        selection.removeAll()
        modelContext.saveNow()
    }
}

/// Right-click ▸ Edit Transaction… in the register. Everything about a transaction is changed here, so nothing can be
/// bumped by accident in the list itself.
private struct EditTransactionSheet: View {
    let transaction: Transaction
    let account: Account
    let categories: [Category]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var payee: String
    @State private var category: Category?
    @State private var paymentChoice: PaymentChoice?
    @State private var checkNumber: String
    @State private var memo: String
    @State private var amount: Decimal
    @State private var investmentType: InvestmentType
    @State private var limitMessage: String?

    init(transaction: Transaction, account: Account, categories: [Category]) {
        self.transaction = transaction
        self.account = account
        self.categories = categories
        _date = State(initialValue: transaction.date)
        _payee = State(initialValue: transaction.payee)
        _category = State(initialValue: transaction.category)
        _paymentChoice = State(initialValue: transaction.paymentChoice)
        _checkNumber = State(initialValue: transaction.checkNumber)
        _memo = State(initialValue: transaction.memo)
        _amount = State(initialValue: transaction.amount)
        _investmentType = State(initialValue: InvestmentType.of(transaction))
    }

    private var isInvestment: Bool { account.supportsHoldings && !transaction.isTransfer }
    /// ATM withdrawals are always the same: payee, category, method and memo can't be changed.
    private var isAtm: Bool { transaction.isAtmWithdrawal }
    private var amountIsLocked: Bool { transaction.isTransfer }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if isAtm {
                        LabeledContent("Payee") {
                            Label(payee, systemImage: "lock.fill").foregroundStyle(.secondary)
                        }
                    } else {
                        FormTextField(account.supportsHoldings ? "Description" : "Payee", text: $payee)
                    }

                    if isInvestment {
                        Picker("Type", selection: $investmentType) {
                            ForEach(InvestmentType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } else if let fixed = transaction.fixedCategoryTitle {
                        LabeledContent("Category") {
                            Label(fixed, systemImage: "lock.fill").foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Category", selection: $category) {
                            CategoryOptions(
                                categories: categories,
                                only: amount > 0 ? .income : (amount < 0 ? .expense : nil),
                                keeping: category
                            )
                        }
                    }

                    if !account.supportsHoldings {
                        if isAtm {
                            LabeledContent("Payment method") {
                                Label(transaction.paymentTitle, systemImage: "lock.fill").foregroundStyle(.secondary)
                            }
                        } else if let locked = account.lockedPaymentType, !transaction.isTransfer {
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

                    if isAtm {
                        LabeledContent("Memo") {
                            Label(memo, systemImage: "lock.fill").foregroundStyle(.secondary)
                        }
                    } else {
                        FormTextField("Memo", text: $memo)
                    }

                    if amountIsLocked {
                        LabeledContent("Amount") {
                            Text(amount, format: .appCurrency).foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("Amount") {
                            CurrencyField("Amount", amount: $amount)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Edit Transaction")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if amountIsLocked {
                            Text("Part of a transfer or payment, so the amount is shared with the other account and the matching entry moves with the date. Delete it and enter it again to change the amount.")
                        } else {
                            Text("Amounts are positive for deposits and negative for payments.")
                        }
                        if let limitMessage { Text(limitMessage).foregroundStyle(.orange) }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 520)
    }

    private func save() {
        guard transaction.isLive else { dismiss(); return }
        if !amountIsLocked, account.wouldExceedLimit(adding: amount - transaction.amount) {
            limitMessage = account.limitMessage
            return
        }
        transaction.date = date
        if !isAtm {
            transaction.payee = payee
            transaction.memo = memo
        }
        if isInvestment {
            // The type sets the sign and the category, so the size typed is what counts.
            if !amountIsLocked { transaction.amount = abs(amount) }
            investmentType.apply(to: transaction, categories: categories)
        } else {
            if transaction.fixedCategoryTitle == nil { transaction.category = category }
            if isAtm {
                // Method stays as recorded.
            } else if let locked = account.lockedPaymentType, !transaction.isTransfer {
                transaction.paymentChoice = .type(locked)
                transaction.checkNumber = ""
            } else {
                transaction.paymentChoice = paymentChoice
                transaction.checkNumber = paymentChoice?.isCheck == true ? checkNumber : ""
            }
            if !amountIsLocked { transaction.amount = amount }
        }
        if transaction.isTransfer { Transfers.syncPeer(of: transaction, in: modelContext) }
        modelContext.saveNow()
        dismiss()
    }
}
