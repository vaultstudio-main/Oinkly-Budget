import SwiftUI
import SwiftData

/// ATM Withdrawal: moves cash from a checking or savings account into Cash on Hand. One withdrawal, two linked
/// entries, so it never counts as income or spending. A window on the Mac.
struct AtmWithdrawalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]

    @State private var source: Account?
    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var confirmation: String?

    /// Every ATM withdrawal reads the same, on both sides.
    static let fixedPayee = "ATM Withdrawal"
    static let fixedMemo = "Cash"

    /// Only checking and savings accounts can be withdrawn from.
    private var sources: [Account] {
        allAccounts.live.filter { ($0.type == .checking || $0.type == .savings) && !$0.isClosed }
    }

    /// Always the built-in Cash on Hand.
    private var cash: Account? { allAccounts.live.first(where: \.isDefault) }

    private var canSave: Bool { source?.isLive == true && cash?.isLive == true && (amount ?? 0) > 0 }

    var body: some View {
        content
            .frame(width: 460, height: 620)
            .background(Theme.background)
            .onAppear(perform: pickDefaultSource)
    }

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty || cash == nil {
            ContentUnavailableView("No Account to Withdraw From", systemImage: "banknote",
                                   description: Text("Add a checking or savings account in Settings ▸ Accounts, and you can record ATM withdrawals into Cash on Hand."))
        } else {
            form
        }
    }

    private var fields: some View {
        Group {
            Section("Withdrawal") {
                Picker("From", selection: $source) {
                    ForEach(sources) { Text($0.name).tag(Optional($0)) }
                }
                LabeledContent("To") {
                    Label(cash?.name ?? Account.defaultName, systemImage: "lock.fill").foregroundStyle(.secondary)
                }
                CurrencyField("Amount", value: $amount)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                LabeledContent("Status") {
                    Label(ReconcileState.reconciled.title, systemImage: "lock.fill").foregroundStyle(.secondary)
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
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Withdraw", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
    }

    private var summary: String {
        guard let source, source.isLive, let amount, amount > 0 else {
            return "Choose where the cash comes from and how much. It is taken out of that account and added to Cash on Hand."
        }
        return "Takes \(amount.formatted(.appCurrency)) out of \(source.name) and adds it to \(cash?.name ?? Account.defaultName)."
    }

    private func pickDefaultSource() {
        if source == nil { source = sources.first { $0.type == .checking } ?? sources.first }
    }

    private func save() {
        guard let source, source.isLive, let cash, cash.isLive, let amount, amount > 0 else { return }
        let moved = Transfers.move(
            from: source, to: cash, amount: amount, date: date, memo: Self.fixedMemo, state: .reconciled,
            paymentType: .atm, checkNumber: "",
            payeeOut: Self.fixedPayee, payeeIn: Self.fixedPayee, in: modelContext
        )
        // Cash coming in is cash, whatever it came from.
        moved.into.paymentChoice = .type(.cash)
        // An ATM withdrawal is always the same record: ATM Withdrawal, category ATM, cash, memo "Cash", no receipt.
        for leg in [moved.out, moved.into] {
            leg.isAtmWithdrawal = true
            leg.noReceipt = true
        }
        modelContext.saveNow()

        confirmation = "Moved \(amount.formatted(.appCurrency)) from \(source.name) to \(cash.name)."
        self.amount = nil
    }
}
