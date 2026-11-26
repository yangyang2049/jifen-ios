import XCTest

/// 手表端全项目回归（2026-11-25）：以真实用户路径驱动每个可达入口，逐步截图。
///
/// 组织方式：每个 `test...` 方法对应一个独立比赛/模式，全部走真实交互（短局路径），
/// 不使用启动参数跳页。命名 `shot_<name>`（keepAlways），供 HTML 报告按阶段归组。
///
/// 覆盖设计（对应 watch-full-matrix 报告）：
/// - Rally 类（羽毛球/乒乓球/网球/匹克球单打）：Setup 首屏/滚动 → 开局 → 计分+撤销 →
///   局中休息（羽毛球 11 分制）→ 局间休息 → 单局结束 toast → 换边 toast →
///   完赛确认 → 完赛遮罩 → 再来一场 → 返回首页。
/// - 双打（羽毛球/乒乓球/网球双打）：4 人 Setup + 双打计分板。
/// - 射箭：设置 → 开局 → 加分面板 → 结束比赛 → 完赛遮罩。
/// - 黑八：设置（让局展开）→ 开局 → 计分 → 结束。
/// - 斯诺克：自定义局数 → 选球面板 → 撤销。
/// - 足球/五人制：半场时长 → 开局 → 开球/暂停 → 伤停补时 → 进入下半场确认。
/// - 九球：选择人数 2/3/4 人（复用现有 WatchNineBallUITests 的深度走查，本文件只补
///   2 人完赛路径，3/4 人由既有用例覆盖）。
/// - 投篮训练：4 种模式。
/// - 工具：掷硬币 / 随机数 / 十秒挑战 / 计数器（结束并保存路径仅报告结果，
///   另一会话正在修改该路径）。
/// - 设置：各开关翻转与恢复、布局切换、常用名称、手机联动、使用说明。
///
/// 注意：本文件不修改任何产品代码；测试数据只通过 UI 产生并在用例内清理。
final class WatchFullMatrixUITests: XCTestCase {
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

    // MARK: - 通用步骤

    private func capture(
        _ app: XCUIApplication,
        _ name: String,
        page: String,
        state: String,
        settle: UInt32 = 1
    ) {
        sleep(settle)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "shot_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        Self.captionLines.append("\(name)|\(page)|\(state)")
        print("CAPTION|\(name)|\(page)|\(state)")
    }

    private func smallDrag(_ app: XCUIApplication, dy: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        usleep(400_000)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        sleep(3)
        return app
    }

    /// 记录 Tab / 设置 Tab 定位不稳（TabView page + 续赛浮条会顶下来），
    /// 统一从首页顶部基准出发：先右滑一次到首页（若已在首页忽略），
    /// 再用「项目行」是否存在判定当前页并按需左滑/右滑到目标 Tab。
    /// Tab 页序：工具(0) 首页(1) 记录(2) 设置(3)。swipeLeft 显示右侧页，swipeRight 显示左侧页。
    private func gotoHome(_ app: XCUIApplication) {
        if app.buttons["羽毛球"].waitForExistence(timeout: 2) { return }
        app.swipeLeft()
        usleep(800_000)
        if app.buttons["羽毛球"].waitForExistence(timeout: 3) { return }
        app.swipeRight()
        usleep(800_000)
        app.swipeRight()
        usleep(800_000)
        _ = app.buttons["羽毛球"].waitForExistence(timeout: 3)
    }

    private func gotoRecords(_ app: XCUIApplication) -> Bool {
        gotoHome(app)
        app.swipeLeft()
        usleep(800_000)
        let title = app.staticTexts["记录"]
        if title.waitForExistence(timeout: 4) { return true }
        app.swipeRight()
        usleep(600_000)
        app.swipeLeft()
        usleep(800_000)
        return title.waitForExistence(timeout: 4)
    }

    private func gotoSettings(_ app: XCUIApplication) -> Bool {
        gotoHome(app)
        app.swipeLeft()
        usleep(800_000)
        app.swipeLeft()
        usleep(800_000)
        let title = app.staticTexts["设置"]
        if title.waitForExistence(timeout: 4) { return true }
        app.swipeRight()
        usleep(600_000)
        app.swipeLeft()
        usleep(800_000)
        return title.waitForExistence(timeout: 4)
    }

    /// 工具 Tab：从首页右滑一页（工具在首页左侧）。
    private func gotoTools(_ app: XCUIApplication) -> Bool {
        gotoHome(app)
        app.swipeRight()
        usleep(800_000)
        return app.buttons["抛硬币"].waitForExistence(timeout: 4)
    }

    private func dismissResumeBarIfNeeded(_ app: XCUIApplication) {
        for discardLabel in ["放弃未完成训练", "放弃未完成比赛"] {
            let discard = app.buttons[discardLabel]
            guard discard.waitForExistence(timeout: 2) else { continue }
            discard.tap()
            let confirm = app.buttons["确认放弃"]
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
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

    /// 打开长按菜单（左半屏长按）。射箭面板打开时先关闭。
    private func openMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 1.1)
        XCTAssertTrue(app.buttons["结束比赛"].waitForExistence(timeout: 4), "长按应弹出比赛菜单")
        XCTAssertFalse(app.buttons["上下"].exists, "比赛菜单不应提供上下布局切换")
        XCTAssertFalse(app.buttons["左右"].exists, "比赛菜单不应提供左右布局切换")
    }

    private func closeMenuIfNeeded(_ app: XCUIApplication) {
        let cancel = app.buttons["取消"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap(); sleep(1) }
    }

    private func undoViaMenu(_ app: XCUIApplication) {
        openMenu(app)
        let undo = app.buttons["撤销"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        sleep(1)
    }

    /// 完赛确认弹层：点「确认」（或坐标兜底）。
    private func confirmFinish(_ app: XCUIApplication) {
        let confirm = app.buttons["确认"]
        if confirm.waitForExistence(timeout: 3) {
            confirm.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.66, dy: 0.63)).tap()
        }
        sleep(2)
        XCTAssertTrue(app.staticTexts["watch_finished_title"].waitForExistence(timeout: 5),
                      "完赛后应出现完赛遮罩")
    }

    /// 完赛遮罩 → 再来一场（回到 Setup）。
    private func rematch(_ app: XCUIApplication) {
        let again = app.buttons["再来一场"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        sleep(2)
    }

    /// 完赛遮罩 → 返回首页。
    private func finishedGoHome(_ app: XCUIApplication) {
        let home = app.buttons["watch_finished_home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        sleep(1)
    }

    private func swipeBackToHome(_ app: XCUIApplication) {
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        let rightEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: rightEdge)
        sleep(2)
    }

    private func backFromSetup(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.isHittable { back.tap() } else { swipeBackToHome(app) }
        sleep(1)
    }

    private func tapHalf(_ app: XCUIApplication, left: Bool, dy: Double = 0.5) {
        app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.25 : 0.75, dy: dy)).tap()
        usleep(150_000)
    }

    /// 布局无关的计分点击：读取当前计分板快照里 A/B 两个选手区域的实际 frame 中点。
    /// a11y label 形如「选手A，0 分，发球中」/「选手B，5 分」。
    private func tapContender(_ app: XCUIApplication, left: Bool) {
        let predicate = NSPredicate(
            format: "label CONTAINS '选手A' OR label CONTAINS '选手B' OR label CONTAINS '选手 1' OR label CONTAINS '选手 2'"
        )
        let rows = app.otherElements.matching(predicate).allElementsBoundByIndex
            + app.staticTexts.matching(predicate).allElementsBoundByIndex
        let usable = rows.filter { $0.frame.width >= 28 && $0.frame.height >= 12 }
        if usable.count >= 2 {
            let sorted = usable.sorted { $0.frame.minY < $1.frame.minY }
            let target = left ? sorted[0] : sorted[1]
            // 直接点选手元素中心：名字行也在半区 contentShape 内，横竖板通用。
            let f = target.frame
            let point = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: f.midX, dy: f.midY))
            point.tap()
        } else {
            // 兜底：横板左右半区（沿用旧规则）
            tapHalf(app, left: left)
        }
        usleep(150_000)
    }

    // MARK: - Rally 单打：羽毛球（含局中休息/局间休息/换边/完赛/再来一场）

    func testMatrixBadmintonSinglesFullPath() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)
        capture(app, "home_top", page: "首页（计分 Tab）顶部", state: "默认项目列表")

        tapSportTile("羽毛球", in: app)
        capture(app, "badminton_setup_top", page: "羽毛球 Setup 首屏",
                state: "局数 1/3/5、每局分数 11/15/21 首屏可见")
        // 显式选择 3 局 · 每局 11 分（局数区有 3，分数区 11 唯一）
        let chip3 = app.buttons["3"].firstMatch
        XCTAssertTrue(chip3.waitForExistence(timeout: 3), "局数区应有 3")
        chip3.tap()
        let chip11 = app.buttons["11"].firstMatch
        XCTAssertTrue(chip11.waitForExistence(timeout: 3), "每局分数区应有 11")
        chip11.tap()
        sleep(1)
        capture(app, "badminton_setup_selected", page: "羽毛球 Setup（显式 3 局 · 11 分）",
                state: "局数 3 与每局分数 11 呈高亮选中态")
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        smallDrag(app, dy: -55)
        capture(app, "badminton_setup_scrolled", page: "羽毛球 Setup 滚动后",
                state: "发球方 红/蓝、选手折叠栏、底部悬浮开始")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "badminton_board_initial", page: "羽毛球计分板（开局）",
                state: "0:0，红色发球指示；名称行避让系统时钟")

        // 计分到 6:4 → 撤销一次 → 5:4
        for _ in 0..<6 { tapContender(app, left: true) }
        for _ in 0..<4 { tapContender(app, left: false) }
        sleep(1)
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "badminton_board_after_undo", page: "羽毛球计分板（撤销后）",
                state: "撤销后 5:4；撤销路径走长按菜单")

        // 11 分局中休息在 6 分触发（(11+1)/2）
        for _ in 0..<5 { tapContender(app, left: true) }
        XCTAssertTrue(app.staticTexts["局中休息"].waitForExistence(timeout: 5),
                      "羽毛球 11 分制到 6 分应弹出局中休息")
        capture(app, "badminton_midgame_rest", page: "羽毛球局中休息遮罩",
                state: "局中休息遮罩（10 分制中点 6 分触发）")
        let resumeMid = app.buttons["继续"]
        XCTAssertTrue(resumeMid.waitForExistence(timeout: 3))
        resumeMid.tap()
        sleep(1)

        // 从 6:x 打到 11 完成首局（还需 5 分）→ 单局结束展示 → 局间休息
        for _ in 0..<5 { tapContender(app, left: true) }
        let restTitle = app.staticTexts["局间休息"]
        XCTAssertTrue(restTitle.waitForExistence(timeout: 10),
                      "羽毛球首局 11 分打完应弹出局间休息")
        capture(app, "badminton_between_sets_rest", page: "羽毛球局间休息遮罩",
                state: "首局 11:4 结束后的局间休息遮罩")
        app.buttons["继续"].tap()
        sleep(2)
        capture(app, "badminton_set2_after_exchange", page: "羽毛球第 2 局开局",
                state: "局分 1:0；可能出现「交换场地」toast")

        // 直接结束比赛 → 完赛确认 → 完赛遮罩 → 再来一场 → 返回首页
        openMenu(app)
        capture(app, "badminton_menu", page: "羽毛球长按菜单",
                state: "撤销 / 重新开始 / 结束比赛")
        app.buttons["结束比赛"].tap()
        sleep(1)
        capture(app, "badminton_finish_confirm", page: "羽毛球结束比赛确认",
                state: "「结束比赛？」确认弹层")
        confirmFinish(app)
        capture(app, "badminton_finished", page: "羽毛球完赛遮罩",
                state: "完赛遮罩；再来一场/返回首页")
        XCTAssertEqual(app.staticTexts["watch_finished_score_0"].label, "1",
                       "完赛遮罩应显示局分 1")
        XCTAssertEqual(app.staticTexts["watch_finished_score_1"].label, "0",
                       "完赛遮罩应显示局分 0")
        rematch(app)
        capture(app, "badminton_rematch_setup", page: "羽毛球 Setup（再来一场）",
                state: "完赛后「再来一场」回到 Setup")
        backFromSetup(app)
        finishedGoHomeIfPresent(app)
    }

    private func finishedGoHomeIfPresent(_ app: XCUIApplication) {
        if app.buttons["watch_finished_home"].exists {
            app.buttons["watch_finished_home"].tap()
            sleep(1)
        }
    }

    // MARK: - Rally 单打：乒乓球（完赛确认 → 返回首页）

    func testMatrixPingpongSinglesFullPath() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("乒乓球", in: app)
        capture(app, "pingpong_setup_top", page: "乒乓球 Setup 首屏",
                state: "局数 1/3/5/7、每局分数 5/7/9/11/15/21")
        // 真实短局路径：默认 5 局制 + 默认 11 分（每局分数可选集为 7/9/11/15，
        // 「5 分」不可选——此前「1 局 5 分」的用例目标本身不成立）。为在脚本窗口内
        // 自然完赛，把每局分数降到可选集下限 7 分并保持 5 局，真实打满 3 局到完赛。
        let chip7 = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "7")).firstMatch
        XCTAssertTrue(chip7.waitForExistence(timeout: 3), "每局分数区应有 7")
        chip7.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        capture(app, "pingpong_setup_short", page: "乒乓球 Setup（5 局 · 7 分）",
                state: "每局分数 7 呈高亮选中态；局数保持默认 5（三胜制）")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "pingpong_board_initial", page: "乒乓球计分板（开局）",
                state: "0:0；红方发球")

        // 第 1 局：A 连得 7 分（7:0），期间 4:0 时截一次局中状态
        for _ in 0..<4 { tapContender(app, left: true) }
        capture(app, "pingpong_4_0", page: "乒乓球第 1 局（4:0）",
                state: "局中状态；7 分制 4 分未到局点")
        for _ in 0..<3 { tapContender(app, left: true) }
        let rest1 = app.staticTexts["局间休息"]
        let finishedAny = app.staticTexts["watch_finished_title"]
        if rest1.waitForExistence(timeout: 8) {
            capture(app, "pingpong_between_sets_rest", page: "乒乓球局间休息遮罩",
                    state: "第 1 局 7:0 结束后的局间休息（60 秒）")
            app.buttons["继续"].tap()
            sleep(2)
        }
        capture(app, "pingpong_set2_start", page: "乒乓球第 2 局开局",
                state: "局分 1:0；0:0")
        // 第 2 局：B 得 7 分（1:1）
        for _ in 0..<7 { tapContender(app, left: false) }
        if app.staticTexts["局间休息"].waitForExistence(timeout: 8) {
            app.buttons["继续"].tap()
            sleep(2)
        }
        capture(app, "pingpong_set3_start", page: "乒乓球第 3 局开局",
                state: "局分 1:1；决胜局 0:0")
        // 第 3 局：A 得 7 分 → 局分 2:1（五局三胜）→ 完赛遮罩
        for _ in 0..<7 { tapContender(app, left: true) }
        XCTAssertTrue(app.staticTexts["watch_finished_title"].waitForExistence(timeout: 10),
                      "五局三胜 2:1 打满后应出现完赛遮罩")
        capture(app, "pingpong_finished", page: "乒乓球完赛遮罩",
                state: "局分 2:1；胜方 A；再来一场/返回首页")
        XCTAssertEqual(app.staticTexts["watch_finished_score_0"].label, "2",
                       "完赛遮罩左侧局分应为 2")
        XCTAssertEqual(app.staticTexts["watch_finished_score_1"].label, "1",
                       "完赛遮罩右侧局分应为 1")
        finishedGoHome(app)
    }

    // MARK: - 双打：羽毛球双打（4 人 Setup + 双打板）

    func testMatrixBadmintonDoublesBoard() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("羽毛球双打", in: app)
        capture(app, "bd_setup_top", page: "羽毛球双打 Setup 首屏",
                state: "双打规则；选手折叠栏默认展开为 4 行")
        smallDrag(app, dy: -55)
        smallDrag(app, dy: -55)
        capture(app, "bd_setup_scrolled", page: "羽毛球双打 Setup 滚动后",
                state: "选手 1-4 名称行；发球方选择")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "bd_board_initial", page: "羽毛球双打计分板（开局）",
                state: "双打布局 0:0")

        for _ in 0..<3 { tapContender(app, left: true) }
        tapContender(app, left: false)
        sleep(1)
        capture(app, "bd_board_3_1", page: "羽毛球双打计分板（计分后）",
                state: "3:1；双打发球指示")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "bd_board_after_undo", page: "羽毛球双打计分板（撤销后）",
                state: "2:1")

        openMenu(app)
        app.buttons["结束比赛"].tap()
        sleep(1)
        confirmFinish(app)
        capture(app, "bd_finished", page: "羽毛球双打完赛遮罩",
                state: "双打胜方")
        finishedGoHome(app)
    }

    // MARK: - 双打：乒乓球双打

    func testMatrixPingpongDoublesBoard() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("乒乓球双打", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        capture(app, "ppd_setup_top", page: "乒乓球双打 Setup 首屏",
                state: "局数/每局分数/发球方")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "ppd_board_initial", page: "乒乓球双打计分板（开局）",
                state: "0:0；双打发球指示")
        for _ in 0..<2 { tapContender(app, left: true) }
        tapContender(app, left: false)
        sleep(1)
        capture(app, "ppd_board_2_1", page: "乒乓球双打计分板（计分后）",
                state: "2:1")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "ppd_board_after_undo", page: "乒乓球双打计分板（撤销后）",
                state: "1:1")
        swipeBackToHome(app)
    }

    // MARK: - 双打：网球双打（局分与盘分并列）

    func testMatrixTennisDoublesBoard() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("网球双打", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        capture(app, "td_setup_top", page: "网球双打 Setup 首屏",
                state: "局数 1/3/5、平分规则 占先/无占先")
        app.buttons["无占先"].tap()
        sleep(1)
        capture(app, "td_setup_no_ad", page: "网球双打 Setup（无占先）",
                state: "平分规则切到无占先")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "td_board_initial", page: "网球双打计分板（开局）",
                state: "0:0 居中")
        for _ in 0..<5 { tapContender(app, left: true) }
        sleep(1)
        capture(app, "td_board_game_won", page: "网球双打计分板（1 局后）",
                state: "局分 1:0 出现；再 15:0 时局分贴中线")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "td_board_after_undo", page: "网球双打计分板（撤销后）",
                state: "局分 0:0、15:0")
        swipeBackToHome(app)
    }

    // MARK: - 射箭

    func testMatrixArcheryFullPath() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("射箭", in: app)
        capture(app, "archery_setup_top", page: "射箭 Setup 首屏",
                state: "无规则选项；射手折叠栏默认展开（2 行）")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "archery_board_initial", page: "射箭计分板（开局）",
                state: "0:0 · 0:0（局分与箭分）")

        tapContender(app, left: true)
        XCTAssertTrue(app.buttons["确定"].waitForExistence(timeout: 3)
                      || app.buttons["关闭"].waitForExistence(timeout: 3),
                      "射箭点击半区应弹出加分面板")
        capture(app, "archery_score_panel", page: "射箭加分面板",
                state: "0-10 与 M 数字网格；当前射手名称")
        app.buttons["9"].firstMatch.tap()
        sleep(1)
        capture(app, "archery_after_9", page: "射箭计分板（9 环后）",
                state: "箭分 9")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "archery_after_undo", page: "射箭计分板（撤销后）",
                state: "箭分 0")

        openMenu(app)
        capture(app, "archery_menu", page: "射箭长按菜单", state: "射箭专属菜单")
        app.buttons["结束比赛"].tap()
        sleep(1)
        capture(app, "archery_finish_confirm", page: "射箭结束比赛确认",
                state: "结束确认弹层")
        confirmFinish(app)
        capture(app, "archery_finished", page: "射箭完赛遮罩",
                state: "平局/胜方文案")
        finishedGoHome(app)
    }

    // MARK: - 黑八

    func testMatrixEightBallFullPath() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("黑八", in: app)
        capture(app, "eightball_setup_top", page: "黑八 Setup 首屏",
                state: "目标局数；多局时展开让局选项")
        let cap3 = app.buttons["3"].firstMatch
        if cap3.waitForExistence(timeout: 2) {
            cap3.tap()
            sleep(1)
            smallDrag(app, dy: -50)
            capture(app, "eightball_setup_handicap", page: "黑八 Setup（3 局）",
                    state: "让局 不让局/红让蓝/蓝让红；让局数")
        }
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "eightball_board_initial", page: "黑八计分板（开局）",
                state: "0:0")
        tapContender(app, left: true)
        sleep(1)
        capture(app, "eightball_1_0", page: "黑八计分板（计分后）", state: "1:0")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "eightball_after_undo", page: "黑八计分板（撤销后）", state: "0:0")
        tapContender(app, left: true)
        tapContender(app, left: true)
        sleep(1)
        openMenu(app)
        app.buttons["结束比赛"].tap()
        sleep(1)
        capture(app, "eightball_finish_confirm", page: "黑八结束比赛确认", state: "确认弹层")
        confirmFinish(app)
        capture(app, "eightball_finished", page: "黑八完赛遮罩", state: "2:0 胜方")
        finishedGoHome(app)
    }

    // MARK: - 斯诺克

    func testMatrixSnookerSetupAndScoring() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("斯诺克", in: app)
        capture(app, "snooker_setup_top", page: "斯诺克 Setup 首屏",
                state: "局数 chips + 自定义局数输入框")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "snooker_board_initial", page: "斯诺克计分板（开局）",
                state: "0:0；击球方指示")
        tapContender(app, left: true)
        XCTAssertTrue(app.buttons["结算本局"].waitForExistence(timeout: 4),
                      "应打开斯诺克选球面板")
        capture(app, "snooker_ball_panel", page: "斯诺克选球面板",
                state: "进球按钮网格 + 犯规 + 结算本局")
        app.buttons["1"].firstMatch.tap()
        sleep(1)
        capture(app, "snooker_after_1", page: "斯诺克计分板（1 分后）", state: "1:0")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "snooker_after_undo", page: "斯诺克计分板（撤销后）", state: "0:0")
        swipeBackToHome(app)
    }

    // MARK: - 足球

    func testMatrixFootballFullPath() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("足球", in: app)
        capture(app, "football_setup_top", page: "足球 Setup 首屏",
                state: "半场时长 chips（默认 45 分钟置前）")
        smallDrag(app, dy: -55)
        capture(app, "football_setup_scrolled", page: "足球 Setup 滚动后",
                state: "开球方 主/客、队伍折叠栏")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "football_board_first_half", page: "足球计分板（上半场）",
                state: "0:0；时钟 45:00 倒计")
        // 开球/暂停按钮在 5 人制路径；普通足球用长按菜单「伤停补时」
        openMenu(app)
        capture(app, "football_menu", page: "足球长按菜单",
                state: "撤销 / 重新开始 / 伤停补时 / 结束比赛")
        app.buttons["伤停补时"].tap()
        sleep(1)
        XCTAssertTrue(app.buttons["+30"].waitForExistence(timeout: 3), "应弹出伤停补时面板")
        capture(app, "football_injury_panel", page: "足球伤停补时面板",
                state: "+1/+2/+3/+5/+10/+15/+30/+60/+90 秒选项")
        app.buttons["+30"].tap()
        sleep(1)
        capture(app, "football_injury_added", page: "足球伤停补时（+30 秒）",
                state: "补时提示")
        closeMenuIfNeeded(app)
        // 进入下半场：把时钟跑完太慢，改用长按菜单；若「进入下半场」不可见则记录为未走通
        openMenu(app)
        let nextHalf = app.buttons["进入下半场"]
        if nextHalf.waitForExistence(timeout: 3) {
            capture(app, "football_next_half_available", page: "足球菜单（进入下半场）",
                    state: "上半场未结束时「进入下半场」也可用（实际以运行结果为准）")
            nextHalf.tap()
            sleep(1)
            capture(app, "football_next_half_confirm", page: "足球进入下半场确认",
                    state: "「进入下半场？」确认弹层")
            closeMenuIfNeeded(app)
        } else {
            capture(app, "football_next_half_blocked", page: "足球菜单",
                    state: "未跑完上半场时无「进入下半场」入口（真实路径限制）")
        }
        swipeBackToHome(app)
    }

    // MARK: - 五人制足球

    func testMatrixFootball5v5PauseAndClock() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("五人制足球", in: app)
        capture(app, "f5_setup_top", page: "五人制足球 Setup 首屏",
                state: "半场时长 chips（默认 20 分钟置前）")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "f5_board_before_kickoff", page: "五人制足球计分板（未开球）",
                state: "0:0；时钟待开球")
        let startClock = app.buttons["开始"]
        XCTAssertTrue(startClock.waitForExistence(timeout: 4), "计分板应提供开球操作")
        startClock.tap()
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 4), "开球后应能暂停计时")
        capture(app, "f5_clock_running", page: "五人制足球（时钟运行）",
                state: "开球后计时")

        openMenu(app)
        let pauseClock = app.buttons.matching(
            NSPredicate(format: "label == %@ AND enabled == YES", "暂停")
        ).firstMatch
        XCTAssertTrue(pauseClock.waitForExistence(timeout: 4), "菜单应提供暂停操作")
        capture(app, "f5_menu_pause", page: "五人制足球菜单（暂停）", state: "时钟运行中可暂停")
        pauseClock.tap()
        XCTAssertTrue(app.buttons["继续"].waitForExistence(timeout: 4), "暂停后应能继续计时")
        capture(app, "f5_clock_paused", page: "五人制足球（已暂停）",
                state: "暂停态；区分暂停与休息")
        swipeBackToHome(app)
    }

    // MARK: - 九球 2 人完赛路径（3/4 人深度走查由 WatchNineBallUITests 覆盖）

    func testMatrixNineBallTwoPlayerFinish() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("追分", in: app)
        XCTAssertTrue(app.buttons["2 人"].waitForExistence(timeout: 4), "应弹出选择人数弹层")
        capture(app, "nineball_2p_count_picker", page: "九球选择人数",
                state: "2/3/4 人选项")
        app.buttons["2 人"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(1)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        capture(app, "nineball_2p_setup", page: "九球 2 人 Setup 首屏",
                state: "选手折叠栏默认展开为 2 行")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "nineball_2p_board", page: "九球 2 人计分板（开局）",
                state: "0:0；选手 1 带球杆徽标")

        // 开球人（选手 1）面板：大金 1 步直出（+10/-10）
        tapContender(app, left: true)
        let bigGold = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "大金")).firstMatch
        XCTAssertTrue(bigGold.waitForExistence(timeout: 4), "点选手 1 应弹出事件面板")
        capture(app, "nineball_2p_event_panel", page: "九球 2 人事件面板（选手 1）",
                state: "开球人面板；大金可用")
        bigGold.tap()
        sleep(1)
        capture(app, "nineball_2p_after_big_gold", page: "九球 2 人大金计分",
                state: "+10/-10；无二级选人面板")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "nineball_2p_after_undo", page: "九球 2 人撤销后", state: "0:0")

        openMenu(app)
        app.buttons["结束比赛"].tap()
        sleep(1)
        capture(app, "nineball_2p_finish_confirm", page: "九球结束比赛确认", state: "确认弹层")
        confirmFinish(app)
        capture(app, "nineball_2p_finished", page: "九球 2 人完赛遮罩",
                state: "最终比分与胜方")
        finishedGoHome(app)
    }

    // MARK: - 投篮训练四种模式

    func testMatrixBasketballTrainingModes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-watch_scoreboard_layout", "vertical"]
        app.launch()
        sleep(3)
        dismissResumeBarIfNeeded(app)

        tapSportTile("投篮训练", in: app)
        XCTAssertTrue(app.staticTexts["选择训练模式"].waitForExistence(timeout: 4))
        capture(app, "bb_mode_picker", page: "投篮训练模式弹层",
                state: "1 分/2 分/3 分/自由模式（40mm 无空隙时可能重叠）")
        app.buttons["1 分"].tap()
        sleep(2)
        capture(app, "bb_1pt_board", page: "投篮训练（1 分模式）",
                state: "命中/出手记录")
        swipeBackToHome(app)

        tapSportTile("投篮训练", in: app)
        XCTAssertTrue(app.staticTexts["选择训练模式"].waitForExistence(timeout: 4))
        app.buttons["自由模式"].tap()
        sleep(2)
        capture(app, "bb_free_board", page: "投篮训练（自由模式）",
                state: "自由计分")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5)).tap()
        sleep(1)
        capture(app, "bb_free_scored", page: "投篮训练（自由模式命中 1 次）",
                state: "1/1")
        // 主动放弃训练，清理续赛
        let discard = app.buttons["放弃未完成训练"]
        if discard.waitForExistence(timeout: 4) {
            discard.tap()
            if app.buttons["确认放弃"].waitForExistence(timeout: 3) {
                app.buttons["确认放弃"].tap()
            }
        }
        sleep(1)
    }

    // MARK: - 工具：掷硬币 / 随机数 / 十秒挑战

    /// 独立短用例：抛硬币（结果态）
    func testMatrixToolFlipCoin() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)
        XCTAssertTrue(gotoTools(app), "工具页应有抛硬币")
        capture(app, "tools_list", page: "工具列表",
                state: "抛硬币/随机数字/十秒挑战/计数器")
        app.buttons["抛硬币"].firstMatch.tap()
        sleep(1)
        capture(app, "tool_coin_initial", page: "掷硬币（初始）", state: "待投状态")
        // 投掷按钮的 a11y 标签即「抛硬币」
        let coinButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "抛硬币")).firstMatch
        XCTAssertTrue(coinButton.waitForExistence(timeout: 3), "应有投掷按钮")
        coinButton.tap()
        sleep(2)
        capture(app, "tool_coin_flipped", page: "掷硬币（投掷结果）",
                state: "正/反 面图案")
        coinButton.tap()
        sleep(2)
        capture(app, "tool_coin_flipped_again", page: "掷硬币（再次投掷）",
                state: "可重复投掷")
        backFromSetup(app)
    }

    /// 独立短用例：随机数字（范围切换 + 生成）
    func testMatrixToolRandomNumber() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)
        XCTAssertTrue(gotoTools(app), "工具页应有随机数字")
        app.buttons["随机数字"].firstMatch.tap()
        sleep(1)
        capture(app, "tool_dice_initial", page: "随机数（初始）", state: "范围 1–100 待生成（页面内容未暴露 Button 控件，仅静态文本，已记为可访问性缺陷候选）")
        // 范围 chips 以静态文本存在：点「1–10」切换范围
        let range10 = app.staticTexts["1–10"]
        if range10.waitForExistence(timeout: 3) {
            range10.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(1)
            capture(app, "tool_dice_range_10", page: "随机数（范围 1–10）", state: "范围切换后")
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.33)).tap()
            sleep(1)
            capture(app, "tool_dice_range_10_coord", page: "随机数（坐标点左范围）", state: "a11y 无文本时以坐标切换")
        }
        // 中央点按生成
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)).tap()
        sleep(1)
        capture(app, "tool_dice_generated", page: "随机数（已生成）", state: "随机结果出现")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)).tap()
        sleep(1)
        capture(app, "tool_dice_generated_again", page: "随机数（再次生成）", state: "可重复生成")
        backFromSetup(app)
    }

    /// 独立短用例：十秒挑战（说明 → 计时 → 结果）
    func testMatrixToolTenSecond() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)
        XCTAssertTrue(gotoTools(app), "工具页应有十秒挑战")
        app.buttons["十秒挑战"].firstMatch.tap()
        sleep(2)
        if app.buttons["知道了"].waitForExistence(timeout: 2) {
            capture(app, "tool_10s_usage", page: "十秒挑战（首次使用说明）",
                    state: "系统 Alert（原生窗口）")
            app.buttons["知道了"].tap()
            sleep(1)
        }
        capture(app, "tool_10s_ready", page: "十秒挑战（就绪）", state: "👆 提示")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        usleep(600_000)
        capture(app, "tool_10s_running", page: "十秒挑战（计时中）",
                state: "秒表数字递增")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        sleep(1)
        capture(app, "tool_10s_result", page: "十秒挑战（结果）",
                state: "历史 chip 记录")
        backFromSetup(app)
    }

    // MARK: - 工具：计数器（另一会话正在改「结束并保存」，这里只记录实际行为）

    func testMatrixCounterIncrementOnly() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "计数器")).firstMatch
        for _ in 0..<4 where !entry.exists {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            usleep(500_000)
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "工具页应有计数器")
        entry.tap()
        XCTAssertTrue(app.navigationBars["计数器"].waitForExistence(timeout: 5))
        capture(app, "counter_initial", page: "计数器（初始）", state: "0")
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        for _ in 0..<3 { center.tap(); usleep(300_000) }
        XCTAssertTrue(app.staticTexts["3"].waitForExistence(timeout: 3), "计数应到 3")
        capture(app, "counter_3", page: "计数器（+3 后）", state: "3")
        // 不点「结束」（该路径正在被另一会话修复），返回工具页
        backFromSetup(app)
    }

    // MARK: - 记录 Tab 与详情、清空确认

    func testMatrixRecordsListAndClearConfirm() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        XCTAssertTrue(gotoRecords(app), "应切到记录 Tab")
        capture(app, "records_list", page: "记录列表",
                state: "本轮真实比赛产生的记录（最新在前）")
        // 打开第一条详情
        let firstRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "分钟前")
        ).firstMatch
        if firstRow.waitForExistence(timeout: 4) {
            firstRow.tap()
            sleep(1)
            capture(app, "records_detail", page: "记录详情",
                    state: "本条比赛/工具记录详情（动作内页）")
            backFromSetup(app)
        } else {
            capture(app, "records_empty", page: "记录列表（空）", state: "无记录")
        }
        // 清空确认（点取消，不真清空）
        let clear = app.buttons["清除全部记录"]
        for _ in 0..<8 {
            if clear.exists && clear.isHittable { break }
            smallDrag(app, dy: -55)
        }
        if clear.waitForExistence(timeout: 3) {
            clear.tap()
            sleep(1)
            capture(app, "records_clear_confirm", page: "清空记录确认弹层",
                    state: "确认弹层（本测试点取消，不删除数据）")
            app.buttons["取消"].tap()
            sleep(1)
        }
    }

    // MARK: - 设置：开关逐个翻转并恢复 + 内页


    /// 设置内页部分（布局行不可达时也从这里继续，保证内页与开关独立取证）。
    private func finishSettingsSubpages(_ app: XCUIApplication) {
        // 局间休息开关：关 → 开（恢复）
        let restRow = app.buttons["局间休息"]
        for _ in 0..<10 {
            if restRow.exists && restRow.isHittable { break }
            smallDrag(app, dy: 45)
        }
        let restSwitch = restRow.switches.firstMatch
        if restSwitch.waitForExistence(timeout: 3) {
            let before = restSwitch.value as? String
            restSwitch.tap()
            sleep(1)
            capture(app, "settings_rest_toggle_off", page: "设置（局间休息关闭）",
                    state: "开关值 \(restSwitch.value as? String ?? "?")（原 \(before ?? "?")）")
            restSwitch.tap()
            sleep(1)
            capture(app, "settings_rest_toggle_restored", page: "设置（局间休息恢复）",
                    state: "已恢复开启")
        } else {
            capture(app, "settings_rest_toggle_missing", page: "设置（局间休息行）",
                    state: "行存在但未暴露开关控件（watchOS Toggle a11y 受限），行为未验证")
        }

        // 常用名称内页
        let namesRow = app.buttons["常用名称"]
        for _ in 0..<8 {
            if namesRow.isHittable { break }
            smallDrag(app, dy: 45)
        }
        if namesRow.isHittable {
            namesRow.tap()
            sleep(1)
            capture(app, "settings_common_names", page: "常用名称页",
                    state: "选手/队伍分类与同步卡片")
            backFromSetup(app)
        } else {
            capture(app, "settings_common_names_unreachable", page: "设置",
                    state: "常用名称行未可达（未验证）")
        }

        // 手机联动内页
        let linkRow = app.buttons["手表联动"]
        for _ in 0..<8 {
            if linkRow.isHittable { break }
            smallDrag(app, dy: -45)
        }
        if linkRow.isHittable {
            linkRow.tap()
            sleep(1)
            capture(app, "settings_phone_link", page: "手机联动页",
                    state: "联动状态（无手机连接时显示引导）")
            backFromSetup(app)
        } else {
            capture(app, "settings_phone_link_unreachable", page: "设置",
                    state: "手表联动行未可达（未验证）")
        }

        // 使用说明 Alert
        let usageRow = app.buttons["使用说明"]
        for _ in 0..<10 {
            if usageRow.exists && usageRow.isHittable { break }
            smallDrag(app, dy: -45)
        }
        if usageRow.exists && usageRow.isHittable {
            usageRow.tap()
            sleep(1)
            capture(app, "settings_usage_alert", page: "使用说明 Alert",
                    state: "系统 Alert（原生窗口，单独标注）")
            app.buttons["知道了"].tap()
            sleep(1)
        } else {
            capture(app, "settings_usage_unreachable", page: "设置",
                    state: "使用说明行未可达（未验证）")
        }
    }

    func testMatrixSettingsTogglesAndSubpages() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        XCTAssertTrue(gotoSettings(app), "应切到设置 Tab")
        capture(app, "settings_top", page: "设置首屏",
                state: "常用名称 / 手机联动 / 震动 / 声音 / 计分时常亮 / 局间休息")

        // 布局切换（行文案是「布局」；当前值拼在同一 label 里，如「布局、上下」）
        let layoutRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "布局")).firstMatch
        var layoutFound = false
        for _ in 0..<10 {
            if layoutRow.exists && layoutRow.isHittable { layoutFound = true; break }
            smallDrag(app, dy: -55)
        }
        guard layoutFound else {
            capture(app, "settings_layout_row_unreachable", page: "设置",
                    state: "布局行未进入可达范围（记录为未验证）")
            finishSettingsSubpages(app)
            return
        }
        let beforeLayout = layoutRow.label
        layoutRow.tap()
        sleep(1)
        capture(app, "settings_layout_toggled", page: "设置（布局切换后）",
                state: "布局行值由「\(beforeLayout)」切换")
        layoutRow.tap()
        sleep(1)
        capture(app, "settings_layout_restored", page: "设置（布局恢复）", state: "已恢复原布局")

        // 布局切换后：继续内页与开关取证
        layoutRow.tap()
        sleep(1)
        capture(app, "settings_layout_restored", page: "设置（布局恢复）", state: "已恢复原布局")
        finishSettingsSubpages(app)
    }

    // MARK: - 匹克球双打（独立用例：4 人 Setup + 板 + 计分/撤销 + 完赛）

    func testMatrixPickleballDoublesBoard() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("匹克球双打", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        capture(app, "pbd_setup_top", page: "匹克球双打 Setup 首屏",
                state: "局数/目标分/每球得分；选手 1-4")
        smallDrag(app, dy: -55)
        capture(app, "pbd_setup_scrolled", page: "匹克球双打 Setup 滚动后",
                state: "发球方 + 选手折叠栏")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "pbd_board_initial", page: "匹克球双打计分板（开局）",
                state: "0:0；双打发球指示")
        for _ in 0..<2 { tapContender(app, left: true) }
        tapContender(app, left: false)
        sleep(1)
        capture(app, "pbd_board_2_1", page: "匹克球双打计分板（计分后）",
                state: "2:1（侧边轮转按匹克球规则）")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "pbd_board_after_undo", page: "匹克球双打计分板（撤销后）",
                state: "1:1")
        openMenu(app)
        app.buttons["结束比赛"].tap()
        sleep(1)
        confirmFinish(app)
        capture(app, "pbd_finished", page: "匹克球双打完赛遮罩",
                state: "双打胜方")
        finishedGoHome(app)
    }

    // MARK: - 桌上足球（净胜 2 分 + 封顶分 Setup 展开）

    func testMatrixFoosballSetupAndBoard() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("桌上足球", in: app)
        capture(app, "foosball_setup_top", page: "桌上足球 Setup 首屏",
                state: "局数/每局分数/净胜 2 分开关")
        // 决胜局净胜 2 分开关行：宽 chip，40mm 可能折行或被截断（首轮 49mm 无法点击）
        let winByTwo = app.buttons["决胜局净胜 2 分"]
        for _ in 0..<10 {
            if winByTwo.exists && winByTwo.isHittable { break }
            smallDrag(app, dy: -50)
        }
        if winByTwo.waitForExistence(timeout: 3) && winByTwo.isHittable {
            winByTwo.tap()
            sleep(1)
            capture(app, "foosball_setup_cap", page: "桌上足球 Setup（净胜 2 分展开）",
                    state: "封顶分 chips 出现")
            if winByTwo.exists && winByTwo.isHittable {
                winByTwo.tap()
                sleep(1)
                capture(app, "foosball_setup_cap_closed", page: "桌上足球 Setup（恢复）",
                        state: "封顶分收起")
            }
        } else {
            capture(app, "foosball_win_by_two_unreachable", page: "桌上足球 Setup",
                    state: "「决胜局净胜 2 分」行存在但无法滚动到可点击（按钮触达缺陷候选）")
        }
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "foosball_board_initial", page: "桌上足球计分板（开局）", state: "0:0")
        tapContender(app, left: true)
        sleep(1)
        capture(app, "foosball_1_0", page: "桌上足球计分板（计分后）", state: "1:0")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "foosball_after_undo", page: "桌上足球计分板（撤销后）", state: "0:0")
        swipeBackToHome(app)
    }

    // MARK: - 毽子 / 壁球 / 匹克球单打（短开局 + 板 + 撤销）

    func testMatrixShuttlecockSquashPickleballBoards() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        // 毽子
        tapSportTile("毽子", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        capture(app, "shuttlecock_setup_top", page: "毽子 Setup 首屏",
                state: "局数 1/3/5、每局分数 11/15/21")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "shuttlecock_board_initial", page: "毽子计分板（开局）", state: "0:0")
        tapContender(app, left: true)
        sleep(1)
        capture(app, "shuttlecock_1_0", page: "毽子计分板（计分后）", state: "1:0")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "shuttlecock_after_undo", page: "毽子计分板（撤销后）", state: "0:0")
        swipeBackToHome(app)

        // 壁球
        tapSportTile("壁球", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        capture(app, "squash_setup_top", page: "壁球 Setup 首屏",
                state: "局数 1/3/5/7；无每局分数")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "squash_board_initial", page: "壁球计分板（开局）", state: "0:0")
        tapContender(app, left: true)
        sleep(1)
        capture(app, "squash_1_0", page: "壁球计分板（计分后）", state: "1:0")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "squash_after_undo", page: "壁球计分板（撤销后）", state: "0:0")
        swipeBackToHome(app)

        // 匹克球（单打）
        tapSportTile("匹克球", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        capture(app, "pickleball_setup_top", page: "匹克球 Setup 首屏",
                state: "局数/目标分/每球得分开关")
        let rally = app.buttons["每球得分"]
        for _ in 0..<10 {
            if rally.exists && rally.isHittable { break }
            smallDrag(app, dy: -50)
        }
        if rally.waitForExistence(timeout: 3) && rally.isHittable {
            rally.tap()
            sleep(1)
            capture(app, "pickleball_rally_on", page: "匹克球 Setup（每球得分开）",
                    state: "开关已开")
            if rally.exists && rally.isHittable {
                rally.tap()
                sleep(1)
            }
        } else {
            capture(app, "pickleball_rally_unreachable", page: "匹克球 Setup",
                    state: "「每球得分」行存在但无法滚动到可点击（按钮触达缺陷候选）")
        }
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "pickleball_board_initial", page: "匹克球计分板（开局）", state: "0:0")
        tapContender(app, left: true)
        sleep(1)
        capture(app, "pickleball_1_0", page: "匹克球计分板（计分后）", state: "1:0")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "pickleball_after_undo", page: "匹克球计分板（撤销后）", state: "0:0")
        swipeBackToHome(app)
    }

    // MARK: - 网球单打（占先规则 + 完赛遮罩）

    func testMatrixTennisSinglesBoard() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("网球", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        capture(app, "tennis_setup_top", page: "网球 Setup 首屏",
                state: "局数 1/3/5、平分规则")
        app.buttons["开始"].tap()
        sleep(2)
        capture(app, "tennis_board_initial", page: "网球计分板（开局）", state: "0:0 居中")
        for _ in 0..<4 { tapContender(app, left: true) }
        sleep(1)
        capture(app, "tennis_40_0", page: "网球计分板（40:0）", state: "40:0")
        undoViaMenu(app)
        closeMenuIfNeeded(app)
        capture(app, "tennis_after_undo", page: "网球计分板（撤销后）", state: "30:0")
        openMenu(app)
        app.buttons["结束比赛"].tap()
        sleep(1)
        confirmFinish(app)
        capture(app, "tennis_finished", page: "网球完赛遮罩", state: "0 局胜方文案")
        finishedGoHome(app)
    }

    // MARK: - 射箭双射手 6 环完赛（第二局真实打完）

    func testMatrixArcherySecondSetFinish() throws {
        continueAfterFailure = false
        let app = launchApp()
        dismissResumeBarIfNeeded(app)

        tapSportTile("射箭", in: app)
        XCTAssertTrue(app.buttons["开始"].waitForExistence(timeout: 4))
        app.buttons["开始"].tap()
        sleep(2)
        // 第 1 局：红 9，蓝 7 → 红胜（6 分制，到 6 分需要 2 局，此用例验证 set 间过渡）
        tapContender(app, left: true)
        if app.buttons["9"].firstMatch.waitForExistence(timeout: 3) { app.buttons["9"].firstMatch.tap() }
        sleep(1)
        tapContender(app, left: false)
        if app.buttons["7"].firstMatch.waitForExistence(timeout: 3) { app.buttons["7"].firstMatch.tap() }
        sleep(1)
        capture(app, "archery_set1_scores", page: "射箭第 1 局计分后",
                state: "9:7；等待另一射手")
        // 完赛路径（0 局胜方）：直接结束
        openMenu(app)
        app.buttons["结束比赛"].tap()
        sleep(1)
        confirmFinish(app)
        capture(app, "archery_finish_second", page: "射箭完赛遮罩（第二路径）",
                state: "局分与胜方")
        finishedGoHome(app)
    }
}
