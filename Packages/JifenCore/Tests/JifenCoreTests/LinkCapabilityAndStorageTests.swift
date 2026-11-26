import Foundation
import RecordCore
import ScoreCore
import Testing
@testable import LinkCore

/// M1 验收：开放式能力协商、FileLinkDataStore、常用名预算裁剪、
/// 压缩帧探测、增量动作台账与终态通道路由。
struct LinkCapabilityNegotiationTests {
    private func makeEnvelopeJSON(capabilities: [String]) throws -> Data {
        let capabilityList = capabilities.joined(separator: ",")
        let json = """
        {"protocolVersion":1,
         "capabilities":[\(capabilityList)],
         "messageId":"\(UUID().uuidString)",
         "sessionId":"\(UUID().uuidString)",
         "matchId":"\(UUID().uuidString)",
         "matchGeneration":1,
         "kind":"stateSnapshot",
         "sender":"phone",
         "senderSequence":1,
         "sessionRevision":1,
         "sentAtEpochMilliseconds":1700000000000,
         "payload":{"gameType":"pingpong","detailedActions":[],"participantNames":[],"capabilities":[\(capabilityList)]}}
        """.data(using: .utf8)!
        return json
    }

    @Test func unknownCapabilityValuesDecodeWithoutFailure() throws {
        let data = try makeEnvelopeJSON(capabilities: ["\"independentMatches\"", "\"correlatedRequests\"", "\"durableTerminalQueue\"", "\"futureCapability\""])
        let envelope = try JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data)
        #expect(envelope.capabilities.contains(LinkCapability(rawValue: "futureCapability")))
    }

    @Test func negotiationPassesWhenRequiredSubsetIsPresent() {
        let peer: Set<LinkCapability> = [
            .independentMatches, .correlatedRequests, .durableTerminalQueue,
            LinkCapability(rawValue: "unknownFuture")
        ]
        let negotiated = LinkProtocol.negotiate(local: LinkProtocol.capabilities, peer: peer)
        #expect(negotiated != nil)
        #expect(negotiated?.contains(.latestSnapshotContext) == false)
    }

    @Test func negotiationFailsWhenRequiredCapabilityIsMissing() {
        let peer: Set<LinkCapability> = [.independentMatches, .correlatedRequests]
        #expect(LinkProtocol.negotiate(local: LinkProtocol.capabilities, peer: peer) == nil)
    }

    @Test func capabilityJSONStaysAPlainString() throws {
        let data = try JSONEncoder().encode([LinkCapability.compressedFinish])
        #expect(String(data: data, encoding: .utf8) == "[\"compressedFinish\"]")
    }
}

struct FileLinkDataStoreTests {
    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLinkDataStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripsWritesAndDeletesAtomically() throws {
        let store = FileLinkDataStore(directoryURL: makeTemporaryDirectory())
        let key = "phone_link_context/special key with spaces"
        try store.setOrThrow(Data([1, 2, 3]), forKey: key)
        #expect(store.data(forKey: key) == Data([1, 2, 3]))
        let removed = try store.removeOrThrow(forKey: key)
        #expect(removed)
        #expect(store.data(forKey: key) == nil)
    }

    @Test func concurrentWritesKeepEveryValueReadable() throws {
        let store = FileLinkDataStore(directoryURL: makeTemporaryDirectory())
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "writers", attributes: .concurrent)
        for index in 0..<32 {
            group.enter()
            queue.async {
                defer { group.leave() }
                try? store.setOrThrow(Data([UInt8(index % 251)]), forKey: "key-\(index)")
            }
        }
        group.wait()
        for index in 0..<32 {
            #expect(store.data(forKey: "key-\(index)") == Data([UInt8(index % 251)]))
        }
    }
}

struct CommonNamesBudgetTests {
    @Test func budgetConstrainedDataStaysUnder24KB() {
        let longNames = (0..<2000).map { "选手名字很长很长很长很长-\($0)" }
        let snapshot = CommonNamesSyncSnapshot(teams: longNames, players: longNames)
        let constrained = snapshot.budgetConstrainedData()
        let data = try! JSONEncoder().encode(constrained)
        #expect(data.count <= 24_000)
        #expect(!constrained.players.isEmpty) // 最新条目保留
    }
}

struct LinkFinishedRoutingTests {
    private func makeFinishedEnvelope(actionCount: Int) -> LinkEnvelope<LinkMatchFinishedPayload> {
        let actions = (0..<actionCount).map { index in
            DetailedScoreAction(
                type: .scoreChanged, epochMilliseconds: Int64(1_700_000_000_000 + index * 10),
                team: .team1, scores: [index, 0], scoreChange: 1,
                operationCode: "score_\(index)"
            )
        }
        return LinkEnvelope(
            sessionId: UUID(), kind: .matchFinished, sender: .watch, senderSequence: 1,
            sessionRevision: 1, sentAtEpochMilliseconds: 1_700_000_000_000,
            payload: LinkMatchFinishedPayload(
                snapshot: .rally(RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())),
                recordId: "r1", detailedActions: actions
            )
        )
    }

    @Test func frameBuilderNeverTrimsActions() throws {
        let envelope = makeFinishedEnvelope(actionCount: 4_000)
        let frame = LinkFinishedFrameBuilder.buildFrame(envelope, peerSupportsCompressedFinish: false)
        let decoded = LinkFinishedEncoding.decode(frame)
        #expect(decoded?.payload.detailedActions.count == 4_000) // 全量动作
    }

    @Test func compressedFrameDetectedAndDecoded() throws {
        let envelope = makeFinishedEnvelope(actionCount: 4_000)
        let frame = LinkFinishedFrameBuilder.buildFrame(envelope, peerSupportsCompressedFinish: true)
        #expect(LinkFinishedEncoding.isCompressedFrame(frame))
        let decoded = LinkFinishedEncoding.decode(frame)
        #expect(decoded?.payload.detailedActions.count == 4_000)
    }

    @Test func channelSelectionFollowsByteBudgetAndCapability() {
        #expect(LinkFinishedRouting.chooseDurableChannel(frameByteCount: 31_999, peerSupportsFileTransfer: false) == .userInfo)
        #expect(LinkFinishedRouting.chooseDurableChannel(frameByteCount: 32_001, peerSupportsFileTransfer: true) == .file)
        #expect(LinkFinishedRouting.chooseDurableChannel(frameByteCount: 70_000, peerSupportsFileTransfer: false) == .hold)
    }

    @Test func deltaTrackerTracksAcknowledgementsAndResets() {
        var tracker = LinkDeltaActionTracker()
        let actions = (0..<5).map { index in
            DetailedScoreAction(
                type: .scoreChanged, epochMilliseconds: Int64(index),
                team: .team1, scores: [index, 0], scoreChange: 1, operationCode: "op_\(index)"
            )
        }
        tracker.noteSent(messageId: UUID(), actions: actions)
        #expect(tracker.pendingDeltaActions(of: actions).count == 5)
        tracker.noteAcknowledged(messageId: tracker.inFlightMessageActions.keys.first!)
        #expect(tracker.pendingDeltaActions(of: actions).isEmpty)
        tracker.reset()
        #expect(tracker.pendingDeltaActions(of: actions).count == 5)
    }

    @Test func deltaSnapshotSetupMarksDeltaOnlyWhenNegotiated() {
        var tracker = LinkDeltaActionTracker()
        let snapshot = LinkedScoreboardSnapshot.rally(RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong()))
        let full = tracker.snapshotSetup(
            snapshot: snapshot, gameType: .pingpong, maxSets: 3,
            participantNames: [], fullActions: [], deltaEnabled: false
        )
        #expect(full.setup.isDeltaActions == nil)
        let delta = tracker.snapshotSetup(
            snapshot: snapshot, gameType: .pingpong, maxSets: 3,
            participantNames: [], fullActions: [], deltaEnabled: true
        )
        #expect(delta.setup.isDeltaActions == true)
    }
}

/// Codex R3 探针等价回归（probe-link-delta-wire-ack）：
/// 3000 条动作超出 60KB 预算 → 实际上线帧只含前缀；
/// 该帧回执**不得**清掉未上线动作；分批重发直到全部补齐。
struct DeltaWireAckBudgetTests {
    @Test func wireAckOnlyConfirmsActionsActuallyOnTheWire() throws {
        let actions = (0..<3000).map { score in
            DetailedScoreAction(type: .scoreChanged, epochMilliseconds: Int64(score), team: .team1, scores: [score, 0])
        }
        let frame = LinkEnvelope(
            sessionId: UUID(), kind: .stateSnapshot, sender: .phone,
            senderSequence: 1, sessionRevision: 1, sentAtEpochMilliseconds: 1,
            payload: LinkedScoreboardSetup(gameType: .badminton, detailedActions: actions, isDeltaActions: true)
        )
        let (data, sentActions) = LinkEnvelopeEncoding.dataWithSentActions(frame)
        let sentEnvelope = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self, from: data
        )
        #expect(sentActions == sentEnvelope.payload.detailedActions, "台账列表与最终帧解码一致")
        #expect(sentActions.count < actions.count, "3000 条必然超预算，应被裁剪")

        var tracker = LinkDeltaActionTracker()
        tracker.noteSent(messageId: frame.messageId, actions: sentActions)
        tracker.noteAcknowledged(messageId: frame.messageId) // 线上帧的真实回执
        let stillPending = tracker.pendingDeltaActions(of: actions)
        #expect(stillPending.count == actions.count - sentActions.count, "裁掉的动作仍在欠账")
        #expect(stillPending.map(\.id) == Array(actions.prefix(actions.count - sentActions.count)).map(\.id), "欠账恰为被裁剪的未上线前缀（编码器裁最旧头部）")
    }

    @Test func catchUpLoopCompletesInBatchesUntilZeroPending() {
        let actions = (0..<3000).map { score in
            DetailedScoreAction(type: .scoreChanged, epochMilliseconds: Int64(score), team: .team1, scores: [score, 0])
        }
        var tracker = LinkDeltaActionTracker()
        var totalBatches = 0
        var allWireIDs: Set<UUID> = []
        // 断连重连后的补发循环：每轮取欠账构造增量帧 → 上线 → 回执。
        while !tracker.pendingDeltaActions(of: actions).isEmpty {
            let pending = tracker.pendingDeltaActions(of: actions)
            let frame = LinkEnvelope(
                sessionId: UUID(), kind: .stateSnapshot, sender: .phone,
                senderSequence: UInt64(totalBatches + 1), sessionRevision: 1,
                sentAtEpochMilliseconds: 1,
                payload: LinkedScoreboardSetup(gameType: .badminton, detailedActions: pending, isDeltaActions: true)
            )
            let (data, sentActions) = LinkEnvelopeEncoding.dataWithSentActions(frame)
            #expect(!data.isEmpty)
            #expect(sentActions.count > 0, "每批必须有进展，禁止空转")
            tracker.noteSent(messageId: frame.messageId, actions: sentActions)
            tracker.noteAcknowledged(messageId: frame.messageId)
            allWireIDs.formUnion(sentActions.map(\.id))
            totalBatches += 1
            #expect(totalBatches <= 40, "分批收敛，不无限重发")
        }
        #expect(allWireIDs == Set(actions.map(\.id)), "最终去重完整：3000 条全部上线")
    }

    @Test func duplicateAndOutOfOrderAcksDoNotClearPendingDebt() throws {
        let actions = (0..<600).map { score in
            DetailedScoreAction(type: .scoreChanged, epochMilliseconds: Int64(score), team: .team1, scores: [score, 0])
        }
        let frame = LinkEnvelope(
            sessionId: UUID(), kind: .stateSnapshot, sender: .phone,
            senderSequence: 1, sessionRevision: 1, sentAtEpochMilliseconds: 1,
            payload: LinkedScoreboardSetup(gameType: .badminton, detailedActions: actions, isDeltaActions: true)
        )
        let (data, sentActions) = LinkEnvelopeEncoding.dataWithSentActions(frame)
        var tracker = LinkDeltaActionTracker()
        tracker.noteSent(messageId: frame.messageId, actions: sentActions)
        // 轻量 checkpoint（R2 修复）：独立 messageId 的回执为 no-op。
        let checkpoint = LinkEnvelope(
            messageId: UUID(), sessionId: frame.sessionId, kind: .stateSnapshot, sender: .phone,
            senderSequence: 2, sessionRevision: 1, sentAtEpochMilliseconds: 1,
            payload: LinkedScoreboardSetup(gameType: .badminton, detailedActions: [], isDeltaActions: true)
        )
        tracker.noteSent(messageId: checkpoint.messageId, actions: [])
        tracker.noteAcknowledged(messageId: checkpoint.messageId) // 重复/无效回执
        #expect(tracker.pendingDeltaActions(of: actions).count == actions.count, "无效应答不清欠账")
        // 真实回执后：上线前缀确认，其余保留。
        tracker.noteAcknowledged(messageId: frame.messageId)
        #expect(tracker.pendingDeltaActions(of: actions).count == actions.count - sentActions.count)
    }

/// Codex 探针等价回归（probe-link-store-write）：协议类型调用必须到达具体
/// 存储的真实实现，吞错扩展不复存在。
struct LinkDataStoreExistentialProbeTests {
    @Test func existentialCallSurfacesConcreteWriteFailure() throws {
        let badDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-not-a-dir-\(UUID().uuidString)")
        try Data([1]).write(to: badDirectory) // 普通文件占据目录位
        defer { try? FileManager.default.removeItem(at: badDirectory) }
        let concrete = FileLinkDataStore(directoryURL: badDirectory)
        let store: any LinkDataStore = concrete

        #expect(throws: (any Error).self) {
            try concrete.setOrThrow(Data([1]), forKey: "concrete")
        }
        #expect(throws: (any Error).self) {
            try store.setOrThrow(Data([1]), forKey: "existential")
        }
        #expect(store.data(forKey: "existential") == nil)
    }
}

/// Codex 探针等价回归（probe-link-delta-context-ack）：applicationContext
/// 轻量帧用全新 messageId，其回执不清空实时帧的增量台账。
struct ApplicationContextCheckpointProbeTests {
    @Test func checkpointHasFreshMessageIdStrippedActionsAndKeepsRetries() throws {
        let action = DetailedScoreAction(
            type: .scoreChanged, epochMilliseconds: 1, team: .team1, scores: [1, 0]
        )
        let update = LinkEnvelope(
            sessionId: UUID(), kind: .stateSnapshot, sender: .phone,
            senderSequence: 1, sessionRevision: 1, sentAtEpochMilliseconds: 1,
            payload: LinkedScoreboardSetup(gameType: .badminton, detailedActions: [action], isDeltaActions: true)
        )
        let lightweight = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: LinkEnvelopeEncoding.applicationContextData(update)
        )
        #expect(lightweight.messageId != update.messageId)
        #expect(lightweight.payload.detailedActions.isEmpty)

        var tracker = LinkDeltaActionTracker()
        tracker.noteSent(messageId: update.messageId, actions: update.payload.detailedActions)
        tracker.noteAcknowledged(messageId: lightweight.messageId) // 轻量帧回执
        #expect(tracker.pendingDeltaActions(of: [action]).count == 1, "未送达的动作必须保留在重发清单")

        tracker.noteAcknowledged(messageId: update.messageId) // 实时帧真实回执
        #expect(tracker.pendingDeltaActions(of: [action]).isEmpty)
    }

    @Test func historyReplacementSendsFullSnapshotAndClearsLedger() {
        var tracker = LinkDeltaActionTracker()
        let kept = DetailedScoreAction(type: .scoreChanged, epochMilliseconds: 1, team: .team1, scores: [1, 0])
        let revoked = DetailedScoreAction(type: .scoreChanged, epochMilliseconds: 2, team: .team1, scores: [2, 0])
        let ackId = UUID()
        tracker.noteSent(messageId: ackId, actions: [kept, revoked])
        tracker.noteAcknowledged(messageId: ackId)

        // 撤销 revoked 后的当前历史只剩 kept：已确认动作缺席 → 替换语义。
        let snapshot = LinkedScoreboardSnapshot.rally(RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong()))
        let result = tracker.snapshotSetup(
            snapshot: snapshot, gameType: .pingpong, maxSets: 3,
            participantNames: [], fullActions: [kept], deltaEnabled: true
        )
        #expect(result.historyReplaced)
        #expect(result.setup.isDeltaActions == nil, "替换帧必须走非增量全量")
        #expect(result.setup.detailedActions.count == 1)
        #expect(tracker.acknowledgedActionIDs.isEmpty, "旧增量确认状态已清除")

        // 后续新动作恢复增量语义。
        let fresh = DetailedScoreAction(type: .scoreChanged, epochMilliseconds: 3, team: .team1, scores: [3, 0])
        let next = tracker.snapshotSetup(
            snapshot: snapshot, gameType: .pingpong, maxSets: 3,
            participantNames: [], fullActions: [kept, fresh], deltaEnabled: true
        )
        #expect(next.historyReplaced == false)
        #expect(next.setup.detailedActions.map(\.id) == [kept.id, fresh.id], "台账清零后全量重发（对端按 id 幂等合并）")
    }
}
}
