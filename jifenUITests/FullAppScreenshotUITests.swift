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
            87,
            "Expected broad screenshot coverage, got \(count). Dir: \(UITestScreenshotStore.outputDirectory.path)"
        )
    }

    func testCaptureMeSecondaryScreenshots() {
        captureMeSecondaryPages()
        for name in [
            "40_me_root",
            "41_me_scoreboard_settings",
            "42_me_appearance",
            "43_me_faq",
            "44_me_about"
        ] {
            let url = UITestScreenshotStore.outputDirectory
                .appendingPathComponent("\(UITestScreenshotStore.devicePrefix)_\(name).png")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "Expected focused Me screenshot: \(url.lastPathComponent)"
            )
        }
    }

    /// 重点项目截图矩阵：四种球类分别覆盖单打/双打，并补齐掼蛋的真实操作状态。
    /// 每个场景都保留设置、初始计分板、操作后和菜单 Overlay 四张截图，方便人工复核。
    func testCapturePrioritySportsVariants() {
        let variants: [(id: String, label: String, doubles: Bool)] = [
            ("pingpong", "乒乓球", false),
            ("pingpong", "乒乓球", true),
            ("badminton", "羽毛球", false),
            ("badminton", "羽毛球", true),
            ("tennis", "网球", false),
            ("tennis", "网球", true),
            ("pickleball", "匹克球", false),
            ("pickleball", "匹克球", true),
        ]

        for (offset, variant) in variants.enumerated() {
            let index = offset + 1
            let mode = variant.doubles ? "doubles" : "singles"
            XCTContext.runActivity(named: "Priority \(variant.id) \(mode)") { _ in
                XCTAssertTrue(openPriorityScoreboardSetup(id: variant.id, label: variant.label))
                XCTAssertTrue(
                    selectSinglesDoublesMode(doubles: variant.doubles),
                    "Cannot select \(mode) for \(variant.id)"
                )
                snap(String(format: "70_%02d_setup_%@_%@", index, variant.id, mode), settle: 0.5)

                XCTAssertTrue(tapStart(), "Start button not found for \(variant.id) \(mode)")
                XCTAssertTrue(waitForPriorityScoreboard(), "Scoreboard did not open for \(variant.id) \(mode)")

                if variant.doubles {
                    assertDoublesPlayersVisible(for: variant.id)
                }
                snap(String(format: "71_%02d_board_%@_%@", index, variant.id, mode), settle: 0.6)

                tapPriorityScorePanels()
                snap(String(format: "72_%02d_scored_%@_%@", index, variant.id, mode), settle: 0.6)
                XCTAssertTrue(openPriorityScoreboardMenu(), "Menu did not open for \(variant.id) \(mode)")
                snap(String(format: "73_%02d_menu_%@_%@", index, variant.id, mode), settle: 0.4)
            }
        }

        capturePriorityGuandan(index: variants.count + 1)
    }

    func testGuandanDirectUpgradeFlow() {
        capturePriorityGuandan(index: 7)
    }

    func testPingPongTerminalScoreHoldsBeforeNextSet() {
        relaunch()
        XCTAssertTrue(openPriorityScoreboardSetup(id: "pingpong", label: "乒乓球"))
        XCTAssertTrue(selectSinglesDoublesMode(doubles: false))
        XCTAssertTrue(tapStart())
        XCTAssertTrue(waitForPriorityScoreboard())

        for _ in 0..<11 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        }

        let terminalScoreWasVisible = app.staticTexts["11"].waitForExistence(timeout: 0.3)
        XCTAssertTrue(terminalScoreWasVisible, "Terminal score must remain visible during the one-second hold")
        snap("74_pingpong_terminal_score_11", settle: 0.1)

        RunLoop.current.run(until: Date().addingTimeInterval(1.05))
        XCTAssertFalse(app.staticTexts["11"].exists)
        XCTAssertTrue(app.staticTexts["0"].exists)
        snap("75_pingpong_next_set", settle: 0.1)
    }

    func testBasketballFoulLongPressDoesNotOpenScoreboardMenu() {
        relaunch()
        XCTAssertTrue(openPriorityScoreboardSetup(id: "basketball", label: "篮球"))
        XCTAssertTrue(tapStart())
        XCTAssertTrue(waitForPriorityScoreboard())

        let foulRow = app.descendants(matching: .any)["basketball_left_foul_row"]
        XCTAssertTrue(foulRow.waitForExistence(timeout: 4))
        foulRow.tap()
        XCTAssertEqual(foulRow.value as? String, "1")

        foulRow.press(forDuration: 0.7)
        XCTAssertEqual(foulRow.value as? String, "0")
        XCTAssertFalse(
            app.descendants(matching: .any)["scoreboard_menu_dialog"].exists,
            "Removing a foul must not also open the whole-board menu"
        )
    }

    func testSnookerFrameScoreHoldsBeforeNextFrame() {
        relaunch()
        XCTAssertTrue(openPriorityScoreboardSetup(id: "snooker", label: "斯诺克"))
        let threeFrames = app.buttons
            .matching(NSPredicate(format: "label == %@", "3"))
            .allElementsBoundByIndex
            .first(where: { $0.isHittable })
        XCTAssertNotNil(threeFrames)
        threeFrames?.tap()
        XCTAssertTrue(tapStart())
        XCTAssertTrue(waitForPriorityScoreboard())

        let redBall = app.descendants(matching: .any)["snooker_ball_1"]
        XCTAssertTrue(redBall.waitForExistence(timeout: 4))
        redBall.tap()
        let leftScoreOne = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "scoreboard_left_panel",
                "1"
            )
        ).firstMatch
        XCTAssertTrue(leftScoreOne.waitForExistence(timeout: 1))

        XCTAssertTrue(openPriorityScoreboardMenu())
        let menuSettle = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "结算本局"))
            .firstMatch
        XCTAssertTrue(menuSettle.waitForExistence(timeout: 3))
        menuSettle.tap()
        let confirmSettle = app.buttons["结算本局"].firstMatch
        XCTAssertTrue(confirmSettle.waitForExistence(timeout: 3))
        confirmSettle.tap()

        let frameStatus = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "snooker_frame_status",
                "局"
            )
        ).firstMatch
        XCTAssertTrue(frameStatus.waitForExistence(timeout: 0.3))
        XCTAssertTrue(leftScoreOne.exists)
        XCTAssertEqual(frameStatus.value as? String, "0|1|3|0")

        RunLoop.current.run(until: Date().addingTimeInterval(1.05))
        let leftScoreZero = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "scoreboard_left_panel",
                "0"
            )
        ).firstMatch
        XCTAssertTrue(leftScoreZero.waitForExistence(timeout: 1))
        XCTAssertEqual(frameStatus.value as? String, "1|2|3|0")
    }

    func testSnookerFoulPanelPresentsAndDismissesWithoutBlockingTheScoreboard() {
        relaunch()
        XCTAssertTrue(openPriorityScoreboardSetup(id: "snooker", label: "斯诺克"))
        XCTAssertTrue(tapStart())
        XCTAssertTrue(waitForPriorityScoreboard())

        let foulButton = app.buttons["snooker_foul_button"]
        XCTAssertTrue(foulButton.waitForExistence(timeout: 4))
        foulButton.tap()

        let closeButton = app.buttons["snooker_foul_close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3))
        XCTAssertTrue(foulButton.isHittable, "Hidden foul overlay still blocks scoreboard controls")
    }

    private func capturePriorityGuandan(index: Int) {
        XCTContext.runActivity(named: "Priority guandan") { _ in
            XCTAssertTrue(openPriorityScoreboardSetup(id: "guandan", label: "掼蛋"))
            snap(String(format: "70_%02d_setup_guandan", index), settle: 0.5)
            XCTAssertTrue(tapStart(), "Start button not found for guandan")
            XCTAssertTrue(waitForPriorityScoreboard(), "Guandan scoreboard did not open")
            snap(String(format: "71_%02d_board_guandan", index), settle: 0.6)

            let identifiedUpgrade = app.descendants(matching: .any)["guandan_round_red_plus_1"]
            let labeledUpgrade = app.buttons.matching(
                NSPredicate(format: "label == %@", "+1")
            ).firstMatch
            let directUpgrade = identifiedUpgrade.exists ? identifiedUpgrade : labeledUpgrade
            XCTAssertTrue(directUpgrade.waitForExistence(timeout: 3), "Guandan direct +1 control is missing")
            if directUpgrade.exists, directUpgrade.isHittable { directUpgrade.tap() }
            XCTAssertFalse(app.staticTexts["选择升几级"].exists, "Legacy Guandan settlement panel should not appear")
            XCTAssertTrue(
                app.staticTexts["3"].waitForExistence(timeout: 2),
                "Guandan direct +1 should advance the red rank from 2 to 3"
            )
            snap(String(format: "72_%02d_round_result_guandan", index), settle: 0.5)

            XCTAssertTrue(openPriorityScoreboardMenu(), "Menu did not open for guandan")
            snap(String(format: "73_%02d_menu_guandan", index), settle: 0.4)
        }
    }

    /// 回归网球独立计分板与追分紧凑菜单两种非通用布局。
    func testScoreboardMenuLayoutVariants() {
        for item in [(id: "tennis", label: "网球"), (id: "nine_ball", label: "追分")] {
            relaunch()
            XCTAssertTrue(selectTab("计分"))
            scrollUntilExists(identifier: "scoreboard_catalog_\(item.id)")
            let card = app.descendants(matching: .any)["scoreboard_catalog_\(item.id)"]
            XCTAssertTrue(card.waitForExistence(timeout: 3), "Missing \(item.id) card")
            card.tap()
            XCTAssertTrue(tapStart(), "Start button not found for \(item.id)")
            XCUIDevice.shared.orientation = .landscapeRight
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            revealScoreboardChrome(fromLeftCorner: true)
            XCTAssertTrue(
                app.descendants(matching: .any)["scoreboard_back_button"].waitForExistence(timeout: 8),
                "Scoreboard did not open for \(item.id)"
            )
            if item.id == "tennis" {
                let back = app.descendants(matching: .any)["scoreboard_back_button"]
                XCTAssertLessThan(back.frame.midX, app.frame.midX, "Tennis back button must stay on the left")
                XCTAssertGreaterThan(back.frame.midY, app.frame.midY, "Tennis back button must stay at the bottom")
            }
            exerciseScoreboardChrome(for: item.id)
        }
    }

    // MARK: - Launch

    private func relaunch() {
        if app != nil {
            terminateAndWait(app)
        }
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints",
            "-UITestScreenshotMode", "1"
        ]
        XCTAssertTrue(launchAndWait(app), "Screenshot app failed to reach the foreground")
        XCTAssertTrue(waitForTabs(timeout: 12), "Tab bar not ready after launch")
        // Ensure portrait for tab navigation
        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func captureFirstLaunchLegalScreen() {
        if app != nil {
            terminateAndWait(app)
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
        XCTAssertTrue(launchAndWait(app), "Legal screenshot app failed to reach the foreground")

        let title = app.staticTexts["使用前请先阅读并同意"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "First-launch legal screen not ready")
        snap("00_first_launch_legal")
    }

    private func launchAndWait(_ app: XCUIApplication) -> Bool {
        if app.state != .notRunning {
            app.terminate()
            guard app.wait(for: .notRunning, timeout: 5) else { return false }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.launch()
        return app.wait(for: .runningForeground, timeout: 12)
    }

    private func terminateAndWait(_ app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5), "Screenshot app failed to terminate")
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

                // 部分计分板仅在横屏尺寸下挂载完整的无障碍树。先完成方向切换，
                // 再检查页面标识，避免把“尚未布局”误判为“未打开”。
                XCUIDevice.shared.orientation = .landscapeLeft
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                revealScoreboardChrome(fromLeftCorner: true)
                let scoreboard = app.descendants(matching: .any)["scoreboard_back_button"]
                XCTAssertTrue(
                    scoreboard.waitForExistence(timeout: 8),
                    "Scoreboard did not open for \(item.id)"
                )

                snap(String(format: "11_%02d_board_%@", index + 1, item.id), settle: 0.6)
                exerciseScoreboardChrome(for: item.id)
            }
        }
    }

    private func openPriorityScoreboardSetup(id: String, label: String) -> Bool {
        relaunch()
        guard selectTab("计分") else { return false }
        scrollUntilExists(identifier: "scoreboard_catalog_\(id)")

        let card = app.descendants(matching: .any)["scoreboard_catalog_\(id)"]
        if card.waitForExistence(timeout: 3), card.isHittable {
            card.tap()
        } else {
            let byLabel = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", label)
            ).firstMatch
            guard byLabel.waitForExistence(timeout: 3), byLabel.isHittable else { return false }
            byLabel.tap()
        }

        dismissWatchStartGuideIfNeeded()
        return app.buttons["开始"].waitForExistence(timeout: 4)
            || app.buttons["Start"].waitForExistence(timeout: 1)
            || app.buttons["确认"].waitForExistence(timeout: 1)
    }

    private func dismissWatchStartGuideIfNeeded() {
        let closeButton = app.buttons["linked_score_watch_start_guide_close"]
        if closeButton.waitForExistence(timeout: 0.8), closeButton.isHittable {
            closeButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }

    private func selectSinglesDoublesMode(doubles: Bool) -> Bool {
        let picker = app.segmentedControls["singles_doubles_picker"]
        guard picker.waitForExistence(timeout: 4) else { return false }

        let optionID = doubles ? "doubles_option" : "singles_option"
        let option = app.buttons[optionID]
        if option.exists, option.isHittable {
            option.tap()
        } else {
            picker.coordinate(
                withNormalizedOffset: CGVector(dx: doubles ? 0.75 : 0.25, dy: 0.5)
            ).tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let expected = doubles ? "双打" : "单打"
        return (picker.value as? String) == expected
    }

    private func waitForPriorityScoreboard() -> Bool {
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        revealScoreboardChrome(fromLeftCorner: true)
        return app.descendants(matching: .any)["scoreboard_back_button"]
            .waitForExistence(timeout: 8)
    }

    private func assertDoublesPlayersVisible(for id: String) {
        for name in ["红A", "红B", "蓝A", "蓝B"] {
            let player = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", name))
                .firstMatch
            XCTAssertTrue(player.waitForExistence(timeout: 4), "\(id) doubles player is missing: \(name)")
        }
    }

    private func tapPriorityScorePanels() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    private func openPriorityScoreboardMenu() -> Bool {
        let dialog = app.descendants(matching: .any)["scoreboard_menu_dialog"]
        if dialog.exists { return true }

        revealScoreboardChrome(fromLeftCorner: false)
        let menu = app.descendants(matching: .any)["scoreboard_menu_button"]
        if menu.waitForExistence(timeout: 2), menu.isHittable {
            menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.94)).tap()
        }
        if !dialog.waitForExistence(timeout: 1) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.94)).tap()
        }
        return dialog.waitForExistence(timeout: 3)
    }

    /// 每个计分板都实际操作菜单与撤销，避免截图存在但按钮失效、遮挡或菜单未挂载。
    private func exerciseScoreboardChrome(for id: String) {
        revealScoreboardChrome(fromLeftCorner: false)
        let dialog = app.descendants(matching: .any)["scoreboard_menu_dialog"]
        let menu = app.descendants(matching: .any)["scoreboard_menu_button"]
        if !dialog.exists {
            XCTAssertTrue(menu.waitForExistence(timeout: 3), "Missing menu button for \(id)")
            if menu.exists {
                menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                // 控制栏正在淡出时 identifier 仍可能存在但暂不可点，使用其固定右下角热区。
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.94)).tap()
            }
        }

        if !dialog.waitForExistence(timeout: 0.5) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.94)).tap()
        }

        XCTAssertTrue(dialog.waitForExistence(timeout: 3), "Menu did not open for \(id)")
        guard dialog.exists else { return }

        let undoCandidates = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "撤销")
        ).allElementsBoundByIndex
        let undo = undoCandidates.max(by: { $0.frame.midY < $1.frame.midY })
        XCTAssertNotNil(undo, "Menu undo is missing for \(id)")
        if let undo, undo.exists, undo.isHittable {
            undo.tap()
            XCTAssertTrue(dialog.exists, "Undo unexpectedly dismissed menu for \(id)")
        }

        var closedViaMenuAction = false
        let close = app.descendants(matching: .any)["scoreboard_menu_close_button"]
        if close.exists, close.isHittable {
            close.tap()
        } else {
            let closeByLabel = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "关闭", "xmark")
            ).firstMatch
            if closeByLabel.waitForExistence(timeout: 1), closeByLabel.isHittable {
                closeByLabel.tap()
            } else {
                // 追分等紧凑布局可能不暴露 xmark 节点；“显示设置”按设计会先关闭菜单。
                let displayByID = app.descendants(matching: .any)["scoreboard_menu_action_displaySettings"]
                let displayByLabel = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", "显示设置")
                ).firstMatch
                let displaySettings = displayByID.exists ? displayByID : displayByLabel
                XCTAssertTrue(displaySettings.waitForExistence(timeout: 2), "Menu close fallback is missing for \(id)")
                if displaySettings.exists {
                    displaySettings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    closedViaMenuAction = true
                }
            }
        }
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 2), "Menu did not close for \(id)")

        if closedViaMenuAction { return }
        let edit = app.descendants(matching: .any)["scoreboard_edit_button"]
        if edit.exists, edit.isHittable {
            edit.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let done = app.descendants(matching: .any)["scoreboard_edit_button"]
            XCTAssertTrue(done.exists, "Edit control disappeared for \(id)")
            if done.exists, done.isHittable { done.tap() }
        }
    }

    /// 沉浸模式会自动隐藏控制栏；角落触摸既是产品支持的唤出方式，也是测试前置条件。
    private func revealScoreboardChrome(fromLeftCorner: Bool) {
        let expectedID = fromLeftCorner ? "scoreboard_back_button" : "scoreboard_menu_button"
        if app.descendants(matching: .any)[expectedID].exists { return }
        app.coordinate(
            withNormalizedOffset: CGVector(dx: fromLeftCorner ? 0.02 : 0.98, dy: 0.98)
        ).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
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

        tapSettingsEntry("settings_scoreboard_entry", fallback: "计分设置")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        snap("41_me_scoreboard_settings")
        closeMeDestination("settings_scoreboard_sheet_close")

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
        tapSettingsEntry("settings_faq_entry", fallback: "常见问题")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        snap("43_me_faq")
        closeMeDestination("settings_faq_sheet_close")

        selectTab("我的")
        tapSettingsEntry("settings_about_entry", fallback: "关于我们")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        snap("44_me_about")
        closeMeDestination("settings_about_sheet_close")
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
        // 首次进入支持手表联动的项目时，关闭锚定在手表按钮上的一次性引导。
        let guideDismiss = app.buttons["linked_score_watch_start_guide_close"]
        if guideDismiss.waitForExistence(timeout: 0.8), guideDismiss.isHittable {
            guideDismiss.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
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

    private func tapSettingsEntry(_ identifier: String, fallback: String) {
        let entry = app.descendants(matching: .any)[identifier]
        if entry.waitForExistence(timeout: 3) {
            entry.tap()
            return
        }
        tapRow(fallback)
    }

    private func closeMeDestination(_ sheetCloseIdentifier: String) {
        guard UITestScreenshotStore.devicePrefix == "iPad" else {
            navigateBack()
            return
        }

        let closeButton = app.buttons[sheetCloseIdentifier]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 3),
            "Missing iPad settings sheet close button: \(sheetCloseIdentifier)"
        )
        closeButton.tap()

        let sheetIdentifier = String(sheetCloseIdentifier.dropLast("_close".count))
        let sheet = app.descendants(matching: .any)[sheetIdentifier]
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "iPad settings sheet did not close")
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
