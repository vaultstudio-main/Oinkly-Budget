import AppKit
import SwiftData

/// Starting over with an empty database. Deleting tens of thousands of transactions one at a time takes minutes and
/// ties the app up, so instead the database files are removed while the app is not using them: the next launch
/// deletes them before opening the database, and the app starts fresh. Needs no time however much data there is.
enum StoreReset {
    /// Also settable from the command line: `open -a Piggybank --args -piggybank.resetStoreOnLaunch YES`.
    static let key = "piggybank.resetStoreOnLaunch"

    private static let budgetsKey = "piggybank.budgetsToKeepAfterReset"

    /// Asks for the database to be emptied at the next launch, then quits. With `keepingBudgets`, the budget amounts
    /// on the built-in categories are carried over to the fresh database.
    @MainActor
    static func requestAndQuit(keepingBudgets context: ModelContext? = nil) {
        guard ClosingCountdown.run(.quit, reason: "It closes to erase all data. Open it again afterwards for a fresh start. Cancel if you are not ready.") else { return }
        if let context, let categories = try? context.fetch(FetchDescriptor<Category>()) {
            var kept: [String: String] = [:]
            for category in categories where category.isLive && !category.isCustom && category.monthlyLimit != 0 {
                if let systemKey = category.systemKey { kept[systemKey] = "\(category.monthlyLimit)" }
            }
            UserDefaults.standard.set(kept, forKey: budgetsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: budgetsKey)
        }
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.synchronize()
        NSApp.terminate(nil)
    }

    /// Runs before the database is opened. Removes the store, its journal files and its external attachments.
    static func performIfRequested(for configuration: ModelConfiguration) {
        guard UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        let url = configuration.url
        let folder = url.deletingLastPathComponent()
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        let storeName = url.lastPathComponent
        for name in names where name.hasPrefix(storeName) || name.hasPrefix("." + storeName.replacingOccurrences(of: ".store", with: "")) {
            try? manager.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Puts the budget amounts carried over from before a reset back on the built-in categories. Call once the
    /// built-in categories exist.
    static func restoreKeptBudgets(in context: ModelContext) {
        guard let kept = UserDefaults.standard.dictionary(forKey: budgetsKey) as? [String: String] else { return }
        UserDefaults.standard.removeObject(forKey: budgetsKey)
        guard let categories = try? context.fetch(FetchDescriptor<Category>()) else { return }
        for category in categories {
            if let key = category.systemKey, let text = kept[key], let amount = Decimal(string: text) {
                category.monthlyLimit = amount
            }
        }
    }
}
