import Foundation
import SwiftData

/// Repeating transactions: a rule that adds a pending transaction on each due date, for you to confirm or edit.
enum Recurring {
    /// Most entries made in one go after the app was closed for a long while. Older missed dates are skipped.
    static let maxCatchUp = 12

    /// What a pass of the runner did.
    struct Result {
        var created = 0
        var skipped = 0
    }

    // MARK: Dates

    /// The first due date of `rule` strictly after `date`, or nil when the rule has no more.
    static func date(after date: Date, for rule: RecurringTransaction, calendar: Calendar = .current) -> Date? {
        let first = calendar.startOfDay(for: rule.startDate)
        let limit = calendar.startOfDay(for: date)
        var step = 0
        while step < 5000, let candidate = rule.frequency.date(step, after: first, calendar: calendar) {
            let day = calendar.startOfDay(for: candidate)
            if day > limit {
                if let end = rule.endDate, day > calendar.startOfDay(for: end) { return nil }
                return day
            }
            step += 1
        }
        return nil
    }

    /// The first due date on or after `day`, or nil when the rule has ended by then.
    static func firstDue(onOrAfter day: Date, for rule: RecurringTransaction, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: rule.startDate)
        let today = calendar.startOfDay(for: day)
        if start >= today {
            if let end = rule.endDate, start > calendar.startOfDay(for: end) { return nil }
            return start
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        return date(after: yesterday, for: rule, calendar: calendar)
    }

    /// Every due date of `rule` from its next one through `end`, soonest first.
    static func dates(of rule: RecurringTransaction, through end: Date, limit: Int = 400, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var current = calendar.startOfDay(for: rule.nextDate)
        let stop = calendar.startOfDay(for: end)
        while current <= stop, result.count < limit {
            if let last = rule.endDate, current > calendar.startOfDay(for: last) { break }
            result.append(current)
            guard let following = date(after: current, for: rule, calendar: calendar) else { break }
            current = following
        }
        return result
    }

    // MARK: Making entries

    /// Whether the rule has already made an entry for this day.
    private static func hasEntry(_ rule: RecurringTransaction, on day: Date, calendar: Calendar) -> Bool {
        rule.transactions.contains { $0.isLive && calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// Adds a pending transaction for one due date of a rule. It never makes a second one for the same day.
    @MainActor
    @discardableResult
    static func makeEntry(for rule: RecurringTransaction, on day: Date, in context: ModelContext, calendar: Calendar = .current) -> Transaction? {
        guard rule.isLive, let account = rule.account, account.isLive, !hasEntry(rule, on: day, calendar: calendar),
              !account.wouldExceedLimit(adding: rule.amount) else { return nil }
        let entry = Transaction(account: account, date: day, payee: rule.payee,
                                category: rule.category?.isLive == true ? rule.category : nil,
                                memo: rule.memo, amount: rule.amount)
        entry.state = .pending
        entry.recurring = rule
        if let locked = account.lockedPaymentType {
            entry.paymentChoice = .type(locked)
        } else if let type = PayeeMemory.builtInMethod(rule.paymentTypeRaw) {
            entry.paymentChoice = .type(type)
        } else if rule.paymentTypeRaw.hasPrefix("custom:") {
            let name = String(rule.paymentTypeRaw.dropFirst("custom:".count))
            let methods = (try? context.fetch(FetchDescriptor<CustomPaymentMethod>())) ?? []
            if let method = methods.live.first(where: { $0.name == name }) { entry.paymentChoice = .custom(method) }
        }
        context.insert(entry)
        return entry
    }

    /// What ticking an entry a rule made does. A pending entry is confirmed and goes straight to Reconciled, whether it is a
    /// paycheque or a payment. Ticking a confirmed entry again takes it back to pending.
    static func toggleConfirmed(_ entry: Transaction) {
        entry.state = entry.state == .pending ? .reconciled : .pending
    }

    /// Moves a rule on to its next due date, or finishes it when there are no more.
    static func advance(_ rule: RecurringTransaction, calendar: Calendar = .current) {
        if let following = date(after: rule.nextDate, for: rule, calendar: calendar) {
            rule.nextDate = following
        } else {
            rule.isActive = false
        }
    }

    /// Brings every active rule up to date: one pending entry for each due date that has come, oldest first. When the app
    /// was closed for a long time, only the newest `maxCatchUp` are made. Running it again straight away changes nothing.
    @MainActor
    @discardableResult
    static func run(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Result {
        var result = Result()
        let today = calendar.startOfDay(for: now)
        let rules = ((try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []).live
        for rule in rules where rule.isActive && rule.autoEnter && rule.account?.isLive == true {
            var due = dates(of: rule, through: today, calendar: calendar)
            // So many were missed that the list was cut short: jump to the last year, so the newest ones are the ones made.
            if due.count >= 400, let recent = firstDue(onOrAfter: calendar.date(byAdding: .year, value: -1, to: today) ?? today, for: rule, calendar: calendar) {
                rule.nextDate = recent
                due = dates(of: rule, through: today, calendar: calendar)
            }
            guard !due.isEmpty else { continue }
            let skipped = max(due.count - maxCatchUp, 0)
            result.skipped += skipped
            for day in due.dropFirst(skipped) where makeEntry(for: rule, on: day, in: context, calendar: calendar) != nil {
                result.created += 1
            }
            // Move past everything that was due.
            let last = due[due.count - 1]
            if let following = date(after: last, for: rule, calendar: calendar) {
                rule.nextDate = following
            } else {
                rule.nextDate = last
                rule.isActive = false
            }
        }
        context.saveNow()
        return result
    }

    // MARK: Lists, the calendar, reminders and widgets

    /// One date of one repeating transaction, as the Recurring page, the menu bar item, the reminders and the widgets show it.
    struct Occurrence: Identifiable {
        enum Kind {
            /// A date still to come.
            case coming
            /// Today or past, for a rule that waits for you ("Reminder only"): add it or skip it.
            case due
            /// The pending entry the rule already made for this date.
            case added
        }

        let rule: RecurringTransaction
        let date: Date
        let kind: Kind
        /// For `.added`, the entry itself.
        var entry: Transaction?
        var isOverdue = false

        var id: String { "\(rule.persistentModelID.hashValue)-\(date.timeIntervalSince1970)-\(kind)" }
    }

    /// Every date of the active rules from `start` through `end`: entries already made, dates still to come, and dates a
    /// "reminder only" rule is waiting on. Soonest first.
    static func occurrences(_ rules: [RecurringTransaction], from start: Date, through end: Date, now: Date = .now, calendar: Calendar = .current) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        var result: [Occurrence] = []
        for rule in rules.live where rule.account?.isLive == true {
            for entry in rule.transactions where entry.isLive {
                let day = calendar.startOfDay(for: entry.date)
                if day >= first && day <= last { result.append(Occurrence(rule: rule, date: day, kind: .added, entry: entry)) }
            }
            guard rule.isActive else { continue }
            for day in dates(of: rule, through: last, calendar: calendar) where day >= first {
                if hasEntry(rule, on: day, calendar: calendar) { continue }
                if day > today {
                    result.append(Occurrence(rule: rule, date: day, kind: .coming))
                } else if !rule.autoEnter {
                    result.append(Occurrence(rule: rule, date: day, kind: .due, isOverdue: day < today))
                }
            }
        }
        return result.sorted { $0.date != $1.date ? $0.date < $1.date : $0.rule.payee < $1.rule.payee }
    }

    /// What is still ahead: dates in the next `days` days, plus anything a "reminder only" rule is waiting on. No entries
    /// that were already made.
    static func upcoming(_ rules: [RecurringTransaction], days: Int = 30, now: Date = .now, calendar: Calendar = .current) -> [Occurrence] {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days, to: today) ?? today
        let back = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        return occurrences(rules, from: back, through: end, now: now, calendar: calendar).filter { $0.kind != .added }
    }

    /// A reminder for the system's notifications. It never has an amount in it.
    struct Reminder: Identifiable {
        let id: String
        let title: String
        let body: String
        let fireDate: Date
    }

    /// One reminder on the morning of each date in the next `horizonDays` days.
    static func reminders(_ rules: [RecurringTransaction], horizonDays: Int = 45, hour: Int = 9, now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        upcoming(rules, days: horizonDays, now: now, calendar: calendar).compactMap { item in
            guard item.kind != .due || !item.isOverdue, let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: item.date), fire > now else { return nil }
            let rule = item.rule
            let account = rule.account?.name ?? "your account"
            let body = rule.autoEnter
                ? "A pending entry is added to \(account) today. Open Oinkly Budget to confirm it."
                : "Open Oinkly Budget ▸ Bills & Recurring to add it to \(account)."
            return Reminder(id: "\(rule.persistentModelID.hashValue)-\(item.date.timeIntervalSince1970)", title: "\(rule.payee) repeats today", body: body, fireDate: fire)
        }
    }

    // MARK: Looking ahead

    /// What the active rules would add over the next `days` days, as money in and money out.
    static func forecast(_ rules: [RecurringTransaction], days: Int = 30, now: Date = .now, calendar: Calendar = .current) -> (income: Decimal, spending: Decimal, count: Int) {
        let end = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        var income: Decimal = 0, spending: Decimal = 0, count = 0
        for rule in rules.live where rule.isActive {
            let ahead = dates(of: rule, through: end, calendar: calendar).filter { $0 >= calendar.startOfDay(for: now) }
            for _ in ahead {
                count += 1
                if rule.amount > 0 { income += rule.amount } else { spending -= rule.amount }
            }
        }
        return (income, spending, count)
    }

    /// A rule's expected amount in a month, averaged: weekly rules count 52/12 times, and so on.
    static func monthlyAmount(of rule: RecurringTransaction) -> Decimal {
        switch rule.frequency {
        case .once: 0
        case .weekly: rule.amount * 52 / 12
        case .everyTwoWeeks: rule.amount * 26 / 12
        case .monthly: rule.amount
        case .everyThreeMonths: rule.amount / 3
        case .yearly: rule.amount / 12
        }
    }
}
