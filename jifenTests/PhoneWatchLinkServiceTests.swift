import XCTest
import LinkCore
import ScoreCore
@testable import jifen

@MainActor
final class PhoneWatchLinkServiceTests: XCTestCase {
    func testRestoresFollowerRoleAndLatestSnapshotAfterProcessRestart() throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 6, authorityEpoch: 3)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")

        let service = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        let restored = try XCTUnwrap(service.linkedResumeDescriptor)
        XCTAssertEqual(restored.handle, fixture.handle)
        XCTAssertEqual(restored.role, .phoneFollower)
        XCTAssertEqual(restored.authorityEpoch, 3)
        XCTAssertEqual(restored.revision, 6)
        XCTAssertEqual(restored.snapshot, fixture.snapshot)
    }

    func testForceTakeoverUsesCorrelatedStatusAndRaisesAuthorityEpoch() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 4, authorityEpoch: 7)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        transport.automaticallyRespondToStatusQueries = true
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        try await service.forceTakeover(sessionId: fixture.handle.sessionId)

        let current = try XCTUnwrap(service.linkedResumeDescriptor)
        XCTAssertEqual(current.role, .phoneController)
        XCTAssertEqual(current.authorityEpoch, 8)
        XCTAssertEqual(current.revision, 5)
        XCTAssertEqual(current.snapshot, fixture.snapshot)
        XCTAssertEqual(transport.publishedSnapshots.count, 1)

        let persistedData = try XCTUnwrap(store.data(forKey: "phone_link_context"))
        let persisted = try JSONDecoder().decode(PhoneLinkResumeContext.self, from: persistedData)
        XCTAssertEqual(persisted.role, .phoneController)
        XCTAssertEqual(persisted.authorityEpoch, 8)
    }

    func testWatchControllerTwoMatchesCreateExactlyTwoRecords() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 0, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let sink = RecordingPhoneLinkSink()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: sink
        )

        let firstFinished = finishedEnvelope(
            handle: fixture.handle,
            authorityEpoch: 2,
            revision: 1,
            snapshot: fixture.snapshot
        )
        transport.deliver(try JSONEncoder().encode(firstFinished))
        await settleMainQueue()

        let secondHandle = fixture.handle.nextMatch()
        let secondState = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton()
        )
        let secondSnapshot = LinkedScoreboardSnapshot.rally(secondState)
        let nextMatch = LinkEnvelope(
            sessionId: secondHandle.sessionId,
            matchId: secondHandle.matchId,
            matchGeneration: secondHandle.matchGeneration,
            authorityEpoch: 2,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: 2,
            sessionRevision: 1,
            sentAtEpochMilliseconds: 2_000,
            payload: LinkedScoreboardSetup(
                gameType: .badminton,
                maxSets: secondState.rules.maxSets,
                initialSnapshot: secondSnapshot,
                participantNames: ["Alice", "Bob"]
            )
        )
        transport.deliver(try JSONEncoder().encode(nextMatch))
        await settleMainQueue()

        let secondFinished = finishedEnvelope(
            handle: secondHandle,
            authorityEpoch: 2,
            revision: 2,
            snapshot: secondSnapshot
        )
        let secondFinishedData = try JSONEncoder().encode(secondFinished)
        transport.deliver(secondFinishedData)
        transport.deliver(secondFinishedData)
        await settleMainQueue()

        XCTAssertEqual(sink.matchIds, [fixture.handle.matchId, secondHandle.matchId])
        XCTAssertEqual(Set(sink.matchIds).count, 2)
        XCTAssertEqual(service.linkedResumeDescriptor?.handle, secondHandle)
    }

    private func makeContext(
        revision: UInt64,
        authorityEpoch: UInt64
    ) -> (
        handle: LinkedMatchHandle,
        snapshot: LinkedScoreboardSnapshot,
        context: PhoneLinkResumeContext
    ) {
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton()
        )
        let snapshot = LinkedScoreboardSnapshot.rally(state)
        let setup = LinkedScoreboardSetup(
            gameType: .badminton,
            maxSets: state.rules.maxSets,
            initialSnapshot: snapshot,
            participantNames: ["Alice", "Bob"]
        )
        return (
            handle,
            snapshot,
            PhoneLinkResumeContext(
                handle: handle,
                setup: setup,
                role: .phoneFollower,
                authorityEpoch: authorityEpoch,
                revision: revision,
                latestAuthoritativeSnapshot: snapshot,
                detailedActions: [],
                completedMatchIds: [],
                pendingTerminalMessageIds: []
            )
        )
    }

    private func finishedEnvelope(
        handle: LinkedMatchHandle,
        authorityEpoch: UInt64,
        revision: UInt64,
        snapshot: LinkedScoreboardSnapshot
    ) -> LinkEnvelope<LinkMatchFinishedPayload> {
        LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: authorityEpoch,
            kind: .matchFinished,
            sender: .watch,
            senderSequence: revision,
            sessionRevision: revision,
            sentAtEpochMilliseconds: Int64(revision) * 1_000,
            payload: LinkMatchFinishedPayload(
                snapshot: snapshot,
                recordId: "watch-\(handle.matchId.uuidString)",
                startTimeEpochMilliseconds: 1_000,
                endTimeEpochMilliseconds: 2_000,
                durationSeconds: 1,
                totalScoreChanges: 1,
                participantNames: ["Alice", "Bob"]
            )
        )
    }

    private func settleMainQueue() async {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

private final class InMemoryLinkDataStore: @unchecked Sendable, LinkDataStore {
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

@MainActor
private final class RecordingPhoneLinkSink: PhoneLinkRecordSink {
    private(set) var matchIds: [UUID] = []

    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID
    ) throws -> String {
        matchIds.append(matchId)
        return "record-\(matchId.uuidString)"
    }
}

private final class FakeWatchLinkTransport: @unchecked Sendable, WatchLinkTransport {
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

    var automaticallyRespondToStatusQueries = false
    private(set) var realtimeMessages: [Data] = []
    private(set) var publishedSnapshots: [Data] = []
    private(set) var durableMessages: [Data] = []

    func activate() {}

    func refreshStatus() {
        onStatusChange?(status)
    }

    func sendRealtime(_ data: Data) async throws {
        realtimeMessages.append(data)
        guard automaticallyRespondToStatusQueries,
              let query = try? JSONDecoder().decode(
                  LinkEnvelope<EmptyLinkPayload>.self,
                  from: data
              ),
              query.kind == .statusQuery else {
            return
        }
        let response = LinkEnvelope(
            correlationId: query.messageId,
            sessionId: query.sessionId,
            matchId: query.matchId,
            matchGeneration: query.matchGeneration,
            authorityEpoch: query.authorityEpoch,
            kind: .statusResponse,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: query.sessionRevision,
            sentAtEpochMilliseconds: query.sentAtEpochMilliseconds + 1,
            payload: LinkStatusPayload(
                role: .watchController,
                revision: query.sessionRevision
            )
        )
        onReceive?(try JSONEncoder().encode(response))
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

    func deliver(_ data: Data) {
        onReceive?(data)
    }
}
