import XCTest

/// Exercises page/sheet boundaries and local drafts without sending a write request.
final class GroupAlignedFormsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testCreateAndJoinUsePages() {
        let app = launch()
        tap("group_create", app)
        XCTAssertTrue(app.textFields["group_name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modal_close_button"].exists)
        XCTAssertFalse(app.buttons["group_create_submit"].isEnabled)
        screenshot("01-create-page", app)
        back(app)
        tap("group_join", app)
        XCTAssertTrue(app.textFields["group_number"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modal_close_button"].exists)
        screenshot("10-join-page", app)
        back(app)
        XCTAssertTrue(app.buttons["group_create"].exists)
    }

    func testMemberAndReportSheetsAndProfilePage() {
        let app = openGroup()
        tap("小组管理", app); tap("group_menu_editProfile", app)
        XCTAssertTrue(app.textFields["group_edit_name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modal_close_button"].exists)
        XCTAssertTrue(app.buttons["group_management_submit"].isHittable)
        XCTAssertEqual(app.buttons["group_management_submit"].label, "保存")
        screenshot("02-profile-page", app)
        back(app)
        tap("小组管理", app); tap("group_menu_report", app)
        XCTAssertTrue(app.buttons["group_report_submit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modal_close_button"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group_report_reason_")).count, 7)
        screenshot("09-report-sheet", app)
        tap("modal_close_button", app)
        tap("group_tab_2", app); screenshot("13-records", app)
        tap("group_tab_3", app)
        reveal("group_add_temporary", app)
        screenshot("12-members", app)
        tap("group_add_temporary", app)
        let names = app.descendants(matching: .any)["group_temporary_names"].firstMatch
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modal_close_button"].exists)
        XCTAssertTrue(app.buttons["取消"].exists)
        XCTAssertFalse(app.buttons["group_management_submit"].isEnabled)
        names.tap(); names.typeText("新成员甲\n新成员乙")
        XCTAssertTrue(app.buttons["group_management_submit"].isEnabled)
        app.swipeUp()
        screenshot("08-temporary-sheet-draft", app)
        tap("modal_close_button", app)
        XCTAssertTrue(app.buttons["group_tab_3"].exists)
    }

    func testOverviewHostsSharedSetupAndManualKeepsItsForm() {
        let app = openGroup()
        tap("group_overview_start", app)
        XCTAssertTrue(app.descendants(matching: .any)["group_seat_A1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modal_close_button"].exists)
        let start = app.buttons["sports_setup_start"]
        let watchStart = app.buttons["sports_setup_watch_start"]
        XCTAssertFalse(start.isEnabled)
        XCTAssertFalse(watchStart.exists)
        XCTAssertFalse(app.switches["每球得分"].exists)
        XCTAssertFalse(app.buttons["setup_pickleball_rally_scoring"].exists)
        screenshot("04-start-page-empty-roster", app)
        tap("group_seat_A1", app); tap("group_member_pick_ui-a", app)
        XCTAssertFalse(start.isEnabled)
        tap("group_seat_B1", app); tap("group_member_pick_ui-b", app)
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(watchStart.exists)
        screenshot("04-start-page-inline-roster", app)
        app.buttons["取消"].tap()
        tap("group_overview_addResult", app)
        XCTAssertTrue(app.buttons["group_match_submit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modal_close_button"].exists)
        XCTAssertFalse(app.buttons["group_match_submit"].isEnabled)
        screenshot("05-result-page", app)
        openManualRules(app)
        XCTAssertFalse(app.switches["净胜两分"].exists)
        XCTAssertFalse(app.switches["每球得分"].exists)
        XCTAssertFalse(app.buttons["每球得分"].exists)
        XCTAssertFalse(app.buttons["发球方得分"].exists)
    }

    func testOnlyPickleballOffersScoringModeInDirectStartAndManualResult() {
        let app = openGroup(["-UITestMatchSetupSport", "pickleball"])
        tap("group_overview_start", app)
        reveal("setup_pickleball_rally_scoring", app)
        let directRally = app.buttons["setup_pickleball_rally_scoring"]
        let directServer = app.buttons["setup_pickleball_server_scoring"]
        XCTAssertTrue(directRally.isSelected)
        directServer.tap()
        XCTAssertTrue(directServer.isSelected)
        XCTAssertFalse(app.switches["净胜两分"].exists)
        app.buttons["取消"].tap()

        tap("group_overview_addResult", app)
        openManualRules(app)
        reveal("发球方得分", app)
        let manualRally = app.buttons["每球得分"]
        let manualServer = app.buttons["发球方得分"]
        XCTAssertTrue(manualRally.exists)
        XCTAssertTrue(manualRally.isSelected)
        manualServer.tap()
        XCTAssertTrue(manualServer.isSelected)
        XCTAssertFalse(app.switches["每球得分"].exists)
        XCTAssertFalse(app.switches["净胜两分"].exists)
    }

    private func openManualRules(_ app: XCUIApplication) {
        reveal("group_match_rules_summary", app)
        tap("group_match_rules_summary", app)
        XCTAssertTrue(app.buttons["项目默认"].waitForExistence(timeout: 5))
    }

    func testActivityAndLineupPagesKeepRegistrationSheet() {
        let app = openGroup(["-UITestGroupsMulti"])
        tap("group_tab_1", app); tap("group_activity_create", app)
        XCTAssertTrue(app.textFields["group_activity_title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modal_close_button"].exists)
        XCTAssertTrue(app.buttons["group_activity_save"].isEnabled)
        screenshot("03-activity-form-page", app)
        back(app)
        tap("周末羽毛球", app)
        XCTAssertTrue(app.buttons["group_activity_registration_manage"].waitForExistence(timeout: 5))
        screenshot("11-activity-detail-page", app)
        tap("group_activity_registration_manage", app)
        XCTAssertTrue(app.buttons["group_registration_close"].waitForExistence(timeout: 5))
        let member = app.buttons["group_registration_member_ui-b"]
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        member.tap()
        XCTAssertTrue(app.buttons["group_registration_save"].isEnabled)
        screenshot("07-registration-sheet-draft", app)
        tap("group_registration_close", app)
        XCTAssertTrue(app.buttons["group_registration_discard"].waitForExistence(timeout: 5))
        tap("group_registration_discard", app)
        tap("group_activity_lineup_open", app)
        reveal("group_activity_lineup_edit", app); tap("group_activity_lineup_edit", app)
        XCTAssertTrue(app.buttons["group_training_publish"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modal_close_button"].exists)
        screenshot("06-lineup-page", app)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-UITestGroupsFixture", "-UITestGroupsFreshDrafts"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["group_create"].waitForExistence(timeout: 15))
        return app
    }

    private func openGroup(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(extra)
        tap("group_card_ui-group", app)
        XCTAssertTrue(app.buttons["group_tab_0"].waitForExistence(timeout: 10))
        return app
    }

    private func reveal(_ identifier: String, _ app: XCUIApplication) {
        let control = app.descendants(matching: .any)[identifier].firstMatch
        for _ in 0..<6 where !control.isHittable { app.swipeUp() }
        XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
    }

    private func tap(_ identifier: String, _ app: XCUIApplication) {
        let control = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
        control.tap()
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.element(boundBy: app.navigationBars.count - 1).buttons.firstMatch.tap()
    }

    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "aligned-v3-" + name
        image.lifetime = .keepAlways
        add(image)
    }
}
