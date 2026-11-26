import XCTest

/// 手表端投篮训练的开局前弹层与续赛浮条 UI 验证。
final class WatchBasketballTrainingUITests: XCTestCase {
    private func capture(_ name: String, settle: UInt32 = 1) {
        sleep(settle)
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
            let confirm = app.buttons["确认放弃"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 2))
            confirm.tap()
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

    func testVerticalTrainingMissTargetIncludesTopEdge() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-watch_scoreboard_layout", "vertical"
        ]
        app.launch()
        dismissResumeBarIfNeeded(app)
        tapSportTile("投篮训练", in: app)
        let twoPoint = app.buttons["2 分"]
        XCTAssertTrue(twoPoint.waitForExistence(timeout: 3))
        twoPoint.tap()

        let miss = app.buttons["watch_training_miss_2"]
        let made = app.buttons["watch_training_made_2"]
        XCTAssertTrue(miss.waitForExistence(timeout: 4))
        XCTAssertTrue(made.waitForExistence(timeout: 4))
        XCTAssertLessThan(miss.frame.midY, made.frame.midY)
        XCTAssertEqual(miss.value as? String, "0")
        miss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()

        let counted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: miss)
        XCTAssertEqual(XCTWaiter.wait(for: [counted], timeout: 3), .completed)
        XCTAssertEqual(made.value as? String, "0")
        capture("bb_vertical_top_tap", settle: 0)
    }

    func testModePickerAndResumeBarWording() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
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

        tapSportTile("羽毛球", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        let back = app.navigationBars.buttons.firstMatch
        if back.isHittable {
            back.tap()
        } else {
            app.swipeRight()
        }
        XCTAssertTrue(resumeScoring.waitForExistence(timeout: 4), "退出新比赛设置应保留原续赛")

        let discard = app.buttons["放弃未完成训练"]
        let confirm = expandDiscardButton(
            discard, on: resumeScoring, confirmation: app.buttons["确认放弃"]
        )
        capture("bb_03_confirm_zh_hans", settle: 0)
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 4))
        XCTAssertTrue(discard.exists)
        XCTAssertTrue(resumeScoring.exists, "确认超时后应保留续赛")

        for (language, locale, discard, resume, confirmation, screenshot) in [
            ("en", "en_US", "Discard unfinished training", "Resume scoring", "Discard", "bb_04_confirm_en"),
            ("fr-CA", "fr_CA", "Abandonner l’entraînement en cours", "Reprendre", "Abandonner", "bb_05_confirm_fr_ca"),
            ("ko", "ko_KR", "미완료 훈련 버리기", "재개", "버리기", "bb_06_confirm_ko"),
        ] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            _ = expandDiscardButton(
                app.buttons[discard],
                on: app.buttons[resume],
                confirmation: app.buttons[confirmation]
            )
            capture(screenshot, settle: 0)
        }

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
        let traditionalResume = app.buttons["繼續計分"]
        let traditionalConfirm = expandDiscardButton(
            app.buttons["放棄未完成訓練"],
            on: traditionalResume,
            confirmation: app.buttons["確認放棄"]
        )
        capture("bb_07_confirm_zh_hant", settle: 0)
        let confirmFrame = traditionalConfirm.frame
        let overlap = confirmFrame.intersection(traditionalResume.frame)
        traditionalConfirm.coordinate(withNormalizedOffset: CGVector(
            dx: (overlap.midX - confirmFrame.minX) / confirmFrame.width,
            dy: 0.5
        )).tap()
        XCTAssertTrue(traditionalResume.waitForNonExistence(timeout: 4), "点覆盖区域应放弃续赛")
    }

    private func expandDiscardButton(
        _ discard: XCUIElement,
        on resume: XCUIElement,
        confirmation: XCUIElement
    ) -> XCUIElement {
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        let discardFrame = discard.frame
        let resumeFrame = resume.frame
        discard.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        let confirmationFrame = confirmation.frame
        XCTAssertGreaterThan(confirmationFrame.width, discardFrame.width)
        XCTAssertEqual(confirmationFrame.maxX, discardFrame.maxX, accuracy: 1)
        XCTAssertEqual(resume.frame, resumeFrame, "展开时续赛内容应留在原位")
        XCTAssertTrue(confirmationFrame.intersects(resumeFrame), "确认按钮应覆盖续赛内容")
        return confirmation
    }
}
