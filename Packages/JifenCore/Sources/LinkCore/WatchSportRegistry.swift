import RecordCore
import ScoreCore

public enum WatchSetupFamily: String, Codable, Sendable {
    case rally
    case tennis
    case archery
    case eightBall
    case nineBall
    case snooker
    case football
    case basketballTraining
}

public struct WatchSportDescriptor: Equatable, Sendable {
    public let gameType: GameType
    public var baseKind: RecordGameKind { .sport(gameType) }
    public let setupFamily: WatchSetupFamily
    public let supportsWatchLocalSetup: Bool
    public let supportsPhoneWatchLink: Bool
    /// Whether this game type represents a dedicated doubles variant.
    /// Shuttlecock uses one game type for both singles and doubles.
    public let isDoubles: Bool
    /// Default sets for racket sports, or frames in the snooker setup.
    public let defaultMaxSets: Int?
    public let defaultFootballHalfLengthSeconds: Int?

    fileprivate init(
        _ gameType: GameType,
        _ setupFamily: WatchSetupFamily,
        supportsWatchLocalSetup: Bool = true,
        isDoubles: Bool = false,
        defaultMaxSets: Int? = nil,
        defaultFootballHalfLengthSeconds: Int? = nil
    ) {
        self.gameType = gameType
        self.setupFamily = setupFamily
        self.supportsWatchLocalSetup = supportsWatchLocalSetup
        self.supportsPhoneWatchLink = true
        self.isDoubles = isDoubles
        self.defaultMaxSets = defaultMaxSets
        self.defaultFootballHalfLengthSeconds = defaultFootballHalfLengthSeconds
    }
}

public enum WatchSportRegistry {
    private static let entries: [WatchSportDescriptor] = [
        .init(.pingpong, .rally, defaultMaxSets: 5),
        .init(.pingpongDoubles, .rally, isDoubles: true, defaultMaxSets: 5),
        .init(.badminton, .rally, defaultMaxSets: 3),
        .init(.badmintonDoubles, .rally, isDoubles: true, defaultMaxSets: 3),
        .init(.pickleball, .rally, defaultMaxSets: 3),
        .init(.pickleballDoubles, .rally, isDoubles: true, defaultMaxSets: 3),
        .init(.shuttlecock, .rally, defaultMaxSets: 3),
        .init(.squash, .rally, defaultMaxSets: 5),
        .init(.foosball, .rally, defaultMaxSets: 3),
        .init(.foosballDoubles, .rally, supportsWatchLocalSetup: false, isDoubles: true, defaultMaxSets: 3),
        .init(.tennis, .tennis, defaultMaxSets: 3),
        .init(.tennisDoubles, .tennis, isDoubles: true, defaultMaxSets: 3),
        .init(.archeryDual, .archery),
        .init(.eightBall, .eightBall),
        .init(.nineBall, .nineBall),
        .init(.snooker, .snooker, defaultMaxSets: 1),
        .init(.football, .football, defaultFootballHalfLengthSeconds: 45 * 60),
        .init(.football5v5, .football, defaultFootballHalfLengthSeconds: 20 * 60),
        .init(.basketballTraining, .basketballTraining),
    ]

    private static let byGameType = Dictionary(uniqueKeysWithValues: entries.map { ($0.gameType, $0) })
    private static let nineBallPlayerCounts = 2...4

    public static let allLinkedGameTypes: Set<GameType> = Set(
        entries.filter(\.supportsPhoneWatchLink).map(\.gameType)
    )

    public static func descriptor(for gameType: GameType) -> WatchSportDescriptor? {
        byGameType[gameType]
    }

    public static func supportsPhoneWatchLink(
        _ gameType: GameType,
        playerCount: Int? = nil,
        competitionFormat: CompetitionFormat? = nil
    ) -> Bool {
        guard allLinkedGameTypes.contains(gameType) else { return false }
        if gameType == .shuttlecock, competitionFormat == .team { return false }
        if gameType == .nineBall { return nineBallPlayerCounts.contains(playerCount ?? 2) }
        return true
    }

    /// Checks the snapshot family. Opening a linked game also checks its player setup.
    public static func matchesSnapshot(_ snapshot: LinkedScoreboardSnapshot, for gameType: GameType) -> Bool {
        descriptor(for: gameType)?.setupFamily == snapshot.watchSetupFamily
    }

    public static func isValidLinkedSetup(_ setup: LinkedScoreboardSetup) -> Bool {
        guard let descriptor = descriptor(for: setup.gameType),
              descriptor.supportsPhoneWatchLink,
              let snapshot = setup.initialSnapshot,
              descriptor.setupFamily == snapshot.watchSetupFamily else { return false }

        switch snapshot {
        case .rally(let state):
            let hasFourDoublesPlayers = state.doubles?.playerNames.count == 4
            if descriptor.isDoubles { return hasFourDoublesPlayers }
            return state.doubles == nil || (setup.gameType == .shuttlecock && hasFourDoublesPlayers)
        case .tennis(let state):
            return descriptor.isDoubles ? state.doublesPlayerNames?.count == 4 : state.doublesPlayerNames == nil
        case .eightBall, .snooker:
            return setup.participantNames.count == 2
        case .nineBall(let state):
            return nineBallPlayerCounts.contains(state.playerCount)
        case .archery, .football, .basketballTraining:
            return true
        }
    }
}

private extension LinkedScoreboardSnapshot {
    var watchSetupFamily: WatchSetupFamily {
        switch self {
        case .rally: .rally
        case .tennis: .tennis
        case .archery: .archery
        case .eightBall: .eightBall
        case .nineBall: .nineBall
        case .snooker: .snooker
        case .football: .football
        case .basketballTraining: .basketballTraining
        }
    }
}
