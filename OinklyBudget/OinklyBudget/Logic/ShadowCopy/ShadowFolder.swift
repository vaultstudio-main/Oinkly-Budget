import Foundation
import Darwin

/// What the shadow copy's latest file is: which save it matches and how much data it holds.
nonisolated struct ShadowInfo: Codable, Equatable, Sendable {
    var formatVersion: Int
    /// The database shape (OinklyBudgetSchemaV4 is 4).
    var schemaVersion: Int
    /// Goes up by one at every copy.
    var copyNumber: Int
    var savedAt: Date
    var appVersion: String
    /// Names this data, so a shadow copy of other data is noticed.
    var dataID: String
    /// "This Mac" or "Shared data".
    var source: String
    /// When the copy was made from shared data: which save of it, and which shared data.
    var sharedRevision: Int?
    var sharedFileID: String?
    var accounts: Int
    var transactions: Int
}

/// One of the files in a shadow copy, the latest or an older one.
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
        case .unavailable(let why): "The shadow copy folder can't be used: \(why)"
        case .verifyFailed(let why): "The copy didn't pass its safety check, so nothing was changed: \(why)"
        case .copyFailed(let why): "The shadow copy couldn't be written: \(why)"
        case .newerFormat: "That shadow copy was made by a newer version of Oinkly Budget. Update the app and try again."
        }
    }
}

/// A shadow copy on disk: a folder inside the one the person chose, holding the latest copy of the data file, the
/// receipts, a note about which save it matches, and a few older copies. Plain files and the system's own SQLite, like the
/// shared folder, and only the owner can open it. The data file in it is only ever a complete, checked copy.
nonisolated struct ShadowFolder: Sendable {
    let url: URL

    static let folderName = "Oinkly Budget Shadow Copy"
    static let storeName = "OinklyBudget.store"
    static let infoName = "shadow.json"
    static let olderName = "Older copies"
    static let readmeName = "Read Me.txt"
    static let formatVersion = 1
    static let schemaVersion = 4
    /// The newest older copies kept, and how many days back one per day is kept as well.
    static let keepNewest = 10
    static let keepDays = 7

    /// The shadow copy that lives inside `parent`, the folder the person chose.
    init(inside parent: URL) { url = parent.appendingPathComponent(Self.folderName, isDirectory: true) }
    init(at url: URL) { self.url = url }

    var storeURL: URL { url.appendingPathComponent(Self.storeName) }
    var infoURL: URL { url.appendingPathComponent(Self.infoName) }
    var olderURL: URL { url.appendingPathComponent(Self.olderName, isDirectory: true) }
    var readmeURL: URL { url.appendingPathComponent(Self.readmeName) }

    private var manager: FileManager { .default }
    var exists: Bool { manager.fileExists(atPath: url.path) }
    var hasStore: Bool { manager.fileExists(atPath: storeURL.path) }

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

    func readInfo() -> ShadowInfo? {
        guard let data = try? Data(contentsOf: infoURL) else { return nil }
        return try? Self.decoder.decode(ShadowInfo.self, from: data)
    }

    /// The older copies, newest first.
    func olderVersions() -> [ShadowVersion] {
        guard let files = try? manager.contentsOfDirectory(at: olderURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "store" }.compactMap { store in
            guard let data = try? Data(contentsOf: store.deletingPathExtension().appendingPathExtension("json")),
                  let info = try? Self.decoder.decode(ShadowInfo.self, from: data) else { return nil }
            return ShadowVersion(url: store, info: info, isLatest: false)
        }.sorted { ($0.info.savedAt, $0.info.copyNumber) > ($1.info.savedAt, $1.info.copyNumber) }
    }

    /// The latest copy and the older ones, newest first.
    func allVersions() -> [ShadowVersion] {
        var result: [ShadowVersion] = []
        if let info = readInfo(), hasStore { result.append(ShadowVersion(url: storeURL, info: info, isLatest: true)) }
        return result + olderVersions()
    }

    /// Whether a copy opens and passes SQLite's own check, and holds the number of records its note says.
    func isGood(_ version: ShadowVersion) -> Bool {
        guard (try? SQLiteStore.integrityIsOK(version.url)) == true,
              let counts = try? SQLiteStore.counts(of: version.url) else { return false }
        return counts["ZACCOUNT"] == version.info.accounts && counts["ZTRANSACTION"] == version.info.transactions
    }

    /// The newest copy that is good, or nil when none is.
    func newestGoodVersion() -> ShadowVersion? { allVersions().first { isGood($0) } }

    // MARK: Writing

    /// Writes a new latest copy of `live`. The copy is made beside the old one, checked against the original, and only
    /// then put in place; the old latest becomes an older copy. If anything fails, the shadow copy is left as it was.
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
        let staging = url.appendingPathComponent(".\(Self.storeName).\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: staging) }
        let counts: [String: Int]
        do {
            try SQLiteStore.vacuum(source: live, into: staging)
            let expected = try SQLiteStore.counts(of: live)
            counts = try SQLiteStore.counts(of: staging)
            guard expected == counts else { throw ShadowError.verifyFailed("the record counts differ from the original") }
            guard try SQLiteStore.integrityIsOK(staging) else { throw ShadowError.verifyFailed("the database failed its integrity check") }
        } catch let error as ShadowError {
            throw error
        } catch {
            throw ShadowError.verifyFailed(error.localizedDescription)
        }
        // Receipts go first. Until the data file is replaced, nothing refers to the new ones.
        do { try StoreFiles.copyAttachments(from: live, to: storeURL) } catch { throw ShadowError.copyFailed(error.localizedDescription) }

        let current = readInfo()
        if hasStore { archive(current: current, now: now) }
        if rename(staging.path, storeURL.path) != 0 {
            throw ShadowError.copyFailed("the new copy couldn't replace the old one (\(String(cString: strerror(errno))))")
        }
        let info = ShadowInfo(formatVersion: Self.formatVersion, schemaVersion: Self.schemaVersion, copyNumber: (current?.copyNumber ?? 0) + 1,
                              savedAt: now, appVersion: appVersion, dataID: dataID, source: source,
                              sharedRevision: sharedRevision, sharedFileID: sharedFileID,
                              accounts: counts["ZACCOUNT"] ?? 0, transactions: counts["ZTRANSACTION"] ?? 0)
        try writeInfo(info)
        writeReadMe()
        prune(now: now)
        return info
    }

    private func writeInfo(_ info: ShadowInfo) throws {
        let temporary = url.appendingPathComponent(".\(Self.infoName).\(UUID().uuidString).tmp")
        do {
            try Self.encoder.encode(info).write(to: temporary)
            if rename(temporary.path, infoURL.path) != 0 {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw ShadowError.copyFailed(error.localizedDescription)
        }
    }

    private func writeReadMe() {
        guard !manager.fileExists(atPath: readmeURL.path) else { return }
        let text = """
        This folder is a shadow copy of your Oinkly Budget data, kept up to date by the app.

        "\(Self.storeName)" is the latest copy. "\(Self.olderName)" holds a few earlier ones. The hidden folder beside it holds your receipts.

        It is an ordinary copy of your data, not encrypted. Anyone who can open this folder can read it, and if the folder is in iCloud Drive it is also on Apple's servers.

        To use it, open Oinkly Budget, go to Settings, Data & Backup, Shadow Copy and choose Restore. Please don't edit or move the files in here.
        """
        try? text.write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    /// Keeps the file that is about to be replaced as an older copy, with its note.
    private func archive(current: ShadowInfo?, now: Date) {
        do {
            try manager.createDirectory(at: olderURL, withIntermediateDirectories: true)
            chmod(olderURL.path, 0o700)
            let modified = (try? manager.attributesOfItem(atPath: storeURL.path)[.modificationDate] as? Date) ?? now
            let info = current ?? ShadowInfo(formatVersion: Self.formatVersion, schemaVersion: Self.schemaVersion, copyNumber: 0, savedAt: modified,
                                             appVersion: "", dataID: "", source: "unknown", sharedRevision: nil, sharedFileID: nil,
                                             accounts: (try? SQLiteStore.counts(of: storeURL)["ZACCOUNT"]) ?? 0, transactions: (try? SQLiteStore.counts(of: storeURL)["ZTRANSACTION"]) ?? 0)
            let stamp = ISO8601DateFormatter().string(from: info.savedAt).replacingOccurrences(of: ":", with: "-")
            let base = olderURL.appendingPathComponent("copy \(info.copyNumber) \(stamp)")
            let copy = base.appendingPathExtension("store")
            try? manager.removeItem(at: copy)
            try manager.copyItem(at: storeURL, to: copy)
            try Self.encoder.encode(info).write(to: base.appendingPathExtension("json"))
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
        for version in all where !keep.contains(version.url) {
            try? manager.removeItem(at: version.url)
            try? manager.removeItem(at: version.url.deletingPathExtension().appendingPathExtension("json"))
        }
    }

    // MARK: Using a copy

    /// Puts a copy in place of `target`: the data file and the receipts it needs. The caller keeps a safety copy of what
    /// was there first.
    func restore(_ version: ShadowVersion, to target: URL) throws {
        guard isGood(version) else { throw ShadowError.verifyFailed("that copy didn't pass its check") }
        if version.info.formatVersion > Self.formatVersion || version.info.schemaVersion > Self.schemaVersion { throw ShadowError.newerFormat }
        StoreFiles.remove(store: target)
        do {
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: version.url, to: target)
            // The receipts all live beside the latest copy.
            try StoreFiles.copyAttachments(from: storeURL, to: target)
        } catch {
            throw ShadowError.copyFailed(error.localizedDescription)
        }
    }

    /// Removes the whole shadow copy.
    func removeAll() { try? manager.removeItem(at: url) }

    /// How much room the shadow copy takes.
    func size() -> Int64 {
        guard let walker = manager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in walker { total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }
}

/// What a look at the data against its shadow copy found.
nonisolated enum ShadowFinding: Equatable, Sendable {
    /// The shadow copy is of other data.
    case otherData
    /// The data is empty and the shadow copy is not.
    case dataLooksEmpty(shadowAccounts: Int, shadowTransactions: Int)
    /// The data holds far fewer transactions than the shadow copy.
    case dataMuchSmaller(have: Int, shadowTransactions: Int)
    /// The data file can't be read.
    case dataUnreadable(String)
    /// The shared data is older than the shadow copy.
    case sharedOlder(sharedRevision: Int, shadowRevision: Int)
    /// The shared data is not the data the shadow copy came from.
    case sharedIsDifferent
    case sharedMissing
    case sharedUnreadable(String)

    /// The ones that need the person's decision before the app opens the data.
    var needsDecision: Bool { true }

    var title: String {
        switch self {
        case .otherData: "This shadow copy is of other data"
        case .dataLooksEmpty: "Your data looks empty"
        case .dataMuchSmaller: "Your data has far fewer transactions than the shadow copy"
        case .dataUnreadable: "Your data can't be read"
        case .sharedOlder: "The shared data is older than your shadow copy"
        case .sharedIsDifferent: "The shared data isn't the data your shadow copy came from"
        case .sharedMissing: "The shared data can't be found"
        case .sharedUnreadable: "The shared data can't be read"
        }
    }
}

nonisolated enum ShadowCheck {
    /// Is this shadow copy the data we have? In sharing, by which shared data it came from; alone, by the data's own ID.
    static func belongs(_ info: ShadowInfo, dataID: String, sharedFileID: String?) -> Bool {
        if let sharedFileID {
            if let theirs = info.sharedFileID { return theirs == sharedFileID }
            return info.dataID == dataID
        }
        return info.dataID == dataID
    }

    /// Looks at this Mac's own data file against its shadow copy before the app opens it. Nil means all is well.
    static func lookAtOwnData(store: URL, shadow: ShadowFolder, dataID: String) -> ShadowFinding? {
        guard let info = shadow.readInfo(), shadow.hasStore else { return nil }
        guard belongs(info, dataID: dataID, sharedFileID: nil) else { return .otherData }
        guard FileManager.default.fileExists(atPath: store.path) else {
            // No data file at all while the shadow copy has data: the data was removed.
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

    /// Looks at the shared data against the shadow copy before the app opens it. Nil means all is well.
    static func lookAtSharedData(_ shared: SharedDataFolder, shadow: ShadowFolder, dataID: String) -> ShadowFinding? {
        guard shared.exists, shared.hasStore else {
            return shadow.readInfo() != nil && shadow.hasStore ? .sharedMissing : nil
        }
        do {
            guard try SQLiteStore.integrityIsOK(shared.storeURL) else { return .sharedUnreadable("it failed its integrity check") }
            _ = try SQLiteStore.counts(of: shared.storeURL)
        } catch {
            return .sharedUnreadable(error.localizedDescription)
        }
        guard let info = shadow.readInfo(), shadow.hasStore, let shared = shared.readInfo() else { return nil }
        guard belongs(info, dataID: dataID, sharedFileID: shared.fileID) else { return .sharedIsDifferent }
        if let theirs = info.sharedRevision, info.sharedFileID == shared.fileID, theirs > shared.revision {
            return .sharedOlder(sharedRevision: shared.revision, shadowRevision: theirs)
        }
        return nil
    }
}
