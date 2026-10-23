import SwiftUI
import SwiftData

/// The Recurring tab on the Bills page, laid out like the Bills side: tiles and the month's list on the left, the calendar,
/// the add button and what is coming up in the sidebar.
struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringTransaction.createdAt) private var allRules: [RecurringTransaction]
    @State private var editing: RuleSheet?
    @State private var deleting: RecurringTransaction?
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date?

    private var rules: [RecurringTransaction] { allRules.live }
    private var calendar: Calendar { .current }
    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var monthEnd: Date { calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: monthStart)!)! }

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
        let monthItems = Recurring.occurrences(rules, from: monthStart, through: monthEnd)
        let coming = Recurring.upcoming(rules)
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    tiles(monthItems, coming: coming)
                    monthCard(monthItems)
                }
                .padding(16)
            }
            Divider()
            // The calendar and the button stay put, and the All Recurring card takes the rest of the column, down to the bottom.
            VStack(spacing: 14) {
                MonthCalendar(month: $month, selectedDay: $selectedDay, marks: monthItems.map { CalendarMark(date: $0.date, color: dotColor($0)) })
                addButton
                rulesCard
            }
            .padding(16)
            .frame(width: 360)
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            switch note.userInfo?["action"] as? String {
            case "addRule": editing = .add
            case "editRule": if let rule = rules.first { editing = .edit(rule) }
            case "closeSheets": editing = nil
            default: break
            }
        }
        #endif
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
                    changed()
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Transactions it already added stay in your registers.")
        }
    }

    /// Saves, and brings the reminders and widgets up to date.
    private func changed() {
        modelContext.saveNow()
        Task { await BillNotifier.refresh(in: modelContext) }
    }

    private func dotColor(_ item: Recurring.Occurrence) -> Color {
        switch item.kind {
        case .added: Theme.green
        case .due: item.isOverdue ? Theme.red : .orange
        case .coming: item.rule.amount > 0 ? Color.blue : .orange
        }
    }

    // MARK: Tiles

    private func tiles(_ items: [Recurring.Occurrence], coming: [Recurring.Occurrence]) -> some View {
        func amount(_ item: Recurring.Occurrence) -> Decimal { item.entry?.amount ?? item.rule.amount }
        let moneyIn = items.map(amount).filter { $0 > 0 }.reduce(Decimal(0), +)
        let moneyOut = -items.map(amount).filter { $0 < 0 }.reduce(Decimal(0), +)
        let next = coming.first { $0.kind == .coming }
        return StatGrid {
            StatTile(title: "In This Month") {
                Text(moneyIn, format: .appCurrency).foregroundStyle(Theme.green)
            } note: { Text("from repeating deposits") }
            StatTile(title: "Out This Month") {
                Text(moneyOut, format: .appCurrency).foregroundStyle(Theme.red)
            } note: { Text("from repeating payments") }
            StatTile(title: "Next Up") {
                if let next { Text(next.date, format: .dateTime.month(.abbreviated).day()) } else { Text("None") }
            } note: {
                Text(next?.rule.payee ?? "Nothing coming up")
            }
            StatTile(title: "Rules") {
                Text("\(rules.filter(\.isActive).count)")
            } note: { Text("\(rules.filter { !$0.isActive }.count) paused or finished") }
        }
    }

    /// Right under the calendar, so a new rule is always one click away.
    private var addButton: some View {
        Button { editing = .add } label: {
            Label("Add Recurring", systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: Lists

    private func monthCard(_ items: [Recurring.Occurrence]) -> some View {
        let shown = selectedDay.map { day in items.filter { calendar.isDate($0.date, inSameDayAs: day) } } ?? items
        let title = selectedDay.map { $0.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
            ?? monthStart.formatted(.dateTime.month(.wide).year())
        return ReportCard(title: title, fillsHeight: false) {
            VStack(alignment: .leading, spacing: 8) {
                if selectedDay != nil {
                    HStack {
                        Button("Show whole month") { selectedDay = nil }
                        Spacer()
                    }
                    .font(.callout)
                    .buttonStyle(.borderless)
                }
                if shown.isEmpty {
                    Text(selectedDay == nil ? "Nothing repeats this month." : "Nothing repeats on this day.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(shown) { item in
                        OccurrenceRow(item: item, onEdit: { editing = .edit(item.rule) }, onDelete: { deleting = item.rule }, onChange: changed)
                        if item.id != shown.last?.id { Divider() }
                    }
                }
            }
        }
    }

    /// Every rule that is set up, with the day it comes out and the amount, for editing, pausing, resuming and deleting.
    /// Paused and finished ones only show here. The month's list on the left is where entries are checked off.
    private var rulesCard: some View {
        ReportCard(title: "All Recurring", fillsHeight: true) {
            if rules.isEmpty {
                ContentUnavailableView("No Recurring Transactions", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Add one for a paycheque, rent or anything else that repeats. You can also right-click a transaction in a register and choose Make Recurring."))
                    .frame(height: 200)
            } else {
                // More rules than fit scroll inside the card.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rules.enumerated()), id: \.element.persistentModelID) { index, rule in
                            if index > 0 { Divider() }
                            RuleRow(rule: rule, onEdit: { editing = .edit(rule) }, onDelete: { deleting = rule })
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 200)
    }
}

/// One date of one rule, drawn like a bill: a status mark, the payee, the day and how often, and the amount.
private struct OccurrenceRow: View {
    let item: Recurring.Occurrence
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onChange: () -> Void

    @Environment(\.modelContext) private var modelContext

    private var amount: Decimal { item.entry?.amount ?? item.rule.amount }

    var body: some View {
        if item.rule.isLive {
            HStack(spacing: 12) {
                checkOff
                Button(action: onEdit) {
                    HStack {
                        RuleIconView(rule: item.rule, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.rule.payee).font(.body)
                            Text(subtitle).font(.caption).foregroundStyle(item.isOverdue ? Theme.red : (item.kind == .added ? Theme.green : Color.secondary))
                        }
                        Spacer()
                        Text(amount, format: .appCurrency)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(item.kind == .added ? Color.secondary : Color.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if item.kind == .due {
                    Button("Add") {
                        Recurring.makeEntry(for: item.rule, on: item.date, in: modelContext)
                        Recurring.advance(item.rule)
                        onChange()
                    }
                    Button("Skip") {
                        Recurring.advance(item.rule)
                        onChange()
                    }
                }
            }
            .padding(.vertical, 8)
            .contextMenu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                if item.kind == .coming, Calendar.current.isDate(item.rule.nextDate, inSameDayAs: item.date) {
                    Button("Skip This One", systemImage: "forward.end") {
                        Recurring.advance(item.rule)
                        onChange()
                    }
                }
                if item.rule.isActive {
                    Button("Pause", systemImage: "pause.circle") {
                        item.rule.isActive = false
                        onChange()
                    }
                }
                Divider()
                Button("Delete Rule", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }

    private var isPending: Bool { item.entry?.state == .pending }

    /// The mark at the left, which works like a bill's: tick it to say it is done. A date waiting for you (reminder only)
    /// is added by ticking it. An entry the rule made is ticked to confirm it, and ticked again to take that back.
    private var checkOff: some View {
        Button {
            switch item.kind {
            case .due:
                Recurring.makeEntry(for: item.rule, on: item.date, in: modelContext)
                Recurring.advance(item.rule)
                onChange()
            case .added:
                guard let entry = item.entry, entry.isLive else { return }
                Recurring.toggleConfirmed(entry)
                onChange()
            case .coming:
                break
            }
        } label: {
            Image(systemName: item.kind == .added ? (isPending ? "circle.lefthalf.filled" : "checkmark.circle.fill") : "circle")
                .font(.title3)
                .foregroundStyle(item.kind == .added ? (isPending ? Color.orange : Theme.green) : (item.isOverdue ? Theme.red : Color.secondary))
        }
        .buttonStyle(.plain)
        .disabled(item.kind == .coming)
        .help(item.kind == .due ? "Add it now" : (item.kind == .added ? (isPending ? "Mark as confirmed and reconciled" : "Mark as waiting to be confirmed") : "It is added on its date"))
    }

    private var subtitle: String {
        let day = item.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let tail: String
        switch item.kind {
        case .added: tail = isPending ? "Added · waiting to confirm" : (item.entry?.state == .reconciled ? "Added · reconciled" : "Added · confirmed")
        case .due: tail = item.isOverdue ? "Overdue" : "Due"
        case .coming: tail = item.rule.frequency.title
        }
        return "\(day) · \(tail)"
    }
}

private struct RuleRow: View {
    @Environment(\.modelContext) private var modelContext
    let rule: RecurringTransaction
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// Saves, and brings the reminders and widgets up to date.
    private func changed() {
        modelContext.saveNow()
        Task { await BillNotifier.refresh(in: modelContext) }
    }

    private var isDue: Bool { rule.isActive && rule.nextDate <= Calendar.current.startOfDay(for: .now) }

    private var statusText: String {
        if !rule.isActive { return rule.endDate != nil && Recurring.date(after: rule.nextDate, for: rule) == nil ? "Finished" : "Paused" }
        if !rule.autoEnter { return isDue ? "Due" : "Reminder only" }
        return "Active"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onEdit) {
                HStack(spacing: 10) {
                    RuleIconView(rule: rule, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(rule.payee).font(.body).lineLimit(1)
                            if statusText != "Active" {
                                Text(statusText)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(statusColor.opacity(0.18), in: Capsule())
                                    .foregroundStyle(statusColor)
                            }
                        }
                        Text(rule.frequency.schedule(from: rule.startDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(rule.amount, format: .appCurrency)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(rule.amount > 0 ? Theme.green : Theme.red)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                if rule.isActive {
                    Button("Skip Next", systemImage: "forward.end") {
                        Recurring.advance(rule)
                        changed()
                    }
                    Button("Pause", systemImage: "pause.circle") {
                        rule.isActive = false
                        changed()
                    }
                } else if Recurring.date(after: rule.nextDate, for: rule) != nil || rule.frequency == .once && rule.nextDate >= Calendar.current.startOfDay(for: .now) {
                    Button("Resume", systemImage: "play.circle") {
                        // Pick up from today, not from the days that passed while it was paused.
                        if let next = Recurring.firstDue(onOrAfter: .now, for: rule) { rule.nextDate = next }
                        rule.isActive = true
                        changed()
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(rule.payee)")
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
    /// The icon chosen for the rule, or nil for its category's own.
    @State private var iconSymbol: String?
    @State private var artworkTheme = 0

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

    /// Two columns on one wide window, so nothing scrolls: what repeats on the left, when and how it is added on the right.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(rule == nil ? "New Recurring Transaction" : "Edit Recurring Transaction").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("What Repeats") {
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
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                Divider()
                Form {
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
                    Section("Adding It") {
                        Toggle("Add a pending transaction automatically", isOn: $autoEnter)
                        Text(autoEnter
                             ? "On each due date a pending transaction appears in the account's register. Confirm it, or change it with Edit Transaction."
                             : "Nothing is added by itself. The rule shows as Due here, and you choose Add Now or Skip.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                Divider()
                Form {
                    Section("Icon") { IconPicker(symbol: $iconSymbol, theme: $artworkTheme, category: category, rainbowSeed: ArtworkTheme.seed(payee)) }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(width: 360)
            }
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(rule == nil ? "Add" : "Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .frame(width: 1200, height: 440)
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
            if let rule {
                iconSymbol = ItemIcons.symbol(of: ItemIcons.key(for: rule), in: modelContext)
                artworkTheme = ((try? modelContext.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).live.first { $0.key == ItemIcons.key(for: rule) }?.theme ?? 0
            }
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
        ItemIcons.set(iconSymbol, owner: ItemIcons.key(for: target), in: modelContext)
        ArtworkChoices.apply(artworkTheme, key: ItemIcons.key(for: target), in: modelContext)
        modelContext.saveNow()
        Recurring.run(in: modelContext)
        Task { await BillNotifier.refresh(in: modelContext) }
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
