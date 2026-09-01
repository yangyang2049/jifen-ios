import Foundation

nonisolated enum APIEnvironment: String, Sendable {
    case production
    #if STAGING
    case staging
    #endif

    static var current: APIEnvironment {
        #if STAGING
        return .staging
        #else
        return .production
        #endif
    }

    var restBaseURL: URL {
        switch self {
        case .production:
            URL(string: "https://api.jifenqi.com")!
        #if STAGING
        case .staging:
            URL(string: "https://staging-api.jifenqi.com")!
        #endif
        }
    }

    /// 仅在服务端没有下发有效 wsUrl 时使用。
    /// 从 REST 地址派生，迁移 API 域名时无需再维护一份 WebSocket 域名。
    var webSocketFallbackURL: URL {
        var components = URLComponents(url: restBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = "/ws/"
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    var isStaging: Bool {
        #if STAGING
        self == .staging
        #else
        false
        #endif
    }
}

nonisolated enum WebSocketEndpointResolver {
    static func resolve(serverURL: String?) -> String {
        if let serverURL {
            let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed),
               let scheme = url.scheme?.lowercased(),
               scheme == "ws" || scheme == "wss",
               url.host != nil {
                return trimmed
            }
        }
        return APIEnvironment.current.webSocketFallbackURL.absoluteString
    }
}
