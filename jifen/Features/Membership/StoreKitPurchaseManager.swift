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

    private let client: APIClient
    private let tokenStore: AuthTokenStore
    private let transactionGate = PurchaseTransactionGate()
    private var updatesTask: Task<Void, Never>?

    init(client: APIClient = .shared, tokenStore: AuthTokenStore = .shared) {
        self.client = client
        self.tokenStore = tokenStore
        updatesTask = Task { [weak self] in await self?.listenForTransactions() }
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
            await retryStagingUnfinishedTransactions()
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
        await retryStagingUnfinishedTransactions()
        #else
        await retryPendingServerAcknowledgements()
        #endif
    }

    func purchase(_ product: Product) async {
        guard SessionStore.shared.isAuthenticated else {
            fail(NSLocalizedString("membership_login_required", value: "请先登录后购买", comment: ""))
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

    func restorePurchases() async {
        state = .loading
        message = nil
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                let transaction = try verified(result)
                try await acknowledgeAndFinish(
                    transaction,
                    signedTransactionInfo: result.jwsRepresentation
                )
            }
            await SessionStore.shared.reloadProfile()
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
    private func retryStagingUnfinishedTransactions() async {
        guard SessionStore.shared.isAuthenticated else { return }
        var didAck = false
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID)
            else { continue }
            do {
                try await acknowledgeAndFinish(
                    transaction,
                    signedTransactionInfo: result.jwsRepresentation
                )
                didAck = true
            } catch {
                // Leave the transaction unfinished so a later authenticated launch can retry.
            }
        }
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
