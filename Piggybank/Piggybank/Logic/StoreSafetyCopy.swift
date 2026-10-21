import Foundation

/// A copy of the data file, made once, just before the app first opens it in the new shape. The move is automatic and
/// tested, but this means that if anything ever goes wrong your data from before the update is still on the Mac, in
/// Application Support ▸ Backups. It is kept; delete the folder whenever you are happy with the update.
enum StoreSafetyCopy {
    private static let doneKey = "safetyCopyBeforeV2Made"

    /// The folder the copy goes in, named with the date.
    private static func destination(now: Date = .now) -> URL {
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return URL.applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Before this update (\(stamp))", isDirectory: true)
    }

    /// Copies the data file the first time this runs. Quietly does nothing
    /// on a fresh install, and never stops the app from starting.
    static func makeIfNeeded(localStore: URL) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        UserDefaults.standard.set(true, forKey: doneKey)
        let manager = FileManager.default
        let folder = destination()
        var sources: [(URL, String)] = []
        for suffix in ["", "-wal", "-shm"] {
            sources.append((URL(fileURLWithPath: localStore.path + suffix), localStore.lastPathComponent + suffix))
        }
        // Receipts and photos live beside the store, in a hidden folder.
        let support = localStore.deletingLastPathComponent().appendingPathComponent(".\(localStore.lastPathComponent)_SUPPORT", isDirectory: true)
        sources.append((support, support.lastPathComponent))

        for (source, name) in sources where manager.fileExists(atPath: source.path) {
            do {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: folder.appendingPathComponent(name))
            } catch {
                NSLog("Safety copy of \(name) failed: \(error.localizedDescription)")
            }
        }
    }
}
