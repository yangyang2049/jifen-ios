import XCTest

/// 手表端九球（追分）3–4 人交互与开球人切换的 UI 走查。
///
/// 覆盖：首页 → 选择人数 → 九球设置 → 计分板 → 事件面板 → 二级选人（付分人 /
/// 继续击球人）→ 长按菜单「本局开球人」→ 完赛遮罩。
/// 每一步都会截图（附件名 shot_<name>），并把「页面 + 状态」写进 captions
/// 附件，供 HTML 报告生成器读取。
///
/// 开球人轮转规则（ScoreCore/NineBallChaseTransfers.swift:73-77）：
/// 大金 / 金九 由开球人打时保留球杆；普通胜 / 小金 结束后轮转到下家；
/// 让杆只把 currentShooter 指给接杆人，不换开球人。
final class WatchNineBallUITests: XCTestCase {
    private static var captionLines: [String] = []

    override func tearDownWithError() throws {
        if !Self.captionLines.isEmpty {
            let attachment = XCTAttachment(string: Self.captionLines.joined(separator: "\n"))
            attachment.name = "captions"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        Self.captionLines.removeAll()
    }

    // MARK: - 截图

    @discardableResult
    private func capture(
        _ app: XCUIApplication,
        _ name: String,
        page: String,
        state: String,
        settle: UInt32 = 1
    ) -> XCUIScreenshot {
        sleep(settle)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "shot_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        Self.captionLines.append("\(name)|\(page)|\(state)")
        print("CAPTION|\(name)|\(page)|\(state)")
        return shot
    }

    // MARK: - 导航

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        return app
    }

    /// 上一轮用例会留下未完成的续赛会话，首页顶部因此出现续赛浮条；这里先丢弃它。
    ///
    /// watchOS 的 confirmationDialog 会额外插入一个「关闭」动作按钮，且浮条上的 X
    /// 与弹层里的「放弃未完成比赛」同名；只能点可命中的那一个，否则弹层会一直挡住
    /// 首页列表，后续滑动和点击全部失效。
    private func dismissResumeBarIfNeeded(_ app: XCUIApplication) {
        let discard = app.buttons["放弃未完成比赛"]
        guard discard.waitForExistence(timeout: 2) else { return }
        discard.tap()
        sleep(2)

        let options = app.buttons.matching(NSPredicate(format: "label == %@", "放弃未完成比赛"))
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
    }

    /// watchOS 首页是超长列表，swipeUp 一屏跳 ~660pt 且带惯性，容易把目标项直接
    /// 甩到导航栏后面（不可命中）。这里用固定距离的小拖拽逐步逼近。
    private func smallDrag(_ app: XCUIApplication, dy: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        usleep(400_000)
    }

    private func tapSportTile(_ title: String, in app: XCUIApplication) {
        let tile = app.buttons[title]
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "首页未出现项目「\(title)」")
        for _ in 0..<16 {
            if tile.isHittable { break }
            let midY = tile.frame.midY
            if midY > 200 {
                smallDrag(app, dy: -40)
            } else if midY < 90 {
                smallDrag(app, dy: 30)
            } else {
                smallDrag(app, dy: -20)
            }
        }
        XCTAssertTrue(tile.isHittable, "首页项目「\(title)」未滚动到可点击位置")
        tile.tap()
        sleep(1)
    }

    /// 「4 人」这一行贴着卡片下沿（frame 高 68pt，一半在卡片外），直接 tap 元素
    /// 中心会落到关闭弹层的遮罩上；这里点按钮上部坐标，并在失败时重试整条路径。
    private func selectPlayerCount(_ players: Int, in app: XCUIApplication) {
        for attempt in 0..<3 {
            let countButton = app.buttons["\(players) 人"]
            if countButton.waitForExistence(timeout: 4) {
                sleep(1)
                countButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
                sleep(1)
                if app.buttons["开始"].waitForExistence(timeout: 3) { return }
            }
            if attempt < 2 {
                tapSportTile("追分", in: app)
            }
        }
        XCTFail("未能进入九球设置页（选择人数）")
    }

    private func startNineBall(
        players: Int,
        in app: XCUIApplication,
        setupShotPrefix: String? = nil
    ) {
        tapSportTile("追分", in: app)
        selectPlayerCount(players, in: app)
        if let prefix = setupShotPrefix {
            capture(
                app, "\(prefix)_setup",
                page: "第 4 页 · \(players) 人九球设置（首屏）",
                state: "首屏只能看到前两个选手名称行；第 3/4 行落在底部「开始」按钮下面"
            )
            smallDrag(app, dy: -50)
            smallDrag(app, dy: -50)
            capture(
                app, "\(prefix)_setup_scrolled",
                page: "第 4 页 · \(players) 人九球设置（向上滚动后）",
                state: "滚动后才露出第 3（4）个选手名称行；「开始」始终悬浮在底部"
            )
        }
        let start = app.buttons["开始"]
        XCTAssertTrue(start.waitForExistence(timeout: 3), "未出现九球设置页")
        start.tap()
        sleep(2)
    }

    // MARK: - 触点

    private func playerPoint(_ index: Int, players: Int) -> CGVector {
        switch players {
        case 2:
            return CGVector(dx: index == 0 ? 0.25 : 0.75, dy: 0.5)
        case 3:
            let xs: [Double] = [1.0 / 6.0, 0.5, 5.0 / 6.0]
            return CGVector(dx: xs[index], dy: 0.5)
        default:
            let xs: [Double] = [0.25, 0.75, 0.25, 0.75]
            let ys: [Double] = [0.28, 0.28, 0.72, 0.72]
            return CGVector(dx: xs[index], dy: ys[index])
        }
    }

    private func tapPlayer(_ index: Int, players: Int, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: playerPoint(index, players: players)).tap()
        sleep(1)
    }

    private func longPressPlayer(_ index: Int, players: Int, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: playerPoint(index, players: players)).press(forDuration: 1.1)
        sleep(1)
    }

    private func button(beginningWith prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func closeOverlay(_ app: XCUIApplication) {
        let close = app.buttons["关闭"]
        if close.waitForExistence(timeout: 2) { close.tap(); sleep(1) }
    }

    // MARK: - 3 人

    func testThreePlayerBreakerAndPayerFlows() throws {
        let app = launchApp()
        dismissResumeBarIfNeeded(app)
        capture(
            app, "3p_01_home",
            page: "第 1 页 · 首页（计分 Tab）",
            state: "默认项目列表；点「追分」进入九球"
        )

        tapSportTile("追分", in: app)
        capture(
            app, "3p_02_players",
            page: "第 2 页 · 选择人数",
            state: "九球开局前选 2/3/4 人；本次选「3 人」"
        )

        app.buttons["3 人"].tap()
        sleep(1)
        capture(
            app, "3p_03_setup",
            page: "第 3 页 · 九球设置（首屏）",
            state: "首屏只能看到选手 1/2；选手 3 的名称行被底部「开始」按钮盖住"
        )
        smallDrag(app, dy: -50)
        smallDrag(app, dy: -50)
        capture(
            app, "3p_03b_setup_scrolled",
            page: "第 3 页 · 九球设置（向上滚动后）",
            state: "滚动后才露出选手 3 的名称行；「开始」始终悬浮在底部"
        )

        app.buttons["开始"].tap()
        sleep(2)
        capture(
            app, "3p_04_board",
            page: "第 4 页 · 3 人计分板（初始）",
            state: "0 : 0 : 0；选手 1 姓名左侧有白色球杆徽标＝当前开球人"
        )

        tapPlayer(0, players: 3, in: app)
        XCTAssertTrue(
            app.staticTexts["开球"].waitForExistence(timeout: 3),
            "开球人的事件面板标题应带「开球」徽标"
        )
        XCTAssertTrue(button(beginningWith: "大金", in: app).isEnabled, "开球人应能打大金")
        capture(
            app, "3p_05_event_panel_breaker",
            page: "第 4 页 · 事件面板（选手 1 ＝ 开球人）",
            state: "标题右侧绿色「开球」徽标；大金可用（只有开球人能打）"
        )

        button(beginningWith: "普通胜", in: app).tap()
        sleep(1)
        XCTAssertTrue(
            app.staticTexts["选择付分人"].waitForExistence(timeout: 3),
            "3 人普通胜应进入「选择付分人」二级页"
        )
        let recommendedPayer = button(beginningWith: "选手 3", in: app)
        XCTAssertTrue(recommendedPayer.exists, "推荐付分人应为上家（选手 3）")
        capture(
            app, "3p_06_payer_picker",
            page: "第 4 页 · 二级选择：付分人",
            state: "普通胜 → 1 步选付分人；绿框推荐「上家」（选手 3），右侧显示 -4"
        )

        recommendedPayer.tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["选择付分人"].exists, "选完付分人后二级面板应关闭")
        capture(
            app, "3p_07_after_normal_win",
            page: "第 4 页 · 计分结果（普通胜）",
            state: "选手 1 +4、选手 3 -4；二级面板自动关闭；本局结束 → 开球人轮转到选手 2"
        )

        longPressPlayer(0, players: 3, in: app)
        XCTAssertTrue(app.buttons["本局开球人"].waitForExistence(timeout: 3))
        capture(
            app, "3p_08_menu",
            page: "第 4 页 · 长按菜单",
            state: "撤销 / 重新开始 / 本局开球人 / 结束比赛"
        )

        app.buttons["本局开球人"].tap()
        sleep(1)
        let rotatedBreakerRow = app.buttons["选手 2"]
        XCTAssertTrue(rotatedBreakerRow.waitForExistence(timeout: 3), "未出现开球人选择面板")
        XCTAssertTrue(rotatedBreakerRow.isSelected, "普通胜后当前开球人应为选手 2")
        capture(
            app, "3p_09_breaker_picker",
            page: "第 4 页 · 本局开球人面板",
            state: "全屏选人列表；对勾落在普通胜后自动轮转到的选手 2"
        )

        app.buttons["选手 3"].tap()
        sleep(1)
        capture(
            app, "3p_10_breaker_switched",
            page: "第 4 页 · 计分板（开球人改成选手 3）",
            state: "球杆徽标从选手 2 移到选手 3；比分保持不变"
        )

        tapPlayer(0, players: 3, in: app)
        XCTAssertFalse(app.staticTexts["开球"].exists, "非开球人的面板不应带「开球」徽标")
        XCTAssertFalse(button(beginningWith: "大金", in: app).isEnabled, "非开球人的大金应置灰")
        capture(
            app, "3p_11_event_panel_nonbreaker",
            page: "第 4 页 · 事件面板（选手 1 ≠ 开球人）",
            state: "无「开球」徽标；大金置灰，其余事件仍可用"
        )

        button(beginningWith: "小金", in: app).tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["选择付分人"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            button(beginningWith: "选手 3", in: app).label.contains("开球"),
            "非开球人打小金时推荐「开球」付分"
        )
        capture(
            app, "3p_12_smallgold_picker",
            page: "第 4 页 · 二级选择：小金付分人",
            state: "单人付分的小金 → 推荐「开球」（选手 3），右侧 -7"
        )

        button(beginningWith: "选手 2", in: app).tap()
        sleep(1)
        capture(
            app, "3p_13_after_smallgold",
            page: "第 4 页 · 计分结果（小金）",
            state: "选手 1 +7（累计 11）、选手 2 -7"
        )

        tapPlayer(0, players: 3, in: app)
        button(beginningWith: "让杆", in: app).tap()
        sleep(1)
        XCTAssertTrue(
            app.staticTexts["选择继续击球人"].waitForExistence(timeout: 3),
            "3 人让杆应进入「选择继续击球人」二级页"
        )
        XCTAssertTrue(
            button(beginningWith: "选手 2", in: app).label.contains("下家"),
            "让杆推荐下家（选手 2）"
        )
        capture(
            app, "3p_14_continue_picker",
            page: "第 4 页 · 二级选择：继续击球人",
            state: "让杆 → 推荐「下家」（选手 2），行尾「接杆」标记，不计分"
        )

        button(beginningWith: "选手 2", in: app).tap()
        sleep(1)
        capture(
            app, "3p_15_after_handoff",
            page: "第 4 页 · 计分结果（让杆）",
            state: "交给选手 2 继续，比分不变；让杆不换开球人"
        )

        // 让杆后开球人仍是选手 2（endsRack=false），由它打大金验证「1 步直出」。
        tapPlayer(1, players: 3, in: app)
        XCTAssertTrue(
            app.staticTexts["开球"].waitForExistence(timeout: 3),
            "让杆后开球人（选手 2）的面板应带「开球」徽标"
        )
        XCTAssertTrue(button(beginningWith: "大金", in: app).isEnabled, "开球人的大金应可用")
        capture(
            app, "3p_16_event_panel_breaker_big_gold",
            page: "第 4 页 · 事件面板（选手 2 ＝ 开球人）",
            state: "让杆不换开球人：选手 2 的面板仍带「开球」徽标、大金可用"
        )

        button(beginningWith: "大金", in: app).tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["选择付分人"].exists, "大金应 1 步直接计分，不弹二级页")
        capture(
            app, "3p_17_after_big_gold",
            page: "第 4 页 · 计分结果（大金）",
            state: "大金 1 步直出：选手 1 只剩 1 分、选手 3 -14、选手 2 由 -7 变 13；无二级选人面板"
        )

        longPressPlayer(1, players: 3, in: app)
        if app.buttons["结束比赛"].waitForExistence(timeout: 3) {
            app.buttons["结束比赛"].tap()
            sleep(2)
            capture(
                app, "3p_18_finish_confirm",
                page: "第 4 页 · 结束比赛二次确认",
                state: "长按 → 结束比赛 → 「结束比赛？」确认弹层（取消 / 确认）"
            )
            let confirm = app.buttons["确认"]
            if confirm.waitForExistence(timeout: 2) {
                confirm.tap()
            } else {
                // watchOS 上确认按钮有时没有独立可查询的标签，按弹层里 √ 的位置兜底。
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.66, dy: 0.63)).tap()
            }
            sleep(2)
            capture(
                app, "3p_19_finished",
                page: "第 4 页 · 完赛遮罩",
                state: "三人最终比分 / 胜者文案 / 再来一局；二级面板与开球人面板均已关闭"
            )
        }
    }

    // MARK: - 4 人

    func testFourPlayerQuadrantFlows() throws {
        let app = launchApp()
        dismissResumeBarIfNeeded(app)
        startNineBall(players: 4, in: app, setupShotPrefix: "4p_00")
        capture(
            app, "4p_01_board",
            page: "第 4 页 · 4 人计分板（2×2 棋盘）",
            state: "四个象限各一名选手；选手 1 姓名左侧带球杆徽标（开球人）"
        )

        tapPlayer(1, players: 4, in: app)
        XCTAssertFalse(app.staticTexts["开球"].exists)
        capture(
            app, "4p_02_event_panel",
            page: "第 4 页 · 4 人事件面板（选手 2）",
            state: "紧凑两列事件网格；非开球人无「开球」徽标、大金置灰"
        )

        button(beginningWith: "普通胜", in: app).tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["选择付分人"].waitForExistence(timeout: 3))
        capture(
            app, "4p_03_payer_picker",
            page: "第 4 页 · 4 人付分人选择",
            state: "3 个候选（选手 1/3/4）；绿框推荐上家（选手 1），-4"
        )

        button(beginningWith: "选手 4", in: app).tap()
        sleep(1)
        capture(
            app, "4p_04_after_normal_win",
            page: "第 4 页 · 计分结果（4 人普通胜）",
            state: "选手 2 +4、选手 4 -4；开球人轮转到选手 3"
        )

        longPressPlayer(1, players: 4, in: app)
        XCTAssertTrue(app.buttons["本局开球人"].waitForExistence(timeout: 3))
        capture(
            app, "4p_05_menu",
            page: "第 4 页 · 4 人长按菜单",
            state: "同样有「本局开球人」入口"
        )

        app.buttons["本局开球人"].tap()
        sleep(1)
        let rotated = app.buttons["选手 3"]
        XCTAssertTrue(rotated.waitForExistence(timeout: 3), "未出现 4 人开球人面板")
        XCTAssertTrue(rotated.isSelected, "普通胜后当前开球人应为选手 3")
        capture(
            app, "4p_06_breaker_picker",
            page: "第 4 页 · 4 人本局开球人面板",
            state: "4 行紧凑列表；对勾落在轮转后的选手 3"
        )

        app.buttons["选手 4"].tap()
        sleep(1)
        capture(
            app, "4p_07_breaker_switched",
            page: "第 4 页 · 4 人计分板（开球人＝选手 4）",
            state: "球杆徽标移到右下角选手 4"
        )

        tapPlayer(1, players: 4, in: app)
        button(beginningWith: "小金", in: app).tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["选择付分人"].waitForExistence(timeout: 3))
        capture(
            app, "4p_08_smallgold_picker",
            page: "第 4 页 · 4 人小金付分人",
            state: "非开球人小金 → 推荐「开球」（选手 4），-7"
        )
    }

    // MARK: - 2 人

    func testTwoPlayerSmallGoldUnavailableForBreaker() throws {
        let app = launchApp()
        dismissResumeBarIfNeeded(app)
        startNineBall(players: 2, in: app)
        capture(
            app, "2p_01_board",
            page: "第 4 页 · 2 人计分板",
            state: "两人横向布局；选手 1 姓名左侧带球杆徽标（开球人）"
        )

        tapPlayer(0, players: 2, in: app)
        XCTAssertTrue(app.staticTexts["开球"].waitForExistence(timeout: 3))
        XCTAssertFalse(
            button(beginningWith: "小金", in: app).isEnabled,
            "2 人单人付分下开球人的小金应与手机端一致置灰"
        )
        capture(
            app, "2p_02_event_panel_breaker",
            page: "第 4 页 · 2 人事件面板（开球人）",
            state: "开球人打小金无意义 → 「小金」置灰禁用（对齐手机端）"
        )

        closeOverlay(app)
        tapPlayer(1, players: 2, in: app)
        XCTAssertTrue(button(beginningWith: "小金", in: app).isEnabled)
        capture(
            app, "2p_03_event_panel_opponent",
            page: "第 4 页 · 2 人事件面板（非开球人）",
            state: "非开球人「小金」可用；2 人不弹二级选人"
        )

        button(beginningWith: "小金", in: app).tap()
        sleep(1)
        XCTAssertFalse(app.staticTexts["选择付分人"].exists, "2 人小金不应出现二级选人")
        capture(
            app, "2p_04_after_smallgold",
            page: "第 4 页 · 计分结果（2 人小金）",
            state: "选手 2 +7、开球人选手 1 -7（默认开球人付分）"
        )
    }
}
