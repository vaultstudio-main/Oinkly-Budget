import AppKit
import SwiftData

/// Sharing one data file with other Mac logins, one at a time.
///
/// With sharing on, the app doesn't open the shared file itself. At launch it takes the lock, copies the finished file
/// into a private working copy in its own storage, and works on that. The working copy goes back to the shared folder
/// every couple of minutes while there are changes, when the app is hidden and when it quits, and then the lock is let
/// go. If another login has the data open, the app waits and says so; nothing is ever closed or taken for anyone, except
/// that a copy that has gone quiet for three minutes can be taken over (it has crashed or is asleep).
/// With sharing off, none of this runs and the app uses this Mac's own data as before.
@MainActor
@Observable
final class SharedDataSession {
    static let shared = SharedDataSession()

    // MARK: What a launch decided

    /// What the app has to tell the person before it can open any data.
    enum Decision: Equatable {
        /// Someone else has the data open. `isStale` means their copy has gone quiet and probably stopped.
        case heldBy(SharedLock, isStale: Bool)
        case folderProblem(String)
        case failed(String)
        /// The shared data and the backup copy disagree; the person decides before anything opens.
        case shadowFound(ShadowFinding)
    }

    enum Outcome {
        case local
        case shared(workingStore: URL)
        case waiting
    }

    private(set) var decision: Decision?
    private(set) var isActive = false
    /// Someone took the lock while this copy was asleep or stuck. Nothing more can be saved into the shared data.
    private(set) var lostLock = false
    private(set) var lastSaved: Date?
    /// Shown once after launch, such as "closed unexpectedly, your changes were kept".
    var notice: String?
    var errorMessage: String?

    private var folder: SharedDataFolder?
    private var baseRevision: Int?
    private var fileID: String?

    /// Which save of which shared data this copy was opened from, for the backup copy.
    var shadowSource: (revision: Int, fileID: String)? {
        guard isActive, let baseRevision, let fileID else { return nil }
        return (baseRevision, fileID)
    }
    private let me = SharedLock(token: UUID().uuidString, userName: NSUserName(), fullName: NSFullUserName(), since: .now, heartbeat: .now,
                                pid: ProcessInfo.processInfo.processIdentifier, host: ProcessInfo.processInfo.hostName)
    private var heartbeatTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var isDirty = false
    private var isCheckingIn = false

    /// How the shared data stands, for the dot in the status bar.
    enum Status: Equatable {
        /// Everything is saved to the shared data.
        case saved
        /// There are changes that will be saved within a couple of minutes, or are being saved now.
        case unsaved
        case problem(String)
    }

    /// Nil when this copy isn't using shared data.
    var status: Status? {
        guard Self.isEnabled, isActive else { return nil }
        if lostLock { return .problem("Someone else opened the shared data. Quit and open Oinkly Budget again.") }
        if let errorMessage { return .problem(errorMessage) }
        return isDirty || isCheckingIn ? .unsaved : .saved
    }

    static let enabledKey = "sharedData.enabled"
    private static let nextLaunchKey = "sharedData.nextLaunch"

    /// True once sharing has been turned on for this Mac login.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }

    // MARK: Locations

    static var workingDirectory: URL { URL.applicationSupportDirectory.appendingPathComponent("SharedWorking", isDirectory: true) }
    static var workingStore: URL { workingDirectory.appendingPathComponent(SharedDataFolder.storeName) }
    private static var markerURL: URL { workingDirectory.appendingPathComponent("open.json") }

    // MARK: Launch

    /// Decides what the app opens. Runs once, before the database is opened.
    func prepareAtLaunch() -> Outcome {
        guard Self.isEnabled else {
            #if DEBUG
            NSLog("SHARED: sharing is off")
            #endif
            return .local
        }
        let folder = SharedDataFolder.standard
        self.folder = folder
        let openAnyway = Self.takeNextLaunchChoice()
        // The backup copy gets a look first: missing, damaged, older or different shared data is put to the person.
        if let finding = ShadowCopyManager.sharedFinding(folder, localStore: AppStore.localStoreURL(for: Schema(versionedSchema: OinklyBudgetSchemaV5.self))) {
            decision = .shadowFound(finding)
            return .waiting
        }
        guard folder.exists, folder.hasData else {
            decision = .folderProblem("The shared data can't be found in \(folder.url.path). It may have been moved or deleted.")
            return .waiting
        }
        do {
            var mine = me
            mine.since = .now
            mine.heartbeat = .now
            var result = try folder.acquire(mine, takeOver: openAnyway)
            if case .heldBy(let lock, let stale) = result, stale, lock.userName == mine.userName {
                // This login's own earlier run that closed unexpectedly is not "someone else": take over and recover.
                result = try folder.acquire(mine, takeOver: true)
            }
            if case .heldBy(let lock, let stale) = result {
                decision = .heldBy(lock, isStale: stale)
                #if DEBUG
                NSLog("SHARED: waiting, held by \(lock.displayName), stale \(stale)")
                #endif
                return .waiting
            }
            let recovered: String?
            do { recovered = try openWorkingCopy(from: folder) } catch { folder.release(token: mine.token); throw error }
            isActive = true
            folder.noteMember(userName: mine.userName, fullName: mine.fullName)
            lastSaved = folder.readInfo()?.savedAt
            if let recovered { notice = recovered }
            startTimers()
            return .shared(workingStore: Self.workingStore)
        } catch {
            decision = .failed(error.localizedDescription)
            return .waiting
        }
    }

    private struct Marker: Codable {
        var baseRevision: Int?
        var fileID: String?
    }

    private static var markerExists: Bool { FileManager.default.fileExists(atPath: markerURL.path) }

    /// Makes the working copy ready. After a crash it keeps the unsaved work when it can, and never throws it away
    /// silently. Returns a message to show the person when something was recovered.
    private func openWorkingCopy(from folder: SharedDataFolder) throws -> String? {
        let manager = FileManager.default
        // A folder from before the sealed format is converted once, by whoever opens it first.
        try folder.convertLegacyIfNeeded(appVersion: appVersion)
        let info = folder.readInfo()
        var message: String?

        if Self.markerExists, manager.fileExists(atPath: Self.workingStore.path),
           let data = try? Data(contentsOf: Self.markerURL), let marker = try? JSONDecoder().decode(Marker.self, from: data) {
            if marker.baseRevision == info?.revision, marker.fileID == info?.fileID {
                // Nobody saved since: the working copy still has everything, plus what was never written back.
                baseRevision = marker.baseRevision
                fileID = marker.fileID
                isDirty = true
                return "Oinkly Budget closed unexpectedly last time. Your unsaved changes were kept."
            }
            // The shared data changed while this copy was out. Keep this copy as its own file instead of overwriting.
            let kept = try folder.saveRecoveredCopy(from: Self.workingStore)
            message = "Oinkly Budget closed unexpectedly, and the shared data was saved by someone else in the meantime. Your unsaved changes were kept as “\(kept.lastPathComponent)” in the shared folder, and Oinkly Budget opened the latest shared data."
        }
        let copied = try folder.checkOut(to: Self.workingStore)
        baseRevision = copied?.revision
        fileID = copied?.fileID
        try writeMarker()
        return message
    }

    private func writeMarker() throws {
        try FileManager.default.createDirectory(at: Self.workingDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Marker(baseRevision: baseRevision, fileID: fileID)).write(to: Self.markerURL)
    }

    private func removeMarker() { try? FileManager.default.removeItem(at: Self.markerURL) }

    // MARK: The waiting screen

    /// What the waiting screen sees when it looks again.
    enum Waiting {
        case free
        case heldBy(SharedLock, isStale: Bool)
        case problem(String)
    }

    /// Looks at the lock without taking it. The waiting screen calls this every couple of seconds.
    func lookAgain() -> Waiting {
        let folder = SharedDataFolder.standard
        guard folder.exists, folder.hasData else { return .problem("The shared data can't be found in \(folder.url.path).") }
        guard let holder = folder.holder() else { return .free }
        if holder.lock.userName == NSUserName(), holder.isStale { return .free }
        return .heldBy(holder.lock, isStale: holder.isStale)
    }

    /// The other copy has let go: start again, which takes the lock and opens the data.
    func tryAgain() { Self.relaunch() }

    /// Opens the shared data as it is, without asking about the backup copy this time.
    func openSharedAsItIs() {
        UserDefaults.standard.set(true, forKey: ShadowCopyManager.skipSharedCheckKey)
        Self.relaunch()
    }

    /// Makes the newest good earlier save in the shared folder the current data, then starts again. Returns false when
    /// there is no good earlier save.
    func restoreNewestGoodEarlierSave() async throws -> Bool {
        let shared = SharedDataFolder.standard
        let lock = me
        let version = appVersion
        let staging = URL.applicationSupportDirectory.appendingPathComponent("SharedRescue", isDirectory: true)
        let restored = try await Task.detached { try SharedRescue.restoreNewestGoodEarlierSave(shared, me: lock, appVersion: version, staging: staging) }.value
        if restored { Self.relaunch() }
        return restored
    }

    /// The other copy has gone quiet: take the lock anyway.
    func openAnyway() {
        UserDefaults.standard.set("openAnyway", forKey: Self.nextLaunchKey)
        Self.relaunch()
    }

    /// Leave sharing and use this Mac's own data (for when the shared folder is gone).
    func useThisMacsData() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        Self.relaunch()
    }

    private static func takeNextLaunchChoice() -> Bool {
        let value = UserDefaults.standard.string(forKey: nextLaunchKey)
        UserDefaults.standard.removeObject(forKey: nextLaunchKey)
        return value == "openAnyway"
    }

    // MARK: Turning sharing on and off

    /// Copies this Mac's data into the shared folder (or joins the data already there) and relaunches into it. The
    /// original is only read, never changed or removed.
    func enable(localStore: URL, context: ModelContext) throws {
        try? context.save()
        let folder = SharedDataFolder.standard
        try folder.ensureFolder()
        if !folder.hasData {
            try folder.createStore(from: localStore, by: NSFullUserName(), appVersion: appVersion)
        }
        removeMarker()
        folder.noteMember(userName: me.userName, fullName: me.fullName)
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        Self.relaunch()
    }

    /// Back to this Mac's own data. The latest shared data is copied to this Mac, after a copy of what this Mac had
    /// is kept in Application Support ▸ Backups. The shared data stays where it is for the other logins, unless
    /// `removeSharedFolder` is true and nobody else uses it: then the folder goes to the Trash as well.
    func stopSharing(localStore: URL, removeSharedFolder: Bool = false) async throws {
        // The data to bring to this Mac: the working copy, or the saved shared data (which is unpacked first).
        var useSharedData = false
        if isActive, !lostLock {
            await checkInNow(release: true)
            if let folder, folder.hasStore, !isDirty { useSharedData = true }
        } else if let folder, folder.hasStore {
            useSharedData = true
        }
        let sharedFolder = folder ?? SharedDataFolder.standard
        let workingStore = Self.workingStore
        let backups = URL.applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Before stopping sharing (\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))))", isDirectory: true)
        try await Task.detached {
            if FileManager.default.fileExists(atPath: localStore.path) { _ = try StoreFiles.snapshot(of: localStore, into: backups) }
            let staging = URL.applicationSupportDirectory.appendingPathComponent("SharedStaging", isDirectory: true)
            let copy: URL
            if useSharedData {
                try? FileManager.default.removeItem(at: staging)
                copy = staging.appendingPathComponent("OinklyBudget.store")
                try sharedFolder.unpackLatest(to: copy)
            } else {
                copy = try StoreFiles.snapshot(of: workingStore, into: staging)
            }
            defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
            StoreFiles.remove(store: localStore)
            try FileManager.default.createDirectory(at: localStore.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: copy, to: localStore)
            try StoreFiles.copyAttachments(from: copy, to: localStore)
        }.value
        #if DEBUG
        NSLog("SHARED: stopped sharing. Safety copy of this Mac's data: \(FileManager.default.fileExists(atPath: backups.appendingPathComponent("OinklyBudget.store").path) ? "made at \(backups.path)" : "none (no local data)"). This Mac's data now comes from the \(useSharedData ? "saved shared data" : "working copy")")
        #endif
        // This Mac has its copy now. Take this login's note away, and remove the shared folder when asked and safe.
        let leaving = me
        let note: String? = await Task.detached { Self.leaveSharedFolder(as: leaving, remove: removeSharedFolder) }.value
        if let note { UserDefaults.standard.set(note, forKey: Self.stopNoteKey) }
        stopTimers()
        isActive = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        StoreFiles.remove(store: Self.workingStore)
        try? FileManager.default.removeItem(at: Self.workingDirectory)
        Self.relaunch()
    }

    /// Said once, after the restart that follows stopping sharing.
    static let stopNoteKey = "sharingStopNote"

    /// Takes this login out of the shared folder. When `remove` is true it also moves the folder to the Trash, but only if
    /// nobody else has used it in the last 30 days, and only after taking the lock so nobody opens it meanwhile. Returns
    /// what to tell the person, or nil when there is nothing to say.
    nonisolated static func leaveSharedFolder(as me: SharedLock, remove: Bool, folder: SharedDataFolder = .standard, useTrash: Bool = true) -> String? {
        guard folder.exists else { return nil }
        folder.removeMember(userName: me.userName)
        guard remove else { return nil }
        let others = folder.otherUsers(besides: me.userName, fullName: me.fullName)
        if let first = others.first {
            let who = others.count == 1 ? first.name : "\(first.name) and \(others.count - 1) more"
            return "The shared folder was left in place because \(who) still uses it. The last person to stop sharing can remove it."
        }
        var mine = me
        mine.since = .now
        mine.heartbeat = .now
        guard case .acquired? = try? folder.acquire(mine) else {
            return "The shared folder was left in place because someone has it open right now."
        }
        do {
            return try folder.removeEverything(useTrash: useTrash) ? "The shared folder was moved to the Trash." : "The shared folder was removed."
        } catch {
            folder.release(token: me.token)
            return "The shared folder couldn't be removed: \(error.localizedDescription) It is still in place."
        }
    }

    /// Saves, lets go of the lock so someone else can use the data, and quits.
    func closeForOthers() async {
        await checkInNow(release: true)
        NSApp.terminate(nil)
    }

    /// The earlier saves in the shared folder, newest first.
    func previousSaves() async -> [SharedVersion] {
        let folder = SharedDataFolder.standard
        return await Task.detached { folder.versions() }.value
    }

    /// Makes an earlier save the current data. What is open now is saved first, so it becomes a previous save itself and
    /// nothing is lost. Then the app starts again on the restored data.
    func restore(_ version: SharedVersion) async throws {
        guard isActive, !lostLock, let folder else { throw SharedDataError.folderUnavailable("the shared data isn't open in this copy") }
        await checkInNow(release: false)
        if isDirty || lostLock { throw SharedDataError.copyFailed(errorMessage ?? "the current data couldn't be saved first, so nothing was changed") }
        let name = NSFullUserName()
        let appVersion = appVersion
        let token = me.token
        let base = baseRevision
        let staging = URL.applicationSupportDirectory.appendingPathComponent("SharedRestore", isDirectory: true)
        let info: SharedInfo = try await Task.detached {
            defer { try? FileManager.default.removeItem(at: staging) }
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let copy = staging.appendingPathComponent(SharedDataFolder.storeName)
            try SealedFile.unseal(version.url, to: copy)
            try folder.restoreReceipts(into: copy)
            guard folder.holds(token: token) else { throw SharedDataError.changedMeanwhile }
            let info = try folder.checkIn(from: copy, baseRevision: base, by: name, appVersion: appVersion)
            folder.appendLog("restored the save from \(version.info.savedAt.formatted(date: .abbreviated, time: .shortened)) (number \(version.info.revision)) as save number \(info.revision)")
            folder.release(token: token)
            return info
        }.value
        baseRevision = info.revision
        stopTimers()
        isActive = false
        removeMarker()
        Self.relaunch()
    }

    /// A plain-words report on the shared folder, for Check Sharing.
    func checkSharing() async -> [String] {
        let folder = SharedDataFolder.standard
        return await Task.detached { folder.diagnose() }.value
    }

    // MARK: While running

    private func startTimers() {
        stopTimers()
        heartbeatTask = Task { @MainActor [weak self] in
            var sinceSave = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, self.isActive, !self.lostLock else { return }
                if let folder = self.folder, !folder.refresh(self.me) {
                    self.lockWasTaken()
                    return
                }
                sinceSave += 1
                // Changes go back to the shared file every couple of minutes, so little is lost if the app dies.
                if sinceSave >= 2, self.isDirty {
                    sinceSave = 0
                    await self.checkInNow(release: false)
                }
            }
        }
        // Waking from sleep: look at the lock at once, so a copy that was taken over finds out before it saves anything.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkLockAfterWake() }
        }
    }

    private func stopTimers() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func checkLockAfterWake() {
        guard isActive, !lostLock, let folder else { return }
        if !folder.refresh(me) { lockWasTaken() }
    }

    /// Someone used Open Anyway while this copy was stuck or asleep. What this copy still holds can't go into the shared
    /// data any more; it is kept as a separate copy in the shared folder when the app quits.
    private func lockWasTaken() {
        guard !lostLock else { return }
        lostLock = true
        stopTimers()
        errorMessage = "Someone else opened the shared data while this copy wasn't responding."
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Someone else is using the shared data now"
            alert.informativeText = "Another user opened the shared data while this copy of Oinkly Budget wasn't responding. Changes made here since the last save can no longer go into the shared data. They are kept as a separate copy in the shared folder when you quit. Quit Oinkly Budget, then open it again to start from the shared data."
            alert.runModal()
        }
    }

    /// Called whenever the app saves, so the shared file is brought up to date at the next chance.
    func noteSaved() { if isActive && !lostLock { isDirty = true } }

    /// Writes the working copy back to the shared folder. With `release`, also lets go of the lock.
    func checkInNow(release: Bool) async {
        guard isActive, !lostLock, let folder, !isCheckingIn else { return }
        isCheckingIn = true
        defer { isCheckingIn = false }
        if let container = OinklyBudgetAppDelegate.container {
            // Changes that haven't been written yet count as changes, even before the save notice arrives.
            if container.mainContext.hasChanges { isDirty = true }
            try? container.mainContext.save()
        }
        // Nothing changed since the last save: don't write another copy (it would push a real earlier save out of
        // the previous saves). Letting go of the lock is still needed.
        guard isDirty else {
            if release { await letGo(folder) }
            return
        }
        let name = NSFullUserName()
        let user = NSUserName()
        let version = appVersion
        let token = me.token
        let working = Self.workingStore
        let base = baseRevision
        let result: Result<SharedInfo, Error> = await Task.detached {
            do {
                // Still ours? If another login took the lock, nothing is written.
                guard folder.holds(token: token) else { throw SharedDataError.changedMeanwhile }
                let info = try folder.checkIn(from: working, baseRevision: base, by: name, appVersion: version)
                folder.noteMember(userName: user, fullName: name)
                // A clean close is the moment to tidy up the receipts nothing uses any more.
                if release { folder.removeUnusedAttachments() }
                if release { folder.release(token: token) }
                return .success(info)
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let info):
            isDirty = false
            lastSaved = info.savedAt
            baseRevision = info.revision
            fileID = info.fileID
            errorMessage = nil
            // The backup copy follows each save of the shared data.
            await ShadowCopyManager.shared.afterSharedSave(revision: info.revision, fileID: info.fileID)
            if release {
                stopTimers()
                isActive = false
                removeMarker()
            } else {
                try? writeMarker()
            }
        case .failure(let error):
            if case SharedDataError.changedMeanwhile = error {
                lockWasTaken()
            } else {
                errorMessage = "The shared data couldn't be saved: \(error.localizedDescription) Your changes are safe on this Mac and will be tried again."
            }
        }
    }

    /// Lets go of the lock without saving, because the shared data already has everything. Also the moment to tidy up receipts.
    private func letGo(_ folder: SharedDataFolder) async {
        let token = me.token
        await Task.detached {
            folder.removeUnusedAttachments()
            folder.release(token: token)
        }.value
        stopTimers()
        isActive = false
        removeMarker()
    }

    /// Quitting: save and let go. A copy that lost the lock is kept as a separate file instead.
    func finishForQuit() async {
        if lostLock, let folder {
            _ = try? folder.saveRecoveredCopy(from: Self.workingStore)
            removeMarker()
            return
        }
        await checkInNow(release: true)
    }

    #if DEBUG
    /// For testing without clicking through Settings: `-sharedDataEnable` turns sharing on from this Mac's own data at
    /// launch, if it isn't on yet. Debug builds only.
    static func enableFromLaunchArgumentIfRequested(localStore: URL) {
        guard CommandLine.arguments.contains("-sharedDataEnable"), !isEnabled else { return }
        let folder = SharedDataFolder.standard
        do {
            try folder.ensureFolder()
            if !folder.hasData {
                try folder.createStore(from: localStore, by: NSFullUserName(), appVersion: "1.0")
            }
            UserDefaults.standard.set(true, forKey: enabledKey)
            NSLog("SHARED TEST: sharing turned on")
        } catch {
            NSLog("SHARED TEST: could not turn on sharing: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: Relaunching

    static func relaunch() { AppStore.relaunch() }
}
