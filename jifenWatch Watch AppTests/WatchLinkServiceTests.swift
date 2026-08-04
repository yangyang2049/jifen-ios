import XCTest
import LinkCore
import RecordCore
import ScoreCore
import SessionCore
@testable import jifenWatch_Watch_App

@MainActor
final class WatchLinkServiceTests: XCTestCase {
    func testWatchLinkRejectsMismatchedModeBeforeShowingConfirmation() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store
        )
        let state = RallyMatchEngine.initial(
            leftName: "甲",
            rightName: "乙",
            rules: .badminton()
        )
        let envelope = LinkEnvelope(
            sessionId: UUID(),
            kind: .setupRequest,
            sender: .phone,
            senderSequence: 1,
            sessionRevision: 0,
            sentAtEpochMilliseconds: 1,
            payload: LinkedScoreboardSetup(
                gameType: .badmintonDoubles,
                maxSets: state.rules.maxSets,
                initialSnapshot: .rally(state),
                participantNames: ["甲", "乙"]
            )
        )

        transport.deliver(try JSONEncoder().encode(envelope))
        await settleWatchLinkService()

        XCTAssertNil(service.pendingConfirmRequest)
        let rejection = try XCTUnwrap(
            transport.realtimeMessages.compactMap {
                try? JSONDecoder().decode(
                    LinkEnvelope<EmptyLinkPayload>.self,
                    from: $0
                )
            }.last
        )
        XCTAssertEqual(rejection.kind, .setupRejected)
        XCTAssertEqual(rejection.correlationId, envelope.messageId)
    }

    func testWatchLinkNextMatchCreatesFreshIdentityAndRevision() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store
        )
        let setup = makeWatchLinkSetup()
        transport.deliver(try JSONEncoder().encode(setup.envelope))
        await settleWatchLinkService()
        service.acceptPendingSetup()
        let firstHandle = try XCTUnwrap(service.resumeContext?.handle)

        service.startNextMatch(snapshot: setup.snapshot)
        await settleWatchLinkService()

        let next = try XCTUnwrap(service.resumeContext)
        XCTAssertEqual(next.handle.sessionId, firstHandle.sessionId)
        XCTAssertEqual(next.handle.matchGeneration, firstHandle.matchGeneration + 1)
        XCTAssertNotEqual(next.handle.matchId, firstHandle.matchId)
        XCTAssertEqual(next.revision, 1)
        XCTAssertEqual(next.role, .watchController)
        XCTAssertEqual(transport.publishedSnapshots.count, 1)
    }

    func testWatchLinkTakeoverIsCorrelatedIdempotentAndRestoresFollower() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store
        )
        let setup = makeWatchLinkSetup()
        transport.deliver(try JSONEncoder().encode(setup.envelope))
        await settleWatchLinkService()
        service.acceptPendingSetup()
        let handle = try XCTUnwrap(service.resumeContext?.handle)
        let takeover = LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: 0,
            kind: .takeoverByPhone,
            sender: .phone,
            senderSequence: 2,
            sessionRevision: 0,
            sentAtEpochMilliseconds: 2,
            payload: LinkAuthorityTransferPayload(
                snapshot: setup.snapshot,
                baseRevision: 0
            )
        )
        let takeoverData = try JSONEncoder().encode(takeover)

        transport.deliver(takeoverData)
        await settleWatchLinkService()
        transport.deliver(takeoverData)
        await settleWatchLinkService()

        let context = try XCTUnwrap(service.resumeContext)
        XCTAssertEqual(context.role, .watchFollower)
        XCTAssertEqual(context.authorityEpoch, 1)
        let acknowledgements = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(
                LinkEnvelope<LinkAcknowledgementPayload>.self,
                from: $0
            )
        }.filter { $0.correlationId == takeover.messageId }
        XCTAssertEqual(acknowledgements.count, 2)
        XCTAssertTrue(acknowledgements.allSatisfy { $0.authorityEpoch == 1 })

        let restored = WatchLinkService(
            transport: WatchLinkTestTransport(),
            contextStore: store,
            outboxStore: store
        )
        XCTAssertEqual(restored.resumeContext?.role, .watchFollower)
        XCTAssertEqual(restored.resumeContext?.authorityEpoch, 1)
        XCTAssertEqual(restored.resumeContext?.handle, handle)
    }

    private func makeWatchLinkSetup() -> (
        envelope: LinkEnvelope<LinkedScoreboardSetup>,
        snapshot: LinkedScoreboardSnapshot
    ) {
        let state = RallyMatchEngine.initial(
            leftName: "甲",
            rightName: "乙",
            rules: .badminton()
        )
        let snapshot = LinkedScoreboardSnapshot.rally(state)
        let handle = LinkedMatchHandle(sessionId: UUID())
        return (
            LinkEnvelope(
                sessionId: handle.sessionId,
                matchId: handle.matchId,
                matchGeneration: handle.matchGeneration,
                kind: .setupRequest,
                sender: .phone,
                senderSequence: 1,
                sessionRevision: 0,
                sentAtEpochMilliseconds: 1,
                payload: LinkedScoreboardSetup(
                    gameType: .badminton,
                    maxSets: state.rules.maxSets,
                    initialSnapshot: snapshot,
                    participantNames: ["甲", "乙"]
                )
            ),
            snapshot
        )
    }

    private func settleWatchLinkService() async {
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}

private final class WatchLinkTestDataStore: @unchecked Sendable, LinkDataStore {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) {
        values[key] = data
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }
}

private final class WatchLinkTestTransport: @unchecked Sendable, WatchLinkTransport {
    var status = WatchConnectivityStatus(
        isSupported: true,
        isActivated: true,
        isPaired: true,
        isWatchAppInstalled: true,
        isReachable: true
    )
    var receivedApplicationContext: [String: Any] = [:]
    var isReachable: Bool { status.isReachable }

    var onReceive: (@Sendable (Data) -> Void)?
    var onSendError: (@Sendable (Error) -> Void)?
    var onStatusChange: (@Sendable (WatchConnectivityStatus) -> Void)?
    var onApplicationContext: (@Sendable ([String: Any]) -> Void)?
    var onWatchRecordData: (@Sendable (Data) -> Void)?
    var onCommonNameUsageData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationsData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationAckData: (@Sendable (Data) -> Void)?
    var onCatchUpRequest: (@Sendable () -> Void)?
    var onClearPendingRequest: (@Sendable ([String]) -> Void)?
    var onPendingRecords: (@Sendable ([Data]) -> Void)?

    private(set) var realtimeMessages: [Data] = []
    private(set) var publishedSnapshots: [Data] = []
    private(set) var durableMessages: [Data] = []

    func activate() {}
    func refreshStatus() { onStatusChange?(status) }

    func sendRealtime(_ data: Data) async throws {
        realtimeMessages.append(data)
    }

    func publishLatestSnapshot(_ data: Data) throws {
        publishedSnapshots.append(data)
    }

    func enqueueDurable(_ data: Data) throws {
        durableMessages.append(data)
    }

    func sendInteractive(_ data: Data) throws {
        realtimeMessages.append(data)
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        receivedApplicationContext.merge(context) { _, latest in latest }
    }

    func transferWatchRecord(_ data: Data) throws {}
    func transferCommonNameUsage(_ data: Data) throws {}
    func transferCommonNameMutations(_ data: Data) throws {}
    func transferCommonNameMutationAcknowledgement(_ data: Data) throws {}
    func requestPendingWatchRecords() {}
    func sendPendingWatchRecords(_ datas: [Data]) {}
    func clearPendingWatchRecords(ids: [String]) {}

    func deliver(_ data: Data) {
        onReceive?(data)
    }
}
