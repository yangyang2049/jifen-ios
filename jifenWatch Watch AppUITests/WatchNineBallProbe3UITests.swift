import XCTest

final class WatchNineBallProbe3UITests: XCTestCase {
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

    func testExplorePanels() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)
        let nineBall = app.buttons["追分"]
        scrollTo(nineBall, in: app)
        nineBall.tap()
        sleep(1)
        app.buttons["3 人"].tap()
        sleep(1)
        app.buttons["开始"].tap()
        sleep(2)

        // Tap player 1 zone (left third).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.55)).tap()
        sleep(1)
        dump(app, "event-panel")

        let normalWin = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "普通胜")).firstMatch
        print("PROBE normalWin exists=\(normalWin.exists)")
        normalWin.tap()
        sleep(1)
        dump(app, "payer-picker")

        // Back arrow of secondary picker
        let back = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", "arrow.backward", "arrow.backward")).firstMatch
        print("PROBE back exists=\(back.exists) label=\(back.label) id=\(back.identifier)")
        let close = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "取消")).firstMatch
        print("PROBE close exists=\(close.exists) label=\(close.label)")
    }

    func testExploreMenu() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)
        let nineBall = app.buttons["追分"]
        scrollTo(nineBall, in: app)
        nineBall.tap()
        sleep(1)
        app.buttons["3 人"].tap()
        sleep(1)
        app.buttons["开始"].tap()
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 1.0)
        sleep(1)
        dump(app, "menu")
        let breaker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "本局开球人")).firstMatch
        print("PROBE breakerMenu exists=\(breaker.exists)")
        if breaker.exists { breaker.tap(); sleep(1); dump(app, "breaker-picker") }
    }
}
