import SwiftUI
import SwiftData
import Charts

/// The Planning War Room's third tab: a calculator for paying debt down faster. Put in extra money each month, or a lump sum now, pick which
/// debt gets it first, and see when every loan and card would be paid off and how much interest it would save, against what happens on your
/// current payments. It only works out what would happen: it never changes an account, a payment or a bill.
struct DebtWarPlanView: View {
    @Query private var allAccounts: [Account]
    @AppStorage("debtWarPlanExtra") private var extraText = ""
    @AppStorage("debtWarPlanLump") private var lumpText = ""
    @AppStorage("debtWarPlanStrategy") private var strategyRaw = DebtWarPlan.Strategy.avalanche.rawValue
    /// The debt Laser Focus Annihilation goes after. When it is not one of the debts any more (paid off, deleted), the smallest takes its place.
    @AppStorage("debtWarPlanTarget") private var targetID = ""


    private var extraBinding: Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(extraText) }, set: { extraText = OutlookSettings.text($0) })
    }
    private var lumpBinding: Binding<Decimal?> {
        Binding(get: { OutlookSettings.decimal(lumpText) }, set: { lumpText = OutlookSettings.text($0) })
    }
    private var strategy: DebtWarPlan.Strategy { DebtWarPlan.Strategy(rawValue: strategyRaw) ?? .avalanche }
    private var extra: Double { max((extraBinding.wrappedValue ?? 0).doubleValue, 0) }
    private var lump: Double { max((lumpBinding.wrappedValue ?? 0).doubleValue, 0) }

    /// Every loan and card that still owes something.
    private var debts: [DebtWarPlan.Debt] { WarPlanSummary.debts(from: allAccounts.live) }

    /// The debt the laser is pointed at: the one picked, or the smallest when none was picked or it is gone.
    private func targetDebt(in debts: [DebtWarPlan.Debt]) -> DebtWarPlan.Debt? {
        debts.first { $0.id == targetID } ?? debts.min { $0.owed < $1.owed }
    }

    private func date(afterMonths months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: .now) ?? .now
    }

    private func years(_ months: Int) -> String {
        let y = months / 12, m = months % 12
        switch (y, m) {
        case (0, _): return "\(m) month\(m == 1 ? "" : "s")"
        case (_, 0): return "\(y) year\(y == 1 ? "" : "s")"
        default: return "\(y) yr \(m) mo"
        }
    }

    var body: some View {
        let debts = self.debts
        let target = strategy == .laser ? targetDebt(in: debts)?.id : nil
        let base = DebtWarPlan.simulate(debts, extra: 0, strategy: strategy, target: target)
        let plan = DebtWarPlan.simulate(debts, extra: extra, lump: lump, strategy: strategy, target: target)
        ScrollView {
            VStack(spacing: 14) {
                if debts.isEmpty {
                    ReportPanel(title: "Debt War Plan", summary: "Put extra money on your debts and see how much sooner they are paid off.") {
                        ReportEmpty(message: "You have no loans or credit cards with a balance, so there is nothing to pay down. Add one in Manage Accounts.", height: 160,
                                    title: "No debt to pay off", clean: true).frame(height: 160)
                    }
                } else {
                    controls(debts: debts, target: target)
                    tiles(debts: debts, base: base, plan: plan)
                    chart(base: base, plan: plan)
                    table(debts: debts, base: base, plan: plan, target: target)
                    notes(debts: debts)
                }
            }
            .padding(16)
        }
    }

    // MARK: The calculator

    private func controls(debts: [DebtWarPlan.Debt], target: String?) -> some View {
        ReportPanel(title: "Pay It Down Faster", summary: "Add extra money and choose where it goes first. Everything below follows as you type.") {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) { amountFields; strategyPicker(debts: debts) }
                    VStack(alignment: .leading, spacing: 14) { amountFields; strategyPicker(debts: debts) }
                }
                Divider()
                DebtPayoffScenarios(debts: debts, strategy: strategy, target: target, lump: lump) { extraBinding.wrappedValue = Decimal($0) }
                Divider()
                Text("This is a what-if. It assumes you keep paying what you pay now, add no new charges, and that interest is added each month at the account's rate. When a debt is paid off, its payment goes on to the next one. It never changes any account.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var amountFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Extra each month").frame(width: 150, alignment: .leading)
                CurrencyField("Extra each month", value: extraBinding).labelsHidden().frame(width: 140).multilineTextAlignment(.trailing)
            }
            HStack {
                Text("One-time extra now").frame(width: 150, alignment: .leading)
                CurrencyField("One-time extra now", value: lumpBinding).labelsHidden().frame(width: 140).multilineTextAlignment(.trailing)
            }
        }
        .help("The extra each month is paid on top of your payments every month. The one-time amount is paid once, today, such as a bonus or a tax refund.")
    }

    private func strategyPicker(debts: [DebtWarPlan.Debt]) -> some View {
        let strategies = Picker("Where the extra goes first", selection: $strategyRaw) {
            ForEach(DebtWarPlan.Strategy.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 620)
        // Laser Focus Annihilation needs a target, so its menu sits right beside the buttons. Debts added later appear in it by themselves,
        // since the list is the accounts.
        let target = HStack(spacing: 6) {
            Image(systemName: "scope").foregroundStyle(Theme.red)
            Text("Target").font(.callout)
            Picker("Target", selection: Binding(get: { targetDebt(in: debts)?.id ?? "" }, set: { targetID = $0 })) {
                ForEach(debts) { Text("\($0.name) · \(ReportFormat.money($0.owed))").tag($0.id) }
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

    /// The headline figures, a row of tiles that wraps to fit the window.
    private func tiles(debts: [DebtWarPlan.Debt], base: DebtWarPlan.Result, plan: DebtWarPlan.Result) -> some View {
        let total = debts.reduce(0) { $0 + $1.owed }
        let hasExtra = extra > 0 || lump > 0
        let sooner = base.finishes && plan.finishes ? max(base.months - plan.months, 0) : nil
        let saved = max(base.interest - plan.interest, 0)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            StatTile(title: "You owe") {
                Text(ReportFormat.money(total))
            } note: {
                Text("across \(debts.count) debt\(debts.count == 1 ? "" : "s")")
            }
            StatTile(title: "Debt-free") {
                if plan.finishes { Text(ReportFormat.month(date(afterMonths: plan.months))).foregroundStyle(Theme.green) } else { Text("Not in 50 years").foregroundStyle(.secondary) }
            } note: {
                if hasExtra, base.finishes { Text("instead of \(ReportFormat.month(date(afterMonths: base.months))) on your current payments") }
                else if !base.finishes { Text("your current payments never clear it") }
                else { Text("on your current payments") }
            }
            StatTile(title: "Sooner by") {
                if let sooner, hasExtra { Text(years(sooner)).foregroundStyle(Theme.green) } else { Text("—").foregroundStyle(.secondary) }
            } note: {
                Text(hasExtra ? "than paying only what you pay now" : "add some extra money above")
            }
            StatTile(title: "Interest saved") {
                if hasExtra, plan.finishes, base.finishes { Text(ReportFormat.money(saved)).foregroundStyle(Theme.green) } else { Text("—").foregroundStyle(.secondary) }
            } note: {
                if plan.finishes { Text("\(ReportFormat.money(plan.interest)) interest in all, against \(base.finishes ? ReportFormat.money(base.interest) : "more than you can count")") }
                else { Text("the payments don't cover the interest") }
            }
        }
    }

    private func chart(base: DebtWarPlan.Result, plan: DebtWarPlan.Result) -> some View {
        // The balance over time, up to 30 years, one point a month, so a debt that never clears doesn't fill the chart.
        func points(_ balances: [Double]) -> [(Int, Double)] { Array(balances.prefix(361).enumerated()).map { ($0.offset, $0.element) } }
        let hasExtra = extra > 0 || lump > 0
        return ReportPanel(title: "Balance Over Time", summary: "What you owe in total, month by month, on your current payments and with the extra.") {
            Chart {
                ForEach(points(base.balances), id: \.0) { month, owed in
                    LineMark(x: .value("Date", date(afterMonths: month)), y: .value("Owed", owed), series: .value("Plan", "Current payments"))
                        .foregroundStyle(by: .value("Plan", "Current payments"))
                        .interpolationMethod(.monotone)
                }
                if hasExtra {
                    ForEach(points(plan.balances), id: \.0) { month, owed in
                        LineMark(x: .value("Date", date(afterMonths: month)), y: .value("Owed", owed), series: .value("Plan", "With the extra"))
                            .foregroundStyle(by: .value("Plan", "With the extra"))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartForegroundStyleScale(["Current payments": Color.secondary, "With the extra": Theme.green])
            .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
            .frame(height: 220)
        }
    }

    /// Each debt: what it is, and when it is paid off now and with the extra.
    private func table(debts: [DebtWarPlan.Debt], base: DebtWarPlan.Result, plan: DebtWarPlan.Result, target: String?) -> some View {
        let hasExtra = extra > 0 || lump > 0
        let order = debts.sorted { (plan.byDebt[$0.id]?.payoffMonth ?? .max) < (plan.byDebt[$1.id]?.payoffMonth ?? .max) }
        func when(_ result: DebtWarPlan.DebtResult?) -> String {
            guard let month = result?.payoffMonth else { return "Never" }
            return month == 0 ? "Paid off" : ReportFormat.month(date(afterMonths: month))
        }
        return ReportPanel(title: "Debt by Debt", summary: "In the order they are paid off with the extra.") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("DEBT")
                    Text("OWED").gridColumnAlignment(.trailing)
                    Text("RATE").gridColumnAlignment(.trailing)
                    Text("PAYMENT").gridColumnAlignment(.trailing)
                    Text("PAID OFF NOW").gridColumnAlignment(.trailing)
                    Text("PAID OFF WITH EXTRA").gridColumnAlignment(.trailing)
                    Text("INTEREST SAVED").gridColumnAlignment(.trailing)
                }
                .font(.caption2).foregroundStyle(.secondary)
                Divider().gridCellColumns(7)
                ForEach(order) { debt in
                    let now = base.byDebt[debt.id], with = plan.byDebt[debt.id]
                    GridRow {
                        HStack(spacing: 8) {
                            Image(systemName: debt.id == target ? "scope" : debt.symbol).foregroundStyle(Theme.red).frame(width: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(debt.name).fontWeight(.medium).lineLimit(1)
                                Text(debt.kind).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Text(ReportFormat.money(debt.owed))
                        Text(debt.rate > 0 ? ReportFormat.percent(debt.rate, digits: 2) : "0%")
                        Text(debt.payment > 0 ? ReportFormat.money(debt.payment) : "None set").foregroundStyle(debt.payment > 0 ? Color.primary : .orange)
                        Text(when(now)).foregroundStyle(.secondary)
                        Text(when(with)).foregroundStyle(hasExtra ? Theme.green : Color.primary).fontWeight(hasExtra ? .semibold : .regular)
                        Text(hasExtra && now?.payoffMonth != nil && with?.payoffMonth != nil ? ReportFormat.money(max((now?.interest ?? 0) - (with?.interest ?? 0), 0)) : "—")
                            .foregroundStyle(hasExtra ? Theme.green : .secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private func notes(debts: [DebtWarPlan.Debt]) -> some View {
        let missing = debts.filter { $0.payment <= 0 }
        VStack(alignment: .leading, spacing: 6) {
            if !missing.isEmpty {
                Text("\(missing.map(\.name).joined(separator: ", ")) \(missing.count == 1 ? "has" : "have") no monthly payment set, so only the extra money pays \(missing.count == 1 ? "it" : "them") off. Set a payment on the account for a truer picture.")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
