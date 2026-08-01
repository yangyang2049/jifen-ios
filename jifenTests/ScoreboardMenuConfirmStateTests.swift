import XCTest
@testable import jifen

@MainActor
final class ScoreboardMenuConfirmStateTests: XCTestCase {
    func testArmThenConfirmExecutes() {
        let state = ScoreboardMenuConfirmState()
        state.prepare(forMenuAction: "reset")
        XCTAssertFalse(state.armOrConfirm(.reset))
        XCTAssertTrue(state.resetConfirming)

        state.prepare(forMenuAction: "reset")
        XCTAssertTrue(state.armOrConfirm(.reset))
        XCTAssertNil(state.pending)
    }

    func testSwitchingConfirmActionReArms() {
        let state = ScoreboardMenuConfirmState()
        state.prepare(forMenuAction: "reset")
        XCTAssertFalse(state.armOrConfirm(.reset))

        state.prepare(forMenuAction: "endGame")
        XCTAssertFalse(state.finishConfirming)
        XCTAssertFalse(state.armOrConfirm(.finish))
        XCTAssertTrue(state.finishConfirming)
        XCTAssertFalse(state.resetConfirming)
    }

    func testNonConfirmActionClearsPending() {
        let state = ScoreboardMenuConfirmState()
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
        let state = ScoreboardMenuConfirmState()
        _ = state.armOrConfirm(.settleMatch)
        state.clear()
        XCTAssertNil(state.pending)
    }

    func testDefaultScoreboardMenuIncludesSharedScreenshotAction() {
        let items = ScoreboardMenuItemBuilder.defaultItems()
        XCTAssertEqual(items.filter { $0.action == "screenshot" }.count, 1)
    }

    func testConfirmationAutomaticallyExpires() async throws {
        let state = ScoreboardMenuConfirmState(confirmationDuration: .milliseconds(20))
        XCTAssertFalse(state.armOrConfirm(.reset))
        XCTAssertTrue(state.resetConfirming)

        try await Task.sleep(for: .milliseconds(40))

        XCTAssertNil(state.pending)
        XCTAssertFalse(state.resetConfirming)
    }

    func testTerminalHoldReleasesAfterConfiguredDelay() async throws {
        let hold = ScoreboardTerminalHold<Int>(duration: .milliseconds(20))
        var released = false

        hold.begin(11) { released = true }
        XCTAssertEqual(hold.value, 11)

        try await Task.sleep(for: .milliseconds(40))

        XCTAssertNil(hold.value)
        XCTAssertTrue(released)
    }

    func testTerminalHoldCancellationDoesNotReleaseStaleTransition() async throws {
        let hold = ScoreboardTerminalHold<Int>(duration: .milliseconds(20))
        var released = false
        hold.begin(11) { released = true }

        hold.cancel()
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertNil(hold.value)
        XCTAssertFalse(released)
    }

    func testScreenshotIsAllowedWhileWatchFollowerScoringIsLocked() {
        XCTAssertTrue(ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked("screenshot"))
        XCTAssertFalse(ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked("undo"))
        XCTAssertFalse(ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked("reset"))
        XCTAssertFalse(ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked("endGame"))
    }

    func testSnookerSettleFrameAppearsAfterEndGame() {
        let items = ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: false,
            showWhistle: false,
            showScreenshot: false,
            showDisplaySettings: false,
            extraItems: [
                ScoreboardMenuItem(
                    title: "结算本局",
                    action: "settleFrame",
                    group: .match
                )
            ]
        )
        let ordered = ScoreboardMenuItemBuilder.orderedMatchItems(
            items.filter { $0.group == .match }
        )

        XCTAssertEqual(ordered.last?.action, "settleFrame")
        XCTAssertLessThan(
            try XCTUnwrap(ordered.firstIndex { $0.action == "endGame" }),
            try XCTUnwrap(ordered.firstIndex { $0.action == "settleFrame" })
        )
    }

    func testReadOnlyLinkedBilliardsDisablesMutatingMenuItemsButKeepsRecordVisible() {
        let items = ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: true,
            showWhistle: false,
            showScreenshot: false,
            showDisplaySettings: true,
            scoringEnabled: false,
            extraItems: [
                ScoreboardMenuItem(title: "记录", action: "frameRecord", group: .match),
                ScoreboardMenuItem(title: "结算本局", action: "settleFrame", group: .match)
            ]
        )

        for action in ["undo", "exchangeSide", "reset", "endGame", "settleFrame"] {
            XCTAssertEqual(items.first { $0.action == action }?.enabled, false)
        }
        XCTAssertEqual(items.first { $0.action == "frameRecord" }?.enabled, true)
        XCTAssertEqual(items.first { $0.action == "displaySettings" }?.enabled, true)
    }
}
