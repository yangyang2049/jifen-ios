import XCTest

/// 工具 → 计数器：点「结束」应保存本次计数并把数字归零、留在本页继续，
/// 而不是退出（退出交给左上角返回）。
final class WatchCounterUITests: XCTestCase {
    private func capture(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "shot_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openCounter(_ app: XCUIApplication) {
        // 首页是第 2 页，工具页在它左边。
        let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "计数器")).firstMatch
        for _ in 0..<4 where !entry.exists {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)))
            usleep(500_000)
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "工具页未出现「计数器」")
        entry.tap()
        XCTAssertTrue(app.navigationBars["计数器"].waitForExistence(timeout: 5), "未进入计数器")
    }

    private func countText(_ app: XCUIApplication, _ value: Int) -> XCUIElement {
        app.staticTexts[String(value)].firstMatch
    }

    func testFinishSavesAndResetsCountInPlace() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        openCounter(app)

        // 点屏幕加 3 次。
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        for _ in 0..<3 { center.tap(); usleep(300_000) }
        XCTAssertTrue(countText(app, 3).waitForExistence(timeout: 3), "计数未累加到 3")
        capture("counter-3")

        // 结束 → 确认。
        let finish = app.buttons["watch_counter_finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "结束")).allElementsBoundByIndex.last
        XCTAssertNotNil(confirm)
        XCTAssertTrue(confirm!.waitForExistence(timeout: 3), "未出现结束确认")
        confirm!.tap()

        // 归零但仍在计数器页面。
        XCTAssertTrue(countText(app, 0).waitForExistence(timeout: 5), "结束后应归零")
        XCTAssertTrue(app.navigationBars["计数器"].exists, "结束后应留在计数器页面，而不是退出")
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "十秒挑战")).firstMatch.exists,
                       "不应退回工具列表")
        capture("counter-reset-in-place")

        // 记录确实落库：返回后到「记录」页应能看到这次计数器记录。
        app.navigationBars["计数器"].buttons.firstMatch.tap()
        usleep(600_000)
        for _ in 0..<3 {
            let store = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "计数器")).firstMatch
            if store.exists { break }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
            usleep(600_000)
        }
        let counterRecord = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "计数器")).firstMatch
        XCTAssertTrue(counterRecord.waitForExistence(timeout: 8), "记录页应出现本次计数器记录")
        capture("counter-record-saved")
    }
}
