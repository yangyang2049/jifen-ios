import Foundation
import ScoreCore

/// Persists the exact initial scoreboard state used by a scheduled booking.
/// The returned identifier can be passed straight to `ScoreboardLaunchView` so
/// an app interruption immediately after launch still leaves a resumable game.
@MainActor
enum BookingStartPersistence {
    static func persist(_ request: BookingStartRequest) async -> String? {
        switch request.gameType {
        case .pingpong, .badminton, .volleyball, .airVolleyball,
             .beachVolleyball, .pickleball:
            return await persistRally(request)
        case .tennis:
            return await persistTennis(request)
        case .basketball:
            return await persistBasketball(request)
        case .football:
            return persistFootball(request)
        case .billiards:
            return persistLineScore(request)
        case .eightBall:
            return await persistEightBall(request)
        case .nineBall:
            return await persistNineBall(request)
        case .snooker:
            return await persistSnooker(request)
        default:
            return nil
        }
    }

    private static func persistRally(_ request: BookingStartRequest) async -> String? {
        let setup = request.setup
        let isDoubles = setup.isSingles == false
        let names = resolvedNames(for: request.gameType, setup: setup, isSingles: !isDoubles)
        let scoreCoreType: ScoreCore.GameType
        let rules: RallyRuleSet

        switch request.gameType {
        case .pingpong:
            scoreCoreType = isDoubles ? .pingpongDoubles : .pingpong
            var value = RallyRuleSet.pingPong(
                maxSets: setup.maxSets ?? 5,
                matchCompletionMode: setup.matchCompletionMode ?? .bestOf
            )
            let target = max(1, setup.pointsPerSet ?? 11)
            value.pointsToWinSet = target
            value.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(
                for: scoreCoreType,
                pointsPerSet: target
            )
            value.autoChangeSides = setup.autoChangeSides ?? true
            rules = value
        case .badminton:
            scoreCoreType = isDoubles ? .badmintonDoubles : .badminton
            rules = setup.badmintonRules
        case .volleyball:
            scoreCoreType = .volleyball
            var value = RallyRuleSet.volleyball(maxSets: setup.maxSets ?? 5)
            value.autoChangeSides = setup.autoChangeSides ?? true
            rules = value
        case .airVolleyball:
            scoreCoreType = .airVolleyball
            var value = RallyRuleSet.airVolleyball(maxSets: setup.maxSets ?? 3)
            value.autoChangeSides = setup.autoChangeSides ?? true
            rules = value
        case .beachVolleyball:
            scoreCoreType = .beachVolleyball
            var value = RallyRuleSet.beachVolleyball(maxSets: setup.maxSets ?? 3)
            value.autoChangeSides = setup.autoChangeSides ?? true
            rules = value
        case .pickleball:
            scoreCoreType = isDoubles ? .pickleballDoubles : .pickleball
            var value = RallyRuleSet.pickleball(
                maxSets: setup.maxSets ?? 3,
                matchCompletionMode: setup.matchCompletionMode ?? .bestOf
            )
            value.pointsToWinSet = max(1, setup.targetScore ?? setup.pointsPerSet ?? 11)
            value.pointCap = setup.scoreCap
            value.winByTwo = setup.winByTwo ?? true
            value.autoChangeSides = setup.autoChangeSides ?? true
            value.useRallyScoring = setup.useRallyScoring ?? false
            value.nextSetServerModel = isDoubles ? .alternateFromOpening : .opening
            rules = value
        default:
            return nil
        }

        let store = RallySessionStore(
            leftName: names.left,
            rightName: names.right,
            gameType: scoreCoreType,
            rules: rules,
            participants: isDoubles ? doublesParticipants(setup) : nil,
            openingServer: setup.servingSide == MatchSide.right.rawValue ? .right : .left,
            voiceAnnouncementEnabled: setup.voiceAnnouncement == true
        )
        return await persist(store)
    }

    private static func persistTennis(_ request: BookingStartRequest) async -> String? {
        let setup = request.setup
        let isDoubles = setup.isSingles == false
        let scoreCoreType: ScoreCore.GameType = isDoubles ? .tennisDoubles : .tennis
        let names = resolvedNames(for: .tennis, setup: setup, isSingles: !isDoubles)
        let rules = TennisRuleSet(
            maxSets: setup.maxSets ?? 3,
            tieBreakPoints: setup.tieBreakPoints == 10 ? 10 : 7,
            gamesPerSet: setup.gamesPerSet ?? 6,
            setScoringMode: setup.setScoringMode == "tiebreak_only" ? .tiebreakOnly : .regular,
            matchCompletionMode: setup.matchCompletionMode ?? .bestOf,
            usesNoAdScoring: setup.tennisDeuceMode == "no_ad",
            autoChangeSides: setup.autoChangeSides ?? true
        )
        let doublesNames: [String]? = isDoubles ? [
            setup.team1Player1Name ?? "",
            setup.team2Player1Name ?? "",
            setup.team1Player2Name ?? "",
            setup.team2Player2Name ?? ""
        ] : nil
        var state = TennisMatchState(
            leftName: names.left,
            rightName: names.right,
            rules: rules,
            openingServer: setup.servingSide == MatchSide.right.rawValue ? .right : .left,
            doublesPlayerNames: doublesNames
        )
        if isDoubles {
            state.leftName = state.doublesTeamDisplayName(for: .left)
            state.rightName = state.doublesTeamDisplayName(for: .right)
        }
        let store = TennisSessionStore(
            gameType: scoreCoreType,
            state: state,
            voiceAnnouncementEnabled: setup.voiceAnnouncement == true
        )
        return await persist(store)
    }

    private static func persistBasketball(_ request: BookingStartRequest) async -> String? {
        let setup = request.setup
        let gameMode: BasketballGameMode = setup.basketballMode == "three_x_three"
            ? .threeXThree
            : .fiveVFive
        let names = resolvedNames(for: .basketball, setup: setup)
        let store = BasketballSessionStore(
            leftName: names.left,
            rightName: names.right,
            gameMode: gameMode,
            ruleSet: setup.basketballRuleSet == "nba" ? .nba : .fiba
        )
        return await persist(store)
    }

    private static func persistFootball(_ request: BookingStartRequest) -> String? {
        let setup = request.setup
        let names = resolvedNames(for: .football, setup: setup)
        let state = LineScoreState(
            leftName: names.left,
            rightName: names.right,
            rules: .nonNegative
        )
        let lineResume = LineScoreResumeState(
            state: state,
            undoHistory: [],
            intentTimeline: []
        )
        let halfLength = setup.footballHalfLengthSeconds ?? 45 * 60
        let timer = initialFootballTimerState(halfLengthSeconds: halfLength)
        let footballResume = FootballResumeStateV2(
            lineScore: lineResume,
            timer: timer
        )
        guard let snapshot = try? JSONEncoder().encode(footballResume) else { return nil }
        return persistManualRecord(
            gameType: .football,
            scoreCoreGameType: .football,
            leftName: names.left,
            rightName: names.right,
            snapshot: snapshot,
            configuration: [
                "minimumScore": AnyCodable(LineScoreRuleSet.nonNegative.minimum),
                "maximumScore": AnyCodable(LineScoreRuleSet.nonNegative.maximum),
                "ruleProfileVersion": AnyCodable(1),
                "footballHalfLengthSeconds": AnyCodable(halfLength),
                "showMatchTime": AnyCodable(true)
            ]
        )
    }

    /// Keep scheduled football starts identical to a normal
    /// `FootballViewModel` launch: eleven-a-side starts immediately and carries
    /// a wall-clock anchor so an interruption before the first UI frame still
    /// resumes with elapsed time accounted for.
    static func initialFootballTimerState(
        halfLengthSeconds: Int,
        clock: any FootballClock = SystemFootballClock()
    ) -> FootballTimerStateV2 {
        var session = FootballMatchClockSession(
            state: FootballTimerStateV2(halfLengthSeconds: halfLengthSeconds),
            gameType: .football,
            clock: clock
        )
        session.resetForNewGame()
        return session.snapshot()
    }

    private static func persistLineScore(_ request: BookingStartRequest) -> String? {
        let names = resolvedNames(for: .billiards, setup: request.setup)
        let state = LineScoreState(
            leftName: names.left,
            rightName: names.right,
            rules: .nonNegative
        )
        let resume = LineScoreResumeState(
            state: state,
            undoHistory: [],
            intentTimeline: []
        )
        guard let snapshot = try? JSONEncoder().encode(resume) else { return nil }
        return persistManualRecord(
            gameType: .billiards,
            scoreCoreGameType: .billiards,
            leftName: names.left,
            rightName: names.right,
            snapshot: snapshot,
            configuration: [
                "minimumScore": AnyCodable(LineScoreRuleSet.nonNegative.minimum),
                "maximumScore": AnyCodable(LineScoreRuleSet.nonNegative.maximum)
            ]
        )
    }

    private static func persistEightBall(_ request: BookingStartRequest) async -> String? {
        let setup = request.setup
        let names = resolvedNames(for: .eightBall, setup: setup)
        let target: Int
        let handicap: Int
        let beneficiary: MatchSide?
        if case let .some(.eightBall(targetRacks, handicapRacks, projectedBeneficiary)) =
            setup.billiardsConfiguration(for: .eightBall) {
            target = targetRacks
            handicap = handicapRacks
            beneficiary = projectedBeneficiary
        } else {
            target = 9
            handicap = 0
            beneficiary = nil
        }
        let id = UUID().uuidString
        let state = EightBallState.initial(
            targetPoints: target,
            handicapRacks: handicap,
            handicapBeneficiary: beneficiary
        )
        let store = BilliardsSessionStore(
            gameType: ScoreCore.GameType.eightBall,
            state: state,
            reducer: EightBallReducer(),
            participants: teamParticipants(left: names.left, right: names.right),
            startedAt: Date(),
            recordID: id
        )
        return await persist(store)
    }

    private static func persistNineBall(_ request: BookingStartRequest) async -> String? {
        let setup = request.setup
        let config: NineBallChaseConfig
        let projectedNames: [String]
        if case let .some(.nineBall(names, points)) = setup.billiardsConfiguration(for: .nineBall) {
            config = points
            projectedNames = names
        } else {
            config = NineBallChaseConfig()
            projectedNames = []
        }
        let names = (0..<4).map { index in
            if projectedNames.indices.contains(index), !projectedNames[index].isEmpty {
                return projectedNames[index]
            }
            return String.localizedStringWithFormat(
                NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: ""),
                index + 1
            )
        }
        let playerCount = projectedNames.isEmpty ? 2 : projectedNames.count
        let state = NineBallChaseState.initial(
            config: config,
            playerCount: playerCount,
            playerNames: names
        )
        let id = UUID().uuidString
        let store = BilliardsSessionStore(
            gameType: ScoreCore.GameType.nineBall,
            state: state,
            reducer: NineBallChaseReducer(),
            participants: (0..<state.playerCount).map {
                .init(id: "player_\($0 + 1)", name: names[$0], role: "player")
            },
            startedAt: Date(),
            recordID: id
        )
        return await persist(store)
    }

    private static func persistSnooker(_ request: BookingStartRequest) async -> String? {
        let setup = request.setup
        let names = resolvedNames(for: .snooker, setup: setup)
        let maxFrames: Int
        let firstBreaker: MatchSide
        if case let .some(.snooker(projectedFrames, projectedBreaker)) =
            setup.billiardsConfiguration(for: .snooker) {
            maxFrames = projectedFrames
            firstBreaker = projectedBreaker
        } else {
            maxFrames = 1
            firstBreaker = .left
        }
        let id = UUID().uuidString
        let store = BilliardsSessionStore(
            gameType: ScoreCore.GameType.snooker,
            state: SnookerState.initial(striker: firstBreaker, maxFrames: maxFrames),
            reducer: SnookerReducer(),
            participants: teamParticipants(left: names.left, right: names.right),
            startedAt: Date(),
            recordID: id
        )
        return await persist(store)
    }

    private static func persist(_ store: RallySessionStore) async -> String? {
        let success = await withCheckedContinuation { continuation in
            store.persistSnapshot { continuation.resume(returning: $0) }
        }
        return success ? store.sessionId.uuidString : nil
    }

    private static func persist(_ store: TennisSessionStore) async -> String? {
        let success = await withCheckedContinuation { continuation in
            store.persistSnapshot { continuation.resume(returning: $0) }
        }
        return success ? store.sessionId.uuidString : nil
    }

    private static func persist(_ store: BasketballSessionStore) async -> String? {
        let success = await withCheckedContinuation { continuation in
            store.persistSnapshot { continuation.resume(returning: $0) }
        }
        return success ? store.sessionId.uuidString : nil
    }

    private static func persist<Reducer>(
        _ store: BilliardsSessionStore<Reducer>
    ) async -> String? where Reducer: DomainReducer, Reducer.State: Equatable {
        let success = await withCheckedContinuation { continuation in
            store.persistSnapshot { continuation.resume(returning: $0) }
        }
        return success ? store.sessionId.uuidString : nil
    }

    private static func persistManualRecord(
        gameType: GameType,
        scoreCoreGameType: ScoreCore.GameType,
        leftName: String,
        rightName: String,
        snapshot: Data,
        configuration: [String: AnyCodable]
    ) -> String? {
        let id = UUID().uuidString
        var resolvedConfiguration = configuration
        resolvedConfiguration[ScoreboardRecordConfiguration.Key.scoreCoreGameType] =
            AnyCodable(scoreCoreGameType.rawValue)
        let record = ScoreboardRecord(
            id: id,
            gameType: gameType,
            startTime: Date(),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: 0,
            team2FinalScore: 0,
            totalScoreChanges: 0,
            projectConfiguration: resolvedConfiguration,
            stateSnapshot: snapshot,
            status: .draft
        )
        do {
            try ScoreboardLifecyclePersistence.save(record, finished: false)
            return id
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "Failed to persist scheduled booking start \(id)"
            )
            return nil
        }
    }

    private static func resolvedNames(
        for gameType: GameType,
        setup: SportsSetupResult,
        isSingles: Bool = true
    ) -> (left: String, right: String) {
        let defaults = DefaultParticipantNames.resolve(for: gameType, isSingles: isSingles)
        return (
            clean(setup.team1Name) ?? defaults.left,
            clean(setup.team2Name) ?? defaults.right
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func teamParticipants(left: String, right: String) -> [SessionParticipant] {
        [
            .init(id: TeamID.team0.rawValue, name: left, role: "team"),
            .init(id: TeamID.team1.rawValue, name: right, role: "team")
        ]
    }
}
