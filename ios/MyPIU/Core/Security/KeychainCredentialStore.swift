import Foundation
import Security

enum CredentialStoreError: LocalizedError {
    case malformedRecord
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .malformedRecord: "The saved PIUGAME credentials could not be read."
        case .unhandled(let status): "Keychain returned status \(status)."
        }
    }
}

struct KeychainCredentialStore: Sendable {
    private let service = "com.austinkimchi.mypiu.piugame"

    func save(_ credentials: PIUCredentials) throws {
        try delete()
        let metadata = try JSONEncoder().encode(CredentialMetadata(username: credentials.username, version: credentials.version))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: credentials.username,
            kSecAttrService as String: service,
            kSecAttrGeneric as String: metadata,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(credentials.password.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialStoreError.unhandled(status) }
    }

    func load() throws -> PIUCredentials? {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.unhandled(status) }
        guard let record = result as? [String: Any],
              let passwordData = record[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8),
              let metadataData = record[kSecAttrGeneric as String] as? Data,
              let metadata = try? JSONDecoder().decode(CredentialMetadata.self, from: metadataData) else {
            throw CredentialStoreError.malformedRecord
        }
        return PIUCredentials(username: metadata.username, password: password, version: metadata.version)
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
            kSecAttrService as String: service
        ]
    }
}

private struct CredentialMetadata: Codable {
    let username: String
    let version: PIUGameVersion
}
