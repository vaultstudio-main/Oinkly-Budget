import Foundation
import SwiftData

/// Which checking account is the primary one. It is pinned under Cash on Hand in the side panel, outside any folder,
/// and labelled "Primary Checking". There is at most one. It is kept on the account itself, so it travels with
/// backups and the shared data file.
enum PrimaryChecking {
    /// Where earlier versions kept it, as a setting on this Mac. Only read once, when upgrading.
    static let legacyKey = "primaryCheckingAccount"

    /// Whether `account` should show as the primary checking account.
    static func isPrimary(_ account: Account) -> Bool {
        account.isLive && account.type == .checking && account.isPrimaryChecking
    }

    /// Makes `account` the primary one, or clears it with nil. Only one account is ever primary.
    static func set(_ account: Account?, in context: ModelContext) {
        for other in ((try? context.fetch(FetchDescriptor<Account>())) ?? []) where other.isLive && other.isPrimaryChecking && other !== account {
            other.isPrimaryChecking = false
        }
        account?.isPrimaryChecking = true
    }

    /// Moves the old per-Mac setting onto the account, once, and clears it.
    static func adoptLegacySetting(in context: ModelContext) {
        guard let stored = UserDefaults.standard.string(forKey: legacyKey), !stored.isEmpty else { return }
        defer { UserDefaults.standard.removeObject(forKey: legacyKey) }
        guard let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: Data(stored.utf8)),
              let account = context.model(for: id) as? Account, account.isLive, account.type == .checking else { return }
        let anyPrimary = ((try? context.fetch(FetchDescriptor<Account>())) ?? []).contains { $0.isLive && $0.isPrimaryChecking }
        if !anyPrimary { account.isPrimaryChecking = true }
    }
}
