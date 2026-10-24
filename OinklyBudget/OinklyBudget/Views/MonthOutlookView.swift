import SwiftUI
import SwiftData
import Charts

/// The Monthly Outlook: for one calendar month, the plan against what is really happening. The Outlook tab sets what you
/// planned against what the accounts, bills, repeating entries and budgets now say, and shows when the spare money can be
/// pulled out; the War Plan tab is the sheet you plan on. Settings, in a window of its own, holds the accounts counted, what the
/// month starts with and the buffer.
struct MonthOutlookView: View {
    enum OutlookTab: String, CaseIterable, Identifiable {
        case outlook = "Outlook", warPlan = "War Plan"
        var id: Self { self }
    }

    @AppStorage(OutlookSettings.monthKey) private var monthStamp = 0.0
    @State private var tab = OutlookTab.outlook
    @State private var plan = WarPlanData()
    @Environment(\.openWindow) private var openWindow
    @AppStorage(MonthOutlook.excludedKey) private var excludedStored = ""

    /// The month being shown. It is chosen in the Settings window.
    private var month: Date { OutlookSettings.month(from: monthStamp) }

    /// Which month the page is showing. It is only shown here; it is chosen in Settings.
    private var monthLine: some View {
        let which = tab == .warPlan ? "War Plan" : "Outlook"
        let when = month.formatted(.dateTime.month(.wide).year())
        return Text("\(which) for \(when)").font(.headline).contentTransition(.numericText())
    }

    /// Opens the window where real transactions are tagged to the plan's lines.
    private var linkButton: some View {
        Button {
            openWindow(id: PlanMatchWindow.id)
        } label: {
            Label("Link Transactions", systemImage: "link")
        }
        .help("Opens a window with every transaction of the month, from every account, to tag to a line of the War Plan. The Outlook then shows what really happened next to the plan")
    }

    private var settingsButton: some View {
        Button {
            openWindow(id: OutlookSettings.windowID)
        } label: {
            Label("Settings", systemImage: "slider.horizontal.3")
        }
        .help("Opens this tab's settings in a window, where you choose the month: which accounts the Outlook counts, or what the War Plan starts with and your buffer")
    }

    var body: some View {
        VStack(spacing: 0) {
            FolderTabbedHeader(title: "Monthly Outlook", tabs: OutlookTab.allCases, selection: $tab, label: { $0.rawValue }) {
                monthLine
            } centre: { EmptyView() } trailing: {
                HStack(spacing: 8) {
                    linkButton
                    settingsButton
                }
            }
            OutlookBody(month: month, tab: tab, plan: $plan, excluded: MonthOutlook.excluded(from: excludedStored))
        }
        .background(Theme.background)
        .onAppear {
            // Each start of the app begins on this month, whatever was chosen last time.
            if !OutlookSettings.monthResetThisLaunch { monthStamp = 0; OutlookSettings.monthResetThisLaunch = true }
            plan = WarPlanData.load(for: month)
            UserDefaults.standard.set(tab == .warPlan ? "warPlan" : "outlook", forKey: OutlookSettings.tabKey)
        }
        .onChange(of: tab) { _, new in UserDefaults.standard.set(new == .warPlan ? "warPlan" : "outlook", forKey: OutlookSettings.tabKey) }
        .onChange(of: month) { _, new in plan = WarPlanData.load(for: new) }
        .onChange(of: plan) { _, new in new.save(for: month) }
        // Tagging a transaction in the settings window changes the saved plan, so the page picks it up.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let loaded = WarPlanData.load(for: month)
            if loaded != plan && !(loaded.isEmpty && plan.isEmpty) { plan = loaded }
        }
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
    @Query private var paySources: [BillPaySource]
    @AppStorage(OutlookSettings.startAccountKey) private var startAccount = ""
    @AppStorage(OutlookSettings.startAmountKey) private var startAmount = ""
    @AppStorage(OutlookSettings.bufferKey) private var bufferText = ""
    /// The room the page has, so the pull-out card can take what the rest leaves.
    @State private var viewport: CGFloat = 700
    @State private var pageWidth: CGFloat = 900

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
                                         weeklyAmounts: Dictionary(periods.live.map { ($0.key, $0.weeklyAmount) }, uniquingKeysWith: { first, _ in first }),
                                         billPayerKeys: Dictionary(paySources.live.map { ($0.billKey, $0.accountKey) }, uniquingKeysWith: { first, _ in first }))
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
            VStack(spacing: 10) {
                versusCards(outlook, totals: totals, opening: opening, kept: buffer)
                pullOutCard(outlook, opening: opening, kept: buffer)
                improveCard(outlook, opening: opening, kept: buffer)
                notes(outlook, totals: totals, kept: kept)
            }
            .padding(12)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0.height; pageWidth = $0.width }
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
        let advice = adviceItems(outlook, opening: opening, kept: kept)
        let real = SafePull(opening: opening, buffer: kept, events: realEvents())
        let hasReal = !isFuture && !real.points.isEmpty
        // Real money is only known up to today, or to the end of a month that is over.
        let realEnd = isPast ? (Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month) ?? month) : Calendar.current.startOfDay(for: .now)
        let linked = plan.items.filter { item in item.transactionStamp.map { stamp in transactions.contains { $0.isLive && $0.createdAt.timeIntervalSinceReferenceDate == stamp } } ?? false }.count
        return ReportCard(title: "When You Can Pull Money Out") {
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 18) {
                    dayBlock("Planned", pull: hasPlan ? planned : nil)
                    if hasPlan {
                        Text("\(linked) of \(plan.items.count) plan line\(plan.items.count == 1 ? "" : "s") linked to real transactions")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, -14)
                    }
                    dayBlock("Outlook", pull: actual)
                    if let p = planned.best, let a = actual.best, hasPlan {
                        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: p.date), to: calendar.startOfDay(for: a.date)).day ?? 0
                        dayChip(days)
                    }
                    actualBlock(real, hasReal: hasReal, on: realEnd, against: actual, plan: hasPlan ? planned : nil, buffer: kept)
                    tightest(actual, buffer: kept)
                }
                .frame(width: 300, alignment: .leading)
                BalanceChart(month: month, planned: hasPlan ? planned : nil, actual: actual, real: hasReal ? real : nil, realEnd: realEnd, buffer: kept)
            }
            // Roomy: it takes whatever height the rest of the page leaves, between a floor and a ceiling.
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(height: pullOutHeight(advice: advice), alignment: .top)
        }
        .help("The first day the whole spare amount, what the month ends with less your buffer, can come out and the balance still never drops under the buffer. The outlook spreads budget spending through the month a week at a time.")
    }

    /// The money that really moved through the counted accounts this month, up to today.
    private func realEvents() -> [SafePull.Event] {
        let counted = Set(accounts.map(MonthOutlook.accountKey)).subtracting(excluded)
        let today = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return transactions.live
            .filter { !$0.isOpeningDeposit && $0.date < today && ($0.account.map { counted.contains(MonthOutlook.accountKey($0)) } ?? false) }
            .map { SafePull.Event(date: $0.date, amount: $0.amount) }
    }

    /// What the counted accounts really hold now, set against the Outlook and the plan for the same day, and against the buffer.
    private func actualBlock(_ real: SafePull, hasReal: Bool, on day: Date, against outlook: SafePull, plan: SafePull?, buffer: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text((isPast ? "ACTUAL AT THE END" : "ACTUAL SO FAR")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if hasReal {
                Text(real.ending, format: .appCurrency)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(real.ending < buffer ? Theme.red : Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(real.ending >= buffer ? "\((real.ending - buffer).formatted(.appCurrency)) above the buffer" : "\((buffer - real.ending).formatted(.appCurrency)) under the buffer")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    differenceChip(real.ending - outlook.balance(on: day), against: "the Outlook")
                    if let plan { differenceChip(real.ending - plan.balance(on: day), against: "the plan") }
                }
            } else {
                Text(isFuture ? "Not yet" : "–").font(.system(size: 26, weight: .bold)).foregroundStyle(.tertiary)
                Text(isFuture ? "This month hasn't started" : "No real transactions yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func differenceChip(_ difference: Decimal, against: String) -> some View {
        let color: Color = difference == 0 ? .secondary : (difference > 0 ? Theme.green : Theme.red)
        let words = difference == 0 ? "On \(against)" : "\(abs(difference).formatted(.appCurrency)) \(difference > 0 ? "ahead of" : "behind") \(against)"
        return Text(words)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .lineLimit(1)
    }

    /// The lowest the balance gets this month, so you can see how close it comes to the buffer.
    private func tightest(_ pull: SafePull, buffer: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TIGHTEST POINT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let low = pull.lowest {
                Text(low.balance, format: .appCurrency)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(low.balance < buffer ? Theme.red : Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("On \(low.date.formatted(.dateTime.month(.abbreviated).day())), buffer \(buffer.formatted(.appCurrency))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("–").font(.system(size: 26, weight: .bold)).foregroundStyle(.tertiary)
                Text("Nothing is dated yet").font(.caption).foregroundStyle(.secondary)
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

    // MARK: What to improve

    /// The few things that matter most this month.
    private func adviceItems(_ outlook: MonthOutlook, opening: Decimal, kept: Decimal) -> [OutlookAdvice.Item] {
        let hasPlan = !plan.items.isEmpty
        let planned = SafePull(opening: opening, buffer: kept, events: SafePull.events(plan: plan.items))
        let actual = SafePull(opening: opening, buffer: kept, events: SafePull.events(outlook: outlook))
        return OutlookAdvice.make(outlook: outlook, compare: hasPlan ? WarPlanComparison.build(items: plan.items, outlook: outlook) : nil,
                                  plannedPull: hasPlan ? planned : nil, actualPull: actual, buffer: kept,
                                  startingSet: !startAccount.isEmpty || OutlookSettings.decimal(startAmount) != nil, limit: 4)
    }

    /// Roughly what the list takes: each item's title, its detail over as many lines as the page's width needs, and its margins.
    private func adviceHeight(_ items: [OutlookAdvice.Item]) -> CGFloat {
        let characters = max((pageWidth - 150) / 6.6, 20)
        return items.reduce(0) { $0 + 36 + 17 * ceil(CGFloat($1.detail.count) / characters) }
    }

    /// The pull-out card's height: what is left of the page once the cards and the list are placed, kept between a floor and a ceiling.
    private func pullOutHeight(advice: [OutlookAdvice.Item]) -> CGFloat {
        let chrome: CGFloat = 12 * 2 + Self.versusHeight + 10 + 62 + 10 + 62
        let room = viewport - chrome - adviceHeight(advice)
        return min(max(room, Self.pullOutHeight), 520)
    }

    /// A list, one under another, each with its detail in full.
    private func improveCard(_ outlook: MonthOutlook, opening: Decimal, kept: Decimal) -> some View {
        let items = adviceItems(outlook, opening: opening, kept: kept)
        return ReportCard(title: "What to Improve") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: symbol(item.level)).foregroundStyle(color(item.level)).frame(width: 22).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.callout.weight(.semibold))
                            Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    if item.id != items.last?.id { Divider() }
                }
            }
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
    /// The least the pull-out card's chart area takes.
    private static let pullOutHeight: CGFloat = 430
    private static let versusHeight: CGFloat = 126

    /// Under the cards, only for a month that has closed: when its figures were kept, and what they would be now.
    @ViewBuilder
    private func notes(_ outlook: MonthOutlook, totals: Totals, kept: OutlookSnapshot?) -> some View {
        if let kept {
            Text("Saved \(kept.savedAt.formatted(date: .abbreviated, time: .omitted)), when the month closed."
                 + (outlook.leftToSave != kept.leftToSave ? " With changes made since, it would now be \(outlook.leftToSave.formatted(.appCurrency))." : ""))
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(actual, format: .appCurrency)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(signed ? (actual < 0 ? Theme.red : Theme.green) : (title == "Money In" ? Theme.green : Color.primary))
                .minimumScaleFactor(0.7).lineLimit(1)
            // The plan's place is always here, so the card is the same size with or without a plan.
            HStack {
                Text("Planned").foregroundStyle(.secondary)
                Spacer()
                if let planned { Text(planned, format: .appCurrency).fontWeight(.semibold) } else { Text("–").foregroundStyle(.tertiary) }
            }
            .font(.callout)
            bar(ratio)
            if let difference { chip(difference) } else { noPlanChip }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 126)
        .panelBackground(cornerRadius: 8)
        .help(note)
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

/// The balance through the month, from the plan and from the outlook, with the buffer as a dashed line and a dot on the safe day.
private struct BalanceChart: View {
    let month: Date
    let planned: SafePull?
    let actual: SafePull
    /// What really happened, up to `realEnd`. Nil when nothing has.
    var real: SafePull?
    var realEnd = Date.now
    let buffer: Decimal

    private var end: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: 1, to: month).flatMap { calendar.date(byAdding: .day, value: -1, to: $0) } ?? month
    }

    @ChartContentBuilder
    private func series(_ name: String, _ pull: SafePull, to stop: Date? = nil) -> some ChartContent {
        let last = stop ?? end
        let line = [SafePull.Point(id: -1, date: month, balance: pull.opening)] + pull.points.filter { $0.date <= last } + [SafePull.Point(id: Int.max, date: last, balance: stop == nil ? pull.ending : pull.balance(on: last))]
        ForEach(line) { point in
            LineMark(x: .value("Date", point.date), y: .value("Balance", chartValue(point.balance)), series: .value("Source", name))
                .foregroundStyle(by: .value("Source", name))
                .interpolationMethod(.stepEnd)
        }
        if stop == nil, let best = pull.best {
            PointMark(x: .value("Date", best.date), y: .value("Balance", chartValue(best.balance)))
                .foregroundStyle(by: .value("Source", name))
                .symbolSize(110)
        }
    }

    var body: some View {
        Chart {
            if let planned { series("Plan", planned) }
            series("Outlook", actual)
            if let real { series("Actual", real, to: min(realEnd, end)) }
            RuleMark(y: .value("Buffer", chartValue(buffer)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.orange)
                .annotation(position: .top, alignment: .leading) { Text("Buffer").font(.caption2).foregroundStyle(.orange) }
        }
        .chartForegroundStyleScale(["Plan": Color.accentColor, "Outlook": Theme.green, "Actual": Color.purple])
        .chartXScale(domain: month...end)
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
        .frame(height: 220)
    }
}
