#if DEBUG
import Foundation
import CryptoKit

/// `-sharedEncryptionSelfTest` runs the shared folder's save, open and encrypt steps on a throwaway folder, using a copy
/// of this Mac's own data, then quits. It never touches /Users/Shared/OinklyBudget or the app's real data. Debug only.
enum SharedEncryptionSelfTest {
    static func runIfRequested(localStore: URL) {
        guard CommandLine.arguments.contains("-sharedEncryptionSelfTest") else { return }
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            NSLog("SELFTEST: \(ok ? "PASS" : "FAIL") \(name) \(detail)")
            if !ok { failures += 1 }
        }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("OinklySharedSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let source = try StoreFiles.snapshot(of: localStore, into: root.appendingPathComponent("source"))
            let sourceCounts = try SQLiteStore.counts(of: source)
            NSLog("SELFTEST: source counts \(sourceCounts.values.reduce(0, +)) rows in \(sourceCounts.count) tables")
            let folder = SharedDataFolder(url: root.appendingPathComponent("shared", isDirectory: true))

            try folder.createStore(from: source, by: "Tester", appVersion: "1.0")
            check("plain create", folder.hasStore && !folder.hasVault && folder.readInfo()?.revision == 1 && folder.readInfo()?.encrypted == false)

            let work1 = root.appendingPathComponent("work1/OinklyBudget.store")
            try folder.checkOut(to: work1)
            check("plain check out", try SQLiteStore.counts(of: work1) == sourceCounts)

            // Turn encryption on
            let made = try VaultCrypto.create(passphrase: "correct horse battery")
            let on = SharedSeal(key: made.dataKey, keyFile: made.keyFile)
            let info2 = try folder.checkIn(from: work1, baseRevision: 1, by: "Tester", appVersion: "1.0", seal: on)
            check("encrypt on", folder.hasVault && !folder.hasStore && info2.encrypted && info2.revision == 2 && manager.fileExists(atPath: folder.keysURL.path))
            check("no readable data left", !manager.fileExists(atPath: folder.storeURL.path) && !manager.fileExists(atPath: StoreFiles.supportURL(for: folder.storeURL).path))
            check("encrypted file is not a database", (try? Data(contentsOf: folder.vaultURL).prefix(16)).map { !$0.starts(with: Data("SQLite format 3".utf8)) } ?? false)

            // Another login opens it with the passphrase
            let keyFile = try VaultCrypto.read(keysAt: folder.keysURL)
            let key = try VaultCrypto.unlock(keyFile, secret: "correct horse battery")
            let work2 = root.appendingPathComponent("work2/OinklyBudget.store")
            try folder.checkOut(to: work2, key: key)
            check("encrypted check out", try SQLiteStore.counts(of: work2) == sourceCounts)
            check("wrong passphrase refused", (try? VaultCrypto.unlock(keyFile, secret: "wrong")) == nil)
            check("recovery key opens", (try? VaultCrypto.unlock(keyFile, secret: made.recoveryKey)) != nil)

            // Routine encrypted save, then a stale one
            let info3 = try folder.checkIn(from: work2, baseRevision: 2, by: "Tester", appVersion: "1.0", seal: SharedSeal(key: key, keyFile: nil))
            check("encrypted save", info3.revision == 3 && info3.encrypted && manager.fileExists(atPath: folder.previousVaultURL.path))
            var refused = false
            do { _ = try folder.checkIn(from: work2, baseRevision: 2, by: "Tester", appVersion: "1.0", seal: SharedSeal(key: key, keyFile: nil)) } catch SharedDataError.changedMeanwhile { refused = true } catch {}
            check("stale save refused", refused)

            // Recovered copy stays encrypted
            let recovered = try folder.saveRecoveredCopy(from: work2, seal: SharedSeal(key: key, keyFile: nil))
            let reopen = root.appendingPathComponent("recovered", isDirectory: true)
            try VaultCrypto.open(recovered, into: reopen, key: key)
            let reopenedCounts = try SQLiteStore.counts(of: reopen.appendingPathComponent("OinklyBudget.store"))
            check("recovered copy encrypted and opens", recovered.pathExtension == "vault" && reopenedCounts == sourceCounts)

            // Turn encryption off
            let info4 = try folder.checkIn(from: work2, baseRevision: 3, by: "Tester", appVersion: "1.0", seal: nil)
            check("encrypt off", folder.hasStore && !folder.hasVault && !info4.encrypted && info4.revision == 4
                  && !manager.fileExists(atPath: folder.keysURL.path) && !manager.fileExists(atPath: folder.previousVaultURL.path))
            let work3 = root.appendingPathComponent("work3/OinklyBudget.store")
            try folder.checkOut(to: work3)
            check("plain again", try SQLiteStore.counts(of: work3) == sourceCounts)

            // Share encrypted from the start (this Mac was encrypted before sharing)
            let fresh = SharedDataFolder(url: root.appendingPathComponent("shared2", isDirectory: true))
            try fresh.createStore(from: source, by: "Tester", appVersion: "1.0", seal: SharedSeal(key: key, keyFile: keyFile))
            check("create encrypted", fresh.hasVault && !fresh.hasStore && fresh.isEncrypted && fresh.readInfo()?.encrypted == true)
            let work4 = root.appendingPathComponent("work4/OinklyBudget.store")
            try fresh.checkOut(to: work4, key: key)
            check("opens with the same key", try SQLiteStore.counts(of: work4) == sourceCounts)
        } catch {
            check("no error", false, error.localizedDescription)
        }
        NSLog("SELFTEST: \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
