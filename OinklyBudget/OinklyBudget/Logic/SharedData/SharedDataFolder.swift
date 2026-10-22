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
    /// The database shape (OinklyBudgetSchemaV7 is 7). An older app refuses newer data.
    var schemaVersion: Int
    /// Goes up by one at every save, so two copies can tell whether the file changed while they were away.
    var revision: Int
    var savedAt: Date
    var savedBy: String
    var appVersion: String
    /// Names this particular data. A folder swapped for a different one is noticed.
    var fileID: String
    /// How many records each table of this save holds, so a copy can be checked without opening the original. Nil in
    /// notes from before it was kept.
    var counts: [String: Int]?
    /// The receipt and photo files this save uses, so unused ones can be cleaned up without opening every save. Nil when
    /// that isn't known.
    var attachments: [String]?
}

/// A login that uses the shared data. Each one leaves a small note in the `members` folder when it starts and when it
/// saves, and takes its note away when it stops sharing.
nonisolated struct SharedMember: Codable, Equatable, Sendable {
    var userName: String
    var fullName: String
    var lastSeen: Date

    var displayName: String { fullName.isEmpty ? userName : fullName }
}

/// Someone other than this login who still looks like they use the shared data, and why.
nonisolated struct SharedOtherUser: Equatable, Sendable {
    var name: String
    var lastSeen: Date
    var why: String
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

    // Everything in the folder is in Oinkly Budget's own formats: the data and the receipts are sealed `.pigdata` files
    // (see `SealedFile`), and the lock, the log and the notes about who shares are binary `.pigmeta` files.
    static let storeName = "OinklyBudget.pigdata"
    static let lockName = "lock.pigmeta"
    static let historyName = "previous saves"
    static let logName = "save log.pigmeta"
    static let membersName = "members"
    static let receiptsName = "Receipts"
    static let metaExtension = "pigmeta"
    /// The names the folder used before the sealed format (format 1). Opening such a folder converts it once.
    static let legacyStoreName = "OinklyBudget.store"
    static let legacyInfoName = "info.json"
    static let legacyLockName = "lock.json"
    static let legacyLogName = "save log.txt"
    /// A login that has used the shared data this recently still counts as sharing it.
    static let stillSharingDays = 30
    /// How many of the newest saves are kept, and how many days back one save per day is kept as well.
    static let keepNewest = 5
    static let keepDays = 7
    static let formatVersion = 2
    static let schemaVersion = 7
    /// A lock is stale once its heartbeat is this old, in seconds. The app refreshes it every 60.
    static let staleAfter: TimeInterval = 180

    var storeURL: URL { url.appendingPathComponent(Self.storeName) }
    var lockURL: URL { url.appendingPathComponent(Self.lockName) }
    var receiptsURL: URL { url.appendingPathComponent(Self.receiptsName, isDirectory: true) }
    var legacyStoreURL: URL { url.appendingPathComponent(Self.legacyStoreName) }
    var legacyInfoURL: URL { url.appendingPathComponent(Self.legacyInfoName) }
    var legacyLockURL: URL { url.appendingPathComponent(Self.legacyLockName) }
    var legacyLogURL: URL { url.appendingPathComponent(Self.legacyLogName) }
    var historyURL: URL { url.appendingPathComponent(Self.historyName) }
    var logURL: URL { url.appendingPathComponent(Self.logName) }
    var membersURL: URL { url.appendingPathComponent(Self.membersName, isDirectory: true) }

    private var manager: FileManager { .default }

    var exists: Bool { manager.fileExists(atPath: url.path) }
    var hasStore: Bool { manager.fileExists(atPath: storeURL.path) }
    /// There is shared data here, in the current format or in the format before it (which is converted when opened).
    var hasData: Bool { hasStore || manager.fileExists(atPath: legacyStoreURL.path) }
    var hasLegacyData: Bool { !hasStore && manager.fileExists(atPath: legacyStoreURL.path) }

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

    private static var encoder: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }

    private static var decoder: PropertyListDecoder { PropertyListDecoder() }

    /// How the folder's notes were written before the sealed format.
    private static var legacyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The note about the finished data file: it lives inside the sealed file's header. For a folder still in the old
    /// format it is read from the old note.
    func readInfo() -> SharedInfo? {
        if hasStore {
            guard let header = try? SealedFile.readHeader(storeURL), let data = header.info else { return nil }
            return try? Self.decoder.decode(SharedInfo.self, from: data)
        }
        guard let data = try? Data(contentsOf: legacyInfoURL) else { return nil }
        return try? Self.legacyDecoder.decode(SharedInfo.self, from: data)
    }

    func readLock() -> SharedLock? {
        guard let data = try? Data(contentsOf: lockURL) else { return nil }
        return try? Self.decoder.decode(SharedLock.self, from: data)
    }

    /// A lock written by a copy of the app from before the sealed format.
    func readLegacyLock() -> SharedLock? {
        guard let data = try? Data(contentsOf: legacyLockURL) else { return nil }
        return try? Self.legacyDecoder.decode(SharedLock.self, from: data)
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
        // A copy of the app from before the sealed format keeps its lock under the old name. It counts the same.
        if let legacy = readLegacyLock() {
            let stale = legacy.isStale(now: now)
            if !(takeOver && stale) { return .heldBy(legacy, isStale: stale) }
            try? manager.removeItem(at: legacyLockURL)
        }
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
            if takeOver && stale { return try takeOverLock(body, me: me, previous: unknown) }
            return .heldBy(unknown, isStale: stale)
        }
        if current.token == me.token { return .acquired }
        let stale = current.isStale(now: now)
        guard takeOver && stale else { return .heldBy(current, isStale: stale) }
        // Replace the stale lock, but only if it is still the one we looked at.
        guard readLock()?.token == current.token else { return .heldBy(readLock() ?? current, isStale: false) }
        return try takeOverLock(body, me: me, previous: current)
    }

    /// Replaces a stale lock. Two logins can do this in the same moment and both write, so afterwards each waits a
    /// beat and reads the lock back; only the one whose lock is still there goes on.
    private func takeOverLock(_ body: Data, me: SharedLock, previous: SharedLock) throws -> LockResult {
        try write(body, to: lockURL)
        usleep(150_000)
        if let now = readLock(), now.token == me.token { return .acquired }
        return .heldBy(readLock() ?? previous, isStale: false)
    }

    /// Who has the lock right now, and whether they have gone quiet. A lock file that can't be read is stale only once it
    /// is old, the same rule `acquire` uses. Nil when nobody has it.
    func holder(now: Date = .now) -> (lock: SharedLock, isStale: Bool)? {
        guard manager.fileExists(atPath: lockURL.path) else {
            if let legacy = readLegacyLock() { return (legacy, legacy.isStale(now: now)) }
            return nil
        }
        if let lock = readLock() { return (lock, lock.isStale(now: now)) }
        let age = lockFileAge(now: now) ?? 0
        let unknown = SharedLock(token: "unreadable", userName: "another user", fullName: "", since: now.addingTimeInterval(-age), heartbeat: now.addingTimeInterval(-age))
        return (unknown, age > Self.staleAfter)
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

    /// Unpacks the finished data file into a private working copy, replacing whatever was there, and brings the receipts
    /// along. Returns what was copied.
    @discardableResult
    func checkOut(to working: URL) throws -> SharedInfo? {
        guard hasStore else { throw SharedDataError.folderUnavailable("it has no data file") }
        let layout: SealedFile.Layout
        do {
            layout = try SealedFile.layout(of: storeURL)
        } catch SealedError.newerFormat {
            throw SharedDataError.newerFormat
        } catch {
            throw SharedDataError.verifyFailed("the shared data file can't be read: \(error.localizedDescription)")
        }
        guard let noteData = layout.header.info, let info = try? Self.decoder.decode(SharedInfo.self, from: noteData) else {
            throw SharedDataError.verifyFailed("the shared data file's note can't be read")
        }
        if info.formatVersion > Self.formatVersion || info.schemaVersion > Self.schemaVersion { throw SharedDataError.newerFormat }
        StoreFiles.remove(store: working)
        try manager.createDirectory(at: working.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try SealedFile.unseal(storeURL, to: working)
            try restoreReceipts(into: working)
        } catch {
            throw SharedDataError.copyFailed(error.localizedDescription)
        }
        // The copy is checked against what the note says before anyone works on it.
        do {
            guard try SQLiteStore.integrityIsOK(working) else { throw SharedDataError.verifyFailed("the unpacked copy failed its integrity check") }
            if let expected = info.counts {
                let copy = try SQLiteStore.counts(of: working)
                guard expected == copy else { throw SharedDataError.verifyFailed("the copy's record counts differ from the shared file") }
            }
        } catch let error as SharedDataError {
            throw error
        } catch {
            throw SharedDataError.verifyFailed(error.localizedDescription)
        }
        return info
    }

    // MARK: Check in

    /// Seals the working copy and puts it in place as the new finished data file, in one safe replace. The previous finished
    /// file is kept as one step of undo. If anything fails, the shared file is left exactly as it was.
    /// `baseRevision` is the revision this copy was checked out from; if the shared file has moved on, nothing is written.
    @discardableResult
    func checkIn(from working: URL, baseRevision: Int?, by name: String, appVersion: String, now: Date = .now,
                 fileID forcedFileID: String? = nil, revisionAtLeast: Int? = nil) throws -> SharedInfo {
        guard exists else { throw SharedDataError.folderUnavailable("it can't be found") }
        let current = readInfo()
        if let baseRevision, let current, current.revision != baseRevision { throw SharedDataError.changedMeanwhile }
        // Never write over data that a newer version of the app saved: this version could lose what it doesn't know about.
        if let current, current.formatVersion > Self.formatVersion || current.schemaVersion > Self.schemaVersion { throw SharedDataError.newerFormat }
        removeLeftovers(now: now)
        let temporary = url.appendingPathComponent(".\(Self.storeName).\(UUID().uuidString).tmp")
        let sealedTemporary = url.appendingPathComponent(".\(Self.storeName).\(UUID().uuidString).sealed.tmp")
        defer {
            try? manager.removeItem(at: temporary)
            try? manager.removeItem(at: sealedTemporary)
        }
        let actual: [String: Int]
        do {
            try SQLiteStore.vacuum(source: working, into: temporary)
            let expected = try SQLiteStore.counts(of: working)
            actual = try SQLiteStore.counts(of: temporary)
            guard expected == actual else { throw SharedDataError.verifyFailed("record counts differ after copying") }
            guard try SQLiteStore.integrityIsOK(temporary) else { throw SharedDataError.verifyFailed("the database failed its integrity check") }
        } catch let error as SharedDataError {
            throw error
        } catch {
            throw SharedDataError.verifyFailed(error.localizedDescription)
        }
        let attachments = (try? SQLiteStore.attachmentReferences(of: temporary)).map { Array($0).sorted() }
        // Receipts go first. Until the data is replaced, nothing refers to the new ones, so a failure here leaves the
        // shared data exactly as it was.
        try addReceipts(from: working, appVersion: appVersion)

        // Putting data back from a backup copy carries on that copy's numbering, so the two still agree afterwards.
        let info = SharedInfo(formatVersion: Self.formatVersion, schemaVersion: Self.schemaVersion, revision: max((current?.revision ?? 0) + 1, revisionAtLeast ?? 0),
                              savedAt: now, savedBy: name, appVersion: appVersion, fileID: forcedFileID ?? current?.fileID ?? UUID().uuidString,
                              counts: actual, attachments: attachments)
        do {
            try SealedFile.seal(temporary, to: sealedTemporary, kind: "shared", info: try Self.encoder.encode(info), appVersion: appVersion, now: now)
        } catch {
            throw SharedDataError.copyFailed(error.localizedDescription)
        }
        guard SealedFile.isIntact(sealedTemporary) else { throw SharedDataError.verifyFailed("the sealed copy didn't read back") }
        try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: sealedTemporary.path)
        if hasStore { archive(current: current, now: now) }
        if rename(sealedTemporary.path, storeURL.path) != 0 {
            throw SharedDataError.copyFailed("the new file couldn't replace the old one (\(String(cString: strerror(errno))))")
        }
        appendLog("saved by \(name) as save number \(info.revision) (Oinkly Budget \(appVersion))", now: now)
        return info
    }

    /// Temporary files left by a save that was cut short (a crash, a power cut). Anything this old can't be in use.
    func removeLeftovers(now: Date = .now) {
        guard let files = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix(".") && file.pathExtension == "tmp" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if now.timeIntervalSince(modified) > 600 { try? manager.removeItem(at: file) }
        }
    }

    // MARK: Receipts

    /// Seals each receipt and photo of `working` that the shared folder doesn't have yet. They never change once written
    /// (each has its own unique name), so only new ones are copied.
    private func addReceipts(from working: URL, appVersion: String) throws {
        try sealReceipts(fromSupport: StoreFiles.supportURL(for: working), appVersion: appVersion)
    }

    private func sealReceipts(fromSupport source: URL, appVersion: String) throws {
        guard manager.fileExists(atPath: source.path), let walker = manager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let item as URL in walker {
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let relative = String(item.path.dropFirst(source.path.count + 1))
            let target = receiptsURL.appendingPathComponent(relative + "." + SealedFile.fileExtension)
            guard !manager.fileExists(atPath: target.path) else { continue }
            do {
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try SealedFile.seal(item, to: target, kind: "receipt", appVersion: appVersion)
            } catch {
                throw SharedDataError.copyFailed(error.localizedDescription)
            }
        }
        Self.openUp(receiptsURL)
    }

    /// Unpacks every receipt of the shared folder into the folder that goes with `store`.
    func restoreReceipts(into store: URL) throws {
        guard manager.fileExists(atPath: receiptsURL.path), let walker = manager.enumerator(at: receiptsURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let destination = StoreFiles.supportURL(for: store)
        for case let item as URL in walker {
            guard item.pathExtension == SealedFile.fileExtension, (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let relative = String(item.deletingPathExtension().path.dropFirst(receiptsURL.path.count + 1))
            let target = destination.appendingPathComponent(relative)
            guard !manager.fileExists(atPath: target.path) else { continue }
            try SealedFile.unseal(item, to: target)
        }
    }

    /// Unpacks the finished data file and its receipts to `store`, to use this data somewhere else (leaving sharing).
    func unpackLatest(to store: URL) throws {
        try manager.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try SealedFile.unseal(storeURL, to: store)
            try restoreReceipts(into: store)
        } catch {
            throw SharedDataError.copyFailed(error.localizedDescription)
        }
    }

    // MARK: Receipt clean-up

    /// How long an attachment must have been in the shared folder before it can be removed for not being used.
    static let attachmentGraceDays = 30

    /// Removes receipt and photo files nothing uses any more, so the shared folder doesn't grow for ever. A file is only
    /// removed when it is older than 30 days and no saved copy of the data points to it: not the current data, not any
    /// previous save (going back to one needs its receipts) and not a recovered copy. Each save's note lists the receipts
    /// it uses. If any of those notes can't be read, nothing is removed. Returns how many files were removed.
    @discardableResult
    func removeUnusedAttachments(now: Date = .now) -> Int {
        let root = receiptsURL.appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
        guard let files = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]), !files.isEmpty else { return 0 }
        // Nothing old enough to remove means there is nothing to look up, which is almost always.
        let cutoff = now.addingTimeInterval(-Double(Self.attachmentGraceDays) * 86_400)
        let old = files.filter { $0.pathExtension == SealedFile.fileExtension && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now) < cutoff }
        guard !old.isEmpty else { return 0 }
        // Every saved copy counts, including one whose note can't be read: that stops the clean-up, as it should.
        let saved = ((try? manager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == SealedFile.fileExtension && !$0.lastPathComponent.hasPrefix(".") }
        var stores = [storeURL] + saved
        if let others = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            stores += others.filter { $0.pathExtension == SealedFile.fileExtension && $0.lastPathComponent.contains("recovered") }
        }
        var used = Set<String>()
        for store in stores where manager.fileExists(atPath: store.path) {
            guard let header = try? SealedFile.readHeader(store), let data = header.info,
                  let info = try? Self.decoder.decode(SharedInfo.self, from: data), let names = info.attachments else {
                appendLog("receipt clean-up skipped: \(store.lastPathComponent) couldn't be read", now: now)
                return 0
            }
            used.formUnion(names)
        }
        var removed = 0
        for file in old where !used.contains(file.deletingPathExtension().lastPathComponent) {
            if (try? manager.removeItem(at: file)) != nil { removed += 1 }
        }
        if removed > 0 { appendLog("removed \(removed) receipt file\(removed == 1 ? "" : "s") nothing uses any more", now: now) }
        return removed
    }

    // MARK: Previous saves and the save log

    /// Keeps the file that is about to be replaced, with its note of who saved it and when, then trims the old ones. It is
    /// already sealed, so it is simply copied. A failure here never stops the new save.
    private func archive(current: SharedInfo?, now: Date) {
        do {
            if !manager.fileExists(atPath: historyURL.path) {
                try manager.createDirectory(at: historyURL, withIntermediateDirectories: true)
                chmod(historyURL.path, 0o777)
            }
            let modified = (try? manager.attributesOfItem(atPath: storeURL.path)[.modificationDate] as? Date) ?? now
            let stamp = ISO8601DateFormatter().string(from: current?.savedAt ?? modified).replacingOccurrences(of: ":", with: "-")
            let copy: URL
            if let current {
                copy = historyURL.appendingPathComponent("save \(current.revision) \(stamp).\(SealedFile.fileExtension)")
            } else {
                // A file whose note can't be read is kept aside rather than lost, but isn't listed as a save.
                copy = historyURL.appendingPathComponent("unreadable \(stamp).bad")
            }
            try? manager.removeItem(at: copy)
            try manager.copyItem(at: storeURL, to: copy)
            try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: copy.path)
        } catch {
            appendLog("couldn't keep the previous save: \(error.localizedDescription)", now: now)
        }
        pruneHistory(now: now)
    }

    /// The earlier saves, newest first.
    func versions() -> [SharedVersion] {
        guard let files = try? manager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == SealedFile.fileExtension && !$0.lastPathComponent.hasPrefix(".") }.compactMap { file in
            guard let header = try? SealedFile.readHeader(file), let data = header.info,
                  let info = try? Self.decoder.decode(SharedInfo.self, from: data) else { return nil }
            return SharedVersion(url: file, info: info)
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
        for version in all where !keep.contains(version.url) { try? manager.removeItem(at: version.url) }
    }

    /// One line per save, newest at the end, kept in a binary file. Kept short so it never grows without limit.
    func appendLog(_ text: String, now: Date = .now) {
        let line = "\(now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))  \(now.formatted(date: .omitted, time: .standard))  \(text)"
        var lines = readLog()
        lines.append(line)
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
        if let data = try? Self.encoder.encode(lines) { try? write(data, to: logURL) }
    }

    private func readLog() -> [String] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        return (try? Self.decoder.decode([String].self, from: data)) ?? []
    }

    func recentLog(_ count: Int = 5) -> [String] { Array(readLog().suffix(count)) }

    /// Makes a brand new shared folder from a database that already exists (this Mac's own data). The original is only
    /// read, never changed.
    func createStore(from source: URL, by name: String, appVersion: String) throws {
        try ensureFolder()
        try checkIn(from: source, baseRevision: nil, by: name, appVersion: appVersion)
    }

    /// Where a copy goes when it can't safely replace the shared file, such as after a crash while someone else saved.
    func saveRecoveredCopy(from working: URL, now: Date = .now) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let destination = url.appendingPathComponent("OinklyBudget (recovered \(stamp)).\(SealedFile.fileExtension)")
        let temporary = url.appendingPathComponent(".recovered.\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        try SQLiteStore.vacuum(source: working, into: temporary)
        let counts = try SQLiteStore.counts(of: temporary)
        let attachments = (try? SQLiteStore.attachmentReferences(of: temporary)).map { Array($0).sorted() }
        let info = SharedInfo(formatVersion: Self.formatVersion, schemaVersion: Self.schemaVersion, revision: 0, savedAt: now, savedBy: "a copy kept after a crash",
                              appVersion: "", fileID: readInfo()?.fileID ?? "", counts: counts, attachments: attachments)
        try addReceipts(from: working, appVersion: "")
        try SealedFile.seal(temporary, to: destination, kind: "shared", info: try Self.encoder.encode(info), appVersion: "", now: now)
        try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: destination.path)
        appendLog("kept unsaved changes as \(destination.lastPathComponent)", now: now)
        return destination
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

    // MARK: Converting a folder from before the sealed format

    /// Turns a folder in the old format into the current one, once. Whoever opens it first does it, holding the lock. Every
    /// new file is made first and the data file is put in place last, so a conversion that is cut short leaves the old data
    /// exactly as it was and is simply done again next time. Returns whether anything was converted.
    @discardableResult
    func convertLegacyIfNeeded(appVersion: String, now: Date = .now) throws -> Bool {
        guard hasLegacyData else { return false }
        do {
            guard try SQLiteStore.integrityIsOK(legacyStoreURL) else {
                throw SharedDataError.verifyFailed("the shared data failed its integrity check, so it wasn't converted")
            }
            let legacyInfo = (try? Data(contentsOf: legacyInfoURL)).flatMap { try? Self.legacyDecoder.decode(SharedInfo.self, from: $0) }

            // Receipts
            try sealReceipts(fromSupport: StoreFiles.supportURL(for: legacyStoreURL), appVersion: appVersion)

            // Previous saves
            let legacyHistory = (try? manager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)) ?? []
            for store in legacyHistory where store.pathExtension == "store" {
                let note = store.deletingPathExtension().appendingPathExtension("json")
                guard let info = (try? Data(contentsOf: note)).flatMap({ try? Self.legacyDecoder.decode(SharedInfo.self, from: $0) }),
                      (try? SQLiteStore.integrityIsOK(store)) == true else { continue }
                let stamp = ISO8601DateFormatter().string(from: info.savedAt).replacingOccurrences(of: ":", with: "-")
                let destination = historyURL.appendingPathComponent("save \(info.revision) \(stamp).\(SealedFile.fileExtension)")
                if !manager.fileExists(atPath: destination.path) { try sealLegacyStore(store, info: info, to: destination, appVersion: appVersion, now: now) }
            }

            // Copies kept after a crash
            let rootFiles = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            let legacyRecovered = rootFiles.filter { $0.pathExtension == "store" && $0.lastPathComponent.contains("recovered") }
            for store in legacyRecovered where (try? SQLiteStore.integrityIsOK(store)) == true {
                let destination = store.deletingPathExtension().appendingPathExtension(SealedFile.fileExtension)
                let info = SharedInfo(formatVersion: Self.formatVersion, schemaVersion: legacyInfo?.schemaVersion ?? Self.schemaVersion, revision: 0, savedAt: now,
                                      savedBy: "a copy kept after a crash", appVersion: "", fileID: legacyInfo?.fileID ?? "")
                if !manager.fileExists(atPath: destination.path) { try sealLegacyStore(store, info: info, to: destination, appVersion: appVersion, now: now) }
            }

            // The log
            if readLog().isEmpty, let text = try? String(contentsOf: legacyLogURL, encoding: .utf8) {
                let lines = Array(text.split(separator: "\n").map(String.init).suffix(300))
                if let data = try? Self.encoder.encode(lines) { try? write(data, to: logURL) }
            }

            // The data file goes in last: until it is there, nothing has changed.
            let modified = (try? manager.attributesOfItem(atPath: legacyStoreURL.path)[.modificationDate] as? Date) ?? now
            let info = SharedInfo(formatVersion: Self.formatVersion, schemaVersion: legacyInfo?.schemaVersion ?? Self.schemaVersion,
                                  revision: max(legacyInfo?.revision ?? 1, 1), savedAt: legacyInfo?.savedAt ?? modified,
                                  savedBy: legacyInfo?.savedBy ?? "unknown", appVersion: legacyInfo?.appVersion ?? "",
                                  fileID: (legacyInfo?.fileID.isEmpty == false ? legacyInfo?.fileID : nil) ?? UUID().uuidString)
            try sealLegacyStore(legacyStoreURL, info: info, to: storeURL, appVersion: appVersion, now: now)
        } catch let error as SharedDataError {
            throw error
        } catch {
            throw SharedDataError.copyFailed("the shared data couldn't be converted: \(error.localizedDescription)")
        }
        appendLog("converted the shared folder to Oinkly Budget's own file format", now: now)

        // The old files are no longer used.
        for suffix in ["", "-wal", "-shm"] { try? manager.removeItem(at: URL(fileURLWithPath: legacyStoreURL.path + suffix)) }
        try? manager.removeItem(at: StoreFiles.supportURL(for: legacyStoreURL))
        try? manager.removeItem(at: legacyInfoURL)
        try? manager.removeItem(at: legacyLogURL)
        try? manager.removeItem(at: url.appendingPathComponent("OinklyBudget (previous save).store"))
        let legacyFiles = ((try? manager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "store" || $0.pathExtension == "json" }
        for file in legacyFiles { try? manager.removeItem(at: file) }
        for store in ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).filter({ $0.pathExtension == "store" }) { try? manager.removeItem(at: store) }
        for note in ((try? manager.contentsOfDirectory(at: membersURL, includingPropertiesForKeys: nil)) ?? []).filter({ $0.pathExtension == "json" }) { try? manager.removeItem(at: note) }
        return true
    }

    /// Seals a data file from the old format, filling in what the new note holds that the old one didn't.
    private func sealLegacyStore(_ plain: URL, info: SharedInfo, to destination: URL, appVersion: String, now: Date) throws {
        var note = info
        note.formatVersion = Self.formatVersion
        note.counts = try SQLiteStore.counts(of: plain)
        note.attachments = (try? SQLiteStore.attachmentReferences(of: plain)).map { Array($0).sorted() }
        let temporary = url.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).convert.tmp")
        defer { try? manager.removeItem(at: temporary) }
        try SealedFile.seal(plain, to: temporary, kind: "shared", info: try Self.encoder.encode(note), appVersion: appVersion, now: now)
        guard SealedFile.isIntact(temporary) else { throw SharedDataError.verifyFailed("a converted file didn't read back") }
        try? manager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: temporary.path)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if rename(temporary.path, destination.path) != 0 { throw SharedDataError.copyFailed("a converted file couldn't be put in place") }
    }

    // MARK: Who shares it

    private func memberURL(_ userName: String) -> URL {
        // An account name is plain, but never let one reach outside the folder.
        let safe = userName.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." ? $0 : "_" }
        return membersURL.appendingPathComponent(String(safe) + "." + Self.metaExtension)
    }

    /// Says this login uses the shared data. Failing to write it never matters to the data itself.
    func noteMember(userName: String, fullName: String, now: Date = .now) {
        guard exists else { return }
        if !manager.fileExists(atPath: membersURL.path) {
            mkdir(membersURL.path, 0o777)
            chmod(membersURL.path, 0o777)
        }
        let member = SharedMember(userName: userName, fullName: fullName, lastSeen: now)
        if let data = try? Self.encoder.encode(member) { try? write(data, to: memberURL(userName)) }
    }

    /// Takes this login's note away, because it stopped sharing.
    func removeMember(userName: String) {
        try? manager.removeItem(at: memberURL(userName))
    }

    func members() -> [SharedMember] {
        guard let files = try? manager.contentsOfDirectory(at: membersURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == Self.metaExtension }.compactMap { file in
            (try? Data(contentsOf: file)).flatMap { try? Self.decoder.decode(SharedMember.self, from: $0) }
        }
    }

    /// Everyone besides this login who has used the shared data in the last 30 days: a note they left, a lock they hold,
    /// or a save they made. Copies of the app from before the notes existed show up through their saves. If it can't
    /// be told, the answer errs towards "someone does".
    func otherUsers(besides userName: String, fullName: String, now: Date = .now) -> [SharedOtherUser] {
        let since = now.addingTimeInterval(-Double(Self.stillSharingDays) * 86_400)
        var found: [String: SharedOtherUser] = [:]
        func add(_ name: String, _ date: Date, _ why: String) {
            guard !name.isEmpty, name != userName, name != fullName else { return }
            if let existing = found[name], existing.lastSeen >= date { return }
            found[name] = SharedOtherUser(name: name, lastSeen: date, why: why)
        }
        for member in members() where member.lastSeen >= since && member.userName != userName {
            add(member.displayName, member.lastSeen, "has sharing on")
        }
        if let holder = holder(now: now), holder.lock.userName != userName {
            add(holder.lock.displayName, holder.lock.heartbeat, holder.isStale ? "had it open and may have stopped" : "has it open now")
        }
        let saves = [readInfo()].compactMap { $0 } + versions().map(\.info)
        for info in saves where info.savedAt >= since {
            add(info.savedBy, info.savedAt, "saved a change")
        }
        return found.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Moves the whole shared folder to the Trash, so it can still be put back. If the Trash can't be used, it is removed
    /// instead. Returns whether it went to the Trash. Only called once the caller knows nobody else uses it.
    @discardableResult
    func removeEverything(useTrash: Bool = true) throws -> Bool {
        do {
            guard useTrash else { throw CocoaError(.fileWriteUnknown) }
            try manager.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            do { try manager.removeItem(at: url) } catch { throw SharedDataError.folderUnavailable(error.localizedDescription) }
            return false
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
        let sharing = members()
        if !sharing.isEmpty {
            lines.append("Shared by: " + sharing.sorted { $0.lastSeen > $1.lastSeen }.map { "\($0.displayName) (last used \($0.lastSeen.formatted(date: .abbreviated, time: .shortened)))" }.joined(separator: ", "))
        }
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
        lines.append("Data file: \(hasStore ? describe(storeURL.path) : (hasLegacyData ? "in the old format, converted when it is next opened" : "none yet"))")
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
