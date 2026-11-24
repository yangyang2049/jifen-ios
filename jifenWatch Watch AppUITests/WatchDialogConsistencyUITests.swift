import XCTest

/// 手表端全量弹层一致性与小屏（40mm）防溢出走查：
/// 1. 比赛设置「选择选手」常用名弹层（统一顶栏左标题 + 右关闭钮）
/// 2. 斯诺克选球面板（顶部避让系统时钟 + 犯规胶囊不挤压）
/// 3. 斯诺克「选择本局胜者」（关闭钮移至底部，不再与时钟重叠）
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

        // 滚到底部点击「结算本局」
        for _ in 0..<4 {
            if app.buttons["结算本局"].isHittable { break }
            smallDrag(app, dy: -45)
        }
        app.buttons["结算本局"].tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["选择本局胜者"].waitForExistence(timeout: 4), "应弹出「选择本局胜者」")
        capture("dlg_03_snooker_settlement")

        // 关闭「选择本局胜者」再右滑返回首页
        let closeSettlement = app.buttons["取消"]
        XCTAssertTrue(closeSettlement.waitForExistence(timeout: 2), "选择本局胜者底部应有关闭按钮")
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

        // 滚动到底部验证：意见反馈 / 联系我们 / 用户微信群 / 关于我们
        let wechatRow = app.buttons["用户微信群"]
        for _ in 0..<14 {
            if wechatRow.isHittable { break }
            smallDrag(app, dy: -65)
        }
        XCTAssertTrue(wechatRow.isHittable, "中文设置页应显示「用户微信群」入口")
        wechatRow.tap()
        sleep(1)
        let wechatQR = app.images["用户微信群"]
        XCTAssertTrue(wechatQR.waitForExistence(timeout: 3), "应展示用户微信群二维码")
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
}
