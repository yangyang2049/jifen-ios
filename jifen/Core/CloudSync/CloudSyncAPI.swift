import Foundation

// MARK: - DTOs（对齐后端 /api/matches、/api/display 契约）

nonisolated struct CloudMatch: Codable, Sendable {
    var id: String
    var name: String?
    var type: String?
    var status: String?
    var config: [String: CloudMatchConfigValue]? = nil
}

/// config 值可能是字符串或数字，宽松解析。
nonisolated struct CloudMatchConfigValue: Codable, Sendable {
    var value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let number = try? container.decode(Double.self) {
            value = String(number)
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

nonisolated struct CloudRtTokenResponse: Codable, Sendable {
    var rtToken: String
    var matchId: String
    var role: String?
    var wsUrl: String?

    var resolvedWsUrl: String {
        WebSocketEndpointResolver.resolve(serverURL: wsUrl)
    }
}

nonisolated struct CloudShortCodeResponse: Codable, Sendable {
    var code: String
    var expiresAt: Int64
    var maxUses: Int?
    var usedCount: Int?
    var url: String?
}

nonisolated struct CloudJoinByCodeResponse: Codable, Sendable {
    var matchId: String
    var wsToken: String
    var match: CloudMatch?
    var wsUrl: String?

    var resolvedWsUrl: String {
        WebSocketEndpointResolver.resolve(serverURL: wsUrl)
    }
}

nonisolated struct CloudCreateMatchRequest: Encodable, Sendable {
    var type: String = "SCOREBOARD"
    var name: String
    var config: [String: String]
}

nonisolated struct CloudCreateShortCodeRequest: Encodable, Sendable {
    var ttlSec: Int = 3600
    var maxUses: Int = 10
    var role: String = "DISPLAY"
}

nonisolated struct CloudJoinByCodeRequest: Encodable, Sendable {
    var code: String
}

nonisolated struct CloudUpdateMatchRequest: Encodable, Sendable {
    var config: [String: String]
}

// MARK: - API

/// 跨设备同步 REST API（对齐安卓 MatchSyncRepository）。
struct MatchSyncAPI: Sendable {
    static let shared = MatchSyncAPI()

    func createMatch(gameType: String) async throws -> CloudMatch {
        try await APIClient.shared.request(
            "/api/matches",
            method: .post,
            body: CloudCreateMatchRequest(
                name: "\(gameType)_match_\(Int(Date().timeIntervalSince1970 * 1000))",
                config: ["gameType": gameType]
            ),
            requiresAuth: true
        )
    }

    func getRtToken(matchId: String) async throws -> CloudRtTokenResponse {
        try await APIClient.shared.request(
            "/api/matches/\(matchId)/rt-token",
            requiresAuth: true
        )
    }

    func createShortCode(matchId: String) async throws -> CloudShortCodeResponse {
        try await APIClient.shared.request(
            "/api/matches/\(matchId)/short-code",
            method: .post,
            body: CloudCreateShortCodeRequest(),
            requiresAuth: true
        )
    }

    func joinByCode(_ code: String) async throws -> CloudJoinByCodeResponse {
        try await APIClient.shared.request(
            "/api/matches/join-by-code",
            method: .post,
            body: CloudJoinByCodeRequest(code: code)
        )
    }

    func updateMatchGameType(matchId: String, gameType: String) async throws -> EmptyResponse {
        try await APIClient.shared.request(
            "/api/matches/\(matchId)",
            method: .put,
            body: CloudUpdateMatchRequest(config: ["gameType": gameType]),
            requiresAuth: true
        )
    }
}

// MARK: - 支持云端同步的项目（对齐安卓 GameTypeCloudMapping）

enum CloudSyncGameTypes {
    static let supported: Set<String> = [
        "football", "football_5v5",
        "basketball", "three_basketball",
        "volleyball", "beach_volleyball", "air_volleyball",
        "pingpong", "pingpong_doubles",
        "tennis", "tennis_doubles", "soft_tennis", "padel",
        "shuttlecock", "badminton", "badminton_doubles", "squash",
        "boxing", "archery_dual",
        "billiards", "eight_ball", "nine_ball", "snooker",
        "pickleball", "pickleball_doubles",
        "foosball", "foosball_doubles",
        "simple_score", "doudizhu", "guandan", "shengji", "uno", "multi_scoreboard"
    ]

    static func isSupported(_ gameType: String) -> Bool {
        supported.contains(gameType)
    }

    /// 首页预开房占位类型（对齐安卓 CLOUD_SYNC_PLACEHOLDER_GAME_TYPE）。
    static let placeholder = "simple_score"
}

// MARK: - 错误文案映射（对齐安卓 resolveJoinDisplayError）

enum CloudSyncErrorMapper {
    static func joinFailureMessage(_ error: Error) -> String {
        if let apiError = error as? APIClientError, case .server(_, let code, let message, _) = apiError {
            switch code {
            case "CODE_EXPIRED":
                return NSLocalizedString("sync_code_expired", value: "短码已过期，请让分享端重新生成短码", comment: "")
            case "CODE_EXHAUSTED":
                return NSLocalizedString("sync_code_exhausted", value: "短码已被使用，请让分享端重新生成短码", comment: "")
            case "INVALID_CODE":
                return NSLocalizedString("sync_code_invalid", value: "短码无效", comment: "")
            case "DISPLAY_SLOTS_EXHAUSTED", "CONNECTION_LIMIT_REACHED":
                return NSLocalizedString("sync_join_display_slots_full", value: "该比赛的显示端名额已满", comment: "")
            default:
                if let message, !message.isEmpty { return message }
            }
        }
        return NSLocalizedString(
            "sync_join_display_failed",
            value: "连接失败，请检查短码和网络后重试",
            comment: ""
        )
    }

    static func genericFailureMessage(_ error: Error) -> String {
        if let apiError = error as? APIClientError, let message = apiError.errorDescription, !message.isEmpty {
            return message
        }
        return NSLocalizedString("sync_start_failed", value: "开始同步失败", comment: "")
    }
}
