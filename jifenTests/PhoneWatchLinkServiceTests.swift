import XCTest
import LinkCore
import ScoreCore
import UIKit
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

    func testForegroundStatusRefreshCoalescesOverlappingQueries() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 4, authorityEpoch: 7)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        NotificationCenter.default.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        await settleMainQueue()

        let queries = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: $0)
        }.filter { $0.kind == .statusQuery }
        let query = try XCTUnwrap(queries.first)
        XCTAssertEqual(queries.count, 1)

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
        transport.deliver(try JSONEncoder().encode(response))
        await settleMainQueue()

        XCTAssertEqual(service.linkedResumeDescriptor?.role, .phoneFollower)
    }

    func testResumeDescriptorIsNilWhileSetupHandshakeIsPending() async throws {
        let store = InMemoryLinkDataStore()
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton()
        )
        let snapshot = LinkedScoreboardSnapshot.rally(state)

        let setupTask = Task {
            try await service.startInteractiveSession(
                gameType: .badminton,
                maxSets: state.rules.maxSets,
                initialSnapshot: snapshot,
                participantNames: ["Alice", "Bob"]
            )
        }
        try await settleMainQueue()

        // The setup request is in flight but the watch has not accepted yet —
        // no session exists, so no resume descriptor (no Resume GameBar).
        XCTAssertNil(service.linkedResumeDescriptor)

        let request = try XCTUnwrap(
            transport.realtimeMessages.compactMap {
                try? JSONDecoder().decode(
                    LinkEnvelope<LinkedScoreboardSetup>.self,
                    from: $0
                )
            }.first { $0.kind == .setupRequest }
        )
        let accepted = LinkEnvelope<EmptyLinkPayload>(
            correlationId: request.messageId,
            sessionId: request.sessionId,
            matchId: request.matchId,
            matchGeneration: request.matchGeneration,
            authorityEpoch: 0,
            kind: .setupAccepted,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: 0,
            sentAtEpochMilliseconds: request.sentAtEpochMilliseconds + 1,
            payload: EmptyLinkPayload()
        )
        transport.deliver(try JSONEncoder().encode(accepted))
        await settleMainQueue()

        // Watch accepted: the session is established and the descriptor appears.
        let descriptor = try XCTUnwrap(service.linkedResumeDescriptor)
        XCTAssertEqual(descriptor.handle.sessionId, request.sessionId)
        _ = await setupTask.result
    }

    func testLeaveSessionIfMatchFinishedEndsFinishedLinkedSession() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 4, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        // Watch reports the match finished: the session lifecycle becomes
        // `.matchFinished` and the descriptor surfaces (GameBar visible).
        transport.deliver(try JSONEncoder().encode(
            finishedEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 5, snapshot: fixture.snapshot)
        ))
        await settleMainQueue()
        XCTAssertNotNil(service.linkedResumeDescriptor)

        // Exiting the finished scoreboard ends the session, so no stale
        // GameBar is left behind on Home.
        service.leaveSessionIfMatchFinished(fixture.handle.sessionId)
        await settleMainQueue()
        XCTAssertNil(service.linkedResumeDescriptor)
    }

    func testLeaveSessionIfMatchFinishedKeepsUnfinishedLinkedSession() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 4, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        await settleMainQueue()

        // Mid-match exit must keep the session so the user can re-attach.
        XCTAssertNotNil(service.linkedResumeDescriptor)
        service.leaveSessionIfMatchFinished(fixture.handle.sessionId)
        await settleMainQueue()
        XCTAssertNotNil(service.linkedResumeDescriptor)
    }

    func testStartupRecordLoadersRunOnlyWhenRequestedAndCoalesce() async {
        let scoreboardCounter = LockedInvocationCounter()
        let scoreboardVM = ScoreboardRecordsViewModel {
            scoreboardCounter.increment()
            return []
        }

        XCTAssertFalse(scoreboardVM.hasLoaded)
        scoreboardVM.ensureLoaded()
        scoreboardVM.ensureLoaded()
        for _ in 0..<50 where !scoreboardVM.hasLoaded {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(scoreboardVM.hasLoaded)
        XCTAssertEqual(scoreboardCounter.value, 1)

        var timerLoadCount = 0
        let timerVM = TimerRecordsViewModel {
            timerLoadCount += 1
            return []
        }
        XCTAssertFalse(timerVM.hasLoaded)
        timerVM.ensureLoaded()
        timerVM.ensureLoaded()
        XCTAssertTrue(timerVM.hasLoaded)
        XCTAssertEqual(timerLoadCount, 1)
    }

    func testRecordSummaryCacheRefreshesAfterExternalMutationNotification() async {
        let notificationCenter = NotificationCenter()
        let counter = LockedInvocationCounter()
        let viewModel = ScoreboardRecordsViewModel(
            summaryLoader: {
                counter.increment()
                return []
            },
            notificationCenter: notificationCenter
        )

        viewModel.ensureLoaded()
        for _ in 0..<50 where !viewModel.hasLoaded {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertEqual(counter.value, 1)

        notificationCenter.post(name: .scoreboardRecordsDidChange, object: nil)
        for _ in 0..<50 where counter.value < 2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(counter.value, 2)
    }

    func testQuickStartConfigurationDecodesOnce() throws {
        let suiteName = "QuickStartConfigManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persisted = QuickStartConfig(primarySport: .tennis, secondarySport: .boxing)
        defaults.set(try JSONEncoder().encode(persisted), forKey: "quick-start-test")

        let manager = QuickStartConfigManager(
            userDefaults: defaults,
            configKey: "quick-start-test"
        )
        manager.configureDefaultsIfNeeded(isLargeScreen: true, is2in1: false)
        manager.configureDefaultsIfNeeded(isLargeScreen: false, is2in1: false)

        XCTAssertEqual(manager.quickStartConfig, persisted)
        XCTAssertEqual(manager.configurationReadCount, 1)
    }

    func testRetrySchedulerStaysIdleWithoutWorkAndStartsForRestoredOutbox() throws {
        let idleStore = InMemoryLinkDataStore()
        let idleService = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: idleStore,
            outboxStore: idleStore,
            recordSink: RecordingPhoneLinkSink()
        )
        XCTAssertFalse(idleService.hasScheduledRetryForTesting)

        let pendingStore = InMemoryLinkDataStore()
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let outbox = LinkDurableOutbox(items: [
            .init(
                messageId: UUID(),
                handle: handle,
                data: Data([1]),
                lastSentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
            )
        ])
        pendingStore.set(
            try JSONEncoder().encode(outbox),
            forKey: "phone_link_terminal_outbox"
        )
        let pendingService = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: pendingStore,
            outboxStore: pendingStore,
            recordSink: RecordingPhoneLinkSink()
        )
        XCTAssertTrue(pendingService.hasScheduledRetryForTesting)
    }

    func testLegacyLinkCleanupRunsOnlyOnce() {
        let store = InMemoryLinkDataStore()
        let legacyKeys = [
            "phone_link_context_v1",
            "phone_link_terminal_outbox_v1",
            "phone_link_pending_ack_v1"
        ]
        legacyKeys.forEach { store.set(Data([1]), forKey: $0) }

        _ = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        legacyKeys.forEach { XCTAssertNil(store.data(forKey: $0)) }

        legacyKeys.forEach { store.set(Data([2]), forKey: $0) }
        _ = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        legacyKeys.forEach {
            XCTAssertEqual(store.data(forKey: $0), Data([2]))
            XCTAssertEqual(store.removalCounts[$0], 1)
        }
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

    func testFinishedSnapshotSurvivesMatchFinishedFirstInterleaving() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 0, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        let finished = finishedRallySnapshot()

        // transferUserInfo (matchFinished) can arrive before the final
        // sendMessageData snapshot. The phone accepts rev 3 first...
        transport.deliver(try JSONEncoder().encode(
            finishedEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 3, snapshot: finished)
        ))
        await settleMainQueue()
        XCTAssertEqual(service.latestRemoteSnapshot?.revision, 3)
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot.rallyState?.finished, true)

        // ...so the final snapshot (rev 2, finished) arrives as
        // duplicateOrOlder. Mirroring HarmonyOS it must still be surfaced
        // rather than dropped, so the finish signal can never be lost.
        transport.deliver(try JSONEncoder().encode(
            snapshotEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 2, snapshot: finished)
        ))
        await settleMainQueue()

        let latest = try XCTUnwrap(service.latestRemoteSnapshot)
        XCTAssertEqual(latest.revision, 2)
        XCTAssertEqual(latest.snapshot.rallyState?.finished, true)
    }

    func testUnfinishedDuplicateSnapshotDoesNotOverrideFinishedSignal() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 0, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        // The watch reports the match finished first...
        transport.deliver(try JSONEncoder().encode(
            finishedEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 3, snapshot: finishedRallySnapshot())
        ))
        await settleMainQueue()
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot.rallyState?.finished, true)

        // A stale unfinished retry (rev 2, e.g. a lost ACK replayed) is
        // duplicateOrOlder — surfacing it would wrongly dismiss the finish
        // dialog. Only finished duplicates are surfaced.
        transport.deliver(try JSONEncoder().encode(
            snapshotEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 2, snapshot: fixture.snapshot)
        ))
        await settleMainQueue()

        let latest = try XCTUnwrap(service.latestRemoteSnapshot)
        XCTAssertEqual(latest.revision, 3)
        XCTAssertEqual(latest.snapshot.rallyState?.finished, true)
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

    private func finishedRallySnapshot() -> LinkedScoreboardSnapshot {
        var state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton()
        )
        state.leftPoints = 21
        state.rightPoints = 18
        state.leftSets = 2
        state.rightSets = 0
        state.finished = true
        return .rally(state)
    }

    private func snapshotEnvelope(
        handle: LinkedMatchHandle,
        authorityEpoch: UInt64,
        revision: UInt64,
        snapshot: LinkedScoreboardSnapshot
    ) -> LinkEnvelope<LinkedScoreboardSetup> {
        LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: authorityEpoch,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: revision,
            sessionRevision: revision,
            sentAtEpochMilliseconds: Int64(revision) * 1_000,
            payload: LinkedScoreboardSetup(
                gameType: .badminton,
                maxSets: snapshot.rallyState?.rules.maxSets ?? 3,
                initialSnapshot: snapshot,
                participantNames: ["Alice", "Bob"]
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
    private(set) var removalCounts: [String: Int] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) {
        values[key] = data
    }

    func removeObject(forKey key: String) {
        removalCounts[key, default: 0] += 1
        values.removeValue(forKey: key)
    }
}

private final class LockedInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
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
    var onCatchUpRequest: (@Sendable () -> Void)?
    var onClearPendingRequest: (@Sendable ([String]) -> Void)?
    var onPendingRecords: (@Sendable ([Data]) -> Void)?

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
    func requestPendingWatchRecords() {}
    func sendPendingWatchRecords(_ datas: [Data]) {}
    func clearPendingWatchRecords(ids: [String]) {}

    func deliver(_ data: Data) {
        onReceive?(data)
    }
}
