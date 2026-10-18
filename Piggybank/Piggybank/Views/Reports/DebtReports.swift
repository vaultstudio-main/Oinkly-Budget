import SwiftUI
import SwiftData
import Charts

// MARK: Payoff schedule

struct LoanPayoffScheduleReport: View {
    @Query private var allAccounts: [Account]

    var body: some View {
        let lines = Liabilities.build(allAccounts.live).lines.filter { !$0.isPaidOff }
        let monthly = lines.reduce(Decimal(0)) { $0 + $1.progress.monthlyPayment }

        ReportPanel(title: "Loan Payoff Schedule", summary: "Every loan and card still owing, with its payment, estimated payoff and maturity date.",
                    headline: lines.isEmpty ? nil : monthly.formatted(.appCurrency), headlineNote: lines.isEmpty ? nil : "paid each month") {
            if lines.isEmpty {
                ReportEmpty(message: "No loans or cards with a balance. Debt you add in Settings ▸ Accounts shows up here.", height: 170)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    GridRow {
                        Text("ACCOUNT").gridColumnAlignment(.leading)
                        Text("OWED").gridColumnAlignment(.trailing)
                        Text("PAYMENT").gridColumnAlignment(.trailing)
                        Text("RATE").gridColumnAlignment(.trailing)
                        Text("LEFT").gridColumnAlignment(.trailing)
                        Text("EST. PAYOFF").gridColumnAlignment(.trailing)
                        Text("MATURITY").gridColumnAlignment(.trailing)
                        Text("STATUS").gridColumnAlignment(.leading)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(8)
                    ForEach(lines) { line in
                        let progress = line.progress
                        let estimate = progress.payoffDate()
                        GridRow {
                            Label(line.name, systemImage: line.symbol).lineLimit(1)
                            Text(line.owed, format: .appCurrency).foregroundStyle(Theme.red)
                            Text(progress.monthlyPayment > 0 ? progress.monthlyPayment.formatted(.appCurrency) : "—")
                            Text(progress.annualRate > 0 ? ReportFormat.percent(progress.annualRate, digits: 2) : "—")
                            Text(progress.paymentsLeft.map(String.init) ?? "—")
                            Text(estimate.map(ReportFormat.month) ?? "—")
                            Text(progress.targetDate.map(ReportFormat.month) ?? "—")
                            status(estimate: estimate, maturity: progress.targetDate)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func status(estimate: Date?, maturity: Date?) -> some View {
        if let maturity, let estimate {
            let months = Calendar.current.dateComponents([.month], from: estimate, to: maturity).month ?? 0
            if months > 0 { Label("\(months) mo ahead", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.caption) }
            else if months < 0 { Label("\(-months) mo behind", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption) }
            else { Label("On schedule", systemImage: "checkmark.circle").foregroundStyle(Theme.green).font(.caption) }
        } else if estimate == nil {
            Text("No payment set").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("No maturity date").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Ahead or behind

struct AheadOrBehindReport: View {
    @Query private var allAccounts: [Account]

    private struct Row: Identifiable {
        let name: String
        let months: Int
        var id: String { name }
    }

    var body: some View {
        let rows: [Row] = Liabilities.build(allAccounts.live).lines.compactMap { line in
            guard !line.isPaidOff, let maturity = line.progress.targetDate, let estimate = line.progress.payoffDate() else { return nil }
            return Row(name: line.name, months: Calendar.current.dateComponents([.month], from: estimate, to: maturity).month ?? 0)
        }
        ReportPanel(title: "Ahead or Behind", summary: "Estimated payoff against the maturity date, in months. Right of zero is ahead of schedule.") {
            if rows.isEmpty {
                ReportEmpty(message: "Needs a loan with a maturity date and a monthly payment.", height: 170)
            } else {
                Chart(rows) { row in
                    BarMark(x: .value("Months", row.months), y: .value("Loan", row.name))
                        .foregroundStyle(row.months >= 0 ? Theme.green : Color.orange)
                        .cornerRadius(3)
                        .annotation(position: row.months >= 0 ? .trailing : .leading) {
                            Text(row.months >= 0 ? "\(row.months) mo ahead" : "\(-row.months) mo behind").font(.caption2).foregroundStyle(.secondary)
                        }
                    RuleMark(x: .value("On schedule", 0)).foregroundStyle(.secondary.opacity(0.5))
                }
                .chartXAxisLabel("Months ahead (+) or behind (−)", alignment: .center)
                .frame(height: max(CGFloat(rows.count) * 44, 130))
            }
        }
    }
}

// MARK: Interest

struct InterestPaidReport: View {
    @Query private var allAccounts: [Account]

    private struct Row: Identifiable {
        let name: String
        let kind: String
        let amount: Double
        var id: String { "\(name)-\(kind)" }
    }

    /// Interest paid so far is an estimate: everything paid in, less the part that brought the balance down.
    var body: some View {
        let loans = allAccounts.live.filter { $0.isLoan && !$0.isClosed && $0.originalLoanAmount > 0 }
        var rows: [Row] = []
        var paidTotal = 0.0, aheadTotal = 0.0
        for loan in loans {
            let progress = loan.loanProgress
            let paidIn = loan.transactions.live.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
            let so = max(paidIn - progress.paidOff, 0).doubleValue
            let left = progress.paymentsLeft.map { max(Decimal($0) * progress.monthlyPayment - progress.owed, 0).doubleValue } ?? 0
            rows.append(Row(name: loan.name, kind: "Paid so far", amount: so))
            rows.append(Row(name: loan.name, kind: "Still to come", amount: left))
            paidTotal += so
            aheadTotal += left
        }
        return ReportPanel(title: "Interest Paid", summary: "An estimate of interest paid so far and what's still to come at the current payment.",
                           headline: loans.isEmpty ? nil : ReportFormat.money(paidTotal), headlineNote: loans.isEmpty ? nil : "paid so far · \(ReportFormat.money(aheadTotal)) to come") {
            if loans.isEmpty {
                ReportEmpty(message: "Needs a loan with its original amount filled in, so principal can be told from interest.", height: 170)
            } else {
                Chart(rows) { row in
                    BarMark(x: .value("Interest", row.amount), y: .value("Loan", row.name))
                        .foregroundStyle(by: .value("Kind", row.kind))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(["Paid so far": Theme.red, "Still to come": Color.orange.opacity(0.6)])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(ReportFormat.compact(n)) } } } }
                .frame(height: max(CGFloat(loans.count) * 52, 140))
            }
        }
    }
}

// MARK: Credit cards

struct CreditCardUseReport: View {
    @Query private var allAccounts: [Account]

    var body: some View {
        let cards = allAccounts.live.filter { $0.isCreditCard && !$0.isClosed }
        let owed = cards.reduce(Decimal(0)) { $0 + Goal.owed(on: $1) }
        let limit = cards.reduce(Decimal(0)) { $0 + $1.creditLimit }
        let overall = limit > 0 ? (owed / limit).doubleValue : nil

        ReportPanel(title: "Credit Card Use", summary: "Each card's balance against its limit, and where the balance is heading at the minimum payment.",
                    headline: overall.map { ReportFormat.percent($0 * 100) }, headlineNote: overall == nil ? nil : "of total limit used") {
            if cards.isEmpty {
                ReportEmpty(message: "No credit cards yet.", height: 170)
            } else {
                VStack(spacing: 12) {
                    ForEach(cards) { card in
                        let now = Goal.owed(on: card).doubleValue
                        let cardLimit = card.creditLimit.doubleValue
                        let use = cardLimit > 0 ? now / cardLimit : 0
                        let sixMonths = projected(card)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(card.name, systemImage: card.type.symbol)
                                Spacer()
                                Text("\(ReportFormat.money(now)) of \(cardLimit > 0 ? ReportFormat.money(cardLimit) : "no limit set")")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            ProgressView(value: min(use, 1)).tint(use > 0.5 ? Theme.red : (use > 0.3 ? .orange : Theme.green))
                            HStack {
                                Text(cardLimit > 0 ? "\(ReportFormat.percent(use * 100)) used" + (use > 0.3 ? " · under 30% is healthiest" : "") : "Set a credit limit to see use")
                                Spacer()
                                Text(card.monthlyPayment > 0 ? "About \(ReportFormat.money(sixMonths)) in 6 months" : "Set a minimum payment to project")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// The balance after six months of paying the monthly payment, with interest and no new charges.
    private func projected(_ card: Account) -> Double {
        var owed = Goal.owed(on: card).doubleValue
        let rate = card.interestRate / 1200
        for _ in 0..<ReportTrends.futureMonths { owed = max(owed * (1 + rate) - card.monthlyPayment.doubleValue, 0) }
        return owed
    }
}

// MARK: Payoff plan

struct DebtPayoffPlanReport: View {
    @Query private var allAccounts: [Account]

    private static let extras: [Double] = [0, 50, 100, 250, 500]

    var body: some View {
        let debts = allAccounts.live.filter { ($0.isLoan || $0.isCreditCard) && !$0.isClosed && Goal.owed(on: $0) > 0 }
        let usable = debts.filter { $0.monthlyPayment > 0 }.map {
            ReportMath.PayoffDebt(owed: Goal.owed(on: $0).doubleValue, rate: $0.interestRate, payment: $0.monthlyPayment.doubleValue)
        }
        let results = Self.extras.map { ($0, ReportMath.payoff(usable, extra: $0)) }
        let base = results.first?.1

        ReportPanel(title: "Debt Payoff Plan", summary: "How much sooner you'd be debt-free, and how much interest you'd save, by adding to your payments each month. The extra goes to the highest rate first.") {
            if usable.isEmpty {
                ReportEmpty(message: debts.isEmpty ? "No debt to pay off." : "Set a monthly payment on your loans and cards to see a plan.", height: 170)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    GridRow {
                        Text("EXTRA PER MONTH")
                        Text("DEBT-FREE").gridColumnAlignment(.trailing)
                        Text("MONTHS SOONER").gridColumnAlignment(.trailing)
                        Text("INTEREST").gridColumnAlignment(.trailing)
                        Text("INTEREST SAVED").gridColumnAlignment(.trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(5)
                    ForEach(results, id: \.0) { extra, result in
                        GridRow {
                            Text(extra == 0 ? "Current payments" : "+\(ReportFormat.money(extra))").fontWeight(extra == 0 ? .regular : .medium)
                            if result.finishes {
                                Text(Calendar.current.date(byAdding: .month, value: result.months, to: .now).map(ReportFormat.month) ?? "—")
                                Text(extra == 0 ? "—" : "\(max((base?.months ?? 0) - result.months, 0))").foregroundStyle(Theme.green)
                                Text(ReportFormat.money(result.interest))
                                Text(extra == 0 ? "—" : ReportFormat.money(max((base?.interest ?? 0) - result.interest, 0))).foregroundStyle(Theme.green)
                            } else {
                                Text("Not within 50 years").foregroundStyle(.secondary)
                                Text("—"); Text("—"); Text("—")
                            }
                        }
                        .font(.callout)
                    }
                }
                if usable.count < debts.count {
                    Text("\(debts.count - usable.count) debt\(debts.count - usable.count == 1 ? " has" : "s have") no monthly payment set and aren't counted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
