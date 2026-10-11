import AppKit
import SwiftData

/// Starting over with an empty database. Deleting tens of thousands of transactions one at a time takes minutes and
/// ties the app up, so instead the database files are removed while the app is not using them: the next launch
/// deletes them before opening the database, and the app starts fresh. Needs no time however much data there is.
enum StoreReset {
    /// Also settable from the command line: `open -a Piggybank --args -piggybank.resetStoreOnLaunch YES`.
    static let key = "piggybank.resetStoreOnLaunch"

    /// Asks for the database to be emptied at the next launch, then quits.
    @MainActor
    static func requestAndQuit() {
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
}
