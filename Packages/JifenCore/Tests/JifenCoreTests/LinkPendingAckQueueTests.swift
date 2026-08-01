import Foundation
import LinkCore
import ScoreCore
import Testing

@Test func linkControlRetryQueueRetriesThenClears() {
    var queue = LinkControlRetryQueue()
    let messageId = UUID()
    let data = Data([1, 2, 3])
    queue.enqueue(.init(
        messageId: messageId,
        sessionId: UUID(),
        revision: 1,
        data: data,
        lastSentAtEpochMilliseconds: 0
    ))

    #expect(queue.retryIfDue(nowEpochMilliseconds: 1_000) == nil)
    #expect(queue.retryIfDue(nowEpochMilliseconds: 3_000) == data)
    #expect(queue.retryIfDue(nowEpochMilliseconds: 6_000) == data)
    #expect(queue.retryIfDue(nowEpochMilliseconds: 9_000) == nil)
    #expect(queue.pending == nil)
}

@Test func manualResyncOnlyFlowsFromPhoneFollowerToWatchController() throws {
    #expect(LinkManualResyncPolicy.phoneCanRequest(role: .phoneFollower))
    #expect(!LinkManualResyncPolicy.phoneCanRequest(role: .phoneController))
    #expect(!LinkManualResyncPolicy.phoneCanRequest(role: nil))
    #expect(LinkManualResyncPolicy.watchCanRespond(role: .watchController))
    #expect(!LinkManualResyncPolicy.watchCanRespond(role: .watchFollower))

    let envelope = LinkEnvelope(
        sessionId: UUID(),
        kind: .resyncRequest,
        sender: .phone,
        senderSequence: 2,
        sessionRevision: 7,
        sentAtEpochMilliseconds: 1_000,
        payload: EmptyLinkPayload()
    )
    let decoded = try JSONDecoder().decode(
        LinkEnvelope<EmptyLinkPayload>.self,
        from: JSONEncoder().encode(envelope)
    )
    #expect(decoded.kind == .resyncRequest)
    #expect(decoded.sender == .phone)
    #expect(decoded.sessionRevision == 7)
}

@Test func linkControlRetryQueueAcknowledgeClears() {
    var queue = LinkControlRetryQueue()
    let messageId = UUID()
    queue.enqueue(.init(
        messageId: messageId,
        sessionId: UUID(),
        revision: 2,
        data: Data([9]),
        lastSentAtEpochMilliseconds: 0
    ))
    let cleared = queue.acknowledge(messageId: messageId)
    #expect(cleared)
    #expect(queue.pending == nil)
    #expect(queue.retryIfDue(nowEpochMilliseconds: 10_000) == nil)
}

@Test func durableOutboxRetainsMultipleMatchesAndAcceptsOutOfOrderAcks() throws {
    let sessionId = UUID()
    let firstHandle = LinkedMatchHandle(sessionId: sessionId)
    let secondHandle = firstHandle.nextMatch()
    let firstMessageId = UUID()
    let secondMessageId = UUID()
    var outbox = LinkDurableOutbox(items: [
        .init(
            messageId: firstMessageId,
            handle: firstHandle,
            data: Data([1]),
            lastSentAtEpochMilliseconds: 0
        ),
        .init(
            messageId: secondMessageId,
            handle: secondHandle,
            data: Data([2]),
            lastSentAtEpochMilliseconds: 0
        )
    ])

    let restored = try JSONDecoder().decode(
        LinkDurableOutbox.self,
        from: JSONEncoder().encode(outbox)
    )
    #expect(restored.items.count == 2)
    #expect(outbox.retryDue(nowEpochMilliseconds: 3_000) == [Data([1]), Data([2])])
    #expect(outbox.acknowledge(messageId: secondMessageId)?.handle == secondHandle)
    #expect(outbox.items.map(\.messageId) == [firstMessageId])
    #expect(outbox.acknowledge(messageId: firstMessageId)?.handle == firstHandle)
    #expect(outbox.isEmpty)
}

@Test func authorityTransferPayloadUsesFormalV1Fields() throws {
    let payload = LinkAuthorityTransferPayload(baseRevision: 4)
    let decoded = try JSONDecoder().decode(
        LinkAuthorityTransferPayload.self,
        from: JSONEncoder().encode(payload)
    )
    #expect(decoded.snapshot == nil)
    #expect(decoded.detailedActions.isEmpty)
    #expect(decoded.baseRevision == 4)
}

@Test func takeoverAcknowledgementCarriesFinalSnapshot() throws {
    var state = TennisMatchState(leftName: "A", rightName: "B")
    state.leftPoints = 2
    state.rightPoints = 1
    let messageId = UUID()
    let payload = LinkAcknowledgementPayload(
        acknowledgedMessageId: messageId,
        acknowledgedRevision: 9,
        authoritativeSnapshot: .tennis(state)
    )
    let decoded = try JSONDecoder().decode(
        LinkAcknowledgementPayload.self,
        from: JSONEncoder().encode(payload)
    )
    #expect(decoded.authoritativeSnapshot?.tennisState?.leftPoints == 2)
    #expect(decoded.detailedActions.isEmpty)
}

@Test func revisionGateClassifiesRetriesWithoutAdvancingState() {
    let sessionId = UUID()
    let otherSessionId = UUID()
    var gate = LinkRevisionGate()

    let began = gate.beginSession(sessionId, initialRevision: 0)
    let newer = gate.classify(sessionId: sessionId, revision: 1)
    #expect(began)
    #expect(newer == .newer)
    #expect(gate.latestRevision == 1)
    let duplicate = gate.classify(sessionId: sessionId, revision: 1)
    let older = gate.classify(sessionId: sessionId, revision: 0)
    #expect(duplicate == .duplicateOrOlder)
    #expect(older == .duplicateOrOlder)
    #expect(gate.latestRevision == 1)
    let wrongSession = gate.classify(sessionId: otherSessionId, revision: 2)
    #expect(wrongSession == .wrongSession)
    #expect(gate.latestRevision == 1)
}

@Test func linkedMatchFinishedPayloadRoundTripPreservesTimeline() throws {
    let snapshot = LinkedScoreboardSnapshot.rally(
        RallyMatchEngine.initial(leftName: "红方", rightName: "蓝方", rules: .badminton(maxSets: 3))
    )
    let payload = LinkMatchFinishedPayload(
        snapshot: snapshot,
        recordId: "w_test_1",
        winnerSide: .left,
        manualEnd: false,
        startTimeEpochMilliseconds: 1_700_000_000_000,
        endTimeEpochMilliseconds: 1_700_000_120_000,
        durationSeconds: 120,
        totalScoreChanges: 18
    )
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(LinkMatchFinishedPayload.self, from: data)
    #expect(decoded.recordId == "w_test_1")
    #expect(decoded.startTimeEpochMilliseconds == 1_700_000_000_000)
    #expect(decoded.endTimeEpochMilliseconds == 1_700_000_120_000)
    #expect(decoded.durationSeconds == 120)
    #expect(decoded.totalScoreChanges == 18)
    #expect(decoded.winnerSide == .left)
}

@Test func linkedScoreboardSnapshotRoundTripTennisAndArchery() throws {
    let tennis = TennisMatchState(leftName: "A", rightName: "B")
    let archeryMatch = ArcheryMatchState(
        leftName: "L",
        rightName: "R",
        leftArrowSum: 18,
        rightArrowSum: 17,
        leftSetPoints: 5,
        rightSetPoints: 5,
        currentSet: 6,
        currentShooterIsLeft: true,
        openingShooterIsLeft: false,
        arrowsLeftThisSet: 1,
        arrowsRightThisSet: 1,
        arrowsPerSet: 1,
        pendingSetNumber: 6,
        pendingLeftSetPoints: 5,
        pendingRightSetPoints: 5,
        closestToCenterPending: true
    )
    let archery = LinkedArcheryState(match: archeryMatch)
    let encodedTennis = try JSONEncoder().encode(LinkedScoreboardSnapshot.tennis(tennis))
    let encodedArchery = try JSONEncoder().encode(LinkedScoreboardSnapshot.archery(archery))
    let decodedTennis = try JSONDecoder().decode(LinkedScoreboardSnapshot.self, from: encodedTennis)
    let decodedArchery = try JSONDecoder().decode(LinkedScoreboardSnapshot.self, from: encodedArchery)
    #expect(decodedTennis.tennisState?.leftName == "A")
    #expect(decodedArchery.archeryState?.rightSetPoints == 5)
    #expect(decodedArchery.archeryState?.arrowsLeftThisSet == 1)
    #expect(decodedArchery.archeryState?.arrowsPerSet == 1)
    #expect(decodedArchery.archeryState?.openingShooterIsLeft == false)
    #expect(decodedArchery.archeryState?.pendingSetNumber == 6)
    #expect(decodedArchery.archeryState?.closestToCenterPending == true)
}

@Test func formalV1ArcheryStateRequiresCompleteState() throws {
    let json = """
    {
        "leftName":"L","rightName":"R","leftSetPoints":2,"rightSetPoints":0,
        "leftArrowSum":27,"rightArrowSum":25,"currentShooterIsLeft":false,
        "setNumber":2,"finished":false,"sidesSwapped":false
    }
    """
    let data = Data(json.utf8)
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(LinkedArcheryState.self, from: data)
    }
}

@Test func linkSessionStateMachineRejectsStaleEpochAndWrongMatch() {
    let handle = LinkedMatchHandle(sessionId: UUID())
    var machine = LinkSessionStateMachine(
        handle: handle,
        role: .phoneController,
        authorityEpoch: 3,
        revision: 7
    )

    #expect(
        machine.accept(handle: handle, authorityEpoch: 2, revision: 8)
            == .staleAuthority
    )
    let conflictingHandle = LinkedMatchHandle(
        sessionId: handle.sessionId,
        matchId: UUID(),
        matchGeneration: handle.matchGeneration
    )
    #expect(
        machine.accept(handle: conflictingHandle, authorityEpoch: 3, revision: 8)
            == .wrongMatch
    )
    let nextHandle = handle.nextMatch()
    #expect(
        machine.accept(handle: nextHandle, authorityEpoch: 3, revision: 1)
            == .current
    )
    #expect(machine.handle == nextHandle)
    #expect(machine.revision == 1)
}

@Test func linkSessionStateMachineOwnsSetupTransferFinishAckAndEndLifecycle() {
    let handle = LinkedMatchHandle(sessionId: UUID())
    let setupCorrelation = UUID()
    var machine = LinkSessionStateMachine(
        handle: handle,
        role: .phoneFollower,
        lifecycle: .starting
    )

    let didBeginSetup = machine.beginSetup(correlationId: setupCorrelation)
    #expect(didBeginSetup)
    let didResolveWrongSetup = machine.resolveSetup(
        correlationId: UUID(),
        acceptedRole: .phoneFollower
    )
    #expect(!didResolveWrongSetup)
    let didResolveSetup = machine.resolveSetup(
        correlationId: setupCorrelation,
        acceptedRole: .phoneFollower
    )
    #expect(didResolveSetup)
    #expect(machine.lifecycle == .active)

    let takeoverCorrelation = UUID()
    let didBeginTransfer = machine.beginAuthorityTransfer(
        correlationId: takeoverCorrelation,
        targetRole: .phoneController,
        kind: .phoneTakeover
    )
    #expect(didBeginTransfer)
    let didPrepareWrongTransfer = machine.prepareAuthorityTransfer(
        correlationId: UUID(),
        epoch: 1
    )
    #expect(!didPrepareWrongTransfer)
    let didPrepareTransfer = machine.prepareAuthorityTransfer(
        correlationId: takeoverCorrelation,
        epoch: 1
    )
    #expect(didPrepareTransfer)
    let didCommitWrongTransfer = machine.commitAuthorityTransfer(correlationId: UUID())
    #expect(!didCommitWrongTransfer)
    let didCommitTransfer = machine.commitAuthorityTransfer(
        correlationId: takeoverCorrelation
    )
    #expect(didCommitTransfer)
    #expect(machine.role == .phoneController)
    #expect(machine.authorityEpoch == 1)

    let terminalMessageId = UUID()
    machine.registerPendingAcknowledgement(terminalMessageId)
    #expect(machine.pendingAcknowledgementIds == Set([terminalMessageId]))
    let didFinish = machine.markFinished(matchId: handle.matchId)
    #expect(didFinish)
    #expect(machine.lifecycle == .matchFinished)
    let didAcknowledge = machine.acknowledge(messageId: terminalMessageId)
    #expect(didAcknowledge)
    #expect(machine.pendingAcknowledgementIds.isEmpty)

    let nextHandle = machine.beginNextMatch()
    #expect(nextHandle.matchGeneration == 2)
    #expect(nextHandle.matchId != handle.matchId)
    #expect(machine.lifecycle == .active)
    #expect(machine.revision == 0)

    machine.endSession()
    #expect(machine.lifecycle == .ended)
    #expect(
        machine.accept(
            handle: nextHandle,
            authorityEpoch: machine.authorityEpoch,
            revision: 1
        ) == .endedSession
    )
}

@Test func linkSessionStateMachineRejectsStaleAndMismatchedTransferCorrelations() {
    let handle = LinkedMatchHandle(sessionId: UUID())
    let correlation = UUID()
    var machine = LinkSessionStateMachine(
        handle: handle,
        role: .watchController,
        authorityEpoch: 4,
        revision: 9
    )

    let didBeginTransfer = machine.beginAuthorityTransfer(
        correlationId: correlation,
        targetRole: .watchFollower,
        kind: .phoneTakeover
    )
    #expect(didBeginTransfer)
    let didBeginOverlappingTransfer = machine.beginAuthorityTransfer(
        correlationId: UUID(),
        targetRole: .watchFollower,
        kind: .phoneTakeover
    )
    #expect(!didBeginOverlappingTransfer)
    let didPrepareStaleEpoch = machine.prepareAuthorityTransfer(
        correlationId: correlation,
        epoch: 4
    )
    #expect(!didPrepareStaleEpoch)
    let didRejectWrongTransfer = machine.rejectAuthorityTransfer(correlationId: UUID())
    #expect(!didRejectWrongTransfer)
    let didRejectTransfer = machine.rejectAuthorityTransfer(correlationId: correlation)
    #expect(didRejectTransfer)
    #expect(machine.pendingAuthorityTransfer == nil)

    let rollbackCorrelation = UUID()
    let didBeginRollbackTransfer = machine.beginAuthorityTransfer(
        correlationId: rollbackCorrelation,
        targetRole: .watchFollower,
        kind: .phoneTakeover
    )
    #expect(didBeginRollbackTransfer)
    let didPrepareRollbackTransfer = machine.prepareAuthorityTransfer(
        correlationId: rollbackCorrelation,
        epoch: 5
    )
    #expect(didPrepareRollbackTransfer)
    #expect(machine.authorityEpoch == 5)
    let didRollbackPreparedTransfer = machine.rejectAuthorityTransfer(
        correlationId: rollbackCorrelation
    )
    #expect(didRollbackPreparedTransfer)
    #expect(machine.authorityEpoch == 4)
    #expect(machine.role == .watchController)

    #expect(machine.forceAuthority(to: .watchFollower) == 5)
    #expect(machine.role == .watchFollower)
    #expect(machine.authorityEpoch == 5)
}
