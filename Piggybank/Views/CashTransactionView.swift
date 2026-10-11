import SwiftUI
import SwiftData

/// New Cash Transaction: money spent from, or received into, Cash on Hand. It only ever touches Cash on Hand, and the
/// method is always Cash. Filling Cash on Hand from a bank account is an ATM Withdrawal instead.
/// A window on the Mac and a sheet on iPhone and iPad.
struct CashTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Query(sort: \Payee.name) private var allPayees: [Payee]

    @State private var isPayment = true
    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var payee = ""
    @State private var category: Category?
    @State private var memo = ""
    @State private var state: ReconcileState = .reconciled
    @State private var receipt: Data?
    @State private var noReceipt = false
    @State private var confirmation: String?

    /// Always the built-in Cash on Hand.
    private var cash: Account? { allAccounts.live.first(where: \.isDefault) }
    private var categories: [Category] { allCategories.live }
    private var payees: [Payee] { allPayees.live }

    private var suggestions: [Payee] {
        let matches = PayeeMemory.matches(for: payee, in: payees)
        if matches.count == 1, PayeeMemory.normalized(matches[0].name) == PayeeMemory.normalized(payee) { return [] }
        return matches
    }

    private var canSave: Bool { cash?.isLive == true && (amount ?? 0) > 0 }

    var body: some View {
        #if os(macOS)
        form
            .frame(width: 460, height: 700)
            .background(Theme.background)
        #else
        NavigationStack {
            form
                .navigationTitle("Cash Transaction")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Add", action: save).disabled(!canSave) }
                }
        }
        #endif
    }

    private var fields: some View {
        Group {
            Section("Cash Transaction") {
                LabeledContent("Account") {
                    Label(cash?.name ?? Account.defaultName, systemImage: "lock.fill").foregroundStyle(.secondary)
                }
                Picker("Type", selection: $isPayment) {
                    Text("Spent (money out)").tag(true)
                    Text("Received (money in)").tag(false)
                }
                .pickerStyle(.segmented)
                CurrencyField("Amount", value: $amount)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section("Details") {
                FormTextField("Payee", text: $payee, hint: "Who was it?")
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestions) { suggestion in
                                Button(suggestion.name) { apply(suggestion) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                Picker("Category", selection: $category) {
                    CategoryOptions(categories: categories, only: isPayment ? .expense : .income, keeping: category)
                }
                LabeledContent("Payment method") {
                    Label(PaymentType.cash.title, systemImage: "lock.fill").foregroundStyle(.secondary)
                }
                FormTextField("Memo", text: $memo)
                Picker("Status", selection: $state) {
                    ForEach(ReconcileState.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            }

            Section("Receipt") {
                ReceiptPicker(data: $receipt, noReceipt: $noReceipt)
            }

            if let confirmation {
                Section {
                    Label(confirmation, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                }
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        if cash == nil {
            ContentUnavailableView("No Cash on Hand", systemImage: "dollarsign.circle",
                                   description: Text("Cash on Hand is created automatically. Restart the app if it's missing."))
        } else {
            #if os(macOS)
            VStack(spacing: 0) {
                Form { fields }
                    .formStyle(.grouped)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Add Transaction", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
                .padding(16)
            }
            #else
            Form { fields }
            #endif
        }
    }

    private func apply(_ suggestion: Payee) {
        payee = suggestion.name
        if suggestion.lastAmount != 0 {
            amount = abs(suggestion.lastAmount)
            isPayment = suggestion.lastAmount < 0
        }
        let last = suggestion.lastCategory
        category = last?.isIncome == !isPayment ? last : nil
    }

    private func save() {
        guard let cash, cash.isLive, let amount, amount > 0 else { return }
        let signed = isPayment ? -amount : amount
        PayeeMemory.record(name: payee, category: category, amount: signed, in: modelContext)
        let transaction = Transaction(account: cash, date: date, payee: payee, category: category, memo: memo, amount: signed,
                                      paymentType: .cash)
        transaction.state = state
        transaction.receiptData = receipt
        transaction.noReceipt = receipt == nil && noReceipt
        modelContext.insert(transaction)
        modelContext.saveNow()

        confirmation = "Added \(amount.formatted(.appCurrency)) \(isPayment ? "spent from" : "received into") \(cash.name)."
        self.amount = nil
        payee = ""
        category = nil
        memo = ""
        state = .reconciled
        receipt = nil
        noReceipt = false
    }
}
