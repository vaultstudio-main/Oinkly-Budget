import AppleArchive
import CommonCrypto
import CryptoKit
import Foundation
import System

/// How the encrypted data file is protected. A random **data key** encrypts the data. The data key is never stored in
/// the clear: it is locked up in "key slots", one opened by the person's passphrase and one by a recovery key. Either one
/// opens the data, and changing the passphrase only rewrites the slots, never the data. Everything here is Apple's own:
/// CryptoKit for the key slots, the system's PBKDF2 to stretch a passphrase, and Apple Archive (AES-CTR with an HMAC,
/// compressed) to seal the data. Nothing third-party.
///
/// The encrypted file holds a complete copy of the data folder: the database file and the receipts and photos beside it.
/// The key slots live in a small separate file, so they can be replaced without touching the data.
nonisolated struct VaultKeyFile: Codable, Equatable, Sendable {
    struct Slot: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case passphrase, recovery }
        var kind: Kind
        var salt: Data
        var iterations: Int
        /// The data key, sealed with AES-GCM under a key made from the passphrase (or recovery key) and the salt.
        var sealed: Data
    }

    var formatVersion = 1
    /// Names this vault on this Mac, such as for the remembered key in the Keychain.
    var vaultID = UUID().uuidString
    var createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    var slots: [Slot]
}

nonisolated enum VaultError: LocalizedError {
    case wrongSecret
    case notAVault
    case newerFormat
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .wrongSecret: "That passphrase or recovery key doesn't open this data."
        case .notAVault: "This file isn't Oinkly Budget encrypted data."
        case .newerFormat: "This data was saved by a newer version of Oinkly Budget. Update the app and try again."
        case .failed(let why): why
        }
    }
}

nonisolated enum VaultCrypto {
    static let passphraseIterations = 600_000
    static let recoveryIterations = 100_000
    static let fileName = "OinklyBudget.vault"
    static let keysName = "OinklyBudget.vaultkeys"

    // MARK: Keys

    /// A passphrase or recovery key becomes an AES key by stretching it with PBKDF2-HMAC-SHA256, which makes every
    /// guess slow for someone trying them one after another.
    static func stretch(_ secret: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let password = Array(secret.utf8)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.map { Int8(bitPattern: $0) }, password.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &derived, derived.count)
        }
        guard status == kCCSuccess else { throw VaultError.failed("The key couldn't be made from the passphrase.") }
        return SymmetricKey(data: derived)
    }

    private static func makeSlot(_ kind: VaultKeyFile.Slot.Kind, secret: String, dataKey: SymmetricKey) throws -> VaultKeyFile.Slot {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let iterations = kind == .passphrase ? passphraseIterations : recoveryIterations
        let wrapKey = try stretch(secret, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(dataKey.withUnsafeBytes { Data($0) }, using: wrapKey)
        guard let combined = box.combined else { throw VaultError.failed("The key couldn't be sealed.") }
        return VaultKeyFile.Slot(kind: kind, salt: salt, iterations: iterations, sealed: combined)
    }

    /// A readable recovery key: 32 letters and numbers in groups of four, with no letters that look like others.
    static func newRecoveryKey() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let characters = (0..<32).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] }
        return stride(from: 0, to: 32, by: 4).map { String(characters[$0..<$0 + 4]) }.joined(separator: "-")
    }

    /// Recovery keys are typed from paper, so spacing, dashes and lower case don't matter.
    static func normalizedRecoveryKey(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// A new vault: a fresh data key with a passphrase slot and a recovery slot.
    static func create(passphrase: String) throws -> (keyFile: VaultKeyFile, dataKey: SymmetricKey, recoveryKey: String) {
        let dataKey = SymmetricKey(size: .bits256)
        let recovery = newRecoveryKey()
        let keyFile = VaultKeyFile(slots: [
            try makeSlot(.passphrase, secret: passphrase, dataKey: dataKey),
            try makeSlot(.recovery, secret: normalizedRecoveryKey(recovery), dataKey: dataKey),
        ])
        return (keyFile, dataKey, recovery)
    }

    /// Opens the data key with a passphrase, or with a recovery key.
    static func unlock(_ keyFile: VaultKeyFile, secret: String) throws -> SymmetricKey {
        if keyFile.formatVersion > 1 { throw VaultError.newerFormat }
        let recovery = normalizedRecoveryKey(secret)
        for slot in keyFile.slots {
            let attempt = slot.kind == .passphrase ? secret : recovery
            guard let wrapKey = try? stretch(attempt, salt: slot.salt, iterations: slot.iterations),
                  let box = try? AES.GCM.SealedBox(combined: slot.sealed),
                  let plain = try? AES.GCM.open(box, using: wrapKey) else { continue }
            return SymmetricKey(data: plain)
        }
        throw VaultError.wrongSecret
    }

    /// The same data key under a new passphrase. The data itself is not touched, so this is instant.
    static func changingPassphrase(_ keyFile: VaultKeyFile, dataKey: SymmetricKey, to passphrase: String) throws -> VaultKeyFile {
        var updated = keyFile
        updated.slots.removeAll { $0.kind == .passphrase }
        updated.slots.insert(try makeSlot(.passphrase, secret: passphrase, dataKey: dataKey), at: 0)
        return updated
    }

    /// A new recovery key. The old one stops working.
    static func replacingRecoveryKey(_ keyFile: VaultKeyFile, dataKey: SymmetricKey) throws -> (keyFile: VaultKeyFile, recoveryKey: String) {
        let recovery = newRecoveryKey()
        var updated = keyFile
        updated.slots.removeAll { $0.kind == .recovery }
        updated.slots.append(try makeSlot(.recovery, secret: normalizedRecoveryKey(recovery), dataKey: dataKey))
        return (updated, recovery)
    }

    // MARK: Key file

    static func read(keysAt url: URL) throws -> VaultKeyFile {
        guard let data = try? Data(contentsOf: url) else { throw VaultError.notAVault }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(VaultKeyFile.self, from: data) else { throw VaultError.notAVault }
        return file
    }

    static func write(_ keyFile: VaultKeyFile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(keyFile).write(to: url, options: .atomic)
    }

    // MARK: Sealing a folder

    private static let fields = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,LNK,MOD,FLG")!

    /// Writes everything in `directory` as one encrypted, compressed file. Written beside the destination and then
    /// moved into place, so a failure leaves the old file as it was.
    ///
    /// `verify` is called with the finished temporary file before it replaces anything. Throwing from it stops the replace.
    static func seal(directory: URL, to destination: URL, key: SymmetricKey, verify: ((URL) throws -> Void)? = nil) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let context = ArchiveEncryptionContext(profile: .hkdf_sha256_aesctr_hmac__symmetric__none, compressionAlgorithm: .lzfse)
        try context.setSymmetricKey(key)
        guard let file = ArchiveByteStream.fileStream(path: FilePath(temporary.path), mode: .writeOnly,
                                                      options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o600)),
              let encrypted = ArchiveByteStream.encryptionStream(writingTo: file, encryptionContext: context),
              let encoder = ArchiveStream.encodeStream(writingTo: encrypted) else {
            throw VaultError.failed("The encrypted file couldn't be started.")
        }
        do {
            try encoder.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: fields)
            try encoder.close()
            try encrypted.close()
            try file.close()
        } catch {
            try? encoder.close(); try? encrypted.close(); try? file.close()
            throw VaultError.failed("The data couldn't be encrypted: \(error.localizedDescription)")
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try verify?(temporary)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    /// Decrypts a sealed file into `directory`, which should be empty. A wrong key or damaged file throws.
    static func open(_ vault: URL, into directory: URL, key: SymmetricKey) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let file = ArchiveByteStream.fileStream(path: FilePath(vault.path), mode: .readOnly, options: [], permissions: FilePermissions(rawValue: 0o600)) else {
            throw VaultError.notAVault
        }
        defer { try? file.close() }
        guard let context = ArchiveEncryptionContext(from: file) else { throw VaultError.notAVault }
        try context.setSymmetricKey(key)
        guard let decrypted = ArchiveByteStream.decryptionStream(readingFrom: file, encryptionContext: context),
              let decoder = ArchiveStream.decodeStream(readingFrom: decrypted),
              let extractor = ArchiveStream.extractStream(extractingTo: FilePath(directory.path), flags: [.ignoreOperationNotPermitted]) else {
            throw VaultError.notAVault
        }
        defer { try? extractor.close(); try? decoder.close(); try? decrypted.close() }
        do {
            _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw VaultError.failed("The encrypted data couldn't be read. It may be damaged. (\(error.localizedDescription))")
        }
    }
}
