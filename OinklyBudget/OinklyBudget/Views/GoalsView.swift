import SwiftUI
import SwiftData

private enum GoalSheet: Identifiable {
    case add
    case edit(Goal)
    case progress(Goal)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let goal): "edit-\(goal.persistentModelID.hashValue)"
        case .progress(let goal): "progress-\(goal.persistentModelID.hashValue)"
        }
    }
}

/// Every goal, saving up or paying off a debt. Goals stand on their own: you record progress on the goal itself.
struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.createdAt) private var allGoals: [Goal]
    private var goals: [Goal] { allGoals.live }
    @Query(sort: \Account.name) private var allAccounts: [Account]

    /// Loans with a maturity date that no goal already follows. They sit with the goals so you can see whether the
    /// loan will be paid off before it matures.
    private var datedLoans: [Account] {
        let followed = Set(goals.filter { !$0.isArchived }.compactMap { $0.followedAccount?.persistentModelID })
        return allAccounts.live.filter { $0.isLoan && !$0.isClosed && $0.payoffDate != nil && !followed.contains($0.persistentModelID) && !$0.loanProgress.isPaidOff }
    }

    /// Set by the Planning header's New Goal button. Reset as soon as the sheet opens.
    @Binding var isAdding: Bool

    @State private var sheet: GoalSheet?
    @State private var detail: Goal?
    @State private var deleting: Goal?

    /// Goals still being worked on: nearest date first, then ones with no date.
    private var activeGoals: [Goal] {
        let open = goals.filter { !$0.isArchived }
        let dated = open.filter { $0.targetDate != nil }.sorted { $0.targetDate! < $1.targetDate! }
        let undated = open.filter { $0.targetDate == nil }.sorted { $0.name < $1.name }
        return dated + undated
    }

    /// Reached goals, most recent first. They are archived: they keep their final amount and take no new data.
    private var archivedGoals: [Goal] {
        goals.filter(\.isArchived).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        let open = activeGoals
        let archived = archivedGoals
        let saving = open.filter { !$0.isPayoff }
        let paying = open.filter(\.isPayoff)
        let saved = saving.reduce(Decimal(0)) { $0 + min($1.saved, $1.targetAmount) }
        let savingTarget = saving.reduce(Decimal(0)) { $0 + $1.targetAmount }
        let paidDown = paying.reduce(Decimal(0)) { $0 + min($1.saved, $1.targetAmount) }
        let payoffTarget = paying.reduce(Decimal(0)) { $0 + $1.targetAmount }
        let needed = open.compactMap { $0.progress().neededPerMonth }.reduce(Decimal(0), +)

        ScrollView {
            VStack(spacing: 14) {
                if goals.isEmpty && datedLoans.isEmpty {
                    empty
                } else {
                    StatGrid {
                        StatTile(title: "Saved") {
                            Text(saved, format: .appCurrency).foregroundStyle(Theme.green)
                        } note: {
                            Text("of \(savingTarget.formatted(.appCurrency)) · \(saving.count) goal\(saving.count == 1 ? "" : "s")")
                        }
                        StatTile(title: "Debt Paid Down") {
                            Text(paidDown, format: .appCurrency).foregroundStyle(Theme.green)
                        } note: {
                            Text("of \(payoffTarget.formatted(.appCurrency)) · \(paying.count) goal\(paying.count == 1 ? "" : "s")")
                        }
                        StatTile(title: "Needed Per Month") {
                            Text(needed, format: .appCurrency)
                        } note: {
                            Text("to hit every date")
                        }
                        StatTile(title: "Reached") {
                            Text("\(archived.count)")
                        } note: {
                            Text("of \(goals.count) goal\(goals.count == 1 ? "" : "s")")
                        }
                    }

                    ForEach(open) { goal in
                        if goal.isLive { card(goal) }
                    }

                    if !datedLoans.isEmpty {
                        HStack {
                            Text("LOANS WITH A MATURITY DATE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 6)
                        ForEach(datedLoans) { LoanPlanCard(account: $0) }
                    }

                    if !archived.isEmpty {
                        HStack {
                            Text("COMPLETED").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 6)
                        ForEach(archived) { goal in
                            if goal.isLive { card(goal) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .onChange(of: isAdding) {
            if isAdding { sheet = .add; isAdding = false }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "this goal")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Goal", role: .destructive) {
                if let goal = deleting, goal.isLive { modelContext.delete(goal); modelContext.saveNow() }
                deleting = nil
            }
        } message: {
            Text("The goal and the progress you recorded on it are removed. Your accounts aren't affected.")
        }
        .onAppear { GoalArchiver.archiveReached(in: modelContext) }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            switch note.userInfo?["action"] as? String {
            case "addGoal": sheet = .add
            case "goalDetail": detail = goals.first
            case "closeSheets": sheet = nil; detail = nil
            default: break
            }
        }
        #endif
        .sheet(item: $sheet) { item in
            switch item {
            case .add: GoalEditView(goal: nil)
            case .edit(let goal): GoalEditView(goal: goal)
            case .progress(let goal): GoalProgressSheet(goal: goal)
            }
        }
        .sheet(item: $detail) { goal in
            GoalDetailView(goal: goal) {
                detail = nil
                sheet = .edit(goal)
            }
        }
    }

    private func card(_ goal: Goal) -> some View {
        GoalCard(goal: goal, onOpen: { detail = goal }, onProgress: { sheet = .progress(goal) })
            .contextMenu {
                if !goal.isArchived && !goal.isLinked {
                    Button(goal.isPayoff ? "Add a Payment" : "Add to Savings", systemImage: "plus.circle") { sheet = .progress(goal) }
                }
                Button("Edit", systemImage: "pencil") { sheet = .edit(goal) }
                Button("Delete Goal", systemImage: "trash", role: .destructive) { deleting = goal }
            }
    }

    private var empty: some View {
        ReportCard(title: "No Goals Yet") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Save toward something, like an emergency fund, a trip or a down payment, or set a goal to pay a debt down. Give it a target and a date. Follow a savings or checking account, or a loan or card, and the goal keeps up on its own, or add progress yourself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Create Your First Goal") { sheet = .add }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: Card

/// A card without a title, in the same look as the report cards.
private struct GoalCardBackground<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GoalCard: View {
    let goal: Goal
    let onOpen: () -> Void
    let onProgress: () -> Void

    var body: some View {
        let progress = goal.progress()
        let color = Color(hex: goal.colorHex)
        GoalCardBackground {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            if let account = goal.followedAccount {
                                AccountPicture(data: account.supportsPhoto ? account.photoData : nil, type: account.type, account: account)
                                    .frame(width: 64, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                CategoryBadge(symbol: goal.symbol, color: color, size: 44)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.name).font(.headline)
                                Text(subtitle(progress)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            statusBadge(progress)
                        }

                        ProgressView(value: progress.fraction).tint(progress.isAchieved ? Theme.green : color)

                        HStack(alignment: .firstTextBaseline) {
                            Text(goal.saved, format: .appCurrency).font(.title3.bold())
                            Text(goal.isPayoff ? "paid" : "saved").foregroundStyle(.secondary)
                            Text(progress.fraction, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary)
                            Spacer()
                            if !progress.isAchieved {
                                Text("\(progress.remaining.formatted(.appCurrency)) / \(goal.targetAmount.formatted(.appCurrency)) \(goal.isPayoff ? "left" : "to go")")
                                    .font(.callout.weight(.medium))
                            }
                        }
                        .font(.subheadline)

                        if !progress.isAchieved, let projected = progress.projectedDate {
                            Text("\(goal.isPayoff ? "Estimated payoff" : "Estimated finish") \(projected.formatted(.dateTime.month(.abbreviated).year()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let account = goal.followedAccount {
                    Label("Follows \(account.name)", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !goal.isArchived {
                    Button(action: onProgress) {
                        Label(goal.isPayoff ? "Make Progress: Add a Payment" : "Make Progress: Add to Savings", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(color)
                }
            }
        }
    }

    private func subtitle(_ p: GoalProgress) -> String {
        if let done = goal.completedAt {
            return goal.isPayoff ? "Paid off \(done.formatted(.dateTime.month(.abbreviated).day().year()))"
                                 : "Reached \(done.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        var parts: [String] = []
        if !goal.categoryName.isEmpty { parts.append(goal.categoryName) }
        if let date = goal.targetDate { parts.append("by \(date.formatted(.dateTime.month(.abbreviated).year()))") }
        if let needed = p.neededPerMonth { parts.append("\(needed.formatted(.appCurrency))/mo") }
        return parts.isEmpty ? "No date set" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statusBadge(_ p: GoalProgress) -> some View {
        switch p.status {
        case .achieved: badge(goal.isPayoff ? "Paid off" : "Reached", "checkmark.circle.fill", Theme.green)
        case .onTrack: badge("On track", "checkmark.circle", Theme.green)
        case .behind: badge("Behind", "exclamationmark.triangle.fill", .orange)
        case .pastDue: badge("Past date", "exclamationmark.octagon.fill", Theme.red)
        case .noDate: EmptyView()
        }
    }

    private func badge(_ text: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 4) { Image(systemName: symbol); Text(text) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize()
    }
}

// MARK: Make progress

/// Record progress on a goal: a payment toward a debt, or money added to savings.
struct GoalProgressSheet: View {
    let goal: Goal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Decimal?
    @State private var takingBack = false
    @State private var date = Date.now
    @State private var note = ""

    private var addTitle: String { goal.isPayoff ? "Payment" : "Add" }
    private var backTitle: String { goal.isPayoff ? "Borrowed more" : "Take out" }

    var body: some View {
        NavigationStack {
            Form {
                if goal.isLive {
                    Section {
                        HStack(spacing: 12) {
                            CategoryBadge(symbol: goal.symbol, color: Color(hex: goal.colorHex), size: 40)
                            VStack(alignment: .leading) {
                                Text(goal.name).font(.headline)
                                Text(summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Picker("", selection: $takingBack) {
                            Text(addTitle).tag(false)
                            Text(backTitle).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        LabeledContent("Amount") {
                            CurrencyField("Amount", value: $amount).labelsHidden().multilineTextAlignment(.trailing)
                        }
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        FormTextField("Note", text: $note)
                    } footer: {
                        Text(goal.isPayoff
                             ? "Record a payment you made toward this debt. It counts against what you still owe on the goal. This doesn't change any account."
                             : "Record money you set aside toward this goal. This doesn't change any account.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(goal.isPayoff ? "Add a Payment" : "Add to Savings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled((amount ?? 0) <= 0) }
            }
        }
        .macSheetFrame(minHeight: 420)
    }

    private var summary: String {
        let p = goal.progress()
        return goal.isPayoff
            ? "\(goal.owedNow.formatted(.appCurrency)) still owed · \(p.remaining.formatted(.appCurrency)) left to pay down"
            : "\(goal.saved.formatted(.appCurrency)) of \(goal.targetAmount.formatted(.appCurrency)) saved"
    }

    private func save() {
        guard goal.isLive, let amount, amount > 0 else { return }
        modelContext.insert(GoalContribution(goal: goal, amount: takingBack ? -amount : amount,
                                             date: Calendar.current.startOfDay(for: date), note: note))
        modelContext.saveNow()
        GoalArchiver.archiveReached(in: modelContext)
        dismiss()
    }
}

// MARK: Detail

struct GoalDetailView: View {
    let goal: Goal
    let onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var addingProgress = false

    var body: some View {
        NavigationStack {
            if goal.isLive { content } else { Text("This goal was deleted.").foregroundStyle(.secondary) }
        }
        .macSheetFrame(minHeight: 560)
    }

    private var content: some View {
        let progress = goal.progress()
        return Form {
            Section {
                HStack(spacing: 12) {
                    CategoryBadge(symbol: goal.symbol, color: Color(hex: goal.colorHex), size: 44)
                    VStack(alignment: .leading) {
                        Text(goal.name).font(.title3.bold())
                        Text([goal.categoryName, goal.targetDate.map { "Target \($0.formatted(.dateTime.month(.wide).day().year()))" }]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: progress.fraction).tint(progress.isAchieved ? Theme.green : Color(hex: goal.colorHex))
                if goal.isPayoff {
                    LabeledContent("Owed when you started", value: goal.startingAmount.formatted(.appCurrency))
                    LabeledContent("Paid so far") { Text(goal.saved, format: .appCurrency).foregroundStyle(Theme.green) }
                    LabeledContent("Still owed") { Text(goal.owedNow, format: .appCurrency).foregroundStyle(goal.owedNow > 0 ? Theme.red : Theme.green) }
                    LabeledContent("Goal", value: goal.goalBalance > 0 ? "Down to \(goal.goalBalance.formatted(.appCurrency))" : "Paid off")
                    LabeledContent("Left to pay down", value: progress.remaining.formatted(.appCurrency))
                } else {
                    LabeledContent("Saved") { Text(goal.saved, format: .appCurrency).foregroundStyle(Theme.green) }
                    LabeledContent("Target", value: goal.targetAmount.formatted(.appCurrency))
                    LabeledContent("Still to go", value: progress.remaining.formatted(.appCurrency))
                }
                if let account = goal.followedAccount {
                    LabeledContent("\(account.name) balance", value: account.balance.formatted(.appCurrency))
                }
                if let needed = progress.neededPerMonth {
                    LabeledContent("Needed per month", value: needed.formatted(.appCurrency))
                }
                if let pace = progress.monthlyPace, !progress.isAchieved {
                    LabeledContent(goal.isPayoff ? "Your pace (last 3 months)" : "Your pace (last 3 months)", value: "\(pace.formatted(.appCurrency))/mo")
                }
                if let projected = progress.projectedDate {
                    LabeledContent("At this pace", value: projected.formatted(.dateTime.month(.abbreviated).year()))
                }
            }

            if let done = goal.completedAt {
                Section {
                    Label(goal.isPayoff ? "Paid off on \(done.formatted(.dateTime.month(.wide).day().year()))"
                                        : "Reached on \(done.formatted(.dateTime.month(.wide).day().year()))",
                          systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.green)
                } footer: {
                    Text("This goal is archived. It keeps its final amount and takes no new progress.")
                }
            } else if let account = goal.followedAccount {
                Section {
                    Label(account.name, systemImage: "link")
                } header: {
                    Text("Follows")
                } footer: {
                    Text(goal.isPayoff
                         ? "Payments you make on this account, including with Pay a Bill, count toward the goal on their own."
                         : "Money added to this account counts toward the goal on its own.")
                }
            } else {
                Section {
                    Button(goal.isPayoff ? "Add a Payment" : "Add to Savings", systemImage: "plus.circle.fill") { addingProgress = true }
                }
            }

            let history = goal.contributions.live.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
            if !history.isEmpty {
                Section("History") {
                    ForEach(history) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(label(for: item))
                                Text([item.date.formatted(.dateTime.month(.abbreviated).day().year()), item.note]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.amount, format: .appCurrency)
                                .foregroundStyle(item.amount >= 0 ? Theme.green : Theme.red)
                            if !goal.isArchived {
                                Button { delete(item) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Delete this entry")
                            }
                        }
                    }
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle("Goal")
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                HStack(spacing: 8) {
                    Button("Delete Goal", role: .destructive) { confirmingDelete = true }
                    Button("Edit Goal", action: onEdit)
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(isPresented: $addingProgress) { GoalProgressSheet(goal: goal) }
        .confirmationDialog("Delete this goal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Goal", role: .destructive) {
                dismiss()
                if goal.isLive { modelContext.delete(goal); modelContext.saveNow() }
            }
        } message: {
            Text("The goal and the progress you recorded on it are removed. Your accounts aren't affected.")
        }
    }

    private func label(for item: GoalContribution) -> String {
        if goal.isPayoff { return item.amount >= 0 ? "Payment" : "Borrowed more" }
        return item.amount >= 0 ? "Added" : "Taken out"
    }

    private func delete(_ item: GoalContribution) {
        modelContext.delete(item)
        modelContext.saveNow()
    }
}

// MARK: Add / edit

struct GoalEditView: View {
    let goal: Goal?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var kind: GoalKind
    @State private var category: GoalCategory?
    @State private var name: String
    @State private var target: Decimal?
    @State private var starting: Decimal?
    @State private var owed: Decimal?
    @State private var payoffTo: Decimal?
    @State private var hasDate: Bool
    @State private var targetDate: Date
    @State private var notes: String
    @State private var confirmingDelete = false
    @State private var accountID: PersistentIdentifier?
    @State private var fromNow: Bool
    @State private var makeAccount = false
    @State private var newInstitution = ""
    @State private var newAccountNumber = ""
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var allCategories: [Category]

    init(goal: Goal?) {
        self.goal = goal
        let kind = goal?.kind ?? .save
        _kind = State(initialValue: kind)
        _category = State(initialValue: GoalCategory.list(for: kind).first { $0.title == goal?.categoryName })
        _name = State(initialValue: goal?.name ?? "")
        _target = State(initialValue: goal.flatMap { $0.isPayoff ? nil : $0.targetAmount })
        _starting = State(initialValue: goal.flatMap { !$0.isPayoff && $0.startingAmount != 0 ? $0.startingAmount : nil })
        _owed = State(initialValue: goal.flatMap { $0.isPayoff ? $0.startingAmount : nil })
        _payoffTo = State(initialValue: goal.flatMap { $0.isPayoff && $0.goalBalance != 0 ? $0.goalBalance : nil })
        _hasDate = State(initialValue: goal?.targetDate != nil)
        _targetDate = State(initialValue: goal?.targetDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _notes = State(initialValue: goal?.notes ?? "")
        _accountID = State(initialValue: goal?.followedAccount?.persistentModelID)
        _fromNow = State(initialValue: goal?.followedAccount != nil && !(goal?.isPayoff ?? false) && (goal?.startingAmount ?? 0) != 0)
    }

    /// Accounts this goal could follow: checking and savings for saving, cards and loans for debts. An account can
    /// have one open goal, so any that another goal already follows are left out.
    private var followable: [Account] {
        let taken = Set(((try? modelContext.fetch(FetchDescriptor<Goal>())) ?? []).live
            .filter { $0 !== goal && $0.isLinked }.compactMap { $0.followedAccount?.persistentModelID })
        return allAccounts.live.filter { account in
            guard !account.isClosed, !taken.contains(account.persistentModelID) else { return false }
            return kind == .save ? account.type.group == .checkingSavings && account.type != .cash
                                 : account.type.group == .creditCards || account.type.group == .loans
        }
    }

    private var linked: Account? { followable.first { $0.persistentModelID == accountID } }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if kind == .payoff { return (linked.map { Goal.owed(on: $0) } ?? owed ?? 0) > (payoffTo ?? 0) }
        return (target ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Goal type", selection: $kind) {
                        ForEach(GoalKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(goal != nil)
                    .onChange(of: kind) { _, _ in category = nil; accountID = nil }

                    Picker(kind == .save ? "What are you saving for?" : "What kind of debt?", selection: $category) {
                        Text("Choose…").tag(GoalCategory?.none)
                        ForEach(GoalCategory.list(for: kind)) { item in
                            Label(item.title, systemImage: item.symbol).tag(Optional(item))
                        }
                    }
                    .onChange(of: category) { _, new in
                        if let new, name.trimmingCharacters(in: .whitespaces).isEmpty { name = new.title }
                    }

                    FormTextField("Name", text: $name, hint: kind == .save ? "e.g. Japan trip" : "e.g. Pay off Visa")
                }

                Section {
                    Picker(kind == .save ? "Follow an account" : "Follow a loan or card", selection: $accountID) {
                        Text("None, I'll add progress myself").tag(PersistentIdentifier?.none)
                        ForEach(followable) { account in
                            Text(account.name).tag(Optional(account.persistentModelID))
                        }
                    }
                    if let linked, kind == .save {
                        Toggle("Count only what's added from now on", isOn: $fromNow)
                    }
                    if kind == .save && accountID == nil && goal?.followedAccount == nil {
                        Toggle("Create a savings account for this goal", isOn: $makeAccount)
                    }
                } footer: {
                    if let linked {
                        Text(kind == .save
                             ? (fromNow ? "Progress is the money added to \(linked.name) after today, starting from \(max(linked.balance, 0).formatted(.appCurrency))."
                                        : "Progress is the whole balance of \(linked.name).")
                             : "Progress is how far the balance of \(linked.name) comes down from \(Goal.owed(on: linked).formatted(.appCurrency)) owed today. Payments count on their own.")
                    } else if makeAccount {
                        Text("A new savings account named after the goal is made when you save, so this money has its own place. Fill in its details below.")
                    } else {
                        Text("Link a goal to an account and it keeps up by itself. An account can have one goal at a time.")
                    }
                }

                if makeAccount && kind == .save && accountID == nil {
                    Section {
                        FormTextField("Institution", text: $newInstitution, hint: "Optional")
                        FormTextField("Account number", text: $newAccountNumber, hint: "Optional, up to 17 digits")
                            .onChange(of: newAccountNumber) { _, new in
                                let clean = Account.digits(new, limit: Account.maxAccountNumberLength)
                                if clean != new { newAccountNumber = clean }
                            }
                        LabeledContent("Starting balance", value: max(starting ?? 0, 0).formatted(.appCurrency))
                    } header: {
                        Text("New Savings Account")
                    } footer: {
                        Text("The starting balance is what you entered as already saved below.")
                    }
                }

                Section {
                    if kind == .save {
                        LabeledContent("Target amount") {
                            CurrencyField("Target amount", value: $target).labelsHidden().multilineTextAlignment(.trailing)
                        }
                        if linked == nil {
                            LabeledContent("Already saved") {
                                CurrencyField("Already saved", value: $starting).labelsHidden().multilineTextAlignment(.trailing)
                            }
                        }
                    } else {
                        if let linked {
                            LabeledContent("Amount owed today", value: Goal.owed(on: linked).formatted(.appCurrency))
                        } else {
                            LabeledContent("Amount owed") {
                                CurrencyField("Amount owed", value: $owed).labelsHidden().multilineTextAlignment(.trailing)
                            }
                        }
                        LabeledContent("Pay it down to") {
                            CurrencyField("Leave empty for paid off", value: $payoffTo).labelsHidden().multilineTextAlignment(.trailing)
                        }
                        if let owed = linked.map({ Goal.owed(on: $0) }) ?? owed, owed > 0 {
                            LabeledContent("Amount to pay down", value: max(owed - (payoffTo ?? 0), 0).formatted(.appCurrency))
                        }
                    }
                    Toggle("Set a target date", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Target date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                    }
                } footer: {
                    Text(linked != nil
                         ? (kind == .save ? "The goal follows the account, so there is nothing to add by hand."
                                          : "Leave \"Pay it down to\" empty to aim for paid off.")
                         : (kind == .save
                            ? "Add money to the goal from its card whenever you set some aside."
                            : "Record payments from the goal's card as you make them. Leave \"Pay it down to\" empty to aim for paid off."))
                }

                Section("Notes") {
                    FormTextField("Notes", text: $notes, hint: "Add a note", axis: .vertical, showsLabel: false).lineLimit(1...4)
                }

            }
            .formStyle(.grouped)
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if goal != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete Goal", role: .destructive) { confirmingDelete = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .confirmationDialog("Delete this goal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Goal", role: .destructive) {
                    if let goal { modelContext.delete(goal) }
                    modelContext.saveNow()
                    dismiss()
                }
            } message: {
                Text("The goal and the progress you recorded on it are removed. Your accounts aren't affected.")
            }
        }
        .macSheetFrame(minHeight: 640)
    }

    private func save() {
        let clean = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        let date = hasDate ? Calendar.current.startOfDay(for: targetDate) : nil
        let symbol = category?.symbol ?? goal?.symbol ?? (kind == .save ? "target" : "arrow.down.circle")
        let color = category?.colorHex ?? goal?.colorHex ?? (kind == .save ? "007AFF" : "FF2D55")
        let floor = max(payoffTo ?? 0, 0)
        var account = linked
        if account == nil, makeAccount, kind == .save {
            let made = Account(name: String(clean.prefix(Account.maxNameLength)), type: .savings, openingBalance: 0)
            made.institution = newInstitution.trimmingCharacters(in: .whitespaces)
            made.accountNumber = Account.digits(newAccountNumber, limit: Account.maxAccountNumberLength)
            modelContext.insert(made)
            // What's already saved goes in as a real deposit, with its payee, category and method locked.
            OpeningDeposit.set(max(starting ?? 0, 0), for: made, in: modelContext)
            account = made
        }
        // A goal counts from the account's balance when it is linked, or when the link or the "from now on" choice
        // changes. Otherwise its starting point stays where it was.
        let keepsLink = account != nil && goal?.followedAccount?.persistentModelID == account?.persistentModelID
        let sameStart = keepsLink && (kind == .payoff || fromNow == (goal.map { $0.startingAmount != 0 } ?? false))
        let start: Decimal = {
            if let account, !(sameStart && goal != nil) { return kind == .payoff ? Goal.owed(on: account) : (fromNow ? max(account.balance, 0) : 0) }
            if account != nil, let goal { return goal.startingAmount }
            return max(owed ?? 0, 0)
        }()
        let savedFrom: Decimal = account != nil ? start : max(starting ?? 0, 0)

        if let goal {
            // Only a change to the numbers the goal is measured by can reopen an archived goal.
            let before = (goal.targetAmount, goal.startingAmount, goal.goalBalance)
            goal.name = clean
            goal.categoryName = category?.title ?? ""
            goal.targetDate = date
            goal.symbol = symbol
            goal.colorHex = color
            goal.notes = notes
            goal.account = account
            if goal.isPayoff {
                goal.startingAmount = start
                goal.goalBalance = floor
                goal.targetAmount = max(start - floor, 0)
            } else {
                goal.targetAmount = target ?? 0
                goal.startingAmount = savedFrom
            }
            let after = (goal.targetAmount, goal.startingAmount, goal.goalBalance)
            if goal.isArchived, before != after {
                let when = goal.completedAt, final = goal.finalAmount
                goal.completedAt = nil
                goal.finalAmount = nil
                if goal.progress().isAchieved { goal.completedAt = when; goal.finalAmount = final ?? goal.saved }
            }
        } else if kind == .payoff {
            modelContext.insert(Goal(name: clean, targetAmount: max(start - floor, 0), startingAmount: start, targetDate: date,
                                     symbol: symbol, colorHex: color, notes: notes, account: account, kind: .payoff, goalBalance: floor,
                                     categoryName: category?.title ?? ""))
        } else {
            modelContext.insert(Goal(name: clean, targetAmount: target ?? 0, startingAmount: savedFrom, targetDate: date,
                                     symbol: symbol, colorHex: color, notes: notes, account: account, categoryName: category?.title ?? ""))
        }
        modelContext.saveNow()
        GoalArchiver.archiveReached(in: modelContext)
        dismiss()
    }
}

// MARK: Loans on the Planning page

/// A loan with a maturity date, shown beside the goals: how far along it is and whether it will be paid off before it matures.
private struct LoanPlanCard: View {
    let account: Account

    var body: some View {
        let loan = account.loanProgress
        let estimate = loan.payoffDate()
        GoalCardBackground {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    AccountPicture(data: account.supportsPhoto ? account.photoData : nil, type: account.type, account: account)
                        .frame(width: 64, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    badge(estimate)
                }
                if loan.hasOriginal {
                    ProgressView(value: loan.fraction).tint(Theme.green)
                }
                HStack(alignment: .firstTextBaseline) {
                    if loan.hasOriginal {
                        Text(loan.paidOff, format: .appCurrency).font(.title3.bold())
                        Text("paid").foregroundStyle(.secondary)
                        Text(loan.fraction, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(loan.owed.formatted(.appCurrency)) owed").font(.callout.weight(.medium))
                }
                .font(.subheadline)
                if let estimate {
                    Text("Estimated payoff \(estimate.formatted(.dateTime.month(.abbreviated).year())) at \(loan.monthlyPayment.formatted(.appCurrency))/mo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [account.typeTitle]
        if let date = account.payoffDate { parts.append("matures \(date.formatted(.dateTime.month(.abbreviated).year()))") }
        return parts.joined(separator: " · ")
    }

    /// Ahead of or behind the maturity date, by comparing the estimated payoff with it.
    @ViewBuilder
    private func badge(_ estimate: Date?) -> some View {
        if let maturity = account.payoffDate, let estimate {
            let months = Calendar.current.dateComponents([.month], from: estimate, to: maturity).month ?? 0
            if months > 0 {
                label("\(months) mo ahead", "checkmark.circle.fill", Theme.green)
            } else if months < 0 {
                label("\(-months) mo behind", "exclamationmark.triangle.fill", .orange)
            } else {
                label("On schedule", "checkmark.circle", Theme.green)
            }
        } else if account.payoffDate != nil, account.loanProgress.monthlyPayment <= 0 {
            label("No payment set", "questionmark.circle", .secondary)
        }
    }

    private func label(_ text: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 4) { Image(systemName: symbol); Text(text) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize()
    }
}
