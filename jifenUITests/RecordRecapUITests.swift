import XCTest

final class RecordRecapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The same identifier-driven flow runs on both iPhone and iPad test
    /// destinations. It also exercises the largest accessibility text size in
    /// Chinese and English so the phone scroller and adaptive iPad grid share
    /// one behavioral contract.
    func testFullMatchAndGroupedRecapSwitchInChineseAndEnglish() {
        for configuration in [
            (language: UITestLocale.en.language, locale: UITestLocale.en.locale, fullMatch: "Full Match", details: "Details", secondTrend: "Game 2"),
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
                String(describing: secondTrendChart.value).contains("4"),
                "Second set should contain its own origin plus three local score points"
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
