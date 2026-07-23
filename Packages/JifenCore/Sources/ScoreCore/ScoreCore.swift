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

/// Stable team identity (aligned with HOS `team_0` / `team_1`).
/// Colors stick to identity: team0 = red/A, team1 = blue/B. Not screen left/right.
public enum TeamID: String, Codable, CaseIterable, Sendable {
    case team0 = "team_0"
    case team1 = "team_1"

    public var opposite: TeamID {
        self == .team0 ? .team1 : .team0
    }

    /// Legacy record / UI winner tokens → team identity.
    public static func fromLegacyWinnerToken(_ token: String?) -> TeamID? {
        guard let raw = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "team_0", "team0", "left", "red", "a":
            return .team0
        case "team_1", "team1", "right", "blue", "b":
            return .team1
        default:
            return nil
        }
    }
}

/// Screen placement for team0 (HOS `team0ScreenSide`). Exchange sides flips only this value.
public struct TeamScreenLayout: Codable, Equatable, Sendable {
    public var team0ScreenSide: MatchSide

    public init(team0ScreenSide: MatchSide = .left) {
        self.team0ScreenSide = team0ScreenSide
    }

    public static let `default` = TeamScreenLayout()

    public var sidesSwapped: Bool {
        team0ScreenSide == .right
    }

    public init(sidesSwapped: Bool) {
        team0ScreenSide = sidesSwapped ? .right : .left
    }

    public mutating func exchangeSides() {
        team0ScreenSide = team0ScreenSide.opposite
    }

    public func screenSide(of team: TeamID) -> MatchSide {
        switch team {
        case .team0: team0ScreenSide
        case .team1: team0ScreenSide.opposite
        }
    }

    public func teamID(on screen: MatchSide) -> TeamID {
        screen == team0ScreenSide ? .team0 : .team1
    }

    /// Map a screen tap/side to geometric MatchSide for reducers that still store left/right scores.
    public func geometricSide(for team: TeamID, sidesSwappedInEngine: Bool) -> MatchSide {
        let screen = screenSide(of: team)
        return sidesSwappedInEngine ? screen.opposite : screen
    }
}

/// Setup name adapter: SportsSetup `team1`/`team2` → team0/team1 identity.
public enum TeamSetupMapping {
    public static func team0Name(team1Name: String, team2Name: String) -> String { team1Name }
    public static func team1Name(team1Name: String, team2Name: String) -> String { team2Name }
}

/// S1 dual-side rally family (= Android/HOS S1 DualSide).
public typealias S1DualSideMatchSide = MatchSide

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
