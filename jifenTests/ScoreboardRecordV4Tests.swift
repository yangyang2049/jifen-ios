import LinkCore
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore
import XCTest
@testable import jifen

@MainActor
final class ScoreboardRecordV4Tests: XCTestCase {
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

    func testAll23ProjectPoliciesMatchDetailMatrix() {
        let trend: Set<jifen.GameType> = [
            .pingpong, .badminton, .pickleball, .volleyball, .beachVolleyball,
            .airVolleyball, .archery, .billiards, .nineBall, .snooker, .foosball,
            .simpleScore
        ]
        let noTrend: Set<jifen.GameType> = [
            .tennis, .football, .basketball, .threeBasketball, .boxing, .eightBall,
            .doudizhu, .guandan, .shengji, .uno, .multiScoreboard
        ]
        XCTAssertEqual(trend.count + noTrend.count, 23)
        for game in trend {
            let policy = ScoreboardRecordProjectPolicy.policy(for: game)
            XCTAssertTrue(policy.trendAllowed, "\(game)")
            XCTAssertEqual(policy.detailLayout, .standard, "\(game)")
            var record = makeRecord(id: "trend-\(game.rawValue)", gameType: game)
            record.detailedActions = [
                .init(type: .scoreChanged, scores: [1, 0], scoreChange: 1)
            ]
            XCTAssertTrue(ScoreboardRecordPresentation(record: record).canShowTrend, "\(game)")
        }
        for game in noTrend where game != .multiScoreboard {
            let policy = ScoreboardRecordProjectPolicy.policy(for: game)
            XCTAssertFalse(policy.trendAllowed, "\(game)")
            XCTAssertEqual(policy.detailLayout, .standard, "\(game)")
            var record = makeRecord(id: "no-trend-\(game.rawValue)", gameType: game)
            record.detailedActions = [
                .init(type: .scoreChanged, scores: [1, 0], scoreChange: 1)
            ]
            XCTAssertFalse(ScoreboardRecordPresentation(record: record).canShowTrend, "\(game)")
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
                voiceAnnouncementEnabled: true
            )
            let configuration = ScoreboardRecordConfiguration.rally(
                gameType: coreType,
                state: store.state,
                voiceAnnouncement: true
            )
            let record = makeConfigurationRecord(gameType: appType, configuration: configuration)
            let setup = ScoreboardRecordConfiguration.setup(from: record)

            XCTAssertEqual(record.resolvedScoreCoreGameType, coreType, coreType.rawValue)
            XCTAssertEqual(setup.isSingles, !coreType.isDoublesScoreboard, coreType.rawValue)
            XCTAssertEqual(setup.maxSets, rules.maxSets, coreType.rawValue)
            XCTAssertEqual(setup.pointsPerSet, rules.pointsToWinSet, coreType.rawValue)
            XCTAssertEqual(setup.servingSide, MatchSide.right.rawValue, coreType.rawValue)
            XCTAssertEqual(setup.voiceAnnouncement, true, coreType.rawValue)
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
                "guandanTripleA": AnyCodable(true),
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
}
