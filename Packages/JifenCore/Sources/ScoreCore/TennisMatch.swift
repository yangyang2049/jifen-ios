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

    public init(
        maxSets: Int = 3,
        tieBreakPoints: Int = 7,
        gamesPerSet: Int = 6,
        setScoringMode: TennisSetScoringMode = .regular,
        matchCompletionMode: MatchCompletionMode = .bestOf,
        usesNoAdScoring: Bool = false,
        autoChangeSides: Bool = true
    ) {
        self.maxSets = setScoringMode == .tiebreakOnly ? 1 : max(1, maxSets)
        self.tieBreakPoints = max(1, tieBreakPoints)
        self.gamesPerSet = gamesPerSet == 4 ? 4 : 6
        self.setScoringMode = setScoringMode
        self.matchCompletionMode = setScoringMode == .tiebreakOnly ? .bestOf : matchCompletionMode
        self.usesNoAdScoring = usesNoAdScoring
        self.autoChangeSides = autoChangeSides
    }

    public func isMatchFinished(leftSets: Int, rightSets: Int) -> Bool {
        matchCompletionMode.isMatchFinished(maxSets: maxSets, leftSets: leftSets, rightSets: rightSets)
    }

    private enum CodingKeys: String, CodingKey {
        case maxSets, tieBreakPoints, gamesPerSet, setScoringMode
        case matchCompletionMode, usesNoAdScoring, autoChangeSides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxSets: try container.decodeIfPresent(Int.self, forKey: .maxSets) ?? 3,
            tieBreakPoints: try container.decodeIfPresent(Int.self, forKey: .tieBreakPoints) ?? 7,
            gamesPerSet: try container.decodeIfPresent(Int.self, forKey: .gamesPerSet) ?? 6,
            setScoringMode: try container.decodeIfPresent(TennisSetScoringMode.self, forKey: .setScoringMode) ?? .regular,
            matchCompletionMode: try container.decodeIfPresent(MatchCompletionMode.self, forKey: .matchCompletionMode) ?? .bestOf,
            usesNoAdScoring: try container.decodeIfPresent(Bool.self, forKey: .usesNoAdScoring) ?? false,
            autoChangeSides: try container.decodeIfPresent(Bool.self, forKey: .autoChangeSides) ?? true
        )
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

    public init(
        leftName: String,
        rightName: String,
        rules: TennisRuleSet = .init(),
        openingServer: MatchSide = .left
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
    }

    public var currentSet: Int { leftSets + rightSets + 1 }

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

public enum TennisMatchIntent: Codable, Equatable, Sendable {
    case pointWon(MatchSide)
    case adjustPoints(side: MatchSide, delta: Int)
    case adjustGames(side: MatchSide, delta: Int)
    case adjustSets(side: MatchSide, delta: Int)
    case setNames(left: String, right: String)
    case exchangeSides
    case finish
    case reset
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
}

public struct TennisMatchReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: TennisMatchState,
        intent: TennisMatchIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<TennisMatchState, TennisMatchEvent> {
        if state.finished {
            switch intent {
            case .reset: break
            default: return .rejected(state: state, reason: "Already finished")
            }
        }

        switch intent {
        case .pointWon(let side): return scorePoint(state: state, side: side)
        case .adjustPoints(let side, let delta):
            return adjust(state: state, side: side, delta: delta, keyPath: side == .left ? \.leftPoints : \.rightPoints, range: 0 ... (state.isTieBreak ? 999 : 4))
        case .adjustGames(let side, let delta):
            guard state.rules.setScoringMode != .tiebreakOnly else {
                return .rejected(state: state, reason: "Games are fixed in tiebreak-only format")
            }
            return adjust(
                state: state,
                side: side,
                delta: delta,
                keyPath: side == .left ? \.leftGames : \.rightGames,
                range: 0 ... (state.rules.gamesPerSet + 1)
            )
        case .adjustSets(let side, let delta):
            let maximum = max(1, state.rules.maxSets)
            return adjust(state: state, side: side, delta: delta, keyPath: side == .left ? \.leftSets : \.rightSets, range: 0 ... maximum)
        case .setNames(let left, let right):
            var next = state
            next.leftName = left.trimmingCharacters(in: .whitespacesAndNewlines)
            next.rightName = right.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(state: next, events: [.namesChanged])
        case .exchangeSides:
            let next = exchanged(state)
            return .init(state: next, events: [.sidesExchanged])
        case .finish:
            var next = state
            next.finished = true
            return .init(state: next, events: [.matchFinished(winner: matchWinner(for: next))])
        case .reset:
            let leftName = state.sidesSwapped ? state.rightName : state.leftName
            let rightName = state.sidesSwapped ? state.leftName : state.rightName
            return .init(
                state: .init(leftName: leftName, rightName: rightName, rules: state.rules, openingServer: state.openingServerSide),
                events: [.matchReset]
            )
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
                let crossedSixPointBoundary = pointsBefore > 0 && pointsBefore / 6 != (next.leftPoints + next.rightPoints) / 6
                if crossedSixPointBoundary { applySideChange(state: &next, events: &events) }
                next.servingSide = tieBreakServer(first: next.firstServerInSet, pointsPlayed: next.leftPoints + next.rightPoints)
            }
            return .init(state: next, events: events)
        }

        let winsGame: Bool
        if state.rules.usesNoAdScoring, next.leftPoints >= 3, next.rightPoints >= 3 {
            winsGame = next.leftPoints != next.rightPoints
        } else {
            winsGame = max(next.leftPoints, next.rightPoints) >= 4 && abs(next.leftPoints - next.rightPoints) >= 2
        }
        events.append(.pointScored(side: side, left: next.leftPoints, right: next.rightPoints))
        guard winsGame else { return .init(state: next, events: events) }

        let gameWinner: MatchSide = next.leftPoints > next.rightPoints ? .left : .right
        if gameWinner == .left { next.leftGames += 1 } else { next.rightGames += 1 }
        next.leftPoints = 0
        next.rightPoints = 0
        events.append(.gameCompleted(winner: gameWinner, leftGames: next.leftGames, rightGames: next.rightGames, tieBreak: false))

        if setWinner(next) == gameWinner {
            completeSet(state: &next, winner: gameWinner, events: &events)
        } else if next.leftGames == next.rules.gamesPerSet,
                  next.rightGames == next.rules.gamesPerSet {
            next.isTieBreak = true
            next.servingSide = next.firstServerInSet
        } else {
            if (next.leftGames + next.rightGames).isMultiple(of: 2) == false {
                applySideChange(state: &next, events: &events)
            }
            next.servingSide = (next.leftGames + next.rightGames).isMultiple(of: 2)
                ? next.firstServerInSet
                : next.firstServerInSet.opposite
        }
        return .init(state: next, events: events)
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
        state.firstServerInSet = completedGames.isMultiple(of: 2) ? state.firstServerInSet : state.firstServerInSet.opposite
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
        swap(&next.leftName, &next.rightName)
        swap(&next.leftPoints, &next.rightPoints)
        swap(&next.leftGames, &next.rightGames)
        swap(&next.leftSets, &next.rightSets)
        next.servingSide = next.servingSide.opposite
        next.openingServerSide = next.openingServerSide.opposite
        next.firstServerInSet = next.firstServerInSet.opposite
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

    private func matchWinner(left: Int, right: Int) -> MatchSide? {
        left == right ? nil : (left > right ? .left : .right)
    }

    private func matchWinner(for state: TennisMatchState) -> MatchSide? {
        state.rules.setScoringMode == .tiebreakOnly
            ? matchWinner(left: state.leftPoints, right: state.rightPoints)
            : matchWinner(left: state.leftSets, right: state.rightSets)
    }
}
