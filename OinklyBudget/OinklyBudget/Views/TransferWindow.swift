import SwiftUI
import SwiftData

/// File > Transfer on the Mac. Moves money from one of your accounts to another.
/// Debts (cards, loans, mortgages) can't be picked here; paying those is what Pay a Bill is for.
struct TransferWindow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]

    @State private var source: Account?
    @State private var destination: Account?
    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var memo = ""
    @State private var confirmation: String?

    private var choices: [Account] { Transfers.transferable(allAccounts) }

    private var destinations: [Account] {
        choices.filter { $0.persistentModelID != source?.persistentModelID }
    }

    private var canTransfer: Bool {
        guard let source, source.isLive, let destination, destination.isLive, source != destination,
              let amount, amount > 0 else { return false }
        return !source.wouldExceedLimit(adding: -amount)
    }

    private var exceedsLimit: Bool {
        guard let source, source.isLive, let amount, amount > 0 else { return false }
        return source.wouldExceedLimit(adding: -amount)
    }

    var body: some View {
        content
            .frame(width: 480, height: 400)
            .background(Theme.background)
            .onAppear(perform: pickDefaults)
    }

    private func pickDefaults() {
        if source == nil { source = choices.first { $0.type == .checking } ?? choices.first }
        if destination == nil || destination == source {
            destination = destinations.first { $0.type == .savings } ?? destinations.first
        }
    }

    @ViewBuilder
    private var content: some View {
        if choices.count < 2 {
            ContentUnavailableView("Need Two Accounts", systemImage: "arrow.left.arrow.right",
                                   description: Text("Transfers move money between your own accounts, such as checking and savings. Add a second account first."))
        } else {
            form
        }
    }

    private var fields: some View {
        Group {
            Section("Move money") {
                Picker("From", selection: $source) {
                    ForEach(choices) { Text($0.name).tag(Optional($0)) }
                }
                .onChange(of: source) { _, _ in
                    if destination == source { destination = destinations.first }
                }
                Picker("To", selection: $destination) {
                    ForEach(destinations) { Text($0.name).tag(Optional($0)) }
                }
                LabeledContent("Amount") {
                    CurrencyField("Amount", value: $amount)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                FormTextField("Memo", text: $memo)
            }

            Section {
                Text(summary).font(.callout).foregroundStyle(.secondary)
                if exceedsLimit, let source {
                    Label("This would go over the credit limit on \(source.name).", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                }
            }
        }
    }

    private var summary: String {
        guard let source, source.isLive, let destination, destination.isLive, let amount, amount > 0 else {
            return "Choose where the money comes from, where it goes, and how much. It is recorded in both accounts, and isn't counted as income or spending."
        }
        return "Takes \(amount.formatted(.appCurrency)) out of \(source.name) and puts it into \(destination.name)."
    }

    private var form: some View {
        VStack(spacing: 0) {
            Form { fields }
                .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Transfer", action: transfer)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canTransfer)
            }
            .padding(16)
        }
    }

    private func transfer() {
        guard canTransfer, let source, let destination, let amount else { return }
        Transfers.move(from: source, to: destination, amount: amount, date: Calendar.current.startOfDay(for: date),
                       memo: memo, payeeOut: "Transfer to \(destination.name)", payeeIn: "Transfer from \(source.name)",
                       in: modelContext)
        modelContext.saveNow()
        confirmation = "Moved \(amount.formatted(.appCurrency)) from \(source.name) to \(destination.name)."
        self.amount = nil
        memo = ""
    }
}
