import Foundation

public struct FootballMatchState: Codable, Equatable, Sendable {
    public var leftName: String
    public var rightName: String
    public var leftScore: Int
    public var rightScore: Int
    public var timer: FootballTimerStateV2
    public var stoppageHistory: [Int]
    public var isFiveAside: Bool
    public var kickedOff: Bool
    public var sidesSwapped: Bool
    public var finished: Bool

    // The shared timer stores whole seconds. Carry the remainder in the match
    // so consecutive actions can re-anchor the clock without discarding time.
    // It is part of the persisted and linked wire state: a peer that only
    // receives the whole-second anchor would drift by up to 1s per action.
    public fileprivate(set) var elapsedSubsecondMilliseconds: Int

    public init(
        leftName: String,
        rightName: String,
        leftScore: Int = 0,
        rightScore: Int = 0,
        timer: FootballTimerStateV2? = nil,
        stoppageHistory: [Int] = [],
        isFiveAside: Bool = false,
        kickedOff: Bool? = nil,
        sidesSwapped: Bool = false,
        finished: Bool = false,
        elapsedSubsecondMilliseconds: Int = 0
    ) {
        let timer = timer ?? FootballTimerStateV2(halfLengthSeconds: Self.defaultHalfLength(isFiveAside: isFiveAside))
        self.leftName = leftName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rightName = rightName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.leftScore = LineScoreRuleSet.nonNegative.clamp(leftScore)
        self.rightScore = LineScoreRuleSet.nonNegative.clamp(rightScore)
        self.timer = FootballTimerStateV2(
            stage: min(timer.stage, isFiveAside ? 2 : 4),
            halfLengthSeconds: timer.halfLengthSeconds,
            extraHalfLengthSeconds: timer.extraHalfLengthSeconds,
            elapsedSeconds: timer.elapsedSeconds,
            isRunning: timer.isRunning && !finished,
            savedWallClockMilliseconds: timer.savedWallClockMilliseconds,
            stoppageSeconds: isFiveAside ? [] : timer.stoppageSeconds.map { max(0, $0) }
        )
        self.stoppageHistory = isFiveAside ? [] : stoppageHistory.filter { $0 > 0 }
        self.isFiveAside = isFiveAside
        self.kickedOff = kickedOff ?? (!isFiveAside || timer.isRunning || timer.elapsedSeconds > 0 || timer.stage > 1)
        self.sidesSwapped = sidesSwapped
        self.finished = finished
        self.elapsedSubsecondMilliseconds = min(999, max(0, elapsedSubsecondMilliseconds))
        self.timer.elapsedSeconds = min(self.timer.elapsedSeconds, targetSeconds)
        if self.timer.elapsedSeconds == targetSeconds {
            self.timer.isRunning = false
        }
    }

    public var currentPeriodLengthSeconds: Int {
        max(0, timer.stage >= 3 ? timer.extraHalfLengthSeconds : timer.halfLengthSeconds)
    }

    public var currentStoppageSeconds: Int {
        guard !isFiveAside, (1...4).contains(timer.stage),
              timer.stoppageSeconds.indices.contains(timer.stage - 1) else { return 0 }
        return max(0, timer.stoppageSeconds[timer.stage - 1])
    }

    public var targetSeconds: Int {
        let length = currentPeriodLengthSeconds
        return length + min(currentStoppageSeconds, Int.max - length)
    }

    fileprivate static func defaultHalfLength(isFiveAside: Bool) -> Int {
        (isFiveAside ? FootballGoalMinute.defaultFiveASideHalfMinutes : FootballGoalMinute.regulationHalfMinutes) * 60
    }
}

public extension FootballMatchState {
    /// 只读显示用流逝秒数：与 Reducer 的锚点结算完全同源，但不改状态、
    /// 不入撤销栈、不产生网络帧（1 秒 UI 刷新专用）。
    func displayElapsedSeconds(at epochMilliseconds: Int64) -> Int {
        FootballMatchReducer.displayElapsedSeconds(state: self, at: epochMilliseconds)
    }

    /// 当前半场常规时间内的显示秒数（封顶到半场长度）。
    func mainDisplaySeconds(at epochMilliseconds: Int64) -> Int {
        min(displayElapsedSeconds(at: epochMilliseconds), currentPeriodLengthSeconds)
    }

    /// 超出常规时间后已进行的补时秒数。
    func stoppageElapsedSeconds(at epochMilliseconds: Int64) -> Int {
        max(0, displayElapsedSeconds(at: epochMilliseconds) - currentPeriodLengthSeconds)
    }

    /// 当前半场（含补时）是否已走完。
    func isPeriodCompleted(at epochMilliseconds: Int64) -> Bool {
        displayElapsedSeconds(at: epochMilliseconds) >= targetSeconds
    }

    /// 5 人制允许手动启停表；11 人制由开球/半场推进控制。
    var allowsManualClockPause: Bool { isFiveAside }

    /// 11 人制允许补时与加时。
    var allowsStoppageTime: Bool { !isFiveAside }
    var allowsExtraTime: Bool { !isFiveAside }
}

public enum FootballMatchIntent: Codable, Equatable, Sendable {
    case goal(side: MatchSide)
    case subtractGoal(side: MatchSide)
    case kickOff
    case toggleClock
    case startClock
    case pauseClock
    case addStoppage(seconds: Int)
    case undoLastStoppage
    case advanceStage
    case setNames(left: String, right: String)
    case exchangeSides
    case finish
    case reset(halfLengthSeconds: Int? = nil)
}

public enum FootballMatchEvent: Codable, Equatable, Sendable {
    case goalScored(side: MatchSide, leftScore: Int, rightScore: Int, period: Int, elapsedSeconds: Int)
    case goalSubtracted(side: MatchSide, leftScore: Int, rightScore: Int, period: Int, elapsedSeconds: Int)
    case kickedOff
    case clockToggled(isRunning: Bool, period: Int)
    case stoppageAdded(seconds: Int, period: Int)
    case stoppageUndone(seconds: Int, period: Int)
    case stageAdvanced(newStage: Int)
    case namesChanged
    case sidesExchanged
    case matchFinished(winner: MatchSide?)
    case matchReset
}

public struct FootballMatchReducer: DomainReducer {
    public init() {}

    public static func initial(
        leftName: String,
        rightName: String,
        isFiveAside: Bool = false,
        halfLengthSeconds: Int? = nil,
        extraHalfLengthSeconds: Int = FootballGoalMinute.extraHalfMinutes * 60,
        at epochMilliseconds: Int64
    ) -> FootballMatchState {
        FootballMatchState(
            leftName: leftName,
            rightName: rightName,
            timer: FootballTimerStateV2(
                halfLengthSeconds: halfLengthSeconds ?? FootballMatchState.defaultHalfLength(isFiveAside: isFiveAside),
                extraHalfLengthSeconds: extraHalfLengthSeconds,
                isRunning: !isFiveAside,
                savedWallClockMilliseconds: epochMilliseconds
            ),
            isFiveAside: isFiveAside,
            kickedOff: !isFiveAside
        )
    }

    public static func displayElapsedSeconds(state: FootballMatchState, at epochMilliseconds: Int64) -> Int {
        elapsedTime(in: state, at: epochMilliseconds).seconds
    }

    /// Materializes the running clock without recording an intent.
    public static func settleClock(state: FootballMatchState, at epochMilliseconds: Int64) -> FootballMatchState {
        var next = state
        let anchor = max(0, state.timer.savedWallClockMilliseconds, epochMilliseconds)
        let elapsed = elapsedTime(in: state, at: anchor)
        next.timer.savedWallClockMilliseconds = anchor
        next.timer.elapsedSeconds = elapsed.seconds
        next.elapsedSubsecondMilliseconds = elapsed.milliseconds
        if elapsed.seconds == state.targetSeconds {
            next.timer.isRunning = false
        }
        return next
    }

    public func reduce(
        state: FootballMatchState,
        intent: FootballMatchIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<FootballMatchState, FootballMatchEvent> {
        if state.finished {
            guard case .reset = intent else { return .rejected(state: state, reason: "Already finished") }
        }
        guard (1...(state.isFiveAside ? 2 : 4)).contains(state.timer.stage),
              state.timer.stoppageSeconds.count == 4 else {
            return .rejected(state: state, reason: "Invalid football period")
        }

        var next = Self.settleClock(state: state, at: epochMilliseconds)
        let anchor = next.timer.savedWallClockMilliseconds
        let elapsed = (seconds: next.timer.elapsedSeconds, milliseconds: next.elapsedSubsecondMilliseconds)

        let period = next.timer.stage
        let event: FootballMatchEvent
        switch intent {
        case .goal(let side), .subtractGoal(let side):
            let scored: Bool
            if case .goal = intent { scored = true } else { scored = false }
            let score = side == .left ? state.leftScore : state.rightScore
            let rules = LineScoreRuleSet.nonNegative
            guard rules.clamp(score) == score, scored ? score < rules.maximum : score > rules.minimum else {
                return .rejected(state: state, reason: "Goal count out of range")
            }
            let updated = score + (scored ? 1 : -1)
            if side == .left { next.leftScore = updated } else { next.rightScore = updated }
            if scored {
                event = .goalScored(side: side, leftScore: next.leftScore, rightScore: next.rightScore,
                                    period: period, elapsedSeconds: elapsed.seconds)
            } else {
                event = .goalSubtracted(side: side, leftScore: next.leftScore, rightScore: next.rightScore,
                                        period: period, elapsedSeconds: elapsed.seconds)
            }
        case .kickOff:
            guard !next.kickedOff, elapsed.seconds < next.targetSeconds else {
                return .rejected(state: state, reason: "Cannot kick off")
            }
            next.kickedOff = true
            next.timer.isRunning = true
            event = .kickedOff
        case .toggleClock, .startClock, .pauseClock:
            let shouldRun: Bool
            switch intent {
            case .toggleClock:
                guard next.isFiveAside else { return .rejected(state: state, reason: "Manual toggle unavailable") }
                shouldRun = !next.timer.isRunning
            case .startClock:
                shouldRun = true
            default:
                shouldRun = false
            }
            guard shouldRun != next.timer.isRunning, !shouldRun || elapsed.seconds < next.targetSeconds else {
                return .rejected(state: state, reason: "Clock cannot change")
            }
            next.timer.isRunning = shouldRun
            if shouldRun, !next.kickedOff {
                next.kickedOff = true
                event = .kickedOff
            } else {
                event = .clockToggled(isRunning: shouldRun, period: period)
            }
        case .addStoppage(let seconds):
            guard !next.isFiveAside, seconds > 0, seconds <= Int.max - next.targetSeconds else {
                return .rejected(state: state, reason: "Invalid stoppage time")
            }
            next.timer.stoppageSeconds[period - 1] = next.currentStoppageSeconds + seconds
            next.stoppageHistory.append(seconds)
            next.kickedOff = true
            next.timer.isRunning = true
            event = .stoppageAdded(seconds: seconds, period: period)
        case .undoLastStoppage:
            guard !next.isFiveAside, let seconds = next.stoppageHistory.last,
                  seconds > 0, seconds <= next.currentStoppageSeconds else {
                return .rejected(state: state, reason: "No stoppage time to undo")
            }
            let stoppage = next.currentStoppageSeconds - seconds
            let usedStoppage = max(0, elapsed.seconds - next.currentPeriodLengthSeconds)
            let hasFractionalStoppage = elapsed.seconds >= next.currentPeriodLengthSeconds && elapsed.milliseconds > 0
            guard stoppage > usedStoppage || (stoppage == usedStoppage && !hasFractionalStoppage) else {
                return .rejected(state: state, reason: "Stoppage time already played")
            }
            next.timer.stoppageSeconds[period - 1] = stoppage
            next.stoppageHistory.removeLast()
            if elapsed.seconds == next.targetSeconds { next.timer.isRunning = false }
            event = .stoppageUndone(seconds: seconds, period: period)
        case .advanceStage:
            guard period == 1 || (!next.isFiveAside && period < 4 && elapsed.seconds == next.targetSeconds) else {
                return .rejected(state: state, reason: "No available next period")
            }
            next.timer.stage += 1
            next.timer.elapsedSeconds = 0
            next.timer.isRunning = !next.isFiveAside
            next.kickedOff = true
            next.elapsedSubsecondMilliseconds = 0
            next.stoppageHistory.removeAll()
            event = .stageAdvanced(newStage: next.timer.stage)
        case .setNames(let left, let right):
            next.leftName = left.trimmingCharacters(in: .whitespacesAndNewlines)
            next.rightName = right.trimmingCharacters(in: .whitespacesAndNewlines)
            event = .namesChanged
        case .exchangeSides:
            next.sidesSwapped.toggle()
            event = .sidesExchanged
        case .finish:
            next.finished = true
            next.timer.isRunning = false
            let winner: MatchSide? = next.leftScore == next.rightScore ? nil : (next.leftScore > next.rightScore ? .left : .right)
            event = .matchFinished(winner: winner)
        case .reset(let halfLengthSeconds):
            return .init(
                state: Self.initial(
                    leftName: state.leftName,
                    rightName: state.rightName,
                    isFiveAside: state.isFiveAside,
                    halfLengthSeconds: halfLengthSeconds ?? state.timer.halfLengthSeconds,
                    extraHalfLengthSeconds: state.timer.extraHalfLengthSeconds,
                    at: anchor
                ),
                events: [.matchReset]
            )
        }
        return .init(state: next, events: [event])
    }

    private static func elapsedTime(
        in state: FootballMatchState,
        at epochMilliseconds: Int64
    ) -> (seconds: Int, milliseconds: Int) {
        let elapsed = min(max(0, state.timer.elapsedSeconds), state.targetSeconds)
        let remaining = state.targetSeconds - elapsed
        guard remaining > 0 else { return (elapsed, 0) }
        let remainder = min(999, max(0, state.elapsedSubsecondMilliseconds))
        guard state.timer.isRunning, !state.finished else { return (elapsed, remainder) }

        let anchor = max(0, state.timer.savedWallClockMilliseconds)
        let delta = max(anchor, epochMilliseconds) - anchor
        let milliseconds = Int(delta % 1_000) + remainder
        let seconds = Int(delta / 1_000) + milliseconds / 1_000
        return seconds < remaining ? (elapsed + seconds, milliseconds % 1_000) : (state.targetSeconds, 0)
    }
}
