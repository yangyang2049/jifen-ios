import XCTest
import ScoreCore
@testable import jifen

@MainActor
final class RallySessionStoreTests: XCTestCase {
    private let participants: [SessionParticipant] = [
        .init(id: "left-top", name: "Red A", role: "player"),
        .init(id: "left-bottom", name: "Red B", role: "player"),
        .init(id: "right-top", name: "Blue A", role: "player"),
        .init(id: "right-bottom", name: "Blue B", role: "player")
    ]

    func testPingPongDoublesUsesCrossPlatformSlotOrder() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .pingpongDoubles,
            rules: .pingPong(),
            participants: participants
        )

        XCTAssertEqual(store.state.doubles?.playerNames, ["Red A", "Blue A", "Red B", "Blue B"])
        XCTAssertEqual(store.state.doubles?.serverSlotIndex, 0)
        XCTAssertEqual(store.state.doubles?.receiverSlotIndex, 1)
    }

    func testBadmintonDoublesUsesCrossPlatformSlotOrder() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .badmintonDoubles,
            rules: .badminton(),
            participants: participants
        )

        XCTAssertEqual(store.state.doubles?.playerNames, ["Red A", "Blue A", "Red B", "Blue B"])
        XCTAssertEqual(store.state.doubles?.serverSlotIndex, 2)
        XCTAssertEqual(store.state.doubles?.receiverSlotIndex, 1)
    }

    func testSinglesDoesNotCreateDoublesState() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .pingpong,
            rules: .pingPong()
        )

        XCTAssertNil(store.state.doubles)
    }
}
