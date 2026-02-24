import XCTest

final class jifenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
                app.launch()
            }
        }
    }
}
