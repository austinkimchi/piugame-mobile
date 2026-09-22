import Foundation
import Security

struct KeychainTokenStore: Sendable {
    private let service = "com.austinkimchi.mypiu.access-token"
    private let currentAccount = "mypiu-mobile"
    private let pendingRevocationsAccount = "pending-revocations"

    func save(_ token: MyPIUAccessToken) throws {
        try upsert(try JSONEncoder().encode(token), account: currentAccount)
    }

    func load() throws -> MyPIUAccessToken? {
        guard let data = try data(account: currentAccount) else { return nil }
        guard let token = try? JSONDecoder().decode(MyPIUAccessToken.self, from: data) else {
            throw CredentialStoreError.malformedRecord
        }
        if token.isExpired {
            try delete()
            return nil
        }
        return token
    }

    func delete() throws {
        try delete(account: currentAccount)
    }

    func enqueuePendingRevocation(_ token: MyPIUAccessToken) throws {
        var tokens = try pendingRevocations()
        guard !tokens.contains(where: { $0.value == token.value }) else { return }
        tokens.append(token)
        try replacePendingRevocations(tokens)
    }

    func pendingRevocations() throws -> [MyPIUAccessToken] {
        guard let data = try data(account: pendingRevocationsAccount) else { return [] }
        guard let saved = try? JSONDecoder().decode([MyPIUAccessToken].self, from: data) else {
            throw CredentialStoreError.malformedRecord
        }
        let active = saved.filter { !$0.isExpired }
        if active.count != saved.count {
            try replacePendingRevocations(active)
        }
        return active
    }

    func removePendingRevocation(_ token: MyPIUAccessToken) throws {
        let remaining = try pendingRevocations().filter { $0.value != token.value }
        try replacePendingRevocations(remaining)
    }

    private func replacePendingRevocations(_ tokens: [MyPIUAccessToken]) throws {
        guard !tokens.isEmpty else {
            try delete(account: pendingRevocationsAccount)
            return
        }
        try upsert(try JSONEncoder().encode(tokens), account: pendingRevocationsAccount)
    }

    private func upsert(_ data: Data, account: String) throws {
        let updated = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw CredentialStoreError.unhandled(updated)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialStoreError.unhandled(status) }
    }

    private func data(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialStoreError.unhandled(status)
        }
        return data
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unhandled(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
    }
}
