import XCTest

final class WatchNineBallProbeUITests: XCTestCase {
    func testDumpHomeHierarchy() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        let tree = app.debugDescription
        let attachment = XCTAttachment(string: tree)
        attachment.name = "home-hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "probe-home"
        shot.lifetime = .keepAlways
        add(shot)
        print("PROBE_TREE_BEGIN")
        print(tree)
        print("PROBE_TREE_END")
    }
}
