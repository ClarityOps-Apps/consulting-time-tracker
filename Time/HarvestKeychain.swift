import Foundation
import Security

enum HarvestKeychain {
    private static let service = "co.clarityops.Time.harvest"
    private static let accountKey = "account_id"
    private static let tokenKey = "token"

    static func credentials() -> (accountID: String, token: String)? {
        guard let accountID = read(accountKey), !accountID.isEmpty,
              let token = read(tokenKey), !token.isEmpty else {
            return nil
        }
        return (accountID, token)
    }

    static func save(accountID: String, token: String) throws {
        try write(accountKey, accountID)
        try write(tokenKey, token)
    }

    static func clear() {
        delete(accountKey)
        delete(tokenKey)
    }

    private static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ account: String, _ value: String) throws {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw HarvestStoreError.keychain
        }
    }

    private static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum HarvestStoreError: Error {
    case keychain
}
