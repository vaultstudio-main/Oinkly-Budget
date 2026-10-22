#if DEBUG
import Foundation
import SQLite3
import SwiftData

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

            // S11: receipt clean-up removes only what nothing uses, and only when old enough
            func pointer(_ name: String) -> String { "x'02" + Array(name.utf8).map { String(format: "%02x", $0) }.joined() + "00'" }
            func makeStore(pointingTo names: [String], at url: URL) throws {
                try? manager.removeItem(at: url)
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: url)
                var db: OpaquePointer?
                guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else { throw StoreError.failed("can't open") }
                defer { sqlite3_close(db) }
                sqlite3_exec(db, "UPDATE ZTRANSACTION SET ZRECEIPTDATA = NULL", nil, nil, nil)
                for (index, name) in names.enumerated() {
                    guard sqlite3_exec(db, "UPDATE ZTRANSACTION SET ZRECEIPTDATA = \(pointer(name)) WHERE Z_PK = (SELECT Z_PK FROM ZTRANSACTION ORDER BY Z_PK LIMIT 1 OFFSET \(index))", nil, nil, nil) == SQLITE_OK else { throw StoreError.failed(String(cString: sqlite3_errmsg(db))) }
                }
            }
            let s11 = try fresh("s11")
            let inUse = "11111111-1111-4111-8111-111111111111", inOldSave = "22222222-2222-4222-8222-222222222222"
            let unusedOld = "33333333-3333-4333-8333-333333333333", unusedNew = "44444444-4444-4444-8444-444444444444"
            let work11 = root.appendingPathComponent("w11/OinklyBudget.store")
            try makeStore(pointingTo: [inOldSave], at: work11)
            try s11.checkIn(from: work11, baseRevision: nil, by: "A", appVersion: "1.0")
            try makeStore(pointingTo: [inUse], at: work11)
            try s11.checkIn(from: work11, baseRevision: 1, by: "A", appVersion: "1.0")
            let external = StoreFiles.supportURL(for: s11.storeURL).appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
            try manager.createDirectory(at: external, withIntermediateDirectories: true)
            for (name, age) in [(inUse, 90), (inOldSave, 90), (unusedOld, 90), (unusedNew, 5)] {
                let file = external.appendingPathComponent(name)
                try Data("receipt".utf8).write(to: file)
                try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-Double(age) * 86_400)], ofItemAtPath: file.path)
            }
            check("S11 the pointers are read", try SQLiteStore.attachmentReferences(of: s11.storeURL) == [inUse])
            let removed = s11.removeUnusedAttachments()
            func there(_ name: String) -> Bool { manager.fileExists(atPath: external.appendingPathComponent(name).path) }
            check("S11 an old unused receipt is removed", removed == 1 && !there(unusedOld), "removed \(removed)")
            check("S11 a receipt in use is kept", there(inUse))
            check("S11 a receipt only a previous save uses is kept", there(inOldSave))
            check("S11 a new unused receipt is kept", there(unusedNew))
            // an unreadable saved copy stops the clean-up altogether
            try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-90 * 86_400)], ofItemAtPath: external.appendingPathComponent(unusedNew).path)
            if let old = s11.versions().first { try Data(repeating: 0, count: 4096).write(to: old.url) }
            check("S11 nothing is removed when a saved copy can't be read", s11.removeUnusedAttachments() == 0 && there(unusedNew) && there(inUse))

            // S12: the waiting screen sees an old unreadable lock as stale, and a new one as in use
            let s12 = try fresh("s12")
            try s12.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            check("S12 no lock means free", s12.holder() == nil)
            try Data("not json".utf8).write(to: s12.lockURL)
            check("S12 a new unreadable lock is in use", s12.holder().map { !$0.isStale } ?? false)
            try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-3600)], ofItemAtPath: s12.lockURL.path)
            check("S12 an old unreadable lock is stale", s12.holder()?.isStale == true)
            try manager.removeItem(at: s12.lockURL)
            _ = try s12.acquire(lock("old", heartbeat: .now.addingTimeInterval(-900)))
            check("S12 an old readable lock is stale", s12.holder()?.isStale == true)

            // S13: several logins take over the same stale lock at once; only one keeps it
            let s13 = try fresh("s13")
            try s13.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            _ = try s13.acquire(lock("gone", heartbeat: .now.addingTimeInterval(-900)))
            let takers = (0..<6).map { lock("taker \($0)") }
            let takeResults = Locked([Bool]())
            DispatchQueue.concurrentPerform(iterations: takers.count) { index in
                takeResults.append((try? s13.acquire(takers[index], takeOver: true)) == .acquired)
            }
            let holders = takers.filter { s13.holds(token: $0.token) }
            check("S13 only one takeover wins", takeResults.value.filter { $0 }.count == 1 && holders.count == 1, "\(takeResults.value.filter { $0 }.count) won, \(holders.count) hold")

            // S14: amounts in a bank file
            check("S14 plain amounts", StatementImporter.parseAmount("1,234.56", commaDecimal: false) == Decimal(string: "1234.56"))
            check("S14 comma decimal", StatementImporter.parseAmount("1.234,56", commaDecimal: true) == Decimal(string: "1234.56"))
            check("S14 brackets and signs", StatementImporter.parseAmount("(12.50)", commaDecimal: false) == Decimal(string: "-12.5") && StatementImporter.parseAmount("12.50-", commaDecimal: false) == Decimal(string: "-12.5"))
            check("S14 two decimal points are refused", StatementImporter.parseAmount("1.234.567.89", commaDecimal: false) == nil && StatementImporter.parseAmount("1.234.567", commaDecimal: false) == nil)

            // S15: a repeating transaction missed for ten years makes recent entries, not old ones
            let schema = Schema(versionedSchema: PiggybankSchemaV2.self)
            let memory = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            let context = memory.mainContext
            let account = Account(name: "Test checking", type: .checking, openingBalance: 0)
            context.insert(account)
            let calendar = Calendar.current
            let tenYearsAgo = calendar.date(byAdding: .year, value: -10, to: .now) ?? .now
            let rule = RecurringTransaction(payee: "Weekly thing", account: account, category: nil, amount: -10, frequency: .weekly, startDate: tenYearsAgo)
            context.insert(rule)
            let outcome = Recurring.run(in: context)
            let made = rule.transactions.map(\.date)
            let oldest = made.min() ?? .now
            check("S15 a long-missed rule makes a few entries", outcome.created > 0 && outcome.created <= Recurring.maxCatchUp, "\(outcome.created) made")
            check("S15 and they are recent", oldest > (calendar.date(byAdding: .year, value: -1, to: .now) ?? .now).addingTimeInterval(-8 * 86_400), "oldest \(oldest.formatted(date: .abbreviated, time: .omitted))")
            check("S15 the rule moves on past today", rule.nextDate > .now.addingTimeInterval(-86_400))

            // S16: restoring a backup first keeps a copy of what is there now
            let fileStore = root.appendingPathComponent("restore-test/OinklyBudget.store")
            try manager.createDirectory(at: fileStore.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fileContainer = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: fileStore, cloudKitDatabase: .none))
            let fileContext = fileContainer.mainContext
            fileContext.insert(Account(name: "Before restoring", type: .checking, openingBalance: 0))
            try fileContext.save()
            let backup = try DataBackup.make(from: fileContext)
            let marker = Date(timeIntervalSince1970: 1_000_000_000)
            try DataBackup.makeSafetyCopy(of: fileContext, now: marker)
            let copies = URL.applicationSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
            let made16 = ((try? manager.contentsOfDirectory(at: copies, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("Before restoring a backup") && $0.lastPathComponent.contains("2001") }
            check("S16 a copy is made before restoring", made16.count == 1 && manager.fileExists(atPath: made16[0].appendingPathComponent("OinklyBudget.store").path), "\(made16.map(\.lastPathComponent))")
            let copied16 = try made16.first.map { try SQLiteStore.counts(of: $0.appendingPathComponent("OinklyBudget.store")) }
            check("S16 and it holds the current data", (copied16?["ZACCOUNT"] ?? 0) >= 1)
            for copy in made16 { try? manager.removeItem(at: copy) }
            try DataBackup.restore(backup, into: fileContext)
            let restored = try fileContext.fetch(FetchDescriptor<Account>()).filter { $0.name == "Before restoring" }
            check("S16 the restore still works", restored.count == 1)
            let stray = ((try? manager.contentsOfDirectory(at: copies, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("Before restoring a backup") }
            for copy in stray { try? manager.removeItem(at: copy) }

            // S17: repeating transactions in lists, reminders and widgets
            let rContainer = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            let rc = rContainer.mainContext
            let rAccount = Account(name: "Repeat checking", type: .checking, openingBalance: 0)
            rc.insert(rAccount)
            let rToday = calendar.startOfDay(for: .now)
            let weeksAgo = calendar.date(byAdding: .day, value: -21, to: rToday) ?? rToday
            let auto = RecurringTransaction(payee: "Paycheque", account: rAccount, category: nil, amount: 1234.56, frequency: .weekly, startDate: weeksAgo)
            let manual = RecurringTransaction(payee: "Rent", account: rAccount, category: nil, amount: -987.65, frequency: .monthly,
                                              startDate: calendar.date(byAdding: .day, value: -2, to: rToday) ?? rToday)
            manual.autoEnter = false
            rc.insert(auto); rc.insert(manual)
            _ = Recurring.run(in: rc)
            let rules17 = [auto, manual]
            let monthStart = calendar.dateInterval(of: .month, for: .now)?.start ?? rToday
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? rToday
            let inMonth = Recurring.occurrences(rules17, from: monthStart, through: monthEnd)
            check("S17 the month lists entries already added", inMonth.contains { $0.kind == .added && $0.rule === auto } || monthStart > weeksAgo)
            let ahead = Recurring.upcoming(rules17, days: 30)
            check("S17 upcoming never lists an entry already made", ahead.allSatisfy { $0.kind != .added })
            check("S17 upcoming lists dates still to come", ahead.contains { $0.kind == .coming && $0.rule === auto })
            check("S17 a reminder-only rule shows as waiting", ahead.contains { $0.kind == .due && $0.isOverdue && $0.rule === manual })
            check("S17 soonest first", ahead.map(\.date) == ahead.map(\.date).sorted())
            let reminders17 = Recurring.reminders(rules17)
            check("S17 reminders are for the future only", !reminders17.isEmpty && reminders17.allSatisfy { $0.fireDate > .now })
            check("S17 reminders never contain an amount", reminders17.allSatisfy { r in
                !(r.title + r.body).contains("1234") && !(r.title + r.body).contains("987") && !(r.title + r.body).contains("$") && !(r.title + r.body).contains(".56")
            })
            let snapshot17 = WidgetSnapshot(updated: .now, bills: [], reminders: [], repeating: ahead.map { WidgetSnapshot.Repeating(id: $0.id, name: $0.rule.payee, due: $0.date, isOverdue: $0.isOverdue) })
            let encoder17 = JSONEncoder(); encoder17.dateEncodingStrategy = .iso8601
            let decoder17 = JSONDecoder(); decoder17.dateDecodingStrategy = .iso8601
            let round = try decoder17.decode(WidgetSnapshot.self, from: encoder17.encode(snapshot17))
            check("S17 the widget file carries repeating transactions", round.repeating.count == ahead.count && round.repeating.first?.name == ahead.first?.rule.payee)
            let json17 = String(data: try encoder17.encode(snapshot17), encoding: .utf8) ?? ""
            check("S17 and no amounts", !json17.contains("1234") && !json17.contains("987"))
            let oldFile = Data("{\"updated\":\"2026-10-01T10:00:00Z\",\"bills\":[],\"reminders\":[]}".utf8)
            check("S17 an older widget file still reads", (try? decoder17.decode(WidgetSnapshot.self, from: oldFile))?.repeating.isEmpty == true)
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
