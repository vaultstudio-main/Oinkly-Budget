#if DEBUG
import Foundation
import SQLite3
import SwiftData

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

            // The backup copy: the snapshot and the portable .pig file
            let schema = Schema(versionedSchema: OinklyBudgetSchemaV9.self)
            let bigCopy = root.appendingPathComponent("big-open/OinklyBudget.store")
            try manager.createDirectory(at: bigCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: big, to: bigCopy)
            let container = try ModelContainer(for: schema, migrationPlan: OinklyBudgetMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: bigCopy, cloudKitDatabase: .none))
            // The old way (account by account) on a container nothing has been read from yet, for a fair comparison
            let slowCopy = root.appendingPathComponent("slow-open/OinklyBudget.store")
            try manager.createDirectory(at: slowCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: big, to: slowCopy)
            let slowContainer = try ModelContainer(for: schema, migrationPlan: OinklyBudgetMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: slowCopy, cloudKitDatabase: .none))
            let slowRecords = try time("portable file: the old account-by-account way (main thread)") { try DataBackup.slowTransactions(in: slowContainer.mainContext) }
            let backupFile = try time("portable file: read everything into a backup (main thread)") { try DataBackup.make(from: container.mainContext) }
            let backupJSON = try time("portable file: turn it into JSON (main thread)") { try DataBackup.plainJSON(backupFile) }
            NSLog("TIMING: the JSON is \(backupJSON.count / 1_000_000) MB")
            // The two ways must give the same transactions
            func canonical(_ records: [BackupFile.TransactionRecord]) throws -> Data {
                let ordered = records.sorted { ($0.accountID, $0.date, $0.createdAt, $0.payee, $0.amount) < ($1.accountID, $1.date, $1.createdAt, $1.payee, $1.amount) }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                encoder.outputFormatting = [.sortedKeys]
                return try encoder.encode(ordered)
            }
            NSLog("TIMING: the fast and the slow way give the same transactions: \(try canonical(slowRecords) == canonical(backupFile.transactions))")
            let backupCopy = ShadowFolder(inside: root.appendingPathComponent("backup-copy", isDirectory: true))
            let snapshotInfo = try time("backup copy: snapshot and seal (background)") { try backupCopy.write(from: big, dataID: "timing", source: "This Mac", appVersion: "1.0") }
            try time("backup copy: seal and write the portable file (background)") { try backupCopy.writePortable(json: backupJSON, info: DataBackup.portableInfo(backupFile), matching: snapshotInfo, appVersion: "1.0") }
            func kilobytes(_ url: URL?) -> Int { url.flatMap { try? manager.attributesOfItem(atPath: $0.path)[.size] as? Int }.map { $0 / 1_000 } ?? 0 }
            NSLog("TIMING: sealed snapshot \(kilobytes(backupCopy.storeURL)) KB, sealed portable file \(kilobytes(backupCopy.portableVersions().first?.url)) KB")

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
