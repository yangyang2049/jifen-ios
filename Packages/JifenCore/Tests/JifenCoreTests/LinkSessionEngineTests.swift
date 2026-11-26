import Foundation
import LinkCore
import RecordCore
import ScoreCore
import Testing

/// Shared transport boundary: safe receive (compressed-finish magic before
/// envelope decoding), channel fallback and bounded retry, all exercised
/// without WatchConnectivity.
struct LinkSessionEngineTests {

    // MARK: - Receive

    @Test func terminalFramesAreProbedBeforeEnvelopeDecoding() throws {
        let actions = makeActions(count: 24, padding: 400)
        let finish = finishEnvelope(actions: actions)
        let compressed = LinkFinishedEncoding.encode(finish, compress: true)
        #expect(LinkFinishedEncoding.isCompressedFrame(compressed))

        let snapshotData = try JSONEncoder().encode(try snapshotEnvelope(actions: actions))
        // The compressed frame is not JSON, so LinkEnvelopeHead must never see it.
        do {
            _ = try JSONDecoder().decode(LinkEnvelopeHead.self, from: compressed)
            Issue.record("a compressed terminal frame must not decode as an envelope head")
        } catch {
            // Expected: only the magic-prefix probe can classify this frame.
        }

        let engine = makeEngine(localPeer: .phone)
        switch engine.route(compressed) {
        case .terminalFrame(let frame):
            #expect(frame == compressed)
        default:
            Issue.record("compressed finish frame must route as a terminal frame")
        }
        switch engine.route(snapshotData) {
        case .envelope(let head, let body):
            #expect(head.kind == .stateSnapshot)
            #expect(head.sender == .watch)
            #expect(body == snapshotData)
        default:
            Issue.record("regular envelope must route as .envelope")
        }
    }

    @Test func foreignOversizeAndUndecodableFramesNeverReachHandlers() throws {
        let engine = makeEngine(localPeer: .phone)
        switch engine.route(Data("not an envelope".utf8)) {
        case .undecodable: break
        default: Issue.record("garbage must route as .undecodable")
        }

        // A frame this peer claims to have sent itself is never accepted.
        let ownData = try JSONEncoder().encode(try snapshotEnvelope(sender: .phone))
        switch engine.route(ownData) {
        case .wrongSender(let head):
            #expect(head.sender == .phone)
        default:
            Issue.record("echo of the local peer must route as .wrongSender")
        }

        let bounded = makeEngine(localPeer: .phone, maximumFrameBytes: 128)
        switch bounded.route(Data(repeating: 0, count: 129)) {
        case .oversize(let count):
            #expect(count == 129)
        default:
            Issue.record("frame above the budget must route as .oversize")
        }
        // Size wins over the magic prefix: nothing is parsed above the budget.
        var oversizeTerminal = Data([0x4A, 0x46, 0x01])
        oversizeTerminal.append(Data(repeating: 0, count: 200))
        switch bounded.route(oversizeTerminal) {
        case .oversize: break
        default: Issue.record("oversize terminal frame must not be parsed")
        }
    }

    // MARK: - Send

    @Test func stateSnapshotPublishesStrippedCheckpointThenRealtime() async throws {
        let transport = RecordingTransport()
        let engine = makeEngine(localPeer: .watch, transport: transport)
        let actions = makeActions(count: 12, padding: 200)
        let envelope = try snapshotEnvelope(actions: actions)

        let outcome = await engine.send(envelope)

        #expect(outcome.steps == [.latestSnapshot, .realtime])
        #expect(outcome.isFullyDelivered)
        #expect(!outcome.isHeld)
        let contextData = try #require(transport.publishedSnapshots.first)
        let context = try JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: contextData)
        #expect(context.payload.detailedActions.isEmpty)
        #expect(context.payload.initialSnapshot == envelope.payload.initialSnapshot)
        // The checkpoint frame carries its own id, so its ACK cannot clear the
        // live frame's pending action ledger.
        #expect(context.messageId != envelope.messageId)
        let liveData = try #require(transport.sentRealtime.first)
        let live = try JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: liveData)
        #expect(live.payload.detailedActions.count == actions.count)
    }

    @Test func unreachablePeerStillReceivesTheLatestCheckpoint() async throws {
        let transport = RecordingTransport()
        transport.setReachable(false)
        let engine = makeEngine(localPeer: .watch, transport: transport)

        let outcome = await engine.send(try snapshotEnvelope(actions: makeActions(count: 2)))

        #expect(outcome.steps == [.latestSnapshot])
        #expect(transport.publishedSnapshots.count == 1)
        #expect(transport.sentRealtime.isEmpty)
    }

    @Test func replayableFramesPickBoundedDurableChannels() async throws {
        let transport = RecordingTransport()
        let engine = makeEngine(localPeer: .watch, transport: transport)
        let small = Data(repeating: 7, count: 1_000)
        let large = Data(repeating: 7, count: 33_000)

        // Reachable and within the live budget: live only, never duplicated.
        let liveOutcome = await engine.sendReplayableFrame(
            small, kind: .matchFinished, peerSupportsFileTransfer: false
        )
        #expect(liveOutcome.steps == [.realtime])
        #expect(transport.enqueuedDurable.isEmpty)

        // Unreachable: <= 32 KB rides transferUserInfo, the outbox keeps it.
        transport.setReachable(false)
        let queuedOutcome = await engine.sendReplayableFrame(
            small, kind: .matchFinished, peerSupportsFileTransfer: false
        )
        #expect(queuedOutcome.steps == [.durableUserInfo])
        #expect(transport.enqueuedDurable == [small])

        // 33 KB with no negotiated file channel: hold, never trimmed.
        let heldOutcome = await engine.sendReplayableFrame(
            large, kind: .matchFinished, peerSupportsFileTransfer: false
        )
        #expect(heldOutcome.steps == [.hold])
        #expect(heldOutcome.isHeld)

        // With a negotiated file channel and an injected sink it goes to file.
        let recorder = FileSinkRecorder()
        let fileEngine = makeEngine(localPeer: .watch, transport: transport) { data, kind in
            recorder.record(data, kind: kind)
        }
        let fileOutcome = await fileEngine.sendReplayableFrame(
            large, kind: .matchFinished, peerSupportsFileTransfer: true
        )
        #expect(fileOutcome.steps == [.durableFile])
        #expect(recorder.kinds == [.matchFinished])
        #expect(recorder.frames == [large])
    }

    @Test func terminalEnvelopesAreBuiltUntrimmedBeforeChannelChoice() async throws {
        let transport = RecordingTransport()
        let engine = makeEngine(localPeer: .watch, transport: transport)
        let actions = makeActions(count: 4, padding: 64)
        let finish = finishEnvelope(actions: actions)

        let outcome = await engine.send(finish, peerSupportsCompressedFinish: false)

        #expect(outcome.steps == [.realtime])
        let sent = try #require(transport.sentRealtime.first)
        let decoded = try #require(LinkFinishedEncoding.decode(sent))
        #expect(decoded.payload.detailedActions.count == actions.count)
    }

    @Test func unnegotiatedFileChannelHoldsInsteadOfFailing() async {
        let transport = RecordingTransport()
        transport.setReachable(false)
        let engine = makeEngine(localPeer: .phone, transport: transport)
        let large = Data(repeating: 3, count: 40_000)

        // The peer claims file support but this build injected no sink: the
        // frame is reported, never thrown, and the app keeps it in the outbox.
        let outcome = await engine.sendReplayableFrame(
            large, kind: .intentFrame, peerSupportsFileTransfer: true
        )
        #expect(outcome.steps == [.durableFile])
        #expect(outcome.failures.keys.contains(.durableFile))
        #expect(outcome.firstErrorDescription != nil)
    }

    @Test func channelFailuresAreReportedWithoutSuppressingOtherChannels() async throws {
        let transport = RecordingTransport()
        transport.fail(.realtime)
        let engine = makeEngine(localPeer: .watch, transport: transport)

        let outcome = await engine.send(try snapshotEnvelope(actions: makeActions(count: 2)))

        #expect(outcome.steps == [.latestSnapshot, .realtime])
        #expect(!outcome.isFullyDelivered)
        #expect(outcome.failures.keys.contains(.realtime))
        #expect(transport.publishedSnapshots.count == 1)
    }

    @Test func intentFramesGoLiveFirstThenFallBack() async {
        let transport = RecordingTransport()
        let engine = makeEngine(localPeer: .watch, transport: transport)
        let intent = Data(repeating: 4, count: 200)

        // Reachable and within the live budget: one live send, no duplicate.
        let live = await engine.sendReplayableFrame(intent, kind: .intentFrame, peerSupportsFileTransfer: true)
        #expect(live.steps == [.realtime])
        #expect(transport.sentRealtime == [intent])
        #expect(transport.enqueuedDurable.isEmpty)

        // Unreachable: the frame waits in the durable dictionary channel.
        transport.setReachable(false)
        let queued = await engine.sendReplayableFrame(intent, kind: .intentFrame, peerSupportsFileTransfer: true)
        #expect(queued.steps == [.durableUserInfo])
        #expect(transport.enqueuedDurable == [intent])

        // Live send fails: the fallback still delivers and the failure is kept.
        transport.setReachable(true)
        transport.fail(.realtime)
        let failed = await engine.sendReplayableFrame(intent, kind: .intentFrame, peerSupportsFileTransfer: true)
        #expect(failed.steps == [.realtime, .durableUserInfo])
        #expect(failed.failures.keys.contains(.realtime))
        #expect(transport.enqueuedDurable == [intent, intent])

        // Too large for the dictionary channel without a file channel: hold.
        let huge = Data(repeating: 5, count: 40_000)
        let held = await engine.sendReplayableFrame(huge, kind: .intentFrame, peerSupportsFileTransfer: false)
        #expect(held.isHeld)
    }

    // MARK: - Bounded retry

    @Test func interactiveRetryIsBoundedAndExpires() {
        let clock = TestClock(now: 1_000)
        let messageId = UUID()
        let frame = Data(repeating: 1, count: 64)
        var engine = makeEngine(localPeer: .watch, clock: clock)
        engine.pendingControl.enqueue(.init(
            messageId: messageId,
            sessionId: UUID(),
            revision: 3,
            data: frame,
            lastSentAtEpochMilliseconds: 1_000
        ))

        for _ in 0..<LinkControlRetryQueue.maxRetries {
            clock.advance(LinkControlRetryQueue.retryIntervalMilliseconds)
            let due = engine.retryDue()
            #expect(due == [.resendControl(frame)])
        }
        clock.advance(LinkControlRetryQueue.retryIntervalMilliseconds)
        let expired = engine.retryDue()
        #expect(expired == [.controlExpired(messageId: messageId)])
        #expect(engine.pendingControl.pending == nil)
        #expect(engine.nextRetryDeadlineEpochMilliseconds() == nil)
        #expect(engine.nextRetryDelayNanoseconds() == nil)
    }

    @Test func historyFramesAreRetainedUntilThePeerIsReachable() {
        let clock = TestClock(now: 0)
        let transport = RecordingTransport()
        transport.setReachable(false)
        let frame = Data(repeating: 2, count: 64)
        var engine = makeEngine(localPeer: .phone, transport: transport, clock: clock)
        engine.pendingControl.enqueue(.init(
            messageId: UUID(),
            sessionId: UUID(),
            revision: 1,
            data: frame,
            lastSentAtEpochMilliseconds: 0
        ))

        // Unreachable pending history: no retry, no deadline, nothing dropped.
        clock.advance(120_000)
        let skipped = engine.retryDue(retainsControlFrame: true)
        #expect(skipped.isEmpty)
        #expect(engine.nextRetryDeadlineEpochMilliseconds(retainsControlFrame: true) == nil)
        #expect(engine.nextRetryDeadlineEpochMilliseconds(retainsControlFrame: false) != nil)

        // Reconnect: the retained frame is resent immediately and survives
        // every attempt bound.
        transport.setReachable(true)
        let immediate = engine.retryDue(retainsControlFrame: true, sendImmediately: true)
        #expect(immediate == [.resendControl(frame)])
        for _ in 0..<(LinkControlRetryQueue.maxRetries + 2) {
            clock.advance(LinkControlRetryQueue.retryIntervalMilliseconds)
            let retained = engine.retryDue(retainsControlFrame: true)
            #expect(retained == [.resendControl(frame)])
        }
        #expect(engine.pendingControl.pending != nil)
        #expect(engine.nextRetryDelayNanoseconds(retainsControlFrame: true) != nil)
    }

    @Test func durableTerminalFramesNeverExpire() {
        let clock = TestClock(now: 0)
        let handle = LinkedMatchHandle(sessionId: UUID())
        let messageId = UUID()
        let frame = Data(repeating: 9, count: 33_000)
        var engine = makeEngine(localPeer: .watch, clock: clock)
        engine.terminalOutbox.enqueue(.init(
            messageId: messageId,
            handle: handle,
            data: frame,
            lastSentAtEpochMilliseconds: 0,
            peerSupportsFileTransfer: true
        ))

        clock.advance(7 * 24 * 60 * 60 * 1_000)
        let actions = engine.retryDue()
        #expect(actions.count == 1)
        guard case .resendTerminal(let item) = actions.first else {
            Issue.record("due durable item must be a terminal resend")
            return
        }
        #expect(item.messageId == messageId)
        #expect(item.data == frame)
        #expect(item.peerSupportsFileTransfer == true)
        // Retained: only an acknowledgement removes a durable item.
        #expect(engine.terminalOutbox.items.count == 1)
        // Pending session ends keep their one-second backoff.
        #expect(engine.nextRetryDelayNanoseconds(hasPendingSessionEnd: true) == 1_000_000_000)
    }

    // MARK: - Fixtures

    private func makeActions(count: Int, padding: Int = 32) -> [DetailedScoreAction] {
        (0..<count).map { _ in
            DetailedScoreAction(
                id: UUID(),
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
    }

    private func finishEnvelope(
        sender: LinkPeer = .watch,
        actions: [DetailedScoreAction]
    ) -> LinkEnvelope<LinkMatchFinishedPayload> {
        LinkEnvelope(
            sessionId: UUID(),
            kind: .matchFinished,
            sender: sender,
            senderSequence: 2,
            sessionRevision: 4,
            sentAtEpochMilliseconds: 1_700_002_600_000,
            payload: LinkMatchFinishedPayload(
                snapshot: .football(FootballMatchState(leftName: "A", rightName: "B", leftScore: 1, rightScore: 0)),
                recordId: "finish",
                totalScoreChanges: actions.count,
                detailedActions: actions
            )
        )
    }

    private func snapshotEnvelope(
        sender: LinkPeer = .watch,
        actions: [DetailedScoreAction] = []
    ) throws -> LinkEnvelope<LinkedScoreboardSetup> {
        LinkEnvelope(
            sessionId: UUID(),
            kind: .stateSnapshot,
            sender: sender,
            senderSequence: 1,
            sessionRevision: 3,
            sentAtEpochMilliseconds: 1_000,
            payload: LinkedScoreboardSetup(
                gameType: .pingpong,
                initialSnapshot: .football(
                    FootballMatchState(leftName: "A", rightName: "B", leftScore: 2, rightScore: 1)
                ),
                detailedActions: actions
            )
        )
    }

    private func makeEngine(
        localPeer: LinkPeer,
        transport: any LinkTransport = RecordingTransport(),
        clock: any LinkClock = TestClock(now: 0),
        maximumFrameBytes: Int = LinkSessionEngine.defaultMaximumFrameBytes,
        fileTransfer: (@Sendable (Data, WatchTransferFileKind) throws -> Void)? = nil
    ) -> LinkSessionEngine {
        LinkSessionEngine(
            localPeer: localPeer,
            transport: transport,
            clock: clock,
            maximumFrameBytes: maximumFrameBytes,
            fileTransfer: fileTransfer
        )
    }
}

private enum TestTransportError: Error { case injected }

private final class RecordingTransport: LinkTransport, @unchecked Sendable {
    private enum Slot { case realtime, latestSnapshot, durableUserInfo }

    private let lock = NSLock()
    private var realtimeFrames: [Data] = []
    private var snapshotFrames: [Data] = []
    private var durableFrames: [Data] = []
    private var failing: Set<LinkSendChannel> = []
    private var reachable = true

    var isReachable: Bool { locked { reachable } }
    var sentRealtime: [Data] { locked { realtimeFrames } }
    var publishedSnapshots: [Data] { locked { snapshotFrames } }
    var enqueuedDurable: [Data] { locked { durableFrames } }

    func setReachable(_ value: Bool) {
        locked { reachable = value }
    }

    func fail(_ channel: LinkSendChannel) {
        _ = locked { failing.insert(channel) }
    }

    func sendRealtime(_ data: Data) async throws {
        try record(data, slot: .realtime)
    }

    func publishLatestSnapshot(_ data: Data) throws {
        try record(data, slot: .latestSnapshot)
    }

    func enqueueDurable(_ data: Data) throws {
        try record(data, slot: .durableUserInfo)
    }

    private func record(_ data: Data, slot: Slot) throws {
        try locked {
            switch slot {
            case .realtime:
                guard !failing.contains(.realtime) else { throw TestTransportError.injected }
                realtimeFrames.append(data)
            case .latestSnapshot:
                guard !failing.contains(.latestSnapshot) else { throw TestTransportError.injected }
                snapshotFrames.append(data)
            case .durableUserInfo:
                guard !failing.contains(.durableUserInfo) else { throw TestTransportError.injected }
                durableFrames.append(data)
            }
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private final class FileSinkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedKinds: [WatchTransferFileKind] = []
    private var recordedFrames: [Data] = []

    var kinds: [WatchTransferFileKind] { locked { recordedKinds } }
    var frames: [Data] { locked { recordedFrames } }

    func record(_ data: Data, kind: WatchTransferFileKind) {
        locked {
            recordedKinds.append(kind)
            recordedFrames.append(data)
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class TestClock: LinkClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Int64

    init(now: Int64) {
        current = now
    }

    func nowEpochMilliseconds() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ milliseconds: Int64) {
        lock.lock()
        current += milliseconds
        lock.unlock()
    }
}
