import XCTest

final class RecordRecapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCloudTableTennisUsesFullRecapTrendAndTimeline() {
        let app = cloudRecordApp("pingpong")
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["record_detail_section_all"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["record_detail_section_sets-0-2"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["score_trend_tab_picker"].exists)
        XCTAssertTrue(app.buttons["分享"].exists)
        XCTAssertTrue(app.buttons["再来一场"].exists)
        let recap = XCTAttachment(screenshot: app.screenshot())
        recap.name = "云端乒乓球-完整概览趋势分局卡片"; recap.lifetime = .keepAlways; add(recap)
        app.segmentedControls.buttons["明细"].tap()
        XCTAssertTrue(app.buttons["record_detail_section_sets-0-2"].exists)
        let timeline = XCTAttachment(screenshot: app.screenshot())
        timeline.name = "云端乒乓球-逐分明细"; timeline.lifetime = .keepAlways; add(timeline)
    }

    func testCloudMultiplayerUsesRankingAndScoreChangeCards() {
        let app = cloudRecordApp("multi_scoreboard")
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["multi_score_record_actions"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["record_not_found"].exists)
        XCTAssertFalse(app.staticTexts["红方"].exists)
        XCTAssertFalse(app.staticTexts["蓝方"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "云端多人记录-排名与分数变化卡片"; shot.lifetime = .keepAlways; add(shot)
    }

    private func cloudRecordApp(_ project: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints", "-UITestRecordFixtures", "-UITestRecordDetail", project, "-UITestCloudRecordDetail"]
        return app
    }

    /// The same identifier-driven flow runs on both iPhone and iPad test
    /// destinations. It also exercises the largest accessibility text size in
    /// Chinese and English so the phone scroller and adaptive iPad grid share
    /// one behavioral contract.
    func testFullMatchAndGroupedRecapSwitchInChineseAndEnglish() {
        for configuration in [
            (language: UITestLocale.en.language, locale: UITestLocale.en.locale, fullMatch: "Full Match", details: "Details", secondTrend: "Set 2"),
            (language: UITestLocale.zhHans.language, locale: UITestLocale.zhHans.locale, fullMatch: "全场", details: "明细", secondTrend: "第 2 局"),
            (language: UITestLocale.zhHant.language, locale: UITestLocale.zhHant.locale, fullMatch: "全場", details: "明細", secondTrend: "第 2 局")
        ] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", "(\(configuration.language))",
                "-AppleLocale", configuration.locale,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
                "-UITestSkipLegalConsent",
                "-UITestSkipScoreboardUsageHints",
                "-UITestRecordFixtures",
                "-UITestRecordDetail", "pingpong"
            ]
            app.launch()

            let fullMatch = app.buttons["record_detail_section_all"]
            let firstSet = app.buttons["record_detail_section_sets-0-1"]
            let secondSet = app.buttons["record_detail_section_sets-0-2"]
            XCTAssertTrue(fullMatch.waitForExistence(timeout: 8))
            XCTAssertEqual(fullMatch.label, configuration.fullMatch)
            XCTAssertTrue(firstSet.exists)
            XCTAssertTrue(secondSet.exists)

            let trendPicker = app.descendants(matching: .any)["score_trend_tab_picker"]
            XCTAssertTrue(trendPicker.waitForExistence(timeout: 4))
            trendPicker.tap()
            let trendMatches = app.buttons.matching(
                NSPredicate(format: "label == %@", configuration.secondTrend)
            )
            let secondTrend = trendMatches.element(boundBy: 0)
            XCTAssertTrue(secondTrend.waitForExistence(timeout: 4))
            secondTrend.tap()
            let secondTrendChart = app.descendants(matching: .any).matching(
                identifier: "score_trend_chart_sets-0-2-trend-0"
            ).firstMatch
            XCTAssertTrue(secondTrendChart.waitForExistence(timeout: 4))
            XCTAssertTrue(
                String(describing: secondTrendChart.value).contains("20"),
                "Second set should contain its own origin plus the 19 recorded scoring points"
            )

            secondSet.tap()
            XCTAssertTrue(secondSet.isSelected)

            let details = app.segmentedControls.buttons[configuration.details]
            XCTAssertTrue(details.waitForExistence(timeout: 4))
            details.tap()
            XCTAssertTrue(secondSet.exists, "Timeline must reuse the recap grouping selection")

            fullMatch.tap()
            XCTAssertTrue(fullMatch.isSelected)
            app.terminate()
        }
    }

    func testMultiScoreUsesRankingAndScoreChangesWithoutRecapSwitch() {
        for configuration in [
            (language: UITestLocale.en.language, locale: UITestLocale.en.locale, ranking: "Final Ranking", recap: "Recap", details: "Details", trend: "Score Trend"),
            (language: UITestLocale.zhHans.language, locale: UITestLocale.zhHans.locale, ranking: "最终排名", recap: "复盘", details: "明细", trend: "比分趋势"),
            (language: UITestLocale.zhHant.language, locale: UITestLocale.zhHant.locale, ranking: "最終排名", recap: "覆盤", details: "明細", trend: "比分趨勢")
        ] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", "(\(configuration.language))",
                "-AppleLocale", configuration.locale,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
                "-UITestSkipLegalConsent",
                "-UITestSkipScoreboardUsageHints",
                "-UITestRecordFixtures",
                "-UITestRecordDetail", "multi_scoreboard"
            ]
            app.launch()

            XCTAssertTrue(app.staticTexts[configuration.ranking].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["multi_score_record_actions"].waitForExistence(timeout: 4))
            XCTAssertFalse(app.segmentedControls.buttons[configuration.recap].exists)
            XCTAssertFalse(app.segmentedControls.buttons[configuration.details].exists)
            XCTAssertFalse(app.staticTexts[configuration.trend].exists)
            app.terminate()
        }
    }
}
