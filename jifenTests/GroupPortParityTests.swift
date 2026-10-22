import XCTest
import CoreImage
import SwiftUI
import UIKit
@testable import jifen

@MainActor final class GroupPortParityTests: XCTestCase {
    func testProfileChangesOmitUnchangedFieldsAndAllowClearingDescription() throws {
        let original = GroupProfileFields(name: "周六羽毛球", description: "固定球友", joinPolicy: "open")
        var edited = original
        edited.description = " 新简介 "
        let data = try JSONEncoder().encode(edited.changes(from: original, canEditJoinPolicy: true))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String: String], ["description": "新简介"])
        edited.description = " "
        XCTAssertEqual(edited.changes(from: original, canEditJoinPolicy: true).description, "")
        edited = original
        edited.name = " 周六羽毛球 "
        edited.joinPolicy = "closed"
        let unchanged = edited.changes(from: original, canEditJoinPolicy: false)
        XCTAssertNil(unchanged.name); XCTAssertNil(unchanged.description); XCTAssertNil(unchanged.joinPolicy)
    }

    func testCancelledActivityOrSessionCannotEnterResults() {
        XCTAssertFalse(GroupActivityPolicy.allowsMatchEntry(activityStatus: "cancelled", sessionStatus: nil))
        XCTAssertFalse(GroupActivityPolicy.allowsMatchEntry(activityStatus: "recruiting", sessionStatus: "cancelled"))
        XCTAssertTrue(GroupActivityPolicy.allowsMatchEntry(activityStatus: "completed", sessionStatus: "completed"))
        XCTAssertTrue(GroupActivityPolicy.allowsMatchEntry(activityStatus: "recruiting", sessionStatus: "scheduled"))
    }

    func testNotificationTargetsFollowTheEventAndKeepLegacyFallbacks() {
        for kind in ["activity_created", "activity_changed", "activity_cancelled"] {
            XCTAssertEqual(GroupNoticeTarget.resolve(kind: kind, resourceID: " activity "), .activity("activity"))
        }
        for kind in ["result_pending", "result_confirmed", "result_voided"] {
            XCTAssertEqual(GroupNoticeTarget.resolve(kind: kind, resourceID: "result"), .result("result"))
        }
        for kind in ["join_requested", "role_changed", "ownership_transferred"] {
            XCTAssertEqual(GroupNoticeTarget.resolve(kind: kind, resourceID: "request"), .group(tab: 3))
        }
        for kind in ["member_removed", "join_rejected"] {
            XCTAssertEqual(GroupNoticeTarget.resolve(kind: kind, resourceID: "member"), .message)
        }
        for id in [nil, "", " \n"] as [String?] {
            XCTAssertEqual(GroupNoticeTarget.resolve(kind: "result_pending", resourceID: id), .group(tab: 0))
        }
        XCTAssertEqual(GroupNoticeTarget.resolve(kind: "join_approved", resourceID: "request"), .group(tab: 0))
        XCTAssertEqual(GroupNoticeTarget.resolve(kind: "result_future_kind", resourceID: "resource"), .group(tab: 0))
        XCTAssertEqual(GroupNoticeTarget.resolve(kind: "training_changed", resourceID: "plan"), .group(tab: 1))
    }

    private func rules() -> GroupMatchRules { .init(sport: .badminton, maxSets: 3, matchCompletionMode: "best_of", pointsToWinSet: 21, pointCap: 30, winByTwo: true, useRallyScoring: true, gamesPerSet: 6, tieBreakPoints: 7, setScoringMode: "regular", usesNoAdScoring: false) }
    private func group() -> ScoreGroup { .init(id: "group", groupNo: "123456", name: "Test", description: "", sport: .badminton, status: "active", joinPolicy: "approval", ownerMemberId: "owner", memberLimit: 30, createdAt: 1, updatedAt: 1, revision: 3) }
    private func member(_ id: String, role: String = "member", kind: String = "account") -> GroupMember { .init(id: id, groupId: "group", kind: kind, role: role, status: "active", displayName: id, accountId: id, joinedAt: 1) }
    private func result(submitter: String = "a") -> GroupResult {
        .init(id: "result", groupId: "group", activityId: "", gameId: "game", format: .doubles, sport: .badminton, setScore: .init(a: 2, b: 0), rules: rules(), participants: [.init(memberId: "a", side: "A", seat: 0), .init(memberId: "a2", side: "A", seat: 1), .init(memberId: "b", side: "B", seat: 0), .init(memberId: "b2", side: "B", seat: 1)], playedAt: 1, submitterMemberId: submitter, confirmedByMemberId: "", status: "pending_confirmation", source: "manual", reason: "", createdAt: 1, revision: 1)
    }
    private func body() -> GroupResultBody { .init(gameId: "game", clientSessionId: "session", clientRecordId: nil, activityId: "activity", format: .singles, bestOf: 3, rules: rules(), setScore: .init(a: 2, b: 0), sets: nil, playedAt: 1234, source: "manual", participants: [.init(memberId: "a", side: "A", seat: 0), .init(memberId: "b", side: "B", seat: 0)], activitySessionId: "activity-session") }
    private func withPersistence(_ work: (GroupLocalPersistence, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try work(GroupLocalPersistence(root: root), root)
    }

    func testPersonalConfirmationTasksKeepUnrelatedResultsInHistory() {
        let pending = result()
        var confirmed = pending
        confirmed.id = "confirmed"; confirmed.status = "confirmed"; confirmed.playedAt = 2
        for id in ["other", "a", "a2"] {
            let tasks = GroupPermissions.confirmationTasks([pending, confirmed], group: group(), me: member(id))
            XCTAssertTrue(tasks.isEmpty)
            XCTAssertEqual(GroupPermissions.resultHistory([pending, confirmed], pending: [pending], tasks: tasks, format: nil).map(\.id), ["confirmed", "result"])
            XCTAssertTrue(GroupPermissions.resultHistory([pending, confirmed], pending: [pending], tasks: tasks, format: .singles).isEmpty)
        }
        for me in [member("b"), member("admin", role: "admin")] {
            let tasks = GroupPermissions.confirmationTasks([pending, confirmed], group: group(), me: me)
            XCTAssertEqual(tasks.map(\.id), ["result"])
            XCTAssertEqual(GroupPermissions.resultHistory([pending, confirmed], pending: [pending], tasks: tasks, format: nil).map(\.id), ["confirmed"])
        }
        var archived = group(); archived.status = "archived"
        XCTAssertTrue(GroupPermissions.confirmationTasks([pending], group: archived, me: member("b")).isEmpty)
        XCTAssertTrue(GroupPermissions.confirmationTasks([pending], group: group(), me: nil).isEmpty)
        var authority = result(submitter: "owner"); authority.canAuthorityConfirm = true
        XCTAssertEqual(GroupPermissions.confirmationTasks([authority], group: group(), me: member("owner", role: "owner")).map(\.id), ["result"])
    }

    func testKnownRegionOverridesChineseLanguage() {
        for language in ["zh-Hans", "zh-Hant", "en"] {
            XCTAssertEqual(GroupInvitationLink.website(regionCode: " cn ", localization: language), "https://jifenqi.com")
            for region in ["US", "HK", "MO", "TW", "JP"] { XCTAssertEqual(GroupInvitationLink.website(regionCode: region, localization: language), "https://iscoreboard.live") }
        }
    }
    func testMissingRegionUsesEffectiveAppLanguage() {
        for region in [nil, "", " "] {
            for language in ["zh-Hans", "zh-Hant", "zh_TW"] { XCTAssertEqual(GroupInvitationLink.website(regionCode: region, localization: language), "https://jifenqi.com") }
            for language in ["en", "ja", "ar"] { XCTAssertEqual(GroupInvitationLink.website(regionCode: region, localization: language), "https://iscoreboard.live") }
        }
    }
    func testQRAndTextInvitationUseIdenticalURL() {
        for region in ["CN", "US", nil] {
            for language in ["zh-Hans", "zh-Hant", "en"] { XCTAssertEqual(GroupQRPayload.encode("123456", regionCode: region, localization: language), GroupInvitationLink.joinURL(groupNo: "123456", regionCode: region, localization: language)?.absoluteString) }
        }
    }
    func testGeneratedQRIsReadableAndContainsHTTPSInvitation() throws {
        let image = try XCTUnwrap(GroupQRCode.image("123456")), cg = try XCTUnwrap(image.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let payload = try XCTUnwrap((detector.features(in: CIImage(cgImage: cg)).first as? CIQRCodeFeature)?.messageString)
        XCTAssertTrue(payload.hasPrefix("https://")); XCTAssertEqual(GroupQRPayload.parse(payload), "123456")
    }
    func testLegacyJSONAndNumericInvitationsRemainReadable() {
        XCTAssertEqual(GroupQRPayload.parse("{\"type\":\"JIFEN_GROUP\",\"v\":1,\"groupNo\":\"123456\"}"), "123456")
        XCTAssertEqual(GroupQRPayload.parse("123456"), "123456")
        XCTAssertNil(GroupQRPayload.parse("{\"type\":\"JIFEN_GROUP\",\"v\":2,\"groupNo\":\"123456\"}"))
    }
    func testSpectatorSubmissionCanBeConfirmedByParticipant() {
        XCTAssertTrue(GroupPermissions.confirmation(result(submitter: "spectator"), group: group(), me: member("a")).allowed)
        XCTAssertFalse(GroupPermissions.confirmation(result(submitter: "spectator"), group: group(), me: member("other")).allowed)
    }
    func testSubmitterAndTeammateWaitForOpponent() {
        XCTAssertFalse(GroupPermissions.confirmation(result(), group: group(), me: member("a")).allowed)
        XCTAssertFalse(GroupPermissions.confirmation(result(), group: group(), me: member("a2")).allowed)
        XCTAssertTrue(GroupPermissions.confirmation(result(), group: group(), me: member("b2")).allowed)
    }
    func testAuthorityConfirmationRequiresServerFlagAndOwner() {
        var row = result(submitter: "owner"); row.canAuthorityConfirm = true
        let owner = GroupPermissions.confirmation(row, group: group(), me: member("owner", role: "owner"))
        XCTAssertTrue(owner.allowed); XCTAssertTrue(owner.authority)
        XCTAssertFalse(GroupPermissions.confirmation(row, group: group(), me: member("admin", role: "admin")).authority)
        row.canAuthorityConfirm = false
        XCTAssertFalse(GroupPermissions.confirmation(row, group: group(), me: member("owner", role: "owner")).allowed)
    }
    func testArchivedGroupCannotConfirmOrChangeMembers() {
        var archived = group(); archived.status = "archived"
        XCTAssertFalse(GroupPermissions.confirmation(result(), group: archived, me: member("owner", role: "owner")).allowed)
        XCTAssertFalse(GroupPermissions.canManageMember(archived, me: member("owner", role: "owner"), target: member("a")))
    }
    func testAdministratorCannotManageOwnerOrAnotherAdministrator() {
        XCTAssertFalse(GroupPermissions.canManageMember(group(), me: member("admin", role: "admin"), target: member("owner", role: "owner")))
        XCTAssertFalse(GroupPermissions.canManageMember(group(), me: member("admin", role: "admin"), target: member("admin2", role: "admin")))
        XCTAssertTrue(GroupPermissions.canManageMember(group(), me: member("admin", role: "admin"), target: member("temp", kind: "temporary")))
    }
    func testCapabilitiesDecodeObjectsAndGateCreationTypes() throws {
        let json = """
        {"groupNoLength":6,"nameMin":2,"nameMax":24,"descriptionMax":200,"memberLimitDefault":30,"memberLimitMax":50,"sports":[{"sport":"pickleball","defaultRules":null,"ruleOptions":{"pointsToWinSet":[7,11,15,21]}}],"groupTypes":["peer"],"allowedActions":["join_group"],"supportsActivityLineup":true,"minClientContractVersion":1}
        """
        let data = try JSONDecoder().decode(GroupCapabilities.self, from: Data(json.utf8))
        XCTAssertEqual(data.sport(.pickleball)?.ruleOptions?.pointsToWinSet, [7,11,15,21])
        XCTAssertEqual(data.groupTypes, ["peer"]); XCTAssertTrue(data.allows("join_group")); XCTAssertFalse(data.allows("create_group"))
    }
    func testMinimumClientContractDisablesWrites() throws {
        var data = GroupCapabilities(groupNoLength: 6, nameMin: 2, nameMax: 24, descriptionMax: 200, memberLimitDefault: 30, memberLimitMax: 50)
        data.minClientContractVersion = 2; XCTAssertFalse(data.allows("start_game"))
    }
    func testActivityAndTrainingSessionIdentitiesReachWireBody() throws {
        var value = body(); value.trainingSessionId = "training"
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        XCTAssertEqual(json["activitySessionId"] as? String, "activity-session"); XCTAssertEqual(json["trainingSessionId"] as? String, "training")
        let game = GroupGameBody(clientSessionId: "session", activityId: "activity", format: .singles, rules: rules(), participants: value.participants, activitySessionId: "activity-session")
        let gameJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any]); XCTAssertEqual(gameJSON["activitySessionId"] as? String, "activity-session")
    }
    func testLegacyContextDecodesWithoutNewSessionField() throws {
        let context = GroupMatchContext(accountID: "a", groupID: "g", groupName: "g", gameID: "game", clientSessionID: "s", format: .singles, rules: rules(), participants: [])
        let data = try JSONEncoder().encode(context)
        XCTAssertNil(try JSONDecoder().decode(GroupMatchContext.self, from: data).activitySessionID)
    }
    func testStableScheduleIDsAreEncoded() throws {
        let row = GroupTrainingSessionBody(orderNo: 1, court: "Court", startsAt: 100, format: .singles, seats: [], id: "stable")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]); XCTAssertEqual(json["id"] as? String, "stable")
    }
    func testRepairReplacesOneBodyAndPreservesOriginalIdempotencyKey() throws {
        try withPersistence { persistence, _ in
            try persistence.enqueueManual(body(), id: "record", accountID: "a", groupID: "g", key: "original-key")
            var corrected = body(); corrected.playedAt = 9876; corrected.setScore = .init(a: 0, b: 2)
            try persistence.enqueueManual(corrected, id: "record", accountID: "a", groupID: "g", key: "new-key")
            let rows = persistence.uploads(accountID: "a"); XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.key, "original-key"); XCTAssertEqual(rows.first?.body.playedAt, 9876); XCTAssertEqual(rows.first?.body.setScore.b, 2)
        }
    }
    func testTerminalTombstonePreventsReenqueueAndDoesNotRetainBody() throws {
        try withPersistence { persistence, root in
            try persistence.enqueueManual(body(), id: "record", accountID: "a", groupID: "g", key: "key")
            try persistence.markUploaded("record", accountID: "a", resultID: "remote")
            try persistence.enqueueManual(body(), id: "record", accountID: "a", groupID: "g", key: "key")
            XCTAssertTrue(persistence.uploads(accountID: "a").isEmpty)
            let text = String(decoding: try Data(contentsOf: root.appendingPathComponent("tombstones.json")), as: UTF8.self)
            XCTAssertFalse(text.contains("participants")); XCTAssertFalse(text.contains("setScore")); XCTAssertTrue(text.contains("remote"))
        }
    }
    func testLegacyUploadedRowsMigrateWithoutLosingPendingRows() throws {
        try withPersistence { persistence, root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let terminal = GroupPendingUpload(id: "done", accountID: "a", groupID: "g", key: "key", body: body(), uploaded: true)
            let pending = GroupPendingUpload(id: "pending", accountID: "a", groupID: "g", key: "key2", body: body())
            try JSONEncoder().encode([terminal,pending]).write(to: root.appendingPathComponent("outbox.json"))
            XCTAssertEqual(persistence.uploads(accountID: "a").map(\.id), ["pending"])
            XCTAssertEqual(GroupLocalPersistence(root: root).uploads(accountID: "a").map(\.id), ["pending"])
        }
    }
    func testLeavingGroupPreservesOtherAccountAndOtherGroupUploads() throws {
        try withPersistence { persistence, _ in
            for (id, account, group) in [("1","a","g"),("2","a","other"),("3","b","g")] { try persistence.enqueueManual(body(), id: id, accountID: account, groupID: group, key: id) }
            try persistence.forgetGroup("g", accountID: "a")
            XCTAssertEqual(persistence.uploads(accountID: "a").map(\.id), ["2"]); XCTAssertEqual(persistence.uploads(accountID: "b").map(\.id), ["3"])
            try persistence.enqueueManual(body(), id: "1", accountID: "a", groupID: "g", key: "1"); XCTAssertEqual(persistence.uploads(accountID: "a").count, 1)
        }
    }
    func testDraftsAreIsolatedAndAccountDeletionRemovesOnlyOwnDraft() throws {
        try withPersistence { persistence, _ in
            try persistence.saveDraft(["a"], key: "match:g", accountID: "a"); try persistence.saveDraft(["b"], key: "match:g", accountID: "b")
            XCTAssertEqual(persistence.loadDraft([String].self, key: "match:g", accountID: "a"), ["a"])
            persistence.deleteAccountData(accountID: "a")
            XCTAssertNil(persistence.loadDraft([String].self, key: "match:g", accountID: "a")); XCTAssertEqual(persistence.loadDraft([String].self, key: "match:g", accountID: "b"), ["b"])
            XCTAssertThrowsError(try persistence.enqueueManual(body(), id: "old", accountID: "a", groupID: "g", key: "k"))
        }
    }
    func testTemporaryNamesSupportSingleUnicodeScalarAndDeduplicateBatch() {
        XCTAssertTrue(GroupInputValidation.validName("王")); XCTAssertFalse(GroupInputValidation.validName(" "))
        XCTAssertEqual(GroupInputValidation.temporaryNames("王\nA，王; B"), ["王","A","B"])
    }
    func testTemporaryAdditionPublishesOnceAndRejectsOldIdentityWithoutResettingDetail() throws {
        let account = "roster-test-" + UUID().uuidString
        let previous = UserDefaults.standard.object(forKey: "groups.lastAccountID")
        defer {
            GroupLocalPersistence.shared.removeCache(accountID: account)
            UserDefaults.standard.set(previous, forKey: "groups.lastAccountID")
        }
        let detail = GroupDetailCache(group: group(), members: [member("owner", role: "owner")], activities: [], results: [], rankings: [], stats: nil, nextCursor: nil, syncedAt: Date())
        var cache = GroupAccountCache(); cache.groups = [group()]; cache.details["group"] = detail
        try GroupLocalPersistence.shared.saveCache(cache, accountID: account)
        let store = GroupStore(observeConnectivity: false, signedInAccountID: { account })
        store.sessionDidChange(userID: account)
        let identity = store.identityRevision
        let added = member("new-player", kind: "temporary")
        XCTAssertTrue(store.acceptTemporaryMember(added, groupID: "group", accountID: account, identity: identity))
        XCTAssertTrue(store.acceptTemporaryMember(added, groupID: "group", accountID: account, identity: identity))
        XCTAssertEqual(store.cache.details["group"]?.members.map(\.id), ["owner", "new-player"])
        XCTAssertEqual(store.cache.details["group"]?.group, detail.group)
        XCTAssertFalse(store.acceptTemporaryMember(added, groupID: "other-group", accountID: account, identity: identity))
        XCTAssertFalse(store.acceptTemporaryMember(member("formal"), groupID: "group", accountID: account, identity: identity))
        store.sessionDidChange(userID: nil)
        XCTAssertFalse(store.acceptTemporaryMember(added, groupID: "group", accountID: account, identity: identity))
        XCTAssertTrue(store.cache.details.isEmpty)
    }

    func testOverviewCanOpenSetupBeforeTwoMembers() {
        for count in [0, 1] {
            let policy = GroupOverviewActions(group: group(), memberCount: count, hasResults: true, confirmedMatchCount: 2, isCoach: false)
            XCTAssertEqual(policy.actions, [.addResult, .start]); XCTAssertTrue(policy.showSecondaryInvite)
        }
    }
    func testOverviewStartsWithOneActionAndAddsManualEntryAfterHistory() {
        let fresh = GroupOverviewActions(group: group(), memberCount: 2, hasResults: false, confirmedMatchCount: 0, isCoach: false)
        XCTAssertEqual(fresh.actions, [.start]); XCTAssertTrue(fresh.showSecondaryInvite)
        for (hasResults, confirmed) in [(true, 0), (false, 1)] {
            XCTAssertEqual(GroupOverviewActions(group: group(), memberCount: 2, hasResults: hasResults, confirmedMatchCount: confirmed, isCoach: false).actions, [.addResult, .start])
        }
    }
    func testCoachingFooterLimitsManualResultsToCoach() {
        var coaching = group(); coaching.groupType = "coaching"
        XCTAssertEqual(GroupOverviewActions(group: coaching, memberCount: 2, hasResults: true, confirmedMatchCount: 1, isCoach: false).actions, [.training])
        XCTAssertEqual(GroupOverviewActions(group: coaching, memberCount: 2, hasResults: true, confirmedMatchCount: 1, isCoach: true).actions, [.addResult, .training])
        XCTAssertEqual(GroupOverviewActions(group: coaching, memberCount: 2, hasResults: false, confirmedMatchCount: 0, isCoach: true).actions, [.training])
    }
    func testReadOnlyOverviewHasNoFooterAndClosedOrFullGroupsCannotInvite() {
        for status in ["archived", "dissolving"] {
            var readOnly = group(); readOnly.status = status
            let policy = GroupOverviewActions(group: readOnly, memberCount: 2, hasResults: true, confirmedMatchCount: 1, isCoach: false)
            XCTAssertTrue(policy.actions.isEmpty); XCTAssertFalse(policy.showSecondaryInvite)
        }
        var closed = group(); closed.joinPolicy = "closed"
        XCTAssertFalse(GroupOverviewActions(group: closed, memberCount: 1, hasResults: false, confirmedMatchCount: 0, isCoach: false).canInvite)
        XCTAssertFalse(GroupOverviewActions(group: group(), memberCount: 30, hasResults: true, confirmedMatchCount: 1, isCoach: false).showSecondaryInvite)
    }
}

private nonisolated final class GroupWriteAttempts: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [(String, Data)] = []
    func append(key: String, body: Data) -> Int { lock.lock(); defer { lock.unlock() }; rows.append((key, body)); return rows.count }
    func snapshot() -> [(String, Data)] { lock.lock(); defer { lock.unlock() }; return rows }
}

@MainActor private final class GroupOperationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor private final class GroupTestAccount {
    var id: String?
    init(_ id: String) { self.id = id }
}

extension GroupPortParityTests {
    private func createBody() -> GroupCreateBody { .init(name: "Club", description: "", sport: .badminton, joinPolicy: "open") }
    private func reminderActivity() -> GroupActivity {
        .init(id: "activity", groupId: "group", title: "Match", startsAt: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000), place: "Court", capacity: 4, note: "", format: .singles, status: "recruiting", creatorMemberId: "owner", registeredMemberIds: ["me"], gameId: "", createdAt: 1, revision: 1)
    }
    func testPendingCreationSurvivesRestartInterleavingAndStaysScoped() throws {
        try withPersistence { persistence, root in
            let body = createBody()
            let first = try persistence.pendingWrite(accountID: "a", path: "", body: body)
            let other = try persistence.pendingWrite(accountID: "a", path: "/group/activities", body: body)
            let accountB = try persistence.pendingWrite(accountID: "b", path: "", body: body)
            let restarted = GroupLocalPersistence(root: root)
            XCTAssertEqual(first.key, try restarted.pendingWrite(accountID: "a", path: "", body: body).key)
            XCTAssertNotEqual(first.key, other.key); XCTAssertNotEqual(first.key, accountB.key)
            var changed = body; changed.name = "Other club"
            XCTAssertNotEqual(first.key, try restarted.pendingWrite(accountID: "a", path: "", body: changed).key)
            try restarted.completeWrite(key: first.key, accountID: "b")
            XCTAssertEqual(first.key, try restarted.pendingWrite(accountID: "a", path: "", body: body).key)
            try restarted.completeWrite(key: first.key, accountID: "a")
            XCTAssertNotEqual(first.key, try restarted.pendingWrite(accountID: "a", path: "", body: body).key)
            XCTAssertEqual(other.key, try restarted.pendingWrite(accountID: "a", path: "/group/activities", body: body).key)
            restarted.deleteAccountData(accountID: "a")
            XCTAssertThrowsError(try restarted.pendingWrite(accountID: "a", path: "", body: body))
            XCTAssertEqual(accountB.key, try restarted.pendingWrite(accountID: "b", path: "", body: body).key)
        }
    }
    func testDamagedPendingCreationRegistryFailsClosed() throws {
        try withPersistence { persistence, root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("pending-writes.json"), bad = Data("broken registry".utf8)
            try bad.write(to: url)
            XCTAssertThrowsError(try persistence.pendingWrite(accountID: "a", path: "", body: createBody()))
            XCTAssertEqual(try Data(contentsOf: url), bad)
        }
    }
    func testPendingCreationPrunesOnlyExpiredInactiveRequests() throws {
        try withPersistence { persistence, root in
            let start = Date(timeIntervalSince1970: 1_000_000)
            let body = createBody()
            let stale = try persistence.pendingWrite(accountID: "a", path: "", body: body, now: start)
            let recent = try persistence.pendingWrite(accountID: "b", path: "", body: body, now: start.addingTimeInterval(1))
            let active = try persistence.pendingWrite(accountID: "a", path: "/group/activities", body: body, now: start)
            let expiry = start.addingTimeInterval(GroupLocalPersistence.pendingWriteRetention)
            let restarted = GroupLocalPersistence(root: root)
            XCTAssertEqual(active.key, try restarted.pendingWrite(accountID: "a", path: "/group/activities", body: body, now: expiry).key)
            let rows = try JSONDecoder().decode([GroupPendingWrite].self, from: Data(contentsOf: root.appendingPathComponent("pending-writes.json")))
            XCTAssertFalse(rows.contains { $0.key == stale.key })
            XCTAssertEqual(Set(rows.map(\.key)), [recent.key, active.key])
            XCTAssertEqual(rows.first { $0.key == active.key }?.lastUsedAt, expiry)
            XCTAssertEqual(active.key, try restarted.pendingWrite(accountID: "a", path: "/group/activities", body: body, now: expiry.addingTimeInterval(GroupLocalPersistence.pendingWriteRetention + 1)).key,
                           "Even an old matching retry must keep its original key")
        }
    }
    func testLegacyPendingCreationGetsAFullRetentionWindowWithoutChangingIdentity() throws {
        try withPersistence { persistence, root in
            let body = createBody(), encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let legacy = GroupPendingWrite(accountID: "a", path: "", body: try encoder.encode(body), key: "legacy-key")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("pending-writes.json")
            try encoder.encode([legacy]).write(to: url)
            let migration = Date(timeIntervalSince1970: 1_000_000)
            _ = try persistence.pendingWrite(accountID: "b", path: "", body: body, now: migration)
            let rows = try JSONDecoder().decode([GroupPendingWrite].self, from: Data(contentsOf: url))
            XCTAssertEqual(rows.first { $0.key == legacy.key }?.lastUsedAt, migration)
            let restarted = GroupLocalPersistence(root: root)
            XCTAssertEqual(legacy.key, try restarted.pendingWrite(accountID: "a", path: "", body: body, now: migration.addingTimeInterval(1)).key)
            _ = try restarted.pendingWrite(accountID: "b", path: "", body: body, now: migration.addingTimeInterval(GroupLocalPersistence.pendingWriteRetention + 1))
            let pruned = try JSONDecoder().decode([GroupPendingWrite].self, from: Data(contentsOf: url))
            XCTAssertFalse(pruned.contains { $0.key == legacy.key })
        }
    }
    func testGroupCreationLostResponseReplaysAfterRestart() async throws { try await assertCreationRetry(activity: false, malformed: false) }
    func testActivityCreationLostResponseReplaysAfterRestart() async throws { try await assertCreationRetry(activity: true, malformed: false) }
    func testGroupCreationMalformedSuccessRetainsOriginalRequest() async throws { try await assertCreationRetry(activity: false, malformed: true) }
    func testActivityCreationMalformedSuccessRetainsOriginalRequest() async throws { try await assertCreationRetry(activity: true, malformed: true) }
    private func assertCreationRetry(activity: Bool, malformed: Bool) async throws {
        let (tokens, original, session, token) = wireFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token); try? FileManager.default.removeItem(at: root) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let reply = String(decoding: try activity ? JSONEncoder().encode(reminderActivity()) : JSONEncoder().encode(group()), as: UTF8.self)
        let attempts = GroupWriteAttempts()
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["create_group", "create_activity"]); return }
            let index = attempts.append(key: proto.request.value(forHTTPHeaderField: "Idempotency-Key") ?? "", body: proto.bodyData())
            if index == 1 {
                if malformed { proto.reply("{}") }
                else { proto.client?.urlProtocol(proto, didFailWithError: URLError(.networkConnectionLost)) }
            } else { proto.reply(reply) }
        }
        var repository = original; repository.persistence = GroupLocalPersistence(root: root)
        let body = GroupActivityBody(title: "Match", startsAt: 10_000_000, place: "Court", capacity: 4, note: "", format: .singles)
        func submit(_ repository: GroupRepository) async throws {
            if activity { _ = try await repository.createActivity(groupID: "group", body: body, accountID: "a") }
            else { _ = try await repository.createGroup(body: createBody(), accountID: "a") }
        }
        do { try await submit(repository); XCTFail("Expected an uncertain result") }
        catch { if malformed { XCTAssertEqual(error as? APIClientError, .decoding) } else { XCTAssertTrue(error is URLError) } }
        repository.persistence = GroupLocalPersistence(root: root)
        try await submit(repository)
        try await submit(repository) // A separately confirmed new creation gets a fresh key.
        let rows = attempts.snapshot(); XCTAssertEqual(rows.count, 3)
        XCTAssertFalse(rows[0].0.isEmpty); XCTAssertEqual(rows[0].0, rows[1].0); XCTAssertNotEqual(rows[1].0, rows[2].0)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: rows[0].1) as? NSDictionary, try JSONSerialization.jsonObject(with: rows[1].1) as? NSDictionary)
        await tokens.clearAuth()
    }
    func testRejectedCreationClearsOnlyItsOwnPendingRequest() async throws {
        let (tokens, original, session, token) = wireFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token); try? FileManager.default.removeItem(at: root) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        var repository = original; repository.persistence = GroupLocalPersistence(root: root)
        let first = try repository.persistence.pendingWrite(accountID: "a", path: "", body: createBody())
        let other = try repository.persistence.pendingWrite(accountID: "b", path: "", body: createBody())
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["create_group"]); return }
            proto.reply("{\"error\":\"INVALID_GROUP_NAME\"}", status: 422)
        }
        do { _ = try await repository.createGroup(body: createBody(), accountID: "a"); XCTFail("Expected rejection") } catch {}
        XCTAssertNotEqual(first.key, try repository.persistence.pendingWrite(accountID: "a", path: "", body: createBody()).key)
        XCTAssertEqual(other.key, try repository.persistence.pendingWrite(accountID: "b", path: "", body: createBody()).key)
        await tokens.clearAuth()
    }
    func testCreationCannotDispatchBeforeItsRetryIdentityIsPersisted() async throws {
        let (tokens, original, session, token) = wireFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token); try? FileManager.default.removeItem(at: root) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        try Data("not a directory".utf8).write(to: root)
        var repository = original; repository.persistence = GroupLocalPersistence(root: root)
        let requests = GroupWriteAttempts()
        GroupWireProtocol.register(token) { proto in _ = requests.append(key: "unexpected", body: proto.bodyData()); proto.reply("{}") }
        do { _ = try await repository.createGroup(body: createBody(), accountID: "a"); XCTFail("Persistence must fail before dispatch") }
        catch { XCTAssertTrue(error is CocoaError) }
        XCTAssertTrue(requests.snapshot().isEmpty)
        await tokens.clearAuth()
    }
    func testUnauthorizedCreationRetainsKeyAcrossExpiredSessionAndSignIn() async throws {
        let (tokens, original, session, token) = wireFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token); try? FileManager.default.removeItem(at: root) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        var repository = original; repository.persistence = GroupLocalPersistence(root: root)
        let pending = try repository.persistence.pendingWrite(accountID: "a", path: "", body: createBody())
        let attempts = GroupWriteAttempts()
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["create_group"]); return }
            if proto.request.url!.path.hasSuffix("/auth/refresh") { proto.reply("{\"error\":\"TOKEN_EXPIRED\"}", status: 401); return }
            _ = attempts.append(key: proto.request.value(forHTTPHeaderField: "Idempotency-Key") ?? "", body: proto.bodyData())
            proto.reply("{\"error\":\"TOKEN_EXPIRED\"}", status: 401)
        }
        do { _ = try await repository.createGroup(body: createBody(), accountID: "a"); XCTFail("Expected expired session") }
        catch { XCTAssertEqual(error as? APIClientError, .sessionExpired) }
        repository.persistence = GroupLocalPersistence(root: root)
        XCTAssertEqual(pending.key, try repository.persistence.pendingWrite(accountID: "a", path: "", body: createBody()).key)
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let reply = String(decoding: try JSONEncoder().encode(group()), as: UTF8.self)
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["create_group"]); return }
            _ = attempts.append(key: proto.request.value(forHTTPHeaderField: "Idempotency-Key") ?? "", body: proto.bodyData())
            proto.reply(reply)
        }
        _ = try await repository.createGroup(body: createBody(), accountID: "a")
        let rows = attempts.snapshot()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0.0 }, [pending.key, pending.key])
        await tokens.clearAuth()
    }
    func testAccountSwitchDuringCreationRetainsOriginalRetryIdentity() async throws {
        let (tokens, original, session, token) = wireFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token); try? FileManager.default.removeItem(at: root) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        var fixtureRepository = original; fixtureRepository.persistence = GroupLocalPersistence(root: root)
        let repository = fixtureRepository, requested = expectation(description: "create dispatched"), gate = GroupWireGate()
        let reply = String(decoding: try JSONEncoder().encode(group()), as: UTF8.self), attempts = GroupWriteAttempts()
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["create_group"]); return }
            _ = attempts.append(key: proto.request.value(forHTTPHeaderField: "Idempotency-Key") ?? "", body: proto.bodyData())
            requested.fulfill(); gate.hold { proto.reply(reply) }
        }
        let body = createBody()
        let task = Task { try await repository.createGroup(body: body, accountID: "a") }
        await fulfillment(of: [requested], timeout: 3)
        try await tokens.setAuth(token: "new-" + token, expiresAt: Date().addingTimeInterval(3600))
        gate.release()
        do { _ = try await task.value; XCTFail("Old session must not accept a response") } catch { XCTAssertTrue(error is CancellationError) }
        let rows = attempts.snapshot(); XCTAssertEqual(rows.count, 1)
        let pending = try GroupLocalPersistence(root: root).pendingWrite(accountID: "a", path: "", body: body)
        XCTAssertEqual(rows.first?.0, pending.key)
        XCTAssertNotEqual(pending.key, try repository.persistence.pendingWrite(accountID: "b", path: "", body: body).key)
        await tokens.clearAuth()
    }
    func testFailedActivityRefreshPreservesReminderAndSuccessfulEmptyRefreshRemovesIt() throws {
        try withReminder { manager, activity in
            manager.synchronize(accountID: "a", group: group(), memberID: "me", activities: nil)
            XCTAssertTrue(manager.enabled(accountID: "a", activityID: activity.id))
            manager.synchronize(accountID: "a", group: group(), memberID: "me", activities: [activity])
            XCTAssertTrue(manager.enabled(accountID: "a", activityID: activity.id))
            manager.synchronize(accountID: "a", group: group(), memberID: "me", activities: [])
            XCTAssertFalse(manager.enabled(accountID: "a", activityID: activity.id))
        }
    }
    func testReadOnlyGroupClearsRemindersEvenWhenActivitiesFailed() throws {
        for status in ["archived", "dissolving"] {
            try withReminder { manager, activity in
                var current = group(); current.status = status
                manager.synchronize(accountID: "a", group: current, memberID: "me", activities: nil)
                XCTAssertFalse(manager.enabled(accountID: "a", activityID: activity.id), status)
            }
        }
    }
    func testSuccessfulCancelledActivityOrUnregistrationStillRemovesReminder() throws {
        for cancelled in [false, true] {
            try withReminder { manager, initial in
                var activity = initial
                if cancelled { activity.status = "cancelled" } else { activity.registeredMemberIds = [] }
                manager.synchronize(accountID: "a", group: group(), memberID: "me", activities: [activity])
                XCTAssertFalse(manager.enabled(accountID: "a", activityID: activity.id))
            }
        }
    }
    private func withReminder(_ work: (GroupActivityReminder, GroupActivity) throws -> Void) throws {
        let suite = "group-reminder-review-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let activity = reminderActivity()
        let row: [String: Any] = ["accountID": "a", "groupID": "group", "activityID": activity.id, "title": activity.title, "place": activity.place, "startsAt": activity.startsAt]
        defaults.set(try JSONSerialization.data(withJSONObject: [row]), forKey: "groups.activityReminders")
        try work(GroupActivityReminder(defaults: defaults), activity)
    }
    func testPersistedUploadFailuresResolveCurrentCopyInAll47Languages() throws {
        try withPersistence { persistence, root in
            let legacy = GroupPendingUpload(id: "record", accountID: "a", groupID: "group", key: "key", body: body(), failure: "小组已归档", failureCode: "GROUP_ARCHIVED")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode([legacy]).write(to: root.appendingPathComponent("outbox.json"))
            let restored = try XCTUnwrap(GroupLocalPersistence(root: root).uploads(accountID: "a").first)
            XCTAssertEqual(LocalizationTestSupport.promotedLocales.count, 47)
            for locale in LocalizationTestSupport.promotedLocales {
                let bundle = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"))))
                XCTAssertEqual(restored.failureMessage(bundle: bundle), bundle.localizedString(forKey: "group_archive_readonly", value: nil, table: nil), locale)
                var uncoded = restored; uncoded.failureCode = nil
                XCTAssertEqual(uncoded.failureMessage(bundle: bundle), bundle.localizedString(forKey: "group_save_failed", value: nil, table: nil), locale)
                uncoded.body.setScore = .init(a: 0, b: 0)
                XCTAssertEqual(uncoded.failureMessage(bundle: bundle), bundle.localizedString(forKey: "group_invalid_result", value: nil, table: nil), locale)
            }
            try persistence.updateRetry("record", accountID: "a", code: "GROUP_ARCHIVED", failure: "小组已归档", next: nil)
            XCTAssertEqual(persistence.uploads(accountID: "a").first?.failure, "GROUP_ARCHIVED")
            try persistence.updateRetry("record", accountID: "a", code: "RATE_LIMITED", failure: nil, next: Date().addingTimeInterval(30))
            XCTAssertNil(persistence.uploads(accountID: "a").first?.failureMessage())
            try persistence.markFailure("record", accountID: "a", message: "旧的本地化失败文案")
            XCTAssertEqual(persistence.uploads(accountID: "a").first?.failure, "UPLOAD_FAILED")
            XCTAssertEqual(persistence.uploads(accountID: "a").first?.failureCode, "UPLOAD_FAILED")
        }
    }
    func testOldAccountCompletionCannotUnlockCurrentAccount() async throws { try await assertMutationIsolation(returnToOriginalAccount: false) }
    func testOldLoginCompletionCannotUnlockLaterLoginOfSameAccount() async throws { try await assertMutationIsolation(returnToOriginalAccount: true) }
    private func assertMutationIsolation(returnToOriginalAccount: Bool) async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        let defaults = UserDefaults.standard, oldLast = defaults.object(forKey: "groups.lastAccountID"), oldEnabled = defaults.object(forKey: "groups.enabled")
        defaults.set(true, forKey: "groups.enabled")
        defer { defaults.set(oldLast, forKey: "groups.lastAccountID"); defaults.set(oldEnabled, forKey: "groups.enabled") }
        let a = "review-a-" + UUID().uuidString, b = "review-b-" + UUID().uuidString
        let account = GroupTestAccount(a)
        let store = GroupStore(observeConnectivity: false, signedInAccountID: { account.id }); store.repository = repository
        defer { store.sessionDidChange(userID: nil) }
        store.sessionDidChange(userID: a)
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let gateA = GroupOperationGate(), gateB = GroupOperationGate()
        let startedA = expectation(description: "A writing"), startedB = expectation(description: "current account writing")
        let taskA = Task { await store.perform { startedA.fulfill(); await gateA.wait() } }
        await fulfillment(of: [startedA], timeout: 3)
        account.id = b; store.sessionDidChange(userID: b)
        if returnToOriginalAccount { account.id = a; store.sessionDidChange(userID: a) }
        try await tokens.setAuth(token: "later-" + token, expiresAt: Date().addingTimeInterval(3600))
        let taskB = Task { await store.perform { startedB.fulfill(); await gateB.wait() } }
        await fulfillment(of: [startedB], timeout: 3)
        XCTAssertTrue(store.mutating)
        gateA.release(); let acceptedA = await taskA.value
        XCTAssertFalse(acceptedA); XCTAssertTrue(store.mutating, "Old completion must leave the current write locked")
        gateB.release(); let acceptedB = await taskB.value
        XCTAssertTrue(acceptedB); XCTAssertFalse(store.mutating)
        await tokens.clearAuth()
    }
}

extension GroupPortParityTests {
    private func directBody() -> GroupDirectLineupBody {
        .init(title: "", startsAt: 1_000_000, place: "Gym", format: .singles, timingMode: "sequence", sessionMinutes: 30,
              sessions: [.init(orderNo: 1, court: "1", startsAt: 1_000_000, format: .singles,
                               seats: [.init(memberId: "a", side: "A", seat: 0), .init(memberId: "b", side: "B", seat: 0)])])
    }
    private func lineupOriginal(id: String = "existing", seats: [GroupSeat], needsLineup: Bool = false, frozen: Bool = false) -> GroupActivitySession {
        .init(id: id, activityId: "activity", groupId: "group", orderNo: 1, court: "1", startsAt: 1_000_000,
              endsAt: 2_800_000, format: .doubles, status: frozen ? "started" : "scheduled", seats: seats,
              needsLineup: needsLineup, isFrozen: frozen)
    }
    private func lineupDraft(_ original: GroupActivitySession) -> GroupTrainingDraftSession {
        var row = GroupTrainingDraftSession(startsAt: original.date, court: original.court, format: original.format)
        row.serverID = original.id; row.frozen = original.frozen
        for seat in original.seats { row.memberIDs[(seat.side == "A" ? 0 : 2) + seat.seat] = seat.memberId }
        return row
    }

    func testCancellationReasonLimitsMatchServerUTF16WithoutSplittingCharacters() {
        for reason in ["", " \n\t", String(repeating: "球", count: 300), String(repeating: "😀", count: 150)] {
            XCTAssertTrue(GroupActivityPolicy.validCancellationReason(reason))
            XCTAssertEqual(GroupActivityPolicy.limitedCancellationReason(reason), reason)
        }
        for reason in [String(repeating: "球", count: 301), String(repeating: "😀", count: 151)] {
            XCTAssertFalse(GroupActivityPolicy.validCancellationReason(reason))
        }
        XCTAssertEqual(GroupActivityPolicy.limitedCancellationReason(String(repeating: "球", count: 301)), String(repeating: "球", count: 300))
        XCTAssertEqual(GroupActivityPolicy.limitedCancellationReason(String(repeating: "😀", count: 151)), String(repeating: "😀", count: 150))
        let nearLimit = String(repeating: "A", count: 299)
        XCTAssertEqual(GroupActivityPolicy.limitedCancellationReason(nearLimit + "😀"), nearLimit)
        XCTAssertEqual(GroupActivityPolicy.limitedCancellationReason(nearLimit + "e\u{301}"), nearLimit)
    }

    func testRegistrationDeadlineFollowsStartUnlessCustomAndCanFollowAgain() {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let later = start.addingTimeInterval(3600)
        XCTAssertTrue(GroupActivityPolicy.registrationFollowsStart(closes: start, starts: start))
        XCTAssertEqual(GroupActivityPolicy.registrationCloseAfterStartChange(closes: start, previousStart: start, newStart: later), later)
        let custom = start.addingTimeInterval(-1800)
        XCTAssertFalse(GroupActivityPolicy.registrationFollowsStart(closes: custom, starts: start))
        XCTAssertEqual(GroupActivityPolicy.registrationCloseAfterStartChange(closes: custom, previousStart: start, newStart: later), custom)
        // Restoring the current start time re-enables following subsequent start-time edits.
        XCTAssertEqual(GroupActivityPolicy.registrationCloseAfterStartChange(closes: later, previousStart: later, newStart: later.addingTimeInterval(600)), later.addingTimeInterval(600))
    }

    func testConfirmedRegistrationDeadlineUsesExactStartForTheSameLocalMinute() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 19, minute: 30, second: 37))).addingTimeInterval(0.456)
        let minuteSelection = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 19, minute: 30)))
        let confirmed = GroupActivityPolicy.registrationCloseAfterSelection(minuteSelection, starts: start, calendar: calendar)
        XCTAssertEqual(confirmed, start, "Minute-only pickers must recover the start's seconds and subsecond precision")
        XCTAssertTrue(GroupActivityPolicy.registrationFollowsStart(closes: confirmed, starts: start))
        let nextStart = start.addingTimeInterval(3600)
        XCTAssertEqual(GroupActivityPolicy.registrationCloseAfterStartChange(closes: confirmed, previousStart: start, newStart: nextStart), nextStart)
        for custom in [minuteSelection.addingTimeInterval(-60), minuteSelection.addingTimeInterval(60), minuteSelection.addingTimeInterval(-86400)] {
            XCTAssertEqual(GroupActivityPolicy.registrationCloseAfterSelection(custom, starts: start, calendar: calendar), custom,
                "Different minutes and dates keep the selected deadline")
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(GroupActivityPolicy.registrationCloseAfterSelection(minuteSelection, starts: start, calendar: utc), start)
    }

    func testRegistrationDeadlineModeDoesNotChangeBeforePickerConfirmation() {
        let start = Date(timeIntervalSince1970: 2_000_017.456)
        let custom = start.addingTimeInterval(-17.456)
        let later = start.addingTimeInterval(3600)
        // Opening or cancelling the picker does not assign its pending value to the binding.
        // Existing data remains an exact-date comparison until a selection is confirmed.
        XCTAssertFalse(GroupActivityPolicy.registrationFollowsStart(closes: custom, starts: start))
        XCTAssertEqual(GroupActivityPolicy.registrationCloseAfterStartChange(closes: custom, previousStart: start, newStart: later), custom)
        XCTAssertTrue(GroupActivityPolicy.registrationFollowsStart(closes: start, starts: start))
        XCTAssertEqual(GroupActivityPolicy.registrationCloseAfterStartChange(closes: start, previousStart: start, newStart: later), later)
    }

    func testPendingUploadShowsOnlyAnApplicableActionAndNeedsARealCloudIdentity() {
        var row = GroupPendingUpload(id: "record", accountID: "a", groupID: "group", key: "stable-key", body: body())
        XCTAssertEqual(row.primaryAction, .retry)
        row.failureCode = "INVALID_SET_SCORE"; row.failure = nil; row.body.gameId = nil
        XCTAssertEqual(row.primaryAction, .repair, "Stable codes also classify records without a legacy failure string")
        row.failure = "NETWORK_FAILED"; XCTAssertEqual(row.primaryAction, .repair, "The stable code takes precedence over legacy text")
        row.failureCode = nil; row.body.gameId = "game"
        XCTAssertEqual(row.primaryAction, .retry)
        for code in ["RULES_REVIEW_REQUIRED", "INVALID_RESULT", "INVALID_MATCH_RESULT", "INVALID_SET_SCORE", "INVALID_SET_DETAILS", "INVALID_RULES", "RULES_CONFLICT"] {
            row.failure = code; row.body.gameId = "game"
            XCTAssertEqual(row.primaryAction, .viewFrozenConfiguration, code)
            row.body.gameId = nil
            XCTAssertEqual(row.primaryAction, .repair, code)
        }
        for code in ["RESULT_CONFLICT", "GAME_EXISTS", "GAME_ABANDONED"] {
            row.failure = code; row.body.gameId = "game"
            XCTAssertEqual(row.primaryAction, .viewFrozenConfiguration, code)
            row.body.gameId = nil; XCTAssertNil(row.primaryAction, "A conflict alone does not identify a cloud result")
        }
        row.failure = "GROUP_DISSOLVING"; XCTAssertNil(row.primaryAction)
        row.failure = "GROUP_ARCHIVED"; XCTAssertEqual(row.primaryAction, .retry)
        row.failure = "RESULT_CONFLICT"; row.existingResultID = "  "
        XCTAssertNil(row.primaryAction)
        row.existingResultID = "cloud-result"; XCTAssertEqual(row.primaryAction, .viewCloudResult)
        row.uploaded = true; XCTAssertNil(row.primaryAction)
    }

    func testPendingUploadActionClassificationDoesNotChangeDurableRecord() throws {
        try withPersistence { persistence, root in
            try persistence.enqueueManual(body(), id: "record", accountID: "a", groupID: "group", key: "stable-key")
            try persistence.updateRetry("record", accountID: "a", code: "INVALID_RESULT", failure: "invalid", next: nil)
            let path = root.appendingPathComponent("outbox.json")
            let original = try Data(contentsOf: path)
            let row = try XCTUnwrap(GroupLocalPersistence(root: root).uploads(accountID: "a").first)
            XCTAssertEqual(row.primaryAction, .viewFrozenConfiguration)
            XCTAssertEqual(row.id, "record"); XCTAssertEqual(row.key, "stable-key")
            XCTAssertEqual(row.body.gameId, "game"); XCTAssertEqual(row.body.clientSessionId, "session")
            XCTAssertEqual(try Data(contentsOf: path), original)
            XCTAssertEqual(GroupLocalPersistence(root: root).uploads(accountID: "a").count, 1)
        }
    }

    func testMemberNameLimitStaysAt24ScalarsIndependentlyOfGroupNames() {
        XCTAssertEqual(GroupInputValidation.memberNameMax, 24)
        for unit in ["球", "😀"] {
            XCTAssertTrue(GroupInputValidation.validName(" " + String(repeating: unit, count: 24) + " "))
            XCTAssertFalse(GroupInputValidation.validName(String(repeating: unit, count: 25)))
        }
    }

    func testGroupNameUsesServerScalarLimitsWhileDescriptionUsesUTF16() {
        for unit in ["球", "😀"] {
            XCTAssertTrue(GroupInputValidation.validName(" " + String(repeating: unit, count: 24) + " ", minimum: 2, maximum: 24))
            XCTAssertFalse(GroupInputValidation.validName(unit, minimum: 2, maximum: 24))
            XCTAssertFalse(GroupInputValidation.validName(String(repeating: unit, count: 25), minimum: 2, maximum: 24))
        }
        XCTAssertTrue(GroupInputValidation.validName("e\u{301}", minimum: 2, maximum: 24), "Two Unicode scalars, one grapheme")
        XCTAssertTrue(GroupInputValidation.validText(String(repeating: "😀", count: 100), maximum: 200))
        XCTAssertFalse(GroupInputValidation.validText(String(repeating: "😀", count: 101), maximum: 200))
    }

    func testActivityTextLimitsMatchTheServerIncludingAutomaticTitles() {
        XCTAssertTrue(GroupActivityPolicy.validText(title: "", place: "", note: ""))
        XCTAssertTrue(GroupActivityPolicy.validText(title: "  ", place: ""))
        XCTAssertTrue(GroupActivityPolicy.validText(title: String(repeating: "球", count: 40), place: String(repeating: "馆", count: 80), note: String(repeating: "注", count: 300)))
        XCTAssertFalse(GroupActivityPolicy.validText(title: String(repeating: "球", count: 41), place: ""))
        XCTAssertFalse(GroupActivityPolicy.validText(title: "", place: String(repeating: "馆", count: 81)))
        XCTAssertFalse(GroupActivityPolicy.validText(title: "", place: "", note: String(repeating: "注", count: 301)))
        XCTAssertTrue(GroupActivityPolicy.validText(title: String(repeating: "🏸", count: 40), place: String(repeating: "🏸", count: 40)))
        XCTAssertFalse(GroupActivityPolicy.validText(title: "", place: String(repeating: "🏸", count: 41)))
        for count in [200, 201, 300] { XCTAssertTrue(GroupActivityPolicy.validText(title: "", place: "", note: String(repeating: "x", count: count))) }
    }
    func testActivityCapacityUsesFormatAndRegistrationsInsteadOfGroupCapacity() {
        XCTAssertEqual(GroupActivityPolicy.defaultJoinPolicy, "open")
        XCTAssertEqual(GroupActivityPolicy.minimumCapacity(format: .singles), 2)
        XCTAssertEqual(GroupActivityPolicy.minimumCapacity(format: .doubles), 4)
        XCTAssertEqual(GroupActivityPolicy.minimumCapacity(format: .doubles, registeredCount: 8), 8)
        XCTAssertTrue(GroupActivityPolicy.validCapacity(100, format: .doubles))
        XCTAssertFalse(GroupActivityPolicy.validCapacity(101, format: .singles))
        XCTAssertFalse(GroupActivityPolicy.validCapacity(3, format: .doubles))
        XCTAssertFalse(GroupActivityPolicy.validCapacity(4, format: .doubles, registeredCount: 5))
        XCTAssertFalse(GroupActivityPolicy.validCapacity(100, format: .singles, registeredCount: 101))
        XCTAssertEqual(GroupActivityPolicy.durationOptions(current: 30), [20,30,45,60])
        XCTAssertEqual(GroupActivityPolicy.durationOptions(current: 35), [20,30,35,45,60])
    }
    func testExistingLineupCanBeClearedButNewSchedulesCannotBeEmpty() {
        XCTAssertNil(GroupTrainingValidation.lineupProblem([], minutes: 30, allowsEmpty: true))
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([], minutes: 30), .incomplete)
        let frozen = lineupOriginal(seats: [], frozen: true)
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([], minutes: 30, allowsEmpty: true, originals: [frozen]), .frozen)
    }
    func testUnchangedMissingLineupPreservesSeatPositionsAndAllowsOtherEdits() {
        let seats: [GroupSeat] = [.init(memberId: "a", side: "A", seat: 1), .init(memberId: "b", side: "B", seat: 0)]
        let original = lineupOriginal(seats: seats, needsLineup: true)
        let row = lineupDraft(original)
        XCTAssertEqual(row.body(orderNo: 1).seats, seats)
        var other = GroupTrainingDraftSession(startsAt: original.date.addingTimeInterval(3600), court: "2")
        other.memberIDs = ["c", "", "d", ""]
        XCTAssertNil(GroupTrainingValidation.lineupProblem([row, other], minutes: 30, originals: [original], allowedMemberIDs: ["a","b","c","d"]))
        var changed = row; changed.court = "New court"
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([changed], minutes: 30, originals: [original]), .incomplete)
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([row], minutes: 30), .incomplete)
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([other], minutes: 30, allowedMemberIDs: ["c"]), .incomplete)
    }
    func testFrozenLineupCannotBeChangedRemovedOrReordered() {
        let original = lineupOriginal(seats: [.init(memberId: "a", side: "A", seat: 0), .init(memberId: "a2", side: "A", seat: 1), .init(memberId: "b", side: "B", seat: 0), .init(memberId: "b2", side: "B", seat: 1)], frozen: true)
        let row = lineupDraft(original)
        XCTAssertNil(GroupTrainingValidation.lineupProblem([row], minutes: 30, originals: [original], allowedMemberIDs: []))
        var changed = row; changed.startsAt.addTimeInterval(60)
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([changed], minutes: 30, originals: [original]), .frozen)
        var first = GroupTrainingDraftSession(); first.memberIDs = ["c", "", "d", ""]
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([first, row], minutes: 30, originals: [original]), .frozen)
    }
    func testDirectLineupRetryPersistsKeyAndFirstAnchoredPayloadPerAccountAndGroup() throws {
        try withPersistence { persistence, root in
            let raw = directBody(), now = Date(timeIntervalSince1970: 10_000)
            let first = try persistence.pendingDirectLineup(accountID: "a", groupID: "group", body: raw, now: now)
            XCTAssertEqual(first.body.startsAt, 10_060_000)
            XCTAssertEqual(first.body.sessions[0].startsAt, first.body.startsAt)
            let restarted = GroupLocalPersistence(root: root)
            let retry = try restarted.pendingDirectLineup(accountID: "a", groupID: "group", body: raw, now: now.addingTimeInterval(600))
            XCTAssertEqual(first.key, retry.key); XCTAssertEqual(first.body.startsAt, retry.body.startsAt)
            let otherAccount = try restarted.pendingDirectLineup(accountID: "b", groupID: "group", body: raw)
            let otherGroup = try restarted.pendingDirectLineup(accountID: "a", groupID: "other", body: raw)
            XCTAssertNotEqual(first.key, otherAccount.key); XCTAssertNotEqual(first.key, otherGroup.key)
            var edited = raw; edited.place = "Other gym"
            XCTAssertNotEqual(try restarted.pendingDirectLineup(accountID: "a", groupID: "group", body: edited).key, first.key)
            try restarted.completeDirectLineup(key: first.key, accountID: "b")
            XCTAssertEqual(try restarted.pendingDirectLineup(accountID: "a", groupID: "group", body: raw).key, first.key)
            try restarted.completeDirectLineup(key: first.key, accountID: "a")
            XCTAssertNotEqual(try restarted.pendingDirectLineup(accountID: "a", groupID: "group", body: raw).key, first.key)
            restarted.deleteAccountData(accountID: "a")
            XCTAssertThrowsError(try restarted.pendingDirectLineup(accountID: "a", groupID: "group", body: raw))
            XCTAssertEqual(try restarted.pendingDirectLineup(accountID: "b", groupID: "group", body: raw).key, otherAccount.key)
        }
    }
    func testDirectLineupLostResponseReusesTheSameWireRequestAfterRestart() async throws {
        let (tokens, originalRepository, session, token) = wireFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token); try? FileManager.default.removeItem(at: root) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let attempts = GroupWriteAttempts()
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["create_activity"]); return }
            let index = attempts.append(key: proto.request.value(forHTTPHeaderField: "Idempotency-Key") ?? "", body: proto.bodyData())
            if index == 1 { proto.client?.urlProtocol(proto, didFailWithError: URLError(.networkConnectionLost)) }
            else { proto.reply("{\"activityId\":\"created-once\",\"groupId\":\"group\"}") }
        }
        var repository = originalRepository; repository.persistence = GroupLocalPersistence(root: root)
        do { _ = try await repository.createDirectLineup(groupID: "group", body: directBody(), accountID: "account"); XCTFail("Expected the lost response") }
        catch { XCTAssertTrue(error is URLError, "Unexpected transport failure: \(error)") }
        repository.persistence = GroupLocalPersistence(root: root)
        let result = try await repository.createDirectLineup(groupID: "group", body: directBody(), accountID: "account")
        XCTAssertEqual(result.activityId, "created-once")
        let rows = attempts.snapshot(); XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows[0].0.isEmpty); XCTAssertEqual(rows[0].0, rows[1].0)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: rows[0].1) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: rows[1].1) as? NSDictionary)
        await tokens.clearAuth()
    }
    func testWriteCapabilityMappingCoversActivityAndManagementOperations() {
        let cases: [(String, HTTPMethod, String?)] = [
            ("/g/activities", .post, "create_activity"), ("/g/direct-lineups", .post, "create_activity"),
            ("/g/activities/a", .patch, "update_activity"), ("/g/activities/a/lineup", .put, "update_activity"),
            ("/g/activities/a/cancel", .post, "update_activity"), ("/g/activities/a/register", .post, "register_activity"),
            ("/g/results/r/confirm", .post, "confirm_result"), ("/g/results/r/void", .post, "void_result"),
            ("/g/members/m", .patch, "manage_members"), ("/g/members/m/remove", .post, "manage_members"),
            ("/g", .patch, "manage_group"), ("/g/dissolve/cancel", .post, "manage_group"),
            ("/g/leave", .post, nil), ("/g/report", .post, nil), ("/g/activities", .get, nil)
        ]
        for (path, method, expected) in cases { XCTAssertEqual(GroupWriteCapability.required(for: path, method: method), expected, path) }
    }
    func testDisabledActivityCapabilityDoesNotSendAWriteRequest() async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        GroupWireProtocol.register(token) { proto in
            XCTAssertEqual(proto.request.httpMethod, "GET", "A disabled action must never send a write")
            XCTAssertTrue(proto.request.url!.path.hasSuffix("/capabilities"))
            proto.replyCapabilities(actions: ["join_group"])
        }
        do { let _: EmptyResponse = try await repository.write("/group/activities", body: EmptyRequest()); XCTFail("Expected disabled action") }
        catch { guard case APIClientError.server(status: 409, code: "ACTION_DISABLED", message: _, nextAvailableAt: _) = error else { return XCTFail("Unexpected error: \(error)") } }
        await tokens.clearAuth()
    }
    func testInvitationDownloadFallbackUsesTheSameRegionAsTheJoinLink() {
        for (region, domain) in [("CN", "https://jifenqi.com"), ("US", "https://iscoreboard.live"), ("HK", "https://iscoreboard.live")] {
            let text = GroupInvitationText.message(group: group(), regionCode: region, localization: "en")
            XCTAssertTrue(text.contains(domain + "/groups/join?groupNo=123456"))
            XCTAssertTrue(text.contains(domain + "/download"))
        }
    }
}

private nonisolated final class GroupWireProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var handlers: [String: @Sendable (GroupWireProtocol) -> Void] = [:]
        func put(_ token: String, _ handler: (@Sendable (GroupWireProtocol) -> Void)?) { lock.lock(); defer { lock.unlock() }; handlers["Bearer " + token] = handler }
        func get(_ token: String) -> (@Sendable (GroupWireProtocol) -> Void)? { lock.lock(); defer { lock.unlock() }; return handlers[token] }
    }
    private static let registry = Registry()
    static func register(_ token: String, _ handler: @escaping @Sendable (GroupWireProtocol) -> Void) { registry.put(token, handler) }
    static func remove(_ token: String) { registry.put(token, nil) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { guard let handler = Self.registry.get(request.value(forHTTPHeaderField: "Authorization") ?? "") else { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)); return }; handler(self) }
    override func stopLoading() {}
    func reply(_ body: String, status: Int = 200) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    func replyCapabilities(actions: [String]) {
        let value: [String: Any] = ["groupNoLength": 6, "nameMin": 2, "nameMax": 24, "descriptionMax": 200,
            "memberLimitDefault": 30, "memberLimitMax": 50, "allowedActions": actions]
        reply(String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!)
    }
    func bodyData() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
        return data
    }
}
private nonisolated final class GroupWireGate: @unchecked Sendable {
    let lock = NSLock(); var reply: (() -> Void)?; var released = false
    func hold(_ work: @escaping () -> Void) { lock.lock(); if released { lock.unlock(); work() } else { reply = work; lock.unlock() } }
    func release() { lock.lock(); released = true; let work = reply; reply = nil; lock.unlock(); work?() }
}

extension GroupPortParityTests {
    private func wireFixture() -> (AuthTokenStore, GroupRepository, URLSession, String) {
        let token = "group-fixture-" + UUID().uuidString
        let tokens = AuthTokenStore(service: "com.douhua.jifen.group-wire-tests." + token)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [GroupWireProtocol.self]
        let session = URLSession(configuration: config)
        return (tokens, GroupRepository(client: APIClient(session: session, tokenStore: tokens)), session, token)
    }
    func testPaginationReadsAllPagesWithPinnedAuthentication() async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        GroupWireProtocol.register(token) { proto in
            let query = URLComponents(url: proto.request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            XCTAssertEqual(query.first { $0.name == "limit" }?.value, "100")
            XCTAssertEqual(proto.request.url!.path, "/api/groups/g/members")
            if query.contains(where: { $0.name == "cursor" && $0.value == "next" }) { proto.reply("{\"items\":[\"b\"],\"nextCursor\":null}") }
            else { proto.reply("{\"items\":[\"a\"],\"nextCursor\":\"next\"}") }
        }
        let rows: [String] = try await repository.allPages("/g/members")
        XCTAssertEqual(rows, ["a", "b"]); await tokens.clearAuth()
    }
    func testRepeatedPaginationCursorFailsInsteadOfLooping() async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        GroupWireProtocol.register(token) { $0.reply("{\"items\":[],\"nextCursor\":\"stuck\"}") }
        do { let _: [String] = try await repository.allPages("/g/members"); XCTFail("Repeated cursor must fail") }
        catch { guard case GroupFlowError.repeatedCursor = error else { return XCTFail("Unexpected error: \(error)") } }
        await tokens.clearAuth()
    }
    func testSameAccountReloginRejectsInFlightGroupPagination() async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let requested = expectation(description: "group page requested"), gate = GroupWireGate()
        GroupWireProtocol.register(token) { proto in requested.fulfill(); gate.hold { proto.reply("{\"items\":[\"stale\"],\"nextCursor\":\"next\"}") } }
        let task = Task<[String], Error> { try await repository.allPages("/g/members") }
        await fulfillment(of: [requested], timeout: 3)
        await tokens.clearAuth(); try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600)); gate.release()
        do { _ = try await task.value; XCTFail("Stale login session must not reach a second page") }
        catch { XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)") }
        await tokens.clearAuth()
    }
    func testProfilePatchSendsOnlyChangedFieldsWithoutIfMatch() async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["manage_group"]); return }
            XCTAssertNil(proto.request.value(forHTTPHeaderField: "If-Match"))
            XCTAssertEqual(proto.request.httpMethod, "PATCH")
            XCTAssertEqual(try? JSONSerialization.jsonObject(with: proto.bodyData()) as? [String: String], ["description": "新简介"])
            proto.reply("""
                {"id":"g","groupNo":"82603158","name":"其他管理员的新名称","description":"新简介","sport":"badminton","status":"active","joinPolicy":"closed","ownerMemberId":"owner","memberLimit":30,"createdAt":1,"updatedAt":2,"revision":9}
                """)
        }
        let original = GroupProfileFields(name: "原名称", description: "原简介", joinPolicy: "open")
        var edited = original; edited.description = "新简介"
        let saved: ScoreGroup = try await repository.write("/g", body: edited.changes(from: original, canEditJoinPolicy: true), method: .patch)
        XCTAssertEqual(saved.name, "其他管理员的新名称"); XCTAssertEqual(saved.joinPolicy, "closed")
        await tokens.clearAuth()
    }

    func testOtherConditionalActionsIncludeIfMatchAndDoNotMutateInput() async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["manage_group", "restore_group"]); return }
            XCTAssertEqual(proto.request.value(forHTTPHeaderField: "If-Match"), "\"7\"")
            XCTAssertEqual(proto.request.httpMethod, "PATCH")
            proto.reply("{\"error\":\"REVISION_CONFLICT\",\"message\":\"reload\"}", status: 409)
        }
        let input = GroupActionBody(name: "Preserve this input", description: "draft", joinPolicy: "approval")
        do { let _: ScoreGroup = try await repository.write("/g/restore", body: input, method: .patch, revision: 7); XCTFail("Expected conflict") }
        catch { guard case APIClientError.server(status: 409, code: _, message: _, nextAvailableAt: _) = error else { return XCTFail("Unexpected error: \(error)") } }
        XCTAssertEqual(input.name, "Preserve this input"); XCTAssertEqual(input.description, "draft"); await tokens.clearAuth()
    }
    func testScheduleShiftUsesDurationAndPreservesFrozenIdentityAndTime() {
        let time = Date(timeIntervalSince1970: 10000)
        var a = GroupTrainingDraftSession(startsAt: time); a.serverID = "a"
        var frozen = GroupTrainingDraftSession(startsAt: time.addingTimeInterval(7200)); frozen.serverID = "frozen"; frozen.frozen = true
        var c = GroupTrainingDraftSession(startsAt: time.addingTimeInterval(14400)); c.serverID = "c"
        let shifted = GroupTrainingValidation.shifted([a, frozen, c], from: a.id, minutes: 45)
        XCTAssertEqual(shifted[0].startsAt, a.startsAt); XCTAssertEqual(shifted[1], frozen)
        XCTAssertEqual(shifted[2].startsAt, frozen.startsAt.addingTimeInterval(2700)); XCTAssertEqual(shifted[2].serverID, "c")
    }
    func testSeparateTrainingPlanConflictChecksTimeCourtAndMembers() {
        let time = Date(timeIntervalSince1970: 10000)
        var own = GroupTrainingDraftSession(startsAt: time, court: "1"); own.memberIDs = ["a", "", "b", ""]
        let other = GroupTrainingSession(id: "session", planId: "other", groupId: "group", orderNo: 1, court: "2", startsAt: 10000000, endsAt: 12700000, format: .singles, status: "scheduled", resultId: "", seats: [.init(memberId: "b", side: "A", seat: 0), .init(memberId: "c", side: "B", seat: 0)], mySide: nil)
        let plan = GroupTrainingPlan(id: "other", groupId: "group", creatorMemberId: "owner", trainingDate: 10000000, startsAt: 10000000, endsAt: 12700000, sessionMinutes: 45, place: "Gym", note: "", status: "published", cancelReason: "", publishedAt: 1, sessionCount: 1, mySessionCount: 0, sessions: [other], createdAt: 1, revision: 1)
        XCTAssertEqual(GroupTrainingValidation.otherPlanConflicts([own], minutes: 45, place: "Gym", plans: [plan], excluding: nil).map(\.id), ["session"])
        XCTAssertTrue(GroupTrainingValidation.otherPlanConflicts([own], minutes: 45, place: "Gym", plans: [plan], excluding: "other").isEmpty)
        own.startsAt = time.addingTimeInterval(2700)
        XCTAssertTrue(GroupTrainingValidation.otherPlanConflicts([own], minutes: 45, place: "Gym", plans: [plan], excluding: nil).isEmpty)
    }
    func testJoinAvailabilitySeparatesCapacityLifecycleAndPendingApplication() throws {
        func preview(_ fields: String) throws -> GroupPreview {
            try JSONDecoder().decode(GroupPreview.self, from: Data(("{\"groupNo\":\"123456\",\"name\":\"Test\",\"memberCount\":1," + fields + "}").utf8))
        }
        XCTAssertEqual(try preview("\"joinPolicy\":\"open\",\"availability\":\"pending_approval\",\"status\":\"active\"").effectiveAvailability, "available")
        XCTAssertEqual(try preview("\"joinPolicy\":\"closed\",\"availability\":\"pending_approval\",\"status\":\"active\"").effectiveAvailability, "closed")
        XCTAssertTrue(try preview("\"joinPolicy\":\"closed\",\"availability\":\"pending_approval\",\"status\":\"active\"").hasPendingRequest)
        XCTAssertEqual(try preview("\"joinPolicy\":\"closed\",\"availability\":\"already_member\",\"status\":\"archived\"").effectiveAvailability, "already_member")
        XCTAssertEqual(try preview("\"joinPolicy\":\"open\",\"availability\":\"available\",\"status\":\"dissolving\"").effectiveAvailability, "dissolving")
    }
}

extension GroupPortParityTests {
    func testCustomRulesReachNativeEnginesAndRoundTripForBothFormats() {
        for sport in GroupSport.allCases {
            var value = rules(); value.sport = sport
            value.maxSets = sport == .tennis ? 1 : 4; value.matchCompletionMode = sport == .tennis ? "best_of" : "play_all"
            value.pointsToWinSet = sport == .tennis ? 6 : 7; value.pointCap = nil; value.winByTwo = false; value.useRallyScoring = false
            for format in GroupFormat.allCases {
                let setup = value.setup(format: format)
                XCTAssertEqual(GroupMatchRules(sport: sport, setup: setup), value)
                if sport == .tennis { XCTAssertEqual(setup.tennisRules.maxSets, 1); continue }
                let native = sport == .badminton ? setup.badmintonRules : sport == .tableTennis ? setup.pingPongRules : setup.pickleballRules
                XCTAssertEqual(native.pointsToWinSet, 7); XCTAssertEqual(native.maxSets, 4); XCTAssertNil(native.pointCap)
                XCTAssertFalse(native.winByTwo); XCTAssertFalse(native.useRallyScoring)
            }
        }
    }
    func testWaitingConfirmationNamesExcludeTemporaryAndRemovedParticipants() {
        let members = [member("a"), member("a2"), member("b", kind: "temporary"), member("b2")]
        XCTAssertEqual(GroupPermissions.waitingNames(result(), members: members), ["b2"])
        var removed = member("b2"); removed.status = "removed"
        XCTAssertTrue(GroupPermissions.waitingNames(result(), members: Array(members.prefix(3)) + [removed]).isEmpty)
    }
    func testBatchImportNormalizesWhitespaceAndCaseAndSupportsChineseSeparator() {
        XCTAssertEqual(GroupInputValidation.temporaryNames("A  B、a b\n王，王"), ["A B", "王"])
    }
    func testNoticeKindsUseTheAndroidLabelsAndOpenRules() {
        // UI runs persist their app language on the simulator; assert that language's copy.
        let chinese = ["收到入组申请", "入组申请已通过", "入组申请未通过", "新增活动", "活动已修改", "活动已取消", "赛果待确认", "赛果已确认", "赛果已作废", "你的角色已变更", "你已被移出小组", "组长已变更"]
        let traditional = ["收到入組申請", "入組申請已通過", "入組申請未通過", "新增活動", "活動已修改", "活動已取消", "賽果待確認", "賽果已確認", "賽果已作廢", "你的角色已變更", "你已被移出小組", "組長已變更"]
        let localization = Bundle.main.preferredLocalizations.first ?? "en"
        let expectations: [(kind: String, label: String, opens: Bool)] = [
            ("join_requested", "Join request received", true),
            ("join_approved", "Join request approved", true),
            ("join_rejected", "Join request declined", false),
            ("activity_created", "Activity created", true),
            ("activity_changed", "Activity updated", true),
            ("activity_cancelled", "Activity cancelled", true),
            ("result_pending", "Result awaiting confirmation", true),
            ("result_confirmed", "Result confirmed", true),
            ("result_voided", "Result voided", true),
            ("role_changed", "Your role changed", true),
            ("member_removed", "You were removed from the group", false),
            ("ownership_transferred", "Group owner changed", true)
        ]
        for (index, item) in expectations.enumerated() {
            let notice = self.notice(item.kind)
            switch localization {
            case "en": XCTAssertEqual(notice.label, item.label, item.kind)
            case "zh-Hans": XCTAssertEqual(notice.label, chinese[index], item.kind)
            case "zh-Hant": XCTAssertEqual(notice.label, traditional[index], item.kind)
            default:
                // The full locale matrix is validated by LocalizationIntegrityTests.
                XCTAssertFalse(notice.label.isEmpty, item.kind)
                XCTAssertFalse(notice.label.hasPrefix("group_notice_"), item.kind)
            }
            XCTAssertEqual(notice.opensGroup, item.opens, item.kind)
        }
        XCTAssertEqual(notice("legacy_kind").label, "Notification")
        XCTAssertTrue(notice("legacy_kind").opensGroup)
    }
    func testNoticeReceiptMustEchoTheAcknowledgedNotice() {
        let notice = self.notice("activity_changed")
        var complete = notice; complete.seenAt = 100
        XCTAssertTrue(complete.isReceipt(for: notice))
        var unrelated = complete; unrelated.id = "other"
        XCTAssertFalse(unrelated.isReceipt(for: notice))
        XCTAssertFalse(notice.isReceipt(for: notice))
    }
    func testDirectScheduleMovesTheActivityAndItsMatchesTogether() {
        let now = Date()
        var first = GroupTrainingDraftSession(); first.startsAt = now.addingTimeInterval(600)
        var second = GroupTrainingDraftSession(); second.startsAt = now.addingTimeInterval(2400)
        // 未来开场：活动与场次都不动
        let future = GroupTrainingValidation.anchored([first, second], startsAt: now.addingTimeInterval(600), now: now)
        XCTAssertEqual(future.startsAt, now.addingTimeInterval(600))
        XCTAssertEqual(future.sessions.map(\.startsAt), [now.addingTimeInterval(600), now.addingTimeInterval(2400)])
        // 过去的开场：活动推到一分钟后，场次跟着整体平移，场间 30 分钟间隔保持不变
        let past = GroupTrainingValidation.anchored([first, second], startsAt: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(past.startsAt, now.addingTimeInterval(60))
        let shift = now.addingTimeInterval(60).timeIntervalSince(now.addingTimeInterval(-3600))
        XCTAssertEqual(past.sessions.map(\.startsAt), [first.startsAt.addingTimeInterval(shift), second.startsAt.addingTimeInterval(shift)])
        XCTAssertEqual(past.sessions[1].startsAt.timeIntervalSince(past.sessions[0].startsAt), 1800, accuracy: 0.001)
    }

    func testDirectScheduleDateChangesShiftEverySessionByTheSameDelta() {
        let base = Date()
        var first = GroupTrainingDraftSession(); first.startsAt = base
        var second = GroupTrainingDraftSession(); second.startsAt = base.addingTimeInterval(1800)
        // 安卓 setDirectDate：改日期是整体平移，不是只改第一场
        let moved = GroupTrainingValidation.shiftAll([first, second], by: 86_400)
        XCTAssertEqual(moved.map(\.startsAt), [base.addingTimeInterval(86_400), base.addingTimeInterval(88_200)])
        XCTAssertEqual(moved[1].startsAt.timeIntervalSince(moved[0].startsAt), 1800, accuracy: 0.001)
        // 零位移与非有限位移都不动（DatePicker 的 onChange 不该制造 NaN 漂移）
        XCTAssertEqual(GroupTrainingValidation.shiftAll([first, second], by: 0), [first, second])
        XCTAssertEqual(GroupTrainingValidation.shiftAll([first, second], by: .nan), [first, second])
    }

    func testDirectEditorPastDateOnlyShiftsOnceOnSubmission() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for mode in ["sequence", "estimated"] {
            var draft = GroupDirectScheduleDraft(date: now.addingTimeInterval(600))
            draft.timingMode = mode
            draft.add(format: .singles)
            draft.date = now.addingTimeInterval(-86_400)
            XCTAssertEqual(draft.sessions[0].startsAt, draft.date)
            let saved = draft.scheduled(now: now)
            XCTAssertEqual(saved.startsAt, now.addingTimeInterval(60))
            XCTAssertEqual(saved.sessions.map(\.startsAt), [now.addingTimeInterval(60), now.addingTimeInterval(1860)])
        }
    }

    func testDirectEditorPreservesCustomTimesWhenChangingModeDurationAndAdding() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = GroupDirectScheduleDraft(date: date)
        draft.timingMode = "estimated"
        draft.add(format: .singles)
        draft.sessions[0].startsAt = date.addingTimeInterval(4000)
        let originals = draft.sessions.map(\.startsAt)
        draft.timingMode = "sequence"; draft.minutes = 45
        XCTAssertEqual(draft.sessions.map(\.startsAt), originals)
        draft.add(format: .doubles)
        XCTAssertEqual(draft.sessions.last?.startsAt, date.addingTimeInterval(6700))
        XCTAssertEqual(Array(draft.sessions.prefix(2)).map(\.startsAt), originals)
        draft.date = date.addingTimeInterval(86_400)
        XCTAssertEqual(draft.sessions.map(\.startsAt), (originals + [date.addingTimeInterval(6700)]).map { $0.addingTimeInterval(86_400) })
    }

    func testRankingRateRequiresFiveGamesAndNonblankServerText() {
        var row = GroupRanking(memberId: "member", displayName: " ", games: 4, wins: 4, losses: 0, draws: nil, setsWon: 8, setsLost: 0, winRateText: "100%", rank: 1)
        XCTAssertNil(row.qualifiedWinRate)
        XCTAssertEqual(row.name, "member")
        row.games = 5
        XCTAssertEqual(row.qualifiedWinRate, "100%")
        row.winRateText = " \n "
        XCTAssertNil(row.qualifiedWinRate)
    }

    func testRankingsRemainScopedByFormatAcrossSwitchesAndCacheRoundTrip() throws {
        var cache = GroupDetailCache(group: group(), members: [], activities: [], results: [], rankings: [], stats: nil, nextCursor: nil, syncedAt: Date())
        let row = GroupRanking(memberId: "singles-only", displayName: "A", games: 5, wins: 5, losses: 0, draws: 0, setsWon: 10, setsLost: 0, winRateText: "100%", rank: 1)
        cache.rankings = [row]
        XCTAssertTrue(cache.rankings(for: .singles).isEmpty, "Legacy snapshots must not guess the format")
        XCTAssertTrue(cache.rankings(for: .doubles).isEmpty)
        cache.setRankings([row], format: .singles)
        cache.setRankings([], format: .doubles)
        let restored = try JSONDecoder().decode(GroupDetailCache.self, from: JSONEncoder().encode(cache))
        XCTAssertTrue(restored.hasAnyRanking, "An empty doubles tab must retain the singles filter entry")
        XCTAssertEqual(restored.rankings(for: .singles).map(\.memberId), ["singles-only"])
        XCTAssertTrue(restored.rankings(for: .doubles).isEmpty, "Never display singles rows as doubles")
    }

    func testNoticeRefreshKeepsServerReceiptTimeAndUnreadCorrection() {
        let unread = notice("activity_changed")
        var receipt = unread; receipt.seenAt = 123_456
        var receipts = GroupNoticeReadReceipts(); receipts.record(receipt)
        XCTAssertEqual(receipts.applying(to: unread).seenAt, 123_456)
        XCTAssertEqual(receipts.staleUnreadCount(in: [unread]), 1)
        XCTAssertEqual(receipts.staleUnreadCount(in: [receipt]), 0)
        var unrelated = unread; unrelated.id = "unrelated"
        XCTAssertNil(receipts.applying(to: unrelated).seenAt)
        receipts.removeAll()
        XCTAssertNil(receipts.applying(to: unread).seenAt, "Account switches must clear receipts")
    }

    private func notice(_ kind: String) -> GroupNotification {
        .init(id: "notice", groupId: "group", groupName: "Test", kind: kind, resourceId: nil, title: "", reason: nil, createdAt: 1, seenAt: nil)
    }

    func testManagementMenuEntriesFollowTheAndroidIdentityAndStatusGates() {
        // 安卓 GroupManagementTopBarMenu：自管理条目 → 分隔线 → 危险操作（解散 / 退出 / 举报）。
        let expectations: [(role: String?, status: String, entries: [String])] = [
            // 组长：编辑 / 转让 / 归档 → 分隔线 → 解散 / 举报（组长没有「退出」）
            ("owner", "active", ["editProfile", "transfer", "archive", "divider", "dissolve", "report"]),
            // 归档态：转让可、恢复可，但解散必须消失
            ("owner", "archived", ["transfer", "restore", "divider", "report"]),
            // 冷静期：只剩撤销解散 + 举报，归档 / 解散都不在
            ("owner", "dissolving", ["cancelDissolve", "divider", "report"]),
            ("owner", "dissolved", ["restore", "divider", "report"]),
            // 管理员：能编辑能退出，不能转让 / 归档 / 解散
            ("admin", "active", ["editProfile", "divider", "leave", "report"]),
            // 管理员在只读态没有自管理条目 → 分隔线也不该出现（安卓 (isAdmin && !archived) || isOwner）
            ("admin", "archived", ["leave", "report"]),
            ("admin", "dissolving", ["leave", "report"]),
            // 普通组员：只有退出 + 举报，没有分隔线（安卓 (isAdmin && !archived) || isOwner 都不成立）
            ("member", "active", ["leave", "report"]),
            ("member", "archived", ["leave", "report"]),
            // 非成员（例如只读预览）：连退出都不能给，只剩举报
            (nil, "active", ["report"])
        ]
        for item in expectations {
            let policy = GroupManagementMenu(role: item.role, status: item.status)
            XCTAssertEqual(policy.entries.map(\.rawValue), item.entries, "\(item.role ?? "none") / \(item.status)")
        }
    }

    func testOnlySimpleGroupConfirmationsUseSystemAlerts() {
        for entry in [GroupManagementMenu.Entry.archive, .restore, .cancelDissolve, .dissolve, .leave] {
            XCTAssertNotNil(entry.confirmationHintKey)
        }
        for entry in [GroupManagementMenu.Entry.editProfile, .transfer, .report, .divider] {
            XCTAssertNil(entry.confirmationHintKey)
        }
    }

    func testManagementMenuGatesTransferAndDissolveByStatus() {
        // 安卓 canTransferOwnership = isOwner && status ∈ {active, archived}（冷静期服务端直接 409）。
        for status in ["active", "archived"] {
            let owner = GroupManagementMenu(role: "owner", status: status)
            XCTAssertTrue(owner.canTransfer, status)
            XCTAssertFalse(GroupManagementMenu(role: "admin", status: status).canTransfer, status)
            XCTAssertFalse(GroupManagementMenu(role: "member", status: status).canTransfer, status)
        }
        for status in ["dissolving", "dissolved"] {
            XCTAssertFalse(GroupManagementMenu(role: "owner", status: status).canTransfer, status)
            XCTAssertFalse(GroupManagementMenu(role: "owner", status: status).canDissolve, status)
        }
        // 解散只在 active 态出现：归档小组必须先恢复，冷静期小组只能撤销。
        XCTAssertTrue(GroupManagementMenu(role: "owner", status: "active").canDissolve)
        XCTAssertFalse(GroupManagementMenu(role: "owner", status: "archived").canDissolve)
        XCTAssertFalse(GroupManagementMenu(role: "admin", status: "active").canDissolve)
    }

    func testManagementMenuMarksDestructiveEntriesAndOmitsTheDividerTitle() {
        let titles: [(entry: GroupManagementMenu.Entry, key: String?, destructive: Bool)] = [
            (.editProfile, "edit_profile", false), (.transfer, "transfer", false), (.archive, "archive", false),
            (.restore, "restore", false), (.cancelDissolve, "cancel_dissolve", false),
            (.dissolve, "dissolve", true), (.leave, "leave", true), (.report, "report", true),
            (.divider, nil, false)
        ]
        for item in titles {
            XCTAssertEqual(item.entry.titleKey, item.key, item.entry.rawValue)
            XCTAssertEqual(item.entry.isDestructive, item.destructive, item.entry.rawValue)
        }
    }
}

extension GroupPortParityTests {
    func testResultConflictKeepsCloudIdentityForUploadsWithoutGameID() async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        GroupWireProtocol.register(token) { proto in
            if proto.request.url!.path.hasSuffix("/capabilities") { proto.replyCapabilities(actions: ["submit_result"]); return }
            proto.reply("{\"error\":\"RESULT_CONFLICT\",\"message\":\"existing result\",\"currentResultId\":\"cloud-result\"}", status: 409)
        }
        do { let _: GroupResult = try await repository.write("/g/results", body: body(), key: "stable"); XCTFail("Expected conflict") }
        catch {
            let context = try XCTUnwrap(error as? APIClientServerContextError)
            XCTAssertEqual(context.currentResultID, "cloud-result")
            guard case .server(status: 409, code: "RESULT_CONFLICT", message: _, nextAvailableAt: _) = context.underlying else { return XCTFail("Unexpected conflict: \(context)") }
            try withPersistence { persistence, _ in
                var value = body(); value.gameId = nil
                try persistence.enqueueManual(value, id: "record", accountID: "a", groupID: "g", key: "stable")
                try persistence.updateRetry("record", accountID: "a", code: "RESULT_CONFLICT", failure: "conflict", next: nil, existingResultID: context.currentResultID)
                XCTAssertEqual(persistence.uploads(accountID: "a").first?.existingResultID, "cloud-result")
                XCTAssertNil(persistence.uploads(accountID: "a").first?.body.gameId)
            }
        }
        await tokens.clearAuth()
    }

    // MARK: - s5 赛果与排行

    func testSetDetailsAreOptionalPlaceholdersUntilAScoreIsEntered() {
        let row = GroupScore(a: 21, b: 19)
        XCTAssertNil(GroupInputValidation.scoredDetails(includesSets: false, sets: []))
        XCTAssertNil(GroupInputValidation.scoredDetails(includesSets: false, sets: [row]))
        // 展开了明细但一行都没加：只按总分校验（安卓 hasDetailInput）。
        XCTAssertNil(GroupInputValidation.scoredDetails(includesSets: true, sets: []))
        XCTAssertEqual(GroupInputValidation.scoredDetails(includesSets: true, sets: [row])?.count, 1)
    }

    func testRankingFailureIsScopedPerGroupAndFormat() {
        XCTAssertEqual(GroupStore.rankKey("g1", format: .singles), "g1:singles")
        XCTAssertEqual(GroupStore.rankKey("g1", format: .doubles), "g1:doubles")
        XCTAssertNotEqual(GroupStore.rankKey("g1", format: .singles), GroupStore.rankKey("g2", format: .singles))
    }

    func testResultHistoryKeepsOtherPeoplesPendingResults() {
        let mine = self.result("r1", status: "pending_confirmation", submitter: "me", participants: [("me", "A"), ("other", "B")], playedAt: 30)
        let theirs = self.result("r2", status: "pending_confirmation", submitter: "other", participants: [("other", "A"), ("third", "B")], playedAt: 20)
        let confirmed = self.result("r3", status: "confirmed", submitter: "other", participants: [("other", "A"), ("third", "B")], playedAt: 10)
        let tasks = [theirs] // 只有我能确认的才进「待我确认」
        let history = GroupPermissions.resultHistory([confirmed], pending: [mine, theirs], tasks: tasks, format: nil)
        XCTAssertEqual(history.map(\.id), ["r1", "r3"], "待确认的他人赛果保留在记录里，我的待办不重复")
    }

    // MARK: - s6 分享 / 举报

    func testInviteGatingMatchesTheAndroidBlacklist() {
        XCTAssertTrue(GroupPermissions.canInvite(preview(status: "active", policy: "open", availability: "available", count: 1, limit: 8)))
        // 状态：安卓要求严格等于 active，解散中 / 归档一律不可邀请。
        XCTAssertFalse(GroupPermissions.canInvite(preview(status: "dissolving", policy: "open", availability: "available", count: 1, limit: 8)))
        XCTAssertFalse(GroupPermissions.canInvite(preview(status: "archived", policy: "open", availability: "available", count: 1, limit: 8)))
        // 入组策略：安卓用黑名单（!= closed），不是白名单。
        XCTAssertFalse(GroupPermissions.canInvite(preview(status: "active", policy: "closed", availability: "available", count: 1, limit: 8)))
        XCTAssertTrue(GroupPermissions.canInvite(preview(status: "active", policy: "approval", availability: "available", count: 1, limit: 8)))
        // availability：四类「不可加入」。
        for blocked in ["full", "closed", "archived", "not_found"] {
            XCTAssertFalse(GroupPermissions.canInvite(preview(status: "active", policy: "open", availability: blocked, count: 1, limit: 8)), blocked)
        }
        // 已是成员 / 待审批仍然可以转发邀请。
        for allowed in ["already_member", "pending_approval"] {
            XCTAssertTrue(GroupPermissions.canInvite(preview(status: "active", policy: "open", availability: allowed, count: 1, limit: 8)), allowed)
        }
        // 满员不可邀请。
        XCTAssertFalse(GroupPermissions.canInvite(preview(status: "active", policy: "open", availability: "available", count: 8, limit: 8)))
        // 字段缺失按安卓 DTO 默认值兜底（status=active、memberLimit=100），不能反过来判成不可邀请。
        XCTAssertTrue(GroupPermissions.canInvite(preview(status: nil, policy: "open", availability: "available", count: 0, limit: nil)))
    }

    func testGroupInviteCardUsesTheAndroidPosterSize() {
        let card = GroupInviteCard.image(name: "Saturday Doubles Friendly", groupNo: "82603158", approval: true)
        XCTAssertNotNil(card, "二维码生成失败时不应返回卡片")
        XCTAssertEqual(card?.size, GroupInviteCard.size)
        XCTAssertEqual(card?.scale, 1)
        XCTAssertEqual(card?.cgImage?.width, 720)
        XCTAssertEqual(card?.cgImage?.height, 920)
    }

    func testGroupQrRendersAtTheAndroidModuleSize() {
        let image = GroupQRCode.image("82603158")
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width, 640)
        XCTAssertEqual(image?.scale, 1)
    }

    func testPeerCreationStaysPeerWhenServerOffersCoaching() throws {
        var capability = GroupCapabilities(groupNoLength: 6, nameMin: 2, nameMax: 24, descriptionMax: 200, memberLimitDefault: 30, memberLimitMax: 50)
        capability.groupTypes = ["peer", "coaching"]
        XCTAssertTrue(capability.allowsPeerCreation)
        let body = GroupCreateBody(name: "Friends", description: "", sport: .badminton, joinPolicy: "approval")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["groupType"] as? String, "peer")
        capability.groupTypes = ["coaching"]; XCTAssertFalse(capability.allowsPeerCreation)
        capability.groupTypes = ["peer"]; capability.allowedActions = ["join_group"]
        XCTAssertFalse(capability.allowsPeerCreation)
    }

    func testInvitationContainsSportNameNumberJoinAndDownloadOnBothDomains() {
        for sport in GroupSport.allCases {
            var value = group(); value.sport = sport
            for region in ["CN", "US"] {
                let text = GroupInvitationText.message(group: value, regionCode: region, localization: "en")
                XCTAssertTrue(text.contains(value.name)); XCTAssertTrue(text.contains(sport.title))
                XCTAssertTrue(text.contains(value.groupNo))
                XCTAssertTrue(text.contains(GroupInvitationLink.joinURL(groupNo: value.groupNo, regionCode: region, localization: "en")!.absoluteString))
                XCTAssertTrue(text.contains(GroupInvitationLink.website(regionCode: region, localization: "en") + "/download")); XCTAssertFalse(text.contains("%@"))
            }
        }
    }

    func testEntryDraftBlankDetailsAreOptionalAndZeroIsRealInput() {
        var draft = GroupResultEntryDraft()
        draft.selectTotal(.init(a: 2, b: 0), rules: rules())
        draft.detailsExpanded = true; draft.reconcileDetails(rules())
        XCTAssertEqual(draft.sets.count, 2)
        XCTAssertFalse(draft.hasDetailInput); XCTAssertNil(draft.details)
        XCTAssertTrue(draft.isValid(rules()))
        draft.sets[0].b = "0"
        XCTAssertTrue(draft.hasDetailInput); XCTAssertFalse(draft.isValid(rules()))
        draft.sets = [.init(a: "21", b: "0"), .init(a: "21", b: "19")]
        XCTAssertTrue(draft.isValid(rules()))
        draft.clearTotal()
        XCTAssertEqual(draft.score, .init(a: 2, b: 0)); XCTAssertTrue(draft.isValid(rules()))
        draft.clearDetails(); XCTAssertNil(draft.score); XCTAssertFalse(draft.isValid(rules()))
    }

    func testEntryDraftDetailsNeedNoWinnerOrderAndNeverRewriteEnteredPoints() {
        var draft = GroupResultEntryDraft()
        draft.selectTotal(.init(a: 2, b: 1), rules: rules())
        draft.detailsExpanded = true; draft.reconcileDetails(rules())
        XCTAssertEqual(draft.sets, Array(repeating: .init(), count: 3), "Show empty detail rows without guessing any actual points")
        XCTAssertTrue(draft.isValid(rules()), "Simply expanding optional details preserves fast total-only entry")
        draft.sets = [.init(a: "19", b: "21"), .init(a: "21", b: "19"), .init(a: "21", b: "18")]
        XCTAssertTrue(draft.isValid(rules()), "Actual points determine each game winner")
        let entered = draft.sets
        draft.selectTotal(.init(a: 2, b: 0), rules: rules())
        XCTAssertEqual(draft.sets, entered); XCTAssertFalse(draft.isValid(rules()))
        draft.clearTotal()
        XCTAssertEqual(draft.score, .init(a: 2, b: 1)); XCTAssertTrue(draft.isValid(rules()))
        var otherRules = rules(); otherRules.pointsToWinSet = 11; otherRules.pointCap = nil
        draft.reconcileDetails(otherRules)
        XCTAssertEqual(draft.sets, entered); XCTAssertFalse(draft.isValid(otherRules))
    }

    func testEntryDraftPreservesPartialDetailsWhenChangingTotal() {
        var draft = GroupResultEntryDraft()
        draft.selectTotal(.init(a: 2, b: 1), rules: rules())
        draft.detailsExpanded = true; draft.reconcileDetails(rules())
        draft.sets[0].a = "19"
        let entered = draft.sets[0]
        draft.selectTotal(.init(a: 2, b: 0), rules: rules())
        XCTAssertEqual(draft.sets.count, 2, "Only the unused trailing placeholder is reclaimed")
        XCTAssertEqual(draft.sets[0], entered); XCTAssertFalse(draft.isValid(rules()))
    }

    func testEntryDraftCanShrinkTotalAndExplicitlyRemoveAnExcessScoredGame() {
        var draft = GroupResultEntryDraft(); draft.detailsExpanded = true
        draft.selectTotal(.init(a: 2, b: 1), rules: rules())
        draft.sets = [.init(a: "19", b: "21"), .init(a: "21", b: "19"), .init(a: "21", b: "18")]
        let entered = draft.sets
        draft.selectTotal(.init(a: 2, b: 0), rules: rules())
        XCTAssertEqual(draft.sets, entered, "An entered extra game is not silently dropped")
        XCTAssertTrue(draft.hasExcessDetailRows); XCTAssertFalse(draft.isValid(rules()))
        draft.removeSet(at: 0, rules: rules())
        XCTAssertEqual(draft.sets, Array(entered.dropFirst()))
        XCTAssertFalse(draft.hasExcessDetailRows); XCTAssertTrue(draft.isValid(rules()))
    }

    func testEntryDraftGrowthAppendsBlankRowsAndPreservesEnteredPoints() {
        var draft = GroupResultEntryDraft(); draft.detailsExpanded = true
        draft.selectTotal(.init(a: 2, b: 0), rules: rules())
        draft.sets[0] = .init(a: "21", b: "19")
        let entered = draft.sets
        draft.selectTotal(.init(a: 2, b: 1), rules: rules())
        XCTAssertEqual(draft.sets.count, 3)
        XCTAssertEqual(Array(draft.sets.prefix(2)), entered)
        XCTAssertEqual(draft.sets[2], .init(), "New detail rows never guess actual points")
        draft.sets[1] = .init(a: "19", b: "21"); draft.sets[2] = .init(a: "21", b: "18")
        XCTAssertTrue(draft.isValid(rules()), "The larger total can be completed directly")
    }

    func testEntryDraftClearingAnExcessTrailingGameReclaimsOnlyItsBlankRow() {
        var draft = GroupResultEntryDraft(); draft.detailsExpanded = true
        draft.selectTotal(.init(a: 2, b: 1), rules: rules())
        draft.sets = [.init(a: "21", b: "19"), .init(a: "21", b: "18"), .init(a: "0", b: "21")]
        draft.selectTotal(.init(a: 2, b: 0), rules: rules())
        XCTAssertEqual(draft.sets.count, 3)
        draft.sets[2] = .init(); draft.reconcileDetails(rules())
        XCTAssertEqual(draft.sets, [.init(a: "21", b: "19"), .init(a: "21", b: "18")])
        XCTAssertTrue(draft.isValid(rules()))
    }

    func testEntryDraftCanDeriveTotalFromDirectGameScores() {
        var draft = GroupResultEntryDraft()
        draft.detailsExpanded = true
        draft.sets = [.init(a: "21", b: "19"), .init(a: "21", b: "18")]
        XCTAssertEqual(draft.score, .init(a: 2, b: 0)); XCTAssertTrue(draft.isValid(rules()))
    }

    func testEntryDraftRejectsPartialTotalsInvalidNumbersAndExtraGames() {
        var draft = GroupResultEntryDraft()
        draft.total = .init(a: "2")
        draft.sets = [.init(a: "21", b: "0"), .init(a: "21", b: "0")]
        XCTAssertFalse(draft.isValid(rules()))
        draft.total = .init(a: "-2", b: "0"); XCTAssertNil(draft.score)
        draft.total = .init(a: "999999999999999999999999", b: "0"); XCTAssertNil(draft.score)
        draft.total = .init(); draft.sets.append(.init(a: "0", b: "21"))
        XCTAssertFalse(draft.isValid(rules()), "No games after the match has already ended")
        var long = rules(); long.maxSets = 99
        var longDraft = GroupResultEntryDraft(); longDraft.detailsExpanded = true
        longDraft.selectTotal(.init(a: 50, b: 49), rules: long)
        XCTAssertEqual(longDraft.sets.count, 99)
        XCTAssertFalse(longDraft.hasDetailInput); XCTAssertTrue(longDraft.isValid(long))
    }

    func testLineupDistinguishesAllFiveAndroidValidationCases() {
        var row = GroupTrainingDraftSession(startsAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([row], minutes: 30), .incomplete)
        row.memberIDs = ["a", "", "a", ""]
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([row], minutes: 30), .duplicate)
        row.memberIDs = ["a", "", "b", ""]
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([row, row], minutes: 30, maximumSessions: 1), .sessions)
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([row, row], minutes: 30, maximumPerMember: 1), .memberLimit)
        XCTAssertEqual(GroupTrainingValidation.lineupProblem([row, row], minutes: 30), .conflict)
        XCTAssertNil(GroupTrainingValidation.lineupProblem([row, row], minutes: 30, skipsConflicts: true))
        var later = row; later.startsAt = row.startsAt.addingTimeInterval(1800)
        XCTAssertNil(GroupTrainingValidation.lineupProblem([row, later], minutes: 30))
        XCTAssertNil(GroupTrainingValidation.lineupProblem([later, row], minutes: 30, skipsConflicts: true), "Sequence mode ignores draft timestamps")
    }

    private func preview(status: String?, policy: String, availability: String, count: Int, limit: Int?) -> GroupPreview {
        var payload: [String: Any] = ["groupNo": "82603158", "name": "Test", "description": "", "sport": "badminton",
                                     "memberCount": count, "joinPolicy": policy, "availability": availability]
        if let status { payload["status"] = status }
        if let limit { payload["memberLimit"] = limit }
        return try! JSONDecoder().decode(GroupPreview.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func result(_ id: String, status: String, submitter: String, participants: [(String, String)], playedAt: Int64) -> GroupResult {
        .init(id: id, groupId: "group", activityId: "", gameId: "game", format: .singles, sport: .badminton,
              setScore: .init(a: 2, b: 0), rules: rules(),
              participants: participants.map { .init(memberId: $0.0, side: $0.1, seat: 0) },
              playedAt: playedAt, submitterMemberId: submitter, confirmedByMemberId: "", status: status,
              source: "manual", reason: "", createdAt: 1, revision: 1)
    }
}

extension GroupPortParityTests {
    func testCoachingConfirmationRequiresCoachAndNeverUsesPeerAuthority() {
        var training = group(); training.groupType = "coaching"
        for me in [member("b"), member("admin", role: "admin")] {
            XCTAssertFalse(GroupPermissions.confirmation(result(), group: training, me: me).allowed)
            XCTAssertTrue(GroupPermissions.confirmationTasks([result()], group: training, me: me).isEmpty)
        }
        let owner = member("owner", role: "owner")
        var pending = result(); pending.canAuthorityConfirm = true
        training.isCoach = false
        XCTAssertFalse(GroupPermissions.confirmation(pending, group: training, me: owner).allowed)
        for coach in [true, nil] as [Bool?] {
            training.isCoach = coach
            let permission = GroupPermissions.confirmation(pending, group: training, me: owner)
            XCTAssertTrue(permission.allowed); XCTAssertFalse(permission.authority)
            XCTAssertFalse(GroupPermissions.confirmation(result(submitter: "owner"), group: training, me: owner).allowed)
        }
    }
    func testEveryBackendGroupRejectionHasLocalizedCopy() {
        // Captured independently from api-server GroupError call sites on 2026-10-17.
        let codes = """
        ACCOUNT_NOT_ACTIVE ACTION_DISABLED ACTIVITY_FULL ACTIVITY_HAS_PENDING_SESSIONS ACTIVITY_NOT_CANCELLABLE ACTIVITY_NOT_EDITABLE ACTIVITY_NOT_FOUND ACTIVITY_NOT_OPEN ACTIVITY_REGISTRATION_DISABLED ACTIVITY_SESSION_REQUIRED ACTIVITY_TITLE_BLOCKED COACHING_GROUP_NO_ADMIN FORMAT_MISMATCH GAME_ABANDONED GAME_EXISTS GAME_HAS_RESULT GAME_NOT_FOUND GAME_NOT_OPEN GROUP_ARCHIVED GROUP_DISSOLVING GROUP_FULL GROUP_JOIN_CLOSED GROUP_JOIN_MESSAGE_BLOCKED GROUP_MEMBER_NAME_BLOCKED GROUP_MODERATION_CONFLICT GROUP_NOT_DISSOLVING GROUP_NOT_FOUND GROUP_NUMBER_ALLOCATION_FAILED IDEMPOTENCY_KEY_REUSED INVALID_ACTIVITY INVALID_ACTIVITY_CAPACITY INVALID_CURSOR INVALID_DISPLAY_NAME INVALID_FORMAT INVALID_GROUP_DESCRIPTION INVALID_GROUP_NAME INVALID_GROUP_NUMBER INVALID_GROUP_TYPE INVALID_INITIAL_JOIN_POLICY INVALID_JOIN_POLICY INVALID_LEAVE_REASON INVALID_LIMIT INVALID_LINEUP INVALID_MEMBER_STATUS INVALID_PERIOD INVALID_PLAN_NOTE INVALID_REASON INVALID_REQUEST INVALID_RESULT INVALID_RESULT_STATE INVALID_ROLE INVALID_RULES INVALID_TARGET INVALID_TRANSFER_TARGET JOIN_REQUEST_COOLDOWN LINEUP_CONFLICT NEED_LOGIN NOTICE_NOT_FOUND NOT_COACH NOT_PEER_GROUP OWNER_TRANSFER_REQUIRED PLACE_LOCKED PLAN_CANCELLED PLAN_NOT_FOUND REASON_REQUIRED REGISTRATION_CLOSED REQUEST_NOT_PENDING RESULT_CONFLICT REVISION_CONFLICT REVISION_REQUIRED ROLE_FORBIDDEN RULES_CONFLICT SESSION_CANCELLED SESSION_COMPLETED SESSION_HAS_RESULT SESSION_NOT_FOUND UNSUPPORTED_FORMAT UNSUPPORTED_SPORT
        """.split(separator: " ").map(String.init)
        let fallback = NSLocalizedString("network_request_failed", value: "Request failed. Please try again.", comment: "")
        for code in codes {
            let error = APIClientError.server(status: 409, code: code, message: "UNLOCALIZED_SERVER_MESSAGE", nextAvailableAt: nil)
            let message = groupErrorMessage(error)
            XCTAssertFalse(message.isEmpty, code)
            XCTAssertNotEqual(message, fallback, code)
            XCTAssertNotEqual(message, "UNLOCALIZED_SERVER_MESSAGE", code)
            XCTAssertNotEqual(message, code, code)
        }
    }

    func testGroupRejectionCopyDistinguishesPermissionConflictAndRegistration() {
        for (code, key) in [("ROLE_FORBIDDEN", "error_permission"),
                            ("RESULT_CONFLICT", "error_conflict"),
                            ("REGISTRATION_CLOSED", "error_registration_closed"),
                            ("ACTION_DISABLED", "error_action_disabled"),
                            ("UPDATE_REQUIRED", "error_update_required")] {
            let error = APIClientError.server(status: 409, code: code, message: nil, nextAvailableAt: nil)
            XCTAssertEqual(groupErrorMessage(error), groupText(key, "MISSING_COPY"), code)
            XCTAssertNotEqual(groupErrorMessage(error), "MISSING_COPY", code)
            let wrapped = APIClientServerContextError(underlying: error, currentResultID: "existing-result")
            XCTAssertEqual(groupErrorMessage(wrapped), groupErrorMessage(error), code)
        }
    }

    func testGroupCountersResolvePluralCopyInEveryShippedLanguage() throws {
        let locales = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "fr-CA", "es-MX", "es-ES", "pt-BR", "pt-PT", "ar", "he", "ur", "ru", "uk", "pl", "tr", "it", "nl", "id", "vi", "th", "hi", "bn", "gu", "kn", "ml", "mr", "or", "pa", "ta", "te", "ca", "hr", "cs", "da", "fi", "el", "hu", "ms", "nb", "ro", "sk", "sl", "sv"]
        for locale in locales {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"), locale)
            let bundle = try XCTUnwrap(Bundle(path: path), locale)
            for key in ["activity_direct_match_count", "archived_count"] {
                let format = bundle.localizedString(forKey: key, value: nil, table: nil)
                for count in [0, 1, 2, 3, 5, 11, 21, 100] {
                    let rendered = String.localizedStringWithFormat(format, count)
                    XCTAssertFalse(rendered.isEmpty, "\(locale) \(key)")
                    XCTAssertFalse(rendered.contains("%"), "\(locale) \(key): \(rendered)")
                    if locale != "en" {
                        XCTAssertFalse(rendered.contains("all group members"), "\(locale): \(rendered)")
                        XCTAssertFalse(rendered.contains(" groups"), "\(locale): \(rendered)")
                    }
                }
            }
        }
    }

}


@MainActor final class ThemeActionForegroundTests: XCTestCase {
    func testLightGreenLabelsAreWhiteAndDarkModeKeepsContrast() {
        XCTAssertNotNil(UIImage(systemName: "checkmark.circle"))
        let dynamicPrimaryLabel = UIColor(Theme.textOnPrimary)
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            for fill in [Theme.primary, Theme.primaryDark, Theme.toolWhistleRed, Color.black, Color.white] {
                let background = UIColor(fill).resolvedColor(with: traits)
                let foreground = UIColor(Theme.actionForeground(on: fill)).resolvedColor(with: traits)
                if appearance == .light && (fill == Theme.primary || fill == Theme.primaryDark) {
                    XCTAssertEqual(foreground, UIColor.white)
                } else {
                    let a = luminance(background), b = luminance(foreground)
                    XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
                }
            }
            let primaryLabel = dynamicPrimaryLabel.resolvedColor(with: traits)
            XCTAssertEqual(primaryLabel, appearance == .light ? UIColor.white : UIColor.black)
        }
        XCTAssertEqual(Theme.actionForeground(on: UIColor.black), UIColor.white)
        XCTAssertEqual(Theme.actionForeground(on: UIColor.white), UIColor.black)
    }
    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
