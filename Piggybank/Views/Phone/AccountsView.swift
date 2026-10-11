#if os(iOS)
import SwiftUI
import SwiftData

struct PhoneAccountView: View {
    let account: Account

    @Environment(\.modelContext) private var modelContext
    @State private var editing: Transaction?
    @State private var isAdding = false
    @State private var isPaying = false
    @State private var isCharging = false
    @State private var isWithdrawing = false
    @State private var isSpendingCash = false
    @State private var isEditingAccount = false
    @State private var showAccountNumber = false
    @State private var month = MonthFilter.start(of: .now)

    private var monthTransactions: [Transaction] {
        MonthFilter.transactions(account.transactions.live, in: month)
    }

    private var monthIn: Decimal { monthTransactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount } }
    private var monthOut: Decimal { monthTransactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount } }

    /// Loans show every payment; there is no month by month.
    private var shownTransactions: [Transaction] { account.isLoan ? account.transactions.live : monthTransactions }

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
        Section("\(account.financingWord) Progress") {
            if loan.hasOriginal {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: loan.fraction).tint(.green)
                    Text(loan.isPaidOff ? "Paid off" : "\(loan.fraction.formatted(.percent.precision(.fractionLength(0)))) paid off")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            LabeledContent(account.isLeased ? "Total lease cost" : "Original loan", value: loan.hasOriginal ? loan.original.formatted(.appCurrency) : "Not set")
            LabeledContent("Monthly payment", value: loan.monthlyPayment > 0 ? loan.monthlyPayment.formatted(.appCurrency) : "Not set")
            if !account.isLeased {
                LabeledContent("Interest rate") {
                    if account.interestRate > 0 {
                        Text("\(account.interestRate.formatted(.number.precision(.fractionLength(0...3))))%")
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
                }
            }
            if let bill = account.loanBill {
                LabeledContent("Payment due", value: LoanBill.dueText(bill))
                LabeledContent("This month's payment") { LoanPaymentStatus(account: account) }
            }
            if let start = account.loanStartDate {
                LabeledContent("\(account.financingWord) started", value: start.formatted(.dateTime.month(.abbreviated).day().year()))
            }
            LabeledContent("Paid off so far") {
                Text(loan.hasOriginal ? loan.paidOff.formatted(.appCurrency) : "Not set")
                    .foregroundStyle(loan.hasOriginal ? Color.green : Color.secondary)
            }
            LabeledContent("Still owed") { Text(loan.owed, format: .appCurrency).foregroundStyle(.red) }
            if loan.isPaidOff {
                LabeledContent("Status") { Text("Paid off").foregroundStyle(.green) }
            } else {
                if let target = loan.targetDate {
                    LabeledContent(account.isLeased ? "Lease end date" : "Maturity date", value: target.formatted(.dateTime.month(.abbreviated).day().year()))
                    if let count = LoanBill.paymentsToMaturity(account) { LabeledContent("Payments to maturity", value: "About \(count)") }
                    if let needed = loan.paymentNeeded() { LabeledContent("Needed per month", value: needed.formatted(.appCurrency)) }
                    switch loan.targetStatus() {
                    case .onTrack: LabeledContent("Your payment") { HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill"); Text("On track") }.fixedSize().foregroundStyle(.green) }
                    case .behind: LabeledContent("Your payment") { HStack(spacing: 6) { Image(systemName: "exclamationmark.triangle.fill"); Text("Behind") }.fixedSize().foregroundStyle(.orange) }
                    case .pastDue: LabeledContent("Your payment") { HStack(spacing: 6) { Image(systemName: "exclamationmark.octagon.fill"); Text("Past the date") }.fixedSize().foregroundStyle(.red) }
                    case nil: EmptyView()
                    }
                } else if let count = loan.paymentsLeft, let date = loan.payoffDate() {
                    LabeledContent("Payments left", value: "About \(count)")
                    LabeledContent(account.isLeased ? "Estimated lease end" : "Estimated payoff", value: date.formatted(.dateTime.month(.abbreviated).year()))
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
                    Text("Current balance").font(.subheadline).foregroundStyle(.secondary)
                    Text(account.balance, format: .appCurrency)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(account.balance < 0 ? Color.red : Color.primary)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: account.balance)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            if account.supportsHoldings { HoldingsSections(account: account) }

            if account.isLoan {
                loanSection
            } else {
                Section {
                    MonthSelector(month: $month, range: MonthFilter.range(for: account.transactions.live))
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
                LabeledContent("Type", value: account.typeTitle)
                if account.supportsVIN {
                    LabeledContent("VIN", value: account.vin.isEmpty ? "Not set" : account.vin)
                }
                if account.isLoan {
                    LabeledContent("\(account.financingWord) for", value: account.loanPurpose.isEmpty ? "Not set" : account.loanPurpose)
                }
                if !account.institution.isEmpty {
                    LabeledContent(account.isLoan ? account.lenderLabel : "Institution", value: account.institution)
                }
                if !account.accountNumber.isEmpty {
                    LabeledContent(account.numberLabel) {
                        HStack {
                            Text(showAccountNumber ? account.accountNumber : account.maskedAccountNumber)
                                .monospacedDigit()
                            Button(showAccountNumber ? "Hide" : "Show") { showAccountNumber.toggle() }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
                    }
                }
                if account.isCreditCard {
                    LabeledContent("Credit limit", value: account.creditLimit > 0 ? account.creditLimit.formatted(.appCurrency) : "Not set")
                    if account.creditLimit > 0 {
                        LabeledContent("Available credit", value: account.availableCredit.formatted(.appCurrency))
                    }
                    LabeledContent("Interest rate (APR)") {
                        if account.interestRate > 0 {
                            Text("\(account.interestRate.formatted(.number.precision(.fractionLength(0...3))))%")
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Minimum payment", value: account.monthlyPayment > 0 ? account.monthlyPayment.formatted(.appCurrency) : "Not set")
                    if let bill = account.loanBill {
                        LabeledContent("Payment due", value: LoanBill.dueText(bill))
                        LabeledContent("This month's payment") { LoanPaymentStatus(account: account) }
                    } else {
                        LabeledContent("Payment due", value: "Not set")
                    }
                }
                if !account.isLoan, !account.isCreditCard, !account.routingNumber.isEmpty {
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
                    Text(account.transactions.isEmpty ? (account.isLoan ? "No payments yet. Tap Make a Payment to add one." : "No transactions yet. Tap + to add one.") : "No transactions in \(month.formatted(.dateTime.month(.wide).year())).")
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
                if account.isCashOnHand {
                    // Cash on Hand takes cash transactions, and is filled by withdrawals.
                    Menu {
                        Button("New Cash Transaction", systemImage: "dollarsign.circle") { isSpendingCash = true }
                        Button("ATM Withdrawal", systemImage: "banknote") { isWithdrawing = true }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                } else if account.isLoan {
                    // A loan only takes payments, so the button is a payment.
                    Button("Make a Payment", systemImage: "creditcard") { isPaying = true }
                } else if account.isCreditCard {
                    Menu {
                        Button("New Credit Card Charge", systemImage: "plus") { isCharging = true }
                        Button("Make a Payment", systemImage: "creditcard") { isPaying = true }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                } else {
                    Button("Add Transaction", systemImage: "plus") { isAdding = true }
                }
            }
        }
        .sheet(isPresented: $isPaying) { BillPayWindow(initialDebt: account) }
        .sheet(isPresented: $isCharging) { CreditCardChargeView(initialCard: account) }
        .sheet(isPresented: $isWithdrawing) { AtmWithdrawalView() }
        .sheet(isPresented: $isSpendingCash) { CashTransactionView() }
        .sheet(isPresented: $isAdding) { PhoneTransactionForm(transaction: nil, defaultAccount: account) }
        .sheet(isPresented: $isEditingAccount) { AccountEditView(account: account) }
        .sheet(item: $editing) { if $0.isLive { PhoneTransactionForm(transaction: $0) } }
    }
}
#endif
