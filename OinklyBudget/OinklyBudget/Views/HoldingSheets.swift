import SwiftUI
import SwiftData

/// Which holdings sheet is open.
enum HoldingSheet: Identifiable {
    case add
    case edit(Holding)
    case price(Holding)
    case accountValue

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let holding): "edit-\(holding.persistentModelID.hashValue)"
        case .price(let holding): "price-\(holding.persistentModelID.hashValue)"
        case .accountValue: "value"
        }
    }
}

extension View {
    /// Presents the add, edit, update-price and update-value sheets for an investment account.
    func holdingSheets(_ sheet: Binding<HoldingSheet?>, account: Account) -> some View {
        self.sheet(item: sheet) { item in
            switch item {
            case .add: HoldingEditView(account: account, holding: nil)
            case .edit(let holding): HoldingEditView(account: account, holding: holding)
            case .price(let holding): UpdatePriceView(holding: holding)
            case .accountValue: UpdateValueView(account: account)
            }
        }
    }
}

extension View {
    /// Mac sheets need a minimum size.
    func macSheetFrame(minHeight: CGFloat) -> some View {
        frame(minWidth: 420, minHeight: minHeight)
    }
}

private func gainText(_ amount: Decimal) -> String {
    amount >= 0 ? "a gain of \(amount.formatted(.appCurrency))" : "a loss of \((-amount).formatted(.appCurrency))"
}

// MARK: Add / edit

struct HoldingEditView: View {
    let account: Account
    let holding: Holding?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var symbol: String
    @State private var shares: Decimal?
    @State private var price: Decimal?
    @State private var cost: Decimal?
    @State private var funding = HoldingsLedger.Funding.alreadyInAccount
    @State private var source: Account?
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @State private var confirmingRemove = false

    init(account: Account, holding: Holding?) {
        self.account = account
        self.holding = holding
        _name = State(initialValue: holding?.name ?? "")
        _symbol = State(initialValue: holding?.symbol ?? "")
        _shares = State(initialValue: holding?.shares)
        _price = State(initialValue: holding?.price)
        _cost = State(initialValue: holding?.costBasis)
    }

    /// Where money for a new holding can come from: any of your other accounts that aren't debts.
    private var sources: [Account] {
        allAccounts.live.filter { !$0.isDebt && $0.persistentModelID != account.persistentModelID }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && shares != nil && price != nil
            && (funding != .fromAccount || source != nil)
    }

    /// What changing the price will record on the account.
    private var priceEffect: Decimal? {
        guard let holding, let price, price != holding.price else { return nil }
        return holding.shares * (price - holding.price)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Holding") {
                    FormTextField("Name", text: $name, hint: "such as Vanguard Total Market")
                    FormTextField("Symbol", text: $symbol, hint: "Optional")
                }

                Section {
                    TextField("Shares or units", value: $shares, format: .number.precision(.fractionLength(0...6)), prompt: Text("0"))
                    CurrencyField("Price per share", value: $price)
                    CurrencyField("Cost basis (total paid)", value: $cost)
                } header: {
                    Text("Position")
                } footer: {
                    if let effect = priceEffect {
                        Text("Changing the price records \(gainText(effect)) on \(account.name).")
                    } else {
                        Text("Leave the cost basis empty to use today's value.")
                    }
                }

                if holding == nil {
                    Section {
                        Picker("Funding", selection: $funding) {
                            ForEach(HoldingsLedger.Funding.allCases.filter { $0 != .fromAccount || !sources.isEmpty }) {
                                Text($0.title).tag($0)
                            }
                        }
                        if funding == .fromAccount {
                            Picker("Moved from", selection: $source) {
                                Text("Choose…").tag(Account?.none)
                                ForEach(sources) { Text($0.name).tag(Optional($0)) }
                            }
                        }
                    } footer: {
                        switch funding {
                        case .alreadyInAccount: Text("The account's balance already includes this holding, so nothing is added.")
                        case .fromAccount: Text("Moves the holding's value out of the other account and into this one. It isn't counted as income or spending.")
                        case .outside: Text("Adds the holding's value as a deposit, such as money from a paycheck.")
                        }
                    }
                } else {
                    Section {
                        Button("Remove Holding", role: .destructive) { confirmingRemove = true }
                    } footer: {
                        Text("Removing a holding doesn't change the account's balance.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(holding == nil ? "New Holding" : "Edit Holding")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .confirmationDialog("Remove this holding?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive, action: remove)
                Button("Cancel", role: .cancel) {}
            }
        }
        .macSheetFrame(minHeight: 440)
    }

    private func save() {
        guard let shares, let price else { return }
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanSymbol = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        if let holding {
            HoldingsLedger.edit(holding, name: cleanName, symbol: cleanSymbol, shares: shares, price: price,
                                costBasis: cost ?? shares * price, in: modelContext)
        } else {
            HoldingsLedger.add(to: account, name: cleanName, symbol: cleanSymbol, shares: shares, price: price,
                               costBasis: cost, funding: funding, source: source, in: modelContext)
        }
        modelContext.saveNow()
        dismiss()
    }

    private func remove() {
        if let holding { modelContext.delete(holding) }
        modelContext.saveNow()
        dismiss()
    }
}

// MARK: Update price

struct UpdatePriceView: View {
    let holding: Holding

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var price: Decimal?

    init(holding: Holding) {
        self.holding = holding
        _price = State(initialValue: holding.price)
    }

    private var effect: Decimal? {
        guard let price, price != holding.price else { return nil }
        return holding.shares * (price - holding.price)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Holding", value: holding.name)
                    LabeledContent("Shares or units", value: holding.shares.formatted(.number.precision(.fractionLength(0...6))))
                    LabeledContent("Last price", value: holding.price.formatted(.appCurrency))
                    CurrencyField("New price per share", value: $price)
                } footer: {
                    if let effect, let price {
                        Text("Value goes to \((holding.shares * price).formatted(.appCurrency)). This records \(gainText(effect)) on the account.")
                    } else {
                        Text("Enter today's price. The change is recorded as a gain or loss on the account.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Update Price")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let price { HoldingsLedger.updatePrice(holding, to: price, in: modelContext) }
                        modelContext.saveNow()
                        dismiss()
                    }
                    .disabled(price == nil)
                }
            }
        }
        .macSheetFrame(minHeight: 300)
    }
}

// MARK: Update account value

struct UpdateValueView: View {
    let account: Account

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var value: Decimal?

    init(account: Account) {
        self.account = account
        _value = State(initialValue: account.balance)
    }

    private var effect: Decimal? {
        guard let value, value != account.balance else { return nil }
        return value - account.balance
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Account", value: account.name)
                    LabeledContent("Current value", value: account.balance.formatted(.appCurrency))
                    CurrencyField("New value", value: $value)
                } footer: {
                    if let effect {
                        Text("This records \(gainText(effect)) on the account, so it counts as growth in your Investments report.")
                    } else {
                        Text("Enter what the account is worth today. The difference is recorded as a gain or loss.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Update Account Value")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value { HoldingsLedger.setAccountValue(account, to: value, in: modelContext) }
                        modelContext.saveNow()
                        dismiss()
                    }
                    .disabled(value == nil)
                }
            }
        }
        .macSheetFrame(minHeight: 280)
    }
}
