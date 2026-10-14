import SwiftUI
import SwiftData

/// New Credit Card Charge: adds debt to a credit card, and refuses a charge that would reach the card's credit limit.
/// A window on the Mac (File menu).
struct CreditCardChargeView: View {
    /// The card to start on, when opened from its own page.
    var initialCard: Account?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Query(sort: \Payee.name) private var allPayees: [Payee]

    @State private var card: Account?
    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var payee = ""
    @State private var category: Category?
    @State private var memo = ""
    @State private var state: ReconcileState = .unreconciled
    @State private var receipt: Data?
    @State private var noReceipt = false
    @State private var limitMessage: String?
    @State private var confirmation: String?

    private var cards: [Account] { allAccounts.live.filter { $0.isCreditCard && !$0.isClosed } }
    private var categories: [Category] { allCategories.live }
    private var payees: [Payee] { allPayees.live }

    private var suggestions: [Payee] {
        let matches = PayeeMemory.matches(for: payee, in: payees)
        if matches.count == 1, PayeeMemory.normalized(matches[0].name) == PayeeMemory.normalized(payee) { return [] }
        return matches
    }

    private var charge: Decimal { abs(amount ?? 0) }
    private var canSave: Bool { card?.isLive == true && charge > 0 }
    private var exceedsLimit: Bool { card?.wouldExceedLimit(adding: -charge) == true }

    var body: some View {
        content
            .frame(width: 460, height: 680)
            .background(Theme.background)
            .onAppear(perform: pickDefaultCard)
            .alert(limitAlertTitle, isPresented: limitAlertShowing) { Button("OK", role: .cancel) {} } message: { Text(limitMessage ?? "") }
    }

    private var limitAlertTitle: String { "Exceeds Credit Limit" }
    private var limitAlertShowing: Binding<Bool> {
        Binding(get: { limitMessage != nil }, set: { if !$0 { limitMessage = nil } })
    }

    @ViewBuilder
    private var content: some View {
        if cards.isEmpty {
            ContentUnavailableView("No Credit Cards", systemImage: "creditcard",
                                   description: Text("Add a credit card in Settings ▸ Accounts and you can record charges on it here."))
        } else {
            form
        }
    }

    private var fields: some View {
        Group {
            Section("Charge") {
                Picker("Card", selection: $card) {
                    ForEach(cards) { Text($0.name).tag(Optional($0)) }
                }
                CurrencyField("Amount", value: $amount)
                if let card, card.isLive, card.creditLimit > 0 {
                    LabeledContent("Available credit") {
                        Text(card.availableCredit, format: .appCurrency)
                            .foregroundStyle(exceedsLimit ? Theme.red : .secondary)
                    }
                }
                if exceedsLimit, let card {
                    Label("This would reach the credit limit on \(card.name).", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
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
                    CategoryOptions(categories: categories, only: .expense, keeping: category)
                }
                LabeledContent("Payment method") {
                    Label("Credit Card", systemImage: "lock.fill").foregroundStyle(.secondary)
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

    private var form: some View {
        VStack(spacing: 0) {
            Form { fields }
                .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Charge", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
    }

    private func pickDefaultCard() {
        guard card == nil else { return }
        card = cards.first { $0.id == initialCard?.id } ?? cards.first
    }

    private func apply(_ suggestion: Payee) {
        payee = suggestion.name
        if suggestion.lastAmount != 0 { amount = abs(suggestion.lastAmount) }
        let last = suggestion.lastCategory
        category = last?.isIncome == false ? last : nil
    }

    private func save() {
        guard let card, card.isLive, charge > 0 else { return }
        if card.wouldExceedLimit(adding: -charge) {
            limitMessage = card.limitMessage
            return
        }
        PayeeMemory.record(name: payee, category: category, amount: -charge, in: modelContext)
        let transaction = Transaction(account: card, date: date, payee: payee, category: category, memo: memo, amount: -charge,
                                      paymentType: .creditCard)
        transaction.state = state
        transaction.receiptData = receipt
        transaction.noReceipt = receipt == nil && noReceipt
        modelContext.insert(transaction)
        modelContext.saveNow()

        confirmation = "Added a \(charge.formatted(.appCurrency)) charge to \(card.name)."
        amount = nil
        payee = ""
        category = nil
        memo = ""
        state = .unreconciled
        receipt = nil
        noReceipt = false
    }
}

/// Resolves the card the window was opened from, then shows the charge form.
struct CreditCardChargeWindow: View {
    let accountID: PersistentIdentifier?
    @Query private var allAccounts: [Account]

    var body: some View {
        CreditCardChargeView(initialCard: allAccounts.live.first { $0.id == accountID })
    }
}
