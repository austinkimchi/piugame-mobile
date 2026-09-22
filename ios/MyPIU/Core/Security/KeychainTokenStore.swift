import Foundation
import Security

struct KeychainTokenStore: Sendable {
    private let service = "com.austinkimchi.mypiu.access-token"
    private let account = "mypiu-mobile"

    func save(_ token: MyPIUAccessToken) throws {
        try delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: try JSONEncoder().encode(token)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialStoreError.unhandled(status) }
    }

    func load() throws -> MyPIUAccessToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = try? JSONDecoder().decode(MyPIUAccessToken.self, from: data) else {
            if status == errSecSuccess { throw CredentialStoreError.malformedRecord }
            throw CredentialStoreError.unhandled(status)
        }
        if token.isExpired {
            try delete()
            return nil
        }
        return token
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unhandled(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
    }
}
