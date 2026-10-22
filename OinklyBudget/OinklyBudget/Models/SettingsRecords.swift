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
