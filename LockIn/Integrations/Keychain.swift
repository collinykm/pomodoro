import Foundation
import Security

/// Minimal Keychain wrapper for OAuth tokens.
///
/// Uses the data-protection keychain (`kSecUseDataProtectionKeychain`). Items there are tied to
/// the app's identity (bundle id + team) instead of the exact code signature of one build, so
/// rebuilding or reinstalling the app does not trigger the "LockIn wants to use your confidential
/// information" password prompt the legacy file-based keychain shows.
enum Keychain {
    private static let service = "com.lockin.app"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query = baseQuery(key)
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
