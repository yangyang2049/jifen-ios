import Foundation
import ScoreCore

public enum ScoreboardSessionFactory {
    public static func rally(
        gameType: GameType,
        leftName: String,
        rightName: String,
        rules: RallyRuleSet? = nil,
        openingServer: MatchSide = .left,
        doubles: RallyDoublesState? = nil
    ) -> ScoreSessionCore<RallyMatchReducer>? {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        guard descriptor.kind == .rally,
              let resolvedRules = rules ?? ScoreboardKernelRegistry.defaultRallyRules(for: gameType),
              isRallyRuleProfileCompatible(resolvedRules, gameType: gameType) else { return nil }
        let resolvedDoubles = resolvedRallyDoubles(
            gameType: gameType,
            supplied: doubles,
            openingServer: openingServer
        )
        guard !isRallyDoubles(gameType) || resolvedDoubles != nil else { return nil }
        let state = RallyMatchEngine.initial(
            leftName: leftName,
            rightName: rightName,
            rules: resolvedRules,
            openingServer: openingServer,
            doubles: resolvedDoubles
        )
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: resolvedDoubles.map(doublesParticipants) ?? participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: RallyMatchReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func tennis(
        gameType: GameType,
        leftName: String,
        rightName: String,
        rules: TennisRuleSet? = nil,
        openingServer: MatchSide = .left,
        doublesPlayerNames: [String]? = nil
    ) -> ScoreSessionCore<TennisMatchReducer>? {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        guard descriptor.kind == .tennis,
              let resolvedRules = rules ?? ScoreboardKernelRegistry.defaultTennisRules(for: gameType),
              isTennisRuleProfileCompatible(resolvedRules, gameType: gameType) else { return nil }
        let normalizedDoublesNames = gameType == .tennisDoubles
            ? normalizedDoublesPlayerNames(doublesPlayerNames)
            : nil
        let state = TennisMatchState(
            leftName: leftName,
            rightName: rightName,
            rules: resolvedRules,
            openingServer: openingServer,
            doublesPlayerNames: normalizedDoublesNames
        )
        let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: normalizedDoublesNames.map(doublesParticipants) ?? participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: TennisMatchReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func line(
        gameType: GameType,
        leftName: String,
        rightName: String,
        rules: LineScoreRuleSet? = nil
    ) -> ScoreSessionCore<LineScoreReducer>? {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        guard descriptor.kind == .line,
              let resolvedRules = rules ?? ScoreboardKernelRegistry.defaultLineRules(for: gameType) else { return nil }
        let state = LineScoreState(leftName: leftName, rightName: rightName, rules: resolvedRules)
        let session = ScoreSession<LineScoreState, LineScoreEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: LineScoreReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func boxing(
        leftName: String,
        rightName: String,
        maxRounds: Int = 3
    ) -> ScoreSessionCore<BoxingMatchReducer> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .boxing)
        let state = BoxingMatchState(leftName: leftName, rightName: rightName, maxRounds: maxRounds)
        let session = ScoreSession<BoxingMatchState, BoxingMatchEvent>(
            gameType: .boxing,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: BoxingMatchReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func archery(
        leftName: String,
        rightName: String,
        openingShooterIsLeft: Bool = true,
        rules: ArcheryMatchRules = .default
    ) -> ScoreSessionCore<ArcheryMatchReducer> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .archeryDual)
        let state = ArcheryMatchState(
            leftName: leftName,
            rightName: rightName,
            currentShooterIsLeft: openingShooterIsLeft,
            openingShooterIsLeft: openingShooterIsLeft,
            rules: rules
        )
        let session = ScoreSession<ArcheryMatchState, ArcheryMatchEvent>(
            gameType: .archeryDual,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: ArcheryMatchReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func basketball(
        gameType: GameType,
        leftName: String,
        rightName: String,
        ruleSet: BasketballRuleSet = .fiba
    ) -> ScoreSessionCore<BasketballMatchReducer>? {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        guard descriptor.kind == .basketball,
              gameType == .basketball || gameType == .threeBasketball else { return nil }
        let gameMode: BasketballGameMode = gameType == .basketball ? .fiveVFive : .threeXThree
        let state = BasketballMatchEngine.initial(
            leftName: leftName,
            rightName: rightName,
            gameMode: gameMode,
            ruleSet: ruleSet
        )
        let session = ScoreSession<BasketballMatchState, BasketballMatchEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(
            seedSession: session,
            reducer: BasketballMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
    }

    public static func eightBall(
        leftName: String,
        rightName: String,
        targetPoints: Int = 9,
        handicapRacks: Int = 0,
        handicapBeneficiary: MatchSide? = nil
    ) -> ScoreSessionCore<EightBallReducer> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .eightBall)
        let state = EightBallState.initial(
            targetPoints: targetPoints,
            handicapRacks: handicapRacks,
            handicapBeneficiary: handicapBeneficiary
        )
        let session = ScoreSession<EightBallState, EightBallEvent>(
            gameType: .eightBall,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(
            seedSession: session,
            reducer: EightBallReducer(),
            shouldFinish: { _, state in state.finished }
        )
    }

    public static func nineBall(
        playerNames: [String],
        config: NineBallChaseConfig = .init()
    ) -> ScoreSessionCore<NineBallChaseReducer>? {
        guard (2 ... 4).contains(playerNames.count) else { return nil }
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .nineBall)
        let state = NineBallChaseState.initial(
            config: config,
            playerCount: playerNames.count,
            playerNames: playerNames
        )
        let resolvedNames = (0 ..< state.playerCount).map {
            state.resolvedName(at: $0)
        }
        let session = ScoreSession<NineBallChaseState, NineBallChaseEvent>(
            gameType: .nineBall,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: playerParticipants(resolvedNames)
        )
        return ScoreSessionCore(
            seedSession: session,
            reducer: NineBallChaseReducer(),
            shouldFinish: { _, state in state.finished }
        )
    }

    public static func snooker(
        leftName: String,
        rightName: String,
        openingStriker: MatchSide = .left,
        maxFrames: Int = 1
    ) -> ScoreSessionCore<SnookerReducer> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .snooker)
        let state = SnookerState.initial(striker: openingStriker, maxFrames: maxFrames)
        let session = ScoreSession<SnookerState, SnookerEvent>(
            gameType: .snooker,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(
            seedSession: session,
            reducer: SnookerReducer(),
            shouldFinish: { _, state in state.finished }
        )
    }

    public static func guandan(
        redName: String,
        blueName: String,
        aStageMode: GuandanAStageMode = .singleA,
        passACondition: GuandanPassACondition = .notLast,
        tripleAFallbackRank: String = "2"
    ) -> ScoreSessionCore<GuandanSessionReducer> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .guandan)
        let state = GuandanMatchState.initial(
            redName: redName,
            blueName: blueName,
            aStageMode: aStageMode,
            passACondition: passACondition,
            tripleAFallbackRank: tripleAFallbackRank
        )
        let session = ScoreSession<GuandanMatchState, GuandanSessionEvent>(
            gameType: .guandan,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(redName, blueName)
        )
        return ScoreSessionCore(
            seedSession: session,
            reducer: GuandanSessionReducer(),
            shouldFinish: { _, state in state.phase == .finished }
        )
    }

    public static func shengji(
        leftName: String,
        rightName: String,
        maxTierIndex: Int = 12,
        dealer: MatchSide? = nil
    ) -> ScoreSessionCore<ShengjiTierReducer> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .shengji)
        let state = ShengjiTierState(
            maxTierIndex: maxTierIndex,
            dealer: dealer
        )
        let session = ScoreSession<ShengjiTierState, ShengjiTierEvent>(
            gameType: .shengji,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(
            seedSession: session,
            reducer: ShengjiTierReducer(),
            shouldFinish: { _, state in state.finished }
        )
    }

    public static func doudizhu(
        playerNames: [String]
    ) -> ScoreSessionCore<DoudizhuScoreReducer>? {
        guard (3 ... 4).contains(playerNames.count) else { return nil }
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .doudizhu)
        let session = ScoreSession<DoudizhuScoreState, DoudizhuScoreEvent>(
            gameType: .doudizhu,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: DoudizhuScoreState(scores: Array(repeating: 0, count: playerNames.count)),
            participants: playerParticipants(playerNames)
        )
        return ScoreSessionCore(seedSession: session, reducer: DoudizhuScoreReducer())
    }

    public static func multiScoreboard(
        playerNames: [String],
        customAdjustEnabled: Bool = false,
        allowRemoveWhileHasScore: Bool = false
    ) -> ScoreSessionCore<MultiParticipantReducer>? {
        multiParticipant(
            gameType: .multiScoreboard,
            playerNames: playerNames,
            customAdjustEnabled: customAdjustEnabled,
            allowRemoveWhileHasScore: allowRemoveWhileHasScore
        )
    }

    public static func uno(
        playerNames: [String],
        targetScore: Int = 500
    ) -> ScoreSessionCore<MultiParticipantReducer>? {
        multiParticipant(
            gameType: .uno,
            playerNames: playerNames,
            targetScore: targetScore
        )
    }

    /// Shared S3 constructor used by UNO and the generic multi-scoreboard.
    /// Android keeps UNO target detection in its controller: the reducer accepts
    /// the round score first, then the controller dispatches `.finish` when the
    /// configured target is reached. The target therefore travels in metadata.
    public static func multiParticipant(
        gameType: GameType,
        playerNames: [String],
        targetScore: Int? = nil,
        customAdjustEnabled: Bool = false,
        allowRemoveWhileHasScore: Bool = false
    ) -> ScoreSessionCore<MultiParticipantReducer>? {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        let allowedCount: ClosedRange<Int>
        switch gameType {
        case .multiScoreboard:
            guard descriptor.kind == .multi, targetScore == nil else { return nil }
            allowedCount = 3 ... 9
        case .uno:
            guard descriptor.kind == .uno,
                  customAdjustEnabled == false,
                  (1 ... 99_999).contains(targetScore ?? 500) else { return nil }
            allowedCount = 2 ... 10
        default:
            return nil
        }
        guard allowedCount.contains(playerNames.count) else { return nil }

        let normalizedNames = normalizedPlayerNames(playerNames)
        let stateParticipants = normalizedNames.enumerated().map { index, name in
            MultiParticipant(id: "p\(index)", name: name)
        }
        let state = MultiParticipantState(
            participants: stateParticipants,
            allowRemoveWhileHasScore: allowRemoveWhileHasScore
        )
        var extras: [String: String] = [:]
        if gameType == .uno {
            extras["targetScore"] = String(targetScore ?? 500)
        } else {
            extras["customAdjustEnabled"] = String(customAdjustEnabled)
        }
        let session = ScoreSession<MultiParticipantState, MultiParticipantEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: stateParticipants.map {
                SessionParticipant(id: $0.id, name: $0.name, role: "player")
            },
            metadata: .init(extras: extras)
        )
        return ScoreSessionCore(
            seedSession: session,
            reducer: MultiParticipantReducer(),
            shouldFinish: { _, state in state.finished }
        )
    }

    private static func participants(_ left: String, _ right: String) -> [SessionParticipant] {
        [
            .init(id: TeamID.team0.rawValue, name: left, role: "team"),
            .init(id: TeamID.team1.rawValue, name: right, role: "team")
        ]
    }

    private static func playerParticipants(_ names: [String]) -> [SessionParticipant] {
        names.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return SessionParticipant(
                id: "player-\(index)",
                name: trimmed.isEmpty ? "P\(index + 1)" : trimmed,
                role: "player"
            )
        }
    }

    private static func normalizedPlayerNames(_ names: [String]) -> [String] {
        names.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "P\(index + 1)" : trimmed
        }
    }

    private static func doublesParticipants(_ names: [String]) -> [SessionParticipant] {
        let defaults = ["Player 1", "Player 3", "Player 2", "Player 4"]
        let ids = ["left-top", "right-top", "left-bottom", "right-bottom"]
        return ids.indices.map { index in
            let trimmed = names.indices.contains(index)
                ? names[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return SessionParticipant(
                id: ids[index],
                name: trimmed.isEmpty ? defaults[index] : trimmed,
                role: "player"
            )
        }
    }

    private static func doublesParticipants(_ doubles: RallyDoublesState) -> [SessionParticipant] {
        doublesParticipants(doubles.playerNames)
    }

    private static func isRallyDoubles(_ gameType: GameType) -> Bool {
        switch gameType {
        case .pingpongDoubles, .badmintonDoubles, .pickleballDoubles, .foosballDoubles:
            true
        default:
            false
        }
    }

    private static func isRallyRuleProfileCompatible(
        _ rules: RallyRuleSet,
        gameType: GameType
    ) -> Bool {
        let isPickleball = gameType == .pickleball || gameType == .pickleballDoubles
        return isPickleball == (rules.sportProfile == .pickleball)
    }

    private static func isTennisRuleProfileCompatible(
        _ rules: TennisRuleSet,
        gameType: GameType
    ) -> Bool {
        switch gameType {
        case .softTennis:
            rules.familyProfile == .softTennis
        case .padel:
            rules.familyProfile == .padel
        case .tennis, .tennisDoubles:
            rules.familyProfile == .tennis
        default:
            false
        }
    }

    private static func resolvedRallyDoubles(
        gameType: GameType,
        supplied: RallyDoublesState?,
        openingServer: MatchSide
    ) -> RallyDoublesState? {
        guard isRallyDoubles(gameType) else { return nil }
        if let supplied {
            switch (gameType, supplied.rotation) {
            case (.pingpongDoubles, .pingPong),
                 (.badmintonDoubles, .badminton),
                 (.pickleballDoubles, .pickleball),
                 (.foosballDoubles, .foosball):
                return supplied
            default:
                return nil
            }
        }
        let names = normalizedDoublesPlayerNames(nil)
        switch gameType {
        case .pingpongDoubles:
            return .pingPong(
                playerNames: names,
                openingServerSlotIndex: openingServer == .left ? 0 : 1,
                openingReceiverSlotIndex: openingServer == .left ? 1 : 0
            )
        case .badmintonDoubles:
            return .badminton(playerNames: names, servingTeam0: openingServer == .left)
        case .pickleballDoubles:
            return .pickleball(playerNames: names, servingTeam0: openingServer == .left)
        case .foosballDoubles:
            return .foosball(playerNames: names)
        default:
            return nil
        }
    }

    private static func normalizedDoublesPlayerNames(_ supplied: [String]?) -> [String] {
        let defaults = ["Player 1", "Player 3", "Player 2", "Player 4"]
        return defaults.indices.map { index in
            guard let supplied, supplied.indices.contains(index) else { return defaults[index] }
            let trimmed = supplied[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? defaults[index] : trimmed
        }
    }
}
