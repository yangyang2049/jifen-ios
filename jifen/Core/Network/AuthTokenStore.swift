import Foundation
import Security

nonisolated struct AuthSessionSnapshot: Sendable {
    let revision: UInt64
    let token: String?
    let expiresAt: Date?
}

actor AuthTokenStore {
    static let shared = AuthTokenStore()

    private enum Key: String {
        case authToken = "auth-token"
        case authExpiry = "auth-expiry"
        #if STAGING
        case stagingToken = "ios-staging-token"
        #endif
        case pendingIap = "pending-apple-iap"
    }

    private let service: String
    private var sessionRevision: UInt64 = 0

    init(service: String = "com.douhua.jifen.ios.secure") {
        self.service = service
    }

    func authSessionRevision() -> UInt64 { sessionRevision }

    func authSnapshot() -> AuthSessionSnapshot {
        AuthSessionSnapshot(revision: sessionRevision, token: authToken(), expiresAt: authExpiry())
    }

    private func matches(_ snapshot: AuthSessionSnapshot) -> Bool {
        sessionRevision == snapshot.revision && authToken() == snapshot.token
    }

    /// Refresh changes credentials inside one login session; it may not replace a later login.
    func setRefreshedAuth(token: String, expiresAt: Date, ifMatching snapshot: AuthSessionSnapshot) throws -> AuthSessionSnapshot? {
        guard matches(snapshot) else { return nil }
        try writeString(token, key: .authToken)
        try writeString(String(expiresAt.timeIntervalSince1970), key: .authExpiry)
        return authSnapshot()
    }

    /// Compare and clear atomically so an old request cannot log out another account.
    func clearAuth(ifMatching snapshot: AuthSessionSnapshot) -> UInt64? {
        guard matches(snapshot) else { return nil }
        clearAuth()
        return sessionRevision
    }

    func clearAuth(ifRevisionMatches revision: UInt64) -> UInt64? {
        guard sessionRevision == revision else { return nil }
        clearAuth()
        return sessionRevision
    }

    func authToken() -> String? { readString(.authToken) }

    func authExpiry() -> Date? {
        guard let value = readString(.authExpiry), let seconds = TimeInterval(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func setAuth(token: String, expiresAt: Date) throws {
        sessionRevision &+= 1
        try writeString(token, key: .authToken)
        try writeString(String(expiresAt.timeIntervalSince1970), key: .authExpiry)
    }

    func setAuth(token: String, expiresAt: Date, ifRevisionMatches revision: UInt64) throws -> Bool {
        guard sessionRevision == revision else { return false }
        try setAuth(token: token, expiresAt: expiresAt)
        return true
    }

    func clearAuth() {
        sessionRevision &+= 1
        delete(.authToken)
        delete(.authExpiry)
    }

    #if STAGING
    func stagingToken() -> String? { readString(.stagingToken) }
    func setStagingToken(_ token: String) throws { try writeString(token, key: .stagingToken) }
    func clearStagingToken() { delete(.stagingToken) }
    #endif

    func pendingIapTransactions() -> [String] {
        guard let value = readString(.pendingIap),
              let data = value.data(using: .utf8),
              let transactions = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return transactions
    }

    func setPendingIapTransactions(_ values: [String]) throws {
        if values.isEmpty {
            delete(.pendingIap)
            return
        }
        let data = try JSONEncoder().encode(Array(Set(values)))
        guard let value = String(data: data, encoding: .utf8) else { throw KeychainError.encoding }
        try writeString(value, key: .pendingIap)
    }

    private func readString(_ key: Key) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeString(_ value: String, key: Key) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encoding }
        let query = baseQuery(key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw KeychainError.status(insertStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    private func delete(_ key: Key) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}

enum KeychainError: LocalizedError {
    case encoding
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encoding: "Unable to encode secure value."
        case .status(let status): "Keychain error (\(status))."
        }
    }
}
