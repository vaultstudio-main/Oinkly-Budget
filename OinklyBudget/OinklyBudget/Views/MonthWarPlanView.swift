import SwiftUI
import SwiftData

/// The Month Outlook's second tab: a blank sheet for the month. The person adds lines, or pulls in paycheques, bills and
/// budgets from the outlook as ordinary lines, and sees what is left after each one and how much is extra so far.
/// Nothing is fixed: every line can be changed or removed. It is kept on this Mac, a month at a time.
struct MonthWarPlanView: View {
    let outlook: MonthOutlook

    /// One line of the plan. Money out and money in are both stored as a positive amount.
    struct PlanItem: Codable, Identifiable, Equatable {
        var id = UUID()
        var title: String
        var date: Date
        var amount: Decimal
        var isIncome: Bool
        /// Where the line came from, for its icon: "bill", "budget", "income" or nil for one typed in.
        var origin: String?

        var symbol: String {
            switch origin {
            case "bill": "calendar"
            case "budget": "chart.pie"
            case "income": "banknote"
            default: isIncome ? "arrow.down.circle" : "arrow.up.circle"
            }
        }
    }

    private struct Stored: Codable {
        var start: Decimal = 0
        /// An account whose balance is the starting amount, as `MonthOutlook.accountKey`. Nil when a number is typed.
        var startAccount: String?
        /// Money to keep out of reach: the plan counts only what is above it as spare.
        var buffer: Decimal?
        var items: [PlanItem] = []
    }

    @Query(sort: \Account.name) private var allAccounts: [Account]
    @State private var items: [PlanItem] = []
    @State private var typedStart: Decimal?
    @State private var startAccount: String?
    @State private var buffer: Decimal?
    @State private var draft: PlanItem?

    private var storageKey: String { "warPlan." + OutlookSnapshots.key(for: outlook.month) }
    private var accounts: [Account] { allAccounts.live.filter { !$0.supportsHoldings } }
    private var startingAccount: Account? { startAccount.flatMap { key in accounts.first { MonthOutlook.accountKey($0) == key } } }
    private var opening: Decimal { startingAccount?.balance(asOf: .now) ?? typedStart ?? 0 }

    private var sorted: [PlanItem] {
        items.sorted { ($0.date, $0.isIncome ? 0 : 1, $0.title) < ($1.date, $1.isIncome ? 0 : 1, $1.title) }
    }

    private var monthEnd: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: outlook.month) ?? outlook.month) ?? outlook.month
    }

    private func signed(_ item: PlanItem) -> Decimal { item.isIncome ? item.amount : -item.amount }

    var body: some View {
        let list = sorted
        let extra = list.reduce(Decimal(0)) { $0 + signed($1) }
        let ending = opening + extra
        let kept = buffer ?? 0
        let moneyIn = list.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount }
        let moneyOut = list.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 + $1.amount }
        let best = bestDay(list, spare: ending - kept)
        return VStack(spacing: 14) {
                ReportCard(title: "Monthly War Plan") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 30) {
                            figure("Extra This Month", extra, note: "money in less money out, from the lines below")
                            figure("Left at the End", ending, note: "the starting amount plus the extra")
                            figure("Above the Buffer", ending - kept, note: "left at the end less your buffer")
                            bestDayFigure(best, spare: ending - kept)
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Text("Starting with")
                            Menu {
                                Button("A number I type") { startAccount = nil }
                                Divider()
                                ForEach(accounts) { account in
                                    Button("\(account.name): \(account.balance(asOf: .now).formatted(.appCurrency))") { startAccount = MonthOutlook.accountKey(account) }
                                }
                            } label: {
                                Text(startingAccount.map { "\($0.name)'s balance" } ?? "A number I type")
                            }
                            .fixedSize()
                            if let account = startingAccount {
                                Text(account.balance(asOf: .now), format: .appCurrency).fontWeight(.semibold)
                            } else {
                                CurrencyField("Starting amount", value: $typedStart)
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 130)
                            }
                            Text("Buffer")
                            CurrencyField("Buffer", value: $buffer)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .help("Money to keep untouched. Left After turns orange when a line takes you under it")
                            Spacer()
                            Menu("Pull In…", systemImage: "square.and.arrow.down") {
                                Button("Paycheques and Income") { pull(incomeLines) }
                                Button("Bills and Repeating Expenses") { pull(billLines) }
                                Button("Budgets") { pull(budgetLines) }
                            }
                            .fixedSize()
                            .help("Copies lines from the Overview into the plan, where you can change or remove them")
                            Button("Add a Line", systemImage: "plus.circle") { draft = newDraft() }
                        }
                        Text("This sheet starts blank. Add a line for anything you expect, or pull in the paycheques, bills and budgets the Overview already knows, then change or remove whatever you like. This is only a what-if sheet: it never changes your accounts, transactions, bills or budgets, and nothing else in the app reads it.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                table(list, kept: kept)
                totalsCard(kept: kept, extra: extra, ending: ending, moneyIn: moneyIn, moneyOut: moneyOut)
        }
        .padding(16)
        .sheet(item: $draft) { item in
            PlanItemForm(item: item, isNew: !items.contains { $0.id == item.id },
                         save: { saved in
                             if let index = items.firstIndex(where: { $0.id == saved.id }) { items[index] = saved } else { items.append(saved) }
                         },
                         remove: { items.removeAll { $0.id == item.id } })
        }
        .onAppear(perform: load)
        .onChange(of: outlook.month) { _, _ in load() }
        .onChange(of: items) { _, _ in save() }
        .onChange(of: typedStart) { _, _ in save() }
        .onChange(of: startAccount) { _, _ in save() }
        .onChange(of: buffer) { _, _ in save() }
    }

    // MARK: Pieces

    private func figure(_ title: String, _ amount: Decimal, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
            Text(amount, format: .appCurrency)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(amount < 0 ? Theme.red : Theme.green)
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Best day to move the extra

    /// The earliest day from which the whole spare amount can be taken out and the plan still never drops below the buffer.
    /// That is the day after the last line that leaves less than the month ends with.
    private func bestDay(_ list: [PlanItem], spare: Decimal) -> Date? {
        guard spare > 0, !list.isEmpty else { return nil }
        let balances = running(list)
        let ending = balances[balances.count - 1].left
        let first = (balances.lastIndex { $0.left < ending } ?? -1) + 1
        return first < list.count ? list[first].date : nil
    }

    private func bestDayFigure(_ date: Date?, spare: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BEST DAY TO MOVE IT").font(.caption).foregroundStyle(.secondary)
            if let date {
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 30, weight: .bold))
                Text("from here the full \(spare.formatted(.appCurrency)) is there and stays above your buffer").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("None yet").font(.system(size: 30, weight: .bold)).foregroundStyle(.secondary)
                Text(spare > 0 ? "add lines to find it" : "nothing is spare yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: The table

    private static let rowHeight: CGFloat = 30
    private static let widths: (icon: CGFloat, date: CGFloat, amount: CGFloat, balance: CGFloat) = (34, 90, 115, 125)

    /// One cell: a fixed width, or the rest of the row when `width` is nil, with a line down its left edge.
    private func cell<Content: View>(_ width: CGFloat?, _ alignment: Alignment = .leading, @ViewBuilder _ content: () -> Content) -> some View {
        ZStack { content() }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: width, height: Self.rowHeight, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 1) }
    }

    /// A whole row of the table; blank for the empty rows that fill the rest of the page.
    private func tableRow(icon: String? = nil, iconColor: Color = .secondary, date: String = "", title: String = "",
                          moneyIn: Decimal? = nil, moneyOut: Decimal? = nil, left: Decimal? = nil, extra: Decimal? = nil,
                          leftColor: Color = .primary, bold: Bool = false) -> some View {
        HStack(spacing: 0) {
            cell(Self.widths.icon, .center) { if let icon { Image(systemName: icon).foregroundStyle(iconColor) } }
            cell(Self.widths.date) { Text(date) }
            cell(nil) { Text(title).fontWeight(bold ? .semibold : .regular) }
            cell(Self.widths.amount, .trailing) { if let moneyIn { Text(moneyIn, format: .appCurrency).foregroundStyle(Theme.green) } }
            cell(Self.widths.amount, .trailing) { if let moneyOut { Text(moneyOut, format: .appCurrency) } }
            cell(Self.widths.balance, .trailing) { if let left { Text(left, format: .appCurrency).fontWeight(.semibold).foregroundStyle(leftColor) } }
            cell(Self.widths.balance, .trailing) { if let extra { Text(extra, format: .appCurrency).foregroundStyle(extra < 0 ? Theme.red : Theme.green) } }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.14)).frame(height: 1) }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            cell(Self.widths.icon, .center) { Text("") }
            cell(Self.widths.date) { Text("Date") }
            cell(nil) { Text("Item") }
            cell(Self.widths.amount, .trailing) { Text("Money In") }
            cell(Self.widths.amount, .trailing) { Text("Money Out") }
            cell(Self.widths.balance, .trailing) { Text("Left After") }
            cell(Self.widths.balance, .trailing) { Text("Extra So Far") }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .background(Color.primary.opacity(0.08))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.14)).frame(height: 1) }
    }

    private func leftColor(_ left: Decimal, kept: Decimal) -> Color {
        left < 0 ? Theme.red : (left < kept ? Color.orange : Color.primary)
    }

    private func table(_ list: [PlanItem], kept: Decimal) -> some View {
        let balances = running(list)
        return VStack(alignment: .leading, spacing: 8) {
            Text("WAR PLAN").font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                headerRow
                GeometryReader { geo in
                    ScrollView {
                        VStack(spacing: 0) {
                            tableRow(icon: "flag", date: "Start", title: startingAccount.map { "Starting with \($0.name)'s balance" } ?? "Starting with", left: opening)
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                                Button { draft = item } label: {
                                    tableRow(icon: item.symbol, iconColor: item.isIncome ? Theme.green : .secondary,
                                             date: item.date.formatted(.dateTime.weekday(.abbreviated).day()), title: item.title,
                                             moneyIn: item.isIncome ? item.amount : nil, moneyOut: item.isIncome ? nil : item.amount,
                                             left: balances[index].left, extra: balances[index].extra,
                                             leftColor: leftColor(balances[index].left, kept: kept))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Click to change or remove this line")
                                .contextMenu {
                                    Button("Change…", systemImage: "pencil") { draft = item }
                                    Button("Remove", systemImage: "trash", role: .destructive) { items.removeAll { $0.id == item.id } }
                                }
                            }
                            // Empty rows to the bottom of the page, so it reads as a sheet to fill in.
                            ForEach(0..<max(0, Int(geo.size.height / Self.rowHeight) - list.count - 1), id: \.self) { _ in tableRow() }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2), lineWidth: 1) }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelBackground(cornerRadius: 8)
    }

    /// Its own card under the table: the totals, the buffer zone and what is really spare.
    private func totalsCard(kept: Decimal, extra: Decimal, ending: Decimal, moneyIn: Decimal, moneyOut: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTALS").font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                tableRow(icon: "sum", title: "Totals", moneyIn: moneyIn, moneyOut: moneyOut, left: ending, extra: extra,
                         leftColor: leftColor(ending, kept: kept), bold: true)
                tableRow(icon: "shield", iconColor: .orange, title: "Buffer zone: kept untouched", left: kept)
                    .background(Color.orange.opacity(0.08))
                tableRow(icon: "checkmark.circle", iconColor: ending - kept < 0 ? Theme.red : Theme.green, title: "Above the buffer: what is really spare",
                         left: ending - kept, leftColor: ending - kept < 0 ? Theme.red : Theme.green, bold: true)
                    .background(Color.primary.opacity(0.06))
            }
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2), lineWidth: 1) }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .panelBackground(cornerRadius: 8)
    }

    private func running(_ list: [PlanItem]) -> [(left: Decimal, extra: Decimal)] {
        var left = opening
        var extra: Decimal = 0
        return list.map { item in
            left += signed(item)
            extra += signed(item)
            return (left, extra)
        }
    }

    private func newDraft() -> PlanItem {
        let today = Calendar.current.isDate(.now, equalTo: outlook.month, toGranularity: .month)
        return PlanItem(title: "", date: today ? .now : outlook.month, amount: 0, isIncome: false, origin: nil)
    }

    // MARK: Pulling in

    private var incomeLines: [PlanItem] {
        outlook.income.map { PlanItem(title: $0.title, date: $0.date, amount: $0.counted, isIncome: true, origin: "income") }
            + (outlook.otherIncome > 0 ? [PlanItem(title: "Other income so far", date: outlook.month, amount: outlook.otherIncome, isIncome: true, origin: "income")] : [])
    }

    private var billLines: [PlanItem] {
        (outlook.bills + outlook.budgets.flatMap(\.inside)).map { PlanItem(title: $0.title, date: $0.date, amount: $0.counted, isIncome: false, origin: "bill") }
    }

    private var budgetLines: [PlanItem] {
        outlook.budgets.map { PlanItem(title: $0.category.name + " budget", date: monthEnd, amount: $0.counted, isIncome: false, origin: "budget") }
    }

    /// Adds the lines that aren't already in the plan with the same name, date and amount.
    private func pull(_ lines: [PlanItem]) {
        for line in lines where line.amount > 0 && !items.contains(where: { $0.title == line.title && $0.date == line.date && $0.amount == line.amount }) {
            items.append(line)
        }
    }

    // MARK: Keeping

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey), let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            items = []
            typedStart = nil
            startAccount = nil
            buffer = nil
            return
        }
        items = stored.items
        typedStart = stored.start == 0 ? nil : stored.start
        startAccount = stored.startAccount
        buffer = stored.buffer
    }

    private func save() {
        let stored = Stored(start: typedStart ?? 0, startAccount: startAccount, buffer: buffer, items: items)
        if stored.items.isEmpty && stored.start == 0 && stored.startAccount == nil && (buffer ?? 0) == 0 {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

/// Adds or changes one line of the plan.
private struct PlanItemForm: View {
    @State var item: MonthWarPlanView.PlanItem
    let isNew: Bool
    let save: (MonthWarPlanView.PlanItem) -> Void
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool { !item.title.trimmingCharacters(in: .whitespaces).isEmpty && item.amount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add a Line" : "Change Line").font(.headline)
            Picker("Kind", selection: $item.isIncome) {
                Text("Money Out").tag(false)
                Text("Money In").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("What is it", text: $item.title)
            DatePicker("Date", selection: $item.date, displayedComponents: .date)
            CurrencyField("Amount", amount: $item.amount)
            HStack {
                if !isNew {
                    Button("Remove", role: .destructive) { remove(); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Add" : "Save") {
                    item.title = item.title.trimmingCharacters(in: .whitespaces)
                    save(item)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
