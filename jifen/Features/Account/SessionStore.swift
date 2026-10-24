import Foundation
import Observation
import UIKit

/// 注销账号结果（对齐安卓 AccountDeletionResult：success + status/message）。
struct AccountDeletionOutcome: Sendable {
    let success: Bool
    let status: String?
    let message: String?

    func localizedMessage(bundle: Bundle = .main) -> String {
        let normalized = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let completed = normalized.isEmpty || ["deleted", "completed", "complete", "success", "succeeded"].contains(normalized)
        let key = success
            ? (completed ? "account_deletion_success" : "account_deletion_submitted")
            : "account_deletion_failed"
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
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
    static let shared: SessionStore = {
        #if DEBUG
        if GroupJoinAuthUITestFixture.enabled { return GroupJoinAuthUITestFixture.makeSession() }
        #endif
        return SessionStore()
    }()

    enum State: Equatable {
        case restoring
        case signedOut
        case authenticated
    }

    private(set) var state: State = .restoring
    private(set) var user: AppUser?
    private(set) var isWorking = false
    var lastError: String?
    private(set) var wechatBindingStatus: WechatBindingStatus?
    var presentsWechatUpgradePrompt = false
    private let bindingPrompt: WechatBindingUpgradePrompt

    private let client: APIClient
    private let tokenStore: AuthTokenStore
    private let appleProvider: any AccountIdentityProviding
    private let postAuthenticationWarmup: (@MainActor (String?) async -> Void)?
    private let postAccountLinkCleanup: (@MainActor (String) async -> Void)?
    private var didRestore = false
    /// 两步补偿：图片已传成功但 PATCH profile 失败时记住 URL，下次上传先补 PATCH，不重复传图。
    private var pendingAvatarURL: String?
    #if DEBUG
    /// UI 测试假登录态：没有真实 token，抑制 401/无 token 引发的会话过期回退。
    private var uiTestFakeSessionActive = false
    #endif
    private var lastProfileReloadAt: Date?
    private var sessionGeneration: UInt64 = 0
    private var sessionExpiredObserver: NSObjectProtocol?

    init(
        client: APIClient = .shared,
        tokenStore: AuthTokenStore = .shared,
        appleProvider: (any AccountIdentityProviding)? = nil,
        postAuthenticationWarmup: (@MainActor (String?) async -> Void)? = nil,
        postAccountLinkCleanup: (@MainActor (String) async -> Void)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.appleProvider = appleProvider ?? ProductionAppleAuthProvider(client: client)
        self.postAuthenticationWarmup = postAuthenticationWarmup
        self.postAccountLinkCleanup = postAccountLinkCleanup
        self.bindingPrompt = WechatBindingUpgradePrompt(defaults: defaults)
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: .apiSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let revision = (notification.userInfo?["authSessionRevision"] as? UInt64)
                ?? (notification.userInfo?["authSessionRevision"] as? NSNumber)?.uint64Value
            Task { @MainActor in
                guard let self else { return }
                await self.expireSession(expectedAuthRevision: revision)
            }
        }
    }

    var isAuthenticated: Bool { state == .authenticated && user != nil }

    /// Only this flow's source session may await a confirmation receipt after
    /// atomic token expiry. A replacement session keeps normal expiry handling.
    private var wechatBindingContext: WechatBindingSessionContext?
    var isWechatBindingSessionActive: Bool { wechatBindingContext != nil }

    /// 生效中的会员状态：服务端账号会员，或未登录时本机 Apple ID 的 StoreKit 权益
    /// （Guideline 5.1.1(v)：购买与权益不强制要求登录账号）。
    var isVIP: Bool { user?.isVIP == true || StoreKitPurchaseManager.shared.hasLocalEntitlement }

    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        #if DEBUG
        if GroupCaptureFixture.enabled {
            NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
            user = AppUser(uid: "cross-platform-capture", id: GroupCaptureFixture.accountID, name: GroupCaptureFixture.accountName, role: "FREE", plan: "FREE", createdAt: GroupCaptureFixture.referenceTime)
            state = .authenticated; uiTestFakeSessionActive = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestFakeSession") {
            var stub = AppUser(
                uid: "ui-test-uid",
                id: "ui-test-user",
                name: "UITestUser",
                role: "FREE",
                plan: "FREE",
                createdAt: Int64(Date().timeIntervalSince1970 * 1000)
            )
            if ProcessInfo.processInfo.arguments.contains("-UITestFakeSessionReview") {
                stub.avatarVisibility = "OWNER_PREVIEW"
            }
            if WechatBindingFixture.enabled {
                stub.uid = "10482"; stub.name = "杨同学"
                wechatBindingStatus = WechatBindingFixture.status
            }
            user = stub
            state = .authenticated
            uiTestFakeSessionActive = true
            return
        }
        #endif
        let generation = sessionGeneration
        let snapshot = await tokenStore.authSnapshot()
        guard generation == sessionGeneration else { return }
        guard snapshot.token != nil else {
            state = .signedOut
            return
        }
        do {
            // 启动恢复走短超时且不重试：离线时快速失败，不占满 45s 资源超时把首屏挂住。
            let profile: AppUser = try await client.request("/api/auth/me", requiresAuth: true, timeout: 8, retries: 0,
                                                         expectedAuthRevision: snapshot.revision)
            try await ensureSession(revision: snapshot.revision, generation: generation)
            user = profile
            state = .authenticated
            lastError = nil
            await reloadWechatBindingStatus()
            try await ensureSession(revision: snapshot.revision, generation: generation)
            await runPostAuthenticationWarmup(userId: user?.id)
        } catch {
            if error is CancellationError || generation != sessionGeneration { return }
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
        await performAuth(method: "apple") { try await appleProvider.signIn() }
    }

    func signInWithWechat() async {
        await performAuth(method: "wechat") { try await ProductionWechatAuthProvider.shared.signIn() }
    }

    /// 账号密码登录（对齐安卓 AuthRepository.loginWithEmail：POST api/auth/login/email）。
    func signInWithEmail(account: String, password: String) async {
        await performAuth(method: "password") {
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
        #if DEBUG
        // 假登录态没有真实 token，不能用 Keychain 里遗留的旧凭证打真实接口，
        // 否则用户身份会被替换成别的账号，与夹具账号不一致后会报「请先登录」。
        if uiTestFakeSessionActive { return }
        #endif
        let generation = sessionGeneration
        let revision = await tokenStore.authSessionRevision()
        do {
            try await ensureSession(revision: revision, generation: generation)
            let profile: AppUser = try await client.request("/api/auth/me", requiresAuth: true, expectedAuthRevision: revision)
            try await ensureSession(revision: revision, generation: generation)
            user = profile
        } catch {
            guard generation == sessionGeneration else { return }
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
        let generation = sessionGeneration
        let revision = await tokenStore.authSessionRevision()
        do {
            try await ensureSession(revision: revision, generation: generation)
            let response: ProfileUpdateResponse = try await client.request(
                "/api/auth/profile",
                method: .patch,
                body: Body(name: name),
                requiresAuth: true,
                expectedAuthRevision: revision
            )
            try await ensureSession(revision: revision, generation: generation)
            user = response.user
            lastError = nil
            if response.user.nameVisibility?.uppercased() == "OWNER_PREVIEW" {
                return .submittedForReview
            }
            return .updated
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || generation != sessionGeneration { return .cancelled }
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
              case .server(_, let code, _, let nextAvailableAt) = apiError,
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
        return NSLocalizedString(
            "me_profile_nickname_cooldown_generic",
            value: "昵称修改后需要稍等一会儿，请稍后再试",
            comment: ""
        )
    }

    func uploadAvatar(_ sourceData: Data) async -> ProfileUpdateOutcome {
        nonisolated struct UploadResponse: Decodable, Sendable { let url: String }
        nonisolated struct Body: Encodable, Sendable { let avatarUrl: String }
        guard !isWorking else {
            return .failed(NSLocalizedString(
                "me_profile_avatar_upload_failed",
                value: "头像上传失败，请稍后重试",
                comment: ""
            ))
        }
        guard let jpegData = Self.prepareAvatarJPEG(sourceData) else {
            let message = NSLocalizedString("account_avatar_invalid", value: "无法读取这张图片", comment: "")
            lastError = message
            return .failed(message)
        }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        let generation = sessionGeneration
        let revision = await tokenStore.authSessionRevision()
        do {
            try await ensureSession(revision: revision, generation: generation)
            let appliedURL: String
            var uploadedJPEG: Data? = nil
            if let pendingAvatarURL {
                // 上一步已把图传上去了：只补 PATCH，不再重复上传图片
                let response: ProfileUpdateResponse = try await client.request(
                    "/api/auth/profile",
                    method: .patch,
                    body: Body(avatarUrl: pendingAvatarURL),
                    requiresAuth: true,
                    expectedAuthRevision: revision
                )
                try await ensureSession(revision: revision, generation: generation)
                appliedURL = pendingAvatarURL
                self.pendingAvatarURL = nil
                user = response.user
            } else {
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
                    boundary: boundary,
                    expectedAuthRevision: revision
                )
                try await ensureSession(revision: revision, generation: generation)
                do {
                    let response: ProfileUpdateResponse = try await client.request(
                        "/api/auth/profile",
                        method: .patch,
                        body: Body(avatarUrl: upload.url),
                        requiresAuth: true,
                        expectedAuthRevision: revision
                    )
                    try await ensureSession(revision: revision, generation: generation)
                    appliedURL = upload.url
                    user = response.user
                    uploadedJPEG = jpegData
                } catch let patchError as APIClientError {
                    // 图已在服务端，记住 URL，下次点头像直接补 PATCH；仅会话失效不补偿。
                    if case .sessionExpired = patchError { throw patchError }
                    try await ensureSession(revision: revision, generation: generation)
                    pendingAvatarURL = upload.url
                    throw patchError
                }
            }
            // 刚上传的图已在内存：种进缓存，头部同步出图，免一次网络回拉
            if let avatarURL = APIAssetURLResolver.resolve(appliedURL),
               let image = uploadedJPEG.flatMap(UIImage.init(data:)) {
                RemoteImageCache.shared.insert(image, for: avatarURL)
            }
            lastError = nil
            if user?.avatarVisibility?.uppercased() == "OWNER_PREVIEW" {
                return .submittedForReview
            }
            return .updated
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || generation != sessionGeneration { return .cancelled }
            if error as? APIClientError == .sessionExpired {
                pendingAvatarURL = nil
                await expireSession()
                return .failed(lastError ?? error.localizedDescription)
            }
            let message = Self.profileUpdateErrorMessage(error)
            lastError = message
            return .failed(message)
        }
    }

    func logout() async {
        wechatBindingContext = nil
        isWorking = false
        GroupPushManager.shared.sessionDidChange(userID: nil)
        presentsWechatUpgradePrompt = false
        wechatBindingStatus = nil
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let revision = await tokenStore.authSessionRevision()
        guard generation == sessionGeneration else { return }
        let _: SuccessResponse? = try? await client.request(
            "/api/auth/logout",
            method: .post,
            body: EmptyRequest(),
            requiresAuth: isAuthenticated,
            expectedAuthRevision: revision
        )
        guard generation == sessionGeneration else { return }
        guard await client.clearSession(expectedAuthRevision: revision), generation == sessionGeneration else { return }
        pendingAvatarURL = nil
        lastProfileReloadAt = nil
        user = nil
        state = .signedOut
        // 登出即终止云端同步会话：发送 LEAVE、断开 WebSocket 并禁止自动重连（对齐安卓端会话随登出终止）。
        CloudSyncSession.shared.end(reason: "logout")
        GroupPushManager.shared.sessionDidChange(userID: nil)
        GroupStore.shared.sessionDidChange(userID: nil)
        await CommonDataCloudSyncManager.shared.sessionDidChange(userId: nil)
    }

    private func expireSession(expectedAuthRevision: UInt64? = nil) async {
        #if DEBUG
        if uiTestFakeSessionActive { return }
        #endif
        let expectedUserID = user?.id
        let snapshot = await tokenStore.authSnapshot()
        // Network failures have already atomically expired the original token in APIClient.
        // Read revision/token together and never clear a newer login from a delayed callback.
        guard snapshot.token == nil, user?.id == expectedUserID,
              expectedAuthRevision == nil || snapshot.revision == expectedAuthRevision else { return }
        if let context = wechatBindingContext,
           context.generation == sessionGeneration, user?.id == context.accountID,
           snapshot.revision == context.authRevision &+ 1 {
            // Keep the flow available for confirm/recover. Closing without a
            // replacement rechecks this expiry instead of silently losing it.
            return
        }
        pendingAvatarURL = nil
        lastProfileReloadAt = nil
        user = nil
        state = .signedOut
        wechatBindingStatus = nil
        presentsWechatUpgradePrompt = false
        lastError = APIClientError.sessionExpired.localizedDescription
        // 凭证已失效（401），本地直接断开云端同步 WebSocket，不再发送 LEAVE。
        CloudSyncSession.shared.endFromServer()
        GroupPushManager.shared.sessionDidChange(userID: nil)
        GroupStore.shared.sessionDidChange(userID: nil)
        await CommonDataCloudSyncManager.shared.sessionDidChange(userId: nil)
    }

    func deleteAccount() async -> AccountDeletionOutcome? {
        let generation = sessionGeneration
        let revision = await tokenStore.authSessionRevision()
        do {
            try await ensureSession(revision: revision, generation: generation)
            let response: AccountDeletionResponse = try await client.request(
                "/api/account-deletion/request",
                method: .post,
                // Server contract: exact simplified literal, matched verbatim by the backend. Do not localize.
                body: AccountDeletionRequestBody(confirmText: "注销账号"),
                requiresAuth: true,
                headers: ["Idempotency-Key": UUID().uuidString],
                expectedAuthRevision: revision
            )
            try await ensureSession(revision: revision, generation: generation)
            if response.success == false {
                return AccountDeletionOutcome(success: false, status: response.status, message: response.message)
            }
            if let accountID = user?.id { GroupLocalPersistence.shared.deleteAccountData(accountID: accountID) }
            await logout()
            return AccountDeletionOutcome(success: true, status: response.status, message: response.message)
        } catch {
            guard generation == sessionGeneration else { return nil }
            await handle(error)
            return nil
        }
    }

    #if DEBUG
    func installWechatBindingFixture(masterUserID: String) {
        guard WechatBindingFixture.enabled, uiTestFakeSessionActive else { return }
        let account = masterUserID == WechatBindingFixture.accounts.current.id
            ? WechatBindingFixture.accounts.current : WechatBindingFixture.accounts.wechat
        user?.id = account.id
        user?.uid = account.uid
        user?.name = account.name
        var status = WechatBindingFixture.status
        status.providers = ["apple", "wechat"]
        status.wechat = .init(bound: true, canBind: false)
        wechatBindingStatus = status
    }
    #endif

    func reloadWechatBindingStatus() async {
        guard isAuthenticated else { wechatBindingStatus = nil; return }
        #if DEBUG
        if uiTestFakeSessionActive { return }
        #endif
        let generation = sessionGeneration
        let revision = await tokenStore.authSessionRevision()
        do {
            let status = try await WechatBindingService(client: client).status(expectedAuthRevision: revision)
            try await ensureSession(revision: revision, generation: generation)
            wechatBindingStatus = status
            if bindingPrompt.offer(status: status) { presentsWechatUpgradePrompt = true }
        } catch {
            guard generation == sessionGeneration else { return }
            // An unavailable/new endpoint must not prevent launch, login or profile use.
            wechatBindingStatus = nil
        }
    }

    func markWechatBindingPromptPresented() {
        bindingPrompt.markPresented()
    }

    func beginWechatBinding() async throws -> WechatBindingSessionContext {
        guard isAuthenticated, let accountID = user?.id, !isWorking else { throw CancellationError() }
        isWorking = true
        presentsWechatUpgradePrompt = false
        let generation = sessionGeneration
        let revision = await tokenStore.authSessionRevision()
        do {
            try await ensureSession(revision: revision, generation: generation)
            guard user?.id == accountID else { throw CancellationError() }
            let context = WechatBindingSessionContext(accountID: accountID, authRevision: revision, generation: generation)
            wechatBindingContext = context
            return context
        } catch {
            if generation == sessionGeneration { isWorking = false }
            throw error
        }
    }

    func validateWechatBinding(_ context: WechatBindingSessionContext) async throws {
        guard wechatBindingContext == context else { throw CancellationError() }
        try await ensureSession(revision: context.authRevision, generation: context.generation)
        guard wechatBindingContext == context, isAuthenticated, user?.id == context.accountID else { throw CancellationError() }
    }

    func updateWechatBinding(_ status: WechatBindingStatus, context: WechatBindingSessionContext) async throws {
        try await validateWechatBinding(context)
        wechatBindingStatus = status
    }

    func endWechatBinding(_ context: WechatBindingSessionContext) async {
        guard wechatBindingContext == context else { return }
        wechatBindingContext = nil
        guard context.generation == sessionGeneration else { return }
        isWorking = false
        await expireSession(expectedAuthRevision: context.authRevision &+ 1)
    }

    /// The merge response is the only path that can replace the current login.
    /// A delayed response can never overwrite a later manual login or logout.
    func applyLinkedAccount(_ response: AuthResponse, bindings: WechatBindingStatus,
                            context: WechatBindingSessionContext) async throws {
        guard wechatBindingContext == context, context.generation == sessionGeneration,
              let expiry = APIDateParser.date(from: response.expiresAt) else { throw CancellationError() }
        let snapshot = await tokenStore.authSnapshot()
        guard wechatBindingContext == context, context.generation == sessionGeneration else { throw CancellationError() }
        let stillOriginal = snapshot.revision == context.authRevision && user?.id == context.accountID
        let expiredOriginal = snapshot.token == nil && snapshot.revision == context.authRevision &+ 1
            && user?.id == context.accountID
        guard stillOriginal || expiredOriginal else { throw CancellationError() }
        guard try await tokenStore.setLinkedAuth(token: response.token, expiresAt: expiry,
                                                replacingSourceRevision: context.authRevision),
              context.generation == sessionGeneration else { throw CancellationError() }
        sessionGeneration &+= 1
        wechatBindingContext = nil
        let linkedGeneration = sessionGeneration
        // Keep authentication changes serialized until the new cloud baseline is
        // installed. Logout/expiry can still interrupt and must cancel the warmup.
        isWorking = true
        defer { if sessionGeneration == linkedGeneration { isWorking = false } }
        pendingAvatarURL = nil
        lastProfileReloadAt = nil
        user = response.user
        state = .authenticated
        wechatBindingStatus = bindings
        lastError = nil
        // Invalidate even when the chosen account ID is unchanged: roles and
        // historical member aliases have changed underneath the cached pages.
        CloudSyncSession.shared.end(reason: "account_linked")
        GroupStore.shared.sessionDidChange(userID: nil)
        if let postAccountLinkCleanup {
            await postAccountLinkCleanup(response.user.id)
        } else {
            try await CommonDataCloudSyncManager.shared.completeAccountLink(userID: response.user.id, context: context)
        }
        guard sessionGeneration == linkedGeneration, isAuthenticated,
              user?.id == response.user.id else { throw CancellationError() }
        await runPostAuthenticationWarmup(userId: response.user.id)
        guard sessionGeneration == linkedGeneration, isAuthenticated,
              user?.id == response.user.id else { throw CancellationError() }
    }

    private func performAuth(method: String, _ operation: () async throws -> AuthResponse) async {
        guard !isWorking else { return }
        presentsWechatUpgradePrompt = false
        wechatBindingStatus = nil
        let interruptedRestore = state == .restoring
        isWorking = true
        sessionGeneration &+= 1
        let generation = sessionGeneration
        lastError = nil
        defer { if generation == sessionGeneration { isWorking = false } }
        let revision = await tokenStore.authSessionRevision()
        do {
            guard generation == sessionGeneration else { throw CancellationError() }
            let response = try await operation()
            guard generation == sessionGeneration else { throw CancellationError() }
            guard let expiry = APIDateParser.date(from: response.expiresAt) else {
                #if DEBUG
                print("[AccountAuth] local session rejected: invalid expiresAt=\(response.expiresAt)")
                #endif
                throw APIClientError.decoding
            }
            guard try await tokenStore.setAuth(token: response.token, expiresAt: expiry, ifRevisionMatches: revision),
                  generation == sessionGeneration else { throw CancellationError() }
            pendingAvatarURL = nil
            lastProfileReloadAt = nil
            user = response.user
            state = .authenticated
            lastError = nil
            #if DEBUG
            print("[AccountAuth] local session authenticated")
            #endif
            await reloadWechatBindingStatus()
            try await ensureSession(revision: revision &+ 1, generation: generation)
            await runPostAuthenticationWarmup(userId: response.user.id)
            try await ensureSession(revision: revision &+ 1, generation: generation)
            AppAnalytics.trackLoginSuccess(method: method)
        } catch {
            guard generation == sessionGeneration else { return }
            let outcome = Self.analyticsAuthOutcome(error)
            AppAnalytics.trackAuthResult(
                method: method,
                result: outcome.result,
                errorCategory: outcome.category
            )
            await handle(error)
            guard interruptedRestore, generation == sessionGeneration else { return }
            // A failed or cancelled login superseded the launch-time restore,
            // but did not replace its credentials. Retry with a fresh generation
            // snapshot; the original restore must still be discarded.
            didRestore = false
            state = .signedOut
            await restore()
        }
    }

    private nonisolated static func analyticsAuthOutcome(_ error: Error) -> (result: AnalyticsResult, category: String) {
        if let wechatError = error as? WechatAuthError, case .cancelled = wechatError {
            return (.cancelled, "user_cancelled")
        }
        if let appleError = error as? AppleAuthError {
            switch appleError {
            case .cancelled: return (.cancelled, "user_cancelled")
            case .stagingTokenRequired: return (.failed, "configuration")
            case .invalidCredential: return (.failed, "invalid_credential")
            case .nonceGenerationFailed: return (.failed, "nonce")
            }
        }
        if let apiError = error as? APIClientError {
            switch apiError {
            case .invalidResponse: return (.failed, "invalid_response")
            case .sessionExpired: return (.failed, "session_expired")
            case .unauthorized: return (.failed, "session_expired")
            case .server: return (.failed, "server")
            case .decoding: return (.failed, "decoding")
            }
        }
        return (.failed, "unknown")
    }

    private func runPostAuthenticationWarmup(userId: String?) async {
        if let postAuthenticationWarmup {
            await postAuthenticationWarmup(userId)
            return
        }
        GroupStore.shared.sessionDidChange(userID: userId)
        GroupPushManager.shared.sessionDidChange(userID: userId)
        Task { await GroupStore.shared.refresh(); GroupPushManager.shared.synchronize() }
        async let commonDataSync: Void = CommonDataCloudSyncManager.shared.sessionDidChange(
            userId: userId
        )
        async let purchaseSync: Void = StoreKitPurchaseManager.shared.sessionDidAuthenticate()
        _ = await (commonDataSync, purchaseSync)
    }

    private func handle(_ error: Error) async {
        guard !(error is CancellationError) else { return }
        if error as? APIClientError == .sessionExpired {
            await expireSession()
        } else {
            lastError = error.localizedDescription
        }
    }

    private func ensureSession(revision: UInt64, generation: UInt64) async throws {
        guard await tokenStore.authSessionRevision() == revision, sessionGeneration == generation else {
            throw CancellationError()
        }
    }

    nonisolated static func prepareAvatarJPEG(_ data: Data) -> Data? {
        guard var image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1024
        let longest = max(image.size.width, image.size.height)
        if longest > maxSide {
            let scale = maxSide / longest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
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

#if DEBUG
/// Exercises the real login UI/session transition without Apple authorization or a server write.
@MainActor @Observable final class GroupJoinAuthUITestFixture {
    static let shared = GroupJoinAuthUITestFixture()
    nonisolated static var enabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITestGroupsFixture") && arguments.contains("-UITestGroupJoinAuth")
    }
    var appleAttempts = 0
    var joinAttempts = 0
    var metadata: String { "authenticated=\(SessionStore.shared.isAuthenticated);apple=\(appleAttempts);join=\(joinAttempts)" }

    static func makeSession() -> SessionStore {
        let tokens = AuthTokenStore(service: "group-join-ui-test.\(UUID().uuidString)")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GroupJoinAuthUITestTransport.self]
        let client = APIClient(session: URLSession(configuration: configuration), tokenStore: tokens)
        return SessionStore(client: client, tokenStore: tokens, appleProvider: AppleProvider(), postAuthenticationWarmup: { id in
            GroupStore.shared.sessionDidChange(userID: id)
            await GroupStore.shared.refresh()
        })
    }

    private struct AppleProvider: AccountIdentityProviding {
        let providerID: AccountIdentityProviderID = .apple
        func signIn() async throws -> AuthResponse {
            GroupJoinAuthUITestFixture.shared.appleAttempts += 1
            throw AppleAuthError.cancelled
        }
    }
}

private nonisolated final class GroupJoinAuthUITestTransport: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.path == PasswordLoginEndpoint.path else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let body = #"{"token":"ui-test-group-token","expiresAt":"2099-01-01T00:00:00Z","user":{"id":"ui-test-user","name":"UITestUser","role":"FREE","plan":"FREE","createdAt":1}}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif

nonisolated private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(Data(value.utf8))
    }
}
