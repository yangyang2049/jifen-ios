import XCTest
final class GroupBilliardsUITests:XCTestCase {
    private func scrollUp(_ app:XCUIApplication) {
        let bottom=app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY-150 : app.frame.maxY-100
        let origin=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0))
        let start=origin.withOffset(CGVector(dx:app.frame.midX,dy:bottom))
        let end=origin.withOffset(CGVector(dx:app.frame.midX,dy:120))
        start.press(forDuration:0.05,thenDragTo:end)
    }
    func testCreationNoticePreservesDraftUntilConfirmed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-UITestGroupsFixture", "-UITestGroupsFreshDrafts", "-UITestBilliardsGroup", "-national_day_2026_10_autopopup_count", "99"]
        app.launch()
        XCTAssertTrue(app.buttons["group_create"].waitForExistence(timeout: 15))
        app.buttons["group_create"].tap()
        let name = app.textFields["group_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Version club")
        let done = app.buttons["group_create_keyboard_done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        let tile = app.buttons["group_create_sport_billiards"]
        for _ in 0..<6 where !tile.isHittable { scrollUp(app) }
        tile.tap()
        XCTAssertEqual(app.alerts.count, 0, "Selecting billiards must not show the notice")
        let create = app.buttons["group_create_submit"]
        create.tap()
        let notice = app.alerts["台球小组版本提示"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        // 文案里的版本号来自 CFBundleShortVersionString，测试不再钉死具体版本，只校验占位符已正确替换。
        XCTAssertTrue(notice.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "iScoreboard")).firstMatch.exists)
        XCTAssertTrue(notice.staticTexts.containing(NSPredicate(format: "label MATCHES %@", ".*[0-9]+\\.[0-9]+.*")).firstMatch.exists, "版本号占位符没有被替换")
        notice.buttons["暂不创建"].tap()
        XCTAssertEqual(name.value as? String, "Version club")
        XCTAssertTrue(tile.isSelected)
        create.tap()
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "Retrying creation must show the notice again")
        notice.buttons["继续创建"].tap()
        XCTAssertFalse(notice.waitForExistence(timeout: 1))
        XCTAssertTrue(name.exists, "The offline fixture blocks writes and keeps the form")
    }

    func testCreateGridAndThreePlayerManualForm() {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","-UITestSkipLegalConsent","-UITestSkipScoreboardUsageHints","-UITestFakeSession","-UITestSportsVoiceMissing","-UITestGroupsFixture","-UITestGroupsFreshDrafts","-UITestBilliardsGroup","-national_day_2026_10_autopopup_count","99"]
        app.launch()
        XCTAssertTrue(app.buttons["group_create"].waitForExistence(timeout:15));app.buttons["group_create"].tap()
        XCTAssertTrue(app.textFields["group_name"].waitForExistence(timeout:10))
        let done=app.buttons["group_create_keyboard_done"];if done.waitForExistence(timeout:3){done.tap()}
        let tile=app.buttons["group_create_sport_billiards"]
        XCTAssertTrue(tile.waitForExistence(timeout:5))
        for _ in 0..<6 where !tile.isHittable {scrollUp(app)}
        XCTAssertTrue(tile.isHittable);tile.tap()
        let selected=expectation(for:NSPredicate(format:"selected == true"),evaluatedWith:tile);wait(for:[selected],timeout:5)
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["group_card_ui-group"].tap()
        let manual=app.buttons["billiards_manual"];XCTAssertTrue(manual.waitForExistence(timeout:10));manual.tap()
        let count=app.buttons["billiards_count"];XCTAssertTrue(count.waitForExistence(timeout:5));count.tap()
        app.buttons["3"].firstMatch.tap()
        let third=app.buttons["billiards_seat_2"];for _ in 0..<8 where !third.isHittable{scrollUp(app)}
        XCTAssertTrue(third.exists)
        let submit=app.buttons["billiards_submit"];for _ in 0..<8 where !submit.isHittable{scrollUp(app)}
        XCTAssertFalse(submit.isEnabled)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="three-player-group-manual";attachment.lifetime = .keepAlways;add(attachment)
    }
}
