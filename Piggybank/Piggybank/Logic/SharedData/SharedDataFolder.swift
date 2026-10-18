import Foundation
import SQLite3

/// Who has the shared data folder open. Written beside the data file while one copy of the app is using it.
nonisolated struct SharedLock: Codable, Equatable, Sendable {
    /// Identifies one running copy of the app, so a lock can tell its owner from anyone else.
    var token: String
    var userName: String
    var fullName: String
    var since: Date
    /// Refreshed every minute while the app runs. A lock whose heartbeat has stopped is stale.
    var heartbeat: Date
    /// Which process and Mac wrote the lock. When it is this Mac, a process that no longer exists proves the lock is
    /// left over from a crash, without waiting for the heartbeat to go quiet.
    var pid: Int32?
    var host: String?

    func isStale(now: Date = .now) -> Bool { now.timeIntervalSince(heartbeat) > SharedDataFolder.staleAfter }

    /// The app that wrote this lock is no longer running on this Mac.
    func ownerIsGone(hostName: String = ProcessInfo.processInfo.hostName) -> Bool {
        guard let pid, pid > 0, host == hostName else { return false }
        // Signal 0 only checks. ESRCH means no such process; EPERM means it exists but belongs to another login.
        return kill(pid, 0) == -1 && errno == ESRCH
    }
}

/// About the finished data file: when it was last saved and by whom.
nonisolated struct SharedInfo: Codable, Equatable, Sendable {
    var formatVersion: Int
    var savedAt: Date
    var savedBy: String
    var appVersion: String
}

nonisolated enum SharedDataError: LocalizedError {
    case folderUnavailable
    case notAnOinklyFolder
    case newerFormat
    case copyFailed(String)
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .folderUnavailable: "The shared folder can't be found or can't be written to. Check that it is still there and that this Mac login may change it."
        case .notAnOinklyFolder: "That folder doesn't hold OinklyBudget data."
        case .newerFormat: "That data was saved by a newer version of OinklyBudget. Update the app and try again."
        case .copyFailed(let why): "The data couldn't be copied: \(why)"
        case .verifyFailed(let why): "The copy didn't pass its safety check, so nothing was changed: \(why)"
        }
    }
}

/// A folder two Mac logins share. It holds one finished data file, a lock saying who has it open, and a note about the
/// last save. The data file is only ever a complete, closed file: a person works on a private copy and the app writes
/// that copy back in one safe step. SQLite's side files never exist in the shared folder, so two logins can't corrupt
/// each other's database.
///
/// Everything here uses plain files and the system's own SQLite. It knows nothing about the app's models.
nonisolated struct SharedDataFolder: Sendable {
    let url: URL

    static let storeName = "OinklyBudget.store"
    static let lockName = "lock.json"
    static let infoName = "info.json"
    static let previousName = "OinklyBudget (previous save).store"
    static let formatVersion = 1
    /// A lock is stale once its heartbeat is this old, in seconds. The app refreshes it every 60.
    static let staleAfter: TimeInterval = 180

    var storeURL: URL { url.appendingPathComponent(Self.storeName) }
    var lockURL: URL { url.appendingPathComponent(Self.lockName) }
    var infoURL: URL { url.appendingPathComponent(Self.infoName) }
    var previousURL: URL { url.appendingPathComponent(Self.previousName) }

    private var manager: FileManager { .default }

    var hasStore: Bool { manager.fileExists(atPath: storeURL.path) }

    // MARK: Info and lock

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func readInfo() -> SharedInfo? {
        guard let data = try? Data(contentsOf: infoURL) else { return nil }
        return try? Self.decoder.decode(SharedInfo.self, from: data)
    }

    private func writeInfo(_ info: SharedInfo) throws {
        try write(Self.encoder.encode(info), to: infoURL)
    }

    func readLock() -> SharedLock? {
        guard let data = try? Data(contentsOf: lockURL) else { return nil }
        return try? Self.decoder.decode(SharedLock.self, from: data)
    }

    private func writeLock(_ lock: SharedLock) throws {
        try write(Self.encoder.encode(lock), to: lockURL)
    }

    /// Writes through a temporary file and renames it, so a reader never sees half a file. The file is made readable
    /// and writable by every login, because the next person to use the folder is a different login.
    private func write(_ data: Data, to destination: URL) throws {
        let temporary = url.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: temporary.path)
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw SharedDataError.copyFailed(error.localizedDescription)
        }
    }

    enum LockResult: Equatable {
        case acquired
        /// Someone else has it. `isStale` says their heartbeat stopped, so they may have crashed.
        case heldBy(SharedLock, isStale: Bool)
    }

    /// Takes the lock for `me`. If another copy holds it, nothing changes unless `takeOver` is true and that lock is stale.
    func acquire(_ me: SharedLock, takeOver: Bool = false, now: Date = .now) throws -> LockResult {
        guard manager.fileExists(atPath: url.path) else { throw SharedDataError.folderUnavailable }
        if let current = readLock(), current.token != me.token {
            let stale = current.isStale(now: now) || current.ownerIsGone()
            if !(takeOver && stale) { return .heldBy(current, isStale: stale) }
        }
        try writeLock(me)
        // Two copies starting at the same instant could both write. Look again: the last writer wins, and the other
        // sees it here.
        Thread.sleep(forTimeInterval: 0.15)
        if let after = readLock(), after.token != me.token { return .heldBy(after, isStale: after.isStale(now: now) || after.ownerIsGone()) }
        return .acquired
    }

    /// Shows the lock is still in use. False when someone else has taken it over.
    @discardableResult
    func refresh(_ me: SharedLock, now: Date = .now) -> Bool {
        guard let current = readLock(), current.token == me.token else { return false }
        var updated = current
        updated.heartbeat = now
        return (try? writeLock(updated)) != nil
    }

    /// Lets go of the lock, but only if it is still ours.
    func release(token: String) {
        guard let current = readLock(), current.token == token else { return }
        try? manager.removeItem(at: lockURL)
    }

    // MARK: Check out

    /// Copies the finished data file to a private working copy, replacing whatever was there.
    func checkOut(to working: URL) throws {
        guard hasStore else { throw SharedDataError.notAnOinklyFolder }
        if let info = readInfo(), info.formatVersion > Self.formatVersion { throw SharedDataError.newerFormat }
        try Self.removeStore(at: working)
        try manager.createDirectory(at: working.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try manager.copyItem(at: storeURL, to: working)
            try Self.copyAttachments(from: storeURL, to: working)
        } catch {
            throw SharedDataError.copyFailed(error.localizedDescription)
        }
        // The copy is checked against the original before anyone works on it.
        let original = try SQLiteStore.counts(of: storeURL)
        let copy = try SQLiteStore.counts(of: working)
        guard original == copy else { throw SharedDataError.verifyFailed("the copy's record counts differ from the shared file") }
    }

    // MARK: Check in

    /// Writes the working copy back as the new finished data file, in one safe replace. The previous finished file is
    /// kept beside it as one step of undo. If anything fails, the shared file is left exactly as it was.
    func checkIn(from working: URL, by name: String, appVersion: String, now: Date = .now) throws {
        guard manager.fileExists(atPath: url.path) else { throw SharedDataError.folderUnavailable }
        let temporary = url.appendingPathComponent(".\(Self.storeName).\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        try SQLiteStore.vacuum(source: working, into: temporary)
        let expected = try SQLiteStore.counts(of: working)
        let actual = try SQLiteStore.counts(of: temporary)
        guard expected == actual else { throw SharedDataError.verifyFailed("record counts differ after copying") }
        guard try SQLiteStore.integrityIsOK(temporary) else { throw SharedDataError.verifyFailed("the database failed its integrity check") }
        try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: temporary.path)
        // Attachments go first. Until the database is replaced, nothing refers to the new ones, so a failure here
        // leaves the shared data exactly as it was.
        try Self.copyAttachments(from: working, to: storeURL)

        if hasStore {
            try? manager.removeItem(at: previousURL)
            try? manager.copyItem(at: storeURL, to: previousURL)
            try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: previousURL.path)
            _ = try manager.replaceItemAt(storeURL, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: storeURL)
        }
        try writeInfo(SharedInfo(formatVersion: Self.formatVersion, savedAt: now, savedBy: name, appVersion: appVersion))
    }

    /// Makes a brand new shared folder from a database that already exists (this Mac's own data). The original is
    /// only read, never changed.
    func createStore(from source: URL, by name: String, appVersion: String) throws {
        guard manager.fileExists(atPath: url.path) else { throw SharedDataError.folderUnavailable }
        try? manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: url.path)
        try checkIn(from: source, by: name, appVersion: appVersion)
    }

    /// Where a copy goes when it can't safely replace the shared file, such as after a crash while someone else saved.
    func saveRecoveredCopy(from working: URL, now: Date = .now) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let destination = url.appendingPathComponent("OinklyBudget (recovered \(stamp)).store")
        try SQLiteStore.vacuum(source: working, into: destination)
        try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: destination.path)
        try Self.copyAttachments(from: working, to: destination)
        return destination
    }

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
        try? manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: destination.path)
        guard let walker = manager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let item as URL in walker {
            let relative = String(item.path.dropFirst(source.path.count))
            let target = URL(fileURLWithPath: destination.path + relative)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
                try? manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: target.path)
            } else if !manager.fileExists(atPath: target.path) {
                try manager.copyItem(at: item, to: target)
                try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: target.path)
            }
        }
    }

    /// Removes a store, the side files SQLite keeps beside it while it is open, and its attachments.
    static func removeStore(at store: URL) throws {
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: store.path + suffix)
            if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
        }
        let support = supportURL(for: store)
        if manager.fileExists(atPath: support.path) { try manager.removeItem(at: support) }
    }
}

/// Reading and copying an SQLite database with the system's own SQLite. A database that is open in the app can be
/// copied safely: `VACUUM INTO` writes a complete, consistent file with no side files.
nonisolated enum SQLiteStore {
    private static func open(_ url: URL, readOnly: Bool) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open the file"
            if let handle { sqlite3_close(handle) }
            throw SharedDataError.copyFailed(message)
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
            throw SharedDataError.copyFailed(message)
        }
    }

    /// The number of rows in every data table, by table name. Two copies of the same data have the same counts.
    static func counts(of url: URL) throws -> [String: Int] {
        let db = try open(url, readOnly: true)
        defer { sqlite3_close(db) }
        var tables: [String] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' AND name NOT LIKE 'Z\\_%' ESCAPE '\\'", -1, &statement, nil) == SQLITE_OK else {
            throw SharedDataError.verifyFailed(String(cString: sqlite3_errmsg(db)))
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

    static func integrityIsOK(_ url: URL) throws -> Bool {
        let db = try open(url, readOnly: true)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW && String(cString: sqlite3_column_text(statement, 0)) == "ok"
    }
}
