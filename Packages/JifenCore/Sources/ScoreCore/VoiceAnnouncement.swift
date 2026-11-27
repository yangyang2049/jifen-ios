import Foundation

// MARK: - Models

public enum VoiceAnnouncementPhase: String, Sendable {
    case opening
    case scoreChange = "score_change"
    case gameEnd = "game_end"
    case setEnd = "set_end"
    case matchEnd = "match_end"
    case sideChange = "side_change"
    case breakStart = "break_start"
    case breakWarning = "break_warning"
    case breakResume = "break_resume"
}

public enum VoiceCriticalPoint: String, Sendable {
    case gamePoint = "game_point"
    case matchPoint = "match_point"
    case gameBall = "game_ball"
    case matchBall = "match_ball"
}

public enum VoiceBreakCue: String, Sendable {
    case twentySeconds = "twenty_seconds"
    case halfTime = "half_time"
    case fifteenSeconds = "fifteen_seconds"
    case time
}

public struct VoiceSetScore: Codable, Equatable, Sendable {
    public var leftGames: Int
    public var rightGames: Int

    public init(leftGames: Int, rightGames: Int) {
        self.leftGames = leftGames
        self.rightGames = rightGames
    }

    public func swapped() -> VoiceSetScore {
        VoiceSetScore(leftGames: rightGames, rightGames: leftGames)
    }
}

public struct VoiceAnnouncementPayload: Equatable, Sendable {
    public var gameType: GameType
    public var phase: VoiceAnnouncementPhase
    public var leftTeamName: String
    public var rightTeamName: String
    public var leftScore: Int
    public var rightScore: Int
    public var leftSets: Int
    public var rightSets: Int
    public var currentSet: Int?
    public var scoringSide: MatchSide?
    public var serverSide: MatchSide?
    public var winnerSide: MatchSide?
    public var winnerName: String?
    public var serverName: String?
    public var receiverName: String?
    public var leftPlayerNames: [String]
    public var rightPlayerNames: [String]
    public var serviceOver: Bool
    public var criticalPoint: VoiceCriticalPoint?
    public var isInterval: Bool
    public var isManualEnd: Bool
    public var isTieBreak: Bool
    public var tieBreakTarget: Int?
    public var tennisDeuceMode: String?
    public var setScores: [VoiceSetScore]
    /// Pickleball doubles server number (1 or 2). Nil for singles / other sports.
    public var serverNumber: Int?
    public var sideChange: Bool
    public var breakCue: VoiceBreakCue?
    public var breakDurationSeconds: Int?
    public var secondServer: Bool
    public var starPointReturnedAdvantages: Int
    public var maxSets: Int?
    /// The reducer normalizes a lost advantage back to 3:3. Preserve that
    /// transition for calls such as French "égalité" and soft-tennis "deuce again".
    public var returnedToDeuce: Bool

    public init(
        gameType: GameType,
        phase: VoiceAnnouncementPhase,
        leftTeamName: String,
        rightTeamName: String,
        leftScore: Int,
        rightScore: Int,
        leftSets: Int = 0,
        rightSets: Int = 0,
        currentSet: Int? = nil,
        scoringSide: MatchSide? = nil,
        serverSide: MatchSide? = nil,
        winnerSide: MatchSide? = nil,
        winnerName: String? = nil,
        serverName: String? = nil,
        receiverName: String? = nil,
        leftPlayerNames: [String] = [],
        rightPlayerNames: [String] = [],
        serviceOver: Bool = false,
        criticalPoint: VoiceCriticalPoint? = nil,
        isInterval: Bool = false,
        isManualEnd: Bool = false,
        isTieBreak: Bool = false,
        tieBreakTarget: Int? = nil,
        tennisDeuceMode: String? = nil,
        setScores: [VoiceSetScore] = [],
        serverNumber: Int? = nil,
        sideChange: Bool = false,
        breakCue: VoiceBreakCue? = nil,
        breakDurationSeconds: Int? = nil,
        secondServer: Bool = false,
        starPointReturnedAdvantages: Int = 0,
        maxSets: Int? = nil,
        returnedToDeuce: Bool = false
    ) {
        self.gameType = gameType
        self.phase = phase
        self.leftTeamName = leftTeamName
        self.rightTeamName = rightTeamName
        self.leftScore = leftScore
        self.rightScore = rightScore
        self.leftSets = leftSets
        self.rightSets = rightSets
        self.currentSet = currentSet
        self.scoringSide = scoringSide
        self.serverSide = serverSide
        self.winnerSide = winnerSide
        self.winnerName = winnerName
        self.serverName = serverName
        self.receiverName = receiverName
        self.leftPlayerNames = leftPlayerNames
        self.rightPlayerNames = rightPlayerNames
        self.serviceOver = serviceOver
        self.criticalPoint = criticalPoint
        self.isInterval = isInterval
        self.isManualEnd = isManualEnd
        self.isTieBreak = isTieBreak
        self.tieBreakTarget = tieBreakTarget
        self.tennisDeuceMode = tennisDeuceMode
        self.setScores = setScores
        self.serverNumber = serverNumber
        self.sideChange = sideChange
        self.breakCue = breakCue
        self.breakDurationSeconds = breakDurationSeconds
        self.secondServer = secondServer
        self.starPointReturnedAdvantages = starPointReturnedAdvantages
        self.maxSets = maxSets
        self.returnedToDeuce = returnedToDeuce
    }
}

/// Android 3.1 suppresses the pickleball-only start call for other sports and
/// avoids a second "Time" when tennis/padel have already called it at 30 s.
public enum OfficialBreakVoicePolicy {
    public static func shouldSpeak(gameType: GameType, cue: OfficialBreakCue) -> Bool {
        if cue == .start {
            return gameType == .pickleball || gameType == .pickleballDoubles
        }
        if cue == .complete {
            return gameType != .tennis && gameType != .tennisDoubles && gameType != .padel
        }
        return true
    }

    public static func shouldSpeak(
        gameType: GameType,
        cue: OfficialBreakCue,
        state: OfficialBreakState,
        officialBreaksEnabled: Bool
    ) -> Bool {
        guard officialBreaksEnabled, state.source == .official else { return false }
        return shouldSpeak(gameType: gameType, cue: cue)
    }
}

public enum OfficialBreakVoiceMapper {
    public static func payload(
        gameType: GameType,
        cue: OfficialBreakCue,
        state: OfficialBreakState,
        leftName: String,
        rightName: String,
        leftScore: Int,
        rightScore: Int,
        servingSide: MatchSide?,
        serverName: String? = nil,
        serverNumber: Int? = nil,
        currentSet: Int? = nil
    ) -> VoiceAnnouncementPayload? {
        guard OfficialBreakVoicePolicy.shouldSpeak(
            gameType: gameType,
            cue: cue,
            state: state,
            officialBreaksEnabled: true
        ) else {
            return nil
        }
        let phase: VoiceAnnouncementPhase = switch cue {
        case .start: .breakStart
        case .complete, .earlyResume: .breakResume
        case .twentySeconds, .halfTime, .fifteenSeconds, .time: .breakWarning
        }
        let breakCue: VoiceBreakCue? = switch cue {
        case .twentySeconds: .twentySeconds
        case .halfTime: .halfTime
        case .fifteenSeconds: .fifteenSeconds
        case .time: .time
        case .start, .complete, .earlyResume: nil
        }
        return VoiceAnnouncementPayload(
            gameType: gameType,
            phase: phase,
            leftTeamName: leftName,
            rightTeamName: rightName,
            leftScore: leftScore,
            rightScore: rightScore,
            currentSet: currentSet,
            serverSide: servingSide,
            serverName: serverName,
            serverNumber: serverNumber,
            sideChange: state.afterAction == .exchangeSides || state.afterAction == .advanceAndExchange,
            breakCue: breakCue,
            breakDurationSeconds: state.durationSeconds
        )
    }
}

public enum VoiceAnnouncementSupport {
    public static func isSupported(_ gameType: GameType) -> Bool {
        isBadminton(gameType) || isPingpong(gameType) || isTennisFamily(gameType)
            || isPickleball(gameType) || isVolleyball(gameType)
            || gameType == .squash || gameType == .shuttlecock
    }

    public static func isBadminton(_ gameType: GameType) -> Bool {
        gameType == .badminton || gameType == .badmintonDoubles
    }

    public static func isPingpong(_ gameType: GameType) -> Bool {
        gameType == .pingpong || gameType == .pingpongDoubles
    }

    public static func isTennis(_ gameType: GameType) -> Bool {
        gameType == .tennis || gameType == .tennisDoubles
    }

    public static func isTennisFamily(_ gameType: GameType) -> Bool {
        isTennis(gameType) || gameType == .softTennis || gameType == .padel
    }

    public static func isPickleball(_ gameType: GameType) -> Bool {
        gameType == .pickleball || gameType == .pickleballDoubles
    }

    public static func isVolleyball(_ gameType: GameType) -> Bool {
        gameType == .volleyball || gameType == .beachVolleyball || gameType == .airVolleyball
    }
}

/// Pure scheduling policy shared by the platform announcer and tests.
public enum VoiceAnnouncementBatchPolicy {
    public static func shouldDebounce(_ payloads: [VoiceAnnouncementPayload]) -> Bool {
        guard payloads.count == 1, let payload = payloads.first else { return false }
        return payload.phase == .scoreChange
            && payload.criticalPoint == nil
            && !payload.isInterval
            && !payload.serviceOver
    }

    public static func queuePolicy(_ payloads: [VoiceAnnouncementPayload]) -> VoiceAnnouncementQueuePolicy {
        guard payloads.count == 1, let payload = payloads.first else { return .flush }
        switch payload.phase {
        case .opening, .scoreChange:
            return .latestScore
        case .sideChange, .breakStart, .breakWarning:
            return .append
        case .gameEnd, .setEnd, .matchEnd, .breakResume:
            return .flush
        }
    }
}

public enum VoiceAnnouncementQueuePolicy: Equatable, Sendable {
    case latestScore
    case flush
    case append
}

// MARK: - Rally event → payloads (aligned with Android VoiceAnnouncementEventMapper)

public enum RallyVoiceAnnouncementMapper {
    public static func payloads(
        gameType: GameType,
        before: RallyMatchState,
        after: RallyMatchState,
        events: [RallyMatchEvent],
        completedSetScores: [VoiceSetScore]
    ) -> [VoiceAnnouncementPayload] {
        let isRallyVoice = VoiceAnnouncementSupport.isBadminton(gameType)
            || VoiceAnnouncementSupport.isPingpong(gameType)
            || VoiceAnnouncementSupport.isPickleball(gameType)
            || VoiceAnnouncementSupport.isVolleyball(gameType)
            || gameType == .squash
            || gameType == .shuttlecock
        guard VoiceAnnouncementSupport.isSupported(gameType), isRallyVoice else {
            return []
        }

        let point = events.compactMap { event -> (MatchSide, Int, Int)? in
            if case let .pointScored(side, left, right) = event {
                return (side, left, right)
            }
            return nil
        }.last

        let sideOut = events.compactMap { event -> (MatchSide, Int, Int)? in
            if case let .sideOut(servingSide, left, right) = event {
                return (servingSide, left, right)
            }
            return nil
        }.last

        let setEnd = events.compactMap { event -> (MatchSide, Int, Int, Int, Int, Int)? in
            if case let .setCompleted(winner, setNumber, leftPoints, rightPoints, leftSets, rightSets) = event {
                return (winner, setNumber, leftPoints, rightPoints, leftSets, rightSets)
            }
            return nil
        }.last

        let matchFinished = events.contains {
            if case .matchFinished = $0 { return true }
            return false
        }
        var matchWinner: MatchSide?
        for event in events {
            if case let .matchFinished(winner) = event { matchWinner = winner }
        }
        let sideChanged = events.contains {
            if case .sidesExchanged = $0 { return true }
            return false
        }
        let sideReminder = events.contains {
            if case .sidesExchangeReminder = $0 { return true }
            return false
        }

        // Manual exchange-only intent.
        if point == nil, sideOut == nil, setEnd == nil, !matchFinished {
            if sideChanged || sideReminder {
                return [sideChangePayload(gameType: gameType, state: after)]
            }
            return []
        }

        // Manual finish. A tied score intentionally has no inferred winner.
        if point == nil, sideOut == nil, setEnd == nil, matchFinished {
            return [basePayload(
                gameType: gameType,
                phase: .matchEnd,
                state: after,
                leftScore: after.leftPoints,
                rightScore: after.rightPoints,
                leftSets: after.leftSets,
                rightSets: after.rightSets,
                currentSet: after.currentSet,
                winnerSide: matchWinner,
                isManualEnd: true,
                setScores: completedSetScores,
                serverNumber: pickleballServerNumber(gameType: gameType, state: after)
            )]
        }

        // Traditional pickleball side-out (no point scored).
        if point == nil, let sideOut, setEnd == nil, !matchFinished {
            let useRally = after.rules.useRallyScoring
            let secondServer = gameType == .pickleballDoubles
                && before.servingSide == after.servingSide
                && before.doubles?.pickleballServerNumber == 1
                && after.doubles?.pickleballServerNumber == 2
            return [
                basePayload(
                    gameType: gameType,
                    phase: .scoreChange,
                    state: after,
                    leftScore: sideOut.1,
                    rightScore: sideOut.2,
                    leftSets: after.leftSets,
                    rightSets: after.rightSets,
                    serverSide: sideOut.0,
                    serviceOver: !useRally && !secondServer,
                    secondServer: secondServer,
                    serverNumber: pickleballServerNumber(gameType: gameType, state: after)
                )
            ]
        }

        guard let point else { return [] }

        let namesState = after
        let servingSideAfterPoint = after.servingSide
        let serviceOver: Bool = {
            if VoiceAnnouncementSupport.isPingpong(gameType) {
                return before.servingSide != servingSideAfterPoint
            }
            if VoiceAnnouncementSupport.isBadminton(gameType) {
                return before.servingSide != point.0
            }
            if VoiceAnnouncementSupport.isVolleyball(gameType) {
                return before.servingSide != point.0
            }
            // Pickleball traditional: only server scores — serviceOver only on sideOut path.
            return false
        }()

        let leftAtEnd = setEnd?.2 ?? point.1
        let rightAtEnd = setEnd?.3 ?? point.2
        let serverNumber = pickleballServerNumber(gameType: gameType, state: after)

        let main: VoiceAnnouncementPayload
        if matchFinished, let setEnd {
            main = basePayload(
                gameType: gameType,
                phase: .matchEnd,
                state: namesState,
                leftScore: leftAtEnd,
                rightScore: rightAtEnd,
                leftSets: setEnd.4,
                rightSets: setEnd.5,
                currentSet: setEnd.1,
                winnerSide: setEnd.0,
                setScores: completedSetScores,
                serverNumber: serverNumber
            )
        } else if let setEnd {
            main = basePayload(
                gameType: gameType,
                phase: .setEnd,
                state: namesState,
                leftScore: leftAtEnd,
                rightScore: rightAtEnd,
                leftSets: setEnd.4,
                rightSets: setEnd.5,
                currentSet: setEnd.1,
                winnerSide: setEnd.0,
                setScores: completedSetScores,
                serverNumber: serverNumber
            )
        } else {
            main = basePayload(
                gameType: gameType,
                phase: .scoreChange,
                state: namesState,
                leftScore: point.1,
                rightScore: point.2,
                leftSets: before.leftSets,
                rightSets: before.rightSets,
                scoringSide: point.0,
                serverSide: servingSideAfterPoint,
                serviceOver: serviceOver,
                criticalPoint: rallyCriticalPoint(
                    gameType: gameType,
                    state: before,
                    leftScore: point.1,
                    rightScore: point.2
                ),
                isInterval: badmintonIntervalReached(
                    gameType: gameType,
                    before: before,
                    leftScore: point.1,
                    rightScore: point.2
                ),
                serverNumber: serverNumber
            )
        }

        var result = [main]
        if (sideChanged || sideReminder), !matchFinished {
            result.append(sideChangePayload(gameType: gameType, state: after))
        }
        return result
    }

    public static func openingPayload(gameType: GameType, state: RallyMatchState) -> VoiceAnnouncementPayload? {
        guard state.leftPoints == 0,
              state.rightPoints == 0,
              state.leftSets == 0,
              state.rightSets == 0,
              !state.finished
        else {
            return nil
        }
        return basePayload(
            gameType: gameType,
            phase: .opening,
            state: state,
            leftScore: 0,
            rightScore: 0,
            leftSets: 0,
            rightSets: 0,
            serverSide: state.servingSide,
            serverNumber: pickleballServerNumber(gameType: gameType, state: state)
        )
    }

    private static func pickleballServerNumber(
        gameType: GameType,
        state: RallyMatchState
    ) -> Int? {
        guard VoiceAnnouncementSupport.isPickleball(gameType),
              !state.rules.useRallyScoring else {
            return nil
        }
        return state.doubles?.pickleballServerNumber
            ?? (gameType == .pickleballDoubles ? 2 : nil)
    }

    private static func sideChangePayload(gameType: GameType, state: RallyMatchState) -> VoiceAnnouncementPayload {
        basePayload(
            gameType: gameType,
            phase: .sideChange,
            state: state,
            leftScore: state.leftPoints,
            rightScore: state.rightPoints,
            leftSets: state.leftSets,
            rightSets: state.rightSets
        )
    }

    private static func basePayload(
        gameType: GameType,
        phase: VoiceAnnouncementPhase,
        state: RallyMatchState,
        leftScore: Int,
        rightScore: Int,
        leftSets: Int,
        rightSets: Int,
        currentSet: Int? = nil,
        scoringSide: MatchSide? = nil,
        serverSide: MatchSide? = nil,
        winnerSide: MatchSide? = nil,
        serviceOver: Bool = false,
        criticalPoint: VoiceCriticalPoint? = nil,
        isInterval: Bool = false,
        isManualEnd: Bool = false,
        setScores: [VoiceSetScore] = [],
        secondServer: Bool = false,
        serverNumber: Int? = nil
    ) -> VoiceAnnouncementPayload {
        let leftPlayers = teamPlayerNames(state.doubles, side: .left)
        let rightPlayers = teamPlayerNames(state.doubles, side: .right)
        let serverName = state.doubles?.serverName
            ?? serverSide.map { $0 == .left ? state.leftName : state.rightName }
        return VoiceAnnouncementPayload(
            gameType: gameType,
            phase: phase,
            leftTeamName: state.leftName,
            rightTeamName: state.rightName,
            leftScore: leftScore,
            rightScore: rightScore,
            leftSets: leftSets,
            rightSets: rightSets,
            currentSet: currentSet,
            scoringSide: scoringSide,
            serverSide: serverSide,
            winnerSide: winnerSide,
            serverName: serverName,
            receiverName: state.doubles?.receiverName,
            leftPlayerNames: leftPlayers,
            rightPlayerNames: rightPlayers,
            serviceOver: serviceOver,
            criticalPoint: criticalPoint,
            isInterval: isInterval,
            isManualEnd: isManualEnd,
            setScores: setScores,
            serverNumber: serverNumber,
            secondServer: secondServer,
            maxSets: state.rules.maxSets
        )
    }

    private static func teamPlayerNames(_ doubles: RallyDoublesState?, side: MatchSide) -> [String] {
        guard let names = doubles?.playerNames, names.count >= 4 else { return [] }
        let indices = side == .left ? [0, 2] : [1, 3]
        return indices.map { names[$0] }.filter { !$0.isEmpty }
    }

    private static func rallyCriticalPoint(
        gameType: GameType,
        state: RallyMatchState,
        leftScore: Int,
        rightScore: Int
    ) -> VoiceCriticalPoint? {
        guard (VoiceAnnouncementSupport.isBadminton(gameType) || gameType == .squash),
              leftScore != rightScore else { return nil }
        let leaderSide: MatchSide = leftScore > rightScore ? .left : .right
        let leaderScore = max(leftScore, rightScore)
        let trailingScore = min(leftScore, rightScore)
        let setNumber = state.currentSet
        let nextLeaderScore = leaderScore + 1
        let winsAtCap = state.rules.pointCap(for: setNumber).map { nextLeaderScore >= $0 } ?? false
        let reachesTarget = nextLeaderScore >= state.rules.target(for: setNumber)
        let hasWinningMargin = !state.rules.usesWinByTwo(for: setNumber)
            || nextLeaderScore - trailingScore >= 2
        guard winsAtCap || (reachesTarget && hasWinningMargin) else { return nil }
        let nextLeftSets = state.leftSets + (leaderSide == .left ? 1 : 0)
        let nextRightSets = state.rightSets + (leaderSide == .right ? 1 : 0)
        let isMatch = state.rules.isMatchFinished(leftSets: nextLeftSets, rightSets: nextRightSets)
        if gameType == .squash {
            return isMatch ? .matchBall : .gameBall
        }
        return isMatch ? .matchPoint : .gamePoint
    }

    private static func badmintonIntervalReached(
        gameType: GameType,
        before: RallyMatchState,
        leftScore: Int,
        rightScore: Int
    ) -> Bool {
        guard VoiceAnnouncementSupport.isBadminton(gameType) else { return false }
        let interval = max(1, (before.rules.target(for: before.currentSet) + 1) / 2)
        return max(before.leftPoints, before.rightPoints) < interval
            && max(leftScore, rightScore) == interval
    }
}

// MARK: - Tennis event → payloads (aligned with Android VoiceAnnouncementEventMapper.tennisPayloads)

public enum TennisVoiceAnnouncementMapper {
    public static func payloads(
        gameType: GameType,
        before: TennisMatchState,
        after: TennisMatchState,
        intent: TennisMatchIntent,
        events: [TennisMatchEvent],
        completedSetScores: [VoiceSetScore]
    ) -> [VoiceAnnouncementPayload] {
        guard VoiceAnnouncementSupport.isTennisFamily(gameType) else {
            return []
        }

        let point = events.compactMap { event -> (MatchSide, Int, Int)? in
            if case let .pointScored(side, left, right) = event { return (side, left, right) }
            return nil
        }.last
        let gameEnd = events.compactMap { event -> (MatchSide, Int, Int, Bool)? in
            if case let .gameCompleted(winner, leftGames, rightGames, tieBreak) = event {
                return (winner, leftGames, rightGames, tieBreak)
            }
            return nil
        }.last
        let setEnd = events.compactMap { event -> (MatchSide, Int, Int, Int, Int, Int)? in
            if case let .setCompleted(winner, setNumber, leftGames, rightGames, leftSets, rightSets) = event {
                return (winner, setNumber, leftGames, rightGames, leftSets, rightSets)
            }
            return nil
        }.last
        var matchEnd: MatchSide?
        for event in events {
            if case let .matchFinished(winner) = event { matchEnd = winner }
        }
        let matchFinished = events.contains {
            if case .matchFinished = $0 { return true }
            return false
        }
        let sideChanged = events.contains {
            if case .sidesExchanged = $0 { return true }
            return false
        }
        let sideReminder = events.contains {
            if case .sidesExchangeReminder = $0 { return true }
            return false
        }

        // Manual exchange and finish produce no point/game event but still need speech.
        if point == nil, gameEnd == nil, setEnd == nil, !matchFinished {
            if sideChanged || sideReminder {
                return [basePayload(
                    gameType: gameType,
                    phase: .sideChange,
                    state: after,
                    leftScore: after.leftPoints,
                    rightScore: after.rightPoints,
                    leftSets: after.leftSets,
                    rightSets: after.rightSets
                )]
            }
            return []
        }

        if point == nil, gameEnd == nil, setEnd == nil, matchFinished {
            return [basePayload(
                gameType: gameType,
                phase: .matchEnd,
                state: after,
                leftScore: after.rules.setScoringMode == .tiebreakOnly ? after.leftPoints : after.leftGames,
                rightScore: after.rules.setScoringMode == .tiebreakOnly ? after.rightPoints : after.rightGames,
                leftSets: after.leftSets,
                rightSets: after.rightSets,
                currentSet: after.currentSet,
                winnerSide: matchEnd,
                isManualEnd: true,
                isTieBreak: after.rules.setScoringMode == .tiebreakOnly,
                tieBreakTarget: after.rules.tieBreakPoints,
                tennisDeuceMode: before.rules.usesNoAdScoring ? "no_ad" : "advantage",
                setScores: completedSetScores
            )]
        }

        let namesState = after
        let servingSideAfterPoint = after.servingSide
        let deuceMode = before.rules.familyProfile == .padel
            ? before.rules.padelDeuceMode.rawValue
            : (before.rules.usesNoAdScoring ? "no_ad" : "advantage")

        var main: VoiceAnnouncementPayload
        if matchFinished {
            let leftScore = setEnd?.2 ?? gameEnd?.1 ?? point?.1 ?? after.leftPoints
            let rightScore = setEnd?.3 ?? gameEnd?.2 ?? point?.2 ?? after.rightPoints
            let leftSets = setEnd?.4 ?? after.leftSets
            let rightSets = setEnd?.5 ?? after.rightSets
            let winner = setEnd?.0 ?? matchEnd ?? winnerByScore(left: leftSets, right: rightSets)
            main = basePayload(
                gameType: gameType,
                phase: .matchEnd,
                state: namesState,
                leftScore: leftScore,
                rightScore: rightScore,
                leftSets: leftSets,
                rightSets: rightSets,
                currentSet: setEnd?.1,
                winnerSide: winner,
                isTieBreak: before.rules.setScoringMode == .tiebreakOnly,
                tieBreakTarget: before.rules.tieBreakPoints,
                tennisDeuceMode: deuceMode,
                setScores: completedSetScores
            )
        } else if let setEnd {
            main = basePayload(
                gameType: gameType,
                phase: .setEnd,
                state: namesState,
                leftScore: setEnd.2,
                rightScore: setEnd.3,
                leftSets: setEnd.4,
                rightSets: setEnd.5,
                currentSet: setEnd.1,
                winnerSide: setEnd.0,
                isTieBreak: gameEnd?.3 == true,
                tieBreakTarget: before.rules.tieBreakPoints,
                tennisDeuceMode: deuceMode,
                setScores: completedSetScores
            )
        } else if let gameEnd {
            let winner = point?.0 ?? winnerByScore(left: gameEnd.1, right: gameEnd.2)
            main = basePayload(
                gameType: gameType,
                phase: .gameEnd,
                state: namesState,
                leftScore: gameEnd.1,
                rightScore: gameEnd.2,
                leftSets: before.leftSets,
                rightSets: before.rightSets,
                currentSet: before.leftSets + before.rightSets + 1,
                winnerSide: winner,
                // Entering a tie-break is represented by the resulting state (4-4 or 6-6).
                isTieBreak: after.isTieBreak,
                tieBreakTarget: before.rules.tieBreakPoints,
                tennisDeuceMode: deuceMode
            )
        } else if let point {
            main = basePayload(
                gameType: gameType,
                phase: .scoreChange,
                state: namesState,
                leftScore: point.1,
                rightScore: point.2,
                leftSets: before.leftSets,
                rightSets: before.rightSets,
                scoringSide: point.0,
                serverSide: servingSideAfterPoint,
                isTieBreak: before.isTieBreak,
                tieBreakTarget: before.rules.tieBreakPoints,
                tennisDeuceMode: deuceMode
            )
        } else {
            return []
        }

        if main.phase == .scoreChange, !before.isTieBreak,
           main.leftScore == 3, main.rightScore == 3,
           max(before.leftPoints, before.rightPoints) == 4,
           min(before.leftPoints, before.rightPoints) == 3 {
            main.returnedToDeuce = true
        }
        var result = [main]
        if (sideChanged || sideReminder), !matchFinished {
            result.append(
                basePayload(
                    gameType: gameType,
                    phase: .sideChange,
                    state: namesState,
                    leftScore: namesState.leftPoints,
                    rightScore: namesState.rightPoints,
                    leftSets: namesState.leftSets,
                    rightSets: namesState.rightSets
                )
            )
        }
        return result
    }

    public static func openingPayload(
        gameType: GameType,
        state: TennisMatchState
    ) -> VoiceAnnouncementPayload? {
        guard VoiceAnnouncementSupport.isTennisFamily(gameType),
              state.leftPoints == 0,
              state.rightPoints == 0,
              state.leftGames == 0,
              state.rightGames == 0,
              state.leftSets == 0,
              state.rightSets == 0,
              !state.finished
        else { return nil }
        return basePayload(
            gameType: gameType,
            phase: .opening,
            state: state,
            leftScore: 0,
            rightScore: 0,
            leftSets: 0,
            rightSets: 0,
            serverSide: state.servingSide,
            isTieBreak: state.rules.setScoringMode == .tiebreakOnly,
            tieBreakTarget: state.rules.tieBreakPoints
        )
    }

    private static func winnerByScore(left: Int, right: Int) -> MatchSide? {
        if left > right { return .left }
        if right > left { return .right }
        return nil
    }

    private static func basePayload(
        gameType: GameType,
        phase: VoiceAnnouncementPhase,
        state: TennisMatchState,
        leftScore: Int,
        rightScore: Int,
        leftSets: Int,
        rightSets: Int,
        currentSet: Int? = nil,
        scoringSide: MatchSide? = nil,
        serverSide: MatchSide? = nil,
        winnerSide: MatchSide? = nil,
        isManualEnd: Bool = false,
        isTieBreak: Bool = false,
        tieBreakTarget: Int? = nil,
        tennisDeuceMode: String? = nil,
        setScores: [VoiceSetScore] = []
    ) -> VoiceAnnouncementPayload {
        let leftPlayers = tennisTeamPlayerNames(state, side: .left)
        let rightPlayers = tennisTeamPlayerNames(state, side: .right)
        let serverName: String? = {
            if let names = state.doublesPlayerNames,
               let slot = TennisDoublesServing.currentServerSlot(in: state),
               names.indices.contains(slot), !names[slot].isEmpty {
                return names[slot]
            }
            guard let serverSide else { return nil }
            return serverSide == .left ? state.leftName : state.rightName
        }()
        return VoiceAnnouncementPayload(
            gameType: gameType,
            phase: phase,
            leftTeamName: state.leftName,
            rightTeamName: state.rightName,
            leftScore: leftScore,
            rightScore: rightScore,
            leftSets: leftSets,
            rightSets: rightSets,
            currentSet: currentSet,
            scoringSide: scoringSide,
            serverSide: serverSide,
            winnerSide: winnerSide,
            serverName: serverName,
            leftPlayerNames: leftPlayers,
            rightPlayerNames: rightPlayers,
            isManualEnd: isManualEnd,
            isTieBreak: isTieBreak,
            tieBreakTarget: tieBreakTarget,
            tennisDeuceMode: tennisDeuceMode,
            setScores: setScores,
            starPointReturnedAdvantages: state.starPointReturnedAdvantages ?? 0,
            maxSets: state.rules.familyProfile == .softTennis
                ? state.rules.softTennisMatchGames
                : state.rules.maxSets
        )
    }

    private static func tennisTeamPlayerNames(_ state: TennisMatchState, side: MatchSide) -> [String] {
        guard let names = state.doublesPlayerNames, names.count >= 4 else { return [] }
        let indices = side == .left ? [0, 2] : [1, 3]
        return indices.map { names[$0] }.filter { !$0.isEmpty }
    }
}
