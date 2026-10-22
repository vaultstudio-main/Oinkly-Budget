import Foundation
import SwiftData

/// One of the person's own reminders, kept in the database so everyone who shares the data sees the same ones. The
/// reminder itself is stored as a small piece of JSON, so adding a field to a reminder later never changes the database.
@Model
final class ReminderRecord {
    var reminderID: UUID = UUID()
    var payload: Data = Data()
    /// The place in the list, so reminders stay in the order they were made.
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    init(reminderID: UUID, payload: Data, sortIndex: Int) {
        self.reminderID = reminderID
        self.payload = payload
        self.sortIndex = sortIndex
    }
}

/// A saved way of reading one bank's CSV file, kept in the database for the same reason as the reminders.
@Model
final class ImportLayoutRecord {
    var layoutID: UUID = UUID()
    var payload: Data = Data()
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    init(layoutID: UUID, payload: Data, sortIndex: Int) {
        self.layoutID = layoutID
        self.payload = payload
        self.sortIndex = sortIndex
    }
}

/// The colour a person picked for an account's or a bill's default picture. It has its own record, found by a key made from
/// the account's type and name or the bill's creation time, so the account and bill models stay exactly as they were.
/// No choice means the picture keeps the colour of its account group.
@Model
final class ArtworkChoice {
    var key: String = ""
    /// Which colour theme (see `ArtworkTheme`). Zero is Automatic and is never stored.
    var theme: Int = 0
    var createdAt: Date = Date.now

    init(key: String, theme: Int) {
        self.key = key
        self.theme = theme
    }
}

enum ArtworkChoices {
    static func key(for account: Account) -> String { "account|\(account.type.rawValue)|\(account.name)" }
    static func key(for bill: Bill) -> String { "bill|" + String(format: "%.6f", bill.createdAt.timeIntervalSinceReferenceDate) }

    private static func all(in context: ModelContext) -> [ArtworkChoice] {
        ((try? context.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).live
    }

    static func theme(for account: Account) -> Int { account.isLive ? theme(forKey: key(for: account), in: account.modelContext) : 0 }
    static func theme(for bill: Bill) -> Int { bill.isLive ? theme(forKey: key(for: bill), in: bill.modelContext) : 0 }

    private static func theme(forKey key: String, in context: ModelContext?) -> Int {
        guard let context else { return 0 }
        return all(in: context).first { $0.key == key }?.theme ?? 0
    }

    /// Remembers the colour for an account, or forgets it when it is Automatic. `previousKey` is the key it had before a
    /// rename. Does not save.
    static func set(_ theme: Int, for account: Account, previousKey: String? = nil, in context: ModelContext) {
        apply(theme, key: key(for: account), previousKey: previousKey, in: context)
    }

    static func set(_ theme: Int, for bill: Bill, in context: ModelContext) {
        apply(theme, key: key(for: bill), previousKey: nil, in: context)
    }

    static func apply(_ theme: Int, key: String, previousKey: String? = nil, in context: ModelContext) {
        let valid = ArtworkTheme.isValid(theme) ? theme : 0
        let existing = all(in: context)
        for old in existing where old.key == previousKey && old.key != key { context.delete(old) }
        let mine = existing.filter { $0.key == key }
        for extra in mine.dropFirst() { context.delete(extra) }
        if valid == 0 {
            for choice in mine { context.delete(choice) }
        } else if let choice = mine.first {
            if choice.theme != valid { choice.theme = valid }
        } else {
            context.insert(ArtworkChoice(key: key, theme: valid))
        }
    }

    /// Choices whose account or bill is gone (or was renamed somewhere that doesn't carry the colour along).
    static func removeOrphans(in context: ModelContext) {
        let accounts = Set(((try? context.fetch(FetchDescriptor<Account>())) ?? []).live.map { key(for: $0) })
        let bills = Set(((try? context.fetch(FetchDescriptor<Bill>())) ?? []).live.map { key(for: $0) })
        for choice in all(in: context) where !accounts.contains(choice.key) && !bills.contains(choice.key) { context.delete(choice) }
    }
}

/// Reading and writing the records above. `legacyKey` is where earlier builds kept the same list in this Mac's
/// preferences; `adoptLegacy` moves it into the database once.
enum SettingsRecords {
    private static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }

    // MARK: Reminders

    static func reminders(in context: ModelContext) -> [CustomReminder] {
        let records = ((try? context.fetch(FetchDescriptor<ReminderRecord>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []).live
        return records.compactMap { try? JSONDecoder().decode(CustomReminder.self, from: $0.payload) }
    }

    /// Makes the stored reminders match `items`: adds new ones, updates changed ones, removes the rest. Does not save.
    static func setReminders(_ items: [CustomReminder], in context: ModelContext) {
        let records = ((try? context.fetch(FetchDescriptor<ReminderRecord>())) ?? []).live
        var byID: [UUID: ReminderRecord] = [:]
        for record in records {
            // Two records for one reminder can't be told apart: keep the first.
            if byID[record.reminderID] == nil { byID[record.reminderID] = record } else { context.delete(record) }
        }
        let keep = Set(items.map(\.id))
        for record in byID.values where !keep.contains(record.reminderID) { context.delete(record) }
        for (index, item) in items.enumerated() {
            guard let data = encode(item) else { continue }
            if let record = byID[item.id] {
                if record.payload != data { record.payload = data }
                if record.sortIndex != index { record.sortIndex = index }
            } else {
                context.insert(ReminderRecord(reminderID: item.id, payload: data, sortIndex: index))
            }
        }
    }

    // MARK: Import layouts

    static func importLayouts(in context: ModelContext) -> [SavedImportLayout] {
        let records = ((try? context.fetch(FetchDescriptor<ImportLayoutRecord>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []).live
        return records.compactMap { try? JSONDecoder().decode(SavedImportLayout.self, from: $0.payload) }
    }

    static func setImportLayouts(_ items: [SavedImportLayout], in context: ModelContext) {
        let records = ((try? context.fetch(FetchDescriptor<ImportLayoutRecord>())) ?? []).live
        var byID: [UUID: ImportLayoutRecord] = [:]
        for record in records {
            if byID[record.layoutID] == nil { byID[record.layoutID] = record } else { context.delete(record) }
        }
        let keep = Set(items.map(\.id))
        for record in byID.values where !keep.contains(record.layoutID) { context.delete(record) }
        for (index, item) in items.enumerated() {
            guard let data = encode(item) else { continue }
            if let record = byID[item.id] {
                if record.payload != data { record.payload = data }
                if record.sortIndex != index { record.sortIndex = index }
            } else {
                context.insert(ImportLayoutRecord(layoutID: item.id, payload: data, sortIndex: index))
            }
        }
    }

    // MARK: Moving them out of this Mac's preferences

    private static let remindersMovedKey = "customRemindersMovedToDatabase"
    private static let layoutsMovedKey = "importLayoutsMovedToDatabase"

    /// Earlier builds kept reminders and saved import layouts in this Mac's preferences. Adds whatever the database
    /// doesn't have yet, once per login, and leaves the old copy where it is. Safe to run on every launch.
    static func adoptLegacy(in context: ModelContext, defaults: UserDefaults = .standard) {
        if !defaults.bool(forKey: remindersMovedKey) {
            if let data = defaults.data(forKey: "customReminders"), let old = try? JSONDecoder().decode([CustomReminder].self, from: data) {
                var current = reminders(in: context)
                let known = Set(current.map(\.id))
                current += old.filter { !known.contains($0.id) }
                setReminders(current, in: context)
            }
            defaults.set(true, forKey: remindersMovedKey)
        }
        if !defaults.bool(forKey: layoutsMovedKey) {
            if let data = defaults.data(forKey: "savedImportLayouts"), let old = try? JSONDecoder().decode([SavedImportLayout].self, from: data) {
                var current = importLayouts(in: context)
                let known = Set(current.map(\.id))
                current += old.filter { !known.contains($0.id) }
                setImportLayouts(current, in: context)
            }
            defaults.set(true, forKey: layoutsMovedKey)
        }
    }
}

/// What the Month Outlook said when a month closed, kept so a past month still shows what it showed then, even after a bill
/// or a budget is edited. Its own record, found by the month's key ("2026-10"), so no other model changes.
@Model
final class OutlookSnapshot {
    var monthKey: String = ""
    var incomeTotal: Decimal = 0
    var billsTotal: Decimal = 0
    var budgetsTotal: Decimal = 0
    var otherSpending: Decimal = 0
    var leftToSave: Decimal = 0
    /// How much more (positive) or less the bills with a linked payment came to than expected.
    var billDifference: Decimal = 0
    var budgetOverspend: Decimal = 0
    var savedAt: Date = Date.now

    init(monthKey: String, outlook: MonthOutlook) {
        self.monthKey = monthKey
        incomeTotal = outlook.incomeTotal
        billsTotal = outlook.billsTotal
        budgetsTotal = outlook.budgetsTotal
        otherSpending = outlook.otherSpending
        leftToSave = outlook.leftToSave
        billDifference = outlook.billDifference
        budgetOverspend = outlook.budgetOverspend
    }

    init(monthKey: String, incomeTotal: Decimal, billsTotal: Decimal, budgetsTotal: Decimal, otherSpending: Decimal,
         leftToSave: Decimal, billDifference: Decimal, budgetOverspend: Decimal, savedAt: Date) {
        self.monthKey = monthKey
        self.incomeTotal = incomeTotal
        self.billsTotal = billsTotal
        self.budgetsTotal = budgetsTotal
        self.otherSpending = otherSpending
        self.leftToSave = leftToSave
        self.billDifference = billDifference
        self.budgetOverspend = budgetOverspend
        self.savedAt = savedAt
    }
}

enum OutlookSnapshots {
    static func key(for month: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func snapshot(for month: Date, in context: ModelContext) -> OutlookSnapshot? {
        let wanted = key(for: month)
        return ((try? context.fetch(FetchDescriptor<OutlookSnapshot>())) ?? []).live.first { $0.monthKey == wanted }
    }

    /// Builds the outlook for the month containing `month` from what is in the database now.
    static func outlook(for month: Date, in context: ModelContext) -> MonthOutlook {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.date >= start && $0.date < end }))) ?? []
        return MonthOutlook.build(month: start, bills: ((try? context.fetch(FetchDescriptor<Bill>())) ?? []).live,
                                  rules: ((try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []).live,
                                  categories: ((try? context.fetch(FetchDescriptor<Category>())) ?? []).live, monthTransactions: transactions,
                                  excludedAccounts: MonthOutlook.excluded(from: UserDefaults.standard.string(forKey: MonthOutlook.excludedKey) ?? ""),
                                  cashBudgetKeys: CashBudgets.keys(in: context))
    }

    /// Keeps the figures of last month, if they haven't been kept yet. Does nothing before there is any data.
    static func closeLastMonth(in context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start,
              let last = calendar.date(byAdding: .month, value: -1, to: thisMonth),
              snapshot(for: last, in: context) == nil else { return }
        let built = outlook(for: last, in: context)
        guard built.incomeTotal != 0 || built.outTotal != 0 else { return }
        context.insert(OutlookSnapshot(monthKey: key(for: last), outlook: built))
        context.saveNow()
    }
}

/// Marks a budget as a cash budget: paid for in cash, so the Month Outlook leaves it out. Its own record, found by the
/// category's key, so the category model stays exactly as it was.
@Model
final class CashBudgetMark {
    var key: String = ""
    var createdAt: Date = Date.now

    init(key: String) { self.key = key }
}

enum CashBudgets {
    /// Built-in and custom categories keep a stable key; anything else is found by name.
    static func key(for category: Category) -> String { category.systemKey ?? "name|" + category.name }

    private static func all(in context: ModelContext) -> [CashBudgetMark] {
        ((try? context.fetch(FetchDescriptor<CashBudgetMark>())) ?? []).live
    }

    static func keys(in context: ModelContext) -> Set<String> { Set(all(in: context).map(\.key)) }

    static func isCash(_ category: Category) -> Bool {
        guard category.isLive, let context = category.modelContext else { return false }
        return keys(in: context).contains(key(for: category))
    }

    /// Marks or unmarks a category. Does not save.
    static func set(_ cash: Bool, for category: Category, in context: ModelContext) {
        let wanted = key(for: category)
        let mine = all(in: context).filter { $0.key == wanted }
        if cash {
            for extra in mine.dropFirst() { context.delete(extra) }
            if mine.isEmpty { context.insert(CashBudgetMark(key: wanted)) }
        } else {
            for mark in mine { context.delete(mark) }
        }
    }

    /// Marks for categories that are gone.
    static func removeOrphans(in context: ModelContext) {
        let present = Set(((try? context.fetch(FetchDescriptor<Category>())) ?? []).live.map { key(for: $0) })
        for mark in all(in: context) where !present.contains(mark.key) { context.delete(mark) }
    }
}
