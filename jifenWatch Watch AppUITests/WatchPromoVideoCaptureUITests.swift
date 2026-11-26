import XCTest

/// 手表端宣传片素材：真实手表端首页、乒乓球计分过程与多项目计分板截图。
///
/// 仅在显式指定 `-only-testing:jifenWatch Watch AppUITests/WatchPromoVideoCaptureUITests` 时运行；
/// 截图以 `promo_<序号>_<名称>` 附件保存，由 `scripts/compose_watch_promo_video.py` 合成为竖屏宣传片。
/// 宿主在运行前卸载并重装 App，保证首页从干净状态起步。
final class WatchPromoVideoCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotIndex = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    }

    func testCapturePromoFootage() throws {
        relaunch()
        snap("home_top")

        // 用数码表冠缓慢滚动首页，便于外部录屏截取真实滚动镜头（拖动长按会触发置顶弹窗）。
        sleep(1)
        for index in 0..<6 {
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.35, velocity: .slow)
            usleep(250_000)
            snap("home_scroll_\(index)")
        }
        sleep(1)

        // 乒乓球：默认选手，从 8:7 打到 11:9 拿下首局。
        relaunch()
        guard openSport("乒乓球") else { return }
        guard tapStart() else { return }
        sleep(2)
        snap("pp_0_0")
        for _ in 0..<8 { tapHalf(left: true) }
        for _ in 0..<7 { tapHalf(left: false) }
        sleep(1)
        snap("pp_8_7")
        for (step, left) in [true, false, true, false, true].enumerated() {
            tapHalf(left: left)
            usleep(900_000)
            snap("pp_step_\(step)")
        }
        sleep(2)
        snap("pp_game_end")

        // 多项目计分板快剪。
        let montage: [(tile: String, left: Int, right: Int)] = [
            ("羽毛球", 9, 7), ("网球", 2, 1), ("八球", 3, 2), ("足球", 2, 1), ("匹克球", 6, 4)
        ]
        for item in montage {
            relaunch()
            guard openSport(item.tile) else { continue }
            guard tapStart() else { continue }
            sleep(2)
            for _ in 0..<item.left { tapHalf(left: true) }
            for _ in 0..<item.right { tapHalf(left: false) }
            sleep(1)
            snap("sport_\(item.tile)")
        }
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        shotIndex += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "promo_%02d_%@", shotIndex, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func relaunch() {
        app.terminate()
        app.launch()
        sleep(3)
        dismissResumeIfNeeded()
    }

    private func openSport(_ title: String) -> Bool {
        let tile = app.buttons[title]
        guard tile.waitForExistence(timeout: 8) else { return false }
        for _ in 0..<30 {
            if tile.isHittable { break }
            drag(dy: tile.frame.midY > 200 ? -55 : 30, duration: 0.01)
        }
        guard tile.isHittable else { return false }
        tile.tap()
        sleep(1)
        return true
    }

    private func tapStart() -> Bool {
        let start = app.buttons["开始"]
        guard start.waitForExistence(timeout: 6) else { return false }
        for _ in 0..<14 where !start.isHittable { drag(dy: -45, duration: 0.01) }
        guard start.isHittable else { return false }
        start.tap()
        return true
    }

    private func dismissResumeIfNeeded() {
        for label in ["放弃未完成比赛", "放弃未完成训练"] {
            let discard = app.buttons[label]
            guard discard.waitForExistence(timeout: 1) else { continue }
            discard.tap()
            for confirm in ["确认放弃", "确认"] {
                let button = app.buttons[confirm]
                if button.waitForExistence(timeout: 2) { button.tap(); break }
            }
            sleep(1)
            break
        }
    }

    private func tapHalf(left: Bool) {
        app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.25 : 0.75, dy: 0.5)).tap()
        usleep(200_000)
    }

    private func drag(dy: CGFloat, duration: TimeInterval) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: duration, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        usleep(300_000)
    }
}
