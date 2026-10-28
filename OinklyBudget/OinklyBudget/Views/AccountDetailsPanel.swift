import SwiftUI
import SwiftData

/// Account facts shown above the register: kind, bank details and this month's activity.
struct AccountDetailsPanel: View {
    let account: Account
    let month: Date
    let onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showAccountNumber = false

    /// This account's totals from the ledger snapshot, when there is one. With a lot of transactions, adding them up
    /// here every time the panel redraws would be slow.
    private var ledger: LedgerSnapshot.Series? { LedgerIndex.shared.latest?.accounts[account.persistentModelID] }

    /// Only this month's transactions are loaded.
    private var monthTransactions: [Transaction] {
        let id = account.persistentModelID
        let start = month
        let end = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.account?.persistentModelID == id && $0.date >= start && $0.date < end })
        return ((try? modelContext.fetch(descriptor)) ?? []).filter(\.isLive)
    }

    /// Opening balance plus everything already matched to a statement.
    private var reconciledBalance: Decimal {
        if let ledger { return account.openingBalance + ledger.reconciledSum }
        return account.transactions.live.filter(\.isReconciled).reduce(account.openingBalance) { $0 + $1.amount }
    }

    private var unreconciled: some View {
        let count: Int
        let total: Decimal
        if let ledger {
            count = ledger.unreconciledCount
            total = ledger.unreconciledSum
        } else {
            let open = account.transactions.live.filter { $0.state == .unreconciled }
            count = open.count
            total = open.reduce(Decimal(0)) { $0 + $1.amount }
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(count) transaction\(count == 1 ? "" : "s")")
            Text(total, format: .appCurrency).foregroundStyle(count == 0 ? Color.secondary : ReconcileState.unreconciled.color)
        }
    }

    private var pendingSummary: some View {
        let count: Int
        let total: Decimal
        if let ledger {
            count = ledger.pendingCount
            total = ledger.pendingSum
        } else {
            let pending = account.transactions.live.filter { $0.state == .pending }
            count = pending.count
            total = pending.reduce(Decimal(0)) { $0 + $1.amount }
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(count) transaction\(count == 1 ? "" : "s")")
            Text(total, format: .appCurrency).foregroundStyle(count == 0 ? Color.secondary : ReconcileState.pending.color)
        }
    }

    @Query(sort: \Goal.createdAt) private var allGoals: [Goal]

    /// The open goal that follows this account, if any.
    private var followingGoal: Goal? {
        allGoals.live.first { !$0.isPayoff && $0.followedAccount?.persistentModelID == account.persistentModelID }
    }

    /// The goal that follows this account, laid out the same way on every kind of account: a divider, then its own grid
    /// with the same rows every time, and the progress bar at the bottom. The account's own details stay on the other
    /// side of the divider.
    private func goalSection(_ goal: Goal) -> some View {
        let progress = goal.progress()
        let needed = progress.neededPerMonth
        let pace = progress.monthlyPace ?? 0
        let shortfall = needed.map { max($0 - max(pace, 0), 0) }
        let none = Text("None").foregroundStyle(.secondary)
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("GOAL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    GridRow {
                        item("Goal") { Text(goal.name).lineLimit(1) }
                        item("Target Date") {
                            if let date = goal.targetDate { Text(date, format: .dateTime.month(.abbreviated).day().year()) } else { none }
                        }
                    }
                    GridRow {
                        item("Status") {
                            switch progress.status {
                            case .achieved: Label("Reached", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                            case .onTrack: Label("On track", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                            case .behind: Label("Behind", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            case .pastDue: Label("Past the date", systemImage: "exclamationmark.octagon.fill").foregroundStyle(Theme.red)
                            case .noDate: none
                            }
                        }
                        item("Needed Per Month") {
                            if let needed { Text(needed, format: .appCurrency) } else { none }
                        }
                    }
                    GridRow {
                        item("Your Pace") { Text("\(max(pace, 0).formatted(.appCurrency))/mo") }
                        item("To Catch Up") {
                            if let shortfall, shortfall > 0 {
                                Text("+\(shortfall.formatted(.appCurrency))/mo").foregroundStyle(.orange)
                            } else { none }
                        }
                    }
                    GridRow {
                        item("Estimated Finish") {
                            if let projected = progress.projectedDate { Text(projected, format: .dateTime.month(.abbreviated).year()) } else { none }
                        }
                        item(goal.isPayoff ? "Paid Off" : "Saved") { Text(goal.saved, format: .appCurrency) }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                        .tint(progress.isAchieved ? Theme.green : Color(hex: goal.colorHex))
                    Text(progress.isAchieved ? "Goal reached"
                         : "\(progress.fraction.formatted(.percent.precision(.fractionLength(0)))) \(goal.isPayoff ? "paid off" : "saved") · goal \(goal.targetAmount.formatted(.appCurrency))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 290, alignment: .leading)
            .padding(.leading, 20)
            // A line down the left edge, as tall as the goal's own rows rather than as tall as the card.
            .overlay(alignment: .leading) { Divider() }
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
        let goal = followingGoal
        var items: [DetailItem] = [
            DetailItem("Type") { Text(account.typeTitle) },
            DetailItem("\(account.financingWord) For") { text(account.loanPurpose) },
        ]
        if account.supportsVIN { items.append(DetailItem("VIN") { text(account.vin) }) }
        items += [
            DetailItem(account.lenderLabel) { text(account.institution) },
            DetailItem(account.isLeased ? "Total Lease Cost" : "Original Loan") { amount(loan.original, set: loan.hasOriginal) },
            DetailItem("Monthly Payment") { amount(loan.monthlyPayment, set: loan.monthlyPayment > 0) },
            DetailItem("Paid Off So Far") {
                if loan.hasOriginal {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loan.paidOff, format: .appCurrency).foregroundStyle(Theme.green)
                        Text(loan.fraction, format: .percent.precision(.fractionLength(0))).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    text("")
                }
            },
            DetailItem("Still Owed") { Text(loan.owed, format: .appCurrency).foregroundStyle(Theme.red) },
            DetailItem("Account Number") { accountNumber },
        ]
        if !account.isLeased { items.append(DetailItem("Interest Rate") { interest }) }
        items += [
            DetailItem("Payments Left") { paymentsLeft(loan) },
            DetailItem(loan.targetDate == nil ? (account.isLeased ? "Estimated Lease End" : "Estimated Payoff") : (account.isLeased ? "Lease End Date" : "Maturity Date")) { payoff(loan) },
        ]
        if let bill = account.loanBill {
            items.append(DetailItem("Payment Due") { Text(LoanBill.dueText(bill)) })
            if LoanBill.thisMonth(account) != nil {
                items.append(DetailItem("This Month's Payment") { LoanPaymentStatus(account: account) })
            }
        }
        if let start = account.loanStartDate {
            items.append(DetailItem("\(account.financingWord) Started") { Text(start, format: .dateTime.month(.abbreviated).day().year()) })
        }
        if loan.targetDate != nil {
            items += [
                DetailItem("Payments to Maturity") { paymentsToMaturity },
                DetailItem("Needed Per Month") { needed(loan) },
                DetailItem("Your Payment") { targetStatus(loan) },
            ]
        }
        return Panel(title: "\(account.financingWord) Details") {
            withBalance {
                AccountPicture(data: account.photoData, type: account.type, account: account)
                    .frame(width: 150, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 14) {
                    detailGrid(items, columns: goal == nil ? 4 : 3)

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
                if let goal {
                    goalSection(goal)
                }
            }
        }
    }

    /// The details with the balance and Edit Details at the right. When the window is too narrow for that, the balance moves to
    /// its own row above the details instead of being squeezed into a column of single characters.
    private func withBalance<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let details = content()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                details
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    balanceBlock
                    Button("Edit Details", action: onEdit)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Spacer()
                    balanceBlock
                    Button("Edit Details", action: onEdit)
                }
                HStack(alignment: .top, spacing: 20) { details }
            }
        }
    }

    /// The current balance, big, in the top-right corner of the card. Every account type shows it the same way;
    /// a loan's balance is negative because it is money owed.
    private var balanceBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("CURRENT BALANCE").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(account.balance, format: .appCurrency)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(account.balance < 0 ? Theme.red : .primary)
                .lineLimit(1)
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
        let goal = followingGoal
        var items: [DetailItem] = [
            DetailItem("Kind") {
                Label(account.isDebt ? "Debt" : "Asset",
                      systemImage: account.isDebt ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill")
                    .foregroundStyle(account.isDebt ? Theme.red : Theme.green)
            },
            DetailItem("Type") { Text(account.type.title) },
        ]
        if !account.isCashOnHand { items.append(DetailItem("Institution") { text(account.institution) }) }
        if account.isLoan { items.append(DetailItem("Loan For") { text(account.loanPurpose) }) }
        if account.isCreditCard {
            items.append(DetailItem("Credit Limit") { amount(account.creditLimit, set: account.creditLimit > 0) })
        } else if !account.isCashOnHand {
            items.append(DetailItem("Opening Balance") {
                Text(account.openingBalance, format: .appCurrency)
                if let goal {
                    Text("Goal target \(goal.targetAmount.formatted(.appCurrency))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            })
        }
        if !account.isCashOnHand { items.append(DetailItem(account.numberLabel) { accountNumber }) }
        if account.supportsVIN { items.append(DetailItem("VIN") { text(account.vin) }) }
        if account.isCreditCard {
            items.append(DetailItem("Interest Rate (APR)") { interest })
        } else if account.hasRoutingNumbers {
            items.append(DetailItem("Routing Number") { text(account.achRouting) })
        }
        if account.hasRoutingNumbers, !account.wireRouting.isEmpty {
            items.append(DetailItem("Wire Routing Number") { text(account.wireRouting) })
        }
        if account.hasRoutingNumbers, !account.digitalRouting.isEmpty {
            items.append(DetailItem("Digital Routing Number") { text(account.digitalRouting) })
        }
        items += [
            DetailItem("Transactions (\(monthLabel))") { Text(monthTransactions.count, format: .number) },
            DetailItem("In / Out (\(monthLabel))") { inOut },
        ]
        if account.isCreditCard {
            items += [
                DetailItem("Current Balance on Card") {
                    Text(max(-account.balance, 0), format: .appCurrency).foregroundStyle(account.balance < 0 ? Theme.red : .primary)
                },
                DetailItem("Available Credit") { amount(account.availableCredit, set: account.creditLimit > 0) },
                DetailItem("Minimum Payment") { amount(account.monthlyPayment, set: account.monthlyPayment > 0) },
            ]
            if let bill = account.loanBill {
                items.append(DetailItem("Payment Due") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LoanBill.dueText(bill))
                        LoanPaymentStatus(account: account).font(.caption)
                    }
                })
            } else {
                items.append(DetailItem("Payment Due") { text("") })
            }
        } else {
            items.append(DetailItem("Reconciled Balance") {
                Text(reconciledBalance, format: .appCurrency).foregroundStyle(Theme.green)
            })
        }
        items += [
            DetailItem("Unreconciled") { unreconciled },
            DetailItem("Pending") { pendingSummary },
        ]
        return Panel(title: "Account Details") {
            withBalance {
                AccountPicture(data: account.supportsPhoto ? account.photoData : nil, type: account.type, account: account)
                    .frame(width: 150, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 14) {
                    detailGrid(items, columns: goal == nil ? 4 : 3)
                }
                if let goal {
                    goalSection(goal)
                }
            }
        }
    }

    /// One fact in the details grid: a title and its value.
    private struct DetailItem: Identifiable {
        let id = UUID()
        let title: String
        let content: AnyView
        init<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) {
            self.title = title
            self.content = AnyView(content())
        }
    }

    /// The facts flowed into even rows of equal columns, so there are no holes and nothing is pushed over. Values wrap
    /// inside their column instead of running off it.
    private func detailGrid(_ items: [DetailItem], columns: Int) -> some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        return Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { entry in
                        item(entry.title) { entry.content }
                            .frame(width: 150, alignment: .topLeading)
                    }
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
