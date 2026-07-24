import XCTest
@testable import jifen

final class AppReviewPromptTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppReviewPromptTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRequestBecomesEligibleOnFifthLaunch() {
        for _ in 0..<4 {
            AppReviewPrompt.recordLaunch(defaults: defaults)
            XCTAssertFalse(
                AppReviewPrompt.consumePendingRequest(
                    defaults: defaults,
                    launchThreshold: 5
                )
            )
        }

        AppReviewPrompt.recordLaunch(defaults: defaults)
        XCTAssertTrue(
            AppReviewPrompt.consumePendingRequest(
                defaults: defaults,
                launchThreshold: 5
            )
        )
    }

    func testRequestIsConsumedOnlyOnce() {
        for _ in 0..<5 {
            AppReviewPrompt.recordLaunch(defaults: defaults)
        }

        XCTAssertTrue(
            AppReviewPrompt.consumePendingRequest(
                defaults: defaults,
                launchThreshold: 5
            )
        )
        XCTAssertFalse(
            AppReviewPrompt.consumePendingRequest(
                defaults: defaults,
                launchThreshold: 5
            )
        )
    }

    func testChangingThresholdChangesEligibilityWithoutCodeChanges() {
        for _ in 0..<3 {
            AppReviewPrompt.recordLaunch(defaults: defaults)
        }

        XCTAssertFalse(
            AppReviewPrompt.consumePendingRequest(
                defaults: defaults,
                launchThreshold: 5
            )
        )
        XCTAssertTrue(
            AppReviewPrompt.consumePendingRequest(
                defaults: defaults,
                launchThreshold: 3
            )
        )
    }

    func testZeroThresholdDisablesAutomaticRequest() {
        AppReviewPrompt.recordLaunch(defaults: defaults)
        XCTAssertFalse(
            AppReviewPrompt.consumePendingRequest(
                defaults: defaults,
                launchThreshold: 0
            )
        )
    }
}
