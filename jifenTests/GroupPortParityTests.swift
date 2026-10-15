import XCTest
import CoreImage
@testable import jifen

@MainActor final class GroupPortParityTests: XCTestCase {
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
    func testOverviewInvitationIsTheOnlyActionUntilTwoMembers() {
        for count in [0, 1] {
            let policy = GroupOverviewActions(group: group(), memberCount: count, hasResults: true, confirmedMatchCount: 2, isCoach: false)
            XCTAssertEqual(policy.actions, [.invite]); XCTAssertFalse(policy.showSecondaryInvite)
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
    func testVersionConflictIncludesIfMatchAndDoesNotMutateInput() async throws {
        let (tokens, repository, session, token) = wireFixture()
        defer { session.invalidateAndCancel(); GroupWireProtocol.remove(token) }
        try await tokens.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        GroupWireProtocol.register(token) { proto in
            XCTAssertEqual(proto.request.value(forHTTPHeaderField: "If-Match"), "\"7\"")
            XCTAssertEqual(proto.request.httpMethod, "PATCH")
            proto.reply("{\"error\":\"REVISION_CONFLICT\",\"message\":\"reload\"}", status: 409)
        }
        let input = GroupActionBody(name: "Preserve this input", description: "draft", joinPolicy: "approval")
        do { let _: ScoreGroup = try await repository.write("/g", body: input, method: .patch, revision: 7); XCTFail("Expected conflict") }
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
        for item in expectations {
            let notice = self.notice(item.kind)
            XCTAssertEqual(notice.label, item.label, item.kind)
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
        GroupWireProtocol.register(token) { $0.reply("{\"error\":\"RESULT_CONFLICT\",\"message\":\"existing result\",\"currentResultId\":\"cloud-result\"}", status: 409) }
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
    }

    func testGroupQrRendersAtTheAndroidModuleSize() {
        let image = GroupQRCode.image("82603158")
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width, 640)
        XCTAssertEqual(image?.scale, 1)
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
