import ScoreCore
import XCTest
@testable import jifen

/// 任务二：预约开赛透传篮球规则集/节时/加时，并按锁定值预填。
@MainActor
final class BookingBasketballTimingTests: XCTestCase {
    func testSavingAfterSwitchingSportsAndCopyingKeepsLockedTiming() throws {
        let source = LocalBooking(id: "source", sportType: .basketball, dateTime: Date(), location: "Court",
                                  basketballRuleSet: "custom", basketballPeriodDurationSeconds: 1440,
                                  basketballOvertimeDurationSeconds: 240)
        // 编辑表单切换项目后空草稿回退来源；复制预约走相同的保存策略。
        let retained = try XCTUnwrap(BookingBasketballTiming.forSaving(sportType: .basketball, source: source,
                                   ruleSet: nil, periodSeconds: nil, overtimeSeconds: nil))
        XCTAssertEqual(retained, BookingBasketballTiming(ruleSet: .custom, periodSeconds: 1440, overtimeSeconds: 240))
        XCTAssertNil(BookingBasketballTiming.forSaving(sportType: .pickleball, source: source,
                      ruleSet: "custom", periodSeconds: 1200, overtimeSeconds: 180))
        let copied = LocalBooking(id: "copy", sportType: .basketball, dateTime: Date(), location: "Other court",
                                  basketballRuleSet: retained.ruleSet.rawValue,
                                  basketballPeriodDurationSeconds: retained.periodSeconds,
                                  basketballOvertimeDurationSeconds: retained.overtimeSeconds)
        XCTAssertEqual(copied.resolvedBasketballTiming(), retained)
    }

    func testBookingFormCanOverrideSourceWithCustomOrPresetTiming() throws {
        let custom = BookingBasketballTiming.forSaving(sportType: .basketball, source: nil,
                         ruleSet: "custom", periodSeconds: 900, overtimeSeconds: 420)
        XCTAssertEqual(custom, BookingBasketballTiming(ruleSet: .custom, periodSeconds: 900, overtimeSeconds: 420))
        let nba = BookingBasketballTiming.forSaving(sportType: .basketball, source: nil,
                      ruleSet: "nba", periodSeconds: 900, overtimeSeconds: 420)
        XCTAssertEqual(nba, BookingBasketballTiming(ruleSet: .nba, periodSeconds: 720, overtimeSeconds: 300))
        XCTAssertNil(BookingBasketballTiming.forSaving(sportType: .basketball, source: nil,
                         ruleSet: nil, periodSeconds: nil, overtimeSeconds: nil))
    }

    func testChoosingProjectDefaultClearsLockedTimingWhenEditingOrCopying() throws {
        let fixture = try makePreferences()
        defer { fixture.cleanup() }
        fixture.preferences.basketballRuleSet = "nba"

        let source = LocalBooking(id: "source", sportType: .basketball, dateTime: Date(), location: "Court",
                                  basketballRuleSet: "custom", basketballPeriodDurationSeconds: 1440,
                                  basketballOvertimeDurationSeconds: 240)
        for id in [source.id, "copy"] {
            let timing = BookingBasketballTiming.forSaving(
                sportType: .basketball, source: source, ruleSet: nil,
                periodSeconds: 1440, overtimeSeconds: 240, useProjectDefault: true
            )
            XCTAssertNil(timing)
            let saved = LocalBooking(
                id: id, sportType: .basketball, dateTime: source.dateTime, location: source.location,
                basketballRuleSet: timing?.ruleSet.rawValue,
                basketballPeriodDurationSeconds: timing?.periodSeconds,
                basketballOvertimeDurationSeconds: timing?.overtimeSeconds
            )
            XCTAssertNil(saved.basketballRuleSet)
            XCTAssertNil(saved.basketballPeriodDurationSeconds)
            XCTAssertNil(saved.basketballOvertimeDurationSeconds)
            let request = try XCTUnwrap(saved.makeStartRequest(preferences: fixture.preferences))
            XCTAssertEqual(request.setup.basketballRuleSet, "nba")
            XCTAssertEqual(request.setup.basketballPeriodSeconds, 720)
            XCTAssertEqual(request.setup.basketballOvertimeSeconds, 300)
        }
    }

    func testBasketballSummaryHasExactlyOneTimingDescription() {
        let timing = BookingBasketballTiming(ruleSet: .custom, periodSeconds: 1440, overtimeSeconds: 240)
        XCTAssertEqual(timing.localizedSummary, String(format: NSLocalizedString("basketball_record_timing", comment: ""),
                       NSLocalizedString("custom", comment: ""), 24, 4))
    }

    func testClockResetUsesThePreMatchConfiguredDuration() {
        var state = BasketballMatchEngine.initial(leftName: "A", rightName: "B", gameMode: .fiveVFive,
            ruleSet: .custom, periodDurationSeconds: 1200, overtimeDurationSeconds: 180)
        state.gameTimeSeconds = 42
        let reset = BasketballMatchEngine.resetGameClock(state)
        XCTAssertEqual(reset.gameTimeSeconds, 1200)
        XCTAssertEqual(reset.periodDurationSeconds, 1200)
        XCTAssertEqual(reset.overtimeDurationSeconds, 180)
    }

    private func makePreferences() throws -> (preferences: PreferencesManager, cleanup: () -> Void) {
        let suite = "booking-basketball-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preferences = PreferencesManager(defaults: defaults)
        defaults.removePersistentDomain(forName: suite)
        return (preferences, { defaults.removePersistentDomain(forName: suite) })
    }

    private func makeManager() throws -> (manager: LocalBookingManager, cleanup: () -> Void) {
        let suite = "booking-basketball-manager-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let manager = LocalBookingManager(userDefaults: defaults, schedulesNotifications: false)
        return (manager, { defaults.removePersistentDomain(forName: suite) })
    }

    func testLockedCustomTimingPrefillsScheduledStart() throws {
        let fixture = try makePreferences()
        defer { fixture.cleanup() }
        let booking = LocalBooking(
            id: "basketball-custom",
            sportType: .basketball,
            dateTime: Date(),
            location: "Court",
            team1Name: "红",
            team2Name: "蓝",
            basketballRuleSet: "custom",
            basketballPeriodDurationSeconds: 1_200,
            basketballOvertimeDurationSeconds: 180
        )
        let timing = try XCTUnwrap(booking.resolvedBasketballTiming(preferences: fixture.preferences))
        XCTAssertEqual(timing.ruleSet, .custom)
        XCTAssertEqual(timing.periodSeconds, 1_200)
        XCTAssertEqual(timing.overtimeSeconds, 180)

        let request = try XCTUnwrap(booking.makeStartRequest(preferences: fixture.preferences))
        XCTAssertEqual(request.setup.basketballRuleSet, "custom")
        XCTAssertEqual(request.setup.basketballPeriodSeconds, 1_200)
        XCTAssertEqual(request.setup.basketballOvertimeSeconds, 180)
        XCTAssertEqual(request.setup.basketballMode, "five_v_five")
    }

    func testLegacyBookingWithoutLockedTimingUsesFibaDefaults() throws {
        let fixture = try makePreferences()
        defer { fixture.cleanup() }
        let booking = LocalBooking(
            id: "basketball-legacy",
            sportType: .basketball,
            dateTime: Date(),
            location: "Court"
        )
        XCTAssertNil(booking.basketballRuleSet)
        let request = try XCTUnwrap(booking.makeStartRequest(preferences: fixture.preferences))
        XCTAssertEqual(request.setup.basketballRuleSet, "fiba")
        XCTAssertEqual(request.setup.basketballPeriodSeconds, 600)
        XCTAssertEqual(request.setup.basketballOvertimeSeconds, 300)
    }

    func testNonCustomRuleSetIgnoresCustomDurations() throws {
        let fixture = try makePreferences()
        defer { fixture.cleanup() }
        let booking = LocalBooking(
            id: "basketball-nba",
            sportType: .basketball,
            dateTime: Date(),
            location: "Court",
            basketballRuleSet: "nba",
            basketballPeriodDurationSeconds: 1_200,
            basketballOvertimeDurationSeconds: 180
        )
        let request = try XCTUnwrap(booking.makeStartRequest(preferences: fixture.preferences))
        // NBA 固定 12 分钟、加时 5 分钟，自定义时长只在 custom 规则集下生效。
        XCTAssertEqual(request.setup.basketballRuleSet, "nba")
        XCTAssertEqual(request.setup.basketballPeriodSeconds, 720)
        XCTAssertEqual(request.setup.basketballOvertimeSeconds, 300)
    }

    func testInvalidTimingValuesAreDroppedInsteadOfLeakingDefaults() {
        let booking = LocalBooking(
            id: "basketball-invalid",
            sportType: .basketball,
            dateTime: Date(),
            location: "Court",
            basketballRuleSet: " FIBA ",
            basketballPeriodDurationSeconds: 90,
            basketballOvertimeDurationSeconds: 7_200
        )
        XCTAssertEqual(booking.basketballRuleSet, "fiba")
        XCTAssertNil(booking.basketballPeriodDurationSeconds)
        XCTAssertNil(booking.basketballOvertimeDurationSeconds)

        let unknown = LocalBooking(
            id: "basketball-unknown",
            sportType: .basketball,
            dateTime: Date(),
            location: "Court",
            basketballRuleSet: "wnba"
        )
        XCTAssertNil(unknown.basketballRuleSet)
    }

    func testNonBasketballBookingNeverPersistsBasketballTiming() {
        let booking = LocalBooking(
            id: "pickleball-1",
            sportType: .pickleball,
            dateTime: Date(),
            location: "Court",
            basketballRuleSet: "custom",
            basketballPeriodDurationSeconds: 1_200,
            basketballOvertimeDurationSeconds: 180
        )
        XCTAssertNil(booking.basketballRuleSet)
        XCTAssertNil(booking.basketballPeriodDurationSeconds)
        XCTAssertNil(booking.basketballOvertimeDurationSeconds)
        XCTAssertNil(booking.resolvedBasketballTiming())
    }

    func testCodableRoundTripKeepsTimingAndLegacyPayloadDecodesWithoutIt() throws {
        let booking = LocalBooking(
            id: "basketball-codable",
            sportType: .basketball,
            dateTime: Date(timeIntervalSince1970: 1_700_000_000),
            location: "Court",
            basketballRuleSet: "custom",
            basketballPeriodDurationSeconds: 1_440,
            basketballOvertimeDurationSeconds: 240,
            // ISO 8601 存储按秒精度，固定创建/更新时间，避免默认 Date() 的亚秒差异。
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(LocalBooking.self, from: encoder.encode(booking))
        XCTAssertEqual(restored, booking)
        XCTAssertEqual(restored.basketballPeriodDurationSeconds, 1_440)
        XCTAssertEqual(restored.basketballOvertimeDurationSeconds, 240)

        let legacy = """
        {
          "id": "legacy-basketball",
          "sportType": "basketball",
          "dateTime": "2026-01-01T08:00:00Z",
          "durationMinutes": 90,
          "location": "Court",
          "gameFormat": "",
          "participantNames": [],
          "notes": "",
          "reminderMinutes": [15],
          "status": "pending",
          "createdAt": "2026-01-01T08:00:00Z",
          "updatedAt": "2026-01-01T08:00:00Z"
        }
        """
        let decodedLegacy = try decoder.decode(LocalBooking.self, from: Data(legacy.utf8))
        XCTAssertNil(decodedLegacy.basketballRuleSet)
        XCTAssertNil(decodedLegacy.basketballPeriodDurationSeconds)
        XCTAssertNil(decodedLegacy.basketballOvertimeDurationSeconds)
    }

    func testLockBasketballSetupWritesBackResolvedTiming() throws {
        let fixture = try makeManager()
        defer { fixture.cleanup() }
        let booking = LocalBooking(
            id: "lock-me",
            sportType: .basketball,
            dateTime: Date(),
            location: "Court"
        )
        XCTAssertTrue(fixture.manager.upsertBooking(booking))

        var setup = SportsSetupResult(team1Name: "红", team2Name: "蓝")
        setup.basketballMode = "five_v_five"
        setup.basketballRuleSet = "custom"
        setup.basketballPeriodSeconds = 900
        setup.basketballOvertimeSeconds = 420
        XCTAssertTrue(fixture.manager.lockBasketballSetup(booking.id, setup: setup))

        let locked = try XCTUnwrap(fixture.manager.getBooking(by: booking.id))
        XCTAssertEqual(locked.basketballRuleSet, "custom")
        XCTAssertEqual(locked.basketballPeriodDurationSeconds, 900)
        XCTAssertEqual(locked.basketballOvertimeDurationSeconds, 420)
        XCTAssertEqual(locked.resolvedBasketballTiming()?.periodSeconds, 900)
        XCTAssertEqual(locked.resolvedBasketballTiming()?.overtimeSeconds, 420)

        // 再次开赛应读数不变（幂等），不应刷新 updatedAt。
        let before = locked.updatedAt
        XCTAssertTrue(fixture.manager.lockBasketballSetup(booking.id, setup: setup))
        XCTAssertEqual(fixture.manager.getBooking(by: booking.id)?.updatedAt, before)
    }

    func testLockBasketballSetupIgnoresNonBasketballAndEmptyRuleSet() throws {
        let fixture = try makeManager()
        defer { fixture.cleanup() }
        let booking = LocalBooking(
            id: "pickleball-lock",
            sportType: .pickleball,
            dateTime: Date(),
            location: "Court"
        )
        XCTAssertTrue(fixture.manager.upsertBooking(booking))

        var setup = SportsSetupResult(team1Name: "A", team2Name: "B")
        setup.basketballRuleSet = "custom"
        setup.basketballPeriodSeconds = 900
        XCTAssertFalse(fixture.manager.lockBasketballSetup(booking.id, setup: setup))

        var empty = SportsSetupResult(team1Name: "A", team2Name: "B")
        empty.basketballRuleSet = ""
        XCTAssertFalse(fixture.manager.lockBasketballSetup(booking.id, setup: empty))
        XCTAssertFalse(fixture.manager.lockBasketballSetup("", setup: setup))
        XCTAssertNil(fixture.manager.getBooking(by: booking.id)?.basketballRuleSet)
    }
}
