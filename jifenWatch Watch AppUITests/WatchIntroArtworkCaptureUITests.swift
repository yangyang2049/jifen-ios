import XCTest

/// 手表联动介绍弹层的原版设备素材：真实手表端乒乓球计分板。
///
/// 语言由宿主通过 `TEST_RUNNER_WATCH_INTRO_LOCALE`（en / zh-Hans / zh-Hant）指定；
/// 宿主每轮先卸载 App，保证从首页干净起步。截图保持手表原生分辨率，
/// 供与 Apple 原版 Ultra 4 机身边框合成，不做二次缩放。
final class WatchIntroArtworkCaptureUITests: XCTestCase {
    private struct Locale {
        let language: String
        let appleLocale: String
        let tile: String
        let playersSection: String
        let selectPlayer: String
        let leftName: String
        let rightName: String
        let start: String
        let discard: String
    }

    private func configuration() -> Locale {
        switch ProcessInfo.processInfo.environment["WATCH_INTRO_LOCALE"] ?? "zh-Hans" {
        case "en":
            return Locale(
                language: "en", appleLocale: "en_US", tile: "Table Tennis",
                playersSection: "Players", selectPlayer: "Select player",
                leftName: "Adam", rightName: "Bob",
                start: "Start", discard: "Discard unfinished game"
            )
        case "zh-Hant":
            return Locale(
                language: "zh-Hant", appleLocale: "zh_TW", tile: "乒乓球",
                playersSection: "選手", selectPlayer: "選擇常用選手",
                leftName: "劉備", rightName: "曹操",
                start: "開始", discard: "放棄未完成比賽"
            )
        default:
            return Locale(
                language: "zh-Hans", appleLocale: "zh_CN", tile: "乒乓球",
                playersSection: "选手", selectPlayer: "选择常用选手",
                leftName: "刘备", rightName: "曹操",
                start: "开始", discard: "放弃未完成比赛"
            )
        }
    }

    func testCapturePingPongScoreboard() throws {
        continueAfterFailure = false
        let locale = configuration()
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(locale.language))",
            "-AppleLocale", locale.appleLocale
        ]
        app.launch()
        sleep(3)
        dismissResumeIfNeeded(app)

        let tile = app.buttons[locale.tile]
        XCTAssertTrue(tile.waitForExistence(timeout: 8), "首页未出现项目「\(locale.tile)」")
        for _ in 0..<24 {
            if tile.isHittable { break }
            drag(app, dy: tile.frame.midY > 200 ? -55 : 30)
        }
        XCTAssertTrue(tile.isHittable, "首页项目「\(locale.tile)」不可点击")
        tile.tap()
        sleep(1)

        let playersHeader = app.buttons[locale.playersSection]
        XCTAssertTrue(playersHeader.waitForExistence(timeout: 6), "Setup 未出现「\(locale.playersSection)」")
        for _ in 0..<12 where !playersHeader.isHittable {
            drag(app, dy: -45)
        }
        playersHeader.tap()
        usleep(400_000)

        for (slotIndex, name) in [locale.leftName, locale.rightName].enumerated() {
            let pickerButton = app.buttons
                .matching(NSPredicate(format: "label == %@", locale.selectPlayer))
                .element(boundBy: slotIndex)
            XCTAssertTrue(pickerButton.waitForExistence(timeout: 4), "选手选择按钮 \(slotIndex) 缺失")
            for _ in 0..<12 where !pickerButton.isHittable {
                drag(app, dy: -45)
            }
            pickerButton.tap()
            let choice = app.buttons[name]
            XCTAssertTrue(choice.waitForExistence(timeout: 4), "常用选手「\(name)」未出现")
            choice.tap()
            usleep(350_000)
        }

        let start = app.buttons[locale.start]
        XCTAssertTrue(start.waitForExistence(timeout: 6), "Setup 未出现「\(locale.start)」")
        for _ in 0..<12 where !start.isHittable {
            drag(app, dy: -45)
        }
        start.tap()
        sleep(2)

        // 首局中段比分 7:4；默认 5 局 11 分制，不会被这 11 分打完。
        for _ in 0..<7 { tapHalf(app, left: true) }
        for _ in 0..<4 { tapHalf(app, left: false) }
        sleep(1)

        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "watch_scoreboard_\(locale.language)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissResumeIfNeeded(_ app: XCUIApplication) {
        for label in ["放弃未完成比赛", "放棄未完成比賽", "Discard unfinished game",
                      "放弃未完成训练", "放棄未完成訓練", "Discard unfinished training"] {
            let discard = app.buttons[label]
            guard discard.waitForExistence(timeout: 1) else { continue }
            discard.tap()
            for confirm in ["确认放弃", "確認放棄", "Discard", "确认", "確認"] {
                let button = app.buttons[confirm]
                if button.waitForExistence(timeout: 2) { button.tap(); break }
            }
            sleep(1)
            break
        }
    }

    private func tapHalf(_ app: XCUIApplication, left: Bool) {
        app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.25 : 0.75, dy: 0.5)).tap()
        usleep(180_000)
    }

    private func drag(_ app: XCUIApplication, dy: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        usleep(300_000)
    }
}
