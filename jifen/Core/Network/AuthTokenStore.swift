import CryptoKit
import Foundation
import Security

nonisolated struct AuthSessionSnapshot: Sendable {
    let revision: UInt64
    let token: String?
    let expiresAt: Date?
}

actor AuthTokenStore {
    static let shared = AuthTokenStore()

    nonisolated private struct Credentials: Codable, Sendable {
        var token: String
        var expiresAt: Date
    }

    private enum Key: String {
        case authToken = "auth-token"
        case authExpiry = "auth-expiry"
        #if STAGING
        case stagingToken = "ios-staging-token"
        #endif
        case pendingIap = "pending-apple-iap"
    }

    private let service: String
    private let authFileURL: URL
    private var suppressStoredAuth = false
    private var sessionRevision: UInt64 = 0
    #if DEBUG
    private var didLogAuthSource = false
    #endif

    /// A namespace identifier is safe to inspect without reading any credentials.
    nonisolated var serviceIdentifier: String { service }

    init(service: String = AppTestRuntime.authService, authFileURL: URL? = nil) {
        self.service = service
        let root = AppTestRuntime.storageRootURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let filename = SHA256.hash(data: Data(service.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
        self.authFileURL = authFileURL ?? root.appendingPathComponent("auth-sessions", isDirectory: true).appendingPathComponent(filename)
    }

    func authSessionRevision() -> UInt64 { sessionRevision }

    func authSnapshot() -> AuthSessionSnapshot {
        let credentials = storedCredentials()
        #if DEBUG
        if !didLogAuthSource {
            didLogAuthSource = true
            print("[AuthTokenStore] login source=app-container-file, loginCredentialPresent=\(credentials != nil)")
        }
        #endif
        return AuthSessionSnapshot(revision: sessionRevision, token: credentials?.token, expiresAt: credentials?.expiresAt)
    }

    private func matches(_ snapshot: AuthSessionSnapshot) -> Bool {
        sessionRevision == snapshot.revision && authToken() == snapshot.token
    }

    /// Refresh changes credentials inside one login session; it may not replace a later login.
    func setRefreshedAuth(token: String, expiresAt: Date, ifMatching snapshot: AuthSessionSnapshot) throws -> AuthSessionSnapshot? {
        guard matches(snapshot) else { return nil }
        try saveCredentials(.init(token: token, expiresAt: expiresAt), to: authFileURL)
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

    func authToken() -> String? {
        storedCredentials()?.token
    }

    func authExpiry() -> Date? {
        storedCredentials()?.expiresAt
    }

    func setAuth(token: String, expiresAt: Date) throws {
        try saveCredentials(.init(token: token, expiresAt: expiresAt), to: authFileURL)
        sessionRevision &+= 1
        suppressStoredAuth = false
    }

    func setAuth(token: String, expiresAt: Date, ifRevisionMatches revision: UInt64) throws -> Bool {
        guard sessionRevision == revision else { return false }
        try setAuth(token: token, expiresAt: expiresAt)
        return true
    }

    /// Confirmation can race the source token's atomic 401 clear. Decide and
    /// install in one actor turn; a later login or a second clear is never eligible.
    func setLinkedAuth(token: String, expiresAt: Date, replacingSourceRevision revision: UInt64) throws -> Bool {
        guard sessionRevision == revision || (sessionRevision == revision &+ 1 && authToken() == nil) else { return false }
        try setAuth(token: token, expiresAt: expiresAt)
        return true
    }

    func clearAuth() {
        sessionRevision &+= 1
        suppressStoredAuth = true
        try? FileManager.default.removeItem(at: authFileURL)
        // Remove legacy credentials on logout, but never read them for login.
        delete(.authToken)
        delete(.authExpiry)
    }

    #if STAGING
    private var stagingFileURL: URL { authFileURL.deletingPathExtension().appendingPathExtension("staging.json") }
    func stagingToken() -> String? {
        readCredentials(from: stagingFileURL)?.token
    }
    func setStagingToken(_ token: String) throws {
        try saveCredentials(.init(token: token, expiresAt: .distantFuture), to: stagingFileURL)
    }
    func clearStagingToken() {
        try? FileManager.default.removeItem(at: stagingFileURL)
        delete(.stagingToken)
    }
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

    private func storedCredentials() -> Credentials? {
        suppressStoredAuth ? nil : readCredentials(from: authFileURL)
    }

    private func readCredentials(from url: URL) -> Credentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    /// App-container storage follows uninstall, while surviving normal updates
    /// and the app's record/preferences reset. Legacy Keychain login is ignored.
    private func saveCredentials(_ credentials: Credentials, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(credentials).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
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
