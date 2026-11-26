import XCTest

/// 手表 Setup 自定义数字弹层（对齐鸿蒙手表铅笔 pill + 数字键盘）：
/// 1. 足球半场时长输入预设外的 35 分钟并生效
/// 2. 斯诺克局数输入预设外的 21 局并生效
final class WatchNumberKeypadUITests: XCTestCase {
    private func capture(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "shot_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissLinkErrorIfNeeded(_ app: XCUIApplication) {
        let alert = app.alerts["联动失败"]
        if alert.exists {
            alert.buttons.firstMatch.tap()
        }
    }

    private func dismissResumeBarIfNeeded(_ app: XCUIApplication) {
        dismissLinkErrorIfNeeded(app)
        for discardLabel in ["放弃未完成训练", "放弃未完成比赛"] {
            let discard = app.buttons[discardLabel]
            guard discard.waitForExistence(timeout: 2) else { continue }
            discard.tap()
            let confirm = app.buttons["确认放弃"]
            if confirm.waitForExistence(timeout: 2) {
                confirm.tap()
            }
            break
        }
    }

    private func smallDrag(_ app: XCUIApplication, dy: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        usleep(400_000)
    }

    private func tapSportTile(_ title: String, in app: XCUIApplication) {
        let tile = app.buttons[title]
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "首页未出现项目「\(title)」")
        for _ in 0..<24 {
            dismissLinkErrorIfNeeded(app)
            if tile.isHittable { break }
            let midY = tile.frame.midY
            if midY > 200 {
                smallDrag(app, dy: -55)
            } else if midY < 90 {
                smallDrag(app, dy: 30)
            } else {
                smallDrag(app, dy: -25)
            }
        }
        XCTAssertTrue(tile.isHittable, "首页项目「\(title)」未滚动到可点击位置")
        tile.tap()
        sleep(1)
    }

    /// 横向档位行按需左滑，直到末位铅笔方格进入可点区域。
    private func revealCustomChip(in app: XCUIApplication, anchor: XCUIElement) -> XCUIElement {
        let chip = app.buttons["watch_setup_custom_number"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "未渲染自定义数字入口")
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))

        for _ in 0..<16 {
            if chip.isHittable { return chip }
            let screenHeight = app.frame.height
            // 优先按档位行自身的高度横滑；标题行不参与横向滚动，拿它当锚点会滑不动。
            let rowY = chip.exists ? chip.frame.midY : anchor.frame.midY + 20
            let y = min(max(rowY, 30), screenHeight - 30) / screenHeight
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: y))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -70, dy: 0)))
            usleep(300_000)
        }
        XCTFail("自定义数字入口未滚动到可点位置")
        return chip
    }

    private func typeNumber(_ digits: [Int], in app: XCUIApplication) {
        for digit in digits {
            let key = app.buttons["watch_keypad_digit_\(digit)"]
            XCTAssertTrue(key.waitForExistence(timeout: 4), "数字键 \(digit) 未出现")
            key.tap()
        }
        let confirm = app.buttons["watch_keypad_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
    }

    func testFootballHalfLengthAcceptsCustomMinutes() {
        let app = XCUIApplication()
        app.launch()
        dismissResumeBarIfNeeded(app)
        capture("01-home")
        tapSportTile("足球", in: app)
        capture("02-football-setup")

        let chip = revealCustomChip(in: app, anchor: app.staticTexts["半场时长（分钟）"])
        capture("03-pencil-revealed")
        chip.tap()
        sleep(1)
        let dump = XCTAttachment(string: app.debugDescription)
        dump.name = "hierarchy-after-pencil"
        dump.lifetime = .keepAlways
        add(dump)

        XCTAssertTrue(app.buttons["watch_keypad_digit_3"].waitForExistence(timeout: 4))
        capture("04-keypad-open")
        typeNumber([3, 5], in: app)
        sleep(1)
        capture("05-after-confirm")

        let updated = app.buttons["watch_setup_custom_number"].firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 4))
        XCTAssertEqual(updated.value as? String, "35", "确认后自定义方格应显示 35")
    }

    func testSnookerFramesAcceptCustomValue() {
        let app = XCUIApplication()
        app.launch()
        dismissResumeBarIfNeeded(app)
        tapSportTile("斯诺克", in: app)
        capture("11-snooker-setup")

        let chip = revealCustomChip(in: app, anchor: app.staticTexts["局数"])
        capture("12-pencil-revealed")
        chip.tap()

        XCTAssertTrue(app.buttons["watch_keypad_digit_2"].waitForExistence(timeout: 4))
        typeNumber([2, 1], in: app)
        sleep(1)
        capture("13-after-confirm")

        let updated = app.buttons["watch_setup_custom_number"].firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 4))
        XCTAssertEqual(updated.value as? String, "21", "确认后自定义方格应显示 21")
    }
}
