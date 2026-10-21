import Foundation
import Darwin

/// Who has the shared data open. Written beside the data file while one copy of the app is using it.
nonisolated struct SharedLock: Codable, Equatable, Sendable {
    /// Identifies one running copy of the app, so a lock can tell its owner from anyone else.
    var token: String
    var userName: String
    var fullName: String
    var since: Date
    /// Refreshed every minute while the app runs. A lock whose heartbeat has stopped is stale.
    var heartbeat: Date
    /// Which process and Mac wrote the lock. When it is this Mac and that process no longer exists, the lock was left by
    /// a crash and doesn't need to wait for the heartbeat to go quiet.
    var pid: Int32?
    var host: String?

    /// The name to show: the person's full name, or their account name.
    var displayName: String { fullName.isEmpty ? userName : fullName }

    func isStale(now: Date = .now) -> Bool { now.timeIntervalSince(heartbeat) > SharedDataFolder.staleAfter || ownerIsGone() }

    /// The app that wrote this lock is no longer running on this Mac. From the sandbox the check may not be allowed
    /// (it answers "not permitted" for another login's process); then only the heartbeat decides.
    func ownerIsGone(hostName: String = ProcessInfo.processInfo.hostName) -> Bool {
        guard let pid, pid > 0, host == hostName else { return false }
        return kill(pid, 0) == -1 && errno == ESRCH
    }
}

/// About the finished data file: when it was last saved and by whom.
nonisolated struct SharedInfo: Codable, Equatable, Sendable {
    var formatVersion: Int
    /// The database shape (PiggybankSchemaV2 is 2). An older app refuses newer data.
    var schemaVersion: Int
    /// Goes up by one at every save, so two copies can tell whether the file changed while they were away.
    var revision: Int
    var savedAt: Date
    var savedBy: String
    var appVersion: String
    /// Names this particular data. A folder swapped for a different one is noticed.
    var fileID: String
}

/// One earlier finished save kept in the `previous saves` folder.
nonisolated struct SharedVersion: Identifiable, Equatable, Sendable {
    var url: URL
    var info: SharedInfo
    var id: URL { url }
}

nonisolated enum SharedDataError: LocalizedError {
    case folderUnavailable(String)
    case notOpenToEveryone(String)
    case newerFormat
    case copyFailed(String)
    case verifyFailed(String)
    /// Someone else saved into the shared file while this copy was out.
    case changedMeanwhile

    var errorDescription: String? {
        switch self {
        case .folderUnavailable(let why): "The shared folder can't be used: \(why)"
        case .notOpenToEveryone(let why): "The shared folder isn't open to every user on this Mac: \(why)"
        case .newerFormat: "That data was saved by a newer version of Oinkly Budget. Update the app and try again."
        case .copyFailed(let why): "The data couldn't be copied: \(why)"
        case .verifyFailed(let why): "The copy didn't pass its safety check, so nothing was changed: \(why)"
        case .changedMeanwhile: "The shared data was saved by someone else while this copy was open."
        }
    }
}

/// The folder every Mac login shares: `/Users/Shared/OinklyBudget`. It holds one finished data file, a lock saying who
/// has it open, and a note about the last save. The data file is only ever a complete, closed file: a person works on a
/// private copy and the app writes that copy back in one safe step. SQLite's side files never exist in the shared
/// folder, so two logins can't corrupt each other's database.
///
/// Everything here uses plain files and the system's own SQLite. It knows nothing about the app's models.
nonisolated struct SharedDataFolder: Sendable {
    let url: URL

    /// The one place sharing happens. The app has a sandbox exception for exactly this folder.
    static let defaultURL = URL(fileURLWithPath: "/Users/Shared/OinklyBudget", isDirectory: true)
    static var standard: SharedDataFolder { SharedDataFolder(url: defaultURL) }

    static let storeName = "OinklyBudget.store"
    static let lockName = "lock.json"
    static let infoName = "info.json"
    static let previousName = "OinklyBudget (previous save).store"
    static let historyName = "previous saves"
    static let logName = "save log.txt"
    /// How many of the newest saves are kept, and how many days back one save per day is kept as well.
    static let keepNewest = 5
    static let keepDays = 7
    static let formatVersion = 1
    static let schemaVersion = 2
    /// A lock is stale once its heartbeat is this old, in seconds. The app refreshes it every 60.
    static let staleAfter: TimeInterval = 180

    var storeURL: URL { url.appendingPathComponent(Self.storeName) }
    var lockURL: URL { url.appendingPathComponent(Self.lockName) }
    var infoURL: URL { url.appendingPathComponent(Self.infoName) }
    var previousURL: URL { url.appendingPathComponent(Self.previousName) }
    var historyURL: URL { url.appendingPathComponent(Self.historyName) }
    var logURL: URL { url.appendingPathComponent(Self.logName) }

    private var manager: FileManager { .default }

    var exists: Bool { manager.fileExists(atPath: url.path) }
    var hasStore: Bool { manager.fileExists(atPath: storeURL.path) }
    var hasData: Bool { hasStore }

    // MARK: The folder itself

    /// Makes the folder if it isn't there, open to every login (not sticky, so one login can replace another's files).
    func ensureFolder() throws {
        if !exists {
            guard mkdir(url.path, 0o777) == 0 else {
                throw SharedDataError.folderUnavailable("it couldn't be created (\(String(cString: strerror(errno))))")
            }
            chmod(url.path, 0o777)
        }
        var info = stat()
        guard stat(url.path, &info) == 0 else { throw SharedDataError.folderUnavailable("it couldn't be read") }
        let mode = info.st_mode & 0o7777
        guard info.st_mode & S_IFMT == S_IFDIR else { throw SharedDataError.folderUnavailable("it isn't a folder") }
        if mode & 0o1000 != 0 || mode & 0o777 != 0o777 {
            // Only the login that made the folder may change its permissions. Try; if it isn't allowed, say what's wrong.
            if info.st_uid == getuid() { chmod(url.path, 0o777) }
            var after = stat()
            stat(url.path, &after)
            let now = after.st_mode & 0o7777
            if now & 0o1000 != 0 || now & 0o777 != 0o777 {
                let owner = getpwuid(info.st_uid).map { String(cString: $0.pointee.pw_name) } ?? "another user"
                throw SharedDataError.notOpenToEveryone("it belongs to \(owner) with permissions \(String(now, radix: 8)). It needs to be open to every user (777, not sticky).")
            }
        }
    }

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

    /// When the lock file last changed. Used when the lock can't be read, for example while it is still being written.
    private func lockFileAge(now: Date) -> TimeInterval? {
        guard let attributes = try? manager.attributesOfItem(atPath: lockURL.path), let modified = attributes[.modificationDate] as? Date else { return nil }
        return now.timeIntervalSince(modified)
    }

    /// Writes through a temporary file and renames it, so a reader never sees half a file. The file is made readable
    /// and writable by every login, because the next person to use the folder is a different login.
    private func write(_ data: Data, to destination: URL) throws {
        let temporary = url.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: temporary.path)
            if rename(temporary.path, destination.path) != 0 {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
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

    /// Takes the lock for `me`. Creating the file exclusively means only one login can win when two start together. If
    /// another copy holds it, nothing changes unless `takeOver` is true and that lock is stale.
    func acquire(_ me: SharedLock, takeOver: Bool = false, now: Date = .now) throws -> LockResult {
        guard exists else { throw SharedDataError.folderUnavailable("it can't be found") }
        let body = try Self.encoder.encode(me)
        let handle = open(lockURL.path, O_CREAT | O_EXCL | O_WRONLY, 0o666)
        if handle >= 0 {
            _ = body.withUnsafeBytes { Darwin.write(handle, $0.baseAddress, body.count) }
            close(handle)
            chmod(lockURL.path, 0o666)
            return .acquired
        }
        guard errno == EEXIST else { throw SharedDataError.folderUnavailable("the lock couldn't be created (\(String(cString: strerror(errno))))") }

        guard let current = readLock() else {
            // The file exists but can't be read: it is being written right now, or it is damaged. Fresh means in use.
            let age = lockFileAge(now: now) ?? 0
            let unknown = SharedLock(token: "unreadable", userName: "another user", fullName: "", since: now.addingTimeInterval(-age), heartbeat: now.addingTimeInterval(-age))
            let stale = age > Self.staleAfter
            if takeOver && stale { try write(body, to: lockURL); return .acquired }
            return .heldBy(unknown, isStale: stale)
        }
        if current.token == me.token { return .acquired }
        let stale = current.isStale(now: now)
        guard takeOver && stale else { return .heldBy(current, isStale: stale) }
        // Replace the stale lock, but only if it is still the one we looked at.
        guard readLock()?.token == current.token else { return .heldBy(readLock() ?? current, isStale: false) }
        try write(body, to: lockURL)
        return .acquired
    }

    /// Shows the lock is still in use. False when someone else has taken it over.
    @discardableResult
    func refresh(_ me: SharedLock, now: Date = .now) -> Bool {
        guard let current = readLock(), current.token == me.token else { return false }
        var updated = current
        updated.heartbeat = now
        return (try? write(Self.encoder.encode(updated), to: lockURL)) != nil
    }

    /// Whether the lock is still this copy's.
    func holds(token: String) -> Bool { readLock()?.token == token }

    /// Lets go of the lock, but only if it is still ours.
    func release(token: String) {
        guard readLock()?.token == token else { return }
        try? manager.removeItem(at: lockURL)
    }

    // MARK: Check out

    /// Copies the finished data file to a private working copy, replacing whatever was there. Returns what was copied.
    @discardableResult
    func checkOut(to working: URL) throws -> SharedInfo? {
        let info = readInfo()
        if let info, info.formatVersion > Self.formatVersion || info.schemaVersion > Self.schemaVersion { throw SharedDataError.newerFormat }
        guard hasStore else { throw SharedDataError.folderUnavailable("it has no data file") }
        StoreFiles.remove(store: working)
        try manager.createDirectory(at: working.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try manager.copyItem(at: storeURL, to: working)
            try StoreFiles.copyAttachments(from: storeURL, to: working)
        } catch {
            throw SharedDataError.copyFailed(error.localizedDescription)
        }
        // The copy is checked against the original before anyone works on it.
        do {
            let original = try SQLiteStore.counts(of: storeURL)
            let copy = try SQLiteStore.counts(of: working)
            guard original == copy else { throw SharedDataError.verifyFailed("the copy's record counts differ from the shared file") }
        } catch let error as SharedDataError {
            throw error
        } catch {
            throw SharedDataError.verifyFailed(error.localizedDescription)
        }
        return info
    }

    // MARK: Check in

    /// Writes the working copy back as the new finished data file, in one safe replace. The previous finished file is
    /// kept beside it as one step of undo. If anything fails, the shared file is left exactly as it was.
    /// `baseRevision` is the revision this copy was checked out from; if the shared file has moved on, nothing is written.
    @discardableResult
    func checkIn(from working: URL, baseRevision: Int?, by name: String, appVersion: String, now: Date = .now) throws -> SharedInfo {
        guard exists else { throw SharedDataError.folderUnavailable("it can't be found") }
        let current = readInfo()
        if let baseRevision, let current, current.revision != baseRevision { throw SharedDataError.changedMeanwhile }
        let temporary = url.appendingPathComponent(".\(Self.storeName).\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        do {
            try SQLiteStore.vacuum(source: working, into: temporary)
            let expected = try SQLiteStore.counts(of: working)
            let actual = try SQLiteStore.counts(of: temporary)
            guard expected == actual else { throw SharedDataError.verifyFailed("record counts differ after copying") }
            guard try SQLiteStore.integrityIsOK(temporary) else { throw SharedDataError.verifyFailed("the database failed its integrity check") }
        } catch let error as SharedDataError {
            throw error
        } catch {
            throw SharedDataError.verifyFailed(error.localizedDescription)
        }
        try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: temporary.path)
        // Attachments go first. Until the database is replaced, nothing refers to the new ones, so a failure here
        // leaves the shared data exactly as it was.
        try Self.copyAttachments(from: working, to: storeURL)

        if hasStore { archive(current: current, now: now) }
        if rename(temporary.path, storeURL.path) != 0 {
            throw SharedDataError.copyFailed("the new file couldn't replace the old one (\(String(cString: strerror(errno))))")
        }
        let info = SharedInfo(formatVersion: Self.formatVersion, schemaVersion: Self.schemaVersion, revision: (current?.revision ?? 0) + 1,
                              savedAt: now, savedBy: name, appVersion: appVersion, fileID: current?.fileID ?? UUID().uuidString)
        try writeInfo(info)
        appendLog("saved by \(name) as save number \(info.revision) (Oinkly Budget \(appVersion))", now: now)
        return info
    }

    // MARK: Previous saves and the save log

    /// Keeps the file that is about to be replaced, with a note of who saved it and when, then trims the old ones.
    /// A failure here never stops the new save.
    private func archive(current: SharedInfo?, now: Date) {
        try? manager.removeItem(at: previousURL)
        do {
            if !manager.fileExists(atPath: historyURL.path) {
                try manager.createDirectory(at: historyURL, withIntermediateDirectories: true)
                chmod(historyURL.path, 0o777)
            }
            let modified = (try? manager.attributesOfItem(atPath: storeURL.path)[.modificationDate] as? Date) ?? now
            let info = current ?? SharedInfo(formatVersion: Self.formatVersion, schemaVersion: Self.schemaVersion, revision: 0, savedAt: modified,
                                             savedBy: "unknown", appVersion: "", fileID: "")
            let stamp = ISO8601DateFormatter().string(from: info.savedAt).replacingOccurrences(of: ":", with: "-")
            let base = historyURL.appendingPathComponent("save \(info.revision) \(stamp)")
            let copy = base.appendingPathExtension("store")
            try? manager.removeItem(at: copy)
            try manager.copyItem(at: storeURL, to: copy)
            try Self.encoder.encode(info).write(to: base.appendingPathExtension("json"))
            for file in [copy, base.appendingPathExtension("json")] { try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: file.path) }
        } catch {
            appendLog("couldn't keep the previous save: \(error.localizedDescription)", now: now)
        }
        pruneHistory(now: now)
    }

    /// The earlier saves, newest first.
    func versions() -> [SharedVersion] {
        guard let files = try? manager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "store" }.compactMap { store in
            guard let data = try? Data(contentsOf: store.deletingPathExtension().appendingPathExtension("json")),
                  let info = try? Self.decoder.decode(SharedInfo.self, from: data) else { return nil }
            return SharedVersion(url: store, info: info)
        }.sorted { $0.info.savedAt > $1.info.savedAt }
    }

    /// Keeps the newest few saves, plus the newest save of each of the last few days. Everything else is removed.
    func pruneHistory(now: Date = .now, calendar: Calendar = .current) {
        let all = versions()
        var keep = Set(all.prefix(Self.keepNewest).map(\.url))
        let cutoff = calendar.startOfDay(for: now).addingTimeInterval(-Double(Self.keepDays - 1) * 86_400)
        var seenDays = Set<Date>()
        for version in all where version.info.savedAt >= cutoff {
            if seenDays.insert(calendar.startOfDay(for: version.info.savedAt)).inserted { keep.insert(version.url) }
        }
        for version in all where !keep.contains(version.url) {
            try? manager.removeItem(at: version.url)
            try? manager.removeItem(at: version.url.deletingPathExtension().appendingPathExtension("json"))
        }
    }

    /// One line per save, newest at the end. Kept short so it never grows without limit.
    func appendLog(_ text: String, now: Date = .now) {
        let line = "\(now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))  \(now.formatted(date: .omitted, time: .standard))  \(text)"
        var lines = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        lines.append(line)
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
        try? write(Data((lines.joined(separator: "\n") + "\n").utf8), to: logURL)
    }

    func recentLog(_ count: Int = 5) -> [String] {
        ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").split(separator: "\n").suffix(count).map(String.init)
    }

    /// Makes a brand new shared folder from a database that already exists (this Mac's own data). The original is only
    /// read, never changed.
    func createStore(from source: URL, by name: String, appVersion: String) throws {
        try ensureFolder()
        try checkIn(from: source, baseRevision: nil, by: name, appVersion: appVersion)
    }

    /// Where a copy goes when it can't safely replace the shared file, such as after a crash while someone else saved.
    func saveRecoveredCopy(from working: URL, now: Date = .now) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let destination = url.appendingPathComponent("OinklyBudget (recovered \(stamp)).store")
        try SQLiteStore.vacuum(source: working, into: destination)
        try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: destination.path)
        try Self.copyAttachments(from: working, to: destination)
        appendLog("kept unsaved changes as \(destination.lastPathComponent)", now: now)
        return destination
    }

    /// Adds any attachment files the destination doesn't have yet, and makes them readable and writable by every login.
    static func copyAttachments(from sourceStore: URL, to destinationStore: URL) throws {
        do { try StoreFiles.copyAttachments(from: sourceStore, to: destinationStore) } catch { throw SharedDataError.copyFailed(error.localizedDescription) }
        openUp(StoreFiles.supportURL(for: destinationStore))
    }

    /// Opens everything under a folder to every login, so the next person can add to it and replace files in it.
    private static func openUp(_ root: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return }
        try? manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.path)
        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let item as URL in walker {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try? manager.setAttributes([.posixPermissions: isDirectory ? 0o777 : 0o666], ofItemAtPath: item.path)
        }
    }

    // MARK: Check Sharing

    /// A plain-words report on the folder, for when something doesn't work.
    func diagnose(now: Date = .now) -> [String] {
        var lines: [String] = []
        func describe(_ path: String) -> String {
            var info = stat()
            guard lstat(path, &info) == 0 else { return "missing" }
            let owner = getpwuid(info.st_uid).map { String(cString: $0.pointee.pw_name) } ?? "uid \(info.st_uid)"
            return "owner \(owner), permissions \(String(info.st_mode & 0o7777, radix: 8))"
        }
        lines.append("Folder: \(url.path)")
        guard exists else { return lines + ["The folder doesn't exist yet. It is made when sharing is turned on."] }
        lines.append("Folder: \(describe(url.path))")
        var folder = stat()
        stat(url.path, &folder)
        let mode = folder.st_mode & 0o7777
        lines.append(mode & 0o1000 == 0 && mode & 0o777 == 0o777 ? "OK: open to every user." : "PROBLEM: it must be open to every user (777, not sticky).")
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeAvailableCapacityForImportantUsageKey])
        lines.append(values?.volumeIsLocal == true ? "OK: on this Mac's own disk." : "PROBLEM: not on this Mac's own disk.")
        if let free = values?.volumeAvailableCapacityForImportantUsage { lines.append("Free space: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)).") }

        // Can this login create, rename and delete a file here?
        let probe = url.appendingPathComponent(".check-\(UUID().uuidString)")
        let renamed = probe.appendingPathExtension("moved")
        if manager.createFile(atPath: probe.path, contents: Data("check".utf8)) {
            lines.append(rename(probe.path, renamed.path) == 0 ? "OK: this login can create and rename files here." : "PROBLEM: this login can't rename files here.")
            try? manager.removeItem(at: probe)
            if unlink(renamed.path) == 0 || !manager.fileExists(atPath: renamed.path) { lines.append("OK: and delete them.") } else { lines.append("PROBLEM: this login can't delete files here.") }
        } else {
            lines.append("PROBLEM: this login can't create files here (\(String(cString: strerror(errno)))).")
        }
        lines.append("Data file: \(hasStore ? describe(storeURL.path) : "none yet")")
        if let info = readInfo() {
            lines.append("Last saved: \(info.savedAt.formatted(date: .abbreviated, time: .shortened)) by \(info.savedBy), save number \(info.revision), schema \(info.schemaVersion).")
        }
        if let lock = readLock() {
            let quiet = Int(now.timeIntervalSince(lock.heartbeat))
            lines.append("In use by \(lock.displayName) since \(lock.since.formatted(date: .omitted, time: .shortened)); last sign of life \(quiet) seconds ago\(lock.isStale(now: now) ? " (stale)" : "").")
        } else {
            lines.append("Not in use.")
        }
        let saves = versions()
        lines.append(saves.isEmpty ? "No previous saves yet." : "\(saves.count) previous save\(saves.count == 1 ? " is" : "s are") kept, the newest from \(saves[0].info.savedAt.formatted(date: .abbreviated, time: .shortened)).")
        for entry in recentLog() { lines.append("Log: \(entry)") }
        return lines
    }
}
