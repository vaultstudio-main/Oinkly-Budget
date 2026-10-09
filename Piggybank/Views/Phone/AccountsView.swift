#if os(iOS)
import SwiftUI
import SwiftData

struct AccountsView: View {
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live }

    @State private var editing: Account?

    var body: some View {
        NavigationStack {
            List {
                ForEach(AccountGroup.allCases) { group in
                    let members = accounts.filter { $0.type.group == group }
                    if !members.isEmpty {
                        Section(group.title) {
                            ForEach(members) { account in
                                if account.isLive {
                                NavigationLink(value: account) {
                                    HStack(spacing: 12) {
                                        CategoryBadge(symbol: account.type.symbol, color: .accentColor)
                                        Text(account.name).font(.headline)
                                        Spacer()
                                        Text(account.balance, format: .appCurrency)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(account.balance < 0 ? Color.red : Color.primary)
                                    }
                                }
                                .contextMenu {
                                    Button("Edit Details", systemImage: "pencil") { editing = account }
                                }
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if accounts.isEmpty {
                    ContentUnavailableView("No Accounts", systemImage: "wallet.pass", description: Text("Add accounts in Settings ▸ Accounts."))
                }
            }
            .navigationTitle("Accounts")
            .navigationDestination(for: Account.self) { PhoneAccountView(account: $0) }
            .sheet(item: $editing) { AccountEditView(account: $0) }
        }
    }
}

struct PhoneAccountView: View {
    let account: Account

    @Environment(\.modelContext) private var modelContext
    @State private var editing: Transaction?
    @State private var isAdding = false
    @State private var isEditingAccount = false
    @State private var showAccountNumber = false
    @State private var month = MonthFilter.start(of: .now)

    private var monthTransactions: [Transaction] {
        MonthFilter.transactions(account.transactions, in: month)
    }

    private var monthIn: Decimal { monthTransactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount } }
    private var monthOut: Decimal { monthTransactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount } }

    /// Loans show every payment; there is no month by month.
    private var shownTransactions: [Transaction] { account.isLoan ? account.transactions : monthTransactions }

    private var days: [(day: Date, items: [Transaction])] {
        let grouped = Dictionary(grouping: shownTransactions) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day, default: []].sorted { $0.createdAt > $1.createdAt })
        }
    }

    /// Original amount, monthly payment and how much has been paid off.
    @ViewBuilder
    private var loanSection: some View {
        let loan = account.loanProgress
        Section("Loan Progress") {
            if loan.hasOriginal {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: loan.fraction).tint(.green)
                    Text(loan.isPaidOff ? "Paid off" : "\(loan.fraction.formatted(.percent.precision(.fractionLength(0)))) paid off")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            LabeledContent("Original loan", value: loan.hasOriginal ? loan.original.formatted(.appCurrency) : "Not set")
            LabeledContent("Monthly payment", value: loan.monthlyPayment > 0 ? loan.monthlyPayment.formatted(.appCurrency) : "Not set")
            LabeledContent("Paid off so far") {
                Text(loan.hasOriginal ? loan.paidOff.formatted(.appCurrency) : "Not set")
                    .foregroundStyle(loan.hasOriginal ? Color.green : Color.secondary)
            }
            LabeledContent("Still owed") { Text(loan.owed, format: .appCurrency).foregroundStyle(.red) }
            if loan.isPaidOff {
                LabeledContent("Status") { Text("Paid off").foregroundStyle(.green) }
            } else {
                if let target = loan.targetDate {
                    LabeledContent("Payoff date", value: target.formatted(.dateTime.month(.abbreviated).day().year()))
                    if let months = loan.monthsToTarget() { LabeledContent("Months left", value: "\(months)") }
                    if let needed = loan.paymentNeeded() { LabeledContent("Needed per month", value: needed.formatted(.appCurrency)) }
                    switch loan.targetStatus() {
                    case .onTrack: LabeledContent("Your payment") { Label("On track", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    case .behind: LabeledContent("Your payment") { Label("Behind", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    case .pastDue: LabeledContent("Your payment") { Label("Past the date", systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red) }
                    case nil: EmptyView()
                    }
                } else if let count = loan.paymentsLeft, let date = loan.payoffDate() {
                    LabeledContent("Payments left", value: "About \(count)")
                    LabeledContent("Estimated payoff", value: date.formatted(.dateTime.month(.abbreviated).year()))
                }
            }
        }
    }

    var body: some View {
        // The account can be deleted from Settings while this page is still in the navigation stack.
        if account.isLive { content }
    }

    private var content: some View {
        List {
            if account.supportsPhoto, let photo = AccountPhoto.image(from: account.photoData) {
                Section {
                    photo
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                VStack(spacing: 4) {
                    Text(account.isLoan ? "Still owed" : "Balance").font(.subheadline).foregroundStyle(.secondary)
                    Text(account.isLoan ? account.loanProgress.owed : account.balance, format: .appCurrency)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(account.isLoan || account.balance < 0 ? Color.red : Color.primary)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: account.balance)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            if account.isLoan {
                loanSection
            } else {
                Section {
                    MonthSelector(month: $month, range: MonthFilter.range(for: account.transactions))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }

            Section("Details") {
                HStack {
                    Text("Kind")
                    Spacer()
                    Label(account.isDebt ? "Debt" : "Asset",
                          systemImage: account.isDebt ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill")
                        .foregroundStyle(account.isDebt ? Color.red : Color.green)
                }
                LabeledContent("Type", value: account.type.title)
                if account.supportsVIN {
                    LabeledContent("VIN", value: account.vin.isEmpty ? "Not set" : account.vin)
                }
                if account.isLoan {
                    LabeledContent("Loan for", value: account.loanPurpose.isEmpty ? "Not set" : account.loanPurpose)
                }
                if !account.institution.isEmpty {
                    LabeledContent("Institution", value: account.institution)
                }
                if !account.accountNumber.isEmpty {
                    LabeledContent("Account number") {
                        HStack {
                            Text(showAccountNumber ? account.accountNumber : account.maskedAccountNumber)
                                .monospacedDigit()
                            Button(showAccountNumber ? "Hide" : "Show") { showAccountNumber.toggle() }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
                    }
                }
                if !account.routingNumber.isEmpty {
                    LabeledContent("Routing number", value: account.routingNumber)
                }
                if !account.isLoan {
                    LabeledContent("Transactions (\(MonthFilter.shortLabel(month)))", value: "\(monthTransactions.count)")
                    LabeledContent("In / Out (\(MonthFilter.shortLabel(month)))") {
                        HStack(spacing: 4) {
                            Text(monthIn, format: .appCurrency).foregroundStyle(.green)
                            Text("/").foregroundStyle(.secondary)
                            Text(monthOut, format: .appCurrency).foregroundStyle(.red)
                        }
                    }
                }
                if !account.notes.isEmpty {
                    LabeledContent("Notes", value: account.notes)
                }
                Button("Edit Details") { isEditingAccount = true }
            }

            if days.isEmpty {
                Section {
                    Text(account.transactions.isEmpty ? "No transactions yet. Tap + to add one." : "No transactions in \(month.formatted(.dateTime.month(.wide).year())).")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(days, id: \.day) { day in
                Section(day.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(day.items) { transaction in
                        Button { editing = transaction } label: { TransactionRowView(transaction: transaction) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { Transfers.delete(transaction, in: modelContext); modelContext.saveNow() } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = transaction }
                                Button("Delete", systemImage: "trash", role: .destructive) { Transfers.delete(transaction, in: modelContext); modelContext.saveNow() }
                            }
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Transaction", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) { PhoneTransactionForm(transaction: nil, defaultAccount: account) }
        .sheet(isPresented: $isEditingAccount) { AccountEditView(account: account) }
        .sheet(item: $editing) { PhoneTransactionForm(transaction: $0) }
    }
}
#endif
