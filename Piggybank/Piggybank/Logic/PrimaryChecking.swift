import Foundation
import SwiftData

/// Which checking account is the primary one. It is pinned under Cash on Hand in the side panel, outside any folder,
/// and labelled "Primary Checking". There is at most one.
///
/// This is a setting kept on this Mac, not part of the database, so it is not in backups. When the database next
/// changes shape it can move onto the account itself.
enum PrimaryChecking {
    static let key = "primaryCheckingAccount"

    private static func encode(_ id: PersistentIdentifier) -> String {
        guard let data = try? JSONEncoder().encode(id) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode(_ stored: String) -> PersistentIdentifier? {
        guard !stored.isEmpty else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: Data(stored.utf8))
    }

    /// Whether `account` is the one saved in `stored`, whatever its type is now.
    static func isStored(_ account: Account, stored: String) -> Bool {
        account.isLive && decode(stored) == account.persistentModelID
    }

    /// Whether `account` should show as the primary checking account.
    static func isPrimary(_ account: Account, stored: String) -> Bool {
        account.type == .checking && isStored(account, stored: stored)
    }

    /// Makes `account` the primary one, or clears it with nil.
    static func set(_ account: Account?) {
        let value = account.map { encode($0.persistentModelID) } ?? ""
        UserDefaults.standard.set(value, forKey: key)
    }

    static var current: String { UserDefaults.standard.string(forKey: key) ?? "" }
}
