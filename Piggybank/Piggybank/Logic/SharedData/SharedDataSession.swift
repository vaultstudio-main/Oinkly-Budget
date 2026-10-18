import AppKit
import SwiftData

/// Using one data folder with other Mac logins, one at a time.
///
/// When a shared folder is set, the app does not open the shared file itself. At launch it takes the lock, copies the
/// finished file to a private working copy in its own storage, and works on that. The working copy is written back to the
/// shared folder now and then, when the app is hidden and when it quits, and then the lock is let go.
/// When no shared folder is set, none of this runs and the app uses this Mac's own data as before.
@MainActor
@Observable
final class SharedDataSession {
    static let shared = SharedDataSession()

    // MARK: What a launch decided

    /// What the app has to ask the person before it can open any data.
    enum Decision: Equatable {
        /// Someone else has the file open. `isStale` means their app may have crashed.
        case heldBy(SharedLock, isStale: Bool)
        case folderMissing
        case failed(String)
    }

    enum Outcome {
        case local
        case shared(workingStore: URL)
        case needsDecision(Decision)
    }

    private(set) var decision: Decision?
    private(set) var isActive = false
    /// Opened without the lock. Nothing done in this session is written back.
    private(set) var isReadOnly = false
    private(set) var folderPath = ""
    private(set) var lastSaved: Date?
    private(set) var openSince: Date?
    /// Shown once after launch, such as "your unsaved changes were kept as a separate file".
    var notice: String?
    var errorMessage: String?

    private var folder: SharedDataFolder?
    private var scopedURL: URL?
    private let me = SharedLock(token: UUID().uuidString, userName: NSUserName(), fullName: NSFullUserName(), since: .now, heartbeat: .now,
                                pid: ProcessInfo.processInfo.processIdentifier, host: ProcessInfo.processInfo.hostName)
    private var heartbeatTask: Task<Void, Never>?
    private var isDirty = false
    private var isCheckingIn = false

    private static let bookmarkKey = "sharedData.folderBookmark"
    private static let markerName = "open.json"

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1" }

    /// True once a shared folder has been chosen on this Mac login.
    static var isConfigured: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    // MARK: Locations

    static var workingDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("SharedWorking", isDirectory: true)
    }
    static var workingStore: URL { workingDirectory.appendingPathComponent(SharedDataFolder.storeName) }
    private static var markerURL: URL { workingDirectory.appendingPathComponent(markerName) }

    #if DEBUG
    /// For testing without the folder chooser: `-sharedDataTestFolder` shares through a folder inside the app's own
    /// storage, made from this Mac's data the first time. Debug builds only.
    static func enableTestFolderIfRequested() {
        guard CommandLine.arguments.contains("-sharedDataTestFolder"), !isConfigured else { return }
        let url = URL.documentsDirectory.appendingPathComponent("SharedTest", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let folder = SharedDataFolder(url: url)
        if !folder.hasStore {
            let local = URL.applicationSupportDirectory.appendingPathComponent("default.store")
            try? folder.createStore(from: local, by: NSFullUserName(), appVersion: "1.1")
        }
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }
    }
    #endif

    // MARK: Launch

    /// Decides what the app opens. Runs once, before the database is opened.
    func prepareAtLaunch(readOnly: Bool = false, takeOver: Bool = false) -> Outcome {
        guard Self.isConfigured else { return .local }
        guard let folder = resolveFolder() else {
            decision = .folderMissing
            return .needsDecision(.folderMissing)
        }
        self.folder = folder
        folderPath = folder.url.path
        isReadOnly = readOnly

        do {
            var recovered: String?
            if readOnly {
                try folder.checkOut(to: Self.workingStore)
                try? FileManager.default.removeItem(at: Self.markerURL)
            } else {
                var mine = me
                mine.since = .now
                let first = try folder.acquire(mine, takeOver: takeOver)
                switch first {
                case .heldBy(let lock, let stale):
                    // The same person's own earlier run that closed unexpectedly is not "someone else": take over
                    // and recover. A second window of the same login that is still running is a real conflict.
                    if lock.userName == mine.userName, stale {
                        _ = try folder.acquire(mine, takeOver: true)
                    } else {
                        decision = .heldBy(lock, isStale: stale)
                        return .needsDecision(.heldBy(lock, isStale: stale))
                    }
                case .acquired:
                    break
                }
                openSince = .now
                recovered = try openWorkingCopy(from: folder)
            }
            isActive = true
            lastSaved = folder.readInfo()?.savedAt
            if let recovered { notice = recovered }
            startTimers()
            return .shared(workingStore: Self.workingStore)
        } catch {
            decision = .failed(error.localizedDescription)
            return .needsDecision(.failed(error.localizedDescription))
        }
    }

    private static var markerExists: Bool { FileManager.default.fileExists(atPath: markerURL.path) }

    /// Makes the working copy ready. After a crash it keeps the unsaved work when it can, and never throws it away
    /// silently. Returns a message to show the person when something was recovered.
    private func openWorkingCopy(from folder: SharedDataFolder) throws -> String? {
        let manager = FileManager.default
        let savedAt = folder.readInfo()?.savedAt
        var message: String?

        if Self.markerExists, manager.fileExists(atPath: Self.workingStore.path),
           let data = try? Data(contentsOf: Self.markerURL),
           let marker = try? Self.markerDecoder.decode(Marker.self, from: data) {
            if marker.base == savedAt {
                // Nobody saved since: the working copy still has everything, plus what was never written back.
                return "OinklyBudget closed unexpectedly last time. Your unsaved changes were kept."
            }
            // The shared file changed while this copy was out. Keep this copy as its own file instead of overwriting.
            let kept = try folder.saveRecoveredCopy(from: Self.workingStore)
            message = "OinklyBudget closed unexpectedly, and the shared data was saved by someone else in the meantime. Your unsaved changes were kept as “\(kept.lastPathComponent)” in the shared folder, and OinklyBudget opened the latest shared data."
        }
        try folder.checkOut(to: Self.workingStore)
        try writeMarker(base: savedAt)
        return message
    }

    private struct Marker: Codable { var base: Date? }

    private static var markerDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func writeMarker(base: Date?) throws {
        try FileManager.default.createDirectory(at: Self.workingDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Marker(base: base)).write(to: Self.markerURL)
    }

    // MARK: Folder access

    private func resolveFolder() -> SharedDataFolder? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        scopedURL = url
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return SharedDataFolder(url: url)
    }

    // MARK: Turning sharing on and off

    /// Asks for a folder, then shares this Mac's data (or the data already in the folder) through it. Relaunches.
    func chooseFolderAndEnable(currentStore: URL?, context: ModelContext) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose or make a folder that every Mac login you want to share with can open, such as one in /Users/Shared."
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.startAccessingSecurityScopedResource() else { errorMessage = "This folder can't be opened."; return }
        defer { url.stopAccessingSecurityScopedResource() }
        let chosen = SharedDataFolder(url: url)
        errorMessage = nil
        do {
            if !chosen.hasStore {
                guard let currentStore else { throw SharedDataError.folderUnavailable }
                try? context.save()
                try chosen.createStore(from: currentStore, by: NSFullUserName(), appVersion: appVersion)
            }
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            try? FileManager.default.removeItem(at: Self.markerURL)
            Self.relaunch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Goes back to this Mac's own data. The shared file keeps what was last saved.
    func stopSharing() async {
        await checkInNow(release: true)
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        try? SharedDataFolder.removeStore(at: Self.workingStore)
        try? FileManager.default.removeItem(at: Self.markerURL)
        Self.relaunch()
    }

    /// Saves, lets go of the lock so someone else can use the file, and quits.
    func closeForOthers() async {
        await checkInNow(release: true)
        try? FileManager.default.removeItem(at: Self.markerURL)
        NSApp.terminate(nil)
    }

    /// Choosing something at the "someone has the file" screen.
    func resolve(readOnly: Bool = false, takeOver: Bool = false) {
        // The working copy and lock are set up at launch, so a new choice means a fresh launch with that choice.
        UserDefaults.standard.set(readOnly ? "readOnly" : (takeOver ? "takeOver" : ""), forKey: "sharedData.nextLaunch")
        Self.relaunch()
    }

    func useThisMacsData() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        Self.relaunch()
    }

    /// One-time instructions left by the "someone has the file" screen for the next launch.
    static func takeNextLaunchChoice() -> (readOnly: Bool, takeOver: Bool) {
        let value = UserDefaults.standard.string(forKey: "sharedData.nextLaunch") ?? ""
        UserDefaults.standard.removeObject(forKey: "sharedData.nextLaunch")
        return (value == "readOnly", value == "takeOver")
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: While running

    private func startTimers() {
        guard !isReadOnly else { return }
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            var sinceSave = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, self.isActive else { return }
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
    }

    private func lockWasTaken() {
        isActive = false
        isReadOnly = true
        errorMessage = "Someone else has taken over the shared file. Changes made here can no longer be saved to it."
        notice = "Someone else has taken over the shared file, so changes made from now on in this window won't be saved to it. Quit OinklyBudget, then open it again to start from the shared file."
    }

    /// Called whenever the app saves, so the shared file is brought up to date at the next chance.
    func noteSaved() { if isActive && !isReadOnly { isDirty = true } }

    /// Writes the working copy back to the shared folder. With `release`, also lets go of the lock.
    func checkInNow(release: Bool) async {
        guard isActive, !isReadOnly, let folder, !isCheckingIn else { return }
        isCheckingIn = true
        defer { isCheckingIn = false }
        if let container = PiggybankAppDelegate.container { try? container.mainContext.save() }
        let name = NSFullUserName()
        let version = appVersion
        let token = me.token
        let working = Self.workingStore
        let result: Result<Void, Error> = await Task.detached {
            do {
                try folder.checkIn(from: working, by: name, appVersion: version)
                if release { folder.release(token: token) }
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success:
            isDirty = false
            lastSaved = .now
            errorMessage = nil
            if release {
                isActive = false
                try? FileManager.default.removeItem(at: Self.markerURL)
            } else {
                try? writeMarker(base: folder.readInfo()?.savedAt)
            }
        case .failure(let error):
            errorMessage = "The shared file couldn't be updated: \(error.localizedDescription) Your changes are safe on this Mac and will be tried again."
        }
    }
}
