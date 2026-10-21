import AppKit
import CryptoKit
import SwiftData

/// Encrypted data, using one shape: an encrypted **vault** file, a private **working copy** the app opens, and a
/// **check-in** that seals the working copy back into the vault.
///
/// While encryption is on, the data at rest is only the vault (and the small key file beside it). At launch the vault is
/// opened into a working copy in the app's own storage, and the app runs on that, as on any database. The working copy is
/// sealed back every couple of minutes, when the app is hidden and when it quits, and is deleted on a clean quit.
/// Honest limit: while the app is open the working copy is plain on disk, and after a crash it stays until the next
/// launch. Encryption protects the data at rest, such as a copied file, a backup or a lost Mac without FileVault. It does
/// not protect a Mac that is unlocked and in use.
///
/// This is the same working copy and check-in a shared data file needs, so when that arrives the vault can live in the
/// shared folder instead of this Mac's storage.
@MainActor
@Observable
final class VaultSession {
    static let shared = VaultSession()

    enum Outcome {
        case local
        case open(workingStore: URL)
        case quit
    }

    private(set) var isActive = false
    private(set) var lastSealed: Date?
    var errorMessage: String?
    /// Shown once after launch, such as "closed unexpectedly, your changes were kept".
    var notice: String?

    private var keyFile: VaultKeyFile?
    private var dataKey: SymmetricKey?
    private var isDirty = false
    private var isSealing = false
    private var timer: Task<Void, Never>?
    /// With a shared data file, where the key file lives (in the shared folder) instead of this Mac's vault folder.
    private var sharedKeysURL: URL?
    private var keysLocation: URL { sharedKeysURL ?? Self.keysURL }

    // MARK: Locations

    static var vaultDirectory: URL { URL.applicationSupportDirectory.appendingPathComponent("Vault", isDirectory: true) }
    static var vaultURL: URL { vaultDirectory.appendingPathComponent(VaultCrypto.fileName) }
    static var keysURL: URL { vaultDirectory.appendingPathComponent(VaultCrypto.keysName) }
    static var previousURL: URL { vaultDirectory.appendingPathComponent("OinklyBudget (previous save).vault") }
    static var workingDirectory: URL { URL.applicationSupportDirectory.appendingPathComponent("VaultWorking", isDirectory: true) }
    static var workingStore: URL { workingDirectory.appendingPathComponent("OinklyBudget.store") }
    private static var markerURL: URL { workingDirectory.appendingPathComponent("open.marker") }
    private static var stagingDirectory: URL { URL.applicationSupportDirectory.appendingPathComponent("VaultStaging", isDirectory: true) }
    private static let cleanupKey = "vault.removeLocalDataAfterOpen"

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: vaultURL.path) }
    var vaultID: String? { keyFile?.vaultID }
    /// The open vault's key file and data key, for sharing the encrypted data.
    var currentKeyFile: VaultKeyFile? { keyFile }
    var currentKey: SymmetricKey? { dataKey }
    var hasRemembered: Bool { vaultID.flatMap { VaultKeychain.load(vaultID: $0) } != nil }

    /// This Mac's own, unencrypted data file, as the app opened it before encryption was turned on.
    static func localStoreURL(for schema: Schema) -> URL {
        ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none).url
    }

    // MARK: Launch

    /// Decides what the app opens. Runs once, before the database is opened. With encryption on it asks for the
    /// passphrase first.
    func prepareAtLaunch(localStore: URL) -> Outcome {
        guard Self.isEnabled else { return .local }
        guard let file = try? VaultCrypto.read(keysAt: Self.keysURL) else {
            VaultPrompt.tell("The key file for your encrypted data is missing", "Oinkly Budget can't open the encrypted data without OinklyBudget.vaultkeys beside it. Nothing was changed. Put the key file back, or restore from a backup.")
            return .quit
        }
        keyFile = file

        guard let key = obtainKey(file) else { return .quit }
        dataKey = key

        do {
            if let notice = try openWorkingCopy(key: key) { self.notice = notice }
        } catch {
            VaultPrompt.tell("The encrypted data couldn't be opened", error.localizedDescription)
            return .quit
        }
        // Once the encrypted copy has opened, this Mac's old unencrypted copy is no longer needed.
        if UserDefaults.standard.bool(forKey: Self.cleanupKey) {
            UserDefaults.standard.removeObject(forKey: Self.cleanupKey)
            StoreFiles.remove(store: localStore)
        }
        isActive = true
        startTimer()
        return .open(workingStore: Self.workingStore)
    }

    /// The key from the Keychain if it was remembered, otherwise by asking.
    func obtainKey(_ file: VaultKeyFile) -> SymmetricKey? {
        if let remembered = VaultKeychain.load(vaultID: file.vaultID), remembered.count == 32 { return SymmetricKey(data: remembered) }
        var message: String?
        while true {
            #if DEBUG
            // For testing without typing into the password field: `-vaultTestPassphrase <passphrase>` answers the prompt.
            if let index = CommandLine.arguments.firstIndex(of: "-vaultTestPassphrase"), index + 1 < CommandLine.arguments.count,
               let key = try? VaultCrypto.unlock(file, secret: CommandLine.arguments[index + 1]) {
                if CommandLine.arguments.contains("-vaultTestRemember") { VaultKeychain.save(key.withUnsafeBytes { Data($0) }, vaultID: file.vaultID) }
                return key
            }
            #endif
            guard let answer = VaultPrompt.askToUnlock(message: message) else { return nil }
            do {
                let key = try VaultCrypto.unlock(file, secret: answer.secret)
                if answer.remember { VaultKeychain.save(key.withUnsafeBytes { Data($0) }, vaultID: file.vaultID) }
                return key
            } catch {
                message = "That didn't open it. Check the passphrase, or type your recovery key."
            }
        }
    }

    /// Opens the vault into a working copy. After a crash the working copy from last time is kept, because it holds
    /// everything the vault has plus what was never sealed. Returns a message to show when that happened.
    private func openWorkingCopy(key: SymmetricKey) throws -> String? {
        let manager = FileManager.default
        if manager.fileExists(atPath: Self.markerURL.path), manager.fileExists(atPath: Self.workingStore.path) {
            return "Oinkly Budget closed unexpectedly last time. Your unsaved changes were kept."
        }
        try? manager.removeItem(at: Self.workingDirectory)
        try VaultCrypto.open(Self.vaultURL, into: Self.workingDirectory, key: key)
        guard manager.fileExists(atPath: Self.workingStore.path) else { throw VaultError.notAVault }
        manager.createFile(atPath: Self.markerURL.path, contents: Data())
        return nil
    }

    // MARK: While running

    func noteSaved() { if isActive { isDirty = true } }

    /// The shared data session opened encrypted shared data. The key settings (change passphrase, new recovery key,
    /// remember on this Mac) then work on the shared key file, with the key it already holds.
    func adoptShared(keyFile: VaultKeyFile, key: SymmetricKey, keysURL: URL) {
        self.keyFile = keyFile
        dataKey = key
        sharedKeysURL = keysURL
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard let self, self.isActive else { return }
                if self.isDirty { await self.sealNow(final: false) }
            }
        }
    }

    /// Seals the working copy back into the vault. With `final`, the plain working copy is deleted afterwards.
    func sealNow(final: Bool) async {
        guard isActive, let key = dataKey, !isSealing else { return }
        isSealing = true
        defer { isSealing = false }
        if let container = PiggybankAppDelegate.container { try? container.mainContext.save() }
        let live = Self.workingStore
        let staging = Self.stagingDirectory
        let vault = Self.vaultURL
        let previous = Self.previousURL

        let result: Result<Void, Error> = await Task.detached {
            do {
                // A snapshot first, so what is sealed is one consistent moment and the app can keep saving meanwhile.
                _ = try StoreFiles.snapshot(of: live, into: staging)
                if FileManager.default.fileExists(atPath: vault.path) {
                    try? FileManager.default.removeItem(at: previous)
                    try? FileManager.default.copyItem(at: vault, to: previous)
                }
                try VaultCrypto.seal(directory: staging, to: vault, key: key) { sealed in
                    // The new file is opened again and compared before it replaces the old one.
                    let check = staging.deletingLastPathComponent().appendingPathComponent("VaultVerify", isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: check) }
                    try? FileManager.default.removeItem(at: check)
                    try VaultCrypto.open(sealed, into: check, key: key)
                    let expected = try SQLiteStore.counts(of: staging.appendingPathComponent("OinklyBudget.store"))
                    let actual = try SQLiteStore.counts(of: check.appendingPathComponent("OinklyBudget.store"))
                    guard expected == actual else { throw VaultError.failed("The sealed copy didn't match, so the vault was left as it was.") }
                }
                try? FileManager.default.removeItem(at: staging)
                return .success(())
            } catch {
                try? FileManager.default.removeItem(at: staging)
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            isDirty = false
            lastSealed = .now
            errorMessage = nil
            if final {
                StoreFiles.remove(store: Self.workingStore)
                try? FileManager.default.removeItem(at: Self.workingDirectory)
                isActive = false
            }
        case .failure(let error):
            errorMessage = "The encrypted data couldn't be saved: \(error.localizedDescription) Your changes are safe on this Mac and will be tried again."
        }
    }

    // MARK: Turning on

    /// A new vault, not yet written anywhere. The person is shown the recovery key before anything is changed.
    struct Pending {
        let keyFile: VaultKeyFile
        let dataKey: SymmetricKey
        let recoveryKey: String
    }

    nonisolated func prepareEnable(passphrase: String) throws -> Pending {
        let made = try VaultCrypto.create(passphrase: passphrase)
        return Pending(keyFile: made.keyFile, dataKey: made.dataKey, recoveryKey: made.recoveryKey)
    }

    /// Seals this Mac's data into a new vault and relaunches into it. The unencrypted copy is removed only after the
    /// encrypted one has opened.
    func commitEnable(_ pending: Pending, localStore: URL, remember: Bool, keepLocalCopy: Bool = false) async throws {
        if let container = PiggybankAppDelegate.container { try? container.mainContext.save() }
        let staging = Self.stagingDirectory
        let vaultDirectory = Self.vaultDirectory
        let vault = Self.vaultURL
        let keys = Self.keysURL
        try await Task.detached {
            try FileManager.default.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
            _ = try StoreFiles.snapshot(of: localStore, into: staging)
            defer { try? FileManager.default.removeItem(at: staging) }
            try VaultCrypto.seal(directory: staging, to: vault, key: pending.dataKey) { sealed in
                let check = staging.deletingLastPathComponent().appendingPathComponent("VaultVerify", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: check) }
                try? FileManager.default.removeItem(at: check)
                try VaultCrypto.open(sealed, into: check, key: pending.dataKey)
                let expected = try SQLiteStore.counts(of: staging.appendingPathComponent("OinklyBudget.store"))
                let actual = try SQLiteStore.counts(of: check.appendingPathComponent("OinklyBudget.store"))
                guard expected == actual else { throw VaultError.failed("The encrypted copy didn't match, so nothing was changed.") }
            }
            try VaultCrypto.write(pending.keyFile, to: keys)
        }.value
        if remember { VaultKeychain.save(pending.dataKey.withUnsafeBytes { Data($0) }, vaultID: pending.keyFile.vaultID) }
        try? FileManager.default.removeItem(at: Self.workingDirectory)
        if !keepLocalCopy { UserDefaults.standard.set(true, forKey: Self.cleanupKey) }
        Self.relaunch()
    }

    // MARK: Changes while on

    /// True when `secret` opens the vault. Used to confirm the person before changing anything.
    func confirm(_ secret: String) -> Bool {
        guard let keyFile else { return false }
        return (try? VaultCrypto.unlock(keyFile, secret: secret)) != nil
    }

    func changePassphrase(current: String, to new: String) throws {
        guard let keyFile, let dataKey, confirm(current) else { throw VaultError.wrongSecret }
        let updated = try VaultCrypto.changingPassphrase(keyFile, dataKey: dataKey, to: new)
        try VaultCrypto.write(updated, to: keysLocation)
        try? FileManager.default.setAttributes([.posixPermissions: sharedKeysURL == nil ? 0o600 : 0o666], ofItemAtPath: keysLocation.path)
        self.keyFile = updated
    }

    /// A new recovery key, replacing the old one.
    func newRecoveryKey(current: String) throws -> String {
        guard let keyFile, let dataKey, confirm(current) else { throw VaultError.wrongSecret }
        let result = try VaultCrypto.replacingRecoveryKey(keyFile, dataKey: dataKey)
        try VaultCrypto.write(result.keyFile, to: keysLocation)
        try? FileManager.default.setAttributes([.posixPermissions: sharedKeysURL == nil ? 0o600 : 0o666], ofItemAtPath: keysLocation.path)
        self.keyFile = result.keyFile
        return result.recoveryKey
    }

    func setRemember(_ on: Bool) {
        guard let keyFile, let dataKey else { return }
        if on { VaultKeychain.save(dataKey.withUnsafeBytes { Data($0) }, vaultID: keyFile.vaultID) }
        else { VaultKeychain.delete(vaultID: keyFile.vaultID) }
    }

    /// Back to ordinary data on this Mac: the latest data is copied out of the vault into this Mac's own data file, the
    /// vault is removed, and the app relaunches.
    func turnOff(current: String, localStore: URL) async throws {
        guard let keyFile, confirm(current) else { throw VaultError.wrongSecret }
        await sealNow(final: false)
        let live = Self.workingStore
        let staging = Self.stagingDirectory
        try await Task.detached {
            let copy = try StoreFiles.snapshot(of: live, into: staging)
            defer { try? FileManager.default.removeItem(at: staging) }
            StoreFiles.remove(store: localStore)
            try FileManager.default.createDirectory(at: localStore.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: copy, to: localStore)
            try StoreFiles.copyAttachments(from: copy, to: localStore)
        }.value
        VaultKeychain.delete(vaultID: keyFile.vaultID)
        isActive = false
        StoreFiles.remove(store: Self.workingStore)
        try? FileManager.default.removeItem(at: Self.workingDirectory)
        try? FileManager.default.removeItem(at: Self.vaultDirectory)
        Self.relaunch()
    }

    #if DEBUG
    /// For testing without typing into the password fields: `-vaultTestEnable <passphrase> [-vaultTestRemember]` turns
    /// encryption on, and `-vaultTestDisable <passphrase>` turns it off. The recovery key is written to the log.
    func runTestCommands() {
        let args = CommandLine.arguments
        guard let schemaStore = Optional(VaultSession.localStoreURL(for: Schema(versionedSchema: PiggybankSchemaV2.self))) else { return }
        if let index = args.firstIndex(of: "-vaultTestEnable"), index + 1 < args.count, !Self.isEnabled {
            let passphrase = args[index + 1]
            let remember = args.contains("-vaultTestRemember")
            Task { @MainActor in
                do {
                    let pending = try self.prepareEnable(passphrase: passphrase)
                    NSLog("VAULT TEST recovery key: \(pending.recoveryKey)")
                    try await self.commitEnable(pending, localStore: schemaStore, remember: remember, keepLocalCopy: args.contains("-vaultTestKeepLocal"))
                } catch {
                    NSLog("VAULT TEST enable failed: \(error.localizedDescription)")
                }
            }
        } else if let index = args.firstIndex(of: "-vaultTestDisable"), index + 1 < args.count, isActive {
            let passphrase = args[index + 1]
            Task { @MainActor in
                do { try await self.turnOff(current: passphrase, localStore: schemaStore) }
                catch { NSLog("VAULT TEST disable failed: \(error.localizedDescription)") }
            }
        }
    }
    #endif

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// The plain AppKit prompts used before the app has any windows.
@MainActor
enum VaultPrompt {
    static func tell(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    /// Asks for the passphrase (or recovery key). Nil when the person chooses to quit.
    static func askToUnlock(message: String?) -> (secret: String, remember: Bool)? {
        // The prompt comes before any window, so bring the app forward or the field won't take the keyboard.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Unlock Oinkly Budget"
        alert.informativeText = (message.map { $0 + "\n\n" } ?? "") + "Your data is encrypted. Enter your passphrase to open it. If you've forgotten it, type your recovery key instead."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 28, width: 300, height: 24))
        field.placeholderString = "Passphrase or recovery key"
        let remember = NSButton(checkboxWithTitle: "Remember on this Mac", target: nil, action: nil)
        remember.frame = NSRect(x: 0, y: 0, width: 300, height: 22)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
        box.addSubview(field)
        box.addSubview(remember)
        alert.accessoryView = box
        alert.addButton(withTitle: "Unlock")
        alert.addButton(withTitle: "Quit")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let secret = field.stringValue
        return secret.isEmpty ? askToUnlock(message: "Enter your passphrase.") : (secret, remember.state == .on)
    }

    /// Asks for a passphrase in a small dialog. Nil when cancelled.
    static func askPassphrase(title: String, detail: String, button: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }
}
