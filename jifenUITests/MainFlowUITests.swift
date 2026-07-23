import XCTest

final class MainFlowUITests: XCTestCase {
    private let tabNames = ["Home", "Records", "Score", "Timer", "Me"]
    private let destructiveKeywords = [
        "delete", "clear", "reset", "remove", "erase", "destroy",
        "删除", "清空", "重置", "移除", "抹掉"
    ]
    private let unstableKeywords = [
        "sheet grabber", "cancel", "back", "done", "close", "关闭", "取消"
    ]
    private let maxScrollPassesPerTab = 14
    private let cancelButtonKeywords = ["cancel", "取消", "关闭", "back", "返回"]
    private let preferredDialogButtons = [
        "Continue", "继续", "Confirm", "确认", "OK", "好", "Allow", "允许", "Done", "完成", "确定"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }

    func testMainTabsAreVisibleAndNavigable() {
        let app = launchApp()
        XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))

        for tab in tabNames {
            let button = tabButton(named: tab, in: app)
            XCTAssertTrue(button.exists, "Missing tab: \(tab)")
            button.tap()
            XCTAssertTrue(button.isHittable || button.isSelected, "Failed to select tab: \(tab)")
        }
    }

    func testMeTabContainsLocalSettings() {
        let app = launchApp()
        XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))

        let meTab = tabButton(named: "Me", in: app)
        XCTAssertTrue(meTab.exists)
        meTab.tap()

        XCTAssertTrue(app.staticTexts["Scoreboard Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
        XCTAssertTrue(app.staticTexts["Clear data"].exists)
        XCTAssertTrue(app.staticTexts["Rate App"].exists)
        XCTAssertTrue(app.staticTexts["Share with Friends"].exists)
        XCTAssertTrue(app.staticTexts["FAQ"].exists)
        XCTAssertTrue(app.staticTexts["About Us"].exists)
        XCTAssertFalse(app.staticTexts["Common Names"].exists)
    }

    func testHomeContainsCommonNamesAndPlaces() {
        let app = launchApp()
        XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))

        let names = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Common Names")).firstMatch
        let places = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Common Places")).firstMatch
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        XCTAssertTrue(names.label.contains("Teams and players"))
        XCTAssertTrue(places.exists)
        XCTAssertTrue(places.label.contains("Venues, courts, places"))
    }

    func testTapVisibleComponentsAcrossAllTabs() {
        for tab in tabNames {
            let app = launchApp()
            defer { app.terminate() }

            XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))
            XCTAssertTrue(selectTab(named: tab, in: app), "Failed to select tab: \(tab)")

            let tappedCount = crawlAllVisibleComponents(in: app, tab: tab)
            XCTAssertGreaterThan(tappedCount, 0, "No tappable components found in tab: \(tab)")
            ensureReturnedToTabRoot(app)
        }
    }

    func testPingPongDoublesSetupShowsAllPlayersOnScoreboard() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(openPingPongSetup(in: app))
        let modeControl = app.segmentedControls["singles_doubles_picker"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 3))
        let doublesOption = app.buttons["doubles_option"]
        if doublesOption.exists {
            doublesOption.tap()
        } else {
            modeControl.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        }

        XCTAssertEqual(modeControl.value as? String, "双打")
        XCTAssertTrue(app.textFields.element(boundBy: 3).waitForExistence(timeout: 3))
        app.buttons["开始"].tap()

        for name in ["红A", "红B", "蓝A", "蓝B"] {
            let player = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", name))
                .firstMatch
            XCTAssertTrue(player.waitForExistence(timeout: 8), "Missing doubles player: \(name)")
        }
    }

    func testScoreboardShowsBottomLeftBackButton() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(openPingPongSetup(in: app))
        app.buttons["开始"].tap()

        XCUIDevice.shared.orientation = .landscapeLeft
        let back = app.descendants(matching: .any)["scoreboard_back_button"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "Scoreboard missing bottom-left back button")
        XCUIDevice.shared.orientation = .portrait
    }

    func testPlayAllSetupSupportsEvenAndCustomSetCounts() {
        runPlayAllSetup(appearance: "light")
    }

    func testPlayAllSetupInDarkMode() {
        runPlayAllSetup(appearance: "dark")
    }

    func testNewTimerAndToolsParityFlow() {
        var app = launchChineseApp()
        defer { app.terminate() }

        XCTAssertTrue(app.tabBars.buttons["计时"].waitForExistence(timeout: 8))
        app.tabBars.buttons["计时"].tap()
        let checkers = app.descendants(matching: .any)["timer_dest_checkers"]
        XCTAssertTrue(checkers.waitForExistence(timeout: 5))
        checkers.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "国际跳棋")).firstMatch.waitForExistence(timeout: 5))
        addScreenshot("International checkers setup")

        app.terminate()
        app = launchChineseApp(arguments: ["-UITestOpenTools"])
        XCTAssertTrue(openToolsList(in: app))
        let randomTeam = app.descendants(matching: .any)["tool_card_random_team"]
        XCTAssertTrue(randomTeam.waitForExistence(timeout: 5))
        randomTeam.tap()
        XCTAssertTrue(app.buttons["random_team_players_4"].waitForExistence(timeout: 5))
        app.buttons["random_team_players_4"].tap()
        XCTAssertTrue(app.buttons["一键分组"].waitForExistence(timeout: 5))
        addScreenshot("Random team - 4 players")

        app.terminate()
        app = launchChineseApp(arguments: ["-UITestOpenTools"])
        XCTAssertTrue(openToolsList(in: app))
        let barrage = app.descendants(matching: .any)["tool_card_fullscreen_barrage"]
        XCTAssertTrue(barrage.waitForExistence(timeout: 5))
        barrage.tap()
        let message = app.textFields["barrage_message_field"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.tap()
        message.typeText("加油！")
        app.buttons["barrage_start_static"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["barrage_running"].waitForExistence(timeout: 5))
        addScreenshot("Fullscreen barrage - static")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.descendants(matching: .any)["barrage_running"].waitForExistence(timeout: 5))
        addScreenshot("Fullscreen barrage - landscape")
        XCUIDevice.shared.orientation = .portrait

        app.terminate()
        app = launchLocalizedApp(language: "en", locale: "en_US", appearance: "dark")
        XCTAssertTrue(app.tabBars.buttons["Timer"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Timer"].tap()
        let englishCheckers = app.descendants(matching: .any)["timer_dest_checkers"]
        XCTAssertTrue(englishCheckers.waitForExistence(timeout: 5))
        englishCheckers.tap()
        addScreenshot("International checkers setup - English dark")

        app.terminate()
        app = launchLocalizedApp(language: "en", locale: "en_US", appearance: "dark", arguments: ["-UITestOpenTools"])
        XCTAssertTrue(openToolsList(in: app))
        app.descendants(matching: .any)["tool_card_random_team"].tap()
        let fourPlayers = app.buttons["random_team_players_4"]
        XCTAssertTrue(fourPlayers.waitForExistence(timeout: 5))
        fourPlayers.tap()
        XCTAssertTrue(app.buttons["Simulate"].waitForExistence(timeout: 5))
        addScreenshot("Random team - English dark")

        app.terminate()
        app = launchLocalizedApp(language: "en", locale: "en_US", appearance: "dark", arguments: ["-UITestOpenTools"])
        XCTAssertTrue(openToolsList(in: app))
        app.descendants(matching: .any)["tool_card_fullscreen_barrage"].tap()
        XCTAssertTrue(app.textFields["barrage_message_field"].waitForExistence(timeout: 5))
        addScreenshot("Fullscreen barrage editor - English dark")
    }

    func testAll23RecordDetailFixturesUseProjectMatrix() {
        defer { clearRecordFixtures() }
        let trendProjects: Set<String> = [
            "pingpong", "badminton", "pickleball", "basketball", "three_basketball",
            "volleyball", "beach_volleyball", "air_volleyball", "archery_dual",
            "billiards", "nine_ball", "snooker", "foosball", "simple_score"
        ]
        let allProjects = [
            "pingpong", "badminton", "tennis", "pickleball", "football", "basketball",
            "three_basketball", "volleyball", "beach_volleyball", "air_volleyball",
            "archery_dual", "boxing", "billiards", "eight_ball", "nine_ball", "snooker",
            "doudizhu", "guandan", "shengji", "uno", "foosball", "simple_score", "multi_scoreboard"
        ]

        for project in allProjects {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                "-UITestRecordFixtures", "-UITestRecordDetail", project
            ]
            app.launch()
            XCTAssertTrue(app.buttons["再来一局"].waitForExistence(timeout: 5), "Missing replay for \(project)")
            XCTAssertTrue(app.buttons["复盘"].exists || app.staticTexts["复盘"].exists, "Missing recap for \(project)")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "fixture")).firstMatch.exists, "Internal fixture text leaked for \(project)")
            let hasTrend = app.staticTexts["比分趋势"].exists
            XCTAssertEqual(hasTrend, trendProjects.contains(project), "Trend policy mismatch for \(project)")
            app.terminate()
        }
    }

    private func clearRecordFixtures() {
        let cleanup = XCUIApplication()
        cleanup.launchArguments += ["-UITestClearRecordFixtures"]
        cleanup.launch()
        cleanup.terminate()
    }

    private func launchChineseApp(arguments: [String] = []) -> XCUIApplication {
        launchLocalizedApp(language: "zh-Hans", locale: "zh_CN", arguments: arguments)
    }

    private func launchLocalizedApp(
        language: String,
        locale: String,
        appearance: String? = nil,
        arguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if let appearance {
            app.launchArguments += ["-jifen-v2.appAppearanceMode", appearance]
        }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private func openToolsList(in app: XCUIApplication) -> Bool {
        if app.descendants(matching: .any)["tool_card_random_team"].waitForExistence(timeout: 5) {
            return true
        }
        guard app.tabBars.buttons["首页"].waitForExistence(timeout: 8) else { return false }
        app.tabBars.buttons["首页"].tap()
        let allTools = app.buttons["home_all_tools_button"]
        for _ in 0..<8 {
            if allTools.exists && allTools.isHittable {
                allTools.tap()
                return app.descendants(matching: .any)["tool_card_random_team"].waitForExistence(timeout: 5)
            }
            app.swipeUp(velocity: .fast)
        }
        return false
    }

    private func addScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func runPlayAllSetup(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-jifen-v2.appAppearanceMode", appearance
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(openPingPongSetup(in: app))

        let modeSelector = app.buttons["match_completion_mode_selector"]
        XCTAssertTrue(modeSelector.waitForExistence(timeout: 5))
        XCTAssertTrue(modeSelector.label.contains("经典"))
        modeSelector.tap()

        let playAll = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "打满")).firstMatch
        XCTAssertTrue(playAll.waitForExistence(timeout: 3))
        playAll.tap()
        XCTAssertTrue(modeSelector.label.contains("打满"))

        let evenSetOption = app.buttons["2"]
        XCTAssertTrue(evenSetOption.waitForExistence(timeout: 3))
        evenSetOption.tap()
        XCTAssertFalse(app.staticTexts["经典模式请输入 1-99 的奇数；打满模式请输入 1-99。"].exists)

        let customSetsButton = app.buttons["custom_match_sets_button"]
        XCTAssertTrue(customSetsButton.waitForExistence(timeout: 3))
        customSetsButton.tap()
        let customField = app.textFields["custom_max_sets_field"]
        XCTAssertTrue(customField.waitForExistence(timeout: 3))
        customField.tap()
        customField.typeText("8")
        XCTAssertEqual(customField.value as? String, "8")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Play all setup - \(appearance)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func openPingPongSetup(in app: XCUIApplication) -> Bool {
        let scoreTab = app.tabBars.buttons["计分"]
        guard scoreTab.waitForExistence(timeout: 8) else { return false }
        scoreTab.tap()

        let card = app.descendants(matching: .any)["scoreboard_catalog_pingpong"]
        guard card.waitForExistence(timeout: 5) else { return false }
        card.tap()
        return app.segmentedControls["singles_doubles_picker"].waitForExistence(timeout: 5)
    }

    @discardableResult
    private func crawlAllVisibleComponents(in app: XCUIApplication, tab: String) -> Int {
        var seenFingerprints = Set<String>()
        var totalTapped = 0
        var staleRounds = 0
        var shouldSwipeUp = true

        for _ in 0..<maxScrollPassesPerTab {
            ensureReturnedToTabRoot(app)
            guard selectTab(named: tab, in: app) else { break }

            let tappedThisRound = tapAllSafeVisibleCandidates(in: app, seenFingerprints: &seenFingerprints)
            totalTapped += tappedThisRound

            if tappedThisRound == 0 {
                staleRounds += 1
            } else {
                staleRounds = 0
            }

            if staleRounds >= 3 { break }
            if !performScroll(in: app, up: shouldSwipeUp) { break }
            shouldSwipeUp.toggle()
        }

        return totalTapped
    }

    @discardableResult
    private func tapAllSafeVisibleCandidates(in app: XCUIApplication, seenFingerprints: inout Set<String>) -> Int {
        var tapped = 0
        let candidates = candidateElements(in: app)

        for element in candidates {
            guard isVisiblyTapCandidate(element, in: app) else { continue }
            guard isSafeToTap(element: element) else { continue }

            let fingerprint = fingerprint(for: element)
            guard !seenFingerprints.contains(fingerprint) else { continue }

            seenFingerprints.insert(fingerprint)
            let label = debugLabel(for: element)
            var didTap = false

            XCTContext.runActivity(named: "Tap \(label)") { _ in
                didTap = safeTap(element, in: app)
            }
            guard didTap else { continue }
            tapped += 1

            dismissSystemAlertIfNeeded()
            ensureReturnedToTabRoot(app)
        }

        return tapped
    }

    private func candidateElements(in app: XCUIApplication) -> [XCUIElement] {
        app.buttons.allElementsBoundByIndex +
            app.cells.allElementsBoundByIndex +
            app.collectionViews.cells.allElementsBoundByIndex +
            app.tables.cells.allElementsBoundByIndex +
            app.segmentedControls.buttons.allElementsBoundByIndex +
            app.switches.allElementsBoundByIndex
    }

    private func isSafeToTap(element: XCUIElement) -> Bool {
        let primary = debugLabel(for: element)
        let secondary = "\(element.identifier) \(element.label)".lowercased()
        guard !primary.isEmpty else { return false }
        guard !tabNames.contains(primary) else { return false }
        guard !destructiveKeywords.contains(where: { primary.lowercased().contains($0) || secondary.contains($0) }) else { return false }
        guard !unstableKeywords.contains(where: { primary.lowercased().contains($0) || secondary.contains($0) }) else { return false }
        return true
    }

    private func fingerprint(for element: XCUIElement) -> String {
        let frame = element.frame
        let x = Int(frame.minX.rounded())
        let y = Int(frame.minY.rounded())
        let w = Int(frame.width.rounded())
        let h = Int(frame.height.rounded())
        return "\(element.elementType.rawValue)|\(element.identifier)|\(element.label)|\(x)|\(y)|\(w)|\(h)"
    }

    @discardableResult
    private func performScroll(in app: XCUIApplication, up: Bool) -> Bool {
        if app.scrollViews.firstMatch.exists {
            up ? app.scrollViews.firstMatch.swipeUp() : app.scrollViews.firstMatch.swipeDown()
            return true
        }
        if app.tables.firstMatch.exists {
            up ? app.tables.firstMatch.swipeUp() : app.tables.firstMatch.swipeDown()
            return true
        }
        if app.collectionViews.firstMatch.exists {
            up ? app.collectionViews.firstMatch.swipeUp() : app.collectionViews.firstMatch.swipeDown()
            return true
        }

        up ? app.swipeUp() : app.swipeDown()
        return true
    }

    private func isVisiblyTapCandidate(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width >= 8, frame.height >= 8 else { return false }
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite else { return false }

        let window = app.windows.firstMatch
        let windowFrame = window.exists ? window.frame : CGRect(x: 0, y: 0, width: 390, height: 844)
        return frame.intersects(windowFrame)
    }

    @discardableResult
    private func safeTap(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else { return false }

        let window = app.windows.firstMatch
        let windowFrame = window.exists ? window.frame : CGRect(x: 0, y: 0, width: 390, height: 844)
        guard windowFrame.width > 0, windowFrame.height > 0 else { return false }

        let normalizedX = (frame.midX - windowFrame.minX) / windowFrame.width
        let normalizedY = (frame.midY - windowFrame.minY) / windowFrame.height
        guard normalizedX.isFinite, normalizedY.isFinite else { return false }
        guard (0...1).contains(normalizedX), (0...1).contains(normalizedY) else { return false }

        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: normalizedY))
        coordinate.tap()
        return true
    }

    private func debugLabel(for element: XCUIElement) -> String {
        if !element.identifier.isEmpty { return element.identifier }
        if !element.label.isEmpty { return element.label }
        let frame = element.frame
        if frame.minX.isFinite, frame.minY.isFinite {
            return "\(element.elementType.rawValue)-\(Int(frame.minX))-\(Int(frame.minY))"
        }
        return "\(element.elementType.rawValue)-unknown-frame"
    }

    private func navigateBackIfNeeded(from app: XCUIApplication) {
        for _ in 0..<3 {
            if app.tabBars.firstMatch.exists { return }

            let navBack = app.navigationBars.buttons.allElementsBoundByIndex.first {
                isVisiblyTapCandidate($0, in: app) && isNonCancelButton($0)
            }
            if let navBack {
                _ = safeTap(navBack, in: app)
            } else if isVisiblyTapCandidate(app.buttons["Back"], in: app) {
                _ = safeTap(app.buttons["Back"], in: app)
            } else if isVisiblyTapCandidate(app.buttons["Done"], in: app) {
                _ = safeTap(app.buttons["Done"], in: app)
            } else {
                app.swipeRight()
            }
        }
    }

    private func ensureReturnedToTabRoot(_ app: XCUIApplication) {
        XCUIDevice.shared.orientation = .portrait
        for _ in 0..<5 {
            if tabBarUsable(in: app) { return }
            if dismissKnownOverlayIfNeeded(in: app) { continue }
            navigateBackIfNeeded(from: app)
        }
    }

    private func tabBarUsable(in app: XCUIApplication) -> Bool {
        return tabNames.contains {
            let button = tabButton(named: $0, in: app)
            return isVisiblyTapCandidate(button, in: app)
        }
    }

    @discardableResult
    private func selectTab(named tab: String, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            XCUIDevice.shared.orientation = .portrait
            let tabButton = tabButton(named: tab, in: app)
            if isVisiblyTapCandidate(tabButton, in: app), safeTap(tabButton, in: app) {
                return true
            }
            if dismissKnownOverlayIfNeeded(in: app) { continue }
            navigateBackIfNeeded(from: app)
        }
        return false
    }

    @discardableResult
    private func dismissKnownOverlayIfNeeded(in app: XCUIApplication) -> Bool {
        if tapPreferredDialogButton(in: app.alerts.firstMatch, app: app) { return true }
        if tapPreferredDialogButton(in: app.sheets.firstMatch, app: app) { return true }

        let overlayButtons = ["xmark", "Close", "Done", "Back"]
        for title in overlayButtons {
            let button = app.buttons[title]
            if isVisiblyTapCandidate(button, in: app), safeTap(button, in: app) {
                return true
            }
        }

        let navBack = app.navigationBars.buttons.allElementsBoundByIndex.first {
            isVisiblyTapCandidate($0, in: app) && isNonCancelButton($0)
        }
        if let navBack {
            return safeTap(navBack, in: app)
        }

        return false
    }

    @discardableResult
    private func tapPreferredDialogButton(in container: XCUIElement, app: XCUIApplication) -> Bool {
        guard container.exists else { return false }

        for title in preferredDialogButtons {
            let button = container.buttons[title]
            if isVisiblyTapCandidate(button, in: app), safeTap(button, in: app) {
                return true
            }
        }

        let buttons = container.buttons.allElementsBoundByIndex
        if let fallback = buttons.first(where: {
            isNonCancelButton($0) && isVisiblyTapCandidate($0, in: app)
        }) {
            return safeTap(fallback, in: app)
        }

        return false
    }

    private func isNonCancelButton(_ button: XCUIElement) -> Bool {
        let text = (button.label.isEmpty ? button.identifier : button.label).lowercased()
        guard !text.isEmpty else { return true }
        return !cancelButtonKeywords.contains(where: { text.contains($0) })
    }

    private func dismissSystemAlertIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButtons = ["Allow", "允许", "OK", "好", "Continue", "继续"]

        for title in allowButtons where springboard.buttons[title].exists {
            springboard.buttons[title].tap()
            break
        }
    }

    private func tabButton(named tab: String, in app: XCUIApplication) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons[tab]
        if tabBarButton.exists { return tabBarButton }

        let predicate = NSPredicate(format: "label == %@", tab)
        return app.buttons.matching(predicate).firstMatch
    }

    private func waitForTabNavigationReady(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if tabNames.contains(where: { tabButton(named: $0, in: app).exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        return false
    }
}
