import SwiftUI
import SwiftData
import Charts

/// The Monthly Outlook's fourth tab: a calculator for saving up. Every savings account is grown month by month with its own interest rate and
/// deposits; put in extra money each month or a lump sum now, pick where it goes (or point the laser at one account), and see when each account
/// reaches its target and when everything reaches your overall goal. It only works out what would happen: it never changes an account.
struct SavingsWarPlanView: View {
    @Query private var allAccounts: [Account]
    @AppStorage("savingsWarPlanExtra") private var extraText = ""
    @AppStorage("savingsWarPlanLump") private var lumpText = ""
    @AppStorage("savingsWarPlanGoal") private var goalText = ""
    @AppStorage("savingsWarPlanStrategy") private var strategyRaw = SavingsWarPlan.Strategy.even.rawValue
    @AppStorage("savingsWarPlanTarget") private var targetID = ""
    /// Each account's own rate, monthly deposit and target, kept together as one small piece of text: `[account: Row]`.
    @AppStorage("savingsWarPlanRows") private var rowsText = ""

    private struct Row: Codable, Equatable {
        var rate: Double = 0
        var deposit: Double = 0
        var target: Double?
    }

    private static let quickAmounts: [Double] = [50, 100, 250, 500, 1000]
    private static let savingsTypes: [AccountType] = [.savings, .moneyMarket, .certificateOfDeposit, .healthSavings]

    private var rows: [String: Row] {
        get { (try? JSONDecoder().decode([String: Row].self, from: Data(rowsText.utf8))) ?? [:] }
        nonmutating set { rowsText = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    }

    private func binding(_ text: Binding<String>) -> Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(text.wrappedValue) }, set: { text.wrappedValue = OutlookSettings.text($0) })
    }
    private var extra: Double { max((OutlookSettings.decimal(extraText) ?? 0).doubleValue, 0) }
    private var lump: Double { max((OutlookSettings.decimal(lumpText) ?? 0).doubleValue, 0) }
    private var goal: Double? { (OutlookSettings.decimal(goalText)?.doubleValue).flatMap { $0 > 0 ? $0 : nil } }
    private var strategy: SavingsWarPlan.Strategy { SavingsWarPlan.Strategy(rawValue: strategyRaw) ?? .even }
    private var hasExtra: Bool { extra > 0 || lump > 0 }

    /// Every savings account that is still open, with what the plan knows about it. Its target is the one typed here, or else that of the open
    /// saving goal that follows it.
    private var accounts: [SavingsWarPlan.Account] {
        let saved = rows
        return allAccounts.live.filter { Self.savingsTypes.contains($0.type) && !$0.isClosed }
            .sorted { $0.balance > $1.balance }
            .map { account in
                let id = String(describing: account.persistentModelID)
                let row = saved[id] ?? Row()
                let goalTarget = account.goals.first { $0.isLive && $0.kind == .save && $0.completedAt == nil && $0.targetAmount > 0 }?.targetAmount.doubleValue
                return SavingsWarPlan.Account(id: id, name: account.name, kind: account.typeTitle, symbol: account.type.symbol,
                                              balance: max(account.balance.doubleValue, 0), rate: row.rate, deposit: row.deposit, target: row.target ?? goalTarget)
            }
    }

    private func laserTarget(in accounts: [SavingsWarPlan.Account]) -> SavingsWarPlan.Account? {
        accounts.first { $0.id == targetID } ?? accounts.first { $0.hasTarget && ($0.target ?? 0) > $0.balance } ?? accounts.first
    }

    private func date(afterMonths months: Int) -> Date { Calendar.current.date(byAdding: .month, value: months, to: .now) ?? .now }

    var body: some View {
        let accounts = self.accounts
        let target = strategy == .laser ? laserTarget(in: accounts)?.id : nil
        let base = SavingsWarPlan.simulate(accounts, extra: 0, goal: goal, strategy: strategy, laserTarget: target)
        let plan = SavingsWarPlan.simulate(accounts, extra: extra, lump: lump, goal: goal, strategy: strategy, laserTarget: target)
        ScrollView {
            VStack(spacing: 14) {
                if accounts.isEmpty {
                    ReportPanel(title: "Savings War Plan", summary: "See how long it takes to save up, and how much sooner with extra money.") {
                        ReportEmpty(message: "You have no savings accounts yet. Add a Savings, Money Market, CD or Health Savings account in Manage Accounts.", height: 160,
                                    title: "No savings accounts", clean: true).frame(height: 160)
                    }
                } else {
                    controls(accounts: accounts)
                    tiles(accounts: accounts, base: base, plan: plan)
                    chart(base: base, plan: plan)
                    table(accounts: accounts, base: base, plan: plan, target: target)
                    Text("This is a what-if. It grows each account at the rate you give it, adds your monthly deposit and any extra, and compounds the interest each month. It assumes no withdrawals and that rates stay the same. It never changes any account.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    // MARK: The calculator

    private func controls(accounts: [SavingsWarPlan.Account]) -> some View {
        ReportPanel(title: "Save Up Faster", summary: "Add extra money and a goal, and choose where the extra goes first. Everything below follows as you type.") {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) { amountFields; strategyPicker(accounts: accounts) }
                    VStack(alignment: .leading, spacing: 14) { amountFields; strategyPicker(accounts: accounts) }
                }
                HStack(spacing: 8) {
                    Text("Quick amounts").font(.caption).foregroundStyle(.secondary)
                    ForEach(Self.quickAmounts, id: \.self) { amount in
                        Button("+\(ReportFormat.money(amount))") { extraText = OutlookSettings.text(Decimal(amount)) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Button("Clear") { extraText = ""; lumpText = ""; goalText = "" }
                        .buttonStyle(.borderless).controlSize(.small).disabled(extra == 0 && lump == 0 && goal == nil)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var amountFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Extra each month", text: $extraText)
            field("One-time deposit now", text: $lumpText)
            field("Total goal (optional)", text: $goalText)
        }
        .help("The extra each month is saved on top of each account's own deposit. The one-time deposit is saved once, today. The total goal is how much you want saved across all of these accounts, and the plan runs until you reach it.")
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).frame(width: 160, alignment: .leading)
            CurrencyField(title, value: binding(text)).labelsHidden().frame(width: 140).multilineTextAlignment(.trailing)
        }
    }

    private func strategyPicker(accounts: [SavingsWarPlan.Account]) -> some View {
        let strategies = Picker("Where the extra goes first", selection: $strategyRaw) {
            ForEach(SavingsWarPlan.Strategy.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560)
        // Laser Focus Annihilation needs a target account, so its menu sits right beside the buttons.
        let target = HStack(spacing: 6) {
            Image(systemName: "scope").foregroundStyle(Theme.red)
            Text("Target").font(.callout)
            Picker("Target", selection: Binding(get: { laserTarget(in: accounts)?.id ?? "" }, set: { targetID = $0 })) {
                ForEach(accounts) { Text("\($0.name) · \(ReportFormat.money($0.balance))").tag($0.id) }
            }
            .labelsHidden().frame(width: 260)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Where the extra goes first").font(.callout)
            if strategy == .laser {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { strategies; target }
                    VStack(alignment: .leading, spacing: 8) { strategies; target }
                }
            } else {
                strategies
            }
            Text(strategy.blurb).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Results

    private func tiles(accounts: [SavingsWarPlan.Account], base: SavingsWarPlan.Result, plan: SavingsWarPlan.Result) -> some View {
        let now = accounts.reduce(0) { $0 + $1.balance }
        let hasStop = goal != nil || accounts.contains(where: \.hasTarget)
        let sooner = base.finishes && plan.finishes ? max(base.months - plan.months, 0) : nil
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            StatTile(title: "Saved now") { Text(ReportFormat.money(now)) } note: { Text("across \(accounts.count) account\(accounts.count == 1 ? "" : "s")") }
            StatTile(title: hasStop ? "All goals reached" : "In five years") {
                if hasStop {
                    if plan.finishes { Text(ReportFormat.month(date(afterMonths: plan.months))).foregroundStyle(Theme.green) } else { Text("Not in 50 years").foregroundStyle(.secondary) }
                } else {
                    Text(ReportFormat.money(plan.totals.last ?? now)).foregroundStyle(Theme.green)
                }
            } note: {
                if !hasStop { Text("set a target on an account, or a total goal, to see when") }
                else if hasExtra, base.finishes { Text("instead of \(ReportFormat.month(date(afterMonths: base.months))) without the extra") }
                else if !base.finishes { Text("not without more saved each month") }
                else { Text("on your own deposits") }
            }
            StatTile(title: "Sooner by") {
                if let sooner, hasExtra { Text(years(sooner)).foregroundStyle(Theme.green) } else { Text("—").foregroundStyle(.secondary) }
            } note: { Text(hasExtra ? "than saving only what you save now" : "add some extra money above") }
            StatTile(title: "Interest earned") { Text(ReportFormat.money(plan.interest)).foregroundStyle(Theme.green) } note: {
                Text(hasExtra ? "\(ReportFormat.money(max(plan.interest - base.interest, 0))) more than without the extra" : "over the whole plan")
            }
        }
    }

    private func years(_ months: Int) -> String {
        let y = months / 12, m = months % 12
        switch (y, m) {
        case (0, _): return "\(m) month\(m == 1 ? "" : "s")"
        case (_, 0): return "\(y) year\(y == 1 ? "" : "s")"
        default: return "\(y) yr \(m) mo"
        }
    }

    private func chart(base: SavingsWarPlan.Result, plan: SavingsWarPlan.Result) -> some View {
        // Up to ten years, one point a month.
        func points(_ totals: [Double]) -> [(Int, Double)] { Array(totals.prefix(121).enumerated()).map { ($0.offset, $0.element) } }
        return ReportPanel(title: "Savings Over Time", summary: "Everything saved in total, month by month, on your own deposits and with the extra.") {
            Chart {
                ForEach(points(base.totals), id: \.0) { month, total in
                    LineMark(x: .value("Date", date(afterMonths: month)), y: .value("Saved", total), series: .value("Plan", "Your own deposits"))
                        .foregroundStyle(by: .value("Plan", "Your own deposits")).interpolationMethod(.monotone)
                }
                if hasExtra {
                    ForEach(points(plan.totals), id: \.0) { month, total in
                        LineMark(x: .value("Date", date(afterMonths: month)), y: .value("Saved", total), series: .value("Plan", "With the extra"))
                            .foregroundStyle(by: .value("Plan", "With the extra")).interpolationMethod(.monotone)
                    }
                }
                if let goal {
                    RuleMark(y: .value("Goal", goal)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(Color.orange)
                        .annotation(position: .top, alignment: .leading) { Text("Goal").font(.caption2).foregroundStyle(.orange) }
                }
            }
            .chartForegroundStyleScale(["Your own deposits": Color.secondary, "With the extra": Theme.green])
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
            .frame(height: 220)
        }
    }

    /// Each savings account, with the three things you can set on it and when it reaches its target.
    private func table(accounts: [SavingsWarPlan.Account], base: SavingsWarPlan.Result, plan: SavingsWarPlan.Result, target: String?) -> some View {
        func when(_ result: SavingsWarPlan.AccountResult?, hasTarget: Bool) -> String {
            guard hasTarget else { return "No target" }
            guard let month = result?.reachedMonth else { return "Not in 50 years" }
            return month == 0 ? "Reached" : ReportFormat.month(date(afterMonths: month))
        }
        return ReportPanel(title: "Account by Account", summary: "Set each account's yearly rate, what you add each month and the balance it should reach. A target from a saving goal that follows the account is filled in for you.") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("ACCOUNT")
                    Text("BALANCE").gridColumnAlignment(.trailing)
                    Text("RATE (APY)").gridColumnAlignment(.trailing)
                    Text("ADDED EACH MONTH").gridColumnAlignment(.trailing)
                    Text("TARGET").gridColumnAlignment(.trailing)
                    Text("REACHED NOW").gridColumnAlignment(.trailing)
                    Text("REACHED WITH EXTRA").gridColumnAlignment(.trailing)
                    Text("AT THE END").gridColumnAlignment(.trailing)
                }
                .font(.caption2).foregroundStyle(.secondary)
                Divider().gridCellColumns(8)
                ForEach(accounts) { account in
                    let now = base.byAccount[account.id], with = plan.byAccount[account.id]
                    GridRow {
                        HStack(spacing: 8) {
                            Image(systemName: account.id == target ? "scope" : account.symbol).foregroundStyle(Theme.green).frame(width: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(account.name).fontWeight(.medium).lineLimit(1)
                                Text(account.kind).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Text(ReportFormat.money(account.balance))
                        HStack(spacing: 2) {
                            TextField("Rate", value: Binding(get: { rows[account.id]?.rate ?? 0 }, set: { new in update(account.id) { $0.rate = max(new, 0) } }),
                                      format: .number.precision(.fractionLength(0...3)))
                                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 60)
                            Text("%").foregroundStyle(.secondary)
                        }
                        CurrencyField("Added each month", value: Binding(get: { (rows[account.id]?.deposit).flatMap { $0 > 0 ? Decimal($0) : nil } },
                                                                          set: { new in update(account.id) { $0.deposit = max((new ?? 0).doubleValue, 0) } }))
                            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 110)
                        CurrencyField("Target", value: Binding(get: { account.target.flatMap { $0 > 0 ? Decimal($0) : nil } },
                                                                set: { new in update(account.id) { $0.target = (new?.doubleValue).flatMap { $0 > 0 ? $0 : nil } } }))
                            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 110)
                        Text(when(now, hasTarget: account.hasTarget)).foregroundStyle(.secondary)
                        Text(when(with, hasTarget: account.hasTarget)).foregroundStyle(hasExtra && account.hasTarget ? Theme.green : Color.primary)
                            .fontWeight(hasExtra && account.hasTarget ? .semibold : .regular)
                        Text(ReportFormat.money(with?.balanceAtEnd ?? account.balance))
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func update(_ id: String, _ change: (inout Row) -> Void) {
        var all = rows
        var row = all[id] ?? Row()
        change(&row)
        all[id] = row
        rows = all
    }
}
