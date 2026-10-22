import AppKit
import SwiftData

/// Keeps the backup copy: a second, separate copy of the data in a folder the person chose (Documents, say), refreshed on
/// its own. Alone it copies this Mac's data; while sharing it copies the working copy each time the shared data is
/// saved, so it matches the shared data. The app never runs on the backup copy and never writes over the data from it
/// without asking.
@MainActor
@Observable
final class ShadowCopyManager {
    static let shared = ShadowCopyManager()

    enum Status: Equatable {
        case notSetUp
        case copying
        case upToDate(Date)
        /// Changes have waited too long for the next copy.
        case behind(Date?)
        case folderMissing
        case otherData
        case failed(String)
    }

    private(set) var status: Status = .notSetUp
    /// Whether the backup copy is on, for the switch in Settings (which needs something it can watch).
    private(set) var isOn = UserDefaults.standard.data(forKey: "shadowCopyFolderBookmark") != nil
    private(set) var lastCopy: Date?
    private(set) var versionCount = 0
    private(set) var size: Int64 = 0
    private(set) var folderPath: String?
    /// When the newest portable .pig file in the backup copy was made.
    private(set) var lastPortable: Date?
    private(set) var portableCount = 0
    /// True when something asked Settings to scroll to the backup copy. Settings clears it once it has.
    var revealRequested = false

    private static let bookmarkKey = "shadowCopyFolderBookmark"
    private static let snoozeKey = "shadowCopyAskAgainAfter"
    private static let declinedKey = "shadowCopyDontAsk"
    static let skipCheckKey = "shadowCopySkipCheckOnce"
    static let skipSharedCheckKey = "shadowCopySkipSharedCheckOnce"
    static let restoreKey = "shadowCopyRestorePending"
    nonisolated static let portableRestoreKey = "shadowCopyPortableRestorePending"
    /// A portable file is made at most this often by the timed copies (quitting and Copy Now always make one).
    static let portableEvery: TimeInterval = 24 * 3600
    /// Building the portable file holds the window for as long as it takes to read all the data. When that took longer than
    /// this, the timed copies leave it to quitting and Copy Now, so nobody is ever stuck waiting at a random moment.
    static let portableBuildLimit: TimeInterval = 1.5
    private static let portableBuildKey = "shadowCopyPortableBuildSeconds"

    /// How long after a change the app waits before copying, so a burst of edits makes one copy.
    static let patience: Duration = .seconds(180)
    /// Changes that have waited this long without a copy count as behind.
    static let behindAfter: TimeInterval = 20 * 60

    private var dirty = false
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var failures = 0

    var isSetUp: Bool {
        #if DEBUG
        if let preview { return preview.isSetUp }
        #endif
        return UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    #if DEBUG
    /// For the debug picture of Settings only: shows the page as if a backup copy were (or weren't) set up.
    var preview: (isSetUp: Bool, status: Status)?

    func showPreview(isSetUp: Bool, status: Status, path: String?, copies: Int, bytes: Int64, lastCopy: Date?, lastPortable: Date?, portables: Int) {
        preview = (isSetUp, status)
        isOn = isSetUp
        self.status = status
        folderPath = path
        versionCount = copies
        size = bytes
        self.lastCopy = lastCopy
        self.lastPortable = lastPortable
        portableCount = portables
    }
    #endif

    private init() {
        refreshStatus()
    }

    // MARK: Starting

    /// Begins watching for changes. Safe to call more than once.
    func start() {
        guard observers.isEmpty, !ScreenshotMode.isOn else { return }
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ShadowCopyManager.shared.noteChange() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ShadowCopyManager.shared.copyAtHide() }
        })
        if isSetUp {
            Task {
                if let shared = SharedDataSession.shared.shadowSource {
                    await afterSharedSave(revision: shared.revision, fileID: shared.fileID)
                } else if let fresh = await shadowIsNewerThanData() {
                    // Nothing changed since the last copy: just say so.
                    lastCopy = fresh
                    refreshStatus()
                    await reloadDetails()
                } else {
                    await copyNow(onlyIfChanged: false)
                }
            }
        }
        refreshStatus()
    }

    /// The time of the last copy, when it is newer than anything changed in this Mac's data since.
    private func shadowIsNewerThanData() async -> Date? {
        guard let parent = resolveParent() else { return nil }
        let store = AppStore.localStoreURL(for: Schema(versionedSchema: OinklyBudgetSchemaV4.self))
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        return await Task.detached {
            guard let saved = ShadowFolder(inside: parent).readInfo()?.savedAt else { return nil }
            let newest = ["", "-wal"].compactMap { suffix in
                (try? FileManager.default.attributesOfItem(atPath: store.path + suffix))?[.modificationDate] as? Date
            }.max()
            guard let newest, saved >= newest else { return nil }
            return saved
        }.value
    }

    /// Only copies while the app is running on the real data, never on the stand-in used while it waits or when the data can't open.
    private var canCopyNow: Bool {
        !ScreenshotMode.isOn && !StartupState.isHoldingPlace && isSetUp
    }

    // MARK: Changes

    func noteChange() {
        guard isSetUp, !SharedDataSession.shared.isActive else { return }
        dirty = true
        refreshStatus()
        guard pending == nil else { return }
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.patience)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            await self?.copyNow()
        }
    }

    private func copyAtHide() {
        guard isSetUp, dirty, !SharedDataSession.shared.isActive else { return }
        pending?.cancel()
        pending = nil
        Task { await copyNow() }
    }

    /// Called as the app quits, so the last changes are copied too.
    func copyForQuit() async {
        guard isSetUp, !SharedDataSession.shared.isActive else { return }
        pending?.cancel()
        pending = nil
        if dirty { await copyNow(portable: .always) }
    }

    /// The shared data was just saved: make the backup copy match it.
    func afterSharedSave(revision: Int, fileID: String) async {
        guard isSetUp else { return }
        await copyNow(source: .shared(revision: revision, fileID: fileID))
    }

    // MARK: Copying

    enum Source {
        case thisMac
        case shared(revision: Int, fileID: String)
    }

    /// Whether a copy also makes the portable .pig file: always, only when the last one is a day old, or not at all.
    enum PortableMode { case never, ifDue, always }

    /// Makes a copy now. With `onlyIfChanged`, nothing happens when nothing changed since the last one. Each copy is a
    /// snapshot of the data file; a portable .pig file is made beside it when it is due.
    func copyNow(source: Source = .thisMac, onlyIfChanged: Bool = true, portable: PortableMode = .ifDue) async {
        guard canCopyNow else { return }
        if onlyIfChanged, !dirty, case .thisMac = source, lastCopy != nil { return }
        guard let parent = resolveParent() else {
            status = .folderMissing
            return
        }
        let schema = Schema(versionedSchema: OinklyBudgetSchemaV4.self)
        let live: URL
        let sourceName: String
        var revision: Int?
        var fileID: String?
        switch source {
        case .thisMac:
            live = AppStore.localStoreURL(for: schema)
            sourceName = "This Mac"
            OinklyBudgetAppDelegate.container?.mainContext.saveNow()
        case .shared(let sharedRevision, let sharedFileID):
            live = SharedDataSession.workingStore
            sourceName = "Shared data"
            revision = sharedRevision
            fileID = sharedFileID
        }
        let id = Self.dataID(beside: AppStore.localStoreURL(for: schema))
        let version = AppVersion.display
        // The portable file is built here, from what is on screen, because reading the data needs the main thread. Sealing
        // and writing it happen in the background with the snapshot.
        let makePortable: Bool
        switch portable {
        case .never: makePortable = false
        case .always: makePortable = true
        case .ifDue:
            let lastBuild = UserDefaults.standard.double(forKey: Self.portableBuildKey)
            makePortable = (lastPortable.map { Date.now.timeIntervalSince($0) > Self.portableEvery } ?? true) && lastBuild < Self.portableBuildLimit
        }
        var portableJSON: Data?
        var portableInfo: PortableInfo?
        if makePortable, let context = OinklyBudgetAppDelegate.container?.mainContext {
            let begin = Date()
            if let file = try? DataBackup.make(from: context), let json = try? DataBackup.plainJSON(file) {
                portableJSON = json
                portableInfo = DataBackup.portableInfo(file, source: sourceName)
            }
            UserDefaults.standard.set(Date().timeIntervalSince(begin), forKey: Self.portableBuildKey)
        }
        status = .copying
        dirty = false
        let accessing = parent.startAccessingSecurityScopedResource()
        let json = portableJSON
        let pinfo = portableInfo
        let result: Result<(ShadowInfo, Bool), Error> = await Task.detached {
            let folder = ShadowFolder(inside: parent)
            if let existing = folder.readInfo(), !ShadowCheck.belongs(existing, dataID: id, sharedFileID: fileID) {
                return .failure(ShadowCopyManager.OtherData())
            }
            do {
                let info = try folder.write(from: live, dataID: id, source: sourceName, sharedRevision: revision, sharedFileID: fileID, appVersion: version)
                var wrotePortable = false
                if let json, let pinfo { wrotePortable = (try? folder.writePortable(json: json, info: pinfo, matching: info, appVersion: version)) ?? false }
                return .success((info, wrotePortable))
            } catch { return .failure(error) }
        }.value
        if accessing { parent.stopAccessingSecurityScopedResource() }
        switch result {
        case .success(let (info, wrotePortable)):
            if wrotePortable { lastPortable = pinfo?.savedAt }
            failures = 0
            lastCopy = info.savedAt
            status = .upToDate(info.savedAt)
            await refreshDetails(parent: parent)
        case .failure(let error):
            dirty = true
            if error is OtherData {
                status = .otherData
            } else {
                failures += 1
                status = failures >= 2 ? .failed(error.localizedDescription) : .behind(lastCopy)
            }
        }
    }

    private struct OtherData: Error {}

    private func refreshStatus() {
        guard isSetUp else { status = .notSetUp; return }
        switch status {
        case .copying, .folderMissing, .otherData, .failed: return
        default: break
        }
        if let lastCopy {
            status = dirty && Date.now.timeIntervalSince(lastCopy) > Self.behindAfter ? .behind(lastCopy) : .upToDate(lastCopy)
        } else if case .notSetUp = status {
            status = .behind(nil)
        }
    }

    /// Looks at the status again, for the label that is on screen. Cheap.
    func tick() {
        guard isSetUp else { status = .notSetUp; return }
        if case .upToDate(let when) = status, dirty, Date.now.timeIntervalSince(when) > Self.behindAfter { status = .behind(when) }
    }

    private func refreshDetails(parent: URL) async {
        let accessing = parent.startAccessingSecurityScopedResource()
        let details: (Int, Int64, Date?, Int, Date?) = await Task.detached {
            let folder = ShadowFolder(inside: parent)
            let portables = folder.portableVersions()
            return (folder.olderVersions().count + (folder.hasStore ? 1 : 0), folder.size(), folder.readInfo()?.savedAt, portables.count, portables.first?.info.savedAt)
        }.value
        if accessing { parent.stopAccessingSecurityScopedResource() }
        versionCount = details.0
        size = details.1
        portableCount = details.3
        lastPortable = details.4
        if lastCopy == nil { lastCopy = details.2 }
        folderPath = parent.path
    }

    /// Reads what is in the folder, for Settings.
    func reloadDetails() async {
        guard let parent = resolveParent() else { return }
        await refreshDetails(parent: parent)
        refreshStatus()
    }

    // MARK: The folder

    /// The folder the person chose, from the permission the app saved when they chose it. Nil when it can't be found.
    func resolveParent() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        folderPath = url.path
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Asks where to keep the backup copy, remembers the permission, and starts copying.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.message = "Choose where to keep your backup copy. A folder called “\(ShadowFolder.folderName)” is made inside it."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.declinedKey)
        isOn = true
        folderPath = url.path
        failures = 0
        status = .behind(nil)
        dirty = true
        Task { await copyNow(onlyIfChanged: false, portable: .always) }
    }

    /// Stops copying. What is already in the folder stays.
    func turnOff() {
        pending?.cancel()
        pending = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        isOn = false
        folderPath = nil
        lastCopy = nil
        versionCount = 0
        size = 0
        status = .notSetUp
    }

    /// Turns the backup copy off and moves its folder to the Trash (or removes it if the Trash can't be used).
    func turnOffAndDeleteFolder() {
        if let parent = resolveParent() {
            let accessing = parent.startAccessingSecurityScopedResource()
            ShadowFolder(inside: parent).removeToTrash()
            if accessing { parent.stopAccessingSecurityScopedResource() }
        }
        turnOff()
    }

    /// Starts a new backup copy in the same folder, for when the one there is of other data.
    func replaceExisting() async {
        guard let parent = resolveParent() else { return }
        let accessing = parent.startAccessingSecurityScopedResource()
        await Task.detached { ShadowFolder(inside: parent).removeAll() }.value
        if accessing { parent.stopAccessingSecurityScopedResource() }
        failures = 0
        status = .behind(nil)
        await copyNow(onlyIfChanged: false)
    }

    /// Deletes the copies in the folder (used when erasing all data on request).
    func deleteCopies() {
        guard let parent = resolveParent() else { return }
        let accessing = parent.startAccessingSecurityScopedResource()
        ShadowFolder(inside: parent).removeAll()
        if accessing { parent.stopAccessingSecurityScopedResource() }
        lastCopy = nil
        versionCount = 0
        size = 0
        status = .behind(nil)
    }

    func revealInFinder() {
        guard let parent = resolveParent() else { return }
        let folder = ShadowFolder(inside: parent)
        let accessing = parent.startAccessingSecurityScopedResource()
        NSWorkspace.shared.activateFileViewerSelecting([folder.exists ? folder.url : parent])
        if accessing { parent.stopAccessingSecurityScopedResource() }
    }

    // MARK: Asking the first time

    /// True when it is time to offer a backup copy: nothing set up, the person has put some data in, and they haven't
    /// said no. "Not now" waits a week.
    func shouldAsk(hasData: Bool) -> Bool {
        guard !isSetUp, hasData, !ScreenshotMode.isOn, !StartupState.isHoldingPlace else { return false }
        if UserDefaults.standard.bool(forKey: Self.declinedKey) { return false }
        if let after = UserDefaults.standard.object(forKey: Self.snoozeKey) as? Date, after > .now { return false }
        return true
    }

    func snoozeAsking() { UserDefaults.standard.set(Date.now.addingTimeInterval(7 * 86_400), forKey: Self.snoozeKey) }
    func stopAsking() { UserDefaults.standard.set(true, forKey: Self.declinedKey) }

    /// True when quitting should wait for one more copy.
    var needsCopyAtQuit: Bool { isSetUp && dirty && !SharedDataSession.shared.isActive && !StartupState.isHoldingPlace && !ScreenshotMode.isOn }

    /// Whether a backup copy is set up, for code that runs before the app is ready.
    nonisolated static var isSetUpNow: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// Looks at this Mac's data against the backup copy before the app opens it. Nil means all is well (or there is no
    /// backup copy, or the person chose to keep their data as it is for this start).
    nonisolated static func launchFinding(localStore: URL) -> ShadowFinding? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: skipCheckKey) {
            defaults.removeObject(forKey: skipCheckKey)
            return nil
        }
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let parent = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        return ShadowCheck.lookAtOwnData(store: localStore, shadow: ShadowFolder(inside: parent), dataID: dataID(beside: localStore))
    }

    /// Looks at the shared data against the backup copy before the app opens it. Nil means all is well.
    nonisolated static func sharedFinding(_ shared: SharedDataFolder, localStore: URL) -> ShadowFinding? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: skipSharedCheckKey) {
            defaults.removeObject(forKey: skipSharedCheckKey)
            return nil
        }
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let parent = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        return ShadowCheck.lookAtSharedData(shared, shadow: ShadowFolder(inside: parent), dataID: dataID(beside: localStore))
    }

    /// Puts the shared data back from a copy in the backup copy folder.
    func rebuildShared(from version: ShadowVersion, shared: SharedDataFolder = .standard) async throws {
        guard let parent = resolveParent() else { throw ShadowError.unavailable("the backup copy folder can't be found") }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        let me = SharedLock(token: UUID().uuidString, userName: NSUserName(), fullName: NSFullUserName(), since: .now, heartbeat: .now,
                            pid: ProcessInfo.processInfo.processIdentifier, host: ProcessInfo.processInfo.hostName)
        let appVersion = AppVersion.display
        let staging = URL.applicationSupportDirectory.appendingPathComponent("SharedRescue", isDirectory: true)
        try await Task.detached {
            try SharedRescue.rebuild(shared, from: version, in: ShadowFolder(inside: parent), me: me, appVersion: appVersion, staging: staging)
        }.value
    }

    /// For a new Mac: asks for the folder that holds a backup copy, remembers it, and restores the newest good copy at
    /// the next start. Returns false when nothing was chosen or the folder holds no backup copy.
    func restoreFromChosenFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose the folder that contains “\(ShadowFolder.folderName)”."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return restoreFromFolder(url)
    }

    /// Restores from the backup copy inside `url` (a folder the person chose) at the next start: the newest good snapshot,
    /// or the newest good portable file when no snapshot is usable. Returns a problem to show, or nil.
    func restoreFromFolder(_ url: URL) -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let folder = ShadowFolder(inside: url)
        guard folder.exists else {
            return FileManager.default.fileExists(atPath: url.appendingPathComponent(ShadowFolder.storeName).path)
                ? "That is the backup copy folder itself. Choose the folder that contains it instead."
                : "There is no “\(ShadowFolder.folderName)” folder in there."
        }
        let snapshot = folder.newestGoodVersion()
        let portable = snapshot == nil ? folder.newestGoodPortable() : nil
        guard snapshot != nil || portable != nil else { return "That backup copy has no good copy in it." }
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return "The app couldn't keep access to that folder."
        }
        let when = snapshot?.info.savedAt ?? portable?.info.savedAt ?? .now
        let transactions = snapshot?.info.transactions ?? portable?.info.transactions ?? 0
        guard ClosingCountdown.run(.restart, reason: "It restarts to bring back your data from the backup copy made \(when.formatted(date: .abbreviated, time: .shortened)), with \(transactions.formatted()) transactions.") else { return nil }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        if let snapshot { UserDefaults.standard.set(snapshot.url.path, forKey: Self.restoreKey) }
        else if let portable { UserDefaults.standard.set(portable.url.path, forKey: Self.portableRestoreKey) }
        UserDefaults.standard.synchronize()
        AppStore.relaunch()
        return nil
    }

    // MARK: This data's name

    /// A name for this Mac's data, kept beside the data file, so a backup copy of other data is noticed.
    nonisolated static func dataID(beside store: URL) -> String {
        let file = store.deletingLastPathComponent().appendingPathComponent("shadow-data-id.txt")
        if let text = try? String(contentsOf: file, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = UUID().uuidString
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? id.write(to: file, atomically: true, encoding: .utf8)
        return id
    }

    // MARK: Restoring

    /// Asks for a copy to be put in place of this Mac's data at the next start, then restarts. The swap itself happens
    /// before the app opens its data, with a safety copy of what is there.
    func requestRestore(_ version: ShadowVersion, countdown: Bool = true) -> Bool {
        if countdown {
            guard ClosingCountdown.run(.restart, reason: "It restarts to restore your data from the backup copy. Finish anything you are doing now.") else { return false }
        }
        UserDefaults.standard.set(version.url.path, forKey: Self.restoreKey)
        UserDefaults.standard.synchronize()
        AppStore.relaunch()
        return true
    }

    /// Runs before the data is opened: if a restore was asked for, makes a safety copy and puts the chosen copy in place.
    /// Returns a note to show afterwards.
    nonisolated static func performPendingRestore(localStore: URL) -> String? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: stagedRestoreKey) { return performStagedRestore(localStore: localStore) }
        guard let path = defaults.string(forKey: restoreKey) else { return nil }
        defaults.removeObject(forKey: restoreKey)
        guard let data = defaults.data(forKey: bookmarkKey) else { return "The backup copy folder wasn't set up, so nothing was restored." }
        var stale = false
        guard let parent = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return "The backup copy folder couldn't be opened, so nothing was restored."
        }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        let folder = ShadowFolder(inside: parent)
        guard let version = folder.allVersions().first(where: { $0.url.path == path }) else { return "That backup copy couldn't be found, so nothing was restored." }
        do {
            let backups = URL.applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("Before restoring a backup copy (\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))))", isDirectory: true)
            if FileManager.default.fileExists(atPath: localStore.path) { _ = try StoreFiles.snapshot(of: localStore, into: backups) }
            try folder.restore(version, to: localStore)
            // This data now is the data the backup copy came from, on a new Mac as much as on the old one.
            let idFile = localStore.deletingLastPathComponent().appendingPathComponent("shadow-data-id.txt")
            if !version.info.dataID.isEmpty { try? version.info.dataID.write(to: idFile, atomically: true, encoding: .utf8) }
            return "Restored your data from the backup copy made \(version.info.savedAt.formatted(date: .abbreviated, time: .shortened)). What was there before is in Application Support ▸ Backups."
        } catch {
            return "The backup copy couldn't be restored: \(error.localizedDescription) Your data was not changed."
        }
    }

    nonisolated static let stagedRestoreKey = "shadowCopyStagedRestore"
    nonisolated private static let stagedRestoreIDKey = "shadowCopyStagedRestoreDataID"
    nonisolated private static var stagedFolder: URL { URL.applicationSupportDirectory.appendingPathComponent("PendingRestore", isDirectory: true) }

    /// A copy that was opened from Finder was unpacked into the app's own folder before the restart; this puts it in
    /// place, after a safety copy of what is there. Runs before the data is opened.
    nonisolated private static func performStagedRestore(localStore: URL) -> String? {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: stagedRestoreKey)
        let staged = stagedFolder.appendingPathComponent("OinklyBudget.store")
        defer { try? FileManager.default.removeItem(at: stagedFolder) }
        guard FileManager.default.fileExists(atPath: staged.path) else { return "The copy to restore couldn't be found, so nothing was restored." }
        do {
            let backups = URL.applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("Before restoring a copy (\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))))", isDirectory: true)
            if FileManager.default.fileExists(atPath: localStore.path) { _ = try StoreFiles.snapshot(of: localStore, into: backups) }
            StoreFiles.remove(store: localStore)
            try FileManager.default.createDirectory(at: localStore.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staged, to: localStore)
            if let id = defaults.string(forKey: stagedRestoreIDKey), !id.isEmpty {
                try? id.write(to: localStore.deletingLastPathComponent().appendingPathComponent("shadow-data-id.txt"), atomically: true, encoding: .utf8)
            }
            defaults.removeObject(forKey: stagedRestoreIDKey)
            return "Restored your data from the copy you opened. What was there before is in Application Support ▸ Backups. Receipts and photos are only brought back when you restore from Settings ▸ Data & Backup ▸ Backup Copy."
        } catch {
            return "The copy couldn't be restored: \(error.localizedDescription) Your data was not changed."
        }
    }

    /// Unpacks a copy opened from Finder into the app's own folder and restarts to restore it. Returns a problem to show, or nil.
    func stageRestore(from url: URL, info: ShadowInfo) -> String? {
        let staged = Self.stagedFolder.appendingPathComponent("OinklyBudget.store")
        try? FileManager.default.removeItem(at: Self.stagedFolder)
        do {
            try FileManager.default.createDirectory(at: Self.stagedFolder, withIntermediateDirectories: true)
            try SealedFile.unseal(url, to: staged)
            guard (try? SQLiteStore.integrityIsOK(staged)) == true, let counts = try? SQLiteStore.counts(of: staged),
                  counts["ZACCOUNT"] == info.accounts, counts["ZTRANSACTION"] == info.transactions else {
                try? FileManager.default.removeItem(at: Self.stagedFolder)
                return "What came out of that copy isn't the data it should be, so nothing was changed."
            }
        } catch {
            try? FileManager.default.removeItem(at: Self.stagedFolder)
            return error.localizedDescription
        }
        UserDefaults.standard.set(true, forKey: Self.stagedRestoreKey)
        UserDefaults.standard.set(info.dataID, forKey: Self.stagedRestoreIDKey)
        UserDefaults.standard.synchronize()
        return nil
    }

    /// Asks for a portable .pig file of the backup copy to be put in place of this Mac's data at the next start, then
    /// restarts. The swap happens before the data is opened (see `preparePortableRestore`).
    func requestRestore(portable file: PortableVersion, countdown: Bool = true) -> Bool {
        if countdown {
            guard ClosingCountdown.run(.restart, reason: "It restarts to restore your data from the backup copy's portable file. Finish anything you are doing now.") else { return false }
        }
        UserDefaults.standard.set(file.url.path, forKey: Self.portableRestoreKey)
        UserDefaults.standard.synchronize()
        AppStore.relaunch()
        return true
    }

    /// Runs before the data is opened: if a portable restore was asked for, reads the file, makes a safety copy of this
    /// Mac's data and clears it away. The caller opens a fresh data file and imports the returned file into it.
    @MainActor
    static func preparePortableRestore(localStore: URL) -> (file: BackupFile?, note: String?) {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: portableRestoreKey) else { return (nil, nil) }
        defaults.removeObject(forKey: portableRestoreKey)
        guard !SharedDataSession.isEnabled else { return (nil, "A portable file restores this Mac's own data, so nothing was restored while sharing is on.") }
        guard let data = defaults.data(forKey: bookmarkKey) else { return (nil, "The backup copy folder wasn't set up, so nothing was restored.") }
        var stale = false
        guard let parent = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return (nil, "The backup copy folder couldn't be opened, so nothing was restored.")
        }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        let folder = ShadowFolder(inside: parent)
        guard let portable = folder.portableVersions().first(where: { $0.url.path == path }), folder.isGood(portable) else {
            return (nil, "That portable file couldn't be found or didn't pass its check, so nothing was restored.")
        }
        do {
            let file = try DataBackup.decode(try Data(contentsOf: portable.url))
            let backups = URL.applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("Before restoring a backup copy (\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))))", isDirectory: true)
            if FileManager.default.fileExists(atPath: localStore.path) { _ = try StoreFiles.snapshot(of: localStore, into: backups) }
            StoreFiles.remove(store: localStore)
            return (file, "Restored your data from the backup copy's portable file made \(portable.info.savedAt.formatted(date: .abbreviated, time: .shortened)). What was there before is in Application Support ▸ Backups.")
        } catch {
            return (nil, "The portable file couldn't be restored: \(error.localizedDescription) Your data was not changed.")
        }
    }

    /// The portable files in the backup copy, newest first.
    func portableVersions() async -> [PortableVersion] {
        guard let parent = resolveParent() else { return [] }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        return await Task.detached { ShadowFolder(inside: parent).portableVersions() }.value
    }

    /// For the rescue screen and Settings: what is in the backup copy, newest first, without keeping access open.
    func versions() async -> [ShadowVersion] {
        guard let parent = resolveParent() else { return [] }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        return await Task.detached { ShadowFolder(inside: parent).allVersions() }.value
    }
}


/// Opening a copy from Finder (a `.pigdata` file): say what is in it, ask first, then restore it.
@MainActor
enum CopyOpener {
    static func offerRestore(of url: URL) async {
        // A launch by double-click arrives before the app is ready. Wait for the main window.
        for _ in 0..<40 where !NSApp.windows.contains(where: { $0.title == "Oinkly Budget" && $0.isVisible }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let header = try? SealedFile.readHeader(url), header.kind == "data", let data = header.info,
              let info = try? SealedFile.decodeInfo(ShadowInfo.self, from: data) else {
            show(title: "Couldn't open that file", text: "It isn't a copy of Oinkly Budget data, or it is damaged or from a newer version.")
            return
        }
        guard !SharedDataSession.isEnabled else {
            show(title: "Sharing is on", text: "A copy restores this Mac's own data. Stop sharing first, or restore from the backup copy in Settings.")
            return
        }
        guard SealedFile.isIntact(url) else {
            show(title: "That copy is damaged", text: "It didn't pass its check, so nothing was changed.")
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restore from this copy?"
        alert.informativeText = "\(url.lastPathComponent) was made \(info.savedAt.formatted(date: .abbreviated, time: .shortened)) and holds \(info.accounts) accounts and \(info.transactions.formatted()) transactions. Everything currently in Oinkly Budget is replaced with it. A copy of what is there now is kept first. Receipts and photos aren't in a single file; restore from Settings ▸ Data & Backup ▸ Backup Copy to bring those back too."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let problem = ShadowCopyManager.shared.stageRestore(from: url, info: info) {
            show(title: "Couldn't restore that copy", text: problem)
            return
        }
        guard ClosingCountdown.run(.restart, reason: "It restarts to restore your data from the copy you opened. Finish anything you are doing now.") else { return }
        AppStore.relaunch()
    }

    private static func show(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
