import Foundation
import LinkCore
import LinkSync
import ScoreCore
import Testing

@Suite struct SharedIntentSyncTests {
    private let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
    private enum StorageFailure: Error { case interrupted }

    @Test func concurrentScoresWithSameBaseRevisionMergeAndRetryReturnsOriginalReceipt() throws {
        var phone = makePhone()
        var watch = makeWatch()
        let journal = Journal<Score>()
        let optimistic = try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_100) { _ in }
        #expect(watch.displayedState.right == 1)

        let local = operation(.rally(.pointWon(.left)), from: .phone, sequence: 1)
        let first = try journal.submit(local, to: &phone)
        let second = try journal.submit(optimistic, to: &phone)
        #expect(second.op.baseRevision == first.op.baseRevision)
        #expect(try watch.receive(first) { _ in } == .advanced)
        #expect(watch.displayedState.left == 1 && watch.displayedState.right == 1)
        #expect(try watch.receive(second) { _ in } == .advanced)
        #expect(watch.checkpoint.confirmedState == phone.checkpoint.state)
        #expect(try LinkStateHash.snapshot(Score.snapshot(watch.checkpoint.confirmedState)) == second.stateHash)
        #expect(watch.checkpoint.pendingOperations.isEmpty)

        let restored = try roundTrip(phone.checkpoint)
        phone = makePhone(checkpoint: restored)
        for _ in 0..<3 {
            #expect(try journal.submit(optimistic, to: &phone, at: 99_000) == second)
        }
        #expect(journal.receipts.count == 2)
        #expect(phone.checkpoint.committedRevision == 2)
    }

    @Test func persistenceErrorsLeaveBothStatesAndQueuesUnchanged() throws {
        var phone = makePhone()
        var watch = makeWatch()
        let id = UUID()
        #expect(throws: StorageFailure.interrupted) {
            try watch.enqueue(.rally(.pointWon(.right)), opId: id, createdAtEpochMilliseconds: 1_000) { _ in
                throw StorageFailure.interrupted
            }
        }
        #expect(watch.checkpoint.pendingOperations.isEmpty)
        #expect(watch.displayedState == Score())
        let pending = try watch.enqueue(.rally(.pointWon(.right)), opId: id, createdAtEpochMilliseconds: 1_000) { _ in }
        #expect(throws: StorageFailure.interrupted) {
            try phone.process(pending, from: .watch, phoneClockReferenceEpochMilliseconds: 1_000, lookup: { _ in nil }) { _, _ in
                throw StorageFailure.interrupted
            }
        }
        #expect(phone.checkpoint.committedRevision == 0)
        #expect(phone.checkpoint.state == Score())
        let journal = Journal<Score>()
        let commit = try journal.submit(pending, to: &phone)
        #expect(throws: StorageFailure.interrupted) {
            try watch.receive(commit) { _ in throw StorageFailure.interrupted }
        }
        #expect(watch.checkpoint.committedRevision == 0)
        #expect(watch.checkpoint.pendingOperations.first?.operation == pending)
        #expect(try watch.receive(commit) { _ in } == .advanced)
        #expect(watch.checkpoint.confirmedState == phone.checkpoint.state)
    }

    @Test func revisionGapRepairsOnlyWithReceiptsForProcessedPendingOperations() throws {
        var phone = makePhone()
        var watch = makeWatch()
        let journal = Journal<Score>()
        let local = try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_100) { _ in }
        let next = try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_200) { _ in }
        let first = try journal.submit(operation(.rally(.pointWon(.left)), from: .phone, sequence: 1), to: &phone)
        let skipped = try journal.submit(local, to: &phone)
        let third = try journal.submit(operation(.rally(.pointWon(.left)), from: .phone, sequence: 2), to: &phone)
        #expect(try watch.receive(first) { _ in } == .advanced)
        #expect(try watch.receive(third) { _ in Issue.record("Gap persisted") } == .needsResync)
        #expect(watch.checkpoint.committedRevision == 1)

        let missing = try phone.authoritativeCheckpoint(watchResults: [])
        #expect(try watch.receive(missing) { _ in Issue.record("Missing receipt persisted") } == .needsResync)
        #expect(watch.checkpoint.pendingOperations.count == 2)
        let authority = try phone.authoritativeCheckpoint(watchResults: [first, skipped, third])
        let decoded = try roundTrip(authority)
        #expect(try watch.receive(decoded) { _ in } == .advanced)
        #expect(watch.checkpoint.pendingOperations.map(\.operation) == [next])
        #expect(watch.checkpoint.confirmedState.left == 2 && watch.checkpoint.confirmedState.right == 1)
        #expect(watch.displayedState.right == 2)
        #expect(try watch.receive(decoded) { _ in Issue.record("Duplicate checkpoint persisted") } == .alreadyConfirmed)
    }

    @Test func hashMismatchPreservesPendingThenAuthorityRepairsSameRevision() throws {
        var phone = makePhone()
        var watch = makeWatch()
        let journal = Journal<Score>()
        let op = try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_000) { _ in }
        let good = try journal.submit(op, to: &phone)
        let bad = LinkOperationCommitPayload(
            committedRevision: good.committedRevision, op: good.op, outcome: good.outcome,
            effectiveEpochMilliseconds: good.effectiveEpochMilliseconds, timeWasClamped: false,
            stateHash: good.stateHash ^ 1
        )
        #expect(try watch.receive(bad) { _ in Issue.record("Corrupt hash persisted") } == .needsResync)
        #expect(watch.checkpoint.pendingOperations.first?.operation == op)
        #expect(try watch.receive(good) { _ in } == .advanced)

        var freshWatch = makeWatch()
        var initial = Score()
        initial.left = 2
        let seedHost = makePhone(checkpoint: PhoneHostCheckpoint(handle: handle, state: initial, initialEpochMilliseconds: 1_000))
        let seedAuthority = try seedHost.authoritativeCheckpoint(watchResults: [])
        #expect(try freshWatch.receive(seedAuthority) { _ in } == .advanced)
        #expect(freshWatch.checkpoint.committedRevision == 0)
        #expect(freshWatch.displayedState == initial)
    }

    @Test(arguments: [false, true])
    func offlineFinishSurvivesRestartAndConvergesToOneResult(phoneFinishedFirst: Bool) throws {
        var phone = makePhone()
        var watch = makeWatch()
        let journal = Journal<Score>()
        for _ in 0..<2 {
            try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_200) { _ in }
        }
        try watch.enqueue(.finish, opId: UUID(), createdAtEpochMilliseconds: 1_300) { _ in }
        watch = makeWatch(checkpoint: try roundTrip(watch.checkpoint))
        #expect(watch.isPendingFinish)
        if phoneFinishedFirst {
            _ = try journal.submit(operation(.rally(.pointWon(.left)), from: .phone, sequence: 1), to: &phone)
            let finishing = try journal.submit(operation(.finish, from: .phone, sequence: 2), to: &phone)
            #expect(finishing.outcome == .accepted)
            #expect(try watch.receive(finishing) { _ in Issue.record("Gap persisted") } == .needsResync)
        }
        let outstanding = watch.checkpoint.pendingOperations.map(\.operation)
        let results = try outstanding.map { try journal.submit($0, to: &phone) }
        if phoneFinishedFirst {
            let authority = try phone.authoritativeCheckpoint(watchResults: results)
            #expect(try watch.receive(authority) { _ in } == .advanced)
            #expect(try watch.receive(authority) { _ in Issue.record("Checkpoint persisted twice") } == .alreadyConfirmed)
            #expect(watch.checkpoint.excludedScoringOperationCount == 2)
            #expect(phone.checkpoint.state.left == 1 && phone.checkpoint.state.right == 0)
            #expect(results.allSatisfy { $0.rejectionReason == LinkOperationRejectionReason.matchFinished.rawValue })
        } else {
            for result in results { #expect(try watch.receive(result) { _ in } == .advanced) }
            #expect(watch.checkpoint.excludedScoringOperationCount == 0)
            #expect(phone.checkpoint.state.right == 2)
            #expect(results.last?.outcome == .accepted)
        }
        #expect(watch.checkpoint.confirmedState.finished)
        #expect(Score.snapshot(watch.checkpoint.confirmedState) == Score.snapshot(phone.checkpoint.state))
        #expect(!watch.isPendingFinish && watch.checkpoint.pendingOperations.isEmpty)
        #expect(watch.checkpoint.handle.matchId == phone.checkpoint.handle.matchId)
        for (op, result) in zip(outstanding, results) {
            #expect(try journal.submit(op, to: &phone) == result)
            #expect(try watch.receive(result) { _ in Issue.record("Duplicate result persisted") } == .alreadyConfirmed)
        }
    }

    @Test func undoOfUnsentTailReusesSequenceAndSentUndoCannotUndoAnotherPeersEdit() throws {
        var phone = makePhone()
        var watch = makeWatch()
        let journal = Journal<Score>()
        let first = try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_000) { _ in }
        let canceled = try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_100) { _ in }
        #expect(try watch.cancelUnsentScore(canceled.opId) { _ in })
        #expect(watch.displayedState.right == 1)
        let replacement = try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_150) { _ in }
        #expect(replacement.clientSeq == canceled.clientSeq)
        for op in [first, replacement] {
            try watch.markSent(op.opId) { _ in }
            #expect(try watch.receive(journal.submit(op, to: &phone)) { _ in } == .advanced)
        }

        let acceptedUndo = try watch.enqueue(.undo(targetOpId: replacement.opId), opId: UUID(), createdAtEpochMilliseconds: 1_200) { _ in }
        let undoCommit = try journal.submit(acceptedUndo, to: &phone)
        #expect(undoCommit.authoritativeSnapshot != nil)
        #expect(try watch.receive(undoCommit) { _ in } == .advanced)
        #expect(watch.checkpoint.confirmedState.right == 1)

        let competing = try journal.submit(operation(.rally(.pointWon(.left)), from: .phone, sequence: 1), to: &phone)
        #expect(try watch.receive(competing) { _ in } == .advanced)
        let staleUndo = try watch.enqueue(.undo(targetOpId: first.opId), opId: UUID(), createdAtEpochMilliseconds: 1_300) { _ in }
        let rejected = try journal.submit(staleUndo, to: &phone)
        #expect(rejected.rejectionReason == LinkOperationRejectionReason.undoTargetUnavailable.rawValue)
        #expect(try watch.receive(rejected) { _ in } == .advanced)
        #expect(watch.displayedState.left == 1 && watch.displayedState.right == 1)
    }

    @Test(arguments: [10, 50])
    func offlineBatchesKeepOrderAcrossRestartAndRejectLateOldMatchOnActiveJournal(count: Int) throws {
        var phone = makePhone()
        var watch = makeWatch()
        let journal = Journal<Score>()
        for seq in 1...count {
            let op = try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_000 + Int64(seq)) { _ in }
            #expect(op.clientSeq == UInt64(seq))
        }
        watch = makeWatch(checkpoint: try roundTrip(watch.checkpoint))
        let outbox = watch.checkpoint.pendingOperations
        let competing = try journal.submit(operation(.rally(.pointWon(.left)), from: .phone, sequence: 1), to: &phone)
        #expect(throws: PhoneHostSequenceError.missingSequence(expected: 1)) {
            try journal.submit(outbox[1].operation, to: &phone)
        }
        #expect(try watch.receive(competing) { _ in } == .advanced)
        for pending in outbox {
            let status = try journal.submit(pending.operation, to: &phone)
            #expect(try watch.receive(status) { _ in } == .advanced)
        }
        #expect(watch.displayedState.left == 1 && watch.displayedState.right == count)
        #expect(watch.checkpoint.pendingOperations.isEmpty)
        let finishing = try journal.submit(operation(.finish, from: .phone, sequence: 2), to: &phone)
        #expect(try watch.receive(finishing) { _ in } == .advanced)
        let nextId = UUID()
        let rollover = try journal.submit(operation(.nextMatch(matchId: nextId, matchGeneration: 2), from: .phone, sequence: 3), to: &phone)
        let nextHandle = try #require(phone.checkpoint.nextMatchHandle)
        #expect(rollover.op.handle == handle && rollover.outcome == .accepted)
        #expect(nextHandle.matchId == nextId)
        let late = operation(.rally(.pointWon(.right)), from: .watch, sequence: UInt64(count + 1))
        var next = makePhone(checkpoint: PhoneHostCheckpoint(handle: nextHandle, state: Score(), initialEpochMilliseconds: 2_000))
        #expect(throws: PhoneHostSequenceError.wrongHandle) {
            try journal.submit(late, to: &next)
        }
        let archived = try journal.submit(late, to: &phone, active: false)
        #expect(archived.rejectionReason == LinkOperationRejectionReason.matchFinished.rawValue)
        #expect(next.checkpoint.committedRevision == 0 && next.checkpoint.state == Score())
        #expect(phone.checkpoint.state.right == count)
    }

    @Test func limitsHaveFinishReserveAndNeverDiscardExistingPendingScores() throws {
        var watch = makeWatch(pendingLimit: 2, pendingAgeLimitMilliseconds: 10)
        try watch.enqueue(.rally(.pointWon(.left)), opId: UUID(), createdAtEpochMilliseconds: 1_000) { _ in }
        #expect(throws: WatchReplayQueueError.queueTooOld) {
            try watch.enqueue(.rally(.pointWon(.left)), opId: UUID(), createdAtEpochMilliseconds: 1_011) { _ in }
        }
        try watch.enqueue(.rally(.pointWon(.right)), opId: UUID(), createdAtEpochMilliseconds: 1_005) { _ in }
        #expect(throws: WatchReplayQueueError.queueFull) {
            try watch.enqueue(.rally(.pointWon(.left)), opId: UUID(), createdAtEpochMilliseconds: 1_006) { _ in }
        }
        try watch.enqueue(.finish, opId: UUID(), createdAtEpochMilliseconds: 10_000) { _ in }
        #expect(watch.checkpoint.pendingOperations.count == 3)
        #expect(watch.isPendingFinish)
        #expect(throws: WatchReplayQueueError.awaitingFinishConfirmation) {
            try watch.enqueue(.nextMatch(matchId: UUID(), matchGeneration: 2), opId: UUID(), createdAtEpochMilliseconds: 10_000) { _ in }
        }
    }

    @Test func footballReplaysAcceptedEffectiveTimesWhileHostClockMovesBackwards() throws {
        let initial = FootballMatchReducer.initial(leftName: "L", rightName: "R", at: 1_000)
        func transition(_ state: FootballMatchState, _ op: LinkOperation, _ time: Int64) -> LinkIntentTransition<FootballMatchState> {
            guard case .football(let intent) = op.intent else { return .rejected(.reducerRejected) }
            let result = FootballMatchReducer().reduce(state: state, intent: intent, at: time)
            return result.accepted ? .accepted(state: result.state) : .rejected(.reducerRejected)
        }
        func snapshot(_ state: FootballMatchState) -> LinkedScoreboardSnapshot {
            .football(LinkedFootballState(
                leftName: state.leftName, rightName: state.rightName, leftScore: state.leftScore,
                rightScore: state.rightScore, timer: state.timer, kickedOff: state.kickedOff, finished: state.finished
            ))
        }
        var phone = PhoneHostSequencer(
            checkpoint: PhoneHostCheckpoint(handle: handle, state: initial, initialEpochMilliseconds: 1_000),
            snapshot: snapshot, isFinished: \.finished, transition: transition
        )
        var watch = WatchOptimisticReplayEngine(
            checkpoint: WatchReplayCheckpoint(handle: handle, confirmedState: initial, initialEpochMilliseconds: 1_000),
            snapshot: snapshot, installSnapshot: { _, _ in nil }, isFinished: \.finished, transition: transition
        )
        let journal = Journal<FootballMatchState>()
        let behind = try watch.enqueue(.football(.goal(side: .left)), opId: UUID(), createdAtEpochMilliseconds: 100) { _ in }
        let faster = try watch.enqueue(.football(.goal(side: .right)), opId: UUID(), createdAtEpochMilliseconds: 241_000) { _ in }
        let local = operation(.football(.goal(side: .left)), from: .phone, sequence: 1, createdAt: 60_500)
        let first = try journal.submit(behind, to: &phone, at: 2_000)
        let second = try journal.submit(faster, to: &phone, at: 61_000)
        let third = try journal.submit(local, to: &phone, at: 59_000)
        #expect([first, second, third].map(\.effectiveEpochMilliseconds) == [1_000, 63_000, 63_000])
        #expect([first, second, third].map(\.timeWasClamped) == [true, true, true])
        #expect(phone.checkpoint.phoneClockReferenceEpochMilliseconds == 61_000)
        for commit in [first, second, third] {
            #expect(try watch.receive(commit) { _ in } == .advanced)
        }
        #expect(phone.checkpoint.state == watch.checkpoint.confirmedState)
        #expect(phone.checkpoint.state.timer.savedWallClockMilliseconds == 63_000)
        #expect(FootballMatchReducer.displayElapsedSeconds(state: phone.checkpoint.state, at: 63_000) == 62)
        #expect(try LinkStateHash.snapshot(snapshot(watch.checkpoint.confirmedState)) == third.stateHash)
    }

    private func operation(
        _ intent: LinkedScoreboardIntent, from origin: LinkPeer, sequence: UInt64, createdAt: Int64 = 1_100
    ) -> LinkOperation {
        LinkOperation(opId: UUID(), handle: handle, origin: origin, clientSeq: sequence,
                      baseRevision: 0, createdAtEpochMilliseconds: createdAt, intent: intent)
    }

    private func makePhone(checkpoint: PhoneHostCheckpoint<Score>? = nil) -> PhoneHostSequencer<Score> {
        PhoneHostSequencer(
            checkpoint: checkpoint ?? PhoneHostCheckpoint(handle: handle, state: Score(), initialEpochMilliseconds: 1_000),
            snapshot: Score.snapshot, isFinished: \.finished, transition: Score.transition
        )
    }

    private func makeWatch(
        checkpoint: WatchReplayCheckpoint<Score>? = nil,
        pendingLimit: Int = 500,
        pendingAgeLimitMilliseconds: Int64 = 604_800_000
    ) -> WatchOptimisticReplayEngine<Score> {
        WatchOptimisticReplayEngine(
            checkpoint: checkpoint ?? WatchReplayCheckpoint(handle: handle, confirmedState: Score(), initialEpochMilliseconds: 1_000),
            pendingLimit: pendingLimit, pendingAgeLimitMilliseconds: pendingAgeLimitMilliseconds,
            snapshot: Score.snapshot, installSnapshot: Score.install, isFinished: \.finished, transition: Score.transition
        )
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private final class Journal<State> {
        var receipts: [UUID: LinkOperationCommitPayload] = [:]

        func submit(
            _ operation: LinkOperation, to phone: inout PhoneHostSequencer<State>, at: Int64 = 1_100, active: Bool = true
        ) throws -> LinkOperationCommitPayload {
            try phone.process(operation, from: operation.origin, phoneClockReferenceEpochMilliseconds: at, isActiveMatch: active,
                              lookup: { receipts[$0] }, persist: { _, commit in receipts[commit.op.opId] = commit })
        }
    }

    private struct Score: Codable, Equatable {
        var left = 0
        var right = 0
        var finished = false
        var lastOpId: UUID?
        var lastSide: MatchSide?

        static func snapshot(_ score: Self) -> LinkedScoreboardSnapshot {
            var state = RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())
            state.leftPoints = score.left
            state.rightPoints = score.right
            state.finished = score.finished
            return .rally(state)
        }

        static func install(_: Self, _ snapshot: LinkedScoreboardSnapshot) -> Self? {
            guard case .rally(let rally) = snapshot else { return nil }
            return Score(left: rally.leftPoints, right: rally.rightPoints, finished: rally.finished)
        }

        static func transition(_ state: Self, _ op: LinkOperation, _ time: Int64) -> LinkIntentTransition<Self> {
            var next = state
            switch op.intent {
            case .rally(.pointWon(let side)):
                if side == .left { next.left += 1 } else { next.right += 1 }
                next.lastOpId = op.opId
                next.lastSide = side
            case .undo(let target):
                guard (target == nil || target == state.lastOpId), let side = state.lastSide else {
                    return .rejected(.undoTargetUnavailable)
                }
                if side == .left { next.left -= 1 } else { next.right -= 1 }
                next.lastOpId = nil
                next.lastSide = nil
            case .finish:
                next.finished = true
            default:
                return .rejected(.reducerRejected)
            }
            return .accepted(state: next)
        }
    }
}
