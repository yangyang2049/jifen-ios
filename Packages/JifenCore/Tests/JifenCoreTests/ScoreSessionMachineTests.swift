import Foundation
import ScoreCore
import SessionCore
import Testing

@Test func synchronousSessionMachineMatchesTheActorAndKeepsResumeData() async throws {
    let seed = ScoreSession<LineScoreState, LineScoreEvent>(
        gameType: .simpleScore,
        ruleFamily: .s1,
        reducerType: "line/v1",
        state: LineScoreState(leftName: "A", rightName: "B")
    )
    let canDispatch: @Sendable (String, LineScoreIntent) -> Bool = { actor, _ in actor == "watch" }
    let canUndo: @Sendable (String) -> Bool = { $0 == "watch" }
    let shouldFinish: @Sendable (LineScoreIntent, LineScoreState) -> Bool = { _, state in state.finished }
    var machine = ScoreSessionMachine(
        seedSession: seed, reducer: LineScoreReducer(), canDispatch: canDispatch, canUndo: canUndo, shouldFinish: shouldFinish
    )
    let actor = ScoreSessionCore(
        seedSession: seed, reducer: LineScoreReducer(), canDispatch: canDispatch, canUndo: canUndo, shouldFinish: shouldFinish
    )

    let denied = machine.dispatch(actorId: "peer", intent: .pointWon(.left), at: 1_000)
    guard case .rejected(let rejected, let reason) = denied else {
        Issue.record("Expected the session's permission policy to reject the intent")
        return
    }
    #expect(rejected.version == seed.version)
    #expect(reason == "Permission denied")

    _ = machine.dispatch(actorId: "watch", intent: .pointWon(.left), at: 2_000)
    _ = await actor.dispatch(actorId: "watch", intent: .pointWon(.left), at: 2_000)
    _ = machine.dispatchNonUndoable(actorId: "watch", intent: .setNames(left: "甲", right: "乙"), at: 3_000)
    _ = await actor.dispatchNonUndoable(actorId: "watch", intent: .setNames(left: "甲", right: "乙"), at: 3_000)
    #expect(machine.intentTimeline().map(\.epochMilliseconds) == [2_000])
    #expect(machine.currentSession.state.leftName == "甲")
    let replayed = try machine.replay()
    #expect(replayed.state.leftName == "A")
    #expect(replayed.state.leftScore == 1)

    let participants = [SessionParticipant(id: "home", name: "甲")]
    let metadata = SessionMetadata(title: "Training")
    let payload = Data([1, 2, 3])
    machine.updateParticipants(participants)
    await actor.updateParticipants(participants)
    machine.updateMetadata(metadata)
    await actor.updateMetadata(metadata)
    machine.setResumeAuxiliaryPayload(payload)
    await actor.setResumeAuxiliaryPayload(payload)

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let encoded = try encoder.encode(machine.resumeBundle())
    let actorBundle = await actor.resumeBundle()
    #expect(try encoder.encode(actorBundle) == encoded)
    let decoded = try JSONDecoder().decode(ScoreSessionResumeBundle<LineScoreState, LineScoreEvent, LineScoreIntent>.self, from: encoded)
    var restored = ScoreSessionMachine(resumeBundle: decoded, reducer: LineScoreReducer(), canUndo: canUndo)

    let merge: @Sendable (LineScoreState, LineScoreState) -> LineScoreState = { previous, current in
        var result = previous
        result.leftName = current.leftName
        result.rightName = current.rightName
        return result
    }
    let deniedUndo = restored.undo(actorId: "peer")
    #expect(!deniedUndo)
    let restoredUndo = restored.undo(actorId: "watch", mergingState: merge)
    let actorUndo = await actor.undo(actorId: "watch", mergingState: merge)
    #expect(restoredUndo && actorUndo)
    #expect(restored.currentSession.state.leftScore == 0)
    #expect(restored.currentSession.state.leftName == "甲")
    #expect(restored.currentSession.metadata.title == "Training")
    #expect(restored.currentSession.participants.map(\.name) == ["甲"])
    #expect(restored.resumeBundle().auxiliaryPayload == payload)
    #expect(restored.intentTimeline().isEmpty)
    let undone = await actor.resumeBundle()
    #expect(try encoder.encode(restored.resumeBundle()) == encoder.encode(undone))
}

@Test func copiedMachineKeepsIndependentUndoAndRebaseState() throws {
    let seed = ScoreSession<LineScoreState, LineScoreEvent>(
        gameType: .simpleScore, ruleFamily: .s1, reducerType: "line/v1",
        state: LineScoreState(leftName: "A", rightName: "B")
    )
    var confirmed = ScoreSessionMachine(seedSession: seed, reducer: LineScoreReducer())
    _ = confirmed.dispatch(actorId: "phone", intent: .pointWon(.left), at: 1_000)

    var optimistic = confirmed
    _ = optimistic.dispatch(actorId: "watch", intent: .pointWon(.right), at: 2_000)
    #expect(optimistic.currentSession.state.rightScore == 1)
    #expect(confirmed.currentSession.state.rightScore == 0)
    #expect(confirmed.resumeBundle().undoFrames.count == 1)

    let authoritative = LineScoreState(leftName: "A", rightName: "B", leftScore: 2)
    optimistic.rebase(to: authoritative, status: .finished)
    let crossedRebase = optimistic.undo(actorId: "watch")
    #expect(!crossedRebase)
    #expect(optimistic.resumeBundle().undoFrames.isEmpty)
    #expect(optimistic.intentTimeline().isEmpty)
    let rebased = try optimistic.replay()
    #expect(rebased.state == authoritative)
    #expect(rebased.status == .finished)

    let confirmedUndo = confirmed.undo(actorId: "phone")
    #expect(confirmedUndo)
    #expect(confirmed.currentSession.state.leftScore == 0)
    #expect(optimistic.currentSession.state.leftScore == 2)
}
