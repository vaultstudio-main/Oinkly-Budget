import Foundation
import SQLite3

/// Working with the database file and the attachments that live beside it, using plain files and the system's own
/// SQLite. It knows nothing about the app's models. A database that is open in the app can be copied safely:
/// `VACUUM INTO` writes a complete, consistent file with no side files.
nonisolated enum StoreError: LocalizedError {
    case failed(String)
    var errorDescription: String? { switch self { case .failed(let why): why } }
}

nonisolated enum StoreFiles {
    /// Where SwiftData keeps large attachments (receipts, photos) for a store: a hidden folder beside it named after
    /// the store. They are not inside the database file, so they have to travel with it.
    static func supportURL(for store: URL) -> URL {
        store.deletingLastPathComponent().appendingPathComponent("." + store.deletingPathExtension().lastPathComponent + "_SUPPORT")
    }

    /// Adds any attachment files the destination doesn't have yet. Attachments never change once written (each has its
    /// own unique name), so copying only the new ones is safe and can be repeated.
    static func copyAttachments(from sourceStore: URL, to destinationStore: URL) throws {
        let manager = FileManager.default
        let source = supportURL(for: sourceStore)
        guard manager.fileExists(atPath: source.path) else { return }
        let destination = supportURL(for: destinationStore)
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let walker = manager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let item as URL in walker {
            let relative = String(item.path.dropFirst(source.path.count))
            let target = URL(fileURLWithPath: destination.path + relative)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if !manager.fileExists(atPath: target.path) {
                try manager.copyItem(at: item, to: target)
            }
        }
    }

    /// Removes a store, the side files SQLite keeps beside it while it is open, and its attachments.
    static func remove(store: URL) {
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? manager.removeItem(at: URL(fileURLWithPath: store.path + suffix))
        }
        try? manager.removeItem(at: supportURL(for: store))
    }

    /// A consistent copy of a live store and its attachments, written into `directory` as OinklyBudget.store. The copy
    /// is checked against the original before it is trusted.
    static func snapshot(of live: URL, into directory: URL) throws -> URL {
        let manager = FileManager.default
        try? manager.removeItem(at: directory)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = directory.appendingPathComponent("OinklyBudget.store")
        try SQLiteStore.vacuum(source: live, into: copy)
        try copyAttachments(from: live, to: copy)
        let expected = try SQLiteStore.counts(of: live)
        let actual = try SQLiteStore.counts(of: copy)
        guard expected == actual else { throw StoreError.failed("The copy's record counts didn't match, so nothing was changed.") }
        guard try SQLiteStore.integrityIsOK(copy) else { throw StoreError.failed("The copy failed its integrity check, so nothing was changed.") }
        return copy
    }
}

nonisolated enum SQLiteStore {
    private static func open(_ url: URL, readOnly: Bool) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open the file"
            if let handle { sqlite3_close(handle) }
            throw StoreError.failed("The database couldn't be opened: \(message)")
        }
        sqlite3_busy_timeout(handle, 5000)
        return handle
    }

    static func vacuum(source: URL, into destination: URL) throws {
        let db = try open(source, readOnly: false)
        defer { sqlite3_close(db) }
        try? FileManager.default.removeItem(at: destination)
        let quoted = destination.path.replacingOccurrences(of: "'", with: "''")
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, "VACUUM INTO '\(quoted)'", nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw StoreError.failed("The database couldn't be copied: \(message)")
        }
    }

    /// The number of rows in every data table, by table name. Two copies of the same data have the same counts.
    static func counts(of url: URL) throws -> [String: Int] {
        let db = try open(url, readOnly: true)
        defer { sqlite3_close(db) }
        var tables: [String] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' AND name NOT LIKE 'Z\\_%' ESCAPE '\\'", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.failed(String(cString: sqlite3_errmsg(db)))
        }
        while sqlite3_step(statement) == SQLITE_ROW { tables.append(String(cString: sqlite3_column_text(statement, 0))) }
        sqlite3_finalize(statement)

        var result: [String: Int] = [:]
        for table in tables {
            var count: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \"\(table)\"", -1, &count, nil) == SQLITE_OK else { continue }
            if sqlite3_step(count) == SQLITE_ROW { result[table] = Int(sqlite3_column_int64(count, 0)) }
            sqlite3_finalize(count)
        }
        return result
    }

    /// The names of the attachment files this database points to. SwiftData keeps a large receipt or photo in a file
    /// beside the database and stores a short pointer to it in the column: a 0x02 byte, the file's name (a UUID, 36
    /// characters) and a 0x00 byte. Smaller ones sit inside the column itself and have no file. Every data column of every
    /// table is looked at, so a receipt, an account photo or anything added later is covered.
    static func attachmentReferences(of url: URL) throws -> Set<String> {
        let db = try open(url, readOnly: true)
        defer { sqlite3_close(db) }
        var pairs: [(table: String, column: String)] = []
        var statement: OpaquePointer?
        let find = """
        SELECT m.name, p.name FROM sqlite_master m, pragma_table_info(m.name) p
        WHERE m.type = 'table' AND m.name LIKE 'Z%' AND m.name NOT LIKE 'Z\\_%' ESCAPE '\\' AND upper(p.type) = 'BLOB'
        """
        guard sqlite3_prepare_v2(db, find, -1, &statement, nil) == SQLITE_OK else { throw StoreError.failed(String(cString: sqlite3_errmsg(db))) }
        while sqlite3_step(statement) == SQLITE_ROW {
            pairs.append((String(cString: sqlite3_column_text(statement, 0)), String(cString: sqlite3_column_text(statement, 1))))
        }
        sqlite3_finalize(statement)

        var names = Set<String>()
        for (table, column) in pairs {
            var rows: OpaquePointer?
            let query = "SELECT \"\(column)\" FROM \"\(table)\" WHERE typeof(\"\(column)\") = 'blob' AND length(\"\(column)\") = 38"
            guard sqlite3_prepare_v2(db, query, -1, &rows, nil) == SQLITE_OK else { throw StoreError.failed(String(cString: sqlite3_errmsg(db))) }
            while sqlite3_step(rows) == SQLITE_ROW {
                guard let bytes = sqlite3_column_blob(rows, 0), sqlite3_column_bytes(rows, 0) == 38 else { continue }
                let data = Data(bytes: bytes, count: 38)
                guard data.first == 0x02, data.last == 0x00, let name = String(data: data.subdata(in: 1..<37), encoding: .ascii) else { continue }
                names.insert(name)
            }
            sqlite3_finalize(rows)
        }
        return names
    }

    static func integrityIsOK(_ url: URL) throws -> Bool {
        let db = try open(url, readOnly: true)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW && String(cString: sqlite3_column_text(statement, 0)) == "ok"
    }
}
