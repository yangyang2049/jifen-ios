import XCTest
import LinkCore
@testable import jifen

@MainActor
final class CommonNamesWatchSyncTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CommonNamesWatchSyncTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPhoneAtomicallyArbitratesAndDeduplicatesWatchBatch() throws {
        let manager = CommonNamesManager(userDefaults: defaults)
        try manager.addName("Alice", type: .player)
        let initialRevision = manager.currentRevision
        let mutations = [
            CommonNameMutation(kind: .add, nameType: .player, newName: "Bob"),
            CommonNameMutation(kind: .add, nameType: .player, newName: "alice"),
            CommonNameMutation(kind: .rename, nameType: .player, originalName: "Alice", newName: "Alicia"),
            CommonNameMutation(kind: .delete, nameType: .player, originalName: "Missing")
        ]

        var notificationCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: .commonNamesDidChange,
            object: nil,
            queue: nil
        ) { _ in notificationCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        let acknowledgement = manager.applyWatchMutations(mutations)
        XCTAssertEqual(manager.getNames(type: .player), ["Bob", "Alicia"])
        XCTAssertEqual(acknowledgement.results.map(\.status), [.applied, .noChange, .applied, .noChange])
        XCTAssertEqual(manager.currentRevision, initialRevision + 1)
        XCTAssertEqual(notificationCount, 1)

        let repeated = manager.applyWatchMutations(mutations)
        XCTAssertEqual(repeated.results.map(\.status), acknowledgement.results.map(\.status))
        XCTAssertEqual(manager.currentRevision, initialRevision + 1)
        XCTAssertEqual(notificationCount, 1)
    }

    func testMissingRenameConflictsAndWatchInputIsClamped() {
        let manager = CommonNamesManager(userDefaults: defaults)
        let conflict = CommonNameMutation(
            kind: .rename,
            nameType: .team,
            originalName: "Missing",
            newName: "New Team"
        )
        let longName = CommonNameMutation(
            kind: .add,
            nameType: .player,
            newName: String(repeating: "A", count: 40)
        )
        let invalidDelete = CommonNameMutation(
            kind: .delete,
            nameType: .player,
            originalName: "   "
        )
        let acknowledgement = manager.applyWatchMutations([conflict, longName, invalidDelete])

        XCTAssertEqual(acknowledgement.results.map(\.status), [.conflict, .applied, .invalid])
        XCTAssertEqual(manager.getNames(type: .player).first?.count, 24)

        let relaunchedManager = CommonNamesManager(userDefaults: defaults)
        let repeated = relaunchedManager.applyWatchMutations([conflict, longName, invalidDelete])
        XCTAssertEqual(repeated.results.map(\.status), [.conflict, .applied, .invalid])
        XCTAssertEqual(relaunchedManager.currentRevision, manager.currentRevision)
    }
}
