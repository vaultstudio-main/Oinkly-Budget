import AppKit
import SwiftData

/// Keeps the shadow copy: a second, separate copy of the data in a folder the person chose (Documents, say), refreshed on
/// its own. Alone it copies this Mac's data; while sharing it copies the working copy each time the shared data is
/// saved, so it matches the shared data. The app never runs on the shadow copy and never writes over the data from it
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
    private(set) var lastCopy: Date?
    private(set) var versionCount = 0
    private(set) var size: Int64 = 0
    private(set) var folderPath: String?

    private static let bookmarkKey = "shadowCopyFolderBookmark"
    private static let snoozeKey = "shadowCopyAskAgainAfter"
    private static let declinedKey = "shadowCopyDontAsk"
    static let skipCheckKey = "shadowCopySkipCheckOnce"
    static let restoreKey = "shadowCopyRestorePending"

    /// How long after a change the app waits before copying, so a burst of edits makes one copy.
    static let patience: Duration = .seconds(180)
    /// Changes that have waited this long without a copy count as behind.
    static let behindAfter: TimeInterval = 20 * 60

    private var dirty = false
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var failures = 0

    var isSetUp: Bool { UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil }

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
        if dirty { await copyNow() }
    }

    /// The shared data was just saved: make the shadow copy match it.
    func afterSharedSave(revision: Int, fileID: String) async {
        guard isSetUp else { return }
        await copyNow(source: .shared(revision: revision, fileID: fileID))
    }

    // MARK: Copying

    enum Source {
        case thisMac
        case shared(revision: Int, fileID: String)
    }

    /// Makes a copy now. With `onlyIfChanged`, nothing happens when nothing changed since the last one.
    func copyNow(source: Source = .thisMac, onlyIfChanged: Bool = true) async {
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
        status = .copying
        dirty = false
        let accessing = parent.startAccessingSecurityScopedResource()
        let result: Result<ShadowInfo, Error> = await Task.detached {
            let folder = ShadowFolder(inside: parent)
            if let existing = folder.readInfo(), !ShadowCheck.belongs(existing, dataID: id, sharedFileID: fileID) {
                return .failure(ShadowCopyManager.OtherData())
            }
            do { return .success(try folder.write(from: live, dataID: id, source: sourceName, sharedRevision: revision, sharedFileID: fileID, appVersion: version)) }
            catch { return .failure(error) }
        }.value
        if accessing { parent.stopAccessingSecurityScopedResource() }
        switch result {
        case .success(let info):
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
        let details: (Int, Int64, Date?) = await Task.detached {
            let folder = ShadowFolder(inside: parent)
            return (folder.olderVersions().count + (folder.hasStore ? 1 : 0), folder.size(), folder.readInfo()?.savedAt)
        }.value
        if accessing { parent.stopAccessingSecurityScopedResource() }
        versionCount = details.0
        size = details.1
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

    /// Asks where to keep the shadow copy, remembers the permission, and starts copying.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.message = "Choose where to keep your shadow copy. A folder called “\(ShadowFolder.folderName)” is made inside it."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.declinedKey)
        folderPath = url.path
        failures = 0
        status = .behind(nil)
        dirty = true
        Task { await copyNow(onlyIfChanged: false) }
    }

    /// Stops copying. What is already in the folder stays.
    func turnOff() {
        pending?.cancel()
        pending = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        folderPath = nil
        lastCopy = nil
        versionCount = 0
        size = 0
        status = .notSetUp
    }

    /// Starts a new shadow copy in the same folder, for when the one there is of other data.
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

    /// True when it is time to offer a shadow copy: nothing set up, the person has put some data in, and they haven't
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

    /// Whether a shadow copy is set up, for code that runs before the app is ready.
    nonisolated static var isSetUpNow: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// Looks at this Mac's data against the shadow copy before the app opens it. Nil means all is well (or there is no
    /// shadow copy, or the person chose to keep their data as it is for this start).
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

    // MARK: This data's name

    /// A name for this Mac's data, kept beside the data file, so a shadow copy of other data is noticed.
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
            guard ClosingCountdown.run(.restart, reason: "It restarts to restore your data from the shadow copy. Finish anything you are doing now.") else { return false }
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
        guard let path = defaults.string(forKey: restoreKey) else { return nil }
        defaults.removeObject(forKey: restoreKey)
        guard let data = defaults.data(forKey: bookmarkKey) else { return "The shadow copy folder wasn't set up, so nothing was restored." }
        var stale = false
        guard let parent = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return "The shadow copy folder couldn't be opened, so nothing was restored."
        }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        let folder = ShadowFolder(inside: parent)
        guard let version = folder.allVersions().first(where: { $0.url.path == path }) else { return "That shadow copy couldn't be found, so nothing was restored." }
        do {
            let backups = URL.applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("Before restoring a shadow copy (\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))))", isDirectory: true)
            if FileManager.default.fileExists(atPath: localStore.path) { _ = try StoreFiles.snapshot(of: localStore, into: backups) }
            try folder.restore(version, to: localStore)
            return "Restored your data from the shadow copy made \(version.info.savedAt.formatted(date: .abbreviated, time: .shortened)). What was there before is in Application Support ▸ Backups."
        } catch {
            return "The shadow copy couldn't be restored: \(error.localizedDescription) Your data was not changed."
        }
    }

    /// For the rescue screen and Settings: what is in the shadow copy, newest first, without keeping access open.
    func versions() async -> [ShadowVersion] {
        guard let parent = resolveParent() else { return [] }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
        return await Task.detached { ShadowFolder(inside: parent).allVersions() }.value
    }
}
