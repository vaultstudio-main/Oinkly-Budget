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
                    .help("Opens this tab's settings in a window: which accounts the Outlook counts, or what the War Plan starts with and your buffer")
                }
            }
            OutlookBody(month: month, tab: tab, plan: $plan, excluded: MonthOutlook.excluded(from: excludedStored))
        }
        .background(Theme.background)
        .onAppear {
            plan = WarPlanData.load(for: month)
            UserDefaults.standard.set(tab == .warPlan ? "warPlan" : "outlook", forKey: OutlookSettings.tabKey)
        }
        .onChange(of: tab) { _, new in UserDefaults.standard.set(new == .warPlan ? "warPlan" : "outlook", forKey: OutlookSettings.tabKey) }
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
    private var accounts: [Account] { allAccounts.live.filter(MonthOutlook.isEligible) }

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
                planChart(outlook)
                improveCard(outlook, opening: opening, kept: buffer)
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
                HStack(alignment: .top, spacing: 14) { cards() }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], spacing: 14) { cards() }
            }
            Label(hasPlan ? "Each card sets your plan against what the outlook says now. The plan is only a what-if sheet and never changes the outlook."
                          : "No plan for this month yet. Add lines on the War Plan tab, or pull them in, and each card will show the plan against the outlook.",
                  systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
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
            .frame(height: Self.pullOutHeight, alignment: .top)
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

    // MARK: Plan against outlook, as a chart

    /// Each planned line as a pair of bars: what was planned and what the outlook now says. Always shown, with a set height that
    /// scrolls, and the bars sit at the top of it.
    private func planChart(_ outlook: MonthOutlook) -> some View {
        let rows = plan.items.isEmpty ? [] : WarPlanComparison.build(items: plan.items, outlook: outlook).rows
            .filter { ($0.planned ?? 0) > 0 || ($0.actual ?? 0) > 0 }
            .sorted { max($0.planned ?? 0, $0.actual ?? 0) > max($1.planned ?? 0, $1.actual ?? 0) }
        return ReportCard(title: "Plan vs. Outlook") {
            Group {
                if rows.isEmpty {
                    placeholder("A pair of bars for each planned line, planned against outlook, appear here once the War Plan has lines.")
                } else {
                    ScrollView { PlanVsOutlookChart(rows: rows) }
                }
            }
            .frame(height: Self.chartHeight, alignment: .top)
        }
    }

    // MARK: What to improve

    /// A short report on what could be better this month.
    private func improveCard(_ outlook: MonthOutlook, opening: Decimal, kept: Decimal) -> some View {
        let hasPlan = !plan.items.isEmpty
        let planned = SafePull(opening: opening, buffer: kept, events: SafePull.events(plan: plan.items))
        let actual = SafePull(opening: opening, buffer: kept, events: SafePull.events(outlook: outlook))
        let items = OutlookAdvice.make(outlook: outlook, compare: hasPlan ? WarPlanComparison.build(items: plan.items, outlook: outlook) : nil,
                                       plannedPull: hasPlan ? planned : nil, actualPull: actual, buffer: kept,
                                       startingSet: !startAccount.isEmpty || OutlookSettings.decimal(startAmount) != nil)
        return ReportCard(title: "What to Improve") {
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: symbol(item.level)).foregroundStyle(color(item.level)).frame(width: 22).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).fontWeight(.semibold)
                            Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    if item.id != items.last?.id { Divider() }
                }
              }
            }
            .frame(height: Self.reportHeight, alignment: .top)
        }
    }

    private func symbol(_ level: OutlookAdvice.Level) -> String {
        switch level {
        case .problem: "exclamationmark.triangle.fill"
        case .watch: "eye.fill"
        case .tip: "lightbulb.fill"
        case .good: "checkmark.seal.fill"
        }
    }

    private func color(_ level: OutlookAdvice.Level) -> Color {
        switch level {
        case .problem: Theme.red
        case .watch: .orange
        case .tip: .accentColor
        case .good: Theme.green
        }
    }

    // MARK: Fixed sizes

    /// Every card on the page has a place that is always there, with a set height: when there is more than fits it scrolls inside,
    /// and when there is less it sits at the top of its place. The page never jumps about as a plan or a month changes.
    private static let cardHeight: CGFloat = 215
    private static let pullOutHeight: CGFloat = 255
    private static let listHeight: CGFloat = 215
    private static let chartHeight: CGFloat = 255
    private static let reportHeight: CGFloat = 235

    /// What a card says in its place until there is something to show.
    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Each planned line next to the outlook line of the same name. Always shown, with a place for the lines even when there is no plan.
    private func lineByLine(_ outlook: MonthOutlook) -> some View {
        let rows = plan.items.isEmpty ? [] : WarPlanComparison.build(items: plan.items, outlook: outlook).rows
        return ReportCard(title: "Line by Line") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    Text("").frame(width: 24)
                    Text("ITEM").frame(maxWidth: .infinity, alignment: .leading)
                    Text("PLANNED").frame(width: 110, alignment: .trailing)
                    Text("OUTLOOK").frame(width: 110, alignment: .trailing)
                    Text("DIFFERENCE").frame(width: 130, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 6)
                Divider()
                if rows.isEmpty {
                    placeholder("Each planned line appears here next to the outlook line of the same name, with the difference. Add lines on the War Plan tab, or pull them in.")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                lineRow(row)
                                Divider()
                            }
                            Text("Lines are matched by name. The plan is only a what-if sheet and never changes the outlook.")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        }
                    }
                }
            }
            .frame(height: Self.listHeight, alignment: .top)
        }
    }

    private func lineRow(_ row: WarPlanComparison.Row) -> some View {
        HStack(spacing: 16) {
            Image(systemName: statusSymbol(row)).foregroundStyle(statusColor(row)).frame(width: 24)
            HStack(spacing: 6) {
                Text(row.title).lineLimit(1)
                if row.planned == nil { Text("not in plan").font(.caption2).foregroundStyle(.secondary) }
                if row.actual == nil { Text("not in outlook yet").font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.planned.map { $0.formatted(.appCurrency) } ?? "–").foregroundStyle(row.planned == nil ? .tertiary : .primary)
                .frame(width: 110, alignment: .trailing)
            Text(row.actual.map { $0.formatted(.appCurrency) } ?? "–").foregroundStyle(row.actual == nil ? .tertiary : .primary)
                .frame(width: 110, alignment: .trailing)
            differenceText(row.difference, goodWhenMore: row.isIncome)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.vertical, 7)
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
            // The plan's place is always here, so the card is the same size with or without a plan.
            HStack {
                Text("Planned").foregroundStyle(.secondary)
                Spacer()
                if let planned { Text(planned, format: .appCurrency).fontWeight(.semibold) } else { Text("–").foregroundStyle(.tertiary) }
            }
            .font(.callout)
            bar(ratio)
            if let difference { chip(difference) } else { noPlanChip }
            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 215)
        .panelBackground(cornerRadius: 8)
        .accessibilityElement(children: .combine)
    }

    /// The bar fills to the outlook's share of the plan; the tick is the plan itself.
    private func bar(_ ratio: Double?) -> some View {
        GeometryReader { geo in
            let scale = max(1, ratio ?? 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                if let ratio {
                    Capsule().fill(barColor).frame(width: geo.size.width * ratio / scale)
                    Rectangle().fill(Color.primary.opacity(0.6)).frame(width: 2, height: 12).offset(x: geo.size.width / scale - 1)
                }
            }
        }
        .frame(height: 8)
    }

    private var noPlanChip: some View {
        Text("No plan yet")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.secondary.opacity(0.18), in: Capsule())
            .foregroundStyle(.secondary)
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

// MARK: Charts

private func chartValue(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }

/// Planned and outlook amounts side by side for each line.
private struct PlanVsOutlookChart: View {
    let rows: [WarPlanComparison.Row]

    var body: some View {
        Chart {
            ForEach(rows) { row in
                BarMark(x: .value("Amount", chartValue(row.planned ?? 0)), y: .value("Item", row.title))
                    .position(by: .value("Source", "Planned"))
                    .foregroundStyle(by: .value("Source", "Planned"))
                    .annotation(position: .trailing, spacing: 4) { label(row.planned) }
                BarMark(x: .value("Amount", chartValue(row.actual ?? 0)), y: .value("Item", row.title))
                    .position(by: .value("Source", "Outlook"))
                    .foregroundStyle(by: .value("Source", "Outlook"))
                    .annotation(position: .trailing, spacing: 4) { label(row.actual) }
            }
        }
        .chartForegroundStyleScale(["Planned": Color.accentColor, "Outlook": Theme.green])
        .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
        .frame(height: max(CGFloat(rows.count) * 56 + 50, 140))
    }

    private func label(_ amount: Decimal?) -> some View {
        Text(amount.map { ReportFormat.compact(chartValue($0)) } ?? "none").font(.caption2).foregroundStyle(.secondary)
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
        .frame(height: 220)
    }
}
