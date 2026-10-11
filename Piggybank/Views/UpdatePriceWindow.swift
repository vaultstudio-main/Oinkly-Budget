import SwiftUI
import SwiftData

/// File > Update Investment Price on the Mac, and a sheet on iPhone and iPad: pick any holding in any investment account and enter its new price.
struct UpdatePriceWindow: View {
    let accountID: PersistentIdentifier?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    private var accounts: [Account] { allAccounts.live.filter(\.supportsHoldings) }

    @State private var holding: Holding?
    @State private var price: Decimal?
    @State private var lastUpdated: String?

    private var holdings: [Holding] { accounts.flatMap { $0.holdings.live } }

    private var effect: Decimal? {
        guard let holding, holding.isLive, let price, price != holding.price else { return nil }
        return holding.shares * (price - holding.price)
    }

    var body: some View {
        #if os(macOS)
        content
            .frame(width: 460, height: 380)
            .background(Theme.background)
            .onAppear(perform: pickDefault)
        #else
        NavigationStack {
            content
                .navigationTitle("Update Price")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save).disabled(holding == nil || price == nil || effect == nil)
                    }
                }
        }
        .onAppear(perform: pickDefault)
        #endif
    }

    private func pickDefault() {
        if holding == nil {
            let preferred = accounts.first { $0.id == accountID }?.holdings.live.first
            select(preferred ?? holdings.first)
        }
    }

    @ViewBuilder
    private var content: some View {
        if holdings.isEmpty {
            ContentUnavailableView("No Holdings", systemImage: "chart.line.uptrend.xyaxis",
                                   description: Text("Add holdings to an investment account first, from its page."))
        } else {
            form
        }
    }

    private var fields: some View {
        Group {
            Section("Holding") {
                Picker("Holding", selection: $holding) {
                    ForEach(accounts) { account in
                        let members = account.holdings.live.sorted { $0.name < $1.name }
                        if !members.isEmpty {
                            Section(account.name) {
                                ForEach(members) { Text($0.symbol.isEmpty ? $0.name : "\($0.name) (\($0.symbol))").tag(Optional($0)) }
                            }
                        }
                    }
                }
                .onChange(of: holding) { _, new in select(new) }

                if let holding, holding.isLive {
                    LabeledContent("Shares or units", value: holding.shares.formatted(.number.precision(.fractionLength(0...6))))
                    LabeledContent("Last price", value: "\(holding.price.formatted(.appCurrency)) on \(holding.priceDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                }
            }

            Section {
                LabeledContent("New price per share") {
                    CurrencyField("New price per share", value: $price)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                if let effect, let holding, let price {
                    Text("Value goes to \((holding.shares * price).formatted(.appCurrency)). This records \(effect >= 0 ? "a gain of \(effect.formatted(.appCurrency))" : "a loss of \((-effect).formatted(.appCurrency))") on the account.")
                } else if let lastUpdated {
                    Text(lastUpdated)
                } else {
                    Text("The change is recorded as a gain or loss on the account.")
                }
            }
        }
    }

    private var form: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Form { fields }
                .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(holding == nil || price == nil || effect == nil)
            }
            .padding(16)
        }
        #else
        Form { fields }
        #endif
    }

    private func select(_ new: Holding?) {
        holding = new
        price = new?.isLive == true ? new?.price : nil
    }

    private func save() {
        guard let holding, holding.isLive, let price else { return }
        let name = holding.label
        let change = effect ?? 0
        HoldingsLedger.updatePrice(holding, to: price, in: modelContext)
        modelContext.saveNow()
        lastUpdated = "Updated \(name) to \(price.formatted(.appCurrency)) (\(change >= 0 ? "+" : "−")\(abs(change).formatted(.appCurrency))). Pick another holding to keep going."
        self.price = price
    }
}
