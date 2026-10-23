import Foundation

/// How a month's money ebbs and flows, and the earliest day the spare money can be pulled out safely: the day from which the
/// whole spare amount (what the month ends with, less the buffer) can come out and the balance still never drops under the buffer.
/// It is worked out twice, once from the War Plan's lines and once from the Monthly Outlook's real information, so the two can be compared.
struct SafePull {
    /// Money moving on a day: plus for money in, minus for money out.
    struct Event {
        let date: Date
        let amount: Decimal
    }

    /// The balance after an event.
    struct Point: Identifiable {
        /// Its place in the month's order, so two events on one day are still two points.
        let id: Int
        let date: Date
        let balance: Decimal
    }

    let opening: Decimal
    let buffer: Decimal
    let points: [Point]

    init(opening: Decimal, buffer: Decimal, events: [Event]) {
        self.opening = opening
        self.buffer = buffer
        // On one day the money in counts first, as it does in the War Plan sheet.
        // Events are by day, whatever time of day they were made for.
        let calendar = Calendar.current
        let sorted = events.map { Event(date: calendar.startOfDay(for: $0.date), amount: $0.amount) }
            .sorted { ($0.date, $0.amount > 0 ? 0 : 1) < ($1.date, $1.amount > 0 ? 0 : 1) }
        var total = opening
        var made: [Point] = []
        for event in sorted {
            total += event.amount
            made.append(Point(id: made.count, date: event.date, balance: total))
        }
        points = made
    }

    var ending: Decimal { points.last?.balance ?? opening }
    /// What is really spare: the end of the month less the buffer.
    var spare: Decimal { ending - buffer }

    /// The earliest day the whole spare amount can come out. It is the day after the last time the balance was under what
    /// the month ends with. Nil when nothing is spare or nothing is planned.
    var best: Point? {
        guard spare > 0, !points.isEmpty else { return nil }
        let end = ending
        var first = (points.lastIndex { $0.balance < end } ?? -1) + 1
        guard first < points.count else { return nil }
        // The whole day counts: the balance at its close.
        while first + 1 < points.count, points[first + 1].date == points[first].date { first += 1 }
        return points[first]
    }

    /// The lowest the balance gets, and when.
    var lowest: Point? { points.min { $0.balance < $1.balance } }

    // MARK: Where the events come from

    static func events(plan items: [WarPlanItem]) -> [Event] {
        items.map { Event(date: $0.date, amount: $0.isIncome ? $0.amount : -$0.amount) }
    }

    /// The outlook's own lines have dates. What a budget spends beyond them, and spending that belongs to no budget, has no
    /// date, so it is spread over the month a week at a time.
    static func events(outlook: MonthOutlook, calendar: Calendar = .current) -> [Event] {
        var list: [Event] = []
        for line in outlook.income { list.append(Event(date: line.date, amount: line.counted)) }
        if outlook.otherIncome != 0 { list.append(Event(date: outlook.month, amount: outlook.otherIncome)) }
        for line in outlook.bills { list.append(Event(date: line.date, amount: -line.counted)) }
        var undated: Decimal = outlook.otherSpending
        for budget in outlook.budgets {
            for line in budget.inside { list.append(Event(date: line.date, amount: -line.counted)) }
            undated += max(budget.counted - budget.inside.reduce(0) { $0 + $1.counted }, 0)
        }
        list += spread(undated, over: outlook.month, calendar: calendar)
        return list
    }

    /// An amount of spending split into weekly pieces through the month, starting on its first day.
    static func spread(_ amount: Decimal, over month: Date, calendar: Calendar = .current) -> [Event] {
        guard amount > 0, let days = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weeks = max((days + 6) / 7, 1)
        let piece = amount / Decimal(weeks)
        return (0..<weeks).compactMap { week in
            calendar.date(byAdding: .day, value: week * 7, to: month).map { Event(date: $0, amount: -piece) }
        }
    }
}
