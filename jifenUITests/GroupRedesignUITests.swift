import XCTest
import UIKit

final class GroupRedesignUITests: XCTestCase {
    func testMeScannerGroupApprovalPreviewHidesTabBarAndRestoresHome() {
        let app = openGroupFromMeScanner(["-UITestGroupScanApproval"])
        XCTAssertTrue(app.staticTexts["group_preview_name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["group_join_submit"].exists)
        assertMainTabBarHidden(app)
        capture(app, "scan-group-approval-without-tabbar")
        returnFromScannedGroupToHome(app, title: "加入小组")
    }

    func testMeScannerOpenGroupJoinKeepsTabBarHidden() {
        let app = openGroupFromMeScanner()
        XCTAssertTrue(app.buttons["group_join_submit"].waitForExistence(timeout: 10))
        assertMainTabBarHidden(app)
        app.buttons["group_join_submit"].tap()
        XCTAssertTrue(app.buttons["group_overview_addResult"].waitForExistence(timeout: 10))
        assertMainTabBarHidden(app)
        capture(app, "scan-group-joined-without-tabbar")
        returnFromScannedGroupToHome(app, title: "球友小组")
    }

    func testMeScannerExistingMemberOpensGroupWithoutTabBar() {
        let app = openGroupFromMeScanner(["-UITestGroupScanMember"])
        XCTAssertTrue(app.buttons["group_overview_addResult"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["group_join_submit"].exists)
        assertMainTabBarHidden(app)
        capture(app, "scan-group-existing-member-without-tabbar")
        returnFromScannedGroupToHome(app, title: "球友小组")
    }

    private func openGroupFromMeScanner(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestSportsVoiceMissing",
            "-UITestFakeSession", "-UITestGroupsFixture", "-UITestGroupScan",
            "-UITestQRScanPayload", "https://jifenqi.com/groups/join?groupNo=12345678",
            "-national_day_2026_10_autopopup_count", "99"
        ] + extra
        app.launch()
        let groups = app.navigationBars["我的小组"]
        XCTAssertTrue(groups.waitForExistence(timeout: 15))
        groups.buttons.firstMatch.tap()
        let me = app.tabBars.buttons["我的"]
        XCTAssertTrue(me.waitForExistence(timeout: 5))
        me.tap()
        let scan = app.buttons["settings_qr_login_entry"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        return app
    }

    private func assertMainTabBarHidden(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.tabBars.allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, "Scanned group destinations must hide the main Tab Bar", file: file, line: line)
    }

    private func returnFromScannedGroupToHome(_ app: XCUIApplication, title: String) {
        app.navigationBars[title].buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].isHittable)
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["settings_qr_login_entry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["扫码"].exists, "The original scanner must close after routing to the group")
    }

    func testGuestGroupPreviewOffersLoginChoicesAndCanCancel() throws {
        let app = openGuestJoin()
        enterGroupNumber("123456", app: app)
        XCTAssertFalse(app.buttons["account_login_password"].exists, "Public previews must not require authentication")
        app.buttons["group_join_scan"].tap()
        XCTAssertTrue(app.buttons["group_scan_photo"].waitForExistence(timeout: 5))
        app.buttons["modal_close_button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["group_join_submit"].waitForExistence(timeout: 5))
        app.buttons["group_join_submit"].tap()
        XCTAssertTrue(app.buttons["account_login_password"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account_login_apple"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "account_login_password").count, 1)
        XCTAssertTrue(app.buttons["account_login_password"].isHittable)
        capture(app, "guest-group-login-choices")
        app.buttons["account_login_password"].tap()
        XCTAssertTrue(app.textFields["password_login_account"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["account_login_password"].waitForExistence(timeout: 5))
        app.buttons["modal_close_button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["group_join_submit"].waitForExistence(timeout: 5))
        assertJoinFixture("authenticated=false;apple=0;join=0", app: app)
        XCTAssertEqual(app.textFields["group_number"].value as? String, "123456")
        XCTAssertTrue(app.staticTexts["group_preview_name"].exists)
    }

    func testGuestLoginReturnsToGroupWithoutAutomaticallyJoining() throws {
        try verifyGuestLoginRequiresJoinConfirmation(approval: false)
    }

    func testGuestLoginPreservesApprovalMessageAndRequiresConfirmation() throws {
        try verifyGuestLoginRequiresJoinConfirmation(approval: true)
    }

    func testGuestInvitationRefreshesAvailabilityAfterLogin() throws {
        let app = openGuestJoin(["-UITestGroupJoinFull"])
        app.open(try XCTUnwrap(URL(string: "https://iscoreboard.live/groups/join?groupNo=654321")))
        XCTAssertTrue(app.staticTexts["group_preview_name"].waitForExistence(timeout: 10))
        app.buttons["group_join_submit"].tap()
        completeFixturePasswordLogin(app)
        assertJoinFixture("authenticated=true;apple=0;join=0", app: app)
        XCTAssertTrue(app.staticTexts["group_preview_name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["group_number"].value as? String, "654321")
        XCTAssertFalse(app.buttons["group_join_submit"].exists, "A group that became full while logging in must not accept a join")
        capture(app, "guest-invitation-full-after-login")
    }

    func testSignedInGroupJoinDoesNotPresentLogin() {
        let app = openGuestJoin(["-UITestFakeSession"])
        enterGroupNumber("123456", app: app)
        app.buttons["group_join_submit"].tap()
        assertJoinFixture("authenticated=true;apple=0;join=1", app: app)
        XCTAssertFalse(app.buttons["account_login_password"].exists)
    }

    func testGroupLoginOnlyRequestsAppleAfterExplicitConsentAndTap() {
        let app = openGuestJoin()
        enterGroupNumber("123456", app: app)
        app.buttons["group_join_submit"].tap()
        XCTAssertTrue(app.buttons["account_login_password"].waitForExistence(timeout: 5))
        app.buttons["account_login_agreement"].tap()
        app.buttons["account_login_apple"].tap()
        XCTAssertTrue(app.staticTexts["已取消登录"].waitForExistence(timeout: 5))
        app.buttons["modal_close_button"].firstMatch.tap()
        assertJoinFixture("authenticated=false;apple=1;join=0", app: app)
        XCTAssertTrue(app.staticTexts["group_preview_name"].exists)
    }

    private func verifyGuestLoginRequiresJoinConfirmation(approval: Bool) throws {
        let app = openGuestJoin(approval ? ["-UITestGroupJoinApproval"] : [])
        enterGroupNumber("123456", app: app)
        if approval {
            app.textFields["group_join_message"].tap()
            app.textFields["group_join_message"].typeText("一起打球")
            app.buttons["group_keyboard_done"].tap()
        }
        app.buttons["group_join_submit"].tap()
        completeFixturePasswordLogin(app)
        assertJoinFixture("authenticated=true;apple=0;join=0", app: app)
        XCTAssertTrue(app.buttons["group_join_submit"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["group_number"].value as? String, "123456")
        if approval { XCTAssertEqual(app.textFields["group_join_message"].value as? String, "一起打球") }
        capture(app, approval ? "guest-approval-after-login" : "guest-open-group-after-login")
        app.buttons["group_join_submit"].tap()
        assertJoinFixture("authenticated=true;apple=0;join=1", app: app)
    }

    private func openGuestJoin(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestSportsVoiceMissing", "-UITestGroupsFixture", "-UITestGroupJoinAuth", "-UITestShowPasswordLogin", "-national_day_2026_10_autopopup_count", "99"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["group_join"].waitForExistence(timeout: 15))
        app.buttons["group_join"].tap()
        XCTAssertTrue(app.textFields["group_number"].waitForExistence(timeout: 5))
        return app
    }

    private func enterGroupNumber(_ number: String, app: XCUIApplication) {
        app.textFields["group_number"].tap()
        app.textFields["group_number"].typeText(number)
        app.buttons["group_keyboard_done"].tap()
        XCTAssertTrue(app.staticTexts["group_preview_name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["group_join_submit"].waitForExistence(timeout: 5))
    }

    private func completeFixturePasswordLogin(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["account_login_password"].waitForExistence(timeout: 5))
        app.buttons["account_login_password"].tap()
        XCTAssertTrue(app.textFields["password_login_account"].waitForExistence(timeout: 5))
        app.textFields["password_login_account"].tap()
        app.textFields["password_login_account"].typeText("fixture@example.com")
        app.secureTextFields["password_login_password"].tap()
        app.secureTextFields["password_login_password"].typeText("fixture-password")
        app.buttons["account_login_agreement"].tap()
        app.buttons["password_login_submit"].tap()
        dismissPasswordSavePrompt(app)
    }

    /// iOS offers to save the fixture password after the login sheet closes.
    /// The prompt follows the device language, not the app's `-AppleLanguages`
    /// override, and it can be hosted by either the app or SpringBoard.
    private func dismissPasswordSavePrompt(_ app: XCUIApplication) {
        let hosts = [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")]
        let declineLabels = ["以后", "稍后", "Not Now", "Not now"]
        let acceptLabels = ["保存", "Save"]
        for _ in 0..<4 {
            var target: XCUIElement?
            for host in hosts {
                for label in declineLabels + acceptLabels {
                    let button = host.buttons[label]
                    if button.waitForExistence(timeout: 0.5), button.isHittable {
                        target = button
                        break
                    }
                }
                if target != nil { break }
            }
            guard let button = target else { return }
            button.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: button)
            if XCTWaiter.wait(for: [dismissed], timeout: 2) == .completed { return }
        }
        XCTFail("The system save-password prompt still covers the group action")
    }

    private func assertJoinFixture(_ value: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let fixture = app.descendants(matching: .any)["group_join_auth_fixture"].firstMatch
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: fixture)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }

    func testEnglishGroupHeadingsAndHomeMemberCount() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestGroupsFixture", "-UITestGroupsFreshDrafts", "-national_day_2026_10_autopopup_count", "99"]
        app.launch()
        XCTAssertTrue(app.navigationBars["My Groups"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["group_create"].label, "Create Group")
        XCTAssertEqual(app.buttons["group_join"].label, "Join Group")
        app.navigationBars["My Groups"].buttons.firstMatch.tap()
        let card = app.buttons["home_group_card_ui-group"]
        for _ in 0..<6 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["My Groups"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "4 members")).firstMatch.exists)
        capture(app, "english-home-group-heading-and-count")
        card.tap()
        let addResult = app.buttons["group_overview_addResult"]
        XCTAssertTrue(addResult.waitForExistence(timeout: 10))
        XCTAssertEqual(addResult.label, "Add Result")
        addResult.tap()
        XCTAssertTrue(app.navigationBars["Add Match Result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose a Member"].firstMatch.exists)
        let submit = app.buttons["group_match_submit"]
        for _ in 0..<5 where !submit.isHittable { app.swipeUp() }
        XCTAssertTrue(submit.exists)
        XCTAssertEqual(submit.label, "Submit Result")
        XCTAssertEqual(app.buttons["group_result_manual"].label, "Manual Entry")
        capture(app, "english-group-result-headings")
    }

    func testHomeGroupCardOpensDetailAndArrowOpensListWithoutRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestGroupsFixture", "-national_day_2026_10_autopopup_count", "99"]
        app.launch()
        XCTAssertTrue(app.navigationBars["我的小组"].waitForExistence(timeout: 15))
        app.navigationBars["我的小组"].buttons.firstMatch.tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home_group_card_")).firstMatch
        for _ in 0..<6 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        capture(app, "home-group-shared-section-title")
        card.tap()
        XCTAssertTrue(app.buttons["group_tab_0"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["group_create"].exists)
        capture(app, "home-group-direct-detail")
        app.navigationBars.buttons.firstMatch.tap()
        let arrow = app.buttons["home_groups"]
        for _ in 0..<6 where !arrow.isHittable { app.swipeUp() }
        XCTAssertTrue(arrow.waitForExistence(timeout: 5))
        arrow.tap()
        XCTAssertTrue(app.navigationBars["我的小组"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["group_create"].exists)
        XCTAssertTrue(app.buttons["group_notices"].exists)
        XCTAssertFalse(app.navigationBars["我的小组"].buttons["刷新"].exists)
        capture(app, "group-list-compact-sections-without-refresh")
    }

    func testHomeBellOpensNoticesDirectlyWithUnreadReminder() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestGroupsFixture", "-national_day_2026_10_autopopup_count", "99"]
        app.launch()
        XCTAssertTrue(app.navigationBars["我的小组"].waitForExistence(timeout: 15))
        app.navigationBars["我的小组"].buttons.firstMatch.tap()
        let bell = app.buttons["home_group_notices"]
        for _ in 0..<6 where !bell.isHittable { app.swipeUp() }
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertEqual(bell.value as? String, "1")
        capture(app, "home-group-notice-bell")
        bell.tap()
        XCTAssertTrue(app.descendants(matching: .any)["group_notice_inbox"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group_notices_mark_all"].exists)
        capture(app, "home-group-direct-notice-inbox")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 5), "The inbox must return directly to Home")
    }

    func testDestructiveManagementMenuItemsRenderRedForOwnerAndMember() throws {
        for member in [false, true] {
            let app = openGroup(member ? ["-UITestGroupsStudent"] : [])
            app.buttons["小组管理"].tap()
            for action in member ? ["leave", "report"] : ["dissolve", "report"] {
                let button = app.buttons["group_menu_" + action]
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                let image = try XCTUnwrap(button.screenshot().image.cgImage)
                var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                try pixels.withUnsafeMutableBytes { bytes in
                    let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                }
                let redPixels = stride(from: 0, to: pixels.count, by: 4).filter { index in
                    Int(pixels[index]) > 120 && Int(pixels[index]) > Int(pixels[index + 1]) + 45
                        && Int(pixels[index]) > Int(pixels[index + 2]) + 30
                }.count
                XCTAssertGreaterThan(redPixels, 8, action + " must visibly use destructive red")
            }
            capture(app, member ? "group-member-destructive-menu" : "group-owner-destructive-menu")
            app.terminate()
        }
    }

    func testIncompleteRosterUsesOriginalMemberAndBatchFlowWithoutLosingMatchSetup() {
        let app = openGroup(["-UITestGroupsInviteOnly", "-UITestGroupsNoHistory"])
        app.buttons["group_overview_start"].tap()
        let doubles = app.buttons["双打"].firstMatch
        XCTAssertTrue(doubles.waitForExistence(timeout: 5)); doubles.tap()
        XCTAssertTrue(app.buttons["group_seat_A2"].exists)
        app.buttons["group_seat_A1"].tap()
        app.buttons["group_member_pick_ui-a"].tap()
        app.buttons["group_seat_B1"].tap()
        let addTemporary = app.buttons["group_roster_add_temporary"]
        for _ in 0..<3 where !addTemporary.isHittable { app.scrollViews.firstMatch.swipeUp() }
        addTemporary.tap()
        let names = app.descendants(matching: .any)["group_temporary_names"].firstMatch
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        names.tap(); names.typeText("Test Alpha\nTest Beta")
        let common = app.buttons["group_temporary_common_names"]
        if !common.isHittable { app.swipeUp() }
        common.tap()
        XCTAssertTrue(app.navigationBars["常用名称"].waitForExistence(timeout: 5))
        app.navigationBars["常用名称"].buttons.firstMatch.tap()
        XCTAssertTrue((names.value as? String)?.contains("Test Beta") == true)
        capture(app, "group-roster-match-original-batch-form")
        app.navigationBars["临时成员"].buttons["关闭"].tap()
        let selectedPlayer = app.buttons["group_member_pick_ui-a"]
        for _ in 0..<3 where !selectedPlayer.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(selectedPlayer.exists, "The member pool stays inline when the batch sheet closes")
        XCTAssertTrue(selectedPlayer.isSelected, "A1 remains assigned and can be cleared by tapping its token")
        XCTAssertTrue(app.buttons["group_seat_A2"].exists, "Doubles must remain selected")
        XCTAssertEqual(app.buttons["group_seat_A1"].value as? String, "甲", "The chosen A1 must survive")
        for _ in 0..<3 where !app.buttons["group_match_submit"].exists { app.swipeUp() }
        XCTAssertFalse(app.buttons["group_match_submit"].isEnabled, "An incomplete match cannot start")
        capture(app, "group-roster-match-draft-retained")
    }

    func testOverviewToastStaysAbovePrimaryActionBar() {
        let app = openGroup(["-UITestGroupsOnlyTemporary"])
        app.buttons["小组管理"].tap()
        app.buttons["group_menu_transfer"].tap()
        let toast = app.staticTexts["group_toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        let start = app.buttons["group_overview_start"]
        XCTAssertTrue(start.exists)
        XCTAssertLessThanOrEqual(toast.frame.maxY, start.frame.minY, "The toast must clear the primary action bar")
        capture(app, "group-overview-transfer-toast")
    }

    func testIncompleteDirectScheduleCanAddMatchesAndUseOriginalBatchForm() {
        let app = openGroup(["-UITestGroupsInviteOnly", "-UITestGroupsEmpty"])
        app.buttons["group_tab_1"].tap()
        app.buttons["group_activity_direct"].tap()
        let title = app.textFields["group_direct_title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Keep schedule\n")
        let add = app.buttons["group_roster_add_temporary"]
        if !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["group_temporary_names"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["临时成员"].buttons["关闭"].tap()
        if !title.isHittable { app.swipeDown() }
        XCTAssertTrue((title.value as? String)?.contains("Keep schedule") == true)
        for _ in 0..<3 where !app.buttons["group_activity_direct_save"].exists { app.swipeUp() }
        XCTAssertFalse(app.buttons["group_activity_direct_save"].isEnabled)
        capture(app, "group-roster-direct-draft-retained")
    }

    func testProfileEditorUsesPhoneNavigationAndTabletSheet() {
        let app = openGroup()
        let tablet = app.windows.firstMatch.frame.width >= 600
        app.buttons["小组管理"].tap()
        app.buttons["group_menu_editProfile"].tap()
        let name = app.textFields["group_edit_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let editorBar = app.navigationBars["修改小组资料"]
        let save = app.buttons["group_management_submit"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The custom footer owns Save on both phone and tablet")
        XCTAssertFalse(editorBar.buttons["group_management_submit"].exists)
        XCTAssertGreaterThan(save.frame.minY, name.frame.maxY)
        XCTAssertGreaterThanOrEqual(save.frame.height, 48)
        if tablet {
            let close = editorBar.buttons["modal_close_button"]
            XCTAssertTrue(close.exists)
            XCTAssertEqual(close.label, "关闭", "The cross keeps its localized VoiceOver label")
        }
        name.tap(); name.typeText(" draft")
        XCTAssertTrue((name.value as? String)?.contains("draft") == true)
        XCTAssertTrue(save.isHittable, "The footer must remain reachable while the keyboard is open")
        if app.keyboards.firstMatch.exists { XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY + 1) }
        capture(app, tablet ? "group-edit-tablet-sheet-keyboard" : "group-edit-phone-page-keyboard")
        if tablet {
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return frame.width > frame.height && editorBar.buttons["modal_close_button"].isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)
            XCTAssertTrue((name.value as? String)?.contains("draft") == true)
            XCTAssertTrue(save.isHittable, "Rotation must preserve the custom footer above the keyboard")
            XCTAssertGreaterThanOrEqual(editorBar.buttons["modal_close_button"].frame.width, 44)
            XCTAssertGreaterThanOrEqual(editorBar.buttons["modal_close_button"].frame.height, 44)
            capture(app, "group-edit-tablet-sheet-landscape", fullScreen: true)
            editorBar.buttons["modal_close_button"].tap()
        } else {
            XCTAssertFalse(editorBar.buttons["modal_close_button"].exists)
            XCTAssertTrue(editorBar.buttons.firstMatch.isHittable)
            editorBar.buttons.firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["group_tab_0"].waitForExistence(timeout: 5))
        app.buttons["小组管理"].tap(); app.buttons["group_menu_editProfile"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse((name.value as? String)?.contains("draft") == true, "Cancelled edits must not modify the group")
    }

    func testReviewEmptyTabsAndTransferWithoutAccountCandidates() {
        let app = openGroup(["-UITestGroupsEmpty", "-UITestGroupsNoHistory", "-UITestGroupsOnlyTemporary"])
        app.buttons["group_tab_1"].tap()
        let title = app.staticTexts["group_empty_title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let activitiesY = title.frame.minY
        capture(app, "group-review-empty-activities")
        app.buttons["group_tab_2"].tap()
        let recordTitle = app.staticTexts["group_records_empty"].firstMatch
        XCTAssertTrue(recordTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(recordTitle.frame.minY, activitiesY, accuracy: 1)
        capture(app, "group-review-empty-records")
        app.buttons["小组管理"].tap()
        app.buttons["group_menu_transfer"].tap()
        XCTAssertTrue(app.staticTexts["暂无可转让的正式成员，临时成员不能接任组长。"].waitForExistence(timeout: 3))
        let toast = app.staticTexts["group_toast"]
        XCTAssertTrue(toast.exists)
        XCTAssertLessThan(toast.frame.height, app.windows.firstMatch.frame.height / 3, "The toast must occupy only its message")
        XCTAssertFalse(app.buttons["group_management_submit"].exists)
        capture(app, "group-review-transfer-toast")
        app.buttons["group_tab_3"].tap()
        let add = app.buttons["group_add_temporary"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.isHittable)
        capture(app, "group-review-add-temporary")
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["group_temporary_names"].firstMatch.waitForExistence(timeout: 5))
    }

    func testBetaNoticeCollapsesAndCanExpandInPopulatedAndEmptyLists() {
        for empty in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-UITestGroupsFixture", "-national_day_2026_10_autopopup_count", "99"]
            if empty { app.launchArguments.append("-UITestGroupsListEmpty") }
            app.launch()
            XCTAssertTrue(app.buttons["group_create"].waitForExistence(timeout: 15))
            let expand = app.buttons["group_beta_notice_expand"]
            let collapse = app.buttons["group_beta_notice_collapse"]
            revealBetaNotice(app)
            if expand.exists { expand.tap() }
            XCTAssertTrue(collapse.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(collapse.frame.width, 44)
            XCTAssertGreaterThanOrEqual(collapse.frame.height, 44)
            collapse.tap()
            XCTAssertTrue(expand.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(expand.frame.height, 44)
            XCTAssertFalse(collapse.exists)
            capture(app, empty ? "group-beta-empty-collapsed" : "group-beta-collapsed")
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["group_create"].waitForExistence(timeout: 15))
            revealBetaNotice(app)
            XCTAssertTrue(expand.waitForExistence(timeout: 15))
            expand.tap()
            XCTAssertTrue(collapse.waitForExistence(timeout: 5))
            XCTAssertFalse(expand.exists)
            capture(app, empty ? "group-beta-empty-expanded" : "group-beta-expanded")
            app.terminate()
        }
    }

    private func revealBetaNotice(_ app: XCUIApplication) {
        for _ in 0..<6 {
            let expand = app.buttons["group_beta_notice_expand"]
            let collapse = app.buttons["group_beta_notice_collapse"]
            if expand.isHittable || collapse.isHittable { return }
            app.swipeUp()
        }
    }

    func testInvitationColdAndWarmOpenPrefillsJoinPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-national_day_2026_10_autopopup_count", "99"]
        app.open(try XCTUnwrap(URL(string: "https://jifenqi.com/groups/join?groupNo=72856000")))
        let number = app.textFields["group_number"]
        XCTAssertTrue(number.waitForExistence(timeout: 15))
        XCTAssertEqual(number.value as? String, "72856000")
        let joinBar = app.navigationBars["Join Group"]
        XCTAssertTrue(joinBar.exists)
        XCTAssertFalse(joinBar.buttons["modal_close_button"].exists, "External invitations use the main navigation stack")
        capture(app, "group-invitation-cold-open")
        app.open(try XCTUnwrap(URL(string: "https://iscoreboard.live/groups/join?groupNo=123456")))
        let updated = NSPredicate(format: "value == %@", "123456")
        expectation(for: updated, evaluatedWith: number)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(joinBar.buttons["modal_close_button"].exists)
        capture(app, "group-invitation-warm-open")
        XCTAssertTrue(joinBar.buttons.firstMatch.isHittable)
        joinBar.buttons.firstMatch.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: number)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed, "Back must leave the pushed invitation page")
        app.open(try XCTUnwrap(URL(string: "https://jifenqi.com/groups/join?groupNo=72856000")))
        XCTAssertTrue(number.waitForExistence(timeout: 10))
        XCTAssertEqual(number.value as? String, "72856000", "A later invitation must push normally after returning")
    }

    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }
    private func openGroup(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-UITestGroupsFixture", "-national_day_2026_10_autopopup_count", "99"] + extra
        app.launch()
        if extra.contains("-UITestGroupsArchived") {
            let archive = app.descendants(matching: .any)["group_archived_entry"].firstMatch
            XCTAssertTrue(archive.waitForExistence(timeout: 15))
            archive.tap()
        }
        let card = app.descendants(matching: .any)["group_card_ui-group"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        XCTAssertTrue(app.buttons["group_tab_0"].waitForExistence(timeout: 10))
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String, fullScreen: Bool = false) {
        let attachment = XCTAttachment(screenshot: fullScreen ? XCUIScreen.main.screenshot() : app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCreateDoesNotOfferCoachingWhenServerAdvertisesIt() {
        let app = openGroup(["-UITestGroupsAllTypes"])
        app.navigationBars.buttons.firstMatch.tap()
        let create = app.buttons["group_create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        capture(app, "groups-list-width")
        create.tap()
        XCTAssertTrue(app.textFields["group_name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["group_create_policy"].firstMatch.value as? String, "直接加入")
        XCTAssertFalse(app.staticTexts["训练组"].exists)
        XCTAssertFalse(app.buttons["训练组"].exists)
        XCTAssertFalse(app.staticTexts["小组类型"].exists)
        capture(app, "groups-peer-only-create")
    }

    func testRuleOptionsUseSelectableChips() {
        let app = openGroup()
        app.buttons["group_overview_addResult"].tap()
        let rules = app.buttons["group_match_rules_summary"]
        for _ in 0..<4 where !rules.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(rules.waitForExistence(timeout: 5)); rules.tap()
        let eleven = app.buttons["11"].firstMatch
        XCTAssertTrue(eleven.waitForExistence(timeout: 5)); eleven.tap()
        XCTAssertTrue(eleven.isSelected)
        XCTAssertTrue(app.buttons["21"].firstMatch.exists)
        capture(app, "groups-rule-options")
    }

    func testFailedReportReadBlocksSubmissionUntilRetry() {
        let app = openGroup(["-UITestReportReadFailureOnce"])
        app.buttons["小组管理"].tap()
        app.buttons["group_menu_report"].tap()
        let error = app.staticTexts["group_report_error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let submit = app.buttons["group_report_submit"]
        XCTAssertTrue(submit.exists)
        XCTAssertFalse(submit.isEnabled, "A failed read must not become a new report with empty attachments")
        let refresh = app.buttons["刷新进度"]
        for _ in 0..<5 where !refresh.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(refresh.isHittable)
        refresh.tap()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in submit.isEnabled }, object: nil)
        let result = XCTWaiter.wait(for: [loaded], timeout: 10)
        if result != .completed {
            let snapshot = XCTAttachment(string: app.debugDescription)
            snapshot.name = "Report state after retry"; snapshot.lifetime = .keepAlways
            add(snapshot)
            capture(app, "report-read-retry-failure")
        }
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(error.exists)
        XCTAssertTrue(app.staticTexts["Original report evidence"].exists, "Retry must hydrate an existing case instead of preserving an unread empty draft")
        submit.tap()
        let detail = app.descendants(matching: .any).matching(identifier: "group_report_detail").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.value as? String, "Original report evidence")
        app.terminate()
    }

    func testReportUsesCloseIconAndKeepsReasons() {
        let app = openGroup()
        app.buttons["小组管理"].tap()
        app.buttons["group_menu_report"].tap()
        XCTAssertTrue(app.navigationBars["举报小组"].waitForExistence(timeout: 5))
        let close = app.navigationBars["举报小组"].buttons["modal_close_button"]
        XCTAssertTrue(close.exists)
        XCTAssertEqual(close.label, "关闭")
        XCTAssertFalse(app.staticTexts["登录已失效，请重新登录"].exists)
        let addImage = app.buttons["添加图片"].firstMatch
        for _ in 0..<5 where !addImage.isHittable || addImage.frame.maxY > app.buttons["group_report_submit"].frame.minY { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(addImage.waitForExistence(timeout: 5))
        XCTAssertTrue(addImage.isHittable)
        let submit = app.buttons["group_report_submit"]
        XCTAssertTrue(submit.isHittable)
        XCTAssertLessThanOrEqual(addImage.frame.maxY, submit.frame.minY)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(submit.frame))
        capture(app, "groups-report-close")
        close.tap()
        XCTAssertTrue(app.buttons["group_tab_0"].waitForExistence(timeout: 5))
    }

    func testRankingTableShowsMeAndInsufficientGamesAndKeepsFormatFilters() {
        let app = openGroup()
        app.buttons["group_tab_2"].tap()
        let table = app.scrollViews["group_rank_table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["甲（我）"].exists)
        capture(app, "groups-ranking-identity")
        table.swipeLeft()
        XCTAssertTrue(app.staticTexts["胜率"].exists)
        XCTAssertTrue(app.staticTexts["场次不足"].exists)
        capture(app, "groups-ranking-six-columns")
        app.buttons["group_rank_format_doubles"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["group_rank_empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group_rank_format_singles"].exists)
        XCTAssertFalse(app.buttons["group_rank_row_ui-a"].exists)
        app.buttons["group_rank_format_singles"].tap()
        XCTAssertTrue(app.buttons["group_rank_row_ui-a"].waitForExistence(timeout: 5))
    }

    func testRankingErrorKeepsBothFiltersAndRetry() {
        let app = openGroup(["-UITestGroupsRankError"])
        app.buttons["group_tab_2"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["group_rank_error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group_rank_format_singles"].exists)
        app.buttons["group_rank_format_doubles"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["group_rank_error"].firstMatch.exists)
        XCTAssertTrue(app.buttons["重试"].exists)
        capture(app, "groups-ranking-error-filters")
    }

    func testMatchHistoryWithoutRankingsDoesNotShowRankingFilters() {
        let app = openGroup(["-UITestGroupsNoRankings"])
        app.buttons["group_tab_2"].tap()
        XCTAssertTrue(app.buttons["group_record_filter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["group_rank_format_singles"].exists)
        XCTAssertFalse(app.buttons["group_rank_format_doubles"].exists)
    }

    func testOverviewTabsRecordFilterAndSecondaryQR() {
        let app = openGroup()
        capture(app, "groups-overview")
        app.buttons["小组二维码"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["小组二维码"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["小组管理"].exists)
        capture(app, "groups-qr")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["group_tab_1"].tap(); capture(app, "groups-activities")
        app.buttons["group_tab_2"].tap()
        XCTAssertTrue(app.buttons["group_record_filter"].exists)
        app.buttons["group_record_filter"].tap()
        let doubles = app.collectionViews.buttons["双打"].firstMatch
        XCTAssertTrue(doubles.waitForExistence(timeout: 5)); doubles.tap()
        XCTAssertTrue(app.staticTexts["暂无比赛记录"].waitForExistence(timeout: 5))
        capture(app, "groups-records-filter")
        app.buttons["group_tab_3"].tap()
        XCTAssertTrue(app.staticTexts["组长"].exists)
        XCTAssertTrue(app.staticTexts["新队友"].exists)
        XCTAssertTrue(app.buttons["同意"].exists)
        XCTAssertTrue(app.buttons["拒绝"].exists)
        XCTAssertTrue(app.staticTexts["临时成员"].firstMatch.exists)
        capture(app, "groups-members")
    }
    func testEmptyStatesAndManagementDialog() {
        let app = openGroup(["-UITestGroupsEmpty"])
        app.buttons["group_tab_2"].tap()
        XCTAssertTrue(app.staticTexts["暂无比赛记录"].exists)
        capture(app, "groups-empty")
        app.buttons["小组管理"].tap()
        app.buttons["修改小组资料"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        capture(app, "groups-edit")
    }
    func testCoachingScheduleFixedDoublesSeatsAndAbsenceNotice() {
        let app = openGroup(["-UITestGroupsCoaching"])
        app.buttons["group_tab_1"].tap()
        capture(app, "groups-training")
        XCTAssertTrue(app.staticTexts["学员请假"].waitForExistence(timeout: 5))
        let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "临时有事")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        let start = app.buttons["立即计分"].firstMatch
        for _ in 0..<3 where !start.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(start.isHittable, app.debugDescription)
        start.tap()
        XCTAssertTrue(app.buttons["group_match_submit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group_match_submit"].isEnabled)
        for (seat, player) in [("A1", "甲"), ("A2", "乙"), ("B1", "丙"), ("B2", "丁")] { let row = app.descendants(matching: .any)["group_seat_" + seat].firstMatch; XCTAssertTrue(row.exists); XCTAssertEqual(row.value as? String, player) }
        capture(app, "groups-training-fixed-seats")
    }
    func testLandscapeOverviewAndQR() {
        let app = openGroup(["-UITestGroupsLandscape"])
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 5), .completed)
        let bounds = app.windows.firstMatch.frame
        for element in [app.buttons["小组二维码"].firstMatch, app.buttons["group_tab_3"], app.buttons["小组管理"]] {
            XCTAssertTrue(element.isHittable)
            XCTAssertTrue(bounds.contains(element.frame), "Clipped element: \(element.label) \(element.frame) outside \(bounds)")
        }
        capture(app, "groups-landscape-overview", fullScreen: true)
        app.buttons["小组二维码"].firstMatch.tap()
        XCTAssertTrue(app.images["group_qr"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["小组管理"].exists)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(app.images["group_qr"].frame))
        capture(app, "groups-landscape-qr", fullScreen: true)
    }

    func testOverviewActionsStayAtBottomAndDoNotAppearOnOtherTabs() {
        let app = openGroup()
        let primary = app.buttons["group_overview_start"]
        let secondary = app.buttons["group_overview_addResult"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(primary.isHittable, app.debugDescription); XCTAssertTrue(secondary.isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["group_overview_invite"].exists)
        XCTAssertTrue(app.buttons["group_secondary_invite"].exists)
        let bounds = app.windows.firstMatch.frame
        XCTAssertGreaterThan(primary.frame.minY, bounds.height * 0.75)
        XCTAssertTrue(bounds.contains(primary.frame)); XCTAssertTrue(bounds.contains(secondary.frame))
        let y = primary.frame.minY
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertEqual(primary.frame.minY, y, accuracy: 1)
        capture(app, "groups-bottom-two-actions")
        app.buttons["group_tab_1"].tap()
        XCTAssertFalse(primary.exists); XCTAssertFalse(secondary.exists)
    }
    func testOverviewInviteOnlyBeforeSecondMember() {
        let app = openGroup(["-UITestGroupsInviteOnly"])
        XCTAssertTrue(app.buttons["group_overview_invite"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["group_overview_invite"].isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["group_overview_start"].exists)
        XCTAssertFalse(app.buttons["group_overview_addResult"].exists)
        XCTAssertFalse(app.buttons["group_secondary_invite"].exists)
        capture(app, "groups-bottom-invite-only")
    }
    func testOverviewHasOneScoringActionBeforeAnyHistory() {
        let app = openGroup(["-UITestGroupsNoHistory"])
        XCTAssertTrue(app.buttons["group_overview_start"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["group_overview_start"].isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["group_overview_addResult"].exists)
        capture(app, "groups-bottom-first-match")
    }
    func testStudentOverviewOnlyOpensTrainingAndArchivedHasNoActions() {
        let student = openGroup(["-UITestGroupsCoaching", "-UITestGroupsStudent"])
        XCTAssertTrue(student.buttons["group_overview_training"].waitForExistence(timeout: 5), student.debugDescription)
        XCTAssertTrue(student.buttons["group_overview_training"].isHittable, student.debugDescription)
        XCTAssertFalse(student.buttons["group_overview_addResult"].exists)
        student.buttons["group_overview_training"].tap()
        XCTAssertTrue(student.buttons["group_tab_1"].isSelected)
        student.terminate()
        let archived = openGroup(["-UITestGroupsArchived"])
        XCTAssertFalse(archived.buttons["group_overview_start"].exists)
        XCTAssertFalse(archived.buttons["group_overview_addResult"].exists)
        XCTAssertFalse(archived.buttons["group_overview_invite"].exists)
    }

    private func openActivityLineupEditor(_ app: XCUIApplication) {
        let open = app.buttons["group_activity_lineup_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
        if !open.isHittable { app.swipeUp() }; open.tap()
        let edit = app.buttons["group_activity_lineup_edit"]
        if edit.waitForExistence(timeout: 2) { edit.tap() }
        XCTAssertTrue(app.buttons["group_training_publish"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testMultiActivityOpensNativeLineupAndIsReadyToSaveWithoutSubmitting() {
        let app = openGroup(["-UITestGroupsMulti"])
        app.staticTexts["周末羽毛球"].firstMatch.tap()
        openActivityLineupEditor(app)
        let save = app.buttons["group_training_publish"]
        XCTAssertTrue(save.isHittable, app.debugDescription)
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(app.buttons["group_schedule_confirm"].exists, "Saving no longer needs a second preview page")
        capture(app, "groups-native-lineup-ready-to-save")
    }

    func testActivityFormAllowsAutomaticTitleAndRejectsOversizedTitle() {
        let app = openGroup()
        app.buttons["group_tab_1"].tap()
        app.buttons["group_activity_create"].tap()
        let title = app.textFields["group_activity_title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let save = app.buttons["group_activity_save"]
        XCTAssertTrue(save.isEnabled, "An empty title should use the server's automatic name")
        title.tap(); title.typeText(String(repeating: "x", count: 41))
        XCTAssertFalse(save.isEnabled)
        title.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(save.isEnabled)
        app.swipeUp()
        capture(app, "groups-activity-contract-limits")
    }

    func testDisabledActivityCapabilitiesDisableCreateAndEditControls() {
        let app = openGroup(["-UITestGroupsActivitiesDisabled", "-UITestGroupsMulti"])
        app.buttons["group_tab_1"].tap()
        XCTAssertFalse(app.buttons["group_activity_create"].isEnabled)
        XCTAssertFalse(app.buttons["group_activity_direct"].isEnabled)
        app.staticTexts["周末羽毛球"].firstMatch.tap()
        let open = app.buttons["group_activity_lineup_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let edit = app.buttons["group_activity_lineup_edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(edit.isEnabled)
        capture(app, "groups-activity-disabled-capabilities")
    }

    func testExistingLineupCanRemoveItsLastUnstartedMatchAndReachSave() {
        let app = openGroup(["-UITestGroupsMulti"])
        app.staticTexts["周末羽毛球"].firstMatch.tap()
        openActivityLineupEditor(app)
        let remove = app.buttons["group_schedule_remove_ui-activity-session"]
        for _ in 0..<6 where !remove.isHittable { app.swipeUp() }
        XCTAssertTrue(remove.exists); remove.tap()
        let save = app.buttons["group_training_publish"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["group_schedule_empty"].firstMatch.exists)
        XCTAssertFalse(app.buttons["group_schedule_confirm"].exists)
        capture(app, "groups-existing-lineup-cleared")
    }

    func testUnchangedMissingLineupCanReachSaveWithoutAddingAPlayer() {
        let app = openGroup(["-UITestGroupsMulti", "-UITestGroupsMissingLineup"])
        app.staticTexts["周末羽毛球"].firstMatch.tap()
        openActivityLineupEditor(app)
        XCTAssertTrue(app.buttons["group_training_publish"].isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "选择成员")).firstMatch.exists)
        XCTAssertFalse(app.buttons["group_schedule_confirm"].exists)
        capture(app, "groups-lineup-missing-seat-retained")
    }
    func testNativeMembersDisplayWithoutSearch() {
        let app = openGroup()
        app.buttons["group_tab_3"].tap()
        XCTAssertTrue(app.staticTexts["丙"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["丁"].firstMatch.exists)
        XCTAssertFalse(app.textFields["group_member_search"].exists)
        capture(app, "groups-members")
    }
    func testNotificationInboxHasUnreadActivitySnapshot() {
        let app = openGroup()
        app.navigationBars.buttons.firstMatch.tap()
        let notifications = app.buttons["group_notices"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5)); notifications.tap()
        let notice = app.buttons["group_notice_open_ui-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(notice.label.contains("周末羽毛球已改期"), notice.debugDescription)
        XCTAssertTrue(notice.label.contains("场馆调整"), notice.debugDescription)
        XCTAssertTrue(app.buttons["group_notice_seen_ui-notice"].exists)
        capture(app, "groups-notification-inbox")
    }

    func testIndependentSeatSelectionAndManualResultValidationWithoutSubmitting() {
        let app = openGroup(["-UITestGroupsFreshDrafts"])
        app.buttons["group_overview_addResult"].tap()
        let submit = app.buttons["group_match_submit"]
        let firstSeat = app.descendants(matching: .any)["group_seat_A1"].firstMatch
        XCTAssertTrue(firstSeat.waitForExistence(timeout: 5))
        for _ in 0..<5 where !submit.exists { app.swipeUp() }
        XCTAssertTrue(submit.waitForExistence(timeout: 5), app.debugDescription); XCTAssertFalse(submit.isEnabled)
        let form = app.scrollViews.firstMatch
        let navigationBottom = app.navigationBars.element(boundBy: app.navigationBars.count - 1).frame.maxY
        for _ in 0..<5 where !firstSeat.isHittable || firstSeat.frame.minY < navigationBottom { form.swipeDown() }
        for (seat, member) in [("A1", "ui-a"), ("B1", "ui-b")] {
            let slot = app.descendants(matching: .any)["group_seat_" + seat].firstMatch
            for _ in 0..<4 where !slot.isHittable || slot.frame.minY < navigationBottom { form.swipeDown() }
            XCTAssertTrue(slot.isHittable, app.debugDescription); slot.tap()
            let player = app.buttons["group_member_pick_" + member]
            XCTAssertTrue(player.waitForExistence(timeout: 5), app.debugDescription); player.tap()
        }
        let manual = app.buttons["group_result_manual"]
        for _ in 0..<5 where !manual.isHittable { form.swipeUp() }
        XCTAssertTrue(manual.isHittable, app.debugDescription); manual.tap()
        for (id, score) in [("group_score_A", "2"), ("group_score_B", "0")] {
            let field = app.textFields[id]
            for _ in 0..<5 where !field.isHittable || (app.keyboards.firstMatch.exists && field.frame.maxY >= app.keyboards.firstMatch.frame.minY) { form.swipeUp() }
            field.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3)); field.typeText(score)
            let done = app.buttons["group_result_keyboard_done"]
            XCTAssertTrue(done.waitForExistence(timeout: 3)); done.tap()
        }
        for _ in 0..<3 where !submit.isHittable { app.swipeUp() }
        XCTAssertTrue(submit.isEnabled); capture(app, "groups-native-manual-valid-seats")
        let disclosure = app.buttons["group_result_sets_toggle"]
        for _ in 0..<5 where !disclosure.isHittable { form.swipeUp() }
        disclosure.tap()
        for _ in 0..<6 where !submit.isHittable { form.swipeUp() }
        XCTAssertTrue(submit.isEnabled, "Opening blank details must keep a valid total submittable")
        for index in 0..<2 {
            for (side, value) in [("A", "21"), ("B", "0")] {
                let field = app.textFields["group_detail_\(index)_\(side)"]
                for _ in 0..<8 {
                    if field.exists && field.isHittable && field.frame.minY >= navigationBottom + 4 { break }
                    if (field.exists && field.frame.minY < navigationBottom + 4) || (!field.exists && index == 0 && side == "A") { form.swipeDown() }
                    else { form.swipeUp() }
                }
                XCTAssertTrue(field.isHittable, app.debugDescription)
                XCTAssertNotEqual(field.value as? String, "0", "Untouched scores must be blank")
                field.tap(); field.typeText(value)
                let done = app.buttons["group_result_keyboard_done"]
                XCTAssertTrue(done.waitForExistence(timeout: 3)); done.tap()
            }
        }
        for _ in 0..<4 where !submit.isHittable { form.swipeUp() }
        XCTAssertTrue(submit.isEnabled)
        let clear = app.buttons["group_result_clear_total"]
        for _ in 0..<6 where !clear.isHittable { form.swipeDown() }
        XCTAssertTrue(clear.isHittable, app.debugDescription); clear.tap()
        for _ in 0..<6 where !submit.isHittable { form.swipeUp() }
        XCTAssertTrue(submit.isEnabled, "Completed details can supply the overall score")
        capture(app, "groups-manual-details-without-total")
    }
    func testTemporaryBatchFormValidatesNamesWithoutSubmitting() {
        let app = openGroup(); app.buttons["group_tab_3"].tap()
        let add = app.buttons["group_add_temporary"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.isHittable); add.tap()
        let field = app.descendants(matching: .any)["group_temporary_names"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("戊\n己")
        let submit = app.buttons["group_management_submit"]
        for _ in 0..<5 where !submit.exists { app.swipeUp() }
        XCTAssertTrue(submit.waitForExistence(timeout: 5), app.debugDescription); XCTAssertTrue(submit.isEnabled)
        capture(app, "groups-native-temporary-batch")
    }
    func testFooterButtonsFitAvailableWidthAtCurrentDynamicTypeSize() {
        let app = openGroup()
        let primary = app.buttons["group_overview_start"], secondary = app.buttons["group_overview_addResult"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5)); XCTAssertTrue(primary.isHittable); XCTAssertTrue(secondary.isHittable)
        let bounds = app.windows.firstMatch.frame
        XCTAssertTrue(bounds.contains(primary.frame)); XCTAssertTrue(bounds.contains(secondary.frame))
        XCTAssertGreaterThanOrEqual(primary.frame.height, 44); XCTAssertGreaterThanOrEqual(secondary.frame.height, 44)
        XCTAssertFalse(secondary.frame.intersects(primary.frame))
        capture(app, "groups-accessibility-footer")
    }
    func testDissolutionCooldownHasNoFooterAndBlocksTransfer() {
        let app = openGroup(["-UITestGroupsDissolving"])
        XCTAssertFalse(app.buttons["group_overview_start"].exists)
        XCTAssertFalse(app.buttons["group_overview_addResult"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "只读7天")).firstMatch.exists)
        app.buttons["小组管理"].tap()
        XCTAssertTrue(app.buttons["撤销解散"].exists)
        XCTAssertFalse(app.buttons["group_transfer"].isEnabled)
        capture(app, "groups-dissolution-cooldown")
    }

}


/// Appended as an independent class to the already registered GroupRedesignUITests source.
/// Existing tests and their fixture arguments are unchanged.
final class GroupCrossPlatformCaptureUITests: XCTestCase {
    private enum CaptureError: Error { case missing(String), invalidMetadata(String), unsupported(String) }
    private let canonicalHash = "021b1d8d4714984bb9deddbbc3dccb50c468ff21cec49055ddef947e342e7a47"
    private let adapterHash = "117c3bf1e14c1deebd1b86d63156d931f9413942ebedc76ca92b9f6157dc6817"
    private let reportAliases: [String: String] = [
        "create-approval-selected": "create-approval-selected",
        "inventory-management-actions": "admin",
        "inventory-member-actions": "member-actions",
        "inventory-result-actions": "result-actions",
        "inventory-edit-group": "dialog-edit-group",
        "inventory-edit-group-conflict": "group-conflict",
        "inventory-transfer-picker": "dialog-transfer-owner",
        "inventory-transfer-confirm": "transfer-selected",
        "inventory-member-report": "dialog-report",
        "inventory-visitor-report": "visitor-report",
        "inventory-dissolve-confirm": "dialog-dissolve",
        "inventory-archive-confirm": "dialog-archive",
        "inventory-leave-group-confirm": "dialog-leave",
        "inventory-temporary-members": "dialog-temporary-member",
        "inventory-common-name-import": "dialog-common-name-import",
        "inventory-rename-temporary-member": "member-rename",
        "inventory-remove-member-confirm": "member-remove",
        "inventory-approve-join-confirm": "request-approve",
        "inventory-reject-join-confirm": "request-reject",
        "inventory-training-cancel": "training-cancel",
        "inventory-training-leave": "training-leave",
        "inventory-result-authority-confirm-detail": "result-authority",
        "inventory-result-normal-confirm-detail": "result-normal",
        "inventory-result-void-detail-pending": "result-void-pending",
        "inventory-result-void-detail-confirmed": "result-void-confirmed",
        "inventory-result-authority-confirm-list": "records-authority",
        "inventory-result-void-list": "result-void-list",
        "inventory-upload-discard-confirm": "upload-discard",
        "inventory-activity-date-time": "activity-date",
        "inventory-activity-registration-deadline": "activity-deadline",
        "inventory-activity-common-places": "activity-place",
        "inventory-activity-cancel": "activity-cancel",
        "inventory-activity-abandon": "activity-abandon",
        "inventory-registration-draft-discard": "registration-draft",
        "activity-registration-draft-discard": "registration-draft",
        "inventory-result-played-at": "result-date",
        "inventory-result-save-draft-return": "result-draft-return",
        "inventory-result-abandon": "result-abandon",
        "inventory-lineup-clock": "lineup-clock",
        "inventory-lineup-finish": "lineup-finish",
        "inventory-lineup-reload-confirm": "lineup-conflict-reload",
        "inventory-training-sequence-preview": "training-shift-preview",
        "inventory-training-date-picker": "training-date",
        "inventory-training-clock-picker": "training-clock",
        "inventory-training-conflict-review": "training-conflict",
        "inventory-activity-conflict-review": "activity-conflict",
    ]
    private let nativeDifferences: [String: String] = [
        "inventory-edit-group-conflict": "Legacy scene ID now captures the editable profile form after an isolated save failure. The removed local/latest comparison and recovery draft are not recreated.",
        "inventory-activity-conflict-review": "Legacy scene ID now captures the editable activity form after an isolated save failure, without the removed version-choice controls.",
        "activity-registration-draft-discard": "Native registration editor exits directly and drops unsubmitted selections.",
        "inventory-registration-draft-discard": "Native registration editor exits directly and drops unsubmitted selections.",
        "inventory-activity-common-places": "Existing native CommonPlacePickerView with no saved local places in this fixture.",
        "lineup-correction": "Cancelled sessions keep their frozen lineup and expose no scoring or corrective-result action.",
        "inventory-result-actions": "Native result detail Form contains details and void actions rather than a record card menu.",
        "inventory-dissolve-confirm": "Native management editor provides explanation and an action-specific confirmation label.",
        "inventory-archive-confirm": "Native management editor provides explanation and an action-specific confirmation label.",
        "inventory-leave-group-confirm": "Native management editor provides explanation and an action-specific confirmation label.",
        "inventory-result-authority-confirm-detail": "Native alert contains the matchup, score, explanation, Cancel and Confirm.",
        "inventory-result-normal-confirm-detail": "Native alert contains the matchup, score, explanation, Cancel and Confirm.",
        "inventory-result-void-detail-pending": "Native result Form requires an inline void reason and final void action.",
        "inventory-result-void-detail-confirmed": "Native result Form requires an inline void reason and final void action.",
        "inventory-result-void-list": "Native record list navigates to result detail; void action and reason are shown there.",
        "inventory-result-save-draft-return": "Capture actually leaves the result editor through its production Back action and reopens it. The current form state is captured; no obsolete draft-save prompt or retention guarantee is invented.",
        "inventory-result-abandon": "Native release confirmation lives on activity detail, then unlocks the corresponding result flow.",
        "inventory-lineup-finish": "Native activity detail exposes Finish directly for terminal sessions; no extra pre-submit modal.",
    ]
    private let baseline = ["list", "create", "join", "join-approval", "detail-overview", "detail-activities", "detail-records", "detail-records-doubles", "detail-members", "admin", "activity", "activity-create", "lineup", "result", "result-launch", "result-detail", "member-results", "share", "notices", "coach", "student", "training-plan", "dialog-edit-group", "dialog-report", "dialog-transfer-owner", "dialog-dissolve", "dialog-temporary-member", "dialog-common-name-import"]

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testCompactJoinLocalizedLayouts() throws {
        let environment = ProcessInfo.processInfo.environment
        let sourceHash = environment["GROUP_CAPTURE_SOURCE_HASH"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_SOURCE_HASH"] ?? ""
        guard sourceHash.count == 64 else { throw CaptureError.invalidMetadata("Source hash missing") }
        for (language, locale, expected) in [("en", "en_US", "Open"), ("zh-Hant", "zh_TW", "可加入"), ("de", "de_DE", "Offen")] {
            for appearance in ["Light", "Dark"] {
                let app = XCUIApplication()
                app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-national_day_2026_10_autopopup_count", "99", "-UITestGroupsCrossPlatform", "-GroupCaptureScene", "join", "-GroupCaptureNow", "1791864000000", "-GroupCaptureDataHash", canonicalHash, "-GroupCaptureSourceHash", sourceHash, "-GroupCaptureLocale", locale, "-jifen-v2.appAppearanceMode", appearance.lowercased(), "-AppleInterfaceStyle", appearance, "-GroupCaptureAppearance", appearance]
                app.launch()
                defer { app.terminate() }
                try tap("group_join", app); try require("group_number", app)
                app.textFields["group_number"].tap(); app.textFields["group_number"].typeText("82603162")
                try tap("group_keyboard_done", app); try require("group_preview_name", app); try require("group_join_availability", app)
                let badge = app.staticTexts["group_join_availability"]
                XCTAssertEqual(badge.label, expected)
                XCTAssertTrue(app.windows.firstMatch.frame.contains(badge.frame))
                XCTAssertLessThan(badge.frame.width, 110)
                XCTAssertTrue(app.buttons["group_join_scan"].exists)
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "join-\(language)-\(appearance.lowercased())"; shot.lifetime = .keepAlways; add(shot)
                let proof = XCTAttachment(string: "language=\(language)\nsource=\(sourceHash)\nbadge=\(badge.label)\nframe=\(badge.frame)\n\(app.debugDescription)"); proof.name = "join-\(language)-\(appearance.lowercased())-proof"; proof.lifetime = .keepAlways; add(proof)
                // The single scan entry retains photo recognition in the scanner toolbar.
                try tap("group_join_scan", app)
                XCTAssertTrue(app.buttons["group_scan_photo"].waitForExistence(timeout: 5))
                app.terminate()
            }
        }
    }

    func testCaptureLocalizedPhonePages() throws {
        let env = ProcessInfo.processInfo.environment
        func captureValue(_ key: String) -> String? { env[key] ?? env["TEST_RUNNER_" + key] }
        let language = captureValue("GROUP_CAPTURE_LANGUAGE") ?? "en"
        let expectedJoin = captureValue("GROUP_CAPTURE_JOIN_LABEL") ?? ""
        let locale = captureValue("GROUP_CAPTURE_LOCALE") ?? language
        let sourceHash = captureValue("GROUP_CAPTURE_SOURCE_HASH") ?? ""
        let scenes = (captureValue("GROUP_CAPTURE_SCENES") ?? "list").split(separator: ",").map(String.init)
        guard sourceHash.count == 64 else { throw CaptureError.invalidMetadata("Missing localized source identity") }
        for scene in scenes {
            XCTContext.runActivity(named: "\(language)-\(scene)") { activity in
                let app = XCUIApplication()
                defer { app.terminate() }
                do {
                    app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                        "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing",
                        "-national_day_2026_10_autopopup_count", "99", "-UITestGroupsCrossPlatform", "-GroupCaptureScene", scene,
                        "-GroupCaptureNow", "1791864000000", "-GroupCaptureDataHash", canonicalHash, "-GroupCaptureSourceHash", sourceHash,
                        "-GroupCaptureLocale", locale, "-GroupCaptureAppearance", "Light", "-jifen-v2.appAppearanceMode", "light",
                        "-AppleInterfaceStyle", "Light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
                    app.launch()
                    let identity = app.descendants(matching: .any)["group_capture_identity"].firstMatch
                    guard identity.waitForExistence(timeout: 20),
                          (identity.value as? String)?.contains("source=\(sourceHash);ready=true") == true else {
                        throw CaptureError.invalidMetadata("Localized production fixture is not ready")
                    }
                    switch scene {
                    case "list":
                        try require("group_card_seed_group_badminton", app)
                        guard !expectedJoin.isEmpty, app.buttons["group_join"].label.contains(expectedJoin) else { throw CaptureError.invalidMetadata("Rendered language does not match requested language") }
                    case "create": try tap("group_create", app); try require("group_name", app)
                    case "join", "join-empty", "join-approval":
                        try tap("group_join", app); try require("group_number", app)
                        if scene != "join-empty" {
                            app.textFields["group_number"].tap(); app.textFields["group_number"].typeText("82603162")
                            try tap("group_keyboard_done", app); try keyboardClosed(app); try require("group_preview_name", app)
                        }
                    case "detail-overview": try require("group_tab_0", app)
                    case "detail-activities": try require("group_tab_1", app)
                    case "detail-records": try require("group_record_filter", app)
                    case "detail-members": try require("group_add_temporary", app)
                    case "activity": try require("group_activity_registration_count", app)
                    case "activity-create": try tap("group_activity_create", app); try require("group_activity_title", app)
                    case "activity-edit": try tap("group_activity_more", app); try tap("group_activity_edit", app); try require("group_activity_title", app)
                    case "lineup": try openActivityLineupEditor(app); try require("group_schedule_starts_compare_activity_session_1", app)
                    case "result": try tap("group_overview_addResult", app); try require("group_seat_A1", app)
                    case "result-detail":
                        guard app.navigationBars.firstMatch.waitForExistence(timeout: 5) else { throw CaptureError.missing("result detail navigation") }
                    case "member-results": try require("我", app)
                    case "share": try require("group_qr", app)
                    case "notices": try tap("group_detail_notices", app); try require("group_notices_mark_all", app)
                    default: throw CaptureError.unsupported(scene)
                    }
                    guard !app.alerts.firstMatch.exists, !app.sheets.firstMatch.exists else {
                        throw CaptureError.missing("Unexpected overlay in ordinary localized page")
                    }
                    let frame = app.windows.firstMatch.frame
                    guard frame.width == 402, frame.height == 874 else { throw CaptureError.invalidMetadata("Localized capture viewport changed") }
                    Thread.sleep(forTimeInterval: 0.6)
                    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    shot.name = "capture-\(scene)"; shot.lifetime = .keepAlways; activity.add(shot)
                    let metadata: [String: Any] = ["scene": scene, "platform": "ios", "language": language, "locale": locale,
                        "appearance": "light", "captureStatus": "captured", "sourceSHA256": sourceHash,
                        "canonicalSHA256": canonicalHash, "adapterSHA256": adapterHash, "logicalWidth": frame.width, "logicalHeight": frame.height,
                        "captureAtUTC": ISO8601DateFormatter().string(from: Date()), "transport": "strict-offline",
                        "scope": "ordinary-pages-only", "expectedJoinLabel": expectedJoin, "runtimeJoinLabel": app.buttons["group_join"].exists ? app.buttons["group_join"].label : "", "productionHierarchy": app.debugDescription]
                    let proof = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
                    proof.name = "metadata-\(scene)"; proof.lifetime = .keepAlways; activity.add(proof)
                    print("LOCALIZED_PAGE \(language) \(scene) captured")
                } catch {
                    XCTFail("\(language)/\(scene): \(error)")
                    let proof = XCTAttachment(string: "\(error)\n\(app.debugDescription)")
                    proof.name = "failed-\(scene)"; proof.lifetime = .keepAlways; activity.add(proof)
                }
            }
        }
    }

    func testCaptureCanonicalPhoneScenes() throws {
        let environment = ProcessInfo.processInfo.environment
        let realActivityNavigation = environment["GROUP_CAPTURE_REAL_ACTIVITY_NAVIGATION"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_REAL_ACTIVITY_NAVIGATION"] ?? "false"
        let sourceHash = environment["GROUP_CAPTURE_SOURCE_HASH"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_SOURCE_HASH"] ?? ""
        let sourceSnapshotAtUTC = environment["GROUP_CAPTURE_SOURCE_AT_UTC"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_SOURCE_AT_UTC"] ?? ""
        guard sourceHash.count == 64, !sourceSnapshotAtUTC.isEmpty else { throw CaptureError.invalidMetadata("Runner source snapshot metadata missing") }
        let appearance = environment["GROUP_CAPTURE_APPEARANCE"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_APPEARANCE"] ?? "Light"
        guard ["Light", "Dark"].contains(appearance) else { throw CaptureError.invalidMetadata("Unsupported appearance") }
        let supplied = environment["GROUP_CAPTURE_SCENES"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_SCENES"]
        let scenes = supplied?.split(separator: ",").map(String.init) ?? baseline
        XCTAssertFalse(scenes.isEmpty)
        for scene in scenes {
            XCTContext.runActivity(named: scene) { activity in
                let app = XCUIApplication()
                defer { app.terminate() }
                do {
                    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-national_day_2026_10_autopopup_count", "99", "-UITestGroupsCrossPlatform", "-GroupCaptureScene", scene, "-GroupCaptureNow", "1791864000000", "-GroupCaptureDataHash", canonicalHash, "-GroupCaptureSourceHash", sourceHash, "-jifen-v2.appAppearanceMode", appearance.lowercased(), "-AppleInterfaceStyle", appearance, "-GroupCaptureAppearance", appearance, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
                    app.launchArguments += ["-GroupCaptureRealActivityNavigation", realActivityNavigation]
                    if ["activity-edit", "activity-registration", "registration-draft", "activity-conflict"].contains(reportAliases[scene] ?? scene) {
                        // Keep editable capture fixtures in the future as real policy uses the current device clock.
                        let futureStart = Int64(ceil((Date().timeIntervalSince1970 + 86400) / 900) * 900 * 1000)
                        app.launchArguments += ["-GroupCaptureActivityStart", String(futureStart)]
                    }
                    app.launch()
                    let identity = app.descendants(matching: .any)["group_capture_identity"].firstMatch
                    guard identity.waitForExistence(timeout: 20) else { throw CaptureError.missing("capture identity") }
                    let expected = "scene=\(scene);canonical=\(canonicalHash);adapter=\(adapterHash);referenceTime=1791864000000;transport=strict-offline;source=\(sourceHash);ready=true"
                    let predicate = NSPredicate(format: "value == %@", expected)
                    guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: identity)], timeout: 15) == .completed else { throw CaptureError.invalidMetadata(identity.value as? String ?? "") }
                    let frame = app.windows.firstMatch.frame
                    guard abs(frame.width - 402) < 1, abs(frame.height - 874) < 1 else { throw CaptureError.invalidMetadata("Expected iPhone 17 Pro 402×874 pt, got \(frame)") }
                    if realActivityNavigation == "true", ["activity", "activity-edit", "activity-registration", "lineup", "lineup-review", "lineup-frozen", "lineup-correction", "result-frozen", "activity-cancel", "activity-abandon", "result-abandon", "registration-draft", "lineup-clock", "lineup-finish", "lineup-conflict-reload", "activity-conflict"].contains(reportAliases[scene] ?? scene) {
                        try require("group_tab_1", app)
                        try tap("group_activity_status_compare_activity_multi", app)
                    }
                    try prepare(scene, app)
                    let preparedScene = reportAliases[scene] ?? scene
                    if ["request-reject", "dialog-restore"].contains(preparedScene) {
                        let metadata: [String: Any] = ["scene": scene, "platform": "ios", "captureStatus": "removed", "reason": "This action executes directly; its former confirmation overlay no longer exists.", "runtimeStateEvidence": ["directWriteAttempt": "verified through the strict-offline write rejection", "confirmationOverlay": "absent"], "sourceSHA256": sourceHash, "expectedState": expectedState(for: scene)]
                        let proof = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
                        proof.name = "metadata-" + scene; proof.lifetime = .keepAlways; activity.add(proof)
                        return
                    }
                    if ["dialog-report", "visitor-report", "dialog-temporary-member"].contains(preparedScene) {
                        let sheetBar = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }.last
                        guard let sheetBar, sheetBar.frame.minY > 180 else {
                            throw CaptureError.missing("content-sized sheet starts too close to full height")
                        }
                    }
                    if ["activity-create", "activity-edit"].contains(scene) {
                        try scrollActivityForm(app)
                        let note = element("group_activity_note", app)
                        let save = app.buttons["group_activity_save"].firstMatch
                        guard note.exists && note.isHittable && note.frame.maxY <= save.frame.minY - 8 else {
                            throw CaptureError.missing("complete note field above the fixed activity footer")
                        }
                    }
                    // UIKit sheet transitions can outlive XCTest's idle signal.
                    Thread.sleep(forTimeInterval: 0.8)
                    let childScenes: Set<String> = ["activity", "activity-create", "activity-edit", "lineup", "lineup-review", "lineup-direct", "result", "result-launch", "result-rules", "result-detail", "member-results", "share", "notices", "dialog-edit-group", "inventory-edit-group"]
                    if childScenes.contains(scene), app.tabBars.allElementsBoundByIndex.contains(where: { $0.exists && $0.isHittable && $0.frame.intersects(frame) }) {
                        throw CaptureError.missing("production group child still shows the main tab bar")
                    }
                    if scene == "activity-create" {
                        guard !app.buttons["多场比赛"].exists && !app.buttons["单场比赛"].exists else { throw CaptureError.missing("obsolete activity mode selector") }
                    }
                    let hierarchyAtCapture = app.debugDescription
                    let capturedScreen = XCUIScreen.main.screenshot()
                    // 检查真实截图的页边背景，避免夹具锁定浅色却记录为深色。
                    let sourceImage = try XCTUnwrap(capturedScreen.image.cgImage)
                    // Nested sheets add a second dim layer outside the card. Verify the visible
                    // dialog surface instead of misclassifying that dark scrim as a dark theme.
                    let dialog = app.descendants(matching: .any)["group_alert"].firstMatch
                    let scale = CGFloat(sourceImage.width) / frame.width
                    let samplePoint = dialog.exists
                        ? CGPoint(x: dialog.frame.midX * scale, y: (dialog.frame.minY + 8) * scale)
                        : CGPoint(x: 2, y: sourceImage.height / 2)
                    let sample = try XCTUnwrap(sourceImage.cropping(to: CGRect(x: samplePoint.x, y: samplePoint.y, width: 1, height: 1)))
                    var pixel = [UInt8](repeating: 0, count: 4)
                    try pixel.withUnsafeMutableBytes { bytes in
                        let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    }
                    let backgroundBrightness = Double(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / (3 * 255)
                    guard appearance == "Dark" ? backgroundBrightness < 0.5 : backgroundBrightness > 0.5 else {
                        throw CaptureError.invalidMetadata("Rendered theme differs from requested appearance")
                    }
                    let captureAtUTC = ISO8601DateFormatter().string(from: Date())
                    let screenshot = XCTAttachment(screenshot: capturedScreen)
                    screenshot.name = "capture-\(scene)"; screenshot.lifetime = .keepAlways
                    activity.add(screenshot)
                    let metadata: [String: Any] = ["scene": scene, "platform": "ios", "device": "iPhone 17 Pro", "logicalWidth": frame.width, "logicalHeight": frame.height, "canonicalSHA256": canonicalHash, "adapterSHA256": adapterHash, "referenceTime": 1791864000000, "language": "zh-Hans", "appearance": appearance.lowercased(), "backgroundBrightness": backgroundBrightness, "orientation": "portrait", "captureStatus": "captured", "captureAtUTC": captureAtUTC, "sourceSnapshotAtUTC": sourceSnapshotAtUTC, "sourceSHA256": sourceHash, "metadataSchemaVersion": 2, "reportCaseId": scene, "expectedState": expectedState(for: scene), "runtimeStateEvidence": ["preparationAssertions": "passed", "crossPlatformComparisonReview": "pending"], "nativeDifference": nativeDifferences[scene] ?? "", "transport": "strict-offline", "captureEntryPath": environment["TEST_RUNNER_GROUP_CAPTURE_REAL_ACTIVITY_NAVIGATION"] == "true" ? "Activity scenes navigate through the production group activity list; other scenes use isolated production views" : "isolated production scene", "transitionSettleSeconds": 0.8, "productionHierarchy": hierarchyAtCapture]
                    let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                    let proof = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    proof.name = "metadata-\(scene)"; proof.lifetime = .keepAlways; activity.add(proof)
                } catch {
                    XCTFail("Scene \(scene) was not captured: \(error)")
                    let diagnostic = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    diagnostic.name = "diagnostic-\(scene)"; diagnostic.lifetime = .keepAlways; activity.add(diagnostic)
                    let proof = XCTAttachment(string: "scene=\(scene)\nstatus=failed\nerror=\(error)\n\(app.debugDescription)")
                    proof.name = "failed-\(scene)"; proof.lifetime = .keepAlways; activity.add(proof)
                }
            }
        }
    }

    private func expectedState(for reportScene: String) -> [String: Any] {
        let scenario = reportAliases[reportScene] ?? reportScene
        var state: [String: Any] = ["nativeScenario": scenario, "specificationStatus": "expected-fixture-and-control-target; review-runtime-hierarchy-before-comparing"]
        switch scenario {
        case "training-notices": state.merge(["target": "GroupTrainingNoticeInbox", "actor": "student", "notifications": 0, "groupNo": "82603161"]) { _, new in new }
        case "registration-draft": state.merge(["target": "native direct return after discarding local edits", "temporaryMemberID": "seed_m_seed_group_badminton_5", "pendingAdd": true]) { _, new in new }
        case "lineup-correction": state.merge(["activityStatus": "completed", "sessionStatus": "cancelled", "resultId": "", "canManage": false, "canCorrectResult": true, "gameState": "submitted"]) { _, new in new }
        case "activity-abandon": state.merge(["target": "single-activity release confirmation", "format": "singles", "registeredCount": 2, "capacity": 6, "nativeResumeScore": "7:4"]) { _, new in new }
        case "result-abandon": state.merge(["target": "multi-activity release confirmation", "format": "doubles", "nativeResumeScore": "7:4"]) { _, new in new }
        case "request-approve", "request-reject": state.merge(["groupNo": "82603164", "members": 1, "applicant": "林晨", "canonicalPeerGroupPreserved": true, "confirmationOverlay": scenario == "request-approve" ? "present" : "removed"]) { _, new in new }
        case "dialog-restore": state.merge(["confirmationOverlay": "removed", "action": "restore directly"]) { _, new in new }
        case "result-void-confirmed": state.merge(["resultStatus": "confirmed", "resultRevision": 2, "confirmationMode": "owner_authority", "confirmedMatchCount": 2, "monthMatchCount": 2, "activeMembers30d": 6]) { _, new in new }
        case "student", "training-leave": state.merge(["actor": "student", "sessionSides": ["B", "A"], "mySessionCount": 2]) { _, new in new }
        default: break
        }
        let resultTargets = ["result-detail": "seed_result_1", "result-detail-confirmed": "seed_result_1", "result-detail-pending": "seed_result_2", "result-detail-voided": "seed_result_1", "result-authority": "compare_authority_result", "result-normal": "compare_normal_result", "result-void-pending": "compare_authority_result", "result-void-confirmed": "compare_authority_result", "result-actions": "seed_result_2", "result-void-list": "seed_result_2"]
        if let resultID = resultTargets[scenario] { state["targetResultID"] = resultID }
        return state
    }

    private func element(_ key: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[key].firstMatch
    }
    private func actionElement(_ key: String, _ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[key].firstMatch
        if button.exists { return button }
        if key.hasPrefix("group_") { return element(key, app) }
        return button
    }
    private func scrollActive(_ app: XCUIApplication, up: Bool = true) throws {
        let window = app.windows.firstMatch.frame
        let navBottom = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && $0.frame.intersects(window) }.map { $0.frame.maxY }.max() ?? window.minY
        let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 12 : window.maxY - 100
        let viewport = CGRect(x: window.minX, y: navBottom + 12, width: window.width, height: max(0, keyboardTop - navBottom - 12))
        // SwiftUI Form may expose a Table or a container whose own hit-test is false while rows are tappable.
        let containers = Array(app.tables.allElementsBoundByIndex.reversed()) + Array(app.collectionViews.allElementsBoundByIndex.reversed()) + Array(app.scrollViews.allElementsBoundByIndex.reversed())
        let container = containers.first { $0.exists && $0.frame.intersection(viewport).height > 90 && $0.frame.intersection(viewport).width > 100 }
        // A short native List can have no scroll container. Public dragging still proves its footer remains pinned.
        let visible = container?.frame.intersection(viewport) ?? viewport
        guard !visible.isNull, visible.height > 60 else { throw CaptureError.missing("visible scroll area") }
        let startY = visible.minY + visible.height * (up ? 0.78 : 0.22)
        let endY = visible.minY + visible.height * (up ? 0.22 : 0.78)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: visible.midX, dy: startY)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: visible.midX, dy: endY)))
    }
    private func scrollActivityForm(_ app: XCUIApplication) throws {
        let window = app.windows.firstMatch.frame
        let top = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && $0.frame.intersects(window) }.map { $0.frame.maxY }.max() ?? window.minY
        let save = app.buttons["group_activity_save"].firstMatch
        let bottom = save.exists ? save.frame.minY - 16 : window.maxY - 100
        let viewport = CGRect(x: window.minX, y: top + 8, width: window.width, height: max(0, bottom - top - 8))
        let candidates = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.frame.intersection(viewport).height > 120 }
        guard let container = candidates.max(by: { a, b in
            let x = a.frame.intersection(viewport), y = b.frame.intersection(viewport)
            return x.width * x.height < y.width * y.height
        }) else { throw CaptureError.missing("native activity form ScrollView") }
        let area = container.frame.intersection(viewport)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: area.midX, dy: area.minY + area.height * 0.8))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: area.midX, dy: area.minY + area.height * 0.2)))
    }
    private func locate(_ key: String, _ app: XCUIApplication, action: Bool, scroll: Bool) throws -> XCUIElement {
        for attempt in 0..<(scroll ? 9 : 2) {
            let item = action ? actionElement(key, app) : element(key, app)
            if item.exists && (!action || item.isHittable) { return item }
            if attempt == 0, item.waitForExistence(timeout: 1), !action || item.isHittable { return item }
            if scroll && attempt < 8 { try scrollActive(app) }
        }
        throw CaptureError.missing(key)
    }
    private func require(_ key: String, _ app: XCUIApplication, scroll: Bool = false) throws {
        _ = try locate(key, app, action: false, scroll: scroll)
    }
    private func tap(_ key: String, _ app: XCUIApplication) throws {
        try locate(key, app, action: true, scroll: true).tap()
    }
    private func requireFullyVisibleAction(_ key: String, _ app: XCUIApplication) throws {
        for attempt in 0..<9 {
            let item = actionElement(key, app)
            let window = app.windows.firstMatch.frame
            let top = (app.navigationBars.allElementsBoundByIndex.filter { $0.exists && $0.frame.intersects(window) }.map { $0.frame.maxY }.max() ?? window.minY) + 8
            var bottom = window.maxY - 24
            for bar in app.tabBars.allElementsBoundByIndex where bar.exists && bar.frame.intersects(window) { bottom = min(bottom, bar.frame.minY - 8) }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 8) }
            let viewport = CGRect(x: window.minX + 8, y: top, width: window.width - 16, height: max(0, bottom - top))
            if item.exists && item.isEnabled && item.isHittable && viewport.contains(item.frame) { return }
            if attempt < 8 { try scrollActive(app, up: !item.exists || item.frame.minY >= viewport.minY) }
        }
        throw CaptureError.missing("fully visible enabled action: " + key)
    }
    private func groupAlertContainer(_ app: XCUIApplication) -> XCUIElement {
        let panel = app.descendants(matching: .any)["group_alert"].firstMatch
        if panel.waitForExistence(timeout: 1) { return panel }
        return app.alerts.firstMatch
    }
    private func requireSystemAlertAction(_ label: String, _ app: XCUIApplication) throws {
        let alert = groupAlertContainer(app)
        guard alert.waitForExistence(timeout: 3), alert.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch.isEnabled, alert.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch.isHittable else {
            throw CaptureError.missing("system alert confirmation: " + label)
        }
        guard alert.buttons.matching(NSPredicate(format: "label == %@", "取消")).firstMatch.exists else { throw CaptureError.missing("system alert cancellation") }
    }
    private func verifyResultConfirmation(_ app: XCUIApplication) throws {
        try requireSystemAlertAction("确认结果", app)
        let texts = groupAlertContainer(app).staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
        guard texts.contains(":"), texts.contains("计入") && texts.contains("战绩"), texts.count > 50 else { throw CaptureError.missing("complete result confirmation explanation: " + texts) }
    }
    private func requireConfirmationAction(_ label: String, _ app: XCUIApplication) throws {
        var sheet = app.sheets.firstMatch
        if !sheet.waitForExistence(timeout: 3) { sheet = groupAlertContainer(app) }
        guard sheet.exists else { throw CaptureError.missing("native confirmation sheet or alert: " + label) }
        let action = sheet.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        guard action.waitForExistence(timeout: 2), action.isEnabled, action.isHittable else { throw CaptureError.missing("native confirmation action: " + label) }
    }
    private func keyboardClosed(_ app: XCUIApplication) throws {
        let predicate = NSPredicate(format: "exists == false")
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.keyboards.firstMatch)], timeout: 4) == .completed else { throw CaptureError.missing("preview still has keyboard open") }
    }
    private func validateScheduleEditor(_ app: XCUIApplication, activity: Bool = false) throws {
        try require(activity ? "活动排阵" : "训练排期", app)
        _ = try locate("group_training_publish", app, action: true, scroll: true)
        // Keep normal editor screenshots at the top after proving its real CTA is reachable.
        for _ in 0..<8 { try scrollActive(app, up: false) }
    }
    private func openManagement(_ key: String, _ app: XCUIApplication) throws {
        try tap("小组管理", app); try tap(key, app)
    }
    private func openManual(_ app: XCUIApplication) throws {
        try tap("group_overview_addResult", app); try require("group_match_submit", app, scroll: true); try restoreTop(app)
    }
    private func openActivityMatches(_ app: XCUIApplication) throws {
        if actionElement("group_activity_lineup_open", app).exists { try tap("group_activity_lineup_open", app) }
    }
    private func openActivityLineupEditor(_ app: XCUIApplication) throws {
        try openActivityMatches(app)
        if actionElement("group_activity_lineup_edit", app).exists { try tap("group_activity_lineup_edit", app) }
        try require("group_training_publish", app)
    }
    private func openTrainingEditor(_ app: XCUIApplication) throws {
        try tap("group_training_plan_menu_compare_training_plan", app); try tap("修改排期", app)
        try require("训练排期", app)
    }
    private func restoreTop(_ app: XCUIApplication) throws { for _ in 0..<8 { try scrollActive(app, up: false) } }
    private func openDatePicker(_ key: String, _ app: XCUIApplication, time: Bool = false) throws {
        let picker = try locate(key, app, action: false, scroll: true)
        let direct = app.buttons[key].firstMatch
        if direct.exists {
            try requireFullyVisibleAction(key, app); direct.tap()
        } else {
            let buttons = picker.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            if let button = time ? buttons.last : buttons.first { button.tap() } else { picker.tap() }
        }
        let predicate = NSPredicate { _, _ in
            app.pickerWheels.firstMatch.exists || app.datePickers.allElementsBoundByIndex.contains { $0.exists && $0.frame.height > 90 } || app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*[0-9]{4}年[0-9]{1,2}月.*")).firstMatch.exists
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 4) == .completed else { throw CaptureError.missing("actual native date/time picker " + key) }
    }
    private func setDetails(_ app: XCUIApplication) throws {
        try openManual(app)
        try tap("group_result_sets_toggle", app)
        if !element("group_detail_0_A", app).exists { try tap("group_result_add_set", app) }
        try require("group_detail_0_A", app, scroll: true)
        try require("group_detail_0_B", app, scroll: true)
    }
    private func prepare(_ reportScene: String, _ app: XCUIApplication) throws {
        let scene = reportAliases[reportScene] ?? reportScene
        switch scene {
        case "archived-list": try tap("group_archived_entry", app); try require("已归档小组", app)
        case "activity-registration": try tap("group_activity_registration_manage", app); try require("group_registration_save", app)
        case "lineup-direct": try tap("group_activity_direct", app); try require("group_activity_direct_save", app)
        case "members-removed": try require("已离组成员", app); try require("group_tab_3", app)
        case "home": _ = try locate("home_groups", app, action: true, scroll: true)
        case "detail-failure":
            try require("无法加载小组", app); try require("重试", app)
            XCTAssertLessThan(app.buttons["group_tab_0"].frame.minY, 180, "Failure state keeps tabs beneath the navigation bar")
        case "create-approval-selected":
            try tap("group_create", app); try tap("group_create_policy", app); try tap("需要审批", app); try require("group_create_submit", app)
        case "visitor-report":
            try tap("group_join", app); app.textFields["group_number"].tap(); app.textFields["group_number"].typeText("82603162")
            try tap("group_keyboard_done", app); try require("group_preview_name", app); try keyboardClosed(app); try tap("group_join_preview_more", app); try tap("group_join_preview_report", app); try require("group_preview_report_submit", app)
        case "transfer-selected":
            try openManagement("转让组长", app)
            try tap("group_transfer_member_seed_m_seed_group_badminton_1", app)
            let selected = try locate("group_transfer_member_seed_m_seed_group_badminton_1", app, action: true, scroll: false)
            guard selected.isSelected else { throw CaptureError.missing("selected new owner 杨扬") }
            let confirm = try locate("group_management_submit", app, action: true, scroll: true)
            guard confirm.isEnabled else { throw CaptureError.missing("valid new owner confirmation") }
            confirm.tap(); try requireConfirmationAction("转让", app)
            try require("确定将组长身份转让给 杨扬？转让后你将成为普通成员。", app)
        case "member-actions", "member-rename", "member-remove":
            try tap("group_member_manage_seed_m_seed_group_badminton_5", app); try require("改名", app); try require("移除", app)
            if scene == "member-rename" { try tap("改名", app); try require("group_member_rename", app); try requireConfirmationAction("保存", app) }
            if scene == "member-remove" { try tap("移除", app); try requireConfirmationAction("移除", app) }
        case "request-approve", "request-reject":
            try require("林晨", app, scroll: true)
            let action = try locate(scene == "request-approve" ? "通过" : "拒绝", app, action: true, scroll: true)
            guard action.isEnabled && action.isHittable else { throw CaptureError.missing("actual pending request action") }
            action.tap()
            if scene == "request-approve" {
                try requireConfirmationAction("通过", app)
                try require("林晨 将成为小组成员，可以看到活动与战绩。", app)
            } else {
                try require("Capture writes disabled: /compare_group_approval/join-requests/compare_join_request/reject", app, scroll: true)
                guard !groupAlertContainer(app).exists else { throw CaptureError.missing("reject must execute without a confirmation overlay") }
            }
        case "training-cancel":
            try tap("group_training_plan_menu_compare_training_plan", app); try tap("取消排期", app); try require("取消原因", app)
        case "training-leave": try tap("请假", app); try require("请假说明（选填，最多 100 字）", app)
        case "training-notices":
            try tap("group_training_notices", app)
            try require("group_training_notice_inbox", app); try require("group_training_notices_empty", app)
        case "lineup-frozen":
            try openActivityLineupEditor(app); try require("group_schedule_starts_compare_activity_session_1", app)
            guard !element("group_schedule_starts_compare_activity_session_1", app).isEnabled else { throw CaptureError.missing("frozen activity row") }
        case "lineup-correction":
            try openActivityMatches(app)
            try require("活动排阵", app)
            for label in ["补记赛果", "开始计分", "录入/补记结果"] {
                guard !app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch.exists else {
                    throw CaptureError.missing("cancelled session still exposes: " + label)
                }
            }
        case "result-frozen":
            try openActivityMatches(app)
            try tap("group_activity_frozen_manual_1", app); try require("group_seat_A1", app)
            let rules = try locate("group_match_rules_summary", app, action: true, scroll: true)
            guard !rules.isEnabled else { throw CaptureError.missing("frozen rules") }
            _ = try locate("group_match_submit", app, action: true, scroll: true)
            for _ in 0..<3 { try scrollActive(app, up: false) }
            try require("group_seat_A1", app)
        case "training-plan-frozen":
            try openTrainingEditor(app); try require("group_schedule_starts_compare_training_session_1", app)
            guard !element("group_schedule_starts_compare_training_session_1", app).isEnabled else { throw CaptureError.missing("frozen training row") }
        case "result-details-expansion": try setDetails(app)
        case "training-shift-preview":
            try openTrainingEditor(app); try tap("group_schedule_shift_compare_training_session_1", app); try require("顺延本场及后续场次", app); try require("保存", app)
        case "activity-date", "activity-deadline", "activity-place":
            try tap("发起活动", app); try require("group_activity_save", app)
            if scene != "activity-place" {
                try openDatePicker(scene == "activity-date" ? "group_activity_date" : "group_activity_closes", app)
                if scene == "activity-date" {
                    let mode = app.segmentedControls["group_date_time_mode"]
                    guard mode.waitForExistence(timeout: 3) else { throw CaptureError.missing("date/time mode") }
                    mode.buttons["时间"].tap()
                    guard app.pickerWheels.firstMatch.waitForExistence(timeout: 3) else { throw CaptureError.missing("editable time wheels") }
                    mode.buttons["日期"].tap()
                }
            }
            else {
                try tap("group_activity_place_picker", app)
                let alert = groupAlertContainer(app)
                guard alert.waitForExistence(timeout: 3), alert.buttons["取消"].exists else { throw CaptureError.missing("native saved-location dialog and cancellation") }
                let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
                guard message.contains("暂无常用地点"), message.contains("可在首页"), message.contains("选择常用地点") else { throw CaptureError.missing("complete empty saved-location explanation") }
            }
        case "result-date": try openManual(app); try openDatePicker("group_result_played_at", app)
        case "lineup-clock":
            try openActivityLineupEditor(app); try openDatePicker("group_schedule_starts_compare_activity_session_1", app, time: true)
            guard app.pickerWheels.firstMatch.waitForExistence(timeout: 3) else { throw CaptureError.missing("lineup time wheels, not calendar") }
        case "training-date", "training-clock":
            try openTrainingEditor(app)
            try openDatePicker(scene == "training-date" ? "group_schedule_date" : "group_schedule_starts_compare_training_session_1", app, time: scene == "training-clock")
        case "activity-cancel":
            try tap("group_activity_more", app); try tap("取消活动", app)
            let reason = groupAlertContainer(app).textFields.firstMatch
            guard reason.waitForExistence(timeout: 3) else { throw CaptureError.missing("actual cancel-activity reason field") }
            reason.tap(); reason.typeText("场馆临时关闭")
            guard groupAlertContainer(app).buttons["group_activity_cancel_action"].firstMatch.isEnabled else { throw CaptureError.missing("cancel activity confirmation") }
        case "activity-abandon":
            try require("单场计分续局", app); try require("group_activity_registration_count", app)
            _ = try locate("继续本机计分", app, action: true, scroll: true)
            try tap("group_activity_abandon_compare_capture_single_game", app); try requireConfirmationAction("放弃本场", app)
        case "result-abandon":
            try openActivityMatches(app)
            _ = try locate("继续本机计分", app, action: true, scroll: true)
            try tap("group_activity_abandon_compare_frozen_activity_game", app); try requireConfirmationAction("放弃本场", app)
        case "registration-draft":
            try tap("group_activity_registration_manage", app)
            let control = try locate("group_registration_member_seed_m_seed_group_badminton_5", app, action: true, scroll: true)
            guard control.isEnabled && control.isHittable && !control.isSelected else { throw CaptureError.missing("unregistered temporary member row") }
            control.tap()
            guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: control)], timeout: 3) == .completed else { throw CaptureError.missing("pending temporary member registration") }
            let save = try locate("group_registration_save", app, action: true, scroll: false)
            guard save.isEnabled else { throw CaptureError.missing("dirty registration save") }
            try require("待报名", app)
            try tap("group_registration_close", app)
            try require("group_activity_registration_manage", app)
            guard !groupAlertContainer(app).exists else { throw CaptureError.missing("registration should exit without confirmation") }
            try tap("group_activity_registration_manage", app)
            let reopened = try locate("group_registration_member_seed_m_seed_group_badminton_5", app, action: true, scroll: true)
            guard !reopened.isSelected else { throw CaptureError.missing("unsubmitted registration was retained after exit") }
            try tap("group_registration_close", app)
            try require("group_activity_registration_manage", app)
        case "result-authority", "result-normal", "result-actions", "result-void-pending", "result-void-confirmed", "result-void-list":
            try require("比赛详情", app)
            if scene == "result-authority" || scene == "result-normal" {
                let entry = "确认结果"
                try tap(entry, app)
                try verifyResultConfirmation(app)
                groupAlertContainer(app).buttons["取消"].tap()
                try requireFullyVisibleAction(entry, app)
                try tap(entry, app)
                try verifyResultConfirmation(app)
            }
            if scene == "result-actions" { try requireFullyVisibleAction("确认结果", app) }
            if scene.hasPrefix("result-void") {
                guard !app.textFields["作废原因"].exists else { throw CaptureError.missing("reason field appeared before tapping Void") }
                try tap("作废", app)
                let alert = groupAlertContainer(app)
                guard alert.waitForExistence(timeout: 3), alert.textFields.firstMatch.exists, alert.buttons["取消"].exists else { throw CaptureError.missing("void reason dialog with cancellation") }
                guard !alert.buttons["作废"].isEnabled else { throw CaptureError.missing("empty reason enabled void submission") }
            }
        case "records-authority":
            try tap("确认结果", app); try verifyResultConfirmation(app)
            groupAlertContainer(app).buttons["取消"].tap()
            try tap("确认结果", app); try verifyResultConfirmation(app)
        case "upload-discard": try tap("放弃上传", app); try requireConfirmationAction("放弃上传", app)
        case "lineup-finish":
            try openActivityMatches(app)
            let button = try locate("group_activity_finish", app, action: true, scroll: true)
            guard button.isEnabled else { throw CaptureError.missing("actual finish activity control") }
        case "result-draft-return":
            try openManual(app)
            try requireFullyVisibleAction("group_quick_score_2_0", app)
            try tap("group_quick_score_2_0", app)
            guard actionElement("group_quick_score_2_0", app).isSelected else { throw CaptureError.missing("selected 2:0 score before actual return") }
            let navigation = app.navigationBars.firstMatch
            guard navigation.exists, navigation.buttons.firstMatch.exists else { throw CaptureError.missing("production result back action") }
            navigation.buttons.firstMatch.tap()
            try require("group_overview_addResult", app)
            try openManual(app)
            try requireFullyVisibleAction("group_quick_score_2_0", app)
        case "group-conflict":
            try openManagement("修改小组资料", app)
            try tap("group_edit_policy", app); try tap("直接加入", app)
            try tap("group_management_submit", app)
            try require("数据已变更，请刷新并核对后重试。", app, scroll: true)
            try require("group_management_submit", app)
            guard !app.buttons["加载最新版本"].exists, !app.buttons["继续编辑本地版本"].exists else { throw CaptureError.missing("removed profile version comparison remains visible") }
        case "activity-conflict":
            try tap("group_activity_more", app); try tap("group_activity_edit", app); try tap("group_activity_save", app)
            try require("数据已变更，请刷新并核对后重试。", app, scroll: true)
            try require("group_activity_save", app)
            guard !app.buttons["加载最新版本"].exists, !app.buttons["继续编辑本地版本"].exists else { throw CaptureError.missing("removed activity version comparison remains visible") }
        case "training-conflict", "lineup-conflict-reload":
            if scene == "training-conflict" { try openTrainingEditor(app) } else { try openActivityLineupEditor(app) }
            try tap("group_training_publish", app)
            try tap("加载最新版本", app)
            if scene == "training-conflict" {
                // Public reload confirmation reads the newer snapshot, then leaves the real conflict review open.
                let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "加载最新版本"))
                    .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
                guard let confirmation = confirmations.last else { throw CaptureError.missing("reload confirm") }; confirmation.tap()
                try require("最新版本", app, scroll: true)
                try require("保留我的修改", app, scroll: true); app.swipeUp()
            } else {
                try requireConfirmationAction("加载最新版本", app)
                try require("放弃未保存的场次安排，加载最新版本？", app)
            }
        case "list":
            try require("group_card_seed_group_badminton", app)
            let create = app.buttons["group_create"], join = app.buttons["group_join"]
            guard create.isHittable, join.isHittable, create.frame.minY > app.windows.firstMatch.frame.height * 0.75 else { throw CaptureError.missing("sticky group footer") }
            let y = create.frame.minY
            try scrollActive(app)
            guard abs(create.frame.minY - y) < 1 else { throw CaptureError.missing("group footer moved with list") }
            try scrollActive(app, up: false)
            let card = element("group_card_seed_group_badminton", app)
            let memberCountVisible = card.label.contains("6 人") || card.descendants(matching: .staticText).allElementsBoundByIndex.contains { $0.label.contains("6 人") }
            guard memberCountVisible else { throw CaptureError.missing("canonical badminton member count") }

        case "create": try tap("group_create", app); try require("group_create_submit", app)
        case "join", "join-approval", "join-empty":
            try tap("group_join", app); try require("group_number", app)
            if scene != "join-empty" {
                app.textFields["group_number"].tap(); app.textFields["group_number"].typeText("82603162")
                if scene == "join-approval" { try tap("group_keyboard_done", app); try keyboardClosed(app) }
                if scene != "join-approval" { try tap("group_keyboard_done", app) }; try require("group_preview_name", app)
                try keyboardClosed(app)
                guard app.staticTexts["滨江周末球友"].firstMatch.exists else { throw CaptureError.missing("canonical visitor preview") }
                if scene == "join-approval" {
                    app.textFields["group_join_message"].tap()
                    guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { throw CaptureError.missing("message keyboard") }
                    try tap("group_keyboard_done", app); try keyboardClosed(app)
                }
            }
        case "detail-overview", "detail-admin", "detail-member", "detail-archived", "detail-dissolving", "detail-offline", "detail-empty": try require("group_tab_0", app)
        case "detail-activities": try require("group_tab_1", app); try require("周六双打友谊赛", app)
        case "detail-records": try require("group_record_filter", app)
        case "detail-records-doubles": try tap("双打", app); try require("group_record_filter", app)
        case "detail-members": try require("group_add_temporary", app)
        case "admin":
            try tap("小组管理", app); try require("修改小组资料", app)
            guard !app.descendants(matching: .any)["group_menu_push_settings"].firstMatch.exists,
                  !app.buttons["通知设置"].exists else {
                throw CaptureError.missing("management menu still contains notification settings")
            }
        case "activity": try require("周六双打友谊赛", app); try require("滨江体育中心", app); try require("group_activity_registration_count", app); try require("双打", app)
        case "activity-create": try tap("发起活动", app); try require("group_activity_save", app)
        case "activity-edit": try tap("group_activity_more", app); try tap("group_activity_edit", app); try require("group_activity_save", app)
        case "lineup", "lineup-review":
            try openActivityLineupEditor(app)
            try validateScheduleEditor(app, activity: true)
        case "result", "result-rules", "result-member-picker":
            try openManual(app)
            if scene == "result-rules" { try tap("group_match_rules_summary", app); try require("项目默认", app, scroll: true) }
            if scene == "result-member-picker" { try tap("group_seat_A1", app); try require("group_member_pick_seed_m_seed_group_badminton_0", app) }
        case "result-launch": try tap("group_overview_start", app); try require("group_match_submit", app)
        case "result-detail", "result-detail-pending", "result-detail-confirmed", "result-detail-voided":
            try require("比赛详情", app)
            try require(scene == "result-detail-pending" ? "待确认" : scene == "result-detail-voided" ? "已作废" : "比赛信息", app)
            try require(scene == "result-detail-pending" ? "2 : 0" : "2 : 1", app)
        case "member-results": try require("我", app)
        case "share", "share-readonly": try require("group_qr", app); try require("小组号 82603158", app)
        case "notices":
            try tap("group_detail_notices", app)
            try require("周六双打友谊赛", app)
            try require("group_notices_push_settings", app)
            try tap("group_notices_push_settings", app)
            try require("通知设置", app)
            let settingsBack = app.navigationBars["通知设置"].buttons["BackButton"]
            guard settingsBack.exists && settingsBack.isHittable else { throw CaptureError.missing("native back from notification settings") }
            settingsBack.tap()
            try require("group_notices_mark_all", app)
            let markAll = try locate("group_notices_mark_all", app, action: true, scroll: false)
            guard markAll.frame.width >= 32, markAll.frame.height >= 32 else {
                throw CaptureError.missing("visible mark-all toolbar button")
            }
        case "coach", "student": try require("训练排期", app); try require("滨江体育中心 2 号馆", app)
        case "training-plan-create": try tap("group_training_add", app); try validateScheduleEditor(app)
        case "training-plan", "training-plan-edit", "training-plan-review":
            try tap("group_training_plan_menu_compare_training_plan", app); try tap("修改排期", app)
            try validateScheduleEditor(app)
        case "dialog-edit-group": try openManagement("修改小组资料", app); try require("group_management_submit", app)
        case "dialog-transfer-owner":
            try openManagement("转让组长", app)
            try require("group_transfer_member_seed_m_seed_group_badminton_1", app)
        case "dialog-report": try openManagement("举报小组", app); try require("提交", app)
        case "dialog-dissolve": try openManagement("解散小组", app); try requireSystemAlertAction("解散小组", app)
        case "dialog-archive": try openManagement("归档", app); try requireSystemAlertAction("归档", app)
        case "dialog-restore":
            try openManagement("恢复", app)
            try require("Capture writes disabled: /seed_group_badminton/restore", app)
            guard !groupAlertContainer(app).exists else { throw CaptureError.missing("restore must execute without a confirmation overlay") }
        case "dialog-leave": try openManagement("退出小组", app); try requireSystemAlertAction("退出小组", app)
        case "dialog-temporary-member", "dialog-common-name-import":
            try tap("group_add_temporary", app); try require("group_temporary_names", app)
            if scene == "dialog-common-name-import" {
                try tap("常用名称", app); try require("林丹", app); try require("谌龙", app)
                let back = app.navigationBars["常用名称"].buttons["BackButton"]
                guard back.exists && back.isHittable else { throw CaptureError.missing("native back to temporary-member sheet") }
                back.tap(); try require("group_temporary_names", app)
                try tap("group_temporary_common_names", app); try require("林丹", app)
            }
        case "dialog-rename-member": try tap("group_member_manage_seed_m_seed_group_badminton_5", app); try tap("改名", app); try require("group_member_operation_submit", app)
        default: throw CaptureError.unsupported(scene)
        }
    }
}
