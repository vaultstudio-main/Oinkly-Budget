#if DEBUG
import Foundation
import SQLite3

/// `-sharedTimingTest <transactions>` makes a large copy of this Mac's own data (by repeating its transactions) in a
/// throwaway folder and times the steps of sharing on it, then quits. Never touches the real data. Debug only.
enum SharedTimingTest {
    static func runIfRequested(localStore: URL) {
        guard let flag = CommandLine.arguments.firstIndex(of: "-sharedTimingTest") else { return }
        let target = flag + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[flag + 1]) ?? 20_000 : 20_000
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("OinklyTiming-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        func time<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
            let begin = Date()
            let result = try work()
            NSLog("TIMING: \(name): \(String(format: "%.2f", Date().timeIntervalSince(begin))) s")
            return result
        }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let big = try StoreFiles.snapshot(of: localStore, into: root.appendingPathComponent("big")).deletingLastPathComponent().appendingPathComponent("OinklyBudget.store")
            try inflate(big, to: target)
            let counts = try SQLiteStore.counts(of: big)
            let size = (try? manager.attributesOfItem(atPath: big.path)[.size] as? Int) ?? 0
            NSLog("TIMING: test data has \(counts["ZTRANSACTION"] ?? 0) transactions, \(counts.values.reduce(0, +)) rows, \(size / 1_000_000) MB")

            let folder = SharedDataFolder(url: root.appendingPathComponent("shared", isDirectory: true))
            try folder.ensureFolder()
            try time("first save into the shared folder (copy, counts, integrity check)") { try folder.checkIn(from: big, baseRevision: nil, by: "Timer", appVersion: "1.0") }
            let work = root.appendingPathComponent("work/OinklyBudget.store")
            try time("open: copy to the working copy and check it") { try folder.checkOut(to: work) }
            var revision = folder.readInfo()?.revision
            for round in 1...3 {
                try time("routine save \(round) (also keeps the previous save)") {
                    let info = try folder.checkIn(from: work, baseRevision: revision, by: "Timer", appVersion: "1.0")
                    revision = info.revision
                }
            }
            try time("keeping a previous save, listing and trimming") { folder.pruneHistory(); _ = folder.versions() }
            try time("record counts alone") { _ = try SQLiteStore.counts(of: work) }
            try time("integrity check alone") { _ = try SQLiteStore.integrityIsOK(work) }
            try time("one copy of the file alone (VACUUM INTO)") { try SQLiteStore.vacuum(source: work, into: root.appendingPathComponent("v.store")) }
        } catch {
            NSLog("TIMING: failed: \(error.localizedDescription)")
        }
        exit(0)
    }

    /// Repeats the transactions until there are `target` of them. Only meant for timing; the copy isn't valid app data.
    private static func inflate(_ store: URL, to target: Int) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(store.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else { throw StoreError.failed("can't open the test copy") }
        defer { sqlite3_close(db) }
        var columns: [String] = []
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT name FROM pragma_table_info('ZTRANSACTION') WHERE name <> 'Z_PK'", -1, &statement, nil)
        while sqlite3_step(statement) == SQLITE_ROW { columns.append(String(cString: sqlite3_column_text(statement, 0))) }
        sqlite3_finalize(statement)
        let list = columns.joined(separator: ",")
        func count() -> Int {
            var s: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZTRANSACTION", -1, &s, nil)
            defer { sqlite3_finalize(s) }
            return sqlite3_step(s) == SQLITE_ROW ? Int(sqlite3_column_int64(s, 0)) : 0
        }
        guard count() > 0 else { throw StoreError.failed("this Mac's data has no transactions to repeat") }
        while count() < target {
            let missing = target - count()
            guard sqlite3_exec(db, "INSERT INTO ZTRANSACTION (\(list)) SELECT \(list) FROM ZTRANSACTION LIMIT \(missing)", nil, nil, nil) == SQLITE_OK else {
                throw StoreError.failed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}
#endif
