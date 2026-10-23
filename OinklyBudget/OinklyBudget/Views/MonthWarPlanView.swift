import SwiftUI

/// The Month Outlook's second tab: the month as a ledger, line by line in date order, with what is left after each line.
/// Paycheques, bills, repeating expenses and budgets come from the outlook; the person can add lines of their own to plan around.
struct MonthWarPlanView: View {
    let outlook: MonthOutlook

    /// A line the person added. Kept on this Mac, a month at a time.
    struct PlanItem: Codable, Identifiable, Equatable {
        var id = UUID()
        var title: String
        var date: Date
        /// Always positive; `isIncome` says which way it goes.
        var amount: Decimal
        var isIncome: Bool
    }

    private struct Stored: Codable {
        var start: Decimal = 0
        var items: [PlanItem] = []
    }

    private struct Row: Identifiable {
        let id: String
        let date: Date
        let title: String
        let note: String
        /// Plus for money in, minus for money out.
        let amount: Decimal
        let isMine: Bool
    }

    @State private var items: [PlanItem] = []
    @State private var start: Decimal?
    @State private var adding = false
    @State private var draft = PlanItem(title: "", date: .now, amount: 0, isIncome: false)

    private var storageKey: String { "warPlan." + OutlookSnapshots.key(for: outlook.month) }

    private func note(_ status: MonthOutlook.Status) -> String {
        switch status {
        case .expected: "Expected"
        case .overdue: "Overdue"
        case .paid: "Paid"
        case .over: "Paid, over"
        case .under: "Paid, under"
        case .received: "Received"
        }
    }

    private var rows: [Row] {
        var list: [Row] = []
        let calendar = Calendar.current
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: outlook.month) ?? outlook.month) ?? outlook.month
        for line in outlook.income {
            list.append(Row(id: line.id, date: line.date, title: line.title, note: note(line.status), amount: line.counted, isMine: false))
        }
        if outlook.otherIncome != 0 {
            list.append(Row(id: "other-income", date: outlook.month, title: "Other income so far", note: "Received", amount: outlook.otherIncome, isMine: false))
        }
        for line in outlook.bills {
            list.append(Row(id: line.id, date: line.date, title: line.title, note: note(line.status), amount: -line.counted, isMine: false))
        }
        for budget in outlook.budgets {
            // Bills and repeating expenses inside a budget have their own dated lines; the budget's line is the rest of it.
            for line in budget.inside {
                list.append(Row(id: line.id, date: line.date, title: line.title + " (\(budget.category.name))", note: note(line.status), amount: -line.counted, isMine: false))
            }
            let rest = budget.counted - budget.inside.reduce(0) { $0 + $1.counted }
            if rest > 0 {
                list.append(Row(id: "budget-" + budget.category.name, date: monthEnd, title: budget.category.name + " budget",
                                note: budget.over > 0 ? "Over by \(budget.over.formatted(.appCurrency))" : "\(budget.remaining.formatted(.appCurrency)) left to spend",
                                amount: -rest, isMine: false))
            }
        }
        if outlook.otherSpending > 0 {
            list.append(Row(id: "other-spending", date: monthEnd, title: "Everything else", note: "Spent with no bill or budget", amount: -outlook.otherSpending, isMine: false))
        }
        for item in items {
            list.append(Row(id: item.id.uuidString, date: item.date, title: item.title, note: "Mine", amount: item.isIncome ? item.amount : -item.amount, isMine: true))
        }
        return list.sorted { ($0.date, $0.amount < 0 ? 1 : 0, $0.title) < ($1.date, $1.amount < 0 ? 1 : 0, $1.title) }
    }

    var body: some View {
        let all = rows
        let opening = start ?? 0
        let ending = all.reduce(opening) { $0 + $1.amount }
        return ScrollView {
            VStack(spacing: 14) {
                ReportCard(title: "Monthly War Plan") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ending, format: .appCurrency)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(ending < 0 ? Theme.red : Theme.green)
                            Text("left at the end of the month").foregroundStyle(.secondary)
                            Spacer()
                            Button("Add a Line", systemImage: "plus.circle") {
                                draft = PlanItem(title: "", date: Calendar.current.isDate(.now, equalTo: outlook.month, toGranularity: .month) ? .now : outlook.month,
                                                 amount: 0, isIncome: false)
                                adding = true
                            }
                            .popover(isPresented: $adding, arrowEdge: .bottom) { addForm }
                        }
                        HStack {
                            Text("Starting with")
                            CurrencyField("Starting amount", value: $start)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 130)
                            Text("Optional: money already in the accounts you are planning with.").font(.callout).foregroundStyle(.secondary)
                        }
                        Text("Every line of the month in date order, with what is left after it. Budgets count at their limit, or what has been spent if that is more, on the last day of the month. Add lines of your own to plan around, and they are kept for this month.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                ReportCard(title: "Line by Line") {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        if all.isEmpty {
                            Text("Nothing is planned for this month yet.").foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                        let balances = runningBalances(all, from: opening)
                        ForEach(Array(all.enumerated()), id: \.element.id) { index, row in
                            line(row, balance: balances[index])
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear(perform: load)
        .onChange(of: outlook.month) { _, _ in load() }
        .onChange(of: items) { _, _ in save() }
        .onChange(of: start) { _, _ in save() }
    }

    private func runningBalances(_ list: [Row], from opening: Decimal) -> [Decimal] {
        var total = opening
        return list.map { total += $0.amount; return total }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Date").frame(width: 80, alignment: .leading)
            Text("Item").frame(maxWidth: .infinity, alignment: .leading)
            Text("Money In").frame(width: 100, alignment: .trailing)
            Text("Money Out").frame(width: 100, alignment: .trailing)
            Text("Left After").frame(width: 110, alignment: .trailing)
            Color.clear.frame(width: 22)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }

    private func line(_ row: Row, balance: Decimal) -> some View {
        HStack(spacing: 12) {
            Text(row.date.formatted(.dateTime.weekday(.abbreviated).day())).frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                Text(row.note).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.amount > 0 ? row.amount.formatted(.appCurrency) : "").foregroundStyle(Theme.green).frame(width: 100, alignment: .trailing)
            Text(row.amount < 0 ? (-row.amount).formatted(.appCurrency) : "").frame(width: 100, alignment: .trailing)
            Text(balance, format: .appCurrency).fontWeight(.semibold)
                .foregroundStyle(balance < 0 ? Theme.red : Color.primary)
                .frame(width: 110, alignment: .trailing)
            if row.isMine {
                Button {
                    items.removeAll { $0.id.uuidString == row.id }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Remove this line")
                .accessibilityLabel("Remove \(row.title)")
                .frame(width: 22)
            } else {
                Color.clear.frame(width: 22)
            }
        }
        .padding(.vertical, 6)
        .background(row.isMine ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a Line").font(.headline)
            Picker("Kind", selection: $draft.isIncome) {
                Text("Money Out").tag(false)
                Text("Money In").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("What is it", text: $draft.title)
            DatePicker("Date", selection: $draft.date, displayedComponents: .date)
            CurrencyField("Amount", amount: $draft.amount)
            HStack {
                Spacer()
                Button("Cancel") { adding = false }
                Button("Add") {
                    draft.title = draft.title.trimmingCharacters(in: .whitespaces)
                    items.append(draft)
                    adding = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.amount <= 0)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey), let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            items = []
            start = nil
            return
        }
        items = stored.items
        start = stored.start == 0 ? nil : stored.start
    }

    private func save() {
        let stored = Stored(start: start ?? 0, items: items)
        if stored.items.isEmpty && stored.start == 0 {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
