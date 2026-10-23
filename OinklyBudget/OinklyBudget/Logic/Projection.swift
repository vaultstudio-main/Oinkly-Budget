import Foundation

/// Where the next stretch of months is heading: what comes in, what goes out, what is kept, and what you are worth at the end.
/// It assumes income and spending stay at the average of the last three full months, and that what is owned holds its value. It
/// is an estimate to plan with, not a promise.
struct Projection {
    /// Whether a month has happened, is happening, or is still to come.
    enum Kind {
        case actual, current, projected
    }

    struct Month: Identifiable {
        let date: Date
        let income: Double
        let spending: Double
        /// Bills due that month, from the Bills page. They are already part of spending, so they are not added to it.
        let bills: Double
        var kind: Kind = .projected
        /// What really came in and went out so far, for a month that has happened or is happening.
        var incomeSoFar = 0.0
        var spendingSoFar = 0.0
        var saved: Double { income - spending }
        var id: Date { date }
    }

    struct NetPoint: Identifiable {
        let date: Date
        let value: Double
        /// False for what really was, true for where it is heading.
        var projected = true
        var id: String { "\(date.timeIntervalSince1970)-\(projected)" }
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
    /// What really came in and went out so far in the period.
    var incomeSoFar: Double { months.reduce(0) { $0 + $1.incomeSoFar } }
    var spendingSoFar: Double { months.reduce(0) { $0 + $1.spendingSoFar } }

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
        var net = [NetPoint(date: thisMonth, value: netWorthNow, projected: false)]
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

    /// A calendar stretch, such as this quarter or this year: the months that have happened as they were, this month as what has
    /// happened plus the rest of it at the average, and the months still to come at the average.
    /// `netWorthHistory` is what you were worth at the end of each past month, oldest first.
    static func period(history: [(date: Date, income: Double, spending: Double)], netWorthHistory: [(date: Date, value: Double)], netWorthNow: Double,
                       bills: [Bill], from start: Date, through end: Date, now: Date = .now, calendar: Calendar = .current) -> Projection {
        let average = averages(history: history)
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let first = calendar.dateInterval(of: .month, for: start)?.start ?? start
        let last = calendar.dateInterval(of: .month, for: end)?.start ?? end
        var months: [Month] = []
        var net: [NetPoint] = []
        var running = netWorthNow
        var month = first
        while month <= last {
            guard let next = calendar.date(byAdding: .month, value: 1, to: month), let monthEnd = calendar.date(byAdding: .day, value: -1, to: next) else { break }
            let due = Bills.occurrences(bills, from: month, through: monthEnd, now: now, calendar: calendar).reduce(0.0) { $0 + $1.bill.amount.doubleValue }
            let actual = history.first { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            if month < thisMonth {
                months.append(Month(date: month, income: actual?.income ?? 0, spending: actual?.spending ?? 0, bills: due, kind: .actual,
                                    incomeSoFar: actual?.income ?? 0, spendingSoFar: actual?.spending ?? 0))
                if let worth = netWorthHistory.first(where: { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }) {
                    net.append(NetPoint(date: month, value: worth.value, projected: false))
                }
            } else if month == thisMonth {
                let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 30 * 86_400)
                let done = min(max(now.timeIntervalSince(interval.start) / interval.duration, 0), 1)
                let soFarIncome = actual?.income ?? 0, soFarSpending = actual?.spending ?? 0
                months.append(Month(date: month, income: soFarIncome + average.income * (1 - done), spending: soFarSpending + average.spending * (1 - done),
                                    bills: due, kind: .current, incomeSoFar: soFarIncome, spendingSoFar: soFarSpending))
                net.append(NetPoint(date: now, value: netWorthNow, projected: false))
                running = netWorthNow + (average.income - average.spending) * (1 - done)
                net.append(NetPoint(date: month, value: running, projected: true))
            } else {
                months.append(Month(date: month, income: average.income, spending: average.spending, bills: due))
                running += average.income - average.spending
                net.append(NetPoint(date: month, value: running, projected: true))
            }
            month = next
        }
        return Projection(monthlyIncome: average.income, monthlySpending: average.spending, months: months, netWorth: net)
    }

    /// January to December of the year containing `now`.
    static func calendarYear(of now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let interval = calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 365 * 86_400)
        return (interval.start, calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end)
    }

    /// The three months of the calendar quarter containing `now`.
    static func calendarQuarter(of now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let firstMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: year, month: firstMonth, day: 1)) ?? now
        let end = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 3, to: start) ?? start) ?? start
        return (start, end)
    }

    /// One calendar year of a long-range projection.
    struct Year: Identifiable {
        /// The calendar year, such as 2027.
        let year: Int
        /// What is kept in that year alone.
        let keptInYear: Double
        /// What is kept from now to the end of that year.
        let saved: Double
        /// What you would be worth on December 31 of that year.
        let netWorth: Double
        var id: Int { year }
    }

    /// The next `count` calendar years, starting with next year: what is kept in each and what you would be worth at the end of it,
    /// at the same monthly pace.
    static func years(_ count: Int, monthlyIncome: Double, monthlySpending: Double, netWorthNow: Double, now: Date = .now, calendar: Calendar = .current) -> [Year] {
        let thisYear = calendar.component(.year, from: now)
        let interval = calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 365 * 86_400)
        let left = min(max(interval.end.timeIntervalSince(now) / interval.duration, 0), 1) * 12
        let monthly = monthlyIncome - monthlySpending
        return (1...max(count, 1)).map { index in
            let saved = monthly * (left + 12 * Double(index))
            return Year(year: thisYear + index, keptInYear: monthly * 12, saved: saved, netWorth: netWorthNow + saved)
        }
    }
}
