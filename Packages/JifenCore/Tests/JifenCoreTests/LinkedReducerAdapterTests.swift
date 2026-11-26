import Foundation
import LinkCore
import LinkSync
import RecordCore
import ScoreCore
import Testing

struct LinkedReducerAdapterTests {
    private let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())

    @Test func allEightNativeReducersProjectDeterministicActionsAndShareFinish() throws {
        let startTime = Date(timeIntervalSince1970: 1)
        let cases: [(GameType, LinkedReducerSnapshot, LinkedScoreboardIntent)] = [
            (.pingpong, .rally(RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())), .rally(.pointWon(.left))),
            (.tennis, .tennis(TennisMatchState(leftName: "L", rightName: "R")), .tennis(.pointWon(.left))),
            (.archeryDual, .archery(ArcheryMatchState(leftName: "L", rightName: "R")), .archery(.recordArrow(side: .left, value: 8))),
            (.eightBall, .eightBall(.initial()), .eightBall(.addRack(.left))),
            (.nineBall, .nineBall(.initial()), .nineBall(.deltaTotal(player: 0, delta: 1))),
            (.snooker, .snooker(.initial()), .snooker(.potBall(points: 1))),
            (.football, .football(FootballMatchReducer.initial(leftName: "L", rightName: "R", at: 1_000)), .football(.goal(side: .left))),
            (.basketballTraining, .shotTraining(.init(mode: .free, startTime: startTime)), .shotTraining(.recordShot(points: 2, made: true))),
        ]

        let adapter = LinkedReducerAdapter()
        for (gameType, native, intent) in cases {
            let seed = try #require(LinkedReducerState(gameType: gameType, state: native))
            let scoring = operation(intent, sequence: 1)
            let (next, actions) = try accepted(adapter.transition(seed, scoring, 63_000))
            let (replayed, replayedActions) = try accepted(adapter.transition(seed, scoring, 63_000))
            #expect(next == replayed, "Non-deterministic state for \(gameType)")
            #expect(actions == replayedActions && !actions.isEmpty, "Non-deterministic or missing actions for \(gameType)")
            #expect(actions.map(\.epochMilliseconds) == Array(repeating: 63_000, count: actions.count))
            if gameType == .football {
                #expect(actions.first?.operationCode == "goal")
                #expect(actions.first?.footballPeriod == 1)
                #expect(actions.first?.footballElapsedSeconds == 62)
            }
            let finishing = operation(.finish, sequence: 2)
            let (finished, finalActions) = try accepted(adapter.transition(next, finishing, 64_000))
            #expect(adapter.isFinished(finished))
            #expect(finalActions.contains { $0.type == .matchFinished })

            let restartTime: Int64 = 65_000
            #expect(adapter.nextMatchSnapshot(from: seed, at: restartTime) == nil)
            let reset = try #require(adapter.nextMatchSnapshot(from: finished, at: restartTime))
            #expect(adapter.nextMatchSnapshot(from: finished, at: restartTime) == reset)
            let fresh = try #require(adapter.state(gameType: gameType, from: reset))
            #expect(!adapter.isFinished(fresh) && fresh.latestUndoableOperationId == nil)
            switch fresh.current {
            case .football(let football):
                #expect(football.timer.savedWallClockMilliseconds == restartTime)
                #expect(football.timer.elapsedSeconds == 0 && football.timer.isRunning)
                #expect(football.leftScore == 0 && football.rightScore == 0)
            case .shotTraining(let training):
                #expect(training.startTime == Date(timeIntervalSince1970: 65))
                #expect(training.mode == .free && training.shots.isEmpty)
                #expect(training.earlierCounts == .init())
            default:
                #expect(fresh.current == seed.current)
            }
        }
    }

    @Test func rematchRetainsConfiguredHandicapAndFiveAsideKickoffPolicy() throws {
        let adapter = LinkedReducerAdapter()
        let footballStart = FootballMatchReducer.initial(
            leftName: "Home", rightName: "Away", isFiveAside: true, halfLengthSeconds: 420, at: 1_000
        )
        let football = try #require(LinkedReducerState(gameType: .football5v5, state: .football(footballStart)))
        let kickoff = operation(.football(.kickOff), sequence: 1)
        let (running, _) = try accepted(adapter.transition(football, kickoff, 1_100))
        let finish = operation(.finish, sequence: 2)
        let (stopped, _) = try accepted(adapter.transition(running, finish, 1_200))
        let reset = try #require(adapter.nextMatchSnapshot(from: stopped, at: 2_000))
        let restarted = try #require(adapter.state(gameType: .football5v5, from: reset))
        let expected = FootballMatchReducer.initial(
            leftName: "Home", rightName: "Away", isFiveAside: true, halfLengthSeconds: 420, at: 2_000
        )
        #expect(restarted.current == .football(expected))

        let eightBallStart = EightBallState.initial(targetPoints: 7, handicapRacks: 2, handicapBeneficiary: .right)
        let eightBall = try #require(LinkedReducerState(gameType: .eightBall, state: .eightBall(eightBallStart)))
        let rack = operation(.eightBall(.addRack(.left)), sequence: 1)
        let (scored, _) = try accepted(adapter.transition(eightBall, rack, 1_100))
        let (finished, _) = try accepted(adapter.transition(scored, finish, 1_200))
        #expect(adapter.nextMatchSnapshot(from: finished, at: 2_000) == .eightBall(eightBallStart))
    }

    @Test func restoredUndoUsesExactTargetAndPreservesCompetingScores() throws {
        let adapter = LinkedReducerAdapter()
        let initial = RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())
        let seed = try #require(LinkedReducerState(gameType: .pingpong, state: .rally(initial)))
        let first = operation(.rally(.pointWon(.left)), sequence: 1)
        let second = operation(.rally(.pointWon(.right)), sequence: 2)
        let (left, firstActions) = try accepted(adapter.transition(seed, first, 1_100))
        let (both, secondActions) = try accepted(adapter.transition(left, second, 1_200))
        #expect(firstActions.first?.id != secondActions.first?.id)

        let restored = try JSONDecoder().decode(LinkedReducerState.self, from: JSONEncoder().encode(both))
        #expect(restored.latestUndoableOperationId == second.opId)
        let competingUndo = operation(.undo(targetOpId: first.opId), sequence: 3)
        if case .rejected(.undoTargetUnavailable) = adapter.transition(restored, competingUndo, 1_300) {
            // The later, named edit still exists.
        } else {
            Issue.record("A stale undo removed the competing edit")
        }
        let exactUndo = operation(.undo(targetOpId: second.opId), sequence: 4)
        let (undone, actions) = try accepted(adapter.transition(restored, exactUndo, 1_400))
        #expect(undone == left)
        #expect(actions.first?.type == .undo)
        #expect(actions.first?.operationPayload == second.opId.uuidString)
        #expect(actions.first?.scores == [1, 0])
    }

    @Test func footballScoreUndoKeepsLaterClockEditsAndStopsAtAnotherGoal() throws {
        let adapter = LinkedReducerAdapter()
        let initial = FootballMatchReducer.initial(leftName: "L", rightName: "R", at: 1_000)
        let seed = try #require(LinkedReducerState(gameType: .football, state: .football(initial)))
        let goal = operation(.football(.goal(side: .left)), sequence: 1)
        let pause = operation(.football(.pauseClock), sequence: 2)
        let start = operation(.football(.startClock), sequence: 3)
        let (scored, _) = try accepted(adapter.transition(seed, goal, 1_600))
        let (paused, _) = try accepted(adapter.transition(scored, pause, 2_200))
        let (resumed, _) = try accepted(adapter.transition(paused, start, 3_000))
        #expect(resumed.latestFootballScoreUndoTargetId == goal.opId)
        #expect(resumed.latestUndoableOperationId == start.opId)

        let undo = operation(.undo(targetOpId: goal.opId), sequence: 4)
        let (restored, actions) = try accepted(adapter.transition(resumed, undo, 3_100))
        let (expectedPaused, _) = try accepted(adapter.transition(seed, pause, 2_200))
        let (expectedRestored, _) = try accepted(adapter.transition(expectedPaused, start, 3_000))
        #expect(restored == expectedRestored)
        #expect(try LinkStateHash.snapshot(adapter.snapshot(restored)) == LinkStateHash.snapshot(adapter.snapshot(expectedRestored)))
        #expect(restored.latestFootballScoreUndoTargetId == nil)
        #expect(actions.first?.type == .undo && actions.first?.scores == [0, 0])
        #expect(actions.first?.operationPayload == goal.opId.uuidString)

        let competingGoal = operation(.football(.goal(side: .right)), sequence: 4)
        let (competing, _) = try accepted(adapter.transition(resumed, competingGoal, 3_100))
        #expect(competing.latestFootballScoreUndoTargetId == competingGoal.opId)
        guard case .rejected(.undoTargetUnavailable) = adapter.transition(competing, undo, 3_200) else {
            Issue.record("Undo crossed a newer goal")
            return
        }
    }

    @Test func trainingUndoTargetsMatchingShotAndLeavesLaterShotsAtTheirOriginalTime() throws {
        let adapter = LinkedReducerAdapter()
        let training = ShotTrainingState(mode: .free, startTime: Date(timeIntervalSince1970: 1))
        let seed = try #require(LinkedReducerState(gameType: .basketballTraining, state: .shotTraining(training)))
        let missedTwo = operation(.shotTraining(.recordShot(points: 2, made: false)), sequence: 1)
        let madeTwo = operation(.shotTraining(.recordShot(points: 2, made: true)), sequence: 2)
        let madeThree = operation(.shotTraining(.recordShot(points: 3, made: true)), sequence: 3)
        let (one, _) = try accepted(adapter.transition(seed, missedTwo, 1_100))
        let (two, _) = try accepted(adapter.transition(one, madeTwo, 1_200))
        let (three, _) = try accepted(adapter.transition(two, madeThree, 1_300))
        #expect(three.latestShotTrainingUndoTargetId() == madeThree.opId)
        #expect(three.latestShotTrainingUndoTargetId(points: 2) == madeTwo.opId)
        #expect(three.latestShotTrainingUndoTargetId(made: true, points: 2) == madeTwo.opId)
        #expect(three.latestShotTrainingUndoTargetId(made: false) == missedTwo.opId)
        #expect(three.latestShotTrainingUndoTargetId(made: false, points: 3) == nil)

        let undo = operation(.undo(targetOpId: madeTwo.opId), sequence: 4)
        let (restored, actions) = try accepted(adapter.transition(three, undo, 1_400))
        let (expected, _) = try accepted(adapter.transition(one, madeThree, 1_300))
        #expect(restored == expected)
        #expect(actions.first?.type == .undo && actions.first?.scores == [1, 1])
        #expect(actions.first?.operationPayload == madeTwo.opId.uuidString)
        #expect(restored.latestShotTrainingUndoTargetId(points: 2) == missedTwo.opId)

        let finish = operation(.finish, sequence: 5)
        let (finished, _) = try accepted(adapter.transition(restored, finish, 1_500))
        #expect(finished.latestShotTrainingUndoTargetId() == nil)
        guard case .rejected(.matchFinished) = adapter.transition(finished, undo, 1_600) else {
            Issue.record("Undo crossed confirmed training finish")
            return
        }
    }

    @Test func ordinaryScoreOperationAndCommitFitCorePayloadBudgets() throws {
        let time: Int64 = 1_795_000_000_000
        let side = MatchSide.left
        let adapter = LinkedReducerAdapter()
        let rally = RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())
        let seed = try #require(LinkedReducerState(gameType: .pingpong, state: .rally(rally)))
        var phone = PhoneHostSequencer(
            checkpoint: PhoneHostCheckpoint(handle: handle, state: seed, initialEpochMilliseconds: time),
            snapshot: adapter.snapshot, isFinished: adapter.isFinished, transition: adapter.transition
        )
        let op = LinkOperation(
            opId: UUID(), handle: handle, origin: .watch, clientSeq: 1, baseRevision: 0,
            createdAtEpochMilliseconds: time, intent: .rally(.pointWon(side))
        )
        let commit = try phone.process(
            op, from: .watch, phoneClockReferenceEpochMilliseconds: time, lookup: { _ in nil }, persist: { _, _ in }
        )
        #expect(commit.authoritativeSnapshot == nil)
        #expect(commit.deltaActions.count == 1)
        let opData = try JSONEncoder().encode(op)
        let commitData = try JSONEncoder().encode(commit)
        #expect(opData.count < 300)
        #expect(commitData.count < 500)
        #expect(try JSONDecoder().decode(LinkOperation.self, from: opData) == op)
        #expect(try JSONDecoder().decode(LinkOperationCommitPayload.self, from: commitData) == commit)
    }

    @Test func intentAndReducerFamilyMustMatch() throws {
        let adapter = LinkedReducerAdapter()
        let initial = RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())
        #expect(LinkedReducerState(gameType: .tennis, state: .rally(initial)) == nil)
        let state = try #require(LinkedReducerState(gameType: .pingpong, state: .rally(initial)))
        let unrelated = operation(.football(.goal(side: .left)), sequence: 1)
        guard case .rejected(.intentFamilyMismatch) = adapter.transition(state, unrelated, 1_000) else {
            Issue.record("A football intent was accepted by the rally reducer")
            return
        }
    }

    private func operation(_ intent: LinkedScoreboardIntent, sequence: UInt64) -> LinkOperation {
        LinkOperation(
            opId: UUID(), handle: handle, origin: .watch, clientSeq: sequence,
            baseRevision: 0, createdAtEpochMilliseconds: 1_100, intent: intent
        )
    }

    private func accepted(
        _ transition: LinkIntentTransition<LinkedReducerState>
    ) throws -> (LinkedReducerState, [DetailedScoreAction]) {
        guard case .accepted(let state, let actions) = transition else {
            throw TestError.rejected
        }
        return (state, actions)
    }

    private enum TestError: Error { case rejected }
}
