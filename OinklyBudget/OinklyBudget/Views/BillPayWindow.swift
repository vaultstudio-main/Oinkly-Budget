import SwiftUI
import SwiftData

/// File > Pay a Bill on the Mac. Pick where the money comes from and what it pays. The payment lands in the paying account,
/// takes the same amount off the debt when it pays a loan or card, and ticks the bill off on the Bills page.
struct BillPayWindow: View {
    /// A loan or card to start with, when opened from its own page.
    var initialDebt: Account?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @Query(sort: \Bill.name) private var allBills: [Bill]

    /// What the memo starts as. You can change it before paying.
    private static let defaultMemo = "Monthly payment"

    private enum Choice: Hashable {
        case bill(Bill)
        case account(Account)
    }

    @State private var source: Account?
    @State private var choice: Choice?
    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var memo = BillPayWindow.defaultMemo
    /// Paid bills are normally already out of the account, so they start as Reconciled. Choose Pending if not.
    @State private var state: ReconcileState = .reconciled
    @State private var paymentChoice: PaymentChoice?
    @State private var checkNumber = ""
    @State private var receipt: Data?
    @State private var noReceipt = false
    @State private var confirmation: String?

    private var sources: [Account] { Transfers.billPayable(allAccounts) }
    private var bills: [Bill] { allBills.live }
    private var debts: [Account] { allAccounts.live.filter(\.isDebt) }

    /// What the chosen target means: the debt it pays down (if any) and the bill it settles (if any).
    private var resolved: (debt: Account?, bill: Bill?) {
        switch choice {
        case .bill(let bill) where bill.isLive: return (bill.loan?.isLive == true ? bill.loan : nil, bill)
        case .account(let account) where account.isLive: return (account, account.loanBill)
        default: return (nil, nil)
        }
    }

    private var canPay: Bool {
        guard source?.isLive == true, let amount, amount > 0 else { return false }
        return resolved.debt != nil || resolved.bill != nil
    }

    var body: some View {
        content
            .frame(width: 480, height: 720)
            .background(Theme.background)
            .onAppear(perform: pickDefaultSource)
    }

    private func pickDefaultSource() {
        if source == nil { source = sources.first { $0.type == .checking } ?? sources.first }
        if choice == nil, let debt = initialDebt, debt.isLive {
            choice = .account(debt)
            prefill(choice)
        }
    }

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty || (bills.isEmpty && debts.isEmpty) {
            ContentUnavailableView("Nothing to Pay", systemImage: "creditcard",
                                   description: Text("Add an account to pay from, plus a bill or a loan or card to pay, and it shows up here."))
        } else {
            form
        }
    }

    private var fields: some View {
        Group {
            Section("Pay") {
                Picker("From", selection: $source) {
                    ForEach(sources) { Text($0.name).tag(Optional($0)) }
                }
                Picker("To", selection: $choice) {
                    Text("Choose…").tag(Choice?.none)
                    if !bills.isEmpty {
                        Section("Bills") {
                            ForEach(bills) { bill in
                                Text("\(bill.name) · \(bill.amount.formatted(.appCurrency))").tag(Optional(Choice.bill(bill)))
                            }
                        }
                    }
                    if !debts.isEmpty {
                        Section("Loans & Cards") {
                            ForEach(debts) { Text($0.name).tag(Optional(Choice.account($0))) }
                        }
                    }
                }
                .onChange(of: choice) { _, new in prefill(new) }

                LabeledContent("Amount") {
                    CurrencyField("Amount", value: $amount)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Payment method", selection: $paymentChoice) {
                    PaymentTypeOptions()
                }
                if paymentChoice?.isCheck == true {
                    FormTextField("Check number", text: $checkNumber)
                }
                FormTextField("Memo", text: $memo)
                Picker("Status", selection: $state) {
                    ForEach(ReconcileState.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                if state != .reconciled {
                    Text("You can change the status later in the account's register.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Choose Pending if the payment hasn't gone through yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if source?.supportsReceipts == true {
                Section("Receipt or Bill") {
                    ReceiptPicker(data: $receipt, noReceipt: $noReceipt)
                }
            }

            Section {
                Text(summary).font(.callout).foregroundStyle(.secondary)
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                }
            }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            Form { fields }
                .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Pay", action: pay)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canPay)
            }
            .padding(16)
        }
    }

    /// A plain-words preview of everything this payment will do.
    private var summary: String {
        guard let source, source.isLive, let amount, amount > 0 else {
            return "Choose a bill or a loan or card, and an amount. Every part of the payment is recorded together."
        }
        let (debt, bill) = resolved
        let money = amount.formatted(.appCurrency)
        var parts = ["Takes \(money) out of \(source.name)"]
        if let debt { parts.append("takes \(money) off what you owe on \(debt.name)") }
        if let bill {
            let due = Bills.nearestDue(bill, to: date).map { $0.formatted(.dateTime.month(.abbreviated).day()) }
            parts.append("marks \(bill.name)\(due.map { " (due \($0))" } ?? "") as paid")
        }
        return parts.joined(separator: ", ") + "."
    }

    private func prefill(_ new: Choice?) {
        switch new {
        case .bill(let bill) where bill.isLive: amount = bill.amount > 0 ? bill.amount : amount
        case .account(let account) where account.isLive: amount = account.monthlyPayment > 0 ? account.monthlyPayment : amount
        default: break
        }
    }

    private func pay() {
        guard let source, source.isLive, let amount, amount > 0 else { return }
        let (debt, bill) = resolved
        guard BillPayment.record(from: source, debt: debt, bill: bill, amount: amount, date: date, memo: memo,
                                       state: state, paymentChoice: paymentChoice, checkNumber: checkNumber,
                                       receiptData: receipt, noReceipt: noReceipt, in: modelContext) != nil else { return }
        modelContext.saveNow()
        Task { await BillNotifier.refresh(in: modelContext) }

        confirmation = "Paid \(amount.formatted(.appCurrency)) from \(source.name)\(bill.map { ", and marked \($0.name) paid" } ?? "")."
        self.amount = nil
        choice = nil
        memo = Self.defaultMemo
        state = .reconciled
        checkNumber = ""
        receipt = nil
        noReceipt = false
    }
}
