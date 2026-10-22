import Foundation

nonisolated struct AppMembership: Codable, Equatable, Sendable {
    var memberNo: String
    var displayCode: String
    var numberLabel: String
    var tier: String
    var billingCycle: String
    var purchaseChannel: String
    var purchasedAt: String
    var status: String
    var expiresAt: String?
    var identitySummary: String

    var isActive: Bool { status == "active" }

    func localizedTitle(bundle: Bundle = .main) -> String {
        MembershipDisplayText.title(billingCycle: billingCycle, bundle: bundle)
    }
}

/// Server display strings are Chinese legacy metadata. Render interface copy
/// from stable billing codes so it follows the app's selected language.
nonisolated enum MembershipDisplayText {
    static func title(billingCycle: String?, bundle: Bundle = .main) -> String {
        let key: String
        switch billingCycle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "month", "monthly": key = "membership_monthly_plan_title"
        case "year", "yearly", "annual": key = "membership_yearly_plan_title"
        case "lifetime", "permanent", "permant": key = "membership_lifetime_plan_title"
        default: key = "me_profile_vip_badge"
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

nonisolated struct AppUser: Codable, Equatable, Identifiable, Sendable {
    var uid: String?
    var id: String
    var name: String?
    var nickname: String?
    var nameSource: String?
    var nameUpdatedAt: Int64?
    var nameVisibility: String? = nil
    var avatarVisibility: String? = nil
    var nameModerationReviewReason: String? = nil
    var avatarModerationReviewReason: String? = nil
    var email: String?
    var avatarUrl: String?
    var avatar: String?
    var role: String
    var plan: String
    var createdAt: Int64
    var membership: AppMembership?

    var displayName: String {
        name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? nickname?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? email?.nilIfEmpty
            ?? NSLocalizedString("account_default_name", value: "计分用户", comment: "")
    }

    var isVIP: Bool { role == "VIP" || plan == "VIP" || membership?.isActive == true }

    func localizedMembershipTitle(bundle: Bundle = .main) -> String {
        if let membership, membership.isActive {
            return membership.localizedTitle(bundle: bundle)
        }
        return MembershipDisplayText.title(billingCycle: isVIP ? plan : nil, bundle: bundle)
    }
}

nonisolated enum APIAssetURLResolver {
    static func resolve(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return URL(string: value, relativeTo: APIEnvironment.current.restBaseURL)?.absoluteURL
    }
}

nonisolated struct AuthResponse: Codable, Sendable {
    var user: AppUser
    var token: String
    var expiresAt: String
    var simulated: Bool?
}

nonisolated struct ProfileUpdateResponse: Decodable, Sendable {
    var success: Bool
    var user: AppUser
}

nonisolated enum ProfileUpdateOutcome: Equatable, Sendable {
    case updated
    case submittedForReview
    case cancelled
    case failed(String)
}

/// 资料审核提示条文案：按服务端 visibility 状态码（OWNER_PREVIEW）由客户端生成，
/// 不再显示服务端硬编码中文的 nameVisibilityLabel/avatarVisibilityLabel。
nonisolated enum ProfileModerationBanner {
    static func label(nameVisibility: String?, avatarVisibility: String?) -> String? {
        var parts: [String] = []
        if nameVisibility?.uppercased() == "OWNER_PREVIEW" {
            parts.append(NSLocalizedString(
                "me_profile_name_under_review",
                value: "昵称审核中",
                comment: ""
            ))
        }
        if avatarVisibility?.uppercased() == "OWNER_PREVIEW" {
            parts.append(NSLocalizedString(
                "me_profile_avatar_under_review",
                value: "头像审核中",
                comment: ""
            ))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

nonisolated struct SuccessResponse: Decodable, Sendable {
    var success: Bool
}

nonisolated extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
