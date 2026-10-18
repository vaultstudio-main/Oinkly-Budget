#if DEBUG
import Foundation
import AppKit
import Darwin

/// Phase 0 of the shared data file: can two Mac logins use one folder? Debug builds only.
///
/// Each login runs this against the same folder (one inside /Users/Shared works). It creates a test folder, writes
/// files, and then tries the things the real feature needs to do to files another login made: add to them, replace
/// them, rename and delete them, create a lock the exclusive way, and check whether another login's process is still
/// running. Every step says OK or FAIL with the exact system error, and the report is saved in the folder so both
/// logins' results can be read side by side. It never touches the app's real data.
@MainActor
@Observable
final class PermissionSpike {
    static let shared = PermissionSpike()

    private(set) var lines: [String] = []
    private(set) var folderPath = ""
    private(set) var isRunning = false

    private static let bookmarkKey = "permissionSpike.folderBookmark"
    private static let testFolderName = "OinklyBudget-PermissionTest"

    private var scoped: URL?
    private var report: [String] = []

    var hasFolder: Bool { UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil }
    var text: String { lines.joined(separator: "\n") }

    // MARK: Choosing the folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Users/Shared")
        panel.message = "Choose the folder both logins will use for the test, such as /Users/Shared."
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        folderPath = url.path
        lines = ["Folder chosen: \(url.path)"]
    }

    /// For testing without the folder chooser: `-permissionSpikeFolder <path>` runs the test on that path and quits,
    /// printing the report. The app's sandbox still applies, so a path it may not touch shows up as a failure.
    static func runFromLaunchArgumentsIfRequested() {
        guard let index = CommandLine.arguments.firstIndex(of: "-permissionSpikeFolder"), index + 1 < CommandLine.arguments.count else { return }
        let path = CommandLine.arguments[index + 1]
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            shared.overridePath = path
            shared.run()
            print(shared.text)
            fflush(stdout)
            exit(0)
        }
    }

    private var overridePath: String?

    private func openFolder() -> URL? {
        if let overridePath {
            folderPath = overridePath
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        scoped?.stopAccessingSecurityScopedResource()
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        scoped = url
        folderPath = url.path
        return url
    }

    // MARK: Facts about a path

    private struct Facts {
        var exists = false
        var owner = ""
        var uid: uid_t = 0
        var mode = ""
        var sticky = false
        var isDirectory = false
    }

    private func facts(_ path: String) -> Facts {
        var info = stat()
        guard lstat(path, &info) == 0 else { return Facts() }
        var result = Facts(exists: true)
        result.uid = info.st_uid
        result.owner = getpwuid(info.st_uid).map { String(cString: $0.pointee.pw_name) } ?? "uid \(info.st_uid)"
        result.mode = String(info.st_mode & 0o7777, radix: 8)
        result.sticky = info.st_mode & S_ISVTX != 0
        result.isDirectory = info.st_mode & S_IFMT == S_IFDIR
        return result
    }

    private func describe(_ path: String) -> String {
        let f = facts(path)
        guard f.exists else { return "does not exist" }
        return "owner \(f.owner), mode \(f.mode)\(f.sticky ? " (sticky)" : "")"
    }

    private func errorText(_ code: Int32) -> String { "\(String(cString: strerror(code))) (errno \(code))" }

    private var me: String { NSUserName() }

    private func add(_ status: String, _ message: String) {
        let line = "[\(status)] \(message)"
        lines.append(line)
        report.append(line)
    }

    // MARK: The test

    func run() {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        lines = []
        report = []
        guard let parent = openFolder() else {
            lines = ["Choose a folder first."]
            return
        }
        add("INFO", "Login: \(me) (uid \(getuid())) on \(ProcessInfo.processInfo.hostName)")
        add("INFO", "Process id: \(getpid())")
        add("INFO", "Chosen folder: \(parent.path) — \(describe(parent.path))")
        let values = try? parent.resourceValues(forKeys: [.volumeIsLocalKey, .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey])
        add("INFO", "Volume: \(values?.volumeName ?? "?"), local disk: \(values?.volumeIsLocal.map { $0 ? "yes" : "NO" } ?? "?"), free: \(values?.volumeAvailableCapacityForImportantUsage.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?")")

        let root = parent.appendingPathComponent(Self.testFolderName, isDirectory: true).path
        testFolder(root)
        testFile(root + "/data-file.txt")
        testExclusiveLock(root + "/lock.json")
        testSupportFolder(root + "/support")
        testProcessCheck(root + "/lock.json")
        appendLog(root + "/log.txt")
        writeReport(root + "/report-\(me).txt")
        add("INFO", "Done. A copy of this report is in the folder as report-\(me).txt")
    }

    // MARK: Steps

    /// The folder the app would make for the shared data.
    private func testFolder(_ path: String) {
        add("STEP", "1. The shared subfolder")
        let before = facts(path)
        if !before.exists {
            if mkdir(path, 0o777) == 0 {
                add("OK", "Created the subfolder")
            } else {
                add("FAIL", "Could not create the subfolder: \(errorText(errno))")
                return
            }
        } else {
            add("INFO", "Subfolder already exists: \(describe(path))")
        }
        // The creating login's umask trims the mode, and /Users/Shared is sticky, so ask explicitly for open permissions.
        if chmod(path, 0o777) == 0 {
            add("OK", "Set the subfolder to open permissions. Now: \(describe(path))")
        } else {
            add("FAIL", "Could not set open permissions on the subfolder: \(errorText(errno)) — now \(describe(path))")
        }
        let after = facts(path)
        if after.sticky { add("FAIL", "The subfolder is still sticky, so another login couldn't replace files in it") }
        if after.mode != "777" { add("FAIL", "The subfolder's mode is \(after.mode), not 777") }
    }

    /// The finished data file: the file the second login must be able to replace.
    private func testFile(_ path: String) {
        add("STEP", "2. The finished data file")
        let before = facts(path)
        let stamp = "written by \(me) at \(Date.now.formatted(.iso8601))\n"
        guard before.exists else {
            if write(stamp, to: path) { add("OK", "Created data-file.txt (\(describe(path))). Run the test as the other login next.") }
            return
        }
        add("INFO", "data-file.txt already exists: \(describe(path))")
        let foreign = before.uid != getuid()
        add("INFO", foreign ? "It was made by another login. The next steps are the important ones." : "It was made by this login.")

        // Reading it.
        if let data = FileManager.default.contents(atPath: path) {
            add("OK", "Read it (\(data.count) bytes): \(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?")")
        } else {
            add("FAIL", "Could not read it")
        }
        // Adding to it in place.
        let handle = open(path, O_WRONLY | O_APPEND)
        if handle >= 0 {
            let note = "append by \(me)\n"
            _ = note.withCString { Darwin.write(handle, $0, strlen($0)) }
            close(handle)
            add("OK", "Appended to it in place")
        } else {
            add("FAIL", "Could not append to it: \(errorText(errno))")
        }
        // Replacing it the way a check-in does: write a temporary file, then move it over the old one.
        let temporary = (path as NSString).deletingLastPathComponent + "/.data-file.\(UUID().uuidString).tmp"
        guard write(stamp, to: temporary, quiet: true) else { add("FAIL", "Could not make the temporary file for the replace"); return }
        if rename(temporary, path) == 0 {
            add("OK", "REPLACED it with a new file (rename over \(foreign ? "another login's file" : "its own file")). Now: \(describe(path))")
        } else {
            add("FAIL", "COULD NOT REPLACE it (rename over the existing file): \(errorText(errno))")
            unlink(temporary)
        }
        // Replacing it the way FileManager does, which is what the prototype uses.
        let second = (path as NSString).deletingLastPathComponent + "/.data-file.\(UUID().uuidString).tmp"
        if write(stamp, to: second, quiet: true) {
            do {
                _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: second))
                add("OK", "replaceItemAt worked. Now: \(describe(path))")
            } catch {
                add("FAIL", "replaceItemAt failed: \(error.localizedDescription)")
                unlink(second)
            }
        }
        // Deleting it.
        let spare = (path as NSString).deletingLastPathComponent + "/spare-\(me).txt"
        if write("spare\n", to: spare, quiet: true) {
            if unlink(spare) == 0 { add("OK", "Deleted a file of its own") } else { add("FAIL", "Could not delete a file of its own: \(errorText(errno))") }
        }
    }

    /// The lock: only one login may create it, and a stale one must be replaceable by someone else.
    private func testExclusiveLock(_ path: String) {
        add("STEP", "3. The lock file")
        let before = facts(path)
        let body = "{\"user\":\"\(me)\",\"pid\":\(getpid()),\"host\":\"\(ProcessInfo.processInfo.hostName)\"}\n"
        let handle = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o666)
        if handle >= 0 {
            _ = body.withCString { Darwin.write(handle, $0, strlen($0)) }
            close(handle)
            fchmodat(AT_FDCWD, path, 0o666, 0)
            add("OK", "Created the lock exclusively. Now: \(describe(path))")
        } else if errno == EEXIST {
            add("OK", "The exclusive create was refused because the lock exists (\(describe(path))), as it should be")
            // Take over: replace the other login's lock with ours.
            let temporary = (path as NSString).deletingLastPathComponent + "/.lock.\(UUID().uuidString).tmp"
            if write(body, to: temporary, quiet: true) {
                if rename(temporary, path) == 0 {
                    add("OK", "Took over the lock (replaced \(before.owner)'s lock). Now: \(describe(path))")
                } else {
                    add("FAIL", "Could not take over the lock: \(errorText(errno))")
                    unlink(temporary)
                }
            }
        } else {
            add("FAIL", "Could not create the lock: \(errorText(errno))")
        }
    }

    /// The receipts folder: a folder with files in it that both logins add to.
    private func testSupportFolder(_ path: String) {
        add("STEP", "4. The receipts folder")
        let before = facts(path)
        if !before.exists {
            if mkdir(path, 0o777) == 0 { chmod(path, 0o777); add("OK", "Created it: \(describe(path))") } else { add("FAIL", "Could not create it: \(errorText(errno))"); return }
        } else {
            add("INFO", "It already exists: \(describe(path))")
        }
        let mine = path + "/receipt-\(me).dat"
        if write("receipt from \(me)\n", to: mine) { add("OK", "Added my own receipt file") }
        // Files another login added.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        for name in names where name.hasPrefix("receipt-") && name != "receipt-\(me).dat" {
            let other = path + "/" + name
            add("INFO", "\(name): \(describe(other))")
            if FileManager.default.contents(atPath: other) != nil { add("OK", "Read \(name)") } else { add("FAIL", "Could not read \(name)") }
            let temporary = path + "/.tmp-\(UUID().uuidString)"
            if write("replaced by \(me)\n", to: temporary, quiet: true) {
                if rename(temporary, other) == 0 { add("OK", "Replaced \(name)") } else { add("FAIL", "Could not replace \(name): \(errorText(errno))"); unlink(temporary) }
            }
            if unlink(other) == 0 { add("OK", "Deleted \(name)") } else { add("FAIL", "Could not delete \(name): \(errorText(errno))") }
        }
    }

    /// Can this login tell whether another login's app is still running? This decides how fast a crashed login's lock
    /// can be taken over.
    private func testProcessCheck(_ lockPath: String) {
        add("STEP", "5. Is another login's app still running?")
        add("INFO", kill(getpid(), 0) == 0 ? "Checking my own process works" : "Checking my own process FAILED: \(errorText(errno))")
        guard let data = FileManager.default.contents(atPath: lockPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = object["user"] as? String, let pid = object["pid"] as? Int else {
            add("INFO", "No lock to check")
            return
        }
        if user == me { add("INFO", "The lock is mine (process \(pid)); run the test as the other login to check theirs"); return }
        let result = kill(pid_t(pid), 0)
        if result == 0 {
            add("OK", "kill(\(pid), 0) says \(user)'s process exists")
        } else if errno == ESRCH {
            add("OK", "kill(\(pid), 0) says \(user)'s process is gone (ESRCH). A crashed login's lock can be taken over at once.")
        } else if errno == EPERM {
            add("INFO", "kill(\(pid), 0) returned EPERM. It can't tell if \(user)'s process is running, so only the 3 minute heartbeat can mark a lock stale.")
        } else {
            add("FAIL", "kill(\(pid), 0) failed: \(errorText(errno))")
        }
    }

    private func appendLog(_ path: String) {
        add("STEP", "6. A shared log file")
        let line = "\(Date.now.formatted(.iso8601)) \(me) ran the test\n"
        if !facts(path).exists { _ = write("", to: path, quiet: true) }
        let handle = open(path, O_WRONLY | O_APPEND)
        if handle >= 0 {
            _ = line.withCString { Darwin.write(handle, $0, strlen($0)) }
            close(handle)
            add("OK", "Appended to the shared log (\(describe(path)))")
        } else {
            add("FAIL", "Could not append to the shared log: \(errorText(errno))")
        }
    }

    // MARK: Helpers

    @discardableResult
    private func write(_ text: String, to path: String, quiet: Bool = false) -> Bool {
        let ok = FileManager.default.createFile(atPath: path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o666])
        if ok { chmod(path, 0o666) } else if !quiet { add("FAIL", "Could not write \((path as NSString).lastPathComponent): \(errorText(errno))") }
        return ok
    }

    private func writeReport(_ path: String) {
        write(report.joined(separator: "\n") + "\n", to: path, quiet: true)
    }

    /// Deletes the files this login made in the test folder, and the folder if it is then empty.
    func cleanUp() {
        guard let parent = openFolder() else { return }
        let root = parent.appendingPathComponent(Self.testFolderName).path
        var removed = 0
        for path in ["/data-file.txt", "/lock.json", "/log.txt", "/report-\(me).txt", "/support/receipt-\(me).dat"] where unlink(root + path) == 0 { removed += 1 }
        rmdir(root + "/support")
        rmdir(root)
        lines = ["Removed \(removed) file(s) made by \(me). Files made by other logins, and the folder if anything is left, stay."]
    }
}
#endif
