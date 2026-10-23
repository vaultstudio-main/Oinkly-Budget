import Foundation

/// Where the next stretch of months is heading: what comes in, what goes out, what is kept, and what you are worth at the end.
/// It assumes income and spending stay at the average of the last three full months, and that what is owned holds its value. It
/// is an estimate to plan with, not a promise.
struct Projection {
    struct Month: Identifiable {
        let date: Date
        let income: Double
        let spending: Double
        /// Bills due that month, from the Bills page. They are already part of spending, so they are not added to it.
        let bills: Double
        var saved: Double { income - spending }
        var id: Date { date }
    }

    struct NetPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    let monthlyIncome: Double
    let monthlySpending: Double
    let months: [Month]
    let netWorth: [NetPoint]

    var monthlySaved: Double { monthlyIncome - monthlySpending }
    var totalIncome: Double { months.reduce(0) { $0 + $1.income } }
    var totalSpending: Double { months.reduce(0) { $0 + $1.spending } }
    var totalSaved: Double { totalIncome - totalSpending }
    var totalBills: Double { months.reduce(0) { $0 + $1.bills } }
    /// The share of income kept, as a percent. Nil when nothing comes in.
    var savingsRate: Double? { totalIncome > 0 ? totalSaved / totalIncome * 100 : nil }
    /// Whether there is any history to project from.
    var hasData: Bool { monthlyIncome > 0 || monthlySpending > 0 }

    /// The average income and spending of the last three full months. The month in progress, the last in the history, is left out.
    static func averages(history: [(date: Date, income: Double, spending: Double)]) -> (income: Double, spending: Double) {
        let full = history.dropLast().suffix(3)
        guard !full.isEmpty else { return (0, 0) }
        let count = Double(full.count)
        return (full.reduce(0) { $0 + $1.income } / count, full.reduce(0) { $0 + $1.spending } / count)
    }

    /// The next `count` months after this one. `history` is income and spending by month, oldest first, ending with this month.
    static func make(history: [(date: Date, income: Double, spending: Double)], netWorthNow: Double, bills: [Bill], months count: Int,
                     now: Date = .now, calendar: Calendar = .current) -> Projection {
        let average = averages(history: history)
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var months: [Month] = []
        var net = [NetPoint(date: thisMonth, value: netWorthNow)]
        var running = netWorthNow
        for index in 1...max(count, 1) {
            guard let start = calendar.date(byAdding: .month, value: index, to: thisMonth),
                  let next = calendar.date(byAdding: .month, value: 1, to: start),
                  let end = calendar.date(byAdding: .day, value: -1, to: next) else { continue }
            let due = Bills.occurrences(bills, from: start, through: end, now: now, calendar: calendar).reduce(0.0) { $0 + $1.bill.amount.doubleValue }
            months.append(Month(date: start, income: average.income, spending: average.spending, bills: due))
            running += average.income - average.spending
            net.append(NetPoint(date: start, value: running))
        }
        return Projection(monthlyIncome: average.income, monthlySpending: average.spending, months: months, netWorth: net)
    }

    /// One year of a long-range projection.
    struct Year: Identifiable {
        let year: Int
        let saved: Double
        let netWorth: Double
        var id: Int { year }
    }

    /// Year by year, from now: what has been kept in total and what you would be worth, at the same monthly pace.
    static func years(_ count: Int, monthlyIncome: Double, monthlySpending: Double, netWorthNow: Double) -> [Year] {
        (1...max(count, 1)).map { year in
            let saved = (monthlyIncome - monthlySpending) * 12 * Double(year)
            return Year(year: year, saved: saved, netWorth: netWorthNow + saved)
        }
    }
}
