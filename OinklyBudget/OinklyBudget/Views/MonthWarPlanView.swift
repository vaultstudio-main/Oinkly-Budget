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

    @State private var draft: WarPlanItem?

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
                    HStack(alignment: .top, spacing: 30) {
                        figure("Extra This Month", extra, note: "money in less money out")
                        figure("Left at the End", ending, note: "starting with \(opening.formatted(.appCurrency))")
                        safeFigure(safe, hasLines: !list.isEmpty)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Button("Add a Line", systemImage: "plus.circle") { draft = newDraft() }
                                .buttonStyle(.borderedProminent)
                            Menu("Pull In…", systemImage: "square.and.arrow.down") {
                                Button("Paycheques and Income") { pull(incomeLines) }
                                Button("Bills and Repeating Expenses") { pull(billLines) }
                                Button("Budgets") { pull(budgetLines) }
                            }
                            .fixedSize()
                            .help("Copies lines from the Outlook into the plan, where you can change or remove them")
                        }
                    }
                    Text("This sheet starts blank. Add a line for anything you expect, or pull in the paycheques, bills and budgets the Outlook already knows, then change or remove whatever you like. What you start with, your buffer and the accounts counted are in Settings, top right. This is only a what-if sheet: it never changes your accounts, transactions, bills or budgets.")
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

    // MARK: Safe to move to savings

    /// What the plan says is safe to move to savings, and from which day: what it ends with less the buffer, from the earliest
    /// day all of it can come out and the balance still never drops under the buffer.
    private func safeFigure(_ pull: SafePull, hasLines: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SAFE TO MOVE TO SAVINGS").font(.caption).foregroundStyle(.secondary)
            if pull.spare > 0, let best = pull.best {
                Text(pull.spare, format: .appCurrency).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.green)
                Text("from \(best.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), buffer \(pull.buffer.formatted(.appCurrency))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(max(pull.spare, 0), format: .appCurrency).font(.system(size: 30, weight: .bold)).foregroundStyle(.secondary)
                Text(hasLines ? "nothing is safe to move yet" : "add lines to find it").font(.caption).foregroundStyle(.secondary)
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

    private var budgetLines: [WarPlanItem] {
        outlook.budgets.map { WarPlanItem(title: $0.category.name + " budget", date: monthEnd, amount: $0.counted, isIncome: false, origin: "budget") }
    }

    /// Adds the lines that aren't already in the plan with the same name, date and amount.
    private func pull(_ lines: [WarPlanItem]) {
        for line in lines where line.amount > 0 && !items.contains(where: { $0.title == line.title && $0.date == line.date && $0.amount == line.amount }) {
            items.append(line)
        }
    }

}

/// Adds or changes one line of the plan.
private struct PlanItemForm: View {
    @State var item: WarPlanItem
    let isNew: Bool
    let save: (WarPlanItem) -> Void
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
