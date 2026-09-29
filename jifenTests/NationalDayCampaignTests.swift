import XCTest
@testable import jifen

// 国庆会员活动策略（对齐安卓 NationalDayCampaignPolicyTest 的验收口径）：
// 北京时间窗口、72 小时冷却、展示前持久化互斥。
@MainActor
final class NationalDayCampaignTests: XCTestCase {
    private var beijingCalendar: Calendar { NationalDayCampaignPolicy.beijingCalendar }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        beijingCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - 活动窗口（北京时间，与设备时区无关）

    func testWindowCoversOctober1ToOctober7ExclusiveOfOctober8() {
        // 北京时间 10-1 00:00 含、10-8 00:00 不含。
        XCTAssertTrue(NationalDayCampaignPolicy.isActive(now: date(2026, 10, 1)))
        XCTAssertTrue(NationalDayCampaignPolicy.isActive(now: date(2026, 10, 7, 23, 59)))
        XCTAssertFalse(NationalDayCampaignPolicy.isActive(now: date(2026, 9, 30, 23, 59)))
        XCTAssertFalse(NationalDayCampaignPolicy.isActive(now: date(2026, 10, 8)))
        XCTAssertFalse(NationalDayCampaignPolicy.isActive(now: date(2027, 10, 3)))
    }

    func testWindowUsesBeijingTimeRegardlessOfDeviceTimeZone() {
        // 同一时刻用 UTC 日历表达：UTC 9-30 17:00 = 北京 10-1 01:00，应视为活动中；
        // UTC 10-7 16:00 = 北京 10-8 00:00，活动已结束。
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertTrue(NationalDayCampaignPolicy.isActive(
            now: utc.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 17))!
        ))
        XCTAssertFalse(NationalDayCampaignPolicy.isActive(
            now: utc.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 16))!
        ))
    }

    // MARK: - 72 小时冷却

    func testShouldOfferRequiresSeventyTwoHoursSinceLastShow() {
        let firstShow = date(2026, 10, 1, 9)
        XCTAssertFalse(NationalDayCampaignPolicy.shouldOffer(
            now: firstShow.addingTimeInterval(71 * 3600),
            lastShownAt: firstShow,
            isLifetimeMember: false,
            purchaseAvailable: true
        ))
        XCTAssertTrue(NationalDayCampaignPolicy.shouldOffer(
            now: firstShow.addingTimeInterval(72 * 3600),
            lastShownAt: firstShow,
            isLifetimeMember: false,
            purchaseAvailable: true
        ))
    }

    func testShouldOfferExcludesLifetimeMembersAndUnavailablePurchases() {
        XCTAssertFalse(NationalDayCampaignPolicy.shouldOffer(
            now: date(2026, 10, 3),
            lastShownAt: nil,
            isLifetimeMember: true,
            purchaseAvailable: true
        ))
        XCTAssertFalse(NationalDayCampaignPolicy.shouldOffer(
            now: date(2026, 10, 3),
            lastShownAt: nil,
            isLifetimeMember: false,
            purchaseAvailable: false
        ))
        XCTAssertTrue(NationalDayCampaignPolicy.shouldOffer(
            now: date(2026, 10, 3),
            lastShownAt: nil,
            isLifetimeMember: false,
            purchaseAvailable: true
        ))
    }

    func testShouldOfferIgnoresStaleClockRegression() {
        let lastShown = date(2026, 10, 3, 12)
        // 设备时间被回拨到 lastShown 之前时不应重复展示。
        XCTAssertFalse(NationalDayCampaignPolicy.shouldOffer(
            now: lastShown.addingTimeInterval(-60),
            lastShownAt: lastShown,
            isLifetimeMember: false,
            purchaseAvailable: true
        ))
    }

    // MARK: - 展示前持久化（NationalDayCampaignPrompt）

    func testReservePersistsBeforeShowingAndBlocksRepeatWithin72Hours() {
        let defaults = UserDefaults(suiteName: "national_day_campaign_tests")!
        defaults.removePersistentDomain(forName: "national_day_campaign_tests")
        let prompt = NationalDayCampaignPrompt(defaults: defaults)
        let firstShow = date(2026, 10, 2, 10)

        XCTAssertTrue(prompt.reserve(now: firstShow))
        // 先落盘再展示：reserve 之后立即 wasShownToday。
        XCTAssertTrue(prompt.wasShownToday(now: firstShow))
        XCTAssertEqual(prompt.lastShownAt, firstShow)
        // 进程重启（新实例、同一持久化）后当天不重弹。
        let reopened = NationalDayCampaignPrompt(defaults: defaults)
        XCTAssertTrue(reopened.wasShownToday(now: firstShow.addingTimeInterval(3600)))
        XCTAssertFalse(reopened.reserve(now: firstShow.addingTimeInterval(3600)))
        // 满 72 小时后恢复展示资格。
        XCTAssertTrue(reopened.reserve(now: firstShow.addingTimeInterval(72 * 3600)))
    }

    func testWasShownTodayComparesBeijingCalendarDay() {
        let defaults = UserDefaults(suiteName: "national_day_campaign_tests_day")!
        defaults.removePersistentDomain(forName: "national_day_campaign_tests_day")
        let prompt = NationalDayCampaignPrompt(defaults: defaults)
        // 北京时间 10-2 23:00 展示后，北京时间 10-3 01:00 仍是「已展示过」状态（同日检查按北京日历）。
        _ = prompt.reserve(now: date(2026, 10, 2, 23))
        XCTAssertFalse(prompt.reserve(now: date(2026, 10, 3, 1)))
    }

    // MARK: - 设备语言门控（仅简体中文设备展示）

    func testGateOnlyMatchesSimplifiedChineseDeviceLanguage() {
        XCTAssertTrue(NationalDayCampaignGate.deviceUsesSimplifiedChinese(preferredLanguages: ["zh-Hans-CN", "en"]))
        XCTAssertTrue(NationalDayCampaignGate.deviceUsesSimplifiedChinese(preferredLanguages: ["zh-Hans", "en"]))
        XCTAssertTrue(NationalDayCampaignGate.deviceUsesSimplifiedChinese(preferredLanguages: ["zh_CN"]))
        XCTAssertFalse(NationalDayCampaignGate.deviceUsesSimplifiedChinese(preferredLanguages: ["zh-Hant-TW", "en"]))
        XCTAssertFalse(NationalDayCampaignGate.deviceUsesSimplifiedChinese(preferredLanguages: ["en", "zh-Hans-CN"]))
        XCTAssertFalse(NationalDayCampaignGate.deviceUsesSimplifiedChinese(preferredLanguages: []))
    }
}
