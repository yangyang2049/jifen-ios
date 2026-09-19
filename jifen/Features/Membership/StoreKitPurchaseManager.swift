import Foundation
import Observation
import StoreKit

@MainActor
protocol PurchaseProviding: AnyObject {
    var products: [Product] { get }
    func loadProducts() async
    func purchase(_ product: Product) async
    func restorePurchases() async
}

nonisolated enum PurchaseFlowState: Equatable {
    case idle
    case loading
    case purchasing(String)
    case pending
    case succeeded
    case cancelled
    case failed(String)
}

/// Keeps the time-sensitive part of local StoreKit entitlement evaluation
/// deterministic and unit-testable. `Transaction.currentEntitlements` is the
/// source of truth, while this policy prevents a cached snapshot from granting
/// access after its known expiration date.
nonisolated enum LocalStoreEntitlementPolicy {
    static func isActive(
        hasEntitlementSnapshot: Bool,
        expirationDate: Date?,
        now: Date = Date()
    ) -> Bool {
        guard hasEntitlementSnapshot else { return false }
        guard let expirationDate else { return true }
        return expirationDate > now
    }

    static func effectiveAccessExpiration(
        transactionExpiration: Date,
        isInGracePeriod: Bool,
        gracePeriodExpiration: Date?
    ) -> Date {
        guard isInGracePeriod, let gracePeriodExpiration else {
            return transactionExpiration
        }
        return gracePeriodExpiration
    }
}

/// Coalesces concurrent StoreKit delivery paths for the same transaction.
/// Every caller awaits the authoritative acknowledgement instead of treating
/// "already processing" as an immediate success.
@MainActor
final class PurchaseTransactionGate {
    private var inFlight: [UInt64: Task<Void, Error>] = [:]

    func perform(
        transactionID: UInt64,
        operation: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws {
        if let existing = inFlight[transactionID] {
            try await existing.value
            return
        }

        let task = Task { @MainActor in
            try await operation()
        }
        inFlight[transactionID] = task
        defer { inFlight.removeValue(forKey: transactionID) }
        try await task.value
    }
}

@MainActor
@Observable
final class StoreKitPurchaseManager: PurchaseProviding {
    static let shared = StoreKitPurchaseManager()

    // App Store Connect 实际创建的内购商品：终身会员（非消耗型）+
    // 包月/包年（自动续订订阅，"iscoreboard" 订阅组）。
    static let monthlyProductID = "iscoreboard_monthly_vip"
    static let yearlyProductID = "iscoreboard_yearly_vip"
    static let lifetimeProductID = "iscoreboard_lifetime_vip"
    static let productIDs = [
        monthlyProductID,
        yearlyProductID,
        lifetimeProductID
    ]

    private(set) var products: [Product] = []
    private(set) var didLoadProducts = false
    private(set) var state: PurchaseFlowState = .idle
    var message: String?

    /// 未登录时的会员状态：直接来自本机 Apple ID 的 StoreKit 权益（Guideline 5.1.1(v)，
    /// 购买不要求注册账号；登录后可把权益同步到账号，见 retryPendingServerAcknowledgements）。
    private var hasLocalEntitlementSnapshot = false
    /// Access deadline may differ from the transaction expiration while an
    /// auto-renewable subscription is in Apple's billing grace period.
    private var localEntitlementAccessExpirationDate: Date?
    var hasLocalEntitlement: Bool {
        LocalStoreEntitlementPolicy.isActive(
            hasEntitlementSnapshot: hasLocalEntitlementSnapshot,
            expirationDate: localEntitlementAccessExpirationDate
        )
    }
    /// 本地权益到期时间；nil 表示永久有效（终身买断）。
    private(set) var localEntitlementExpirationDate: Date?

    private let client: APIClient
    private let tokenStore: AuthTokenStore
    private let transactionGate = PurchaseTransactionGate()
    private var updatesTask: Task<Void, Never>?
    private var entitlementExpirationTask: Task<Void, Never>?

    init(client: APIClient = .shared, tokenStore: AuthTokenStore = .shared) {
        self.client = client
        self.tokenStore = tokenStore
        updatesTask = Task { [weak self] in await self?.listenForTransactions() }
        Task { [weak self] in await self?.refreshLocalEntitlement() }
    }

    func loadProducts() async {
        state = .loading
        didLoadProducts = false
        message = nil
        do {
            let values = try await Product.products(for: Self.productIDs)
            products = values.sorted { productOrder($0.id) < productOrder($1.id) }
            didLoadProducts = true
            state = .idle
            if products.isEmpty {
                message = NSLocalizedString("membership_store_unavailable", value: "Apple 内购暂不可用", comment: "")
            }
            #if STAGING
            await retryStagingCurrentEntitlements()
            #else
            await retryPendingServerAcknowledgements()
            #endif
        } catch {
            didLoadProducts = true
            fail(error.localizedDescription)
        }
    }

    /// Replays unfinished StoreKit transactions as soon as an account becomes
    /// available, even when the user never opens the membership screen.
    func sessionDidAuthenticate() async {
        #if STAGING
        await retryStagingCurrentEntitlements()
        #else
        await retryPendingServerAcknowledgements()
        #endif
    }

    func purchase(_ product: Product) async {
        // Guideline 5.1.1(v)：不允许把注册/登录作为购买前提。未登录时直接走 StoreKit，
        // 权益由 Apple ID 提供；交易 JWS 暂存本地，登录后补验并同步到账号。
        guard SessionStore.shared.isAuthenticated else {
            await purchaseWithoutAccount(product)
            return
        }
        state = .purchasing(product.id)
        message = nil
        do {
            let token: AccountTokenResponse = try await client.request(
                "/api/payments/apple-iap/account-token",
                requiresAuth: true
            )
            guard let accountToken = UUID(uuidString: token.appAccountToken) else {
                throw PurchaseError.invalidAccountToken
            }
            let result = try await product.purchase(options: [.appAccountToken(accountToken)])
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                try await acknowledgeAndFinish(
                    transaction,
                    signedTransactionInfo: verification.jwsRepresentation
                )
                await SessionStore.shared.reloadProfile()
                state = .succeeded
                message = NSLocalizedString("membership_purchase_success", value: "购买成功，会员状态已更新", comment: "")
            case .pending:
                state = .pending
                message = NSLocalizedString("membership_purchase_pending", value: "购买正在等待确认，确认后会自动更新", comment: "")
            case .userCancelled:
                state = .cancelled
            @unknown default:
                throw PurchaseError.unknownResult
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// 未登录购买：不经过业务服务端（无 appAccountToken、不做服务端验证），
    /// 会员权益由 Apple ID 的 StoreKit 交易直接提供。
    private func purchaseWithoutAccount(_ product: Product) async {
        state = .purchasing(product.id)
        message = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                try await storePendingJWSAndFinish(
                    transaction,
                    signedTransactionInfo: verification.jwsRepresentation
                )
                await refreshLocalEntitlement()
                state = .succeeded
                message = NSLocalizedString(
                    "membership_purchase_success_signed_out",
                    value: "购买成功，会员已在本机生效；登录后可同步到你的其他设备",
                    comment: ""
                )
            case .pending:
                state = .pending
                message = NSLocalizedString("membership_purchase_pending", value: "购买正在等待确认，确认后会自动更新", comment: "")
            case .userCancelled:
                state = .cancelled
            @unknown default:
                throw PurchaseError.unknownResult
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// 记录待补验的交易 JWS 并立即结束交易：未登录时不与服务端交互，
    /// 登录后由 retryPendingServerAcknowledgements 补验，把权益同步到账号。
    private func storePendingJWSAndFinish(
        _ transaction: Transaction,
        signedTransactionInfo: String
    ) async throws {
        try await storePendingJWS(signedTransactionInfo)
        await transaction.finish()
    }

    /// Persists a signed transaction independently of StoreKit's unfinished
    /// queue. Restored transactions may already be finished, but their JWS is
    /// still required to attach the Apple entitlement to a later login.
    private func storePendingJWS(_ signedTransactionInfo: String) async throws {
        var pending = await tokenStore.pendingIapTransactions()
        if !pending.contains(signedTransactionInfo) {
            pending.append(signedTransactionInfo)
            try await tokenStore.setPendingIapTransactions(pending)
        }
    }

    /// 从 StoreKit currentEntitlements 重算未登录状态下的本地会员权益。
    func refreshLocalEntitlement() async {
        var active = false
        var permanent = false
        var latestExpiration: Date?
        var latestAccessExpiration: Date?
        var needsStatusRetry = false
        let now = Date()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID)
            else { continue }
            // currentEntitlements itself is authoritative and also includes
            // subscriptions in billing grace period. Their transaction expiry
            // can already be in the past, so resolve the grace deadline before
            // applying any date-based cache guard.
            active = true
            guard let expiration = transaction.expirationDate else {
                permanent = true
                continue
            }
            let accessExpiration = await effectiveAccessExpirationDate(
                for: transaction,
                transactionExpiration: expiration
            )
            if latestExpiration == nil || accessExpiration > latestExpiration! {
                latestExpiration = accessExpiration
            }
            if accessExpiration > now {
                if latestAccessExpiration == nil || accessExpiration > latestAccessExpiration! {
                    latestAccessExpiration = accessExpiration
                }
            } else {
                // StoreKit still emitted this transaction as an entitlement,
                // but status metadata wasn't fresh enough to expose a future
                // grace deadline. Trust StoreKit and retry shortly.
                needsStatusRetry = true
            }
        }
        hasLocalEntitlementSnapshot = active
        localEntitlementExpirationDate = permanent ? nil : latestExpiration
        localEntitlementAccessExpirationDate = (permanent || needsStatusRetry)
            ? nil
            : latestAccessExpiration
        let refreshDate = needsStatusRetry
            ? now.addingTimeInterval(60)
            : latestAccessExpiration
        scheduleEntitlementRefresh(at: permanent ? nil : refreshDate)
    }

    private func effectiveAccessExpirationDate(
        for transaction: Transaction,
        transactionExpiration: Date
    ) async -> Date {
        guard transactionExpiration <= Date(),
              let status = await transaction.subscriptionStatus,
              case .verified(let renewalInfo) = status.renewalInfo
        else { return transactionExpiration }
        return LocalStoreEntitlementPolicy.effectiveAccessExpiration(
            transactionExpiration: transactionExpiration,
            isInGracePeriod: status.state == .inGracePeriod,
            gracePeriodExpiration: renewalInfo.gracePeriodExpirationDate
        )
    }

    private func scheduleEntitlementRefresh(at expirationDate: Date?) {
        entitlementExpirationTask?.cancel()
        entitlementExpirationTask = nil
        guard let expirationDate else { return }
        let delay = expirationDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        entitlementExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            // Revoke the cached snapshot before asking StoreKit again, so even
            // a delayed StoreKit sequence cannot expose expired UI state.
            self.hasLocalEntitlementSnapshot = false
            await self.refreshLocalEntitlement()
        }
    }

    func restorePurchases() async {
        state = .loading
        message = nil
        do {
            try await AppStore.sync()
            if SessionStore.shared.isAuthenticated {
                for await result in Transaction.currentEntitlements {
                    guard case .verified(let transaction) = result,
                          Self.productIDs.contains(transaction.productID)
                    else { continue }
                    try await acknowledgeAndFinish(
                        transaction,
                        signedTransactionInfo: result.jwsRepresentation
                    )
                }
                await SessionStore.shared.reloadProfile()
            } else {
                // 未登录恢复必须遍历 currentEntitlements：已完成的历史交易不会再出现在
                // Transaction.unfinished，但仍需保存其 JWS，供登录后关联业务账号。
                for await result in Transaction.currentEntitlements {
                    guard case .verified(let transaction) = result,
                          Self.productIDs.contains(transaction.productID)
                    else { continue }
                    try await storePendingJWS(result.jwsRepresentation)
                    // 对仍未 finish 的有效交易也及时结束；对已结束交易重复调用是幂等的。
                    await transaction.finish()
                }
                await refreshLocalEntitlement()
            }
            state = .succeeded
            message = NSLocalizedString("membership_restore_done", value: "恢复购买完成", comment: "")
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            do {
                let transaction = try verified(result)
                try await acknowledgeAndFinish(
                    transaction,
                    signedTransactionInfo: result.jwsRepresentation
                )
                await SessionStore.shared.reloadProfile()
                state = .succeeded
                message = NSLocalizedString("membership_purchase_success", value: "购买成功，会员状态已更新", comment: "")
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func acknowledgeAndFinish(
        _ transaction: Transaction,
        signedTransactionInfo: String
    ) async throws {
        guard Self.productIDs.contains(transaction.productID) else { return }
        try await transactionGate.perform(transactionID: transaction.id) { [self] in
            try await performAcknowledgement(
                transaction,
                signedTransactionInfo: signedTransactionInfo
            )
        }
    }

    private func performAcknowledgement(
        _ transaction: Transaction,
        signedTransactionInfo: String
    ) async throws {
        guard SessionStore.shared.isAuthenticated else {
            // 未登录（Guideline 5.1.1(v)）：所有环境都先保留 JWS；正式环境登录后
            // 走 verify，Staging 登录后则可从 currentEntitlements 取回交易 ID 授权。
            try await storePendingJWSAndFinish(transaction, signedTransactionInfo: signedTransactionInfo)
            await refreshLocalEntitlement()
            return
        }
        #if STAGING
        guard let stagingToken = await tokenStore.stagingToken(), !stagingToken.isEmpty else {
            throw AppleAuthError.stagingTokenRequired
        }
        struct Body: Encodable, Sendable { let productId: String; let transactionId: String }
        let _: IapAcknowledgeResponse = try await client.request(
            "/api/testing/ios/apple-iap/grant",
            method: .post,
            body: Body(productId: transaction.productID, transactionId: String(transaction.id)),
            requiresAuth: true,
            headers: ["X-IOS-Staging-Token": stagingToken]
        )
        #else
        var pending = await tokenStore.pendingIapTransactions()
        if !pending.contains(signedTransactionInfo) {
            pending.append(signedTransactionInfo)
            try await tokenStore.setPendingIapTransactions(pending)
        }
        try await verifyWithServer(signedTransactionInfo)
        pending.removeAll { $0 == signedTransactionInfo }
        try await tokenStore.setPendingIapTransactions(pending)
        #endif
        await transaction.finish()
    }

    #if STAGING
    private func retryStagingCurrentEntitlements() async {
        guard SessionStore.shared.isAuthenticated else { return }
        var pending = Set(await tokenStore.pendingIapTransactions())
        var didAck = false
        // Signed-out purchases and restores are finished after their JWS is
        // persisted, so retry from currentEntitlements rather than unfinished.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID)
            else { continue }
            do {
                try await acknowledgeAndFinish(
                    transaction,
                    signedTransactionInfo: result.jwsRepresentation
                )
                pending.remove(result.jwsRepresentation)
                didAck = true
            } catch {
                // Keep the saved JWS marker so a later authenticated launch retries.
            }
        }
        try? await tokenStore.setPendingIapTransactions(Array(pending))
        if didAck {
            await SessionStore.shared.reloadProfile()
        }
    }
    #endif

    #if !STAGING
    private func verifyWithServer(_ signedTransactionInfo: String) async throws {
        struct Body: Encodable, Sendable { let signedTransactionInfo: String }
        let _: IapAcknowledgeResponse = try await client.request(
            "/api/payments/apple-iap/verify",
            method: .post,
            body: Body(signedTransactionInfo: signedTransactionInfo),
            requiresAuth: true
        )
    }

    private func retryPendingServerAcknowledgements() async {
        guard SessionStore.shared.isAuthenticated else { return }
        var remaining = Set(await tokenStore.pendingIapTransactions())
        var didVerify = false
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            let value = result.jwsRepresentation
            guard remaining.contains(value) else { continue }
            do {
                try await verifyWithServer(value)
                await transaction.finish()
                remaining.remove(value)
                didVerify = true
            } catch {
                // Keep the JWS so the next launch can retry without finishing the transaction.
            }
        }
        for value in Array(remaining) {
            do {
                try await verifyWithServer(value)
                remaining.remove(value)
                didVerify = true
            } catch {
                // Still not acknowledged by the business server.
            }
        }
        try? await tokenStore.setPendingIapTransactions(Array(remaining))
        // 整批补验只刷新一次会员状态，避免逐笔 verify 后各请求一次 /api/auth/me。
        if didVerify {
            await SessionStore.shared.reloadProfile()
        }
    }
    #endif

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw PurchaseError.unverified
        }
    }

    private func productOrder(_ id: String) -> Int {
        Self.productIDs.firstIndex(of: id) ?? Int.max
    }

    private func fail(_ value: String) {
        state = .failed(value)
        message = value
    }
}

nonisolated private struct AccountTokenResponse: Decodable, Sendable { let appAccountToken: String }
nonisolated private struct IapAcknowledgeResponse: Decodable, Sendable { let success: Bool }

nonisolated private enum PurchaseError: LocalizedError {
    case invalidAccountToken
    case unverified
    case unknownResult

    var errorDescription: String? {
        switch self {
        case .invalidAccountToken: NSLocalizedString("membership_account_token_invalid", value: "购买账户标识无效", comment: "")
        case .unverified: NSLocalizedString("membership_unverified", value: "Apple 无法验证这笔交易", comment: "")
        case .unknownResult: NSLocalizedString("membership_unknown_result", value: "未知购买结果", comment: "")
        }
    }
}
