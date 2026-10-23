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
        var items: [PlanItem] = []
    }

    @Query(sort: \Account.name) private var allAccounts: [Account]
    @State private var items: [PlanItem] = []
    @State private var typedStart: Decimal?
    @State private var startAccount: String?
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
        return ScrollView {
            VStack(spacing: 14) {
                ReportCard(title: "Monthly War Plan") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 30) {
                            figure("Extra This Month", extra, note: "money in less money out, from the lines below")
                            figure("Left at the End", ending, note: "the starting amount plus the extra")
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
                        Text("This sheet starts blank. Add a line for anything you expect, or pull in the paycheques, bills and budgets the Overview already knows, then change or remove whatever you like. Nothing here changes your accounts, bills or budgets.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                ReportCard(title: "Line by Line") {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        if list.isEmpty {
                            Text("No lines yet. Use Add a Line, or Pull In.").foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                        let balances = running(list)
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            line(item, left: balances[index].left, extra: balances[index].extra)
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
        }
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

    private var header: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 22)
            Text("Date").frame(width: 80, alignment: .leading)
            Text("Item").frame(maxWidth: .infinity, alignment: .leading)
            Text("Money In").frame(width: 95, alignment: .trailing)
            Text("Money Out").frame(width: 95, alignment: .trailing)
            Text("Left After").frame(width: 105, alignment: .trailing)
            Text("Extra So Far").frame(width: 105, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }

    private func line(_ item: PlanItem, left: Decimal, extra: Decimal) -> some View {
        Button { draft = item } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .foregroundStyle(item.isIncome ? Theme.green : Color.secondary)
                    .frame(width: 22)
                Text(item.date.formatted(.dateTime.weekday(.abbreviated).day())).frame(width: 80, alignment: .leading)
                Text(item.title).frame(maxWidth: .infinity, alignment: .leading)
                Text(item.isIncome ? item.amount.formatted(.appCurrency) : "").foregroundStyle(Theme.green).frame(width: 95, alignment: .trailing)
                Text(item.isIncome ? "" : item.amount.formatted(.appCurrency)).frame(width: 95, alignment: .trailing)
                Text(left, format: .appCurrency).fontWeight(.semibold)
                    .foregroundStyle(left < 0 ? Theme.red : Color.primary)
                    .frame(width: 105, alignment: .trailing)
                Text(extra, format: .appCurrency)
                    .foregroundStyle(extra < 0 ? Theme.red : Theme.green)
                    .frame(width: 105, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to change or remove this line")
        .contextMenu {
            Button("Change…", systemImage: "pencil") { draft = item }
            Button("Remove", systemImage: "trash", role: .destructive) { items.removeAll { $0.id == item.id } }
        }
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
            return
        }
        items = stored.items
        typedStart = stored.start == 0 ? nil : stored.start
        startAccount = stored.startAccount
    }

    private func save() {
        let stored = Stored(start: typedStart ?? 0, startAccount: startAccount, items: items)
        if stored.items.isEmpty && stored.start == 0 && stored.startAccount == nil {
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
