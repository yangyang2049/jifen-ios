import Foundation
import Testing
@testable import ScoreCore
@testable import SessionCore

@Test func basketballCustomQuartersAndRepeatedOvertime() {
    var state = BasketballMatchEngine.initial(leftName: "H", rightName: "A", gameMode: .fiveVFive,
        ruleSet: .custom, periodDurationSeconds: 1200, overtimeDurationSeconds: 180)
    #expect(state.gameTimeSeconds == 1200)
    state.currentPeriod = 4
    state.gameTimeSeconds = 1
    state.gameRunning = true
    state = BasketballMatchEngine.tickClock(state)
    #expect(state.isOvertime && state.gameTimeSeconds == 180)
    #expect(BasketballMatchEngine.resetGameClock(state).isOvertime)
    #expect(BasketballMatchEngine.resetGameClock(state).gameTimeSeconds == 180)
    state.gameTimeSeconds = 1
    state.gameRunning = true
    state = BasketballMatchEngine.tickClock(state)
    #expect(state.canAdvancePeriod)
    #expect(BasketballMatchEngine.advanceToNextPeriod(state).gameTimeSeconds == 180)
    #expect(BasketballMatchEngine.reset(state).gameTimeSeconds == 1200)
}

@Test func basketballCustomModificationKeepsCurrentClockAndUndoKeepsTiming() {
    let original = BasketballMatchEngine.initial(leftName: "H", rightName: "A", gameMode: .fiveVFive, ruleSet: .nba)
    var scored = BasketballMatchEngine.addPoints(original, side: .left, points: 2)
    scored.gameTimeSeconds = 137
    let changed = BasketballMatchEngine.setTiming(scored, period: 900, overtime: 420, resetCurrentClock: false)
    #expect(changed.leftScore == 2 && changed.gameTimeSeconds == 137)
    let undone = BasketballMatchEngine.mergeUndoTiming(original, changed)
    #expect(undone.leftScore == 0 && undone.gameTimeSeconds == 137)
    #expect(undone.ruleSet == .custom && undone.periodDurationSeconds == 900)
    #expect(undone.leftTimeouts == 2)
    #expect(BasketballMatchEngine.setTiming(changed, period: 1200, overtime: 180, resetCurrentClock: true).gameTimeSeconds == 1200)
}

@Test func basketballCustomTimingCodableMigrationAndBounds() throws {
    let state = BasketballMatchEngine.initial(leftName: "H", rightName: "A", gameMode: .fiveVFive,
        ruleSet: .custom, periodDurationSeconds: 5940, overtimeDurationSeconds: 60)
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(BasketballMatchState.self, from: data) == state)
    var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    old.removeValue(forKey: "periodDurationSeconds")
    old.removeValue(forKey: "overtimeDurationSeconds")
    old["ruleSet"] = "nba"
    let migrated = try JSONDecoder().decode(BasketballMatchState.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(migrated.periodDurationSeconds == 720 && migrated.overtimeDurationSeconds == 300)
    old.removeValue(forKey: "gameTimeSeconds")
    old["isOvertime"] = true
    let oldOvertime = try JSONDecoder().decode(BasketballMatchState.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(oldOvertime.gameTimeSeconds == 300)
    #expect(BasketballMatchEngine.periodSeconds(.custom, customSeconds: 61) == 600)
}

@Test func basketballSessionUndoKeepsNonUndoableTimingChange() async {
    let initial = BasketballMatchEngine.initial(leftName: "H", rightName: "A", gameMode: .fiveVFive)
    let core = ScoreSessionCore(seedSession: ScoreSession<BasketballMatchState, BasketballMatchEvent>(
        gameType: .basketball, ruleFamily: .s2, reducerType: "basketball", state: initial),
        reducer: BasketballMatchReducer(), shouldFinish: { _, state in state.finished })
    _ = await core.dispatch(actorId: "phone", intent: .addPoints(side: .left, points: 2), at: 1)
    _ = await core.dispatchNonUndoable(actorId: "phone",
        intent: .setTiming(periodSeconds: 1200, overtimeSeconds: 180, resetCurrentClock: false), at: 2)
    #expect(await core.undo(actorId: "phone", mergingState: BasketballMatchEngine.mergeUndoTiming))
    let result = await core.snapshot()
    #expect(result.state.leftScore == 0)
    #expect(result.state.ruleSet == .custom && result.state.periodDurationSeconds == 1200)
    #expect(result.state.overtimeDurationSeconds == 180)
    #expect(!BasketballMatchEngine.preservesTimingOnUndo(.reset))
}

@Test func basketballClockUndoKeepsLaterConfigurationAndTimeoutRules() {
    let before = BasketballMatchEngine.initial(leftName: "H", rightName: "A", gameMode: .fiveVFive, ruleSet: .nba)
    let changed = BasketballMatchEngine.setTiming(before, period: 1200, overtime: 180, resetCurrentClock: false)
    let undoClock = BasketballMatchEngine.mergeUndoConfiguration(before, changed)
    #expect(undoClock.ruleSet == .custom && undoClock.periodDurationSeconds == 1200)
    #expect(undoClock.overtimeDurationSeconds == 180 && undoClock.leftTimeouts == 2)
    var fourth = before
    fourth.currentPeriod = 4
    let overtime = BasketballMatchEngine.enterFiveVFiveOvertime(fourth)
    let customOvertime = BasketballMatchEngine.setTiming(overtime, period: 1200, overtime: 180, resetCurrentClock: false)
    let undoOvertime = BasketballMatchEngine.mergeUndoConfiguration(fourth, customOvertime)
    #expect(!undoOvertime.isOvertime && undoOvertime.leftTimeouts == 3)
}

@Test func basketballUndoDoesNotRefillLegacyExplicitTimeoutCounts() {
    let before = BasketballMatchState(leftName: "H", rightName: "A", gameMode: .fiveVFive, leftTimeouts: 0, rightTimeouts: 0)
    var current = before
    current.gameRunning = true
    let undoClock = BasketballMatchEngine.mergeUndoConfiguration(before, current)
    #expect(undoClock.leftTimeouts == 0 && undoClock.rightTimeouts == 0)
    let undoScore = BasketballMatchEngine.mergeUndoTiming(before, current)
    #expect(undoScore.leftTimeouts == 0 && undoScore.rightTimeouts == 0)
}
