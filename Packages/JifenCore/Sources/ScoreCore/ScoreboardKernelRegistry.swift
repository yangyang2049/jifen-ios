import Foundation

public enum ScoreboardKernelKind: String, Codable, Equatable, Sendable {
    case rally
    case tennis
    case line
    case basketball
    case eightBall = "eight_ball"
    case nineBall = "nine_ball"
    case snooker
    case boxing
    case guandan
    case shengji
    case multi
    case uno
    case doudizhu
    case archery
}

public struct ScoreboardKernelDescriptor: Codable, Equatable, Sendable {
    public let gameType: GameType
    public let ruleFamily: RuleFamily
    public let kind: ScoreboardKernelKind
    public let reducerType: String

    public init(gameType: GameType, ruleFamily: RuleFamily, kind: ScoreboardKernelKind, reducerType: String) {
        self.gameType = gameType
        self.ruleFamily = ruleFamily
        self.kind = kind
        self.reducerType = reducerType
    }
}

public enum ScoreboardKernelRegistry {
    public static func descriptor(for gameType: GameType) -> ScoreboardKernelDescriptor {
        let family: RuleFamily
        let kind: ScoreboardKernelKind
        switch gameType {
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles, .pickleball, .pickleballDoubles,
             .volleyball, .airVolleyball, .beachVolleyball, .foosball, .foosballDoubles:
            family = .s1; kind = .rally
        case .tennis, .tennisDoubles:
            family = .s1; kind = .tennis
        case .football, .billiards, .simpleScore:
            family = .s1; kind = .line
        case .basketball, .threeBasketball:
            family = .s2; kind = .basketball
        case .eightBall:
            family = .s2; kind = .eightBall
        case .nineBall:
            family = .s2; kind = .nineBall
        case .snooker:
            family = .s2; kind = .snooker
        case .boxing:
            family = .s2; kind = .boxing
        case .multiScoreboard:
            family = .s3; kind = .multi
        case .uno:
            family = .s3; kind = .uno
        case .guandan:
            family = .s4; kind = .guandan
        case .shengji:
            family = .s4; kind = .shengji
        case .doudizhu:
            family = .s4; kind = .doudizhu
        case .archeryDual:
            family = .s2; kind = .archery
        }
        return .init(gameType: gameType, ruleFamily: family, kind: kind, reducerType: "\(kind.rawValue)/v1")
    }

    public static func defaultRallyRules(for gameType: GameType) -> RallyRuleSet? {
        switch gameType {
        case .pingpong, .pingpongDoubles: .pingPong()
        case .badminton, .badmintonDoubles: .badminton()
        case .pickleball, .pickleballDoubles: .pickleball()
        case .volleyball: .volleyball()
        case .airVolleyball: .airVolleyball()
        case .beachVolleyball: .beachVolleyball()
        case .foosball, .foosballDoubles: .foosball()
        default: nil
        }
    }

    public static func defaultLineRules(for gameType: GameType) -> LineScoreRuleSet? {
        switch gameType {
        case .football, .billiards: .nonNegative
        case .simpleScore: .freeCounter
        default: nil
        }
    }
}
