import Foundation

public enum KeyPointKind: Int, Codable, Equatable, Sendable {
    case game = 1
    case set = 2
    case match = 3
}

public struct KeyPointStatus: Codable, Equatable, Sendable {
    public let kind: KeyPointKind
    public let side: MatchSide

    public init(kind: KeyPointKind, side: MatchSide) {
        self.kind = kind
        self.side = side
    }
}

public struct TennisKeyPointSnapshot: Equatable, Sendable {
    public var leftPoints: Int
    public var rightPoints: Int
    public var leftGames: Int
    public var rightGames: Int
    public var leftSets: Int
    public var rightSets: Int
    public var maxSets: Int
    public var matchCompletionMode: MatchCompletionMode
    public var isTieBreak: Bool
    public var tieBreakTarget: Int
    public var usesNoAdScoring: Bool
    public var finished: Bool

    public init(
        leftPoints: Int,
        rightPoints: Int,
        leftGames: Int,
        rightGames: Int,
        leftSets: Int,
        rightSets: Int,
        maxSets: Int,
        matchCompletionMode: MatchCompletionMode,
        isTieBreak: Bool,
        tieBreakTarget: Int,
        usesNoAdScoring: Bool,
        finished: Bool
    ) {
        self.leftPoints = leftPoints
        self.rightPoints = rightPoints
        self.leftGames = leftGames
        self.rightGames = rightGames
        self.leftSets = leftSets
        self.rightSets = rightSets
        self.maxSets = maxSets
        self.matchCompletionMode = matchCompletionMode
        self.isTieBreak = isTieBreak
        self.tieBreakTarget = tieBreakTarget
        self.usesNoAdScoring = usesNoAdScoring
        self.finished = finished
    }
}

public enum KeyPointResolver {
    public static func rally(state: RallyMatchState) -> KeyPointStatus? {
        guard !state.finished, rallySetWinner(state: state) == nil else { return nil }
        let reducer = RallyMatchReducer()
        let left = rallyKind(
            reducer.reduce(state: state, intent: .pointWon(.left), at: 0).events
        )
        let right = rallyKind(
            reducer.reduce(state: state, intent: .pointWon(.right), at: 0).events
        )
        return resolve(left: left, right: right)
    }

    public static func tennis(snapshot: TennisKeyPointSnapshot) -> KeyPointStatus? {
        guard !snapshot.finished else { return nil }
        let left = tennisKind(afterNextPointFor: .left, snapshot: snapshot)
        let right = tennisKind(afterNextPointFor: .right, snapshot: snapshot)
        return resolve(left: left, right: right)
    }

    private static func rallyKind(_ events: [RallyMatchEvent]) -> KeyPointKind? {
        if events.contains(where: { event in
            if case .matchFinished = event { return true }
            return false
        }) {
            return .match
        }
        if events.contains(where: { event in
            if case .setCompleted = event { return true }
            return false
        }) {
            return .game
        }
        return nil
    }

    private static func rallySetWinner(state: RallyMatchState) -> MatchSide? {
        let setNumber = state.currentSet
        let rules = state.rules
        let target = rules.target(for: setNumber)
        let cap = setNumber == rules.maxSets ? rules.finalSetPointCap ?? rules.pointCap : rules.pointCap
        if let cap, max(state.leftPoints, state.rightPoints) >= cap {
            guard state.leftPoints != state.rightPoints else { return nil }
            return state.leftPoints > state.rightPoints ? .left : .right
        }
        let winByTwo = setNumber == rules.maxSets ? rules.finalSetWinByTwo ?? rules.winByTwo : rules.winByTwo
        if winByTwo, abs(state.leftPoints - state.rightPoints) < 2 { return nil }
        if state.leftPoints >= target { return .left }
        if state.rightPoints >= target { return .right }
        return nil
    }

    private static func tennisKind(
        afterNextPointFor side: MatchSide,
        snapshot: TennisKeyPointSnapshot
    ) -> KeyPointKind? {
        var leftPoints = snapshot.leftPoints
        var rightPoints = snapshot.rightPoints
        if side == .left { leftPoints += 1 } else { rightPoints += 1 }

        let winsGame: Bool
        if snapshot.isTieBreak {
            winsGame = max(leftPoints, rightPoints) >= max(1, snapshot.tieBreakTarget)
                && abs(leftPoints - rightPoints) >= 2
        } else if snapshot.usesNoAdScoring && snapshot.leftPoints >= 3 && snapshot.rightPoints >= 3 {
            winsGame = leftPoints != rightPoints
        } else {
            winsGame = max(leftPoints, rightPoints) >= 4 && abs(leftPoints - rightPoints) >= 2
        }
        guard winsGame else { return nil }

        var leftGames = snapshot.leftGames
        var rightGames = snapshot.rightGames
        if side == .left { leftGames += 1 } else { rightGames += 1 }
        let winsSet = (leftGames >= 6 && leftGames - rightGames >= 2)
            || (rightGames >= 6 && rightGames - leftGames >= 2)
            || (leftGames == 7 && rightGames == 6)
            || (rightGames == 7 && leftGames == 6)
        guard winsSet else { return nil }

        var leftSets = snapshot.leftSets
        var rightSets = snapshot.rightSets
        if side == .left { leftSets += 1 } else { rightSets += 1 }
        return snapshot.matchCompletionMode.isMatchFinished(
            maxSets: snapshot.maxSets,
            leftSets: leftSets,
            rightSets: rightSets
        ) ? .match : .set
    }

    private static func resolve(left: KeyPointKind?, right: KeyPointKind?) -> KeyPointStatus? {
        switch (left, right) {
        case let (.some(leftKind), .some(rightKind)) where leftKind.rawValue > rightKind.rawValue:
            return KeyPointStatus(kind: leftKind, side: .left)
        case let (.some(leftKind), .some(rightKind)) where rightKind.rawValue > leftKind.rawValue:
            return KeyPointStatus(kind: rightKind, side: .right)
        case (.some, .some):
            return nil
        case let (.some(kind), .none):
            return KeyPointStatus(kind: kind, side: .left)
        case let (.none, .some(kind)):
            return KeyPointStatus(kind: kind, side: .right)
        case (.none, .none):
            return nil
        }
    }
}
