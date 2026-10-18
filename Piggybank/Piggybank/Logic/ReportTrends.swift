import Foundation
import SwiftData

/// One point on a trend line. The last six months of a line are a projection.
struct TrendPoint: Identifiable {
    let date: Date
    let value: Double
    let projected: Bool
    var id: String { "\(date.timeIntervalSince1970)-\(projected)" }
}

/// The lines on the Reports page: twelve months of history and a six month projection.
enum ReportTrends {
    static let futureMonths = 6

    // MARK: Net worth

    /// Net worth at the end of each of the last twelve months, then six months at the pace of the last three.
    static func netWorth(accounts: [Account], snapshot: LedgerSnapshot, now: Date = .now, calendar: Calendar = .current) -> [TrendPoint] {
        let live = accounts.live
        let starts = Summary.monthStarts(count: 12, now: now, calendar: calendar)
        var history: [TrendPoint] = []
        for start in starts {
            let cutoff = min(calendar.dateInterval(of: .month, for: start)?.end ?? start, now)
            let total = live.reduce(Decimal(0)) { $0 + $1.openingBalance + snapshot.total(for: $1.persistentModelID, asOf: cutoff) }
            history.append(TrendPoint(date: start, value: total.doubleValue, projected: false))
        }
        guard history.count >= 4, let last = history.last else { return history }
        // The average month-to-month change over the last three months.
        let change = (last.value - history[history.count - 4].value) / 3
        return history + projection(from: last, step: { last.value + change * Double($0) }, calendar: calendar)
    }

    // MARK: Debt

    /// What one debt does over the next six months if the monthly payment keeps being made.
    private struct DebtPath {
        /// Owed now, then after each of the next six payments.
        var owed: [Double]
        /// The payment made in each of the next six months. Zero once it is paid off.
        var payments: [Double]
    }

    private static func debtPath(for account: Account) -> DebtPath {
        let rate = account.interestRate / 100 / 12
        let payment = account.monthlyPayment.doubleValue
        var owed = [Swift.max(-account.balance.doubleValue, 0)]
        var payments: [Double] = []
        for _ in 0..<futureMonths {
            let before = owed[owed.count - 1]
            let due = Swift.min(payment, before * (1 + rate))
            payments.append(before > 0 ? due : 0)
            owed.append(Swift.max(before * (1 + rate) - payment, 0))
        }
        return DebtPath(owed: owed, payments: payments)
    }

    private static func debtAccounts(_ accounts: [Account]) -> [Account] {
        accounts.live.filter { ($0.isLoan || $0.isCreditCard) && !$0.isClosed }
    }

    /// Total owed on loans and cards at the end of each of the last twelve months, then the next six at the monthly payments.
    static func debt(accounts: [Account], snapshot: LedgerSnapshot, now: Date = .now, calendar: Calendar = .current) -> [TrendPoint] {
        let debts = debtAccounts(accounts)
        let starts = Summary.monthStarts(count: 12, now: now, calendar: calendar)
        var history: [TrendPoint] = []
        for start in starts {
            let cutoff = min(calendar.dateInterval(of: .month, for: start)?.end ?? start, now)
            let owed = debts.reduce(Decimal(0)) { $0 + Swift.max(-($1.openingBalance + snapshot.total(for: $1.persistentModelID, asOf: cutoff)), 0) }
            history.append(TrendPoint(date: start, value: owed.doubleValue, projected: false))
        }
        guard let last = history.last else { return history }
        let paths = debts.map(debtPath)
        return history + projection(from: last, step: { month in paths.reduce(0) { $0 + $1.owed[month] } }, calendar: calendar)
    }

    // MARK: Debt-to-income

    /// Monthly debt payments as a percent of monthly income. Income is the average of the month and the two before it.
    /// History uses today's payments, since earlier payment amounts aren't kept.
    static func debtToIncome(accounts: [Account], snapshot: LedgerSnapshot, now: Date = .now, calendar: Calendar = .current) -> [TrendPoint] {
        let debts = debtAccounts(accounts)
        let payments = debts.reduce(0) { $0 + $1.monthlyPayment.doubleValue }
        let income = snapshot.income.map(\.doubleValue)
        let starts = snapshot.monthStarts
        guard payments > 0, !starts.isEmpty else { return [] }

        func average(ending index: Int) -> Double {
            let window = income[Swift.max(index - 2, 0)...index]
            return window.reduce(0, +) / Double(window.count)
        }
        var history: [TrendPoint] = []
        for index in starts.indices {
            let monthly = average(ending: index)
            guard monthly > 0 else { continue }
            history.append(TrendPoint(date: starts[index], value: payments / monthly * 100, projected: false))
        }
        guard let last = history.last, let lastIncome = income.indices.last.map(average(ending:)), lastIncome > 0 else { return history }
        let paths = debts.map(debtPath)
        return history + projection(from: last, step: { month in
            let paid = paths.reduce(0) { $0 + $1.payments[month - 1] }
            return paid / lastIncome * 100
        }, calendar: calendar)
    }

    // MARK: Shared

    /// The next six months after `last`, with `last` repeated first so the dashed line joins the solid one.
    private static func projection(from last: TrendPoint, step: (Int) -> Double, calendar: Calendar) -> [TrendPoint] {
        var points = [TrendPoint(date: last.date, value: last.value, projected: true)]
        for month in 1...futureMonths {
            guard let date = calendar.date(byAdding: .month, value: month, to: last.date) else { continue }
            points.append(TrendPoint(date: date, value: step(month), projected: true))
        }
        return points
    }
}
