import XCTest

/// zh-Hant smoke coverage kept deliberately small: full copy QA runs the
/// LocalizationIntegrity gates, these tests only prove the Traditional
/// resource bundle actually resolves at runtime and no simplified copy leaks
/// into the primary chrome.
final class ZhHantSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchTraditionalApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += UITestLocale.launchArguments(UITestLocale.zhHant) + [
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        return app
    }

    private func anyElement(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
    }

    func testTabBarRendersTraditionalWithoutSimplifiedLeak() {
        let app = launchTraditionalApp()
        defer { app.terminate() }

        for label in ["首頁", "計分", "記錄"] {
            XCTAssertTrue(
                anyElement(app, label).waitForExistence(timeout: 8),
                "Missing Traditional tab label: \(label)"
            )
        }
        for simplified in ["首页", "计分", "记录"] {
            XCTAssertFalse(
                anyElement(app, simplified).exists,
                "Simplified tab label leaked: \(simplified)"
            )
        }
    }

    func testBadmintonSetupShowsTraditionalMatchFeatureCards() {
        let app = launchTraditionalApp()
        defer { app.terminate() }

        XCTAssertTrue(anyElement(app, "計分").waitForExistence(timeout: 8))
        tapScoreTab(app)

        let card = app.descendants(matching: .any)["scoreboard_catalog_badminton"]
        XCTAssertTrue(scrollUntilVisible(card, in: app), "Badminton catalog card missing")
        card.tap()

        XCTAssertTrue(anyElement(app, "比賽功能").waitForExistence(timeout: 5))
        XCTAssertFalse(anyElement(app, "比赛功能").exists, "Simplified section header leaked")
        // Badminton renders feature cards, not the single-switch time row.
        XCTAssertTrue(anyElement(app, "自動換邊").waitForExistence(timeout: 3))
        XCTAssertTrue(anyElement(app, "語音播報").waitForExistence(timeout: 3))
        XCTAssertFalse(anyElement(app, "自动换边").exists, "Simplified feature card leaked")
    }

    func testTableTennisKeyPointBadgeUsesTraditionalTerm() {
        let app = launchTraditionalApp()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        XCTAssertTrue(anyElement(app, "計分").waitForExistence(timeout: 8))
        tapScoreTab(app)
        let card = app.descendants(matching: .any)["scoreboard_catalog_pingpong"]
        XCTAssertTrue(scrollUntilVisible(card, in: app))
        card.tap()

        let start = app.buttons["開始"]
        XCTAssertTrue(start.waitForExistence(timeout: 4), "Setup start button not found")
        start.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["scoreboard_back_button"].waitForExistence(timeout: 10)
        )

        // 10-0 to 11: the leader is one point from the set, so the badge shows.
        // Ping-pong has no mid-game interval that would stall scripted taps.
        for _ in 0..<10 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let badge = app.descendants(matching: .any)["scoreboard_key_point_badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 6), "Key point badge did not appear at 10-0")
        // The identifier lives on the badge container; match the copy by label.
        XCTAssertTrue(
            anyElement(app, "局點").waitForExistence(timeout: 3) || anyElement(app, "賽點").exists,
            "Badge copy is not Traditional Chinese"
        )
        XCTAssertFalse(anyElement(app, "局点").exists, "Simplified key point leaked")
    }

    private func tapScoreTab(_ app: XCUIApplication) {
        let button = app.tabBars.buttons["計分"]
        (button.exists ? button : anyElement(app, "計分")).tap()
    }

    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.waitForExistence(timeout: 2), element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }
}
