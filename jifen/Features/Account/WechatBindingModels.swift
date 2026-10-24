import Foundation

/// The authenticated session's provider is supplied by the server. A user's
/// linked providers alone cannot establish which provider started this session.
nonisolated struct WechatBindingStatus: Decodable, Equatable, Sendable {
    struct Capabilities: Decodable, Equatable, Sendable {
        var wechatBinding: Bool
        var accountMerge: Bool
    }

    struct Wechat: Decodable, Equatable, Sendable {
        var bound: Bool
        var canBind: Bool
    }

    var sessionProvider: String?
    var providers: [String]
    var capabilities: Capabilities
    var wechat: Wechat
}

nonisolated struct WechatBindingResponse: Decodable, Sendable {
    var success: Bool
    var status: String
    var bindings: WechatBindingStatus
}

/// Retain only in memory until this authorization completes. Retry a lost
/// response with the same request ID and code; never reuse it in a new session.
nonisolated struct WechatBindingAttempt: Sendable {
    let code: String
    let requestID: String
    let authRevision: UInt64

    init(code: String, authRevision: UInt64, requestID: UUID = UUID()) {
        self.code = code
        self.requestID = requestID.uuidString
        self.authRevision = authRevision
    }
}

nonisolated enum WechatBindingPolicy {
    static func showsEntry(
        isAuthenticated: Bool,
        language: String,
        status: WechatBindingStatus?
    ) -> Bool {
        guard isAuthenticated, WechatLoginPolicy.supports(language: language),
              let status, status.sessionProvider == "apple", status.providers.contains("apple") else {
            return false
        }
        return status.wechat.bound || (status.capabilities.wechatBinding && status.wechat.canBind)
    }

    static func canBind(
        isAuthenticated: Bool,
        language: String,
        status: WechatBindingStatus?
    ) -> Bool {
        showsEntry(isAuthenticated: isAuthenticated, language: language, status: status)
            && status?.wechat.bound == false && status?.wechat.canBind == true
            && status?.capabilities.wechatBinding == true
    }
}

nonisolated enum WechatBindingEndpoint {
    static let status = "/api/auth/bindings"
    static let bind = "/api/auth/bindings/wechat"

    struct Body: Encodable, Sendable {
        let code: String
        let app_id: String
        let requestId: String
    }
}

nonisolated struct AccountLinkAccount: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var uid: String
    var name: String?
    var avatarUrl: String?
    var providers: [String]
    var counts: Counts? = nil
    var membership: AppMembership? = nil
    struct Counts: Decodable, Equatable, Sendable {
        var groups: Int
        var commonNames: Int
        var commonPlaces: Int
        var records: Int
    }
}

nonisolated struct AccountLinkAccounts: Decodable, Equatable, Sendable {
    var current: AccountLinkAccount
    var wechat: AccountLinkAccount
}

nonisolated enum AccountLinkMode: String, Codable, Sendable { case merge, keep }

nonisolated struct AccountLinkResponse: Decodable, Sendable {
    var success: Bool?
    var status: String
    var bindings: WechatBindingStatus?
    var ticket: String?
    var expiresAt: String?
    var accounts: AccountLinkAccounts?
    var token: String?
    var user: AppUser?
    var merge: Merge?

    struct Merge: Decodable, Sendable {
        var mode: AccountLinkMode
        var masterUserId: String
        var sourceUserId: String
    }

    var authentication: AuthResponse? {
        guard let user, let token, let expiresAt, !token.isEmpty else { return nil }
        return AuthResponse(user: user, token: token, expiresAt: expiresAt)
    }
}

nonisolated struct AccountLinkPreview: Decodable, Sendable {
    var ticket: String
    var expiresAt: String
    var mode: AccountLinkMode
    var masterUserId: String
    var previewToken: String
    var accounts: AccountLinkAccounts
    var summary: Summary
    var blockers: [Blocker]
    var warnings: [String]
    var canConfirm: Bool
    var dataScope: String

    struct Blocker: Decodable, Sendable { var code: String; var message: String }
    struct Summary: Decodable, Sendable {
        var groups: Groups
        var assets: Assets
    }
    struct Groups: Decodable, Sendable {
        var groupCount: Int?
        var recordCount: Int?
        var selfMatchCount: Int?
    }
    struct Assets: Decodable, Sendable {
        var commonNameCount: Int?
        var commonPlaceCount: Int?
        var membership: Membership?
        // Optional for previews from servers predating the subscription warning.
        var automaticRenewalCount: Int? = nil
        var warnings: [String]? = nil

        var showsAutomaticRenewalWarning: Bool {
            (automaticRenewalCount ?? 0) > 1 || warnings?.contains(
                "双方订阅将保留各自续费状态。账号合并不会替你取消任何自动续费。"
            ) == true
        }
    }
    struct Membership: Decodable, Sendable {
        var tier: String?
        var billingCycle: String?
        var expiresAt: String?
        var autoRenew: Bool?
        var memberNo: String?
    }

    var masterAccount: AccountLinkAccount {
        accounts.current.id == masterUserId ? accounts.current : accounts.wechat
    }
    var canSubmit: Bool { canConfirm && blockers.isEmpty && !previewToken.isEmpty && dataScope == "cloud" }
}
