import Foundation

public struct LineScoreRuleSet: Codable, Equatable, Sendable {
    public var minimum: Int
    public var maximum: Int

    public init(minimum: Int = 0, maximum: Int = 9_999) {
        self.minimum = min(minimum, maximum)
        self.maximum = max(minimum, maximum)
    }

    public static let nonNegative = Self()
    public static let freeCounter = Self(minimum: -9_999, maximum: 9_999)

    public func clamp(_ value: Int) -> Int {
        min(maximum, max(minimum, value))
    }
}

public struct LineScoreState: Codable, Equatable, Sendable {
    public var rules: LineScoreRuleSet
    public var leftName: String
    public var rightName: String
    public var leftScore: Int
    public var rightScore: Int
    public var sidesSwapped: Bool
    public var finished: Bool

    public init(
        leftName: String,
        rightName: String,
        rules: LineScoreRuleSet = .nonNegative,
        leftScore: Int = 0,
        rightScore: Int = 0,
        sidesSwapped: Bool = false,
        finished: Bool = false
    ) {
        self.rules = rules
        self.leftName = leftName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rightName = rightName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.leftScore = rules.clamp(leftScore)
        self.rightScore = rules.clamp(rightScore)
        self.sidesSwapped = sidesSwapped
        self.finished = finished
    }
}

public enum LineScoreIntent: Codable, Equatable, Sendable {
    case pointWon(MatchSide)
    case adjust(side: MatchSide, delta: Int)
    case setNames(left: String, right: String)
    case exchangeSides
    case finish
    case reset
}

public enum LineScoreEvent: Codable, Equatable, Sendable {
    case scoreChanged(side: MatchSide, delta: Int, left: Int, right: Int)
    case namesChanged
    case sidesExchanged
    case matchFinished
    case matchReset
}

public struct LineScoreReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: LineScoreState,
        intent: LineScoreIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<LineScoreState, LineScoreEvent> {
        if state.finished {
            switch intent {
            case .reset: break
            default: return .rejected(state: state, reason: "Already finished")
            }
        }

        var next = state
        switch intent {
        case .pointWon(let side):
            return change(state: state, side: side, delta: 1)
        case .adjust(let side, let delta):
            guard delta != 0 else { return .rejected(state: state, reason: "No change") }
            return change(state: state, side: side, delta: delta)
        case .setNames(let left, let right):
            next.leftName = left.trimmingCharacters(in: .whitespacesAndNewlines)
            next.rightName = right.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(state: next, events: [.namesChanged])
        case .exchangeSides:
            swap(&next.leftName, &next.rightName)
            swap(&next.leftScore, &next.rightScore)
            next.sidesSwapped.toggle()
            return .init(state: next, events: [.sidesExchanged])
        case .finish:
            next.finished = true
            return .init(state: next, events: [.matchFinished])
        case .reset:
            let leftName = state.sidesSwapped ? state.rightName : state.leftName
            let rightName = state.sidesSwapped ? state.leftName : state.rightName
            next = .init(leftName: leftName, rightName: rightName, rules: state.rules)
            return .init(state: next, events: [.matchReset])
        }
    }

    private func change(
        state: LineScoreState,
        side: MatchSide,
        delta: Int
    ) -> ReduceResult<LineScoreState, LineScoreEvent> {
        var next = state
        let current = side == .left ? state.leftScore : state.rightScore
        let value = state.rules.clamp(current + delta)
        guard value != current else { return .rejected(state: state, reason: "Out of range") }
        if side == .left { next.leftScore = value } else { next.rightScore = value }
        return .init(state: next, events: [.scoreChanged(side: side, delta: value - current, left: next.leftScore, right: next.rightScore)])
    }
}
