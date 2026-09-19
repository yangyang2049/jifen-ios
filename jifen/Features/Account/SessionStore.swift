import Foundation
import Observation
import UIKit

/// 注销账号结果（对齐安卓 AccountDeletionResult：success + status/message）。
struct AccountDeletionOutcome: Sendable {
    let success: Bool
    let status: String?
    let message: String?
}

nonisolated private struct AccountDeletionRequestBody: Encodable, Sendable {
    var confirmText: String
    let source = "IOS"
}

nonisolated private struct AccountDeletionResponse: Decodable, Sendable {
    var success: Bool?
    var status: String?
    var message: String?
}

nonisolated enum PasswordLoginEndpoint {
    static let path = "/api/auth/login/email"

    struct Body: Encodable, Sendable {
        var email: String
        var password: String
    }
}

@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    enum State: Equatable {
        case restoring
        case signedOut
        case authenticated
    }

    private(set) var state: State = .restoring
    private(set) var user: AppUser?
    private(set) var isWorking = false
    var lastError: String?

    private let client: APIClient
    private let tokenStore: AuthTokenStore
    private let appleProvider: any AccountIdentityProviding
    private var didRestore = false
    private var lastProfileReloadAt: Date?
    private var sessionExpiredObserver: NSObjectProtocol?

    init(client: APIClient = .shared, tokenStore: AuthTokenStore = .shared) {
        self.client = client
        self.tokenStore = tokenStore
        self.appleProvider = ProductionAppleAuthProvider(client: client)
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: .apiSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.expireSession() }
        }
    }

    var isAuthenticated: Bool { state == .authenticated && user != nil }

    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        guard await tokenStore.authToken() != nil else {
            state = .signedOut
            return
        }
        do {
            user = try await client.request("/api/auth/me", requiresAuth: true)
            state = .authenticated
            lastError = nil
            await runPostAuthenticationWarmup(userId: user?.id)
        } catch {
            if error as? APIClientError == .sessionExpired {
                await expireSession()
            } else {
                // A launch-time network outage must not destroy a still-valid login.
                // Allow foreground activation to retry the same Keychain session.
                didRestore = false
                user = nil
                state = .signedOut
                lastError = error.localizedDescription
            }
        }
    }

    func signInWithApple() async {
        await performAuth { try await appleProvider.signIn() }
    }

    /// 账号密码登录（对齐安卓 AuthRepository.loginWithEmail：POST api/auth/login/email）。
    func signInWithEmail(account: String, password: String) async {
        await performAuth {
            try await self.client.request(
                PasswordLoginEndpoint.path,
                method: .post,
                body: PasswordLoginEndpoint.Body(email: account, password: password)
            )
        }
    }

    #if STAGING
    func saveStagingToken(_ token: String) async throws {
        try await tokenStore.setStagingToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    #endif

    func reloadProfile() async {
        guard isAuthenticated else { return }
        do {
            user = try await client.request("/api/auth/me", requiresAuth: true)
        } catch {
            await handle(error)
        }
    }

    func reloadProfileIfNeeded(minimumInterval: TimeInterval = 30) async {
        guard isAuthenticated else { return }
        if let lastProfileReloadAt,
           Date().timeIntervalSince(lastProfileReloadAt) < minimumInterval {
            return
        }
        lastProfileReloadAt = Date()
        await reloadProfile()
    }

    func updateProfile(name: String) async -> ProfileUpdateOutcome {
        struct Body: Encodable, Sendable { var name: String }
        do {
            let response: ProfileUpdateResponse = try await client.request(
                "/api/auth/profile",
                method: .patch,
                body: Body(name: name),
                requiresAuth: true
            )
            user = response.user
            lastError = nil
            if response.user.nameVisibility?.uppercased() == "OWNER_PREVIEW" {
                return .submittedForReview
            }
            return .updated
        } catch {
            if error as? APIClientError == .sessionExpired {
                await expireSession()
                return .failed(lastError ?? error.localizedDescription)
            }
            let message = Self.profileUpdateErrorMessage(error)
            lastError = message
            return .failed(message)
        }
    }

    private static func profileUpdateErrorMessage(_ error: Error) -> String {
        guard let apiError = error as? APIClientError,
              case .server(_, let code, let message, let nextAvailableAt) = apiError,
              code == "NAME_COOLDOWN"
        else {
            return error.localizedDescription
        }

        if let nextAvailableAt,
           let date = APIDateParser.date(from: nextAvailableAt) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return String(
                format: NSLocalizedString(
                    "me_profile_nickname_cooldown",
                    value: "昵称修改后需要稍等一会儿，请在 %@ 后再试",
                    comment: ""
                ),
                formatter.string(from: date)
            )
        }
        return message ?? NSLocalizedString(
            "me_profile_nickname_cooldown_generic",
            value: "昵称修改后需要稍等一会儿，请稍后再试",
            comment: ""
        )
    }

    func uploadAvatar(_ sourceData: Data) async -> Bool {
        nonisolated struct UploadResponse: Decodable, Sendable { let url: String }
        nonisolated struct Body: Encodable, Sendable { let avatarUrl: String }
        guard let jpegData = Self.prepareAvatarJPEG(sourceData) else {
            lastError = NSLocalizedString("account_avatar_invalid", value: "无法读取这张图片", comment: "")
            return false
        }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let boundary = "JifenAvatar-\(UUID().uuidString)"
            var multipart = Data()
            multipart.appendUTF8("--\(boundary)\r\n")
            multipart.appendUTF8("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n")
            multipart.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
            multipart.append(jpegData)
            multipart.appendUTF8("\r\n--\(boundary)--\r\n")
            let upload: UploadResponse = try await client.upload(
                "/api/auth/upload-avatar",
                multipartBody: multipart,
                boundary: boundary
            )
            let response: ProfileUpdateResponse = try await client.request(
                "/api/auth/profile",
                method: .patch,
                body: Body(avatarUrl: upload.url),
                requiresAuth: true
            )
            user = response.user
            return true
        } catch {
            await handle(error)
            return false
        }
    }

    func logout() async {
        let _: SuccessResponse? = try? await client.request(
            "/api/auth/logout",
            method: .post,
            body: EmptyRequest(),
            requiresAuth: isAuthenticated
        )
        await client.clearSession()
        user = nil
        state = .signedOut
        // 登出即终止云端同步会话：发送 LEAVE、断开 WebSocket 并禁止自动重连（对齐安卓端会话随登出终止）。
        CloudSyncSession.shared.end(reason: "logout")
        await CommonDataCloudSyncManager.shared.sessionDidChange(userId: nil)
    }

    private func expireSession() async {
        await client.clearSession()
        user = nil
        state = .signedOut
        lastError = APIClientError.sessionExpired.localizedDescription
        // 凭证已失效（401），本地直接断开云端同步 WebSocket，不再发送 LEAVE。
        CloudSyncSession.shared.endFromServer()
        await CommonDataCloudSyncManager.shared.sessionDidChange(userId: nil)
    }

    func deleteAccount() async -> AccountDeletionOutcome? {
        do {
            let response: AccountDeletionResponse = try await client.request(
                "/api/account-deletion/request",
                method: .post,
                body: AccountDeletionRequestBody(confirmText: "注销账号"),
                requiresAuth: true,
                headers: ["Idempotency-Key": UUID().uuidString]
            )
            if response.success == false {
                return AccountDeletionOutcome(success: false, status: response.status, message: response.message)
            }
            await logout()
            return AccountDeletionOutcome(success: true, status: response.status, message: response.message)
        } catch {
            await handle(error)
            return nil
        }
    }

    private func performAuth(_ operation: () async throws -> AuthResponse) async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let response = try await operation()
            guard let expiry = APIDateParser.date(from: response.expiresAt) else {
                #if DEBUG
                print("[AccountAuth] local session rejected: invalid expiresAt=\(response.expiresAt)")
                #endif
                throw APIClientError.decoding
            }
            try await tokenStore.setAuth(token: response.token, expiresAt: expiry)
            user = response.user
            state = .authenticated
            #if DEBUG
            print("[AccountAuth] local session authenticated")
            #endif
            await runPostAuthenticationWarmup(userId: response.user.id)
        } catch {
            await handle(error)
        }
    }

    private func runPostAuthenticationWarmup(userId: String?) async {
        async let commonDataSync: Void = CommonDataCloudSyncManager.shared.sessionDidChange(
            userId: userId
        )
        async let purchaseSync: Void = StoreKitPurchaseManager.shared.sessionDidAuthenticate()
        _ = await (commonDataSync, purchaseSync)
    }

    private func handle(_ error: Error) async {
        lastError = error.localizedDescription
        if error as? APIClientError == .sessionExpired {
            await expireSession()
        }
    }

    nonisolated private static func prepareAvatarJPEG(_ data: Data) -> Data? {
        guard var image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1024
        let longest = max(image.size.width, image.size.height)
        if longest > maxSide {
            let scale = maxSide / longest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            image = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        }
        for quality in stride(from: 0.86, through: 0.32, by: -0.09) {
            if let output = image.jpegData(compressionQuality: quality), output.count <= 950_000 {
                return output
            }
        }
        return nil
    }
}

nonisolated private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(Data(value.utf8))
    }
}
