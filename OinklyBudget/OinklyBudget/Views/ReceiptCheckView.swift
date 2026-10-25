import SwiftUI

/// What a transaction window keeps about its receipt scan, so that saving can teach this Mac which payee goes with which store.
@MainActor
@Observable
final class ReceiptCheckState {
    var reading: ReceiptReading?
    var isReading = false

    /// Reads the receipt now, on this Mac. Does nothing when there is no receipt.
    func read(_ data: Data?) async {
        guard let data else { reading = nil; isReading = false; return }
        isReading = true
        let found = await ReceiptReader.read(data)
        guard !Task.isCancelled else { return }
        reading = found
        isReading = false
    }

    /// Called when the transaction is saved with its receipt: this Mac remembers that this store's receipts mean this payee.
    func learn(payee: String, receipt: Data?) {
        guard receipt != nil, let merchant = reading?.merchant else { return }
        ReceiptMemory.remember(merchant: merchant, payee: payee)
    }
}

/// What the receipt can be checked against, and how a suggestion is taken: the fields of the transaction being typed.
struct ReceiptChecking {
    let state: ReceiptCheckState
    let amount: Binding<Decimal?>
    let date: Binding<Date>
    let payee: Binding<String>
}

/// Under the receipt picture in a transaction window: what the scan found on the receipt, and anything that doesn't match what has been
/// typed. A suggestion changes nothing until its Use button is pressed.
struct ReceiptCheckView: View {
    let data: Data?
    let checking: ReceiptChecking

    var body: some View {
        let state = checking.state
        VStack(alignment: .leading, spacing: 8) {
            if data == nil {
                EmptyView()
            } else if state.isReading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the receipt…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let reading = state.reading {
                if reading.isEmpty {
                    Label("Couldn't read a total, date or store from this receipt.", systemImage: "questionmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    let suggestions = ReceiptCheck.suggestions(for: reading, amount: checking.amount.wrappedValue, date: checking.date.wrappedValue,
                                                               payee: checking.payee.wrappedValue, remembered: ReceiptMemory.payee(forMerchant: reading.merchant))
                    summary(reading)
                    if suggestions.isEmpty {
                        Label("Matches what you entered.", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Theme.green)
                    } else {
                        ForEach(suggestions) { suggestion in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                                Text(suggestion.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Button("Use") { apply(suggestion) }.controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Read again whenever the receipt changes.
        .task(id: dataKey) { await checking.state.read(data) }
    }

    /// Tells receipts apart without comparing every byte of a photo each time the window redraws.
    private var dataKey: Int { data.map { $0.count &* 31 &+ $0.prefix(256).hashValue } ?? 0 }

    private func summary(_ reading: ReceiptReading) -> some View {
        let parts = [reading.merchant, reading.total.map { $0.formatted(.appCurrency) }, reading.date.map { $0.formatted(date: .abbreviated, time: .omitted) }].compactMap { $0 }
        return Text("The receipt reads: \(parts.joined(separator: " · "))").font(.caption).foregroundStyle(.secondary)
    }

    private func apply(_ suggestion: ReceiptCheck.Suggestion) {
        switch suggestion.field {
        case .amount(let value): checking.amount.wrappedValue = value
        case .date(let value): checking.date.wrappedValue = value
        case .payee(let value): checking.payee.wrappedValue = value
        }
    }
}
