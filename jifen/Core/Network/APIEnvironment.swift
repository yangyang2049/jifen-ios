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

    var webSocketBaseURL: URL {
        switch self {
        case .production:
            URL(string: "wss://api.jifenqi.com/ws/")!
        #if STAGING
        case .staging:
            URL(string: "wss://staging-api.jifenqi.com/ws/")!
        #endif
        }
    }

    var isStaging: Bool {
        #if STAGING
        self == .staging
        #else
        false
        #endif
    }
}

