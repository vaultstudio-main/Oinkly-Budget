#if DEBUG
import Foundation

/// `-sharedFolderSelfTest` runs the shared folder's save, previous-saves and restore steps on a throwaway folder, using a
/// copy of this Mac's own data, then quits. It never touches /Users/Shared/OinklyBudget. Debug only.
enum SharedFolderSelfTest {
    static func runIfRequested(localStore: URL) {
        guard CommandLine.arguments.contains("-sharedFolderSelfTest") else { return }
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            NSLog("SELFTEST: \(ok ? "PASS" : "FAIL") \(name) \(detail)")
            if !ok { failures += 1 }
        }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("OinklySharedSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let source = try StoreFiles.snapshot(of: localStore, into: root.appendingPathComponent("source"))
            let counts = try SQLiteStore.counts(of: source)
            let folder = SharedDataFolder(url: root.appendingPathComponent("shared", isDirectory: true))
            let calendar = Calendar.current

            // Thirty saves, eight hours apart, over ten days.
            let start = Date.now.addingTimeInterval(-10 * 86_400)
            var last = start
            for i in 0..<30 {
                last = start.addingTimeInterval(Double(i) * 8 * 3600)
                if i == 0 { try folder.ensureFolder(); try folder.checkIn(from: source, baseRevision: nil, by: "Tester", appVersion: "1.0", now: last) }
                else { try folder.checkIn(from: source, baseRevision: i, by: "Tester \(i)", appVersion: "1.0", now: last) }
            }
            let info = folder.readInfo()
            check("thirty saves", info?.revision == 30, "revision \(info?.revision ?? -1)")
            folder.pruneHistory(now: last)
            let kept = folder.versions()
            check("history is trimmed", kept.count >= 5 && kept.count <= 12, "kept \(kept.count)")
            check("newest five are kept", Set(kept.prefix(5).map(\.info.revision)) == Set(25...29), "\(kept.prefix(5).map(\.info.revision))")
            let cutoff = calendar.startOfDay(for: last).addingTimeInterval(-6 * 86_400)
            let days = Set(kept.filter { $0.info.savedAt >= cutoff }.map { calendar.startOfDay(for: $0.info.savedAt) })
            check("one per day for a week", days.count >= 6, "\(days.count) days")
            check("nothing else piles up", kept.allSatisfy { $0.info.savedAt >= cutoff || $0.info.revision >= 25 })
            check("every kept save has its data", kept.allSatisfy { $0.info.counts == counts && SealedFile.isIntact($0.url) })

            // Go back to an older save
            if let older = kept.last {
                let copy = root.appendingPathComponent("restore/OinklyBudget.store")
                try manager.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                try SealedFile.unseal(older.url, to: copy)
                let restored = try folder.checkIn(from: copy, baseRevision: 30, by: "Tester", appVersion: "1.0")
                check("restore makes a new save", restored.revision == 31)
                check("the data before restoring is kept", folder.versions().contains { $0.info.revision == 30 })
                check("restored data matches", folder.readInfo()?.counts == counts)
            }
            check("save log written", folder.recentLog(100).count >= 30, "\(folder.recentLog(100).count) lines")
            check("diagnose mentions saves", folder.diagnose().contains { $0.contains("previous saves are kept") })
            let perms = (try? manager.attributesOfItem(atPath: folder.historyURL.path)[.posixPermissions] as? Int) ?? 0
            check("history folder open to every login", perms == 0o777, String(perms, radix: 8))
        } catch {
            check("no error", false, error.localizedDescription)
        }
        NSLog("SELFTEST: \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
