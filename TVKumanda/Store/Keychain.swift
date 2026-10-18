import Foundation
import Security

/// The pairing secret lives in the Keychain, this device only.
enum Keychain {
    private static let service = "com.sametdemirel.tvkumanda"
    private static let account = "paired-tv"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> TVCredentials? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TVCredentials.self, from: data)
    }

    static func save(_ credentials: TVCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        delete()
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}
