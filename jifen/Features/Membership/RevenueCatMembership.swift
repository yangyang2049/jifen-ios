import Foundation
import OSLog
import RevenueCat
import StoreKit

@MainActor
enum RevenueCatMembership {
    enum Mode: Equatable {
        case appStore
        case testStore
    }

    struct Configuration: Equatable {
        let key: String
        let mode: Mode

        init?(key: String?, allowsTestStore: Bool) {
            guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let separator = key.firstIndex(of: "_") else { return nil }
            let suffix = key[key.index(after: separator)...]
            guard !suffix.isEmpty, suffix.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
            }) else { return nil }
            switch key[..<separator] {
            case "appl": mode = .appStore
            case "test" where allowsTestStore: mode = .testStore
            default: return nil
            }
            self.key = key
        }
    }

    enum Identity: Equatable {
        case restoring
        case anonymous
        case account(String)
    }

    static let logger = Logger(subsystem: "com.douhua.jifen.ios", category: "RevenueCatMembership")
    private static var busy = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    static var configuration: Configuration? {
        let bundledKey = Bundle.main.object(forInfoDictionaryKey: "JifenRevenueCatSDKKey") as? String
        #if DEBUG
        if WeekendMembershipCampaign.isPreview,
           let override = Configuration(
               key: ProcessInfo.processInfo.environment["JIFEN_REVENUECAT_SDK_KEY"],
               allowsTestStore: true
           ) {
            return override
        }
        return Configuration(key: bundledKey, allowsTestStore: true)
        #else
        return Configuration(key: bundledKey, allowsTestStore: false)
        #endif
    }

    static func identity(for session: SessionStore) -> Identity {
        if session.state == .restoring { return .restoring }
        if WeekendMembershipCampaign.isPreview { return .anonymous }
        if session.isAuthenticated, let id = session.user?.id { return .account(id) }
        return .anonymous
    }

    static func sessionDidChange() async {
        guard Purchases.isConfigured, configuration?.mode == .appStore else { return }
        let expected = identity(for: .shared)
        do {
            _ = try await withPurchases(for: expected) { _ in () }
        } catch is CancellationError {
        } catch {
            logger.error("Could not update customer identity (code: \((error as NSError).code)).")
        }
    }

    static func record(_ result: Product.PurchaseResult, for identity: Identity) {
        guard configuration?.mode == .appStore else { return }
        Task {
            do {
                _ = try await withPurchases(for: identity) { purchases in
                    try await purchases.recordPurchase(result)
                }
            } catch is CancellationError {
                logger.notice("Skipped purchase reporting after the app session changed.")
            } catch {
                logger.error("Could not record a verified StoreKit purchase (code: \((error as NSError).code)).")
            }
        }
    }

    static func syncRestoredPurchases(for identity: Identity) {
        guard configuration?.mode == .appStore else { return }
        Task {
            do {
                _ = try await withPurchases(for: identity) { purchases in try await purchases.syncPurchases() }
            } catch is CancellationError {
            } catch {
                logger.error("Could not sync restored StoreKit purchases (code: \((error as NSError).code)).")
            }
        }
    }

    /// Keep SDK calls and identity changes ordered so an in-flight operation
    /// cannot report under an account that signed in after the operation began.
    static func withPurchases<T>(
        for expected: Identity,
        _ operation: (Purchases) async throws -> T
    ) async throws -> T? {
        guard let configuration else { return nil }
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().resume() }
        }

        try Task.checkCancellation()
        if configuration.mode == .appStore { try checkCurrentIdentity(expected) }
        if !Purchases.isConfigured {
            let builder = RevenueCat.Configuration.Builder(withAPIKey: configuration.key)
                .with(purchasesAreCompletedBy: configuration.mode == .appStore ? .myApp : .revenueCat,
                      storeKitVersion: .storeKit2)
                .with(automaticDeviceIdentifierCollectionEnabled: false)
            if configuration.mode == .appStore, case .account(let id) = expected {
                _ = builder.with(appUserID: id)
            }
            if configuration.mode == .testStore || WeekendMembershipCampaign.isPreview {
                let suite = configuration.mode == .testStore
                    ? "jifen.revenuecat.test-store" : "jifen.revenuecat.apple-preview"
                if let previewDefaults = UserDefaults(suiteName: suite) {
                    _ = builder.with(userDefaults: previewDefaults)
                }
            }
            Purchases.configure(with: builder.build())
        }

        let purchases = Purchases.shared
        if configuration.mode == .appStore {
            switch expected {
            case .account(let id) where purchases.appUserID != id:
                _ = try await purchases.logIn(id)
            case .anonymous where !purchases.isAnonymous:
                _ = try await purchases.logOut()
            default:
                break
            }
            try checkCurrentIdentity(expected)
        }
        return try await operation(purchases)
    }

    private static func checkCurrentIdentity(_ expected: Identity) throws {
        guard expected != .restoring, identity(for: .shared) == expected else { throw CancellationError() }
    }
}
