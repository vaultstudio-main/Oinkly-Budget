import SwiftUI
import SwiftData

/// Progress on every budget. The Monthly tab shows the budgets that aren't cash budgets for a month; the Cash tab shows the cash
/// budgets a week at a time. A budget set as a weekly amount reads as its weekly amount on the Cash tab, and as its monthly
/// equivalent on the Monthly tab, with this week's progress under it. Click a budget to change its amount. Budgets you have
/// hidden, or made yourself, are set in Settings ▸ Categories.
struct BudgetsView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Query private var cashMarks: [CashBudgetMark]
    @Query private var periods: [BudgetPeriod]

    private enum Tab: String, CaseIterable, Identifiable {
        case monthly = "Monthly", cash = "Cash"
        var id: Self { self }
    }

    @State private var tab = Tab.monthly
    @State private var month = MonthFilter.start(of: .now)
    @State private var week = BudgetsView.weekStart(of: .now)
    @State private var editing: Category?

    private static func weekStart(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    private var monthRange: ClosedRange<Date> {
        let current = MonthFilter.start(of: .now)
        return (Calendar.current.date(byAdding: .month, value: -24, to: current) ?? current)...current
    }

    private var weekRange: ClosedRange<Date> {
        let current = Self.weekStart(of: .now)
        return (Calendar.current.date(byAdding: .weekOfYear, value: -104, to: current) ?? current)...current
    }

    /// Live transactions dated from `start` up to (not including) `end`.
    private func transactions(from start: Date, to end: Date) -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.date >= start && $0.date < end })
        return ((try? modelContext.fetch(descriptor)) ?? []).live
    }

    private func interval(ofWeek start: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: start) ?? DateInterval(start: start, duration: 7 * 86_400)
    }

    private func interval(ofMonth start: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .month, for: start) ?? DateInterval(start: start, duration: 30 * 86_400)
    }

    /// One budget as it is shown: the amount for its own period, what was spent in that period, and a caption.
    private struct Shown: Identifiable {
        let category: Category
        let limit: Decimal
        let spent: Decimal
        let caption: String?
        /// For a weekly budget on the Monthly tab: this week so far.
        var weekSpent: Decimal?
        var weekLimit: Decimal?
        var id: PersistentIdentifier { category.persistentModelID }
    }

    var body: some View {
        let cashKeys = Set(cashMarks.live.map(\.key))
        let weekly = Dictionary(periods.live.map { ($0.key, $0.weeklyAmount) }, uniquingKeysWith: { first, _ in first })
        let all = allCategories.live.filter { !$0.isIncome && $0.showOnBudgets && $0.monthlyLimit > 0 }
        let isCash: (Category) -> Bool = { cashKeys.contains(CashBudgets.key(for: $0)) }

        VStack(spacing: 0) {
            PinnedHeader("Budgets") {
                HStack(spacing: 14) {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    if tab == .monthly {
                        MonthSelector(month: $month, range: monthRange)
                    } else {
                        WeekSelector(week: $week, range: weekRange)
                    }
                    Spacer()
                }
            }
            ScrollView {
                VStack(spacing: 14) {
                    if tab == .monthly {
                        monthlyContent(all.filter { !isCash($0) }, weekly: weekly)
                    } else {
                        cashContent(all.filter(isCash), weekly: weekly)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            if let action = note.userInfo?["action"] as? String, action.hasPrefix("budgetsTab:") {
                tab = action.hasSuffix("cash") ? .cash : .monthly
            }
        }
        #endif
        .sheet(item: $editing, onDismiss: { modelContext.saveNow() }) { category in
            if category.isCustom { CustomBudgetEditView(category: category) } else { BudgetEditView(category: category) }
        }
    }

    // MARK: Monthly

    @ViewBuilder
    private func monthlyContent(_ budgets: [Category], weekly: [String: Decimal]) -> some View {
        let monthInterval = interval(ofMonth: month)
        let table = Budget.spentTable(transactions(from: monthInterval.start, to: monthInterval.end), interval: monthInterval)
        let isCurrentMonth = MonthFilter.isCurrent(month)
        // This week's progress for weekly budgets, only while looking at the current month.
        let currentWeek = interval(ofWeek: Self.weekStart(of: .now))
        let weekTable = isCurrentMonth && weekly.isEmpty == false
            ? Budget.spentTable(transactions(from: currentWeek.start, to: currentWeek.end), interval: currentWeek) : nil
        let shown = budgets.map { category -> Shown in
            let amount = weekly[CashBudgets.key(for: category)]
            return Shown(category: category, limit: category.monthlyLimit, spent: table[category],
                         caption: amount.map { "\($0.formatted(.appCurrency)) a week" },
                         weekSpent: amount != nil ? weekTable?[category] : nil, weekLimit: amount)
        }
        let budgeted = shown.reduce(Decimal(0)) { $0 + $1.limit }
        let spent = shown.reduce(Decimal(0)) { $0 + $1.spent }

        HStack(spacing: 12) {
            total("Budgeted", budgeted, note: "\(shown.count) budget\(shown.count == 1 ? "" : "s")")
            total("Spent", spent, note: "this month")
            total(budgeted - spent < 0 ? "Over" : "Left", abs(budgeted - spent), note: "across all budgets",
                  color: budgeted - spent < 0 ? Theme.red : Theme.green)
        }
        helpLine("Click a budget to change its amount. Cash budgets are on the Cash tab.")
        if shown.isEmpty {
            Text("No budgets are set. Choose Set Hidden and Custom Budgets above, or add some in Settings ▸ Categories.")
                .foregroundStyle(.secondary)
                .padding(.top, 30)
        } else {
            grid(shown)
        }
    }

    // MARK: Cash

    @ViewBuilder
    private func cashContent(_ budgets: [Category], weekly: [String: Decimal]) -> some View {
        let weekInterval = interval(ofWeek: week)
        let monthInterval = interval(ofMonth: MonthFilter.start(of: week))
        let from = min(weekInterval.start, monthInterval.start)
        let to = max(weekInterval.end, monthInterval.end)
        let fetched = transactions(from: from, to: to)
        let weekTable = Budget.spentTable(fetched, interval: weekInterval)
        let monthTable = Budget.spentTable(fetched, interval: monthInterval)
        let weeklyBudgets = budgets.filter { weekly[CashBudgets.key(for: $0)] != nil }
        let monthlyBudgets = budgets.filter { weekly[CashBudgets.key(for: $0)] == nil }
        let weeklyShown = weeklyBudgets.map { Shown(category: $0, limit: weekly[CashBudgets.key(for: $0)] ?? 0, spent: weekTable[$0], caption: "a week") }
        let monthlyShown = monthlyBudgets.map {
            Shown(category: $0, limit: $0.monthlyLimit, spent: monthTable[$0], caption: "a month, \(monthInterval.start.formatted(.dateTime.month(.wide)))")
        }
        // The totals use whichever kind there is, weekly first, so every figure in them is for the same period.
        let tiles = weeklyShown.isEmpty ? monthlyShown : weeklyShown
        let budgeted = tiles.reduce(Decimal(0)) { $0 + $1.limit }
        let spent = tiles.reduce(Decimal(0)) { $0 + $1.spent }

        if budgets.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "banknote").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("No cash budgets yet").font(.headline)
                Text("Edit a budget and tick Counts as a cash budget, and it appears here, where you can follow it a week at a time. Cash budgets are left out of the Month Outlook.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            }
            .padding(.top, 50)
        } else {
            HStack(spacing: 12) {
                total("Budgeted", budgeted, note: weeklyShown.isEmpty ? "this month" : "this week")
                total("Spent", spent, note: weeklyShown.isEmpty ? "this month" : "this week")
                total(budgeted - spent < 0 ? "Over" : "Left", abs(budgeted - spent), note: "across the cash budgets",
                      color: budgeted - spent < 0 ? Theme.red : Theme.green)
            }
            helpLine("Click a budget to change its amount. Spending from every account in the category counts.")
            if !weeklyShown.isEmpty {
                sectionTitle("Week of \(weekInterval.start.formatted(.dateTime.month(.abbreviated).day()))")
                grid(weeklyShown)
            }
            if !monthlyShown.isEmpty {
                sectionTitle("Monthly cash budgets")
                grid(monthlyShown)
            }
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func helpLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap").foregroundStyle(.secondary)
            Text(text)
            Spacer()
            Button {
                UserDefaults.standard.set("categories", forKey: MacSettingsView.tabKey)
                openSettings()
            } label: {
                Label("Set Hidden and Custom Budgets…", systemImage: "slider.horizontal.3")
            }
            .help("Opens Settings ▸ Categories, where you can set a budget on any category, show or hide it here, and add budgets of your own")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func grid(_ items: [Shown]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                Button { editing = item.category } label: { card(item) }
                    .buttonStyle(.plain)
                    .help("Click to change the \(item.category.name) budget")
                    .accessibilityHint("Opens the budget to change its amount")
            }
        }
    }

    /// A centred total, the same width as its neighbours.
    private func total(_ title: String, _ amount: Decimal, note: String, color: Color = .primary) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(amount, format: .appCurrency)
                .font(.title2.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .panelBackground(cornerRadius: 8)
    }

    private func bar(spent: Decimal, limit: Decimal) -> some View {
        ProgressView(value: Budget.progress(spent: spent, limit: limit))
            .tint(spent > limit ? Theme.red : (spent >= limit * Decimal(0.85) ? .orange : Theme.green))
    }

    private func card(_ item: Shown) -> some View {
        let over = item.spent > item.limit
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CategoryBadge(category: item.category, size: 26)
                Text(item.category.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            bar(spent: item.spent, limit: item.limit)
            HStack {
                Text(item.spent, format: .appCurrency).font(.callout.weight(.semibold))
                Text("of \(item.limit.formatted(.appCurrency))").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(over ? "Over by \((item.spent - item.limit).formatted(.appCurrency))" : "\((item.limit - item.spent).formatted(.appCurrency)) left")
                    .font(.caption)
                    .foregroundStyle(over ? Theme.red : .secondary)
            }
            if let caption = item.caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            if let weekSpent = item.weekSpent, let weekLimit = item.weekLimit {
                Divider()
                Text("THIS WEEK").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                bar(spent: weekSpent, limit: weekLimit)
                HStack {
                    Text(weekSpent, format: .appCurrency).font(.caption.weight(.semibold))
                    Text("of \(weekLimit.formatted(.appCurrency))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(weekSpent > weekLimit ? "Over by \((weekSpent - weekLimit).formatted(.appCurrency))" : "\((weekLimit - weekSpent).formatted(.appCurrency)) left")
                        .font(.caption)
                        .foregroundStyle(weekSpent > weekLimit ? Theme.red : .secondary)
                }
            }
        }
        .padding(12)
        .panelBackground(cornerRadius: 8)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// Previous and next week, with the week's dates and a pill to jump back to this week.
struct WeekSelector: View {
    @Binding var week: Date
    let range: ClosedRange<Date>

    private var calendar: Calendar { .current }
    private var interval: DateInterval { calendar.dateInterval(of: .weekOfYear, for: week) ?? DateInterval(start: week, duration: 7 * 86_400) }
    private var isCurrent: Bool { calendar.isDate(week, equalTo: .now, toGranularity: .weekOfYear) }

    private var label: String {
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let first = interval.start.formatted(.dateTime.month(.abbreviated).day())
        let end = calendar.isDate(interval.start, equalTo: last, toGranularity: .month)
            ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        return "\(first) – \(end), \(last.formatted(.dateTime.year()))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(week <= range.lowerBound)
                .accessibilityLabel("Previous week")
            Text(label)
                .font(.headline)
                .frame(minWidth: 170)
                .contentTransition(.numericText())
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(week >= range.upperBound)
                .accessibilityLabel("Next week")
            CurrentPeriodButton(title: "This Week", isCurrent: isCurrent) {
                withAnimation(.smooth) { week = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? week }
            }
        }
    }

    private func step(_ value: Int) {
        if let next = calendar.date(byAdding: .weekOfYear, value: value, to: week) {
            withAnimation(.smooth) { week = min(max(next, range.lowerBound), range.upperBound) }
        }
    }
}
