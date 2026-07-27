import Foundation
import LinkCore
import ScoreCore
import Testing

@Test func linkPendingAckQueueRetriesThenClears() {
    var queue = LinkPendingAckQueue()
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

@Test func linkPendingAckQueueAcknowledgeClears() {
    var queue = LinkPendingAckQueue()
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

@Test func terminalAckQueueRetainsStableEnvelopeAfterRetryBudget() {
    var queue = LinkPendingAckQueue()
    let messageId = UUID()
    let data = Data([4, 5, 6])
    queue.enqueue(.init(
        messageId: messageId,
        sessionId: UUID(),
        revision: 3,
        data: data,
        lastSentAtEpochMilliseconds: 0
    ))

    #expect(queue.retryIfDue(nowEpochMilliseconds: 3_000, retainAfterExhaustion: true) == data)
    #expect(queue.retryIfDue(nowEpochMilliseconds: 6_000, retainAfterExhaustion: true) == data)
    #expect(queue.retryIfDue(nowEpochMilliseconds: 9_000, retainAfterExhaustion: true) == data)
    #expect(queue.pending?.messageId == messageId)
}

@Test func emptyAuthorityTransferPayloadRemainsProtocolV1Compatible() throws {
    let decoded = try JSONDecoder().decode(
        LinkAuthorityTransferPayload.self,
        from: Data("{}".utf8)
    )
    #expect(decoded.snapshot == nil)
    #expect(decoded.detailedActions == nil)
    #expect(decoded.baseRevision == nil)
}

@Test func takeoverAcknowledgementCarriesFinalSnapshotAndDecodesLegacyPayload() throws {
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

    let legacy = Data(
        "{\"acknowledgedMessageId\":\"\(messageId.uuidString)\",\"acknowledgedRevision\":8}".utf8
    )
    let legacyDecoded = try JSONDecoder().decode(LinkAcknowledgementPayload.self, from: legacy)
    #expect(legacyDecoded.authoritativeSnapshot == nil)
    #expect(legacyDecoded.detailedActions == nil)
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

@Test func legacyLinkedArcheryStateWithoutExtendedFieldsStillDecodes() throws {
    let json = """
    {
        "leftName":"L","rightName":"R","leftSetPoints":2,"rightSetPoints":0,
        "leftArrowSum":27,"rightArrowSum":25,"currentShooterIsLeft":false,
        "setNumber":2,"finished":false,"sidesSwapped":false
    }
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(LinkedArcheryState.self, from: data)
    #expect(decoded.leftSetPoints == 2)
    #expect(decoded.arrowsLeftThisSet == nil)
    #expect(decoded.openingShooterIsLeft == nil)
    #expect(decoded.closestToCenterPending == nil)
}
