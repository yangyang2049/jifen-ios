import XCTest

final class jifenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
                "-UITestSkipLegalConsent"
            ]
            app.launch()
        }
    }
}
