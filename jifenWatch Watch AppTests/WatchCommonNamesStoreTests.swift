import XCTest
import LinkCore
@testable import jifenWatch_Watch_App

@MainActor
final class WatchCommonNamesStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    private var storeFileURL: URL {
        directory.appendingPathComponent("store.json", isDirectory: false)
    }

    func testOfflineMutationPersistsAndOverlaysCanonicalSnapshot() throws {
        var store = WatchCommonNamesStore(directoryURL: directory)
        store.apply(.init(teams: [], players: ["Alice"], revision: 1))
        // “bob”已并入共享预制词库，改用非预制样本。
        try store.addName("  Bobby  ", type: .player)

        XCTAssertEqual(store.players, ["Bobby", "Alice"])
        XCTAssertEqual(store.pendingCount, 1)

        store = WatchCommonNamesStore(directoryURL: directory)
        XCTAssertEqual(store.players, ["Bobby", "Alice"])
        XCTAssertEqual(store.pendingCount, 1)

        store.apply(.init(teams: [], players: ["Alice"], revision: 1))
        XCTAssertEqual(store.players, ["Bobby", "Alice"])
    }

    func testAcknowledgementClearsPendingAndConflictRestoresPhoneResult() throws {
        let store = WatchCommonNamesStore(directoryURL: directory)
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
        XCTAssertTrue(WatchCommonNamesStore(directoryURL: directory).hasUnresolvedConflict)
    }

    func testOlderAcknowledgementClearsItsMutationWithoutReplacingNewerCanonicalSnapshot() throws {
        let store = WatchCommonNamesStore(directoryURL: directory)
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
        let store = WatchCommonNamesStore(directoryURL: directory)
        store.apply(.init(teams: [], players: ["Alice"], revision: 1))
        try store.updateName("Alice", newName: "Alicia", type: .player)
        let rename = try XCTUnwrap(store.pendingMutations.first)
        let conflictAcknowledgement = CommonNameMutationAcknowledgement(
            snapshot: .init(teams: [], players: ["Alice"], revision: 1),
            results: [.init(mutationId: rename.id, status: .conflict)]
        )
        store.apply(conflictAcknowledgement)
        XCTAssertTrue(store.hasUnresolvedConflict)

        try store.addName("Bobby", type: .player)
        let add = try XCTUnwrap(store.pendingMutations.first)
        store.apply(.init(
            snapshot: .init(teams: [], players: ["Bobby", "Alice"], revision: 2),
            results: [.init(mutationId: add.id, status: .applied)]
        ))
        XCTAssertFalse(store.hasUnresolvedConflict)

        store.apply(conflictAcknowledgement)
        XCTAssertFalse(store.hasUnresolvedConflict)
        XCTAssertEqual(store.players, ["Bobby", "Alice"])
    }

    func testValidationAndPerTypeLimit() throws {
        let store = WatchCommonNamesStore(directoryURL: directory)
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

    func testNewDefaultParticipantNamesAreRejectedAsCommonNames() {
        let store = WatchCommonNamesStore(directoryURL: directory)

        for name in ["Team A", "Player A", "Archer A", "Red A", "A队", "射手A"] {
            XCTAssertThrowsError(try store.addName(name, type: .player), name)
        }
    }

    /// 预制词判断统一走 LinkCore.PresetCommonNames：简体、繁体与英文样本都必须被拒绝。
    func testSimplifiedTraditionalAndEnglishPresetNamesAreRejected() {
        let store = WatchCommonNamesStore(directoryURL: directory)

        for (name, type) in [("红方", CommonNameSyncType.team), ("紅隊", .team), ("red team", .team)] {
            do {
                _ = try store.addName(name, type: type)
                XCTFail("Preset name should be rejected: \(name)")
            } catch let error as WatchCommonNamesError {
                XCTAssertEqual(error, .presetName, name)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        for (name, type) in [("選手A", CommonNameSyncType.player), ("archer b", .player), ("刘备", .player)] {
            XCTAssertThrowsError(try store.addName(name, type: type), name)
        }
    }

    /// store.json 损坏时重新起算干净状态，不残留旧队名/待发 mutation。
    func testCorruptStoreFileRestartsFromCleanState() throws {
        let seeded = WatchCommonNamesStore(directoryURL: directory)
        try seeded.addName("Alice", type: .player)
        seeded.apply(.init(teams: ["红队"], players: [], revision: 3))
        XCTAssertEqual(seeded.teams, ["红队"])
        XCTAssertEqual(seeded.pendingCount, 1)

        try Data("not-json-at-all".utf8).write(to: storeFileURL, options: .atomic)

        let restarted = WatchCommonNamesStore(directoryURL: directory)
        XCTAssertEqual(restarted.teams, [])
        XCTAssertEqual(restarted.players, [])
        XCTAssertEqual(restarted.pendingCount, 0)
        XCTAssertEqual(restarted.revision, 0)
        XCTAssertEqual(restarted.updatedAtEpochMilliseconds, 0)
        XCTAssertFalse(restarted.hasUnresolvedConflict)

        // 干净状态已覆盖写回，之后的新增照常持久化。
        try restarted.addName("Bobby", type: .player)
        let reloaded = WatchCommonNamesStore(directoryURL: directory)
        XCTAssertEqual(reloaded.players, ["Bobby"])
        XCTAssertEqual(reloaded.pendingCount, 1)
    }

    func testRecordUsagePersistsNewManualNameAndIgnoresExistingOrPresetNames() {
        var store = WatchCommonNamesStore(directoryURL: directory)
        store.apply(.init(teams: [], players: ["Alice"], revision: 1))

        XCTAssertTrue(store.recordUsage("  Bobby  ", type: .player))
        XCTAssertFalse(store.recordUsage("bobby", type: .player))
        // “bob”/“adam” 属于 LinkCore.PresetCommonNames，预制词一律忽略。
        XCTAssertFalse(store.recordUsage("bob", type: .player))
        XCTAssertFalse(store.recordUsage("红方", type: .player))
        XCTAssertEqual(store.players, ["Bobby", "Alice"])
        XCTAssertEqual(store.pendingCount, 1)

        store = WatchCommonNamesStore(directoryURL: directory)
        XCTAssertEqual(store.players, ["Bobby", "Alice"])
        XCTAssertEqual(store.pendingCount, 1)
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
