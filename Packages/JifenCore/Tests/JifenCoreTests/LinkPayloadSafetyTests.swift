import Foundation
import LinkCore
import RecordCore
import ScoreCore
import Testing

/// 64KB 限额守护：WCSession 对超限 payload 直接抛原生异常（而非 Swift error），
/// 发送端必须在编码阶段裁剪/分块（docs/audit/2026-11-24/watch-full-check.md P1-3）。
struct LinkPayloadSafetyTests {

    private func makeAction(id: UUID, padding: Int) -> DetailedScoreAction {
        DetailedScoreAction(
            id: id,
            type: .scoreChanged,
            epochMilliseconds: 1,
            team: .team1,
            scores: [1, 0],
            setScores: [],
            scoreChange: 1,
            operationCode: "point",
            summary: String(repeating: "x", count: padding)
        )
    }

    @Test func envelopeEncodingPassesThroughWhenWithinLimit() throws {
        let actions = (0..<3).map { _ in makeAction(id: UUID(), padding: 10) }
        let envelope = LinkEnvelope(
            sessionId: UUID(),
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: 1,
            sentAtEpochMilliseconds: 0,
            payload: LinkedScoreboardSetup(
                gameType: .pingpong,
                initialSnapshot: nil,
                detailedActions: actions
            )
        )
        let data = LinkEnvelopeEncoding.data(
            envelope,
            actionsKeyPath: \LinkedScoreboardSetup.detailedActions,
            byteLimit: 100_000
        )
        let decoded = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: data
        )
        #expect(decoded.payload.detailedActions.count == 3)
    }

    @Test func envelopeEncodingTrimsOldestActionsUntilWithinLimit() throws {
        let actions = (0..<60).map { _ in makeAction(id: UUID(), padding: 400) }
        let envelope = LinkEnvelope(
            sessionId: UUID(),
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: 1,
            sentAtEpochMilliseconds: 0,
            payload: LinkedScoreboardSetup(
                gameType: .pingpong,
                initialSnapshot: nil,
                detailedActions: actions
            )
        )
        let limit = 6_000
        let data = LinkEnvelopeEncoding.data(
            envelope,
            actionsKeyPath: \LinkedScoreboardSetup.detailedActions,
            byteLimit: limit
        )
        #expect(data.count <= limit)

        let decoded = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: data
        )
        let remaining = decoded.payload.detailedActions
        #expect(!remaining.isEmpty)
        // 裁剪的是最旧尾部：保留的动作必须是原数组末尾的连续后缀。
        #expect(remaining.map { $0.id } == actions.suffix(remaining.count).map { $0.id })
    }

    @Test func envelopeEncodingDropsAllActionsWhenEvenOneDoesNotFit() throws {
        let actions = [makeAction(id: UUID(), padding: 8_000)]
        let envelope = LinkEnvelope(
            sessionId: UUID(),
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: 1,
            sentAtEpochMilliseconds: 0,
            payload: LinkedScoreboardSetup(
                gameType: .pingpong,
                initialSnapshot: nil,
                detailedActions: actions
            )
        )
        let data = LinkEnvelopeEncoding.data(
            envelope,
            actionsKeyPath: \LinkedScoreboardSetup.detailedActions,
            byteLimit: 2_000
        )
        let decoded = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: data
        )
        #expect(decoded.payload.detailedActions.isEmpty)
    }

    @Test func pendingRecordChunkingRespectsBatchBytes() {
        let maxBytes = 100
        let datas = [
            Data(repeating: 1, count: 60),
            Data(repeating: 2, count: 30),
            Data(repeating: 3, count: 50),
            Data(repeating: 4, count: 10)
        ]
        let batches = LinkPendingRecordChunking.chunk(datas, maxBytes: maxBytes)
        for batch in batches {
            #expect(batch.reduce(0) { $0 + $1.count } <= maxBytes)
        }
        #expect(batches.flatMap { $0 } == datas)
        // 单条超限自成一批，调用方（transport）决定是否可投递。
        let oversized = Data(repeating: 9, count: 200)
        let single = LinkPendingRecordChunking.chunk([oversized], maxBytes: maxBytes)
        #expect(single == [[oversized]])
        #expect(LinkPendingRecordChunking.chunk([], maxBytes: maxBytes).isEmpty)
    }

    @Test func applicationContextEncodingStripsDetailedActionsWhileKeepingSnapshot() throws {
        let actions = (0..<20).map { _ in makeAction(id: UUID(), padding: 200) }
        let football = LinkedFootballState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 2,
            rightScore: 1,
            kickedOff: true,
            finished: false
        )
        let sessionId = UUID()
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: 7,
            sessionRevision: 9,
            sentAtEpochMilliseconds: 1_234,
            payload: LinkedScoreboardSetup(
                gameType: .football,
                maxSets: nil,
                initialSnapshot: .football(football),
                detailedActions: actions,
                participantNames: ["主队", "客队"]
            )
        )

        let contextData = LinkEnvelopeEncoding.applicationContextData(envelope)
        let realtimeData = LinkEnvelopeEncoding.encodedData(envelope)
        #expect(contextData.count < realtimeData.count)

        let decodedContext = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: contextData
        )
        #expect(decodedContext.sessionId == sessionId)
        #expect(decodedContext.sessionRevision == 9)
        #expect(decodedContext.payload.gameType == .football)
        #expect(decodedContext.payload.initialSnapshot == .football(football))
        #expect(decodedContext.payload.participantNames == ["主队", "客队"])
        #expect(decodedContext.payload.detailedActions.isEmpty)

        // 泛型分派入口同样剥离动作历史，且实时通道仍保留完整动作。
        func encodeGeneric<T: Codable & Sendable>(_ value: LinkEnvelope<T>) -> Data {
            LinkEnvelopeEncoding.applicationContextData(value)
        }
        let genericDecoded = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: encodeGeneric(envelope)
        )
        #expect(genericDecoded.payload.detailedActions.isEmpty)

        let decodedRealtime = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: realtimeData
        )
        #expect(decodedRealtime.payload.detailedActions.count == 20)
    }
}
