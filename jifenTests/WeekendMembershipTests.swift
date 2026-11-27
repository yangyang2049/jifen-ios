import Foundation
import XCTest
@testable import jifen

final class WeekendMembershipTests: XCTestCase {
    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    func testShanghaiWeekendAndOncePerWeekAcrossYearBoundary() throws {
        let thursday = try date("2026-12-31T15:59:59Z")
        let friday = try date("2026-12-31T16:00:00Z")
        let sunday = try date("2027-01-03T15:59:59Z")
        let monday = try date("2027-01-03T16:00:00Z")
        let nextFriday = try date("2027-01-08T00:00:00Z")

        XCTAssertFalse(WeekendMembershipSchedule.canPresent(at: thursday, lastShownAt: nil))
        XCTAssertTrue(WeekendMembershipSchedule.canPresent(at: friday, lastShownAt: nil))
        XCTAssertTrue(WeekendMembershipSchedule.isActive(at: sunday))
        XCTAssertFalse(WeekendMembershipSchedule.isActive(at: monday))
        XCTAssertFalse(WeekendMembershipSchedule.canPresent(at: sunday, lastShownAt: friday))
        XCTAssertFalse(WeekendMembershipSchedule.canPresent(at: friday, lastShownAt: nextFriday))
        XCTAssertTrue(WeekendMembershipSchedule.canPresent(at: nextFriday, lastShownAt: sunday))
    }

    func testOfferingWindowAcceptsJSONIntegersAndFoundationNumbers() throws {
        let start = try date("2026-11-27T09:00:00+08:00")
        let end = start.addingTimeInterval(3600)
        let integers: [String: Any] = [
            "weekend_membership": true,
            "starts_at": Int(start.timeIntervalSince1970),
            "ends_at": Int(end.timeIntervalSince1970)
        ]
        XCTAssertFalse(WeekendMembershipSchedule.isOfferingEnabled(integers, at: start.addingTimeInterval(-1)))
        XCTAssertTrue(WeekendMembershipSchedule.isOfferingEnabled(integers, at: start))
        XCTAssertFalse(WeekendMembershipSchedule.isOfferingEnabled(integers, at: end))

        let fractional: [String: Any] = [
            "weekend_membership": NSNumber(value: true),
            "starts_at": NSNumber(value: start.timeIntervalSince1970 - 0.5),
            "ends_at": end.timeIntervalSince1970 + 0.5
        ]
        XCTAssertTrue(WeekendMembershipSchedule.isOfferingEnabled(fractional, at: end))
    }

    func testOfferingRejectsMalformedWindowAndRequiresWeekendFlag() throws {
        let now = try date("2026-11-27T09:00:00+08:00")
        let monday = try date("2026-11-30T09:00:00+08:00")
        XCTAssertTrue(WeekendMembershipSchedule.isOfferingEnabled(["weekend_membership": true], at: now))
        XCTAssertFalse(WeekendMembershipSchedule.isOfferingEnabled(["weekend_membership": true], at: monday))
        XCTAssertFalse(WeekendMembershipSchedule.isOfferingEnabled([:], at: now))
        XCTAssertFalse(WeekendMembershipSchedule.isOfferingEnabled(["weekend_membership": 1], at: now))
        XCTAssertFalse(WeekendMembershipSchedule.isOfferingEnabled(
            ["weekend_membership": true, "starts_at": 0], at: now
        ))
        for start: Any in [true, "0", Double.nan, Double.infinity, NSNull(), now.timeIntervalSince1970 + 5] {
            XCTAssertFalse(WeekendMembershipSchedule.isOfferingEnabled(
                ["weekend_membership": true, "starts_at": start, "ends_at": now.timeIntervalSince1970 + 4], at: now
            ))
        }
    }

    func testOfferingRequiresOneLifetimePackageForTheExpectedProduct() {
        func isValid(paywall: Bool = true, count: Int = 1, product: String? = "lifetime") -> Bool {
            WeekendMembershipSchedule.matchesPaywall(
                hasPaywall: paywall, packageCount: count, lifetimeProductID: product, expectedProductID: "lifetime"
            )
        }
        XCTAssertTrue(isValid())
        XCTAssertFalse(isValid(paywall: false))
        XCTAssertFalse(isValid(count: 0))
        XCTAssertFalse(isValid(count: 2))
        XCTAssertFalse(isValid(product: nil))
        XCTAssertFalse(isValid(product: "monthly"))
    }

    @MainActor
    func testPublicSDKKeyValidationAndReleaseRejectsTestStore() {
        typealias Configuration = RevenueCatMembership.Configuration
        XCTAssertEqual(Configuration(key: " appl_example123 ", allowsTestStore: false)?.mode, .appStore)
        XCTAssertEqual(Configuration(key: "test_example123", allowsTestStore: true)?.mode, .testStore)
        XCTAssertNil(Configuration(key: "test_example123", allowsTestStore: false))
        for key in [nil, "", "appl_", "appl_***", "sk_example123", "$(JIFEN_REVENUECAT_SDK_KEY)"] {
            XCTAssertNil(Configuration(key: key, allowsTestStore: true))
        }
    }
}
