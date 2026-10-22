import SwiftUI
import SwiftData

/// What is left to save this month: paycheques and other income, less bills and repeating expenses, less each budget
/// (at its limit, or what has been spent if that is more). Bills count at what really came out once a payment is linked.
struct MonthOutlookView: View {
    @State private var month = MonthFilter.start(of: .now)
    @State private var choosingAccounts = false
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @AppStorage(MonthOutlook.excludedKey) private var excludedStored = ""

    /// Accounts the outlook can count: everything except investments, which hold no bills or budgets.
    private var countable: [Account] { allAccounts.live.filter { !$0.supportsHoldings } }
    private var leftOut: Int { countable.filter { MonthOutlook.excluded(from: excludedStored).contains(MonthOutlook.accountKey($0)) }.count }

    private var range: ClosedRange<Date> {
        let current = MonthFilter.start(of: .now)
        let calendar = Calendar.current
        return (calendar.date(byAdding: .month, value: -24, to: current) ?? current)...(calendar.date(byAdding: .month, value: 12, to: current) ?? current)
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeader("Month Outlook") {
                HStack {
                    MonthSelector(month: $month, range: range)
                    Spacer()
                    Button {
                        choosingAccounts = true
                    } label: {
                        Label(leftOut == 0 ? "All Accounts" : "\(countable.count - leftOut) of \(countable.count) Accounts", systemImage: "slider.horizontal.3")
                    }
                    .help("Choose which accounts are counted in the Month Outlook")
                    .popover(isPresented: $choosingAccounts, arrowEdge: .bottom) { accountChooser }
                }
            }
            OutlookBody(month: month, excluded: MonthOutlook.excluded(from: excludedStored))
        }
        .background(Theme.background)
    }
}

extension MonthOutlookView {
    /// A tick beside each account: ticked accounts are counted.
    fileprivate var accountChooser: some View {
        let excluded = MonthOutlook.excluded(from: excludedStored)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Accounts to count").font(.headline)
            Text("Only ticked accounts count toward the outlook: their income, spending and repeating transactions. A bill is left out when the payment linked to it came from an account that is unticked.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(countable) { account in
                Toggle(isOn: Binding(
                    get: { !MonthOutlook.excluded(from: excludedStored).contains(MonthOutlook.accountKey(account)) },
                    set: { counted in
                        var keys = MonthOutlook.excluded(from: excludedStored)
                        if counted { keys.remove(MonthOutlook.accountKey(account)) } else { keys.insert(MonthOutlook.accountKey(account)) }
                        excludedStored = MonthOutlook.stored(keys)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                        Text(account.typeTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("All") { excludedStored = "" }.disabled(excluded.isEmpty)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct OutlookBody: View {
    let month: Date
    let excluded: Set<String>
    @Query private var transactions: [Transaction]
    @Query private var allBills: [Bill]
    @Query private var allRules: [RecurringTransaction]
    @Query private var allCategories: [Category]
    @Query private var snapshots: [OutlookSnapshot]

    /// The figures kept when this month closed, for a month that is over.
    private var snapshot: OutlookSnapshot? {
        isPast ? snapshots.live.first { $0.monthKey == OutlookSnapshots.key(for: month) } : nil
    }

    /// The numbers the top of the page shows: the saved ones for a closed month, otherwise today's.
    private struct Totals {
        let income, bills, budgets, other, left, billDifference, overspend: Decimal
    }

    init(month: Date, excluded: Set<String>) {
        self.month = month
        self.excluded = excluded
        let end = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
        _transactions = Query(filter: #Predicate<Transaction> { $0.date >= month && $0.date < end })
    }

    private var isFuture: Bool { month > MonthFilter.start(of: .now) }
    private var isPast: Bool { month < MonthFilter.start(of: .now) }

    var body: some View {
        let outlook = MonthOutlook.build(month: month, bills: allBills.live, rules: allRules.live, categories: allCategories.live,
                                         monthTransactions: transactions, excludedAccounts: excluded)
        let kept = snapshot
        let totals = kept.map { Totals(income: $0.incomeTotal, bills: $0.billsTotal, budgets: $0.budgetsTotal, other: $0.otherSpending, left: $0.leftToSave,
                                       billDifference: $0.billDifference, overspend: $0.budgetOverspend) }
            ?? Totals(income: outlook.incomeTotal, bills: outlook.billsTotal, budgets: outlook.budgetsTotal, other: outlook.otherSpending,
                      left: outlook.leftToSave, billDifference: outlook.billDifference, overspend: outlook.budgetOverspend)
        return ScrollView {
            VStack(spacing: 14) {
                summaryCard(outlook, totals: totals, kept: kept)
                StatGrid {
                    StatTile(title: "Money In") { Text(totals.income, format: .appCurrency).foregroundStyle(Theme.green) }
                        note: { Text("\(outlook.income.count) paycheque\(outlook.income.count == 1 ? "" : "s") and other income") }
                    StatTile(title: "Bills & Repeating") { Text(totals.bills, format: .appCurrency) }
                        note: { Text("\(outlook.bills.count) not inside a budget") }
                    StatTile(title: "Budgets") { Text(totals.budgets, format: .appCurrency) }
                        note: { Text(totals.overspend > 0 ? "\(totals.overspend.formatted(.appCurrency)) over" : "\(outlook.budgets.count) budget\(outlook.budgets.count == 1 ? "" : "s"), none over") }
                    StatTile(title: "Everything Else") { Text(totals.other, format: .appCurrency) }
                        note: { Text("spent with no bill or budget") }
                }
                incomeCard(outlook)
                billsCard(outlook)
                budgetsCard(outlook)
            }
            .padding(16)
        }
        .statusBarText("Month Outlook · \(month.formatted(.dateTime.month(.wide).year())) · \(outlook.leftToSave.formatted(.appCurrency)) left to save")
    }

    // MARK: Cards

    private func summaryCard(_ outlook: MonthOutlook, totals: Totals, kept: OutlookSnapshot?) -> some View {
        let left = totals.left
        return ReportCard(title: "Left to Save") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(left, format: .appCurrency)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(left < 0 ? Theme.red : Theme.green)
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline).foregroundStyle(.secondary)
                }
                Text(sentence(income: totals.income, out: totals.income - totals.left)).font(.callout).foregroundStyle(.secondary)
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
        }
    }

    private func sentence(income: Decimal, out: Decimal) -> String {
        let basis = "Income of \(income.formatted(.appCurrency)), less \(out.formatted(.appCurrency)) for bills, budgets and other spending."
        if isFuture { return basis + " This month hasn't started, so every figure is what is expected." }
        if isPast { return basis + " This month is over; what was paid counts at what came out." }
        return basis + " Paid bills count at what came out when their payment is linked; the rest count at what is expected."
    }

    private func incomeCard(_ outlook: MonthOutlook) -> some View {
        ReportCard(title: "Money In") {
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
    }
}
