import XCTest

/// 手表端投篮训练的开局前弹层与续赛浮条 UI 验证。
final class WatchBasketballTrainingUITests: XCTestCase {
    private func capture(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "shot_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func smallDrag(_ app: XCUIApplication, dy: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        usleep(400_000)
    }

    private func dismissResumeBarIfNeeded(_ app: XCUIApplication) {
        for discardLabel in ["放弃未完成训练", "放弃未完成比赛"] {
            let discard = app.buttons[discardLabel]
            guard discard.waitForExistence(timeout: 2) else { continue }
            discard.tap()
            sleep(2)

            let options = app.buttons.matching(NSPredicate(format: "label == %@", discardLabel))
            var tapped = false
            for index in 0..<options.count {
                let candidate = options.element(boundBy: index)
                if candidate.isHittable {
                    candidate.tap()
                    tapped = true
                    break
                }
            }
            if !tapped {
                let cancel = app.buttons["关闭"]
                if cancel.exists { cancel.tap() }
            }
            sleep(2)
            break
        }
    }

    private func tapSportTile(_ title: String, in app: XCUIApplication) {
        let tile = app.buttons[title]
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "首页未出现项目「\(title)」")
        for _ in 0..<24 {
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

    func testModePickerAndResumeBarWording() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        dismissResumeBarIfNeeded(app)

        tapSportTile("投篮训练", in: app)
        XCTAssertTrue(
            app.staticTexts["选择训练模式"].waitForExistence(timeout: 3),
            "应弹出「选择训练模式」弹层"
        )
        capture("bb_01_mode_picker")

        let twoPoint = app.buttons["2 分"]
        XCTAssertTrue(twoPoint.waitForExistence(timeout: 3), "应显示「2 分」按钮")
        twoPoint.tap()
        sleep(2)

        // 右侧命中区域记录一次命中（1/1 = 100%），再右滑返回首页触发续赛浮条。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5)).tap()
        sleep(1)

        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        let rightEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: rightEdge)
        sleep(2)

        let resumeScoring = app.buttons["继续计分"]
        XCTAssertTrue(
            resumeScoring.waitForExistence(timeout: 4),
            "投篮训练续赛浮条应显示「继续计分」"
        )
        XCTAssertFalse(
            app.buttons["继续比赛"].exists,
            "投篮训练续赛浮条不应显示「继续比赛」"
        )
        capture("bb_02_resume_bar")

        let discardButton = app.buttons["放弃未完成训练"]
        XCTAssertTrue(
            discardButton.waitForExistence(timeout: 3),
            "投篮训练续赛浮条关闭按钮应使用「放弃未完成训练」"
        )
        discardButton.tap()
        sleep(2)

        let confirmButtons = app.buttons.matching(NSPredicate(format: "label == %@", "放弃未完成训练"))
        var confirmed = false
        for index in 0..<confirmButtons.count {
            let candidate = confirmButtons.element(boundBy: index)
            if candidate.isHittable {
                candidate.tap()
                confirmed = true
                break
            }
        }
        XCTAssertTrue(confirmed, "二次确认弹层中应可点击「放弃未完成训练」")
        sleep(1)
        XCTAssertFalse(app.buttons["继续计分"].exists, "确认放弃后续赛浮条应消失")
    }
}
