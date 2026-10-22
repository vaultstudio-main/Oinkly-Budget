import Foundation
import Darwin

/// What the backup copy's latest file is: which save it matches and how much data it holds.
nonisolated struct ShadowInfo: Codable, Equatable, Sendable {
    var formatVersion: Int
    /// The database shape (OinklyBudgetSchemaV4 is 4).
    var schemaVersion: Int
    /// Goes up by one at every copy.
    var copyNumber: Int
    var savedAt: Date
    var appVersion: String
    /// Names this data, so a backup copy of other data is noticed.
    var dataID: String
    /// "This Mac" or "Shared data".
    var source: String
    /// When the copy was made from shared data: which save of it, and which shared data.
    var sharedRevision: Int?
    var sharedFileID: String?
    var accounts: Int
    var transactions: Int
    /// The receipt and photo files this copy uses, so unused ones can be cleaned up without opening every copy. Nil in
    /// copies made before it was kept.
    var attachments: [String]?
}

/// What a sealed .pig file says about itself in its header.
nonisolated struct PortableInfo: Codable, Equatable, Sendable {
    var savedAt: Date
    var appVersion: String
    /// "This Mac" or "Shared data".
    var source: String
    var accounts: Int
    var transactions: Int
    /// A short description of what is in it, such as "6 accounts, 1,240 transactions".
    var summary: String
}

/// One of the .pig files in a backup copy's Portable files folder.
nonisolated struct PortableVersion: Identifiable, Equatable, Sendable {
    var url: URL
    var info: PortableInfo
    var id: URL { url }
}

/// One of the files in a backup copy, the latest or an older one.
nonisolated struct ShadowVersion: Identifiable, Equatable, Sendable {
    var url: URL
    var info: ShadowInfo
    var isLatest: Bool
    var id: URL { url }
}

nonisolated enum ShadowError: LocalizedError {
    case unavailable(String)
    case verifyFailed(String)
    case copyFailed(String)
    case newerFormat

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): "The backup copy folder can't be used: \(why)"
        case .verifyFailed(let why): "The copy didn't pass its safety check, so nothing was changed: \(why)"
        case .copyFailed(let why): "The backup copy couldn't be written: \(why)"
        case .newerFormat: "That backup copy was made by a newer version of Oinkly Budget. Update the app and try again."
        }
    }
}

/// A backup copy on disk: a folder inside the one the person chose, holding the latest copy of the data, the receipts and
/// a few older copies. Every file in it is in Oinkly Budget's own sealed format (see `SealedFile`), so only Oinkly Budget
/// can read them, a damaged one is told from a good one without opening it, and only the owner can open the folder. What
/// is in a copy is only ever a complete, checked copy of the data file.
nonisolated struct ShadowFolder: Sendable {
    let url: URL

    static let folderName = "Oinkly Budget Backup Copy"
    static let storeName = "OinklyBudget.pigdata"
    static let olderName = "Older copies"
    static let receiptsName = "Receipts"
    static let portableName = "Portable files"
    /// How many of the portable .pig files are kept (they carry the receipts inside them, so they are large).
    static let keepPortable = 5
    /// A receipt must have been in the backup copy this long before it can be removed for not being used.
    static let receiptGraceDays = 30
    static let formatVersion = 1
    static let schemaVersion = 4
    /// The newest older copies kept, and how many days back one per day is kept as well.
    static let keepNewest = 10
    static let keepDays = 7

    /// The backup copy that lives inside `parent`, the folder the person chose.
    init(inside parent: URL) {
        url = parent.appendingPathComponent(Self.folderName, isDirectory: true)
        // A folder made when this was still called the shadow copy is moved to the new name.
        let old = parent.appendingPathComponent("Oinkly Budget Shadow Copy", isDirectory: true)
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path), manager.fileExists(atPath: old.path) { try? manager.moveItem(at: old, to: url) }
    }
    init(at url: URL) { self.url = url }

    var storeURL: URL { url.appendingPathComponent(Self.storeName) }
    var olderURL: URL { url.appendingPathComponent(Self.olderName, isDirectory: true) }
    var receiptsURL: URL { url.appendingPathComponent(Self.receiptsName, isDirectory: true) }
    var portableURL: URL { url.appendingPathComponent(Self.portableName, isDirectory: true) }

    private var manager: FileManager { .default }
    var exists: Bool { manager.fileExists(atPath: url.path) }
    var hasStore: Bool { manager.fileExists(atPath: storeURL.path) }

    /// What a sealed copy says about itself, read from its header without opening it.
    private static func info(of file: URL) -> ShadowInfo? {
        guard let header = try? SealedFile.readHeader(file), header.kind == "data", let data = header.info else { return nil }
        return try? SealedFile.decodeInfo(ShadowInfo.self, from: data)
    }

    func readInfo() -> ShadowInfo? { Self.info(of: storeURL) }

    /// The older copies, newest first.
    func olderVersions() -> [ShadowVersion] {
        guard let files = try? manager.contentsOfDirectory(at: olderURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == SealedFile.fileExtension && !$0.lastPathComponent.hasPrefix(".") }.compactMap { file in
            Self.info(of: file).map { ShadowVersion(url: file, info: $0, isLatest: false) }
        }.sorted { ($0.info.savedAt, $0.info.copyNumber) > ($1.info.savedAt, $1.info.copyNumber) }
    }

    /// The latest copy and the older ones, newest first.
    func allVersions() -> [ShadowVersion] {
        var result: [ShadowVersion] = []
        if let info = readInfo() { result.append(ShadowVersion(url: storeURL, info: info, isLatest: true)) }
        return result + olderVersions()
    }

    /// Whether a copy is whole: its fingerprint matches, so nothing in it has been cut short or changed.
    func isGood(_ version: ShadowVersion) -> Bool { SealedFile.isIntact(version.url) }

    /// The newest copy that is good, or nil when none is.
    func newestGoodVersion() -> ShadowVersion? { allVersions().first { isGood($0) } }

    // MARK: Writing

    /// Writes a new latest copy of `live`. The copy is made beside the old one, checked against the original, sealed, and
    /// only then put in place; the old latest becomes an older copy. If anything fails, the backup copy is left as it was.
    @discardableResult
    func write(from live: URL, dataID: String, source: String, sharedRevision: Int? = nil, sharedFileID: String? = nil,
               appVersion: String, now: Date = .now) throws -> ShadowInfo {
        if let existing = readInfo(), existing.formatVersion > Self.formatVersion || existing.schemaVersion > Self.schemaVersion { throw ShadowError.newerFormat }
        do {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            chmod(url.path, 0o700)
        } catch {
            throw ShadowError.unavailable(error.localizedDescription)
        }
        let staging = url.appendingPathComponent(".staging.\(UUID().uuidString).tmp")
        let stagingSealed = url.appendingPathComponent(".staging.\(UUID().uuidString).\(SealedFile.fileExtension)")
        defer {
            try? manager.removeItem(at: staging)
            try? manager.removeItem(at: stagingSealed)
        }
        let counts: [String: Int]
        var attachments: [String]?
        do {
            try SQLiteStore.vacuum(source: live, into: staging)
            let expected = try SQLiteStore.counts(of: live)
            counts = try SQLiteStore.counts(of: staging)
            guard expected == counts else { throw ShadowError.verifyFailed("the record counts differ from the original") }
            guard try SQLiteStore.integrityIsOK(staging) else { throw ShadowError.verifyFailed("the database failed its integrity check") }
            attachments = (try? SQLiteStore.attachmentReferences(of: staging)).map { Array($0).sorted() }
        } catch let error as ShadowError {
            throw error
        } catch {
            throw ShadowError.verifyFailed(error.localizedDescription)
        }
        // Receipts go first. Until the data is replaced, nothing refers to the new ones.
        try addReceipts(from: live, appVersion: appVersion)

        let current = readInfo()
        let info = ShadowInfo(formatVersion: Self.formatVersion, schemaVersion: Self.schemaVersion, copyNumber: (current?.copyNumber ?? 0) + 1,
                              savedAt: now, appVersion: appVersion, dataID: dataID, source: source,
                              sharedRevision: sharedRevision, sharedFileID: sharedFileID,
                              accounts: counts["ZACCOUNT"] ?? 0, transactions: counts["ZTRANSACTION"] ?? 0, attachments: attachments)
        do {
            try SealedFile.seal(staging, to: stagingSealed, kind: "data", info: try SealedFile.encodeInfo(info), appVersion: appVersion, now: now)
        } catch {
            throw ShadowError.copyFailed(error.localizedDescription)
        }
        guard SealedFile.isIntact(stagingSealed) else { throw ShadowError.verifyFailed("the sealed copy didn't read back") }
        if hasStore { archive(current: current, now: now) }
        if rename(stagingSealed.path, storeURL.path) != 0 {
            throw ShadowError.copyFailed("the new copy couldn't replace the old one (\(String(cString: strerror(errno))))")
        }
        prune(now: now)
        removeUnusedReceipts(now: now)
        return info
    }

    /// Keeps the file that is about to be replaced as an older copy. It is already sealed, so it is simply copied.
    private func archive(current: ShadowInfo?, now: Date) {
        do {
            try manager.createDirectory(at: olderURL, withIntermediateDirectories: true)
            chmod(olderURL.path, 0o700)
            let info = current ?? ShadowInfo(formatVersion: Self.formatVersion, schemaVersion: Self.schemaVersion, copyNumber: 0, savedAt: now,
                                             appVersion: "", dataID: "", source: "unknown", sharedRevision: nil, sharedFileID: nil, accounts: 0, transactions: 0)
            let stamp = ISO8601DateFormatter().string(from: info.savedAt).replacingOccurrences(of: ":", with: "-")
            let copy = olderURL.appendingPathComponent("copy \(info.copyNumber) \(stamp).\(SealedFile.fileExtension)")
            try? manager.removeItem(at: copy)
            try manager.copyItem(at: storeURL, to: copy)
        } catch {
            // Keeping an older copy never stops the new one.
        }
    }

    /// Keeps the newest few older copies, plus the newest of each of the last few days.
    func prune(now: Date = .now, calendar: Calendar = .current) {
        let all = olderVersions()
        var keep = Set(all.prefix(Self.keepNewest).map(\.url))
        for dayOffset in 0..<Self.keepDays {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            if let newestThatDay = all.first(where: { calendar.isDate($0.info.savedAt, inSameDayAs: day) }) { keep.insert(newestThatDay.url) }
        }
        for version in all where !keep.contains(version.url) { try? manager.removeItem(at: version.url) }
        // Anything cut short by a crash a while ago can't be in use.
        if let leftovers = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for file in leftovers where file.lastPathComponent.hasPrefix(".staging.") {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
                if now.timeIntervalSince(modified) > 600 { try? manager.removeItem(at: file) }
            }
        }
    }

    // MARK: Portable files

    /// The portable .pig files, newest first.
    func portableVersions() -> [PortableVersion] {
        guard let files = try? manager.contentsOfDirectory(at: portableURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "pig" && !$0.lastPathComponent.hasPrefix(".") }.compactMap { file in
            guard let header = try? SealedFile.readHeader(file), header.kind == "backup", let data = header.info,
                  let info = try? SealedFile.decodeInfo(PortableInfo.self, from: data) else { return nil }
            return PortableVersion(url: file, info: info)
        }.sorted { $0.info.savedAt > $1.info.savedAt }
    }

    func isGood(_ portable: PortableVersion) -> Bool { SealedFile.isIntact(portable.url) }

    func newestGoodPortable() -> PortableVersion? { portableVersions().first { isGood($0) } }

    /// Writes a portable .pig file from a backup's JSON, sealed like every other file here, and keeps the newest few. It
    /// is only written when what it holds matches the snapshot made at the same moment (same accounts and transactions);
    /// if the data changed in between, it is skipped and the next copy makes one. Returns whether it was written.
    @discardableResult
    func writePortable(json: Data, info: PortableInfo, matching snapshot: ShadowInfo, appVersion: String, now: Date = .now) throws -> Bool {
        guard info.accounts == snapshot.accounts, info.transactions == snapshot.transactions else { return false }
        try manager.createDirectory(at: portableURL, withIntermediateDirectories: true)
        chmod(portableURL.path, 0o700)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let destination = portableURL.appendingPathComponent("Oinkly Budget Backup \(stamp).pig")
        let plain = portableURL.appendingPathComponent(".portable.\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: plain) }
        do {
            try json.write(to: plain)
            try SealedFile.seal(plain, to: destination, kind: "backup", info: try SealedFile.encodeInfo(info), appVersion: appVersion, now: now)
        } catch {
            throw ShadowError.copyFailed(error.localizedDescription)
        }
        guard SealedFile.isIntact(destination) else {
            try? manager.removeItem(at: destination)
            throw ShadowError.verifyFailed("the portable file didn't read back")
        }
        let all = portableVersions()
        for old in all.dropFirst(Self.keepPortable) { try? manager.removeItem(at: old.url) }
        return true
    }

    // MARK: Receipts

    /// Removes receipts that no copy kept here uses any more, so the folder doesn't grow for ever. A receipt is only
    /// removed when it has been here for over 30 days and neither the latest copy nor any older copy points to it (going
    /// back to an older copy needs its receipts). Portable files carry their receipts inside them, so they don't count.
    /// Each copy's note lists the receipts it uses; if any copy's note can't be read, nothing is removed. Returns how many
    /// files were removed.
    @discardableResult
    func removeUnusedReceipts(now: Date = .now) -> Int {
        let root = receiptsURL.appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
        guard let files = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]), !files.isEmpty else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(Self.receiptGraceDays) * 86_400)
        let old = files.filter { $0.pathExtension == SealedFile.fileExtension && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now) < cutoff }
        guard !old.isEmpty else { return 0 }
        // Every copy counts, including one whose note can't be read: that stops the clean-up, as it should.
        let older = ((try? manager.contentsOfDirectory(at: olderURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == SealedFile.fileExtension && !$0.lastPathComponent.hasPrefix(".") }
        var used = Set<String>()
        for copy in [storeURL] + older where manager.fileExists(atPath: copy.path) {
            guard let info = Self.info(of: copy), let names = info.attachments else { return 0 }
            used.formUnion(names)
        }
        var removed = 0
        for file in old where !used.contains(file.deletingPathExtension().lastPathComponent) {
            if (try? manager.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }

    /// Seals each receipt and photo of `live` that the backup copy doesn't have yet. They never change once written (each
    /// has its own unique name), so only new ones are copied.
    private func addReceipts(from live: URL, appVersion: String) throws {
        let source = StoreFiles.supportURL(for: live)
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
                throw ShadowError.copyFailed(error.localizedDescription)
            }
        }
    }

    /// Unpacks every receipt of the backup copy into the folder that goes with `store`.
    func restoreReceipts(into store: URL) throws {
        guard manager.fileExists(atPath: receiptsURL.path), let walker = manager.enumerator(at: receiptsURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let destination = StoreFiles.supportURL(for: store)
        for case let item as URL in walker {
            guard item.pathExtension == SealedFile.fileExtension, (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let relative = String(item.deletingPathExtension().path.dropFirst(receiptsURL.path.count + 1))
            let target = destination.appendingPathComponent(relative)
            guard !manager.fileExists(atPath: target.path) else { continue }
            do { try SealedFile.unseal(item, to: target) } catch { throw ShadowError.copyFailed(error.localizedDescription) }
        }
    }

    // MARK: Using a copy

    /// Unpacks a copy into `plain` and checks that what came out is the data it says it is.
    func unpack(_ version: ShadowVersion, to plain: URL) throws {
        if version.info.formatVersion > Self.formatVersion || version.info.schemaVersion > Self.schemaVersion { throw ShadowError.newerFormat }
        do { try SealedFile.unseal(version.url, to: plain) } catch { throw ShadowError.verifyFailed(error.localizedDescription) }
        guard (try? SQLiteStore.integrityIsOK(plain)) == true, let counts = try? SQLiteStore.counts(of: plain),
              counts["ZACCOUNT"] == version.info.accounts, counts["ZTRANSACTION"] == version.info.transactions else {
            try? manager.removeItem(at: plain)
            throw ShadowError.verifyFailed("what came out of that copy isn't the data it should be")
        }
    }

    /// Puts a copy in place of `target`: the data file and the receipts. The caller keeps a safety copy of what was there first.
    func restore(_ version: ShadowVersion, to target: URL) throws {
        let staged = target.deletingLastPathComponent().appendingPathComponent(".restoring.\(UUID().uuidString).store")
        defer { try? manager.removeItem(at: staged) }
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try unpack(version, to: staged)
        StoreFiles.remove(store: target)
        do {
            try manager.moveItem(at: staged, to: target)
        } catch {
            throw ShadowError.copyFailed(error.localizedDescription)
        }
        try restoreReceipts(into: target)
    }

    /// Removes the whole backup copy.
    func removeAll() { try? manager.removeItem(at: url) }

    /// Moves the whole backup copy to the Trash, so it can still be put back. If the Trash can't be used, it is removed.
    func removeToTrash() {
        do { try manager.trashItem(at: url, resultingItemURL: nil) } catch { try? manager.removeItem(at: url) }
    }

    /// How much room the backup copy takes.
    func size() -> Int64 {
        guard let walker = manager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in walker { total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }
}

/// What a look at the data against its backup copy found.
nonisolated enum ShadowFinding: Equatable, Sendable {
    /// The backup copy is of other data.
    case otherData
    /// The data is empty and the backup copy is not.
    case dataLooksEmpty(shadowAccounts: Int, shadowTransactions: Int)
    /// The data holds far fewer transactions than the backup copy.
    case dataMuchSmaller(have: Int, shadowTransactions: Int)
    /// The data file can't be read.
    case dataUnreadable(String)
    /// The shared data is older than the backup copy.
    case sharedOlder(sharedRevision: Int, shadowRevision: Int)
    /// The shared data is not the data the backup copy came from.
    case sharedIsDifferent
    case sharedMissing
    case sharedUnreadable(String)

    /// The ones that need the person's decision before the app opens the data.
    var needsDecision: Bool { true }

    var title: String {
        switch self {
        case .otherData: "This backup copy is of other data"
        case .dataLooksEmpty: "Your data looks empty"
        case .dataMuchSmaller: "Your data has far fewer transactions than the backup copy"
        case .dataUnreadable: "Your data can't be read"
        case .sharedOlder: "The shared data is older than your backup copy"
        case .sharedIsDifferent: "The shared data isn't the data your backup copy came from"
        case .sharedMissing: "The shared data can't be found"
        case .sharedUnreadable: "The shared data can't be read"
        }
    }
}

nonisolated enum ShadowCheck {
    /// Is this backup copy the data we have? In sharing, by which shared data it came from; alone, by the data's own ID.
    static func belongs(_ info: ShadowInfo, dataID: String, sharedFileID: String?) -> Bool {
        if let sharedFileID {
            if let theirs = info.sharedFileID { return theirs == sharedFileID }
            return info.dataID == dataID
        }
        return info.dataID == dataID
    }

    /// Looks at this Mac's own data file against its backup copy before the app opens it. Nil means all is well.
    static func lookAtOwnData(store: URL, shadow: ShadowFolder, dataID: String) -> ShadowFinding? {
        guard let info = shadow.readInfo(), shadow.hasStore else { return nil }
        guard belongs(info, dataID: dataID, sharedFileID: nil) else { return .otherData }
        guard FileManager.default.fileExists(atPath: store.path) else {
            // No data file at all while the backup copy has data: the data was removed.
            return info.transactions > 0 || info.accounts > 1 ? .dataLooksEmpty(shadowAccounts: info.accounts, shadowTransactions: info.transactions) : nil
        }
        let counts: [String: Int]
        do {
            guard try SQLiteStore.integrityIsOK(store) else { return .dataUnreadable("it failed its integrity check") }
            counts = try SQLiteStore.counts(of: store)
        } catch {
            return .dataUnreadable(error.localizedDescription)
        }
        let transactions = counts["ZTRANSACTION"] ?? 0
        let accounts = counts["ZACCOUNT"] ?? 0
        let shadowHasData = info.transactions > 0 || info.accounts > 1
        if shadowHasData && transactions == 0 && accounts <= 1 { return .dataLooksEmpty(shadowAccounts: info.accounts, shadowTransactions: info.transactions) }
        if info.transactions >= 20 && transactions * 2 < info.transactions { return .dataMuchSmaller(have: transactions, shadowTransactions: info.transactions) }
        return nil
    }

    /// Looks at the shared data against the backup copy before the app opens it. Nil means all is well.
    static func lookAtSharedData(_ shared: SharedDataFolder, shadow: ShadowFolder, dataID: String) -> ShadowFinding? {
        guard shared.exists, shared.hasData else {
            return shadow.readInfo() != nil && shadow.hasStore ? .sharedMissing : nil
        }
        if shared.hasStore {
            // Sealed data: the fingerprint says whether it is whole, and the note inside says what it is.
            guard SealedFile.isIntact(shared.storeURL) else { return .sharedUnreadable("it failed its check") }
            guard shared.readInfo() != nil else { return .sharedUnreadable("its note can't be read") }
        } else {
            // Data from before the sealed format, which is converted when it is opened.
            do {
                guard try SQLiteStore.integrityIsOK(shared.legacyStoreURL) else { return .sharedUnreadable("it failed its integrity check") }
            } catch {
                return .sharedUnreadable(error.localizedDescription)
            }
        }
        guard let info = shadow.readInfo(), shadow.hasStore, let shared = shared.readInfo() else { return nil }
        guard belongs(info, dataID: dataID, sharedFileID: shared.fileID) else { return .sharedIsDifferent }
        if let theirs = info.sharedRevision, info.sharedFileID == shared.fileID, theirs > shared.revision {
            return .sharedOlder(sharedRevision: shared.revision, shadowRevision: theirs)
        }
        return nil
    }
}

/// Putting the shared data back: from a backup copy, or from the newest good earlier save in the shared folder.
nonisolated enum SharedRescue {
    /// Replaces the shared data with `version` of the backup copy. The folder is made again if it is gone; whatever is
    /// there now is kept as an earlier save. Carries on the backup copy's numbering and data ID, so the two agree.
    static func rebuild(_ shared: SharedDataFolder, from version: ShadowVersion, in shadow: ShadowFolder, me: SharedLock, appVersion: String,
                        staging: URL) throws {
        guard shadow.isGood(version) else { throw ShadowError.verifyFailed("that copy didn't pass its check") }
        let manager = FileManager.default
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(SharedDataFolder.storeName)
        try shadow.unpack(version, to: staged)
        try shadow.restoreReceipts(into: staged)
        try put(staged, into: shared, me: me, appVersion: appVersion, fileID: version.info.sharedFileID, revisionAtLeast: version.info.sharedRevision,
                note: "put back from the backup copy made \(version.info.savedAt.formatted(date: .abbreviated, time: .shortened))")
    }

    /// Makes the newest good earlier save in the shared folder the current data again. Returns false when there is none.
    static func restoreNewestGoodEarlierSave(_ shared: SharedDataFolder, me: SharedLock, appVersion: String, staging: URL) throws -> Bool {
        let manager = FileManager.default
        guard let version = shared.versions().first(where: { SealedFile.isIntact($0.url) }) else { return false }
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(SharedDataFolder.storeName)
        try SealedFile.unseal(version.url, to: staged)
        try shared.restoreReceipts(into: staged)
        try put(staged, into: shared, me: me, appVersion: appVersion, fileID: version.info.fileID.isEmpty ? nil : version.info.fileID, revisionAtLeast: nil,
                note: "put back from the earlier save number \(version.info.revision)")
        return true
    }

    private static func put(_ staged: URL, into shared: SharedDataFolder, me: SharedLock, appVersion: String, fileID: String?, revisionAtLeast: Int?, note: String) throws {
        try shared.ensureFolder()
        var mine = me
        mine.since = .now
        mine.heartbeat = .now
        guard case .acquired = try shared.acquire(mine, takeOver: true) else {
            throw ShadowError.unavailable("someone has the shared data open right now")
        }
        defer { shared.release(token: mine.token) }
        let current = shared.readInfo()
        try shared.checkIn(from: staged, baseRevision: shared.hasStore ? current?.revision : nil, by: me.fullName.isEmpty ? me.userName : me.fullName,
                           appVersion: appVersion, fileID: fileID ?? current?.fileID, revisionAtLeast: revisionAtLeast)
        shared.appendLog(note)
    }
}
