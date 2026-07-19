import Foundation
import LinkCore
import Security
import UIKit

final class AnonymousIdentityProvider: @unchecked Sendable, IdentityProvider {
    static let shared = AnonymousIdentityProvider()

    private let keychainService = "com.douhua.jifen.ios.sync-identity"
    private let keychainAccount = "anonymous-device-id"
    private let displayNameKey = "sync_anonymous_display_name"
    private let lock = NSLock()

    private init() {}

    func currentIdentity() async throws -> SyncIdentity {
        lock.withLock {
            SyncIdentity(localID: loadOrCreateID(), displayName: storedDisplayName())
        }
    }

    func updateDisplayName(_ displayName: String) async throws -> SyncIdentity {
        lock.withLock {
            let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = normalized.isEmpty ? defaultDisplayName() : String(normalized.prefix(32))
            UserDefaults.standard.set(value, forKey: displayNameKey)
            return SyncIdentity(localID: loadOrCreateID(), displayName: value)
        }
    }

    private func storedDisplayName() -> String {
        UserDefaults.standard.string(forKey: displayNameKey) ?? defaultDisplayName()
    }

    private func defaultDisplayName() -> String {
        let model = UIDevice.current.model
        return String(format: NSLocalizedString("sync_guest_device_name", value: "访客 %@", comment: ""), model)
    }

    private func loadOrCreateID() -> UUID {
        if let data = readKeychain(),
           let string = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: string) {
            return id
        }
        let id = UUID()
        saveKeychain(Data(id.uuidString.utf8))
        return id
    }

    private func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func saveKeychain(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
