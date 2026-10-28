import SwiftUI
import SwiftData

/// What a transaction window keeps about its receipt scan, so that saving can teach this Mac which payee goes with which store.
@MainActor
@Observable
final class ReceiptCheckState {
    var reading: ReceiptReading?
    var isReading = false
    /// Suggestions the person turned away for this receipt, so they don't come back while it is attached.
    var dismissed = Set<String>()

    /// Reads the receipt now, on this Mac. Does nothing when there is no receipt.
    func read(_ data: Data?) async {
        guard let data else { reading = nil; isReading = false; return }
        isReading = true
        let found = await ReceiptReader.read(data)
        guard !Task.isCancelled else { return }
        dismissed = []
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
    /// Nil where the payee is fixed, such as paying a bill, so a payee is never suggested.
    var payee: Binding<String>?
    /// The fields below are only passed where the window has them. Without them, only the total, date and payee are checked.
    var category: Binding<Category?>?
    var memo: Binding<String>?
    /// The payment method, only where it can be chosen (a credit card charge and a cash transaction have a fixed one).
    var method: Binding<PaymentChoice?>?
    /// The categories this window offers, and whether the transaction is money out.
    var categories: [Category] = []
    var isPayment = true
}

/// Under the receipt picture in a transaction window: what the scan found on the receipt, and anything that doesn't match what has been
/// typed. A suggestion changes nothing until its Use button is pressed.
struct ReceiptCheckView: View {
    let data: Data?
    let checking: ReceiptChecking
    @Query(sort: \Payee.name) private var payees: [Payee]

    /// Everything the receipt suggests that hasn't been turned away.
    private func suggestions(for reading: ReceiptReading) -> [ReceiptCheck.Suggestion] {
        let remembered = ReceiptMemory.payee(forMerchant: reading.merchant)
        let typed = checking.payee?.wrappedValue ?? ""
        var list = ReceiptCheck.suggestions(for: reading, amount: checking.amount.wrappedValue, date: checking.date.wrappedValue,
                                            payee: typed, remembered: remembered)
        if checking.payee == nil { list.removeAll { if case .payee = $0.field { true } else { false } } }
        // The payee the transaction will have: the one typed, or the one this Mac has learned for the store.
        let name = typed.trimmingCharacters(in: .whitespaces).isEmpty ? (remembered ?? "") : typed
        if checking.category != nil || checking.memo != nil || checking.method != nil {
            var fields = ReceiptCheck.Fields()
            fields.isPayment = checking.isPayment
            fields.categories = checking.categories
            fields.category = checking.category?.wrappedValue
            fields.payeeName = name
            fields.payeeCategory = PayeeMemory.exactMatch(for: name, in: payees)?.lastCategory
            fields.offersMethod = checking.method != nil
            fields.method = checking.method?.wrappedValue
            fields.memo = checking.memo?.wrappedValue ?? ""
            list += ReceiptCheck.moreSuggestions(for: reading, fields: fields)
        }
        return list.filter { !checking.state.dismissed.contains($0.id) }
    }

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
                    let list = suggestions(for: reading)
                    summary(reading)
                    if list.isEmpty {
                        Label("Matches what you entered.", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Theme.green)
                    } else {
                        if list.count > 1 {
                            HStack {
                                Text("Found on the receipt").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Button("Use All") { for suggestion in list { apply(suggestion) } }
                                    .controlSize(.small)
                                    .help("Take every suggestion below. Nothing is changed until you press this or a Use button.")
                            }
                        }
                        ForEach(list) { suggestion in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                                Text(suggestion.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Button("Use") { apply(suggestion) }.controlSize(.small)
                                Button { state.dismissed.insert(suggestion.id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.borderless).controlSize(.small)
                                    .help("Not this one")
                                    .accessibilityLabel("Dismiss this suggestion")
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
        case .payee(let value): checking.payee?.wrappedValue = value
        case .category(let value): checking.category?.wrappedValue = value
        case .method(let value): checking.method?.wrappedValue = .type(value)
        case .memo(let value): checking.memo?.wrappedValue = value
        }
    }
}
