import Foundation
import XCTest

/// Uses fixture data behind the normal group list and its production navigation.
/// The host owns the device pose, PNG capture, recording, and capture-file ACK.
final class DuoGroupWalkthroughUITests: XCTestCase {
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

    func testWalkDuoGroupContentWidths() throws {
        let app = try launch()
        try checkpoint("width_group_01_list", app)
        try tap("group_create", app)
        try require("group_name", app)
        try checkpoint("width_group_02_create", app)
        try back(app)
        try tap("group_join", app)
        try require("group_number", app)
        try checkpoint("width_group_03_join", app)
        try back(app)
        try openFixtureGroup(app)
        try checkpoint("width_group_04_overview", app)
        for tab in [1, 2, 3] {
            try tap("group_tab_\(tab)", app)
            try checkpoint("width_group_05_tab_\(tab)", app)
        }
        try tap("group_tab_2", app)
        try tap("group_rank_row_ui-a", app)
        try require("group_member_results", app)
        try checkpoint("width_group_06_member_results", app)
        try back(app)
        try tap("group_tab_0", app)
        try tap("小组二维码", app)
        try require("group_qr", app)
        try checkpoint("width_group_07_share", app)
        try back(app)
        try tap("group_detail_notices", app)
        try require("group_notice_inbox", app)
        try checkpoint("width_group_08_notices", app)
    }

    func testWalkDuoGroup01ListManagementAndMembers() throws {
        let app = try launch()
        try checkpoint("groups_01_list", app)

        try tap("group_create", app)
        try require("group_name", app)
        try checkpoint("groups_02_create", app)
        try back(app)
        try require("group_create", app)

        try tap("group_join", app)
        try require("group_number", app)
        try checkpoint("groups_03_join", app)
        // Leave the number empty: looking at this form does not submit a join.
        try back(app)
        try openFixtureGroup(app)
        try checkpoint("groups_04_overview", app)

        try tap("小组管理", app)
        try require("group_menu_editProfile", app)
        try checkpoint("groups_05_management_menu", app)
        try tap("group_menu_editProfile", app)
        try require("group_edit_name", app)
        try checkpoint("groups_06_profile", app)
        try closePresentedOrBack(app)
        try require("group_tab_0", app)

        try tap("小组管理", app)
        try tap("group_menu_report", app)
        try require("group_report_submit", app)
        try checkpoint("groups_07_report", app)
        try closePresentedOrBack(app)

        try tap("group_tab_3", app)
        try checkpoint("groups_08_members", app)
        try reveal("group_add_temporary", app)
        try checkpoint("groups_09_temporary_members_section", app)
        try tap("group_add_temporary", app)
        let names = try require("group_temporary_names", app)
        try checkpoint("groups_10_temporary_member_form", app)
        names.tap()
        names.typeText("Alex\nSam")
        try checkpoint("groups_11_temporary_member_local_draft", app)
        // Closing discards this local form; the management submit is never tapped.
        try closePresentedOrBack(app)
        try require("group_tab_3", app)
    }

    func testWalkDuoGroup02MatchAndActivities() throws {
        let app = try launch(["-UITestGroupsMulti"])
        try openFixtureGroup(app)
        try tap("group_overview_start", app)
        try require("group_seat_A1", app)
        try checkpoint("groups_20_start_match_form", app)
        try tap("group_seat_A1", app)
        try require("group_member_pick_ui-a", app)
        try checkpoint("groups_21_inline_member_picker", app)
        try tap("group_member_pick_ui-a", app)
        try tap("group_seat_B1", app)
        try tap("group_member_pick_ui-b", app)
        try checkpoint("groups_22_start_match_local_roster", app)
        try tap("group_match_rules_summary", app)
        try checkpoint("groups_23_start_match_rules", app)
        // Do not tap group_match_submit: it creates a server-side match.
        try back(app)
        try require("group_tab_0", app)

        try tap("group_overview_addResult", app)
        try require("group_match_submit", app)
        try checkpoint("groups_24_manual_result_form", app)
        try tap("group_match_rules_summary", app)
        try checkpoint("groups_25_manual_result_rules", app)
        try tap("group_result_manual", app)
        try require("group_score_A", app)
        try checkpoint("groups_25b_manual_score_fields", app)
        try tap("group_result_sets_toggle", app)
        try checkpoint("groups_25c_manual_set_details", app)
        try back(app)
        try require("group_tab_0", app)

        try tap("group_tab_1", app)
        try checkpoint("groups_26_activities", app)
        try tap("group_activity_create", app)
        try require("group_activity_title", app)
        try checkpoint("groups_27_activity_create", app)
        try reveal("group_activity_note", app)
        try checkpoint("groups_28_activity_create_lower_fields", app)
        try tap("取消", app)
        try require("group_tab_1", app)

        try tap("group_activity_status_ui-activity", app)
        try require("group_activity_registration_manage", app)
        try checkpoint("groups_29_activity_detail", app)

        try tap("group_activity_more", app)
        try tap("group_activity_edit", app)
        try require("group_activity_title", app)
        try requireNavigationTitle("编辑", app)
        try checkpoint("groups_29b_activity_edit", app)
        try reveal("group_activity_note", app)
        try checkpoint("groups_29c_activity_edit_lower_fields", app)
        // The editor is a real navigation destination; Cancel discards it.
        try tap("取消", app)
        try requireVisible("group_activity_registration_manage", app)

        try tap("group_activity_registration_manage", app)
        try require("group_registration_close", app)
        let registeredMember = try require("group_registration_member_ui-b", app)
        try require("group_registration_member_ui-c", app)
        try require("group_registration_member_ui-d", app)
        guard registeredMember.isSelected, registeredMember.value as? String == "已报名" else {
            throw WalkthroughFailure.unexpected("registration fixture must show ui-b as registered")
        }
        try requireNoGroupNoticeError(app)
        try checkpoint("groups_30_registration_form", app)
        // A registration row changes only the sheet's draft; Save is never tapped.
        try tap("group_registration_member_ui-b", app)
        let registration = try require("group_registration_member_ui-b", app)
        guard !registration.isSelected else { throw WalkthroughFailure.unexpected("registration draft did not remove ui-b") }
        try checkpoint("groups_31_registration_local_draft", app)
        try tap("group_registration_close", app)
        try requireVisible("group_activity_registration_manage", app)

        try tap("group_activity_lineup_open", app)
        try require("group_activity_lineup_edit", app)
        try checkpoint("groups_32_activity_lineup", app)
        try tap("group_activity_lineup_edit", app)
        try require("group_training_publish", app)
        try checkpoint("groups_33_activity_lineup_editor", app)
        try tap("group_seat_A1", app)
        try requireVisible("group_member_pick_ui-a", app)
        try checkpoint("groups_33b_activity_lineup_inline_member_picker", app)
        // Assigned member tokens toggle the local seat. Restore it before leaving.
        let seat = try require("group_seat_A1", app)
        let originalName = seat.value as? String
        guard originalName == "甲" else { throw WalkthroughFailure.unexpected("lineup A1 fixture should contain 甲") }
        try tap("group_member_pick_ui-a", app)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", originalName ?? ""), object: seat)
        guard XCTWaiter.wait(for: [changed], timeout: 4) == .completed else {
            try checkpoint("groups_33c_failed_roster_draft", app)
            throw WalkthroughFailure.unexpected("lineup A1 draft did not change")
        }
        try checkpoint("groups_33c_activity_lineup_local_roster_draft", app)
        try tap("group_member_pick_ui-a", app)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", originalName ?? ""), object: seat)
        guard XCTWaiter.wait(for: [restored], timeout: 4) == .completed else { throw WalkthroughFailure.unexpected("lineup A1 draft did not restore") }
        // The first session heading may already be visible. Target its final
        // control so this capture actually reaches the lower roster fields.
        try reveal("group_schedule_shift_ui-activity-session", app)
        try checkpoint("groups_34_activity_lineup_editor_lower_fields", app)
        // Ending the test leaves the editor without saving or publishing.
    }

    func testWalkDuoGroup03RecordsRankingsShareAndNotices() throws {
        let app = try launch()
        try openFixtureGroup(app)
        try tap("group_tab_2", app)
        let rankings = try require("group_rank_table", app)
        try checkpoint("groups_40_records_and_rankings", app)
        rankings.swipeLeft()
        try checkpoint("groups_41_ranking_remaining_columns", app)
        rankings.swipeRight()
        try tap("group_rank_row_ui-a", app)
        try requireNavigationTitle("成员战绩", app)
        try require("group_member_results", app)
        try requireVisible("group_result_ui-result", app)
        try requireNoGroupNoticeError(app)
        try checkpoint("groups_42_member_results", app)
        try back(app)
        try require("group_tab_2", app)

        try tap("group_rank_format_doubles", app)
        try require("group_rank_empty", app)
        try checkpoint("groups_43_doubles_ranking_empty", app)
        try tap("group_rank_format_singles", app)
        try tap("group_result_ui-result", app)
        try requireNavigationTitle("比赛详情", app)
        try require("group_result_detail", app)
        let setScores = app.staticTexts["21:19 · 18:21"].firstMatch
        guard setScores.waitForExistence(timeout: 8) else { throw WalkthroughFailure.missing("fixture result set scores") }
        try reveal(setScores, name: "fixture result set scores", app)
        try requireNoGroupNoticeError(app)
        try checkpoint("groups_44_result_detail", app)
        try back(app)
        try require("group_tab_2", app)

        try tap("group_tab_0", app)
        try tap("小组二维码", app)
        try require("group_qr", app)
        try checkpoint("groups_45_invitation_qr", app)
        // The link/card share buttons are intentionally not tapped.
        try back(app)
        try require("group_tab_0", app)

        try tap("group_detail_notices", app)
        try require("group_notice_inbox", app)
        try require("group_notice_open_ui-notice", app)
        try checkpoint("groups_46_notice_inbox", app)
        // Opening a notice marks it seen, so capture the inbox without opening it
        // or using its mark-read controls.
    }

    private func launch(_ extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints",
            "-UITestFakeSession", "-UITestSportsVoiceMissing",
            "-UITestGroupsFixture", "-UITestGroupsFreshDrafts",
            "-national_day_2026_10_autopopup_count", "99"
        ] + extraArguments
        application = app
        app.launch()
        try require("group_create", app, timeout: 20)
        // This fixture pushes the real group list from Home. It does not use
        // -UITestGroupsCrossPlatform or GroupCaptureRoot's direct destinations.
        return app
    }

    private func openFixtureGroup(_ app: XCUIApplication) throws {
        try tap("group_card_ui-group", app)
        try require("group_tab_0", app)
    }

    @discardableResult
    private func require(_ identifier: String, _ app: XCUIApplication, timeout: TimeInterval = 8) throws -> XCUIElement {
        let control = app.descendants(matching: .any)[identifier].firstMatch
        guard control.waitForExistence(timeout: timeout) else {
            throw WalkthroughFailure.missing(identifier)
        }
        return control
    }

    private func requireNavigationTitle(_ title: String, _ app: XCUIApplication) throws {
        guard app.navigationBars[title].waitForExistence(timeout: 8) else {
            throw WalkthroughFailure.missing("navigation title: " + title)
        }
    }

    private func tap(_ identifier: String, _ app: XCUIApplication) throws {
        let control = try require(identifier, app)
        try reveal(control, name: identifier, app)
        guard control.isEnabled else { throw WalkthroughFailure.disabled(identifier) }
        control.tap()
    }

    private func reveal(_ identifier: String, _ app: XCUIApplication) throws {
        try reveal(try require(identifier, app), name: identifier, app)
    }

    private func requireVisible(_ identifier: String, _ app: XCUIApplication) throws {
        try reveal(identifier, app)
    }

    private func requireNoGroupNoticeError(_ app: XCUIApplication) throws {
        // These populated fixture destinations have no normal notice card.
        let notices = app.descendants(matching: .any).matching(identifier: "group_notice").allElementsBoundByIndex
        if let notice = notices.first(where: { $0.exists && $0.isHittable }) {
            throw WalkthroughFailure.unexpected("fixture destination displayed an error: " + notice.label)
        }
    }

    private func reveal(_ control: XCUIElement, name: String, _ app: XCUIApplication) throws {
        if isVisibleTapTarget(control, app) { return }
        for direction in [true, false] {
            for _ in 0..<7 {
                scroll(app, up: direction)
                if isVisibleTapTarget(control, app) { return }
            }
        }
        throw WalkthroughFailure.missing("hittable " + name)
    }

    /// XCTest can call an offscreen token hittable even while a fixed Save
    /// footer covers it. Scroll it fully clear before synthesizing any tap.
    private func isVisibleTapTarget(_ control: XCUIElement, _ app: XCUIApplication) -> Bool {
        guard control.exists, control.isHittable else { return false }
        for identifier in ["group_training_publish", "group_match_submit", "group_registration_save"] {
            let footer = app.buttons[identifier].firstMatch
            if control.identifier != identifier, footer.exists, footer.isHittable,
               control.frame.intersects(footer.frame) { return false }
        }
        return true
    }

    private func scroll(_ app: XCUIApplication, up: Bool) {
        let scrollView = app.scrollViews.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
        let surface = scrollView ?? app.windows.firstMatch
        if up { surface.swipeUp() } else { surface.swipeDown() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func back(_ app: XCUIApplication) throws {
        let systemBack = app.buttons["BackButton"].firstMatch
        if systemBack.exists, systemBack.isHittable {
            systemBack.tap()
            return
        }
        guard let bar = app.navigationBars.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable }),
              let button = bar.buttons.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) else {
            throw WalkthroughFailure.missing("navigation back button")
        }
        button.tap()
    }

    private func closePresentedOrBack(_ app: XCUIApplication) throws {
        let close = app.buttons["modal_close_button"].firstMatch
        if close.exists && close.isHittable { close.tap() }
        else { try back(app) }
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
        let transportErrors = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@",
            "Unsupported offline group fixture read:", "Offline group fixture blocked write:",
            "登录已失效", "请重新登录", "无法加载", "加载失败", "刷新失败"
        ))
        if let failure = transportErrors.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
            throw WalkthroughFailure.unexpected(failure.label)
        }
        let request = CaptureRequest(
            name: name,
            width: Double(app.frame.width),
            height: Double(app.frame.height),
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
        case captureTimeout(String)
        case unexpected(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name): return "Group walkthrough could not find " + name
            case .disabled(let name): return "Group walkthrough control is disabled: " + name
            case .captureTimeout(let name): return "Host did not remove duo-capture.json within 90 seconds: " + name
            case .unexpected(let detail): return "Group walkthrough unexpected state: " + detail
            }
        }
    }
}
