import SwiftUI
import SwiftData

/// Shown when a lease has been paid down to nothing: what happened to the car? Bought out and financed turns the lease into a regular auto loan,
/// bought out and paid for adds the car as an asset, and returned archives the lease. Nothing happens until a button is pressed, and an archived
/// lease can be brought back from Manage Accounts ▸ Archived.
struct LeaseEndedSheet: View {
    let lease: Account

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Choice: String, CaseIterable, Identifiable {
        case financed = "Bought it and financed it"
        case outright = "Bought it outright"
        case returned = "Returned it"
        var id: Self { self }
    }

    @State private var choice = Choice.returned
    @State private var owed: Decimal?
    @State private var payment: Decimal?
    @State private var rate: Double?
    @State private var name: String
    @State private var worth: Decimal?

    init(lease: Account) {
        self.lease = lease
        _name = State(initialValue: PaidOffLoans.suggestedAssetName(for: lease))
    }

    private var canContinue: Bool {
        switch choice {
        case .financed: (owed ?? 0) > 0 && (payment ?? 0) > 0
        case .outright: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .returned: true
        }
    }

    private var buttonTitle: String {
        switch choice {
        case .financed: "Turn Into an Auto Loan"
        case .outright: "Add as Asset"
        case .returned: "Archive the Lease"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("\(lease.name) has ended", systemImage: "flag.checkered")
                .font(.title3.weight(.semibold))
            Text("The lease is paid down to nothing. What happened to the car?")
            Picker("What happened", selection: $choice) {
                ForEach(Choice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Form {
                switch choice {
                case .financed:
                    CurrencyField("Amount you owe for the buyout", value: $owed)
                    CurrencyField("Monthly payment", value: $payment)
                    HStack {
                        TextField("Interest rate (APR, optional)", value: $rate, format: .number.precision(.fractionLength(0...3)))
                            .multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                case .outright:
                    TextField("Name", text: $name)
                    CurrencyField("What is it worth?", value: $worth)
                case .returned:
                    Text("The lease goes to Manage Accounts ▸ Archived with all of its transactions.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            Text(explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Don't Ask Again") { PaidOffLoans.decline(lease); dismiss() }
                Spacer()
                Button("Not Now") { PaidOffLoans.skipForNow(lease); dismiss() }
                Button(buttonTitle, action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
        }
        .padding(22)
        .frame(width: 540)
    }

    private var explanation: String {
        switch choice {
        case .financed:
            "The lease becomes a regular auto loan that owes this amount from today, with its history kept. Its bill keeps its due date and takes the new payment. You can change any of it by editing the loan."
        case .outright:
            "The car is added as a Vehicle asset worth what you say, and the lease is archived. Nothing is deleted, and you can bring the lease back."
        case .returned:
            "Nothing is deleted, and you can bring the lease back from the Archived tab."
        }
    }

    private func apply() {
        switch choice {
        case .financed:
            PaidOffLoans.convertLeaseToLoan(lease, owed: owed ?? 0, monthlyPayment: payment ?? 0, rate: rate ?? 0, in: modelContext)
        case .outright:
            PaidOffLoans.makeAsset(from: lease, type: .vehicle, name: name, value: worth ?? 0, in: modelContext)
        case .returned:
            PaidOffLoans.archive(lease, in: modelContext)
            modelContext.saveNow()
        }
        dismiss()
    }
}
