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
    let archery = LinkedArcheryState(leftName: "L", rightName: "R", leftSetPoints: 2, rightSetPoints: 1)
    let encodedTennis = try JSONEncoder().encode(LinkedScoreboardSnapshot.tennis(tennis))
    let encodedArchery = try JSONEncoder().encode(LinkedScoreboardSnapshot.archery(archery))
    let decodedTennis = try JSONDecoder().decode(LinkedScoreboardSnapshot.self, from: encodedTennis)
    let decodedArchery = try JSONDecoder().decode(LinkedScoreboardSnapshot.self, from: encodedArchery)
    #expect(decodedTennis.tennisState?.leftName == "A")
    #expect(decodedArchery.archeryState?.rightSetPoints == 1)
}
