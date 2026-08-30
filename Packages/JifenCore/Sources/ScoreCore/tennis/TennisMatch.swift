import Foundation

public enum TennisSetScoringMode: String, Codable, Equatable, Sendable {
    case regular
    case tiebreakOnly = "tiebreak_only"
}

public struct TennisRuleSet: Codable, Equatable, Sendable {
    public var maxSets: Int
    public var tieBreakPoints: Int
    public var gamesPerSet: Int
    public var setScoringMode: TennisSetScoringMode
    public var matchCompletionMode: MatchCompletionMode
    public var usesNoAdScoring: Bool
    public var autoChangeSides: Bool
    public var familyProfile: TennisFamilyRuleProfile
    public var padelDeuceMode: PadelDeuceMode
    /// Soft tennis is one 7- or 9-game match rather than a best-of-sets
    /// tennis match. Nil for regular tennis and padel.
    public var softTennisMatchGames: Int?

    public init(
        maxSets: Int = 3,
        tieBreakPoints: Int = 7,
        gamesPerSet: Int = 6,
        setScoringMode: TennisSetScoringMode = .regular,
        matchCompletionMode: MatchCompletionMode = .bestOf,
        usesNoAdScoring: Bool = false,
        autoChangeSides: Bool = true,
        familyProfile: TennisFamilyRuleProfile = .tennis,
        padelDeuceMode: PadelDeuceMode = .advantage,
        softTennisMatchGames: Int? = nil
    ) {
        self.maxSets = setScoringMode == .tiebreakOnly ? 1 : max(1, maxSets)
        self.tieBreakPoints = max(1, tieBreakPoints)
        self.gamesPerSet = [4, 6, 7, 9].contains(gamesPerSet) ? gamesPerSet : 6
        self.setScoringMode = setScoringMode
        self.matchCompletionMode = setScoringMode == .tiebreakOnly ? .bestOf : matchCompletionMode
        self.usesNoAdScoring = usesNoAdScoring
        self.autoChangeSides = autoChangeSides
        self.familyProfile = familyProfile
        self.padelDeuceMode = padelDeuceMode
        self.softTennisMatchGames = familyProfile == .softTennis
            ? (softTennisMatchGames == 9 ? 9 : 7)
            : nil
    }

    public func isMatchFinished(leftSets: Int, rightSets: Int) -> Bool {
        matchCompletionMode.isMatchFinished(maxSets: maxSets, leftSets: leftSets, rightSets: rightSets)
    }

    private enum CodingKeys: String, CodingKey {
        case maxSets, tieBreakPoints, gamesPerSet, setScoringMode
        case matchCompletionMode, usesNoAdScoring, autoChangeSides
        case familyProfile, padelDeuceMode, softTennisMatchGames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let familyProfile = try container.decodeIfPresent(TennisFamilyRuleProfile.self, forKey: .familyProfile) ?? .tennis
        let storedGamesPerSet = try container.decodeIfPresent(Int.self, forKey: .gamesPerSet) ?? 6
        // Early iOS 2.1 drafts stored 7/9 in gamesPerSet. Migrate those
        // snapshots into the dedicated whole-match field while decoding.
        let softMatchGames = try container.decodeIfPresent(Int.self, forKey: .softTennisMatchGames)
            ?? (familyProfile == .softTennis && [7, 9].contains(storedGamesPerSet) ? storedGamesPerSet : nil)
        self.init(
            maxSets: try container.decodeIfPresent(Int.self, forKey: .maxSets) ?? 3,
            tieBreakPoints: try container.decodeIfPresent(Int.self, forKey: .tieBreakPoints) ?? 7,
            gamesPerSet: familyProfile == .softTennis ? 4 : storedGamesPerSet,
            setScoringMode: try container.decodeIfPresent(TennisSetScoringMode.self, forKey: .setScoringMode) ?? .regular,
            matchCompletionMode: try container.decodeIfPresent(MatchCompletionMode.self, forKey: .matchCompletionMode) ?? .bestOf,
            usesNoAdScoring: try container.decodeIfPresent(Bool.self, forKey: .usesNoAdScoring) ?? false,
            autoChangeSides: try container.decodeIfPresent(Bool.self, forKey: .autoChangeSides) ?? true,
            familyProfile: familyProfile,
            padelDeuceMode: try container.decodeIfPresent(PadelDeuceMode.self, forKey: .padelDeuceMode) ?? .advantage,
            softTennisMatchGames: softMatchGames
        )
    }

    public var softTennisFinalGameAt: Int {
        softTennisMatchGames == 9 ? 4 : 3
    }
}

public struct TennisMatchState: Codable, Equatable, Sendable {
    public var rules: TennisRuleSet
    public var leftName: String
    public var rightName: String
    /// Normal games use raw tennis steps (0,1,2,3,4); tie-breaks use literal points.
    public var leftPoints: Int
    public var rightPoints: Int
    public var leftGames: Int
    public var rightGames: Int
    public var leftSets: Int
    public var rightSets: Int
    public var servingSide: MatchSide
    public var openingServerSide: MatchSide
    public var firstServerInSet: MatchSide
    public var isTieBreak: Bool
    public var sidesSwapped: Bool
    public var finished: Bool
    /// Doubles only. Slot order matches Rally: [team0A, team1A, team0B, team1B].
    public var doublesPlayerNames: [String]?
    /// Doubles only. First server for the current set in A1, B1, A2, B2 order.
    /// Optional so protocol-v1 snapshots decode without migration.
    public var doublesFirstServerSlotInSet: Int?
    /// Padel star-point state. Nil is treated as zero for legacy snapshots.
    public var starPointReturnedAdvantages: Int?
    public var officialBreakState: OfficialBreakState?

    public init(
        leftName: String,
        rightName: String,
        rules: TennisRuleSet = .init(),
        openingServer: MatchSide = .left,
        doublesPlayerNames: [String]? = nil
    ) {
        self.rules = rules
        self.leftName = leftName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rightName = rightName.trimmingCharacters(in: .whitespacesAndNewlines)
        leftPoints = 0
        rightPoints = 0
        leftGames = 0
        rightGames = 0
        leftSets = 0
        rightSets = 0
        servingSide = openingServer
        openingServerSide = openingServer
        firstServerInSet = openingServer
        isTieBreak = rules.setScoringMode == .tiebreakOnly
        sidesSwapped = false
        finished = false
        self.doublesPlayerNames = Self.normalizedDoublesNames(doublesPlayerNames)
        doublesFirstServerSlotInSet = self.doublesPlayerNames == nil
            ? nil
            : (openingServer == .left ? 0 : 1)
        starPointReturnedAdvantages = 0
        officialBreakState = nil
    }

    /// Team display preferring individual doubles names when present.
    public func doublesTeamDisplayName(for side: MatchSide) -> String {
        guard let names = doublesPlayerNames, names.count >= 4 else {
            return side == .left ? leftName : rightName
        }
        let first = side == .left ? names[0] : names[1]
        let second = side == .left ? names[2] : names[3]
        if !first.isEmpty && !second.isEmpty { return "\(first) / \(second)" }
        if !first.isEmpty { return first }
        if !second.isEmpty { return second }
        return side == .left ? leftName : rightName
    }

    private static func normalizedDoublesNames(_ names: [String]?) -> [String]? {
        guard let names, !names.isEmpty else { return nil }
        let normalized = (0..<4).map { index -> String in
            guard names.indices.contains(index) else { return "" }
            return names[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized.contains(where: { !$0.isEmpty }) ? normalized : nil
    }

    public var currentSet: Int { leftSets + rightSets + 1 }

    public func canAdjustPoints(side: MatchSide, delta: Int) -> Bool {
        guard delta != 0 else { return false }
        let current = side == .left ? leftPoints : rightPoints
        let opponent = side == .left ? rightPoints : leftPoints
        let maximum: Int
        if isTieBreak {
            let deuceEdge = max(0, rules.tieBreakPoints - 1)
            maximum = opponent < deuceEdge ? deuceEdge : opponent + 1
        } else if rules.familyProfile == .softTennis {
            maximum = opponent < 3 ? 3 : opponent + 1
        } else {
            maximum = 4
        }
        let next = current + delta
        return next >= 0 && next <= maximum
    }

    public func canAdjustGames(side: MatchSide, delta: Int) -> Bool {
        guard delta != 0, rules.setScoringMode != .tiebreakOnly else { return false }
        let nextLeft = leftGames + (side == .left ? delta : 0)
        let nextRight = rightGames + (side == .right ? delta : 0)
        let maximum = rules.familyProfile == .softTennis
            ? rules.softTennisFinalGameAt + 1
            : rules.gamesPerSet + 1
        let maxTotalGames = rules.familyProfile == .softTennis
            ? (rules.softTennisMatchGames ?? 7)
            : rules.gamesPerSet * 2 + 1
        return nextLeft >= 0 && nextRight >= 0
            && nextLeft <= maximum && nextRight <= maximum
            && nextLeft + nextRight <= maxTotalGames
    }

    public func canAdjustSets(side: MatchSide, delta: Int) -> Bool {
        guard delta != 0 else { return false }
        let nextLeft = leftSets + (side == .left ? delta : 0)
        let nextRight = rightSets + (side == .right ? delta : 0)
        return rules.matchCompletionMode.allowsSetScore(
            maxSets: rules.maxSets,
            leftSets: nextLeft,
            rightSets: nextRight
        )
    }

    public func scoreDisplay(for side: MatchSide) -> String {
        let own = side == .left ? leftPoints : rightPoints
        let other = side == .left ? rightPoints : leftPoints
        if isTieBreak { return String(own) }
        if own >= 3, other >= 3 {
            if own == other || rules.usesNoAdScoring { return "40" }
            return own > other ? "AD" : "40"
        }
        switch own {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }
}

public enum TennisDoublesServing {
    public static func firstServerSlot(in state: TennisMatchState) -> Int? {
        guard state.doublesPlayerNames != nil else { return nil }
        return normalized(
            state.doublesFirstServerSlotInSet
                ?? (state.firstServerInSet == .left ? 0 : 1)
        )
    }

    public static func currentServerSlot(in state: TennisMatchState) -> Int? {
        guard let firstSlot = firstServerSlot(in: state) else { return nil }
        return serverSlot(
            firstServerSlot: firstSlot,
            completedGames: state.leftGames + state.rightGames,
            isTieBreak: state.isTieBreak,
            tieBreakPointsPlayed: state.leftPoints + state.rightPoints,
            familyProfile: state.rules.familyProfile
        )
    }

    public static func currentReceiverSlot(in state: TennisMatchState) -> Int? {
        guard let serverSlot = currentServerSlot(in: state) else { return nil }
        return resolveTennisDoublesReceiverSlot(
            serverSlotIndex: serverSlot,
            pointIndexInGame: max(0, state.leftPoints + state.rightPoints),
            team0FirstReceiverSlotIndex: 0,
            team1FirstReceiverSlotIndex: 1
        )
    }

    public static func serverSlot(
        firstServerSlot: Int,
        completedGames: Int,
        isTieBreak: Bool,
        tieBreakPointsPlayed: Int,
        familyProfile: TennisFamilyRuleProfile = .tennis
    ) -> Int {
        let openingSlot = normalized(firstServerSlot + max(0, completedGames))
        guard isTieBreak else { return openingSlot }
        let played = max(0, tieBreakPointsPlayed)
        guard played > 0 else { return openingSlot }
        let offset = familyProfile == .softTennis
            ? played / 2
            : 1 + (played - 1) / 2
        return normalized(openingSlot + offset)
    }

    public static func side(for slot: Int) -> MatchSide {
        normalized(slot).isMultiple(of: 2) ? .left : .right
    }

    private static func normalized(_ slot: Int) -> Int {
        ((slot % 4) + 4) % 4
    }
}

public enum TennisMatchIntent: Codable, Equatable, Sendable {
    case pointWon(MatchSide)
    case adjustPoints(side: MatchSide, delta: Int)
    case adjustGames(side: MatchSide, delta: Int)
    case adjustSets(side: MatchSide, delta: Int)
    case setNames(left: String, right: String)
    case setDoublesPlayerName(slot: Int, name: String)
    case exchangeSides
    case finish
    case reset
    case setOfficialBreakState(OfficialBreakState?)
}

public enum TennisMatchEvent: Codable, Equatable, Sendable {
    case pointScored(side: MatchSide, left: Int, right: Int)
    case gameCompleted(winner: MatchSide, leftGames: Int, rightGames: Int, tieBreak: Bool)
    case setCompleted(winner: MatchSide, setNumber: Int, leftGames: Int, rightGames: Int, leftSets: Int, rightSets: Int)
    case sidesExchangeReminder
    case sidesExchanged
    case namesChanged
    case adminAdjusted
    case matchFinished(winner: MatchSide?)
    case matchReset
    case officialBreakChanged(OfficialBreakState?)
}

public struct TennisMatchReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: TennisMatchState,
        intent: TennisMatchIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<TennisMatchState, TennisMatchEvent> {
        if state.officialBreakState?.isRunning == true {
            switch intent {
            case .pointWon, .adjustPoints, .adjustGames, .adjustSets:
                return .rejected(state: state, reason: "Scoring is unavailable during an official break")
            default:
                break
            }
        }

        if state.finished {
            switch intent {
            case .adjustSets, .reset: break
            default: return .rejected(state: state, reason: "Already finished")
            }
        }

        switch intent {
        case .pointWon(let side):
            return state.rules.familyProfile == .softTennis
                ? scoreSoftTennisPoint(state: state, side: side)
                : scorePoint(state: state, side: side)
        case .adjustPoints(let side, let delta):
            guard state.canAdjustPoints(side: side, delta: delta) else {
                return .rejected(state: state, reason: "Point score overflow")
            }
            let result = adjust(state: state, side: side, delta: delta, keyPath: side == .left ? \.leftPoints : \.rightPoints, range: 0 ... Int.max)
            guard result.accepted else { return result }
            var next = result.state
            if next.isTieBreak { synchronizeServingState(&next) }
            return .init(state: next, events: result.events)
        case .adjustGames(let side, let delta):
            guard state.canAdjustGames(side: side, delta: delta) else {
                return .rejected(state: state, reason: "Game score overflow")
            }
            let result = adjust(
                state: state,
                side: side,
                delta: delta,
                keyPath: side == .left ? \.leftGames : \.rightGames,
                range: 0 ... (state.rules.familyProfile == .softTennis
                    ? state.rules.softTennisFinalGameAt + 1
                    : state.rules.gamesPerSet + 1)
            )
            guard result.accepted else { return result }
            var next = result.state
            let tieBreakGames = next.rules.familyProfile == .softTennis
                ? next.rules.softTennisFinalGameAt
                : next.rules.gamesPerSet
            let shouldUseTieBreak = next.rules.setScoringMode == .tiebreakOnly
                || (next.leftGames == tieBreakGames && next.rightGames == tieBreakGames)
            if shouldUseTieBreak != state.isTieBreak {
                next.leftPoints = 0
                next.rightPoints = 0
            }
            next.isTieBreak = shouldUseTieBreak
            synchronizeServingState(&next)
            return .init(state: next, events: result.events)
        case .adjustSets(let side, let delta):
            guard state.canAdjustSets(side: side, delta: delta) else {
                return .rejected(state: state, reason: "Set score overflow")
            }
            let result = adjust(state: state, side: side, delta: delta, keyPath: side == .left ? \.leftSets : \.rightSets, range: 0 ... Int.max)
            guard result.accepted else { return result }
            var next = result.state
            next.finished = next.rules.isMatchFinished(leftSets: next.leftSets, rightSets: next.rightSets)
            return .init(state: next, events: result.events)
        case .setNames(let left, let right):
            var next = state
            next.leftName = left.trimmingCharacters(in: .whitespacesAndNewlines)
            next.rightName = right.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(state: next, events: [.namesChanged])
        case .setDoublesPlayerName(let slot, let name):
            guard var names = state.doublesPlayerNames,
                  names.count >= 4,
                  names.indices.contains(slot) else {
                return .rejected(state: state, reason: "Invalid doubles slot")
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .rejected(state: state, reason: "Empty name")
            }
            names[slot] = trimmed
            var next = state
            next.doublesPlayerNames = names
            next.leftName = next.doublesTeamDisplayName(for: .left)
            next.rightName = next.doublesTeamDisplayName(for: .right)
            return .init(state: next, events: [.namesChanged])
        case .exchangeSides:
            let next = exchanged(state)
            return .init(state: next, events: [.sidesExchanged])
        case .finish:
            var next = state
            next.finished = true
            return .init(state: next, events: [.matchFinished(winner: matchWinner(for: next))])
        case .reset:
            return .init(
                state: .init(
                    leftName: state.leftName,
                    rightName: state.rightName,
                    rules: state.rules,
                    openingServer: state.openingServerSide,
                    doublesPlayerNames: state.doublesPlayerNames
                ),
                events: [.matchReset]
            )
        case .setOfficialBreakState(let breakState):
            var next = state
            next.officialBreakState = breakState
            return .init(state: next, events: [.officialBreakChanged(breakState)])
        }
    }

    private func scorePoint(
        state: TennisMatchState,
        side: MatchSide
    ) -> ReduceResult<TennisMatchState, TennisMatchEvent> {
        var next = state
        var events: [TennisMatchEvent] = []
        let pointsBefore = state.leftPoints + state.rightPoints
        if side == .left { next.leftPoints += 1 } else { next.rightPoints += 1 }

        if state.isTieBreak {
            let leading = max(next.leftPoints, next.rightPoints)
            if leading >= state.rules.tieBreakPoints, abs(next.leftPoints - next.rightPoints) >= 2 {
                let winner: MatchSide = next.leftPoints > next.rightPoints ? .left : .right
                events.append(.pointScored(side: side, left: next.leftPoints, right: next.rightPoints))
                if state.rules.setScoringMode == .tiebreakOnly {
                    next.finished = true
                    events.append(.matchFinished(winner: winner))
                    return .init(state: next, events: events)
                }
                next.leftGames = winner == .left ? state.rules.gamesPerSet + 1 : state.rules.gamesPerSet
                next.rightGames = winner == .right ? state.rules.gamesPerSet + 1 : state.rules.gamesPerSet
                events.append(.gameCompleted(winner: winner, leftGames: next.leftGames, rightGames: next.rightGames, tieBreak: true))
                completeSet(state: &next, winner: winner, events: &events)
            } else {
                events.append(.pointScored(side: side, left: next.leftPoints, right: next.rightPoints))
                let boundary = state.rules.familyProfile == .softTennis ? 2 : 6
                let crossedPointBoundary = pointsBefore > 0 && pointsBefore / boundary != (next.leftPoints + next.rightPoints) / boundary
                if crossedPointBoundary { applySideChange(state: &next, events: &events) }
                synchronizeServingState(&next)
            }
            return .init(state: next, events: events)
        }

        // Android keeps deuce in its canonical 3:3 representation. Losing an
        // advantage returns to deuce instead of allowing synthetic 4:4, 5:5…
        // values to accumulate (the star-point counter advances only here).
        let returnedFromAdvantage = (state.leftPoints == 4 && state.rightPoints == 3 && side == .right)
            || (state.rightPoints == 4 && state.leftPoints == 3 && side == .left)
        if returnedFromAdvantage {
            next.leftPoints = 3
            next.rightPoints = 3
        }
        let isDeuce = next.leftPoints >= 3 && next.rightPoints >= 3
        let starPointReached = state.rules.familyProfile == .padel
            && state.rules.padelDeuceMode == .starPoint
            && (state.starPointReturnedAdvantages ?? 0) >= 2
            && isDeuce
        let winsGame: Bool
        if starPointReached {
            winsGame = true
        } else if state.rules.familyProfile == .padel,
                  state.rules.padelDeuceMode == .goldenPoint,
                  isDeuce {
            winsGame = true
        } else if state.rules.usesNoAdScoring, next.leftPoints >= 3, next.rightPoints >= 3 {
            winsGame = next.leftPoints != next.rightPoints
        } else {
            winsGame = max(next.leftPoints, next.rightPoints) >= 4 && abs(next.leftPoints - next.rightPoints) >= 2
        }
        events.append(.pointScored(side: side, left: next.leftPoints, right: next.rightPoints))
        if !winsGame,
           state.rules.familyProfile == .padel,
           state.rules.padelDeuceMode == .starPoint,
           returnedFromAdvantage {
            next.starPointReturnedAdvantages = (state.starPointReturnedAdvantages ?? 0) + 1
        }
        guard winsGame else { return .init(state: next, events: events) }

        let gameWinner: MatchSide = next.leftPoints > next.rightPoints ? .left : .right
        if gameWinner == .left { next.leftGames += 1 } else { next.rightGames += 1 }
        next.leftPoints = 0
        next.rightPoints = 0
        next.starPointReturnedAdvantages = 0
        events.append(.gameCompleted(winner: gameWinner, leftGames: next.leftGames, rightGames: next.rightGames, tieBreak: false))

        if setWinner(next) == gameWinner {
            completeSet(state: &next, winner: gameWinner, events: &events)
        } else if next.leftGames == next.rules.gamesPerSet,
                  next.rightGames == next.rules.gamesPerSet {
            next.isTieBreak = true
            synchronizeServingState(&next)
        } else {
            if (next.leftGames + next.rightGames).isMultiple(of: 2) == false {
                applySideChange(state: &next, events: &events)
            }
            synchronizeServingState(&next)
        }
        return .init(state: next, events: events)
    }

    private func scoreSoftTennisPoint(
        state: TennisMatchState,
        side: MatchSide
    ) -> ReduceResult<TennisMatchState, TennisMatchEvent> {
        var next = state
        var events: [TennisMatchEvent] = []
        let finalGameAt = state.rules.softTennisFinalGameAt
        let finalGame = state.isTieBreak
            || (state.leftGames == finalGameAt && state.rightGames == finalGameAt)
        let pointsBefore = state.leftPoints + state.rightPoints

        next.isTieBreak = finalGame
        if side == .left { next.leftPoints += 1 } else { next.rightPoints += 1 }
        events.append(.pointScored(side: side, left: next.leftPoints, right: next.rightPoints))

        if finalGame {
            let won = max(next.leftPoints, next.rightPoints) >= state.rules.tieBreakPoints
                && abs(next.leftPoints - next.rightPoints) >= 2
            if won {
                let winner: MatchSide = next.leftPoints > next.rightPoints ? .left : .right
                if winner == .left { next.leftGames += 1 } else { next.rightGames += 1 }
                events.append(.gameCompleted(
                    winner: winner,
                    leftGames: next.leftGames,
                    rightGames: next.rightGames,
                    tieBreak: true
                ))
                next.leftPoints = 0
                next.rightPoints = 0
                completeSoftTennisMatch(state: &next, winner: winner, events: &events)
            } else {
                let total = next.leftPoints + next.rightPoints
                if pointsBefore > 0, total / 2 != pointsBefore / 2 {
                    applySideChange(state: &next, events: &events)
                }
                synchronizeServingState(&next)
            }
            return .init(state: next, events: events)
        }

        let won = max(next.leftPoints, next.rightPoints) >= 4
            && abs(next.leftPoints - next.rightPoints) >= 2
        guard won else { return .init(state: next, events: events) }

        let winner: MatchSide = next.leftPoints > next.rightPoints ? .left : .right
        if winner == .left { next.leftGames += 1 } else { next.rightGames += 1 }
        next.leftPoints = 0
        next.rightPoints = 0
        events.append(.gameCompleted(
            winner: winner,
            leftGames: next.leftGames,
            rightGames: next.rightGames,
            tieBreak: false
        ))

        if next.leftGames >= finalGameAt + 1 || next.rightGames >= finalGameAt + 1 {
            completeSoftTennisMatch(state: &next, winner: winner, events: &events)
            return .init(state: next, events: events)
        }

        if next.leftGames == finalGameAt && next.rightGames == finalGameAt {
            next.isTieBreak = true
        }
        if (next.leftGames + next.rightGames).isMultiple(of: 2) == false {
            applySideChange(state: &next, events: &events)
        }
        synchronizeServingState(&next)
        return .init(state: next, events: events)
    }

    private func completeSoftTennisMatch(
        state: inout TennisMatchState,
        winner: MatchSide,
        events: inout [TennisMatchEvent]
    ) {
        state.leftSets = winner == .left ? 1 : 0
        state.rightSets = winner == .right ? 1 : 0
        state.isTieBreak = false
        state.finished = true
        events.append(.setCompleted(
            winner: winner,
            setNumber: 1,
            leftGames: state.leftGames,
            rightGames: state.rightGames,
            leftSets: state.leftSets,
            rightSets: state.rightSets
        ))
        events.append(.matchFinished(winner: winner))
    }

    private func completeSet(
        state: inout TennisMatchState,
        winner setWinner: MatchSide,
        events: inout [TennisMatchEvent]
    ) {
        let completedLeftGames = state.leftGames
        let completedRightGames = state.rightGames
        let setNumber = state.currentSet
        if setWinner == .left { state.leftSets += 1 } else { state.rightSets += 1 }
        events.append(.setCompleted(
            winner: setWinner,
            setNumber: setNumber,
            leftGames: completedLeftGames,
            rightGames: completedRightGames,
            leftSets: state.leftSets,
            rightSets: state.rightSets
        ))
        if state.rules.isMatchFinished(leftSets: state.leftSets, rightSets: state.rightSets) {
            state.finished = true
            events.append(.matchFinished(winner: matchWinner(left: state.leftSets, right: state.rightSets)))
            return
        }
        let completedGames = completedLeftGames + completedRightGames
        if let firstSlot = TennisDoublesServing.firstServerSlot(in: state) {
            let nextFirstSlot = (firstSlot + completedGames) % 4
            state.doublesFirstServerSlotInSet = nextFirstSlot
            state.firstServerInSet = TennisDoublesServing.side(for: nextFirstSlot)
        } else {
            state.firstServerInSet = completedGames.isMultiple(of: 2) ? state.firstServerInSet : state.firstServerInSet.opposite
        }
        state.leftGames = 0
        state.rightGames = 0
        state.leftPoints = 0
        state.rightPoints = 0
        state.isTieBreak = state.rules.setScoringMode == .tiebreakOnly
        state.servingSide = state.firstServerInSet
        if completedGames.isMultiple(of: 2) == false { applySideChange(state: &state, events: &events) }
    }

    private func setWinner(_ state: TennisMatchState) -> MatchSide? {
        if state.rules.setScoringMode == .tiebreakOnly {
            if state.leftGames == 1 { return .left }
            if state.rightGames == 1 { return .right }
            return nil
        }
        let target = state.rules.gamesPerSet
        if state.leftGames >= target, state.leftGames - state.rightGames >= 2 { return .left }
        if state.rightGames >= target, state.rightGames - state.leftGames >= 2 { return .right }
        if state.leftGames == target + 1, state.rightGames == target { return .left }
        if state.rightGames == target + 1, state.leftGames == target { return .right }
        return nil
    }

    private func applySideChange(state: inout TennisMatchState, events: inout [TennisMatchEvent]) {
        if state.rules.autoChangeSides {
            state = exchanged(state)
            events.append(.sidesExchanged)
        } else {
            events.append(.sidesExchangeReminder)
        }
    }

    private func exchanged(_ state: TennisMatchState) -> TennisMatchState {
        var next = state
        // Engine left/right are stable team identities. A court exchange changes
        // only their screen placement; views resolve geometry via TeamScreenLayout.
        next.sidesSwapped.toggle()
        return next
    }

    private func adjust(
        state: TennisMatchState,
        side: MatchSide,
        delta: Int,
        keyPath: WritableKeyPath<TennisMatchState, Int>,
        range: ClosedRange<Int>
    ) -> ReduceResult<TennisMatchState, TennisMatchEvent> {
        guard delta != 0 else { return .rejected(state: state, reason: "No change") }
        var next = state
        let current = next[keyPath: keyPath]
        next[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, current + delta))
        guard next[keyPath: keyPath] != current else { return .rejected(state: state, reason: "Out of range") }
        return .init(state: next, events: [.adminAdjusted])
    }

    private func tieBreakServer(first: MatchSide, pointsPlayed: Int) -> MatchSide {
        let block = (pointsPlayed + 1) / 2
        return block.isMultiple(of: 2) ? first : first.opposite
    }

    private func synchronizeServingState(_ state: inout TennisMatchState) {
        if let slot = TennisDoublesServing.currentServerSlot(in: state) {
            state.servingSide = TennisDoublesServing.side(for: slot)
        } else if state.isTieBreak, state.rules.familyProfile == .softTennis {
            let block = (state.leftPoints + state.rightPoints) / 2
            state.servingSide = block.isMultiple(of: 2)
                ? state.firstServerInSet
                : state.firstServerInSet.opposite
        } else if state.isTieBreak {
            state.servingSide = tieBreakServer(
                first: state.firstServerInSet,
                pointsPlayed: state.leftPoints + state.rightPoints
            )
        } else {
            state.servingSide = (state.leftGames + state.rightGames).isMultiple(of: 2)
                ? state.firstServerInSet
                : state.firstServerInSet.opposite
        }
    }

    private func matchWinner(left: Int, right: Int) -> MatchSide? {
        left == right ? nil : (left > right ? .left : .right)
    }

    private func matchWinner(for state: TennisMatchState) -> MatchSide? {
        state.rules.setScoringMode == .tiebreakOnly
            ? matchWinner(left: state.leftPoints, right: state.rightPoints)
            : matchWinner(left: state.leftSets, right: state.rightSets)
    }
}
