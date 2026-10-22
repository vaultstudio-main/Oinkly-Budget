#if DEBUG
import Foundation

/// `-sharedHardeningTest` tries the things that go wrong with a shared data file, on throwaway folders, using a copy of
/// this Mac's own data, then quits. Never touches /Users/Shared/OinklyBudget. Debug only.
enum SharedHardeningTest {
    static func runIfRequested(localStore: URL) {
        guard CommandLine.arguments.contains("-sharedHardeningTest") else { return }
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            NSLog("HARDENING: \(ok ? "PASS" : "FAIL") \(name) \(detail)")
            if !ok { failures += 1 }
        }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("OinklyHardening-\(UUID().uuidString)", isDirectory: true)
        defer {
            if let walker = manager.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let item as URL in walker { try? manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: item.path) }
            }
            try? manager.removeItem(at: root)
        }
        func lock(_ name: String, heartbeat: Date = .now) -> SharedLock {
            SharedLock(token: UUID().uuidString, userName: name, fullName: name, since: heartbeat, heartbeat: heartbeat, pid: nil, host: nil)
        }
        func opens(_ folder: SharedDataFolder, _ name: String) -> Bool {
            do { try folder.checkOut(to: root.appendingPathComponent("\(name)/OinklyBudget.store")); return true } catch { return false }
        }
        func fresh(_ name: String) throws -> SharedDataFolder {
            let folder = SharedDataFolder(url: root.appendingPathComponent(name, isDirectory: true))
            try folder.ensureFolder()
            return folder
        }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let source = try StoreFiles.snapshot(of: localStore, into: root.appendingPathComponent("source"))
            let counts = try SQLiteStore.counts(of: source)

            // S1: a save that can't be written (disk full, no permission) changes nothing
            let s1 = try fresh("s1")
            try s1.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            let before = try Data(contentsOf: s1.storeURL)
            try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: s1.url.path)
            var failed = false
            do { try s1.checkIn(from: source, baseRevision: 1, by: "A", appVersion: "1.0") } catch { failed = true }
            try manager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: s1.url.path)
            check("S1 a save that can't be written is refused", failed)
            check("S1 the shared data is untouched", (try? Data(contentsOf: s1.storeURL)) == before && s1.readInfo()?.revision == 1)
            check("S1 no half-written files left", ((try? manager.contentsOfDirectory(atPath: s1.url.path)) ?? []).filter { $0.hasSuffix(".tmp") }.isEmpty)

            // S2: a save cut short leaves temporary files; the next save works and clears them
            let s2 = try fresh("s2")
            try s2.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            let leftover = s2.url.appendingPathComponent(".OinklyBudget.store.\(UUID().uuidString).tmp")
            try Data("half a file".utf8).write(to: leftover)
            try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-3600)], ofItemAtPath: leftover.path)
            let fresh2 = s2.url.appendingPathComponent(".OinklyBudget.store.\(UUID().uuidString).tmp")
            try Data("another login saving right now".utf8).write(to: fresh2)
            try s2.checkIn(from: source, baseRevision: 1, by: "A", appVersion: "1.0")
            check("S2 an old leftover is removed", !manager.fileExists(atPath: leftover.path))
            check("S2 a file being written right now is left alone", manager.fileExists(atPath: fresh2.path))
            check("S2 the shared data is still good", try SQLiteStore.counts(of: s2.storeURL) == counts)
            // a crash after the new file was put in place but before the note was written
            let s2b = try fresh("s2b")
            try s2b.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            let info = s2b.readInfo()
            try s2b.checkIn(from: source, baseRevision: 1, by: "A", appVersion: "1.0")
            if let info { try JSONEncoder().encode(info).write(to: s2b.infoURL) } // the note says the old revision again
            check("S2 data and note out of step still opens", opens(s2b, "w2b"))

            // S3: asleep with the lock, taken over meanwhile
            let s3 = try fresh("s3")
            try s3.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            let a = lock("A", heartbeat: .now.addingTimeInterval(-600))
            let b = lock("B")
            check("S3 A takes the lock", try s3.acquire(a) == .acquired)
            guard case .heldBy(_, let stale) = try s3.acquire(b) else { throw StoreError.failed("B should have been refused") }
            check("S3 B is told A has gone quiet", stale)
            check("S3 B can't take it without asking", try s3.acquire(b) != .acquired)
            check("S3 B opens anyway", try s3.acquire(b, takeOver: true) == .acquired)
            check("S3 A finds out when it wakes", !s3.refresh(a) && !s3.holds(token: a.token))
            check("S3 B keeps its lock", s3.holds(token: b.token))

            // S4: the folder is gone
            let s4 = SharedDataFolder(url: root.appendingPathComponent("not-there", isDirectory: true))
            var s4Failed = false
            do { try s4.checkIn(from: source, baseRevision: 1, by: "A", appVersion: "1.0") } catch { s4Failed = true }
            check("S4 saving into a missing folder fails cleanly", s4Failed && !s4.exists)

            // S5: data from a newer version of the app
            let s5 = try fresh("s5")
            try s5.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            guard var newer = s5.readInfo() else { throw StoreError.failed("no note") }
            newer.schemaVersion = 3
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(newer).write(to: s5.infoURL)
            var refusedOpen = false, refusedSave = false
            do { try s5.checkOut(to: root.appendingPathComponent("w5/OinklyBudget.store")) } catch SharedDataError.newerFormat { refusedOpen = true } catch {}
            do { try s5.checkIn(from: source, baseRevision: newer.revision, by: "A", appVersion: "1.0") } catch SharedDataError.newerFormat { refusedSave = true } catch {}
            check("S5 newer data isn't opened", refusedOpen)
            let s5Counts = try SQLiteStore.counts(of: s5.storeURL)
            check("S5 newer data isn't written over", refusedSave && s5Counts == counts)

            // S6: many copies start at the same instant
            let s6 = try fresh("s6")
            try s6.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            let racers = (0..<24).map { lock("racer \($0)") }
            let results = Locked([Bool]())
            DispatchQueue.concurrentPerform(iterations: racers.count) { index in
                let won = (try? s6.acquire(racers[index])) == .acquired
                results.append(won)
            }
            let winners = racers.filter { s6.holds(token: $0.token) }
            check("S6 exactly one copy gets the lock", results.value.filter { $0 }.count == 1 && winners.count == 1, "\(results.value.filter { $0 }.count) won")

            // S7: restoring a previous save (also in the self test); here: it can be opened and checked in again
            let s7 = try fresh("s7")
            try s7.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            try s7.checkIn(from: source, baseRevision: 1, by: "A", appVersion: "1.0")
            let saved = s7.versions()
            let s7Counts = try saved.first.map { try SQLiteStore.counts(of: $0.url) }
            check("S7 the earlier save is listed and opens", saved.count == 1 && s7Counts == counts)

            // S8: a damaged working copy is never written into the shared data
            let s8 = try fresh("s8")
            try s8.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            let broken = root.appendingPathComponent("broken/OinklyBudget.store")
            try manager.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
            var bytes = try Data(contentsOf: source)
            bytes.replaceSubrange(0..<2048, with: Data(repeating: 0xAB, count: 2048))
            try bytes.write(to: broken)
            let good = try Data(contentsOf: s8.storeURL)
            var brokenRefused = false
            do { try s8.checkIn(from: broken, baseRevision: 1, by: "A", appVersion: "1.0") } catch { brokenRefused = true }
            check("S8 a damaged copy is refused and the shared data stays as it was", brokenRefused && (try? Data(contentsOf: s8.storeURL)) == good && s8.readInfo()?.revision == 1)

            // S9: the lock or the note is damaged
            let s9 = try fresh("s9")
            try s9.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            try Data("not json".utf8).write(to: s9.lockURL)
            let me = lock("B")
            if case .heldBy(_, let isStale) = try s9.acquire(me) { check("S9 a fresh unreadable lock counts as in use", !isStale) } else { check("S9 a fresh unreadable lock counts as in use", false) }
            try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-3600)], ofItemAtPath: s9.lockURL.path)
            if case .heldBy(_, let isStale) = try s9.acquire(me) { check("S9 an old unreadable lock is stale", isStale) } else { check("S9 an old unreadable lock is stale", false) }
            check("S9 and can be taken over", try s9.acquire(me, takeOver: true) == .acquired)
            try Data("not json".utf8).write(to: s9.infoURL)
            check("S9 a damaged note doesn't stop opening", opens(s9, "w9"))

            // S10: the receipts folder travels, and only new files are copied
            let s10 = try fresh("s10")
            let work10 = root.appendingPathComponent("w10/OinklyBudget.store")
            try manager.createDirectory(at: work10.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: work10)
            let support = StoreFiles.supportURL(for: work10).appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
            try manager.createDirectory(at: support, withIntermediateDirectories: true)
            try Data("receipt one".utf8).write(to: support.appendingPathComponent("AAAA"))
            try s10.checkIn(from: work10, baseRevision: nil, by: "A", appVersion: "1.0")
            let shared10 = StoreFiles.supportURL(for: s10.storeURL).appendingPathComponent("_EXTERNAL_DATA/AAAA")
            let opened = root.appendingPathComponent("o10/OinklyBudget.store")
            try s10.checkOut(to: opened)
            check("S10 a receipt reaches the shared folder and the next copy", manager.fileExists(atPath: shared10.path) && manager.fileExists(atPath: StoreFiles.supportURL(for: opened).appendingPathComponent("_EXTERNAL_DATA/AAAA").path))
            let perms = (try? manager.attributesOfItem(atPath: shared10.path)[.posixPermissions] as? Int) ?? 0
            check("S10 and any login can replace it", perms == 0o666, String(perms, radix: 8))
        } catch {
            check("no error", false, error.localizedDescription)
        }
        NSLog("HARDENING: \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")")
        exit(failures == 0 ? 0 : 1)
    }
}

/// A value several threads can add to.
private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func append<E>(_ element: E) where T == [E] { lock.lock(); stored.append(element); lock.unlock() }
}
#endif
