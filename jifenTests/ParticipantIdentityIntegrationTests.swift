import XCTest
import Observation
import ScoreCore
import SwiftUI
import UIKit
@testable import jifen

@MainActor final class ParticipantIdentityIntegrationTests: XCTestCase {
    private var directory: URL!
    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("participant-tests-" + UUID().uuidString)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    private func store() -> ParticipantIdentityStore { .init(fileURL: directory.appendingPathComponent("identity.json")) }

    func testMergedCloudHistoryLinksBothLibrariesWithoutNativeFiles() throws {
        let identity = store(), sourceLibrary = identity.ledger.libraryId
        try identity.adopt(libraryId: sourceLibrary, accountId: "source", person: .init(id: "source-person", kind: .account))
        try identity.beginAccount("master")
        let masterLibrary = identity.ledger.libraryId
        try identity.completeAccountLink(masterId: "master", sourceId: "source", mode: "merge")
        for library in [sourceLibrary, masterLibrary] { try identity.recordReceived(key: "same-key", libraryId: library) }
        let cloud = PersonalRecordsCloudSync(fileURL: directory.appendingPathComponent("cloud.json"), identity: identity,
            currentAccountID: { "master" }, scoreRecords: { [] }, timerRecords: { [] })
        let records = [sourceLibrary, masterLibrary].map { library in
            PersonalRecordEnvelope(libraryId: library, recordKey: "same-key", kind: "score", project: "pingpong", playedAt: 1,
                participantMode: "individual", participants: [.init(seatKey: "side:0", kind: "PERSON", nameSnapshot: "旧名称")],
                summary: [:], origin: .init(platform: "android", nativeSchemaVersion: 1), nativePayload: [:], assetIds: [])
        }
        let candidates = PersonalHistoricalNames.candidates(records: [], cloudRecords: records, identity: identity, cloud: cloud)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.name, "旧名称")
        XCTAssertEqual(candidate.recordCount, 2, "Identical native IDs in merged libraries are still two matches")
        XCTAssertEqual(Set(candidate.seats.map(\.libraryId)), [sourceLibrary, masterLibrary])
        _ = try identity.link(name: candidate.name, historicalSeats: candidate.seats)
        for record in records {
            XCTAssertEqual(identity.personalSeats(for: record.recordKey, libraryId: record.libraryId), ["side:0"])
            XCTAssertTrue(PersonalRecordAdapter.isMine(record, identity: identity))
        }
    }

    func testHistoricalCandidatesExcludeArchivedLibrariesGroupsTeamsAndTraining() throws {
        let identity = store(), library = identity.ledger.libraryId
        let cloud = PersonalRecordsCloudSync(fileURL: directory.appendingPathComponent("cloud.json"), identity: identity,
            currentAccountID: { nil }, scoreRecords: { [] }, timerRecords: { [] })
        let base = PersonalRecordEnvelope(libraryId: library, recordKey: "personal", kind: "score", project: "pingpong", playedAt: 1,
            participantMode: "individual", participants: [.init(seatKey: "side:0", kind: "PERSON", nameSnapshot: "个人")],
            summary: [:], origin: .init(platform: "harmony", nativeSchemaVersion: 1), nativePayload: [:], assetIds: [])
        var excluded: [PersonalRecordEnvelope] = []
        var team = base; team.recordKey = "team"; team.participantMode = "team"; excluded.append(team)
        var training = base; training.recordKey = "training"; training.project = "basketball_training"; excluded.append(training)
        var group = base; group.recordKey = "group"; group.origin.sourceSystem = "group"; excluded.append(group)
        var foreign = base; foreign.recordKey = "foreign"; foreign.libraryId = "other-account"; excluded.append(foreign)
        var deleted = base; deleted.recordKey = "deleted"; deleted.deleted = true; excluded.append(deleted)
        let candidates = PersonalHistoricalNames.candidates(records: [], cloudRecords: [base] + excluded, identity: identity, cloud: cloud)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].recordCount, 1)
        XCTAssertEqual(candidates[0].seats[0].recordKey, "personal")
        XCTAssertThrowsError(try identity.link(name: "Other account", historicalSeats: [
            .init(libraryId: "other-account", recordKey: "personal", seat: .init(id: "side:0", name: "Other account"))]))
        XCTAssertTrue(identity.aliases.isEmpty)
    }

    func testPersonalGroupCacheRestoresBeforeAnyNetworkAndStaysAccountScoped() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = PersonalRecordEnvelope(libraryId: "group:one", recordKey: "result", kind: "score", project: "pingpong",
            playedAt: 1, participantMode: "individual", participants: [], summary: [:], origin: .init(nativeSchemaVersion: 1, sourceSystem: "group"),
            nativePayload: [:], assetIds: [])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode([record]))
        let data = try JSONSerialization.data(withJSONObject: ["rows": json, "members": [:]])
        let account = "cached-account"
        let filename = "groups-" + Data(account.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") + ".json"
        try data.write(to: directory.appendingPathComponent(filename))
        var current: String? = account
        let groups = PersonalGroupRecords(cacheDirectoryURL: directory, currentAccountID: { current })
        XCTAssertEqual(groups.visibleRows.map(\.recordKey), ["result"])
        XCTAssertFalse(groups.isLoading)
        current = "another-account"
        XCTAssertTrue(groups.visibleRows.isEmpty)
        groups.restoreCachedRows()
        XCTAssertTrue(groups.visibleRows.isEmpty)
        current = account
        groups.restoreCachedRows()
        XCTAssertEqual(groups.visibleRows.map(\.recordKey), ["result"])
    }

    func testGuestCanChooseMeBeforeLinkingOrSigningIn() {
        let store = store()
        XCTAssertTrue(store.isGuest)
        XCTAssertEqual(store.activeCount, 0)
        XCTAssertEqual(store.pickerSelections.count, 1)
        XCTAssertEqual(store.pickerSelections[0].personRef, store.person)
        XCTAssertEqual(store.person.kind, .guest)
    }

    func testPendingGuestRecordsRemainReadableOfflineOnlyForTheirIntendedAccount() throws {
        let store = store(), guestLibrary = store.ledger.libraryId
        try store.registerRecord("guest-history")
        try store.pinPendingGuest(libraryId: guestLibrary, accountId: "A")
        try store.beginAccount("A")
        XCTAssertTrue(store.canRead(recordKey: "guest-history"))
        XCTAssertEqual(store.ledger.libraryId, guestLibrary)
        try store.beginNewGuest(); try store.beginAccount("B")
        XCTAssertFalse(store.canRead(recordKey: "guest-history"))
        XCTAssertThrowsError(try store.pinPendingGuest(libraryId: guestLibrary, accountId: "B"))
    }

    func testInstallingNewAuthenticationHidesOldLibraryBeforeWarmupFinishes() throws {
        var accountId: String? = "A"
        let store = ParticipantIdentityStore(fileURL: directory.appendingPathComponent("gated.json"), currentAccountID: { accountId })
        try store.adopt(libraryId: store.ledger.libraryId, accountId: "A", person: .init(id: "person-a", kind: .account))
        try store.registerRecord("private-a")
        XCTAssertTrue(store.canRead(recordKey: "private-a"))
        accountId = "B"
        XCTAssertFalse(store.canRead(recordKey: "private-a"))
        XCTAssertFalse(store.canRead(recordKey: "unknown-legacy-a"))
        XCTAssertTrue(store.pickerSelections.isEmpty)
        XCTAssertThrowsError(try store.registerRecord("new-b-before-warmup"))
    }

    func testTimerSaveBindsOwnerBeforeAnImmediateAccountSwitch() async throws {
        let identity = store()
        try identity.beginAccount("timer-owner-A")
        let libraryA = identity.state.activeLibraryId
        let suite = "timer-owner-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = TimerRecordManager(defaults: defaults, rootURL: directory.appendingPathComponent("timers"))
        let record = GameRecordSummary(id: "account-A-timer", gameType: .chess, timestamp: 1)

        manager.addRecord(record, identity: identity)
        XCTAssertEqual(identity.state.recordLibraries[record.id], libraryA,
                       "A successful timer write must own its identity before returning")
        try identity.beginAccount("timer-owner-B")
        await Task.yield()

        XCTAssertEqual(identity.state.recordLibraries[record.id], libraryA)
        XCTAssertFalse(identity.canRead(recordKey: record.id))
        XCTAssertEqual(manager.getRecords().map(\.id), [record.id])
        try identity.beginAccount("timer-owner-A")
        XCTAssertTrue(identity.canRead(recordKey: record.id))
    }

    func testStaleAliasActionsCannotQueueAMutationForANewerAccount() throws {
        var accountID: String? = "A"
        let store = ParticipantIdentityStore(fileURL: directory.appendingPathComponent("alias-gated.json"),
            currentAccountID: { accountID })
        try store.adopt(libraryId: store.ledger.libraryId, accountId: "A", person: .init(id: "person-A", kind: .account))
        let staleAlias = try store.link(name: "Shared name")
        accountID = "B"
        XCTAssertThrowsError(try store.unlink(staleAlias))
        XCTAssertThrowsError(try store.link(name: "Must not attach to A"))
        try store.beginAccount("B")
        let currentAlias = try store.link(name: "Shared name")
        XCTAssertNotEqual(staleAlias.id, currentAlias.id)
        XCTAssertThrowsError(try store.unlink(staleAlias))
        XCTAssertThrowsError(try store.setVisibility(staleAlias, visible: false))
        XCTAssertThrowsError(try store.activate(staleAlias))
        XCTAssertEqual(store.aliases, [currentAlias])
        XCTAssertEqual(store.activeCount, 1)
    }

    func testLocalAssociationPersistsAndHiddenNameKeepsItsQuota() throws {
        let store = store()
        let alias = try store.link(name: "  YY  ")
        try store.setVisibility(alias, visible: false)
        _ = try store.link(name: "小杨"); _ = try store.link(name: "杨扬")
        XCTAssertThrowsError(try store.link(name: "第四个"))
        let restored = self.store()
        XCTAssertEqual(restored.activeCount, 3)
        XCTAssertFalse(restored.aliases.first { $0.id == alias.id }!.visibleInPicker)
    }

    func testKeepDoesNotReadOrReadoptTheDiscardedAccountLibrary() throws {
        let store = store(); let sourceLibrary = store.ledger.libraryId
        try store.migrateLegacyIfNeeded(scoreIDs: ["source-record"], timerIDs: [])
        try store.adopt(libraryId: sourceLibrary, accountId: "source", person: .init(id: "person-source", kind: .account))
        try store.beginAccount("master")
        try store.registerRecord("master-record")
        try store.completeAccountLink(masterId: "master", sourceId: "source", mode: "keep")
        XCTAssertFalse(store.canRead(recordKey: "source-record"))
        XCTAssertTrue(store.canRead(recordKey: "master-record"))
        XCTAssertTrue(store.state.archivedLibraries.contains(sourceLibrary))
        XCTAssertFalse(store.unownedLedgers.contains { $0.libraryId == sourceLibrary })
    }

    func testMergePreservesExplicitHistoryAndInstallsCanonicalPerson() throws {
        let store = store(); let sourceLibrary = store.ledger.libraryId
        try store.registerRecord("source-record", selections: ["side:0": .init(name: "YY", personRef: store.person)])
        try store.adopt(libraryId: sourceLibrary, accountId: "source", person: .init(id: "person-source", kind: .account))
        try store.beginAccount("master")
        try store.completeAccountLink(masterId: "master", sourceId: "source", mode: "merge")
        let canonical = ParticipantPersonRef(id: "person-master", kind: .account)
        try store.install(person: canonical, aliases: [], revision: 1)
        XCTAssertTrue(store.canRead(recordKey: "source-record"))
        XCTAssertEqual(store.selections(for: "source-record")["side:0"]?.name, "YY")
        XCTAssertEqual(store.selections(for: "source-record")["side:0"]?.personRef, canonical)
        XCTAssertEqual(store.personalSeats(for: "source-record"), ["side:0"])
    }

    func testSameRecordKeyInAnotherLibraryDoesNotReplaceLocalOwnership() throws {
        let store = store(); try store.registerRecord("same-id")
        let original = store.libraryId(for: "same-id")
        try store.recordReceived(key: "same-id", libraryId: "different-library")
        XCTAssertEqual(store.libraryId(for: "same-id"), original)
    }

    func testMergeRemapsAliasAndUnuploadedClaimTogetherInOtherLibrary() throws {
        let store = store(), sourceLibrary = store.ledger.libraryId
        let oldAlias = try store.link(name: "旧名")
        try store.registerRecord("old-source")
        try store.installClaims([.init(libraryId: sourceLibrary, recordKey: "old-source", seatKey: "side:0", aliasId: oldAlias.id, nameSnapshot: "旧名")])
        try store.adopt(libraryId: sourceLibrary, accountId: "source", person: .init(id: "source-person", kind: .account))
        try store.beginAccount("master")
        let masterLibrary = store.ledger.libraryId, canonicalAlias = try store.link(name: "旧名")
        try store.completeAccountLink(masterId: "master", sourceId: "source", mode: "merge")
        let person = ParticipantPersonRef(id: "master-person", kind: .account)
        try store.adopt(libraryId: masterLibrary, accountId: "master", person: person)
        try store.install(person: person, aliases: [canonicalAlias], revision: 3)
        let source = try XCTUnwrap(store.state.ledgers[sourceLibrary])
        XCTAssertEqual(source.aliases[0].id, canonicalAlias.id)
        XCTAssertEqual(source.claims[0].aliasId, source.aliases[0].id)
    }

    func testSameRecordKeyInTwoOwnedLibrariesDoesNotShareExplicitSeats() throws {
        let store = store(), firstLibrary = store.ledger.libraryId
        try store.registerRecord("same", selections: ["side:0": .init(name: "YY", personRef: store.person)])
        try store.adopt(libraryId: firstLibrary, accountId: "account", person: .init(id: "canonical", kind: .account))
        try store.recordReceived(key: "same", libraryId: "other-library")
        XCTAssertEqual(store.personalSeats(for: "same", libraryId: firstLibrary), ["side:0"])
        XCTAssertTrue(store.personalSeats(for: "same", libraryId: "other-library").isEmpty)
    }

    func testRenamingHistoricalSeatRevokesClaimWithoutChangingOriginalScore() throws {
        let store = store(); let alias = try store.link(name: "YY")
        try store.registerRecord("history")
        try store.installClaims([.init(libraryId: store.ledger.libraryId, recordKey: "history", seatKey: "side:0", aliasId: alias.id, nameSnapshot: "YY")])
        let changed = ScoreboardRecord(id: "history", gameType: .pingpong, startTime: Date(), team1Name: "别人", team2Name: "小林", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try store.reconcileSelections(record: changed)
        XCTAssertTrue(store.personalSeats(for: "history").isEmpty)
        XCTAssertTrue(store.ledger.claims[0].revoked)
        XCTAssertEqual(changed.team1FinalScore, 11)
    }

    func testTeamAndTrainingLabelsNeverProducePersonalCandidates() {
        for game in [jifen.GameType.basketball, .football, .guandan, .shengji, .simpleScore, .basketballTraining] {
            let record = ScoreboardRecord(id: UUID().uuidString, gameType: game, startTime: Date(),
                team1Name: "杨扬", team2Name: "小林", team1FinalScore: 10, team2FinalScore: 8, totalScoreChanges: 1)
            XCTAssertTrue(PersonalRecordAdapter.seats(record).isEmpty, game.rawValue)
        }
        let team = ScoreboardRecord(id: "team-format", gameType: .shuttlecock, startTime: Date(),
            team1Name: "杨扬", team2Name: "小林", team1FinalScore: 10, team2FinalScore: 8,
            totalScoreChanges: 1, extraData: ["competitionFormat": AnyCodable("team"), "team1Player1Name": AnyCodable("杨扬")])
        XCTAssertTrue(PersonalRecordAdapter.seats(team).isEmpty)
    }

    func testDoublesIdentityIsNotAssignedByNameAndManualEditClearsSelection() {
        var draft = SportsSetupDraft(); draft.isSingles = false
        draft.team1Player1Name = "YY"; draft.team1Player2Name = "YY"
        let person = ParticipantPersonRef(id: "me", kind: .guest)
        draft.participantSelections = ["side:0:player:0": .init(name: "YY", personRef: person)]
        XCTAssertEqual(draft.validParticipantSelections(gameType: .badminton).count, 1)
        draft.team1Player1Name = "别人"
        XCTAssertTrue(draft.validParticipantSelections(gameType: .badminton).isEmpty)
        draft.competitionFormat = .team
        XCTAssertTrue(draft.validParticipantSelections(gameType: .shuttlecock).isEmpty)
    }

    func testAnotherBilliardsMatchPreservesSeatIdentityAfterReload() throws {
        let store = store()
        for game in [jifen.GameType.eightBall, .snooker] {
            let previous = "previous-\(game.rawValue)", next = "next-\(game.rawValue)"
            try store.registerRecord(previous, selections: ["side:1": .init(name: "YY", personRef: store.person)])
            store.copySelections(from: previous, to: next)
            XCTAssertEqual(store.personalSeats(for: next), ["side:1"])
            XCTAssertEqual(self.store().selections(for: next)["side:1"], .init(name: "YY", personRef: store.person))
        }
    }

    func testReplayRestoresIdentityBySeatEvenWhenPlayerNamesMatch() throws {
        let store = store()
        let record = ScoreboardRecord(id: "same-name-replay", gameType: .eightBall, startTime: Date(),
            team1Name: "YY", team2Name: "YY", team1FinalScore: 5, team2FinalScore: 3, totalScoreChanges: 1)
        try store.registerRecord(record.id, selections: ["side:1": .init(name: "YY", personRef: store.person)])

        let setup = ScoreboardRecordConfiguration.setup(from: record, identity: store)
        XCTAssertEqual(setup.participantSelections, ["side:1": .init(name: "YY", personRef: store.person)])
        try store.registerRecord("replayed", selections: setup.participantSelections ?? [:])
        XCTAssertEqual(store.personalSeats(for: "replayed"), ["side:1"])
    }

    func testReplayPreservesDoublesSeatAndRejectsRenamedSelection() throws {
        let store = store()
        var record = ScoreboardRecord(id: "doubles-replay", gameType: .badminton, startTime: Date(),
            team1Name: "YY / 甲", team2Name: "乙 / 丙", team1FinalScore: 21, team2FinalScore: 19,
            totalScoreChanges: 1, projectConfiguration: [
                "team1Player1Name": AnyCodable("YY"), "team1Player2Name": AnyCodable("甲"),
                "team2Player1Name": AnyCodable("乙"), "team2Player2Name": AnyCodable("丙"),
                "isSingles": AnyCodable(false)
            ])
        try store.registerRecord(record.id, selections: ["side:0:player:0": .init(name: "YY", personRef: store.person)])
        let setup = ScoreboardRecordConfiguration.setup(from: record, identity: store)
        XCTAssertEqual(setup.participantSelections?["side:0:player:0"]?.personRef, store.person)
        record.projectConfiguration?["team1Player1Name"] = AnyCodable("别人")
        XCTAssertNil(ScoreboardRecordConfiguration.setup(from: record, identity: store).participantSelections)
    }

    func testReplayCarriesUniqueHistoricalClaimWithoutInferringOtherMatchingNames() throws {
        let store = store()
        let record = ScoreboardRecord(id: "claimed-replay", gameType: .snooker, startTime: Date(),
            team1Name: "旧名", team2Name: "旧名", team1FinalScore: 70, team2FinalScore: 50, totalScoreChanges: 1)
        try store.registerRecord(record.id)
        let alias = try store.link(name: "旧名")
        try store.installClaims([.init(libraryId: store.ledger.libraryId, recordKey: record.id,
            seatKey: "side:0", aliasId: alias.id, nameSnapshot: "旧名")])
        let setup = ScoreboardRecordConfiguration.setup(from: record, identity: store)
        XCTAssertEqual(setup.participantSelections, ["side:0": .init(name: "旧名", personRef: store.person)])
        let renamed = ScoreboardRecord(id: record.id, gameType: .snooker, startTime: record.startTime,
            team1Name: "别人", team2Name: "旧名", team1FinalScore: 70, team2FinalScore: 50, totalScoreChanges: 1)
        XCTAssertNil(ScoreboardRecordConfiguration.setup(from: renamed, identity: store).participantSelections)
        try store.installClaims([.init(libraryId: store.ledger.libraryId, recordKey: record.id,
            seatKey: "side:1", aliasId: alias.id, nameSnapshot: "旧名")])
        XCTAssertNil(ScoreboardRecordConfiguration.setup(from: record, identity: store).participantSelections)
    }

    func testReplayRestoresMultiplayerIdentityAtOriginalIndex() throws {
        let store = store()
        for game in [jifen.GameType.nineBall, .multiScoreboard, .doudizhu, .uno] {
            let record = ScoreboardRecord(id: "multiplayer-replay-\(game.rawValue)", gameType: game, startTime: Date(),
                team1Name: "甲", team2Name: "YY", team1FinalScore: 10, team2FinalScore: -5,
                totalScoreChanges: 1, extraData: ["players": AnyCodable([
                    ["name": "甲", "score": 10], ["name": "YY", "score": -5], ["name": "乙", "score": -5]
                ])])
            try store.registerRecord(record.id, selections: ["player:1": .init(name: "YY", personRef: store.person)])
            let setup = ScoreboardRecordConfiguration.setup(from: record, identity: store)
            XCTAssertEqual(setup.participantSelections, ["player:1": .init(name: "YY", personRef: store.person)], game.rawValue)
            XCTAssertEqual(setup.playerNames, ["甲", "YY", "乙"], game.rawValue)
        }
    }

    func testReplayDoesNotRestoreAnotherAccountsIdentity() throws {
        var accountID: String? = "A"
        let store = ParticipantIdentityStore(fileURL: directory.appendingPathComponent("replay-gated.json"), currentAccountID: { accountID })
        try store.adopt(libraryId: store.ledger.libraryId, accountId: "A", person: .init(id: "person-A", kind: .account))
        let record = ScoreboardRecord(id: "account-A-replay", gameType: .eightBall, startTime: Date(),
            team1Name: "YY", team2Name: "乙", team1FinalScore: 5, team2FinalScore: 3, totalScoreChanges: 1)
        try store.registerRecord(record.id, selections: ["side:0": .init(name: "YY", personRef: store.person)])
        accountID = "B"
        XCTAssertNil(ScoreboardRecordConfiguration.setup(from: record, identity: store).participantSelections)
    }

    func testPersonalSeatIndexUpdatesOnClaimRevisionAndUnlinkAndRemainsObservable() throws {
        let store = store(), recordID = "indexed-claims"
        try store.registerRecord(recordID)
        let alias = try store.link(name: "YY")
        var claim = ParticipantHistoricalClaim(id: "claim", libraryId: store.ledger.libraryId,
            recordKey: recordID, seatKey: "side:0", aliasId: alias.id, nameSnapshot: "YY", revision: 1)
        try store.installClaims([claim])
        XCTAssertEqual(store.personalSeats(for: recordID), ["side:0"])

        let changed = expectation(description: "A cached personal-seat lookup still observes ledger changes")
        withObservationTracking {
            XCTAssertEqual(store.personalSeats(for: recordID), ["side:0"])
        } onChange: {
            changed.fulfill()
        }
        claim.revoked = true; claim.revision = 2
        try store.installClaims([claim])
        XCTAssertTrue(store.personalSeats(for: recordID).isEmpty)
        wait(for: [changed], timeout: 1)

        claim.revoked = false; claim.revision = 3
        try store.installClaims([claim])
        XCTAssertEqual(store.personalSeats(for: recordID), ["side:0"])
        try store.unlink(alias)
        XCTAssertTrue(store.personalSeats(for: recordID).isEmpty)
    }

    func testRallyAndTennisConstructionDoesNotRegisterTransientSessions() {
        let before = ParticipantIdentityStore.shared.state.recordLibraries
        for _ in 0..<4 {
            _ = RallyScoreboardView(leftName: "甲", rightName: "乙", gameType: .pingpong, rules: .pingPong())
            _ = TennisScoreboardView(initialSetup: SportsSetupResult(team1Name: "甲", team2Name: "乙"))
        }
        _ = SimpleScoreboardView()
        _ = FootballScoreboardView()
        _ = ShotTrainingScoreboardView()
        _ = GuandanScoreboardView()
        _ = ShengjiScoreboardView()
        _ = BasketballScoreboardView()
        _ = BasketballSessionStore(leftName: "甲", rightName: "乙")
        _ = EightBallScoreboardView()
        _ = SnookerScoreboardView()
        _ = BilliardsScoreboardView()
        _ = NineBallChaseScoreboardView()
        _ = MultiScoreboardView()
        _ = ArcheryScoreboardView()
        _ = BoxingScoreboardView()
        _ = DoudizhuScoreboardView()
        XCTAssertEqual(ParticipantIdentityStore.shared.state.recordLibraries, before,
            "Constructing a SwiftUI value must not persist its transient session UUID")
    }

    func testHostedIdentityRegistrationUsesInstalledStateAcrossReconstructionAndReappearance() async throws {
        let store = store()
        let selection = ParticipantSelection(name: "YY", personRef: store.person)
        let appeared = expectation(description: "The hosted view actually appears")
        let registered = expectation(description: "Appearance registers the installed session")
        withObservationTracking {
            _ = store.state
        } onChange: {
            registered.fulfill()
        }
        let hosting = UIHostingController(rootView: ParticipantRegistrationHost(recordID: "installed-session",
            selections: ["side:0": selection], identity: store, onAppearance: { appeared.fulfill() }))
        XCTAssertTrue(store.state.recordLibraries.isEmpty, "Constructing the host must not write identity state")
        let navigation = UINavigationController(rootViewController: hosting)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKey() }
        hosting.view.layoutIfNeeded()
        await fulfillment(of: [appeared, registered], timeout: 5)
        XCTAssertEqual(Set(store.state.recordLibraries.keys), ["installed-session"])
        XCTAssertEqual(store.selections(for: "installed-session"), ["side:0": selection])

        // A later edit is authoritative; returning to the view must not apply
        // the original setup again and replace this seat with side:0.
        try store.registerRecord("installed-session", selections: ["side:1": selection])

        let reconstructed = expectation(description: "SwiftUI applies the reconstructed root value")
        let disappeared = expectation(description: "Navigation removes the host from view")
        let reappeared = expectation(description: "Navigation returns to the same hosted state")
        var hasDisappeared = false
        hosting.rootView = ParticipantRegistrationHost(recordID: "transient-reconstructed-session", selections: nil,
            identity: store, revision: 1,
            onAppearance: { if hasDisappeared { reappeared.fulfill() } },
            onDisappearance: {
                guard !hasDisappeared else { return }
                hasDisappeared = true; disappeared.fulfill()
            },
            onReconstruction: { reconstructed.fulfill() })
        hosting.view.layoutIfNeeded()
        await fulfillment(of: [reconstructed], timeout: 5)
        navigation.pushViewController(UIViewController(), animated: false)
        await fulfillment(of: [disappeared], timeout: 5)
        navigation.popViewController(animated: false)
        await fulfillment(of: [reappeared], timeout: 5)
        XCTAssertEqual(Set(store.state.recordLibraries.keys), ["installed-session"])
        XCTAssertEqual(store.selections(for: "installed-session"), ["side:1": selection])
    }

    func testHostedResumeDoesNotReplaceStoredParticipantSelections() async throws {
        let store = store()
        let original = ParticipantSelection(name: "YY", personRef: store.person)
        try store.registerRecord("restored-session", selections: ["side:1": original])
        let appeared = expectation(description: "The restored host actually appears")
        let hosting = UIHostingController(rootView: ParticipantRegistrationHost(recordID: "restored-session",
            selections: nil, identity: store, onAppearance: { appeared.fulfill() }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKey() }
        hosting.view.layoutIfNeeded()
        await fulfillment(of: [appeared], timeout: 5)
        XCTAssertEqual(store.selections(for: "restored-session"), ["side:1": original])
    }

    func testPendingMergeNamesDoNotCancelHistoricalClaimsOrUseExtraSlots() throws {
        let store = store(); let alias = try store.link(name: "旧名")
        let claim = ParticipantHistoricalClaim(libraryId: store.ledger.libraryId, recordKey: "old", seatKey: "side:0", aliasId: alias.id, nameSnapshot: "旧名")
        try store.registerRecord("old"); try store.installClaims([claim])
        var pending = alias; pending.state = .pending
        try store.install(person: store.person, aliases: [pending], revision: 1)
        XCTAssertEqual(store.activeCount, 0)
        XCTAssertEqual(store.personalSeats(for: "old"), ["side:0"])
    }

    func testOpaqueJSONAndParticipantWireRoundTripKeepUnknownFields() throws {
        let value = PersonalJSON.object(["future": .object(["enabled": .bool(true), "timestamp": .integer(1_790_000_000_123)]), "values": .array([.null, .number(1.25)])])
        XCTAssertEqual(try JSONDecoder().decode(PersonalJSON.self, from: JSONEncoder().encode(value)), value)
        let selection = ParticipantSelection(name: "YY", personRef: .init(id: "person-id-not-user-id", kind: .account))
        let data = try JSONEncoder().encode(selection)
        XCTAssertEqual(try JSONDecoder().decode(ParticipantSelection.self, from: data), selection)
    }
}

@MainActor
private struct ParticipantRegistrationHost: View {
    @State private var recordID: String
    @State private var initialSelections: [String: ParticipantSelection]?
    let identity: ParticipantIdentityStore
    let revision: Int
    let onAppearance: (() -> Void)?
    let onDisappearance: (() -> Void)?
    let onReconstruction: (() -> Void)?

    init(recordID: String, selections: [String: ParticipantSelection]?, identity: ParticipantIdentityStore,
         revision: Int = 0, onAppearance: (() -> Void)? = nil, onDisappearance: (() -> Void)? = nil,
         onReconstruction: (() -> Void)? = nil) {
        _recordID = State(initialValue: recordID)
        _initialSelections = State(initialValue: selections)
        self.identity = identity
        self.revision = revision
        self.onAppearance = onAppearance
        self.onDisappearance = onDisappearance
        self.onReconstruction = onReconstruction
    }

    var body: some View {
        Text(recordID)
            .registerParticipantSetupOnAppear(recordID: recordID, selections: initialSelections, identity: identity)
            .onAppear { onAppearance?() }
            .onDisappear { onDisappearance?() }
            .onChange(of: revision) { _, _ in onReconstruction?() }
    }
}
