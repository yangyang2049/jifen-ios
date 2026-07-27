import XCTest
import LinkCore
@testable import jifenWatch_Watch_App

@MainActor
final class WatchCommonNamesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WatchCommonNamesStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testOfflineMutationPersistsAndOverlaysCanonicalSnapshot() throws {
        var store = WatchCommonNamesStore(defaults: defaults)
        store.apply(.init(teams: [], players: ["Alice"], revision: 1))
        try store.addName("  Bob  ", type: .player)

        XCTAssertEqual(store.players, ["Bob", "Alice"])
        XCTAssertEqual(store.pendingCount, 1)

        store = WatchCommonNamesStore(defaults: defaults)
        XCTAssertEqual(store.players, ["Bob", "Alice"])
        XCTAssertEqual(store.pendingCount, 1)

        store.apply(.init(teams: [], players: ["Alice"], revision: 1))
        XCTAssertEqual(store.players, ["Bob", "Alice"])
    }

    func testAcknowledgementClearsPendingAndConflictRestoresPhoneResult() throws {
        let store = WatchCommonNamesStore(defaults: defaults)
        store.apply(.init(teams: [], players: ["Alice"], revision: 1))
        try store.updateName("Alice", newName: "Alicia", type: .player)
        let mutation = try XCTUnwrap(store.pendingMutations.first)

        store.apply(.init(
            snapshot: .init(teams: [], players: ["Alice"], revision: 1),
            results: [.init(mutationId: mutation.id, status: .conflict)]
        ))

        XCTAssertEqual(store.players, ["Alice"])
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertTrue(store.hasUnresolvedConflict)
        XCTAssertTrue(WatchCommonNamesStore(defaults: defaults).hasUnresolvedConflict)
    }

    func testOlderAcknowledgementClearsItsMutationWithoutReplacingNewerCanonicalSnapshot() throws {
        let store = WatchCommonNamesStore(defaults: defaults)
        store.apply(.init(teams: [], players: ["Current"], revision: 5))
        try store.addName("Local", type: .player)
        let mutation = try XCTUnwrap(store.pendingMutations.first)

        store.apply(.init(
            snapshot: .init(teams: [], players: ["Old"], revision: 4),
            results: [.init(mutationId: mutation.id, status: .conflict)]
        ))

        XCTAssertEqual(store.players, ["Current"])
        XCTAssertEqual(store.revision, 5)
        XCTAssertEqual(store.pendingCount, 0)
    }

    func testDuplicateOldConflictAcknowledgementDoesNotRestoreClearedConflictState() throws {
        let store = WatchCommonNamesStore(defaults: defaults)
        store.apply(.init(teams: [], players: ["Alice"], revision: 1))
        try store.updateName("Alice", newName: "Alicia", type: .player)
        let rename = try XCTUnwrap(store.pendingMutations.first)
        let conflictAcknowledgement = CommonNameMutationAcknowledgement(
            snapshot: .init(teams: [], players: ["Alice"], revision: 1),
            results: [.init(mutationId: rename.id, status: .conflict)]
        )
        store.apply(conflictAcknowledgement)
        XCTAssertTrue(store.hasUnresolvedConflict)

        try store.addName("Bob", type: .player)
        let add = try XCTUnwrap(store.pendingMutations.first)
        store.apply(.init(
            snapshot: .init(teams: [], players: ["Bob", "Alice"], revision: 2),
            results: [.init(mutationId: add.id, status: .applied)]
        ))
        XCTAssertFalse(store.hasUnresolvedConflict)

        store.apply(conflictAcknowledgement)
        XCTAssertFalse(store.hasUnresolvedConflict)
        XCTAssertEqual(store.players, ["Bob", "Alice"])
    }

    func testValidationAndPerTypeLimit() throws {
        let store = WatchCommonNamesStore(defaults: defaults)
        store.apply(.init(
            teams: [],
            players: (0..<60).map { "P\($0)" },
            revision: 1
        ))
        XCTAssertEqual(store.players.count, 50)

        let longName = String(repeating: "A", count: 40)
        let stored = try store.addName(longName, type: .player)
        XCTAssertEqual(stored.count, WatchCommonNamesStore.maxNameLength)
        XCTAssertEqual(store.players.count, 50)
        XCTAssertEqual(store.players.first, stored)
        XCTAssertThrowsError(try store.addName(stored.lowercased(), type: .player))
        XCTAssertThrowsError(try store.addName("红方", type: .player))
    }

    func testPhoneLinkProbePolicyAndTrackerRejectWrongResponses() {
        let inactive = WatchConnectivityStatus(
            isSupported: true,
            isActivated: false,
            isPaired: true,
            isWatchAppInstalled: true,
            isReachable: true
        )
        let unreachable = WatchConnectivityStatus(
            isSupported: true,
            isActivated: true,
            isPaired: true,
            isWatchAppInstalled: true,
            isReachable: false
        )
        let reachable = WatchConnectivityStatus(
            isSupported: true,
            isActivated: true,
            isPaired: true,
            isWatchAppInstalled: true,
            isReachable: true
        )
        XCTAssertFalse(WatchPhoneLinkProbeTracker.canStart(with: inactive))
        XCTAssertFalse(WatchPhoneLinkProbeTracker.canStart(with: unreachable))
        XCTAssertTrue(WatchPhoneLinkProbeTracker.canStart(with: reachable))
        XCTAssertEqual(WatchPhoneLinkProbeTracker.timeoutSeconds, 8)

        var tracker = WatchPhoneLinkProbeTracker()
        let expected = UUID()
        tracker.start(expected)
        XCTAssertFalse(tracker.accept(UUID()))
        XCTAssertEqual(tracker.activeProbeID, expected)
        XCTAssertFalse(tracker.accept(sessionID: UUID(), probeID: expected))
        XCTAssertEqual(tracker.activeProbeID, expected)
        XCTAssertTrue(tracker.accept(sessionID: expected, probeID: expected))
        XCTAssertNil(tracker.activeProbeID)
        XCTAssertFalse(tracker.accept(expected))

        tracker.start(expected)
        XCTAssertTrue(tracker.timeout(expected))
        XCTAssertNil(tracker.activeProbeID)
    }
}
