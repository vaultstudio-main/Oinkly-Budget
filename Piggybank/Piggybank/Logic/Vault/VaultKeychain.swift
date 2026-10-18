import Foundation
import Security

/// The data key, remembered for this Mac login only when the person asks. It is kept in the system Keychain, never in
/// a file, and never synced to other devices. Another Mac login has its own Keychain and enters the passphrase once.
nonisolated enum VaultKeychain {
    private static let service = "dev.vaultstudio.oinklybudget.vault"

    private static func query(_ vaultID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: vaultID,
         kSecAttrSynchronizable as String: false]
    }

    static func save(_ key: Data, vaultID: String) {
        delete(vaultID: vaultID)
        var item = query(vaultID)
        item[kSecValueData as String] = key
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(vaultID: String) -> Data? {
        var request = query(vaultID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(vaultID: String) {
        SecItemDelete(query(vaultID) as CFDictionary)
    }
}
