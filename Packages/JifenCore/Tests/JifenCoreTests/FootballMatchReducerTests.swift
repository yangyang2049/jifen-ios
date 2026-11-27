import Foundation
import ScoreCore
import Testing

@Suite struct FootballMatchReducerTests {
    private let reducer = FootballMatchReducer()

    @Test func elevenAsideStartsAutomaticallyAndFiveAsideWaitsForKickOff() {
        let eleven = FootballMatchReducer.initial(leftName: "Home", rightName: "Away", at: 1_000)
        #expect(eleven.timer.halfLengthSeconds == 2_700)
        #expect(eleven.timer.isRunning)
        #expect(eleven.kickedOff)
        #expect(!reducer.reduce(state: eleven, intent: .toggleClock, at: 2_000).accepted)

        let five = FootballMatchReducer.initial(leftName: "Home", rightName: "Away", isFiveAside: true, at: 1_000)
        #expect(five.timer.halfLengthSeconds == 1_200)
        #expect(!five.timer.isRunning)
        #expect(!five.kickedOff)
        #expect(FootballMatchReducer.displayElapsedSeconds(state: five, at: 4_000) == 0)

        let kickoff = reducer.reduce(state: five, intent: .kickOff, at: 4_000)
        #expect(kickoff.state.kickedOff)
        #expect(kickoff.state.timer.isRunning)
        #expect(kickoff.events == [.kickedOff])
        #expect(!reducer.reduce(state: kickoff.state, intent: .kickOff, at: 5_000).accepted)

        let pause = reducer.reduce(state: kickoff.state, intent: .toggleClock, at: 6_000)
        #expect(pause.state.timer.elapsedSeconds == 2)
        #expect(pause.events == [.clockToggled(isRunning: false, period: 1)])
        let resume = reducer.reduce(state: pause.state, intent: .startClock, at: 9_000)
        #expect(resume.state.timer.elapsedSeconds == 2)
        #expect(resume.events == [.clockToggled(isRunning: true, period: 1)])
        let pauseExplicitly = reducer.reduce(state: resume.state, intent: .pauseClock, at: 10_000)
        #expect(pauseExplicitly.state.timer.elapsedSeconds == 3)
        #expect(!pauseExplicitly.state.timer.isRunning)
    }

    @Test func actionsSettleAtTheirInjectedTimesWithoutLosingFractionalSeconds() throws {
        let start = FootballMatchReducer.initial(leftName: "Home", rightName: "Away", at: 1_000)
        let first = reducer.reduce(state: start, intent: .goal(side: .left), at: 1_600)
        #expect(first.events == [.goalScored(side: .left, leftScore: 1, rightScore: 0, period: 1, elapsedSeconds: 0)])
        #expect(first.state.timer.savedWallClockMilliseconds == 1_600)
        #expect(FootballMatchReducer.displayElapsedSeconds(state: first.state, at: 2_000) == 1)
        #expect(first.state.timer.elapsedSeconds == 0)

        let saved = try JSONEncoder().encode(first.state)
        let restored = try JSONDecoder().decode(FootballMatchState.self, from: saved)
        let second = reducer.reduce(state: restored, intent: .goal(side: .right), at: 2_200)
        #expect(second.events == [.goalScored(side: .right, leftScore: 1, rightScore: 1, period: 1, elapsedSeconds: 1)])
        #expect(second.state.timer.savedWallClockMilliseconds == 2_200)

        let replay = reducer.reduce(state: first.state, intent: .goal(side: .right), at: 2_200)
        #expect(replay.state == second.state)
        #expect(replay.events == second.events)
        #expect(FootballMatchReducer.displayElapsedSeconds(state: second.state, at: 3_000) == 2)
    }

    @Test func clockAnchorDoesNotMoveBackwardForAnOlderInput() {
        let start = FootballMatchReducer.initial(leftName: "Home", rightName: "Away", at: 1_000)
        let first = reducer.reduce(state: start, intent: .goal(side: .left), at: 2_200)
        let older = reducer.reduce(state: first.state, intent: .goal(side: .right), at: 1_700)
        #expect(older.state.timer.savedWallClockMilliseconds == 2_200)
        #expect(older.state.timer.elapsedSeconds == 1)
        #expect(older.events == [.goalScored(side: .right, leftScore: 1, rightScore: 1, period: 1, elapsedSeconds: 1)])
        #expect(FootballMatchReducer.displayElapsedSeconds(state: older.state, at: 3_000) == 2)
    }

    @Test func stoppageExtendsTheCurrentPeriodAndCanOnlyUndoUnusedTime() {
        let initial = FootballMatchReducer.initial(leftName: "Home", rightName: "Away", halfLengthSeconds: 60, at: 1_000)
        let added = reducer.reduce(state: initial, intent: .addStoppage(seconds: 30), at: 62_000)
        #expect(added.state.timer.elapsedSeconds == 60)
        #expect(added.state.timer.isRunning)
        #expect(added.events == [.stoppageAdded(seconds: 30, period: 1)])
        let addedAgain = reducer.reduce(state: added.state, intent: .addStoppage(seconds: 15), at: 67_000)
        #expect(addedAgain.state.stoppageHistory == [30, 15])
        #expect(addedAgain.state.targetSeconds == 105)
        let undone = reducer.reduce(state: addedAgain.state, intent: .undoLastStoppage, at: 71_000)
        #expect(undone.events == [.stoppageUndone(seconds: 15, period: 1)])
        #expect(undone.state.timer.elapsedSeconds == 69)
        #expect(undone.state.currentStoppageSeconds == 30)
        let rejected = reducer.reduce(state: undone.state, intent: .undoLastStoppage, at: 71_000)
        #expect(!rejected.accepted)
        #expect(rejected.state == undone.state)

        let rolledBack = reducer.reduce(state: added.state, intent: .undoLastStoppage, at: 62_000)
        #expect(rolledBack.state.targetSeconds == 60)
        #expect(!rolledBack.state.timer.isRunning)
        #expect(rolledBack.state.stoppageHistory.isEmpty)
        #expect(!reducer.reduce(state: added.state, intent: .undoLastStoppage, at: 62_500).accepted)
    }

    @Test func periodAdvancementClampsTheClockAndClearsPerPeriodUndoHistory() {
        let initial = FootballMatchReducer.initial(leftName: "Home", rightName: "Away", halfLengthSeconds: 60,
                                                  extraHalfLengthSeconds: 60, at: 1_000)
        let added = reducer.reduce(state: initial, intent: .addStoppage(seconds: 15), at: 20_000)
        #expect(FootballMatchReducer.displayElapsedSeconds(state: added.state, at: 90_000) == 75)
        let second = reducer.reduce(state: added.state, intent: .advanceStage, at: 90_000)
        #expect(second.events == [.stageAdvanced(newStage: 2)])
        #expect(second.state.timer.elapsedSeconds == 0)
        #expect(second.state.timer.isRunning)
        #expect(second.state.timer.stoppageSeconds == [15, 0, 0, 0])
        #expect(second.state.stoppageHistory.isEmpty)
        #expect(!reducer.reduce(state: second.state, intent: .advanceStage, at: 149_000).accepted)

        let third = reducer.reduce(state: second.state, intent: .advanceStage, at: 150_000)
        #expect(third.events == [.stageAdvanced(newStage: 3)])
        #expect(third.state.timer.isRunning)
        let fourth = reducer.reduce(state: third.state, intent: .advanceStage, at: 210_000)
        #expect(fourth.events == [.stageAdvanced(newStage: 4)])
        #expect(!reducer.reduce(state: fourth.state, intent: .advanceStage, at: 270_000).accepted)
        let goal = reducer.reduce(state: fourth.state, intent: .goal(side: .left), at: 275_000)
        #expect(!goal.state.timer.isRunning)
        #expect(goal.events == [.goalScored(side: .left, leftScore: 1, rightScore: 0, period: 4, elapsedSeconds: 60)])
    }

    @Test func fiveAsideWaitsAtHalfTimeAndRejectsStoppageAndExtraTime() {
        let initial = FootballMatchReducer.initial(leftName: "Home", rightName: "Away", isFiveAside: true,
                                                  halfLengthSeconds: 60, at: 1_000)
        let first = reducer.reduce(state: initial, intent: .toggleClock, at: 1_000).state
        #expect(!reducer.reduce(state: first, intent: .addStoppage(seconds: 15), at: 3_000).accepted)
        let second = reducer.reduce(state: first, intent: .advanceStage, at: 61_000)
        #expect(second.state.kickedOff)
        #expect(!second.state.timer.isRunning)
        #expect(second.state.timer.elapsedSeconds == 0)
        let resumed = reducer.reduce(state: second.state, intent: .toggleClock, at: 65_000)
        #expect(resumed.events == [.clockToggled(isRunning: true, period: 2)])
        #expect(!reducer.reduce(state: resumed.state, intent: .advanceStage, at: 125_000).accepted)
        let reset = reducer.reduce(state: resumed.state, intent: .reset(), at: 126_000)
        #expect(!reset.state.timer.isRunning)
        #expect(!reset.state.kickedOff)
    }

    @Test func scoreEditsPreserveTeamIdentityAndFinishFreezesElapsedTime() {
        let initial = FootballMatchReducer.initial(leftName: "  Home ", rightName: "Away", at: 1_000)
        let reject = reducer.reduce(state: initial, intent: .subtractGoal(side: .right), at: 2_000)
        #expect(!reject.accepted)
        #expect(reject.state == initial)

        let home = reducer.reduce(state: initial, intent: .goal(side: .left), at: 9_000).state
        let away = reducer.reduce(state: home, intent: .goal(side: .right), at: 11_000).state
        let corrected = reducer.reduce(state: away, intent: .subtractGoal(side: .right), at: 12_000)
        #expect(corrected.events == [.goalSubtracted(side: .right, leftScore: 1, rightScore: 0, period: 1, elapsedSeconds: 11)])
        let swapped = reducer.reduce(state: corrected.state, intent: .exchangeSides, at: 13_000)
        #expect(swapped.state.sidesSwapped)
        #expect(swapped.state.leftName == "Home")
        #expect(swapped.state.leftScore == 1)
        let renamed = reducer.reduce(state: swapped.state, intent: .setNames(left: " Home FC  ", right: "Away"), at: 13_000)
        #expect(renamed.state.leftName == "Home FC")

        let finished = reducer.reduce(state: renamed.state, intent: .finish, at: 14_000)
        #expect(finished.events == [.matchFinished(winner: .left)])
        #expect(finished.state.finished)
        #expect(!finished.state.timer.isRunning)
        #expect(FootballMatchReducer.displayElapsedSeconds(state: finished.state, at: 35_000) == 13)
        #expect(!reducer.reduce(state: finished.state, intent: .goal(side: .left), at: 35_000).accepted)
        #expect(reducer.reduce(state: initial, intent: .finish, at: 14_000).events == [.matchFinished(winner: nil)])

        let reset = reducer.reduce(state: finished.state, intent: .reset(halfLengthSeconds: 120), at: 35_000)
        #expect(reset.events == [.matchReset])
        #expect(reset.state.leftName == "Home FC")
        #expect(reset.state.leftScore == 0)
        #expect(!reset.state.sidesSwapped)
        #expect(!reset.state.finished)
        #expect(reset.state.timer.isRunning)
        #expect(reset.state.timer.halfLengthSeconds == 120)
        #expect(reset.state.timer.savedWallClockMilliseconds == 35_000)
    }

    @Test func timerMatchesLegacyClockAtWholeSecondChannelTimestamps() {
        let clock = ReducerParityFootballClock()
        var legacy = FootballMatchClockSession(state: .init(halfLengthSeconds: 60, extraHalfLengthSeconds: 60), clock: clock)
        legacy.resetForNewGame()
        var state = FootballMatchReducer.initial(leftName: "Home", rightName: "Away", halfLengthSeconds: 60,
                                                extraHalfLengthSeconds: 60, at: clock.wallClockMilliseconds())
        #expect(state.timer == legacy.snapshot())

        clock.seconds = 59
        let addedStoppage = legacy.addStoppageSeconds(15)
        #expect(addedStoppage)
        state = reducer.reduce(state: state, intent: .addStoppage(seconds: 15), at: clock.wallClockMilliseconds()).state
        #expect(state.timer == legacy.snapshot())

        clock.seconds = 65
        let goal = reducer.reduce(state: state, intent: .goal(side: .left), at: clock.wallClockMilliseconds())
        #expect(goal.events == [.goalScored(side: .left, leftScore: 1, rightScore: 0, period: 1, elapsedSeconds: 65)])
        state = goal.state
        #expect(state.timer == legacy.snapshot())

        for seconds: Int64 in [75, 135, 195] {
            clock.seconds = seconds
            let advanced = legacy.advanceStage()
            #expect(advanced)
            state = reducer.reduce(state: state, intent: .advanceStage, at: clock.wallClockMilliseconds()).state
            #expect(state.timer == legacy.snapshot())
        }
    }
}

private final class ReducerParityFootballClock: @unchecked Sendable, FootballClock {
    var seconds: Int64 = 0

    func monotonicSeconds() -> Int64 { seconds }
    func wallClockMilliseconds() -> Int64 { 1_000 + seconds * 1_000 }
}
