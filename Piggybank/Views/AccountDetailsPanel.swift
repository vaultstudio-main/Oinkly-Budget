import SwiftUI

/// Account facts shown above the register: kind, bank details and this month's activity.
struct AccountDetailsPanel: View {
    let account: Account
    let month: Date
    let onEdit: () -> Void

    @State private var showAccountNumber = false

    private var monthTransactions: [Transaction] {
        MonthFilter.transactions(account.transactions.live, in: month)
    }

    /// Opening balance plus everything already matched to a statement.
    private var reconciledBalance: Decimal {
        account.transactions.live.filter(\.isReconciled).reduce(account.openingBalance) { $0 + $1.amount }
    }

    private var unreconciled: some View {
        let open = account.transactions.live.filter { $0.state == .unreconciled }
        let total = open.reduce(Decimal(0)) { $0 + $1.amount }
        return HStack(spacing: 4) {
            Text("\(open.count) transaction\(open.count == 1 ? "" : "s")")
            Text("·").foregroundStyle(.secondary)
            Text(total, format: .appCurrency).foregroundStyle(open.isEmpty ? Color.secondary : (total < 0 ? Theme.red : Theme.green))
        }
    }

    private var pendingSummary: some View {
        let pending = account.transactions.live.filter { $0.state == .pending }
        let total = pending.reduce(Decimal(0)) { $0 + $1.amount }
        return HStack(spacing: 4) {
            Text("\(pending.count) transaction\(pending.count == 1 ? "" : "s")")
            Text("·").foregroundStyle(.secondary)
            Text(total, format: .appCurrency).foregroundStyle(pending.isEmpty ? Color.secondary : .orange)
        }
    }

    private var monthLabel: String { MonthFilter.shortLabel(month) }

    var body: some View {
        if account.isLive { content }
    }

    @ViewBuilder
    private var content: some View {
        if account.isLoan { loanContent } else { accountContent }
    }

    // MARK: Loans: no month by month, just how far along the loan is

    private var loanContent: some View {
        let loan = account.loanProgress
        return Panel(title: "\(account.financingWord) Details") {
            HStack(alignment: .top, spacing: 20) {
                if let photo = AccountPhoto.image(from: account.photoData) {
                    photo
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 14) {
                    Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                        GridRow {
                            item("Type") { Text(account.typeTitle) }
                            item("\(account.financingWord) For") { text(account.loanPurpose) }
                            if account.supportsVIN { item("VIN") { text(account.vin) } }
                            item(account.lenderLabel) { text(account.institution) }
                        }
                        GridRow {
                            item(account.isLeased ? "Total Lease Cost" : "Original Loan") { amount(loan.original, set: loan.hasOriginal) }
                            item("Monthly Payment") { amount(loan.monthlyPayment, set: loan.monthlyPayment > 0) }
                            item("Paid Off So Far") {
                                if loan.hasOriginal {
                                    HStack(spacing: 6) {
                                        Text(loan.paidOff, format: .appCurrency).foregroundStyle(Theme.green)
                                        Text(loan.fraction, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary)
                                    }
                                } else {
                                    text("")
                                }
                            }
                            item("Still Owed") { Text(loan.owed, format: .appCurrency).foregroundStyle(Theme.red) }
                        }
                        GridRow {
                            item("Account Number") { accountNumber }
                            if !account.isLeased { item("Interest Rate") { interest } }
                            item("Payments Left") { paymentsLeft(loan) }
                            item(loan.targetDate == nil ? (account.isLeased ? "Estimated Lease End" : "Estimated Payoff") : (account.isLeased ? "Lease End Date" : "Maturity Date")) { payoff(loan) }
                        }
                        if let bill = account.loanBill {
                            GridRow {
                                item("Payment Due") { Text(LoanBill.dueText(bill)) }
                                item("This Month's Payment") { LoanPaymentStatus(account: account) }
                            }
                        }
                        if let start = account.loanStartDate {
                            GridRow {
                                item("\(account.financingWord) Started") { Text(start, format: .dateTime.month(.abbreviated).day().year()) }
                            }
                        }
                        if loan.targetDate != nil {
                            GridRow {
                                item("Payments to Maturity") { paymentsToMaturity }
                                item("Needed Per Month") { needed(loan) }
                                item("Your Payment") { targetStatus(loan) }
                            }
                        }
                        if !account.notes.isEmpty {
                            GridRow {
                                item("Notes") { Text(account.notes) }.gridCellColumns(4)
                            }
                        }
                    }

                    if loan.hasOriginal {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: loan.fraction).tint(Theme.green)
                            Text(loan.isPaidOff ? "Paid off" : "\(loan.fraction.formatted(.percent.precision(.fractionLength(0)))) paid off")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 520)
                    } else {
                        Text(account.isLeased ? "Add the total lease cost in Edit Details to track your progress." : "Add the original loan amount in Edit Details to track your progress.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    balanceBlock
                    Button("Edit Details", action: onEdit)
                }
            }
        }
    }

    /// The current balance, big, in the top-right corner of the card. Every account type shows it the same way;
    /// a loan's balance is negative because it is money owed.
    private var balanceBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("CURRENT BALANCE").font(.caption).foregroundStyle(.secondary)
            Text(account.balance, format: .appCurrency)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(account.balance < 0 ? Theme.red : .primary)
        }
    }

    private var interest: Text {
        account.interestRate > 0 ? Text("\(account.interestRate.formatted(.number.precision(.fractionLength(0...3))))%") : Text("Not set").foregroundStyle(.secondary)
    }

    private func amount(_ value: Decimal, set: Bool) -> Text {
        set ? Text(value, format: .appCurrency) : Text("Not set").foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func paymentsLeft(_ loan: LoanProgress) -> some View {
        if loan.isPaidOff { Text("None") }
        else if let count = loan.paymentsLeft { Text("About \(count)") }
        else { text("") }
    }

    @ViewBuilder
    private var paymentsToMaturity: some View {
        if account.loanProgress.isPaidOff { Text("None") }
        else if let count = LoanBill.paymentsToMaturity(account) { Text("About \(count)") }
        else { text("") }
    }

    @ViewBuilder
    private func needed(_ loan: LoanProgress) -> some View {
        if let amount = loan.paymentNeeded() { Text(amount, format: .appCurrency) } else { text("") }
    }

    @ViewBuilder
    private func targetStatus(_ loan: LoanProgress) -> some View {
        switch loan.targetStatus() {
        case .onTrack: Label("On track", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .behind: Label("Behind", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .pastDue: Label("Past the date", systemImage: "exclamationmark.octagon.fill").foregroundStyle(Theme.red)
        case nil: text("")
        }
    }

    @ViewBuilder
    private func payoff(_ loan: LoanProgress) -> some View {
        if loan.isPaidOff { Text("Paid off").foregroundStyle(Theme.green) }
        else if let target = loan.targetDate { Text(target, format: .dateTime.month(.abbreviated).day().year()) }
        else if let date = loan.payoffDate() { Text(date, format: .dateTime.month(.abbreviated).year()) }
        else { text("") }
    }

    // MARK: Everything else

    private var accountContent: some View {
        Panel(title: "Account Details") {
            HStack(alignment: .top, spacing: 20) {
                if account.supportsPhoto, let photo = AccountPhoto.image(from: account.photoData) {
                    photo
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                    GridRow {
                        item("Kind") {
                            Label(account.isDebt ? "Debt" : "Asset",
                                  systemImage: account.isDebt ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill")
                                .foregroundStyle(account.isDebt ? Theme.red : Theme.green)
                        }
                        item("Type") { Text(account.type.title) }
                        if !account.isCashOnHand { item("Institution") { text(account.institution) } }
                        if account.isLoan {
                            item("Loan For") { text(account.loanPurpose) }
                        }
                        if account.isCreditCard {
                            item("Credit Limit") { amount(account.creditLimit, set: account.creditLimit > 0) }
                        } else if !account.isCashOnHand {
                            item("Opening Balance") { Text(account.openingBalance, format: .appCurrency) }
                        }
                    }
                    GridRow {
                        if !account.isCashOnHand { item(account.numberLabel) { accountNumber } }
                        if account.supportsVIN {
                            item("VIN") { text(account.vin) }
                        }
                        if account.isCreditCard {
                            item("Interest Rate (APR)") { interest }
                        } else if !account.isCashOnHand {
                            item("Routing Number") { text(account.routingNumber) }
                        }
                        item("Transactions (\(monthLabel))") { Text(monthTransactions.count, format: .number) }
                        item("In / Out (\(monthLabel))") { inOut }
                    }
                    GridRow {
                        if account.isCreditCard {
                            item("Current Balance on Card") {
                                Text(max(-account.balance, 0), format: .appCurrency).foregroundStyle(account.balance < 0 ? Theme.red : .primary)
                            }
                            item("Available Credit") { amount(account.availableCredit, set: account.creditLimit > 0) }
                            item("Minimum Payment") { amount(account.monthlyPayment, set: account.monthlyPayment > 0) }
                            if let bill = account.loanBill {
                                item("Payment Due") {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LoanBill.dueText(bill))
                                        LoanPaymentStatus(account: account).font(.caption)
                                    }
                                }
                            } else {
                                item("Payment Due") { text("") }
                            }
                        } else {
                            item("Reconciled Balance") {
                                Text(reconciledBalance, format: .appCurrency).foregroundStyle(Theme.green)
                            }
                        }
                        item("Unreconciled") { unreconciled }
                        item("Pending") { pendingSummary }
                    }
                    if !account.notes.isEmpty {
                        GridRow {
                            item("Notes") { Text(account.notes) }
                                .gridCellColumns(4)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    balanceBlock
                    Button("Edit Details", action: onEdit)
                }
            }
        }
    }

    private func item<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func text(_ value: String) -> Text {
        value.isEmpty ? Text("Not set").foregroundStyle(.secondary) : Text(value)
    }

    private var accountNumber: some View {
        HStack(spacing: 6) {
            if account.accountNumber.isEmpty {
                text("")
            } else {
                Text(showAccountNumber ? account.accountNumber : account.maskedAccountNumber)
                    .monospacedDigit()
                Button(showAccountNumber ? "Hide" : "Show") { showAccountNumber.toggle() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
        }
    }

    private var inOut: some View {
        let income = monthTransactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        let spending = monthTransactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount }
        return HStack(spacing: 4) {
            Text(income, format: .appCurrency).foregroundStyle(Theme.green)
            Text("/").foregroundStyle(.secondary)
            Text(spending, format: .appCurrency).foregroundStyle(Theme.red)
        }
    }
}

/// Whether this month's payment on a loan has been paid, from the loan's bill on the Bills page.
struct LoanPaymentStatus: View {
    let account: Account

    var body: some View {
        if let item = LoanBill.thisMonth(account) {
            let month = item.date.formatted(.dateTime.month(.abbreviated))
            HStack(spacing: 6) {
                if item.isPaid {
                    Image(systemName: "checkmark.circle.fill")
                    Text("\(month): Paid")
                } else if item.isOverdue {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("\(month): Not paid (overdue)")
                } else {
                    Image(systemName: "circle")
                    Text("\(month): Not paid")
                }
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(item.isPaid ? Theme.green : (item.isOverdue ? Theme.red : Color.orange))
        }
    }
}
