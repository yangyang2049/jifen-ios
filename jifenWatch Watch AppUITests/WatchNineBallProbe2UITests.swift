import XCTest

final class WatchNineBallProbe2UITests: XCTestCase {
    private func dump(_ app: XCUIApplication, _ name: String) {
        let text = app.debugDescription
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("PROBE_BEGIN \(name)")
        print(text)
        print("PROBE_END \(name)")
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
    }

    func testReachThreePlayerScoreboard() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)
        let nineBall = app.buttons["追分"]
        scrollTo(nineBall, in: app)
        nineBall.tap()
        sleep(1)
        dump(app, "player-count-picker")
        let three = app.buttons["3 人"]
        if three.waitForExistence(timeout: 3) { three.tap() }
        sleep(1)
        dump(app, "nine-ball-setup")
        let start = app.buttons["开始"]
        if start.waitForExistence(timeout: 3) { start.tap() }
        sleep(2)
        dump(app, "three-player-scoreboard")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "probe-scoreboard"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
