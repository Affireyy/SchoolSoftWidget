import Foundation
import Security

/// Thread-safe helper for storing and retrieving sensitive credentials in the macOS Keychain.
public enum KeychainHelper {
    public static let defaultService = "com.dessimondi.SchoolSoftWidget"

    @discardableResult
    public static func save(password: String, for account: String, service: String = defaultService) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        // Remove existing item before inserting
        delete(for: account, service: service)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public static func get(for account: String, service: String = defaultService) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    @discardableResult
    public static func delete(for account: String, service: String = defaultService) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
