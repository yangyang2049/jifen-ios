import Foundation

public enum RallyServingModel: String, Codable, Sendable {
    case scorerServes
    case pingPongTwoServes
}

public struct RallyRuleSet: Codable, Equatable, Sendable {
    public var maxSets: Int
    public var pointsToWinSet: Int
    public var pointCap: Int?
    public var winByTwo: Bool
    public var finalSetPointsToWin: Int?
    public var decidingSetSideSwitchPoint: Int?
    public var autoChangeSides: Bool
    public var servingModel: RallyServingModel

    public init(
        maxSets: Int,
        pointsToWinSet: Int,
        pointCap: Int? = nil,
        winByTwo: Bool = true,
        finalSetPointsToWin: Int? = nil,
        decidingSetSideSwitchPoint: Int? = nil,
        autoChangeSides: Bool = false,
        servingModel: RallyServingModel = .scorerServes
    ) {
        self.maxSets = max(1, maxSets)
        self.pointsToWinSet = max(1, pointsToWinSet)
        self.pointCap = pointCap
        self.winByTwo = winByTwo
        self.finalSetPointsToWin = finalSetPointsToWin
        self.decidingSetSideSwitchPoint = decidingSetSideSwitchPoint
        self.autoChangeSides = autoChangeSides
        self.servingModel = servingModel
    }

    public var setsToWin: Int { (maxSets + 1) / 2 }

    public func target(for setNumber: Int) -> Int {
        setNumber == maxSets ? finalSetPointsToWin ?? pointsToWinSet : pointsToWinSet
    }

    public static func pingPong(maxSets: Int = 5) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: 11,
            decidingSetSideSwitchPoint: 5,
            servingModel: .pingPongTwoServes
        )
    }

    public static func badminton(maxSets: Int = 3) -> Self {
        .init(maxSets: maxSets, pointsToWinSet: 21, pointCap: 30, decidingSetSideSwitchPoint: 11)
    }

    public static func pickleball(maxSets: Int = 3) -> Self {
        .init(maxSets: maxSets, pointsToWinSet: 11, pointCap: 15)
    }

    public static func volleyball(maxSets: Int = 5) -> Self {
        .init(maxSets: maxSets, pointsToWinSet: 25, finalSetPointsToWin: 15, decidingSetSideSwitchPoint: 8)
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

    public var currentSet: Int { leftSets + rightSets + 1 }
}

public enum RallyMatchIntent: Codable, Sendable {
    case pointWon(MatchSide)
    case setNames(left: String, right: String)
    case exchangeSides
    case finish
    case reset
}

public enum RallyMatchEvent: Codable, Equatable, Sendable {
    case pointScored(side: MatchSide, leftPoints: Int, rightPoints: Int)
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
        openingServer: MatchSide = .left
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
            sidesSwapped: false
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
                openingServer: state.openingServerSide
            )
            return .init(state: reset, events: [.matchReset])
        }
    }

    private func pointWon(_ side: MatchSide, state: RallyMatchState) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        guard !state.finished else { return .rejected(state: state, reason: "Match is already finished") }
        var next = state
        if side == .left { next.leftPoints += 1 } else { next.rightPoints += 1 }
        if let cap = state.rules.pointCap {
            next.leftPoints = min(next.leftPoints, cap)
            next.rightPoints = min(next.rightPoints, cap)
        }
        next.servingSide = nextServer(after: side, state: next)
        var events: [RallyMatchEvent] = [.pointScored(side: side, leftPoints: next.leftPoints, rightPoints: next.rightPoints)]

        let setNumber = state.currentSet
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
            if next.leftSets >= next.rules.setsToWin || next.rightSets >= next.rules.setsToWin {
                next.finished = true
                events.append(.matchFinished(winner: setWinner))
                return .init(state: next, events: events)
            }
            next.leftPoints = 0
            next.rightPoints = 0
            next.firstServerInSet = nextFirstServer(for: next)
            next.servingSide = next.firstServerInSet
            if next.rules.autoChangeSides {
                next = exchanged(next)
                events.append(.sidesExchanged)
            }
            return .init(state: next, events: events)
        }

        if shouldRemindSideChange(previous: state, next: next) {
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
        if let cap = state.rules.pointCap, max(state.leftPoints, state.rightPoints) >= cap {
            return state.leftPoints == state.rightPoints ? nil : (state.leftPoints > state.rightPoints ? .left : .right)
        }
        if state.rules.winByTwo {
            guard abs(state.leftPoints - state.rightPoints) >= 2 else { return nil }
        }
        if state.leftPoints >= target { return .left }
        if state.rightPoints >= target { return .right }
        return nil
    }

    private func nextServer(after scorer: MatchSide, state: RallyMatchState) -> MatchSide {
        guard state.rules.servingModel == .pingPongTwoServes else { return scorer }
        let total = state.leftPoints + state.rightPoints
        let deuce = state.leftPoints >= state.rules.target(for: state.currentSet) - 1 && state.rightPoints >= state.rules.target(for: state.currentSet) - 1
        let turns = deuce ? total : total / 2
        return turns.isMultiple(of: 2) ? state.firstServerInSet : state.firstServerInSet.opposite
    }

    private func nextFirstServer(for state: RallyMatchState) -> MatchSide {
        guard state.rules.servingModel == .pingPongTwoServes else { return state.servingSide }
        return state.currentSet.isMultiple(of: 2) ? state.openingServerSide.opposite : state.openingServerSide
    }

    private func shouldRemindSideChange(previous: RallyMatchState, next: RallyMatchState) -> Bool {
        guard previous.currentSet == previous.rules.maxSets,
              let point = previous.rules.decidingSetSideSwitchPoint else { return false }
        return max(previous.leftPoints, previous.rightPoints) < point && max(next.leftPoints, next.rightPoints) >= point
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
