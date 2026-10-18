import SwiftUI
import SwiftData

/// The Recurring tab on the Bills page: every repeating transaction, what is due next and a quick look ahead.
struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringTransaction.createdAt) private var allRules: [RecurringTransaction]
    @State private var editing: RuleSheet?
    @State private var deleting: RecurringTransaction?

    private var rules: [RecurringTransaction] { allRules.live }

    private enum RuleSheet: Identifiable {
        case add
        case edit(RecurringTransaction)
        var id: String {
            switch self {
            case .add: "add"
            case .edit(let rule): "edit-\(rule.persistentModelID.hashValue)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                lookAhead
                HStack {
                    Text("Repeating transactions add a pending entry on each due date. You confirm or change it in the register.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { editing = .add } label: {
                        Label("Add Recurring", systemImage: "plus.circle.fill").font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                if rules.isEmpty {
                    ContentUnavailableView("No Recurring Transactions", systemImage: "arrow.triangle.2.circlepath",
                                           description: Text("Add one for a paycheque, rent or anything else that repeats. You can also right-click a transaction in a register and choose Make Recurring."))
                        .frame(height: 260)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rules.enumerated()), id: \.element.persistentModelID) { index, rule in
                            if index > 0 { Divider() }
                            RuleRow(rule: rule, onEdit: { editing = .edit(rule) }, onDelete: { deleting = rule })
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .sheet(item: $editing) { sheet in
            switch sheet {
            case .add: RecurringRuleEditor(rule: nil, source: nil)
            case .edit(let rule): RecurringRuleEditor(rule: rule, source: nil)
            }
        }
        .confirmationDialog(deleting.map { "Delete “\($0.payee)”?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Rule", role: .destructive) {
                if let rule = deleting {
                    // The entries it already made stay. Only the rule goes.
                    for entry in rule.transactions where entry.isLive { entry.recurring = nil }
                    modelContext.delete(rule)
                    modelContext.saveNow()
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Transactions it already added stay in your registers.")
        }
    }

    private var lookAhead: some View {
        let ahead = Recurring.forecast(rules)
        return StatGrid {
            StatTile(title: "Next 30 Days: In") {
                Text(ahead.income, format: .appCurrency).foregroundStyle(Theme.green)
            } note: { Text("from your repeating deposits") }
            StatTile(title: "Next 30 Days: Out") {
                Text(ahead.spending, format: .appCurrency).foregroundStyle(Theme.red)
            } note: { Text("from your repeating payments") }
            StatTile(title: "Coming Up") {
                Text("\(ahead.count)")
            } note: { Text("entr\(ahead.count == 1 ? "y" : "ies") in the next 30 days") }
            StatTile(title: "Rules") {
                Text("\(rules.filter(\.isActive).count)")
            } note: { Text("\(rules.filter { !$0.isActive }.count) paused or finished") }
        }
    }
}

private struct RuleRow: View {
    @Environment(\.modelContext) private var modelContext
    let rule: RecurringTransaction
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var isDue: Bool { rule.isActive && rule.nextDate <= Calendar.current.startOfDay(for: .now) }

    private var statusText: String {
        if !rule.isActive { return rule.endDate != nil && Recurring.date(after: rule.nextDate, for: rule) == nil ? "Finished" : "Paused" }
        if !rule.autoEnter { return isDue ? "Due" : "Reminder only" }
        return "Active"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CategoryBadge(category: rule.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.payee).font(.body.weight(.semibold))
                Text([rule.account?.name, rule.frequency.title, rule.category?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(rule.amount, format: .appCurrency)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(rule.amount > 0 ? Theme.green : Theme.red)
                Text(rule.isActive ? "Next: \(rule.nextDate.formatted(.dateTime.month(.abbreviated).day().year()))" : statusText)
                    .font(.caption)
                    .foregroundStyle(isDue ? Color.orange : Color.secondary)
            }
            .frame(width: 150, alignment: .trailing)
            Text(statusText)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(statusColor.opacity(0.18), in: Capsule())
                .foregroundStyle(statusColor)
                .frame(width: 100)
            if isDue && !rule.autoEnter {
                Button("Add Now") {
                    Recurring.makeEntry(for: rule, on: rule.nextDate, in: modelContext)
                    Recurring.advance(rule)
                    modelContext.saveNow()
                }
                Button("Skip") {
                    Recurring.advance(rule)
                    modelContext.saveNow()
                }
            }
            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                if rule.isActive {
                    Button("Skip Next", systemImage: "forward.end") {
                        Recurring.advance(rule)
                        modelContext.saveNow()
                    }
                    Button("Pause", systemImage: "pause.circle") {
                        rule.isActive = false
                        modelContext.saveNow()
                    }
                } else if Recurring.date(after: rule.nextDate, for: rule) != nil || rule.frequency == .once && rule.nextDate >= Calendar.current.startOfDay(for: .now) {
                    Button("Resume", systemImage: "play.circle") {
                        // Pick up from today, not from the days that passed while it was paused.
                        if let next = Recurring.firstDue(onOrAfter: .now, for: rule) { rule.nextDate = next }
                        rule.isActive = true
                        modelContext.saveNow()
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var statusColor: Color {
        switch statusText {
        case "Active": Theme.green
        case "Due": .orange
        default: .secondary
        }
    }
}

/// Add or change a repeating transaction. From a register, "Make Recurring" opens it filled in from that transaction.
struct RecurringRuleEditor: View {
    let rule: RecurringTransaction?
    let source: Transaction?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Query(sort: \CustomPaymentMethod.name) private var allMethods: [CustomPaymentMethod]

    @State private var payee: String
    @State private var account: Account?
    @State private var isPayment: Bool
    @State private var amount: Decimal?
    @State private var category: Category?
    @State private var paymentChoice: PaymentChoice?
    @State private var memo: String
    @State private var frequency: BillFrequency
    @State private var startDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var autoEnter: Bool
    @State private var loadedMethod = false

    init(rule: RecurringTransaction?, source: Transaction?) {
        self.rule = rule
        self.source = source
        let basis = rule
        _payee = State(initialValue: basis?.payee ?? source?.payee ?? "")
        _account = State(initialValue: basis?.account ?? source?.account)
        let signed = basis?.amount ?? source?.amount ?? 0
        _isPayment = State(initialValue: signed <= 0)
        _amount = State(initialValue: signed == 0 ? nil : abs(signed))
        _category = State(initialValue: basis?.category ?? source?.category)
        _paymentChoice = State(initialValue: source?.paymentChoice)
        _memo = State(initialValue: basis?.memo ?? source?.memo ?? "")
        _frequency = State(initialValue: basis?.frequency ?? .monthly)
        let start = basis?.startDate ?? source?.date ?? Calendar.current.startOfDay(for: .now)
        _startDate = State(initialValue: start)
        _hasEnd = State(initialValue: basis?.endDate != nil)
        _endDate = State(initialValue: basis?.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: start) ?? start)
        _autoEnter = State(initialValue: basis?.autoEnter ?? true)
    }

    /// The same accounts New Transaction offers: not loans, cards, Cash on Hand or investments.
    private var choosable: [Account] {
        allAccounts.live.filter { !$0.isLoan && !$0.isCreditCard && !$0.isCashOnHand && !$0.supportsHoldings }
    }

    private var canSave: Bool {
        !payee.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0 && account != nil
            && (!hasEnd || endDate >= startDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("What repeats") {
                    FormTextField("Payee", text: $payee)
                    Picker("Account", selection: $account) {
                        Text("Choose…").tag(Account?.none)
                        ForEach(choosable) { Text($0.name).tag(Optional($0)) }
                    }
                    Picker("Type", selection: $isPayment) {
                        Text("Payment (money out)").tag(true)
                        Text("Deposit (money in)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    CurrencyField("Amount", value: $amount)
                    Picker("Category", selection: $category) {
                        CategoryOptions(categories: allCategories.live, only: isPayment ? .expense : .income, keeping: category)
                    }
                    if account?.lockedPaymentType == nil {
                        Picker("Payment method", selection: $paymentChoice) { PaymentTypeOptions() }
                    }
                    FormTextField("Memo", text: $memo)
                }
                Section("When") {
                    Picker("Repeats", selection: $frequency) {
                        ForEach(BillFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker(frequency == .once ? "Date" : "First date", selection: $startDate, displayedComponents: .date)
                    if frequency != .once {
                        Toggle("Stops on a date", isOn: $hasEnd)
                        if hasEnd { DatePicker("Last date", selection: $endDate, in: startDate..., displayedComponents: .date) }
                    }
                }
                Section {
                    Toggle("Add a pending transaction automatically", isOn: $autoEnter)
                } footer: {
                    Text(autoEnter
                         ? "On each due date a pending transaction appears in the account's register. Confirm it, or change it with Edit Transaction."
                         : "Nothing is added by itself. The rule shows as Due here, and you choose Add Now or Skip.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(rule == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 500, height: 640)
        .background(Theme.background)
        .onChange(of: isPayment) { _, new in
            if let category, category.isIncome == new { self.category = nil }
        }
        .onAppear {
            // A rule's own payment method, which can be one of yours.
            guard !loadedMethod else { return }
            loadedMethod = true
            if let raw = rule?.paymentTypeRaw, !raw.isEmpty {
                if let type = PayeeMemory.builtInMethod(raw) {
                    paymentChoice = .type(type)
                } else if raw.hasPrefix("custom:"), let method = allMethods.live.first(where: { $0.name == String(raw.dropFirst(7)) }) {
                    paymentChoice = .custom(method)
                }
            }
            if let account, !choosable.contains(where: { $0 === account }) { self.account = nil }
        }
    }

    private func save() {
        guard let account, let amount else { return }
        let signed = isPayment ? -amount : amount
        let cleaned = payee.trimmingCharacters(in: .whitespaces)
        let methodRaw = account.lockedPaymentType == nil ? PayeeMemory.raw(paymentChoice) : ""
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)

        let target: RecurringTransaction
        if let rule {
            target = rule
            let schedule = rule.frequencyRaw != frequency.rawValue || calendar.startOfDay(for: rule.startDate) != start
            apply(to: target, cleaned, account, signed, methodRaw, start)
            if schedule { target.nextDate = Recurring.firstDue(onOrAfter: .now, for: target) ?? start }
        } else {
            target = RecurringTransaction(payee: cleaned, account: account, category: category, amount: signed, frequency: frequency, startDate: start)
            apply(to: target, cleaned, account, signed, methodRaw, start)
            modelContext.insert(target)
            if let source {
                // Made from a transaction: that one is the first, so the next entry is the one after it.
                source.recurring = target
                target.nextDate = Recurring.date(after: source.date, for: target) ?? start
                if target.nextDate <= calendar.startOfDay(for: source.date) { target.isActive = false }
            } else {
                // A start in the past doesn't add the days that already went by.
                target.nextDate = Recurring.firstDue(onOrAfter: .now, for: target) ?? start
            }
        }
        modelContext.saveNow()
        Recurring.run(in: modelContext)
        dismiss()
    }

    private func apply(to target: RecurringTransaction, _ payee: String, _ account: Account, _ signed: Decimal, _ methodRaw: String, _ start: Date) {
        target.payee = payee
        target.account = account
        target.category = category
        target.memo = memo
        target.amount = signed
        target.paymentTypeRaw = methodRaw
        target.frequency = frequency
        target.startDate = start
        target.endDate = hasEnd && frequency != .once ? Calendar.current.startOfDay(for: endDate) : nil
        target.autoEnter = autoEnter
    }
}
