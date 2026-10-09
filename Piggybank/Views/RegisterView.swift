import SwiftUI
import SwiftData

private struct RegisterRow: Identifiable {
    let transaction: Transaction
    let balance: Decimal
    var id: PersistentIdentifier { transaction.persistentModelID }
}

struct RegisterView: View {
    let account: Account

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var allCategories: [Category]
    private var categories: [Category] { allCategories.live }
    @State private var selection = Set<PersistentIdentifier>()
    @State private var isEditingDetails = false
    @State private var confirmingDelete = false
    @State private var month = MonthFilter.start(of: .now)

    /// The running balance counts every transaction, so it stays correct when only one month is shown.
    private var rows: [RegisterRow] {
        var balance = account.openingBalance
        return account.transactions
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
            .map { transaction in
                balance += transaction.amount
                return RegisterRow(transaction: transaction, balance: balance)
            }
            .filter { account.isLoan || MonthFilter.contains(month, $0.transaction.date) }
    }

    private func amountColor(_ amount: Decimal) -> Color {
        amount > 0 ? Theme.green : (amount < 0 ? Theme.red : .secondary)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(account.name).font(.largeTitle.bold())
            Spacer()
            if !account.isLoan {
                MonthSelector(month: $month, range: MonthFilter.range(for: account.transactions))
                Spacer()
            }
            Text(account.isLoan ? "STILL OWED" : "CURRENT BALANCE").font(.caption).foregroundStyle(.secondary)
            Text(account.isLoan ? account.loanProgress.owed : account.balance, format: .appCurrency)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(account.isLoan ? Theme.red : (account.balance < 0 ? Theme.red : .primary))
        }
    }

    var body: some View {
        // The account can be deleted from Settings while its register is still on screen.
        if account.isLive { content }
    }

    private var content: some View {
        // Work these out once per redraw. Doing it inside every row and every check made big registers crawl.
        let rows = rows
        let categoryOptions = categories.expensesFirst
        return VStack(spacing: 12) {
            header
            AccountDetailsPanel(account: account, month: month) { isEditingDetails = true }
            Table(rows, selection: $selection) {
                TableColumn("Date") { row in
                    DatePicker("", selection: Bindable(row.transaction).date, displayedComponents: .date)
                        .labelsHidden()
                }
                .width(min: 110, ideal: 120)

                TableColumn("Payee") { row in
                    TextField("", text: Bindable(row.transaction).payee)
                }

                TableColumn("Category") { row in
                    Picker("", selection: Bindable(row.transaction).category) {
                        Text("None").tag(Category?.none)
                        ForEach(categoryOptions) { Text($0.name).tag(Optional($0)) }
                    }
                    .labelsHidden()
                }

                TableColumn("Method") { row in
                    Picker("", selection: Bindable(row.transaction).paymentType) {
                        PaymentTypeOptions()
                    }
                    .labelsHidden()
                }
                .width(min: 110, ideal: 130)

                TableColumn("Memo") { row in
                    TextField("", text: Bindable(row.transaction).memo)
                }

                TableColumn("Amount") { row in
                    if row.transaction.isTransfer {
                        Text(row.transaction.amount, format: .appCurrency)
                            .foregroundStyle(amountColor(row.transaction.amount))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .help("Part of a transfer, so the amount is shared with the other account. Delete it and enter it again to change it.")
                    } else {
                        TextField("", value: Bindable(row.transaction).amount, format: .appCurrency)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(amountColor(row.transaction.amount))
                            .help("Positive for deposits, negative for payments")
                    }
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
            }
            .overlay {
                if account.transactions.isEmpty {
                    ContentUnavailableView("No Transactions", systemImage: "list.bullet.rectangle", description: Text("Use File ▸ New Transaction to add one."))
                } else if rows.isEmpty {
                    ContentUnavailableView("No Transactions in \(month.formatted(.dateTime.month(.wide).year()))", systemImage: "calendar")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Delete Transaction…" : "Delete \(ids.count) Transactions…", role: .destructive) {
                        selection = ids
                        confirmingDelete = true
                    }
                }
            }
            #if os(macOS)
            .alternatingRowBackgrounds(.disabled)
            .onDeleteCommand(perform: requestDelete)
            #endif
        }
        .padding(16)
        .background(Theme.background)
        .sheet(isPresented: $isEditingDetails) { AccountEditView(account: account) }
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
        .toolbar {
            ToolbarItem {
                Button("Delete", systemImage: "trash", action: requestDelete)
                    .disabled(selection.isEmpty)
                    .help("Delete the selected transactions (or right-click a row)")
            }
        }
    }

    private func requestDelete() {
        if !selection.isEmpty { confirmingDelete = true }
    }

    private func deleteSelected() {
        for transaction in account.transactions where selection.contains(transaction.persistentModelID) {
            Transfers.delete(transaction, in: modelContext)
        }
        selection.removeAll()
        modelContext.saveNow()
    }
}
