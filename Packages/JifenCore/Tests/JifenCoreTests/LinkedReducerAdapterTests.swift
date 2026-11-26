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

        let adapter = makeAdapter()
        for (gameType, native, intent) in cases {
            let seed = try #require(LinkedReducerState(gameType: gameType, state: native))
            let scoring = operation(intent, sequence: 1)
            let (next, actions) = try accepted(adapter.transition(seed, scoring, 63_000))
            let (replayed, replayedActions) = try accepted(adapter.transition(seed, scoring, 63_000))
            #expect(next == replayed, "Non-deterministic state for \(gameType)")
            #expect(actions == replayedActions && !actions.isEmpty, "Non-deterministic or missing actions for \(gameType)")
            #expect(actions.map(\.epochMilliseconds) == Array(repeating: 63_000, count: actions.count))
            if gameType == .football {
                #expect(actions.first?.operationCode == "football_goal")
                #expect(actions.first?.footballPeriod == 1)
                #expect(actions.first?.footballElapsedSeconds == 62)
            }
            let finishing = operation(.finish, sequence: 2)
            let (finished, finalActions) = try accepted(adapter.transition(next, finishing, 64_000))
            #expect(adapter.isFinished(finished))
            #expect(finalActions.contains { $0.type == .matchFinished })
        }
    }

    @Test func restoredUndoUsesExactTargetAndPreservesCompetingScores() throws {
        let adapter = makeAdapter()
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

    @Test func ordinaryScoreOperationAndCommitFitCorePayloadBudgets() throws {
        let time: Int64 = 1_795_000_000_000
        let side = MatchSide.left
        let adapter = makeAdapter()
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
        let adapter = makeAdapter()
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

    private func makeAdapter() -> LinkedReducerAdapter {
        LinkedReducerAdapter(
            encodeArchery: { .archery(.init(match: $0)) },
            decodeArchery: {
                guard case .archery(let snapshot) = $0 else { return nil }
                var match = ArcheryMatchState(leftName: snapshot.leftName, rightName: snapshot.rightName)
                snapshot.applying(to: &match)
                return match
            },
            encodeFootball: {
                .football(.init(
                    leftName: $0.leftName, rightName: $0.rightName, leftScore: $0.leftScore, rightScore: $0.rightScore,
                    timer: $0.timer, kickedOff: $0.kickedOff, finished: $0.finished
                ))
            },
            // The production codec must include the native clock remainder
            // and stoppage history. This fixture exercises the reducer path.
            decodeFootball: { _ in nil }
        )
    }
}
