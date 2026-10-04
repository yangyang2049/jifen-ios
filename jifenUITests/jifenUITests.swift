import XCTest

final class jifenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
                "-UITestSkipLegalConsent",
                "-UITestSkipScoreboardUsageHints"
            ]
            app.launch()
        }
    }
}

/// Temporary capture harness for the selected 3D catalog artwork.
final class IconAssetCaptureUITests: XCTestCase {
    func testCaptureSelectedIcons() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints",
            "-UITestScreenshotMode", "1"
        ]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 12))
        UITestScreenshotStore.capture(app, name: "3d_icons_home", testCase: self)

        app.tabBars.buttons["计分"].tap()
        XCTAssertTrue(app.buttons["scoreboard_catalog_badminton"].waitForExistence(timeout: 8))
        UITestScreenshotStore.capture(app, name: "3d_icons_scoreboard", testCase: self)

        app.tabBars.buttons["计时"].tap()
        XCTAssertTrue(app.buttons["timer_dest_go"].waitForExistence(timeout: 8))
        UITestScreenshotStore.capture(app, name: "3d_icons_timer", testCase: self)

        app.terminate()
        app.launchArguments.append("-UITestOpenTools")
        app.launch()
        XCTAssertTrue(app.buttons["tool_card_flip_coin"].waitForExistence(timeout: 10))
        UITestScreenshotStore.capture(app, name: "3d_icons_tools", testCase: self)
    }
}
