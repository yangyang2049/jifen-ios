import XCTest
@testable import jifen

final class ScoreboardMenuConfirmStateTests: XCTestCase {
    func testArmThenConfirmExecutes() {
        var state = ScoreboardMenuConfirmState()
        state.prepare(forMenuAction: "reset")
        XCTAssertFalse(state.armOrConfirm(.reset))
        XCTAssertTrue(state.resetConfirming)

        state.prepare(forMenuAction: "reset")
        XCTAssertTrue(state.armOrConfirm(.reset))
        XCTAssertNil(state.pending)
    }

    func testSwitchingConfirmActionReArms() {
        var state = ScoreboardMenuConfirmState()
        state.prepare(forMenuAction: "reset")
        XCTAssertFalse(state.armOrConfirm(.reset))

        state.prepare(forMenuAction: "endGame")
        XCTAssertFalse(state.finishConfirming)
        XCTAssertFalse(state.armOrConfirm(.finish))
        XCTAssertTrue(state.finishConfirming)
        XCTAssertFalse(state.resetConfirming)
    }

    func testNonConfirmActionClearsPending() {
        var state = ScoreboardMenuConfirmState()
        state.prepare(forMenuAction: "exchangeSide")
        XCTAssertFalse(state.armOrConfirm(.exchangeSide))
        XCTAssertTrue(state.exchangeConfirming)

        state.prepare(forMenuAction: "undo")
        XCTAssertNil(state.pending)
    }

    func testEndGameMapsToFinish() {
        XCTAssertEqual(ScoreboardMenuConfirmAction.fromMenuAction("endGame"), .finish)
        XCTAssertEqual(ScoreboardMenuConfirmAction.fromMenuAction("finish"), .finish)
    }

    func testClear() {
        var state = ScoreboardMenuConfirmState()
        _ = state.armOrConfirm(.settleMatch)
        state.clear()
        XCTAssertNil(state.pending)
    }
}
