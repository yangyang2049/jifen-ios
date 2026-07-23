import Foundation

public enum SnookerBall: Int, Codable, CaseIterable, Sendable {
    case red = 1, yellow, green, brown, blue, pink, black
}

public enum SnookerStage: String, Codable, Sendable {
    case red, color, yellow, green, brown, blue, pink, black, complete

    fileprivate var expectedBall: SnookerBall? {
        switch self {
        case .yellow: .yellow
        case .green: .green
        case .brown: .brown
        case .blue: .blue
        case .pink: .pink
        case .black: .black
        default: nil
        }
    }

    fileprivate var followingClearanceStage: Self {
        switch self {
        case .yellow: .green
        case .green: .brown
        case .brown: .blue
        case .blue: .pink
        case .pink: .black
        case .black: .complete
        default: self
        }
    }
}

public struct SnookerState: Codable, Equatable, Sendable {
    public var leftScore: Int
    public var rightScore: Int
    public var striker: MatchSide
    public var leftBreak: Int
    public var rightBreak: Int
    public var finished: Bool
    public var leftFrames: Int
    public var rightFrames: Int
    public var currentFrame: Int
    public var maxFrames: Int
    public var firstBreaker: MatchSide
    public var redBallsRemaining: Int
    public var nextBallStage: SnookerStage
    public var frameCompletePending: Bool
    public var pendingFrameWinner: MatchSide?

    public static func normalizedMaxFrames(_ value: Int) -> Int {
        let bounded = min(99, max(1, value))
        return bounded.isMultiple(of: 2) ? min(99, bounded + 1) : bounded
    }

    public static func framesToWin(_ maxFrames: Int) -> Int { normalizedMaxFrames(maxFrames) / 2 + 1 }

    public static func initial(striker: MatchSide = .left, maxFrames: Int = 1) -> Self {
        .init(
            leftScore: 0, rightScore: 0, striker: striker,
            leftBreak: 0, rightBreak: 0, finished: false,
            leftFrames: 0, rightFrames: 0, currentFrame: 1,
            maxFrames: normalizedMaxFrames(maxFrames), firstBreaker: striker,
            redBallsRemaining: 15, nextBallStage: .red,
            frameCompletePending: false, pendingFrameWinner: nil
        )
    }
}

public enum SnookerIntent: Codable, Sendable {
    case confirmStriker(MatchSide)
    case potBallAsSide(side: MatchSide, points: Int)
    case foulFromSide(side: MatchSide, pointsToOpponent: Int, switchTurn: Bool)
    case missFromPanel(MatchSide)
    case handoverFromPanel(MatchSide)
    case potBall(points: Int)
    case foul(pointsToOpponent: Int, switchTurn: Bool)
    case miss
    case handover
    case settleFrame(winner: MatchSide)
    case confirmNextFrame
    case finishMatch
    case adminCorrect(left: Int, right: Int, striker: MatchSide)
}

public enum SnookerEvent: Codable, Equatable, Sendable {
    case potted(Int)
    case foul(Int)
    case turnChanged(MatchSide)
    case frameSettled(winner: MatchSide, frame: Int)
    case nextFrameStarted(Int)
    case matchFinished
    case adminCorrected
}

public struct SnookerReducer: DomainReducer {
    public init() {}

    public func reduce(state: SnookerState, intent: SnookerIntent, at epochMilliseconds: Int64) -> ReduceResult<SnookerState, SnookerEvent> {
        if state.finished {
            if case .adminCorrect = intent {} else { return .rejected(state: state, reason: "Already finished") }
        }
        if state.frameCompletePending {
            switch intent {
            case .confirmNextFrame, .adminCorrect: break
            default: return .rejected(state: state, reason: "Frame pending confirmation")
            }
        }
        switch intent {
        case .confirmStriker(let side):
            var next = state
            next.striker = side
            next.leftBreak = 0
            next.rightBreak = 0
            return .init(state: next, events: [.turnChanged(side)])
        case .potBallAsSide(let side, let points):
            return pot(state: state, side: side, points: points)
        case .potBall(let points):
            return pot(state: state, side: state.striker, points: points)
        case .foulFromSide(let side, let points, let switchTurn):
            return foul(state: state, fouler: side, points: points, switchTurn: switchTurn)
        case .foul(let points, let switchTurn):
            return foul(state: state, fouler: state.striker, points: points, switchTurn: switchTurn)
        case .missFromPanel(let side), .handoverFromPanel(let side):
            return changeTurn(state: state, to: side.opposite)
        case .miss, .handover:
            return changeTurn(state: state, to: state.striker.opposite)
        case .settleFrame(let winner):
            return settle(state: state, winner: winner)
        case .confirmNextFrame:
            guard state.frameCompletePending else { return .rejected(state: state, reason: "No pending frame") }
            var next = freshFrame(from: state, frame: state.currentFrame + 1)
            next.frameCompletePending = false
            next.pendingFrameWinner = nil
            return .init(state: next, events: [.nextFrameStarted(next.currentFrame)])
        case .finishMatch:
            var next = state
            next.finished = true
            next.leftBreak = 0
            next.rightBreak = 0
            return .init(state: next, events: [.matchFinished])
        case .adminCorrect(let left, let right, let striker):
            var next = state
            next.leftScore = max(0, left)
            next.rightScore = max(0, right)
            next.striker = striker
            next.redBallsRemaining = min(15, max(0, next.redBallsRemaining))
            next.maxFrames = SnookerState.normalizedMaxFrames(next.maxFrames)
            return .init(state: next, events: [.adminCorrected])
        }
    }

    private func pot(state: SnookerState, side: MatchSide, points: Int) -> ReduceResult<SnookerState, SnookerEvent> {
        guard let ball = SnookerBall(rawValue: points) else { return .rejected(state: state, reason: "Invalid point value") }
        var next = state
        next.striker = side
        if side == .left {
            next.leftScore += points
            next.leftBreak += points
            next.rightBreak = 0
        } else {
            next.rightScore += points
            next.rightBreak += points
            next.leftBreak = 0
        }
        advanceBallFlow(&next, ball: ball)
        if next.nextBallStage == .complete {
            if next.leftScore == next.rightScore {
                next.nextBallStage = .black
            } else {
                let winner: MatchSide = next.leftScore > next.rightScore ? .left : .right
                let settled = settle(state: next, winner: winner, automatic: true)
                return .init(state: settled.state, events: [.potted(points)] + settled.events)
            }
        }
        return .init(state: next, events: [.potted(points)])
    }

    private func foul(state: SnookerState, fouler: MatchSide, points: Int, switchTurn: Bool) -> ReduceResult<SnookerState, SnookerEvent> {
        let gift = min(7, max(4, points))
        var next = state
        let opponent = fouler.opposite
        if opponent == .left { next.leftScore += gift } else { next.rightScore += gift }
        next.leftBreak = 0
        next.rightBreak = 0
        next.striker = switchTurn ? opponent : fouler
        normalizeStageAfterMiss(&next)
        var events: [SnookerEvent] = [.foul(gift)]
        if next.striker != state.striker { events.append(.turnChanged(next.striker)) }
        return .init(state: next, events: events)
    }

    private func changeTurn(state: SnookerState, to side: MatchSide) -> ReduceResult<SnookerState, SnookerEvent> {
        var next = state
        next.striker = side
        next.leftBreak = 0
        next.rightBreak = 0
        normalizeStageAfterMiss(&next)
        return .init(state: next, events: [.turnChanged(side)])
    }

    private func settle(state: SnookerState, winner: MatchSide, automatic: Bool = false) -> ReduceResult<SnookerState, SnookerEvent> {
        var next = state
        if winner == .left { next.leftFrames += 1 } else { next.rightFrames += 1 }
        let frame = state.currentFrame
        let matchFinished = next.leftFrames >= SnookerState.framesToWin(next.maxFrames) || next.rightFrames >= SnookerState.framesToWin(next.maxFrames)
        var events: [SnookerEvent] = [.frameSettled(winner: winner, frame: frame)]
        if matchFinished || next.maxFrames == 1 {
            next.finished = true
            next.leftBreak = 0
            next.rightBreak = 0
            events.append(.matchFinished)
        } else if automatic {
            next.leftBreak = 0
            next.rightBreak = 0
            next.frameCompletePending = true
            next.pendingFrameWinner = winner
        } else {
            next = freshFrame(from: next, frame: frame + 1)
        }
        return .init(state: next, events: events)
    }

    private func freshFrame(from state: SnookerState, frame: Int) -> SnookerState {
        var next = state
        next.leftScore = 0
        next.rightScore = 0
        next.leftBreak = 0
        next.rightBreak = 0
        next.currentFrame = frame
        next.striker = state.firstBreaker == .left ? (frame.isMultiple(of: 2) ? .right : .left) : (frame.isMultiple(of: 2) ? .left : .right)
        next.redBallsRemaining = 15
        next.nextBallStage = .red
        return next
    }

    private func advanceBallFlow(_ state: inout SnookerState, ball: SnookerBall) {
        if ball == .red {
            if state.redBallsRemaining > 0 {
                state.redBallsRemaining -= 1
                state.nextBallStage = .color
            }
        } else if state.nextBallStage == .color {
            state.nextBallStage = state.redBallsRemaining > 0 ? .red : .yellow
        } else if state.nextBallStage.expectedBall == ball {
            state.nextBallStage = state.nextBallStage.followingClearanceStage
        }
    }

    private func normalizeStageAfterMiss(_ state: inout SnookerState) {
        if state.redBallsRemaining > 0 {
            state.nextBallStage = .red
        } else if state.nextBallStage == .red {
            state.nextBallStage = .color
        }
    }
}
