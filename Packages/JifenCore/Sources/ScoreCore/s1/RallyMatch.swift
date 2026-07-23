import Foundation

/// S1 dual-side rally family (= Android `S1DualSide*` / HOS per-sport rally reducers).
/// Geometric `left`/`right` scores are screen sides; team identity uses `TeamID` + `TeamScreenLayout`.

public enum MatchCompletionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case bestOf = "best_of"
    case playAll = "play_all"

    public func isMatchFinished(maxSets: Int, leftSets: Int, rightSets: Int) -> Bool {
        let normalizedMaxSets = max(1, maxSets)
        if self == .playAll {
            return leftSets + rightSets >= normalizedMaxSets
        }
        let setsToWin = (normalizedMaxSets + 1) / 2
        return leftSets >= setsToWin || rightSets >= setsToWin
    }

    public func allowsSetScore(maxSets: Int, leftSets: Int, rightSets: Int) -> Bool {
        let normalizedMaxSets = max(1, maxSets)
        guard leftSets >= 0, rightSets >= 0, leftSets + rightSets <= normalizedMaxSets else {
            return false
        }
        if self == .playAll {
            return true
        }
        guard normalizedMaxSets.isMultiple(of: 2) == false else { return false }
        let setsToWin = (normalizedMaxSets + 1) / 2
        return leftSets <= setsToWin && rightSets <= setsToWin
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .bestOf
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum RallyServingModel: String, Codable, Sendable {
    case scorerServes
    case pingPongTwoServes
}

/// Aligns with Android `PickleballNextSetServingModel`.
public enum RallyNextSetServerModel: String, Codable, Sendable {
    case scorerContinues
    case opening
    case alternateFromOpening
}

public struct RallyRuleSet: Codable, Equatable, Sendable {
    public var maxSets: Int
    public var pointsToWinSet: Int
    public var pointCap: Int?
    public var winByTwo: Bool
    /// Optional deciding-set override. Used by foosball where win-by-two and
    /// the score cap apply only to the final configured set.
    public var finalSetPointCap: Int?
    public var finalSetWinByTwo: Bool?
    public var finalSetPointsToWin: Int?
    public var decidingSetSideSwitchPoint: Int?
    public var sideSwitchEveryTotalPoints: Int?
    public var finalSetSideSwitchEveryTotalPoints: Int?
    public var autoChangeSides: Bool
    public var servingModel: RallyServingModel
    public var useRallyScoring: Bool
    public var matchCompletionMode: MatchCompletionMode
    /// Pickleball: singles `.opening`, doubles `.alternateFromOpening`.
    public var nextSetServerModel: RallyNextSetServerModel

    public init(
        maxSets: Int,
        pointsToWinSet: Int,
        pointCap: Int? = nil,
        winByTwo: Bool = true,
        finalSetPointCap: Int? = nil,
        finalSetWinByTwo: Bool? = nil,
        finalSetPointsToWin: Int? = nil,
        decidingSetSideSwitchPoint: Int? = nil,
        sideSwitchEveryTotalPoints: Int? = nil,
        finalSetSideSwitchEveryTotalPoints: Int? = nil,
        autoChangeSides: Bool = false,
        servingModel: RallyServingModel = .scorerServes,
        useRallyScoring: Bool = true,
        matchCompletionMode: MatchCompletionMode = .bestOf,
        nextSetServerModel: RallyNextSetServerModel = .scorerContinues
    ) {
        self.maxSets = max(1, maxSets)
        self.pointsToWinSet = max(1, pointsToWinSet)
        self.pointCap = pointCap
        self.winByTwo = winByTwo
        self.finalSetPointCap = finalSetPointCap
        self.finalSetWinByTwo = finalSetWinByTwo
        self.finalSetPointsToWin = finalSetPointsToWin
        self.decidingSetSideSwitchPoint = decidingSetSideSwitchPoint
        self.sideSwitchEveryTotalPoints = sideSwitchEveryTotalPoints
        self.finalSetSideSwitchEveryTotalPoints = finalSetSideSwitchEveryTotalPoints
        self.autoChangeSides = autoChangeSides
        self.servingModel = servingModel
        self.useRallyScoring = useRallyScoring
        self.matchCompletionMode = matchCompletionMode
        self.nextSetServerModel = nextSetServerModel
    }

    public var setsToWin: Int { (maxSets + 1) / 2 }

    public func isMatchFinished(leftSets: Int, rightSets: Int) -> Bool {
        matchCompletionMode.isMatchFinished(maxSets: maxSets, leftSets: leftSets, rightSets: rightSets)
    }

    private enum CodingKeys: String, CodingKey {
        case maxSets
        case pointsToWinSet
        case pointCap
        case winByTwo
        case finalSetPointCap
        case finalSetWinByTwo
        case finalSetPointsToWin
        case decidingSetSideSwitchPoint
        case sideSwitchEveryTotalPoints
        case finalSetSideSwitchEveryTotalPoints
        case autoChangeSides
        case servingModel
        case useRallyScoring
        case matchCompletionMode
        case nextSetServerModel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxSets = max(1, try container.decode(Int.self, forKey: .maxSets))
        pointsToWinSet = max(1, try container.decode(Int.self, forKey: .pointsToWinSet))
        pointCap = try container.decodeIfPresent(Int.self, forKey: .pointCap)
        winByTwo = try container.decode(Bool.self, forKey: .winByTwo)
        finalSetPointCap = try container.decodeIfPresent(Int.self, forKey: .finalSetPointCap)
        finalSetWinByTwo = try container.decodeIfPresent(Bool.self, forKey: .finalSetWinByTwo)
        finalSetPointsToWin = try container.decodeIfPresent(Int.self, forKey: .finalSetPointsToWin)
        decidingSetSideSwitchPoint = try container.decodeIfPresent(Int.self, forKey: .decidingSetSideSwitchPoint)
        sideSwitchEveryTotalPoints = try container.decodeIfPresent(Int.self, forKey: .sideSwitchEveryTotalPoints)
        finalSetSideSwitchEveryTotalPoints = try container.decodeIfPresent(Int.self, forKey: .finalSetSideSwitchEveryTotalPoints)
        autoChangeSides = try container.decode(Bool.self, forKey: .autoChangeSides)
        servingModel = try container.decode(RallyServingModel.self, forKey: .servingModel)
        useRallyScoring = try container.decodeIfPresent(Bool.self, forKey: .useRallyScoring) ?? true
        matchCompletionMode = try container.decodeIfPresent(MatchCompletionMode.self, forKey: .matchCompletionMode) ?? .bestOf
        nextSetServerModel = try container.decodeIfPresent(RallyNextSetServerModel.self, forKey: .nextSetServerModel) ?? .scorerContinues
    }

    public func target(for setNumber: Int) -> Int {
        setNumber == maxSets ? finalSetPointsToWin ?? pointsToWinSet : pointsToWinSet
    }

    /// Aligns with Android `resolveRallyDecidingSetSideSwitchPoint`:
    /// ping-pong uses `points/2` (11→5); badminton uses `(points+1)/2` (21→11).
    public static func decidingSetSideSwitchPoint(for gameType: GameType, pointsPerSet: Int) -> Int? {
        let points = max(1, pointsPerSet)
        switch gameType {
        case .pingpong, .pingpongDoubles:
            return max(1, points / 2)
        case .badminton, .badmintonDoubles:
            return max(1, (points + 1) / 2)
        default:
            return nil
        }
    }

    /// Aligns with Android/Harmony `resolveBadmintonPointCap`:
    /// target < 21 → cap 21; target == 21 → cap 30; target > 21 → no cap.
    public static func badmintonPointCap(for pointsPerSet: Int) -> Int? {
        let points = max(1, pointsPerSet)
        if points > 21 { return nil }
        if points < 21 { return 21 }
        return 30
    }

    public static func pingPong(maxSets: Int = 5, matchCompletionMode: MatchCompletionMode = .bestOf) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: 11,
            decidingSetSideSwitchPoint: decidingSetSideSwitchPoint(for: .pingpong, pointsPerSet: 11),
            servingModel: .pingPongTwoServes,
            matchCompletionMode: matchCompletionMode
        )
    }

    public static func badminton(maxSets: Int = 3, matchCompletionMode: MatchCompletionMode = .bestOf) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: 21,
            pointCap: badmintonPointCap(for: 21),
            decidingSetSideSwitchPoint: decidingSetSideSwitchPoint(for: .badminton, pointsPerSet: 21),
            matchCompletionMode: matchCompletionMode
        )
    }

    public static func pickleball(maxSets: Int = 3, matchCompletionMode: MatchCompletionMode = .bestOf) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: 11,
            pointCap: nil,
            useRallyScoring: false,
            matchCompletionMode: matchCompletionMode,
            nextSetServerModel: .opening
        )
    }

    public static func volleyball(maxSets: Int = 5) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: 25,
            finalSetPointsToWin: 15,
            decidingSetSideSwitchPoint: 8,
            nextSetServerModel: .alternateFromOpening
        )
    }

    public static func airVolleyball(maxSets: Int = 3) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: 21,
            finalSetPointsToWin: 15,
            decidingSetSideSwitchPoint: 8,
            nextSetServerModel: .alternateFromOpening
        )
    }

    public static func beachVolleyball(maxSets: Int = 3) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: 21,
            finalSetPointsToWin: 15,
            sideSwitchEveryTotalPoints: 7,
            finalSetSideSwitchEveryTotalPoints: 5,
            nextSetServerModel: .alternateFromOpening
        )
    }

    public static func foosball(maxSets: Int = 3) -> Self {
        .init(maxSets: maxSets, pointsToWinSet: 5, winByTwo: false)
    }
}

public struct RallyMatchState: Codable, Equatable, Sendable {
    public var rules: RallyRuleSet
    public var leftName: String
    public var rightName: String
    public var leftPoints: Int
    public var rightPoints: Int
    public var leftSets: Int
    public var rightSets: Int
    public var servingSide: MatchSide
    public var openingServerSide: MatchSide
    public var firstServerInSet: MatchSide
    public var finished: Bool
    public var sidesSwapped: Bool
    public var doubles: RallyDoublesState?

    public var currentSet: Int { leftSets + rightSets + 1 }
}

public enum RallyMatchIntent: Codable, Sendable {
    case pointWon(MatchSide)
    case setNames(left: String, right: String)
    case adjustPoints(side: MatchSide, delta: Int)
    case adjustSets(side: MatchSide, delta: Int)
    case setDoublesPlayerName(slot: Int, name: String)
    case exchangeSides
    case finish
    case reset
}

public enum RallyMatchEvent: Codable, Equatable, Sendable {
    case pointScored(side: MatchSide, leftPoints: Int, rightPoints: Int)
    /// Traditional pickleball side-out: serve changes without a point.
    case sideOut(servingSide: MatchSide, leftPoints: Int, rightPoints: Int)
    case setCompleted(winner: MatchSide, setNumber: Int, leftPoints: Int, rightPoints: Int, leftSets: Int, rightSets: Int)
    case sidesExchangeReminder
    case sidesExchanged
    case matchFinished(winner: MatchSide?)
    case matchReset
}

public enum RallyMatchEngine {
    public static func initial(
        leftName: String,
        rightName: String,
        rules: RallyRuleSet,
        openingServer: MatchSide = .left,
        doubles: RallyDoublesState? = nil
    ) -> RallyMatchState {
        RallyMatchState(
            rules: rules,
            leftName: leftName,
            rightName: rightName,
            leftPoints: 0,
            rightPoints: 0,
            leftSets: 0,
            rightSets: 0,
            servingSide: openingServer,
            openingServerSide: openingServer,
            firstServerInSet: openingServer,
            finished: false,
            sidesSwapped: false,
            doubles: doubles
        )
    }

    public static func score(for side: MatchSide, in state: RallyMatchState) -> Int {
        side == .left ? state.leftPoints : state.rightPoints
    }
}

public struct RallyMatchReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: RallyMatchState,
        intent: RallyMatchIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        switch intent {
        case .pointWon(let side):
            return pointWon(side, state: state)
        case .setNames(let left, let right):
            return .init(state: withNames(left: left, right: right, state: state))
        case .adjustPoints(let side, let delta):
            return adjustPoints(side: side, delta: delta, state: state)
        case .adjustSets(let side, let delta):
            return adjustSets(side: side, delta: delta, state: state)
        case .setDoublesPlayerName(let slot, let name):
            return setDoublesPlayerName(slot: slot, name: name, state: state)
        case .exchangeSides:
            return .init(state: exchanged(state), events: [.sidesExchanged])
        case .finish:
            guard !state.finished else { return .rejected(state: state, reason: "Match is already finished") }
            return .init(state: finished(state), events: [.matchFinished(winner: winner(of: state))])
        case .reset:
            let reset = RallyMatchEngine.initial(
                leftName: state.leftName,
                rightName: state.rightName,
                rules: state.rules,
                openingServer: state.openingServerSide,
                doubles: resetDoubles(state.doubles, openingServer: state.openingServerSide)
            )
            return .init(state: reset, events: [.matchReset])
        }
    }

    private func pointWon(_ side: MatchSide, state: RallyMatchState) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        guard !state.finished else { return .rejected(state: state, reason: "Match is already finished") }

        if usesPickleballServeRules(state) {
            return pickleballPointWon(side, state: state)
        }

        if !state.rules.useRallyScoring,
           state.rules.servingModel == .scorerServes,
           side != state.servingSide {
            var next = state
            next.servingSide = side
            return .init(state: next)
        }
        var next = state
        if side == .left { next.leftPoints += 1 } else { next.rightPoints += 1 }
        if let cap = effectivePointCap(in: state, setNumber: state.currentSet) {
            next.leftPoints = min(next.leftPoints, cap)
            next.rightPoints = min(next.rightPoints, cap)
        }
        next.doubles = advanceDoubles(previous: state, next: next, scorer: side)
        next.servingSide = nextServer(after: side, state: next)
        return finalizePointResult(previous: state, next: next, scoredSide: side)
    }

    private func usesPickleballServeRules(_ state: RallyMatchState) -> Bool {
        if case .pickleball = state.doubles?.rotation { return true }
        // Singles pickleball only (factory uses `.opening`); volleyball uses `.alternateFromOpening`.
        return state.rules.nextSetServerModel == .opening
    }

    /// Aligns with Android `PickleballMatchEngine.recordRally`.
    private func pickleballPointWon(
        _ side: MatchSide,
        state: RallyMatchState
    ) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        if state.rules.useRallyScoring {
            return pickleballRallyPointWon(side, state: state)
        }
        return pickleballTraditionalPointWon(side, state: state)
    }

    private func pickleballTraditionalPointWon(
        _ side: MatchSide,
        state: RallyMatchState
    ) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        if side != state.servingSide {
            var next = state
            applyPickleballSideOut(&next)
            return .init(
                state: next,
                events: [
                    .sideOut(
                        servingSide: next.servingSide,
                        leftPoints: next.leftPoints,
                        rightPoints: next.rightPoints
                    )
                ]
            )
        }

        var next = state
        if side == .left { next.leftPoints += 1 } else { next.rightPoints += 1 }
        if let cap = effectivePointCap(in: state, setNumber: state.currentSet) {
            next.leftPoints = min(next.leftPoints, cap)
            next.rightPoints = min(next.rightPoints, cap)
        }
        if case .pickleball(var rotation) = next.doubles?.rotation {
            togglePickleballPartnerSwap(&rotation, servingTeam0: state.servingSide == .left)
            if rotation.isFirstServeOfGame {
                rotation.isFirstServeOfGame = false
            }
            refreshPickleballDoublesSlots(&rotation, servingTeam0: next.servingSide == .left)
            next.doubles?.rotation = .pickleball(rotation)
        }
        next.servingSide = side
        return finalizePointResult(previous: state, next: next, scoredSide: side)
    }

    private func pickleballRallyPointWon(
        _ side: MatchSide,
        state: RallyMatchState
    ) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        var next = state
        if side == .left { next.leftPoints += 1 } else { next.rightPoints += 1 }
        if let cap = effectivePointCap(in: state, setNumber: state.currentSet) {
            next.leftPoints = min(next.leftPoints, cap)
            next.rightPoints = min(next.rightPoints, cap)
        }

        if case .pickleball(var rotation) = next.doubles?.rotation {
            if side == state.servingSide {
                togglePickleballPartnerSwap(&rotation, servingTeam0: state.servingSide == .left)
            }
            if rotation.serverNumber == 1 {
                rotation.serverNumber = 2
            } else {
                next.servingSide = state.servingSide.opposite
                rotation.serverNumber = 1
            }
            refreshPickleballDoublesSlots(&rotation, servingTeam0: next.servingSide == .left)
            next.doubles?.rotation = .pickleball(rotation)
        } else {
            next.servingSide = state.servingSide.opposite
        }

        return finalizePointResult(previous: state, next: next, scoredSide: side)
    }

    private func applyPickleballSideOut(_ state: inout RallyMatchState) {
        if case .pickleball(var rotation) = state.doubles?.rotation {
            if rotation.isFirstServeOfGame {
                state.servingSide = state.servingSide.opposite
                rotation.serverNumber = 1
                rotation.isFirstServeOfGame = false
            } else if rotation.serverNumber == 1 {
                rotation.serverNumber = 2
            } else {
                state.servingSide = state.servingSide.opposite
                rotation.serverNumber = 1
            }
            refreshPickleballDoublesSlots(&rotation, servingTeam0: state.servingSide == .left)
            state.doubles?.rotation = .pickleball(rotation)
        } else {
            state.servingSide = state.servingSide.opposite
        }
    }

    private func finalizePointResult(
        previous: RallyMatchState,
        next initialNext: RallyMatchState,
        scoredSide: MatchSide
    ) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        var next = initialNext
        var events: [RallyMatchEvent] = [
            .pointScored(side: scoredSide, leftPoints: next.leftPoints, rightPoints: next.rightPoints)
        ]

        let setNumber = previous.currentSet
        if let setWinner = setWinner(in: next, setNumber: setNumber) {
            let finalLeftPoints = next.leftPoints
            let finalRightPoints = next.rightPoints
            if setWinner == .left { next.leftSets += 1 } else { next.rightSets += 1 }
            events.append(.setCompleted(
                winner: setWinner,
                setNumber: setNumber,
                leftPoints: finalLeftPoints,
                rightPoints: finalRightPoints,
                leftSets: next.leftSets,
                rightSets: next.rightSets
            ))
            if next.rules.isMatchFinished(leftSets: next.leftSets, rightSets: next.rightSets) {
                next.finished = true
                events.append(.matchFinished(winner: winner(of: next)))
                return .init(state: next, events: events)
            }
            next.leftPoints = 0
            next.rightPoints = 0
            next.firstServerInSet = nextFirstServer(for: next)
            next.servingSide = next.firstServerInSet
            next.doubles = startNextSetDoubles(next.doubles, servingSide: next.firstServerInSet)
            if next.rules.autoChangeSides {
                next = exchanged(next)
                events.append(.sidesExchanged)
            }
            return .init(state: next, events: events)
        }

        if shouldRemindSideChange(previous: previous, next: next) {
            if next.rules.autoChangeSides {
                next = exchanged(next)
                events.append(.sidesExchanged)
            } else {
                events.append(.sidesExchangeReminder)
            }
        }
        return .init(state: next, events: events)
    }

    private func setWinner(in state: RallyMatchState, setNumber: Int) -> MatchSide? {
        let target = state.rules.target(for: setNumber)
        if let cap = effectivePointCap(in: state, setNumber: setNumber), max(state.leftPoints, state.rightPoints) >= cap {
            return state.leftPoints == state.rightPoints ? nil : (state.leftPoints > state.rightPoints ? .left : .right)
        }
        if effectiveWinByTwo(in: state, setNumber: setNumber) {
            guard abs(state.leftPoints - state.rightPoints) >= 2 else { return nil }
        }
        if state.leftPoints >= target { return .left }
        if state.rightPoints >= target { return .right }
        return nil
    }

    private func effectivePointCap(in state: RallyMatchState, setNumber: Int) -> Int? {
        if setNumber == state.rules.maxSets, let finalCap = state.rules.finalSetPointCap {
            return finalCap
        }
        return state.rules.pointCap
    }

    private func effectiveWinByTwo(in state: RallyMatchState, setNumber: Int) -> Bool {
        if setNumber == state.rules.maxSets, let finalWinByTwo = state.rules.finalSetWinByTwo {
            return finalWinByTwo
        }
        return state.rules.winByTwo
    }

    private func nextServer(after scorer: MatchSide, state: RallyMatchState) -> MatchSide {
        guard state.rules.servingModel == .pingPongTwoServes else { return scorer }
        let total = state.leftPoints + state.rightPoints
        let deuce = state.leftPoints >= state.rules.target(for: state.currentSet) - 1 && state.rightPoints >= state.rules.target(for: state.currentSet) - 1
        let turns = deuce ? total : total / 2
        return turns.isMultiple(of: 2) ? state.firstServerInSet : state.firstServerInSet.opposite
    }

    private func nextFirstServer(for state: RallyMatchState) -> MatchSide {
        switch state.rules.nextSetServerModel {
        case .opening:
            return state.openingServerSide
        case .alternateFromOpening:
            return state.currentSet.isMultiple(of: 2)
                ? state.openingServerSide.opposite
                : state.openingServerSide
        case .scorerContinues:
            break
        }
        guard state.rules.servingModel == .pingPongTwoServes else { return state.servingSide }
        return state.currentSet.isMultiple(of: 2) ? state.openingServerSide.opposite : state.openingServerSide
    }

    private func shouldRemindSideChange(previous: RallyMatchState, next: RallyMatchState) -> Bool {
        let isFinalSet = previous.currentSet == previous.rules.maxSets
        let interval = isFinalSet
            ? previous.rules.finalSetSideSwitchEveryTotalPoints ?? previous.rules.sideSwitchEveryTotalPoints
            : previous.rules.sideSwitchEveryTotalPoints
        if let interval, interval > 0 {
            let previousTotal = previous.leftPoints + previous.rightPoints
            let nextTotal = next.leftPoints + next.rightPoints
            if previousTotal / interval < nextTotal / interval {
                return true
            }
        }
        guard previous.currentSet == previous.rules.maxSets,
              let point = previous.rules.decidingSetSideSwitchPoint else { return false }
        return max(previous.leftPoints, previous.rightPoints) < point && max(next.leftPoints, next.rightPoints) >= point
    }

    private func advanceDoubles(
        previous: RallyMatchState,
        next: RallyMatchState,
        scorer: MatchSide
    ) -> RallyDoublesState? {
        guard var doubles = previous.doubles else { return nil }
        switch doubles.rotation {
        case .pingPong(let rotation):
            let result = advancePingPongDoublesRotation(
                current: rotation,
                previousTeam0Score: previous.leftPoints,
                previousTeam1Score: previous.rightPoints,
                nextTeam0Score: next.leftPoints,
                nextTeam1Score: next.rightPoints,
                pointsToWin: previous.rules.target(for: previous.currentSet),
                isDecidingSet: previous.currentSet == previous.rules.maxSets
            )
            doubles.rotation = .pingPong(result.state)
        case .badminton(let rotation):
            doubles.rotation = .badminton(advanceBadmintonDoublesRotation(
                current: rotation,
                scoringTeam0: scorer == .left,
                nextTeam0Score: next.leftPoints,
                nextTeam1Score: next.rightPoints
            ))
        case .pickleball:
            break
        case .foosball:
            break
        }
        return doubles
    }

    private func startNextSetDoubles(
        _ doubles: RallyDoublesState?,
        servingSide: MatchSide
    ) -> RallyDoublesState? {
        guard var doubles else { return nil }
        switch doubles.rotation {
        case .pingPong:
            let server = servingSide == .left ? 0 : 1
            doubles.rotation = .pingPong(createPingPongDoublesRotation(
                openingServerSlotIndex: server,
                openingReceiverSlotIndex: server == 0 ? 1 : 0
            ))
        case .badminton(let rotation):
            let servingTeam0 = servingSide == .left
            let server = badmintonPlayerAtServiceCourt(
                team0: servingTeam0,
                rightCourt: true,
                team0CourtOrderSwapped: rotation.team0CourtOrderSwapped,
                team1CourtOrderSwapped: rotation.team1CourtOrderSwapped
            )
            let receiver = badmintonPlayerAtServiceCourt(
                team0: !servingTeam0,
                rightCourt: true,
                team0CourtOrderSwapped: rotation.team0CourtOrderSwapped,
                team1CourtOrderSwapped: rotation.team1CourtOrderSwapped
            )
            doubles.rotation = .badminton(.init(
                serverSlotIndex: server,
                receiverSlotIndex: receiver,
                team0CourtOrderSwapped: rotation.team0CourtOrderSwapped,
                team1CourtOrderSwapped: rotation.team1CourtOrderSwapped
            ))
        case .pickleball:
            doubles.rotation = .pickleball(createPickleballDoublesRotation(servingTeam0: servingSide == .left))
        case .foosball:
            break
        }
        return doubles
    }

    private func resetDoubles(
        _ doubles: RallyDoublesState?,
        openingServer: MatchSide
    ) -> RallyDoublesState? {
        guard let doubles else { return nil }
        switch doubles.rotation {
        case .pingPong:
            let server = openingServer == .left ? 0 : 1
            return .pingPong(
                playerNames: doubles.playerNames,
                openingServerSlotIndex: server,
                openingReceiverSlotIndex: server == 0 ? 1 : 0
            )
        case .badminton:
            return .badminton(playerNames: doubles.playerNames, servingTeam0: openingServer == .left)
        case .pickleball:
            return .pickleball(playerNames: doubles.playerNames, servingTeam0: openingServer == .left)
        case .foosball:
            return .foosball(playerNames: doubles.playerNames)
        }
    }

    private func adjustPoints(side: MatchSide, delta: Int, state: RallyMatchState) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        guard delta != 0 else { return .rejected(state: state, reason: "Zero delta") }
        var next = state
        if side == .left {
            next.leftPoints = max(0, next.leftPoints + delta)
        } else {
            next.rightPoints = max(0, next.rightPoints + delta)
        }
        if let cap = effectivePointCap(in: state, setNumber: state.currentSet) {
            next.leftPoints = min(next.leftPoints, cap)
            next.rightPoints = min(next.rightPoints, cap)
        }
        guard next.leftPoints != state.leftPoints || next.rightPoints != state.rightPoints else {
            return .rejected(state: state, reason: "No change")
        }
        return .init(state: next)
    }

    private func adjustSets(side: MatchSide, delta: Int, state: RallyMatchState) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        guard delta != 0 else { return .rejected(state: state, reason: "Zero delta") }
        var nextLeft = state.leftSets
        var nextRight = state.rightSets
        if side == .left {
            nextLeft = max(0, nextLeft + delta)
        } else {
            nextRight = max(0, nextRight + delta)
        }
        guard state.rules.matchCompletionMode.allowsSetScore(
            maxSets: state.rules.maxSets,
            leftSets: nextLeft,
            rightSets: nextRight
        ) else {
            return .rejected(state: state, reason: "Set score overflow")
        }
        var next = state
        next.leftSets = nextLeft
        next.rightSets = nextRight
        next.finished = state.rules.isMatchFinished(leftSets: nextLeft, rightSets: nextRight)
        return .init(state: next)
    }

    private func setDoublesPlayerName(slot: Int, name: String, state: RallyMatchState) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        guard var doubles = state.doubles, (0..<4).contains(slot) else {
            return .rejected(state: state, reason: "Invalid doubles slot")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected(state: state, reason: "Empty name") }
        doubles.playerNames[slot] = trimmed
        var next = state
        next.doubles = doubles
        return .init(state: next)
    }

    private func withNames(left: String, right: String, state: RallyMatchState) -> RallyMatchState {
        var next = state
        next.leftName = left.trimmingCharacters(in: .whitespacesAndNewlines)
        next.rightName = right.trimmingCharacters(in: .whitespacesAndNewlines)
        return next
    }

    private func exchanged(_ state: RallyMatchState) -> RallyMatchState {
        var next = state
        next.sidesSwapped.toggle()
        return next
    }

    private func finished(_ state: RallyMatchState) -> RallyMatchState {
        var next = state
        next.finished = true
        return next
    }

    private func winner(of state: RallyMatchState) -> MatchSide? {
        state.leftSets == state.rightSets ? nil : (state.leftSets > state.rightSets ? .left : .right)
    }
}
