import Foundation
import SwiftData

/// Calculations behind the Net Worth, Cash Flow and Debt reports.
enum ReportMath {
    // MARK: Assets and net worth

    /// Total of everything you own at the end of each of the last twelve months, then six months at the pace of the last three.
    static func assets(accounts: [Account], snapshot: LedgerSnapshot, now: Date = .now, calendar: Calendar = .current) -> [TrendPoint] {
        let owned = accounts.live.filter { !$0.isDebt }
        let starts = Summary.monthStarts(count: 12, now: now, calendar: calendar)
        var history: [TrendPoint] = []
        for start in starts {
            let cutoff = min(calendar.dateInterval(of: .month, for: start)?.end ?? start, now)
            let total = owned.reduce(Decimal(0)) { $0 + $1.openingBalance + snapshot.total(for: $1.persistentModelID, asOf: cutoff) }
            history.append(TrendPoint(date: start, value: total.doubleValue, projected: false))
        }
        guard history.count >= 4, let last = history.last else { return history }
        let change = (last.value - history[history.count - 4].value) / 3
        return history + future(from: last, calendar: calendar) { last.value + change * Double($0) }
    }

    /// The months after `last`, with `last` repeated first so a dashed line joins a solid one.
    static func future(from last: TrendPoint, months: Int = ReportTrends.futureMonths, calendar: Calendar = .current, value: (Int) -> Double) -> [TrendPoint] {
        var points = [TrendPoint(date: last.date, value: last.value, projected: true)]
        for month in 1...months {
            guard let date = calendar.date(byAdding: .month, value: month, to: last.date) else { continue }
            points.append(TrendPoint(date: date, value: value(month), projected: true))
        }
        return points
    }

    /// The three paths of the net worth range: low, expected and high. The spread is one standard deviation of the
    /// month-to-month changes over the last year.
    struct RangePoint: Identifiable {
        let date: Date
        let low: Double
        let expected: Double
        let high: Double
        var id: Date { date }
    }

    static func netWorthRange(from history: [TrendPoint], calendar: Calendar = .current) -> [RangePoint] {
        let past = history.filter { !$0.projected }
        guard past.count >= 4, let last = past.last else { return [] }
        let changes = zip(past.dropFirst(), past).map { $0.value - $1.value }
        let mean = changes.reduce(0, +) / Double(changes.count)
        let variance = changes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(changes.count)
        let spread = variance.squareRoot()
        let recent = (last.value - past[past.count - 4].value) / 3
        var points = [RangePoint(date: last.date, low: last.value, expected: last.value, high: last.value)]
        for month in 1...ReportTrends.futureMonths {
            guard let date = calendar.date(byAdding: .month, value: month, to: last.date) else { continue }
            let step = Double(month)
            points.append(RangePoint(date: date,
                                     low: last.value + (recent - spread) * step,
                                     expected: last.value + recent * step,
                                     high: last.value + (recent + spread) * step))
        }
        return points
    }

    // MARK: Account movement

    struct Mover: Identifiable {
        let id: Account.ID
        let name: String
        let symbol: String
        let isDebt: Bool
        let now: Decimal
        /// Change in the balance over the last three and twelve months. For a debt, a positive number is paying it down.
        let threeMonths: Decimal
        let twelveMonths: Decimal
    }

    /// Every account with how its balance moved, biggest recent change first.
    static func movers(accounts: [Account], snapshot: LedgerSnapshot, now: Date = .now, calendar: Calendar = .current) -> [Mover] {
        let three = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        let twelve = calendar.date(byAdding: .month, value: -12, to: now) ?? now
        func balance(_ account: Account, _ date: Date) -> Decimal {
            account.openingBalance + snapshot.total(for: account.persistentModelID, asOf: date)
        }
        return accounts.live.filter { !$0.isClosed }.map { account in
            let current = balance(account, now)
            return Mover(id: account.id, name: account.name, symbol: account.type.symbol, isDebt: account.isDebt, now: current,
                         threeMonths: current - balance(account, three), twelveMonths: current - balance(account, twelve))
        }
        .sorted { abs($0.threeMonths) > abs($1.threeMonths) }
    }

    /// One account's balance at the end of each of the last twelve months.
    static func history(of account: Account, snapshot: LedgerSnapshot, now: Date = .now, calendar: Calendar = .current) -> [TrendPoint] {
        Summary.monthStarts(count: 12, now: now, calendar: calendar).map { start in
            let cutoff = min(calendar.dateInterval(of: .month, for: start)?.end ?? start, now)
            let value = account.openingBalance + snapshot.total(for: account.persistentModelID, asOf: cutoff)
            return TrendPoint(date: start, value: value.doubleValue, projected: false)
        }
    }

    // MARK: Cash flow

    struct FlowMonth: Identifiable {
        let date: Date
        let income: Double
        let spending: Double
        let projected: Bool
        var net: Double { income - spending }
        var id: String { "\(date.timeIntervalSince1970)-\(projected)" }
    }

    /// Twelve months of income and spending from the ledger, then six projected at the average of the last three months.
    static func monthlyFlow(snapshot: LedgerSnapshot, calendar: Calendar = .current) -> [FlowMonth] {
        var months: [FlowMonth] = snapshot.monthStarts.indices.map { index in
            FlowMonth(date: snapshot.monthStarts[index], income: snapshot.income[index].doubleValue,
                      spending: snapshot.spending[index].doubleValue, projected: false)
        }
        guard months.count >= 3, let last = months.last else { return months }
        let recent = months.suffix(3)
        let income = recent.reduce(0) { $0 + $1.income } / 3
        let spending = recent.reduce(0) { $0 + $1.spending } / 3
        for month in 1...ReportTrends.futureMonths {
            guard let date = calendar.date(byAdding: .month, value: month, to: last.date) else { continue }
            months.append(FlowMonth(date: date, income: income, spending: spending, projected: true))
        }
        return months
    }

    struct ForecastWeek: Identifiable {
        let date: Date
        let balance: Double
        var id: Date { date }
    }

    struct Forecast {
        var weeks: [ForecastWeek] = []
        var startBalance: Double = 0
        var weeklyIncome: Double = 0
        var weeklyOtherSpending: Double = 0
        /// Bills still to pay in the next 30 days, and what they add up to.
        var billsNext30: Double = 0
        var incomeNext30: Double = 0

        var lowest: ForecastWeek? { weeks.min { $0.balance < $1.balance } }
    }

    /// The balance of your checking and savings each week for six months. Income and everyday spending continue at the
    /// average of the last three months; bills are put in on the days they are due.
    static func forecast(accounts: [Account], bills: [Bill], rules: [RecurringTransaction] = [], snapshot: LedgerSnapshot, billPayments: Decimal,
                         now: Date = .now, calendar: Calendar = .current) -> Forecast {
        var result = Forecast()
        let liquid = accounts.live.filter { $0.type.group == .checkingSavings && !$0.isClosed }
        result.startBalance = liquid.reduce(Decimal(0)) { $0 + $1.openingBalance + snapshot.total(for: $1.persistentModelID, asOf: now) }.doubleValue

        // Averages over the last three full months, as weekly amounts.
        let count = snapshot.income.count
        guard count >= 4 else { return result }
        // Repeating transactions are put in on their own dates below, so what they usually add up to is taken out of the
        // averages. Otherwise they would count twice.
        let liveRules = rules.live.filter { $0.isActive && $0.account?.isLive == true && $0.account?.type.group == .checkingSavings }
        let ruleIncomeMonthly = liveRules.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + Recurring.monthlyAmount(of: $1) }
        let ruleSpendingMonthly = liveRules.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - Recurring.monthlyAmount(of: $1) }
        let incomeMonthly = max((1...3).reduce(Decimal(0)) { $0 + snapshot.income[count - 1 - $1] } / 3 - ruleIncomeMonthly, 0)
        let spendingMonthly = (1...3).reduce(Decimal(0)) { $0 + snapshot.spending[count - 1 - $1] } / 3
        let billsMonthly = billPayments / 3
        let otherMonthly = max(spendingMonthly - billsMonthly - ruleSpendingMonthly, 0)
        let perWeek = 12.0 / 52.0
        result.weeklyIncome = incomeMonthly.doubleValue * perWeek
        result.weeklyOtherSpending = otherMonthly.doubleValue * perWeek

        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .month, value: ReportTrends.futureMonths, to: today) ?? today
        let due = Bills.occurrences(bills, from: today, through: end, now: now, calendar: calendar).filter { !$0.isPaid }
        let thirty = calendar.date(byAdding: .day, value: 30, to: today) ?? today
        result.billsNext30 = due.filter { $0.date <= thirty }.reduce(0) { $0 + $1.bill.amount.doubleValue }
        result.incomeNext30 = result.weeklyIncome * 30 / 7
        // Each rule's entries on their due dates, from today to the end of the forecast.
        var ruleEntries: [(date: Date, amount: Double)] = []
        for rule in liveRules {
            for date in Recurring.dates(of: rule, through: end, calendar: calendar) where date >= today {
                ruleEntries.append((date, rule.amount.doubleValue))
            }
        }
        result.incomeNext30 += ruleEntries.filter { $0.date <= thirty && $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        result.billsNext30 += ruleEntries.filter { $0.date <= thirty && $0.amount < 0 }.reduce(0) { $0 - $1.amount }

        var balance = result.startBalance
        result.weeks.append(ForecastWeek(date: today, balance: balance))
        var weekStart = today
        while let next = calendar.date(byAdding: .day, value: 7, to: weekStart), next <= end {
            let billsThisWeek = due.filter { $0.date >= weekStart && $0.date < next }.reduce(0) { $0 + $1.bill.amount.doubleValue }
            let rulesThisWeek = ruleEntries.filter { $0.date >= weekStart && $0.date < next }.reduce(0) { $0 + $1.amount }
            balance += result.weeklyIncome - result.weeklyOtherSpending - billsThisWeek + rulesThisWeek
            result.weeks.append(ForecastWeek(date: next, balance: balance))
            weekStart = next
        }
        return result
    }

    // MARK: Debt payoff

    struct PayoffDebt {
        var owed: Double
        /// Yearly rate in percent.
        var rate: Double
        var payment: Double
    }

    struct PayoffResult {
        var months: Int
        var interest: Double
        /// False when the payments never clear the debt (they don't cover the interest).
        var finishes: Bool
    }

    /// Pays every debt its monthly payment each month, plus `extra` on the one with the highest rate (the "avalanche"
    /// order). When a debt is paid off, its payment rolls onto the next, and keeps rolling to the rest. This uses the same
    /// arithmetic as the Debt War Plan, so the two always agree.
    static func payoff(_ debts: [PayoffDebt], extra: Double, limit: Int = 600) -> PayoffResult {
        let list = debts.enumerated().map {
            DebtWarPlan.Debt(id: "\($0.offset)", name: "", kind: "", symbol: "", owed: $0.element.owed, rate: $0.element.rate, payment: $0.element.payment)
        }
        let result = DebtWarPlan.simulate(list, extra: extra, strategy: .avalanche, limit: limit)
        return PayoffResult(months: result.months, interest: result.interest, finishes: result.finishes)
    }
}
