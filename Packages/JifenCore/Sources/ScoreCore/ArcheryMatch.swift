import Foundation

/// World Archery set-points rules (aligned with HOS `archeryReducer` / Android parity helpers).
public struct ArcheryMatchRules: Codable, Equatable, Sendable {
    public var normalArrowsPerSet: Int
    public var shootOffArrowsPerSet: Int
    public var setPointsToWin: Int
    public var setPointsWin: Int
    public var shootOffSetPointsWin: Int
    public var setPointsTie: Int

    public init(
        normalArrowsPerSet: Int = 3,
        shootOffArrowsPerSet: Int = 1,
        setPointsToWin: Int = 6,
        setPointsWin: Int = 2,
        shootOffSetPointsWin: Int = 1,
        setPointsTie: Int = 1
    ) {
        self.normalArrowsPerSet = max(1, normalArrowsPerSet)
        self.shootOffArrowsPerSet = max(1, shootOffArrowsPerSet)
        self.setPointsToWin = max(1, setPointsToWin)
        self.setPointsWin = max(1, setPointsWin)
        self.shootOffSetPointsWin = max(1, shootOffSetPointsWin)
        self.setPointsTie = max(0, setPointsTie)
    }

    public static let `default` = ArcheryMatchRules()
}

public struct ArcheryMatchState: Codable, Equatable, Sendable {
    public var leftName: String
    public var rightName: String
    public var leftArrowSum: Int
    public var rightArrowSum: Int
    public var leftSetPoints: Int
    public var rightSetPoints: Int
    public var currentSet: Int
    public var currentShooterIsLeft: Bool
    public var openingShooterIsLeft: Bool
    public var arrowsLeftThisSet: Int
    public var arrowsRightThisSet: Int
    public var arrowsPerSet: Int
    public var pendingSetNumber: Int
    public var pendingSetWinnerIsLeft: Bool?
    public var pendingLeftSetPoints: Int
    public var pendingRightSetPoints: Int
    public var closestToCenterPending: Bool
    public var finished: Bool
    public var sidesSwapped: Bool
    public var rules: ArcheryMatchRules

    public init(
        leftName: String,
        rightName: String,
        leftArrowSum: Int = 0,
        rightArrowSum: Int = 0,
        leftSetPoints: Int = 0,
        rightSetPoints: Int = 0,
        currentSet: Int = 1,
        currentShooterIsLeft: Bool = true,
        openingShooterIsLeft: Bool = true,
        arrowsLeftThisSet: Int = 0,
        arrowsRightThisSet: Int = 0,
        arrowsPerSet: Int? = nil,
        pendingSetNumber: Int = 0,
        pendingSetWinnerIsLeft: Bool? = nil,
        pendingLeftSetPoints: Int = 0,
        pendingRightSetPoints: Int = 0,
        closestToCenterPending: Bool = false,
        finished: Bool = false,
        sidesSwapped: Bool = false,
        rules: ArcheryMatchRules = .default
    ) {
        self.leftName = leftName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rightName = rightName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.leftArrowSum = max(0, leftArrowSum)
        self.rightArrowSum = max(0, rightArrowSum)
        self.leftSetPoints = max(0, leftSetPoints)
        self.rightSetPoints = max(0, rightSetPoints)
        self.currentSet = max(1, currentSet)
        self.currentShooterIsLeft = currentShooterIsLeft
        self.openingShooterIsLeft = openingShooterIsLeft
        self.arrowsLeftThisSet = max(0, arrowsLeftThisSet)
        self.arrowsRightThisSet = max(0, arrowsRightThisSet)
        self.arrowsPerSet = max(1, arrowsPerSet ?? rules.normalArrowsPerSet)
        self.pendingSetNumber = max(0, pendingSetNumber)
        self.pendingSetWinnerIsLeft = pendingSetWinnerIsLeft
        self.pendingLeftSetPoints = max(0, pendingLeftSetPoints)
        self.pendingRightSetPoints = max(0, pendingRightSetPoints)
        self.closestToCenterPending = closestToCenterPending
        self.finished = finished
        self.sidesSwapped = sidesSwapped
        self.rules = rules
    }

    public var isShootOffSet: Bool {
        arrowsPerSet == rules.shootOffArrowsPerSet
            && leftSetPoints == rules.setPointsToWin - 1
            && rightSetPoints == rules.setPointsToWin - 1
    }

    public var needsClosestToCenter: Bool {
        closestToCenterPending && !finished
    }

    public var setCompletionPending: Bool {
        pendingSetNumber > 0
    }

    public var winnerSide: MatchSide? {
        guard finished else { return nil }
        if leftSetPoints > rightSetPoints { return .left }
        if rightSetPoints > leftSetPoints { return .right }
        return nil
    }

    public var currentShooter: MatchSide {
        currentShooterIsLeft ? .left : .right
    }
}

public enum ArcheryMatchIntent: Codable, Equatable, Sendable {
    /// Record one arrow. `side` nil = current shooter; `value` nil = miss (0).
    case recordArrow(side: MatchSide?, value: Int?)
    /// Apply pending set end. For CTC shootoff ties, pass the winner.
    case completeSet(closestToCenterWinner: MatchSide?)
    case adjustArrowSum(side: MatchSide, delta: Int)
    case adjustSetPoints(side: MatchSide, delta: Int)
    case setNames(left: String, right: String)
    case setOpeningShooter(isLeft: Bool)
    case selectShooter(isLeft: Bool)
    case exchangeSides
    case finish
    case reset
}

public enum ArcheryMatchEvent: Codable, Equatable, Sendable {
    case arrowScored(side: MatchSide, points: Int, leftArrowSum: Int, rightArrowSum: Int)
    case setReady(setNumber: Int, leftArrowSum: Int, rightArrowSum: Int, pendingLeftSetPoints: Int, pendingRightSetPoints: Int)
    case closestToCenterRequired(setNumber: Int, tiedArrowSum: Int)
    case setCompleted(setNumber: Int, winner: MatchSide?, leftSetPoints: Int, rightSetPoints: Int)
    case matchFinished(winner: MatchSide?)
    case arrowSumAdjusted(side: MatchSide, delta: Int)
    case setPointsAdjusted(side: MatchSide, delta: Int)
    case namesChanged
    case openingShooterChanged
    case shooterSelected
    case sidesExchanged
    case matchReset
}

public struct ArcheryMatchReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: ArcheryMatchState,
        intent: ArcheryMatchIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<ArcheryMatchState, ArcheryMatchEvent> {
        _ = epochMilliseconds
        if state.finished {
            switch intent {
            case .adjustArrowSum, .adjustSetPoints, .setNames, .reset:
                break
            default:
                return .rejected(state: state, reason: "Already finished")
            }
        }

        var next = state
        switch intent {
        case .recordArrow(let side, let value):
            return recordArrow(state: state, side: side, value: value)
        case .completeSet(let closestWinner):
            return completeSet(state: state, closestToCenterWinner: closestWinner)
        case .adjustArrowSum(let side, let delta):
            if side == .left {
                next.leftArrowSum = max(0, next.leftArrowSum + delta)
            } else {
                next.rightArrowSum = max(0, next.rightArrowSum + delta)
            }
            return .init(state: next, events: [.arrowSumAdjusted(side: side, delta: delta)])
        case .adjustSetPoints(let side, let delta):
            if side == .left {
                next.leftSetPoints = max(0, next.leftSetPoints + delta)
            } else {
                next.rightSetPoints = max(0, next.rightSetPoints + delta)
            }
            next.pendingLeftSetPoints = next.leftSetPoints
            next.pendingRightSetPoints = next.rightSetPoints
            return .init(state: next, events: [.setPointsAdjusted(side: side, delta: delta)])
        case .setNames(let left, let right):
            next.leftName = left.trimmingCharacters(in: .whitespacesAndNewlines)
            next.rightName = right.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(state: next, events: [.namesChanged])
        case .setOpeningShooter(let isLeft):
            next.openingShooterIsLeft = isLeft
            if next.currentSet == 1 && next.arrowsLeftThisSet == 0 && next.arrowsRightThisSet == 0 {
                next.currentShooterIsLeft = isLeft
            }
            return .init(state: next, events: [.openingShooterChanged])
        case .selectShooter(let isLeft):
            guard !next.setCompletionPending else {
                return .rejected(state: state, reason: "Set completion pending")
            }
            next.currentShooterIsLeft = isLeft
            return .init(state: next, events: [.shooterSelected])
        case .exchangeSides:
            swap(&next.leftName, &next.rightName)
            swap(&next.leftArrowSum, &next.rightArrowSum)
            swap(&next.leftSetPoints, &next.rightSetPoints)
            swap(&next.arrowsLeftThisSet, &next.arrowsRightThisSet)
            swap(&next.pendingLeftSetPoints, &next.pendingRightSetPoints)
            if let pending = next.pendingSetWinnerIsLeft {
                next.pendingSetWinnerIsLeft = !pending
            }
            next.currentShooterIsLeft.toggle()
            next.openingShooterIsLeft.toggle()
            next.sidesSwapped.toggle()
            return .init(state: next, events: [.sidesExchanged])
        case .finish:
            next.finished = true
            clearPending(&next)
            return .init(state: next, events: [.matchFinished(winner: next.winnerSide)])
        case .reset:
            let leftName = state.sidesSwapped ? state.rightName : state.leftName
            let rightName = state.sidesSwapped ? state.leftName : state.rightName
            next = .init(
                leftName: leftName,
                rightName: rightName,
                currentShooterIsLeft: state.openingShooterIsLeft,
                openingShooterIsLeft: state.openingShooterIsLeft,
                rules: state.rules
            )
            return .init(state: next, events: [.matchReset])
        }
    }

    private func recordArrow(
        state: ArcheryMatchState,
        side: MatchSide?,
        value: Int?
    ) -> ReduceResult<ArcheryMatchState, ArcheryMatchEvent> {
        guard !state.setCompletionPending else {
            return .rejected(state: state, reason: "Set completion pending")
        }
        let shooter = side ?? state.currentShooter
        let arrowsUsed = shooter == .left ? state.arrowsLeftThisSet : state.arrowsRightThisSet
        guard arrowsUsed < state.arrowsPerSet else {
            return .rejected(state: state, reason: "Shooter has no arrows left in this set")
        }

        var next = state
        let points = Self.arrowPoints(value)
        if shooter == .left {
            next.leftArrowSum += points
            next.arrowsLeftThisSet += 1
        } else {
            next.rightArrowSum += points
            next.arrowsRightThisSet += 1
        }
        next.currentShooterIsLeft = shooter == .left ? false : true

        var events: [ArcheryMatchEvent] = [
            .arrowScored(
                side: shooter,
                points: points,
                leftArrowSum: next.leftArrowSum,
                rightArrowSum: next.rightArrowSum
            )
        ]

        if next.arrowsLeftThisSet >= next.arrowsPerSet && next.arrowsRightThisSet >= next.arrowsPerSet {
            prepareSetEnd(&next, events: &events)
        }
        return .init(state: next, events: events)
    }

    private func prepareSetEnd(
        _ state: inout ArcheryMatchState,
        events: inout [ArcheryMatchEvent]
    ) {
        state.pendingSetNumber = state.currentSet
        let shootOff = state.isShootOffSet
        if state.leftArrowSum > state.rightArrowSum {
            state.pendingSetWinnerIsLeft = true
        } else if state.rightArrowSum > state.leftArrowSum {
            state.pendingSetWinnerIsLeft = false
        } else {
            state.pendingSetWinnerIsLeft = nil
        }

        if shootOff && state.pendingSetWinnerIsLeft == nil {
            state.closestToCenterPending = true
            state.pendingLeftSetPoints = state.leftSetPoints
            state.pendingRightSetPoints = state.rightSetPoints
            events.append(
                .closestToCenterRequired(setNumber: state.currentSet, tiedArrowSum: state.leftArrowSum)
            )
            return
        }

        applyPendingSetPoints(&state)
        events.append(
            .setReady(
                setNumber: state.currentSet,
                leftArrowSum: state.leftArrowSum,
                rightArrowSum: state.rightArrowSum,
                pendingLeftSetPoints: state.pendingLeftSetPoints,
                pendingRightSetPoints: state.pendingRightSetPoints
            )
        )
    }

    private func applyPendingSetPoints(_ state: inout ArcheryMatchState) {
        let winPoints = state.isShootOffSet ? state.rules.shootOffSetPointsWin : state.rules.setPointsWin
        var left = state.leftSetPoints
        var right = state.rightSetPoints
        if state.pendingSetWinnerIsLeft == true {
            left += winPoints
        } else if state.pendingSetWinnerIsLeft == false {
            right += winPoints
        } else {
            left += state.rules.setPointsTie
            right += state.rules.setPointsTie
        }
        state.pendingLeftSetPoints = left
        state.pendingRightSetPoints = right
        state.closestToCenterPending = false
    }

    private func completeSet(
        state: ArcheryMatchState,
        closestToCenterWinner: MatchSide?
    ) -> ReduceResult<ArcheryMatchState, ArcheryMatchEvent> {
        guard state.setCompletionPending else {
            return .rejected(state: state, reason: "No set completion pending")
        }

        var next = state
        if next.closestToCenterPending {
            guard let winner = closestToCenterWinner else {
                return .rejected(state: state, reason: "Closest-to-center winner required")
            }
            next.pendingSetWinnerIsLeft = winner == .left
            next.pendingLeftSetPoints = next.leftSetPoints + (winner == .left ? next.rules.shootOffSetPointsWin : 0)
            next.pendingRightSetPoints = next.rightSetPoints + (winner == .right ? next.rules.shootOffSetPointsWin : 0)
            next.closestToCenterPending = false
        }

        let setNumber = next.pendingSetNumber
        let winner: MatchSide? = {
            if next.pendingSetWinnerIsLeft == true { return .left }
            if next.pendingSetWinnerIsLeft == false { return .right }
            return nil
        }()

        next.leftSetPoints = next.pendingLeftSetPoints
        next.rightSetPoints = next.pendingRightSetPoints

        var events: [ArcheryMatchEvent] = [
            .setCompleted(
                setNumber: setNumber,
                winner: winner,
                leftSetPoints: next.leftSetPoints,
                rightSetPoints: next.rightSetPoints
            )
        ]

        if next.leftSetPoints >= next.rules.setPointsToWin || next.rightSetPoints >= next.rules.setPointsToWin {
            next.finished = true
            clearPending(&next)
            events.append(.matchFinished(winner: next.winnerSide))
            return .init(state: next, events: events)
        }

        next.currentSet += 1
        next.leftArrowSum = 0
        next.rightArrowSum = 0
        next.arrowsLeftThisSet = 0
        next.arrowsRightThisSet = 0
        next.arrowsPerSet = (next.leftSetPoints == next.rules.setPointsToWin - 1
            && next.rightSetPoints == next.rules.setPointsToWin - 1)
            ? next.rules.shootOffArrowsPerSet
            : next.rules.normalArrowsPerSet
        next.currentShooterIsLeft = ArcheryShooterRules.nextStartingIsLeft(
            leftSetPoints: next.leftSetPoints,
            rightSetPoints: next.rightSetPoints,
            openingIsLeft: next.openingShooterIsLeft
        )
        clearPending(&next)
        return .init(state: next, events: events)
    }

    private func clearPending(_ state: inout ArcheryMatchState) {
        state.pendingSetNumber = 0
        state.pendingSetWinnerIsLeft = nil
        state.pendingLeftSetPoints = state.leftSetPoints
        state.pendingRightSetPoints = state.rightSetPoints
        state.closestToCenterPending = false
    }

    public static func arrowPoints(_ value: Int?) -> Int {
        guard let value else { return 0 }
        return max(0, min(10, value))
    }
}
