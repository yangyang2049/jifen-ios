import XCTest

final class GroupRedesignUITests: XCTestCase {
    func testInvitationColdAndWarmOpenPrefillsJoinPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-national_day_2026_10_autopopup_count", "99"]
        app.open(try XCTUnwrap(URL(string: "https://jifenqi.com/groups/join?groupNo=72856000")))
        let number = app.textFields["group_number"]
        XCTAssertTrue(number.waitForExistence(timeout: 15))
        XCTAssertEqual(number.value as? String, "72856000")
        capture(app, "group-invitation-cold-open")
        app.open(try XCTUnwrap(URL(string: "https://iscoreboard.live/groups/join?groupNo=123456")))
        let updated = NSPredicate(format: "value == %@", "123456")
        expectation(for: updated, evaluatedWith: app.textFields["group_number"])
        waitForExpectations(timeout: 15)
        capture(app, "group-invitation-warm-open")
    }

    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }
    private func openGroup(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-UITestGroupsFixture", "-national_day_2026_10_autopopup_count", "99"] + extra
        app.launch()
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

    func testMultiActivityOpensNativeLineupAndReviewWithoutSubmitting() {
        let app = openGroup(["-UITestGroupsMulti"])
        app.staticTexts["周末羽毛球"].firstMatch.tap()
        let session = app.descendants(matching: .any)["group_activity_session_1"].firstMatch
        for _ in 0..<8 where !session.exists { app.swipeUp() }
        XCTAssertTrue(session.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["编排场次"].tap()
        let review = app.buttons["group_training_publish"]
        for _ in 0..<6 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isHittable, app.debugDescription)
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.buttons["group_schedule_confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group_schedule_confirm"].isEnabled)
        capture(app, "groups-native-lineup-review")
    }
    func testNativeMemberSearchAndTemporaryBatchForm() {
        let app = openGroup()
        app.buttons["group_tab_3"].tap()
        let search = app.textFields["group_member_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("丙")
        XCTAssertTrue(app.staticTexts["丙"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["丁"].firstMatch.exists)
        capture(app, "groups-member-search")
    }
    func testNotificationInboxHasUnreadActivitySnapshot() {
        let app = openGroup()
        app.navigationBars.buttons.firstMatch.tap()
        let notifications = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "通知")).firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 5)); notifications.tap()
        XCTAssertTrue(app.staticTexts["周末羽毛球已改期"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["场馆调整"].exists)
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
        let form = app.collectionViews.firstMatch
        let navigationBottom = app.navigationBars["补记比赛"].frame.maxY
        for _ in 0..<5 where !firstSeat.isHittable || firstSeat.frame.minY < navigationBottom { form.swipeDown() }
        for (seat, member) in [("A1", "ui-a"), ("B1", "ui-b")] {
            let slot = app.descendants(matching: .any)["group_seat_" + seat].firstMatch
            for _ in 0..<4 where !slot.isHittable || slot.frame.minY < navigationBottom { form.swipeDown() }
            XCTAssertTrue(slot.isHittable, app.debugDescription); slot.tap()
            let player = app.buttons["group_member_pick_" + member]
            XCTAssertTrue(player.waitForExistence(timeout: 5), app.debugDescription); player.tap()
        }
        for (id, score) in [("group_score_A", "2"), ("group_score_B", "0")] {
            let field = app.textFields[id]
            for _ in 0..<5 where !field.isHittable || (app.keyboards.firstMatch.exists && field.frame.maxY >= app.keyboards.firstMatch.frame.minY) { form.swipeUp() }
            field.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3)); field.typeText(score)
        }
        for _ in 0..<3 where !submit.isHittable { app.swipeUp() }
        XCTAssertTrue(submit.isEnabled); capture(app, "groups-native-manual-valid-seats")
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
        "activity-registration-draft-discard": "Native registration Form and discard confirmation with local pending selections.",
        "inventory-registration-draft-discard": "Native registration Form and discard confirmation with local pending selections.",
        "inventory-activity-common-places": "Existing native CommonPlacePickerView with no saved local places in this fixture.",
        "lineup-correction": "Completed activity forbids reopening the lineup editor; native activity page exposes the corrective past-match action.",
        "inventory-member-actions": "Native member settings Form contains rename/admin/remove actions rather than a member action menu.",
        "inventory-result-actions": "Native result detail Form contains details and void actions rather than a record card menu.",
        "inventory-transfer-confirm": "Native transfer Form shows a selected member and explanatory hint; no extra pre-submit confirmation.",
        "inventory-dissolve-confirm": "Native management action Form provides explanation and final Save action.",
        "inventory-archive-confirm": "Native management action Form provides explanation and final Save action.",
        "inventory-leave-group-confirm": "Native management action Form provides explanation and final Save action.",
        "inventory-approve-join-confirm": "Native pending-request row exposes direct Approve action; no extra confirmation.",
        "inventory-reject-join-confirm": "Native pending-request row exposes direct Reject action; no extra confirmation.",
        "inventory-result-authority-confirm-detail": "Native result Form exposes authority confirmation directly; no extra confirmation dialog.",
        "inventory-result-normal-confirm-detail": "Native result Form exposes normal confirmation directly; no extra confirmation dialog.",
        "inventory-result-void-detail-pending": "Native result Form requires an inline void reason and final void action.",
        "inventory-result-void-detail-confirmed": "Native result Form requires an inline void reason and final void action.",
        "inventory-result-void-list": "Native record list navigates to result detail; void action and reason are shown there.",
        "inventory-result-save-draft-return": "Native editor auto-persists changes; capture closes and reopens the editor to prove the retained draft, without an invented modal.",
        "inventory-result-abandon": "Native release confirmation lives on activity detail, then unlocks the corresponding result flow.",
        "inventory-lineup-finish": "Native activity detail exposes Finish directly for terminal sessions; no extra pre-submit modal.",
    ]
    private let baseline = ["list", "create", "join", "join-approval", "detail-overview", "detail-activities", "detail-records", "detail-records-doubles", "detail-members", "admin", "activity", "activity-create", "lineup", "result", "result-launch", "result-detail", "member-results", "share", "notices", "coach", "student", "training-plan", "dialog-edit-group", "dialog-report", "dialog-transfer-owner", "dialog-dissolve", "dialog-temporary-member", "dialog-common-name-import"]

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testCaptureCanonicalPhoneScenes() throws {
        let environment = ProcessInfo.processInfo.environment
        let sourceHash = environment["GROUP_CAPTURE_SOURCE_HASH"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_SOURCE_HASH"] ?? ""
        let sourceSnapshotAtUTC = environment["GROUP_CAPTURE_SOURCE_AT_UTC"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_SOURCE_AT_UTC"] ?? ""
        guard sourceHash.count == 64, !sourceSnapshotAtUTC.isEmpty else { throw CaptureError.invalidMetadata("Runner source snapshot metadata missing") }
        let supplied = environment["GROUP_CAPTURE_SCENES"] ?? environment["TEST_RUNNER_GROUP_CAPTURE_SCENES"]
        let scenes = supplied?.split(separator: ",").map(String.init) ?? baseline
        XCTAssertFalse(scenes.isEmpty)
        for scene in scenes {
            XCTContext.runActivity(named: scene) { activity in
                let app = XCUIApplication()
                defer { app.terminate() }
                do {
                    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UITestSkipLegalConsent", "-UITestSkipScoreboardUsageHints", "-UITestFakeSession", "-UITestSportsVoiceMissing", "-national_day_2026_10_autopopup_count", "99", "-UITestGroupsCrossPlatform", "-GroupCaptureScene", scene, "-GroupCaptureNow", "1791864000000", "-GroupCaptureDataHash", canonicalHash, "-GroupCaptureSourceHash", sourceHash, "-AppleInterfaceStyle", "Light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
                    app.launch()
                    let identity = app.descendants(matching: .any)["group_capture_identity"].firstMatch
                    guard identity.waitForExistence(timeout: 20) else { throw CaptureError.missing("capture identity") }
                    let expected = "scene=\(scene);canonical=\(canonicalHash);adapter=\(adapterHash);referenceTime=1791864000000;transport=strict-offline;source=\(sourceHash);ready=true"
                    let predicate = NSPredicate(format: "value == %@", expected)
                    guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: identity)], timeout: 15) == .completed else { throw CaptureError.invalidMetadata(identity.value as? String ?? "") }
                    let frame = app.windows.firstMatch.frame
                    guard abs(frame.width - 402) < 1, abs(frame.height - 874) < 1 else { throw CaptureError.invalidMetadata("Expected iPhone 17 Pro 402×874 pt, got \(frame)") }
                    try prepare(scene, app)
                    let capturedScreen = XCUIScreen.main.screenshot()
                    let captureAtUTC = ISO8601DateFormatter().string(from: Date())
                    let screenshot = XCTAttachment(screenshot: capturedScreen)
                    screenshot.name = "capture-\(scene)"; screenshot.lifetime = .keepAlways
                    activity.add(screenshot)
                    let metadata: [String: Any] = ["scene": scene, "platform": "ios", "device": "iPhone 17 Pro", "logicalWidth": frame.width, "logicalHeight": frame.height, "canonicalSHA256": canonicalHash, "adapterSHA256": adapterHash, "referenceTime": 1791864000000, "language": "zh-Hans", "appearance": "light", "orientation": "portrait", "captureStatus": "captured", "captureAtUTC": captureAtUTC, "sourceSnapshotAtUTC": sourceSnapshotAtUTC, "sourceSHA256": sourceHash, "metadataSchemaVersion": 2, "reportCaseId": scene, "expectedState": expectedState(for: scene), "runtimeStateEvidence": ["preparationAssertions": "passed", "crossPlatformComparisonReview": "pending"], "nativeDifference": nativeDifferences[scene] ?? "", "transport": "strict-offline", "productionHierarchy": app.debugDescription]
                    let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                    let proof = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    proof.name = "metadata-\(scene)"; proof.lifetime = .keepAlways; activity.add(proof)
                } catch {
                    XCTFail("Scene \(scene) was not captured: \(error)")
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
        case "registration-draft": state.merge(["target": "native dirty-discard confirmation", "temporaryMemberID": "seed_m_seed_group_badminton_5", "pendingAdd": true]) { _, new in new }
        case "lineup-correction": state.merge(["activityStatus": "completed", "sessionStatus": "cancelled", "resultId": "", "canManage": false, "canCorrectResult": true, "gameState": "submitted"]) { _, new in new }
        case "activity-abandon": state.merge(["target": "single-activity release confirmation", "format": "singles", "registeredCount": 2, "capacity": 6, "nativeResumeScore": "7:4"]) { _, new in new }
        case "result-abandon": state.merge(["target": "multi-activity release confirmation", "format": "doubles", "nativeResumeScore": "7:4"]) { _, new in new }
        case "request-approve", "request-reject": state.merge(["groupNo": "82603164", "members": 1, "applicant": "林晨", "canonicalPeerGroupPreserved": true]) { _, new in new }
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
    private func requireConfirmationAction(_ label: String, _ app: XCUIApplication) throws {
        let sheet = app.sheets.firstMatch
        guard sheet.waitForExistence(timeout: 3) else { throw CaptureError.missing("native confirmation sheet: " + label) }
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
        try tap("group_overview_addResult", app); try require("group_match_submit", app)
    }
    private func openTrainingEditor(_ app: XCUIApplication) throws {
        try tap("group_training_plan_menu_compare_training_plan", app); try tap("修改排期", app)
        try require("训练排期", app)
    }
    private func restoreTop(_ app: XCUIApplication) throws { for _ in 0..<8 { try scrollActive(app, up: false) } }
    private func openDatePicker(_ key: String, _ app: XCUIApplication, time: Bool = false) throws {
        let picker = try locate(key, app, action: false, scroll: true)
        let buttons = picker.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        if let button = time ? buttons.last : buttons.first { button.tap() } else { picker.tap() }
        let predicate = NSPredicate { _, _ in
            app.pickerWheels.firstMatch.exists || app.datePickers.allElementsBoundByIndex.contains { $0.exists && $0.frame.height > 90 } || app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*[0-9]{4}年[0-9]{1,2}月.*")).firstMatch.exists
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 4) == .completed else { throw CaptureError.missing("actual native date/time picker " + key) }
    }
    private func setDetails(_ app: XCUIApplication) throws {
        try openManual(app)
        let toggle = try locate("group_result_sets_toggle", app, action: false, scroll: true)
        let control = toggle.descendants(matching: .switch).allElementsBoundByIndex.first { $0.exists && $0.isEnabled && $0.isHittable } ?? toggle
        guard control.isEnabled && control.isHittable, control.value as? String == "0" else { throw CaptureError.missing("actual set details switch initially off") }
        control.tap()
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: control)], timeout: 3) == .completed else { throw CaptureError.missing("set details enabled") }
        try tap("添加每局比分", app)
        try require("每局比分", app, scroll: true)
    }
    private func prepare(_ reportScene: String, _ app: XCUIApplication) throws {
        let scene = reportAliases[reportScene] ?? reportScene
        switch scene {
        case "home": _ = try locate("home_groups", app, action: true, scroll: true)
        case "detail-failure": try require("无法加载小组", app); try require("重试", app)
        case "create-approval-selected":
            try tap("group_create", app); try tap("group_create_policy", app); try tap("需要审批", app); try require("group_create_submit", app)
        case "visitor-report":
            try tap("group_join", app); app.textFields["group_number"].tap(); app.textFields["group_number"].typeText("82603162")
            try tap("预览小组", app); try keyboardClosed(app); try tap("举报小组", app); try require("提交举报", app)
        case "transfer-selected":
            try openManagement("转让小组", app); try tap("group_seat_新组主", app)
            try tap("group_member_pick_seed_m_seed_group_badminton_1", app)
            let selected = try locate("group_seat_新组主", app, action: true, scroll: false)
            guard selected.value as? String == "杨扬" || selected.label.contains("杨扬") else { throw CaptureError.missing("selected new owner 杨扬") }
            let confirm = try locate("group_management_submit", app, action: true, scroll: true)
            guard confirm.isEnabled else { throw CaptureError.missing("valid new owner confirmation") }
        case "member-actions", "member-rename", "member-remove":
            try tap("group_member_manage_seed_m_seed_group_badminton_5", app); try require("group_management_submit", app)
            if scene != "member-actions" { try require("临时球友 小陈", app) }
            if scene == "member-remove" { try tap("移除成员", app); try requireConfirmationAction("移除成员", app) }
        case "request-approve", "request-reject":
            try require("林晨", app, scroll: true)
            let action = try locate(scene == "request-approve" ? "同意" : "拒绝", app, action: true, scroll: true)
            guard action.isEnabled && action.isHittable else { throw CaptureError.missing("actual pending request action") }
        case "training-cancel":
            try tap("group_training_plan_menu_compare_training_plan", app); try tap("取消排期", app); try require("取消原因", app)
        case "training-leave": try tap("通知请假", app); try require("请假说明（选填，最多 100 字）", app)
        case "training-notices":
            try tap("group_training_notices", app)
            try require("group_training_notice_inbox", app); try require("group_training_notices_empty", app)
        case "lineup-frozen":
            try tap("编排场次", app); try require("group_schedule_starts_compare_activity_session_1", app)
            guard !element("group_schedule_starts_compare_activity_session_1", app).isEnabled else { throw CaptureError.missing("frozen activity row") }
        case "lineup-correction":
            let button = try locate("补记比赛", app, action: true, scroll: true)
            guard button.isEnabled else { throw CaptureError.missing("corrective result action") }
        case "result-frozen":
            try tap("group_activity_frozen_manual_1", app); try require("group_seat_A1", app)
            let rules = try locate("比赛规则", app, action: true, scroll: false)
            guard !rules.isEnabled else { throw CaptureError.missing("frozen rules") }
            _ = try locate("group_match_submit", app, action: true, scroll: true)
            for _ in 0..<3 { try scrollActive(app, up: false) }
            try require("group_seat_A1", app)
        case "training-plan-frozen":
            try openTrainingEditor(app); try require("group_schedule_starts_compare_training_session_1", app)
            guard !element("group_schedule_starts_compare_training_session_1", app).isEnabled else { throw CaptureError.missing("frozen training row") }
        case "result-details-expansion": try setDetails(app)
        case "training-shift-preview":
            try openTrainingEditor(app); try tap("group_schedule_shift_compare_training_session_1", app); try require("顺延本场及后续场次", app); try require("确认", app)
        case "activity-date", "activity-deadline", "activity-place":
            try tap("创建活动", app); try require("group_activity_save", app)
            if scene != "activity-place" { try openDatePicker(scene == "activity-date" ? "group_activity_starts" : "group_activity_closes", app) }
            else { try tap("group_activity_place_picker", app); try require("暂无已保存地点", app); try require("选择地点", app) }
        case "result-date": try openManual(app); try openDatePicker("group_result_played_at", app)
        case "lineup-clock": try tap("编排场次", app); try openDatePicker("group_schedule_starts_compare_activity_session_1", app, time: true)
        case "training-date", "training-clock":
            try openTrainingEditor(app)
            try openDatePicker(scene == "training-date" ? "group_schedule_date" : "group_schedule_starts_compare_training_session_1", app, time: scene == "training-clock")
        case "activity-cancel":
            let reason = try locate("group_activity_cancel_reason", app, action: false, scroll: true)
            reason.tap(); reason.typeText("场馆临时关闭"); try scrollActive(app)
            try tap("group_activity_cancel_action", app); try requireConfirmationAction("取消活动", app)
        case "activity-abandon":
            try require("单场计分续局", app); try require("2/6 · 单打", app)
            _ = try locate("继续本机计分", app, action: true, scroll: true)
            try tap("group_activity_abandon_compare_capture_single_game", app); try requireConfirmationAction("释放比赛占位", app)
        case "result-abandon":
            _ = try locate("继续本机计分", app, action: true, scroll: true)
            try tap("group_activity_abandon_compare_frozen_activity_game", app); try requireConfirmationAction("释放比赛占位", app)
        case "registration-draft":
            try tap("group_activity_registration_manage", app)
            let toggle = try locate("group_registration_member_seed_m_seed_group_badminton_5", app, action: false, scroll: true)
            // The identifier belongs to SwiftUI's whole Form row; tap the nested native UISwitch, not the label at the row's center.
            let control = toggle.descendants(matching: .switch).allElementsBoundByIndex.first { $0.exists && $0.isEnabled && $0.isHittable } ?? toggle
            guard control.isEnabled && control.isHittable, control.value as? String == "0" else { throw CaptureError.missing("real unregistered temporary member switch") }
            control.tap()
            guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: control)], timeout: 3) == .completed else { throw CaptureError.missing("pending temporary member registration") }
            let preview = try locate("group_registration_preview", app, action: true, scroll: true)
            guard preview.isEnabled else { throw CaptureError.missing("dirty registration preview") }
            try require("+ 报名", app)
            try tap("group_registration_close", app); try requireConfirmationAction("放弃", app)
        case "result-authority", "result-normal", "result-actions", "result-void-pending", "result-void-confirmed", "result-void-list":
            try require("比赛详情", app)
            if scene == "result-authority" { _ = try locate("组长权威确认", app, action: true, scroll: true) }
            if scene == "result-normal" || scene == "result-actions" { try requireFullyVisibleAction("确认结果", app) }
            if scene.hasPrefix("result-void") { try require("作废原因", app, scroll: true); _ = try locate("作废结果", app, action: true, scroll: true) }
        case "records-authority": try tap("组长权威确认", app); try requireConfirmationAction("组长权威确认", app)
        case "upload-discard": try tap("放弃上传", app); try requireConfirmationAction("放弃上传", app)
        case "lineup-finish":
            let button = try locate("group_activity_finish", app, action: true, scroll: true)
            guard button.isEnabled else { throw CaptureError.missing("actual finish activity control") }
        case "result-draft-return":
            try openManual(app)
            let scoreRow = try locate("整场局分", app, action: true, scroll: true)
            // Native Form exposes a whole row and its smaller Menu trigger; tap the actual control.
            let trigger = scoreRow.descendants(matching: .button).allElementsBoundByIndex.first {
                $0.exists && $0.isEnabled && $0.isHittable && $0.frame.width < scoreRow.frame.width
            } ?? scoreRow
            trigger.tap()
            let scoreChoice = try locate("2:0", app, action: false, scroll: false)
            guard scoreChoice.isEnabled && scoreChoice.isHittable else { throw CaptureError.missing("actual 2:0 overall score choice") }
            scoreChoice.tap()
            guard app.textFields["group_score_A"].value as? String == "2", app.textFields["group_score_B"].value as? String == "0" else { throw CaptureError.missing("chosen overall score 2:0") }
            try tap("关闭", app)
            try openManual(app); try require("group_score_A", app)
            guard app.textFields["group_score_A"].value as? String == "2", app.textFields["group_score_B"].value as? String == "0" else { throw CaptureError.missing("retained manual result draft") }
        case "group-conflict":
            try openManagement("修改小组资料", app)
            try tap("group_edit_policy", app); try tap("持小组号可直接加入", app)
            try tap("group_management_submit", app)
            try tap("加载最新版本", app); try require("最新版本", app, scroll: true)
        case "activity-conflict":
            try tap("编辑", app); try tap("group_activity_save", app); try tap("加载最新版本", app)
            try require("最新版本", app, scroll: true)
        case "training-conflict", "lineup-conflict-reload":
            if scene == "training-conflict" { try openTrainingEditor(app) } else { try tap("编排场次", app) }
            try tap("group_training_publish", app); try tap("group_schedule_confirm", app)
            try tap("加载最新版本", app)
            if scene == "training-conflict" {
                // Public reload confirmation reads the newer snapshot, then leaves the real conflict review open.
                let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "加载最新版本"))
                    .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
                guard let confirmation = confirmations.last else { throw CaptureError.missing("reload confirm") }; confirmation.tap()
                try require("最新版本", app, scroll: true)
            } else { try requireConfirmationAction("加载最新版本", app) }
        case "list":
            try require("group_card_seed_group_badminton", app)
            let create = app.buttons["group_create"], join = app.buttons["group_join"]
            guard create.isHittable, join.isHittable, create.frame.minY > app.windows.firstMatch.frame.height * 0.75 else { throw CaptureError.missing("sticky group footer") }
            let y = create.frame.minY
            try scrollActive(app)
            guard abs(create.frame.minY - y) < 1 else { throw CaptureError.missing("group footer moved with list") }
            try scrollActive(app, up: false)
            let card = element("group_card_seed_group_badminton", app)
            let memberCountVisible = card.label.contains("6 成员") || card.descendants(matching: .staticText).allElementsBoundByIndex.contains { $0.label.contains("6 成员") }
            guard memberCountVisible else { throw CaptureError.missing("canonical badminton member count") }

        case "create": try tap("group_create", app); try require("group_create_submit", app)
        case "join", "join-approval", "join-empty":
            try tap("group_join", app); try require("group_number", app)
            if scene != "join-empty" {
                app.textFields["group_number"].tap(); app.textFields["group_number"].typeText("82603162")
                if scene == "join-approval" { try tap("group_keyboard_done", app); try keyboardClosed(app) }
                try tap("预览小组", app); try require("group_preview_name", app)
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
        case "detail-members": try require("group_member_search", app)
        case "admin": try tap("小组管理", app); try require("修改小组资料", app)
        case "activity": try require("周六双打友谊赛", app); try require("滨江体育中心", app); try require("4/12 · 双打", app)
        case "activity-create": try tap("创建活动", app); try require("group_activity_save", app)
        case "activity-edit": try tap("编辑", app); try require("group_activity_save", app)
        case "lineup", "lineup-review":
            try tap("编排场次", app)
            if scene == "lineup-review" { try tap("group_training_publish", app); try require("group_schedule_confirm", app, scroll: true) }
            else { try validateScheduleEditor(app, activity: true) }
        case "result", "result-rules", "result-member-picker":
            try openManual(app)
            if scene == "result-rules" { try tap("比赛规则", app); try require("恢复默认规则", app) }
            if scene == "result-member-picker" { try tap("group_seat_A1", app); try require("group_member_pick_seed_m_seed_group_badminton_0", app) }
        case "result-launch": try tap("group_overview_start", app); try require("group_match_submit", app)
        case "result-detail", "result-detail-pending", "result-detail-confirmed", "result-detail-voided":
            try require("比赛详情", app)
            try require(scene == "result-detail-pending" ? "待确认" : scene == "result-detail-voided" ? "已作废" : "已确认", app)
            try require(scene == "result-detail-pending" ? "2 : 0" : "2 : 1", app)
        case "member-results": try require("我", app)
        case "share", "share-readonly": try require("group_qr", app); try require("#82603158", app)
        case "notices": try require("周六双打友谊赛", app)
        case "coach", "student": try require("训练排期", app); try require("滨江体育中心 2 号馆", app)
        case "training-plan-create": try tap("group_training_add", app); try validateScheduleEditor(app)
        case "training-plan", "training-plan-edit", "training-plan-review":
            try tap("group_training_plan_menu_compare_training_plan", app); try tap("修改排期", app)
            if scene == "training-plan-review" { try tap("group_training_publish", app); try require("group_schedule_confirm", app, scroll: true) }
            else { try validateScheduleEditor(app) }
        case "dialog-edit-group": try openManagement("修改小组资料", app); try require("group_management_submit", app)
        case "dialog-transfer-owner":
            try openManagement("转让小组", app); try tap("group_seat_新组主", app)
            try require("group_member_pick_seed_m_seed_group_badminton_1", app)
        case "dialog-report": try openManagement("举报小组", app); try require("提交举报", app)
        case "dialog-dissolve": try openManagement("解散小组", app); try require("group_management_submit", app)
        case "dialog-archive": try openManagement("归档小组", app); try require("group_management_submit", app)
        case "dialog-restore": try openManagement("恢复小组", app); try require("group_management_submit", app)
        case "dialog-leave": try openManagement("退出小组", app); try require("group_management_submit", app)
        case "dialog-temporary-member", "dialog-common-name-import":
            try tap("group_add_temporary", app); try require("group_temporary_names", app)
            if scene == "dialog-common-name-import" { try tap("已保存名称", app); try require("林丹", app); try require("谌龙", app) }
        case "dialog-rename-member": try tap("group_member_manage_seed_m_seed_group_badminton_5", app); try require("group_management_submit", app)
        default: throw CaptureError.unsupported(scene)
        }
    }
}
