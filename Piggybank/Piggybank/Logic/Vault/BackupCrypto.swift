import CommonCrypto
import CryptoKit
import Foundation

/// Encrypted `.pig` backups. A backup is the same JSON as ever, sealed with AES-GCM under a key made from a passphrase.
/// It carries its own salt, so a backup opens on any Mac with the passphrase, whether or not that Mac uses encrypted
/// data. Plain backups still open as they always did.
nonisolated enum BackupCrypto {
    private static let magic = Data("OBPIG1\n".utf8)

    static func isEncrypted(_ data: Data) -> Bool { data.starts(with: magic) }

    static func encrypt(_ plain: Data, passphrase: String) throws -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let iterations = VaultCrypto.passphraseIterations
        let key = try VaultCrypto.stretch(passphrase, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else { throw VaultError.failed("The backup couldn't be sealed.") }
        var out = magic
        out.append(salt)
        withUnsafeBytes(of: UInt32(iterations).bigEndian) { out.append(contentsOf: $0) }
        out.append(combined)
        return out
    }

    static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        guard isEncrypted(data), data.count > magic.count + 20 else { throw VaultError.notAVault }
        let body = data.dropFirst(magic.count)
        let salt = Data(body.prefix(16))
        let iterations = Int(UInt32(bigEndian: body.dropFirst(16).prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
        let sealed = Data(body.dropFirst(20))
        guard iterations >= 1000, iterations <= 10_000_000 else { throw VaultError.notAVault }
        let key = try VaultCrypto.stretch(passphrase, salt: salt, iterations: iterations)
        guard let box = try? AES.GCM.SealedBox(combined: sealed), let plain = try? AES.GCM.open(box, using: key) else {
            throw VaultError.wrongSecret
        }
        return plain
    }
}
