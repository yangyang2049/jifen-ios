import Foundation

public enum GameType: String, Codable, CaseIterable, Sendable {
    case football
    case basketball
    case threeBasketball = "three_basketball"
    case volleyball
    case airVolleyball = "air_volleyball"
    case beachVolleyball = "beach_volleyball"
    case pingpong
    case pingpongDoubles = "pingpong_doubles"
    case tennis
    case tennisDoubles = "tennis_doubles"
    case badminton
    case badmintonDoubles = "badminton_doubles"
    case pickleball
    case pickleballDoubles = "pickleball_doubles"
    case archeryDual = "archery_dual"
    case boxing
    case billiards
    case eightBall = "eight_ball"
    case nineBall = "nine_ball"
    case snooker
    case guandan
    case shengji
    case uno
    case doudizhu
    case foosball
    case foosballDoubles = "foosball_doubles"
    case simpleScore = "simple_score"
    case multiScoreboard = "multi_scoreboard"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "archery": self = .archeryDual
        case "simpleScore": self = .simpleScore
        case "multiScoreboard": self = .multiScoreboard
        default:
            guard let gameType = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown game type: \(value)")
            }
            self = gameType
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum RuleFamily: String, Codable, Sendable {
    case s1
    case s2
    case s3
    case s4
}

public enum MatchSide: String, Codable, CaseIterable, Sendable {
    case left
    case right

    public var opposite: MatchSide {
        self == .left ? .right : .left
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case live
    case finished
    case abandoned
}

public struct SessionParticipant: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var role: String?

    public init(id: String, name: String, role: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
    }
}

public struct SessionMetadata: Codable, Equatable, Sendable {
    public var title: String?
    public var extras: [String: String]

    public init(title: String? = nil, extras: [String: String] = [:]) {
        self.title = title
        self.extras = extras
    }
}

public struct ReduceResult<State: Codable & Sendable, Event: Codable & Sendable>: Sendable {
    public let state: State
    public let events: [Event]
    public let accepted: Bool
    public let reason: String?

    public init(state: State, events: [Event] = [], accepted: Bool = true, reason: String? = nil) {
        self.state = state
        self.events = events
        self.accepted = accepted
        self.reason = reason
    }

    public static func rejected(state: State, reason: String) -> Self {
        Self(state: state, accepted: false, reason: reason)
    }
}

public protocol DomainReducer: Sendable {
    associatedtype State: Codable & Sendable
    associatedtype Intent: Codable & Sendable
    associatedtype Event: Codable & Sendable

    func reduce(state: State, intent: Intent, at epochMilliseconds: Int64) -> ReduceResult<State, Event>
}
