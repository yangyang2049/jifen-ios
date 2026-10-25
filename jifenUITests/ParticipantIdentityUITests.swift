import XCTest

final class ParticipantIdentityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFilterCanBeClearedAndPersonalPageHidesMainTabs() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestRecordFixtures", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        let records = app.buttons.matching(NSPredicate(format: "label == %@", "记录")).firstMatch
        XCTAssertTrue(records.waitForExistence(timeout: 12)); records.tap()
        let personal = app.buttons["personal_records_entry"]
        XCTAssertTrue(personal.waitForExistence(timeout: 6))
        app.buttons["records_more"].tap()
        app.buttons["筛选"].tap()
        let today = app.buttons["今天"]
        XCTAssertTrue(today.waitForExistence(timeout: 4)); today.tap()
        app.segmentedControls.buttons["计时"].tap()
        let project = app.buttons["records_project_filter_family:badminton"]
        let filterForm = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        XCTAssertTrue(filterForm.waitForExistence(timeout: 4))
        for _ in 0..<18 {
            if project.exists && project.isHittable { break }
            // A short drag inside the form cannot skip whole groups of rows
            // or accidentally swipe the sheet's presentation handle.
            filterForm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: filterForm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        }
        if !project.exists || !project.isHittable {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "项目筛选定位失败"; screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "项目筛选辅助功能层级"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(project.isHittable); project.tap()
        app.buttons["records_apply_filter"].tap()
        let clear = app.buttons["records_clear_filters"], conditions = app.buttons["records_active_conditions"]
        XCTAssertTrue(clear.waitForExistence(timeout: 4))
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        XCTAssertLessThanOrEqual(conditions.frame.maxX, clear.frame.minX)
        XCTAssertTrue(app.staticTexts["没有符合筛选条件的记录"].exists)
        let active = XCTAttachment(screenshot: app.screenshot()); active.name = "筛选状态-左右布局"; active.lifetime = .keepAlways; add(active)
        clear.tap(); XCTAssertFalse(clear.exists)
        personal.tap()
        XCTAssertTrue(app.navigationBars["我的记录"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let mine = XCTAttachment(screenshot: app.screenshot()); mine.name = "我的记录-二级页面"; mine.lifetime = .keepAlways; add(mine)
    }
}
