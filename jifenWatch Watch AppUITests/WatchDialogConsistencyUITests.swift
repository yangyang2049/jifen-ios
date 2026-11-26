import XCTest

/// 手表端全量弹层一致性与小屏（40mm）防溢出走查：
/// 1. 比赛设置「选择选手」常用名弹层（统一顶栏左标题 + 右关闭钮）
/// 2. 斯诺克选球面板（顶部避让系统时钟 + 犯规胶囊不挤压）
/// 3. 斯诺克「选择本局胜方」（关闭钮移至底部，不再与时钟重叠）
/// 4. 足球「伤停补时」（自适应宽度 + 统一顶栏，40mm 不溢出）
final class WatchDialogConsistencyUITests: XCTestCase {
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
        dismissLinkErrorIfNeeded(app)
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

    private func dismissLinkErrorIfNeeded(_ app: XCUIApplication) {
        let alert = app.alerts["联动失败"]
        if alert.exists {
            alert.buttons.firstMatch.tap()
        }
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

    func testLocalizedWatchHomeLabels() {
        let app = XCUIApplication()
        for (language, locale, doubles) in [
            ("de", "de_DE", "Badminton-Doppel"),
            ("fr-CA", "fr_CA", "Doubles de badminton"),
            ("ar", "ar_SA", "زوجي كرة الريشة"),
            ("ja", "ja_JP", "バドミントンダブルス"),
            ("te", "te_IN", "బ్యాడ్మింటన్ డబుల్స్"),
        ] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()

            XCTAssertTrue(app.buttons[doubles].waitForExistence(timeout: 5), language)
            capture("localized_home_\(language)")
        }
    }

    func testSnookerPanelsAndSetupCommonNamePicker() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        dismissResumeBarIfNeeded(app)

        tapSportTile("斯诺克", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4), "应进入斯诺克设置页")

        // 先把「选手」折叠栏滚动到页面上半区（避开底部悬浮的「开始」按钮）再点击展开
        let setupMid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
        let playersToggle = app.buttons["选手"]
        XCTAssertTrue(playersToggle.waitForExistence(timeout: 3), "斯诺克设置页应有「选手」折叠栏")
        for _ in 0..<6 {
            if playersToggle.isHittable && playersToggle.frame.midY < 120 { break }
            setupMid.press(forDuration: 0.05, thenDragTo: setupMid.withOffset(CGVector(dx: 0, dy: -55)))
            usleep(400_000)
        }
        playersToggle.tap()
        sleep(1)

        let pickerButton = app.buttons["选择常用选手"].firstMatch
        XCTAssertTrue(pickerButton.waitForExistence(timeout: 3), "展开选手后应显示「选择常用选手」按钮")
        for _ in 0..<5 {
            if pickerButton.isHittable && pickerButton.frame.midY < 130 { break }
            setupMid.press(forDuration: 0.05, thenDragTo: setupMid.withOffset(CGVector(dx: 0, dy: -45)))
            usleep(400_000)
        }
        pickerButton.tap()
        XCTAssertTrue(app.staticTexts["选择常用选手"].waitForExistence(timeout: 3), "应弹出「选择常用选手」弹层")
        capture("dlg_01_common_name_picker")
        let close = app.buttons["取消"]
        XCTAssertTrue(close.waitForExistence(timeout: 2), "选择常用选手弹层应有顶栏关闭按钮")
        close.tap()
        sleep(1)

        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 3), "关闭弹层后应回到设置页")
        app.buttons["开始"].tap()
        sleep(2)

        // 点击左半区打开斯诺克选球面板
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        sleep(1)
        XCTAssertTrue(app.buttons["结算本局"].waitForExistence(timeout: 4), "应打开斯诺克选球面板")
        capture("dlg_02_snooker_scoring")

        // The scroll view can expose an accessibility hit point underneath
        // the fixed close footer. Scroll the button center into the viewport.
        let settle = app.buttons["结算本局"]
        let scoringClose = app.buttons["关闭"].firstMatch
        XCTAssertTrue(scoringClose.waitForExistence(timeout: 3))
        for _ in 0..<6 {
            if settle.isHittable, settle.frame.midY < scoringClose.frame.minY - 8 { break }
            smallDrag(app, dy: -45)
        }
        XCTAssertTrue(settle.isHittable && settle.frame.midY < scoringClose.frame.minY - 8)
        settle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["选择本局胜方"].waitForExistence(timeout: 4), "应弹出「选择本局胜方」")
        capture("dlg_03_snooker_settlement")

        // 关闭「选择本局胜方」再右滑返回首页
        let closeSettlement = app.buttons["取消"]
        XCTAssertTrue(closeSettlement.waitForExistence(timeout: 2), "选择本局胜方底部应有关闭按钮")
        closeSettlement.tap()
        sleep(1)
    }

    func testFootballInjuryPanelFitsScreen() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        dismissResumeBarIfNeeded(app)

        tapSportTile("足球", in: app)
        let start = app.buttons["开始"]
        XCTAssertTrue(start.waitForExistence(timeout: 4), "应进入足球设置页")
        start.tap()
        sleep(2)

        // 长按打开菜单并进入「伤停补时」
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 1.1)
        sleep(1)
        let injuryButton = app.buttons["伤停补时"]
        XCTAssertTrue(injuryButton.waitForExistence(timeout: 4), "足球长按菜单应有「伤停补时」")
        injuryButton.tap()
        sleep(1)

        XCTAssertTrue(app.buttons["+30"].waitForExistence(timeout: 3), "应弹出伤停补时面板")
        app.buttons["+30"].tap()
        sleep(1)
        capture("dlg_04_football_injury")

        let close = app.buttons["取消"]
        XCTAssertTrue(close.waitForExistence(timeout: 2), "伤停补时弹层顶栏应有关闭按钮")
        close.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["+30"].exists, "点击顶栏关闭后应关闭伤停补时面板")
    }

    func testArcheryFinishUsesSharedTieLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        dismissResumeBarIfNeeded(app)
        tapSportTile("射箭", in: app)

        let start = app.buttons["开始"]
        XCTAssertTrue(start.waitForExistence(timeout: 4))
        start.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 1.1)

        let end = app.buttons["结束比赛"]
        XCTAssertTrue(end.waitForExistence(timeout: 4))
        end.tap()
        let confirm = app.buttons["确定"].exists ? app.buttons["确定"] : app.buttons["确认"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        let title = app.staticTexts["watch_finished_title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["watch_finished_score_0"].label, "0")
        XCTAssertEqual(app.staticTexts["watch_finished_score_1"].label, "0")
        XCTAssertFalse(app.staticTexts["watch_finished_winner_badge"].exists)
        XCTAssertTrue(app.buttons["再来一场"].waitForExistence(timeout: 5))
        app.buttons["watch_finished_home"].tap()
        XCTAssertTrue(app.buttons["射箭"].waitForExistence(timeout: 4))
    }

    func testSettingsAboutAndSupportQRPages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        sleep(3)

        // 从默认首页（Tab 1）向左划两页到设置（Tab 3）
        app.swipeLeft()
        usleep(600_000)
        app.swipeLeft()
        sleep(1)
        XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 3), "应切换到设置 Tab")

        // 滚动到底部验证：意见反馈 / 联系我们 / 微信群 / 关于我们
        let wechatRow = app.buttons["微信群"]
        for _ in 0..<14 {
            if wechatRow.isHittable { break }
            smallDrag(app, dy: -65)
        }
        XCTAssertTrue(wechatRow.isHittable, "中文设置页应显示「微信群」入口")
        wechatRow.tap()
        sleep(1)
        let wechatQR = app.images["微信群"]
        XCTAssertTrue(wechatQR.waitForExistence(timeout: 3), "应展示微信群二维码")
        XCTAssertEqual(wechatQR.value as? String, "https://c.weixin.com/g/n1ltxDV-Ogi46YYG")
        capture("settings_01_wechat_group")

        let back = app.navigationBars.buttons.firstMatch
        if back.isHittable { back.tap() } else { app.swipeRight() }
        sleep(1)

        let contactRow = app.buttons["联系我们"]
        for _ in 0..<6 {
            if contactRow.isHittable { break }
            smallDrag(app, dy: 45)
        }
        XCTAssertTrue(contactRow.isHittable, "设置页应可点「联系我们」")
        contactRow.tap()
        sleep(1)
        let contactQRZh = app.images["联系我们"]
        XCTAssertTrue(contactQRZh.waitForExistence(timeout: 3))
        XCTAssertEqual(contactQRZh.value as? String, "https://jifenqi.com/contact")
        if back.isHittable { back.tap() } else { app.swipeRight() }
        sleep(1)

        let aboutRow = app.buttons["关于我们"]
        for _ in 0..<6 {
            if aboutRow.isHittable { break }
            smallDrag(app, dy: -55)
        }
        XCTAssertTrue(aboutRow.isHittable, "设置页应可点「关于我们」")
        aboutRow.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["全能计分器"].waitForExistence(timeout: 3))
        capture("settings_02_about_icon")

        // 切英文验证：隐藏微信群、联系我们切到 iscoreboard.live
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        sleep(3)
        app.swipeLeft()
        usleep(600_000)
        app.swipeLeft()
        sleep(1)
        let contactRowEn = app.buttons["Contact Us"]
        for _ in 0..<14 {
            if contactRowEn.isHittable { break }
            smallDrag(app, dy: -65)
        }
        XCTAssertTrue(contactRowEn.isHittable, "英文设置页应显示 Contact Us")
        XCTAssertFalse(app.buttons["WeChat Group"].exists, "非中文环境不应显示微信群入口")
        contactRowEn.tap()
        sleep(1)
        let contactQREn = app.images["Contact Us"]
        XCTAssertTrue(contactQREn.waitForExistence(timeout: 3))
        XCTAssertEqual(contactQREn.value as? String, "https://iscoreboard.live/contact")
        capture("settings_03_contact_en")
    }

    func testBadmintonRestOverlaysAndTennisDoublesLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-watch_scoreboard_layout", "horizontal", "-watch_set_break_enabled", "YES",
            "-watchBadmintonSetupMaxSets", "3", "-watchBadmintonSetupPointsPerSet", "21"
        ]
        app.launch()
        sleep(3)
        dismissResumeBarIfNeeded(app)

        // 1. Badminton: 11-point mid-game rest overlay + menu overlay (0px bottom black band check)
        tapSportTile("羽毛球", in: app)
        let start = app.buttons["开始"]
        XCTAssertTrue(start.waitForExistence(timeout: 4))
        start.tap()
        sleep(2)

        let leftHalf = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        for _ in 0..<11 {
            leftHalf.tap()
            usleep(120_000)
        }
        XCTAssertTrue(app.staticTexts["局中休息"].waitForExistence(timeout: 4), "羽毛球 11 分应弹出局中休息")
        capture("overlay_01_badminton_mid_game_rest")

        app.buttons["继续"].tap()
        sleep(1)

        // Score to 21 to verify between-set rest overlay
        for _ in 0..<10 {
            leftHalf.tap()
            usleep(120_000)
        }
        XCTAssertTrue(app.staticTexts["局间休息"].waitForExistence(timeout: 5), "羽毛球首局结束应弹出局间休息")
        capture("overlay_02_badminton_between_sets_rest")
        app.buttons["继续"].tap()
        sleep(1)

        // Long-press menu overlay (0px bottom black band check)
        leftHalf.press(forDuration: 1.1)
        sleep(1)
        XCTAssertTrue(app.buttons["结束比赛"].waitForExistence(timeout: 4))
        capture("overlay_03_scoreboard_menu")

        app.buttons["结束比赛"].tap()
        sleep(1)
        capture("overlay_04_finish_confirm")
        let confirmButton = app.buttons["确定"].exists ? app.buttons["确定"] : app.buttons["确认"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3))
        confirmButton.tap()
        sleep(1)
        let finishedHome = app.buttons["watch_finished_home"]
        XCTAssertTrue(finishedHome.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["watch_finished_winner_badge"].exists)
        XCTAssertEqual(app.staticTexts["watch_finished_score_0"].label, "1")
        XCTAssertEqual(app.staticTexts["watch_finished_score_1"].label, "0")
        capture("overlay_05_finished")
        finishedHome.tap()
        sleep(1)

        // 2. Tennis Doubles: 0-0 centered vs 15-0 / 40-0 with game score pinned flush to center line
        tapSportTile("网球双打", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        app.buttons["开始"].tap()
        sleep(2)
        capture("tennis_01_doubles_initial_centered")

        // Win 1 game (4 points) so primaryMeta (game count) appears, then score 1 point (15:0)
        for _ in 0..<5 {
            leftHalf.tap()
            usleep(200_000)
        }
        sleep(1)
        capture("tennis_02_doubles_with_games_15_0")

        // Score 2 more points (40:0) to confirm game count stays flush to center line
        for _ in 0..<2 {
            leftHalf.tap()
            usleep(200_000)
        }
        sleep(1)
        capture("tennis_03_doubles_with_games_40_0")
    }

    func testTennisDoublesSetsAndEmojiReplacementIcons() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        sleep(3)
        dismissResumeBarIfNeeded(app)

        // 1. Records tab empty state (EmptyStateCourt vector icon)
        app.swipeLeft()
        sleep(1)
        XCTAssertTrue(app.staticTexts["记录"].waitForExistence(timeout: 3))
        if !app.staticTexts["暂无记录"].exists {
            let clearButton = app.buttons["清空所有记录"].exists ? app.buttons["清空所有记录"] : app.buttons["清除全部"]
            for _ in 0..<8 {
                if clearButton.isHittable { break }
                smallDrag(app, dy: -65)
            }
            if clearButton.isHittable {
                clearButton.tap()
                sleep(1)
                let confirmClear = app.buttons["清空所有记录"].exists ? app.buttons["清空所有记录"] : app.buttons["清除全部"]
                if confirmClear.waitForExistence(timeout: 2) {
                    confirmClear.tap()
                    sleep(1)
                }
            }
        }
        capture("icon_01_records_empty_court")

        // 2. Tools tab -> Random Number tap icon (SF Symbol hand.tap.fill)
        app.swipeRight()
        usleep(600_000)
        app.swipeRight()
        sleep(1)
        XCTAssertTrue(app.staticTexts["工具"].waitForExistence(timeout: 3))
        let randomRow = app.buttons["随机数字"]
        XCTAssertTrue(randomRow.waitForExistence(timeout: 3))
        randomRow.tap()
        sleep(1)
        capture("icon_02_random_number_tap")
        let range10 = app.buttons["watch_random_number_range_10"]
        let range100 = app.buttons["watch_random_number_range_100"]
        XCTAssertTrue(range10.waitForExistence(timeout: 3), "应直接展示 1–10 分段选项")
        XCTAssertTrue(range100.exists, "应直接展示 1–100 分段选项")
        range10.tap()
        usleep(400_000)
        capture("icon_02b_random_number_range_10")
        range100.tap()
        usleep(300_000)
        app.swipeRight()
        sleep(1)

        // Return to Home tab (Tab 1)
        app.swipeLeft()
        sleep(1)
        XCTAssertTrue(app.staticTexts["计分"].waitForExistence(timeout: 3))

        // 3. Tennis Doubles: 4pt center gap with games only, then sets + games (40:30 and AD:40)
        tapSportTile("网球双打", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        app.buttons["开始"].tap()
        sleep(2)

        let leftHalf = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let rightHalf = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))

        // Win 1 game + 3 points (40:0, games 1:0)
        for _ in 0..<7 {
            leftHalf.tap()
            usleep(160_000)
        }
        sleep(1)
        capture("tennis_doubles_01_games_only_4pt")

        // Finish Set 1 (need 1 more point for game 2 + 16 points for games 3..6 = 17 taps)
        for _ in 0..<17 {
            leftHalf.tap()
            usleep(150_000)
        }
        let continueRest = app.buttons["继续"]
        XCTAssertTrue(continueRest.waitForExistence(timeout: 8), "打完第一盘后应出现盘间休息")
        continueRest.tap()
        sleep(1)

        // Set 2 start (sets 1:0, games 0:0, score 15:0)
        leftHalf.tap()
        sleep(1)
        capture("tennis_doubles_02_sets_only_new_set")

        // Win 1 game on left (3 more taps) + 1 game on right (4 taps) + 2nd game on left (4 taps)
        for _ in 0..<3 {
            leftHalf.tap()
            usleep(160_000)
        }
        for _ in 0..<4 {
            rightHalf.tap()
            usleep(160_000)
        }
        for _ in 0..<4 {
            leftHalf.tap()
            usleep(160_000)
        }
        // Score 40:30 (3 taps left, 2 taps right)
        for _ in 0..<3 {
            leftHalf.tap()
            usleep(160_000)
        }
        for _ in 0..<2 {
            rightHalf.tap()
            usleep(160_000)
        }
        sleep(1)
        capture("tennis_doubles_03_sets_and_games_40_30")

        // Score right once (40:40) then left once (AD:40)
        rightHalf.tap()
        usleep(220_000)
        leftHalf.tap()
        sleep(1)
        capture("tennis_doubles_04_sets_and_games_ad_40")
    }
}
