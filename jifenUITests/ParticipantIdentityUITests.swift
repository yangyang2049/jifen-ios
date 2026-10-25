import XCTest

final class ParticipantIdentityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPersonalEntryHidesWhileSearchingAndReturnsAfterCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestRecordFixtures",
            "-national_day_2026_last_shown_at", String(Date().timeIntervalSince1970)]
        app.launch()
        defer { app.terminate() }
        app.descendants(matching: .any)["main_tab_1"].firstMatch.tap()
        let personal = app.buttons["personal_records_entry"]
        XCTAssertTrue(personal.waitForExistence(timeout: 6))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(personal.waitForNonExistence(timeout: 5))
        search.typeText("不存在的项目")
        XCTAssertFalse(personal.exists)
        // Native search dismissal uses different accessibility roles on iPhone and iPad.
        let closeSearch = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["取消", "关闭", "Cancel", "Close"])).firstMatch
        if closeSearch.exists {
            closeSearch.tap()
        } else {
            // iPad keeps search inline without a cancel control.
            search.buttons["清除文本"].tap()
            let hideKeyboard = app.buttons["隐藏键盘"]
            if hideKeyboard.exists { hideKeyboard.tap() }
        }
        XCTAssertTrue(personal.waitForExistence(timeout: 5), app.debugDescription)
        personal.tap()
        XCTAssertTrue(app.navigationBars["我的记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields.firstMatch.exists)
    }

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
