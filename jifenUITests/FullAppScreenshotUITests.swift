import XCTest

/// 全页面截图 UI 测试：覆盖 Tab、全部计分板、计时面板、工具、二三级页面。
/// iPhone / iPad 截图带设备前缀写入仓库根目录 `UITestScreenshots-All/`。
/// 横屏计分/计时页每次结束后 terminate+relaunch，避免方向锁导致后续导航失败。
final class FullAppScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    private let scoreboards: [(id: String, label: String)] = [
        ("pingpong", "乒乓球"),
        ("badminton", "羽毛球"),
        ("tennis", "网球"),
        ("pickleball", "匹克球"),
        ("football", "足球"),
        ("basketball", "篮球"),
        ("three_basketball", "三人篮球"),
        ("volleyball", "排球"),
        ("beach_volleyball", "沙滩排球"),
        ("air_volleyball", "气排球"),
        ("archery", "射箭"),
        ("boxing", "拳击"),
        ("billiards", "台球"),
        ("eight_ball", "黑八"),
        ("nine_ball", "追分"),
        ("snooker", "斯诺克"),
        ("doudizhu", "斗地主"),
        ("guandan", "掼蛋"),
        ("shengji", "升级"),
        ("uno", "UNO"),
        ("foosball", "桌上足球"),
        ("simpleScore", "简单计分"),
        ("multiScoreboard", "多人计分"),
    ]

    private let timers: [(id: String, label: String, needsSetup: Bool)] = [
        ("go", "围棋", true),
        ("xiangqi", "象棋", true),
        ("chess", "国际象棋", true),
        ("checkers", "国际跳棋", true),
        ("cube", "魔方", false),
        ("stopwatch", "秒表", false),
        ("timeout", "倒计时", false),
        ("basketball24", "篮球24秒", false),
        ("basketball12", "篮球12秒", false),
    ]

    private let tools: [(id: String, label: String)] = [
        ("flip_coin", "抛硬币"),
        ("dice", "骰子"),
        ("whistle", "哨子"),
        ("random_team", "随机分组"),
        ("red_yellow_card", "红黄牌"),
        ("fullscreen_barrage", "全屏弹幕"),
        ("points_table", "积分表"),
        ("time", "翻页时钟"),
        ("aa_calculator", "AA计算器"),
        ("ten_second", "十秒挑战"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testCaptureFullAppScreenshots() throws {
        UITestScreenshotStore.resetOutputDirectory()
        defer {
            let count = UITestScreenshotStore.writtenFileCount()
            writeManifest(count: count)
        }

        captureFirstLaunchLegalScreen()
        captureTabRootsAndHomeSecondary()
        captureAllScoreboards()
        captureAllTimers()
        captureAllTools()
        captureMeSecondaryPages()
        captureScheduleFlow()
        captureRecordsAndLocalSync()

        let count = UITestScreenshotStore.writtenFileCount()
        XCTAssertGreaterThanOrEqual(
            count,
            90,
            "Expected broad screenshot coverage, got \(count). Dir: \(UITestScreenshotStore.outputDirectory.path)"
        )
    }

    // MARK: - Launch

    private func relaunch() {
        if app != nil {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent",
            "-UITestScreenshotMode", "1"
        ]
        app.launch()
        XCTAssertTrue(waitForTabs(timeout: 12), "Tab bar not ready after launch")
        // Ensure portrait for tab navigation
        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func captureFirstLaunchLegalScreen() {
        if app != nil {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-legal_documents_accepted_version", "",
            "-UITestDisableAnalytics",
            "-UITestScreenshotMode", "1"
        ]
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        let title = app.staticTexts["使用前请先阅读并同意"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "First-launch legal screen not ready")
        snap("00_first_launch_legal")
    }

    private func waitForTabs(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if selectTab("首页") || selectTab("Home") { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @discardableResult
    private func selectTab(_ name: String) -> Bool {
        let aliases: [String: [String]] = [
            "首页": ["首页", "Home"],
            "记录": ["记录", "Records"],
            "计分": ["计分", "Score"],
            "计时": ["计时", "Timer"],
            "我的": ["我的", "Me"],
            "Home": ["首页", "Home"],
            "Records": ["记录", "Records"],
            "Score": ["计分", "Score"],
            "Timer": ["计时", "Timer"],
            "Me": ["我的", "Me"]
        ]
        let names = aliases[name] ?? [name]
        for n in names {
            // iPhone: standard tab bar. iPad (iOS 18+/26): may expose tabs outside `tabBars`.
            let candidates: [XCUIElement] = [
                app.tabBars.buttons[n],
                app.buttons[n],
                app.otherElements[n]
            ]
            for button in candidates {
                if button.waitForExistence(timeout: 0.6), button.isHittable {
                    if !button.isSelected { button.tap() }
                    return true
                }
            }
        }
        // Last resort: fuzzy match any hittable control with the tab label.
        for n in names {
            let fuzzy = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR label CONTAINS %@", n, n))
                .allElementsBoundByIndex
                .first(where: { $0.isHittable })
            if let el = fuzzy {
                el.tap()
                return true
            }
        }
        return false
    }

    private func snap(_ name: String, settle: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        UITestScreenshotStore.capture(app, name: name, testCase: self, settleNanoseconds: 200_000_000)
    }

    // MARK: - Tabs + home secondary

    private func captureTabRootsAndHomeSecondary() {
        relaunch()
        selectTab("首页"); snap("01_tab_home")
        selectTab("记录"); snap("02_tab_records")
        selectTab("计分"); snap("03_tab_score")
        selectTab("计时")
        // Ensure basketball 24s/12s (below the fold on smaller phones) are visible.
        app.swipeUp()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        snap("04_tab_timer")
        selectTab("我的"); snap("05_tab_me")

        selectTab("首页")
        let newGame = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "新比赛")).firstMatch
        if newGame.waitForExistence(timeout: 4) {
            newGame.tap()
            snap("06_home_new_game_dialog")
            dismissDialog()
        }

        for _ in 0..<6 { app.swipeUp() }
        tapContaining("常用名称")
        if app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "常用名称")).firstMatch.waitForExistence(timeout: 3) {
            snap("07_home_common_names")
            let add = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "添加")).firstMatch
            if add.exists {
                add.tap()
                snap("07b_home_common_names_add")
                dismissDialog()
            }
            navigateBack()
        }

        selectTab("首页")
        for _ in 0..<6 { app.swipeUp() }
        tapContaining("常用地点")
        if app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "常用地点")).firstMatch.waitForExistence(timeout: 3) {
            snap("08_home_common_places")
            navigateBack()
        }

        selectTab("首页")
        let edit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "编辑")).firstMatch
        if edit.exists {
            edit.tap()
            snap("09_home_quick_start_edit")
            dismissDialog()
        }
    }

    // MARK: - Scoreboards

    private func captureAllScoreboards() {
        for (index, item) in scoreboards.enumerated() {
            XCTContext.runActivity(named: "Scoreboard \(item.id)") { _ in
                relaunch()
                guard selectTab("计分") else {
                    XCTFail("Cannot open Score tab for \(item.id)")
                    return
                }

                scrollUntilExists(identifier: "scoreboard_catalog_\(item.id)")
                let card = app.descendants(matching: .any)["scoreboard_catalog_\(item.id)"]
                if card.waitForExistence(timeout: 2) {
                    card.tap()
                } else {
                    let byLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", item.label)).firstMatch
                    guard byLabel.waitForExistence(timeout: 3) else {
                        XCTFail("Missing scoreboard card: \(item.id)")
                        return
                    }
                    byLabel.tap()
                }

                snap(String(format: "10_%02d_setup_%@", index + 1, item.id), settle: 0.5)
                XCTAssertTrue(tapStart(), "Start button not found for \(item.id)")
                let scoreboard = app.descendants(matching: .any)["scoreboard_back_button"]
                XCTAssertTrue(
                    scoreboard.waitForExistence(timeout: 8),
                    "Scoreboard did not open for \(item.id)"
                )

                // Landscape boards need orientation settle
                XCUIDevice.shared.orientation = .landscapeLeft
                RunLoop.current.run(until: Date().addingTimeInterval(1.2))
                snap(String(format: "11_%02d_board_%@", index + 1, item.id), settle: 0.6)
            }
        }
    }

    // MARK: - Timers

    private func captureAllTimers() {
        for (index, item) in timers.enumerated() {
            XCTContext.runActivity(named: "Timer \(item.id)") { _ in
                relaunch()
                guard selectTab("计时") else {
                    XCTFail("Cannot open Timer tab for \(item.id)")
                    return
                }

                scrollUntilExists(identifier: "timer_dest_\(item.id)")
                let card = app.descendants(matching: .any)["timer_dest_\(item.id)"]
                if card.waitForExistence(timeout: 3) {
                    for _ in 0..<4 where !card.isHittable {
                        app.swipeUp()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    }
                    card.tap()
                } else {
                    // Labels may be "篮球 24 秒" / "Basketball 24s" depending on locale strings.
                    let altLabels = [
                        item.label,
                        item.label.replacingOccurrences(of: "篮球24秒", with: "篮球 24"),
                        item.label.replacingOccurrences(of: "篮球12秒", with: "篮球 12"),
                        item.label.replacingOccurrences(of: "篮球24秒", with: "24"),
                        item.label.replacingOccurrences(of: "篮球12秒", with: "12"),
                    ]
                    var tapped = false
                    for label in altLabels {
                        let byLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
                        if byLabel.waitForExistence(timeout: 1.5) {
                            byLabel.tap()
                            tapped = true
                            break
                        }
                    }
                    guard tapped else {
                        XCTFail("Missing timer card: \(item.id)")
                        return
                    }
                }

                if item.needsSetup {
                    snap(String(format: "20_%02d_timer_setup_%@", index + 1, item.id), settle: 0.4)
                    XCTAssertTrue(tapStart(), "Timer start button not found for \(item.id)")
                }

                XCUIDevice.shared.orientation = .landscapeLeft
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
                snap(String(format: "21_%02d_timer_%@", index + 1, item.id), settle: 0.5)
            }
        }
    }

    // MARK: - Tools

    private func captureAllTools() {
        relaunch()
        openToolsListFromHome()
        XCTAssertTrue(
            app.navigationBars["工具"].waitForExistence(timeout: 4)
                || app.staticTexts["比赛工具"].waitForExistence(timeout: 2)
                || app.staticTexts["其他工具"].waitForExistence(timeout: 2),
            "Tools list did not open"
        )
        snap("30_tools_list")

        for (index, item) in tools.enumerated() {
            XCTContext.runActivity(named: "Tool \(item.id)") { _ in
                if !app.descendants(matching: .any)["tool_card_\(item.id)"].exists {
                    openToolsListFromHome()
                }

                let card = app.descendants(matching: .any)["tool_card_\(item.id)"]
                if card.waitForExistence(timeout: 3) {
                    for _ in 0..<6 where !card.isHittable {
                        app.swipeUp()
                    }
                    card.tap()
                } else {
                    let labels = [item.label, item.label.replacingOccurrences(of: "哨子", with: "哨声")]
                    var tapped = false
                    for label in labels {
                        let byLabel = app.descendants(matching: .any)
                            .matching(NSPredicate(format: "label CONTAINS %@", label))
                            .firstMatch
                        if byLabel.waitForExistence(timeout: 2) {
                            byLabel.tap()
                            tapped = true
                            break
                        }
                    }
                    guard tapped else {
                        XCTFail("Missing tool: \(item.id)")
                        return
                    }
                }

                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                snap(String(format: "31_%02d_tool_%@", index + 1, item.id))
                navigateBack()
            }
        }
    }

    private func openToolsListFromHome() {
        relaunch()
        selectTab("首页")
        for _ in 0..<6 { app.swipeUp() }

        let allTools = app.descendants(matching: .any)["home_all_tools_button"]
        if allTools.waitForExistence(timeout: 3) {
            allTools.tap()
            return
        }

        // Fallback for older accessibility trees
        let chevron = app.buttons.matching(NSPredicate(format: "label == %@", "chevron.right")).firstMatch
        if chevron.exists {
            chevron.tap()
            return
        }
        let toolsText = app.staticTexts["工具"]
        if toolsText.exists {
            toolsText.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
    }

    // MARK: - Me

    private func captureMeSecondaryPages() {
        relaunch()
        selectTab("我的")
        snap("40_me_root")

        tapRow("计分器设置")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        snap("41_me_scoreboard_settings")
        navigateBack()

        selectTab("我的")
        if app.staticTexts["手表联动"].exists || app.buttons["手表联动"].exists
            || app.staticTexts["Watch Link"].exists || app.buttons["Watch Link"].exists {
            tapRow("手表联动")
            if !(app.navigationBars["手表联动"].waitForExistence(timeout: 2)
                || app.navigationBars["Watch Link"].waitForExistence(timeout: 1)) {
                tapRow("Watch Link")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            snap("41b_me_watch_link")
            navigateBack()
        }

        selectTab("我的")
        tapRow("外观")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        snap("42_me_appearance")
        dismissDialog()

        selectTab("我的")
        tapRow("常见问题")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        snap("43_me_faq")
        navigateBack()

        selectTab("我的")
        tapRow("关于我们")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        snap("44_me_about")
        navigateBack()
    }

    // MARK: - Schedule / records / sync

    private func captureScheduleFlow() {
        relaunch()
        selectTab("首页")
        for _ in 0..<4 { app.swipeUp() }

        let scheduleEntry = app.descendants(matching: .any)["home_schedule_all_button"]
        if scheduleEntry.waitForExistence(timeout: 3) {
            scheduleEntry.tap()
        } else {
            // Prefer the section chevron over the empty-state "预约新球局" CTA
            let chevron = app.buttons.matching(NSPredicate(format: "label == %@", "我的球局")).firstMatch
            if chevron.waitForExistence(timeout: 2) {
                chevron.tap()
            } else {
                tapContaining("查看全部")
            }
        }

        XCTAssertTrue(
            app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@ OR label CONTAINS %@", "我的球局", "我的球局")).firstMatch.waitForExistence(timeout: 4)
                || app.staticTexts["暂无待进行球局"].waitForExistence(timeout: 2)
                || app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "预约新球局")).firstMatch.waitForExistence(timeout: 2),
            "Schedule list did not open"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        snap("50_schedule_list")

        let createTapped = tapFirstHittableButton(containing: "预约新球局", maxScrolls: 3)
            || tapFirstHittableButton(containing: "预约", maxScrolls: 1)
        if createTapped {
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            snap("51_schedule_create")
        }
    }

    private func captureRecordsAndLocalSync() {
        relaunch()
        selectTab("记录")
        snap("60_records_root")
        // Local sync entry removed from the app; keep records-only capture.
    }

    // MARK: - Helpers

    @discardableResult
    private func tapFirstHittableButton(containing label: String, maxScrolls: Int) -> Bool {
        for pass in 0...maxScrolls {
            let candidates = app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", label))
                .allElementsBoundByIndex
            if let button = candidates.first(where: { $0.isHittable }) {
                button.tap()
                return true
            }
            if pass < maxScrolls {
                app.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
        }
        return false
    }

    private func scrollUntilExists(identifier: String) {
        let target = app.descendants(matching: .any)[identifier]
        for _ in 0..<10 {
            if target.exists, target.isHittable { return }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        for _ in 0..<10 {
            if target.exists, target.isHittable { return }
            app.swipeDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    @discardableResult
    private func tapStart() -> Bool {
        for label in ["开始", "Start", "确认"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 1.2), button.isHittable {
                button.tap()
                return true
            }
            let fuzzy = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            if fuzzy.exists, fuzzy.isHittable {
                fuzzy.tap()
                return true
            }
        }
        return false
    }

    private func tapContaining(_ text: String) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        if button.waitForExistence(timeout: 3), button.isHittable {
            button.tap()
        }
    }

    private func tapRow(_ text: String) {
        let candidates: [XCUIElement] = [
            app.buttons[text],
            app.staticTexts[text],
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch,
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        ]
        for el in candidates where el.waitForExistence(timeout: 2) {
            if el.isHittable {
                el.tap()
                return
            }
            el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
    }

    private func navigateBack() {
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.isHittable {
                back.tap()
                return
            }
        }
        for label in ["返回", "关闭", "Close", "Back"] {
            if app.buttons[label].exists {
                app.buttons[label].tap()
                return
            }
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func dismissDialog() {
        for label in ["取消", "关闭", "Cancel", "Close", "完成", "Done"] {
            let button = app.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                return
            }
        }
        app.swipeDown()
    }

    private func writeManifest(count: Int) {
        let listing = ((try? FileManager.default.contentsOfDirectory(atPath: UITestScreenshotStore.outputDirectory.path)) ?? [])
            .filter { $0.hasSuffix(".png") }
            .sorted()
            .joined(separator: "\n")
        let manifest = UITestScreenshotStore.outputDirectory.appendingPathComponent("INDEX.txt")
        try? """
        UITestScreenshots index
        generated: \(ISO8601DateFormatter().string(from: Date()))
        \(UITestScreenshotStore.devicePrefix) count: \(count)
        total count: \(UITestScreenshotStore.totalWrittenFileCount())

        \(listing)
        """.write(to: manifest, atomically: true, encoding: .utf8)
    }
}
