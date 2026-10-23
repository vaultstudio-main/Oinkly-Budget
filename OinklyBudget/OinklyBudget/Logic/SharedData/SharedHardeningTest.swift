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
        /// Changes the note inside a shared folder's sealed data file, keeping the data.
        func rewriteNote(_ folder: SharedDataFolder, _ change: (inout SharedInfo) -> Void) throws {
            guard var note = folder.readInfo() else { throw StoreError.failed("no note") }
            change(&note)
            let plain = root.appendingPathComponent("rewrite-\(UUID().uuidString).store")
            defer { try? manager.removeItem(at: plain) }
            try SealedFile.unseal(folder.storeURL, to: plain)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try SealedFile.seal(plain, to: folder.storeURL, kind: "shared", info: try encoder.encode(note), appVersion: "1.0")
        }
        func unwrap<T>(_ value: T?) throws -> T {
            guard let value else { throw CocoaError(.fileNoSuchFile) }
            return value
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
            check("S2 the shared data is still good", s2.readInfo()?.counts == counts && SealedFile.isIntact(s2.storeURL))
            // the note lives inside the data file, so the two can't be out of step
            let s2b = try fresh("s2b")
            try s2b.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            try s2b.checkIn(from: source, baseRevision: 1, by: "A", appVersion: "1.0")
            check("S2 the note and the data are one file, and it opens", s2b.readInfo()?.revision == 2 && opens(s2b, "w2b"))

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
            newer.schemaVersion = 10
            try rewriteNote(s5) { $0.schemaVersion = 10 }
            var refusedOpen = false, refusedSave = false
            do { try s5.checkOut(to: root.appendingPathComponent("w5/OinklyBudget.store")) } catch SharedDataError.newerFormat { refusedOpen = true } catch {}
            do { try s5.checkIn(from: source, baseRevision: newer.revision, by: "A", appVersion: "1.0") } catch SharedDataError.newerFormat { refusedSave = true } catch {}
            check("S5 newer data isn't opened", refusedOpen)
            check("S5 newer data isn't written over", refusedSave && s5.readInfo()?.schemaVersion == 10 && s5.readInfo()?.counts == counts)

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
            check("S7 the earlier save is listed and opens", saved.count == 1 && saved.first?.info.counts == counts && SealedFile.isIntact(saved[0].url))

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
            try Data("not a sealed file".utf8).write(to: s9.storeURL)
            check("S9 a damaged data file is refused, not opened", !opens(s9, "w9"))

            // S10: the receipts folder travels, and only new files are copied
            let s10 = try fresh("s10")
            let work10 = root.appendingPathComponent("w10/OinklyBudget.store")
            try manager.createDirectory(at: work10.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: work10)
            let support = StoreFiles.supportURL(for: work10).appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
            try manager.createDirectory(at: support, withIntermediateDirectories: true)
            try Data("receipt one".utf8).write(to: support.appendingPathComponent("AAAA"))
            try s10.checkIn(from: work10, baseRevision: nil, by: "A", appVersion: "1.0")
            let shared10 = s10.receiptsURL.appendingPathComponent("_EXTERNAL_DATA/AAAA.pigdata")
            let opened = root.appendingPathComponent("o10/OinklyBudget.store")
            try s10.checkOut(to: opened)
            check("S10 a receipt reaches the shared folder sealed, and the next copy", manager.fileExists(atPath: shared10.path) && (try? Data(contentsOf: shared10)) != Data("receipt one".utf8) && manager.fileExists(atPath: StoreFiles.supportURL(for: opened).appendingPathComponent("_EXTERNAL_DATA/AAAA").path))
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
            let external = s11.receiptsURL.appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
            try manager.createDirectory(at: external, withIntermediateDirectories: true)
            let receiptPlain11 = root.appendingPathComponent("receipt-plain-11")
            try Data("receipt".utf8).write(to: receiptPlain11)
            for (name, age) in [(inUse, 90), (inOldSave, 90), (unusedOld, 90), (unusedNew, 5)] {
                let file = external.appendingPathComponent(name + ".pigdata")
                try SealedFile.seal(receiptPlain11, to: file, kind: "receipt", appVersion: "1.0")
                try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-Double(age) * 86_400)], ofItemAtPath: file.path)
            }
            check("S11 the receipts a save uses are in its note", s11.readInfo()?.attachments == [inUse])
            let removed = s11.removeUnusedAttachments()
            func there(_ name: String) -> Bool { manager.fileExists(atPath: external.appendingPathComponent(name + ".pigdata").path) }
            check("S11 an old unused receipt is removed", removed == 1 && !there(unusedOld), "removed \(removed)")
            check("S11 a receipt in use is kept", there(inUse))
            check("S11 a receipt only a previous save uses is kept", there(inOldSave))
            check("S11 a new unused receipt is kept", there(unusedNew))
            // an unreadable saved copy stops the clean-up altogether
            try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-90 * 86_400)], ofItemAtPath: external.appendingPathComponent(unusedNew + ".pigdata").path)
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
            let schema = Schema(versionedSchema: OinklyBudgetSchemaV9.self)
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
            check("S17 and no amounts", !json17.contains("1234.56") && !json17.contains("987.65") && !json17.lowercased().contains("amount"))
            let oldFile = Data("{\"updated\":\"2026-10-01T10:00:00Z\",\"bills\":[],\"reminders\":[]}".utf8)
            check("S17 an older widget file still reads", (try? decoder17.decode(WidgetSnapshot.self, from: oldFile))?.repeating.isEmpty == true)

            // S18: the day a bill or rule comes out, in words
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.locale = Locale(identifier: "en_US")
            let friday = gregorian.date(from: DateComponents(year: 2026, month: 10, day: 23)) ?? .now
            let fifth = gregorian.date(from: DateComponents(year: 2026, month: 10, day: 5)) ?? .now
            check("S18 monthly", BillFrequency.monthly.schedule(from: fifth, calendar: gregorian) == "The 5th of every month", BillFrequency.monthly.schedule(from: fifth, calendar: gregorian))
            check("S18 every three months", BillFrequency.everyThreeMonths.schedule(from: fifth, calendar: gregorian) == "The 5th, every 3 months")
            check("S18 weekly", BillFrequency.weekly.schedule(from: friday, calendar: gregorian) == "Every Friday", BillFrequency.weekly.schedule(from: friday, calendar: gregorian))
            check("S18 every other week", BillFrequency.everyTwoWeeks.schedule(from: friday, calendar: gregorian) == "Every other Friday")
            check("S18 yearly", BillFrequency.yearly.schedule(from: fifth, calendar: gregorian).hasPrefix("Every ") && BillFrequency.yearly.schedule(from: fifth, calendar: gregorian).contains("5"), BillFrequency.yearly.schedule(from: fifth, calendar: gregorian))
            check("S18 once", BillFrequency.once.schedule(from: fifth, calendar: gregorian).contains("2026"))
            check("S18 23rd", BillFrequency.monthly.schedule(from: friday, calendar: gregorian) == "The 23rd of every month")

            // S19: ticking an entry a rule made confirms it, and ticking again takes that back
            if let entry = auto.transactions.first(where: { $0.isLive }) {
                entry.state = .pending
                entry.state = entry.state == .pending ? .unreconciled : .pending
                check("S19 confirmed", entry.state == .unreconciled)
                entry.state = entry.state == .pending ? .unreconciled : .pending
                check("S19 back to waiting", entry.state == .pending)
            } else {
                check("S19 an entry exists to tick", false)
            }

            // S20: the database dot
            let dbStatus = DatabaseStatus()
            let t0 = Date.now
            dbStatus.poll(context: fileContext, now: t0)
            check("S20 nothing waiting means saved", dbStatus.state == .saved)
            fileContext.insert(Account(name: "Waiting to save", type: .checking, openingBalance: 0))
            dbStatus.poll(context: fileContext, now: t0.addingTimeInterval(1))
            check("S20 a change is shown as saving", dbStatus.state == .unsaved)
            dbStatus.poll(context: fileContext, now: t0.addingTimeInterval(3))
            check("S20 still saving within the wait", dbStatus.state == .unsaved && fileContext.hasChanges)
            dbStatus.poll(context: fileContext, now: t0.addingTimeInterval(6))
            check("S20 saved after the wait", dbStatus.state == .saved && !fileContext.hasChanges && dbStatus.lastSaved != nil)
            let waiting = try fileContext.fetch(FetchDescriptor<Account>()).filter { $0.name == "Waiting to save" }
            check("S20 and it really is in the database", waiting.count == 1)

            // S21: what the widget lists
            let wNow = gregorian.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12)) ?? .now
            func d(_ day: Int, month: Int = 10, hour: Int = 0) -> Date { gregorian.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .now }
            let wSnapshot = WidgetSnapshot(
                updated: wNow,
                bills: [
                    .init(id: "b1", name: "Electric", due: d(12), isImportant: true, isOverdue: false),
                    .init(id: "b2", name: "Water", due: d(28), isImportant: false, isOverdue: false),
                    .init(id: "b3", name: "Internet", due: d(2), isImportant: false, isOverdue: true),
                    .init(id: "b4", name: "Next month's bill", due: d(3, month: 11), isImportant: false, isOverdue: false),
                ],
                reminders: [
                    .init(id: "m1", title: "Review my budget", next: d(11, hour: 9)),
                    .init(id: "m2", title: "Back up my data", next: d(2, month: 11, hour: 9)),
                ],
                repeating: [
                    .init(id: "r1", name: "Paycheque", due: d(15), isOverdue: false),
                    .init(id: "r2", name: "Gym", due: d(8), isOverdue: true),
                    .init(id: "r3", name: "Next month's rule", due: d(1, month: 11), isOverdue: false),
                ])
            let month = WidgetLines.make(wSnapshot, now: wNow, calendar: gregorian)
            check("S21 this month lists bills, repeating and reminders", Set(month.map(\.kind)) == [.bill, .repeating, .reminder], "\(month.map(\.name))")
            check("S21 nothing from next month", !month.contains { $0.name.hasPrefix("Next month") || $0.name == "Back up my data" })
            check("S21 overdue first, then soonest", month.map(\.name) == ["Internet", "Gym", "Review my budget", "Electric", "Paycheque", "Water"], "\(month.map(\.name))")
            let week = WidgetLines.make(wSnapshot, now: wNow, options: .init(lookAheadDays: 7), calendar: gregorian)
            check("S21 seven days leaves out what is further off", week.contains { $0.name == "Electric" } && week.contains { $0.name == "Paycheque" } && !week.contains { $0.name == "Water" }, "\(week.map(\.name))")
            let important = WidgetLines.make(wSnapshot, now: wNow, options: .init(onlyImportant: true), calendar: gregorian)
            check("S21 important bills only drops repeating ones", important.allSatisfy { $0.kind != .repeating && ($0.kind != .bill || $0.isImportant) })
            let bare = WidgetLines.make(wSnapshot, now: wNow, options: .init(includeRepeating: false, includeReminders: false), calendar: gregorian)
            check("S21 switches turn repeating and reminders off", bare.allSatisfy { $0.kind == .bill })
            check("S21 no snapshot means no lines", WidgetLines.make(nil, now: wNow, calendar: gregorian).isEmpty)

            // S22: reminders and saved import layouts live in the database, and a 2.0 data file opens in 3.0 without loss
            let v2 = Schema(versionedSchema: OinklyBudgetSchemaV2.self)
            let v2Store = root.appendingPathComponent("v2-file/OinklyBudget.store")
            try manager.createDirectory(at: v2Store.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                let old = try ModelContainer(for: v2, configurations: ModelConfiguration(schema: v2, url: v2Store, cloudKitDatabase: .none))
                old.mainContext.insert(Account(name: "Kept through the upgrade", type: .savings, openingBalance: 0))
                old.mainContext.insert(Tag(name: "Kept tag"))
                try old.mainContext.save()
            }
            let upgraded = try ModelContainer(for: schema, migrationPlan: OinklyBudgetMigrationPlan.self,
                                              configurations: ModelConfiguration(schema: schema, url: v2Store, cloudKitDatabase: .none))
            let uc = upgraded.mainContext
            check("S22 a 2.0 data file opens in 3.0 with its data", ((try? uc.fetch(FetchDescriptor<Account>())) ?? []).contains { $0.name == "Kept through the upgrade" }
                  && ((try? uc.fetch(FetchDescriptor<Tag>())) ?? []).count == 1)
            var reminder = CustomReminder()
            reminder.title = "Both of us"
            var second = CustomReminder()
            second.title = "Second one"
            SettingsRecords.setReminders([reminder, second], in: uc)
            SettingsRecords.setImportLayouts([SavedImportLayout(name: "My bank", headers: ["Date", "Amount"], layout: ImportLayout())], in: uc)
            try uc.save()
            check("S22 reminders are stored in order", SettingsRecords.reminders(in: uc).map(\.title) == ["Both of us", "Second one"])
            check("S22 import layouts are stored", SettingsRecords.importLayouts(in: uc).map(\.name) == ["My bank"])
            SettingsRecords.setReminders([second], in: uc)
            SettingsRecords.setReminders([second, reminder], in: uc)
            try uc.save()
            check("S22 changes and removals apply, with no duplicates", SettingsRecords.reminders(in: uc).map(\.title) == ["Second one", "Both of us"]
                  && ((try? uc.fetch(FetchDescriptor<ReminderRecord>())) ?? []).count == 2)
            let withSettings = try DataBackup.make(from: uc)
            check("S22 a backup holds them", withSettings.reminders?.count == 2 && withSettings.importLayouts?.count == 1)
            let reread = try DataBackup.decode(try DataBackup.encode(withSettings))
            check("S22 and reads them back", reread.reminders?.map(\.title) == ["Second one", "Both of us"] && reread.importLayouts?.first?.name == "My bank")
            SettingsRecords.setReminders([], in: uc)
            try uc.save()
            var oldBackup = withSettings
            oldBackup.reminders = nil
            oldBackup.importLayouts = nil
            check("S22 a backup from before them leaves the current ones alone", { () -> Bool in
                SettingsRecords.setReminders([reminder], in: uc)
                try? DataBackup.restore(oldBackup, into: uc)
                return SettingsRecords.reminders(in: uc).map(\.title) == ["Both of us"]
            }())
            // Moving them out of preferences happens once, and adds without replacing
            let suite = "OinklyHardening-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            var legacyOnly = CustomReminder()
            legacyOnly.title = "From preferences"
            defaults.set(try JSONEncoder().encode([reminder, legacyOnly]), forKey: "customReminders")
            SettingsRecords.adoptLegacy(in: uc, defaults: defaults)
            SettingsRecords.adoptLegacy(in: uc, defaults: defaults)
            try uc.save()
            check("S22 old reminders are moved in once, none twice", SettingsRecords.reminders(in: uc).map(\.title) == ["Both of us", "From preferences"], "\(SettingsRecords.reminders(in: uc).map(\.title))")

            // S23: the colour picked for a default picture, kept in its own record
            let artAccount = Account(name: "Colourful", type: .savings, openingBalance: 0)
            let artBill = Bill(name: "Colourful bill", amount: 10, frequency: .monthly, dueDate: .now)
            uc.insert(artAccount); uc.insert(artBill)
            ArtworkChoices.set(3, for: artAccount, in: uc)
            ArtworkChoices.set(5, for: artBill, in: uc)
            try uc.save()
            check("S23 a colour is remembered for an account and a bill", ArtworkChoices.theme(for: artAccount) == 3 && ArtworkChoices.theme(for: artBill) == 5)
            check("S23 no choice means Automatic", ArtworkChoices.theme(for: try uc.fetch(FetchDescriptor<Account>()).first { $0.name == "Kept through the upgrade" }!) == 0)
            ArtworkChoices.set(4, for: artAccount, in: uc)
            ArtworkChoices.set(4, for: artAccount, in: uc)
            try uc.save()
            check("S23 changing it keeps one record", ArtworkChoices.theme(for: artAccount) == 4 && ((try? uc.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).filter { $0.key == ArtworkChoices.key(for: artAccount) }.count == 1)
            ArtworkChoices.set(99, for: artBill, in: uc)
            try uc.save()
            check("S23 a colour that doesn't exist becomes Automatic", ArtworkChoices.theme(for: artBill) == 0)
            let artBackup = try DataBackup.decode(try DataBackup.encode(try DataBackup.make(from: uc)))
            check("S23 a backup holds the colour", artBackup.accounts.first { $0.name == "Colourful" }?.artworkTheme == 4)
            try DataBackup.restore(artBackup, into: uc)
            let restoredArt = try uc.fetch(FetchDescriptor<Account>()).first { $0.name == "Colourful" }
            check("S23 and a restore brings it back", restoredArt.map { ArtworkChoices.theme(for: $0) } == 4)
            // Renaming moves the colour with the account
            if let restoredArt {
                let before = ArtworkChoices.key(for: restoredArt)
                restoredArt.name = "Renamed colourful"
                ArtworkChoices.set(4, for: restoredArt, previousKey: before, in: uc)
                try uc.save()
                check("S23 a rename keeps the colour with no stray copy", ArtworkChoices.theme(for: restoredArt) == 4 && ((try? uc.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).count == 1)
                uc.delete(restoredArt)
            }
            try uc.save()
            ArtworkChoices.removeOrphans(in: uc)
            try uc.save()
            check("S23 deleting the account leaves no stray choice", ((try? uc.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).isEmpty)

            // S24: stopping sharing and removing the shared folder, only when nobody else uses it
            func tester(_ name: String, saver: String? = nil) throws -> SharedDataFolder {
                let folder = try fresh(name)
                try folder.checkIn(from: source, baseRevision: nil, by: saver ?? "Me Myself", appVersion: "1.0")
                return folder
            }
            let myLock = lock("me")
            var mine = myLock
            mine.fullName = "Me Myself"
            let s24a = try tester("s24a")
            s24a.noteMember(userName: "me", fullName: "Me Myself")
            check("S24 a login that shares leaves a note", s24a.members().map(\.userName) == ["me"])
            check("S24 alone, nobody else is found", s24a.otherUsers(besides: "me", fullName: "Me Myself").isEmpty)
            s24a.noteMember(userName: "sam", fullName: "Sam Other", now: .now.addingTimeInterval(-10 * 86_400))
            check("S24 another login seen lately is found", s24a.otherUsers(besides: "me", fullName: "Me Myself").map(\.name) == ["Sam Other"])
            s24a.noteMember(userName: "sam", fullName: "Sam Other", now: .now.addingTimeInterval(-40 * 86_400))
            check("S24 one not seen for over 30 days is not", s24a.otherUsers(besides: "me", fullName: "Me Myself").isEmpty)
            let s24b = try tester("s24b", saver: "Pat Else")
            check("S24 a save by someone else counts, even without a note", s24b.otherUsers(besides: "me", fullName: "Me Myself").map(\.name) == ["Pat Else"])
            let s24c = try tester("s24c")
            _ = try s24c.acquire(lock("other-login"))
            check("S24 someone holding it open counts", s24c.otherUsers(besides: "me", fullName: "Me Myself").map(\.name) == ["other-login"])
            // The choice itself
            let keep = try tester("s24-keep")
            keep.noteMember(userName: "me", fullName: "Me Myself")
            let noteKeep = SharedDataSession.leaveSharedFolder(as: mine, remove: false, folder: keep, useTrash: false)
            check("S24 without the choice the folder stays and only this login's note goes", noteKeep == nil && keep.exists && keep.members().isEmpty)
            let shared = try tester("s24-shared", saver: "Pat Else")
            shared.noteMember(userName: "pat", fullName: "Pat Else")
            let noteShared = SharedDataSession.leaveSharedFolder(as: mine, remove: true, folder: shared, useTrash: false)
            check("S24 with someone else still sharing nothing is removed", shared.exists && shared.hasStore && (noteShared ?? "").contains("left in place"), noteShared ?? "")
            let busy = try tester("s24-busy")
            _ = try busy.acquire(lock("other-login"))
            let noteBusy = SharedDataSession.leaveSharedFolder(as: mine, remove: true, folder: busy, useTrash: false)
            check("S24 while someone has it open nothing is removed", busy.exists && (noteBusy ?? "").contains("left in place"), noteBusy ?? "")
            let alone = try tester("s24-alone")
            alone.noteMember(userName: "me", fullName: "Me Myself")
            let noteAlone = SharedDataSession.leaveSharedFolder(as: mine, remove: true, folder: alone, useTrash: false)
            check("S24 when nobody else uses it the folder is removed", !alone.exists && (noteAlone ?? "").contains("removed"), noteAlone ?? "")
            let gone = SharedDataFolder(url: root.appendingPathComponent("never-made", isDirectory: true))
            check("S24 a folder that is already gone is fine", SharedDataSession.leaveSharedFolder(as: mine, remove: true, folder: gone, useTrash: false) == nil)

            // S25: the backup copy: writing, older copies, damage, and the checks against the data
            let shadowRoot = root.appendingPathComponent("shadow-parent", isDirectory: true)
            try manager.createDirectory(at: shadowRoot, withIntermediateDirectories: true)
            let shadow = ShadowFolder(inside: shadowRoot)
            let shadowFirst = try shadow.write(from: source, dataID: "data-1", source: "This Mac", appVersion: "1.0")
            check("S25 the first copy is number 1 and matches the data", shadowFirst.copyNumber == 1 && shadowFirst.accounts == (counts["ZACCOUNT"] ?? 0) && shadowFirst.transactions == (counts["ZTRANSACTION"] ?? 0))
            check("S25 it passes its own check", shadow.allVersions().first.map { shadow.isGood($0) } == true)
            var shadowStat = stat()
            stat(shadow.url.path, &shadowStat)
            check("S25 only its owner can open the folder", shadowStat.st_mode & 0o077 == 0)
            check("S25 no half-written files are left", ((try? manager.contentsOfDirectory(atPath: shadow.url.path)) ?? []).filter { $0.hasSuffix(".tmp") }.isEmpty)
            let shadowSecond = try shadow.write(from: source, dataID: "data-1", source: "This Mac", appVersion: "1.0")
            check("S25 the next copy is number 2 and the first becomes an older copy", shadowSecond.copyNumber == 2 && shadow.olderVersions().count == 1 && shadow.olderVersions().first?.info.copyNumber == 1)
            for _ in 0..<14 { try shadow.write(from: source, dataID: "data-1", source: "This Mac", appVersion: "1.0") }
            check("S25 older copies are trimmed to the newest ten", shadow.olderVersions().count == ShadowFolder.keepNewest, "\(shadow.olderVersions().count)")
            check("S25 the newest older copy is the one just before the latest", shadow.olderVersions().first?.info.copyNumber == (shadow.readInfo()?.copyNumber ?? 0) - 1)
            // A damaged latest copy is noticed, and the newest good one is found
            let latestBytes = try Data(contentsOf: shadow.storeURL)
            try Data(latestBytes.prefix(latestBytes.count / 3)).write(to: shadow.storeURL)
            check("S25 a damaged copy fails its check", shadow.allVersions().first.map { shadow.isGood($0) } == false)
            check("S25 the newest good copy is the next one back", shadow.newestGoodVersion()?.isLatest == false && shadow.newestGoodVersion()?.info.copyNumber == (shadow.readInfo()?.copyNumber ?? 0) - 1)
            // Putting a copy back
            let restoreTarget = root.appendingPathComponent("restored/OinklyBudget.store")
            if let good = shadow.newestGoodVersion() {
                try shadow.restore(good, to: restoreTarget)
                let back = try SQLiteStore.counts(of: restoreTarget)
                check("S25 a restored copy holds the same records", back["ZACCOUNT"] == good.info.accounts && back["ZTRANSACTION"] == good.info.transactions)
                check("S25 a damaged copy is refused", { () -> Bool in
                    guard let bad = shadow.allVersions().first(where: { $0.isLatest }) else { return false }
                    return (try? shadow.restore(bad, to: root.appendingPathComponent("refused/OinklyBudget.store"))) == nil
                }())
            }
            // A backup copy that can't be written changes nothing
            let shadowBefore = shadow.readInfo()
            check("S25 a copy from a missing file fails and leaves the shadow alone", (try? shadow.write(from: root.appendingPathComponent("nothing.store"), dataID: "data-1", source: "This Mac", appVersion: "1.0")) == nil && shadow.readInfo() == shadowBefore)
            // The checks against the data
            let shadow2 = ShadowFolder(inside: root.appendingPathComponent("shadow-2", isDirectory: true))
            try shadow2.write(from: source, dataID: "data-2", source: "This Mac", appVersion: "1.0")
            check("S25 matching data has nothing to say", ShadowCheck.lookAtOwnData(store: source, shadow: shadow2, dataID: "data-2") == nil || (counts["ZTRANSACTION"] ?? 0) == 0)
            check("S25 a backup copy of other data is noticed", ShadowCheck.lookAtOwnData(store: source, shadow: shadow2, dataID: "someone-else") == .otherData)
            check("S25 no backup copy means nothing to say", ShadowCheck.lookAtOwnData(store: source, shadow: ShadowFolder(inside: root.appendingPathComponent("none")), dataID: "data-2") == nil)
            let emptyStore = root.appendingPathComponent("empty/OinklyBudget.store")
            try manager.createDirectory(at: emptyStore.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { _ = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: emptyStore, cloudKitDatabase: .none)) }
            // The backup copy says it holds a lot: put the same data back in its wrapper with a bigger note
            var bigInfo = try unwrap(shadow2.readInfo())
            bigInfo.accounts = 5
            bigInfo.transactions = 200
            let bigPlain = root.appendingPathComponent("big-plain.store")
            try SealedFile.unseal(shadow2.storeURL, to: bigPlain)
            try SealedFile.seal(bigPlain, to: shadow2.storeURL, kind: "data", info: try SealedFile.encodeInfo(bigInfo), appVersion: "1.0")
            check("S25 empty data against a full backup copy is noticed", {
                if case .dataLooksEmpty = ShadowCheck.lookAtOwnData(store: emptyStore, shadow: shadow2, dataID: "data-2") { return true }
                return false
            }())
            check("S25 data that has gone missing is noticed", {
                if case .dataLooksEmpty = ShadowCheck.lookAtOwnData(store: root.appendingPathComponent("gone.store"), shadow: shadow2, dataID: "data-2") { return true }
                return false
            }())
            let garbage = root.appendingPathComponent("garbage.store")
            try Data("not a database at all".utf8).write(to: garbage)
            check("S25 unreadable data is noticed", {
                if case .dataUnreadable = ShadowCheck.lookAtOwnData(store: garbage, shadow: shadow2, dataID: "data-2") { return true }
                return false
            }())
            // Sharing
            let sharedA = try fresh("s25-shared")
            let sharedInfo = try sharedA.checkIn(from: source, baseRevision: nil, by: "A", appVersion: "1.0")
            let shadow3 = ShadowFolder(inside: root.appendingPathComponent("shadow-3", isDirectory: true))
            try shadow3.write(from: source, dataID: "data-3", source: "Shared data", sharedRevision: sharedInfo.revision, sharedFileID: sharedInfo.fileID, appVersion: "1.0")
            check("S25 shared data that matches the backup copy has nothing to say", ShadowCheck.lookAtSharedData(sharedA, shadow: shadow3, dataID: "data-3") == nil)
            let shadow4 = ShadowFolder(inside: root.appendingPathComponent("shadow-4", isDirectory: true))
            try shadow4.write(from: source, dataID: "data-3", source: "Shared data", sharedRevision: sharedInfo.revision + 4, sharedFileID: sharedInfo.fileID, appVersion: "1.0")
            check("S25 shared data older than the backup copy is noticed", ShadowCheck.lookAtSharedData(sharedA, shadow: shadow4, dataID: "data-3") == .sharedOlder(sharedRevision: sharedInfo.revision, shadowRevision: sharedInfo.revision + 4))
            let shadow5 = ShadowFolder(inside: root.appendingPathComponent("shadow-5", isDirectory: true))
            try shadow5.write(from: source, dataID: "data-3", source: "Shared data", sharedRevision: 1, sharedFileID: "another-shared-data", appVersion: "1.0")
            check("S25 shared data that isn't the data the shadow came from is noticed", ShadowCheck.lookAtSharedData(sharedA, shadow: shadow5, dataID: "data-3") == .sharedIsDifferent)
            let sharedGone = SharedDataFolder(url: root.appendingPathComponent("s25-gone", isDirectory: true))
            check("S25 shared data that is missing is noticed when there is a backup copy", ShadowCheck.lookAtSharedData(sharedGone, shadow: shadow3, dataID: "data-3") == .sharedMissing)
            check("S25 and not when there is none", ShadowCheck.lookAtSharedData(sharedGone, shadow: ShadowFolder(inside: root.appendingPathComponent("no-shadow")), dataID: "data-3") == nil)
            let sharedBad = try fresh("s25-bad")
            try Data("damaged".utf8).write(to: sharedBad.storeURL)
            check("S25 damaged shared data is noticed", {
                if case .sharedUnreadable = ShadowCheck.lookAtSharedData(sharedBad, shadow: shadow3, dataID: "data-3") { return true }
                return false
            }())

            // S26: putting the shared data back from the backup copy or from an earlier save
            let staging26 = root.appendingPathComponent("rescue-staging", isDirectory: true)
            var me26 = lock("me")
            me26.fullName = "Me Myself"
            guard let version3 = shadow3.allVersions().first, let version4 = shadow4.allVersions().first, let version5 = shadow5.allVersions().first else { throw CocoaError(.fileNoSuchFile) }
            // The folder is gone
            try SharedRescue.rebuild(sharedGone, from: version3, in: shadow3, me: me26, appVersion: "1.0", staging: staging26)
            let gotBack = sharedGone.readInfo()?.counts ?? [:]
            check("S26 a missing shared folder is made again from the backup copy", sharedGone.hasStore && SealedFile.isIntact(sharedGone.storeURL) && gotBack["ZACCOUNT"] == version3.info.accounts && gotBack["ZTRANSACTION"] == version3.info.transactions)
            check("S26 it carries on the backup copy's data ID and numbering", sharedGone.readInfo()?.fileID == version3.info.sharedFileID && (sharedGone.readInfo()?.revision ?? 0) >= (version3.info.sharedRevision ?? 0))
            check("S26 and the two agree afterwards", ShadowCheck.lookAtSharedData(sharedGone, shadow: shadow3, dataID: "data-3") == nil)
            check("S26 the lock is let go afterwards", sharedGone.holder() == nil)
            // Shared data older than the backup copy
            try SharedRescue.rebuild(sharedA, from: version4, in: shadow4, me: me26, appVersion: "1.0", staging: staging26)
            check("S26 shared data that went backwards is put right", ShadowCheck.lookAtSharedData(sharedA, shadow: shadow4, dataID: "data-3") == nil && (sharedA.readInfo()?.revision ?? 0) >= (version4.info.sharedRevision ?? 99))
            check("S26 what was there is kept as an earlier save", !sharedA.versions().isEmpty)
            // Different shared data
            let sharedOther = try tester("s26-other", saver: "Pat Else")
            try SharedRescue.rebuild(sharedOther, from: version5, in: shadow5, me: me26, appVersion: "1.0", staging: staging26)
            check("S26 different shared data can be replaced by the backup copy's", ShadowCheck.lookAtSharedData(sharedOther, shadow: shadow5, dataID: "data-3") == nil && sharedOther.readInfo()?.fileID == "another-shared-data")
            // Damaged shared data
            try SharedRescue.rebuild(sharedBad, from: version3, in: shadow3, me: me26, appVersion: "1.0", staging: staging26)
            check("S26 damaged shared data is replaced and the damaged file kept", SealedFile.isIntact(sharedBad.storeURL) && sharedBad.readInfo() != nil
                  && ((try? manager.contentsOfDirectory(atPath: sharedBad.historyURL.path)) ?? []).contains { $0.hasSuffix(".bad") })
            // Somebody has it open
            let busy26 = try tester("s26-busy")
            _ = try busy26.acquire(lock("other-login"))
            let busyBefore = busy26.readInfo()
            check("S26 nothing is put back while someone has the shared data open", (try? SharedRescue.rebuild(busy26, from: version3, in: shadow3, me: me26, appVersion: "1.0", staging: staging26)) == nil && busy26.readInfo() == busyBefore)
            // A damaged copy is refused
            check("S26 a damaged backup copy is refused", { () -> Bool in
                guard let latest = shadow.allVersions().first(where: { $0.isLatest }) else { return false }
                return (try? SharedRescue.rebuild(try! fresh("s26-refused"), from: latest, in: shadow, me: me26, appVersion: "1.0", staging: staging26)) == nil
            }())
            // An earlier save in the shared folder
            let earlier = try tester("s26-earlier")
            try earlier.checkIn(from: source, baseRevision: 1, by: "Me Myself", appVersion: "1.0")
            try Data("damaged".utf8).write(to: earlier.storeURL)
            let restoredEarlier = try SharedRescue.restoreNewestGoodEarlierSave(earlier, me: me26, appVersion: "1.0", staging: staging26)
            check("S26 the newest good earlier save is put back", restoredEarlier && SealedFile.isIntact(earlier.storeURL) && earlier.readInfo() != nil)
            let none = try fresh("s26-none")
            check("S26 with no earlier save nothing is changed", (try? SharedRescue.restoreNewestGoodEarlierSave(none, me: me26, appVersion: "1.0", staging: staging26)) == false)

            // S27: the one status for the database and the backup copy
            let upToDate27 = ShadowCopyManager.Status.upToDate(.now.addingTimeInterval(-300))
            func words(_ database: DatabaseStatus.State, _ shadow: ShadowCopyManager.Status, sharing: Bool = false) -> String {
                MainActor.assumeIsolated { ShadowDatabaseStatusLabel.look(database: database, shadow: shadow, sharing: sharing).text }
            }
            check("S27 all well says copied", words(.saved, upToDate27).hasPrefix("Backup Copy Database · Copied"))
            check("S27 no backup copy set up shows the shadow status", words(.saved, .notSetUp) == "Backup Copy Database · Not set up")
            check("S27 a database problem comes first", words(.problem("x"), .notSetUp) == "Database · Problem" && words(.problem("x"), .failed("y")) == "Database · Problem")
            check("S27 a failing backup copy is next", words(.saved, .failed("y")) == "Backup Copy · Problem")
            check("S27 a backup copy that needs attention beats saving", words(.unsaved, .behind(nil)) == "Backup Copy Database · Out of date" && words(.unsaved, .folderMissing) == "Backup Copy Database · Folder not found")
            check("S27 saving or copying shows as work in progress", words(.unsaved, upToDate27) == "Backup Copy Database · Saving…" && words(.saved, .copying) == "Backup Copy Database · Copying…")
            check("S27 while sharing, unsaved changes are the Shared dot's to report", words(.unsaved, upToDate27, sharing: true).hasPrefix("Backup Copy Database · Copied"))
            check("S27 while sharing, a database problem still shows", words(.problem("x"), upToDate27, sharing: true) == "Database · Problem")

            // S28: the sealed file format, and the backup copy's receipts
            let sealedPlain = root.appendingPathComponent("sealed/plain.store")
            try manager.createDirectory(at: sealedPlain.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: sealedPlain)
            let sealedURL = root.appendingPathComponent("sealed/data.pigdata")
            let header28 = try SealedFile.seal(sealedPlain, to: sealedURL, kind: "data", info: Data("note".utf8), appVersion: "1.0")
            check("S28 a sealed file's header can be read without opening it", (try? SealedFile.readHeader(sealedURL)) == header28 && header28.kind == "data" && header28.info == Data("note".utf8))
            let sealedHead = try Data(contentsOf: sealedURL).prefix(65_536)
            check("S28 it doesn't look like a database or text", !sealedHead.starts(with: Data("SQLite format 3".utf8)) && String(data: sealedHead, encoding: .utf8) == nil)
            check("S28 a database tool can't open it", (try? SQLiteStore.integrityIsOK(sealedURL)) != true)
            check("S28 it passes its own check", SealedFile.isIntact(sealedURL))
            let unsealed = root.appendingPathComponent("sealed/unsealed.store")
            try SealedFile.unseal(sealedURL, to: unsealed)
            check("S28 unpacking gives back exactly the same bytes", try Data(contentsOf: unsealed) == Data(contentsOf: sealedPlain))
            check("S28 and the same records", try SQLiteStore.counts(of: unsealed) == SQLiteStore.counts(of: sealedPlain) && SQLiteStore.integrityIsOK(unsealed))
            // Damage
            var damaged = try Data(contentsOf: sealedURL)
            damaged[damaged.count / 2] ^= 0xFF
            let damagedURL = root.appendingPathComponent("sealed/damaged.pigdata")
            try damaged.write(to: damagedURL)
            check("S28 one changed byte is noticed", !SealedFile.isIntact(damagedURL))
            let refusedOut = root.appendingPathComponent("sealed/refused.store")
            check("S28 a damaged file is refused and leaves nothing behind", (try? SealedFile.unseal(damagedURL, to: refusedOut)) == nil && !manager.fileExists(atPath: refusedOut.path)
                  && ((try? manager.contentsOfDirectory(atPath: refusedOut.deletingLastPathComponent().path)) ?? []).filter { $0.hasSuffix(".tmp") }.isEmpty)
            let cutURL = root.appendingPathComponent("sealed/cut.pigdata")
            try Data(damaged.prefix(damaged.count - 5_000)).write(to: cutURL)
            check("S28 a file cut short is noticed", !SealedFile.isIntact(cutURL) && (try? SealedFile.unseal(cutURL, to: refusedOut)) == nil)
            let textURL = root.appendingPathComponent("sealed/text.pigdata")
            try Data("just some text, not an Oinkly Budget file at all".utf8).write(to: textURL)
            check("S28 other files are not mistaken for sealed ones", (try? SealedFile.readHeader(textURL)) == nil && !SealedFile.isIntact(textURL))
            // A file bigger than one chunk
            let bigURL = root.appendingPathComponent("sealed/big.bin")
            var bigBytes = Data()
            var seed: UInt64 = 42
            for _ in 0..<(3 * SealedFile.chunkSize / 8 + 777) { seed = seed &* 6364136223846793005 &+ 1442695040888963407; withUnsafeBytes(of: seed) { bigBytes.append(contentsOf: $0) } }
            bigBytes.append(Data(repeating: 7, count: 2_000_000))
            try bigBytes.write(to: bigURL)
            let bigSealed = root.appendingPathComponent("sealed/big.pigdata")
            let bigBack = root.appendingPathComponent("sealed/big-back.bin")
            try SealedFile.seal(bigURL, to: bigSealed, kind: "receipt", appVersion: "1.0")
            try SealedFile.unseal(bigSealed, to: bigBack)
            check("S28 a large file survives the round trip", try Data(contentsOf: bigBack) == bigBytes, "\(bigBytes.count) bytes")
            // Receipts in the backup copy
            let receiptSource = root.appendingPathComponent("receipt-source/OinklyBudget.store")
            try manager.createDirectory(at: receiptSource.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: receiptSource)
            let externalDir = StoreFiles.supportURL(for: receiptSource).appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
            try manager.createDirectory(at: externalDir, withIntermediateDirectories: true)
            let receiptBytes = Data((0..<50_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 8)) })
            try receiptBytes.write(to: externalDir.appendingPathComponent("A1B2C3D4"))
            let shadow6 = ShadowFolder(inside: root.appendingPathComponent("shadow-6", isDirectory: true))
            try shadow6.write(from: receiptSource, dataID: "data-6", source: "This Mac", appVersion: "1.0")
            let sealedReceipt = shadow6.receiptsURL.appendingPathComponent("_EXTERNAL_DATA/A1B2C3D4.pigdata")
            check("S28 a receipt is kept sealed in the backup copy", manager.fileExists(atPath: sealedReceipt.path) && (try? Data(contentsOf: sealedReceipt)) != receiptBytes)
            check("S28 and every file in the backup copy is sealed", { () -> Bool in
                guard let walker = manager.enumerator(at: shadow6.url, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
                for case let item as URL in walker where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                    if item.pathExtension != SealedFile.fileExtension { return false }
                }
                return true
            }())
            let restoredStore = root.appendingPathComponent("receipt-restored/OinklyBudget.store")
            if let latest6 = shadow6.allVersions().first {
                try shadow6.restore(latest6, to: restoredStore)
                let restoredReceipt = StoreFiles.supportURL(for: restoredStore).appendingPathComponent("_EXTERNAL_DATA/A1B2C3D4")
                check("S28 restoring brings the receipt back exactly", (try? Data(contentsOf: restoredReceipt)) == receiptBytes)
            }
            check("S28 a second copy doesn't seal the same receipt again", { () -> Bool in
                let before = (try? manager.attributesOfItem(atPath: sealedReceipt.path)[.modificationDate] as? Date) ?? nil
                _ = try? shadow6.write(from: receiptSource, dataID: "data-6", source: "This Mac", appVersion: "1.0")
                let after = (try? manager.attributesOfItem(atPath: sealedReceipt.path)[.modificationDate] as? Date) ?? nil
                return before != nil && before == after
            }())

            // S29: a shared folder from before the sealed format is converted once, without losing anything
            let legacy = try fresh("s29-legacy")
            let jsonEncoder = JSONEncoder(); jsonEncoder.dateEncodingStrategy = .iso8601
            let oldSaved = Date.now.addingTimeInterval(-3 * 86_400)
            let oldInfo = SharedInfo(formatVersion: 1, schemaVersion: 4, revision: 7, savedAt: oldSaved, savedBy: "Old Builder", appVersion: "0.9", fileID: "legacy-file-id")
            try manager.copyItem(at: source, to: legacy.legacyStoreURL)
            try jsonEncoder.encode(oldInfo).write(to: legacy.legacyInfoURL)
            try manager.createDirectory(at: legacy.historyURL, withIntermediateDirectories: true)
            var olderInfo = oldInfo
            olderInfo.revision = 6
            olderInfo.savedAt = oldSaved.addingTimeInterval(-3_600)
            let olderStore = legacy.historyURL.appendingPathComponent("save 6 old.store")
            try manager.copyItem(at: source, to: olderStore)
            try jsonEncoder.encode(olderInfo).write(to: olderStore.deletingPathExtension().appendingPathExtension("json"))
            let legacySupport = StoreFiles.supportURL(for: legacy.legacyStoreURL).appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
            try manager.createDirectory(at: legacySupport, withIntermediateDirectories: true)
            let oldReceipt = Data((0..<3_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
            try oldReceipt.write(to: legacySupport.appendingPathComponent("OLDRECEIPT"))
            try Data("2026-10-01  08:00:00  saved by Old Builder as save number 7\n".utf8).write(to: legacy.legacyLogURL)
            check("S29 an old folder counts as having data, in the old format", legacy.hasData && legacy.hasLegacyData && !legacy.hasStore)
            check("S29 its note is still readable before converting", legacy.readInfo()?.revision == 7 && legacy.readInfo()?.fileID == "legacy-file-id")
            // an old copy of the app holding the lock still counts
            var oldLock = lock("old-app")
            oldLock.fullName = "Old App"
            try jsonEncoder.encode(oldLock).write(to: legacy.legacyLockURL)
            check("S29 a lock under the old name still counts", { () -> Bool in
                if case .heldBy(let held, _)? = try? legacy.acquire(lock("new-app")) { return held.userName == "old-app" }
                return false
            }())
            try manager.removeItem(at: legacy.legacyLockURL)
            check("S29 the shadow checks understand an old folder", ShadowCheck.lookAtSharedData(legacy, shadow: ShadowFolder(inside: root.appendingPathComponent("no-shadow-29")), dataID: "x") == nil)
            // convert
            let converted = try legacy.convertLegacyIfNeeded(appVersion: "1.0")
            check("S29 the folder is converted", converted && legacy.hasStore && !legacy.hasLegacyData && SealedFile.isIntact(legacy.storeURL))
            check("S29 the numbering and data ID carry over", legacy.readInfo()?.revision == 7 && legacy.readInfo()?.fileID == "legacy-file-id" && legacy.readInfo()?.savedBy == "Old Builder")
            check("S29 the records are the same", legacy.readInfo()?.counts == counts)
            check("S29 the previous save is converted", legacy.versions().map(\.info.revision) == [6] && legacy.versions().first.map { SealedFile.isIntact($0.url) } == true)
            check("S29 the receipt is sealed in the new place", manager.fileExists(atPath: legacy.receiptsURL.appendingPathComponent("_EXTERNAL_DATA/OLDRECEIPT.pigdata").path))
            let openedLegacy = root.appendingPathComponent("o29/OinklyBudget.store")
            try legacy.checkOut(to: openedLegacy)
            check("S29 and it comes back exactly when the data is opened", (try? Data(contentsOf: StoreFiles.supportURL(for: openedLegacy).appendingPathComponent("_EXTERNAL_DATA/OLDRECEIPT"))) == oldReceipt)
            check("S29 the log is kept", legacy.recentLog().contains { $0.contains("save number 7") } && legacy.recentLog().contains { $0.contains("converted") })
            let leftovers29 = ((try? manager.contentsOfDirectory(atPath: legacy.url.path)) ?? []).filter { $0.hasSuffix(".store") || $0.hasSuffix(".json") || $0.hasSuffix(".txt") }
            check("S29 the old files are gone", leftovers29.isEmpty && !manager.fileExists(atPath: StoreFiles.supportURL(for: legacy.legacyStoreURL).path) && ((try? manager.contentsOfDirectory(atPath: legacy.historyURL.path)) ?? []).allSatisfy { $0.hasSuffix(".pigdata") }, "\(leftovers29)")
            check("S29 nothing in the folder is plain text, JSON or a database", { () -> Bool in
                guard let walker = manager.enumerator(at: legacy.url, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
                for case let item as URL in walker where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                    if !["pigdata", "pigmeta"].contains(item.pathExtension) { return false }
                }
                return true
            }())
            check("S29 converting again does nothing", try legacy.convertLegacyIfNeeded(appVersion: "1.0") == false)
            // damaged old data is not converted, and stays as it was
            let legacyBad = try fresh("s29-bad")
            try Data(repeating: 0xAB, count: 4_096).write(to: legacyBad.legacyStoreURL)
            check("S29 damaged old data is refused and left alone", (try? legacyBad.convertLegacyIfNeeded(appVersion: "1.0")) == nil && !legacyBad.hasStore && legacyBad.hasLegacyData)
            // a new save into a converted folder works and the earlier data is kept
            let afterConvert = try legacy.checkIn(from: source, baseRevision: 7, by: "New Builder", appVersion: "1.0")
            check("S29 a save after converting carries on from the old numbering", afterConvert.revision == 8 && legacy.versions().contains { $0.info.revision == 7 })
            // two logins both try to convert at once: only the one holding the lock may, so the second finds it done
            let legacy2 = try fresh("s29-two")
            try manager.copyItem(at: source, to: legacy2.legacyStoreURL)
            try jsonEncoder.encode(oldInfo).write(to: legacy2.legacyInfoURL)
            _ = try legacy2.convertLegacyIfNeeded(appVersion: "1.0")
            check("S29 a second look at a converted folder finds nothing to do", try legacy2.convertLegacyIfNeeded(appVersion: "1.0") == false && legacy2.readInfo()?.revision == 7)

            // S30: .pig backups are sealed, and old plain ones still open
            let backup30 = try DataBackup.make(from: uc)
            let sealedBackup = try DataBackup.encode(backup30)
            check("S30 a saved backup is sealed, not JSON", SealedFile.isSealed(sealedBackup) && (try? JSONSerialization.jsonObject(with: sealedBackup)) == nil
                  && String(data: sealedBackup.prefix(4_096), encoding: .utf8) == nil)
            check("S30 and it reads back the same", (try? DataBackup.decode(sealedBackup).summary) == backup30.summary)
            let plainEncoder = JSONEncoder()
            plainEncoder.dateEncodingStrategy = .secondsSince1970
            let plainBackup30 = try plainEncoder.encode(backup30)
            check("S30 a plain backup from an earlier build still opens", (try? DataBackup.decode(plainBackup30).summary) == backup30.summary)
            var damagedBackup = sealedBackup
            damagedBackup[damagedBackup.count / 2] ^= 0xFF
            check("S30 a damaged backup is refused", (try? DataBackup.decode(damagedBackup)) == nil)
            check("S30 so is something that isn't a backup", (try? DataBackup.decode(Data("hello".utf8))) == nil)
            check("S30 the header says what it is without opening it", { () -> Bool in
                let file = root.appendingPathComponent("backup30.pig")
                try? sealedBackup.write(to: file)
                return (try? SealedFile.readHeader(file))?.kind == "backup"
            }())

            // S31: the portable .pig file beside each snapshot in the backup copy
            let shadow7 = ShadowFolder(inside: root.appendingPathComponent("shadow-7", isDirectory: true))
            let snapshot7 = try shadow7.write(from: source, dataID: "data-7", source: "This Mac", appVersion: "1.0")
            let file31 = try DataBackup.make(from: uc)
            let json31 = try DataBackup.plainJSON(file31)
            var portableInfo31 = DataBackup.portableInfo(file31)
            portableInfo31.accounts = snapshot7.accounts
            portableInfo31.transactions = snapshot7.transactions
            let base31 = Date.now
            check("S31 a portable file is written when it matches the snapshot", try shadow7.writePortable(json: json31, info: portableInfo31, matching: snapshot7, appVersion: "1.0", now: base31))
            let listed31 = shadow7.portableVersions()
            check("S31 it is listed, sealed, and says what it is without opening it", listed31.count == 1 && SealedFile.isIntact(listed31[0].url)
                  && (try? SealedFile.readHeader(listed31[0].url))?.kind == "backup" && listed31[0].info.summary == file31.summary)
            check("S31 it is not readable as JSON", (try? JSONSerialization.jsonObject(with: Data(contentsOf: listed31[0].url))) == nil)
            check("S31 and it reads back as the same backup", (try? DataBackup.decode(Data(contentsOf: listed31[0].url)).summary) == file31.summary)
            var other31 = portableInfo31
            other31.transactions += 1
            check("S31 one that doesn't match the snapshot is skipped", try shadow7.writePortable(json: json31, info: other31, matching: snapshot7, appVersion: "1.0", now: base31.addingTimeInterval(1)) == false && shadow7.portableVersions().count == 1)
            for step in 2...8 { try shadow7.writePortable(json: json31, info: portableInfo31, matching: snapshot7, appVersion: "1.0", now: base31.addingTimeInterval(Double(step) * 60)) }
            let kept31 = shadow7.portableVersions()
            check("S31 only the newest five are kept, newest first", kept31.count == ShadowFolder.keepPortable && kept31 == kept31.sorted { $0.info.savedAt > $1.info.savedAt }, "\(kept31.count)")
            check("S31 the snapshot and the older snapshots are not touched by it", shadow7.readInfo() == snapshot7)
            var broken31 = try Data(contentsOf: kept31[0].url)
            broken31[broken31.count / 2] ^= 0xFF
            try broken31.write(to: kept31[0].url)
            check("S31 a damaged portable file is noticed and the next one is offered", !shadow7.isGood(kept31[0]) && shadow7.newestGoodPortable()?.url == kept31[1].url)
            check("S31 every file in the backup copy is in Oinkly Budget's formats", { () -> Bool in
                guard let walker = manager.enumerator(at: shadow7.url, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
                for case let item as URL in walker where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                    if !["pigdata", "pig"].contains(item.pathExtension) { return false }
                }
                return true
            }())
            // Restoring from the portable file
            let freshContainer = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            if let good31 = shadow7.newestGoodPortable() {
                let decoded31 = try DataBackup.decode(Data(contentsOf: good31.url))
                try DataBackup.restore(decoded31, into: freshContainer.mainContext)
                check("S31 restoring from it brings the accounts back", ((try? freshContainer.mainContext.fetch(FetchDescriptor<Account>())) ?? []).filter { $0.isLive && !$0.isDefault }.count == file31.accounts.filter { $0.isDefault != true }.count)
            }
            // A folder made under the old name is moved to the new one
            let oldParent = root.appendingPathComponent("old-name-parent", isDirectory: true)
            let oldFolder = oldParent.appendingPathComponent("Oinkly Budget Shadow Copy", isDirectory: true)
            try manager.createDirectory(at: oldFolder, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: oldFolder.appendingPathComponent("marker.pigdata"))
            let migrated = ShadowFolder(inside: oldParent)
            check("S31 a folder from the shadow copy days is moved to the new name", migrated.exists && !manager.fileExists(atPath: oldFolder.path) && manager.fileExists(atPath: migrated.url.appendingPathComponent("marker.pigdata").path))

            // S32: receipt clean-up in the backup copy
            let shadow8 = ShadowFolder(inside: root.appendingPathComponent("shadow-8", isDirectory: true))
            let work32 = root.appendingPathComponent("w32/OinklyBudget.store")
            let usedNow32 = "55555555-5555-4555-8555-555555555555", usedByOlder32 = "66666666-6666-4666-8666-666666666666"
            let unusedOld32 = "77777777-7777-4777-8777-777777777777", unusedNew32 = "88888888-8888-4888-8888-888888888888"
            try makeStore(pointingTo: [usedByOlder32], at: work32)
            try shadow8.write(from: work32, dataID: "data-8", source: "This Mac", appVersion: "1.0")
            let pool32 = shadow8.receiptsURL.appendingPathComponent("_EXTERNAL_DATA", isDirectory: true)
            try manager.createDirectory(at: pool32, withIntermediateDirectories: true)
            let plain32 = root.appendingPathComponent("plain-32")
            try Data("receipt".utf8).write(to: plain32)
            for (name, age) in [(usedNow32, 90), (usedByOlder32, 90), (unusedOld32, 90), (unusedNew32, 5)] {
                let file = pool32.appendingPathComponent(name + ".pigdata")
                try SealedFile.seal(plain32, to: file, kind: "receipt", appVersion: "1.0")
                try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-Double(age) * 86_400)], ofItemAtPath: file.path)
            }
            try makeStore(pointingTo: [usedNow32], at: work32)
            try shadow8.write(from: work32, dataID: "data-8", source: "This Mac", appVersion: "1.0", now: .now.addingTimeInterval(60))
            func there32(_ name: String) -> Bool { manager.fileExists(atPath: pool32.appendingPathComponent(name + ".pigdata").path) }
            check("S32 each copy's note lists the receipts it uses", shadow8.readInfo()?.attachments == [usedNow32] && shadow8.olderVersions().first?.info.attachments == [usedByOlder32])
            check("S32 an old receipt nothing uses is removed", !there32(unusedOld32))
            check("S32 a receipt the latest copy uses is kept", there32(usedNow32))
            check("S32 a receipt only an older copy uses is kept", there32(usedByOlder32))
            check("S32 a new receipt nothing uses yet is kept", there32(unusedNew32))
            // an older copy whose note can't be read stops the clean-up
            try manager.setAttributes([.modificationDate: Date.now.addingTimeInterval(-90 * 86_400)], ofItemAtPath: pool32.appendingPathComponent(unusedNew32 + ".pigdata").path)
            if let older32 = shadow8.olderVersions().first { try Data(repeating: 0, count: 4_096).write(to: older32.url) }
            check("S32 nothing is removed when a copy's note can't be read", shadow8.removeUnusedReceipts() == 0 && there32(unusedNew32) && there32(usedNow32))

            // S33: when the backup copy reminder asks (every start while the switch is on)
            check("S33 it asks when nothing is set up and there is data", ShadowCopyManager.shouldAsk(isSetUp: false, hasData: true, reminderOn: true))
            check("S33 not when a backup copy is set up", !ShadowCopyManager.shouldAsk(isSetUp: true, hasData: true, reminderOn: true))
            check("S33 not with no data yet", !ShadowCopyManager.shouldAsk(isSetUp: false, hasData: false, reminderOn: true))
            check("S33 not when the reminder is switched off", !ShadowCopyManager.shouldAsk(isSetUp: false, hasData: true, reminderOn: false))

            // S34: a quiet start at login
            check("S34 at login with the menu bar item on, it starts quietly", StartupState.shouldStartHidden(launchedAtLogin: true, menuBarItemOn: true))
            check("S34 at login with the menu bar item off, the window opens", !StartupState.shouldStartHidden(launchedAtLogin: true, menuBarItemOn: false))
            check("S34 opened by the person, the window opens", !StartupState.shouldStartHidden(launchedAtLogin: false, menuBarItemOn: true))

            // S35: the Month Outlook, and linking a bill to the payment that really came out
            do {
                let calendar = Calendar.current
                func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2030, month: 1, day: d))! }
                let oc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let bank = Account(name: "Outlook bank", type: .checking, openingBalance: 0)
                let groceries = Category(name: "Outlook groceries", colorHex: "34C759", symbol: "cart", monthlyLimit: 400)
                let electric = Bill(name: "Electric", amount: 90, frequency: .monthly, dueDate: day(10))
                let paycheque = RecurringTransaction(payee: "Outlook pay", account: bank, category: nil, amount: 3000, frequency: .monthly, startDate: day(20))
                oc.insert(bank); oc.insert(groceries); oc.insert(electric); oc.insert(paycheque)
                let shop = Transaction(account: bank, date: day(3), payee: "Market", category: groceries, amount: -150)
                let fuel = Transaction(account: bank, date: day(4), payee: "Fuel", category: nil, amount: -40)
                let draft = Transaction(account: bank, date: day(11), payee: "City Electric Co", category: nil, amount: -118)
                oc.insert(shop); oc.insert(fuel); oc.insert(draft)
                try oc.save()
                func outlook() throws -> MonthOutlook {
                    MonthOutlook.build(month: day(1), bills: [electric], rules: [paycheque], categories: [groceries],
                                       monthTransactions: try oc.fetch(FetchDescriptor<Transaction>()), now: day(15), calendar: calendar)
                }
                let before = try outlook()
                check("S35 nothing linked: the bill counts at what is expected", before.bills.first?.counted == 90 && before.bills.first?.status == .overdue, "\(before.bills.map(\.counted))")
                check("S35 a payee that looks like the bill is suggested", BillLink.suggestion(for: electric, due: day(10), in: [draft, shop, fuel]) === draft)
                BillLink.link(draft, to: electric, due: day(10), calendar: calendar)
                try oc.save()
                let linked = try outlook()
                check("S35 linked: the bill counts at what came out", linked.bills.first?.counted == 118 && linked.bills.first?.status == .over && linked.billDifference == 28)
                check("S35 a linked payment is not counted twice as other spending", linked.otherSpending == 40, "\(linked.otherSpending)")
                check("S35 a budget counts at its limit when under it", linked.budgets.first?.counted == 400 && linked.budgets.first?.spent == 150)
                check("S35 left to save is income less bills, budgets and other spending", linked.incomeTotal == 3000 && linked.leftToSave == 3000 - 118 - 400 - 40, "\(linked.leftToSave)")
                oc.insert(Transaction(account: bank, date: day(6), payee: "Market again", category: groceries, amount: -300))
                try oc.save()
                let over = try outlook()
                check("S35 a budget that ran over counts at what was spent", over.budgets.first?.counted == 450 && over.budgetOverspend == 50 && over.leftToSave == 3000 - 118 - 450 - 40)
                BillLink.unlink(draft, calendar: calendar)
                try oc.save()
                let unlinked = try outlook()
                check("S35 unlinking puts the bill back to expected and unpaid", unlinked.bills.first?.counted == 90 && !electric.isPaid(on: day(10)) && unlinked.billDifference == 0)
                // Accounts can be left out
                let other = Account(name: "Outlook business", type: .checking, openingBalance: 0)
                oc.insert(other)
                oc.insert(Transaction(account: other, date: day(7), payee: "Business lunch", category: groceries, amount: -75))
                oc.insert(Transaction(account: other, date: day(8), payee: "Client paid", category: nil, amount: 900))
                try oc.save()
                let withBoth = try outlook()
                let without = MonthOutlook.build(month: day(1), bills: [electric], rules: [paycheque], categories: [groceries],
                                                 monthTransactions: try oc.fetch(FetchDescriptor<Transaction>()),
                                                 excludedAccounts: [MonthOutlook.accountKey(other)], now: day(15), calendar: calendar)
                check("S35 an account left out takes its income and spending out", withBoth.otherIncome - without.otherIncome == 900 && without.budgets.first?.spent == (withBoth.budgets.first?.spent ?? 0) - 75)
                check("S35 the choice is kept as text and read back", MonthOutlook.excluded(from: MonthOutlook.stored([MonthOutlook.accountKey(other), "x|y"])) == [MonthOutlook.accountKey(other), "x|y"])
                BillLink.link(draft, to: electric, due: day(10), calendar: calendar)
                let paidFromElsewhere = MonthOutlook.build(month: day(1), bills: [electric], rules: [], categories: [groceries], monthTransactions: try oc.fetch(FetchDescriptor<Transaction>()),
                                                           excludedAccounts: [MonthOutlook.accountKey(bank)], now: day(15), calendar: calendar)
                check("S35 a bill paid from an account that is left out is left out", paidFromElsewhere.bills.isEmpty)
                BillLink.unlink(draft, calendar: calendar)
                try oc.save()
                // A bill inside a budget is counted once
                let inBudget = Bill(name: "Cart club", amount: 25, frequency: .monthly, dueDate: day(20))
                inBudget.category = groceries
                oc.insert(inBudget)
                let both = MonthOutlook.build(month: day(1), bills: [inBudget], rules: [], categories: [groceries],
                                              monthTransactions: try oc.fetch(FetchDescriptor<Transaction>()), now: day(15), calendar: calendar)
                check("S35 a bill in a budgeted category sits inside the budget, not beside it", both.bills.isEmpty && both.budgets.first?.inside.count == 1 && both.budgets.first?.planned == 25)
                check("S35 and the budget still counts at spent plus planned when that is more", both.budgets.first?.counted == (both.budgets.first?.spent ?? 0) + 25, "\(both.budgets.first?.counted ?? 0)")
                // The saved figures of a closed month survive a backup and restore
                oc.insert(OutlookSnapshot(monthKey: OutlookSnapshots.key(for: day(1)), outlook: linked))
                try oc.save()
                let copy = try DataBackup.decode(try DataBackup.encode(try DataBackup.make(from: oc)))
                check("S35 a backup holds the saved month", copy.outlooks?.first?.leftToSave == linked.leftToSave)
                try DataBackup.restore(copy, into: oc)
                check("S35 a restore brings it back", OutlookSnapshots.snapshot(for: day(1), in: oc)?.leftToSave == linked.leftToSave)
                // Cash budgets are left out
                let cashCategory = groceries
                let noCash = MonthOutlook.build(month: day(1), bills: [inBudget], rules: [], categories: [cashCategory],
                                                monthTransactions: try oc.fetch(FetchDescriptor<Transaction>()), now: day(15), calendar: calendar)
                let withCash = MonthOutlook.build(month: day(1), bills: [inBudget], rules: [], categories: [cashCategory],
                                                  monthTransactions: try oc.fetch(FetchDescriptor<Transaction>()),
                                                  cashBudgetKeys: [CashBudgets.key(for: cashCategory)], now: day(15), calendar: calendar)
                check("S35 a cash budget is not in the outlook, nor its bills or spending",
                      withCash.budgets.isEmpty && withCash.bills.isEmpty && withCash.otherSpending == noCash.otherSpending, "\(withCash.budgets.count) \(withCash.bills.count) \(withCash.otherSpending)")
                let cashy = Category(name: "Cash envelope", colorHex: "34C759", symbol: "tag", monthlyLimit: 50, isIncome: false, systemKey: Category.customKeyPrefix + "cashy")
                oc.insert(cashy)
                CashBudgets.set(true, for: cashy, in: oc)
                CashBudgets.set(true, for: cashy, in: oc)
                try oc.save()
                check("S35 marking a budget as cash keeps one record", CashBudgets.isCash(cashy) && ((try? oc.fetch(FetchDescriptor<CashBudgetMark>())) ?? []).count == 1)
                let cashBackup = try DataBackup.decode(try DataBackup.encode(try DataBackup.make(from: oc)))
                try DataBackup.restore(cashBackup, into: oc)
                let restoredCashy = try oc.fetch(FetchDescriptor<Category>()).first { $0.systemKey == Category.customKeyPrefix + "cashy" }
                check("S35 a restore brings the cash budget mark back", restoredCashy.map { CashBudgets.isCash($0) } == true)
                if let restoredCashy { oc.delete(restoredCashy) }
                try oc.save()
                CashBudgets.removeOrphans(in: oc)
                try oc.save()
                check("S35 deleting the budget leaves no stray mark", ((try? oc.fetch(FetchDescriptor<CashBudgetMark>())) ?? []).isEmpty)
            }

            // S36: the backup copy reminder starts on, whatever an earlier build left behind, and then the person's choice stands
            do {
                let suite = "OinklyHardening-S36-\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                check("S36 a new Mac starts with the reminder on", ShadowCopyManager.reminderIsOn(in: defaults))
                defaults.set(true, forKey: "shadowCopyDontAsk")
                check("S36 after that, turning it off is kept", !ShadowCopyManager.reminderIsOn(in: defaults))
                let old = UserDefaults(suiteName: suite + "-old")!
                defer { old.removePersistentDomain(forName: suite + "-old") }
                old.set(true, forKey: "shadowCopyDontAsk")
                old.set(Date.now.addingTimeInterval(86_400), forKey: "shadowCopyAskAgainAfter")
                check("S36 an earlier build's 'don't ask' is cleared the first time", ShadowCopyManager.reminderIsOn(in: old))
                check("S36 and its wait is cleared too", old.object(forKey: "shadowCopyAskAgainAfter") == nil)
            }

            // S37: typing a budget amount in setup is read as it is typed
            check("S37 plain digits", BudgetAmountText.parse("1500") == 1500)
            check("S37 currency signs and commas are ignored", BudgetAmountText.parse("$1,500.50") == Decimal(string: "1500.5"))
            check("S37 a lone digit is read while typing", BudgetAmountText.parse("5") == 5)
            check("S37 a trailing point is read as the whole number so far", BudgetAmountText.parse("12.") == 12)
            check("S37 empty and letters are zero", BudgetAmountText.parse("") == 0 && BudgetAmountText.parse("abc") == 0)
            check("S37 a second point is ignored", BudgetAmountText.parse("1.2.3") == Decimal(string: "1.23"))
            check("S37 a comma decimal separator works where the Mac uses one", BudgetAmountText.parse("12,5", decimalSeparator: ",") == Decimal(string: "12.5"))
            check("S37 zero shows as an empty box", BudgetAmountText.shown(0, editing: true) == "" && BudgetAmountText.shown(0, editing: false) == "")
            check("S37 editing shows the plain number", BudgetAmountText.shown(1500, editing: true) == "1500")

            // S38: an overdue bill and its next date are shown apart, not as a repeat in one list
            do {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                let pc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let loan = Bill(name: "Auto Loan", amount: 400, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: -12, to: today)!, isImportant: true)
                let insurance = Bill(name: "Insurance", amount: 100, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: 4, to: today)!, isImportant: true)
                let notImportant = Bill(name: "Gym", amount: 30, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: -3, to: today)!)
                pc.insert(loan); pc.insert(insurance); pc.insert(notImportant)
                try pc.save()
                let split = Bills.prioritySplit([loan, insurance, notImportant])
                check("S38 a late bill is in the overdue part only", split.overdue.map(\.bill.name) == ["Auto Loan"] && split.overdue.allSatisfy(\.isOverdue), "\(split.overdue.map(\.bill.name))")
                check("S38 what is coming is in its own part, with the same bill's next date", split.upcoming.contains { $0.bill === loan } && split.upcoming.contains { $0.bill === insurance } && split.upcoming.allSatisfy { !$0.isOverdue }, "\(split.upcoming.map(\.bill.name))")
                check("S38 a bill that isn't important is left out", !split.overdue.contains { $0.bill === notImportant } && !split.upcoming.contains { $0.bill === notImportant })
                check("S38 paying the late date clears it from overdue", { loan.setPaid(true, on: split.overdue[0].date); return Bills.prioritySplit([loan, insurance]).overdue.isEmpty }())
            }

            // S39: ticking an entry a repeating rule made
            do {
                let rc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let income = Transaction(account: nil, date: .now, payee: "Pay", amount: 2_000)
                rc.insert(income)
                income.state = .pending
                Recurring.toggleConfirmed(income)
                check("S39 ticking a pending paycheque reconciles it", income.state == .reconciled)
                Recurring.toggleConfirmed(income)
                check("S39 ticking it again takes it back to pending", income.state == .pending)
                let rent = Transaction(account: nil, date: .now, payee: "Rent", amount: -900)
                rc.insert(rent)
                rent.state = .pending
                Recurring.toggleConfirmed(rent)
                check("S39 ticking a pending payment reconciles it too", rent.state == .reconciled)
                Recurring.toggleConfirmed(rent)
                check("S39 and ticking that again takes it back to pending", rent.state == .pending)
            }

            // S40: a bill's pending entry, ticking it off, and paying it
            do {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today)! }
                let bc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let bank = Account(name: "Bills bank", type: .checking, openingBalance: 0)
                bc.insert(bank)
                let power = Bill(name: "Power", amount: 90, frequency: .monthly, dueDate: ago(5))
                let water = Bill(name: "Water", amount: 40, frequency: .monthly, dueDate: ago(3))
                let phone = Bill(name: "Phone", amount: 60, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: 9, to: today)!)
                let gym = Bill(name: "Gym", amount: 25, frequency: .monthly, dueDate: ago(2))
                for bill in [power, water, phone, gym] { bc.insert(bill) }
                BillPaySources.set(bank, for: power, in: bc); BillPaySources.set(bank, for: water, in: bc); BillPaySources.set(bank, for: phone, in: bc)
                try bc.save()
                func entries(_ bill: Bill) -> [Transaction] { BillLink.payments(of: bill, on: bill.dueDate) }
                let made = BillEntries.run(in: bc)
                try bc.save()
                let powerEntry = entries(power).first
                check("S40 a bill with an account gets a pending entry for a due date that has come", made == 2 && powerEntry?.state == .pending && powerEntry?.amount == -90 && powerEntry?.account === bank, "made \(made)")
                check("S40 the entry is linked to that due date and the bill is still unpaid", powerEntry?.paidBill === power && !power.isPaid(on: power.dueDate))
                check("S40 a bill with no account makes none", entries(gym).isEmpty && entries(phone).isEmpty)
                check("S40 running again makes no second one", BillEntries.run(in: bc) == 0)
                BillEntries.markPaid(power, on: power.dueDate, in: bc)
                check("S40 ticking the bill reconciles its entry and marks it paid", entries(power).first?.state == .reconciled && power.isPaid(on: power.dueDate) && entries(power).count == 1)
                BillEntries.markUnpaid(power, on: power.dueDate, in: bc)
                check("S40 ticking again puts the entry back to pending", entries(power).first?.state == .pending && !power.isPaid(on: power.dueDate))
                if let waterEntry = entries(water).first { bc.delete(waterEntry) }
                try bc.save()
                check("S40 an entry that was deleted does not come back", BillEntries.run(in: bc) == 0 && entries(water).isEmpty)
                BillEntries.markPaid(phone, on: phone.dueDate, in: bc)
                check("S40 ticking a bill before its date makes an entry that is already reconciled", entries(phone).count == 1 && entries(phone)[0].state == .reconciled)
                BillEntries.markPaid(gym, on: gym.dueDate, in: bc)
                check("S40 ticking a bill with no account makes no entry", entries(gym).isEmpty && gym.isPaid(on: gym.dueDate))
                BillPayment.record(from: bank, debt: nil, bill: power, amount: 95, date: power.dueDate, state: .reconciled, in: bc)
                try bc.save()
                let afterPay = entries(power)
                check("S40 paying the bill replaces the pending entry with the real payment, reconciled", afterPay.count == 1 && afterPay[0].amount == -95 && afterPay[0].state == .reconciled && afterPay[0].isBillPayment, "\(afterPay.count)")
                BillEntries.markUnpaid(power, on: power.dueDate, in: bc)
                check("S40 unticking does not undo a real payment", entries(power).first?.state == .reconciled)
                // The account follows a rename, and goes with a backup
                let oldKey = BillPaySources.key(for: bank)
                bank.name = "Bills bank renamed"
                BillPaySources.accountChanged(from: oldKey, to: BillPaySources.key(for: bank), in: bc)
                try bc.save()
                check("S40 a renamed account keeps its bills", BillPaySources.account(for: phone, in: bc) === bank)
                let paid = try DataBackup.decode(try DataBackup.encode(try DataBackup.make(from: bc)))
                try DataBackup.restore(paid, into: bc)
                let restoredPhone = try bc.fetch(FetchDescriptor<Bill>()).first { $0.name == "Phone" }
                check("S40 a backup brings back which account a bill comes out of", restoredPhone.flatMap { BillPaySources.account(for: $0, in: bc) }?.name == "Bills bank renamed")
                check("S40 and the links to due dates", restoredPhone.map { !BillLink.payments(of: $0, on: $0.dueDate).isEmpty } == true)
                if let account = try bc.fetch(FetchDescriptor<Account>()).first(where: { $0.name == "Bills bank renamed" }) { bc.delete(account) }
                try bc.save()
                BillPaySources.removeOrphans(in: bc)
                try bc.save()
                check("S40 deleting the account leaves no stray record", ((try? bc.fetch(FetchDescriptor<BillPaySource>())) ?? []).isEmpty)
            }

            // S41: weekly budgets
            do {
                let calendar = Calendar.current
                let wc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                check("S41 a weekly amount is read as about a month: 100 a week is 433.33", BudgetPeriods.monthly(fromWeekly: 100) == Decimal(string: "433.33"))
                check("S41 and 15 a week is 65", BudgetPeriods.monthly(fromWeekly: 15) == 65)
                func month(_ m: Int, year: Int = 2026) -> Date { DateComponents(calendar: calendar, year: year, month: m, day: 10).date! }
                check("S41 100 a week is 428.57 in a 30-day month", BudgetPeriods.monthlyMaximum(weekly: 100, inMonthOf: month(4)) == Decimal(string: "428.57"))
                check("S41 and 442.86 in a 31-day month", BudgetPeriods.monthlyMaximum(weekly: 100, inMonthOf: month(10)) == Decimal(string: "442.86"))
                check("S41 and exactly 400 in a 28-day February", BudgetPeriods.monthlyMaximum(weekly: 100, inMonthOf: month(2)) == 400)
                check("S41 and 414.29 in a 29-day leap February", BudgetPeriods.monthlyMaximum(weekly: 100, inMonthOf: month(2, year: 2028)) == Decimal(string: "414.29"))
                let food = Category(name: "Weekly food", colorHex: "34C759", symbol: "cart", monthlyLimit: 0, isIncome: false, systemKey: Category.customKeyPrefix + "weekly-food")
                wc.insert(food)
                BudgetPeriods.set(amount: 100, weekly: true, for: food, in: wc)
                try wc.save()
                check("S41 a weekly budget keeps its weekly amount and a monthly equivalent", BudgetPeriods.weeklyAmount(for: food) == 100 && food.monthlyLimit == Decimal(string: "433.33"))
                BudgetPeriods.set(amount: 120, weekly: true, for: food, in: wc)
                try wc.save()
                check("S41 changing it keeps one record", ((try? wc.fetch(FetchDescriptor<BudgetPeriod>())) ?? []).count == 1 && BudgetPeriods.weeklyAmount(for: food) == 120)
                // The Month Outlook counts a weekly budget by the days of the month it is showing
                let april = MonthOutlook.build(month: month(4), bills: [], rules: [], categories: [food], monthTransactions: [],
                                               weeklyAmounts: BudgetPeriods.weeklyAmounts(in: wc), now: month(4), calendar: calendar)
                let october = MonthOutlook.build(month: month(10), bills: [], rules: [], categories: [food], monthTransactions: [],
                                                 weeklyAmounts: BudgetPeriods.weeklyAmounts(in: wc), now: month(10), calendar: calendar)
                check("S41 the Month Outlook counts a weekly budget by the month's days", april.budgets.first?.limit == BudgetPeriods.monthlyMaximum(weekly: 120, inMonthOf: month(4)) && october.budgets.first?.limit == BudgetPeriods.monthlyMaximum(weekly: 120, inMonthOf: month(10)) && april.budgets.first?.limit != october.budgets.first?.limit)
                let bank = Account(name: "Weekly bank", type: .checking, openingBalance: 0)
                wc.insert(bank)
                func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))! }
                let week = calendar.dateInterval(of: .weekOfYear, for: .now)!
                let inside = Transaction(account: bank, date: week.start.addingTimeInterval(3_600), payee: "Shop", category: food, amount: -40)
                let before = Transaction(account: bank, date: week.start.addingTimeInterval(-86_400), payee: "Shop", category: food, amount: -25)
                wc.insert(inside); wc.insert(before)
                try wc.save()
                let weekSpend = Budget.spentTable(try wc.fetch(FetchDescriptor<Transaction>()), interval: week)
                check("S41 spending is counted for just the week asked about", weekSpend[food] == 40)
                let backup = try DataBackup.decode(try DataBackup.encode(try DataBackup.make(from: wc)))
                try DataBackup.restore(backup, into: wc)
                let restored = try wc.fetch(FetchDescriptor<Category>()).first { $0.systemKey == Category.customKeyPrefix + "weekly-food" }
                check("S41 a backup brings back the weekly amount", restored.flatMap { BudgetPeriods.weeklyAmount(for: $0) } == 120 && restored?.monthlyLimit == BudgetPeriods.monthly(fromWeekly: 120))
                if let restored {
                    BudgetPeriods.set(amount: 300, weekly: false, for: restored, in: wc)
                    try wc.save()
                    check("S41 making it monthly again clears the weekly record", BudgetPeriods.weeklyAmount(for: restored) == nil && restored.monthlyLimit == 300)
                    BudgetPeriods.set(amount: 50, weekly: true, for: restored, in: wc)
                    wc.delete(restored)
                    try wc.save()
                    BudgetPeriods.removeOrphans(in: wc)
                    try wc.save()
                    check("S41 deleting the budget leaves no stray record", ((try? wc.fetch(FetchDescriptor<BudgetPeriod>())) ?? []).isEmpty)
                }
            }

            // S42: the payment method a bill is usually paid with
            do {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                let mc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let bank = Account(name: "Method bank", type: .checking, openingBalance: 0)
                let own = CustomPaymentMethod(name: "Company Card", symbol: "creditcard")
                mc.insert(bank); mc.insert(own)
                let power = Bill(name: "Power", amount: 90, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: -4, to: today)!)
                let rent = Bill(name: "Rent", amount: 800, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: -3, to: today)!)
                let net = Bill(name: "Internet", amount: 60, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: -2, to: today)!)
                for bill in [power, rent, net] { mc.insert(bill) }
                BillPaySources.set(bank, for: power, in: mc); BillPaySources.set(bank, for: rent, in: mc); BillPaySources.set(bank, for: net, in: mc)
                BillMethods.set(.type(.autoPay), for: power, in: mc)
                BillMethods.set(.custom(own), for: rent, in: mc)
                try mc.save()
                check("S42 a bill remembers its usual method", { if case .type(.autoPay)? = BillMethods.choice(for: power, in: mc) { return true } else { return false } }())
                check("S42 and one of your own methods, by name", { if case .custom(let found)? = BillMethods.choice(for: rent, in: mc) { return found === own } else { return false } }())
                check("S42 a bill with none has none", BillMethods.choice(for: net, in: mc) == nil)
                BillEntries.run(in: mc)
                try mc.save()
                func entry(_ bill: Bill) -> Transaction? { BillLink.payments(of: bill, on: bill.dueDate).first }
                check("S42 the pending entry starts with the bill's method", { if case .type(.autoPay)? = entry(power)?.paymentChoice { return true } else { return false } }())
                check("S42 and with one of your own", { if case .custom(let found)? = entry(rent)?.paymentChoice { return found === own } else { return false } }())
                check("S42 a bill with no method makes an entry with none", entry(net)?.paymentChoice == nil)
                // Choosing a method later fills it in when the bill is ticked
                BillMethods.set(.type(.check), for: net, in: mc)
                BillEntries.markPaid(net, on: net.dueDate, in: mc)
                check("S42 ticking a bill fills in the method an entry was missing", { if case .type(.check)? = entry(net)?.paymentChoice { return true } else { return false } }())
                // Changing and clearing it
                BillMethods.set(.type(.debitCard), for: power, in: mc)
                BillMethods.set(.type(.debitCard), for: power, in: mc)
                try mc.save()
                check("S42 changing it keeps one record", ((try? mc.fetch(FetchDescriptor<BillMethod>())) ?? []).filter { $0.billKey == BillMethods.key(for: power) }.count == 1)
                let backup = try DataBackup.decode(try DataBackup.encode(try DataBackup.make(from: mc)))
                try DataBackup.restore(backup, into: mc)
                let restoredPower = try mc.fetch(FetchDescriptor<Bill>()).first { $0.name == "Power" }
                check("S42 a backup brings back the method", restoredPower.flatMap { BillMethods.choice(for: $0, in: mc) } != nil && { if case .type(.debitCard)? = restoredPower.flatMap({ BillMethods.choice(for: $0, in: mc) }) { return true } else { return false } }())
                if let restoredPower { BillMethods.set(nil, for: restoredPower, in: mc) }
                try mc.save()
                check("S42 clearing it removes the record", restoredPower.map { BillMethods.choice(for: $0, in: mc) } == .some(nil))
                for bill in try mc.fetch(FetchDescriptor<Bill>()) { mc.delete(bill) }
                try mc.save()
                BillMethods.removeOrphans(in: mc)
                try mc.save()
                check("S42 deleting the bills leaves no stray record", ((try? mc.fetch(FetchDescriptor<BillMethod>())) ?? []).isEmpty)
            }

            // S43: the War Plan set against the Month Outlook
            do {
                let today = Date.now
                func line(_ id: String, _ title: String, _ amount: Decimal) -> MonthOutlook.Line {
                    MonthOutlook.Line(id: id, title: title, date: today, kind: "Bill", expected: amount, actual: nil, status: .expected)
                }
                let outlook = MonthOutlook(month: today, income: [line("i1", "Paycheque", 3000)], bills: [line("b1", "Rent", 1300), line("b2", "Power", 90)],
                                           budgets: [], otherIncome: 0, otherSpending: 0)
                let plan: [WarPlanItem] = [
                    .init(title: "paycheque", date: today, amount: 3000, isIncome: true, origin: nil),
                    .init(title: "Rent", date: today, amount: 1200, isIncome: false, origin: nil),
                    .init(title: "Concert", date: today, amount: 80, isIncome: false, origin: nil)]
                let compare = WarPlanComparison.build(items: plan, outlook: outlook)
                func row(_ title: String) -> WarPlanComparison.Row? { compare.rows.first { $0.title == title } }
                check("S43 a planned line is matched by name, whatever the case", row("paycheque")?.actual == 3000 && row("paycheque")?.difference == 0)
                check("S43 a bill that cost more shows the difference", row("Rent")?.difference == 100)
                check("S43 a planned line the outlook lacks has no outlook amount", row("Concert")?.actual == nil && row("Concert")?.difference == nil)
                check("S43 an outlook line not planned is listed", row("Power")?.planned == nil && row("Power")?.actual == 90)
                check("S43 totals compare the plan with the outlook", compare.plannedOut == 1280 && compare.actualOut == 1390 && compare.plannedExtra == 1720 && compare.actualExtra == 1610)
            }

            // S44: the earliest safe day to pull the spare money out
            do {
                let calendar = Calendar.current
                let month = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
                func day(_ d: Int) -> Date { calendar.date(byAdding: .day, value: d - 1, to: month)! }
                let events = [SafePull.Event(date: day(1), amount: 3000), SafePull.Event(date: day(5), amount: -2500),
                              SafePull.Event(date: day(15), amount: 2000), SafePull.Event(date: day(20), amount: -500)]
                let pull = SafePull(opening: 0, buffer: 100, events: events)
                check("S44 the month ends with what the lines add up to", pull.ending == 2000 && pull.spare == 1900)
                check("S44 the safe day is after the last dip below the ending balance", pull.best?.date == day(15))
                check("S44 the lowest point is the rent day", pull.lowest?.date == day(5) && pull.lowest?.balance == 500)
                let early = SafePull(opening: 0, buffer: 0, events: [.init(date: day(2), amount: 1000), .init(date: day(9), amount: -200)])
                check("S44 with no dip the first day is safe", early.best?.date == day(2))
                check("S44 nothing spare means no safe day", SafePull(opening: 0, buffer: 5000, events: events).best == nil)
                check("S44 a month with no lines has no safe day", SafePull(opening: 500, buffer: 0, events: []).best == nil)
                let sameDay = SafePull(opening: 0, buffer: 0, events: [.init(date: day(3), amount: -50), .init(date: day(3), amount: 100)])
                check("S44 money in counts before money out on the same day", sameDay.points.first?.balance == 100)
                let spread = SafePull.spread(100, over: month, calendar: calendar)
                check("S44 undated spending is spread weekly and adds back up", spread.count == 5 && spread.reduce(Decimal(0)) { $0 + $1.amount } == -100)
                check("S44 the settings text round trips", OutlookSettings.decimal(OutlookSettings.text(1234.5)) == 1234.5 && OutlookSettings.decimal("") == nil && OutlookSettings.text(0) == "")
            }

            // S45: only checking, savings and cash accounts count; and the report on what to improve
            do {
                let mc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let bank = Account(name: "S45 bank", type: .checking, openingBalance: 0)
                let card = Account(name: "S45 card", type: .creditCard, openingBalance: 0)
                let broker = Account(name: "S45 broker", type: .brokerage, openingBalance: 0)
                let cash = Account(name: "S45 cash", type: .cash, openingBalance: 0)
                let saver = Account(name: "S45 saver", type: .savings, openingBalance: 0)
                for account in [bank, card, broker, cash, saver] { mc.insert(account) }
                check("S45 checking, savings and cash can count", [bank, cash, saver].allSatisfy(MonthOutlook.isEligible))
                check("S45 cards and investments never count", [card, broker].allSatisfy { !MonthOutlook.isEligible($0) })

                let today = Date.now
                func line(_ title: String, _ amount: Decimal, _ status: MonthOutlook.Status = .expected) -> MonthOutlook.Line {
                    MonthOutlook.Line(id: title, title: title, date: today, kind: "Bill", expected: amount, actual: nil, status: status)
                }
                let late = MonthOutlook(month: today, income: [line("Pay", 1000)], bills: [line("Rent", 1500, .overdue)], budgets: [], otherIncome: 0, otherSpending: 0)
                let pull = SafePull(opening: 0, buffer: 100, events: SafePull.events(outlook: late))
                let advice = OutlookAdvice.make(outlook: late, compare: nil, plannedPull: nil, actualPull: pull, buffer: 100, startingSet: false)
                check("S45 an overdue bill is the first thing it says", advice.first?.id == "overdue" && advice.first?.level == .problem)
                check("S45 a month that ends short says so", advice.contains { $0.id == "short" })
                check("S45 with no plan it suggests making one", advice.contains { $0.id == "no-plan" })
                check("S45 with no starting amount it suggests setting one", advice.contains { $0.id == "no-start" })

                let fine = MonthOutlook(month: today, income: [line("Pay", 3000, .received)], bills: [line("Rent", 1000, .paid)], budgets: [], otherIncome: 0, otherSpending: 0)
                let fineEvents = SafePull.events(outlook: fine)
                let fineAdvice = OutlookAdvice.make(outlook: fine, compare: WarPlanComparison.build(items: [
                    WarPlanItem(title: "Pay", date: today, amount: 3000, isIncome: true, origin: nil),
                    WarPlanItem(title: "Rent", date: today, amount: 1000, isIncome: false, origin: nil)], outlook: fine),
                    plannedPull: SafePull(opening: 500, buffer: 100, events: fineEvents), actualPull: SafePull(opening: 500, buffer: 100, events: fineEvents),
                    buffer: 100, startingSet: true)
                check("S45 a month on plan and above the buffer is on track", fineAdvice.first?.id == "on-track" && fineAdvice.first?.level == .good)
                check("S45 the report is never longer than asked", OutlookAdvice.make(outlook: late, compare: nil, plannedPull: nil, actualPull: pull, buffer: 0, startingSet: false, limit: 2).count == 2)
            }

            // S46: lines know which account they go through, for pulling a plan in by account
            do {
                let calendar = Calendar.current
                let month = MonthFilter.start(of: .now)
                let mc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let bank = Account(name: "S46 bank", type: .checking, openingBalance: 0)
                let saver = Account(name: "S46 saver", type: .savings, openingBalance: 0)
                mc.insert(bank); mc.insert(saver)
                let power = Bill(name: "Power", amount: 90, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: 3, to: month)!)
                let water = Bill(name: "Water", amount: 40, frequency: .monthly, dueDate: calendar.date(byAdding: .day, value: 4, to: month)!)
                mc.insert(power); mc.insert(water)
                try mc.save()
                let payers = [BillPaySources.key(for: power): MonthOutlook.accountKey(bank)]
                let outlook = MonthOutlook.build(month: month, bills: [power, water], rules: [], categories: [], monthTransactions: [], billPayerKeys: payers)
                check("S46 a bill set to come out of an account carries that account", outlook.bills.first { $0.title == "Power" }?.accountKey == MonthOutlook.accountKey(bank))
                check("S46 a bill with no account carries none", outlook.bills.first { $0.title == "Water" }?.accountKey == nil)
            }

            // S47: projections for the quarter, the year and the long run
            do {
                let calendar = Calendar.current
                let thisMonth = MonthFilter.start(of: .now)
                let history: [(date: Date, income: Double, spending: Double)] = (0..<12).map { index in
                    let date = calendar.date(byAdding: .month, value: index - 11, to: thisMonth)!
                    // This month, the last, is part way through and must not count.
                    return index == 11 ? (date, 100, 900) : (date, 3000, 2200)
                }
                let average = Projection.averages(history: history)
                check("S47 the average is of the last three full months and leaves this month out", average.income == 3000 && average.spending == 2200)
                let quarter = Projection.make(history: history, netWorthNow: 10_000, bills: [], months: 3)
                check("S47 a quarter is three months at the average", quarter.months.count == 3 && quarter.totalIncome == 9000 && quarter.totalSpending == 6600 && quarter.totalSaved == 2400)
                check("S47 the first projected month is next month", quarter.months.first?.date == calendar.date(byAdding: .month, value: 1, to: thisMonth))
                check("S47 net worth starts where it is now and adds what is kept", quarter.netWorth.count == 4 && quarter.netWorth.first?.value == 10_000 && quarter.netWorth.last?.value == 12_400)
                check("S47 the savings rate is what is kept of what comes in", abs((quarter.savingsRate ?? 0) - 26.666) < 0.01)
                let year = Projection.make(history: history, netWorthNow: 0, bills: [], months: 12)
                check("S47 a year is twelve months", year.months.count == 12 && year.totalSaved == 9600)
                // A fixed day part way through May, so the month in progress is half done.
                let may = DateComponents(year: 2026, month: 5, day: 16, hour: 12)
                let now = calendar.date(from: may)!
                let mayStart = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
                let fixed: [(date: Date, income: Double, spending: Double)] = (0..<12).map { index in
                    let date = calendar.date(byAdding: .month, value: index - 11, to: mayStart)!
                    return index == 11 ? (date, 1000, 500) : (date, 3000, 2200)
                }
                let worth: [(date: Date, value: Double)] = (1...4).map { (calendar.date(from: DateComponents(year: 2026, month: $0, day: 1))!, Double($0) * 1000) }
                let year2026 = Projection.calendarYear(of: now)
                let yearPlan = Projection.period(history: fixed, netWorthHistory: worth, netWorthNow: 4500, bills: [], from: year2026.start, through: year2026.end, now: now)
                check("S47 a calendar year is January to December", yearPlan.months.count == 12 && yearPlan.months.first?.kind == .actual && yearPlan.months[4].kind == .current && yearPlan.months[5].kind == .projected)
                check("S47 the months that have happened are as they were", yearPlan.months[0].income == 3000 && yearPlan.months[0].spending == 2200 && yearPlan.months[3].incomeSoFar == 3000)
                check("S47 this month is what has happened plus the rest at the average", yearPlan.months[4].incomeSoFar == 1000 && abs(yearPlan.months[4].income - 2500) < 0.5 && abs(yearPlan.months[4].spending - 1600) < 0.5)
                check("S47 the year's income adds up", abs(yearPlan.totalIncome - 35_500) < 0.5)
                check("S47 net worth is what was, today, then where it is heading", yearPlan.netWorth.filter { !$0.projected }.count == 5 && yearPlan.netWorth.filter { !$0.projected }.last?.value == 4500
                      && abs((yearPlan.netWorth.last?.value ?? 0) - 10_500) < 0.5)
                let q = Projection.calendarQuarter(of: now)
                let quarter2 = Projection.period(history: fixed, netWorthHistory: worth, netWorthNow: 4500, bills: [], from: q.start, through: q.end, now: now)
                check("S47 the quarter is April to June", calendar.component(.month, from: q.start) == 4 && calendar.component(.month, from: q.end) == 6 && quarter2.months.count == 3)
                let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))!
                let long = Projection.years(10, monthlyIncome: average.income, monthlySpending: average.spending, netWorthNow: 5_000, now: december)
                check("S47 the long range starts with next year and runs ten calendar years", long.count == 10 && long.first?.year == 2027 && long.last?.year == 2036)
                check("S47 and each year adds a year's saving to what is kept", long[0].keptInYear == 9600 && abs(long[0].netWorth - (5_000 + 9600)) < 20 && abs(long[9].netWorth - (5_000 + 9600 * 10)) < 20)
                check("S47 with no history there is nothing to project", !Projection.make(history: [], netWorthNow: 0, bills: [], months: 3).hasData)
            }

            // S48: an extra payment toward a loan leaves its bill alone
            do {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                let ec = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                // Added up straight from the transactions, so the test doesn't depend on the balance cache refreshing.
                func owed(_ account: Account) -> Decimal { account.transactions.live.reduce(account.openingBalance) { $0 + $1.amount } }
                let bank = Account(name: "S48 bank", type: .checking, openingBalance: 1_000)
                let loan = Account(name: "S48 loan", type: .loan, openingBalance: -5_000)
                ec.insert(bank); ec.insert(loan)
                let bill = Bill(name: "S48 loan payment", amount: 300, frequency: .monthly, dueDate: today)
                bill.loan = loan
                ec.insert(bill)
                try ec.save()
                let extra = BillPayment.record(from: bank, debt: loan, bill: bill, amount: 200, date: today, memo: "Extra Principal Payment", isExtra: true, in: ec)
                try ec.save()
                check("S48 an extra payment comes out of the paying account", owed(bank) == 800)
                check("S48 and goes wholly toward the balance owed", owed(loan) == -4_800)
                check("S48 it is not linked to the bill", extra?.paidBill == nil && extra?.paidDueDate == nil && extra?.isBillPayment == false)
                check("S48 the bill is not marked paid", bill.isPaid(on: today, calendar: calendar) == false)
                check("S48 it is a transfer, so it is neither income nor spending", extra?.isTransfer == true)
                check("S48 a plain bill has no balance to put extra toward", BillPayment.record(from: bank, debt: nil, bill: Bill(name: "S48 power", amount: 50, frequency: .monthly, dueDate: today), amount: 50, date: today, isExtra: true, in: ec) == nil)
                let regular = BillPayment.record(from: bank, debt: loan, bill: bill, amount: 300, date: today, in: ec)
                try ec.save()
                check("S48 a regular payment is linked to the bill", regular?.paidBill === bill, "linked \(regular?.paidBill?.name ?? "nil")")
                check("S48 and ticks it off", bill.isPaid(on: today, calendar: calendar))
                check("S48 and takes its amount off the balance too", owed(loan) == -4_500, "balance \(owed(loan))")
            }

            // S49: narrowing a register to some statuses, or to with or without a receipt
            do {
                let fc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                func make(_ payee: String, _ state: ReconcileState, receipt: Bool) -> Transaction {
                    let t = Transaction(account: nil, date: .now, payee: payee, amount: -10)
                    fc.insert(t)
                    t.state = state
                    t.receiptData = receipt ? Data([1, 2, 3]) : nil
                    return t
                }
                let a1 = make("A", .unreconciled, receipt: true), a2 = make("B", .unreconciled, receipt: false)
                let a3 = make("C", .pending, receipt: true), a4 = make("D", .reconciled, receipt: false)
                let all = [a1, a2, a3, a4]
                func names(_ f: RegisterFilter) -> String { all.filter(f.matches).map(\.payee).joined() }
                check("S49 with nothing ticked everything shows", names(RegisterFilter()) == "ABCD" && !RegisterFilter().isActive)
                check("S49 ticking Unreconciled shows only those", names(RegisterFilter(states: [.unreconciled])) == "AB")
                check("S49 ticking two statuses shows both", names(RegisterFilter(states: [.unreconciled, .pending])) == "ABC")
                check("S49 only reconciled", names(RegisterFilter(states: [.reconciled])) == "D")
                check("S49 with a receipt", names(RegisterFilter(withReceipt: true)) == "AC")
                check("S49 without a receipt", names(RegisterFilter(withoutReceipt: true)) == "BD")
                check("S49 both receipt ticks narrow nothing", names(RegisterFilter(withReceipt: true, withoutReceipt: true)) == "ABCD" && !RegisterFilter(withReceipt: true, withoutReceipt: true).isActive)
                check("S49 a status and a receipt together", names(RegisterFilter(states: [.unreconciled], withoutReceipt: true)) == "B")
                check("S49 the page says what it is showing", RegisterFilter(states: [.pending, .unreconciled], withReceipt: true).summary == "Pending, Unreconciled · With Receipt" && RegisterFilter().summary == "")
            }

            // S50: a credit card never owes more than its limit, though owing exactly the limit is allowed
            do {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                let gc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let card = Account(name: "S50 card", type: .creditCard, openingBalance: -900)
                card.creditLimit = 1_000
                let bank = Account(name: "S50 bank", type: .checking, openingBalance: 5_000)
                gc.insert(card); gc.insert(bank)
                try gc.save()
                check("S50 a charge up to the limit is allowed", card.wouldExceedLimit(adding: -100) == false)
                check("S50 a charge past the limit is refused", card.wouldExceedLimit(adding: -100.01) == true)
                check("S50 a payment is never refused", card.wouldExceedLimit(adding: 500) == false)
                check("S50 a bank account has no limit", bank.wouldExceedLimit(adding: -100_000) == false)
                check("S50 paying a bill from a card past its limit is refused", BillPayment.record(from: card, debt: nil, bill: Bill(name: "S50 power", amount: 200, frequency: .monthly, dueDate: today), amount: 200, date: today, in: gc) == nil)
                check("S50 and within it is recorded", BillPayment.record(from: card, debt: nil, bill: Bill(name: "S50 water", amount: 100, frequency: .monthly, dueDate: today), amount: 100, date: today, in: gc) != nil)
                let rule = RecurringTransaction(payee: "S50 sub", account: card, category: nil, amount: -50, frequency: .monthly, startDate: today)
                gc.insert(rule)
                check("S50 a repeating charge past the limit makes no entry", Recurring.makeEntry(for: rule, on: today, in: gc) == nil)
            }

            // S51: a budget of your own can be put in one of the budget groups
            do {
                let hc = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                Category.ensureSystemCategories(in: hc)
                let own = Category(name: "S51 own", colorHex: "007AFF", symbol: "tag", monthlyLimit: 50, systemKey: Category.customKeyPrefix + UUID().uuidString)
                let ownIncome = Category(name: "S51 income", colorHex: "34C759", symbol: "tag", monthlyLimit: 0, isIncome: true, systemKey: Category.customKeyPrefix + UUID().uuidString)
                hc.insert(own); hc.insert(ownIncome)
                try hc.save()
                let groceries = ((try? hc.fetch(FetchDescriptor<Category>())) ?? []).first { $0.systemKey == "groceries" }!
                let rent = ((try? hc.fetch(FetchDescriptor<Category>())) ?? []).first { $0.systemKey == "housing" }!
                let pay = ((try? hc.fetch(FetchDescriptor<Category>())) ?? []).first { $0.systemKey == "paycheck" }!
                check("S51 built-in categories are in their groups", CategoryGroup.of(groceries) == .food && CategoryGroup.of(rent) == .housing && CategoryGroup.of(pay) == .income)
                check("S51 your own with no pick is Custom", CategoryGroup.of(own, picked: CashBudgets.groups(in: hc)) == .custom)
                CashBudgets.setGroup(.food, for: own, in: hc)
                try hc.save()
                check("S51 your own goes where you put it", CategoryGroup.of(own, picked: CashBudgets.groups(in: hc)) == .food)
                CashBudgets.setGroup(.giving, for: own, in: hc)
                try hc.save()
                check("S51 changing it keeps one record", CategoryGroup.of(own, picked: CashBudgets.groups(in: hc)) == .giving && ((try? hc.fetch(FetchDescriptor<CashBudgetMark>())) ?? []).count == 1)
                check("S51 the pick is not a cash budget", !CashBudgets.isCash(own))
                CashBudgets.removeOrphans(in: hc)
                check("S51 the pick survives the tidy-up", CategoryGroup.of(own, picked: CashBudgets.groups(in: hc)) == .giving)
                CashBudgets.setGroup(.custom, for: own, in: hc)
                try hc.save()
                check("S51 choosing Custom takes the pick away", CategoryGroup.of(own, picked: CashBudgets.groups(in: hc)) == .custom && ((try? hc.fetch(FetchDescriptor<CashBudgetMark>())) ?? []).isEmpty)
                CashBudgets.setGroup(.food, for: own, in: hc)
                hc.delete(own)
                try hc.save()
                CashBudgets.removeOrphans(in: hc)
                check("S51 deleting the budget leaves no stray pick", ((try? hc.fetch(FetchDescriptor<CashBudgetMark>())) ?? []).isEmpty)
                check("S51 your own income stays with Income", CategoryGroup.of(ownIncome, picked: ["x": .food]) == .income)
            }

            // S52: erasing all data also erases the War Plans and the Outlook's amounts, which are kept in preferences
            do {
                let suiteName = "OinklyHardening-\(UUID().uuidString)"
                let suite = UserDefaults(suiteName: suiteName)!
                defer { suite.removePersistentDomain(forName: suiteName) }
                let plan = WarPlanData(items: [WarPlanItem(title: "S52 rent", date: .now, amount: 900, isIncome: false, origin: nil)])
                plan.save(for: .now, defaults: suite)
                plan.save(for: Calendar.current.date(byAdding: .month, value: 1, to: .now)!, defaults: suite)
                suite.set(250.0, forKey: OutlookSettings.bufferKey)
                suite.set("Everyday Checking", forKey: OutlookSettings.startAccountKey)
                suite.set("a|b", forKey: MonthOutlook.excludedKey)
                suite.set("a|b", forKey: TransactionsSettings.accountsKey)
                suite.set(12.0, forKey: OutlookSettings.monthKey)
                check("S52 the plans are there before the erase", !WarPlanData.load(for: .now, defaults: suite).isEmpty)
                OutlookSettings.forgetData(defaults: suite)
                check("S52 every month's War Plan is gone", WarPlanData.load(for: .now, defaults: suite).isEmpty && WarPlanData.load(for: Calendar.current.date(byAdding: .month, value: 1, to: .now)!, defaults: suite).isEmpty)
                check("S52 the buffer, the starting account and the chosen accounts are gone", suite.object(forKey: OutlookSettings.bufferKey) == nil && suite.object(forKey: OutlookSettings.startAccountKey) == nil && suite.object(forKey: MonthOutlook.excludedKey) == nil && suite.object(forKey: TransactionsSettings.accountsKey) == nil)
                check("S52 the month being shown is only a view and stays", suite.object(forKey: OutlookSettings.monthKey) as? Double == 12.0)
            }

            // S53: a bill or repeating rule can have an icon of its own
            do {
                let ic = ModelContext(try ModelContainer(for: Schema(versionedSchema: OinklyBudgetSchemaV9.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
                let bill = Bill(name: "S53 bill", amount: 10, frequency: .monthly, dueDate: .now)
                ic.insert(bill)
                try ic.save()
                let owner = ItemIcons.key(for: bill)
                check("S53 a bill starts with no icon of its own", ItemIcons.symbol(of: owner, in: ic) == nil)
                ItemIcons.set("bolt", owner: owner, in: ic)
                try ic.save()
                check("S53 the icon is kept", ItemIcons.symbol(of: owner, in: ic) == "bolt")
                ItemIcons.set("car", owner: owner, in: ic)
                try ic.save()
                check("S53 changing it keeps one", ItemIcons.symbol(of: owner, in: ic) == "car" && ((try? ic.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).count == 1)
                ArtworkChoices.removeOrphans(in: ic)
                ItemIcons.removeOrphans(in: ic)
                check("S53 the tidy-ups keep it while the bill is there", ItemIcons.symbol(of: owner, in: ic) == "car")
                ItemIcons.set(nil, owner: owner, in: ic)
                try ic.save()
                check("S53 choosing Automatic takes it away", ItemIcons.symbol(of: owner, in: ic) == nil)
                ItemIcons.set("house", owner: owner, in: ic)
                ic.delete(bill)
                try ic.save()
                ItemIcons.removeOrphans(in: ic)
                check("S53 deleting the bill leaves no stray icon", ((try? ic.fetch(FetchDescriptor<ArtworkChoice>())) ?? []).isEmpty)
            }
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
