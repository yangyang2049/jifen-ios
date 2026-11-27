import Foundation
import LinkCore
import LinkSync
import ScoreCore
import Testing

@MainActor
struct PhoneLinkedIntentCoordinatorRecoveryTests {
    private enum Interrupted: Error { case beforeProjection }

    @Test func recoversProjectionBeforeReturningOriginalReceiptAndKeepsOldMatchIsolated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let successor = handle.nextMatch(matchId: UUID())
        let rally = RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())
        let localID = UUID()
        let score: LinkedScoreboardIntent = .rally(.pointWon(.left))
        let time: Int64 = 1_100
        do {
            let interrupted = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) { _ in
                throw Interrupted.beforeProjection
            }
            try interrupted.activate(handle: handle, gameType: .pingpong, initialSnapshot: .rally(rally), initialEpochMilliseconds: 1_000)
            #expect(throws: Interrupted.beforeProjection) {
                try interrupted.submitLocal(
                    score, handle: handle, opId: localID, createdAtEpochMilliseconds: time,
                    phoneClockReferenceEpochMilliseconds: time
                )
            }
            #expect(interrupted.activeCheckpoint?.committedRevision == 1)
        }

        var projections = [PhoneLinkedIntentCoordinator.Projection]()
        let host = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) { projections.append($0) }
        let recovered = try host.recoverActiveMatch(handle: handle)
        #expect(recovered.phoneClientSeq == 1)
        #expect(projections.count == 1)
        let original = try #require(projections.first?.commits.first)
        let duplicate = try host.submitLocal(
            score, handle: handle, opId: localID, createdAtEpochMilliseconds: time,
            phoneClockReferenceEpochMilliseconds: 10_000
        )
        #expect(duplicate == original)
        #expect(projections.count == 1)

        _ = try host.submitLocal(
            .finish, handle: handle, opId: UUID(), createdAtEpochMilliseconds: 1_200,
            phoneClockReferenceEpochMilliseconds: 1_200
        )
        let rollover = try host.submitLocal(
            .nextMatch(matchId: successor.matchId, matchGeneration: successor.matchGeneration),
            handle: handle, opId: UUID(), createdAtEpochMilliseconds: 1_250,
            phoneClockReferenceEpochMilliseconds: 1_250
        )
        #expect(rollover.outcome == .accepted)
        #expect(host.activeCheckpoint?.nextMatchHandle == successor)
        try host.activate(
            handle: successor, gameType: .pingpong, initialSnapshot: .rally(rally), initialEpochMilliseconds: 2_000
        )
        let late = LinkOperation(
            opId: UUID(), handle: handle, origin: .watch, clientSeq: 1, baseRevision: 0,
            createdAtEpochMilliseconds: 1_300, intent: .rally(.pointWon(.right))
        )
        let rejected = try host.receiveWatchOperation(late, phoneClockReferenceEpochMilliseconds: 2_100)
        #expect(rejected.rejectionReason == LinkOperationRejectionReason.matchFinished.rawValue)
        #expect(projections.last?.checkpoint.handle == handle && projections.last?.isActiveMatch == false)
        #expect(host.activeCheckpoint?.handle == successor && host.activeCheckpoint?.committedRevision == 0)
        let repair = try host.checkpoint(for: handle, watchOperationIds: [late.opId], afterConfirmedRevision: 0)
        #expect(repair.watchResults == [LinkProcessedOperation(commit: rejected)])
        #expect(repair.watchClientSeq == 1)
    }

    private var adapter: LinkedReducerAdapter {
        LinkedReducerAdapter()
    }

    @Test func retiredUnfinishedMatchReturnsRepeatableRejection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let retired = LinkedMatchHandle(sessionId: UUID())
        let active = LinkedMatchHandle(sessionId: UUID())
        let state = RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())
        let host = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) { _ in }
        try host.activate(handle: retired, gameType: .pingpong, initialSnapshot: .rally(state), initialEpochMilliseconds: 1_000)
        host.deactivate(handle: retired)
        try host.activate(handle: active, gameType: .pingpong, initialSnapshot: .rally(state), initialEpochMilliseconds: 2_000)
        let late = LinkOperation(
            opId: UUID(), handle: retired, origin: .watch, clientSeq: 1, baseRevision: 0,
            createdAtEpochMilliseconds: 1_100, intent: .rally(.pointWon(.left))
        )
        let result = try host.receiveWatchOperation(late, phoneClockReferenceEpochMilliseconds: 2_100)
        #expect(result.rejectionReason == LinkOperationRejectionReason.sessionInactive.rawValue)
        #expect(try host.receiveWatchOperation(late, phoneClockReferenceEpochMilliseconds: 2_200) == result)
        #expect(host.activeCheckpoint?.handle == active && host.activeCheckpoint?.committedRevision == 0)
    }
}
