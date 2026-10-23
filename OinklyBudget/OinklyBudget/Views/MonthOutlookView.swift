import SwiftUI
import SwiftData

/// The Monthly War Plan: for one calendar month, the plan against what is really happening. The Outlook tab sets what you
/// planned against what the accounts, bills, repeating entries and budgets now say; the War Plan tab is the sheet you plan on.
/// Settings, top right, holds the accounts counted, what the month starts with and the buffer, for both tabs.
struct MonthOutlookView: View {
    enum OutlookTab: String, CaseIterable { case outlook = "Outlook", warPlan = "War Plan" }

    @State private var month = MonthFilter.start(of: .now)
    @State private var tab = OutlookTab.outlook
    @State private var choosingSettings = false
    @State private var plan = WarPlanData()
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @AppStorage(MonthOutlook.excludedKey) private var excludedStored = ""

    /// Accounts the outlook can count: everything except investments, which hold no bills or budgets.
    private var countable: [Account] { allAccounts.live.filter { !$0.supportsHoldings } }
    private var leftOut: Int { countable.filter { MonthOutlook.excluded(from: excludedStored).contains(MonthOutlook.accountKey($0)) }.count }

    private var range: ClosedRange<Date> {
        let current = MonthFilter.start(of: .now)
        let calendar = Calendar.current
        return (calendar.date(byAdding: .month, value: -24, to: current) ?? current)...(calendar.date(byAdding: .month, value: 12, to: current) ?? current)
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeader("Monthly War Plan") {
                HStack {
                    MonthSelector(month: $month, range: range)
                    Picker("View", selection: $tab) {
                        ForEach(OutlookTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    Button {
                        choosingSettings = true
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .help("What the month starts with, your buffer, and which accounts are counted")
                    .popover(isPresented: $choosingSettings, arrowEdge: .bottom) { settings }
                }
            }
            OutlookBody(month: month, tab: tab, plan: $plan, excluded: MonthOutlook.excluded(from: excludedStored))
        }
        .background(Theme.background)
        .onAppear { plan = WarPlanData.load(for: month) }
        .onChange(of: month) { _, new in plan = WarPlanData.load(for: new) }
        .onChange(of: plan) { _, new in new.save(for: month) }
    }
}

extension MonthOutlookView {
    /// Settings for both tabs: what the month starts with, the buffer to keep, and the accounts that count.
    fileprivate var settings: some View {
        let excluded = MonthOutlook.excluded(from: excludedStored)
        let startingAccount = plan.startAccount.flatMap { key in countable.first { MonthOutlook.accountKey($0) == key } }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Monthly War Plan Settings").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Starting with").font(.subheadline.weight(.semibold))
                HStack {
                    Menu {
                        Button("A number I type") { plan.startAccount = nil }
                        Divider()
                        ForEach(countable) { account in
                            Button("\(account.name): \(account.balance(asOf: .now).formatted(.appCurrency))") { plan.startAccount = MonthOutlook.accountKey(account) }
                        }
                    } label: {
                        Text(startingAccount.map { "\($0.name)'s balance" } ?? "A number I type")
                    }
                    .fixedSize()
                    if let startingAccount {
                        Spacer()
                        Text(startingAccount.balance(asOf: .now), format: .appCurrency).fontWeight(.semibold)
                    } else {
                        CurrencyField("Starting amount", value: $plan.start)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                    }
                }
                Text("The money already there when the month begins, from an account's balance now or a number you type. Used by the War Plan and the Above the Buffer card.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Buffer").font(.subheadline.weight(.semibold))
                CurrencyField("Buffer", value: $plan.buffer)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                Text("Money to keep untouched. Only what is above it counts as spare, and the War Plan warns when a line takes you under it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Accounts to count").font(.subheadline.weight(.semibold))
                Text("Only ticked accounts count toward the Outlook: their income, spending and repeating transactions. A bill is left out when the payment linked to it came from an account that is unticked.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(countable) { account in
                    Toggle(isOn: Binding(
                        get: { !MonthOutlook.excluded(from: excludedStored).contains(MonthOutlook.accountKey(account)) },
                        set: { counted in
                            var keys = MonthOutlook.excluded(from: excludedStored)
                            if counted { keys.remove(MonthOutlook.accountKey(account)) } else { keys.insert(MonthOutlook.accountKey(account)) }
                            excludedStored = MonthOutlook.stored(keys)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.name)
                            Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("Count All") { excludedStored = "" }.disabled(excluded.isEmpty)
                    Spacer()
                }
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}

private struct OutlookBody: View {
    let month: Date
    let tab: MonthOutlookView.OutlookTab
    @Binding var plan: WarPlanData
    let excluded: Set<String>
    @Query private var transactions: [Transaction]
    @Query private var allBills: [Bill]
    @Query private var allRules: [RecurringTransaction]
    @Query private var allCategories: [Category]
    @Query private var snapshots: [OutlookSnapshot]
    @Query private var cashMarks: [CashBudgetMark]
    @Query private var periods: [BudgetPeriod]
    @Query private var allAccounts: [Account]

    /// The figures kept when this month closed, for a month that is over.
    private var snapshot: OutlookSnapshot? {
        isPast ? snapshots.live.first { $0.monthKey == OutlookSnapshots.key(for: month) } : nil
    }

    /// The numbers the cards show: the saved ones for a closed month, otherwise today's.
    private struct Totals {
        let income, bills, budgets, other, left, billDifference, overspend: Decimal
        var out: Decimal { income - left }
    }

    init(month: Date, tab: MonthOutlookView.OutlookTab, plan: Binding<WarPlanData>, excluded: Set<String>) {
        self.month = month
        self.tab = tab
        _plan = plan
        self.excluded = excluded
        let end = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
        _transactions = Query(filter: #Predicate<Transaction> { $0.date >= month && $0.date < end })
    }

    private var isFuture: Bool { month > MonthFilter.start(of: .now) }
    private var isPast: Bool { month < MonthFilter.start(of: .now) }

    var body: some View {
        let outlook = MonthOutlook.build(month: month, bills: allBills.live, rules: allRules.live, categories: allCategories.live,
                                         monthTransactions: transactions, excludedAccounts: excluded,
                                         cashBudgetKeys: Set(cashMarks.live.map(\.key)),
                                         weeklyAmounts: Dictionary(periods.live.map { ($0.key, $0.weeklyAmount) }, uniquingKeysWith: { first, _ in first }))
        let kept = snapshot
        let totals = kept.map { Totals(income: $0.incomeTotal, bills: $0.billsTotal, budgets: $0.budgetsTotal, other: $0.otherSpending, left: $0.leftToSave,
                                       billDifference: $0.billDifference, overspend: $0.budgetOverspend) }
            ?? Totals(income: outlook.incomeTotal, bills: outlook.billsTotal, budgets: outlook.budgetsTotal, other: outlook.otherSpending,
                      left: outlook.leftToSave, billDifference: outlook.billDifference, overspend: outlook.budgetOverspend)
        let title = month.formatted(.dateTime.month(.wide).year())
        if tab == .warPlan {
            return AnyView(MonthWarPlanView(outlook: outlook, plan: $plan)
                .statusBarText("Monthly War Plan · \(title) · the plan sheet"))
        }
        return AnyView(ScrollView {
            VStack(spacing: 14) {
                versusCards(outlook, totals: totals)
                lineByLine(outlook)
                notes(outlook, totals: totals, kept: kept)
                Text("What is actually happening").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                incomeCard(outlook)
                billsCard(outlook)
                budgetsCard(outlook)
            }
            .padding(16)
        }
        .statusBarText("Monthly War Plan · \(title) · \(totals.left.formatted(.appCurrency)) left over"))
    }

    // MARK: Plan against outlook

    private var accounts: [Account] { allAccounts.live.filter { !$0.supportsHoldings } }

    /// The four big cards: money in, money out, what is left over, and what is above the buffer. Each sets the plan against the outlook.
    private func versusCards(_ outlook: MonthOutlook, totals: Totals) -> some View {
        let hasPlan = !plan.items.isEmpty
        let plannedIn = plan.items.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount }
        let plannedOut = plan.items.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 + $1.amount }
        let opening = plan.opening(accounts: accounts)
        let kept = plan.kept
        @ViewBuilder func cards() -> some View {
            VersusCard(title: "Money In", symbol: "arrow.down.circle.fill", planned: hasPlan ? plannedIn : nil, actual: totals.income, goodWhenMore: true,
                       note: "\(outlook.income.count) paycheque\(outlook.income.count == 1 ? "" : "s") and other income")
            VersusCard(title: "Money Out", symbol: "arrow.up.circle.fill", planned: hasPlan ? plannedOut : nil, actual: totals.out, goodWhenMore: false,
                       note: "bills, repeating expenses and budgets")
            VersusCard(title: "Left Over", symbol: "banknote.fill", planned: hasPlan ? plannedIn - plannedOut : nil, actual: totals.left, goodWhenMore: true,
                       signed: true, note: "money in less money out")
            VersusCard(title: "Above the Buffer", symbol: "shield.lefthalf.filled", planned: hasPlan ? opening + plannedIn - plannedOut - kept : nil,
                       actual: opening + totals.left - kept, goodWhenMore: true, signed: true,
                       note: "starting with \(opening.formatted(.appCurrency)), buffer \(kept.formatted(.appCurrency))")
        }
        return VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { cards() }.fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], spacing: 14) { cards() }
            }
            if !hasPlan {
                Label("No plan for this month yet. Add lines on the War Plan tab, or pull them in, and each card will show the plan against the outlook.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Each planned line next to the outlook line of the same name. Shown only when there is a plan.
    @ViewBuilder
    private func lineByLine(_ outlook: MonthOutlook) -> some View {
        if !plan.items.isEmpty {
            let compare = WarPlanComparison.build(items: plan.items, outlook: outlook)
            ReportCard(title: "Plan vs. Outlook, Line by Line") {
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 0) {
                        GridRow {
                            Text("").gridColumnAlignment(.center)
                            Text("ITEM").gridColumnAlignment(.leading)
                            Text("PLANNED").frame(minWidth: 110, alignment: .trailing)
                            Text("OUTLOOK").frame(minWidth: 110, alignment: .trailing)
                            Text("DIFFERENCE").frame(minWidth: 130, alignment: .trailing)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                        Divider().gridCellColumns(5)
                        ForEach(compare.rows) { row in
                            GridRow {
                                Image(systemName: statusSymbol(row)).foregroundStyle(statusColor(row)).gridColumnAlignment(.center)
                                HStack(spacing: 6) {
                                    Text(row.title)
                                    if row.planned == nil { Text("not in plan").font(.caption2).foregroundStyle(.secondary) }
                                    if row.actual == nil { Text("not in outlook yet").font(.caption2).foregroundStyle(.secondary) }
                                }
                                .gridColumnAlignment(.leading)
                                Text(row.planned.map { $0.formatted(.appCurrency) } ?? "–").foregroundStyle(row.planned == nil ? .tertiary : .primary)
                                Text(row.actual.map { $0.formatted(.appCurrency) } ?? "–").foregroundStyle(row.actual == nil ? .tertiary : .primary)
                                differenceText(row.difference, goodWhenMore: row.isIncome)
                            }
                            .padding(.vertical, 7)
                            Divider().gridCellColumns(5)
                        }
                    }
                    Text("Lines are matched by name. The plan is only a what-if sheet and never changes the outlook.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusSymbol(_ row: WarPlanComparison.Row) -> String {
        guard let difference = row.difference else { return "circle.dashed" }
        return difference == 0 ? "checkmark.circle.fill" : ((difference > 0) == row.isIncome ? "arrow.up.right.circle.fill" : "exclamationmark.circle.fill")
    }

    private func statusColor(_ row: WarPlanComparison.Row) -> Color {
        guard let difference = row.difference else { return .secondary }
        return difference == 0 ? Theme.green : ((difference > 0) == row.isIncome ? Theme.green : Theme.red)
    }

    private func differenceText(_ difference: Decimal?, goodWhenMore: Bool) -> some View {
        Group {
            if let difference, difference != 0 {
                Text((difference > 0 ? "+" : "−") + abs(difference).formatted(.appCurrency))
                    .fontWeight(.semibold)
                    .foregroundStyle((difference > 0) == goodWhenMore ? Theme.green : Theme.red)
            } else if difference != nil {
                Text("On plan").foregroundStyle(.secondary)
            } else {
                Text("")
            }
        }
    }

    /// Small print under the cards: a closed month's saved figures, bills that ran over and budgets past their limits.
    @ViewBuilder
    private func notes(_ outlook: MonthOutlook, totals: Totals, kept: OutlookSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sentence(income: totals.income, out: totals.out)).font(.callout).foregroundStyle(.secondary)
            if let kept {
                Text("Saved \(kept.savedAt.formatted(date: .abbreviated, time: .omitted)), when the month closed."
                     + (outlook.leftToSave != kept.leftToSave ? " With changes made since, it would now be \(outlook.leftToSave.formatted(.appCurrency))." : ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if totals.billDifference != 0 {
                let more = totals.billDifference > 0
                Label("Bills came to \(abs(totals.billDifference).formatted(.appCurrency)) \(more ? "more" : "less") than expected.",
                      systemImage: more ? "arrow.up.right" : "arrow.down.right")
                    .font(.callout).foregroundStyle(more ? Theme.red : Theme.green)
            }
            if totals.overspend > 0 {
                Label("Budgets are \(totals.overspend.formatted(.appCurrency)) over their limits.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Theme.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sentence(income: Decimal, out: Decimal) -> String {
        let basis = "The outlook is income of \(income.formatted(.appCurrency)), less \(out.formatted(.appCurrency)) for bills, budgets and other spending."
        if isFuture { return basis + " This month hasn't started, so every figure is what is expected." }
        if isPast { return basis + " This month is over; what was paid counts at what came out." }
        return basis + " Paid bills count at what came out when their payment is linked; the rest count at what is expected."
    }

    // MARK: What is actually happening

    private func incomeCard(_ outlook: MonthOutlook) -> some View {
        ReportCard(title: "Paycheques & Income") {
            VStack(spacing: 0) {
                if outlook.income.isEmpty && outlook.otherIncome == 0 {
                    emptyNote("No repeating income this month. Add a paycheque in Bills & Recurring ▸ Recurring, with a positive amount.")
                }
                ForEach(outlook.income) { line in
                    OutlookRow(line: line, isIncome: true)
                    Divider()
                }
                if outlook.otherIncome != 0 {
                    plainRow("Other income", note: "Came in with no repeating entry behind it", amount: outlook.otherIncome, color: Theme.green)
                }
            }
        }
    }

    private func billsCard(_ outlook: MonthOutlook) -> some View {
        ReportCard(title: "Bills & Repeating Expenses") {
            VStack(spacing: 0) {
                if outlook.bills.isEmpty { emptyNote("Nothing due this month outside a budget.") }
                ForEach(outlook.bills) { line in
                    OutlookRow(line: line, isIncome: false)
                    if line.id != outlook.bills.last?.id { Divider() }
                }
            }
        }
    }

    private func budgetsCard(_ outlook: MonthOutlook) -> some View {
        ReportCard(title: "Budgets") {
            VStack(spacing: 0) {
                if outlook.budgets.isEmpty { emptyNote("No budgets are set. Set one in Settings ▸ Categories.") }
                ForEach(outlook.budgets) { budget in
                    BudgetOutlookRow(budget: budget)
                    if budget.id != outlook.budgets.last?.id { Divider() }
                }
                if outlook.otherSpending > 0 {
                    Divider()
                    plainRow("Everything else", note: "Spent with no bill and no budget", amount: outlook.otherSpending, color: .primary)
                }
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }

    private func plainRow(_ title: String, note: String, amount: Decimal, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount, format: .appCurrency).font(.body.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.vertical, 8)
    }
}

/// One of the big cards: what the outlook says, what was planned, and how far apart they are, with a bar showing how much of the plan is reached.
private struct VersusCard: View {
    let title: String
    let symbol: String
    let planned: Decimal?
    let actual: Decimal
    /// True when more is better (money in, left over); false when less is better (money out).
    let goodWhenMore: Bool
    /// A figure that can be negative and is coloured by its sign.
    var signed = false
    let note: String

    private var difference: Decimal? { planned.map { actual - $0 } }

    private var ratio: Double? {
        guard let planned, planned > 0 else { return nil }
        return max(0, Double(truncating: (actual / planned) as NSDecimalNumber))
    }

    private var barColor: Color {
        guard let ratio else { return .secondary }
        return goodWhenMore ? (ratio >= 1 ? Theme.green : .orange) : (ratio > 1 ? Theme.red : Theme.green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(actual, format: .appCurrency)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(signed ? (actual < 0 ? Theme.red : Theme.green) : (title == "Money In" ? Theme.green : Color.primary))
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text("in the outlook").font(.caption).foregroundStyle(.secondary)
            }
            if let planned {
                HStack {
                    Text("Planned").foregroundStyle(.secondary)
                    Spacer()
                    Text(planned, format: .appCurrency).fontWeight(.semibold)
                }
                .font(.callout)
                if let ratio { bar(ratio) }
                if let difference { chip(difference) }
            }
            Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelBackground(cornerRadius: 8)
        .accessibilityElement(children: .combine)
    }

    /// The bar fills to the outlook's share of the plan; the tick is the plan itself.
    private func bar(_ ratio: Double) -> some View {
        GeometryReader { geo in
            let scale = max(1, ratio)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(barColor).frame(width: geo.size.width * ratio / scale)
                Rectangle().fill(Color.primary.opacity(0.6)).frame(width: 2, height: 12).offset(x: geo.size.width / scale - 1)
            }
        }
        .frame(height: 8)
    }

    private func chip(_ difference: Decimal) -> some View {
        let good = (difference > 0) == goodWhenMore
        let words: String
        if difference == 0 {
            words = "On plan"
        } else if goodWhenMore {
            words = "\(abs(difference).formatted(.appCurrency)) \(difference > 0 ? "more" : "less") than planned"
        } else {
            words = "\(abs(difference).formatted(.appCurrency)) \(difference > 0 ? "over" : "under") plan"
        }
        return Text(words)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((difference == 0 ? Color.secondary : (good ? Theme.green : Theme.red)).opacity(0.18), in: Capsule())
            .foregroundStyle(difference == 0 ? Color.secondary : (good ? Theme.green : Theme.red))
    }
}

/// One bill, repeating transaction or paycheque.
private struct OutlookRow: View {
    let line: MonthOutlook.Line
    let isIncome: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(line.status == .overdue ? Theme.red : Color.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(line.counted, format: .appCurrency)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isIncome ? Theme.green : Color.primary)
                if line.actual != nil, line.difference != 0 {
                    Text("\(line.difference > 0 ? "+" : "−")\(abs(line.difference).formatted(.appCurrency)) vs \(line.expected.formatted(.appCurrency))")
                        .font(.caption)
                        .foregroundStyle((line.difference > 0) == isIncome ? Theme.green : Theme.red)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// What VoiceOver reads for the whole row: name, date, state, and the amount with how far it was from expected.
    private var spoken: String {
        var text = "\(line.title), \(subtitle), \(line.counted.formatted(.appCurrency))"
        if line.actual != nil, line.difference != 0 {
            text += ", \(abs(line.difference).formatted(.appCurrency)) \(line.difference > 0 ? "more" : "less") than the expected \(line.expected.formatted(.appCurrency))"
        }
        return text
    }

    private var symbol: String {
        switch line.status {
        case .paid, .received, .over, .under: "checkmark.circle.fill"
        case .overdue: "exclamationmark.circle"
        case .expected: "circle.dotted"
        }
    }

    private var color: Color {
        switch line.status {
        case .paid, .received, .over, .under: Theme.green
        case .overdue: Theme.red
        case .expected: .secondary
        }
    }

    private var subtitle: String {
        let day = line.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let state: String
        switch line.status {
        case .expected: state = "Expected"
        case .overdue: state = "Overdue"
        case .paid: state = "Paid, amount as expected"
        case .over: state = "Paid, more than expected"
        case .under: state = "Paid, less than expected"
        case .received: state = isIncome ? "Added to your account" : "Added"
        }
        return "\(day) · \(state)"
    }
}

/// One budget with its progress and the bills counted inside it.
private struct BudgetOutlookRow: View {
    let budget: MonthOutlook.BudgetLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CategoryBadge(category: budget.category, size: 26)
                Text(budget.category.name).font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                Text(budget.counted, format: .appCurrency).font(.body.weight(.semibold))
            }
            ProgressView(value: Budget.progress(spent: budget.spent + budget.planned, limit: budget.limit))
                .tint(budget.over > 0 ? Theme.red : Theme.green)
            HStack(spacing: 12) {
                Text("Limit \(budget.limit.formatted(.appCurrency))")
                Text("Spent \(budget.spent.formatted(.appCurrency))")
                if budget.planned > 0 { Text("Still to come \(budget.planned.formatted(.appCurrency))") }
                Spacer()
                if budget.over > 0 {
                    Text("\(budget.over.formatted(.appCurrency)) over").foregroundStyle(Theme.red)
                } else {
                    Text("\(budget.remaining.formatted(.appCurrency)) set aside")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !budget.inside.isEmpty {
                Text("Includes " + budget.inside.map(\.title).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var text = "\(budget.category.name) budget, counts as \(budget.counted.formatted(.appCurrency)). Limit \(budget.limit.formatted(.appCurrency)), spent \(budget.spent.formatted(.appCurrency))"
        if budget.planned > 0 { text += ", still to come \(budget.planned.formatted(.appCurrency))" }
        text += budget.over > 0 ? ", \(budget.over.formatted(.appCurrency)) over" : ", \(budget.remaining.formatted(.appCurrency)) set aside"
        if !budget.inside.isEmpty { text += ". Includes " + budget.inside.map(\.title).joined(separator: ", ") }
        return text
    }
}
