import XCTest
import LinkCore
@testable import jifenWatch_Watch_App

@MainActor
final class WatchStartupOptimizationTests: XCTestCase {
    func testDuplicateCommonNamesContextRevisionIsIgnored() throws {
        let suiteName = "WatchStartupCommonNames.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WatchCommonNamesStore(defaults: defaults)

        XCTAssertTrue(store.apply(.init(
            teams: ["Team A"],
            players: ["Alice"],
            revision: 8
        )))
        XCTAssertFalse(store.apply(.init(
            teams: ["Duplicate"],
            players: ["Duplicate"],
            revision: 8
        )))

        XCTAssertEqual(store.teams, ["Team A"])
        XCTAssertEqual(store.players, ["Alice"])
        XCTAssertEqual(store.revision, 8)
    }

    func testResumeRestoreLoadsOnceAndLegacyCleanupRunsOnce() throws {
        let suiteName = "WatchStartupResume.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyKey = "watch_resume_session_v1"
        defaults.set(Data([1]), forKey: legacyKey)

        let first = WatchResumeSessionStore(defaults: defaults)
        XCTAssertEqual(first.restoreAttemptCount, 1)
        XCTAssertNil(defaults.data(forKey: legacyKey))

        defaults.set(Data([2]), forKey: legacyKey)
        let second = WatchResumeSessionStore(defaults: defaults)
        XCTAssertEqual(second.restoreAttemptCount, 1)
        XCTAssertEqual(defaults.data(forKey: legacyKey), Data([2]))
    }

    func testWatchLinkCleanupAndRetrySchedulingAreWorkDriven() throws {
        let store = WatchStartupDataStore()
        let legacyKeys = [
            "watch_link_context_v1",
            "watch_link_terminal_outbox_v1",
            "watch_link_pending_ack_v1"
        ]
        legacyKeys.forEach { store.set(Data([1]), forKey: $0) }

        let idleService = WatchLinkService(
            transport: WatchStartupTransport(),
            contextStore: store,
            outboxStore: store
        )
        XCTAssertFalse(idleService.hasScheduledRetryForTesting)
        legacyKeys.forEach { XCTAssertNil(store.data(forKey: $0)) }

        legacyKeys.forEach { store.set(Data([2]), forKey: $0) }
        _ = WatchLinkService(
            transport: WatchStartupTransport(),
            contextStore: store,
            outboxStore: store
        )
        legacyKeys.forEach {
            XCTAssertEqual(store.data(forKey: $0), Data([2]))
            XCTAssertEqual(store.removalCounts[$0], 1)
        }

        let pendingStore = WatchStartupDataStore()
        let outbox = LinkDurableOutbox(items: [
            .init(
                messageId: UUID(),
                handle: LinkedMatchHandle(sessionId: UUID(), matchId: UUID()),
                data: Data([3]),
                lastSentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
            )
        ])
        pendingStore.set(
            try JSONEncoder().encode(outbox),
            forKey: "watch_link_terminal_outbox"
        )
        let pendingService = WatchLinkService(
            transport: WatchStartupTransport(),
            contextStore: pendingStore,
            outboxStore: pendingStore
        )
        XCTAssertTrue(pendingService.hasScheduledRetryForTesting)
    }
}

private final class WatchStartupDataStore: @unchecked Sendable, LinkDataStore {
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

private final class WatchStartupTransport: @unchecked Sendable, WatchLinkTransport {
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

    func activate() {}
    func refreshStatus() { onStatusChange?(status) }
    func sendRealtime(_ data: Data) async throws {}
    func publishLatestSnapshot(_ data: Data) throws {}
    func enqueueDurable(_ data: Data) throws {}
    func sendInteractive(_ data: Data) throws {}
    func updateApplicationContext(_ context: [String: Any]) throws {
        receivedApplicationContext.merge(context) { _, latest in latest }
    }
    func transferWatchRecord(_ data: Data) throws {}
    func transferCommonNameUsage(_ data: Data) throws {}
    func transferCommonNameMutations(_ data: Data) throws {}
    func transferCommonNameMutationAcknowledgement(_ data: Data) throws {}
}
