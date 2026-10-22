import Foundation
import XCTest

/// Real timer-tab navigation with a host-owned pose, recording and PNG loop.
/// Cube timing needs two independent held touches, so only its actual hint and
/// preparation page are covered; its running/stopped states remain uncovered.
final class DuoTimerWalkthroughUITests: XCTestCase {
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

    func testWalkDuoTimers01GoAndXiangqi() throws {
        let app = try launchTimers()
        try checkpoint("timers_01_board_catalog", app)
        try walkBoardTimer("go", alternateMode: "包干", runningMode: "读秒", app)
        try walkBoardTimer("xiangqi", alternateMode: "包干", runningMode: "加秒", app)
    }

    func testWalkDuoTimers02ChessAndCheckers() throws {
        let app = try launchTimers()
        try walkBoardTimer("chess", alternateMode: "延迟", runningMode: "延迟", app)
        try walkBoardTimer("checkers", alternateMode: "包干", runningMode: "加秒", app)
    }

    func testWalkDuoTimers03StopwatchCountdownAndCubePreparation() throws {
        let app = try launchTimers()
        try openTimer("stopwatch", app)
        try require(app.navigationBars["秒表"].firstMatch, "stopwatch page")
        // This dedicated simulator may retain a previous walkthrough's local
        // state. Normalise it through the real pause/reset controls only.
        let pause = app.buttons["pause.fill"].firstMatch
        if pause.exists { try tap(pause, name: "pause existing stopwatch", app) }
        try require(app.buttons["play.fill"].firstMatch, "stopwatch start control")
        let reset = try require(app.buttons["arrow.counterclockwise"].firstMatch, "stopwatch reset control")
        if reset.isEnabled { try tap(reset, name: "reset local stopwatch", app) }
        try require(app.staticTexts["00:00.00"].firstMatch, "empty stopwatch")
        try checkpoint("timers_stopwatch_01_ready", app)
        try tapButton("play.fill", app)
        try require(app.buttons["flag"].firstMatch, "running stopwatch lap control")
        let stopwatch = try stopwatchClock(app)
        try waitForChange(stopwatch, name: "running stopwatch")
        try checkpoint("timers_stopwatch_02_running", app)
        try tapButton("flag", app)
        try require(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "\\+[0-9]{2}:[0-9]{2}\\.[0-9]{2}")
        ).firstMatch, "first stopwatch split")
        try checkpoint("timers_stopwatch_03_first_split", app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        try tapButton("flag", app)
        try require(app.staticTexts["2"].firstMatch, "second stopwatch lap number")
        try checkpoint("timers_stopwatch_04_two_splits", app)
        try tapButton("pause.fill", app)
        try require(app.buttons["play.fill"].firstMatch, "stopped stopwatch resume control")
        try requireStable(stopwatch, name: "stopped stopwatch")
        try checkpoint("timers_stopwatch_05_stopped", app)
        try navigationBack(app)
        try requireTimers(app)
        try checkpoint("timers_stopwatch_06_catalog_summary", app)

        try openTimer("timeout", app)
        try requireIdentifier("countdown_main_button", app)
        let countdownReset = try requireIdentifier("countdown_reset_button", app)
        if countdownReset.isEnabled { try tap(countdownReset, name: "reset local countdown", app) }
        try checkpoint("timers_countdown_01_idle", app)
        // The original wide-phone layout hides all presets. Missing this real
        // entry is a layout failure, never a reason to rotate the device.
        let quickMode = app.buttons["countdown_mode_quick"].firstMatch
        guard quickMode.waitForExistence(timeout: 5) else {
            throw WalkthroughFailure.invalidState("Countdown mode/custom controls are hidden in this available window; custom-duration coverage was not reached")
        }
        try tap(quickMode, name: "quick countdown mode", app)
        try tapIdentifier("countdown_preset_quick_300", app)
        try tapIdentifier("countdown_preset_custom", app)
        try require(app.staticTexts["自定义"].firstMatch, "custom countdown editor")
        try requireIdentifier("modal_close_button", app)
        try waitForState("custom editor reflects the selected five-minute preset") {
            app.staticTexts["countdown_custom_minutes_value"].firstMatch.label == "5"
                && app.staticTexts["countdown_custom_seconds_value"].firstMatch.label == "0"
        }
        try checkpoint("timers_countdown_02_custom_editor", app)
        try increaseCustomDurationRow("分钟", app)
        try increaseCustomDurationRow("秒", app)
        try require(app.staticTexts["6"].firstMatch, "custom six-minute value")
        try require(app.staticTexts["1"].firstMatch, "custom one-second value")
        try checkpoint("timers_countdown_03_custom_six_minutes_one_second", app)
        try tapIdentifier("modal_close_button", app)
        let countdown = try countdownClock(app)
        try waitForState("custom countdown is 06:01") { countdown.label == "06:01" }
        try checkpoint("timers_countdown_04_custom_ready", app)
        try tapIdentifier("countdown_main_button", app)
        try dismissCountdownNotificationPermissionIfPresented()
        try waitForChange(countdown, name: "running custom countdown")
        try checkpoint("timers_countdown_05_running", app)
        try tapIdentifier("countdown_main_button", app)
        try requireStable(countdown, name: "paused custom countdown")
        try checkpoint("timers_countdown_06_paused", app)
        try tapIdentifier("countdown_main_button", app)
        try waitForChange(countdown, name: "resumed custom countdown")
        try checkpoint("timers_countdown_07_resumed", app)
        try tapIdentifier("countdown_reset_button", app)
        try waitForState("reset custom countdown is 06:01") { countdown.label == "06:01" }
        try checkpoint("timers_countdown_08_reset", app)

        // Relaunch to the actual timer tab instead of guessing the unlabelled
        // countdown toolbar's back/rotate buttons. This does not replace a root
        // with a timer destination; the cube card is clicked below.
        let cubeApp = try launchTimers()
        try openTimer("cube", cubeApp)
        try require(cubeApp.staticTexts["双手放在屏幕上准备"].firstMatch, "cube preparation hint")
        try require(cubeApp.staticTexts["松开双手开始计时"].firstMatch, "cube release-to-start instruction")
        try checkpoint("timers_cube_01_instructions", cubeApp)
        try tapButton("确认", cubeApp)
        try require(cubeApp.staticTexts["0.00"].firstMatch, "cube preparation clock")
        try waitForState("cube hint dismissed") { !cubeApp.buttons["确认"].firstMatch.exists }
        try checkpoint("timers_cube_02_preparation", cubeApp)
        let limitation = "Cube running/stopped states are NOT covered: CubeTimerView requires independent left/right holds for at least 0.5 seconds and exposes no accessible hand-surface targets. No simulated single-touch substitute was used."
        print("DUO_COVERAGE_LIMITATION " + limitation)
        let attachment = XCTAttachment(string: limitation)
        attachment.name = "Cube timing coverage limitation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func walkBoardTimer(_ identifier: String, alternateMode: String, runningMode: String, _ app: XCUIApplication) throws {
        try openTimer(identifier, app)
        try requireIdentifier("modal_close_button", app)
        try require(app.staticTexts["主时间"].firstMatch, "board timer setup main-time fields")
        try checkpoint("timers_" + identifier + "_01_setup_default", app)
        try selectBoardMode(alternateMode, app)
        try checkpoint("timers_" + identifier + "_02_setup_alternate", app)
        if runningMode != alternateMode { try selectBoardMode(runningMode, app) }
        try tapButton("开始", app)
        try requireIdentifier("board_timer_start_button", app)
        let player1 = try requireIdentifier("board_timer_player_1", app)
        let player2 = try requireIdentifier("board_timer_player_2", app)
        try requireIdentifier("board_timer_first_indicator_player_1", app)
        try checkpoint("timers_" + identifier + "_03_ready", app)
        let player1WasLeft = player1.frame.midX < player2.frame.midX
        try tapIdentifier("board_timer_swap_button", app)
        try waitForState("board player positions swapped") {
            player1.exists && player2.exists && (player1.frame.midX < player2.frame.midX) != player1WasLeft
        }
        try checkpoint("timers_" + identifier + "_04_positions_swapped", app)
        try tapIdentifier("board_timer_start_button", app)
        try requireIdentifier("board_timer_pause_button", app)
        try requireIdentifier("board_timer_tap_hint_player_1", app)
        let firstClock = try boardClock(player: 1, app)
        try waitForChange(firstClock, name: identifier + " player one clock", timeout: 12)
        try checkpoint("timers_" + identifier + "_05_player_one_running", app)
        // The current player's source-labelled hint performs the same move as
        // the containing player panel, without guessing a hit-test coordinate.
        try tapIdentifier("board_timer_tap_hint_player_1", app)
        try requireIdentifier("board_timer_tap_hint_player_2", app)
        let secondClock = try boardClock(player: 2, app)
        try waitForChange(secondClock, name: identifier + " player two clock", timeout: 12)
        try checkpoint("timers_" + identifier + "_06_player_two_running", app)
        try tapIdentifier("board_timer_pause_button", app)
        try requireIdentifier("board_timer_resume_button", app)
        try requireIdentifier("board_timer_thinking_indicator_player_2", app)
        try requireStable(secondClock, name: identifier + " paused player two clock")
        try checkpoint("timers_" + identifier + "_07_paused_controls", app)
        try tapIdentifier("board_timer_back_button", app)
        let exitAlert = try require(app.alerts["确认退出"].firstMatch, "board timer exit confirmation")
        try checkpoint("timers_" + identifier + "_08_exit_confirmation", app)
        try tap(exitAlert.buttons["取消"].firstMatch, name: "cancel board timer exit", app)
        try requireIdentifier("board_timer_resume_button", app)
        try tapIdentifier("board_timer_resume_button", app)
        try requireIdentifier("board_timer_pause_button", app)
        try waitForChange(secondClock, name: identifier + " resumed player two clock", timeout: 12)
        try checkpoint("timers_" + identifier + "_09_resumed", app)
        try tapIdentifier("board_timer_pause_button", app)
        try requireIdentifier("board_timer_stop_button", app)
        try tapIdentifier("board_timer_stop_button", app)
        let stopAlert = try require(app.alerts["确认停止"].firstMatch, "board timer stop confirmation")
        try checkpoint("timers_" + identifier + "_10_stop_confirmation", app)
        try tap(stopAlert.buttons["确认"].firstMatch, name: "confirm local board timer end", app)
        try requireIdentifier("board_timer_game_over_result", app)
        try require(app.staticTexts["手动结束"].firstMatch, "manual board timer result")
        try requireIdentifier("board_timer_result_exit_button", app)
        try checkpoint("timers_" + identifier + "_11_result", app)
        try tapIdentifier("board_timer_restart_button", app)
        try requireIdentifier("board_timer_start_button", app)
        try requireIdentifier("board_timer_first_indicator_player_1", app)
        try checkpoint("timers_" + identifier + "_12_restart_ready", app)
        try tapIdentifier("board_timer_back_button", app)
        try requireTimers(app)
    }

    private func launchTimers() throws -> XCUIApplication {
        application?.terminate()
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints",
            "-UITestFakeSession", "-UITestSportsVoiceMissing", "-UITestOpenTimer",
            "-national_day_2026_10_autopopup_count", "99",
            "-national_day_2026_last_shown_at", String(Date().timeIntervalSince1970)
        ]
        application = app
        app.launch()
        try require(app.navigationBars["计时"].firstMatch, "real timer tab", timeout: 20)
        return app
    }

    private func requireTimers(_ app: XCUIApplication) throws {
        try require(app.navigationBars["计时"].firstMatch, "returned timer tab")
    }

    private func openTimer(_ identifier: String, _ app: XCUIApplication) throws {
        try requireTimers(app)
        try tapIdentifier("timer_dest_" + identifier, app)
    }

    private func selectBoardMode(_ title: String, _ app: XCUIApplication) throws {
        let option = app.segmentedControls.buttons[title].firstMatch
        try tap(option, name: "board setup mode " + title, app)
        try waitForState("selected board setup mode " + title) { option.isSelected }
    }

    private func boardClock(player: Int, _ app: XCUIApplication) throws -> XCUIElement {
        let panel = try requireIdentifier("board_timer_player_" + String(player), app)
        return try require(panel.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "([0-9]{2}:)?[0-9]{2}:[0-9]{2}")
        ).firstMatch, "board clock for player " + String(player))
    }

    private func stopwatchClock(_ app: XCUIApplication) throws -> XCUIElement {
        try require(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]{2}:[0-9]{2}\\.[0-9]{2}")
        ).firstMatch, "stopwatch elapsed time")
    }

    private func countdownClock(_ app: XCUIApplication) throws -> XCUIElement {
        try require(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "([0-9]{2}:)?[0-9]{2}:[0-9]{2}")
        ).firstMatch, "countdown remaining time")
    }

    private func increaseCustomDurationRow(_ title: String, _ app: XCUIApplication) throws {
        let row = title == "分钟" ? "minutes" : "seconds"
        try tapIdentifier("countdown_custom_" + row + "_increase", app)
    }

    private func dismissCountdownNotificationPermissionIfPresented() throws {
        // Starting a countdown can request local-notification permission on a
        // fresh simulator. Deny that optional prompt so it cannot cover the
        // running/pause controls or schedule a notification during capture.
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        for title in ["不允许", "Don't Allow", "Don’t Allow"] {
            let deny = alert.buttons[title].firstMatch
            if deny.exists && deny.isHittable {
                deny.tap()
                return
            }
        }
        throw WalkthroughFailure.invalidState("An unexpected system alert covers the countdown: " + alert.label)
    }

    private func waitForChange(_ clock: XCUIElement, name: String, timeout: TimeInterval = 8) throws {
        let before = clock.label
        try waitForState(name + " advances", timeout: timeout) { clock.exists && clock.label != before }
    }

    private func requireStable(_ clock: XCUIElement, name: String) throws {
        let before = clock.label
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        guard clock.exists && clock.label == before else {
            throw WalkthroughFailure.invalidState(name + " is still changing")
        }
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

    private func tapButton(_ title: String, _ app: XCUIApplication) throws {
        try tap(app.buttons[title].firstMatch, name: title, app)
    }

    private func tap(_ element: XCUIElement, name: String, _ app: XCUIApplication) throws {
        try reveal(element, name: name, app)
        guard element.isEnabled else { throw WalkthroughFailure.disabled(name) }
        element.tap()
    }

    private func reveal(_ element: XCUIElement, name: String, _ app: XCUIApplication) throws {
        if element.waitForExistence(timeout: 2) && element.isHittable { return }
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
            case .missing(let name): return "Timer walkthrough could not find " + name
            case .disabled(let name): return "Timer walkthrough control is disabled: " + name
            case .invalidState(let reason): return "Timer walkthrough did not reach the expected state: " + reason
            case .captureTimeout(let name): return "Host did not remove duo-capture.json within 90 seconds: " + name
            }
        }
    }
}
