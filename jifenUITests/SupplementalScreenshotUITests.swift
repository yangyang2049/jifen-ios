import XCTest

/// 补拍上一轮可能遗漏的二三级页面（工具列表 / 预约创建 / 记录 / 同步）。
final class SupplementalScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    func testCaptureSupplementalScreenshots() throws {
        // Do not wipe existing screenshots — only fill gaps.
        relaunch()

        // Tools list
        selectTab("首页")
        for _ in 0..<5 { app.swipeUp() }
        let chevron = app.buttons.matching(NSPredicate(format: "label == %@", "chevron.right")).firstMatch
        if chevron.exists {
            chevron.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        UITestScreenshotStore.capture(app, name: "30_tools_list", testCase: self)

        // Schedule create
        relaunch()
        selectTab("首页")
        for _ in 0..<6 { app.swipeUp() }
        let schedule = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "我的球局", "查看全部")).firstMatch
        if schedule.exists {
            schedule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        UITestScreenshotStore.capture(app, name: "50_schedule_list", testCase: self)
        let create = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "预约新球局")).firstMatch
        if create.exists {
            create.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            UITestScreenshotStore.capture(app, name: "51_schedule_create", testCase: self)
        }

        // Records (local sync entry removed)
        relaunch()
        selectTab("记录")
        UITestScreenshotStore.capture(app, name: "60_records_root", testCase: self)

        let listing = ((try? FileManager.default.contentsOfDirectory(atPath: UITestScreenshotStore.outputDirectory.path)) ?? [])
            .filter { $0.hasSuffix(".png") }
            .sorted()
            .joined(separator: "\n")
        let count = UITestScreenshotStore.writtenFileCount()
        try? """
        UITestScreenshots index
        generated: \(ISO8601DateFormatter().string(from: Date()))
        \(UITestScreenshotStore.devicePrefix) count: \(count)
        total count: \(UITestScreenshotStore.totalWrittenFileCount())

        \(listing)
        """.write(
            to: UITestScreenshotStore.outputDirectory.appendingPathComponent("INDEX.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertGreaterThanOrEqual(count, 70)
    }

    private func relaunch() {
        if app != nil { app.terminate() }
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent"
        ]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        _ = app.tabBars.buttons["首页"].waitForExistence(timeout: 10)
            || app.tabBars.buttons["Home"].waitForExistence(timeout: 2)
    }

    @discardableResult
    private func selectTab(_ name: String) -> Bool {
        for n in [name, name == "首页" ? "Home" : name, name == "记录" ? "Records" : name] {
            let button = app.tabBars.buttons[n]
            if button.exists {
                if !button.isSelected { button.tap() }
                return true
            }
        }
        return false
    }
}
