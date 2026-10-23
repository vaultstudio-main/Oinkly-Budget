import SwiftUI
import SwiftData
import Charts

/// The Monthly Outlook: for one calendar month, the plan against what is really happening. The Outlook tab sets what you
/// planned against what the accounts, bills, repeating entries and budgets now say, and shows when the spare money can be
/// pulled out; the War Plan tab is the sheet you plan on. Settings, in a window of its own, holds the accounts counted, what the
/// month starts with and the buffer.
struct MonthOutlookView: View {
    enum OutlookTab: String, CaseIterable { case outlook = "Outlook", warPlan = "War Plan" }

    @State private var month = MonthFilter.start(of: .now)
    @State private var tab = OutlookTab.outlook
    @State private var plan = WarPlanData()
    @Environment(\.openWindow) private var openWindow
    @AppStorage(MonthOutlook.excludedKey) private var excludedStored = ""

    private var range: ClosedRange<Date> {
        let current = MonthFilter.start(of: .now)
        let calendar = Calendar.current
        return (calendar.date(byAdding: .month, value: -24, to: current) ?? current)...(calendar.date(byAdding: .month, value: 12, to: current) ?? current)
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeader("Monthly Outlook") {
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
                        openWindow(id: OutlookSettings.windowID)
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .help("Opens a window for what the month starts with, your buffer, and which accounts are counted")
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
    @AppStorage(OutlookSettings.startAccountKey) private var startAccount = ""
    @AppStorage(OutlookSettings.startAmountKey) private var startAmount = ""
    @AppStorage(OutlookSettings.bufferKey) private var bufferText = ""

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
    private var accounts: [Account] { allAccounts.live.filter { !$0.supportsHoldings } }

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
        let opening = OutlookSettings.opening(accounts: accounts, startAccount: startAccount, startAmount: startAmount)
        let buffer = OutlookSettings.decimal(bufferText) ?? 0
        if tab == .warPlan {
            let label = accounts.first { MonthOutlook.accountKey($0) == startAccount }.map { "Starting with \($0.name)'s balance" } ?? "Starting with"
            return AnyView(MonthWarPlanView(outlook: outlook, plan: $plan, opening: opening, kept: buffer, startLabel: label)
                .statusBarText("Monthly Outlook · \(title) · the war plan sheet"))
        }
        return AnyView(ScrollView {
            VStack(spacing: 14) {
                versusCards(outlook, totals: totals, opening: opening, kept: buffer)
                pullOutCard(outlook, opening: opening, kept: buffer)
                lineByLine(outlook)
                spendingCard(outlook)
                details(outlook)
                notes(outlook, totals: totals, kept: kept)
            }
            .padding(16)
        }
        .statusBarText("Monthly Outlook · \(title) · \(totals.left.formatted(.appCurrency)) left over"))
    }

    // MARK: Plan against outlook

    /// The four big cards: money in, money out, what is left over, and what is above the buffer. Each sets the plan against the outlook.
    private func versusCards(_ outlook: MonthOutlook, totals: Totals, opening: Decimal, kept: Decimal) -> some View {
        let hasPlan = !plan.items.isEmpty
        let plannedIn = plan.items.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount }
        let plannedOut = plan.items.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 + $1.amount }
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

    // MARK: When the spare money can come out

    /// The earliest safe day to pull the spare money out, from the plan and from what is really happening, with the balance
    /// through the month for each.
    private func pullOutCard(_ outlook: MonthOutlook, opening: Decimal, kept: Decimal) -> some View {
        let hasPlan = !plan.items.isEmpty
        let planned = SafePull(opening: opening, buffer: kept, events: SafePull.events(plan: plan.items))
        let actual = SafePull(opening: opening, buffer: kept, events: SafePull.events(outlook: outlook))
        let calendar = Calendar.current
        return ReportCard(title: "When You Can Pull Money Out") {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    dayBlock("Planned", pull: hasPlan ? planned : nil)
                    dayBlock("Outlook", pull: actual)
                    if let p = planned.best, let a = actual.best, hasPlan {
                        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: p.date), to: calendar.startOfDay(for: a.date)).day ?? 0
                        dayChip(days)
                    }
                    Text("The first day the whole spare amount, what the month ends with less your buffer, can come out and the balance still never drops under the buffer. The outlook spreads budget spending through the month a week at a time.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 290, alignment: .leading)
                BalanceChart(month: month, planned: hasPlan ? planned : nil, actual: actual, buffer: kept)
            }
        }
    }

    private func dayBlock(_ title: String, pull: SafePull?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let pull, let best = pull.best {
                Text(best.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.system(size: 26, weight: .bold))
                Text("\(pull.spare.formatted(.appCurrency)) can come out from here").font(.caption).foregroundStyle(.secondary)
            } else if let pull {
                Text("Not yet").font(.system(size: 26, weight: .bold)).foregroundStyle(.secondary)
                Text(pull.spare > 0 ? "Nothing is dated yet" : "Nothing is spare at the end of the month").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No plan yet").font(.system(size: 26, weight: .bold)).foregroundStyle(.tertiary)
                Text("Add lines on the War Plan tab").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func dayChip(_ days: Int) -> some View {
        let words = days == 0 ? "The same day as planned" : "\(abs(days)) day\(abs(days) == 1 ? "" : "s") \(days > 0 ? "later" : "earlier") than planned"
        let color: Color = days == 0 ? .secondary : (days > 0 ? Theme.red : Theme.green)
        return Text(words)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: Where the money goes

    /// Each budget, then bills and everything else, as bars: what has been paid or spent, and what is still to come. The faint track behind a budget is its limit.
    private func spendingCard(_ outlook: MonthOutlook) -> some View {
        var bars: [SpendBar] = outlook.budgets.map {
            SpendBar(name: $0.category.name, done: $0.spent, coming: $0.planned, limit: $0.limit)
        }
        let paid = outlook.bills.filter { [.paid, .over, .under, .received].contains($0.status) }.reduce(Decimal(0)) { $0 + $1.counted }
        let billsTotal = outlook.bills.reduce(Decimal(0)) { $0 + $1.counted }
        if billsTotal > 0 { bars.append(SpendBar(name: "Bills & repeating", done: paid, coming: billsTotal - paid, limit: nil)) }
        if outlook.otherSpending > 0 { bars.append(SpendBar(name: "Everything else", done: outlook.otherSpending, coming: 0, limit: nil)) }
        bars.sort { $0.done + $0.coming > $1.done + $1.coming }
        return ReportCard(title: "Where the Money Goes") {
            if bars.isEmpty {
                emptyNote("Nothing is due or spent this month yet.")
            } else {
                SpendingChart(bars: bars)
            }
        }
    }

    private func details(_ outlook: MonthOutlook) -> some View {
        DisclosureGroup {
            VStack(spacing: 14) {
                incomeCard(outlook)
                billsCard(outlook)
                budgetsCard(outlook)
            }
            .padding(.top, 12)
        } label: {
            Text("Every paycheque, bill and budget").font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(cornerRadius: 8)
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

// MARK: Charts

/// One bar of the Where the Money Goes chart.
private struct SpendBar: Identifiable {
    let name: String
    /// Paid or spent so far.
    let done: Decimal
    /// Still to come: bills and repeating expenses not paid yet.
    let coming: Decimal
    /// A budget's limit, shown as a mark on its bar.
    let limit: Decimal?
    var id: String { name }

    /// The name with how far along it is, shown above its bar.
    var label: String {
        let spent = (done + coming).formatted(.appCurrency)
        guard let limit else { return "\(name)  ·  \(done.formatted(.appCurrency)) paid of \(spent)" }
        return "\(name)  ·  \((done + coming).formatted(.appCurrency)) of \(limit.formatted(.appCurrency))"
    }
}

private func chartValue(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }

private struct SpendingChart: View {
    let bars: [SpendBar]

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                // A budget's whole limit as a faint track behind its bar, so you see how much of it is used.
                if let limit = bar.limit {
                    RectangleMark(xStart: .value("Start", 0), xEnd: .value("Limit", chartValue(limit)), y: .value("Item", bar.name), height: .ratio(0.5))
                        .foregroundStyle(Color.primary.opacity(0.12))
                }
                BarMark(x: .value("Amount", chartValue(bar.done)), y: .value("Item", bar.name), height: .ratio(0.5))
                    .foregroundStyle(by: .value("Status", "Paid or spent"))
                    .annotation(position: .top, alignment: .leading, spacing: 3) { Text(bar.label).font(.caption).foregroundStyle(.secondary) }
                BarMark(x: .value("Amount", chartValue(bar.coming)), y: .value("Item", bar.name), height: .ratio(0.5))
                    .foregroundStyle(by: .value("Status", "Still to come"))
            }
        }
        .chartYAxis(.hidden)
        .chartForegroundStyleScale(["Paid or spent": Color.accentColor, "Still to come": Color.accentColor.opacity(0.35)])
        .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
        .frame(height: max(CGFloat(bars.count) * 50 + 40, 120))
    }
}

/// The balance through the month, from the plan and from the outlook, with the buffer as a dashed line and a dot on the safe day.
private struct BalanceChart: View {
    let month: Date
    let planned: SafePull?
    let actual: SafePull
    let buffer: Decimal

    private var end: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: 1, to: month).flatMap { calendar.date(byAdding: .day, value: -1, to: $0) } ?? month
    }

    @ChartContentBuilder
    private func series(_ name: String, _ pull: SafePull) -> some ChartContent {
        let line = [SafePull.Point(id: -1, date: month, balance: pull.opening)] + pull.points + [SafePull.Point(id: Int.max, date: end, balance: pull.ending)]
        ForEach(line) { point in
            LineMark(x: .value("Date", point.date), y: .value("Balance", chartValue(point.balance)), series: .value("Source", name))
                .foregroundStyle(by: .value("Source", name))
                .interpolationMethod(.stepEnd)
        }
        if let best = pull.best {
            PointMark(x: .value("Date", best.date), y: .value("Balance", chartValue(best.balance)))
                .foregroundStyle(by: .value("Source", name))
                .symbolSize(110)
        }
    }

    var body: some View {
        Chart {
            if let planned { series("Plan", planned) }
            series("Outlook", actual)
            RuleMark(y: .value("Buffer", chartValue(buffer)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.orange)
                .annotation(position: .top, alignment: .leading) { Text("Buffer").font(.caption2).foregroundStyle(.orange) }
        }
        .chartForegroundStyleScale(["Plan": Color.accentColor, "Outlook": Theme.green])
        .chartXScale(domain: month...end)
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
        .frame(height: 230)
    }
}
