import Foundation

public struct BoxingMatchState: Codable, Equatable, Sendable {
    public var leftName: String
    public var rightName: String
    public var leftTotal: Int
    public var rightTotal: Int
    public var leftRoundsWon: Int
    public var rightRoundsWon: Int
    public var currentRound: Int
    public var maxRounds: Int
    public var sidesSwapped: Bool
    public var finished: Bool

    public init(
        leftName: String,
        rightName: String,
        maxRounds: Int = 3,
        leftTotal: Int = 0,
        rightTotal: Int = 0,
        leftRoundsWon: Int = 0,
        rightRoundsWon: Int = 0,
        currentRound: Int = 1,
        sidesSwapped: Bool = false,
        finished: Bool = false
    ) {
        self.leftName = leftName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rightName = rightName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.leftTotal = max(0, leftTotal)
        self.rightTotal = max(0, rightTotal)
        self.leftRoundsWon = max(0, leftRoundsWon)
        self.rightRoundsWon = max(0, rightRoundsWon)
        self.currentRound = max(1, currentRound)
        self.maxRounds = max(1, maxRounds)
        self.sidesSwapped = sidesSwapped
        self.finished = finished
    }
}

public enum BoxingMatchIntent: Codable, Equatable, Sendable {
    case submitRound(left: Int, right: Int)
    case addPoints(side: MatchSide, points: Int)
    case adjust(leftTotal: Int, rightTotal: Int, currentRound: Int, leftRoundsWon: Int, rightRoundsWon: Int)
    case setNames(left: String, right: String)
    case exchangeSides
    case nextRound
    case finish
    case reset
}

public enum BoxingMatchEvent: Codable, Equatable, Sendable {
    case pointsAdded(side: MatchSide, points: Int)
    case roundCompleted(round: Int, left: Int, right: Int)
    case roundAdvanced(Int)
    case adminAdjusted
    case namesChanged
    case sidesExchanged
    case matchFinished
    case matchReset
}

public struct BoxingMatchReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: BoxingMatchState,
        intent: BoxingMatchIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<BoxingMatchState, BoxingMatchEvent> {
        if state.finished {
            switch intent {
            case .adjust, .reset: break
            default: return .rejected(state: state, reason: "Already finished")
            }
        }

        var next = state
        switch intent {
        case .submitRound(let left, let right):
            let leftPoints = max(0, left)
            let rightPoints = max(0, right)
            guard leftPoints > 0 || rightPoints > 0 else {
                return .rejected(state: state, reason: "Invalid point value")
            }
            let completedRound = state.currentRound
            next.leftTotal += leftPoints
            next.rightTotal += rightPoints
            if leftPoints > rightPoints { next.leftRoundsWon += 1 }
            if rightPoints > leftPoints { next.rightRoundsWon += 1 }
            next.finished = completedRound >= state.maxRounds
            if !next.finished { next.currentRound += 1 }
            var events: [BoxingMatchEvent] = []
            if leftPoints > 0 { events.append(.pointsAdded(side: .left, points: leftPoints)) }
            if rightPoints > 0 { events.append(.pointsAdded(side: .right, points: rightPoints)) }
            events.append(.roundCompleted(round: completedRound, left: leftPoints, right: rightPoints))
            if next.finished { events.append(.matchFinished) } else { events.append(.roundAdvanced(next.currentRound)) }
            return .init(state: next, events: events)
        case .addPoints(let side, let points):
            let value = max(0, points)
            guard value > 0 else { return .rejected(state: state, reason: "Invalid point value") }
            if side == .left { next.leftTotal += value } else { next.rightTotal += value }
            return .init(state: next, events: [.pointsAdded(side: side, points: value)])
        case .adjust(let leftTotal, let rightTotal, let currentRound, let leftRoundsWon, let rightRoundsWon):
            next.leftTotal = max(0, leftTotal)
            next.rightTotal = max(0, rightTotal)
            next.currentRound = max(1, min(state.maxRounds, currentRound))
            next.leftRoundsWon = max(0, leftRoundsWon)
            next.rightRoundsWon = max(0, rightRoundsWon)
            next.finished = false
            return .init(state: next, events: [.adminAdjusted])
        case .setNames(let left, let right):
            next.leftName = left.trimmingCharacters(in: .whitespacesAndNewlines)
            next.rightName = right.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(state: next, events: [.namesChanged])
        case .exchangeSides:
            swap(&next.leftName, &next.rightName)
            swap(&next.leftTotal, &next.rightTotal)
            swap(&next.leftRoundsWon, &next.rightRoundsWon)
            next.sidesSwapped.toggle()
            return .init(state: next, events: [.sidesExchanged])
        case .nextRound:
            let round = state.currentRound + 1
            next.finished = round > state.maxRounds
            if !next.finished { next.currentRound = round }
            return .init(state: next, events: next.finished ? [.matchFinished] : [.roundAdvanced(round)])
        case .finish:
            next.finished = true
            return .init(state: next, events: [.matchFinished])
        case .reset:
            let leftName = state.sidesSwapped ? state.rightName : state.leftName
            let rightName = state.sidesSwapped ? state.leftName : state.rightName
            next = .init(leftName: leftName, rightName: rightName, maxRounds: state.maxRounds)
            return .init(state: next, events: [.matchReset])
        }
    }
}
