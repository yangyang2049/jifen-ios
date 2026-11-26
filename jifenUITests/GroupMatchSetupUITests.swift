import XCTest

/// 小组活动排阵后「开始计分」：四个球类 × 单双打复用本机 Setup 定稿控件。
final class GroupMatchSetupUITests: XCTestCase {
    private static let sports = ["badminton", "table_tennis", "tennis", "pickleball"]

    func testActivityStartScoringShowsFinalizedSetupForEverySportAndFormat() {
        for sport in Self.sports {
            for format in ["doubles", "singles"] {
                let app = launch(sport: sport, singles: format == "singles")
                openActivityMatchSetup(app, format: format)
                assertFinalizedSetupControls(app, sport: sport, format: format)
                capture(app, "activity-match-setup-\(sport)-\(format)")
                app.terminate()
            }
        }
    }

    func testMatchCompletionMenuKeepsClassicAndPlayAllNextToSetCount() {
        let app = launch(sport: "badminton", singles: false)
        openActivityMatchSetup(app, format: "doubles")

        let mode = app.buttons["match_completion_mode_selector"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.label.contains("经典"), mode.label)
        XCTAssertTrue(app.buttons["setup_match_sets_3"].exists, "局数预设应与「经典/打满」下拉同一行")

        mode.tap()
        let playAll = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "打满")).firstMatch
        XCTAssertTrue(playAll.waitForExistence(timeout: 5))
        playAll.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "打满")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group_match_submit"].isEnabled)
        capture(app, "activity-match-setup-play-all")
        app.terminate()
    }

    /// 匹克球：居中摘要要同时显示计分方式、净胜两分与封顶，并随 13/15 与计分方式切换同步。
    func testPickleballRuleSummaryFollowsScoringMode() {
        let app = launch(sport: "pickleball", singles: false)
        openActivityMatchSetup(app, format: "doubles")

        let line = app.staticTexts["group_match_setup_rule_line"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        let rallyChip = app.buttons["setup_pickleball_rally_scoring"]
        let serverChip = app.buttons["setup_pickleball_server_scoring"]
        XCTAssertTrue(rallyChip.exists && serverChip.exists, "开赛页用「发球方得分／每球得分」两项选择")
        XCTAssertTrue(rallyChip.isSelected, "小组默认每球得分开启")
        XCTAssertFalse(serverChip.isSelected)
        XCTAssertTrue(line.label.contains("每球得分"), line.label)
        XCTAssertTrue(line.label.contains("净胜两分"), line.label)
        XCTAssertTrue(line.label.contains("15"), line.label)
        XCTAssertTrue(rallyChip.isSelected)
        capture(app, "pickleball-default-rally-15")

        // 13 封顶：选中态与摘要同步。
        let thirteen = app.buttons["13"].firstMatch
        XCTAssertTrue(thirteen.waitForExistence(timeout: 5))
        if !thirteen.isHittable { app.swipeUp() }
        thirteen.tap()
        XCTAssertTrue(thirteen.isSelected, "13 封顶要显示为选中")
        XCTAssertTrue(line.label.contains("13"), line.label)

        // 切到发球方得分：摘要文案立即改写，且所选方仍是发球方选项。
        serverChip.tap()
        XCTAssertTrue(serverChip.isSelected)
        XCTAssertFalse(rallyChip.isSelected)
        let serverText = serverChip.label
        XCTAssertFalse(serverText.isEmpty)
        XCTAssertTrue(line.label.contains(serverText), line.label)
        XCTAssertFalse(line.label.contains("每球得分"), line.label)
        capture(app, "pickleball-server-scoring-13")
        app.terminate()
    }

    func testPickleballTwentyOneCanStillStart() {
        let app = launch(sport: "pickleball", singles: true)
        openActivityMatchSetup(app, format: "singles")
        let target = app.buttons["21"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        XCTAssertTrue(app.buttons["group_match_submit"].isEnabled, "21 分必须能开赛")
        capture(app, "activity-match-setup-pickleball-21")
        app.terminate()
    }

    private func launch(sport: String, singles: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestSportsVoiceMissing",
            "-UITestFakeSession", "-UITestGroupsFixture", "-UITestGroupsMulti",
            "-UITestMatchSetupSport", sport
        ]
        if singles { arguments.append("-UITestGroupsScheduledSingles") }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["group_create"].waitForExistence(timeout: 20))
        return app
    }

    private func openActivityMatchSetup(_ app: XCUIApplication, format: String) {
        tap("group_card_ui-group", app)
        tap("group_tab_1", app)
        tap("周末羽毛球", app)
        tap("group_activity_lineup_open", app)
        let start = app.buttons["开始计分"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "排阵后的场次要能点「开始计分」")
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["group_match_setup_summary"].firstMatch.waitForExistence(timeout: 10),
                      "开赛页应使用定稿赛制区")
    }

    private func assertFinalizedSetupControls(_ app: XCUIApplication, sport: String, format: String) {
        let label = "\(sport)/\(format)"
        XCTAssertTrue(app.descendants(matching: .any)["group_match_setup_summary"].firstMatch.exists, "\(label) 缺少规则摘要")
        XCTAssertTrue(app.buttons["match_completion_mode_selector"].exists, "\(label) 缺少经典/打满下拉")
        XCTAssertTrue(app.buttons["group_match_submit"].isEnabled, "\(label) 开始计分不可用")
        // 发球方只保留文字与两侧项目图标。
        XCTAssertTrue(app.staticTexts["发球方"].exists, "\(label) 缺少发球方文字")
        if sport == "tennis" {
            XCTAssertTrue(app.buttons["标准赛制"].exists || app.buttons["常规"].exists, "\(label) 缺少网球赛制切换")
            XCTAssertFalse(app.staticTexts["每局分数"].exists, "网球常规不显示每局分数")
        } else {
            let pointLabel = sport == "pickleball" ? "目标分" : "每局分数"
            XCTAssertTrue(app.staticTexts[pointLabel].exists, "\(label) 缺少 \(pointLabel)")
            if sport == "pickleball" {
                XCTAssertTrue(app.staticTexts["最高分上限"].exists, "匹克球 11 分要能选封顶")
            } else {
                XCTAssertFalse(app.staticTexts["最高分上限"].exists, "\(label) 不显示封顶档位")
            }
        }
        // 席位名称行：单打两行（A1/B1），双打四个位置（A1/A2/B1/B2）。
        let seatIDs = ["group_seat_A1", "group_seat_A2", "group_seat_B1", "group_seat_B2"]
        let visibleSeats = seatIDs.filter { app.descendants(matching: .any)[$0].firstMatch.exists }
        let expectedSeats = format == "singles" ? ["group_seat_A1", "group_seat_B1"] : seatIDs
        XCTAssertEqual(Set(visibleSeats), Set(expectedSeats), "\(label) 席位数量")
        if sport != "tennis" {
            let line = app.staticTexts["group_match_setup_rule_line"].firstMatch
            XCTAssertTrue(line.exists, "\(label) 缺少居中规则摘要")
            XCTAssertTrue(line.label.contains("净胜两分"), line.label)
            if sport != "pickleball" {
                XCTAssertTrue(line.label.contains("每球得分"), line.label)
            }
        }
        // 数字预设是圆角 chip，铅笔 chip 原地变输入框（局数/盘数一定有，网球没有每局分数）。
        XCTAssertTrue(app.buttons["custom_match_sets_button"].exists, "\(label) 缺少局数自定义输入")
        if sport != "tennis" {
            XCTAssertTrue(app.buttons["setup_custom_points_button"].exists
                          || app.buttons["setup_custom_pickleballTarget_button"].exists,
                          "\(label) 缺少分数自定义输入")
        }
    }

    private func tap(_ identifier: String, _ app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        if !element.waitForExistence(timeout: 10) || !element.isHittable {
            for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), identifier)
        element.tap()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
