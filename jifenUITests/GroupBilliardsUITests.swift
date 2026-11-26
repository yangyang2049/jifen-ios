import XCTest
final class GroupBilliardsUITests:XCTestCase {
    private func scrollUp(_ app:XCUIApplication) {
        let bottom=app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY-150 : app.frame.maxY-100
        let origin=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0))
        let start=origin.withOffset(CGVector(dx:app.frame.midX,dy:bottom))
        let end=origin.withOffset(CGVector(dx:app.frame.midX,dy:120))
        start.press(forDuration:0.05,thenDragTo:end)
    }
    func testLaunchUsesSharedSetupAndRequiresMembers() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing",
            "-UITestGroupsFixture", "-UITestGroupsFreshDrafts", "-UITestBilliardsGroup"
        ]
        app.launch()
        let group = app.buttons["group_card_ui-group"]
        XCTAssertTrue(group.waitForExistence(timeout: 15))
        group.tap()
        let start = app.buttons["billiards_start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let first = app.buttons["group_seat_1"]
        let second = app.buttons["group_seat_2"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let confirm = app.buttons["nine_ball_setup_start"]
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertEqual(first.value as? String, "")
        XCTAssertEqual(second.value as? String, "")
        XCTAssertFalse(first.isSelected)
        XCTAssertTrue(app.buttons["nine_ball_setup_help"].exists)
        XCTAssertFalse(app.buttons["billiards_member_ui-a"].exists)
        second.tap()
        let close = app.buttons["group_match_picker_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertGreaterThan(close.frame.midY, app.frame.height * 0.25)
        }
        UITestScreenshotStore.capture(app, name: "billiards-compact-seat-picker", testCase: self)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        second.tap()
        let member = app.buttons["group_member_pick_ui-a"]
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        member.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertEqual(second.value as? String, "甲")
        XCTAssertFalse(confirm.isEnabled)
        first.tap()
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        XCTAssertFalse(member.isEnabled)
        app.buttons["group_member_pick_ui-b"].tap()
        XCTAssertTrue(confirm.isEnabled)
        app.buttons["billiards_variant_chip_snooker"].tap()
        let snooker = app.buttons["sports_setup_start"]
        XCTAssertTrue(snooker.waitForExistence(timeout: 5))
        XCTAssertFalse(snooker.isEnabled)
    }

    func testCreationNoticePreservesDraftUntilConfirmed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-UITestGroupsFixture", "-UITestGroupsFreshDrafts", "-UITestBilliardsGroup"]
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
        // 品牌名随语言本地化（中文写「全能计分器」），这里不能钉死 iScoreboard。
        XCTAssertTrue(notice.staticTexts.containing(NSPredicate(format: "label MATCHES %@", ".*[0-9]+\\.[0-9]+.*")).firstMatch.exists, "版本号占位符没有被替换")
        notice.buttons["取消"].tap()
        XCTAssertEqual(name.value as? String, "Version club")
        XCTAssertTrue(tile.isSelected)
        create.tap()
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "Retrying creation must show the notice again")
        notice.buttons["继续"].tap()
        XCTAssertFalse(notice.waitForExistence(timeout: 1))
        XCTAssertTrue(name.exists, "The offline fixture blocks writes and keeps the form")
    }

    func testCreateGridAndThreePlayerManualForm() {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","-UITestSkipLegalConsent","-UITestSkipScoreboardUsageHints","-UITestFakeSession","-UITestSportsVoiceMissing","-UITestGroupsFixture","-UITestGroupsFreshDrafts","-UITestBilliardsGroup"]
        app.launch()
        XCTAssertTrue(app.buttons["group_create"].waitForExistence(timeout:15));app.buttons["group_create"].tap()
        XCTAssertTrue(app.textFields["group_name"].waitForExistence(timeout:10))
        let done=app.buttons["group_create_keyboard_done"];if done.waitForExistence(timeout:3){done.tap()}
        let tile=app.buttons["group_create_sport_billiards"]
        XCTAssertTrue(tile.waitForExistence(timeout:5))
        for _ in 0..<6 where !tile.isHittable {scrollUp(app)}
        XCTAssertTrue(tile.isHittable);tile.tap()
        let selected=expectation(for:NSPredicate(format:"selected == true"),evaluatedWith:tile);wait(for:[selected],timeout:5)
        // iOS 26/27 的系统返回键在 XCUI 里不再以 Button 暴露（automation type mismatch），
        // 重新启动应用回到小组列表比依赖返回键更稳定，且不影响后续台球内页断言。
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["group_card_ui-group"].waitForExistence(timeout: 15))
        app.buttons["group_card_ui-group"].tap()
        let manual=app.buttons["billiards_manual"];XCTAssertTrue(manual.waitForExistence(timeout:10));manual.tap()
        // 一步式：底栏直接进配置页，不再有「先选玩法」弹层。
        XCTAssertFalse(app.buttons["billiards_pick_next"].waitForExistence(timeout:2), "不应再有玩法选择弹层")
        for group in ["nine_ball","eight_ball","snooker","standard"] {
            XCTAssertTrue(app.buttons["billiards_variant_chip_"+group].waitForExistence(timeout:10), "缺少玩法组 chip: "+group)
        }
        UITestScreenshotStore.capture(app, name: "billiards-manual-choices", testCase: self)
        // 九球的民间 / 比赛积分是页内分段，人数分段只在民间出现。
        XCTAssertTrue(app.buttons["billiards_family_folk"].exists);XCTAssertTrue(app.buttons["billiards_family_tournament"].exists)
        let count=app.buttons["billiards_count_3"];XCTAssertTrue(count.waitForExistence(timeout:5));count.tap()
        let third=app.buttons["billiards_seat_2"];for _ in 0..<8 where !third.isHittable{scrollUp(app)}
        XCTAssertTrue(third.exists)
        let submit=app.buttons["billiards_submit"];for _ in 0..<8 where !submit.isHittable{scrollUp(app)}
        // 席位没选齐：主按钮禁用，文案变成「选择第 N 位参赛者」。
        XCTAssertFalse(submit.isEnabled)
        // 普通台球没有任何可调规则：整块「规则设置」不出现。
        let standard=app.buttons["billiards_variant_chip_standard"]
        for _ in 0..<8 where !standard.isHittable{scrollUp(app)}
        standard.tap()
        XCTAssertFalse(app.buttons["billiards_rules_toggle"].exists, "普通台球不应出现规则设置")
        XCTAssertFalse(app.buttons["billiards_family_folk"].exists, "普通台球不应出现九球分段")
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="three-player-group-manual";attachment.lifetime = .keepAlways;add(attachment)
    }

    func testSignedScorePanelKeepsUnbalancedResultDisabledAtLargestTextSize() {
        checkSignedScorePanel(largeText: true)
    }

    func testSignedScorePanelFitsCompactHeight() {
        checkSignedScorePanel(largeText: false)
    }

    private func checkSignedScorePanel(largeText: Bool) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing",
            "-UITestGroupsFixture", "-UITestGroupsFreshDrafts", "-UITestBilliardsGroup",
            "-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge" : "UICTContentSizeCategoryL"
        ]
        app.launch()
        let group = app.buttons["group_card_ui-group"]
        XCTAssertTrue(group.waitForExistence(timeout: 15)); group.tap()
        let manual = app.buttons["billiards_manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10)); manual.tap()

        func tapVisible(_ id: String, avoidFooter: Bool = true) {
            let button = app.buttons[id]
            let footer = app.buttons["billiards_submit"]
            for _ in 0..<10 {
                let clearOfFooter = !avoidFooter || !footer.exists || button.frame.maxY <= footer.frame.minY
                if button.isHittable && clearOfFooter { break }
                scrollUp(app)
            }
            XCTAssertTrue(button.isHittable, id)
            if avoidFooter, footer.exists {
                XCTAssertLessThanOrEqual(button.frame.maxY, footer.frame.minY, "\(id) is covered by the sticky footer")
            }
            button.tap()
        }

        tapVisible("billiards_variant_chip_nine_ball")
        tapVisible("billiards_family_folk")
        tapVisible("billiards_member_ui-a")
        tapVisible("billiards_member_ui-b")
        let submit = app.buttons["billiards_submit"]
        XCTAssertTrue(submit.isEnabled)
        tapVisible("billiards_score_0")
        XCTAssertTrue(app.buttons["billiards_score_key_5"].waitForExistence(timeout: 5))
        if !largeText {
            let panel = app.scrollViews["billiards_score_panel"]
            XCTAssertTrue(panel.exists)
            XCTAssertLessThan(panel.frame.height, app.frame.height * 0.75)
            XCTAssertTrue(app.buttons["billiards_score_key_done"].isHittable)
        }
        tapVisible("billiards_score_key_5", avoidFooter: false)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = largeText ? "billiards-score-panel-largest-text" : "billiards-score-panel-compact"
        attachment.lifetime = .keepAlways
        add(attachment)
        tapVisible("billiards_score_key_done", avoidFooter: false)
        XCTAssertTrue(app.buttons["billiards_score_key_done"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled)
        tapVisible("billiards_score_1")
        XCTAssertTrue(app.buttons["billiards_score_negative"].waitForExistence(timeout: 5))
        tapVisible("billiards_score_negative", avoidFooter: false)
        tapVisible("billiards_score_key_5", avoidFooter: false)
        tapVisible("billiards_score_key_done", avoidFooter: false)
        XCTAssertTrue(submit.isEnabled)
    }

}
