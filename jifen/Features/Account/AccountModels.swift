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
}

nonisolated struct AppUser: Codable, Equatable, Identifiable, Sendable {
    var uid: String?
    var id: String
    var name: String?
    var nickname: String?
    var nameSource: String?
    var nameUpdatedAt: Int64?
    var nameVisibility: String? = nil
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
    case failed(String)
}

nonisolated struct SuccessResponse: Decodable, Sendable {
    var success: Bool
}

nonisolated extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
