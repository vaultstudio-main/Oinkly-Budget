import SwiftUI
import SwiftData

/// Progress on every budget. The Monthly tab shows the budgets set as a monthly amount, a month at a time; the Weekly tab shows the
/// ones set as a weekly amount, a week at a time, with the monthly maximum they add up to. A cash budget is marked as one on its
/// card, whichever tab it is on. Click a budget to change its amount. Budgets you have hidden, or made yourself, are set in
/// Settings ▸ Categories.
struct BudgetsView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Query private var cashMarks: [CashBudgetMark]
    @Query private var periods: [BudgetPeriod]

    private enum Tab: String, CaseIterable, Identifiable {
        case monthly = "Monthly", weekly = "Weekly"
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
        let isCash: Bool
        /// For a weekly budget: what its weekly amount adds up to in a month.
        var monthlyMaximum: Decimal?
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
                    setBudgetsButton
                }
            }
            ScrollView {
                VStack(spacing: 14) {
                    if tab == .monthly {
                        monthlyContent(all.filter { weekly[CashBudgets.key(for: $0)] == nil }, isCash: isCash)
                    } else {
                        weeklyContent(all.filter { weekly[CashBudgets.key(for: $0)] != nil }, weekly: weekly, isCash: isCash)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .piggybankScreenshotAction)) { note in
            if let action = note.userInfo?["action"] as? String, action.hasPrefix("budgetsTab:") {
                tab = action.hasSuffix("weekly") ? .weekly : .monthly
            }
        }
        #endif
        .sheet(item: $editing, onDismiss: { modelContext.saveNow() }) { category in
            if category.isCustom { CustomBudgetEditView(category: category) } else { BudgetEditView(category: category) }
        }
    }

    // MARK: Monthly

    @ViewBuilder
    private func monthlyContent(_ budgets: [Category], isCash: (Category) -> Bool) -> some View {
        let monthInterval = interval(ofMonth: month)
        let table = Budget.spentTable(transactions(from: monthInterval.start, to: monthInterval.end), interval: monthInterval)
        let shown = budgets.map { Shown(category: $0, limit: $0.monthlyLimit, spent: table[$0], isCash: isCash($0)) }
        let budgeted = shown.reduce(Decimal(0)) { $0 + $1.limit }
        let spent = shown.reduce(Decimal(0)) { $0 + $1.spent }

        helpLine("Click a budget to change its amount. Budgets set as a weekly amount are on the Weekly tab.")
        HStack(spacing: 12) {
            total("Budgeted", budgeted, note: "\(shown.count) budget\(shown.count == 1 ? "" : "s")")
            total("Spent", spent, note: "this month")
            total(budgeted - spent < 0 ? "Over" : "Left", abs(budgeted - spent), note: "across all budgets",
                  color: budgeted - spent < 0 ? Theme.red : Theme.green)
        }
        if shown.isEmpty {
            Text("No monthly budgets are set. Choose Set Budgets above, or add some in Settings ▸ Categories.")
                .foregroundStyle(.secondary)
                .padding(.top, 30)
        } else {
            grid(shown)
        }
    }

    // MARK: Weekly

    @ViewBuilder
    private func weeklyContent(_ budgets: [Category], weekly: [String: Decimal], isCash: (Category) -> Bool) -> some View {
        let weekInterval = interval(ofWeek: week)
        let table = Budget.spentTable(transactions(from: weekInterval.start, to: weekInterval.end), interval: weekInterval)
        // The monthly maximum is worked out for the month the week starts in, from the days that month really has.
        let maxMonth = MonthFilter.start(of: week)
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: maxMonth)?.count ?? 30
        let shown = budgets.map { category -> Shown in
            let amount = weekly[CashBudgets.key(for: category)] ?? 0
            return Shown(category: category, limit: amount, spent: table[category], isCash: isCash(category),
                         monthlyMaximum: BudgetPeriods.monthlyMaximum(weekly: amount, inMonthOf: maxMonth))
        }
        let budgeted = shown.reduce(Decimal(0)) { $0 + $1.limit }
        let spent = shown.reduce(Decimal(0)) { $0 + $1.spent }
        let monthlyMaximum = shown.reduce(Decimal(0)) { $0 + ($1.monthlyMaximum ?? 0) }

        if shown.isEmpty {
            helpLine("Click a budget to change its amount. Spending from every account in the category counts.")
            VStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("No weekly budgets yet").font(.headline)
                Text("Edit a budget and choose Weekly, and it appears here, where you can follow it a week at a time. Its monthly maximum is added up for you.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            }
            .padding(.top, 50)
        } else {
            helpLine("Click a budget to change its amount. Spending from every account in the category counts.")
            HStack(spacing: 12) {
                total("Weekly budget", budgeted, note: "\(shown.count) budget\(shown.count == 1 ? "" : "s")")
                total("Spent", spent, note: "this week")
                total(budgeted - spent < 0 ? "Over" : "Left", abs(budgeted - spent), note: "this week",
                      color: budgeted - spent < 0 ? Theme.red : Theme.green)
                total("Monthly maximum", monthlyMaximum, note: "\(maxMonth.formatted(.dateTime.month(.wide))) has \(daysInMonth) days")
            }
            grid(shown)
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// The line of instructions at the top of each tab.
    private func helpLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap").foregroundStyle(.secondary)
            Text(text)
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// In the page's top bar: opens Settings ▸ Categories, where budgets are set, shown or hidden, and made.
    private var setBudgetsButton: some View {
        Button {
            UserDefaults.standard.set("categories", forKey: MacSettingsView.tabKey)
            openSettings()
        } label: {
            Label("Set Budgets…", systemImage: "slider.horizontal.3")
        }
        .help("Opens Settings ▸ Categories, where you can set a budget on any category, show or hide it here, and add budgets of your own")
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
                if item.isCash {
                    Label("Cash", systemImage: "banknote")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.green)
                        .help("A cash budget: paid for in cash, so the Month Outlook leaves it out")
                }
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
            if let monthlyMaximum = item.monthlyMaximum {
                Divider()
                HStack {
                    Text("MONTHLY MAXIMUM").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .help("The weekly amount over seven, times the days in the month")
                    Spacer()
                    Text(monthlyMaximum, format: .appCurrency).font(.caption.weight(.semibold))
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
