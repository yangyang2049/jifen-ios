import Foundation
import ScoreCore
import SessionCore
import Testing

private let multiParticipantSeed = MultiParticipantState(
    participants: [
        .init(id: "a", name: "A"),
        .init(id: "b", name: "B")
    ]
)

@Test func multiParticipantAndroidContractFixtureAdjustsAndRenames() {
    let reducer = MultiParticipantReducer()

    let adjusted = reducer.reduce(
        state: multiParticipantSeed,
        intent: .adjustScore(id: "a", delta: 3),
        at: 1_000
    )
    #expect(adjusted.accepted)
    #expect(adjusted.state.participants.map(\.score) == [3, 0])
    #expect(adjusted.events == [.scoreChanged(id: "a", at: 1_000)])

    let renamed = reducer.reduce(
        state: adjusted.state,
        intent: .renameParticipant(id: "b", newName: "乙"),
        at: 2_000
    )
    #expect(renamed.accepted)
    #expect(renamed.state.participants.map(\.name) == ["A", "乙"])
    #expect(renamed.events == [.renamed(id: "b", at: 2_000)])
}

@Test func multiParticipantRejectsDuplicateAndMissingParticipantOperations() {
    let reducer = MultiParticipantReducer()

    let duplicate = reducer.reduce(
        state: multiParticipantSeed,
        intent: .addParticipant(id: "a", name: "duplicate"),
        at: 1
    )
    #expect(!duplicate.accepted)
    #expect(duplicate.state == multiParticipantSeed)
    #expect(duplicate.reason == "ID already exists")

    let missingRemove = reducer.reduce(
        state: multiParticipantSeed,
        intent: .removeParticipant(id: "missing"),
        at: 2
    )
    #expect(!missingRemove.accepted)
    #expect(missingRemove.reason == "Participant not found")

    let missingRename = reducer.reduce(
        state: multiParticipantSeed,
        intent: .renameParticipant(id: "missing", newName: "N"),
        at: 3
    )
    #expect(!missingRename.accepted)
    #expect(missingRename.reason == "Participant not found")

    let missingAdjust = reducer.reduce(
        state: multiParticipantSeed,
        intent: .adjustScore(id: "missing", delta: 1),
        at: 4
    )
    #expect(!missingAdjust.accepted)
    #expect(missingAdjust.reason == "Participant not found")
}

@Test func multiParticipantRemovalPolicyMatchesAndroidThreePointZero() {
    let reducer = MultiParticipantReducer()
    var scoredState = multiParticipantSeed
    scoredState.participants[0].score = 1

    let scoredRemoval = reducer.reduce(
        state: scoredState,
        intent: .removeParticipant(id: "a"),
        at: 1
    )
    #expect(!scoredRemoval.accepted)
    #expect(scoredRemoval.reason == "Cannot remove a participant with a score")

    let zeroRemoval = reducer.reduce(
        state: multiParticipantSeed,
        intent: .removeParticipant(id: "b"),
        at: 2
    )
    #expect(zeroRemoval.accepted)
    #expect(zeroRemoval.state.participants.map(\.id) == ["a"])
    #expect(zeroRemoval.events == [.participantRemoved(id: "b", at: 2)])

    scoredState.allowRemoveWhileHasScore = true
    let allowedRemoval = reducer.reduce(
        state: scoredState,
        intent: .removeParticipant(id: "a"),
        at: 3
    )
    #expect(allowedRemoval.accepted)
    #expect(allowedRemoval.state.participants.map(\.id) == ["b"])
}

@Test func multiParticipantClampsAdjustSetAndEditAtAndroidBounds() {
    let reducer = MultiParticipantReducer()
    var nearBounds = multiParticipantSeed
    nearBounds.participants[0].score = 9_998
    nearBounds.participants[1].score = -9_998

    let upper = reducer.reduce(
        state: nearBounds,
        intent: .adjustScore(id: "a", delta: Int.max),
        at: 1
    )
    #expect(upper.state.participants[0].score == MultiParticipantState.maximumScore)

    let lower = reducer.reduce(
        state: upper.state,
        intent: .adjustScore(id: "b", delta: Int.min),
        at: 2
    )
    #expect(lower.state.participants[1].score == MultiParticipantState.minimumScore)

    let set = reducer.reduce(
        state: lower.state,
        intent: .setScore(id: "a", score: -100_000),
        at: 3
    )
    #expect(set.state.participants[0].score == MultiParticipantState.minimumScore)

    let edited = reducer.reduce(
        state: set.state,
        intent: .editParticipant(id: "a", newName: "甲", score: 100_000),
        at: 4
    )
    #expect(edited.state.participants[0].name == "甲")
    #expect(edited.state.participants[0].score == MultiParticipantState.maximumScore)
    #expect(
        edited.events == [
            .renamed(id: "a", at: 4),
            .scoreChanged(id: "a", at: 4)
        ]
    )

    let unchanged = reducer.reduce(
        state: edited.state,
        intent: .editParticipant(id: "a", newName: "甲", score: 9_999),
        at: 5
    )
    #expect(unchanged.accepted)
    #expect(unchanged.events.isEmpty)
}

@Test func multiParticipantFinishBlocksMutationButResetReopensSession() {
    let reducer = MultiParticipantReducer()
    let scored = reducer.reduce(
        state: multiParticipantSeed,
        intent: .adjustScore(id: "a", delta: 7),
        at: 1
    )
    let finished = reducer.reduce(state: scored.state, intent: .finish, at: 2)
    #expect(finished.accepted)
    #expect(finished.state.finished)
    #expect(finished.events == [.finished])

    let blocked = reducer.reduce(
        state: finished.state,
        intent: .adjustScore(id: "b", delta: 1),
        at: 3
    )
    #expect(!blocked.accepted)
    #expect(blocked.reason == "Already finished")
    #expect(blocked.state == finished.state)

    let reset = reducer.reduce(state: finished.state, intent: .reset, at: 4)
    #expect(reset.accepted)
    #expect(!reset.state.finished)
    #expect(reset.state.participants.map(\.score) == [0, 0])
    #expect(reset.events == [.reset])
}

@Test func multiParticipantLegacySnapshotDecodesAndroidDefaults() throws {
    let data = Data(
        #"{"participants":[{"id":"a","name":"A","score":5}],"finished":false}"#.utf8
    )
    let state = try JSONDecoder().decode(MultiParticipantState.self, from: data)
    #expect(state.allowRemoveWhileHasScore == false)
    #expect(state.minScore == -9_999)
    #expect(state.maxScore == 9_999)
}

@Test func unoTargetMetadataAndUndoHistorySurviveResume() async throws {
    guard let original = ScoreboardSessionFactory.uno(
        playerNames: ["甲", "乙"],
        targetScore: 500
    ) else {
        Issue.record("UNO factory rejected a valid Android setup")
        return
    }

    _ = await original.dispatch(
        actorId: "phone",
        intent: .adjustScore(id: "p0", delta: 500),
        at: 1
    )
    // Android's controller, rather than S3 reducer, owns target detection.
    #expect(await original.snapshot().status == .live)

    _ = await original.dispatch(actorId: "phone", intent: .finish, at: 2)
    #expect(await original.snapshot().status == .finished)

    let encoded = try JSONEncoder().encode(await original.resumeBundle())
    let decoded = try JSONDecoder().decode(
        ScoreSessionResumeBundle<
            MultiParticipantState,
            MultiParticipantEvent,
            MultiParticipantIntent
        >.self,
        from: encoded
    )
    let resumed = ScoreSessionCore(
        resumeBundle: decoded,
        reducer: MultiParticipantReducer(),
        shouldFinish: { _, state in state.finished }
    )

    #expect(await resumed.snapshot().metadata.extras["targetScore"] == "500")
    #expect(await resumed.undo(actorId: "phone"))
    #expect(await resumed.snapshot().status == .live)
    #expect(await resumed.snapshot().state.participants[0].score == 500)
    #expect(await resumed.undo(actorId: "phone"))
    #expect(await resumed.snapshot().state.participants[0].score == 0)
}
