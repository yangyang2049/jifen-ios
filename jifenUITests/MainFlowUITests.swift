import UIKit
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
            "-AppleLocale", "en_US",
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints"
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

    func testEnglishLocalizationSmokeHasNoChineseOrRawKeys() {
        var app = launchApp()
        XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))

        for tab in tabNames {
            XCTAssertTrue(selectTab(named: tab, in: app), "Failed to select tab: \(tab)")
            if tab == "Home" {
                // Home can contain persisted names from recent or unfinished
                // games. Verify stable product chrome instead of user content.
                for label in ["Home", "Recent Records"] {
                    XCTAssertTrue(
                        app.descendants(matching: .any)[label].exists,
                        "Missing localized Home label: \(label)"
                    )
                }
                XCTAssertTrue(
                    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "New Game")).firstMatch.exists,
                    "Missing localized New Game action"
                )
                assertRawLocalizationKeysAreAbsent(
                    ["tab_home", "recent_records", "home_new_game", "home_no_records"],
                    in: app,
                    context: "Home tab"
                )
            } else if tab == "Records" {
                // Persisted records may contain user-entered Chinese names. Verify
                // the product chrome without treating user content as a translation.
                for label in ["Records", "All", "Score", "Timer"] {
                    XCTAssertTrue(
                        app.descendants(matching: .any)[label].exists,
                        "Missing localized Records label: \(label)"
                    )
                }
                assertRawLocalizationKeysAreAbsent(
                    ["filter", "game_type_filter", "time_filter", "record_empty"],
                    in: app,
                    context: "Records tab"
                )
            } else {
                assertEnglishLocalization(in: app, context: "\(tab) tab")
            }
        }

        XCTAssertTrue(selectTab(named: "Home", in: app))
        let newGame = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "New Game")).firstMatch
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        newGame.tap()
        XCTAssertTrue(app.navigationBars["Select Game"].waitForExistence(timeout: 5))
        let newGameDialog = app.descendants(matching: .any)["new_game_dialog"]
        XCTAssertTrue(newGameDialog.waitForExistence(timeout: 3))
        assertEnglishLocalization(in: newGameDialog, context: "Select Game")
        app.terminate()

        for gameID in ["basketball", "doudizhu"] {
            app = launchLocalizedApp(language: "en", locale: "en_US")
            XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))
            XCTAssertTrue(selectTab(named: "Score", in: app))
            let card = app.descendants(matching: .any)["scoreboard_catalog_\(gameID)"]
            XCTAssertTrue(scrollUntilExists(card, in: app), "Missing scoreboard card: \(gameID)")
            card.tap()
            dismissEnglishWatchGuideIfNeeded(in: app)
            assertEnglishLocalization(in: app, context: "\(gameID) setup")

            let start = app.buttons["Start"]
            if start.waitForExistence(timeout: 2), start.isHittable {
                start.tap()
            }
            XCUIDevice.shared.orientation = .landscapeLeft
            _ = app.descendants(matching: .any)["scoreboard_back_button"].waitForExistence(timeout: 8)
            assertEnglishLocalization(in: app, context: "\(gameID) scoreboard")
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        app = launchLocalizedApp(
            language: "en",
            locale: "en_US",
            arguments: ["-UITestRecordFixtures", "-UITestRecordDetail", "basketball"]
        )
        XCTAssertTrue(app.buttons["Play Again"].waitForExistence(timeout: 5))
        assertEnglishLocalization(in: app, context: "record detail")
        app.terminate()

        for toolID in ["points_table", "aa_calculator", "ten_second"] {
            app = launchLocalizedApp(
                language: "en",
                locale: "en_US",
                arguments: ["-UITestOpenTools"]
            )
            XCTAssertTrue(openToolsList(in: app))
            let card = app.descendants(matching: .any)["tool_card_\(toolID)"]
            XCTAssertTrue(scrollUntilExists(card, in: app), "Missing tool card: \(toolID)")
            card.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
            if toolID == "points_table" {
                // Saved table and team names are user content and may use any
                // language. Verify the stable product chrome instead.
                XCTAssertTrue(app.navigationBars["Standings"].exists)
                assertRawLocalizationKeysAreAbsent(
                    ["points_table_title", "points_table_empty", "points_table_empty_hint"],
                    in: app,
                    context: "points_table tool"
                )
            } else {
                assertEnglishLocalization(in: app, context: "\(toolID) tool")
            }
            app.terminate()
        }
    }

    func testFirstLaunchLegalConsentGatesMainContent() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UITestDisableAnalytics",
            "-legal_documents_accepted_version", ""
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["使用前请先阅读并同意"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["首页"].exists)

        let agreeButton = app.buttons["同意并继续"]
        XCTAssertTrue(agreeButton.exists)
        XCTAssertFalse(agreeButton.isEnabled)

        app.buttons["同意用户协议和隐私政策"].tap()
        XCTAssertTrue(agreeButton.isEnabled)
        agreeButton.tap()

        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 8))
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

    func testMeSecondaryPagesUseExpectedPresentation() {
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))
        let meTab = tabButton(named: "Me", in: app)
        XCTAssertTrue(meTab.exists)
        meTab.tap()

        let destinations = [
            (
                entry: "settings_scoreboard_entry",
                sheet: "settings_scoreboard_sheet",
                close: "settings_scoreboard_sheet_close",
                title: "Scoreboard Settings"
            ),
            (
                entry: "settings_faq_entry",
                sheet: "settings_faq_sheet",
                close: "settings_faq_sheet_close",
                title: "FAQ"
            ),
            (
                entry: "settings_about_entry",
                sheet: "settings_about_sheet",
                close: "settings_about_sheet_close",
                title: "About Us"
            )
        ]

        for destination in destinations {
            let entry = app.descendants(matching: .any)[destination.entry]
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "Missing entry: \(destination.entry)")
            entry.tap()

            let sheet = app.descendants(matching: .any)[destination.sheet]
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Missing sheet: \(destination.sheet)")
                XCTAssertFalse(entry.isHittable, "Underlying Me entry remained interactive")

                let close = app.buttons[destination.close]
                XCTAssertTrue(close.waitForExistence(timeout: 3), "Missing close button: \(destination.close)")
                close.tap()
                XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "Sheet did not close: \(destination.sheet)")
            } else {
                XCTAssertFalse(sheet.exists, "iPhone unexpectedly presented a settings sheet")
                let navigationBar = app.navigationBars[destination.title]
                XCTAssertTrue(navigationBar.waitForExistence(timeout: 5), "Missing pushed page: \(destination.title)")
                let backButton = navigationBar.buttons.element(boundBy: 0)
                XCTAssertTrue(backButton.exists, "Missing back button: \(destination.title)")
                backButton.tap()
            }
        }
    }

    func testIPadMeFormSheetSupportsRotationAndInteractiveDismissal() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only Form Sheet behavior")
        }

        let app = launchApp()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))
        tabButton(named: "Me", in: app).tap()

        let entry = app.descendants(matching: .any)["settings_faq_entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()

        let sheet = app.descendants(matching: .any)["settings_faq_sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Sheet disappeared after rotation")
        let close = app.buttons["settings_faq_sheet_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))

        let dragStart = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
        let dragEnd = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "System drag gesture did not dismiss the sheet")
    }

    func testIPadMeFormSheetPreservesContentInteractions() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only Form Sheet behavior")
        }

        let app = launchApp()
        var originalKeepScreenOnValue: String?
        defer {
            if let originalKeepScreenOnValue {
                restoreKeepScreenOn(in: app, to: originalKeepScreenOnValue)
            }
            app.terminate()
        }

        XCTAssertTrue(waitForTabNavigationReady(in: app, timeout: 8))
        tabButton(named: "Me", in: app).tap()

        app.descendants(matching: .any)["settings_scoreboard_entry"].tap()
        let scoreboardSheet = app.descendants(matching: .any)["settings_scoreboard_sheet"]
        XCTAssertTrue(scoreboardSheet.waitForExistence(timeout: 5))
        scoreboardSheet.swipeUp()

        var keepScreenOn = app.switches["scoreboard_keep_screen_on_toggle"]
        XCTAssertTrue(keepScreenOn.waitForExistence(timeout: 3))
        let originalValue = String(describing: keepScreenOn.value)
        originalKeepScreenOnValue = originalValue
        keepScreenOn.tap()
        let updatedValue = String(describing: keepScreenOn.value)
        XCTAssertNotEqual(updatedValue, originalValue, "Setting toggle did not change")

        let help = app.buttons["scoreboard_immersive_mode_toggle_help"]
        XCTAssertTrue(help.waitForExistence(timeout: 3))
        help.tap()
        let helpAlert = app.alerts.firstMatch
        XCTAssertTrue(helpAlert.waitForExistence(timeout: 3), "Scoreboard help Alert did not appear")
        let helpDismiss = helpAlert.buttons["Got It"]
        XCTAssertTrue(helpDismiss.waitForExistence(timeout: 2), "Scoreboard help Alert was not localized in English")
        helpDismiss.tap()

        app.buttons["settings_scoreboard_sheet_close"].tap()
        XCTAssertTrue(scoreboardSheet.waitForNonExistence(timeout: 5))

        app.descendants(matching: .any)["settings_scoreboard_entry"].tap()
        XCTAssertTrue(scoreboardSheet.waitForExistence(timeout: 5))
        scoreboardSheet.swipeUp()
        keepScreenOn = app.switches["scoreboard_keep_screen_on_toggle"]
        XCTAssertTrue(keepScreenOn.waitForExistence(timeout: 3))
        XCTAssertEqual(String(describing: keepScreenOn.value), updatedValue, "Setting did not persist after reopening")
        keepScreenOn.tap()
        XCTAssertEqual(String(describing: keepScreenOn.value), originalValue, "Test did not restore the original setting")
        app.buttons["settings_scoreboard_sheet_close"].tap()
        XCTAssertTrue(scoreboardSheet.waitForNonExistence(timeout: 5))

        app.descendants(matching: .any)["settings_faq_entry"].tap()
        let faqSheet = app.descendants(matching: .any)["settings_faq_sheet"]
        XCTAssertTrue(faqSheet.waitForExistence(timeout: 5))
        app.buttons["settings_faq_question_1"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings_faq_answer_1"].waitForExistence(timeout: 3),
            "FAQ answer did not expand"
        )
        app.buttons["settings_faq_sheet_close"].tap()
        XCTAssertTrue(faqSheet.waitForNonExistence(timeout: 5))

        app.descendants(matching: .any)["settings_about_entry"].tap()
        let aboutSheet = app.descendants(matching: .any)["settings_about_sheet"]
        XCTAssertTrue(aboutSheet.waitForExistence(timeout: 5))
        for identifier in ["settings_about_terms_link", "settings_about_feedback_link"] {
            let link = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(link.waitForExistence(timeout: 3), "Missing About link: \(identifier)")
            XCTAssertTrue(link.isHittable, "About link is not interactive: \(identifier)")
        }
        app.buttons["settings_about_sheet_close"].tap()
        XCTAssertTrue(aboutSheet.waitForNonExistence(timeout: 5))
    }

    private func restoreKeepScreenOn(in app: XCUIApplication, to expectedValue: String) {
        guard app.state == .runningForeground else { return }

        let alert = app.alerts.firstMatch
        if alert.exists {
            let dismissButton = alert.buttons.firstMatch
            if dismissButton.exists, dismissButton.isHittable {
                dismissButton.tap()
            }
        }

        var toggle = app.switches["scoreboard_keep_screen_on_toggle"]
        if !toggle.exists {
            for identifier in [
                "settings_faq_sheet_close",
                "settings_about_sheet_close"
            ] {
                let close = app.buttons[identifier]
                if close.exists, close.isHittable {
                    close.tap()
                    _ = close.waitForNonExistence(timeout: 2)
                }
            }

            let entry = app.descendants(matching: .any)["settings_scoreboard_entry"]
            if entry.waitForExistence(timeout: 2), entry.isHittable {
                entry.tap()
                let sheet = app.descendants(matching: .any)["settings_scoreboard_sheet"]
                if sheet.waitForExistence(timeout: 2) {
                    sheet.swipeUp()
                }
            }
            toggle = app.switches["scoreboard_keep_screen_on_toggle"]
        }

        if toggle.waitForExistence(timeout: 2),
           String(describing: toggle.value) != expectedValue,
           toggle.isHittable {
            toggle.tap()
        }
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
            "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints"
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
            "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints"
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

    func testScoreboardUsageHintSupportsFirstEntryAndMenuReopen() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent",
            "-UITestResetScoreboardUsageHints"
        ]
        app.launch()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        XCTAssertTrue(openPingPongSetup(in: app))
        app.buttons["开始"].tap()

        let dialog = app.descendants(matching: .any)["scoreboard_usage_hint_dialog"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["scoreboard_usage_hint_body"].exists)

        let menuButton = app.buttons["scoreboard_menu_button"]
        XCTAssertTrue(menuButton.exists)
        XCTAssertFalse(menuButton.isHittable, "Usage dialog must block scoreboard controls")

        app.buttons["scoreboard_usage_hint_confirm"].tap()
        XCTAssertFalse(dialog.waitForExistence(timeout: 1))
        XCTAssertTrue(menuButton.waitForExistence(timeout: 3))
        XCTAssertTrue(menuButton.isHittable)

        let backButton = app.buttons["scoreboard_back_button"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()
        backButton.tap()
        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(openPingPongSetup(in: app))
        app.buttons["开始"].tap()
        XCTAssertFalse(
            dialog.waitForExistence(timeout: 2),
            "A scoreboard must not show its automatic hint twice"
        )

        menuButton.tap()
        let usageMenuItem = app.descendants(matching: .any)["scoreboard_menu_action_usageHint"]
        XCTAssertTrue(usageMenuItem.waitForExistence(timeout: 3))
        usageMenuItem.tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))

        app.buttons["scoreboard_usage_hint_close"].tap()
        XCTAssertFalse(dialog.waitForExistence(timeout: 1))
        XCTAssertTrue(menuButton.isHittable)

        backButton.tap()
        backButton.tap()
        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(openPingPongSetup(in: app))
        let modeControl = app.segmentedControls["singles_doubles_picker"]
        let doublesOption = app.buttons["doubles_option"]
        if doublesOption.exists {
            doublesOption.tap()
        } else {
            modeControl.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        }
        XCTAssertEqual(modeControl.value as? String, "双打")
        app.buttons["开始"].tap()
        XCTAssertTrue(
            dialog.waitForExistence(timeout: 8),
            "Singles and doubles must keep independent lifetime automatic hint state"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["scoreboard_usage_hint_body"]
                .label.contains("双打"),
            "Doubles must use its own help copy"
        )
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

        let timerTab = app.tabBars.buttons["计时"]
        if timerTab.waitForExistence(timeout: 4) {
            timerTab.tap()
        } else {
            let regularTimerButton = app.buttons["计时"].firstMatch
            XCTAssertTrue(regularTimerButton.waitForExistence(timeout: 4))
            regularTimerButton.tap()
        }
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
        XCTAssertTrue(scrollUntilExists(barrage, in: app))
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
        let englishTimerTab = app.buttons["main_tab_3"].firstMatch
        XCTAssertTrue(englishTimerTab.waitForExistence(timeout: 8))
        englishTimerTab.tap()
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
        let englishBarrage = app.descendants(matching: .any)["tool_card_fullscreen_barrage"]
        XCTAssertTrue(scrollUntilExists(englishBarrage, in: app))
        englishBarrage.tap()
        XCTAssertTrue(app.textFields["barrage_message_field"].waitForExistence(timeout: 5))
        addScreenshot("Fullscreen barrage editor - English dark")
    }

    func testBoardTimerPauseAndManualEndFlow() {
        let app = launchChineseApp()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        let timerTab = app.tabBars.buttons["计时"]
        if timerTab.waitForExistence(timeout: 4) {
            timerTab.tap()
        } else {
            let regularTimerButton = app.buttons["计时"].firstMatch
            XCTAssertTrue(regularTimerButton.waitForExistence(timeout: 4))
            regularTimerButton.tap()
        }
        let checkers = app.descendants(matching: .any)["timer_dest_checkers"]
        XCTAssertTrue(scrollUntilExists(checkers, in: app))
        checkers.tap()

        let setupStart = app.buttons["开始"].firstMatch
        XCTAssertTrue(setupStart.waitForExistence(timeout: 5))
        setupStart.tap()

        let boardStart = app.buttons["board_timer_start_button"]
        XCTAssertTrue(boardStart.waitForExistence(timeout: 8))
        let firstIndicator = app.buttons["board_timer_first_indicator_player_1"]
        XCTAssertTrue(firstIndicator.exists)
        firstIndicator.tap()
        let boardToast = app.descendants(matching: .any)["board_timer_toast"]
        XCTAssertTrue(boardToast.waitForExistence(timeout: 2))
        XCTAssertTrue(boardToast.label.contains("红方先手"))

        let initialIndicatorFrame = firstIndicator.frame
        app.buttons["board_timer_swap_button"].tap()
        XCTAssertTrue(firstIndicator.waitForExistence(timeout: 2))
        XCTAssertNotEqual(firstIndicator.frame.midX, initialIndicatorFrame.midX)

        boardStart.tap()
        let player1Hint = app.buttons["board_timer_tap_hint_player_1"]
        XCTAssertTrue(player1Hint.waitForExistence(timeout: 3))

        app.descendants(matching: .any)["board_timer_player_2"].tap()
        XCTAssertTrue(player1Hint.exists, "Tapping the inactive player must not change turns")
        player1Hint.tap()

        let player2Hint = app.buttons["board_timer_tap_hint_player_2"]
        XCTAssertTrue(player2Hint.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["board_timer_pause_button"].exists)
        app.buttons["board_timer_pause_button"].tap()

        let thinkingIndicator = app.buttons["board_timer_thinking_indicator_player_2"]
        XCTAssertTrue(thinkingIndicator.waitForExistence(timeout: 3))
        thinkingIndicator.tap()
        XCTAssertTrue(boardToast.waitForExistence(timeout: 2))
        XCTAssertTrue(boardToast.label.contains("黑方思考中"))
        app.buttons["board_timer_back_button"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.firstMatch.buttons["取消"].tap()

        XCTAssertTrue(app.buttons["board_timer_resume_button"].exists)
        XCTAssertTrue(app.buttons["board_timer_thinking_indicator_player_2"].exists)
        app.buttons["board_timer_stop_button"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        let confirmEndButton = app.alerts.firstMatch.buttons["确认"]
        if confirmEndButton.waitForExistence(timeout: 1) {
            confirmEndButton.tap()
        } else {
            let legacyConfirmEndButton = app.alerts.firstMatch.buttons["确定"]
            XCTAssertTrue(legacyConfirmEndButton.waitForExistence(timeout: 1))
            legacyConfirmEndButton.tap()
        }

        XCTAssertTrue(app.descendants(matching: .any)["board_timer_game_over_result"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["手动结束"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "获胜")).firstMatch.exists)

        app.buttons["board_timer_restart_button"].tap()
        XCTAssertTrue(firstIndicator.waitForExistence(timeout: 3))
        XCTAssertEqual(firstIndicator.frame.midX, initialIndicatorFrame.midX, accuracy: 2)
    }

    func testFullscreenBarrageRotateButtonWorks() {
        let app = launchChineseApp(arguments: ["-UITestOpenTools"])
        defer { app.terminate() }

        XCTAssertTrue(openToolsList(in: app))
        let barrage = app.descendants(matching: .any)["tool_card_fullscreen_barrage"]
        XCTAssertTrue(scrollUntilExists(barrage, in: app))
        barrage.tap()

        let message = app.textFields["barrage_message_field"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.tap()
        message.typeText("旋转测试")
        app.buttons["barrage_start_static"].tap()

        let runningBarrage = app.descendants(matching: .any)["barrage_running"].firstMatch
        XCTAssertTrue(runningBarrage.waitForExistence(timeout: 5))
        let rotateButton = app.buttons["旋转屏幕"]
        XCTAssertTrue(rotateButton.waitForExistence(timeout: 5))
        let initialWindowFrame = app.windows.firstMatch.frame
        rotateButton.tap()

        let rotationDeadline = Date().addingTimeInterval(3)
        var rotationApplied = false
        repeat {
            let usedContentFallback = (runningBarrage.value as? String) == "content_rotated"
            let currentWindowFrame = app.windows.firstMatch.frame
            let sceneRotated = (initialWindowFrame.width > initialWindowFrame.height)
                != (currentWindowFrame.width > currentWindowFrame.height)
            rotationApplied = usedContentFallback || sceneRotated
            if !rotationApplied {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        } while !rotationApplied && Date() < rotationDeadline

        XCTAssertTrue(rotationApplied, "Rotate button should rotate either the scene or the fallback display surface")
        XCTAssertTrue(runningBarrage.exists)
    }

    func testCountdownChipsRespondAcrossTheirVisibleArea() {
        let app = launchChineseApp(arguments: ["-UITestOpenTimer"])
        defer { app.terminate() }

        let countdown = app.descendants(matching: .any)["timer_dest_timeout"]
        XCTAssertTrue(scrollUntilExists(countdown, in: app))
        countdown.tap()

        let sportsMode = app.buttons["countdown_mode_sports"]
        XCTAssertTrue(sportsMode.waitForExistence(timeout: 5))
        sportsMode.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(sportsMode.isSelected)

        let badminton = app.buttons["countdown_sport_badminton"]
        XCTAssertTrue(badminton.waitForExistence(timeout: 3))
        badminton.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(badminton.isSelected)

        let betweenGames = app.buttons["countdown_preset_badminton_between"]
        XCTAssertTrue(betweenGames.waitForExistence(timeout: 3))
        betweenGames.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(betweenGames.isSelected)

        let quickMode = app.buttons["countdown_mode_quick"]
        quickMode.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(quickMode.isSelected)

        let fiveMinutes = app.buttons["countdown_preset_quick_300"]
        XCTAssertTrue(fiveMinutes.waitForExistence(timeout: 3))
        fiveMinutes.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(fiveMinutes.isSelected)
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
                "-UITestSkipLegalConsent",
                "-UITestSkipScoreboardUsageHints",
                "-UITestRecordFixtures", "-UITestRecordDetail", project
            ]
            app.launch()
            XCTAssertTrue(app.buttons["再来一场"].waitForExistence(timeout: 5), "Missing replay for \(project)")
            XCTAssertTrue(app.buttons["复盘"].exists || app.staticTexts["复盘"].exists, "Missing recap for \(project)")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "fixture")).firstMatch.exists, "Internal fixture text leaked for \(project)")
            let hasTrend = app.staticTexts["比分趋势"].exists
            XCTAssertEqual(hasTrend, trendProjects.contains(project), "Trend policy mismatch for \(project)")
            app.terminate()
        }
    }

    private func clearRecordFixtures() {
        let cleanup = XCUIApplication()
        cleanup.launchArguments += [
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints",
            "-UITestClearRecordFixtures"
        ]
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
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints"
        ]
        if let appearance {
            app.launchArguments += ["-jifen-v2.appAppearanceMode", appearance]
        }
        app.launchArguments += arguments
        app.launch()
        XCUIDevice.shared.orientation = .portrait
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

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func addScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissEnglishWatchGuideIfNeeded(in app: XCUIApplication) {
        for label in ["Got It", "Got it"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 0.5), button.isHittable {
                button.tap()
                return
            }
        }
    }

    private func assertEnglishLocalization(
        in root: XCUIElement,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visibleElements = [XCUIElement.ElementType.staticText, .button, .navigationBar]
            .flatMap { root.descendants(matching: $0).allElementsBoundByIndex }
            .filter { element in
                element.exists
                    && !element.frame.isEmpty
                    && element.frame.intersects(root.frame)
            }

        let labels = Set(visibleElements.map(\.label).filter { !$0.isEmpty })
        let chinese = labels.filter {
            $0.range(of: #"[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]"#, options: .regularExpression) != nil
        }.sorted()
        let rawKeys = labels.filter {
            $0.range(of: #"^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$"#, options: .regularExpression) != nil
        }.sorted()

        XCTAssertEqual(chinese, [], "Chinese leaked into English UI at \(context): \(chinese)", file: file, line: line)
        XCTAssertEqual(rawKeys, [], "Raw localization keys leaked at \(context): \(rawKeys)", file: file, line: line)
    }

    private func assertRawLocalizationKeysAreAbsent(
        _ keys: [String],
        in app: XCUIApplication,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let leaked = keys.filter { key in
            app.staticTexts[key].exists || app.buttons[key].exists || app.navigationBars[key].exists
        }
        XCTAssertEqual(leaked, [], "Raw localization keys leaked at \(context): \(leaked)", file: file, line: line)
    }

    private func runPlayAllSetup(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent",
            "-UITestSkipScoreboardUsageHints",
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
        let tabBarScoreButton = app.tabBars.buttons["计分"]
        let scoreTab = tabBarScoreButton.exists
            ? tabBarScoreButton
            : app.buttons.matching(identifier: "main_tab_2").firstMatch
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
        // Recapture the accessibility tree after every navigation. Keeping a bound
        // XCUIElement from the previous page can become ambiguous when both the
        // navigation bar and a scoreboard expose a Back button.
        for _ in 0..<30 {
            var tappedOne = false
            for element in candidateElements(in: app) {
                guard isSafeToTap(element: element) else { continue }
                guard element.exists, element.isHittable else { continue }

                let fingerprint = fingerprint(for: element)
                guard !seenFingerprints.contains(fingerprint) else { continue }

                seenFingerprints.insert(fingerprint)
                let label = debugLabel(for: element)
                var didTap = false

                XCTContext.runActivity(named: "Tap \(label)") { _ in
                    element.tap()
                    didTap = true
                }
                guard didTap else { continue }
                tapped += 1
                tappedOne = true

                dismissSystemAlertIfNeeded()
                ensureReturnedToTabRoot(app)
                break
            }
            if !tappedOne { break }
        }

        return tapped
    }

    private func candidateElements(in app: XCUIApplication) -> [XCUIElement] {
        // Exclude navigation/scoreboard Back controls in the query itself. During a
        // transition XCTest can otherwise re-resolve one bound element by label and
        // find both Back buttons before our Swift-side safety filter can run.
        let nonBackButtons = app.buttons.matching(NSPredicate(
            format: "NOT (label CONTAINS[c] %@ OR identifier CONTAINS[c] %@)",
            "back",
            "back"
        )).allElementsBoundByIndex
        // SwiftUI list rows and segmented options already surface their actionable
        // descendants as buttons. Adding cells here duplicates those controls and can
        // re-resolve a stale cell query as either of two nested Back buttons.
        return nonBackButtons + app.switches.allElementsBoundByIndex
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
        "\(element.elementType.rawValue)|\(element.identifier)|\(element.label)"
    }

    @discardableResult
    private func performScroll(in app: XCUIApplication, up: Bool) -> Bool {
        // The accessibility tree can retain an off-screen ScrollView from a
        // dismissed page. Swiping the application lets XCTest hit-test the visible
        // scroll container instead of failing on that stale zero-height element.
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
        return ""
    }

    private func navigateBackIfNeeded(from app: XCUIApplication) {
        for _ in 0..<3 {
            if app.tabBars.firstMatch.exists { return }

            let navBack = app.buttons.matching(identifier: "BackButton").firstMatch
            let scoreboardBack = app.buttons.matching(identifier: "scoreboard_back_button").firstMatch
            let done = app.buttons.matching(identifier: "Done").firstMatch
            if navBack.exists, navBack.isHittable {
                navBack.tap()
            } else if scoreboardBack.exists {
                // Scoreboards lock to landscape. Querying hittability while the
                // crawler has just requested portrait produces an invalid frame.
                XCUIDevice.shared.orientation = .landscapeLeft
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                scoreboardBack.tap()
            } else if done.exists, done.isHittable {
                done.tap()
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

        let overlayButtons = ["xmark", "Close", "Done"]
        for title in overlayButtons {
            let button = app.buttons[title]
            if isVisiblyTapCandidate(button, in: app), safeTap(button, in: app) {
                return true
            }
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
