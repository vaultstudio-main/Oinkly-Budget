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
    @Query(sort: \Tag.name) private var allTags: [Tag]
    private var tags: [Tag] { allTags.live }
    @State private var selection = Set<PersistentIdentifier>()
    @State private var isEditingDetails = false
    @State private var confirmingDelete = false
    @State private var limitMessage: String?
    @State private var editingDate: Transaction?
    @State private var savingAs: ExportSheet.Kind?
    @State private var pendingImport: PendingImport?
    @State private var makingRecurring: Transaction?
    @Environment(\.openWindow) private var openWindow
    @State private var choosingMonth = false
    /// Narrowing the register to some statuses, or to transactions with or without a receipt. Chosen in Settings.
    @State private var filter = RegisterFilter()
    /// How far the page starts from the left edge of the window, so the month can sit in the middle of the whole window.
    @State private var leftInset: CGFloat = 0

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
            // The balance runs through every transaction, then the ones that don't match are left out, so it stays true.
            .filter { filter.matches($0.transaction) }
    }

    private func amountColor(_ amount: Decimal) -> Color {
        amount > 0 ? Theme.green : (amount < 0 ? Theme.red : .secondary)
    }

    private var header: some View {
        ZStack {
            // The month is only shown here, in the middle of the whole window, under the window's title. It is chosen in Settings.
            VStack(spacing: 2) {
                Text(account.isLoan ? "All Activity" : month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
                if filter.isActive {
                    Text("Showing: \(filter.summary)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .offset(x: -leftInset / 2)
            HStack(alignment: .firstTextBaseline) {
                Text(account.name).font(.largeTitle.bold())
                Spacer()
                Button("Settings", systemImage: "slider.horizontal.3") { choosingMonth = true }
                    .help(account.isLoan ? "Narrow this register to some statuses" : "Choose which month this register shows, and narrow it to some statuses or to transactions with or without a receipt")
                    .popover(isPresented: $choosingMonth, arrowEdge: .bottom) { settingsPopover }
                // Every button says what it does. Importing and exporting data are one pair; printing a statement is separate.
                Button("Import CSV", systemImage: "square.and.arrow.down") {
                    if let url = StatementFilePicker.choose() { pendingImport = PendingImport(url: url) }
                }
                .help("Import a bank statement saved as a CSV file into this account. PDF statements can't be imported.")
                Button("Export CSV", systemImage: "square.and.arrow.up") { savingAs = .csv }
                    .help("Save this account's transactions as a CSV spreadsheet")
                Button("Print PDF", systemImage: "printer") { savingAs = .pdf }
                    .help("Save this account's transactions as a PDF statement to read or print")
            }
        }
    }

    /// The bubble that opens from Settings: the month this register shows, and what to narrow it to. With none ticked in a group,
    /// everything in it shows.
    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Register Settings").font(.headline)
            if !account.isLoan {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Month").font(.subheadline.weight(.semibold))
                    MonthSelector(month: $month, range: MonthFilter.range(first: dateRange.first, last: dateRange.last))
                }
                Divider()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Status").font(.subheadline.weight(.semibold))
                ForEach(ReconcileState.allCases) { state in
                    Toggle(isOn: Binding(
                        get: { filter.states.contains(state) },
                        set: { on in if on { filter.states.insert(state) } else { filter.states.remove(state) } }
                    )) {
                        Label(state.title, systemImage: state.symbol).foregroundStyle(state.color)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            if account.supportsReceipts {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Receipts").font(.subheadline.weight(.semibold))
                    Toggle("With a receipt", isOn: $filter.withReceipt).toggleStyle(.checkbox)
                    Toggle("Without a receipt", isOn: $filter.withoutReceipt).toggleStyle(.checkbox)
                }
            }
            Divider()
            HStack {
                Text("Tick what to show. With nothing ticked in a group, all of it shows.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Clear") { filter = RegisterFilter() }.disabled(!filter.isActive)
            }
        }
        .padding(16)
        .frame(width: 330)
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
            if account.isCashOnHand {
                Button { openWindow(id: "cash-transaction") } label: {
                    Label("New Cash Transaction", systemImage: "plus.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .help("Record cash you spent or received")
            }
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
                        } else if let split = row.transaction.splitTitle {
                            Label(split, systemImage: "arrow.triangle.branch")
                                .help("Divided across several categories. Double-click to see the parts.")
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

                if !tags.isEmpty {
                    TableColumn("Tags") { row in
                        TagChips(transaction: row.transaction)
                    }
                    .width(min: 80, ideal: 150)
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
                    ContentUnavailableView("No Transactions", systemImage: "list.bullet.rectangle", description: Text(account.isCreditCard ? "Use File ▸ New Credit Card Charge to add a charge, or Pay a Bill to pay the card." : (account.isLoan ? "Use File ▸ Pay a Bill to make a payment." : (account.isCashOnHand ? "Use the New Cash Transaction button to record cash, or File ▸ ATM Withdrawal to put cash here." : "Use File ▸ New Transaction to add one."))))
                } else if rows.isEmpty && filter.isActive {
                    ContentUnavailableView("Nothing Matches", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("No transactions here match what is ticked in Settings. Open Settings and press Clear to see them all."))
                } else if rows.isEmpty {
                    ContentUnavailableView("No Transactions in \(month.formatted(.dateTime.month(.wide).year()))", systemImage: "calendar")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                if ids.count == 1, let id = ids.first, let transaction = monthTransactions.first(where: { $0.persistentModelID == id }) {
                    Button("View Details", systemImage: "doc.text.magnifyingglass") {
                        openWindow(id: "transaction-detail", value: TransactionDetailRequest(id: id))
                    }
                    Button("Edit Transaction", systemImage: "pencil") { editingDate = transaction }
                    if transaction.canSplit, transaction.recurring == nil {
                        Button("Make Recurring", systemImage: "arrow.triangle.2.circlepath") { makingRecurring = transaction }
                    }
                }
                if !ids.isEmpty, !tags.isEmpty {
                    let chosen = monthTransactions.filter { ids.contains($0.persistentModelID) }
                    Menu("Tags", systemImage: "tag") {
                        ForEach(tags) { tag in
                            let allHave = !chosen.isEmpty && chosen.allSatisfy { $0.tags.contains { $0 === tag } }
                            Button {
                                Tags.toggle(tag, on: chosen, in: modelContext)
                            } label: {
                                Label(tag.name, systemImage: allHave ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Delete Transaction" : "Delete \(ids.count) Transactions", role: .destructive) {
                        selection = ids
                        confirmingDelete = true
                    }
                }
            } primaryAction: { ids in
                // Double-click: a read-only close look in its own window. Nothing is changed by looking.
                if ids.count == 1, let id = ids.first {
                    openWindow(id: "transaction-detail", value: TransactionDetailRequest(id: id))
                }
            }
            .alternatingRowBackgrounds(.disabled)
            .onDeleteCommand(perform: requestDelete)
        }
        .padding(16)
        .background(Theme.background)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { leftInset = $0 }
        .statusBarText(account.isLoan
            ? "\(rows.count.formatted()) transaction\(rows.count == 1 ? "" : "s") · \(account.name)"
            : "\(rows.count.formatted()) transaction\(rows.count == 1 ? "" : "s") · \(month.formatted(.dateTime.month(.wide).year())) · \(account.name)")
        .focusedSceneValue(\.registerActions, registerActions)
        .sheet(isPresented: $isEditingDetails) { AccountEditView(account: account) }
        .sheet(item: $savingAs) { ExportSheet(account: account, kind: $0, startingMonth: month) }
        .sheet(item: $pendingImport) { ImportStatementSheet(account: account, fileURL: $0.url) }
        .sheet(item: $makingRecurring) { RecurringRuleEditor(rule: nil, source: $0) }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            guard let action = note.userInfo?["action"] as? String else { return }
            if action.hasPrefix("select:") {
                // "select:Payee" or "select:Payee|amount" to pick one of several with the same payee.
                let parts = String(action.dropFirst("select:".count)).split(separator: "|", maxSplits: 1).map(String.init)
                let wanted = parts.count > 1 ? Decimal(string: parts[1]) : nil
                if let match = monthTransactions.first(where: { $0.isLive && $0.payee == parts[0] && (wanted == nil || abs($0.amount) == abs(wanted!)) }) {
                    selection = [match.persistentModelID]
                }
                return
            }
            switch action {
            case "edit": if let chosen = selectedTransaction { editingDate = chosen }
            case "details": if let chosen = selectedTransaction { openWindow(id: "transaction-detail", value: TransactionDetailRequest(id: chosen.persistentModelID)) }
            case "makeRecurring": if let chosen = selectedTransaction { makingRecurring = chosen }
            case "export:pdf": savingAs = .pdf
            case "export:csv": savingAs = .csv
            case "import": pendingImport = PendingImport(url: ScreenshotMode.sampleStatement())
            case "editDetails": isEditingDetails = true
            case "newCash": if account.isCashOnHand { openWindow(id: "cash-transaction") }
            case "closeSheets": editingDate = nil; savingAs = nil; pendingImport = nil; makingRecurring = nil; isEditingDetails = false
            default: break
            }
        }
        #endif
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

    /// The one transaction selected, if exactly one is.
    private var selectedTransaction: Transaction? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return monthTransactions.first { $0.persistentModelID == id && $0.isLive }
    }

    /// What the menu bar's Transaction commands do here.
    private var registerActions: RegisterActions {
        let chosen = selectedTransaction
        return RegisterActions(
            hasSelection: chosen != nil,
            canMakeRecurring: chosen.map { $0.canSplit && $0.recurring == nil } ?? false,
            edit: { if let chosen { editingDate = chosen } },
            details: { if let chosen { openWindow(id: "transaction-detail", value: TransactionDetailRequest(id: chosen.persistentModelID)) } },
            makeRecurring: { if let chosen, chosen.canSplit, chosen.recurring == nil { makingRecurring = chosen } })
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

/// Right-click ▸ Edit Transaction… in the register. It has everything the New Transaction form has (account, date,
/// type, amount, payee, category, method, memo, status and receipt), so a transaction can be changed in every way it
/// could be entered. Only what is locked, such as a transfer's amount or an ATM withdrawal's details, stays fixed.
/// Nothing in the list itself can be bumped by accident.
struct EditTransactionSheet: View {
    let transaction: Transaction
    let account: Account
    let categories: [Category]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @Query(sort: \Payee.name) private var allPayees: [Payee]

    @State private var selectedAccount: Account
    @State private var date: Date
    @State private var isPayment: Bool
    @State private var amount: Decimal?
    @State private var payee: String
    @State private var category: Category?
    @State private var paymentChoice: PaymentChoice?
    @State private var checkNumber: String
    @State private var memo: String
    @State private var state: ReconcileState
    @State private var investmentType: InvestmentType
    @State private var receipt: Data?
    @State private var receiptCheck = ReceiptCheckState()
    @State private var noReceipt: Bool
    @State private var limitMessage: String?
    @State private var isSplitting: Bool
    @State private var parts: [SplitDraft]
    @State private var tagNames: [String]

    init(transaction: Transaction, account: Account, categories: [Category]) {
        self.transaction = transaction
        self.account = account
        self.categories = categories
        _selectedAccount = State(initialValue: account)
        _date = State(initialValue: transaction.date)
        _isPayment = State(initialValue: transaction.amount <= 0)
        _amount = State(initialValue: transaction.amount == 0 ? nil : abs(transaction.amount))
        _payee = State(initialValue: transaction.payee)
        _category = State(initialValue: transaction.category)
        _paymentChoice = State(initialValue: transaction.paymentChoice)
        _checkNumber = State(initialValue: transaction.checkNumber)
        _memo = State(initialValue: transaction.memo)
        _state = State(initialValue: transaction.state)
        _investmentType = State(initialValue: InvestmentType.of(transaction))
        _receipt = State(initialValue: transaction.receiptData)
        _noReceipt = State(initialValue: transaction.noReceipt)
        _isSplitting = State(initialValue: transaction.isSplit)
        _parts = State(initialValue: transaction.isSplit ? Splits.drafts(of: transaction) : [])
        _tagNames = State(initialValue: transaction.tagNames)
    }

    private var isInvestment: Bool { selectedAccount.supportsHoldings && !transaction.isTransfer }
    /// ATM withdrawals are always the same: payee, category, method, memo and status can't be changed.
    private var isAtm: Bool { transaction.isAtmWithdrawal }
    /// The deposit a goal made when it created this account. Its payee, category and method are locked.
    private var isOpening: Bool { transaction.isOpeningDeposit }
    private var amountIsLocked: Bool { transaction.isTransfer }
    private var payees: [Payee] { allPayees.live }

    /// Accounts this transaction can move to: the same ones New Transaction offers, of the same kind (an investment
    /// stays an investment). Transfers, ATM withdrawals and loan payments stay where they are.
    private var accountChoices: [Account] {
        guard !transaction.isTransfer, !isAtm, !account.isLoan else { return [] }
        let live = allAccounts.live
        return live.filter {
            $0.id == account.id
                || (!$0.isLoan && !$0.isCreditCard && !$0.isCashOnHand && $0.supportsHoldings == account.supportsHoldings)
        }
    }

    private var showsReceipt: Bool { selectedAccount.supportsReceipts && !transaction.receiptLocked }

    private var signedAmount: Decimal {
        if amountIsLocked { return transaction.amount }
        let value = amount ?? 0
        return isPayment ? -value : value
    }

    /// The change this would make to the balance of the account it ends up in.
    private var accountChange: Decimal {
        selectedAccount.id == account.id ? signedAmount - transaction.amount : signedAmount
    }

    private var exceedsLimit: Bool { !amountIsLocked && selectedAccount.wouldExceedLimit(adding: accountChange) }

    private var suggestions: [Payee] {
        let matches = PayeeMemory.matches(for: payee, in: payees)
        if matches.count == 1, PayeeMemory.normalized(matches[0].name) == PayeeMemory.normalized(payee) { return [] }
        return matches
    }

    private var canSave: Bool {
        if amountIsLocked { return true }
        guard (amount ?? 0) > 0 else { return false }
        return !isSplitting || Splits.isValid(parts, total: amount ?? 0)
    }

    /// Only an ordinary payment or deposit can be divided across categories.
    private var offersSplit: Bool { !amountIsLocked && !isInvestment && transaction.canSplit }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
            Form {
                Section("Transaction") {
                    if accountChoices.count > 1 {
                        Picker("Account", selection: $selectedAccount) {
                            ForEach(accountChoices) { Text($0.name).tag($0) }
                        }
                    } else {
                        LabeledContent("Account") {
                            Label(account.name, systemImage: "lock.fill").foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if isInvestment {
                        Picker("Type", selection: $investmentType) {
                            ForEach(InvestmentType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } else if !amountIsLocked {
                        Picker("Type", selection: $isPayment) {
                            Text("Payment (money out)").tag(true)
                            Text("Deposit (money in)").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    if amountIsLocked {
                        LabeledContent("Amount") {
                            Text(transaction.amount, format: .appCurrency).foregroundStyle(.secondary)
                        }
                    } else {
                        CurrencyField("Amount", value: $amount)
                    }
                    if exceedsLimit {
                        Label("This would reach the credit limit on \(selectedAccount.name).", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if amountIsLocked {
                        Text("Part of a transfer or payment, so the amount is shared with the other account and the matching entry moves with the date. Delete it and enter it again to change the amount.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Details") {
                    if isAtm || isOpening {
                        LabeledContent("Payee") {
                            Label(payee, systemImage: "lock.fill").foregroundStyle(.secondary)
                        }
                    } else {
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
                    }

                    if isInvestment {
                        EmptyView()
                    } else if let fixed = transaction.fixedCategoryTitle {
                        LabeledContent("Category") {
                            Label(fixed, systemImage: "lock.fill").foregroundStyle(.secondary)
                        }
                    } else {
                        if !isSplitting {
                            Picker("Category", selection: $category) {
                                CategoryOptions(categories: categories, only: isPayment ? .expense : .income, keeping: category)
                            }
                        }
                        if offersSplit { Toggle("Split across categories", isOn: $isSplitting) }
                    }

                    if !selectedAccount.supportsHoldings {
                        if isAtm || isOpening {
                            LabeledContent("Payment method") {
                                Label(transaction.paymentTitle, systemImage: "lock.fill").foregroundStyle(.secondary)
                            }
                        } else if let locked = selectedAccount.lockedPaymentType, !transaction.isTransfer {
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
                        LabeledContent("Status") {
                            Label(ReconcileState.reconciled.title, systemImage: "lock.fill").foregroundStyle(ReconcileState.reconciled.color)
                        }
                    } else {
                        FormTextField("Memo", text: $memo)
                        TagField(names: $tagNames)
                        Picker("Status", selection: $state) {
                            ForEach(ReconcileState.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    }
                }

                if isSplitting && offersSplit {
                    Section("Split") {
                        SplitEditor(parts: $parts, total: amount ?? 0, categories: categories, isPayment: isPayment)
                    }
                }

            }
            .formStyle(.grouped)
            Divider()
            // The receipt beside the form, as in a new transaction, so neither has to scroll.
            ReceiptColumn(supported: showsReceipt, data: $receipt, noReceipt: $noReceipt,
                          checking: ReceiptChecking(state: receiptCheck, amount: $amount, date: $date, payee: $payee))
            }

            if let limitMessage {
                Text(limitMessage).font(.callout).foregroundStyle(.orange).padding(.horizontal, 16)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .screenFitted(width: 1000, height: 700 + (isSplitting ? CGFloat(max(parts.count, 2)) * 70 + 40 : 0))
        .background(Theme.background)
        .onChange(of: isPayment) { _, new in
            if let category, category.isIncome == new { self.category = nil }
            for index in parts.indices where parts[index].category?.isIncome == new { parts[index].category = nil }
        }
        .onChange(of: isSplitting) { _, on in
            if on {
                parts = Splits.starting(category: category, total: amount)
            } else {
                category = parts.first?.category ?? category
                parts = []
            }
        }
        .onChange(of: selectedAccount) { limitMessage = nil }
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

    private func save() {
        receiptCheck.learn(payee: payee, receipt: receipt)
        guard transaction.isLive else { dismiss(); return }
        if !amountIsLocked, selectedAccount.wouldExceedLimit(adding: accountChange) {
            limitMessage = selectedAccount.limitMessage
            return
        }
        let moved = selectedAccount.id != account.id
        if moved { transaction.account = selectedAccount }
        transaction.date = date
        if showsReceipt {
            transaction.receiptData = receipt
            transaction.noReceipt = receipt == nil && noReceipt
        } else if moved {
            // The new account doesn't keep receipts.
            transaction.receiptData = nil
            transaction.noReceipt = false
        }
        if !isAtm {
            if !isOpening { transaction.payee = payee }
            transaction.memo = memo
            transaction.state = state
        }
        if isInvestment {
            // The type sets the sign and the category, so the size typed is what counts.
            if !amountIsLocked { transaction.amount = abs(amount ?? 0) }
            investmentType.apply(to: transaction, categories: categories)
        } else {
            if transaction.fixedCategoryTitle == nil {
                if isSplitting && offersSplit {
                    Splits.apply(parts, to: transaction, isPayment: isPayment, in: modelContext)
                } else {
                    Splits.removeAll(from: transaction, in: modelContext)
                    transaction.category = category
                }
            }
            if isAtm || isOpening {
                // Method stays as recorded.
            } else if let locked = selectedAccount.lockedPaymentType, !transaction.isTransfer {
                transaction.paymentChoice = .type(locked)
                transaction.checkNumber = ""
            } else {
                transaction.paymentChoice = paymentChoice
                transaction.checkNumber = paymentChoice?.isCheck == true ? checkNumber : ""
            }
            if !amountIsLocked { transaction.amount = signedAmount }
            if !isAtm, !isOpening, !transaction.isTransfer { PayeeMemory.record(name: payee, category: isSplitting ? nil : category, amount: signedAmount, in: modelContext) }
        }
        Tags.apply(tagNames, to: transaction, in: modelContext)
        if transaction.isTransfer { Transfers.syncPeer(of: transaction, in: modelContext) }
        modelContext.saveNow()
        dismiss()
    }
}
