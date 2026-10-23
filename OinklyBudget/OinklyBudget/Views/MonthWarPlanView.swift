import SwiftUI
import SwiftData

/// The Monthly Outlook's second tab: a blank sheet for the month. The person adds lines, or pulls in paycheques, bills and
/// budgets from the outlook as ordinary lines, and sees what is left after each one and how much is extra so far.
/// Nothing is fixed: every line can be changed or removed. What it starts with, the buffer and the accounts counted are in
/// the page's Settings. The plan is only a what-if sheet: it never changes accounts, transactions, bills or budgets.
struct MonthWarPlanView: View {
    let outlook: MonthOutlook
    @Binding var plan: WarPlanData
    /// What the month starts with and the buffer, from the Settings window.
    let opening: Decimal
    let kept: Decimal
    let startLabel: String

    @Query(sort: \Account.name) private var allAccounts: [Account]
    @Query(sort: \Category.name) private var allCategories: [Category]
    @State private var draft: WarPlanItem?

    /// The accounts lines can be pulled in from: checking, savings and cash only.
    private var accounts: [Account] { allAccounts.live.filter(MonthOutlook.isEligible) }

    private var items: [WarPlanItem] {
        get { plan.items }
        nonmutating set { plan.items = newValue }
    }

    private var sorted: [WarPlanItem] {
        items.sorted { ($0.date, $0.isIncome ? 0 : 1, $0.title) < ($1.date, $1.isIncome ? 0 : 1, $1.title) }
    }

    private var monthEnd: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: outlook.month) ?? outlook.month) ?? outlook.month
    }

    private func signed(_ item: WarPlanItem) -> Decimal { item.isIncome ? item.amount : -item.amount }

    var body: some View {
        let list = sorted
        let extra = list.reduce(Decimal(0)) { $0 + signed($1) }
        let ending = opening + extra
        let moneyIn = list.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount }
        let moneyOut = list.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 + $1.amount }
        let safe = SafePull(opening: opening, buffer: kept, events: SafePull.events(plan: list))
        return VStack(spacing: 14) {
            ReportCard(title: "Your Plan") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 20) {
                        Text("A blank sheet: add a line for anything you expect, or pull in what the Outlook already knows, then change or remove whatever you like. Starting amount, buffer and accounts are in Settings. It never changes your accounts, transactions, bills or budgets.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 10)
                        Button("Add a Line", systemImage: "plus.circle") { draft = newDraft() }
                            .buttonStyle(.borderedProminent)
                        Menu("Pull In…", systemImage: "square.and.arrow.down") {
                            Button("Paycheques and Income") { pull(incomeLines) }
                            Button("Bills and Repeating Expenses") { pull(billLines) }
                            if !accounts.isEmpty {
                                Divider()
                                Menu("From an Account") {
                                    ForEach(accounts) { account in
                                        Button(account.name) { pull(accountLines(account)) }
                                    }
                                }
                            }
                        }
                        .fixedSize()
                        .help("Copies lines from the Outlook into the plan, where you can change or remove them: all the income, all the bills and repeating expenses, or just those that go through one account. Budgets are never pulled in")
                    }
                    HStack(alignment: .top, spacing: 12) {
                        let incomes = list.filter(\.isIncome), outgoings = list.filter { !$0.isIncome }
                        StatTile(title: "Total Income") {
                            Text(moneyIn, format: .appCurrency).foregroundStyle(Theme.green)
                        } note: { Text("\(incomes.count) line\(incomes.count == 1 ? "" : "s") coming in") }
                        StatTile(title: "Total Outgoing") {
                            Text(moneyOut, format: .appCurrency)
                        } note: { Text("\(outgoings.count) line\(outgoings.count == 1 ? "" : "s") going out") }
                        StatTile(title: "Extra This Month") {
                            Text(extra, format: .appCurrency).foregroundStyle(extra < 0 ? Theme.red : Theme.green)
                        } note: { Text("income less outgoing") }
                        StatTile(title: "Left at the End") {
                            Text(ending, format: .appCurrency).foregroundStyle(ending < 0 ? Theme.red : Theme.green)
                        } note: { Text("starting with \(opening.formatted(.appCurrency))") }
                        StatTile(title: "Tightest Point") {
                            Text(safe.lowest?.balance ?? opening, format: .appCurrency)
                                .foregroundStyle((safe.lowest?.balance ?? opening) < kept ? Theme.red : Color.primary)
                        } note: {
                            Text(safe.lowest.map { "on \($0.date.formatted(.dateTime.month(.abbreviated).day())), buffer \(kept.formatted(.appCurrency))" } ?? "add lines to find it")
                        }
                        safeTile(safe, hasLines: !list.isEmpty)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            table(list, kept: kept)
        }
        .padding(16)
        .sheet(item: $draft) { item in
            PlanItemForm(item: item, isNew: !items.contains { $0.id == item.id },
                         save: { saved in
                             if let index = items.firstIndex(where: { $0.id == saved.id }) { items[index] = saved } else { items.append(saved) }
                         },
                         remove: { items.removeAll { $0.id == item.id } })
        }
    }

    // MARK: Pieces

    // MARK: Safe to move to savings

    /// What the plan says is safe to move to savings, and from which day: what it ends with less the buffer, from the earliest
    /// day all of it can come out and the balance still never drops under the buffer.
    private func safeTile(_ pull: SafePull, hasLines: Bool) -> some View {
        StatTile(title: "Safe to Move to Savings") {
            if pull.spare > 0, pull.best != nil {
                Text(pull.spare, format: .appCurrency).foregroundStyle(Theme.green)
            } else {
                Text(max(pull.spare, 0), format: .appCurrency).foregroundStyle(.secondary)
            }
        } note: {
            if pull.spare > 0, let best = pull.best {
                Text("from \(best.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), buffer \(pull.buffer.formatted(.appCurrency))")
            } else {
                Text(hasLines ? "nothing is safe to move yet" : "add lines to find it")
            }
        }
        .help("What the plan ends with less your buffer, from the earliest day all of it can come out and the balance still never drops under the buffer.")
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
    private func tableRow(icon: String? = nil, iconColor: Color = .secondary, artwork: (symbol: String, theme: Int)? = nil, date: String = "", title: String = "",
                          moneyIn: Decimal? = nil, moneyOut: Decimal? = nil, left: Decimal? = nil, extra: Decimal? = nil,
                          leftColor: Color = .primary, bold: Bool = false) -> some View {
        HStack(spacing: 0) {
            cell(Self.widths.icon, .center) {
                if let artwork {
                    ArtworkTile(symbol: artwork.symbol, theme: artwork.theme)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else if let icon {
                    Image(systemName: icon).foregroundStyle(iconColor)
                }
            }
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

    private func table(_ list: [WarPlanItem], kept: Decimal) -> some View {
        let balances = running(list)
        return VStack(alignment: .leading, spacing: 8) {
            Text("WAR PLAN").font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                headerRow
                GeometryReader { geo in
                    ScrollView {
                        VStack(spacing: 0) {
                            tableRow(icon: "flag", date: "Start", title: startLabel, left: opening)
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                                Button { draft = item } label: {
                                    tableRow(artwork: look(of: item),
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

    /// The icon and colour a line shows: the ones chosen, else its category's icon, else the one for where it came from, in a colour
    /// from the rainbow.
    private func look(of item: WarPlanItem) -> (symbol: String, theme: Int) {
        let category = item.categoryKey.flatMap { key in allCategories.live.first { ($0.systemKey ?? $0.name) == key } }
        return (item.iconSymbol ?? category?.symbol ?? item.symbol,
                ArtworkTheme.resolved(item.iconTheme ?? 0, seed: ArtworkTheme.seed(item.title)))
    }

    private func running(_ list: [WarPlanItem]) -> [(left: Decimal, extra: Decimal)] {
        var left = opening
        var extra: Decimal = 0
        return list.map { item in
            left += signed(item)
            extra += signed(item)
            return (left, extra)
        }
    }

    private func newDraft() -> WarPlanItem {
        let today = Calendar.current.isDate(.now, equalTo: outlook.month, toGranularity: .month)
        return WarPlanItem(title: "", date: today ? .now : outlook.month, amount: 0, isIncome: false, origin: nil)
    }

    // MARK: Pulling in

    private var incomeLines: [WarPlanItem] {
        outlook.income.map { WarPlanItem(title: $0.title, date: $0.date, amount: $0.counted, isIncome: true, origin: "income") }
            + (outlook.otherIncome > 0 ? [WarPlanItem(title: "Other income so far", date: outlook.month, amount: outlook.otherIncome, isIncome: true, origin: "income")] : [])
    }

    private var billLines: [WarPlanItem] {
        (outlook.bills + outlook.budgets.flatMap(\.inside)).map { WarPlanItem(title: $0.title, date: $0.date, amount: $0.counted, isIncome: false, origin: "bill") }
    }

    /// The paycheques, bills and repeating expenses that go through one account: the account a bill was paid from or is set to come
    /// out of, and the account a repeating entry belongs to. Budgets are never part of it.
    private func accountLines(_ account: Account) -> [WarPlanItem] {
        let key = MonthOutlook.accountKey(account)
        return (outlook.income + outlook.bills + outlook.budgets.flatMap(\.inside)).filter { $0.accountKey == key }.map {
            let isIncome = $0.kind == "Income"
            return WarPlanItem(title: $0.title, date: $0.date, amount: $0.counted, isIncome: isIncome, origin: isIncome ? "income" : "bill")
        }
    }

    /// Adds the lines that aren't already in the plan with the same name, date and amount.
    private func pull(_ lines: [WarPlanItem]) {
        for line in lines where line.amount > 0 && !items.contains(where: { $0.title == line.title && $0.date == line.date && $0.amount == line.amount }) {
            items.append(line)
        }
    }

}

/// Adds or changes one line of the plan: what it is, when, how much and which category, and the icon and colour it has in the sheet.
private struct PlanItemForm: View {
    @State var item: WarPlanItem
    let isNew: Bool
    let save: (WarPlanItem) -> Void
    let remove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var allCategories: [Category]

    private var canSave: Bool { !item.title.trimmingCharacters(in: .whitespaces).isEmpty && item.amount > 0 }

    /// The categories to pick from: income ones for money in, the rest for money out.
    private var categories: [Category] { allCategories.live.filter { $0.isIncome == item.isIncome } }
    private var category: Category? { item.categoryKey.flatMap { key in allCategories.live.first { ($0.systemKey ?? $0.name) == key } } }

    private var iconSymbol: Binding<String?> { Binding(get: { item.iconSymbol }, set: { item.iconSymbol = $0 }) }
    private var iconTheme: Binding<Int> { Binding(get: { item.iconTheme ?? 0 }, set: { item.iconTheme = $0 == 0 ? nil : $0 }) }
    private var categoryKey: Binding<String?> { Binding(get: { item.categoryKey }, set: { item.categoryKey = $0 }) }
    private var notes: Binding<String> { Binding(get: { item.notes ?? "" }, set: { item.notes = $0.isEmpty ? nil : $0 }) }

    /// The icons that fit: the category's own list, or the general ones for a line with no category.
    private var fitting: [String] {
        guard let category else { return SymbolChoices.general.symbols }
        return category.systemKey.flatMap { SymbolChoices.symbols(forCategoryKey: $0) } ?? SymbolChoices.offer(for: category).symbols
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "Add a Line" : "Change Line").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section {
                        Picker("Kind", selection: $item.isIncome) {
                            Text("Money Out").tag(false)
                            Text("Money In").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: item.isIncome) { _, _ in
                            // A category of the other kind no longer fits.
                            item.categoryKey = nil
                            item.iconSymbol = nil
                        }
                        TextField("What is it", text: $item.title)
                        DatePicker("Date", selection: $item.date, displayedComponents: .date)
                        CurrencyField("Amount", amount: $item.amount)
                        Picker("Category", selection: categoryKey) {
                            Text("None").tag(String?.none)
                            Divider()
                            ForEach(categories) { category in
                                Label(category.name, systemImage: category.symbol).tag(Optional(category.systemKey ?? category.name))
                            }
                        }
                        .onChange(of: item.categoryKey) { _, _ in item.iconSymbol = nil }
                    }
                    Section("Notes") {
                        TextField("Anything to remember about it", text: notes, axis: .vertical)
                            .lineLimit(3...5)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                Divider()
                Form {
                    Section("Icon") {
                        ArtworkTile(symbol: item.iconSymbol ?? category?.symbol ?? item.symbol,
                                    theme: ArtworkTheme.resolved(item.iconTheme ?? 0, seed: ArtworkTheme.seed(item.title)))
                            .frame(width: 96, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .frame(maxWidth: .infinity)
                        IconPicker(symbol: iconSymbol, theme: iconTheme, category: nil,
                                   automaticSymbol: category?.symbol ?? item.symbol, automaticColor: nil,
                                   rainbowSeed: ArtworkTheme.seed(item.title), fitting: fitting)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(width: 400)
            }
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    if !isNew {
                        Button("Remove", role: .destructive) { remove(); dismiss() }
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(isNew ? "Add" : "Save") {
                        item.title = item.title.trimmingCharacters(in: .whitespaces)
                        save(item)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .background(Theme.background)
        .frame(width: 900, height: 560)
    }
}
