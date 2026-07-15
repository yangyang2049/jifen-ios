import Foundation

public enum BasketballGameMode: String, Codable, Sendable {
    case fiveVFive = "five_v_five"
    case threeXThree = "three_x_three"
}

public enum BasketballRuleSet: String, Codable, Sendable {
    case fiba
    case nba
}

public struct BasketballTimeoutPools: Codable, Equatable, Sendable {
    public var leftFirstHalf: Int
    public var rightFirstHalf: Int
    public var leftSecondHalf: Int
    public var rightSecondHalf: Int
    public var leftRegular: Int
    public var rightRegular: Int
    public var leftOvertime: Int
    public var rightOvertime: Int

    public init(
        leftFirstHalf: Int = 2,
        rightFirstHalf: Int = 2,
        leftSecondHalf: Int = 3,
        rightSecondHalf: Int = 3,
        leftRegular: Int = 7,
        rightRegular: Int = 7,
        leftOvertime: Int = 1,
        rightOvertime: Int = 1
    ) {
        self.leftFirstHalf = leftFirstHalf
        self.rightFirstHalf = rightFirstHalf
        self.leftSecondHalf = leftSecondHalf
        self.rightSecondHalf = rightSecondHalf
        self.leftRegular = leftRegular
        self.rightRegular = rightRegular
        self.leftOvertime = leftOvertime
        self.rightOvertime = rightOvertime
    }
}

public struct BasketballMatchState: Codable, Equatable, Sendable {
    public var leftName: String
    public var rightName: String
    public var leftScore: Int
    public var rightScore: Int
    public var leftFouls: Int
    public var rightFouls: Int
    public var sidesSwapped: Bool
    public var finished: Bool
    public var gameMode: BasketballGameMode
    public var ruleSet: BasketballRuleSet
    public var currentPeriod: Int
    public var periodEnded: Bool
    public var canAdvancePeriod: Bool
    public var isOvertime: Bool
    public var overtimeStartScore: Int
    public var gameTimeSeconds: Int
    public var shotTimeSeconds: Int
    public var gameRunning: Bool
    public var shotRunning: Bool
    public var timeoutPools: BasketballTimeoutPools
    public var leftTimeouts: Int
    public var rightTimeouts: Int

    public init(
        leftName: String,
        rightName: String,
        gameMode: BasketballGameMode,
        ruleSet: BasketballRuleSet = .fiba,
        leftScore: Int = 0,
        rightScore: Int = 0,
        leftFouls: Int = 0,
        rightFouls: Int = 0,
        sidesSwapped: Bool = false,
        finished: Bool = false,
        currentPeriod: Int = 1,
        periodEnded: Bool = false,
        canAdvancePeriod: Bool = false,
        isOvertime: Bool = false,
        overtimeStartScore: Int = 0,
        gameTimeSeconds: Int? = nil,
        shotTimeSeconds: Int? = nil,
        gameRunning: Bool = false,
        shotRunning: Bool = false,
        timeoutPools: BasketballTimeoutPools? = nil,
        leftTimeouts: Int? = nil,
        rightTimeouts: Int? = nil
    ) {
        let defaultGameTime = gameMode == .threeXThree ? 10 * 60 : BasketballMatchEngine.periodSeconds(ruleSet)
        let defaultShotTime = BasketballMatchEngine.defaultShotSeconds(gameMode)
        let pools = timeoutPools ?? BasketballMatchEngine.defaultTimeoutPools(ruleSet)
        let active = BasketballMatchEngine.activeTimeouts(
            gameMode: gameMode,
            ruleSet: ruleSet,
            pools: pools,
            currentPeriod: currentPeriod,
            isOvertime: isOvertime
        )

        self.leftName = leftName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rightName = rightName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.leftScore = max(0, leftScore)
        self.rightScore = max(0, rightScore)
        self.leftFouls = max(0, leftFouls)
        self.rightFouls = max(0, rightFouls)
        self.sidesSwapped = sidesSwapped
        self.finished = finished
        self.gameMode = gameMode
        self.ruleSet = ruleSet
        self.currentPeriod = max(1, min(currentPeriod, 4))
        self.periodEnded = periodEnded
        self.canAdvancePeriod = canAdvancePeriod
        self.isOvertime = isOvertime
        self.overtimeStartScore = max(0, overtimeStartScore)
        self.gameTimeSeconds = max(0, gameTimeSeconds ?? defaultGameTime)
        self.shotTimeSeconds = max(0, shotTimeSeconds ?? defaultShotTime)
        self.gameRunning = gameRunning && !finished
        self.shotRunning = shotRunning && !finished
        self.timeoutPools = pools
        self.leftTimeouts = max(0, leftTimeouts ?? active.left)
        self.rightTimeouts = max(0, rightTimeouts ?? active.right)
    }
}

public enum BasketballMatchIntent: Codable, Equatable, Sendable {
    case addPoints(side: MatchSide, points: Int, resetShotClock: Bool = true)
    case adjustScore(side: MatchSide, delta: Int)
    case addFoul(side: MatchSide)
    case removeFoul(side: MatchSide)
    case rename(side: MatchSide, name: String)
    case setRuleSet(BasketballRuleSet)
    case setClockRunning(Bool)
    case tickClock
    case resetGameClock
    case resetShotClock(seconds: Int? = nil)
    case advanceToNextPeriod
    case enterOvertime
    case selectPeriod(Int)
    case useTimeout(side: MatchSide)
    case adjustTimeout(side: MatchSide, delta: Int)
    case exchangeSides
    case reset
    case finish
}

public enum BasketballMatchEvent: Codable, Equatable, Sendable {
    case stateChanged(
        at: Int64,
        intent: BasketballMatchIntent,
        before: BasketballMatchState,
        after: BasketballMatchState
    )
}

public enum BasketballMatchEngine {
    public static func initial(
        leftName: String,
        rightName: String,
        gameMode: BasketballGameMode,
        ruleSet: BasketballRuleSet = .fiba
    ) -> BasketballMatchState {
        BasketballMatchState(leftName: leftName, rightName: rightName, gameMode: gameMode, ruleSet: ruleSet)
    }

    public static func hasPeriods(_ state: BasketballMatchState) -> Bool {
        state.gameMode == .fiveVFive
    }

    public static func defaultShotSeconds(_ gameMode: BasketballGameMode) -> Int {
        gameMode == .threeXThree ? 12 : 24
    }

    public static func periodSeconds(_ ruleSet: BasketballRuleSet) -> Int {
        ruleSet == .nba ? 12 * 60 : 10 * 60
    }

    public static func overtimeSeconds() -> Int { 5 * 60 }

    public static func scoringButtons(_ state: BasketballMatchState) -> [Int] {
        state.gameMode == .threeXThree ? [1, 2] : [1, 2, 3]
    }

    public static func foulDisplayLimit(_ state: BasketballMatchState) -> Int {
        state.gameMode == .threeXThree ? 10 : 5
    }

    public static func bonusThreshold(_ state: BasketballMatchState) -> Int {
        state.gameMode == .threeXThree ? 7 : 5
    }

    public static func doubleBonusThreshold(_ state: BasketballMatchState) -> Int {
        state.gameMode == .threeXThree ? 10 : 0
    }

    public static func addPoints(_ state: BasketballMatchState, side: MatchSide, points: Int) -> BasketballMatchState {
        guard !state.finished, points > 0 else { return state }
        var next = state
        if side == .left {
            next.leftScore += points
        } else {
            next.rightScore += points
        }
        return maybeFinishAfterScore(next)
    }

    public static func adjustScore(_ state: BasketballMatchState, side: MatchSide, delta: Int) -> BasketballMatchState {
        guard !state.finished, delta != 0 else { return state }
        var next = state
        if side == .left {
            next.leftScore = max(0, next.leftScore + delta)
        } else {
            next.rightScore = max(0, next.rightScore + delta)
        }
        return next == state ? state : maybeFinishAfterScore(next)
    }

    public static func addFoul(_ state: BasketballMatchState, side: MatchSide) -> BasketballMatchState {
        guard !state.finished else { return state }
        var next = state
        if side == .left { next.leftFouls += 1 } else { next.rightFouls += 1 }
        return next
    }

    public static func removeFoul(_ state: BasketballMatchState, side: MatchSide) -> BasketballMatchState {
        guard !state.finished else { return state }
        var next = state
        if side == .left {
            guard next.leftFouls > 0 else { return state }
            next.leftFouls -= 1
        } else {
            guard next.rightFouls > 0 else { return state }
            next.rightFouls -= 1
        }
        return next
    }

    public static func rename(_ state: BasketballMatchState, side: MatchSide, name: String) -> BasketballMatchState {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return state }
        var next = state
        if side == .left { next.leftName = trimmed } else { next.rightName = trimmed }
        return next
    }

    public static func exchangeSides(_ state: BasketballMatchState) -> BasketballMatchState {
        guard !state.finished else { return state }
        var next = state
        next.sidesSwapped.toggle()
        return next
    }

    public static func finish(_ state: BasketballMatchState) -> BasketballMatchState {
        guard !state.finished else { return state }
        var next = state
        next.finished = true
        next.gameRunning = false
        next.shotRunning = false
        return next
    }

    public static func reset(_ state: BasketballMatchState) -> BasketballMatchState {
        initial(leftName: state.leftName, rightName: state.rightName, gameMode: state.gameMode, ruleSet: state.ruleSet)
    }

    public static func setRuleSet(_ state: BasketballMatchState, ruleSet: BasketballRuleSet) -> BasketballMatchState {
        var next = state
        next.ruleSet = ruleSet
        if next.gameMode == .fiveVFive && !next.isOvertime {
            next.gameTimeSeconds = periodSeconds(ruleSet)
        }
        next.timeoutPools.leftOvertime = ruleSet == .nba ? 2 : 1
        next.timeoutPools.rightOvertime = ruleSet == .nba ? 2 : 1
        return refreshActiveTimeouts(next)
    }

    public static func setClockRunning(_ state: BasketballMatchState, running: Bool) -> BasketballMatchState {
        guard !state.finished else { return state }
        var next = state
        next.gameRunning = running
        next.shotRunning = running
        return next
    }

    public static func tickClock(_ state: BasketballMatchState) -> BasketballMatchState {
        guard state.gameRunning, !state.periodEnded, !state.finished else { return state }
        if state.gameMode == .threeXThree && state.isOvertime {
            guard state.shotRunning, state.shotTimeSeconds > 0 else { return state }
            var next = state
            next.shotTimeSeconds -= 1
            return next
        }
        guard state.gameTimeSeconds > 0 else { return state }

        var next = state
        next.gameTimeSeconds -= 1
        if next.shotRunning, next.shotTimeSeconds > 0 {
            next.shotTimeSeconds -= 1
        }
        guard next.gameTimeSeconds == 0 else { return next }

        next.gameRunning = false
        next.shotRunning = false
        if next.gameMode == .threeXThree {
            return next.leftScore == next.rightScore ? startThreeXThreeOvertime(next) : finish(next)
        }
        return handleFiveVFivePeriodExpired(next)
    }

    public static func resetGameClock(_ state: BasketballMatchState) -> BasketballMatchState {
        var next = state
        next.gameRunning = false
        next.shotRunning = false
        next.periodEnded = false
        next.canAdvancePeriod = false
        next.isOvertime = false
        next.overtimeStartScore = 0
        next.gameTimeSeconds = next.gameMode == .threeXThree ? 10 * 60 : periodSeconds(next.ruleSet)
        next.shotTimeSeconds = defaultShotSeconds(next.gameMode)
        return next
    }

    public static func resetShotClock(_ state: BasketballMatchState, seconds: Int? = nil) -> BasketballMatchState {
        var next = state
        next.shotTimeSeconds = max(0, seconds ?? defaultShotSeconds(next.gameMode))
        return next
    }

    public static func advanceToNextPeriod(_ state: BasketballMatchState) -> BasketballMatchState {
        guard state.gameMode == .fiveVFive, state.canAdvancePeriod, !state.finished else { return state }
        if state.isOvertime { return enterFiveVFiveOvertime(state) }
        guard state.currentPeriod < 4 else { return state }

        let previousPeriod = state.currentPeriod
        var next = state
        next.currentPeriod += 1
        next.leftFouls = 0
        next.rightFouls = 0
        next.periodEnded = false
        next.canAdvancePeriod = false
        next.isOvertime = false
        next.overtimeStartScore = 0
        next.gameTimeSeconds = periodSeconds(next.ruleSet)
        next.shotTimeSeconds = defaultShotSeconds(next.gameMode)
        next.gameRunning = false
        next.shotRunning = false
        return next.ruleSet == .fiba && previousPeriod == 2 ? refreshActiveTimeouts(next) : next
    }

    public static func enterFiveVFiveOvertime(_ state: BasketballMatchState) -> BasketballMatchState {
        guard state.gameMode == .fiveVFive else { return state }
        var next = state
        next.timeoutPools.leftOvertime = next.ruleSet == .nba ? 2 : 1
        next.timeoutPools.rightOvertime = next.ruleSet == .nba ? 2 : 1
        next.isOvertime = true
        next.periodEnded = false
        next.canAdvancePeriod = false
        next.overtimeStartScore = next.leftScore
        next.gameTimeSeconds = overtimeSeconds()
        next.shotTimeSeconds = defaultShotSeconds(next.gameMode)
        next.leftFouls = 0
        next.rightFouls = 0
        next.finished = false
        next.gameRunning = false
        next.shotRunning = false
        return refreshActiveTimeouts(next)
    }

    public static func selectPeriod(_ state: BasketballMatchState, period: Int) -> BasketballMatchState {
        guard state.gameMode == .fiveVFive else { return state }
        let target = min(max(period, 1), 4)
        guard !state.isOvertime, target != state.currentPeriod else { return state }
        var next = state
        next.currentPeriod = target
        next.isOvertime = false
        next.overtimeStartScore = 0
        next.finished = false
        next.leftFouls = 0
        next.rightFouls = 0
        next.periodEnded = false
        next.canAdvancePeriod = false
        return refreshActiveTimeouts(resetGameClock(next))
    }

    public static func useTeamTimeout(_ state: BasketballMatchState, side: MatchSide) -> BasketballMatchState {
        let current = side == .left ? state.leftTimeouts : state.rightTimeouts
        guard current > 0 else { return state }
        var next = setActiveTimeout(state, side: side, value: current - 1)
        next.gameRunning = false
        next.shotRunning = false
        return resetShotClock(next)
    }

    public static func adjustTimeout(_ state: BasketballMatchState, side: MatchSide, delta: Int) -> BasketballMatchState {
        let current = side == .left ? state.leftTimeouts : state.rightTimeouts
        return setActiveTimeout(state, side: side, value: current + delta)
    }

    public static func defaultTimeoutPools(_ ruleSet: BasketballRuleSet) -> BasketballTimeoutPools {
        BasketballTimeoutPools(leftOvertime: ruleSet == .nba ? 2 : 1, rightOvertime: ruleSet == .nba ? 2 : 1)
    }

    public static func activeTimeouts(
        gameMode: BasketballGameMode,
        ruleSet: BasketballRuleSet,
        pools: BasketballTimeoutPools,
        currentPeriod: Int,
        isOvertime: Bool
    ) -> (left: Int, right: Int) {
        if gameMode == .threeXThree { return (1, 1) }
        if isOvertime { return (pools.leftOvertime, pools.rightOvertime) }
        if ruleSet == .nba { return (pools.leftRegular, pools.rightRegular) }
        return currentPeriod <= 2
            ? (pools.leftFirstHalf, pools.rightFirstHalf)
            : (pools.leftSecondHalf, pools.rightSecondHalf)
    }

    private static func maybeFinishAfterScore(_ state: BasketballMatchState) -> BasketballMatchState {
        guard state.gameMode == .threeXThree else { return state }
        let overtimeWinner = state.isOvertime && (
            state.leftScore >= state.overtimeStartScore + 2 || state.rightScore >= state.overtimeStartScore + 2
        )
        guard overtimeWinner || (!state.isOvertime && (state.leftScore >= 21 || state.rightScore >= 21)) else {
            return state
        }
        return finish(state)
    }

    private static func startThreeXThreeOvertime(_ state: BasketballMatchState) -> BasketballMatchState {
        var next = state
        next.isOvertime = true
        next.overtimeStartScore = next.leftScore
        next.gameTimeSeconds = 0
        next.shotTimeSeconds = defaultShotSeconds(next.gameMode)
        next.finished = false
        next.gameRunning = false
        next.shotRunning = false
        return next
    }

    private static func handleFiveVFivePeriodExpired(_ state: BasketballMatchState) -> BasketballMatchState {
        if state.isOvertime {
            return state.leftScore == state.rightScore ? markPeriodEnded(state) : finish(state)
        }
        if state.currentPeriod < 4 { return markPeriodEnded(state) }
        return state.leftScore == state.rightScore ? enterFiveVFiveOvertime(state) : finish(state)
    }

    private static func markPeriodEnded(_ state: BasketballMatchState) -> BasketballMatchState {
        var next = state
        next.periodEnded = true
        next.canAdvancePeriod = true
        return next
    }

    private static func refreshActiveTimeouts(_ state: BasketballMatchState) -> BasketballMatchState {
        var next = state
        let active = activeTimeouts(
            gameMode: next.gameMode,
            ruleSet: next.ruleSet,
            pools: next.timeoutPools,
            currentPeriod: next.currentPeriod,
            isOvertime: next.isOvertime
        )
        next.leftTimeouts = active.left
        next.rightTimeouts = active.right
        return next
    }

    private static func maximumTimeouts(_ state: BasketballMatchState) -> Int {
        if state.gameMode == .threeXThree { return 1 }
        if state.isOvertime { return state.ruleSet == .nba ? 2 : 1 }
        if state.ruleSet == .nba { return 7 }
        return state.currentPeriod <= 2 ? 2 : 3
    }

    private static func setActiveTimeout(_ state: BasketballMatchState, side: MatchSide, value: Int) -> BasketballMatchState {
        let clamped = min(max(value, 0), maximumTimeouts(state))
        if state.gameMode == .threeXThree {
            var next = state
            if side == .left { next.leftTimeouts = clamped } else { next.rightTimeouts = clamped }
            return next
        }

        var next = state
        if next.isOvertime {
            if side == .left { next.timeoutPools.leftOvertime = clamped } else { next.timeoutPools.rightOvertime = clamped }
        } else if next.ruleSet == .nba {
            if side == .left { next.timeoutPools.leftRegular = clamped } else { next.timeoutPools.rightRegular = clamped }
        } else if next.currentPeriod <= 2 {
            if side == .left { next.timeoutPools.leftFirstHalf = clamped } else { next.timeoutPools.rightFirstHalf = clamped }
        } else if side == .left {
            next.timeoutPools.leftSecondHalf = clamped
        } else {
            next.timeoutPools.rightSecondHalf = clamped
        }
        return refreshActiveTimeouts(next)
    }
}

public struct BasketballMatchReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: BasketballMatchState,
        intent: BasketballMatchIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<BasketballMatchState, BasketballMatchEvent> {
        let next: BasketballMatchState
        switch intent {
        case .addPoints(let side, let points, let resetShotClock):
            let scored = BasketballMatchEngine.addPoints(state, side: side, points: points)
            next = resetShotClock && !scored.finished
                ? BasketballMatchEngine.resetShotClock(scored)
                : scored
        case .adjustScore(let side, let delta):
            next = BasketballMatchEngine.adjustScore(state, side: side, delta: delta)
        case .addFoul(let side):
            next = BasketballMatchEngine.addFoul(state, side: side)
        case .removeFoul(let side):
            next = BasketballMatchEngine.removeFoul(state, side: side)
        case .rename(let side, let name):
            next = BasketballMatchEngine.rename(state, side: side, name: name)
        case .setRuleSet(let ruleSet):
            next = BasketballMatchEngine.setRuleSet(state, ruleSet: ruleSet)
        case .setClockRunning(let running):
            next = BasketballMatchEngine.setClockRunning(state, running: running)
        case .tickClock:
            next = BasketballMatchEngine.tickClock(state)
        case .resetGameClock:
            next = BasketballMatchEngine.resetGameClock(state)
        case .resetShotClock(let seconds):
            next = BasketballMatchEngine.resetShotClock(state, seconds: seconds)
        case .advanceToNextPeriod:
            next = BasketballMatchEngine.advanceToNextPeriod(state)
        case .enterOvertime:
            next = BasketballMatchEngine.enterFiveVFiveOvertime(state)
        case .selectPeriod(let period):
            next = BasketballMatchEngine.selectPeriod(state, period: period)
        case .useTimeout(let side):
            next = BasketballMatchEngine.useTeamTimeout(state, side: side)
        case .adjustTimeout(let side, let delta):
            next = BasketballMatchEngine.adjustTimeout(state, side: side, delta: delta)
        case .exchangeSides:
            next = BasketballMatchEngine.exchangeSides(state)
        case .reset:
            next = BasketballMatchEngine.reset(state)
        case .finish:
            next = BasketballMatchEngine.finish(state)
        }

        guard next != state else {
            return .rejected(state: state, reason: "State unchanged")
        }
        return .init(
            state: next,
            events: [.stateChanged(at: epochMilliseconds, intent: intent, before: state, after: next)]
        )
    }
}
