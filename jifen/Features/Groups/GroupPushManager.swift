import Foundation
import Observation
import Security
import UIKit
import UserNotifications

nonisolated struct GroupPushDestination: Identifiable, Equatable, Sendable {
    let messageID: String
    let bindingID: String
    var id: String { messageID }
    static func parse(_ info: [AnyHashable: Any]) -> Self? {
        guard let data = info["push"] as? [String: Any], (data["v"] as? Int) == 1,
              let id = data["messageId"] as? String, UUID(uuidString: id) != nil,
              let binding = data["bindingId"] as? String, UUID(uuidString: binding) != nil else { return nil }
        return .init(messageID: id, bindingID: binding)
    }
}
nonisolated struct GroupPushPreferences: Codable, Sendable {
    struct GroupSetting: Codable, Sendable { let groupId: String; var enabled: Bool }
    var enabled: Bool
    var groups: [GroupSetting]
}
nonisolated struct GroupPushMessage: Decodable, Sendable {
    let id, groupId, groupName, kind, sourceType, sourceId, resourceId, title, reason, target: String
    let createdAt: Int64
    var notice: GroupNotification { .init(id: sourceId, groupId: groupId, groupName: groupName, kind: kind, resourceId: resourceId, title: title, reason: reason, createdAt: createdAt, seenAt: nil) }
}
nonisolated private struct PushUnbind: Codable, Sendable { let bindingId: String; let sequence: Int }
nonisolated private struct PushIdentity: Codable {
    var id: String; var key: String; var sequence: Int
    var bindingId: String?; var accountId: String?; var token: String?
    var pending: [PushUnbind]
    var recentBindings: [String: String]? = nil
}
nonisolated private struct PushRegistration: Encodable, Sendable {
    let sequence: Int
    let platform = "ios", provider = "apns", buildChannel = "appstore"
    let applicationId, appVersion, environment, locale, permission, token: String
}
nonisolated private struct PushBinding: Decodable, Sendable { let bindingId: String; let sequence: Int }
nonisolated private struct PushSuccess: Decodable, Sendable { let success: Bool }

@MainActor @Observable final class GroupPushManager {
    static let shared = GroupPushManager()
    var destination: GroupPushDestination?
    private(set) var accountID: String?
    private(set) var tokenRegistrationRevision = 0
    private(set) var registrationStatus = "idle"
    private var generation = 0
    private var identity: PushIdentity?
    private var tail: Task<Void, Never>?
    private let client = APIClient.shared
    private static let service = "com.douhua.jifen.ios.group-push"
    init() { identity = try? Self.readOrCreateIdentity() }

    func sessionDidChange(userID: String?) {
        if accountID != userID {
            generation += 1
            accountID = userID
            if identity?.accountId != userID {
                retireBinding()
                if userID == nil || destination.map({ owner(of: $0.bindingID) != userID }) == true { destination = nil }
            }
        }
        synchronize()
    }
    func receivedToken(_ token: Data) {
        guard AppFeatureFlags.groupRemotePushEnabled else { return }
        tokenRegistrationRevision += 1
        guard identity != nil else { return }
        let value = token.map { String(format: "%02x", $0) }.joined()
        guard identity?.token != value else { return }
        identity?.token = value
        guard persist() else { return }; synchronize()
    }
    func registrationFailed() { /* Retry on the next foreground entry. Token is never logged. */ }
    func open(_ destination: GroupPushDestination) {
        guard AppFeatureFlags.groupRemotePushEnabled else { return }
        guard let owner = owner(of: destination.bindingID), accountID == nil || accountID == owner else { return }
        self.destination = destination
    }
    func matches(_ destination: GroupPushDestination) -> Bool {
        accountID != nil && owner(of: destination.bindingID) == accountID
    }
    private func owner(of binding: String) -> String? {
        if identity?.bindingId == binding { return identity?.accountId }
        return identity?.recentBindings?[binding]
    }
    private func rememberBinding() {
        guard let binding = identity?.bindingId, let account = identity?.accountId else { return }
        var recent = identity?.recentBindings ?? [:]
        if recent.count >= 8, recent[binding] == nil, let oldest = recent.keys.sorted().first { recent.removeValue(forKey: oldest) }
        recent[binding] = account; identity?.recentBindings = recent
    }
    @discardableResult func synchronize() -> Task<Void, Never> {
        let previous = tail
        let task = Task { [weak self] in await previous?.value; guard let self else { return }; await self.reconcile() }
        tail = task
        return task
    }
    func requestPermission() async throws {
        guard AppFeatureFlags.groupRemotePushEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        else if settings.authorizationStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
        synchronize()
    }
    func refreshFromPush(_ info: [AnyHashable: Any]) {
        guard AppFeatureFlags.groupRemotePushEnabled else { return }
        guard let push = GroupPushDestination.parse(info), matches(push) else { return }
        let account = accountID, revision = generation
        Task { [weak self] in
            guard let self, self.generation == revision, self.accountID == account else { return }
            await GroupStore.shared.refresh()
            guard self.generation == revision, self.accountID == account else { return }
            if let message: GroupPushMessage = try? await self.client.request("/api/push/messages/\(push.messageID)", requiresAuth: true),
               self.generation == revision, self.accountID == account {
                await GroupStore.shared.loadDetail(message.groupId)
            }
        }
    }
    private func nextSequence() -> Int? {
        guard var stored = identity, stored.sequence < Int(Int32.max) else { return nil }
        stored.sequence += 1; identity = stored
        return persist() ? stored.sequence : nil
    }
    private func retireBinding() {
        rememberBinding()
        if let binding = identity?.bindingId, let sequence = nextSequence() {
            identity?.pending.append(.init(bindingId: binding, sequence: sequence))
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                let ids = notifications.filter { GroupPushDestination.parse($0.request.content.userInfo)?.bindingID == binding }.map { $0.request.identifier }
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
        identity?.bindingId = nil; identity?.accountId = nil
        _ = persist()
    }
    private func reconcile() async {
        guard LegalConsent.hasAcceptedCurrentDocuments(), AppFeatureFlags.accountFeaturesEnabled else { registrationStatus = "consent_or_account_feature_disabled"; return }
        guard let stored = identity else { registrationStatus = "installation_storage_unavailable"; return }
        for pending in stored.pending {
            do {
                let _: PushSuccess = try await client.request("/api/push/installations/\(stored.id)/binding", method: .delete, body: pending,
                    headers: ["X-Push-Installation-Key": stored.key], timeout: 10, retries: 0)
                identity?.pending.removeAll { $0.bindingId == pending.bindingId && $0.sequence == pending.sequence }; _ = persist()
            } catch { registrationStatus = Self.registrationErrorCode(error, prefix: "unbind"); return }
        }
        guard AppFeatureFlags.groupRemotePushEnabled else { registrationStatus = "release_disabled"; return }
        guard GroupStore.shared.enabled else { registrationStatus = "groups_disabled"; return }
        guard let account = accountID, SessionStore.shared.user?.id == account else { registrationStatus = "account_unavailable"; return }
        let revision = generation, authRevision = await AuthTokenStore.shared.authSessionRevision()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard generation == revision else { return }
        if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) { UIApplication.shared.registerForRemoteNotifications() }
        guard let token = identity?.token else { registrationStatus = "token_unavailable"; return }
        guard let sequence = nextSequence() else { registrationStatus = "installation_storage_unavailable"; return }
        let permission = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) ? "granted" : settings.authorizationStatus == .denied ? "denied" : "unknown"
        let body = PushRegistration(sequence: sequence, applicationId: Bundle.main.bundleIdentifier ?? "com.douhua.jifen.ios",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", environment: Self.environment(),
            locale: Bundle.main.preferredLocalizations.first ?? "en", permission: permission, token: token)
        do {
            let binding: PushBinding = try await client.request("/api/push/installations/\(stored.id)", method: .put, body: body, requiresAuth: true,
                headers: ["X-Push-Installation-Key": stored.key], timeout: 10, retries: 0, expectedAuthRevision: authRevision)
            if generation != revision || accountID != account {
                if let sequence = nextSequence() { identity?.pending.append(.init(bindingId: binding.bindingId, sequence: sequence)); _ = persist() }
                return
            }
            rememberBinding()
            identity?.bindingId = binding.bindingId; identity?.accountId = account; _ = persist()
            registrationStatus = "registered"
        } catch { registrationStatus = Self.registrationErrorCode(error, prefix: "register") }
    }
    private static func registrationErrorCode(_ error: Error, prefix: String) -> String {
        // Diagnostic status only: never retain tokens, request bodies or server messages.
        if let clientError = error as? APIClientError, case let .server(status, code, _, _) = clientError {
            let safeCode = code.flatMap { $0.range(of: "^[A-Z0-9_]{1,80}$", options: .regularExpression) != nil ? $0 : nil } ?? "UNKNOWN"
            return "\(prefix)_http_\(status)_\(safeCode)"
        }
        return "\(prefix)_client_error"
    }
    private func persist() -> Bool {
        guard let identity, let data = try? JSONEncoder().encode(identity) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: "installation"]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insert = query; insert[kSecValueData as String] = data; insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
    private static func readOrCreateIdentity() throws -> PushIdentity {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "installation", kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return try JSONDecoder().decode(PushIdentity.self, from: data) }
        guard status == errSecItemNotFound else { throw KeychainError.status(status) }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw KeychainError.encoding }
        let key = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return PushIdentity(id: UUID().uuidString.lowercased(), key: key, sequence: 0, pending: [])
    }
    private static func environment() -> String {
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"), let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .isoLatin1), let start = text.range(of: "<plist"), let end = text.range(of: "</plist>"),
           let xml = String(text[start.lowerBound..<end.upperBound]).data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
           let entitlements = plist["Entitlements"] as? [String: Any], entitlements["aps-environment"] as? String == "development" { return "sandbox" }
        return "production"
        #endif
    }
}
