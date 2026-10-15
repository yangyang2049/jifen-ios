import XCTest
import RecordCore
import PersistenceCore
@testable import jifen

@MainActor final class GroupContractTests: XCTestCase {
    func testInvitationDomainSelectionUsesRegion() {
        XCTAssertEqual(GroupInvitationLink.joinURL(groupNo: "72856000", regionCode: "CN")?.absoluteString, "https://jifenqi.com/groups/join?groupNo=72856000")
        for region in ["US", "JP", "HK", "TW", "", nil] {
            XCTAssertEqual(GroupInvitationLink.joinURL(groupNo: "72856000", regionCode: region, localization: "en")?.host, "iscoreboard.live")
        }
        XCTAssertNil(GroupInvitationLink.joinURL(groupNo: "123&admin=true", regionCode: "CN"))
    }

    func testInvitationAcceptsBothDomains() throws {
        for base in ["https://jifenqi.com/groups/join", "https://iscoreboard.live/groups/join"] {
            for number in ["123456", "1234567", "72856000"] {
                let link = "\(base)?groupNo=\(number)"
                XCTAssertEqual(GroupInvitationLink.groupNumber(from: try XCTUnwrap(URL(string: link))), number)
                XCTAssertEqual(GroupQRPayload.parse(link), number)
            }
        }
        XCTAssertEqual(GroupInvitationLink.groupNumber(from: try XCTUnwrap(URL(string: "https://jifenqi.com/groups/join/?groupNo=72856000&utm_source=share"))), "72856000")
        XCTAssertNotEqual(GroupInvitation(groupNo: "72856000").id, GroupInvitation(groupNo: "72856000").id)
    }

    func testInvitationRejectsUntrustedAndAmbiguousLinks() throws {
        let links = [
            "jifen://groups/join?groupNo=72856000",
            "https://jifenqi.com.evil.test/groups/join?groupNo=72856000",
            "https://jifenqi.com@evil.test/groups/join?groupNo=72856000",
            "https://user@jifenqi.com/groups/join?groupNo=72856000",
            "https://jifenqi.com:8443/groups/join?groupNo=72856000",
            "http://jifenqi.com/groups/join?groupNo=72856000",
            "https://iscoreboard.life/groups/join?groupNo=72856000",
            "https://jifenqi.com/groups/join/other?groupNo=72856000",
            "https://jifenqi.com/groups/join?groupNo=72856000&groupNo=123456",
            "https://jifenqi.com/groups/join?groupNo=",
            "https://jifenqi.com/groups/join?groupNo=012345",
            "jifen://groups/join?groupNo=12345",
            "jifen://groups/join?groupNo=123456789",
            "jifen://groups/join?groupNo=%E4%B8%80%E4%BA%8C%E4%B8%89%E5%9B%9B%E4%BA%94%E5%85%AD",
        ]
        for link in links {
            XCTAssertNil(GroupInvitationLink.groupNumber(from: try XCTUnwrap(URL(string: link))), link)
        }
    }

    private func rules(_ mode: String = "best_of", sets: Int = 3) -> GroupMatchRules {
        .init(sport: .badminton, maxSets: sets, matchCompletionMode: mode, pointsToWinSet: 21, pointCap: 30, winByTwo: true, useRallyScoring: false, gamesPerSet: 6, tieBreakPoints: 7, setScoringMode: "regular", usesNoAdScoring: false)
    }
    func testActivityCancelOnlyBeforeLaunch() {
        var activity = GroupActivity(id: "a", groupId: "g", title: "match", startsAt: 1, place: "", capacity: 4, note: "", format: .doubles, status: "recruiting", creatorMemberId: "owner", registeredMemberIds: [], gameId: "", createdAt: 1, revision: 1)
        XCTAssertTrue(activity.canCancel)
        activity.gameId = "game"; XCTAssertFalse(activity.canCancel)
        activity.gameId = ""
        for status in ["in_progress", "completed", "cancelled"] { activity.status = status; XCTAssertFalse(activity.canCancel) }
    }
    func testSharedRulesFixtures() throws {
        struct Fixture: Decodable { var name: String; var rules: GroupMatchRules; var setScore: GroupScore; var sets: [GroupScore]?; var valid: Bool }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "rules-v1", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.count, 17)
        for fixture in fixtures { XCTAssertEqual(fixture.rules.validResult(fixture.setScore, sets: fixture.sets), fixture.valid, fixture.name) }
    }
    func testNoCapEncodesExplicitNullAndQRCompatibility() throws {
        var r = rules(); r.pointCap = nil
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        XCTAssertTrue(json["pointCap"] is NSNull)
        XCTAssertEqual(GroupQRPayload.parse(GroupQRPayload.encode("12345678")), "12345678")
        XCTAssertEqual(GroupQRPayload.parse(" 12345678 "), "12345678")
        for raw in ["02345678", "123", "{\"type\":\"JIFEN_GROUP\",\"v\":2,\"groupNo\":\"12345678\"}", "{\"type\":\"AUTH_QR_LOGIN\",\"v\":1,\"groupNo\":\"12345678\"}"] { XCTAssertNil(GroupQRPayload.parse(raw)) }
    }
    func testDurableAssociationQueueIsolationAndWhitelist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = GroupLocalPersistence(root: root)
        let context = GroupMatchContext(accountID: "account-a", groupID: "g", groupName: "friends", gameID: nil, clientSessionID: "client-stable", format: .singles, rules: rules("play_all", sets: 2), participants: [.init(memberId: "a", side: "A", seat: 0, displayName: "A"), .init(memberId: "b", side: "B", seat: 0, displayName: "B")])
        try persistence.saveContext(context, sessionID: "stable-session")
        var record = ScoreboardRecord(id: "stable-session", gameType: .badminton, startTime: Date(), endTime: Date(), duration: 10, team1Name: "A", team2Name: "B", team1FinalScore: 1, team2FinalScore: 1, team1SetScore: 1, team2SetScore: 1, winner: nil, totalScoreChanges: 42, extraData: ["privateValue": AnyCodable("secret")], stateSnapshot: Data("secret-snapshot".utf8), note: "private-note", status: .draft)
        record = persistence.annotate(record)
        try persistence.enqueue(record)
        XCTAssertTrue(persistence.uploads(accountID: "account-a").isEmpty)
        record.status = .finished
        try persistence.enqueue(record); try persistence.enqueue(record)
        let restarted = GroupLocalPersistence(root: root)
        XCTAssertEqual(restarted.context(sessionID: "stable-session")?.participants, context.participants)
        XCTAssertEqual(restarted.uploads(accountID: "account-a").count, 1)
        XCTAssertTrue(restarted.uploads(accountID: "account-b").isEmpty)
        let upload = try XCTUnwrap(restarted.uploads(accountID: "account-a").first)
        XCTAssertNil(upload.failure); XCTAssertNil(upload.body.gameId)
        let body = String(decoding: try JSONEncoder().encode(upload.body), as: UTF8.self)
        XCTAssertFalse(body.contains("secret")); XCTAssertFalse(body.contains("private-note")); XCTAssertFalse(body.contains("stateSnapshot"))
        try restarted.markUploaded(upload.id, accountID: "account-a")
        restarted.repairOutbox(from: [record])
        XCTAssertTrue(restarted.uploads(accountID: "account-a").isEmpty)
        let old = ScoreboardRecord(id: "old-personal", gameType: .badminton, startTime: Date(), team1Name: "A", team2Name: "B", team1FinalScore: 2, team2FinalScore: 0, totalScoreChanges: 1)
        XCTAssertNil(try JSONDecoder().decode(ScoreboardRecord.self, from: JSONEncoder().encode(old)).groupMatchContext)
    }
    func testTennisTiebreakOnlyUsesPointDetailsAndSetWinner() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = GroupLocalPersistence(root: root)
        var r = rules(); r.sport = .tennis; r.maxSets = 1; r.pointCap = nil; r.setScoringMode = "tiebreak_only"; r.tieBreakPoints = 10
        let c = GroupMatchContext(accountID: "a",groupID: "g",groupName: "g",gameID: nil,clientSessionID: "s",format: .singles,rules: r,participants: [.init(memberId: "a",side: "A",seat: 0),.init(memberId: "b",side: "B",seat: 0)])
        try p.saveContext(c, sessionID: "t")
        let record = p.annotate(ScoreboardRecord(id: "t",gameType: .tennis,startTime: Date(),endTime: Date(),team1Name: "A",team2Name: "B",team1FinalScore: 10,team2FinalScore: 8,totalScoreChanges: 30))
        try p.enqueue(record)
        let upload = try XCTUnwrap(p.uploads(accountID: "a").first)
        XCTAssertEqual(upload.body.setScore,.init(a: 1,b: 0)); XCTAssertEqual(upload.body.sets,[.init(a: 10,b: 8)]); XCTAssertNil(upload.failure)
        p.deleteAccountData(accountID: "a"); p.repairOutbox(from: [record]); XCTAssertTrue(p.uploads(accountID: "a").isEmpty)
    }
    func testInitialResumePersistsFrozenSeatsBeforeFirstScore() async throws {
        let context = GroupMatchContext(accountID: "group-unit", groupID: "g", groupName: "group", gameID: nil, clientSessionID: UUID().uuidString, format: .doubles, rules: rules(), participants: [.init(memberId: "a", side: "A", seat: 0), .init(memberId: "b", side: "A", seat: 1), .init(memberId: "c", side: "B", seat: 0), .init(memberId: "d", side: "B", seat: 1)])
        var setup = SportsSetupResult(team1Name: "A / B", team2Name: "C / D"); setup.isSingles = false; setup.maxSets = 3
        let result = await BookingStartPersistence.persist(.init(bookingId: "", gameType: .badminton, setup: setup), groupContext: context)
        let id = try XCTUnwrap(result)
        XCTAssertEqual(GroupLocalPersistence.shared.context(sessionID: id)?.participants, context.participants)
        let uuid = try XCTUnwrap(UUID(uuidString: id))
        let restored = try XCTUnwrap(RallySessionStore(restoring: uuid))
        restored.send(.exchangeSides)
        XCTAssertEqual(GroupLocalPersistence.shared.context(sessionID: id)?.participants, context.participants)
        _ = try await AbandonedResumeSessionCoordinator().abandon(sessionID: uuid)
    }
    func testTrainingLineupAllowsAdjacentMatchesAndSeparateParallelCourts() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        var a = GroupTrainingDraftSession(startsAt: date, court: "1", format: .singles, memberIDs: ["a", "", "b", ""])
        var b = GroupTrainingDraftSession(startsAt: date.addingTimeInterval(30 * 60), court: "1", format: .singles, memberIDs: ["a", "", "b", ""])
        XCTAssertNil(GroupTrainingValidation.lineupIssue([a, b], minutes: 0))
        b.startsAt = date; b.court = "2"; b.memberIDs = ["c", "", "d", ""]
        XCTAssertNil(GroupTrainingValidation.lineupIssue([a, b], minutes: 30))
        b.memberIDs[0] = "a"
        XCTAssertNotNil(GroupTrainingValidation.lineupIssue([a, b], minutes: 30))
        b.memberIDs[0] = "c"; b.court = "  "
        XCTAssertNotNil(GroupTrainingValidation.lineupIssue([a, b], minutes: 30))
        a.startsAt = date.addingTimeInterval(1)
        XCTAssertNotNil(GroupTrainingValidation.lineupIssue([a, b], minutes: 30))
    }
    func testTrainingPlanWithResultsOmitsImmutableLineupFromPatch() throws {
        let patch = GroupTrainingPlanPatch(place: "Court", note: "Update", minutes: 90, sessions: [], hasResults: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        XCTAssertNil(json["sessions"]); XCTAssertNil(json["sessionMinutes"])
        XCTAssertEqual(json["place"] as? String, "Court")
        let editable = GroupTrainingPlanPatch(place: "Court", note: "Update", minutes: 90, sessions: [], hasResults: false)
        let editJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(editable)) as? [String: Any])
        XCTAssertNotNil(editJSON["sessions"]); XCTAssertEqual(editJSON["sessionMinutes"] as? Int, 90)
    }
    func testTrainingPreviewDecodesGroupType() throws {
        let preview = try JSONDecoder().decode(GroupPreview.self, from: Data("""
        {"groupNo":"123456","name":"Training","sport":"badminton","availability":"available","groupType":"coaching"}
        """.utf8))
        XCTAssertEqual(preview.groupType, "coaching")
        XCTAssertEqual(preview.sport, .badminton)
    }

}

@MainActor final class GroupRegistrationDraftTests: XCTestCase {
    private enum FixtureFailure: Error { case injected }

    func testReplacementAtCapacityCancelsBeforeRegistering() async throws {
        var confirmed: Set<String> = ["account", "old"]
        let plan = GroupRegistrationPlan(baseline: confirmed, desired: ["account", "new"], managedIDs: ["old", "new"], capacity: 2)
        var calls: [GroupRegistrationPlan.Change] = []
        try await plan.apply(authorize: { }, write: { change in
            calls.append(change)
            if change.registered { confirmed.insert(change.memberID) } else { confirmed.remove(change.memberID) }
            XCTAssertLessThanOrEqual(confirmed.count, 2)
        }, confirmed: { _ in })
        XCTAssertEqual(calls, [.init(memberID: "old", registered: false), .init(memberID: "new", registered: true)])
        XCTAssertEqual(confirmed, ["account", "new"])
    }

    func testFirstFailureRetainsSuccessesAndOnlyRetriesOutstandingChanges() async throws {
        var baseline: Set<String> = ["account", "old"]
        let desired: Set<String> = ["account", "a", "b"]
        let managed: Set<String> = ["old", "a", "b"]
        let plan = GroupRegistrationPlan(baseline: baseline, desired: desired, managedIDs: managed, capacity: 3)
        var calls: [String] = []
        do {
            try await plan.apply(authorize: { }, write: { change in
                calls.append(change.memberID)
                if change.memberID == "b" { throw FixtureFailure.injected }
            }, confirmed: { change in
                if change.registered { baseline.insert(change.memberID) } else { baseline.remove(change.memberID) }
            })
            XCTFail("Expected the last registration to fail")
        } catch { XCTAssertTrue(error is FixtureFailure) }
        XCTAssertEqual(calls, ["old", "a", "b"])
        XCTAssertEqual(baseline, ["account", "a"])
        let retry = GroupRegistrationPlan(baseline: baseline, desired: desired, managedIDs: managed, capacity: 3)
        XCTAssertEqual(retry.changes, [.init(memberID: "b", registered: true)])
        try await retry.apply(authorize: { }, write: { change in
            XCTAssertEqual(change.memberID, "b")
        }, confirmed: { change in baseline.insert(change.memberID) })
        XCTAssertEqual(baseline, desired)
    }

    func testFailedCancellationStopsBeforeAllAdditions() async {
        let plan = GroupRegistrationPlan(baseline: ["account", "old"], desired: ["account", "a", "b"], managedIDs: ["old", "a", "b"], capacity: 3)
        var calls: [String] = []
        var confirmations = 0
        do {
            try await plan.apply(authorize: { }, write: { change in calls.append(change.memberID); throw FixtureFailure.injected }, confirmed: { _ in confirmations += 1 })
            XCTFail("Expected cancellation failure")
        } catch { XCTAssertTrue(error is FixtureFailure) }
        XCTAssertEqual(calls, ["old"])
        XCTAssertEqual(confirmations, 0)
    }

    func testScopeAndCapacityRejectUnsafeWrites() async {
        let normal = GroupRegistrationPlan(baseline: ["account", "old"], desired: ["new"], managedIDs: ["old", "new"], capacity: 2)
        XCTAssertEqual(normal.projectedCount, 2)
        XCTAssertFalse(normal.changes.contains { $0.memberID == "account" })
        let full = GroupRegistrationPlan(baseline: ["account"], desired: ["account", "a", "b"], managedIDs: ["a", "b"], capacity: 2)
        var writes = 0
        do {
            try await full.apply(authorize: { }, write: { _ in writes += 1 }, confirmed: { _ in })
            XCTFail("Expected capacity failure")
        } catch { XCTAssertTrue(error is GroupRegistrationFailure) }
        XCTAssertEqual(writes, 0)
        do {
            try await normal.apply(authorize: { throw FixtureFailure.injected }, write: { _ in writes += 1 }, confirmed: { _ in })
            XCTFail("Expected identity/role boundary failure")
        } catch { XCTAssertTrue(error is FixtureFailure) }
        XCTAssertEqual(writes, 0)
    }
}
