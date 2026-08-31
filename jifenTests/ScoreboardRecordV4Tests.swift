import LinkCore
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore
import XCTest
@testable import jifen

@MainActor
final class ScoreboardRecordV4Tests: XCTestCase {
    func testFootballLegacySyntheticSetScoreNeverReplacesRealGoalScore() {
        let record = ScoreboardRecord(
            id: "football-2-0",
            gameType: .football,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "主队",
            team2Name: "客队",
            team1FinalScore: 2,
            team2FinalScore: 0,
            team1SetScore: 1,
            team2SetScore: 1,
            totalScoreChanges: 2
        )

        XCTAssertFalse(record.shouldDisplaySecondaryScore)
        XCTAssertEqual(record.primaryScore.left, 2)
        XCTAssertEqual(record.primaryScore.right, 0)
        XCTAssertFalse(record.primaryScore.usesSetScore)
    }

    func testArcheryOpeningShooterRestoresForAnotherMatch() {
        let record = makeConfigurationRecord(
            gameType: .archery,
            configuration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.archeryDual.rawValue),
                "servingSide": AnyCodable(MatchSide.right.rawValue)
            ]
        )

        XCTAssertEqual(ScoreboardRecordConfiguration.setup(from: record).servingSide, MatchSide.right.rawValue)
    }

    func testSnookerMatchTitleRestoresAndOverridesParticipantTitle() {
        let record = makeConfigurationRecord(
            gameType: .snooker,
            configuration: ["matchTitle": AnyCodable("  城市大师赛   决赛  ")]
        )

        XCTAssertEqual(record.configuredMatchTitle, "城市大师赛 决赛")
        XCTAssertEqual(record.displayMatchTitle, "城市大师赛 决赛")
        XCTAssertEqual(
            ScoreboardRecordConfiguration.setup(from: record).matchTitle,
            "城市大师赛 决赛"
        )
    }

    func testMatchTitleIsIgnoredForNonSnookerRecords() {
        let record = makeConfigurationRecord(
            gameType: .billiards,
            configuration: ["matchTitle": AnyCodable("不应显示")]
        )

        XCTAssertNil(record.configuredMatchTitle)
        XCTAssertEqual(record.displayMatchTitle, "红队 vs 蓝队")
    }

    func testRecordNoteTrimsAndTruncatesAtGraphemeBoundaries() {
        let emoji = String(repeating: "👨‍👩‍👧‍👦", count: 100)
        let normalized = ScoreboardRecordNote.normalize("  \(emoji)  ")

        XCTAssertNotNil(normalized)
        XCTAssertLessThanOrEqual(normalized?.unicodeScalars.count ?? 0, 300)
        XCTAssertTrue(normalized?.last == "👨‍👩‍👧‍👦" || normalized?.last == nil)
    }

    func testLegacyRecordDecodesWithoutNoteAndNewRecordRoundTripsNote() throws {
        var record = makeRecord()
        XCTAssertNil(record.note)
        record.note = "赛后复盘 👋"

        let decoded = try decoder().decode(ScoreboardRecord.self, from: encode(record))
        XCTAssertEqual(decoded.note, "赛后复盘 👋")
    }

    func testV3RecordDecodesWithoutV4Fields() throws {
        let old = makeRecord(schemaVersion: 3, actions: ["left +1"])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(old)) as? [String: Any])
        object.removeValue(forKey: "detailedActions")
        object.removeValue(forKey: "setResults")
        object["schemaVersion"] = 3

        let decoded = try decoder().decode(ScoreboardRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertNil(decoded.detailedActions)
        XCTAssertNil(decoded.setResults)
        XCTAssertEqual(decoded.actions, ["left +1"])
    }

    func testV4DetailedActionsRoundTrip() throws {
        let action = DetailedScoreAction(
            type: .scoreChanged,
            epochMilliseconds: 1_700_000_000_000,
            team: .team1,
            scores: [1, 0],
            setScores: [0, 0],
            setNumber: 1,
            scoreChange: 1,
            operationCode: "point"
        )
        let result = RecordSetResult(number: 1, scores: [11, 7], winner: .team1)
        var record = makeRecord()
        record.detailedActions = [action]
        record.setResults = [result]

        let decoded = try decoder().decode(ScoreboardRecord.self, from: encode(record))
        XCTAssertEqual(decoded.schemaVersion, 4)
        XCTAssertEqual(decoded.detailedActions, [action])
        XCTAssertEqual(decoded.setResults, [result])
    }

    func testDoudizhuRecordDetailShowsThreeSignedScoresRolesAndWinnerChanges() {
        let record = ScoreboardRecord(
            id: "doudizhu-detail",
            gameType: .doudizhu,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 8,
            team2FinalScore: -4,
            totalScoreChanges: 1,
            extraData: [
                "players": AnyCodable([
                    ["name": "甲", "finalScore": 8] as [String: Any],
                    ["name": "乙", "finalScore": -4] as [String: Any],
                    ["name": "丙", "finalScore": -4] as [String: Any]
                ])
            ]
        )
        let action = DetailedScoreAction(
            type: .roundFinished,
            scores: [8, -4, -4],
            roundNumber: 1,
            scoreChange: 8,
            winner: .team1,
            landlord: .team1,
            winners: [.team1],
            losers: [.team2, .team3],
            farmers: [.team2, .team3],
            participants: [
                .init(id: "player_1", name: "甲", score: 8, role: "landlord"),
                .init(id: "player_2", name: "乙", score: -4, role: "farmer"),
                .init(id: "player_3", name: "丙", score: -4, role: "farmer")
            ],
            operationCode: "doudizhu_round_landlord_1_farmers_2_3"
        )

        XCTAssertEqual(DoudizhuRecordDetailPolicy.scoreLine(for: action), "+8 / -4 / -4")
        XCTAssertEqual(DoudizhuRecordDetailPolicy.scoreLine(scores: [0, 2, -2]), "0 / +2 / -2")
        XCTAssertEqual(DoudizhuRecordDetailPolicy.winnerNames(for: action, record: record), ["甲"])
        let details = DoudizhuRecordDetailPolicy.scoreDetails(for: action, record: record)
        XCTAssertEqual(details.map(\.team), [.team1, .team2, .team3])
        XCTAssertEqual(details.map(\.playerName), ["甲", "乙", "丙"])
        XCTAssertEqual(details.map(\.role), [.landlord, .farmer, .farmer])
        XCTAssertEqual(details.map(\.scoreChange), [8, -4, -4])
        XCTAssertEqual(details.map(\.isWinner), [true, false, false])
    }

    func testDoudizhuRecordDetailProjectsTwoFarmerWinnersAndLandlordLoss() {
        let record = ScoreboardRecord(
            id: "doudizhu-farmers",
            gameType: .doudizhu,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: -6,
            team2FinalScore: 3,
            totalScoreChanges: 1,
            extraData: [
                "players": AnyCodable([
                    ["name": "甲", "finalScore": -6] as [String: Any],
                    ["name": "乙", "finalScore": 3] as [String: Any],
                    ["name": "丙", "finalScore": 3] as [String: Any]
                ])
            ]
        )
        let action = DetailedScoreAction(
            type: .roundFinished,
            scores: [-6, 3, 3],
            roundNumber: 1,
            scoreChange: 3,
            loser: .team1,
            landlord: .team1,
            winners: [.team2, .team3],
            losers: [.team1],
            farmers: [.team2, .team3],
            participants: [
                .init(id: "player_1", name: "甲", score: -6, role: "landlord"),
                .init(id: "player_2", name: "乙", score: 3, role: "farmer"),
                .init(id: "player_3", name: "丙", score: 3, role: "farmer")
            ],
            operationCode: "doudizhu_round_landlord_1_farmers_2_3"
        )

        XCTAssertEqual(DoudizhuRecordDetailPolicy.winnerNames(for: action, record: record), ["乙", "丙"])
        let details = DoudizhuRecordDetailPolicy.scoreDetails(for: action, record: record)
        XCTAssertEqual(details.map(\.team), [.team2, .team3, .team1])
        XCTAssertEqual(details.map(\.role), [.farmer, .farmer, .landlord])
        XCTAssertEqual(details.map(\.scoreChange), [3, 3, -6])
        XCTAssertEqual(details.map(\.isWinner), [true, true, false])
    }

    func testUserDefaultsBlobMigratesToIndividualAtomicFilesAndKeepsBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("record-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScoreboardRecordFileStore(rootURL: root)
        let records = [makeRecord(id: "one", actions: ["left +1"]), makeRecord(id: "two", actions: ["right +1"])]

        try store.migrateIfNeeded(legacyData: encode(records))
        let migrated = store.loadRecords()

        XCTAssertEqual(Set(migrated.map(\.id)), ["one", "two"])
        XCTAssertTrue(migrated.allSatisfy {
            $0.schemaVersion == ScoreboardRecord.currentSchemaVersion
                && $0.detailedActions?.isEmpty == false
        })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("scoreboard-records-v3-backup.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".record.json") }.count, 2)
    }

    func testCorruptedRecordIsSkippedWithoutLosingHealthyRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("record-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScoreboardRecordFileStore(rootURL: root)
        try store.migrateIfNeeded(legacyData: nil)
        try store.save(makeRecord(id: "healthy"))
        try Data("not-json".utf8).write(to: root.appendingPathComponent("broken.record.json"), options: .atomic)

        XCTAssertEqual(store.loadRecords().map(\.id), ["healthy"])
    }

    func testRecordStorePropagatesSaveFailureInsteadOfSilentlyDroppingRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("record-save-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not-a-directory".utf8).write(to: root, options: .atomic)
        let store = ScoreboardRecordFileStore(rootURL: root)

        XCTAssertThrowsError(try store.save(makeRecord(id: "must-not-disappear")))
    }

    func testFinishedSessionCommitWritesRecordBeforeRemovingResume() async throws {
        let sessionId = UUID()
        let record = makeRecord(id: sessionId.uuidString)
        var storedRecord: ScoreboardRecord?
        var events: [String] = []
        let coordinator = FinishedSessionCommitCoordinator(
            recordLookup: { _ in storedRecord },
            recordWriter: { value in
                events.append("record")
                storedRecord = value
            },
            resumeRemover: { _ in
                events.append("resume")
            }
        )

        let result = try await coordinator.commit(record, sessionId: sessionId)

        XCTAssertEqual(events, ["record", "resume"])
        XCTAssertTrue(result.recordWritten)
        XCTAssertNil(result.cleanupError)
        XCTAssertEqual(storedRecord?.id, record.id)
    }

    func testFinishedSessionCommitRecordFailureNeverRemovesResume() async {
        enum ProbeError: Error { case recordWrite }
        let sessionId = UUID()
        let record = makeRecord(id: sessionId.uuidString)
        var events: [String] = []
        let coordinator = FinishedSessionCommitCoordinator(
            recordLookup: { _ in nil },
            recordWriter: { _ in
                events.append("record")
                throw ProbeError.recordWrite
            },
            resumeRemover: { _ in
                events.append("resume")
            }
        )

        do {
            _ = try await coordinator.commit(record, sessionId: sessionId)
            XCTFail("Expected the formal record failure to propagate")
        } catch ProbeError.recordWrite {
            // Expected. The resume is still the recovery source.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(events, ["record"])
    }

    func testManualResumeRecoversPrefixedRecordIDForStartupReconciliation() throws {
        let sessionID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-resume-record-id-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordID = "football_\(sessionID.uuidString.lowercased())"
        let record = makeRecord(id: recordID, gameType: .football)
        let payload = try JSONEncoder().encode(ManualScoreboardResumeState(
            record: record,
            scoreCoreGameType: .football
        ))
        let envelope = ResumeSessionEnvelope(
            sessionId: sessionID,
            gameType: .football,
            startedAtEpochMilliseconds: 1,
            updatedAtEpochMilliseconds: 2,
            participants: [],
            scoreSummary: "1 : 0",
            payloadKind: .manualState,
            payload: payload
        )
        let snapshotURL = ResumeSessionRepository.snapshotURL(
            sessionId: sessionID,
            rootURL: root
        )
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(envelope).write(to: snapshotURL, options: .atomic)

        XCTAssertEqual(
            ManualResumeSessionStore.recordID(for: sessionID, rootURL: root),
            recordID
        )
    }

    func testFinishedSessionCleanupFailureRetriesWithoutRewritingRecord() async throws {
        enum ProbeError: Error { case cleanup }
        let sessionId = UUID()
        let record = makeRecord(id: sessionId.uuidString)
        var storedRecord: ScoreboardRecord?
        var cleanupShouldFail = true
        var events: [String] = []
        let coordinator = FinishedSessionCommitCoordinator(
            recordLookup: { _ in storedRecord },
            recordWriter: { value in
                events.append("record")
                storedRecord = value
            },
            resumeRemover: { _ in
                events.append("resume")
                if cleanupShouldFail { throw ProbeError.cleanup }
            },
            cleanupRetryScheduler: { _, _ in }
        )

        let first = try await coordinator.commit(record, sessionId: sessionId)
        XCTAssertTrue(first.recordWritten)
        XCTAssertNotNil(first.cleanupError)

        cleanupShouldFail = false
        let retry = try await coordinator.commit(record, sessionId: sessionId)

        XCTAssertFalse(retry.recordWritten)
        XCTAssertNil(retry.cleanupError)
        XCTAssertEqual(events, ["record", "resume", "resume"])
    }

    func testRecordIndexWriteFailureKeepsResumeAvailableForRetry() async throws {
        let sessionId = UUID()
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-index-failure-resume-\(UUID().uuidString)", isDirectory: true)
        let recordRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-index-failure-store-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: resumeRoot)
            try? FileManager.default.removeItem(at: recordRoot)
        }
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        let liveSession = ScoreSession<LineScoreState, LineScoreEvent>(
            sessionId: sessionId,
            gameType: .simpleScore,
            ruleFamily: .s1,
            reducerType: "line/v1",
            state: LineScoreState(
                leftName: "A",
                rightName: "B",
                rules: .freeCounter,
                leftScore: 1,
                rightScore: 0
            )
        )
        try await resumeRepository.save(liveSession)

        try FileManager.default.createDirectory(at: recordRoot, withIntermediateDirectories: true)
        // A directory at the index path lets the atomic record file write
        // succeed while forcing the subsequent index replacement to fail.
        try FileManager.default.createDirectory(
            at: recordRoot.appendingPathComponent("index.json"),
            withIntermediateDirectories: true
        )
        let recordStore = ScoreboardRecordFileStore(rootURL: recordRoot)
        let record = makeRecord(id: sessionId.uuidString)
        let coordinator = FinishedSessionCommitCoordinator(
            recordLookup: { _ in nil },
            recordWriter: { try recordStore.save($0) },
            resumeRemover: { id in try await resumeRepository.remove(sessionId: id) },
            cleanupRetryScheduler: { _, _ in }
        )

        do {
            _ = try await coordinator.commit(record, sessionId: sessionId)
            XCTFail("Expected the record index write to fail")
        } catch {
            // Expected: the durable phase is incomplete, so cleanup never runs.
        }

        let restored: ScoreSession<LineScoreState, LineScoreEvent>? = try await resumeRepository.load(
            sessionId: sessionId
        )
        XCTAssertNotNil(restored)
        let liveSessionIDs = try await resumeRepository.liveEntries().map(\.sessionId)
        XCTAssertEqual(liveSessionIDs, [sessionId])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: recordRoot.path)
                .filter { $0.hasSuffix(".record.json") }
                .count,
            1,
            "The injected fault must occur after the record file write"
        )
    }

    func testReducerFinishedRecordUsesCoordinatorAndSchedulesCleanup() async {
        let sessionId = UUID()
        var writtenRecord: ScoreboardRecord?
        let cleanup = expectation(description: "resume cleanup scheduled after record write")
        let coordinator = FinishedSessionCommitCoordinator(
            recordLookup: { _ in writtenRecord },
            recordWriter: { record in writtenRecord = record },
            resumeRemover: { _ in cleanup.fulfill() }
        )
        let state = EightBallState.initial(targetPoints: 5)

        let success = ReducerScoreboardRecordPersistence.saveRecord(
            id: sessionId.uuidString,
            gameType: .eightBall,
            startedAt: Date(),
            leftName: "A",
            rightName: "B",
            left: 1,
            right: 0,
            actionCount: 1,
            actions: ["finish"],
            finished: true,
            snapshot: state,
            finishedSessionId: sessionId,
            finishedCommitCoordinator: coordinator
        )

        XCTAssertTrue(success)
        XCTAssertEqual(writtenRecord?.id, sessionId.uuidString)
        await fulfillment(of: [cleanup], timeout: 2)
    }

    func testReducerFinishedRecordReplacementOverwritesSnapshotAfterTerminalUndo() async throws {
        let sessionId = UUID()
        var storedRecord: ScoreboardRecord? = makeRecord(
            id: sessionId.uuidString,
            actions: ["old-finish"],
            gameType: .snooker
        )
        var writeCount = 0
        let cleanup = expectation(description: "replacement record cleanup scheduled")
        let coordinator = FinishedSessionCommitCoordinator(
            recordLookup: { _ in storedRecord },
            recordWriter: { record in
                writeCount += 1
                storedRecord = record
            },
            resumeRemover: { _ in cleanup.fulfill() }
        )
        var replacementState = SnookerState.initial(striker: .left, maxFrames: 1)
        replacementState.leftScore = 23
        replacementState.leftFrames = 1
        replacementState.finished = true

        let success = ReducerScoreboardRecordPersistence.saveRecord(
            id: sessionId.uuidString,
            gameType: .snooker,
            startedAt: Date(timeIntervalSince1970: 1),
            leftName: "甲",
            rightName: "乙",
            left: replacementState.leftScore,
            right: replacementState.rightScore,
            leftSets: replacementState.leftFrames,
            rightSets: replacementState.rightFrames,
            actionCount: 2,
            actions: ["point", "new-finish"],
            finished: true,
            snapshot: replacementState,
            finishedSessionId: sessionId,
            finishedCommitCoordinator: coordinator,
            replaceCommittedFinishedRecord: true
        )

        XCTAssertTrue(success)
        XCTAssertEqual(writeCount, 1, "The prior formal record must be overwritten exactly once")
        XCTAssertEqual(storedRecord?.actions, ["point", "new-finish"])
        XCTAssertEqual(storedRecord?.team1FinalScore, 23)
        let snapshotData = try XCTUnwrap(storedRecord?.stateSnapshot)
        XCTAssertEqual(
            try JSONDecoder().decode(SnookerState.self, from: snapshotData),
            replacementState
        )
        await fulfillment(of: [cleanup], timeout: 2)
    }

    func testCatalogDrivenRecordPoliciesCover28PublicEntriesAnd33ExactGameTypes() throws {
        let publicGameTypes = GameCatalog.scoreboardItems.map(\.gameType)
        XCTAssertEqual(publicGameTypes.count, 28)
        XCTAssertEqual(Set(publicGameTypes).count, 28)

        let exactGameTypes = ScoreCore.GameType.allCases
        XCTAssertEqual(exactGameTypes.count, 33)
        let mappedExactTypes = try exactGameTypes.map { exactType in
            try XCTUnwrap(jifen.GameType(scoreCoreGameType: exactType), "Missing public catalog mapping for \(exactType)")
        }
        XCTAssertEqual(Set(mappedExactTypes), Set(publicGameTypes))

        for game in publicGameTypes {
            let policy = ScoreboardRecordProjectPolicy.policy(for: game)
            XCTAssertEqual(
                policy.detailLayout,
                game == .multiScoreboard ? .multiScoreTimeline : .standard,
                "Unexpected detail layout for \(game)"
            )
            var record = makeRecord(id: "catalog-\(game.rawValue)", gameType: game)
            record.detailedActions = [
                .init(type: .scoreChanged, scores: [1, 0], scoreChange: 1)
            ]
            XCTAssertEqual(
                ScoreboardRecordPresentation(record: record).canShowTrend,
                policy.trendAllowed,
                "Trend presentation diverged from catalog policy for \(game)"
            )
        }

        for exactType in exactGameTypes {
            let publicType = try XCTUnwrap(jifen.GameType(scoreCoreGameType: exactType))
            XCTAssertTrue(publicGameTypes.contains(publicType), "\(exactType) is not reachable from GameCatalog")
            XCTAssertTrue(
                RecordsProjectFilter(gameType: publicType, scope: .exact(exactType))
                    .matches(scoreCoreGameType: exactType),
                "Exact record filter does not match \(exactType)"
            )
        }

        XCTAssertEqual(
            ScoreboardRecordProjectPolicy.policy(for: .multiScoreboard).detailLayout,
            .multiScoreTimeline
        )
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .tennis).recapKind, .tennisSets)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .basketball).recapKind, .periods)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .boxing).recapKind, .rounds)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .multiScoreboard).recapKind, .ranking)
    }

    func testMultiScoreDetailBuilderParsesLegacyAdjustmentsAndFiltersLayout() {
        var record = makeRecord(gameType: .multiScoreboard)
        record.extraData = [
            "players": AnyCodable([
                ["name": "同名", "score": 4],
                ["name": "同名", "score": -2],
                ["name": "第三位", "score": 5]
            ])
        ]
        record.actions = [
            "1700000001000|adjust:0:+3",
            "1700000001000|adjust:1:-2",
            "1700000002000|edit:2:+5",
            "1700000002500|layout:landscape",
            "1700000003000|reset",
            "1700000004000|undo",
            "1700000005000|finish",
            "1700000006000|adjust:9:+1",
            "legacy_state"
        ]

        let rows = MultiScoreRecordDetailBuilder.build(record: record)

        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(rows[0].event, .scoreAdjustment(participantName: "同名", delta: 3))
        XCTAssertEqual(rows[1].event, .scoreAdjustment(participantName: "同名", delta: -2))
        XCTAssertNotEqual(rows[0].id, rows[1].id)
        XCTAssertEqual(rows[2].event, .scoreAdjustment(participantName: "第三位", delta: 5))
        XCTAssertEqual(rows[3].event, .reset)
        XCTAssertEqual(rows[4].event, .undo)
        XCTAssertEqual(rows[5].event, .matchFinished)
        XCTAssertEqual(rows[6].event, .scoreAdjustment(participantName: nil, delta: 1))
        XCTAssertEqual(rows[7].event, .stateChanged)
    }

    func testMultiScoreDetailBuilderSupportsUntimedLegacyAndStructuredFallback() {
        var record = makeRecord(gameType: .multiScoreboard)
        record.extraData = [
            "players": AnyCodable([
                ["name": "甲", "score": 1],
                ["name": "乙", "score": 2],
                ["name": "丙", "score": 3]
            ])
        ]
        record.actions = ["adjust:0:+1"]

        let untimed = MultiScoreRecordDetailBuilder.build(record: record)
        XCTAssertEqual(untimed.first?.epochMilliseconds, nil)
        XCTAssertEqual(untimed.first?.event, .scoreAdjustment(participantName: "甲", delta: 1))

        record.actions = ["1700000000000|layout:portrait"]
        record.detailedActions = [
            .init(type: .matchStarted, epochMilliseconds: 1_700_000_000_000),
            .init(
                type: .scoreChanged,
                epochMilliseconds: 1_700_000_001_000,
                team: .team3,
                scoreChange: -4
            ),
            .init(type: .matchFinished, epochMilliseconds: 1_700_000_002_000)
        ]

        let structured = MultiScoreRecordDetailBuilder.build(record: record)
        XCTAssertEqual(structured.map(\.event), [
            .matchStarted,
            .scoreAdjustment(participantName: "丙", delta: -4),
            .matchFinished
        ])
    }

    func testBasketballDetailsNeverShowScoreTrend() {
        for gameType in [jifen.GameType.basketball, .threeBasketball] {
            var record = makeRecord(id: "no-trend-\(gameType.rawValue)", gameType: gameType)
            record.detailedActions = [
                .init(type: .scoreChanged, scores: [1, 0], scoreChange: 1),
                .init(type: .scoreChanged, scores: [1, 1], scoreChange: 1)
            ]

            XCTAssertFalse(ScoreboardRecordPresentation(record: record).canShowTrend, "\(gameType)")
        }
    }

    func testTrendUsesRealScoreChangesAndResetStartsNewSegment() {
        var record = makeRecord()
        record.detailedActions = [
            .init(type: .scoreChanged, scores: [1, 0], scoreChange: 1),
            .init(type: .foul, scores: [1, 0]),
            .init(type: .scoreChanged, scores: [1, 1], scoreChange: 1),
            .init(type: .reset, scores: [1, 1]),
            .init(type: .scoreChanged, scores: [0, 1], scoreChange: 1),
            .init(type: .scoreChanged, scores: [1, 1], scoreChange: 1)
        ]
        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.trendTabs.count, 2)
        XCTAssertEqual(
            presentation.trendTabs[0].points.map { [$0.left, $0.right] },
            [[0, 0], [1, 0], [1, 1]]
        )
        XCTAssertEqual(
            presentation.trendTabs[1].points.map { [$0.left, $0.right] },
            [[0, 0], [0, 1], [1, 1]]
        )
        XCTAssertNotEqual(presentation.trendTabs[0].title, presentation.trendTabs[1].title)
        XCTAssertTrue(presentation.canShowTrend)
    }

    func testTrendFallsBackAcrossPeriodSetAndRoundNumbers() {
        var record = makeRecord()
        record.detailedActions = [
            .init(type: .scoreChanged, scores: [1, 0], setNumber: 1, scoreChange: 1),
            .init(type: .scoreChanged, scores: [0, 1], periodNumber: 2, scoreChange: 1),
            .init(type: .scoreChanged, scores: [2, 0], roundNumber: 3, scoreChange: 1),
        ]

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.trendTabs.count, 1)
        XCTAssertEqual(
            presentation.trendTabs[0].points.map { [$0.left, $0.right] },
            [[0, 0], [1, 0], [0, 1], [2, 0]]
        )
        XCTAssertEqual(presentation.recap.count, 1)
        XCTAssertNil(presentation.recap.first?.number)
        XCTAssertEqual(presentation.recap.first?.actions.count, 3)
        XCTAssertEqual(presentation.recapGroupingQuality, .overallFallback)
    }

    func testTrendGeometryUsesOnlyTheSelectedTabPointCount() {
        let shortTab = ScoreboardTrendChartGeometry.xPositions(pointCount: 3, width: 200)
        let longTab = ScoreboardTrendChartGeometry.xPositions(pointCount: 9, width: 200)

        XCTAssertEqual(shortTab.first, 8)
        XCTAssertEqual(shortTab.last, 192)
        XCTAssertEqual(longTab.first, 8)
        XCTAssertEqual(longTab.last, 192)
        XCTAssertEqual(shortTab[1], 100)
    }

    func testTrendIncludesFoulUndoAndAdministrativeChangesInOriginalOrder() {
        var record = makeRecord(gameType: .snooker)
        record.detailedActions = [
            .init(type: .scoreChanged, epochMilliseconds: 1_000, scores: [1, 0], setNumber: 1, scoreChange: 1),
            .init(type: .foul, epochMilliseconds: 1_000, scores: [1, 4], setNumber: 1, scoreChange: 4),
            .init(type: .serveChanged, epochMilliseconds: 1_000, scores: [1, 4], setNumber: 1),
            .init(type: .undo, epochMilliseconds: 1_000, scores: [1, 0], setNumber: 1),
            .init(type: .stateChanged, epochMilliseconds: 1_000, scores: [3, 2], setNumber: 1, operationCode: "snooker_edit"),
            .init(type: .sideChanged, epochMilliseconds: 1_000, scores: [3, 2], setNumber: 1),
            .init(type: .setFinished, epochMilliseconds: 2_000, scores: [3, 2], setNumber: 1)
        ]

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.trendTabs.count, 1)
        XCTAssertEqual(
            presentation.trendTabs[0].points.map { [$0.left, $0.right] },
            [[0, 0], [1, 0], [1, 4], [1, 0], [3, 2]]
        )
    }

    func testTrendParsesLegacyLineScoreIntentsWhenDetailedActionsAreEmpty() {
        var record = makeRecord(
            actions: [
                "1000|adjust(side: ScoreCore.MatchSide.left, delta: 3)",
                "2000|pointWon(ScoreCore.MatchSide.right)",
                "3000|exchangeSides",
                "4000|finish"
            ],
            gameType: .simpleScore
        )
        record.detailedActions = []

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(
            presentation.trendTabs.first?.points.map { [$0.left, $0.right] },
            [[0, 0], [3, 0], [3, 1]]
        )
        XCTAssertTrue(presentation.canShowTrend)
    }

    func testTrendUsesStableLineScoreSnapshotsAndSplitsReset() {
        let record = makeRecord(
            actions: [
                "1000|snapshot|score_adjust|2,0",
                "2000|snapshot|undo|0,0",
                "3000|snapshot|score_adjust|0,1",
                "4000|snapshot|reset|0,0",
                "5000|snapshot|score_adjust|3,0",
                "6000|snapshot|finish|3,0"
            ],
            gameType: .billiards
        )

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.trendTabs.count, 2)
        XCTAssertEqual(
            presentation.trendTabs[0].points.map { [$0.left, $0.right] },
            [[0, 0], [2, 0], [0, 0], [0, 1]]
        )
        XCTAssertEqual(
            presentation.trendTabs[1].points.map { [$0.left, $0.right] },
            [[0, 0], [3, 0]]
        )
    }

    func testLineScoreViewModelRecordsExactSnapshotsForScoreUndoAndReset() {
        let controller = SimpleScoreboardController()
        let viewModel = LineScoreViewModel(controller: controller, rules: .freeCounter)

        viewModel.adjustScore(isLeft: true, delta: 3)
        XCTAssertTrue(viewModel.undo())
        viewModel.adjustScore(isLeft: false, delta: 2)
        viewModel.reset()

        let bodies = controller.getGameActions().map { raw in
            raw.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? raw
        }
        XCTAssertEqual(bodies, [
            "snapshot|score_adjust|3,0",
            "snapshot|undo|0,0",
            "snapshot|score_adjust|0,2",
            "snapshot|reset|0,0"
        ])
    }

    func testLineScoreFinishUndoResumeAndRefinishKeepsOneTerminalAction() {
        let controller = SimpleScoreboardController()
        let viewModel = LineScoreViewModel(controller: controller, rules: .freeCounter)
        viewModel.adjustScore(isLeft: true, delta: 2)
        viewModel.endGame()

        XCTAssertTrue(viewModel.gameFinished)
        XCTAssertTrue(viewModel.undo())
        XCTAssertFalse(viewModel.gameFinished)

        let resume = LineScoreResumeState(
            state: viewModel.sessionState,
            undoHistory: viewModel.resumeHistory,
            intentTimeline: controller.getGameActions()
        )
        let restoredController = SimpleScoreboardController()
        restoredController.gameActions = resume.intentTimeline
        let restored = LineScoreViewModel(controller: restoredController, rules: .freeCounter)
        restored.restoreSession(resume)
        restored.endGame()

        let bodies = restoredController.getGameActions().map(actionBody)
        XCTAssertEqual(bodies.filter { $0.contains("|finish|") }.count, 1)
        XCTAssertEqual(restored.leftTeam.score, 2)
        XCTAssertTrue(restored.gameFinished)
        XCTAssertEqual(restored.persistenceRevision, 1)
    }

    func testBoxingAndArcheryUndoRollbackTerminalRecordActionsAcrossResume() {
        let boxingController = BoxingScoreboardController()
        let boxing = BoxingViewModel(controller: boxingController)
        boxing.setMaxRounds(1)
        boxing.addRoundScore(leftPoints: 10, rightPoints: 9)
        XCTAssertTrue(boxing.gameFinished)
        XCTAssertTrue(boxing.undo())

        let boxingResume = BoxingResumeState(
            state: BoxingMatchState(
                leftName: boxing.leftTeam.name,
                rightName: boxing.rightTeam.name,
                maxRounds: boxing.maxRounds,
                leftTotal: boxing.leftTeam.score,
                rightTotal: boxing.rightTeam.score,
                leftRoundsWon: boxing.leftTeam.sets ?? 0,
                rightRoundsWon: boxing.rightTeam.sets ?? 0,
                currentRound: boxing.currentRound,
                sidesSwapped: boxing.sidesSwapped,
                finished: boxing.gameFinished
            ),
            undoHistory: boxing.resumeHistory,
            intentTimeline: boxingController.getGameActions()
        )
        let restoredBoxingController = BoxingScoreboardController()
        restoredBoxingController.gameActions = boxingResume.intentTimeline
        let restoredBoxing = BoxingViewModel(controller: restoredBoxingController)
        restoredBoxing.restoreSession(boxingResume)
        restoredBoxing.addRoundScore(leftPoints: 10, rightPoints: 8)
        XCTAssertEqual(
            restoredBoxingController.getGameActions().map(actionBody).filter { $0.hasPrefix("round ") }.count,
            1
        )
        XCTAssertTrue(restoredBoxing.gameFinished)

        let archeryController = BaseScoreboardController(config: .init(gameType: .archery))
        let archery = ArcheryViewModel(controller: archeryController)
        archery.recordArrow(value: 10)
        archery.endGame()
        XCTAssertTrue(archery.gameFinished)
        XCTAssertTrue(archery.undo())
        XCTAssertFalse(archery.gameFinished)
        XCTAssertFalse(archery.detailedActions.contains { $0.type == .matchFinished })

        let archeryResume = ArcheryResumeState(
            state: archery.match,
            undoHistory: archery.resumeHistory,
            intentTimeline: archeryController.getGameActions(),
            detailedActions: archery.detailedActions,
            recordUndoCheckpoints: archery.recordUndoCheckpoints
        )
        let restoredArcheryController = BaseScoreboardController(config: .init(gameType: .archery))
        restoredArcheryController.gameActions = archeryResume.intentTimeline
        let restoredArchery = ArcheryViewModel(controller: restoredArcheryController)
        restoredArchery.restoreSession(archeryResume)
        restoredArchery.endGame()
        XCTAssertEqual(
            restoredArchery.detailedActions.filter { $0.type == .matchFinished }.count,
            1
        )
    }

    func testReducerAdaptersOwnTemplateMenuSnapshotsWithoutLegacyDuplicates() {
        let lineController = SimpleScoreboardController()
        let line = LineScoreViewModel(controller: lineController, rules: .freeCounter)
        XCTAssertTrue(line.recordsExchangeActionInternally)
        XCTAssertTrue(line.recordsResetActionInternally)
        XCTAssertTrue(line.recordsUndoActionInternally)
        line.exchangeSides()
        line.reset()
        XCTAssertEqual(lineController.getGameActions().map(actionBody), [
            "snapshot|exchange_side|0,0",
            "snapshot|reset|0,0"
        ])

        let boxingController = BoxingScoreboardController()
        let boxing = BoxingViewModel(controller: boxingController)
        boxing.exchangeSides()
        boxing.reset()
        XCTAssertEqual(boxingController.getGameActions().map(actionBody), [
            "snapshot|exchange_side|0,0|0,0",
            "snapshot|reset|0,0|0,0"
        ])

        let archeryController = BaseScoreboardController(config: .init(gameType: .archery))
        let archery = ArcheryViewModel(controller: archeryController)
        archery.exchangeSides()
        archery.reset()
        archery.endGame()
        XCTAssertEqual(archeryController.getGameActions().map(actionBody), [
            "snapshot|exchange_sides|0,0|0,0",
            "snapshot|reset|0,0|0,0",
            "snapshot|finish|0,0|0,0"
        ])
        XCTAssertEqual(archery.detailedActions.filter { $0.type == .sideChanged }.count, 1)
        XCTAssertEqual(archery.detailedActions.filter { $0.type == .reset }.count, 1)
        XCTAssertEqual(archery.detailedActions.filter { $0.type == .matchFinished }.count, 1)
    }

    func testLineAndBoxingPersistenceRevisionAdvancesOnlyForAcceptedMutationsAndUndo() {
        let line = LineScoreViewModel(
            controller: SimpleScoreboardController(),
            rules: .freeCounter
        )
        XCTAssertEqual(line.persistenceRevision, 0)
        line.adjustScore(isLeft: true, delta: 0)
        XCTAssertEqual(line.persistenceRevision, 0)
        line.adjustScore(isLeft: true, delta: 1)
        XCTAssertEqual(line.persistenceRevision, 1)
        XCTAssertTrue(line.undo())
        XCTAssertEqual(line.persistenceRevision, 2)

        let boxing = BoxingViewModel(controller: BoxingScoreboardController())
        XCTAssertEqual(boxing.persistenceRevision, 0)
        boxing.addRoundScore(leftPoints: 10, rightPoints: 9)
        XCTAssertEqual(boxing.persistenceRevision, 1)
        XCTAssertTrue(boxing.undo())
        XCTAssertEqual(boxing.persistenceRevision, 2)
    }

    func testArcheryAndBoxingNameEditsRoundTripThroughAuthoritativeResumeState() throws {
        let archeryController = BaseScoreboardController(config: .init(gameType: .archery))
        let archery = ArcheryViewModel(controller: archeryController)
        let originalArcheryName = archery.match.leftName
        archery.startEditName(isLeft: true)
        archery.updateInput(isLeft: true, value: "  新射手  ")
        archery.confirmEditName(isLeft: true)

        XCTAssertEqual(archery.match.leftName, "新射手")
        XCTAssertEqual(archery.leftTeam.name, "新射手")
        XCTAssertEqual(archery.persistenceRevision, 1)
        XCTAssertEqual(archery.resumeHistory.count, 1)
        XCTAssertEqual(archery.recordUndoCheckpoints.count, 1)
        XCTAssertEqual(archery.detailedActions.last?.operationCode, "archery_edit_names")
        XCTAssertEqual(
            archeryController.getGameActions().map(actionBody),
            ["snapshot|archery_edit_names|0,0|0,0"]
        )

        let archerySnapshot = ArcheryResumeState(
            state: archery.match,
            undoHistory: archery.resumeHistory,
            intentTimeline: archeryController.getGameActions(),
            detailedActions: archery.detailedActions,
            recordUndoCheckpoints: archery.recordUndoCheckpoints
        )
        let decodedArchery = try JSONDecoder().decode(
            ArcheryResumeState.self,
            from: JSONEncoder().encode(archerySnapshot)
        )
        let restoredArcheryController = BaseScoreboardController(config: .init(gameType: .archery))
        restoredArcheryController.gameActions = decodedArchery.intentTimeline
        let restoredArchery = ArcheryViewModel(controller: restoredArcheryController)
        restoredArchery.restoreSession(decodedArchery)
        XCTAssertEqual(restoredArchery.match.leftName, "新射手")
        XCTAssertTrue(restoredArchery.undo())
        XCTAssertEqual(restoredArchery.match.leftName, originalArcheryName)

        let boxingController = BoxingScoreboardController()
        let boxing = BoxingViewModel(controller: boxingController)
        let originalBoxingName = boxing.matchState.rightName
        boxing.startEditName(isLeft: false)
        boxing.updateInput(isLeft: false, value: "  蓝拳手  ")
        boxing.confirmEditName(isLeft: false)

        XCTAssertEqual(boxing.matchState.rightName, "蓝拳手")
        XCTAssertEqual(boxing.rightTeam.name, "蓝拳手")
        XCTAssertEqual(boxing.persistenceRevision, 1)
        XCTAssertEqual(
            boxingController.getGameActions().map(actionBody),
            ["snapshot|edit_names|0,0|0,0"]
        )

        let boxingSnapshot = BoxingResumeState(
            state: boxing.matchState,
            undoHistory: boxing.resumeHistory,
            intentTimeline: boxingController.getGameActions()
        )
        let decodedBoxing = try JSONDecoder().decode(
            BoxingResumeState.self,
            from: JSONEncoder().encode(boxingSnapshot)
        )
        let restoredBoxingController = BoxingScoreboardController()
        restoredBoxingController.gameActions = decodedBoxing.intentTimeline
        let restoredBoxing = BoxingViewModel(controller: restoredBoxingController)
        restoredBoxing.restoreSession(decodedBoxing)
        XCTAssertEqual(restoredBoxing.matchState.rightName, "蓝拳手")
        XCTAssertTrue(restoredBoxing.undo())
        XCTAssertEqual(restoredBoxing.matchState.rightName, originalBoxingName)
    }

    func testTrendRejectsNegativeAllZeroAndMultiplayerRecords() {
        var negative = makeRecord(gameType: .simpleScore)
        negative.detailedActions = [
            .init(type: .scoreChanged, scores: [-1, 0], scoreChange: -1)
        ]
        XCTAssertFalse(ScoreboardRecordPresentation(record: negative).canShowTrend)

        var allZero = makeRecord(gameType: .billiards)
        allZero.detailedActions = [
            .init(type: .scoreChanged, scores: [0, 0], scoreChange: 0)
        ]
        XCTAssertFalse(ScoreboardRecordPresentation(record: allZero).canShowTrend)

        var multiplayer = makeRecord(gameType: .nineBall)
        multiplayer.extraData = [
            "players": AnyCodable([
                ["name": "A", "score": 1],
                ["name": "B", "score": 0],
                ["name": "C", "score": 0]
            ])
        ]
        multiplayer.detailedActions = [
            .init(type: .scoreChanged, scores: [1, 0, 0], scoreChange: 1)
        ]
        XCTAssertFalse(ScoreboardRecordPresentation(record: multiplayer).canShowTrend)

        for gameType in [jifen.GameType.pingpong, .archery, .snooker] {
            var negativeByProject = makeRecord(gameType: gameType)
            negativeByProject.detailedActions = [
                .init(type: .scoreChanged, scores: [1, 0], setNumber: 1, scoreChange: 1),
                .init(type: .stateChanged, scores: [1, -1], setNumber: 1)
            ]
            XCTAssertFalse(
                ScoreboardRecordPresentation(record: negativeByProject).canShowTrend,
                "\(gameType)"
            )
        }
    }

    func testTrendIncludesBoundaryWhenItCarriesTheOnlyFinalScoreChange() {
        var record = makeRecord(gameType: .pingpong)
        record.detailedActions = [
            .init(type: .scoreChanged, scores: [10, 8], setNumber: 1, scoreChange: 1),
            .init(type: .setFinished, scores: [11, 8], setNumber: 1)
        ]

        XCTAssertEqual(
            ScoreboardRecordPresentation(record: record).trendTabs.first?.points.map {
                [$0.left, $0.right]
            },
            [[0, 0], [10, 8], [11, 8]]
        )
    }

    func testTrendTrimsLegacyTrailingPostSetScoreDrop() {
        var record = makeRecord(gameType: .pingpong)
        record.detailedActions = [
            .init(type: .scoreChanged, epochMilliseconds: 1_000, scores: [9, 8], setNumber: 1, scoreChange: 1),
            .init(type: .scoreChanged, epochMilliseconds: 2_000, scores: [10, 8], setNumber: 1, scoreChange: 1),
            .init(type: .scoreChanged, epochMilliseconds: 3_000, scores: [0, 0], setNumber: 2, scoreChange: 1),
            .init(type: .setFinished, epochMilliseconds: 3_000, scores: [10, 8], setNumber: 1)
        ]

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(
            presentation.trendTabs.first?.points.map { [$0.left, $0.right] },
            [[0, 0], [9, 8], [10, 8]]
        )
    }

    func testRecapGroupsRallySetsAndRepairsTerminalPointAdvancedToNextSet() {
        var record = makeRecord(gameType: .pingpong)
        let actions: [DetailedScoreAction] = [
            .init(type: .matchStarted, epochMilliseconds: 1_000, scores: [0, 0]),
            .init(type: .scoreChanged, epochMilliseconds: 2_000, team: .team1, scores: [20, 19], setNumber: 1, scoreChange: 1, operationCode: "set_one_point"),
            // Some legacy Rally records stamped the terminal point with the
            // already-advanced currentSet. The adjacent boundary is authoritative.
            .init(type: .scoreChanged, epochMilliseconds: 3_000, team: .team1, scores: [21, 19], setNumber: 2, scoreChange: 1, operationCode: "set_one_terminal"),
            .init(type: .setFinished, epochMilliseconds: 3_000, scores: [21, 19], setScores: [1, 0], setNumber: 1, winner: .team1, operationCode: "set_completed"),
            .init(type: .scoreChanged, epochMilliseconds: 4_000, team: .team2, scores: [0, 1], setNumber: 2, scoreChange: 1, operationCode: "set_two_point"),
            .init(type: .setFinished, epochMilliseconds: 5_000, scores: [11, 8], setScores: [1, 1], setNumber: 2, winner: .team2, operationCode: "set_completed"),
            .init(type: .matchFinished, epochMilliseconds: 6_000, scores: [11, 8], setScores: [1, 1])
        ]
        record.detailedActions = actions
        record.setResults = ScoreboardRecordActionAdapter.setResults(from: actions)

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.recap.map(\.number), [1, 2])
        XCTAssertEqual(presentation.timelineSections, presentation.recap)
        XCTAssertEqual(presentation.recapGroupingQuality, .explicit)
        XCTAssertEqual(
            presentation.recap[0].actions.compactMap(\.operationCode),
            ["set_one_point", "set_one_terminal", "set_completed"]
        )
        XCTAssertTrue(presentation.recap[1].actions.contains { $0.type == .matchFinished })
        XCTAssertEqual(
            presentation.trendTabs.map(\.id),
            ["sets-0-1-trend-0", "sets-0-2-trend-0"]
        )
        XCTAssertEqual(
            presentation.trendTabs[0].points.map { [$0.left, $0.right] },
            [[0, 0], [20, 19], [21, 19]]
        )
        XCTAssertEqual(
            presentation.trendTabs[1].points.map { [$0.left, $0.right] },
            [[0, 0], [0, 1], [11, 8]]
        )
    }

    func testRecapRepairsOnlyTheTerminalScoreAdjacentToEachSameTimestampBoundary() {
        var record = makeRecord(gameType: .pingpong)
        let actions: [DetailedScoreAction] = [
            .init(type: .scoreChanged, epochMilliseconds: 3_000, scores: [11, 8], setNumber: 2, scoreChange: 1, operationCode: "set_one_terminal"),
            .init(type: .setFinished, epochMilliseconds: 3_000, scores: [11, 8], setNumber: 1, operationCode: "set_one_finished"),
            .init(type: .scoreChanged, epochMilliseconds: 3_000, scores: [11, 9], setNumber: 3, scoreChange: 1, operationCode: "set_two_terminal"),
            .init(type: .setFinished, epochMilliseconds: 3_000, scores: [11, 9], setNumber: 2, operationCode: "set_two_finished")
        ]
        record.detailedActions = actions

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.recap.map(\.number), [1, 2])
        XCTAssertEqual(
            presentation.recap[0].actions.compactMap(\.operationCode),
            ["set_one_terminal", "set_one_finished"]
        )
        XCTAssertEqual(
            presentation.recap[1].actions.compactMap(\.operationCode),
            ["set_two_terminal", "set_two_finished"]
        )
    }

    func testMatchFinishedAlwaysStaysInTheLastSegmentEvenWithAdvancedLegacyNumber() {
        var record = makeRecord(gameType: .pingpong)
        record.detailedActions = [
            .init(type: .scoreChanged, scores: [11, 8], setNumber: 1, scoreChange: 1),
            .init(type: .setFinished, scores: [11, 8], setNumber: 1),
            .init(type: .scoreChanged, scores: [11, 7], setNumber: 2, scoreChange: 1),
            .init(type: .setFinished, scores: [11, 7], setNumber: 2),
            .init(type: .matchFinished, scores: [11, 7], setNumber: 3)
        ]

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.recap.map(\.number), [1, 2])
        XCTAssertTrue(presentation.recap[1].actions.contains { $0.type == .matchFinished })
    }

    func testSetResultsSelectsTheNumberAxisForEachFinishedActionType() {
        let actions: [DetailedScoreAction] = [
            .init(type: .setFinished, setNumber: nil, gameNumber: 3, roundNumber: 30, periodNumber: 300),
            .init(type: .roundFinished, setNumber: 4, gameNumber: 40, roundNumber: 5, periodNumber: 500),
            .init(type: .periodFinished, setNumber: 6, gameNumber: 60, roundNumber: 600, periodNumber: 7)
        ]

        XCTAssertEqual(ScoreboardRecordActionAdapter.setResults(from: actions).map(\.number), [3, 5, 7])
    }

    func testTennisRecapInfersUnnumberedPointsFromSetBoundaries() {
        var record = makeRecord(gameType: .tennis)
        let actions: [DetailedScoreAction] = [
            .init(type: .matchStarted, epochMilliseconds: 1_000, scores: [0, 0]),
            .init(type: .scoreChanged, epochMilliseconds: 2_000, scores: [1, 0], operationCode: "set_one_point"),
            .init(type: .stateChanged, epochMilliseconds: 3_000, scores: [6, 4], operationCode: "game_completed"),
            .init(type: .setFinished, epochMilliseconds: 3_000, scores: [6, 4], setScores: [1, 0], setNumber: 1, winner: .team1),
            .init(type: .scoreChanged, epochMilliseconds: 4_000, scores: [0, 1], operationCode: "set_two_point"),
            .init(type: .setFinished, epochMilliseconds: 5_000, scores: [4, 6], setScores: [1, 1], setNumber: 2, winner: .team2),
            .init(type: .matchFinished, epochMilliseconds: 6_000, scores: [4, 6], setScores: [1, 1])
        ]
        record.detailedActions = actions
        record.setResults = ScoreboardRecordActionAdapter.setResults(from: actions)

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.recap.map(\.number), [1, 2])
        XCTAssertTrue(presentation.recap[0].actions.contains { $0.operationCode == "set_one_point" })
        XCTAssertTrue(presentation.recap[1].actions.contains { $0.operationCode == "set_two_point" })
        XCTAssertTrue(presentation.recap[1].actions.contains { $0.type == .matchFinished })
    }

    func testBasketballRecapUsesPeriodsAndSharesTimelineGroups() {
        var record = makeRecord(gameType: .basketball)
        let actions: [DetailedScoreAction] = [
            .init(type: .scoreChanged, epochMilliseconds: 1_000, scores: [2, 0], periodNumber: 1, scoreChange: 2),
            .init(type: .periodFinished, epochMilliseconds: 2_000, scores: [20, 18], periodNumber: 1),
            .init(type: .scoreChanged, epochMilliseconds: 3_000, scores: [22, 18], periodNumber: 2, scoreChange: 2),
            .init(type: .periodFinished, epochMilliseconds: 4_000, scores: [40, 35], periodNumber: 2),
            .init(type: .matchFinished, epochMilliseconds: 5_000, scores: [40, 35])
        ]
        record.detailedActions = actions
        record.setResults = ScoreboardRecordActionAdapter.setResults(from: actions)

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.recap.map(\.number), [1, 2])
        XCTAssertEqual(presentation.timelineSections, presentation.recap)
        XCTAssertEqual(presentation.recap.map { $0.result?.number }, [1, 2])
    }

    func testStableProjectOperationsInferEightBallFramesAndShengjiRounds() {
        var eightBall = makeRecord(gameType: .eightBall)
        eightBall.detailedActions = [
            .init(type: .scoreChanged, scores: [0, 0], operationCode: "eight_ball_pot_3"),
            .init(type: .scoreChanged, scores: [1, 0], operationCode: "eight_ball_rack"),
            .init(type: .scoreChanged, scores: [1, 0], operationCode: "eight_ball_pot_6"),
            .init(type: .scoreChanged, scores: [1, 1], operationCode: "eight_ball_rack")
        ]
        let eightBallPresentation = ScoreboardRecordPresentation(record: eightBall)
        XCTAssertEqual(eightBallPresentation.recap.map(\.number), [1, 2])
        XCTAssertEqual(eightBallPresentation.recapGroupingQuality, .inferred)

        var shengji = makeRecord(gameType: .shengji)
        shengji.detailedActions = [
            .init(type: .scoreChanged, scores: [3, 2], operationCode: "resolveRound(winner:left,delta:1)"),
            .init(type: .scoreChanged, scores: [3, 4], operationCode: "resolveRound(winner:right,delta:2)")
        ]
        let shengjiPresentation = ScoreboardRecordPresentation(record: shengji)
        XCTAssertEqual(shengjiPresentation.recap.map(\.number), [1, 2])
        XCTAssertEqual(shengjiPresentation.recapGroupingQuality, .inferred)
    }

    func testEventsRankingEmptyAndUnreliableLegacyRecordsDoNotInventFirstSegment() {
        for gameType in [jifen.GameType.billiards, .football, .threeBasketball, .nineBall, .simpleScore] {
            var record = makeRecord(gameType: gameType)
            record.detailedActions = [.init(type: .scoreChanged, scores: [1, 0], scoreChange: 1)]
            let presentation = ScoreboardRecordPresentation(record: record)
            XCTAssertEqual(presentation.recap.count, 1, gameType.rawValue)
            XCTAssertNil(presentation.recap.first?.number, gameType.rawValue)
            XCTAssertEqual(presentation.recapGroupingQuality, .unsegmented, gameType.rawValue)
        }
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .billiards).recapKind, .events)

        var ranking = makeRecord(gameType: .multiScoreboard)
        ranking.detailedActions = [.init(type: .scoreChanged, scores: [1, 2, 3])]
        let rankingPresentation = ScoreboardRecordPresentation(record: ranking)
        XCTAssertNil(rankingPresentation.recap.first?.number)
        XCTAssertEqual(rankingPresentation.recapGroupingQuality, .unsegmented)

        let emptyPresentation = ScoreboardRecordPresentation(record: makeRecord())
        XCTAssertTrue(emptyPresentation.recap.isEmpty)
        XCTAssertTrue(emptyPresentation.timelineSections.isEmpty)

        let legacyPresentation = ScoreboardRecordPresentation(
            record: makeRecord(actions: ["left +1"])
        )
        XCTAssertEqual(legacyPresentation.recap.count, 1)
        XCTAssertNil(legacyPresentation.recap.first?.number)
        XCTAssertEqual(legacyPresentation.recapGroupingQuality, .overallFallback)
    }

    func testStandaloneWatchIngestKeepsStructuredActions() throws {
        let id = "watch-ingest-\(UUID().uuidString)"
        let actions = [
            DetailedScoreAction(type: .matchStarted, epochMilliseconds: 1_000, scores: [0, 0]),
            DetailedScoreAction(type: .scoreChanged, epochMilliseconds: 2_000, team: .team1, scores: [1, 0], scoreChange: 1, operationCode: "point"),
            DetailedScoreAction(type: .setFinished, epochMilliseconds: 3_000, scores: [21, 19], setScores: [1, 0], setNumber: 1, winner: .team1)
        ]
        let payload = WatchRecordTransferPayload(
            id: id,
            gameType: "badminton",
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 4_000,
            durationSeconds: 3,
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 21,
            team2FinalScore: 19,
            team1SetScore: 1,
            team2SetScore: 0,
            winner: "甲",
            actions: ["point"],
            detailedActions: actions,
            totalScoreChanges: 1,
            projectConfiguration: ["isDoubles": "true"]
        )

        let record = try WatchStandaloneRecordIngestor.makeRecord(payload)
        XCTAssertEqual(record.detailedActions, actions)
        XCTAssertEqual(record.setResults?.first?.scores, [21, 19])
        XCTAssertEqual(record.totalScoreChanges, 1)
        XCTAssertEqual(record.resolvedScoreCoreGameType, .badmintonDoubles)
        XCTAssertEqual(ScoreboardRecordConfiguration.setup(from: record).isSingles, false)
    }

    func testLinkedWatchIngestKeepsSameTimeline() throws {
        let id = "w_link_ingest_\(UUID().uuidString)"
        let action = DetailedScoreAction(
            type: .scoreChanged,
            epochMilliseconds: 2_000,
            team: .team2,
            scores: [0, 1],
            scoreChange: 1,
            operationCode: "point"
        )
        var state = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .badminton())
        state.rightPoints = 1
        let payload = LinkMatchFinishedPayload(
            snapshot: .rally(state),
            recordId: id,
            winnerSide: .right,
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 3_000,
            durationSeconds: 2,
            totalScoreChanges: 1,
            detailedActions: [action]
        )

        let record = try LinkedMatchRecordIngestor.makeRecord(
            payload: payload,
            gameType: ScoreCore.GameType.badmintonDoubles
        )
        XCTAssertEqual(record.detailedActions, [action])
        XCTAssertEqual(record.totalScoreChanges, 1)
        XCTAssertEqual(record.resolvedScoreCoreGameType, .badmintonDoubles)
    }

    func testTiebreakOnlyTennisConfigurationAndLegacyOverviewOmitGames() {
        for coreType in [ScoreCore.GameType.tennis, .tennisDoubles] {
            let state = TennisMatchState(
                leftName: "甲",
                rightName: "乙",
                rules: TennisRuleSet(
                    maxSets: 1,
                    tieBreakPoints: 10,
                    setScoringMode: .tiebreakOnly
                ),
                doublesPlayerNames: coreType == .tennisDoubles
                    ? ["甲A", "乙A", "甲B", "乙B"]
                    : nil
            )
            let configuration = ScoreboardRecordConfiguration.tennis(
                gameType: coreType,
                state: state,
                voiceAnnouncement: false
            )
            let record = ScoreboardRecord(
                id: coreType.rawValue,
                gameType: .tennis,
                startTime: Date(timeIntervalSince1970: 1),
                team1Name: "甲",
                team2Name: "乙",
                team1FinalScore: 10,
                team2FinalScore: 8,
                team1SetScore: 0,
                team2SetScore: 0,
                totalScoreChanges: 18,
                projectConfiguration: configuration
            )

            XCTAssertNil(configuration["gamesPerSet"], coreType.rawValue)
            XCTAssertTrue(record.isTennisTiebreakOnly, coreType.rawValue)
            XCTAssertFalse(record.shouldDisplaySecondaryScore, coreType.rawValue)
        }
    }

    func testLegacyTiebreakOnlySnapshotRestoresFormatWithoutGamesMetadata() throws {
        let state = TennisMatchState(
            leftName: "甲",
            rightName: "乙",
            rules: TennisRuleSet(
                maxSets: 1,
                tieBreakPoints: 10,
                setScoringMode: .tiebreakOnly
            )
        )
        let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: .tennisDoubles,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: .tennisDoubles).reducerType,
            state: state
        )
        var record = ScoreboardRecord(
            id: "legacy-tiebreak-snapshot",
            gameType: .tennis,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 10,
            team2FinalScore: 8,
            team1SetScore: 0,
            team2SetScore: 0,
            totalScoreChanges: 18
        )
        record.stateSnapshot = try JSONEncoder().encode(session)

        XCTAssertTrue(record.isTennisTiebreakOnly)
        XCTAssertEqual(record.tennisTieBreakPoints, 10)
        XCTAssertFalse(record.shouldDisplaySecondaryScore)
        XCTAssertEqual(record.resolvedScoreCoreGameType, .tennisDoubles)
        let setup = ScoreboardRecordConfiguration.setup(from: record)
        XCTAssertEqual(setup.setScoringMode, "tiebreak_only")
        XCTAssertEqual(setup.tieBreakPoints, 10)
        XCTAssertNil(setup.gamesPerSet)
    }

    func testLinkedTiebreakOnlyTennisRecordUsesPointsAndStripsGamesData() throws {
        var state = TennisMatchState(
            leftName: "甲",
            rightName: "乙",
            rules: TennisRuleSet(
                maxSets: 1,
                tieBreakPoints: 10,
                setScoringMode: .tiebreakOnly
            )
        )
        state.leftPoints = 10
        state.rightPoints = 8
        state.finished = true
        let action = DetailedScoreAction(
            type: .matchFinished,
            scores: [10, 8],
            setScores: [0, 0],
            winner: .team1
        )
        let payload = LinkMatchFinishedPayload(
            snapshot: .tennis(state),
            recordId: "linked-tennis-tiebreak",
            winnerSide: .left,
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 3_000,
            durationSeconds: 2,
            totalScoreChanges: 18,
            detailedActions: [action]
        )

        let record = try LinkedMatchRecordIngestor.makeRecord(
            payload: payload,
            gameType: .tennis
        )

        XCTAssertEqual(record.team1FinalScore, 10)
        XCTAssertEqual(record.team2FinalScore, 8)
        XCTAssertNil(record.team1SetScore)
        XCTAssertNil(record.team2SetScore)
        XCTAssertEqual(record.detailedActions?.first?.setScores, [])
        XCTAssertNil(record.projectConfiguration?["gamesPerSet"])
    }

    func testStandaloneWatchTiebreakOnlyTennisRecordStripsGamesData() throws {
        let action = DetailedScoreAction(
            type: .matchFinished,
            scores: [7, 5],
            setScores: [0, 0],
            winner: .team1
        )
        let payload = WatchRecordTransferPayload(
            id: "watch-tennis-tiebreak",
            gameType: "tennis_doubles",
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 3_000,
            durationSeconds: 2,
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 7,
            team2FinalScore: 5,
            team1SetScore: 0,
            team2SetScore: 0,
            winner: "甲",
            actions: [],
            detailedActions: [action],
            totalScoreChanges: 12,
            projectConfiguration: [
                "setScoringMode": "tiebreak_only",
                "tieBreakPoints": "7"
            ]
        )

        let record = try WatchStandaloneRecordIngestor.makeRecord(payload)

        XCTAssertEqual(record.team1FinalScore, 7)
        XCTAssertEqual(record.team2FinalScore, 5)
        XCTAssertNil(record.team1SetScore)
        XCTAssertNil(record.team2SetScore)
        XCTAssertEqual(record.detailedActions?.first?.setScores, [])
        XCTAssertEqual(record.resolvedScoreCoreGameType, .tennisDoubles)
    }

    func testTiebreakOnlyTennisPresentationOmitsRedundantMatchFinishedAction() {
        for coreType in [ScoreCore.GameType.tennis, .tennisDoubles] {
            let scoreAction = DetailedScoreAction(
                type: .scoreChanged,
                scores: [7, 2],
                scoreChange: 1,
                operationCode: "point"
            )
            let finishedAction = DetailedScoreAction(
                type: .matchFinished,
                scores: [7, 2],
                winner: .team1,
                operationCode: "finish"
            )
            let record = ScoreboardRecord(
                id: "presentation-\(coreType.rawValue)",
                gameType: .tennis,
                startTime: Date(timeIntervalSince1970: 1),
                team1Name: "甲",
                team2Name: "乙",
                team1FinalScore: 7,
                team2FinalScore: 2,
                detailedActions: [scoreAction, finishedAction],
                totalScoreChanges: 7,
                projectConfiguration: [
                    "scoreCoreGameType": AnyCodable(coreType.rawValue),
                    "setScoringMode": AnyCodable("tiebreak_only"),
                    "tieBreakPoints": AnyCodable(7)
                ]
            )

            let presentation = ScoreboardRecordPresentation(record: record)

            XCTAssertEqual(presentation.actions.map(\.type), [.scoreChanged], coreType.rawValue)
            XCTAssertEqual(presentation.recap.first?.actions.map(\.type), [.scoreChanged], coreType.rawValue)
        }
    }

    func testAllTenSinglesAndDoublesModesRoundTripStableIdentityAndSetup() throws {
        let rallyModes: [(ScoreCore.GameType, RallyRuleSet)] = [
            (.pingpong, .pingPong(maxSets: 5, matchCompletionMode: .playAll)),
            (.pingpongDoubles, .pingPong(maxSets: 5, matchCompletionMode: .playAll)),
            (.badminton, .badminton(maxSets: 5, matchCompletionMode: .playAll)),
            (.badmintonDoubles, .badminton(maxSets: 5, matchCompletionMode: .playAll)),
            (.pickleball, .pickleball(maxSets: 5, matchCompletionMode: .playAll)),
            (.pickleballDoubles, .pickleball(maxSets: 5, matchCompletionMode: .playAll)),
            (.foosball, .foosball(maxSets: 5)),
            (.foosballDoubles, .foosball(maxSets: 5))
        ]
        let doublesParticipants: [SessionParticipant] = [
            .init(id: "left-top", name: "红A", role: "player"),
            .init(id: "left-bottom", name: "红B", role: "player"),
            .init(id: "right-top", name: "蓝A", role: "player"),
            .init(id: "right-bottom", name: "蓝B", role: "player")
        ]

        for (coreType, rules) in rallyModes {
            let appType = try XCTUnwrap(jifen.GameType(scoreCoreGameType: coreType))
            let store = RallySessionStore(
                leftName: "红队",
                rightName: "蓝队",
                gameType: coreType,
                rules: rules,
                participants: coreType.isDoublesScoreboard ? doublesParticipants : nil,
                openingServer: .right,
                voiceAnnouncementEnabled: true,
                showMatchTimeEnabled: true
            )
            let configuration = ScoreboardRecordConfiguration.rally(
                gameType: coreType,
                state: store.state,
                voiceAnnouncement: true,
                showMatchTime: true
            )
            let record = makeConfigurationRecord(gameType: appType, configuration: configuration)
            let setup = ScoreboardRecordConfiguration.setup(from: record)

            XCTAssertEqual(record.resolvedScoreCoreGameType, coreType, coreType.rawValue)
            XCTAssertEqual(setup.isSingles, !coreType.isDoublesScoreboard, coreType.rawValue)
            XCTAssertEqual(setup.maxSets, rules.maxSets, coreType.rawValue)
            XCTAssertEqual(setup.pointsPerSet, rules.pointsToWinSet, coreType.rawValue)
            XCTAssertEqual(setup.servingSide, MatchSide.right.rawValue, coreType.rawValue)
            XCTAssertEqual(setup.voiceAnnouncement, true, coreType.rawValue)
            XCTAssertEqual(setup.showMatchTime, true, coreType.rawValue)
            if coreType.isDoublesScoreboard {
                XCTAssertEqual(
                    [setup.team1Player1Name, setup.team2Player1Name, setup.team1Player2Name, setup.team2Player2Name],
                    ["红A", "蓝A", "红B", "蓝B"],
                    coreType.rawValue
                )
            }
        }

        for coreType in [ScoreCore.GameType.tennis, .tennisDoubles] {
            let doublesNames = coreType == .tennisDoubles ? ["红A", "蓝A", "红B", "蓝B"] : nil
            let rules = TennisRuleSet(
                maxSets: 5,
                tieBreakPoints: 10,
                gamesPerSet: 4,
                matchCompletionMode: .playAll,
                usesNoAdScoring: true,
                autoChangeSides: false
            )
            let state = TennisMatchState(
                leftName: "红队",
                rightName: "蓝队",
                rules: rules,
                openingServer: .right,
                doublesPlayerNames: doublesNames
            )
            let appType = try XCTUnwrap(jifen.GameType(scoreCoreGameType: coreType))
            let record = makeConfigurationRecord(
                gameType: appType,
                configuration: ScoreboardRecordConfiguration.tennis(
                    gameType: coreType,
                    state: state,
                    voiceAnnouncement: true
                )
            )
            let setup = ScoreboardRecordConfiguration.setup(from: record)

            XCTAssertEqual(record.resolvedScoreCoreGameType, coreType)
            XCTAssertEqual(setup.isSingles, coreType == .tennis)
            XCTAssertEqual(setup.maxSets, 5)
            XCTAssertEqual(setup.tieBreakPoints, 10)
            XCTAssertEqual(setup.gamesPerSet, 4)
            XCTAssertEqual(setup.matchCompletionMode, .playAll)
            XCTAssertEqual(setup.tennisDeuceMode, "no_ad")
            XCTAssertEqual(setup.autoChangeSides, false)
            XCTAssertEqual(setup.servingSide, MatchSide.right.rawValue)
            if coreType == .tennisDoubles {
                XCTAssertEqual(
                    [setup.team1Player1Name, setup.team2Player1Name, setup.team1Player2Name, setup.team2Player2Name],
                    ["红A", "蓝A", "红B", "蓝B"]
                )
            }
        }
    }

    func testTableTennisAdministrativeRecordTitlesMatchAndroid31() {
        XCTAssertEqual(
            ScoreboardRecordActionTitlePolicy.tableTennisAdministrativeTitle(
                operationCode: "yellow_card",
                teamName: "甲"
            ),
            String.localizedStringWithFormat(NSLocalizedString("record_tt_yellow", comment: ""), "甲")
        )
        XCTAssertEqual(
            ScoreboardRecordActionTitlePolicy.tableTennisAdministrativeTitle(
                operationCode: "tt_red",
                teamName: "乙"
            ),
            String.localizedStringWithFormat(NSLocalizedString("record_tt_red", comment: ""), "乙")
        )
        XCTAssertEqual(
            ScoreboardRecordActionTitlePolicy.tableTennisAdministrativeTitle(
                operationCode: "timeout",
                teamName: "甲"
            ),
            String.localizedStringWithFormat(NSLocalizedString("record_tt_timeout", comment: ""), "甲")
        )
        XCTAssertEqual(
            ScoreboardRecordActionTitlePolicy.tableTennisAdministrativeTitle(
                operationCode: "medical_timeout",
                teamName: "乙"
            ),
            String.localizedStringWithFormat(NSLocalizedString("record_tt_medical", comment: ""), "乙")
        )
        XCTAssertNil(
            ScoreboardRecordActionTitlePolicy.tableTennisAdministrativeTitle(
                operationCode: "point",
                teamName: "甲"
            )
        )
    }

    func testOldRecordModeInferenceSupportsRawSessionAndResumeBundleButLeavesUnknownUnclassified() throws {
        let state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .badminton())
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: .badmintonDoubles,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: .badmintonDoubles).reducerType,
            state: state
        )
        var rawRecord = makeConfigurationRecord(gameType: .badminton, configuration: nil)
        rawRecord.stateSnapshot = try JSONEncoder().encode(session)
        XCTAssertEqual(rawRecord.resolvedScoreCoreGameType, .badmintonDoubles)

        let bundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>(
            replaySeed: session,
            currentSession: session,
            undoFrames: [],
            timeline: []
        )
        var bundleRecord = makeConfigurationRecord(gameType: .badminton, configuration: nil)
        bundleRecord.stateSnapshot = try JSONEncoder().encode(bundle)
        XCTAssertEqual(bundleRecord.resolvedScoreCoreGameType, .badmintonDoubles)

        let unknown = makeConfigurationRecord(gameType: .badminton, configuration: nil)
        XCTAssertNil(unknown.resolvedScoreCoreGameType)
        XCTAssertEqual(unknown.competitionDisplayName, jifen.GameType.badminton.displayName)
    }

    func testGuandanUnoAndCustomAdjustmentConfigurationRestoresFromRecord() {
        let record = ScoreboardRecord(
            id: "configuration-special",
            gameType: .guandan,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 2,
            team2FinalScore: 1,
            totalScoreChanges: 1,
            extraData: [
                "guandanTripleAEnabled": AnyCodable(true),
                "guandanPassACondition": AnyCodable("double_up"),
                "guandanTripleAFallbackRank": AnyCodable("K"),
                "multiScoreCustomAdjustEnabled": AnyCodable(true),
                "unoTargetScore": AnyCodable(700)
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.guandan.rawValue)
            ]
        )
        let setup = ScoreboardRecordConfiguration.setup(from: record)
        XCTAssertEqual(setup.guandanTripleA, true)
        XCTAssertEqual(setup.guandanPassACondition, "double_up")
        XCTAssertEqual(setup.guandanTripleAFallbackRank, "K")
        XCTAssertEqual(setup.multiScoreCustomAdjustEnabled, true)
        XCTAssertEqual(setup.targetScore, 700)
    }

    /// 向后兼容：旧版 iOS 记录用 `guandanTripleA` 键，升级后读取端必须仍能识别。
    func testGuandanLegacyTripleAKeyStillRestores() {
        let record = ScoreboardRecord(
            id: "legacy-guandan",
            gameType: .guandan,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 2,
            team2FinalScore: 1,
            totalScoreChanges: 1,
            extraData: [
                "guandanTripleA": AnyCodable(true),
                "guandanPassACondition": AnyCodable("double_up"),
                "guandanTripleAFallbackRank": AnyCodable("K")
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.guandan.rawValue)
            ]
        )
        let setup = ScoreboardRecordConfiguration.setup(from: record)
        XCTAssertEqual(setup.guandanTripleA, true)
        XCTAssertEqual(setup.guandanPassACondition, "double_up")
        XCTAssertEqual(setup.guandanTripleAFallbackRank, "K")
    }

    /// 向后兼容：旧版 iOS 记录用 `voiceAnnouncement` 键（影响所有抢分运动 + 网球），
    /// 升级后读取端必须仍能识别（`voiceAnnouncementEnabled` 优先，缺失时回退旧键）。
    func testLegacyVoiceAnnouncementKeyStillRestores() {
        let record = ScoreboardRecord(
            id: "legacy-voice",
            gameType: .tennis,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "红队",
            team2Name: "蓝队",
            team1FinalScore: 0,
            team2FinalScore: 0,
            totalScoreChanges: 0,
            extraData: [
                "voiceAnnouncement": AnyCodable(true)
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.tennis.rawValue)
            ]
        )
        let setup = ScoreboardRecordConfiguration.setup(from: record)
        XCTAssertEqual(setup.voiceAnnouncement, true)
    }

    /// 跨端回退：安卓 guandan 记录无 stateSnapshot blob，仅 extraData 摊平 guandanFinalWinner，
    /// resolvedWinnerIdentity 必须据此恢复胜者（否则回 nil，即 BUG-1 的跨端后果）。
    func testGuandanWinnerResolvesFromFlattenedExtraDataWhenNoStateSnapshot() {
        let record = ScoreboardRecord(
            id: "android-guandan",
            gameType: .guandan,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 2,
            team2FinalScore: 1,
            totalScoreChanges: 1,
            extraData: [
                "guandanFinalWinner": AnyCodable("red")
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.guandan.rawValue)
            ]
        )
        XCTAssertEqual(record.resolvedWinnerIdentity, .team(.team0))

        // 蓝方胜者映射为 team1
        var blueRecord = record
        blueRecord.extraData = [
            "guandanFinalWinner": AnyCodable("blue")
        ]
        XCTAssertEqual(blueRecord.resolvedWinnerIdentity, .team(.team1))
    }

    func testWinnerResolutionUsesPositionsForDuplicateNamesAndSupportsMultipleWinners() {
        XCTAssertEqual(
            GameOverWinnerResolver.indices(
                explicit: nil,
                multiScores: [],
                leftScore: "11",
                rightScore: "7",
                participantNames: ["同名", "同名"],
                winnerName: "同名"
            ),
            [0]
        )
        XCTAssertEqual(
            GameOverWinnerResolver.indices(
                explicit: nil,
                multiScores: [12, 12, 5],
                leftScore: nil,
                rightScore: nil,
                participantNames: [],
                winnerName: ""
            ),
            [0, 1]
        )
        XCTAssertEqual(
            GameOverWinnerResolver.indices(
                explicit: nil,
                multiScores: [8, 8, 8],
                leftScore: nil,
                rightScore: nil,
                participantNames: [],
                winnerName: ""
            ),
            []
        )
    }

    func testCompletedMatchChineseResourcesUsePlayAnotherMatchWording() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let phone = try String(contentsOf: repositoryRoot.appendingPathComponent("jifen/Resources/zh-Hans.lproj/Localizable.strings"), encoding: .utf8)
        let watch = try String(contentsOf: repositoryRoot.appendingPathComponent("jifenWatch Watch App/Resources/zh-Hans.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(phone.contains(#""play_again" = "再来一场";"#))
        XCTAssertFalse(phone.contains(#""play_again" = "再来一局";"#))
        XCTAssertTrue(watch.contains(#""watch_play_again" = "再来一场";"#))
        XCTAssertFalse(watch.contains(#""watch_play_again" = "再来一局";"#))
    }

    func testAnyCodableEncodesNestedPlayerPayloadWithNegativeScores() throws {
        let payload = AnyCodable([
            ["name": "甲", "score": -3, "finalScore": -3] as [String: Any],
            ["name": "乙", "score": 12, "finalScore": 12] as [String: Any],
        ])

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let players = try XCTUnwrap(decoded.value as? [Any])
        let first = try XCTUnwrap(players.first as? [String: Any])

        XCTAssertEqual(first["name"] as? String, "甲")
        XCTAssertEqual(first["score"] as? Int, -3)
    }

    func testLifecyclePersistenceNormalizesDraftAndFinishedMetadata() {
        let draftSource = makeRecord()
        let draft = ScoreboardLifecyclePersistence.normalizedRecord(
            draftSource,
            finished: false
        )
        XCTAssertEqual(draft.status.rawValue, ScoreboardRecordStatus.draft.rawValue)
        XCTAssertNil(draft.endTime)
        XCTAssertNil(draft.winner)

        var unfinishedSource = makeRecord()
        unfinishedSource.endTime = nil
        unfinishedSource.status = .draft
        let fallbackEnd = Date(timeIntervalSince1970: 1_700_000_120)
        let finished = ScoreboardLifecyclePersistence.normalizedRecord(
            unfinishedSource,
            finished: true,
            finishedAt: fallbackEnd
        )
        XCTAssertEqual(finished.status.rawValue, ScoreboardRecordStatus.finished.rawValue)
        XCTAssertEqual(finished.endTime, fallbackEnd)
        XCTAssertEqual(finished.winner, "left")
    }

    func testClearAllStoredDataRemovesIndexedOrphanAndCorruptArtifacts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScoreboardRecordFileStoreClearTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: root.appendingPathComponent("orphan.record.json"),
            options: .atomic
        )
        try Data("not-json".utf8).write(
            to: root.appendingPathComponent("index.json"),
            options: .atomic
        )
        try Data("legacy".utf8).write(
            to: root.appendingPathComponent("scoreboard-records-v3-backup.json"),
            options: .atomic
        )

        let store = ScoreboardRecordFileStore(rootURL: root)
        try store.clearAllStoredData()

        let remaining = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent)
        XCTAssertEqual(remaining, ["migration-v4-complete"])
        XCTAssertTrue(store.loadRecords().isEmpty)
    }

    private func makeRecord(
        id: String = "record",
        schemaVersion: Int = 4,
        actions: [String] = [],
        gameType: jifen.GameType = .pingpong
    ) -> ScoreboardRecord {
        var record = ScoreboardRecord(
            id: id,
            gameType: gameType,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_060),
            duration: 60,
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: 11,
            team2FinalScore: 7,
            winner: "left",
            actions: actions,
            totalScoreChanges: actions.count
        )
        record.schemaVersion = schemaVersion
        return record
    }

    private func makeConfigurationRecord(
        gameType: jifen.GameType,
        configuration: [String: AnyCodable]?
    ) -> ScoreboardRecord {
        ScoreboardRecord(
            id: UUID().uuidString,
            gameType: gameType,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "红队",
            team2Name: "蓝队",
            team1FinalScore: 0,
            team2FinalScore: 0,
            totalScoreChanges: 0,
            projectConfiguration: configuration
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func actionBody(_ raw: String) -> String {
        raw.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? raw
    }
}
