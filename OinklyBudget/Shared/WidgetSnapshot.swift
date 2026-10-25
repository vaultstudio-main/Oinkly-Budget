import Foundation

/// What the widgets show, and nothing more: bill names and due dates, and the titles and times of the person's own
/// reminders. There are no amounts, balances or account details in here on purpose, so a widget on a shared screen
/// gives nothing away.
///
/// The app writes this small file into the shared App Group folder whenever its data changes. The widgets only read it,
/// so they never open the database. It can be deleted at any time and is rebuilt the next time the app runs.
/// This file is compiled into both the app and the widget extension.
nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    struct Bill: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var name: String
        var due: Date
        var isImportant: Bool
        var isOverdue: Bool
    }

    struct Reminder: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var title: String
        var next: Date
    }

    /// A date of a repeating transaction: its name and the day, never an amount.
    struct Repeating: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var name: String
        var due: Date
        var isOverdue: Bool
    }

    var updated: Date
    /// Unpaid bills: overdue ones and everything due in the next 30 days, soonest first.
    var bills: [Bill]
    /// The next time each of the person's own reminders will go off, soonest first.
    var reminders: [Reminder]
    /// Repeating transactions coming up in the next 30 days, soonest first. Missing from snapshots written by older versions.
    var repeating: [Repeating] = []

    /// The App Group shared by the app and its widgets. It starts with the team ID, which macOS accepts without
    /// registering it separately.
    /// A Debug build (the one Xcode runs) has its own group, bundle ID and data, so it never touches the copy of the app you use.
    #if DEBUG
    static let groupID = "LVKJ422Q3M.dev.vaultstudio.oinklybudget.debug"
    #else
    static let groupID = "LVKJ422Q3M.dev.vaultstudio.oinklybudget"
    #endif
    static let scheme = "oinklybudget"
    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns false when the shared folder isn't available.
    @discardableResult
    func write() -> Bool {
        guard let url = Self.fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

extension WidgetSnapshot {
    /// A snapshot written before repeating transactions were added has no `repeating` list; it reads as empty.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updated = try container.decode(Date.self, forKey: .updated)
        bills = try container.decode([Bill].self, forKey: .bills)
        reminders = try container.decode([Reminder].self, forKey: .reminders)
        repeating = try container.decodeIfPresent([Repeating].self, forKey: .repeating) ?? []
    }

    private enum CodingKeys: String, CodingKey { case updated, bills, reminders, repeating }
}
