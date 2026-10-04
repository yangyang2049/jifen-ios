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
        ("eight_ball", "黑八追局"),
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

    /// Focused, repeatable source captures for the simplified-Chinese App Store art.
    func testCaptureAppStoreSourceScreenshots() {
        relaunch()
        XCTAssertTrue(selectTab("计分"))
        snap("marketing_sports")

        XCTAssertTrue(openPriorityScoreboardSetup(id: "badminton", label: "羽毛球"))
        snap("marketing_badminton_setup")

        XCTAssertTrue(openPriorityScoreboardSetup(id: "basketball", label: "篮球"))
        XCTAssertTrue(tapStart())
        XCUIDevice.shared.orientation = .landscapeRight
        snap("marketing_basketball")

        relaunch()
        XCTAssertTrue(selectTab("计时"))
        let go = app.descendants(matching: .any)["timer_dest_go"]
        XCTAssertTrue(go.waitForExistence(timeout: 4))
        go.tap()
        XCTAssertTrue(tapStart())
        XCUIDevice.shared.orientation = .landscapeLeft
        snap("marketing_go_timer")
    }

    /// 商店拼贴素材:各运动界面带真实比赛数据(排球/斯诺克/象棋/围棋/UNO/篮球)。
    /// 篮球放最后:它会留下进行中的比赛,干扰后续项目的页面查询。
    func testCaptureMarketingDataScreenshots() {
        captureVolleyballData()
        captureSnookerData()
        captureChessTimerData()
        captureGoTimerData()
        captureUnoRecordData()
        captureBasketballData()
    }

    private func captureVolleyballData() {
        relaunch()
        guard openSportAndStart(id: "volleyball", label: "排球") else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        // 竖屏下左右半场点按计分(布局对称无歧义),再转横屏截图
        scoreRallySide(left: true, times: 25)
        scoreRallySide(left: false, times: 23)
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        snap("marketing_volleyball_data", settle: 0.5)
    }

    private func captureSnookerData() {
        relaunch()
        guard openSportAndStart(id: "snooker", label: "斯诺克") else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        // 用球值按钮组合真实比分:红球连击 + 彩球,换手后再打
        scoreSnookerBall(1, times: 12)
        scoreSnookerBall(5, times: 4)
        scoreSnookerBall(3, times: 2)
        tapSnookerHandover()
        scoreSnookerBall(1, times: 9)
        scoreSnookerBall(4, times: 3)
        scoreSnookerBall(7, times: 1)
        snap("marketing_snooker_data", settle: 0.5)
    }

    private func captureChessTimerData() {
        relaunch()
        guard selectTab("计时") else { return }
        scrollUntilExists(identifier: "timer_dest_xiangqi")
        app.descendants(matching: .any)["timer_dest_xiangqi"].firstMatch.tap()
        guard tapStart() else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        ensureBoardTimerStarted()
        RunLoop.current.run(until: Date().addingTimeInterval(20))
        tapBoardTimerPlayer("2")
        RunLoop.current.run(until: Date().addingTimeInterval(9))
        tapBoardTimerPlayer("1")
        RunLoop.current.run(until: Date().addingTimeInterval(12))
        snap("marketing_xiangqi_data", settle: 0.4)
    }

    private func captureGoTimerData() {
        relaunch()
        guard selectTab("计时") else { return }
        scrollUntilExists(identifier: "timer_dest_go")
        app.descendants(matching: .any)["timer_dest_go"].firstMatch.tap()
        guard tapStart() else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        ensureBoardTimerStarted()
        RunLoop.current.run(until: Date().addingTimeInterval(30))
        snap("marketing_go_data", settle: 0.4)
    }

    /// 棋类计时:横屏下若仍在设置页(开始按钮还在),再点一次开始
    private func ensureBoardTimerStarted() {
        let startButton = app.buttons["开始"]
        if startButton.exists, startButton.isHittable {
            startButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
    }

    private func captureUnoRecordData() {
        relaunch(extraArguments: ["-UITestRecordFixtures", "-UITestRecordDetail", "uno"])
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        snap("marketing_uno_data", settle: 0.6)
    }

    private func captureBasketballData() {
        relaunch()
        guard openSportAndStart(id: "basketball", label: "篮球") else { return }
        XCUIDevice.shared.orientation = .landscapeRight
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        revealScoreboardChrome(fromLeftCorner: true)
        scoreBasketballPoints(left: true, points: 58)
        scoreBasketballPoints(left: false, points: 49)
        snap("marketing_basketball_data", settle: 0.5)
    }

    // MARK: - 商店源图（en / zh-Hans 两个包共用同一条链路）

    /// 一个语言包的差异点只有：界面语言、Setup 用哪个项目、几组人名、快照名前缀。
    /// 比分与时钟两端完全一致，两个包讲的是同一批对局。
    private struct StorePack {
        let locale: UITestLocale.Configuration
        let prefix: String
        let padPrefix: String
        let setupSportID: String
        let duel: [String]
        let teams: [String]
        let uno: [String]
        let multi: [String]

        /// 人名一律走启动参数注入：CJK 用 typeText 打不出来，
        /// 而且折叠线以下的输入框 isHittable 是概率性的，注入没有这两个坑。
        func names(_ values: [String]) -> [String] {
            var arguments: [String] = []
            for (index, value) in values.enumerated() {
                arguments += ["-UITestSetupName\(index + 1)", value]
            }
            return arguments
        }
    }

    private static let englishStorePack = StorePack(
        locale: UITestLocale.en,
        prefix: "marketing_en_",
        padPrefix: "marketing_pad_en_",
        setupSportID: "tennis",
        duel: ["Sam", "Steven"],
        teams: ["Home", "Away"],
        uno: ["Emma", "Liam", "Mia", "Noah"],
        multi: ["Alex", "Jordan", "Mia", "Sofia"]
    )

    private static let chineseStorePack = StorePack(
        locale: UITestLocale.zhHans,
        prefix: "marketing_zh_",
        padPrefix: "marketing_pad_zh_",
        setupSportID: "badminton",
        duel: ["陈明", "李华"],
        teams: ["主队", "客队"],
        uno: ["陈明", "李华", "王芳", "张伟"],
        multi: ["赵磊", "孙倩", "周涛", "吴敏"]
    )

    /// 篮球放最后：它会留下一场进行中的比赛，干扰后续项目的页面查询。
    func testCaptureAppStoreSourceScreenshotsEnglish() {
        captureStoreScreenshots(Self.englishStorePack)
    }

    func testCaptureAppStoreSourceScreenshotsChinese() {
        captureStoreScreenshots(Self.chineseStorePack)
    }

    private func captureStoreScreenshots(_ pack: StorePack) {
        captureStoreRecordDetail(pack)
        captureStoreSetup(pack)
        captureStoreVolleyball(pack)
        captureStoreSnooker(pack)
        captureStoreUnoLive(pack)
        captureStoreMultiLive(pack)
        captureStoreBoardTimer(pack, timerID: "chess", snapSuffix: "chess", firstWait: 19, secondWait: 41)
        captureStoreBoardTimer(pack, timerID: "go", snapSuffix: "go", firstWait: 45, secondWait: 30)
        captureStoreBasketball(pack)
    }

    private func captureStoreRecordDetail(_ pack: StorePack) {
        relaunch(
            extraArguments: [
                "-UITestRecordFixtures", "-UITestRecordDetail", "pingpong",
                "-UITestRecordTeamName1", pack.duel[0], "-UITestRecordTeamName2", pack.duel[1]
            ],
            locale: pack.locale,
            waitForTabBar: false
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        snap(pack.prefix + "record_detail", settle: 0.8)
    }

    private func captureStoreSetup(_ pack: StorePack) {
        relaunch(extraArguments: pack.names(pack.duel), locale: pack.locale)
        guard openCatalogEntry(pack.setupSportID) else { return }
        snap(pack.prefix + "\(pack.setupSportID)_setup", settle: 0.6)
    }

    private func captureStoreVolleyball(_ pack: StorePack) {
        relaunch(extraArguments: pack.names(pack.teams), locale: pack.locale)
        guard openCatalogEntry("volleyball"), tapStart() else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        // 24:23 局点，比分会随每一分变化，比整数局分更像在打
        scoreRallySide(left: true, times: 24)
        scoreRallySide(left: false, times: 23)
        XCUIDevice.shared.orientation = .landscapeLeft
        snap(pack.prefix + "volleyball", settle: 0.6)
    }

    private func captureStoreSnooker(_ pack: StorePack) {
        relaunch(extraArguments: pack.names(pack.duel), locale: pack.locale)
        guard openCatalogEntry("snooker"), tapStart() else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        scoreSnookerBall(1, times: 12)
        scoreSnookerBall(5, times: 4)
        scoreSnookerBall(3, times: 2)
        tapSnookerHandover()
        scoreSnookerBall(1, times: 9)
        scoreSnookerBall(4, times: 3)
        scoreSnookerBall(7, times: 1)
        snap(pack.prefix + "snooker", settle: 0.5)
    }

    /// UNO 用实时计分板（横屏布局是默认），比记录页更像"正在打"，也不用改夹具数据
    private func captureStoreUnoLive(_ pack: StorePack) {
        relaunch(extraArguments: pack.names(pack.uno), locale: pack.locale)
        guard openCatalogEntry("uno"), tapStart() else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        scoreUnoRound(player: pack.uno[0], points: 236)
        scoreUnoRound(player: pack.uno[1], points: 187)
        scoreUnoRound(player: pack.uno[2], points: 312)
        scoreUnoRound(player: pack.uno[3], points: 149)
        snap(pack.prefix + "uno", settle: 0.6)
    }

    private func captureStoreMultiLive(_ pack: StorePack) {
        relaunch(extraArguments: pack.names(pack.multi), locale: pack.locale)
        guard openCatalogEntry("multiScoreboard"), tapStart() else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        tapMultiScoreCell(player: pack.multi[0], times: 12)
        tapMultiScoreCell(player: pack.multi[1], times: 8)
        tapMultiScoreCell(player: pack.multi[2], times: 15)
        tapMultiScoreCell(player: pack.multi[3], times: 3)
        snap(pack.prefix + "multi", settle: 0.6)
    }

    private func captureStoreBoardTimer(_ pack: StorePack, timerID: String, snapSuffix: String, firstWait: TimeInterval, secondWait: TimeInterval) {
        relaunch(locale: pack.locale)
        guard selectTab("计时") else { return }
        scrollUntilExists(identifier: "timer_dest_\(timerID)")
        let entry = app.descendants(matching: .any)["timer_dest_\(timerID)"].firstMatch
        guard entry.waitForExistence(timeout: 4), entry.isHittable else { return }
        entry.tap()
        guard tapStart() else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        ensureStoreBoardTimerStarted()
        // 两边都真实走过时间,读秒数才对得上;计时器只认"点自己这侧交权",
        // 所以要按当前行棋方(第 1 手)那侧,钟才会换到对面走
        RunLoop.current.run(until: Date().addingTimeInterval(firstWait))
        tapBoardTimerPlayer("1")
        RunLoop.current.run(until: Date().addingTimeInterval(secondWait))
        snap(pack.prefix + snapSuffix, settle: 0.4)
    }

    private func captureStoreBasketball(_ pack: StorePack) {
        relaunch(extraArguments: pack.names(pack.teams), locale: pack.locale)
        guard openCatalogEntry("basketball"), tapStart() else { return }
        XCUIDevice.shared.orientation = .landscapeRight
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        revealScoreboardChrome(fromLeftCorner: true)
        scoreBasketballPoints(left: true, points: 71)
        scoreBasketballPoints(left: false, points: 68)
        // 71:68 只可能出现在末节:先把节次真切到 Q4,再让比赛时钟真实走一段
        selectBasketballPeriod("Q4")
        let clock = app.descendants(matching: .any)["basketball_clock_toggle"]
        if clock.waitForExistence(timeout: 2), clock.isHittable {
            clock.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(20))
            clock.tap()
        }
        snap(pack.prefix + "basketball", settle: 0.5)
    }

    // MARK: - iPad 商店源图（横屏 2752×2064，en / zh-Hans 各一套）

    /// iPad 的卖点全在宽度上：Home 双列、记分牌按视口自缩放、记录详情限宽 920 的图表。
    /// 统一横屏还顺带避开了"开启横屏"一次性提示——那个弹窗只在竖屏进记分牌时弹。
    /// 比分与人名沿用两个手机包同一批数据，三个包讲的是同一场球。
    func testCaptureAppStoreSourceScreenshotsEnglishIPad() {
        capturePadScreenshots(Self.englishStorePack)
    }

    func testCaptureAppStoreSourceScreenshotsChineseIPad() {
        capturePadScreenshots(Self.chineseStorePack)
    }

    private func capturePadScreenshots(_ pack: StorePack) {
        capturePadHome(pack)
        capturePadRecordDetail(pack)
        capturePadSetup(pack)
        capturePadSnooker(pack)
        capturePadBasketball(pack)
    }

    /// Home 在 iPad 是唯一有真结构差异的页（宽 ≥768 才双列），所以要带夹具让右列有内容
    private func capturePadHome(_ pack: StorePack) {
        relaunch(
            extraArguments: [
                "-UITestRecordFixtures",
                "-UITestRecordTeamName1", pack.duel[0],
                "-UITestRecordTeamName2", pack.duel[1]
            ],
            locale: pack.locale,
            orientation: .landscapeLeft
        )
        guard selectTab("首页") else { return }
        snap(pack.padPrefix + "home", settle: 1.0)
    }

    private func capturePadRecordDetail(_ pack: StorePack) {
        relaunch(
            extraArguments: [
                "-UITestRecordFixtures", "-UITestRecordDetail", "pingpong",
                "-UITestRecordTeamName1", pack.duel[0], "-UITestRecordTeamName2", pack.duel[1]
            ],
            locale: pack.locale,
            waitForTabBar: false,
            orientation: .landscapeLeft
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        snap(pack.padPrefix + "record_detail", settle: 0.8)
    }

    private func capturePadSetup(_ pack: StorePack) {
        relaunch(
            extraArguments: pack.names(pack.duel),
            locale: pack.locale,
            orientation: .landscapeLeft
        )
        guard openCatalogEntry(pack.setupSportID) else { return }
        snap(pack.padPrefix + "\(pack.setupSportID)_setup", settle: 0.6)
    }

    private func capturePadSnooker(_ pack: StorePack) {
        relaunch(
            extraArguments: pack.names(pack.duel),
            locale: pack.locale,
            orientation: .landscapeLeft
        )
        guard openCatalogEntry("snooker"), tapStart() else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        scoreSnookerBall(1, times: 12)
        scoreSnookerBall(5, times: 4)
        scoreSnookerBall(3, times: 2)
        tapSnookerHandover()
        scoreSnookerBall(1, times: 9)
        scoreSnookerBall(4, times: 3)
        scoreSnookerBall(7, times: 1)
        snap(pack.padPrefix + "snooker", settle: 0.5)
    }

    private func capturePadBasketball(_ pack: StorePack) {
        relaunch(
            extraArguments: pack.names(pack.teams),
            locale: pack.locale,
            orientation: .landscapeLeft
        )
        guard openCatalogEntry("basketball"), tapStart() else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        revealScoreboardChrome(fromLeftCorner: true)
        scoreBasketballPoints(left: true, points: 71)
        scoreBasketballPoints(left: false, points: 68)
        selectBasketballPeriod("Q4")
        let clock = app.descendants(matching: .any)["basketball_clock_toggle"]
        if clock.waitForExistence(timeout: 2), clock.isHittable {
            clock.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(20))
            clock.tap()
        }
        revealScoreboardChrome(fromLeftCorner: true)
        snap(pack.padPrefix + "basketball", settle: 0.5)
    }

    /// 篮球:点节次胶囊开选择器,选到指定节
    private func selectBasketballPeriod(_ period: String) {
        let chip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Q")).firstMatch
        guard chip.waitForExistence(timeout: 2), chip.isHittable else { return }
        chip.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let option = app.buttons.matching(NSPredicate(format: "label == %@", period)).firstMatch
        guard option.waitForExistence(timeout: 2), option.isHittable else { return }
        option.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    /// 打开计分目录里某项目的赛前设置（只开弹窗，不点开始）
    private func openCatalogEntry(_ id: String) -> Bool {
        guard selectTab("计分") else { return false }
        scrollUntilExists(identifier: "scoreboard_catalog_\(id)")
        let card = app.descendants(matching: .any)["scoreboard_catalog_\(id)"]
        guard card.waitForExistence(timeout: 3), card.isHittable else { return false }
        card.tap()
        return true
    }

    /// UNO：点玩家格开结算面板 → 数字牌合计 → 键盘"完成"收起 → 确认记分
    private func scoreUnoRound(player: String, points: Int) {
        let cell = participantCell(named: player)
        guard cell.waitForExistence(timeout: 3), cell.isHittable else { return }
        cell.tap()
        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 3), field.isHittable else { return }
        field.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        field.typeText(String(points))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        tapFirstExisting(["Done", "完成"])
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        _ = tapFirstExisting(["Confirm score", "确认记分"])
    }

    /// 同一个按钮在两种语言下有两个文案；先判存在再点，别用 tapContaining（它会为找不到的按钮反复滑动）
    @discardableResult
    private func tapFirstExisting(_ labels: [String]) -> Bool {
        for label in labels {
            let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            if button.waitForExistence(timeout: 1.2), button.isHittable {
                button.tap()
                return true
            }
        }
        return false
    }

    /// 多人记分：单击玩家格 +1，间隔要大于 0.24s 的双击窗口，否则会走减分
    private func tapMultiScoreCell(player: String, times: Int) {
        let cell = participantCell(named: player)
        guard cell.waitForExistence(timeout: 3), cell.isHittable else { return }
        for _ in 0..<times {
            cell.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
    }

    /// 玩家格上的名字：SwiftUI 可能暴露成 staticText，也可能整格并成一个 button
    private func participantCell(named name: String) -> XCUIElement {
        let text = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if text.waitForExistence(timeout: 1.2) { return text }
        return app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// 棋类计时：横屏后若仍停在设置页，再点一次开始
    private func ensureStoreBoardTimerStarted() {
        for label in ["开始", "Start"] {
            let button = app.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                return
            }
        }
    }

    /// 打开某运动的赛前设置并点开始;失败返回 false,由调用方跳过
    private func openSportAndStart(id: String, label: String) -> Bool {
        guard selectTab("计分") else { return false }
        scrollUntilExists(identifier: "scoreboard_catalog_\(id)")
        let card = app.descendants(matching: .any)["scoreboard_catalog_\(id)"]
        if card.waitForExistence(timeout: 3), card.isHittable {
            card.tap()
        } else {
            let byLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            guard byLabel.waitForExistence(timeout: 3), byLabel.isHittable else { return false }
            byLabel.tap()
        }
        return tapStart()
    }

    /// 排球/斯诺克等点按计分板:点按对应半场 +1
    private func scoreRallySide(left: Bool, times: Int) {
        for _ in 0..<times {
            app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.25 : 0.75, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    /// 斯诺克:点按球值按钮计分(红1/黄2/绿3/棕4/蓝5/粉6/黑7)
    private func scoreSnookerBall(_ points: Int, times: Int) {
        let ball = app.descendants(matching: .any)["snooker_ball_\(points)"]
        guard ball.waitForExistence(timeout: 3), ball.isHittable else { return }
        for _ in 0..<times {
            ball.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        }
    }

    /// 斯诺克:换手(切换击球方)
    private func tapSnookerHandover() {
        let handover = app.descendants(matching: .any)["snooker_action_handover"]
        if handover.waitForExistence(timeout: 2), handover.isHittable {
            handover.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    /// 篮球:按半场缓存 +3/+2/+1 按钮引用后连点,组合出目标比分
    private func scoreBasketballPoints(left: Bool, points: Int) {
        var remaining = points
        for value in [3, 2, 1] {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", "+\(value)")).allElementsBoundByIndex
            let target = matches.first { $0.isHittable && (left ? $0.frame.midX < app.frame.midX : $0.frame.midX > app.frame.midX) }
            guard let target else { continue }
            while remaining >= value {
                target.tap()
                remaining -= value
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            }
        }
    }

    /// 双人计时器:点按某侧切换计时权
    private func tapBoardTimerPlayer(_ playerID: String) {
        let player = app.descendants(matching: .any)["board_timer_player_\(playerID)"]
        if player.waitForExistence(timeout: 2), player.isHittable {
            player.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: playerID == "1" ? 0.25 : 0.75, dy: 0.5)).tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
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

    /// 回归：Setup 打开"比赛抬头"并输入后，计分板顶部正中必须显示抬头文本。
    func testSnookerSetupMatchTitleShowsOnScoreboard() {
        relaunch()
        XCTAssertTrue(openPriorityScoreboardSetup(id: "snooker", label: "斯诺克"))

        let titleToggle = app.switches.matching(
            NSPredicate(format: "label CONTAINS %@", "比赛抬头")
        ).firstMatch
        XCTAssertTrue(titleToggle.waitForExistence(timeout: 4), "Snooker match title toggle missing")
        if let toggleValue = titleToggle.value as? String, toggleValue == "0" {
            titleToggle.tap()
        }

        let titleInput = app.textFields["setup_snooker_match_title_input"]
        XCTAssertTrue(titleInput.waitForExistence(timeout: 3), "Match title input did not appear after toggle")
        titleInput.tap()
        titleInput.typeText("2026 City Open")

        XCTAssertTrue(tapStart())
        XCTAssertTrue(waitForPriorityScoreboard())

        let title = app.staticTexts["snooker_match_title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4), "Match title not visible on snooker scoreboard")
        XCTAssertEqual(title.label, "2026 City Open")

        // 对齐安卓 persistentTopSupplement：编辑模式下抬头编辑器仍可用。
        let editButton = app.buttons["scoreboard_edit_button"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 3))
        editButton.tap()
        let titleEditor = app.textFields["snooker_match_title_editor"]
        XCTAssertTrue(titleEditor.waitForExistence(timeout: 3), "Match title editor missing in edit mode")
        if let editorValue = titleEditor.value as? String {
            XCTAssertTrue(editorValue.contains("2026 City Open"), "Editor should prefill the current title, got \(editorValue)")
        }
        editButton.tap()
        XCTAssertTrue(
            app.staticTexts["snooker_match_title"].waitForExistence(timeout: 3),
            "Match title should stay visible after leaving edit mode"
        )
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

    func testAuditSpecialEditorsAndPaletteOptions() {
        for item in [(id: "pingpong", label: "乒乓球"), (id: "snooker", label: "斯诺克"),
                     (id: "doudizhu", label: "斗地主"), (id: "uno", label: "UNO"),
                     (id: "multiScoreboard", label: "多人计分")] {
            XCTAssertTrue(openPriorityScoreboardSetup(id: item.id, label: item.label))
            XCTAssertTrue(tapStart())
            XCUIDevice.shared.orientation = .landscapeRight
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            if item.id == "doudizhu" {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.09)).tap()
                XCTAssertTrue(app.descendants(matching: .any)["doudizhu_player_0_name_editor"].firstMatch.waitForExistence(timeout: 2))
                snap("audit_doudizhu_02_edit", settle: 0.3)
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.09)).tap()
            } else if ["uno", "multiScoreboard"].contains(item.id) {
                app.staticTexts["玩家 1"].firstMatch.press(forDuration: 1.2)
                XCTAssertTrue(app.descendants(matching: .any)["multi_score_player_name_editor"].firstMatch.waitForExistence(timeout: 2))
                snap("audit_\(item.id)_02_edit", settle: 0.3)
                let cancel = app.buttons["取消"].firstMatch
                if cancel.exists, cancel.isHittable { cancel.tap() }
            }
            XCTAssertTrue(openPriorityScoreboardMenu())
            app.descendants(matching: .any)["scoreboard_menu_action_displaySettings"].firstMatch.tap()
            let hint = app.buttons["知道了"].firstMatch
            if hint.waitForExistence(timeout: 0.4), hint.isHittable { hint.tap() }
            if ["uno", "multiScoreboard"].contains(item.id) {
                snap("audit_\(item.id)_legacy_settings", settle: 0.3)
                continue
            }
            for (index, title) in ["背景", "主题", "字体"].enumerated() {
                let palette = app.buttons["样式与颜色"].firstMatch
                XCTAssertTrue(palette.waitForExistence(timeout: 2))
                if palette.isHittable { palette.tap() }
                let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
                XCTAssertTrue(entry.waitForExistence(timeout: 2))
                if entry.isHittable { entry.tap() }
                snap("audit_\(item.id)_\(8 + index)_palette_panel", settle: 0.3)
                let complete = app.buttons["完成当前面板"].firstMatch
                XCTAssertTrue(complete.waitForExistence(timeout: 2))
                if complete.isHittable { complete.tap() }
            }
            app.buttons["退出样式编辑"].firstMatch.tap()
        }
    }

    func testAuditDoublesEditing() {
        for item in [(id: "pingpong", label: "乒乓球"), (id: "badminton", label: "羽毛球"),
                     (id: "tennis", label: "网球"), (id: "pickleball", label: "匹克球")] {
            XCTAssertTrue(openPriorityScoreboardSetup(id: item.id, label: item.label))
            XCTAssertTrue(selectSinglesDoublesMode(doubles: true))
            XCTAssertTrue(tapStart())
            XCTAssertTrue(waitForPriorityScoreboard())
            snap("audit_\(item.id)_doubles_01_board", settle: 0.3)
            let editID = item.id == "tennis" ? "tennis_scoreboard_edit_button" : "scoreboard_edit_button"
            let edit = app.buttons[editID].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 2))
            edit.tap()
            snap("audit_\(item.id)_doubles_02_edit", settle: 0.3)
            edit.tap()
            XCTAssertTrue(openPriorityScoreboardMenu())
            app.descendants(matching: .any)["scoreboard_menu_action_displaySettings"].firstMatch.tap()
            let hint = app.buttons["知道了"].firstMatch
            if hint.waitForExistence(timeout: 0.5), hint.isHittable { hint.tap() }
            for key in ["mainScore", "playerName", "setGameScore"] {
                let element = app.descendants(matching: .any)["style_element_\(key)_side_left"].firstMatch
                XCTAssertTrue(element.waitForExistence(timeout: 2), "Missing doubles element \(item.id) \(key)")
                if element.exists { element.tap() }
                let slider = app.sliders.firstMatch
                XCTAssertTrue(slider.waitForExistence(timeout: 2))
                if slider.exists { slider.adjust(toNormalizedSliderPosition: 1) }
                snap("audit_\(item.id)_doubles_\(key)_panel", settle: 0.2)
                let close = app.buttons["完成当前面板"].firstMatch
                if close.exists { close.tap() }
            }
            snap("audit_\(item.id)_doubles_03_style_max", settle: 0.3)
            app.buttons["退出样式编辑"].firstMatch.tap()
        }
    }

    func testFollowupBoxingAndStoppageControls() {
        XCTAssertTrue(openPriorityScoreboardSetup(id: "boxing", label: "拳击"))
        XCTAssertTrue(tapStart())
        XCUIDevice.shared.orientation = .landscapeRight
        let add = app.buttons["boxing_add_round"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertEqual(add.frame.midX, app.frame.midX, accuracy: 4)
        XCTAssertGreaterThan(add.frame.midY, app.frame.height * 0.8)
        add.tap()
        snap("audit_boxing_10_add_round", settle: 0.2)

        XCTAssertTrue(openPriorityScoreboardSetup(id: "football", label: "足球"))
        XCTAssertTrue(tapStart())
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertFalse(app.descendants(matching: .any)["football_stoppage_menu"].exists)
        XCTAssertTrue(openPriorityScoreboardMenu())
        let injury = app.descendants(matching: .any)["scoreboard_menu_action_footballInjury"].firstMatch
        XCTAssertTrue(injury.waitForExistence(timeout: 3))
        injury.tap()
        let addMinute = app.buttons["football_stoppage_add_60"].firstMatch
        XCTAssertTrue(addMinute.waitForExistence(timeout: 3))
        addMinute.tap()
        XCTAssertTrue(app.staticTexts["+1:00"].firstMatch.waitForExistence(timeout: 2))
        snap("audit_football_10_stoppage_settings", settle: 0.2)
        app.buttons["football_stoppage_undo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["+0:00"].firstMatch.waitForExistence(timeout: 2))
    }

    /// Current catalog audit. Each snapshot is produced by navigating the real app.
    func testAuditAllScoreboardEditingSurfaces() {
        let added = [(id: "shuttlecock", label: "毽球"), (id: "squash", label: "壁球"),
                     (id: "soft_tennis", label: "软式网球"), (id: "padel", label: "板式网球"),
                     (id: "football_5v5", label: "五人制足球")]
        let filter = ProcessInfo.processInfo.environment["AUDIT_GAME"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_AUDIT_GAME"]
        for item in scoreboards + added where filter == nil || filter!.split(separator: ",").contains(Substring(item.id)) {
            XCTContext.runActivity(named: "Audit \(item.id)") { _ in
                guard openPriorityScoreboardSetup(id: item.id, label: item.label) else {
                    XCTFail("Missing setup: \(item.id)"); return
                }
                guard tapStart() else { XCTFail("Cannot start \(item.id)"); return }
                XCUIDevice.shared.orientation = .landscapeRight
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                revealScoreboardChrome(fromLeftCorner: true)
                snap("audit_\(item.id)_01_board", settle: 0.3)
                let standardEdit = app.buttons["scoreboard_edit_button"].firstMatch
                let tennisEdit = app.buttons["tennis_scoreboard_edit_button"].firstMatch
                let edit = standardEdit.exists ? standardEdit : (tennisEdit.exists ? tennisEdit : app.buttons["pencil"].firstMatch)
                if item.id == "doudizhu" {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.09)).tap()
                    XCTAssertTrue(app.descendants(matching: .any)["doudizhu_player_0_name_editor"].firstMatch.waitForExistence(timeout: 2))
                    snap("audit_doudizhu_02_edit", settle: 0.3)
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.09)).tap()
                } else if edit.waitForExistence(timeout: 2), edit.isHittable {
                    edit.tap()
                    snap("audit_\(item.id)_02_edit", settle: 0.3)
                    if edit.exists, edit.isHittable { edit.tap() }
                } else if ["uno", "multiScoreboard"].contains(item.id) {
                    app.staticTexts["玩家 1"].firstMatch.press(forDuration: 1.2)
                    XCTAssertTrue(app.descendants(matching: .any)["multi_score_player_name_editor"].firstMatch.waitForExistence(timeout: 2))
                    snap("audit_\(item.id)_02_edit", settle: 0.3)
                    app.buttons["取消"].firstMatch.tap()
                } else {
                    XCTFail("Missing edit control: \(item.id)")
                }
                guard openPriorityScoreboardMenu() else {
                    XCTFail("Missing menu: \(item.id)"); return
                }
                snap("audit_\(item.id)_03_menu", settle: 0.2)
                XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "手表")).firstMatch.exists)
                let settings = app.descendants(matching: .any)["scoreboard_menu_action_displaySettings"].firstMatch
                guard settings.waitForExistence(timeout: 2) else {
                    XCTFail("Missing style entry: \(item.id)"); return
                }
                settings.tap()
                let hint = app.buttons["知道了"].firstMatch
                if hint.waitForExistence(timeout: 0.5), hint.isHittable { hint.tap() }
                let legacyStyle = ["basketball", "three_basketball", "nine_ball", "uno", "multiScoreboard"].contains(item.id)
                if !legacyStyle {
                    XCTAssertTrue(app.descendants(matching: .any)["scoreboard_style_editor"].firstMatch.waitForExistence(timeout: 3))
                }
                snap("audit_\(item.id)_04_style", settle: 0.3)
                // Select the rendered score text to open the actual typography panel.
                if !legacyStyle {
                    let score = app.descendants(matching: .any)["style_element_mainScore_side_left"].firstMatch
                    XCTAssertTrue(score.waitForExistence(timeout: 2), "Missing selectable score: \(item.id)")
                    let originalScore = score.exists ? score.label : ""
                    if score.exists { score.tap() }
                    snap("audit_\(item.id)_05_text_panel", settle: 0.3)
                    let slider = app.sliders.firstMatch
                    XCTAssertTrue(slider.waitForExistence(timeout: 2), "Typography panel unreachable: \(item.id)")
                    if slider.exists, slider.isHittable {
                        slider.adjust(toNormalizedSliderPosition: 1)
                        snap("audit_\(item.id)_06_max_font", settle: 0.3)
                    }
                    let close = app.buttons["完成当前面板"].firstMatch
                    if close.exists { close.tap() }
                    if score.exists { XCTAssertEqual(score.label, originalScore, "Style editing changed the score") }
                    if item.id == "snooker" {
                        for identifier in ["snooker_ball_1", "snooker_foul_button", "snooker_action_handover"] {
                            let action = app.buttons[identifier].firstMatch
                            XCTAssertFalse(action.exists, "Scoring control remained visible during style editing: \(identifier)")
                        }
                    }
                }
                let palette = app.buttons["样式与颜色"].firstMatch
                if palette.exists, palette.isHittable {
                    palette.tap()
                    snap("audit_\(item.id)_07_palette", settle: 0.2)
                    for (index, title) in ["背景", "主题", "字体"].enumerated() {
                        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title))
                            .allElementsBoundByIndex.first(where: { $0.isHittable })
                        if let entry {
                            entry.tap()
                            snap("audit_\(item.id)_\(8 + index)_palette_panel", settle: 0.3)
                            let close = app.buttons["完成当前面板"].firstMatch
                            XCTAssertTrue(close.waitForExistence(timeout: 1))
                            if close.exists, close.isHittable { close.tap() }
                            if index < 2, palette.exists, palette.isHittable { palette.tap() }
                        }
                    }
                }
                let cancel = app.buttons["退出样式编辑"].firstMatch
                if cancel.exists, cancel.isHittable { cancel.tap() }
                if !legacyStyle {
                    XCTAssertTrue(openPriorityScoreboardMenu())
                    app.descendants(matching: .any)["scoreboard_menu_action_displaySettings"].firstMatch.tap()
                    XCTAssertFalse(app.buttons["知道了"].firstMatch.waitForExistence(timeout: 0.5), "Usage hint reappeared")
                    let exit = app.buttons["退出样式编辑"].firstMatch
                    if exit.exists { exit.tap() }
                }
            }
        }
    }

    // MARK: - Launch

    private func relaunch(extraArguments: [String] = [], locale: UITestLocale.Configuration = UITestLocale.zhHans, waitForTabBar: Bool = true, orientation: UIDeviceOrientation = .portrait) {
        if app != nil {
            terminateAndWait(app)
        }
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", UITestLocale.languageValue(locale),
            "-AppleLocale", locale.locale,
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints",
            "-UITestScreenshotMode", "1"
        ] + extraArguments
        XCTAssertTrue(launchAndWait(app), "Screenshot app failed to reach the foreground")
        // 夹具会把根视图换成详情页，此时没有 Tab Bar 可等
        if waitForTabBar {
            XCTAssertTrue(waitForTabs(timeout: 12), "Tab bar not ready after launch")
        }
        // Ensure portrait for tab navigation
        XCUIDevice.shared.orientation = orientation
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
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

        relaunch()
        XCTAssertTrue(tapContaining("常用名称"), "Cannot open Common Names from Home")
        if app.navigationBars["常用名称"].waitForExistence(timeout: 3) {
            snap("07_home_common_names")
            if tapContaining("添加"), app.navigationBars["添加"].waitForExistence(timeout: 3) {
                snap("07b_home_common_names_add")
                dismissDialog()
            }
            navigateBack()
        }

        relaunch()
        XCTAssertTrue(tapContaining("常用地点"), "Cannot open Common Places from Home")
        if app.navigationBars["常用地点"].waitForExistence(timeout: 3) {
            snap("08_home_common_places")
            navigateBack()
        }

        relaunch()
        let identifiedEdit = app.buttons["home_quick_start_edit"]
        let edit = identifiedEdit.exists
            ? identifiedEdit
            : app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "编辑")).firstMatch
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

        return app.buttons["开始"].waitForExistence(timeout: 4)
            || app.buttons["Start"].waitForExistence(timeout: 1)
            || app.buttons["确认"].waitForExistence(timeout: 1)
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
        XCTAssertFalse(app.staticTexts["手表联动"].exists)
        XCTAssertFalse(app.buttons["手表联动"].exists)
        XCTAssertFalse(app.buttons["Watch Link"].exists)

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

    @discardableResult
    private func tapContaining(_ text: String) -> Bool {
        for _ in 0..<10 {
            let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            if button.waitForExistence(timeout: 0.5) {
                if button.isHittable {
                    button.tap()
                    return true
                }

                let window = app.windows.firstMatch
                let windowFrame = window.exists ? window.frame : app.frame
                let buttonFrame = button.frame
                if buttonFrame.maxY < windowFrame.minY {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
            } else {
                app.swipeUp()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
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
        let explicitBack = app.buttons.matching(identifier: "BackButton").firstMatch
        if explicitBack.exists, explicitBack.isHittable {
            explicitBack.tap()
            return
        }
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
