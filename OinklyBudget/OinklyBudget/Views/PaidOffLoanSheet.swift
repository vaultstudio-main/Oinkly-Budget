import SwiftUI
import SwiftData

/// Shown when an auto loan or a mortgage has been paid off: offers to add the car or house as an asset, worth what you say, and to archive the
/// loan. Nothing happens until a button is pressed.
struct PaidOffLoanSheet: View {
    let loan: Account

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var value: Decimal?

    init(loan: Account) {
        self.loan = loan
        _name = State(initialValue: PaidOffLoans.suggestedAssetName(for: loan))
        _value = State(initialValue: loan.originalLoanAmount > 0 ? loan.originalLoanAmount : nil)
    }

    private var assetType: AccountType {
        if case .becomesAsset(let type) = PaidOffLoans.outcome(for: loan.type, isLease: loan.isLease) { return type }
        return .asset
    }

    /// An asset already in the side panel that looks like the same car or house.
    private var existing: Account? { PaidOffLoans.existingAsset(for: loan, in: modelContext) }

    private var canAdd: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (value ?? 0) >= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("\(loan.name) is paid off", systemImage: "party.popper.fill")
                .font(.title3.weight(.semibold))
            if let existing {
                Label("You already have \"\(existing.name)\" as an asset, so archiving the loan is probably all you need.", systemImage: "info.circle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            Text("Congratulations, it is all yours. Add it as a \(assetType.title) asset so it still counts towards what you own, and archive the loan.")
            Form {
                TextField("Name", text: $name)
                CurrencyField("What is it worth?", value: $value)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            Text("The worth starts at the original loan amount. Change it to what it is worth now, which you can also do later by editing the asset.")
                .font(.callout).foregroundStyle(.secondary)
            Text("The loan is archived: it leaves the side panel and its bill leaves the Bills page, but its transactions are kept so your history stays right. At year end you are asked whether to keep archived accounts or delete them.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Don't Ask Again") { PaidOffLoans.decline(loan); dismiss() }
                Spacer()
                Button("Not Now") { PaidOffLoans.skipForNow(loan); dismiss() }
                Button("Just Archive the Loan") { archiveOnly() }
                    .keyboardShortcut(existing != nil ? .defaultAction : nil)
                Button("Add as Asset") {
                    PaidOffLoans.makeAsset(from: loan, type: assetType, name: name, value: value ?? 0, in: modelContext)
                    dismiss()
                }
                .keyboardShortcut(existing == nil ? .defaultAction : nil)
                .disabled(!canAdd)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func archiveOnly() {
        PaidOffLoans.archive(loan, in: modelContext)
        modelContext.saveNow()
        dismiss()
    }
}
