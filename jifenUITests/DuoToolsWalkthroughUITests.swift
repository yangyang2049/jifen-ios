import CoreGraphics
import Foundation
import XCTest

/// Walks the real tools list and its production destinations. The host owns
/// folding, PNG capture, video recording, and deletion of the capture-file ACK.
final class DuoToolsWalkthroughUITests: XCTestCase {
    private var application: XCUIApplication?
    private let captureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("duo-capture.json")

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard (environment["DUO_HOST_CAPTURE"] ?? environment["TEST_RUNNER_DUO_HOST_CAPTURE"]) == "1" else {
            throw XCTSkip("Requires DUO_HOST_CAPTURE=1 and a host capture/ACK loop")
        }
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        application?.terminate()
        application = nil
    }

    func testWalkDuoTools01RandomTeamsStandingsAndAA() throws {
        let app = try launchTools()
        try checkpoint("tools_01_catalog", app)

        try openTool("random_team", app)
        try requireIdentifier("random_team_players_4", app)
        try checkpoint("tools_02_random_player_options", app)
        try tapIdentifier("random_team_players_4", app)
        try requireIdentifier("random_team_multitouch_surface", app)
        try checkpoint("tools_03_random_four_player_surface", app)
        try tapButton("一键分组", app)
        try require(app.staticTexts["分组完成！"].firstMatch, "four-player grouping result")
        try require(app.buttons["再来一次"].firstMatch, "grouping retry action")
        try checkpoint("tools_04_random_four_player_result", app)

        try tapButton("重选人数", app)
        try tapIdentifier("random_team_players_6", app)
        try require(app.buttons["3队 · 2+2+2"].firstMatch, "six-player three-team option")
        try checkpoint("tools_05_random_team_count_options", app)
        try tapButton("3队 · 2+2+2", app)
        try tapButton("一键分组", app)
        try require(app.staticTexts["分组完成！"].firstMatch, "six-player grouping result")
        try require(app.staticTexts["C"].firstMatch, "third team in grouping result")
        try checkpoint("tools_06_random_six_player_three_team_result", app)
        try navigationBack(app)
        try requireTools(app)

        try openTool("points_table", app)
        try require(app.navigationBars["积分榜"].firstMatch, "standings list")
        try checkpoint("tools_07_standings_list", app)
        try tapIdentifier("points_table_add", app)
        try require(app.staticTexts["新积分榜"].firstMatch, "new local standings detail")
        try require(app.buttons["操作"].firstMatch, "standings detail menu")
        try checkpoint("tools_08_standings_created_detail", app)
        try tapButton("操作", app)
        try require(app.buttons["编辑"].firstMatch, "standings edit menu action")
        try checkpoint("tools_09_standings_operations", app)
        try tapButton("编辑", app)
        let name = try require(app.textFields["名称"].firstMatch, "standings name editor")
        try require(app.textFields["队伍名称"].firstMatch, "standings team editor")
        try checkpoint("tools_10_standings_edit_form", app)

        let recordName = "Duo Review " + String(Int(Date().timeIntervalSince1970))
        try replaceText(name, with: recordName, name: "standings name", app)
        let teamName = app.textFields["队伍名称"].firstMatch
        try replaceText(teamName, with: "Team A", name: "first standings team", app)
        // Edit rows are intentionally kept in insertion order by the product.
        // The first unlabelled numeric field is the first team's win count.
        let firstWin = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@ OR label == %@", "0", "0")
        ).firstMatch
        try require(firstWin, "standings first-team win editor")
        try replaceText(firstWin, with: "2", name: "first-team wins", app)
        try checkpoint("tools_11_standings_local_name_team_and_win_edits", app)
        try tapIdentifier("points_table_finish_input", app)
        try checkpoint("tools_11b_standings_keyboard_dismissed", app)
        try tapButton("添加队伍", app)
        try waitForState("four standings team editors") {
            app.textFields.matching(identifier: "队伍名称").count == 4
        }
        try reveal(app.textFields.matching(identifier: "队伍名称").element(boundBy: 3), name: "fourth standings team editor", app)
        try checkpoint("tools_12_standings_four_team_edit_form", app)
        try tapButton("完成", app)
        try require(app.staticTexts[recordName].firstMatch, "saved standings name")
        try require(app.staticTexts["Team A"].firstMatch, "saved first-team name")
        try require(app.staticTexts["丁队"].firstMatch, "new fourth team")
        try require(app.staticTexts["6"].firstMatch, "two wins produce six standings points")
        try checkpoint("tools_13_standings_saved_detail", app)
        try navigationBack(app)
        let savedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", recordName)).firstMatch
        try tap(savedRow, name: "new local standings list row", app)
        try require(app.staticTexts["Team A"].firstMatch, "reopened local standings detail")
        try checkpoint("tools_14_standings_reopened_detail", app)
        // Retain this explicitly named local sample for manual inspection.
        try navigationBack(app)
        try navigationBack(app)
        try requireTools(app)

        try openTool("aa_calculator", app)
        let amount = try require(app.textFields["请输入金额"].firstMatch, "AA amount input")
        try checkpoint("tools_15_aa_empty_form", app)
        try replaceText(amount, with: "120", name: "AA total amount", app)
        try checkpoint("tools_16_aa_amount_keyboard", app)
        try tapIdentifier("aa_finish_input", app)
        try checkpoint("tools_16b_aa_keyboard_dismissed", app)
        try tapButton("计算", app)
        try require(app.staticTexts["每人应付"].firstMatch, "AA result heading")
        let twoPersonResult = try require(app.staticTexts["¥60.00"].firstMatch, "AA 120 divided by two result")
        try reveal(twoPersonResult, name: "AA two-person result card", app)
        try checkpoint("tools_17_aa_two_person_result", app)
        try tapButton("¥300", app)
        try incrementAAParticipants(from: 2, app)
        try incrementAAParticipants(from: 3, app)
        try checkpoint("tools_18_aa_quick_amount_four_participants", app)
        try tapButton("计算", app)
        let fourPersonResult = try require(app.staticTexts["¥75.00"].firstMatch, "AA 300 divided by four result")
        try reveal(fourPersonResult, name: "AA four-person result card", app)
        try checkpoint("tools_19_aa_four_person_result", app)
    }

    func testWalkDuoTools02BarrageDiceAndChallenge() throws {
        let app = try launchTools()
        try openTool("fullscreen_barrage", app)
        let message = try requireIdentifier("barrage_message_field", app)
        try checkpoint("tools_30_barrage_settings", app)
        try replaceText(message, with: "HELLO DUO! ENJOY THE MATCH!", name: "barrage message", app)
        try checkpoint("tools_31_barrage_message_keyboard", app)
        try tapIdentifier("barrage_finish_input", app)
        try tapIdentifier("barrage_start_static", app)
        try requireIdentifier("barrage_running", app)
        try require(app.staticTexts["HELLO DUO! ENJOY THE MATCH!"].firstMatch, "static barrage text")
        try checkpoint("tools_32_barrage_static_running", app)
        try tapButton("编辑", app)
        let inlineMessage = try require(app.textFields["输入要展示的内容"].firstMatch, "running barrage editor")
        try require(app.buttons["滚动"].firstMatch, "running barrage scroll mode")
        try checkpoint("tools_33_barrage_running_editor", app)
        try replaceText(inlineMessage, with: "ONE MORE MATCH!", name: "running barrage message", app)
        try checkpoint("tools_34_barrage_inline_edit_keyboard", app)
        try tapIdentifier("barrage_finish_input", app)
        try tapButton("滚动", app)
        try tapButton("完成", app)
        try require(app.buttons["编辑"].firstMatch, "running barrage edit control")
        try waitForState("barrage editor collapsed") { !inlineMessage.exists }
        let windowFrame = app.windows.firstMatch.frame
        for label in ["返回", "编辑", "旋转屏幕"] {
            let control = try require(app.buttons[label].firstMatch, "running barrage " + label)
            try waitForState("barrage control stays inside window: " + label) {
                control.isHittable && windowFrame.insetBy(dx: -1, dy: -1).contains(control.frame)
            }
        }
        try checkpoint("tools_35_barrage_scroll_running", app)
        try tapButton("返回", app)
        try requireIdentifier("barrage_settings", app)
        try tapButton("返回", app)
        try requireTools(app)

        try openTool("dice", app)
        let diceWebView = try require(app.webViews.firstMatch, "dice HTML renderer", timeout: 20)
        try waitForState("dice renderer finished loading", timeout: 20) {
            diceWebView.isHittable && app.activityIndicators.count == 0
        }
        let oneDie = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "1颗")).firstMatch
        try require(oneDie, "one-die count selector")
        try checkpoint("tools_36_dice_one_die_page", app)
        try tap(oneDie, name: "dice count selector", app)
        try require(app.buttons["3颗"].firstMatch, "three-dice option")
        try checkpoint("tools_37_dice_count_options", app)
        try tapButton("3颗", app)
        try require(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "3颗")).firstMatch, "selected three-dice count")
        try checkpoint("tools_38_dice_three_die_page", app)
        diceWebView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let diceResult = diceWebView.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[1-6] \\+ [1-6] \\+ [1-6] = [0-9]{1,2}")
        ).firstMatch
        try require(diceResult, "three-dice arithmetic result", timeout: 12)
        try validateDiceSum(diceResult.label)
        try checkpoint("tools_39_dice_three_die_result", app)
        try tapIdentifier("BackButton", app)
        try requireTools(app)

        try openTool("ten_second", app)
        try require(app.staticTexts["00.00"].firstMatch, "challenge initial timer")
        try checkpoint("tools_40_challenge_ready", app)
        try tapButton("开始", app)
        try require(app.buttons["停止"].firstMatch, "running challenge stop action")
        try checkpoint("tools_41_challenge_running", app)
        // A host ACK must arrive before the product's 59.99-second automatic
        // stop if this checkpoint is to demonstrate a manual stop.
        guard app.buttons["停止"].firstMatch.exists else {
            throw WalkthroughFailure.invalidState("Challenge auto-stopped before the host ACK; manual-stop coverage was not reached")
        }
        try tapButton("停止", app)
        try require(app.staticTexts["误差"].firstMatch, "challenge stopped result")
        try require(app.buttons["开始"].firstMatch, "challenge retry action")
        try checkpoint("tools_42_challenge_manual_stop_result", app)
    }

    func testWalkDuoTools03CoinWhistleCardsAndClock() throws {
        let app = try launchTools()
        try openTool("flip_coin", app)
        try requireIdentifier("BackButton", app)
        try require(app.webViews.firstMatch, "coin renderer", timeout: 20)
        try checkpoint("tools_50_coin_ready", app)
        // FlipCoinView attaches the toss gesture to its centred 336pt coin
        // and the surrounding background; it has no separate toss button.
        app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        try require(app.staticTexts["总计"].firstMatch, "coin toss result statistics")
        try require(app.staticTexts["正面"].firstMatch, "coin heads count")
        try require(app.staticTexts["反面"].firstMatch, "coin tails count")
        try checkpoint("tools_51_coin_first_result", app)
        app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        try require(app.staticTexts["2"].firstMatch, "coin total after two tosses")
        try checkpoint("tools_52_coin_second_result", app)
        try tapIdentifier("BackButton", app)
        try requireTools(app)

        try openTool("whistle", app)
        let shortWhistle = try require(app.buttons["哨声"].firstMatch, "short whistle control")
        let buzzer = try require(app.buttons["蜂鸣"].firstMatch, "buzzer control")
        try checkpoint("tools_53_whistle_and_buzzer_options", app)
        try tap(shortWhistle, name: "short whistle", app)
        try waitForState("short whistle completed") { shortWhistle.isEnabled && buzzer.isEnabled }
        try tap(buzzer, name: "buzzer", app)
        try waitForState("buzzer completed") { shortWhistle.isEnabled && buzzer.isEnabled }
        // These are momentary controls (0.2s and 1s), with no result subpage.
        // Video records their activation; this stable checkpoint shows recovery.
        try checkpoint("tools_54_whistle_controls_after_playback", app)
        try tapIdentifier("BackButton", app)
        try requireTools(app)

        try openTool("red_yellow_card", app)
        try require(app.staticTexts["左右滑动切换"].firstMatch, "card swipe hint")
        let page = try require(app.pageIndicators.firstMatch, "red/yellow card page indicator")
        let yellowPage = paginationState(page)
        guard !yellowPage.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WalkthroughFailure.invalidState("Card page indicator exposes no selection value")
        }
        try checkpoint("tools_55_yellow_card", app)
        app.windows.firstMatch.swipeLeft()
        try waitForState("red card selected") { page.exists && self.paginationState(page) != yellowPage }
        try checkpoint("tools_56_red_card", app)
        app.windows.firstMatch.swipeRight()
        try waitForState("yellow card selected again") { self.paginationState(page) == yellowPage }
        try checkpoint("tools_57_yellow_card_return", app)
        try tapIdentifier("BackButton", app)
        try requireTools(app)

        try openTool("time", app)
        try require(app.buttons["返回"].firstMatch, "clock back control")
        let clock = app.descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES %@", ".*[0-9]{1,2}:[0-9]{2}:[0-9]{2}.*")
        ).firstMatch
        try require(clock, "accessible clock time with seconds")
        try checkpoint("tools_58_flip_clock", app)
        let firstTime = clock.label
        try waitForState("flip clock time advances", timeout: 6) { clock.exists && clock.label != firstTime }
        try checkpoint("tools_59_flip_clock_time_advanced", app)
        // Rotation is the only other clock action. Let the current system
        // orientation response stand; this walkthrough never taps that action.
        try tapButton("返回", app)
        try requireTools(app)
        try checkpoint("tools_60_catalog_after_local_tools", app)
    }

    private func launchTools() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints",
            "-UITestFakeSession", "-UITestSportsVoiceMissing", "-UITestOpenTools",
            "-national_day_2026_10_autopopup_count", "99",
            "-national_day_2026_last_shown_at", String(Date().timeIntervalSince1970)
        ]
        application = app
        app.launch()
        // Home pushes its real tools-list route; no tool replaces the app root.
        try require(app.navigationBars["工具"].firstMatch, "real tools list", timeout: 20)
        return app
    }

    private func requireTools(_ app: XCUIApplication) throws {
        try require(app.navigationBars["工具"].firstMatch, "returned tools list")
    }

    private func openTool(_ identifier: String, _ app: XCUIApplication) throws {
        try requireTools(app)
        try tapIdentifier("tool_card_" + identifier, app)
    }

    @discardableResult
    private func require(_ element: XCUIElement, _ name: String, timeout: TimeInterval = 8) throws -> XCUIElement {
        guard element.waitForExistence(timeout: timeout) else { throw WalkthroughFailure.missing(name) }
        return element
    }

    @discardableResult
    private func requireIdentifier(_ identifier: String, _ app: XCUIApplication) throws -> XCUIElement {
        try require(app.descendants(matching: .any)[identifier].firstMatch, identifier)
    }

    private func tapIdentifier(_ identifier: String, _ app: XCUIApplication) throws {
        try tap(app.descendants(matching: .any)[identifier].firstMatch, name: identifier, app)
    }

    private func tapButton(_ label: String, _ app: XCUIApplication) throws {
        try tap(app.buttons[label].firstMatch, name: label, app)
    }

    private func tap(_ element: XCUIElement, name: String, _ app: XCUIApplication) throws {
        try reveal(element, name: name, app)
        guard element.isEnabled else { throw WalkthroughFailure.disabled(name) }
        element.tap()
    }

    private func reveal(_ element: XCUIElement, name: String, _ app: XCUIApplication) throws {
        if element.waitForExistence(timeout: 2) && element.isHittable { return }
        // Tool cards live in a LazyVGrid; querying before scrolling is allowed
        // to return no element, and must not prevent reaching a lower card.
        for up in [true, false] {
            for _ in 0..<8 {
                let surface = app.scrollViews.allElementsBoundByIndex.first { $0.exists && $0.isHittable } ?? app.windows.firstMatch
                if up { surface.swipeUp() } else { surface.swipeDown() }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                if element.exists && element.isHittable { return }
            }
        }
        throw WalkthroughFailure.missing("hittable " + name)
    }

    private func replaceText(_ field: XCUIElement, with text: String, name: String, _ app: XCUIApplication) throws {
        try reveal(field, name: name, app)
        field.tap()
        let previousValue = field.value as? String ?? ""
        if !previousValue.isEmpty {
            field.press(forDuration: 1.1)
            let selectAll = app.menuItems["全选"].firstMatch
            let selectAllButton = app.buttons["全选"].firstMatch
            if selectAll.waitForExistence(timeout: 1), selectAll.isHittable { selectAll.tap() }
            else if selectAllButton.exists, selectAllButton.isHittable { selectAllButton.tap() }
            else {
                // Select the field's single paragraph when the current edit
                // menu offers word actions instead of Select All.
                field.tap(withNumberOfTaps: 4, numberOfTouches: 1)
            }
        }
        field.typeText(text)
        try waitForState("edited " + name + " (actual: " + String(describing: field.value) + ")") {
            (field.value as? String) == text
        }
    }

    private func tapUniqueButton(in container: XCUIElement, name: String, matching: (XCUIElement) -> Bool) throws {
        let buttons = container.buttons.allElementsBoundByIndex.filter {
            $0.exists && $0.isHittable && $0.isEnabled && matching($0)
        }
        guard buttons.count == 1, let button = buttons.first else {
            throw WalkthroughFailure.invalidState("Expected one " + name + "; found " + String(buttons.count))
        }
        button.tap()
    }

    private func incrementAAParticipants(from count: Int, _ app: XCUIApplication) throws {
        let value = app.staticTexts[String(count)].firstMatch
        try reveal(value, name: "AA participant count " + String(count), app)
        try tapIdentifier("aa_participants_increase", app)
        try require(app.staticTexts[String(count + 1)].firstMatch, "incremented AA participant count")
    }

    private func navigationBack(_ app: XCUIApplication) throws {
        let systemBack = app.buttons["BackButton"].firstMatch
        if systemBack.exists, systemBack.isHittable {
            systemBack.tap()
            return
        }
        guard let bar = app.navigationBars.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable }),
              let back = bar.buttons.allElementsBoundByIndex.first(where: {
                  $0.exists && $0.isHittable && $0.frame.midX < bar.frame.midX
              }) else { throw WalkthroughFailure.missing("navigation back button") }
        back.tap()
    }

    private func paginationState(_ page: XCUIElement) -> String {
        guard page.exists else { return "" }
        return page.label + " " + (page.value as? String ?? "")
    }

    private func validateDiceSum(_ result: String) throws {
        let parts = result.components(separatedBy: " = ")
        guard parts.count == 2, let expected = Int(parts[1]) else {
            throw WalkthroughFailure.invalidState("Dice result has no readable sum: " + result)
        }
        let terms = parts[0].components(separatedBy: " + ").compactMap(Int.init)
        guard terms.count == 3, terms.allSatisfy({ (1...6).contains($0) }), terms.reduce(0, +) == expected else {
            throw WalkthroughFailure.invalidState("Dice result is inconsistent: " + result)
        }
    }

    private func waitForState(_ name: String, timeout: TimeInterval = 8, condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        throw WalkthroughFailure.invalidState("Timed out waiting for " + name)
    }

    private struct CaptureRequest: Encodable {
        let name: String
        let width: Double
        let height: Double
        let hierarchy: String
    }

    private func checkpoint(_ name: String, _ app: XCUIApplication) throws {
        if FileManager.default.fileExists(atPath: captureURL.path) {
            try waitForHostACK("previous capture before " + name)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let request = CaptureRequest(
            name: name, width: Double(app.frame.width), height: Double(app.frame.height),
            hierarchy: app.debugDescription
        )
        try JSONEncoder().encode(request).write(to: captureURL, options: .atomic)
        print("DUO_CAPTURE_READY \(name) \(captureURL.path)")
        try waitForHostACK(name)
        print("DUO_CAPTURE_ACK \(name)")
    }

    private func waitForHostACK(_ name: String) throws {
        let deadline = Date().addingTimeInterval(90)
        while FileManager.default.fileExists(atPath: captureURL.path) {
            guard Date() < deadline else { throw WalkthroughFailure.captureTimeout(name) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private enum WalkthroughFailure: LocalizedError {
        case missing(String)
        case disabled(String)
        case invalidState(String)
        case captureTimeout(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name): return "Tools walkthrough could not find " + name
            case .disabled(let name): return "Tools walkthrough control is disabled: " + name
            case .invalidState(let reason): return "Tools walkthrough did not reach the expected state: " + reason
            case .captureTimeout(let name): return "Host did not remove duo-capture.json within 90 seconds: " + name
            }
        }
    }
}
