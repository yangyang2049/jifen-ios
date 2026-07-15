import Foundation
import ScoreCore

public enum BasketballClockProfile: String, Codable, Sendable {
    case standard
    case threeXThree

    public var initialShotClockSeconds: Int {
        switch self {
        case .standard: 24
        case .threeXThree: 12
        }
    }

    public var resetOptions: [Int] {
        switch self {
        case .standard: [14, 24]
        case .threeXThree: [12]
        }
    }
}

public struct BasketballClockState: Codable, Equatable, Sendable {
    public let profile: BasketballClockProfile
    public var gameClockSeconds: Int
    public var shotClockSeconds: Int
    public var period: Int
    public var isRunning: Bool
    public var isFinished: Bool

    public init(
        profile: BasketballClockProfile,
        gameClockSeconds: Int,
        shotClockSeconds: Int? = nil,
        period: Int = 1,
        isRunning: Bool = false,
        isFinished: Bool = false
    ) {
        self.profile = profile
        self.gameClockSeconds = max(0, gameClockSeconds)
        self.shotClockSeconds = max(0, shotClockSeconds ?? profile.initialShotClockSeconds)
        self.period = max(1, period)
        self.isRunning = isRunning
        self.isFinished = isFinished
    }
}

public enum BasketballClockIntent: Codable, Sendable {
    case start
    case pause
    case tick(seconds: Int)
    case resetShotClock(seconds: Int)
    case setPeriod(Int)
    case finish
}

public enum BasketballClockEvent: Codable, Equatable, Sendable {
    case clockStarted
    case clockPaused
    case clocksAdvanced(gameClockSeconds: Int, shotClockSeconds: Int)
    case shotClockReset(seconds: Int)
    case periodChanged(Int)
    case clockFinished
}

public struct BasketballClockReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: BasketballClockState,
        intent: BasketballClockIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<BasketballClockState, BasketballClockEvent> {
        var next = state
        switch intent {
        case .start:
            guard !state.isFinished else { return .rejected(state: state, reason: "Clock finished") }
            next.isRunning = true
            return .init(state: next, events: [.clockStarted])
        case .pause:
            next.isRunning = false
            return .init(state: next, events: [.clockPaused])
        case .tick(let seconds):
            guard state.isRunning else { return .rejected(state: state, reason: "Clock is paused") }
            guard seconds > 0 else { return .rejected(state: state, reason: "Tick must be positive") }
            next.gameClockSeconds = max(0, state.gameClockSeconds - seconds)
            next.shotClockSeconds = max(0, state.shotClockSeconds - seconds)
            if next.gameClockSeconds == 0 {
                next.isRunning = false
                next.isFinished = true
                return .init(state: next, events: [.clocksAdvanced(gameClockSeconds: 0, shotClockSeconds: next.shotClockSeconds), .clockFinished])
            }
            return .init(state: next, events: [.clocksAdvanced(gameClockSeconds: next.gameClockSeconds, shotClockSeconds: next.shotClockSeconds)])
        case .resetShotClock(let seconds):
            guard state.profile.resetOptions.contains(seconds) else {
                return .rejected(state: state, reason: "Unsupported shot clock reset")
            }
            next.shotClockSeconds = seconds
            return .init(state: next, events: [.shotClockReset(seconds: seconds)])
        case .setPeriod(let period):
            guard period > 0 else { return .rejected(state: state, reason: "Period must be positive") }
            next.period = period
            return .init(state: next, events: [.periodChanged(period)])
        case .finish:
            next.isRunning = false
            next.isFinished = true
            return .init(state: next, events: [.clockFinished])
        }
    }
}
