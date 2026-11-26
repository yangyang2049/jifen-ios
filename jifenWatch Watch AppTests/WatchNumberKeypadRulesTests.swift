import XCTest
@testable import jifenWatch_Watch_App

/// 自定义数字弹层的规则与接入口径（对齐鸿蒙手表 WatchNumberKeypadOverlay）。
final class WatchNumberKeypadRulesTests: XCTestCase {
    // MARK: - 规则

    func testMaxDigitsFollowsUpperBound() {
        XCTAssertEqual(WatchNumberKeypadRules.maxDigits(for: 9), 1)
        XCTAssertEqual(WatchNumberKeypadRules.maxDigits(for: 90), 2)
        XCTAssertEqual(WatchNumberKeypadRules.maxDigits(for: 99), 2)
        XCTAssertEqual(WatchNumberKeypadRules.maxDigits(for: 999), 3)
    }

    func testSanitizeKeepsDigitsDropsLeadingZerosAndClipsLength() {
        XCTAssertEqual(WatchNumberKeypadRules.sanitize("1a2b3", maxDigits: 2), "12")
        XCTAssertEqual(WatchNumberKeypadRules.sanitize("007", maxDigits: 2), "7")
        XCTAssertEqual(WatchNumberKeypadRules.sanitize("0", maxDigits: 2), "")
        XCTAssertEqual(WatchNumberKeypadRules.sanitize("200", maxDigits: 3), "200")
        XCTAssertEqual(WatchNumberKeypadRules.sanitize("-12", maxDigits: 2), "12")
        XCTAssertEqual(WatchNumberKeypadRules.sanitize("", maxDigits: 2), "")
    }

    func testValidationRespectsRangeAndOddRule() {
        XCTAssertTrue(WatchNumberKeypadRules.isValid(1, minValue: 1, maxValue: 99, requiresOdd: true))
        XCTAssertTrue(WatchNumberKeypadRules.isValid(7, minValue: 1, maxValue: 99, requiresOdd: true))
        XCTAssertFalse(WatchNumberKeypadRules.isValid(2, minValue: 1, maxValue: 99, requiresOdd: true))
        XCTAssertFalse(WatchNumberKeypadRules.isValid(101, minValue: 1, maxValue: 99, requiresOdd: false))
        XCTAssertFalse(WatchNumberKeypadRules.isValid(0, minValue: 1, maxValue: 90, requiresOdd: false))
        XCTAssertTrue(WatchNumberKeypadRules.isValid(90, minValue: 1, maxValue: 90, requiresOdd: false))
        XCTAssertTrue(WatchNumberKeypadRules.isValid(999, minValue: 1, maxValue: 999, requiresOdd: false))
    }

    func testValidatedValueRejectsEmptyAndOutOfRangeInput() {
        XCTAssertEqual(WatchNumberKeypadRules.validatedValue("35", minValue: 1, maxValue: 90, requiresOdd: false), 35)
        XCTAssertNil(WatchNumberKeypadRules.validatedValue("", minValue: 1, maxValue: 90, requiresOdd: false))
        XCTAssertNil(WatchNumberKeypadRules.validatedValue("91", minValue: 1, maxValue: 90, requiresOdd: false))
        XCTAssertNil(WatchNumberKeypadRules.validatedValue("4", minValue: 1, maxValue: 9, requiresOdd: true))
        XCTAssertEqual(WatchNumberKeypadRules.validatedValue("5", minValue: 1, maxValue: 9, requiresOdd: true), 5)
    }

    func testCustomIsActiveOnlyForValuesOutsidePresets() {
        XCTAssertFalse(WatchNumberKeypadRules.isCustomActive(value: 3, presets: [1, 3, 5]))
        XCTAssertTrue(WatchNumberKeypadRules.isCustomActive(value: 4, presets: [1, 3, 5]))
        XCTAssertTrue(WatchNumberKeypadRules.isCustomActive(value: 35, presets: [5, 10, 15, 20, 25, 30, 45, 60, 90]))
    }

    func testRangeTextIsLanguageNeutral() {
        XCTAssertEqual(WatchNumberKeypadRules.rangeText(minValue: 1, maxValue: 90), "1–90")
        XCTAssertEqual(WatchNumberKeypadRules.rangeText(minValue: 1, maxValue: 999), "1–999")
    }
}

/// 各项目自定义范围接进草稿后的实际效果。
final class WatchSetupCustomRangeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var preferences: WatchPreferences!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "watch-custom-range-tests")
        defaults.removePersistentDomain(forName: "watch-custom-range-tests")
        preferences = WatchPreferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "watch-custom-range-tests")
        defaults = nil
        preferences = nil
        super.tearDown()
    }

    func testFootballHalfLengthAcceptsArbitraryMinutesWithinRange() {
        for minutes in [1, 35, 44, 89, 90] {
            var draft = WatchSportsSetupDraft(sport: .football, preferences: preferences)
            draft.footballHalfLengthMinutes = WatchSportsSetupDraft.normalizedFootballHalfLengthMinutes(minutes)
            XCTAssertEqual(draft.footballHalfLengthMinutes, minutes)
            XCTAssertEqual(
                WatchScoreboardLaunchConfig(draft: draft).footballHalfLengthSeconds,
                minutes * 60
            )
        }
        XCTAssertEqual(WatchSportsSetupDraft.normalizedFootballHalfLengthMinutes(91), 90)
        XCTAssertEqual(WatchSportsSetupDraft.normalizedFootballHalfLengthMinutes(-5), 1)
    }

    func testSnookerCustomFramesOutsidePresetsStaySelected() {
        var draft = WatchSportsSetupDraft(sport: .snooker, preferences: preferences)
        draft.maxSets = 21
        draft.persistRules(to: preferences)

        let restored = WatchSportsSetupDraft(sport: .snooker, preferences: preferences)
        XCTAssertEqual(restored.maxSets, 21)
        XCTAssertTrue(
            WatchNumberKeypadRules.isCustomActive(
                value: restored.maxSets,
                presets: WatchSportsSetupDraft.snookerFrameOptions
            )
        )
        XCTAssertEqual(WatchScoreboardLaunchConfig(draft: restored).maxSets, 21)
    }

    func testSnookerPresetClearsCustomState() {
        var draft = WatchSportsSetupDraft(sport: .snooker, preferences: preferences)
        draft.maxSets = 21
        draft.maxSets = 7
        XCTAssertFalse(
            WatchNumberKeypadRules.isCustomActive(
                value: draft.maxSets,
                presets: WatchSportsSetupDraft.snookerFrameOptions
            )
        )
    }

    func testEightBallCustomRacksStayVisibleAndClampHandicap() {
        var draft = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        draft.eightBallTargetRacks = 9
        draft.eightBallHandicapBeneficiary = .team1
        draft.eightBallHandicapRacks = 12
        draft.normalizeEightBallHandicap()

        XCTAssertTrue(
            WatchSportsSetupDraft.eightBallRackValues(including: draft.eightBallTargetRacks).contains(9)
        )
        XCTAssertEqual(draft.eightBallHandicapRacks, 8)
        XCTAssertEqual(WatchScoreboardLaunchConfig(draft: draft).eightBallTargetRacks, 9)
    }

    func testBallSportCustomPointsAndSetsFeedLaunchConfig() {
        var badminton = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        badminton.maxSets = 2
        // 奇数限制由弹层拦截，草稿层不做二次夹取，这里只验证取值透传。
        badminton.pointsPerSet = 30
        let badmintonConfig = WatchScoreboardLaunchConfig(draft: badminton)
        XCTAssertEqual(badmintonConfig.pointsPerSet, 30)

        var pingpong = WatchSportsSetupDraft(sport: .pingpong, preferences: preferences)
        pingpong.pointsPerSet = 21
        XCTAssertTrue(pingpong.pingpongPointOptions.contains(21))
        XCTAssertEqual(WatchScoreboardLaunchConfig(draft: pingpong).pointsPerSet, 21)
    }
}
