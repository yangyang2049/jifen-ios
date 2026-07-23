import Foundation

// MARK: - Guandan (aligned with Android GuandanMatchStateMachine / Harmony guandanReducer)

public let guandanRankOrder: [String] = [
    "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"
]

public enum GuandanGamePhase: String, Codable, Sendable, Equatable {
    case notStarted = "not_started"
    case playing
    case roundResult = "round_result"
    case aStage = "a_stage"
    case finished
}

public enum GuandanSide: String, Codable, Sendable, Equatable {
    case red
    case blue
}

public enum GuandanAStageMode: String, Codable, Sendable, Equatable {
    case singleA = "single_a"
    case tripleA = "triple_a"
}

public enum GuandanPassACondition: String, Codable, Sendable, Equatable {
    case notLast = "not_last"
    case doubleUp = "double_up"
}

public struct GuandanTeamState: Codable, Equatable, Sendable {
    public var name: String
    public var currentRank: String

    public init(name: String, currentRank: String = "2") {
        self.name = name
        self.currentRank = currentRank
    }
}

public struct GuandanMatchState: Codable, Equatable, Sendable {
    public var phase: GuandanGamePhase
    public var redTeam: GuandanTeamState
    public var blueTeam: GuandanTeamState
    public var roundWinner: GuandanSide?
    public var lastRoundWinner: GuandanSide?
    public var roundUpgrade: Int?
    public var isInAStage: Bool
    public var aStageTeam: GuandanSide?
    public var aStageMode: GuandanAStageMode
    public var passACondition: GuandanPassACondition
    public var tripleAFallbackRank: String
    public var finalWinner: GuandanSide?
    public var redAFailCount: Int
    public var blueAFailCount: Int

    public init(
        phase: GuandanGamePhase = .notStarted,
        redTeam: GuandanTeamState,
        blueTeam: GuandanTeamState,
        roundWinner: GuandanSide? = nil,
        lastRoundWinner: GuandanSide? = nil,
        roundUpgrade: Int? = nil,
        isInAStage: Bool = false,
        aStageTeam: GuandanSide? = nil,
        aStageMode: GuandanAStageMode = .singleA,
        passACondition: GuandanPassACondition = .notLast,
        tripleAFallbackRank: String = "2",
        finalWinner: GuandanSide? = nil,
        redAFailCount: Int = 0,
        blueAFailCount: Int = 0
    ) {
        self.phase = phase
        self.redTeam = redTeam
        self.blueTeam = blueTeam
        self.roundWinner = roundWinner
        self.lastRoundWinner = lastRoundWinner
        self.roundUpgrade = roundUpgrade
        self.isInAStage = isInAStage
        self.aStageTeam = aStageTeam
        self.aStageMode = aStageMode
        self.passACondition = passACondition
        self.tripleAFallbackRank = tripleAFallbackRank
        self.finalWinner = finalWinner
        self.redAFailCount = redAFailCount
        self.blueAFailCount = blueAFailCount
    }

    public static func initial(
        redName: String,
        blueName: String,
        aStageMode: GuandanAStageMode = .singleA,
        passACondition: GuandanPassACondition = .notLast,
        tripleAFallbackRank: String = "2"
    ) -> GuandanMatchState {
        GuandanMatchState(
            redTeam: GuandanTeamState(name: redName, currentRank: "2"),
            blueTeam: GuandanTeamState(name: blueName, currentRank: "2"),
            aStageMode: aStageMode,
            passACondition: passACondition,
            tripleAFallbackRank: tripleAFallbackRank
        )
    }

    public func aFailCount(for side: GuandanSide) -> Int {
        max(0, side == .red ? redAFailCount : blueAFailCount)
    }

    /// Android/HOS `guandanDisplayRank`: triple-A shows A1/A2/A3 while at A.
    public func displayRank(for side: GuandanSide) -> String {
        let rank = side == .red ? redTeam.currentRank : blueTeam.currentRank
        if phase == .finished, finalWinner == side, rank == "A" {
            return "A"
        }
        guard aStageMode == .tripleA, rank == "A" else { return rank }
        let failCount = aFailCount(for: side)
        let attemptStep: Int
        if lastRoundWinner == side {
            attemptStep = min(3, max(1, failCount + 1))
        } else {
            attemptStep = min(3, max(1, failCount))
        }
        return "A\(attemptStep)"
    }

    public static func rankDisplayScore(_ rank: String) -> Int {
        max(0, guandanRankOrder.firstIndex(of: rank) ?? 0) + 2
    }
}

public enum GuandanSessionIntent: Codable, Sendable {
    case startMatch
    case beginRoundResult(winner: GuandanSide)
    case cancelRoundResult
    case applyRoundSettlement(step: Int)
    case recordPassA(success: Bool)
    case setRedTeamName(String)
    case setBlueTeamName(String)
    case adjustRank(side: GuandanSide, delta: Int)
}

public enum GuandanSessionEvent: Codable, Equatable, Sendable {
    case matchStarted(team1Score: Int, team2Score: Int)
    case roundSettlementApplied(winner: GuandanSide, step: Int)
    case passARecorded(side: GuandanSide, success: Bool, prevAttempt: Int)
}

public struct GuandanSessionReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: GuandanMatchState,
        intent: GuandanSessionIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<GuandanMatchState, GuandanSessionEvent> {
        switch intent {
        case .setRedTeamName(let name):
            var next = state
            next.redTeam.name = name
            return .init(state: next)
        case .setBlueTeamName(let name):
            var next = state
            next.blueTeam.name = name
            return .init(state: next)
        case .adjustRank(let side, let delta):
            return .init(state: adjustRank(state: state, side: side, delta: delta))
        default:
            break
        }

        let before = state
        var next = state
        switch intent {
        case .startMatch:
            next = startMatch(next)
        case .beginRoundResult(let winner):
            next = beginRoundResult(next, winner: winner)
        case .cancelRoundResult:
            next = cancelRoundResult(next)
        case .applyRoundSettlement(let step):
            next = applyRoundSettlement(next, step: step)
        case .recordPassA(let success):
            next = recordPassA(next, success: success)
        case .setRedTeamName, .setBlueTeamName, .adjustRank:
            break
        }
        return .init(state: next, events: buildEvents(before: before, intent: intent, next: next))
    }

    private func upgradeRank(_ current: String, step: Int) -> String {
        let idx = max(0, guandanRankOrder.firstIndex(of: current) ?? 0)
        let nextIdx = min(idx + max(0, step), guandanRankOrder.count - 1)
        return guandanRankOrder[nextIdx]
    }

    private func team(_ state: GuandanMatchState, _ side: GuandanSide) -> GuandanTeamState {
        side == .red ? state.redTeam : state.blueTeam
    }

    private func opposite(_ side: GuandanSide) -> GuandanSide {
        side == .red ? .blue : .red
    }

    private func withTeam(_ state: GuandanMatchState, side: GuandanSide, team: GuandanTeamState) -> GuandanMatchState {
        var next = state
        if side == .red { next.redTeam = team } else { next.blueTeam = team }
        return next
    }

    private func withFailCount(_ state: GuandanMatchState, side: GuandanSide, value: Int) -> GuandanMatchState {
        var next = state
        let clamped = max(0, value)
        if side == .red { next.redAFailCount = clamped } else { next.blueAFailCount = clamped }
        return next
    }

    private func withCurrentAStage(_ state: GuandanMatchState, side: GuandanSide?) -> GuandanMatchState {
        var next = state
        next.aStageTeam = side
        next.isInAStage = side != nil
        return next
    }

    private func startMatch(_ state: GuandanMatchState) -> GuandanMatchState {
        guard state.phase == .notStarted else { return state }
        var next = state
        next.phase = .playing
        return next
    }

    private func beginRoundResult(_ state: GuandanMatchState, winner: GuandanSide) -> GuandanMatchState {
        guard state.phase == .playing else { return state }
        var next = state
        next.phase = .roundResult
        next.roundWinner = winner
        next.lastRoundWinner = winner
        next.roundUpgrade = nil
        return next
    }

    private func cancelRoundResult(_ state: GuandanMatchState) -> GuandanMatchState {
        guard state.phase == .roundResult else { return state }
        var next = state
        next.phase = .playing
        next.roundWinner = nil
        next.roundUpgrade = nil
        return next
    }

    private func applyRoundSettlement(_ state: GuandanMatchState, step: Int) -> GuandanMatchState {
        guard let winner = state.roundWinner, state.phase == .roundResult else { return state }
        let prevAStageTeam = state.aStageTeam
        let prevTeam = team(state, winner)
        let prevRank = prevTeam.currentRank
        let nextRank = upgradeRank(prevRank, step: step)
        var next = withTeam(state, side: winner, team: GuandanTeamState(name: prevTeam.name, currentRank: nextRank))
        next.roundWinner = nil
        next.lastRoundWinner = winner
        next.roundUpgrade = nil

        if prevAStageTeam == nil {
            if prevRank != "A" && nextRank == "A" {
                next = withFailCount(next, side: winner, value: 0)
            }
            let winnerAtA = team(next, winner).currentRank == "A"
            next.phase = .playing
            return withCurrentAStage(next, side: winnerAtA ? winner : nil)
        }

        let winnerIsPassSide = prevAStageTeam == winner
        let passed: Bool = {
            guard winnerIsPassSide else { return false }
            switch state.passACondition {
            case .doubleUp: return step == 3
            case .notLast: return step == 2 || step == 3
            }
        }()
        if passed {
            next.phase = .finished
            next.finalWinner = prevAStageTeam
            return withCurrentAStage(next, side: prevAStageTeam)
        }

        if state.aStageMode == .singleA {
            let winnerAtA = team(next, winner).currentRank == "A"
            next.phase = .playing
            return withCurrentAStage(next, side: winnerAtA ? winner : nil)
        }

        guard let activeAStageTeam = prevAStageTeam else { return next }
        let failCount = state.aFailCount(for: activeAStageTeam) + 1
        next = withFailCount(next, side: activeAStageTeam, value: failCount)
        if failCount >= 3 {
            let fallback = state.tripleAFallbackRank.isEmpty ? "2" : state.tripleAFallbackRank
            let fallbackTeam = GuandanTeamState(name: team(next, activeAStageTeam).name, currentRank: fallback)
            next = withTeam(next, side: activeAStageTeam, team: fallbackTeam)
            next = withFailCount(next, side: activeAStageTeam, value: 0)
        }
        let winnerAtA = team(next, winner).currentRank == "A"
        next.phase = .playing
        return withCurrentAStage(next, side: winnerAtA ? winner : nil)
    }

    private func recordPassA(_ state: GuandanMatchState, success: Bool) -> GuandanMatchState {
        guard state.phase == .aStage, let side = state.aStageTeam else { return state }
        if success {
            var next = state
            next.phase = .finished
            next.finalWinner = side
            return next
        }
        if state.aStageMode == .singleA {
            var next = state
            next.phase = .playing
            return withCurrentAStage(next, side: side)
        }
        let failCount = state.aFailCount(for: side) + 1
        if failCount < 3 {
            var next = withFailCount(state, side: side, value: failCount)
            next.phase = .playing
            return withCurrentAStage(next, side: side)
        }
        let fallback = state.tripleAFallbackRank.isEmpty ? "2" : state.tripleAFallbackRank
        var next = withTeam(state, side: side, team: GuandanTeamState(name: team(state, side).name, currentRank: fallback))
        next = withFailCount(next, side: side, value: 0)
        let other = opposite(side)
        let otherAtA = team(next, other).currentRank == "A"
        next.phase = .playing
        return withCurrentAStage(next, side: otherAtA ? other : nil)
    }

    private func currentAStageTeam(state: GuandanMatchState) -> GuandanSide? {
        if state.lastRoundWinner == .red && state.redTeam.currentRank == "A" { return .red }
        if state.lastRoundWinner == .blue && state.blueTeam.currentRank == "A" { return .blue }
        return nil
    }

    private func adjustRank(state: GuandanMatchState, side: GuandanSide, delta: Int) -> GuandanMatchState {
        guard delta != 0 else { return state }
        let maxRankIdx = guandanRankOrder.count - 1
        let current = team(state, side).currentRank
        let currentRankIdx = max(0, guandanRankOrder.firstIndex(of: current) ?? 0)
        let currentDisplayIdx: Int
        if state.aStageMode == .tripleA && currentRankIdx == maxRankIdx {
            currentDisplayIdx = maxRankIdx + min(max(state.aFailCount(for: side), 0), 2)
        } else {
            currentDisplayIdx = currentRankIdx
        }
        let maxDisplayIdx = state.aStageMode == .tripleA ? maxRankIdx + 2 : maxRankIdx
        let nextDisplayIdx: Int
        if delta > 0 && currentDisplayIdx + delta > maxDisplayIdx {
            nextDisplayIdx = 0
        } else {
            nextDisplayIdx = min(max(currentDisplayIdx + delta, 0), maxDisplayIdx)
        }
        let nextRankIdx = min(nextDisplayIdx, maxRankIdx)
        let nextRank = guandanRankOrder[nextRankIdx]
        let nextFailCount = state.aStageMode == .tripleA && nextDisplayIdx >= maxRankIdx
            ? nextDisplayIdx - maxRankIdx
            : 0
        var next = withTeam(state, side: side, team: GuandanTeamState(name: team(state, side).name, currentRank: nextRank))
        next = withFailCount(next, side: side, value: nextFailCount)
        return withCurrentAStage(next, side: currentAStageTeam(state: next))
    }

    private func buildEvents(
        before: GuandanMatchState,
        intent: GuandanSessionIntent,
        next: GuandanMatchState
    ) -> [GuandanSessionEvent] {
        switch intent {
        case .startMatch where before.phase == .notStarted && next.phase == .playing:
            return [.matchStarted(
                team1Score: GuandanMatchState.rankDisplayScore(next.redTeam.currentRank),
                team2Score: GuandanMatchState.rankDisplayScore(next.blueTeam.currentRank)
            )]
        case .applyRoundSettlement(let step):
            guard let winner = before.roundWinner else { return [] }
            return [.roundSettlementApplied(winner: winner, step: step)]
        case .recordPassA(let success):
            guard let side = before.aStageTeam else { return [] }
            return [.passARecorded(
                side: side,
                success: success,
                prevAttempt: before.aFailCount(for: side)
            )]
        default:
            return []
        }
    }
}
