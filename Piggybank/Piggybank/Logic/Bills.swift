import Foundation
import SwiftData

enum BillFrequency: String, CaseIterable, Identifiable {
    case once, weekly, everyTwoWeeks, monthly, everyThreeMonths, yearly

    var id: Self { self }

    var title: String {
        switch self {
        case .once: "One time"
        case .weekly: "Every week"
        case .everyTwoWeeks: "Every 2 weeks"
        case .monthly: "Every month"
        case .everyThreeMonths: "Every 3 months"
        case .yearly: "Every year"
        }
    }

    /// How often and on which day, for lists of what is set up: "The 5th of every month", "Every Friday". `date` is the
    /// first date it was set for.
    func schedule(from date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.component(.day, from: date)
        let ordinal = NumberFormatter.ordinal.string(from: NSNumber(value: day)) ?? "\(day)"
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        switch self {
        case .once: return date.formatted(.dateTime.month(.abbreviated).day().year())
        case .weekly: return "Every \(weekday)"
        case .everyTwoWeeks: return "Every other \(weekday)"
        case .monthly: return "The \(ordinal) of every month"
        case .everyThreeMonths: return "The \(ordinal), every 3 months"
        case .yearly: return "Every \(date.formatted(.dateTime.month(.wide).day()))"
        }
    }

    /// The date `step` repeats after `start`. Counting from the first date keeps "the 31st" on the last day of short months.
    func date(_ step: Int, after start: Date, calendar: Calendar) -> Date? {
        switch self {
        case .once: step == 0 ? start : nil
        case .weekly: calendar.date(byAdding: .day, value: 7 * step, to: start)
        case .everyTwoWeeks: calendar.date(byAdding: .day, value: 14 * step, to: start)
        case .monthly: calendar.date(byAdding: .month, value: step, to: start)
        case .everyThreeMonths: calendar.date(byAdding: .month, value: 3 * step, to: start)
        case .yearly: calendar.date(byAdding: .year, value: step, to: start)
        }
    }
}

private extension NumberFormatter {
    /// 1st, 2nd, 3rd.
    static let ordinal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}

/// Works out when bills fall due. Shared by the Bills screen and the reminder system.
enum Bills {
    /// One due date of one bill.
    struct Occurrence: Identifiable {
        let bill: Bill
        let date: Date
        let isPaid: Bool
        let isOverdue: Bool

        var id: String { Bills.key(bill, date) }
    }

    /// A notification that should be delivered at `fireDate` for a bill due on `dueDate`.
    struct Reminder: Identifiable {
        let id: String
        let name: String
        let amount: Decimal
        let dueDate: Date
        let fireDate: Date
        let isImportant: Bool
        /// True for the reminder on the day the bill is due, false for the one sent ahead of time.
        var isDueDay = false
    }

    static func key(_ bill: Bill, _ date: Date) -> String {
        "\(bill.persistentModelID.hashValue)-\(date.timeIntervalSince1970)"
    }

    /// Every due date of `bill` from `start` through `end`, in order.
    static func dates(of bill: Bill, from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        let first = calendar.startOfDay(for: bill.dueDate)
        let frequency = bill.frequency
        var result: [Date] = []
        var step = 0
        while step < 5000, let date = frequency.date(step, after: first, calendar: calendar), date <= end {
            if date >= start { result.append(date) }
            step += 1
        }
        return result
    }

    /// Due dates of all bills in the range, soonest first.
    static func occurrences(_ bills: [Bill], from start: Date, through end: Date, now: Date = .now, calendar: Calendar = .current) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: start)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!.addingTimeInterval(-1)
        var found: [Occurrence] = []
        for bill in bills.live {
            for date in dates(of: bill, from: start, through: end, calendar: calendar) {
                let paid = bill.isPaid(on: date, calendar: calendar)
                found.append(Occurrence(bill: bill, date: date, isPaid: paid, isOverdue: !paid && date < today))
            }
        }
        return found.sorted { $0.date != $1.date ? $0.date < $1.date : $0.bill.name < $1.bill.name }
    }

    /// The due date a payment made on `date` settles: the closest unpaid one within a few weeks either side.
    /// Falls back to the closest paid one if every nearby date is already paid. Nil when none are nearby.
    static func nearestDue(_ bill: Bill, to date: Date, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: date)
        let from = calendar.date(byAdding: .day, value: -45, to: day)!
        let through = calendar.date(byAdding: .day, value: 30, to: day)!
        let nearby = dates(of: bill, from: from, through: through, calendar: calendar)
        func distance(_ d: Date) -> TimeInterval { abs(d.timeIntervalSince(day)) }
        let unpaid = nearby.filter { !bill.isPaid(on: $0, calendar: calendar) }
        return (unpaid.isEmpty ? nearby : unpaid).min { distance($0) < distance($1) }
    }

    /// Unpaid bills still ahead (or recently missed), for the Upcoming list.
    static func upcoming(_ bills: [Bill], days: Int = 30, missedDays: Int = 14, now: Date = .now, calendar: Calendar = .current) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -missedDays, to: today)!
        let end = calendar.date(byAdding: .day, value: days, to: today)!
        return occurrences(bills, from: start, through: end, now: now, calendar: calendar).filter { !$0.isPaid }
    }

    /// Important bills that are overdue or inside their reminder window (at least 3 days), for the in-app alert.
    static func alerts(_ bills: [Bill], now: Date = .now, calendar: Calendar = .current) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -30, to: today)!
        let far = calendar.date(byAdding: .day, value: 30, to: today)!
        return occurrences(bills.live.filter(\.isImportant), from: start, through: far, now: now, calendar: calendar)
            .filter { item in
                guard !item.isPaid else { return false }
                let window = max(item.bill.remindDaysBefore, 3)
                let days = calendar.dateComponents([.day], from: today, to: item.date).day ?? 0
                return days <= window
            }
    }

    /// Important bills that are overdue or due in the next `days` days, soonest first, for the Summary page.
    static func priority(_ bills: [Bill], days: Int = 20, limit: Int = 5, now: Date = .now, calendar: Calendar = .current) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -30, to: today)!
        let end = calendar.date(byAdding: .day, value: days, to: today)!
        let found = occurrences(bills.live.filter(\.isImportant), from: start, through: end, now: now, calendar: calendar)
            .filter { !$0.isPaid }
        return Array(found.prefix(limit))
    }

    /// The reminders the notification system should have scheduled for each unpaid due date coming up: one
    /// `remindDaysBefore` days ahead and, when that is not already the day itself, one on the due date, both at `hour`.
    /// Reminders whose time has already passed are left out.
    static func reminders(_ bills: [Bill], horizonDays: Int = 60, hour: Int = 9, now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: horizonDays, to: today)!
        return occurrences(bills.live.filter(\.remindersOn), from: today, through: end, now: now, calendar: calendar)
            .filter { !$0.isPaid }
            .flatMap { item -> [Reminder] in
                var found: [Reminder] = []
                let ahead = calendar.date(byAdding: .day, value: -item.bill.remindDaysBefore, to: item.date)!
                if item.bill.remindDaysBefore > 0,
                   let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: ahead), fire > now {
                    found.append(Reminder(id: item.id, name: item.bill.name, amount: item.bill.amount, dueDate: item.date,
                                          fireDate: fire, isImportant: item.bill.isImportant))
                }
                if let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: item.date), fire > now {
                    found.append(Reminder(id: item.id + "-due", name: item.bill.name, amount: item.bill.amount, dueDate: item.date,
                                          fireDate: fire, isImportant: item.bill.isImportant, isDueDay: true))
                }
                return found
            }
    }
}

/// Paying a bill: one event that lands everywhere it belongs.
extension BillPayment {
    /// When a payment made with Pay a Bill is deleted, the due date it settled goes back to unpaid. Returns whether
    /// anything changed.
    @discardableResult
    static func release(_ transaction: Transaction, calendar: Calendar = .current) -> Bool {
        guard transaction.isLive, let bill = transaction.paidBill, bill.isLive, let due = transaction.paidDueDate else { return false }
        guard bill.isPaid(on: due, calendar: calendar) else { return false }
        bill.setPaid(false, on: due, calendar: calendar)
        return true
    }
}

enum BillPayment {
    /// Records a payment from `source`. Paying a loan or card puts a payment in the paying account and takes the same amount
    /// off the debt. Paying a plain bill puts one expense in the paying account. Either way, the bill, if there is one,
    /// is ticked off for the due date the payment settles. Returns the paying side's transaction.
    @discardableResult
    static func record(
        from source: Account,
        debt: Account?,
        bill: Bill?,
        amount: Decimal,
        date: Date,
        memo: String = "",
        state: ReconcileState = .unreconciled,
        paymentChoice: PaymentChoice? = nil,
        checkNumber: String = "",
        receiptData: Data? = nil,
        noReceipt: Bool = false,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> Transaction? {
        // Bills are never paid out of an investment account, and never by way of one.
        guard !source.supportsHoldings, !(debt?.supportsHoldings ?? false) else { return nil }
        let day = calendar.startOfDay(for: date)
        let out: Transaction
        let check = paymentChoice?.isCheck == true ? checkNumber : ""
        if let debt {
            // One payment, two sides: the method and check number are recorded on both.
            let paid = Transfers.pay(from: source, toward: debt, amount: amount, date: day, memo: memo, state: state,
                                     paymentType: nil, checkNumber: "", in: context)
            paid.into.paymentChoice = paymentChoice
            paid.into.checkNumber = check
            out = paid.out
        } else if let bill {
            out = Transaction(account: source, date: day, payee: bill.name, category: bill.category?.isLive == true ? bill.category : nil,
                              memo: memo, amount: -abs(amount))
            out.state = state
            context.insert(out)
        } else {
            return nil
        }
        out.paymentChoice = paymentChoice
        out.isBillPayment = true
        if let bill, let due = Bills.nearestDue(bill, to: day, calendar: calendar) {
            out.paidBill = bill
            out.paidDueDate = due
        }
        // A receipt, or the bill itself as a PDF, belongs with the checking account side only.
        if source.supportsReceipts {
            out.receiptData = receiptData
            out.noReceipt = receiptData == nil && noReceipt
        }
        out.checkNumber = check
        if let bill, let due = Bills.nearestDue(bill, to: day, calendar: calendar) {
            bill.setPaid(true, on: due, calendar: calendar)
        }
        return out
    }
}
