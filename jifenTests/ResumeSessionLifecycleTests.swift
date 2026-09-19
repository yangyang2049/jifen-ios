import Foundation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore
import XCTest
@testable import jifen

@MainActor
final class ResumeSessionLifecycleTests: XCTestCase {
    private enum StubError: Error {
        case write
        case remove
    }

    func testEmptyManualResumeIsDeletedWithoutCreatingHistory() async throws {
        let envelope = try manualEnvelope(score: 0, totalScoreChanges: 0)
        var writes: [ScoreboardRecord] = []
        var removals: [UUID] = []
        let coordinator = coordinator(
            envelope: envelope,
            recordLookup: { _ in nil },
            recordWriter: { writes.append($0) },
            resumeRemover: { removals.append($0) }
        )

        let result = try await coordinator.abandon(sessionID: envelope.sessionId)

        XCTAssertEqual(result, .discardedWithoutProgress)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(removals, [envelope.sessionId])
    }

    func testMeaningfulManualResumeWritesAbandonedRecordBeforeRemoval() async throws {
        let envelope = try manualEnvelope(score: 3, totalScoreChanges: 1)
        var order: [String] = []
        var written: ScoreboardRecord?
        let coordinator = coordinator(
            envelope: envelope,
            recordLookup: { _ in nil },
            recordWriter: {
                order.append("write")
                written = $0
            },
            resumeRemover: { _ in order.append("remove") }
        )

        let result = try await coordinator.abandon(sessionID: envelope.sessionId)

        XCTAssertEqual(order, ["write", "remove"])
        XCTAssertEqual(written?.status, .abandoned)
        XCTAssertEqual(written?.team1FinalScore, 3)
        XCTAssertEqual(result, .archived(recordID: written!.id, recordWritten: true))
    }

    func testRecordWriteFailurePreservesResumeForRetry() async throws {
        let envelope = try manualEnvelope(score: 1, totalScoreChanges: 1)
        var removed = false
        let coordinator = coordinator(
            envelope: envelope,
            recordLookup: { _ in nil },
            recordWriter: { _ in throw StubError.write },
            resumeRemover: { _ in removed = true }
        )

        do {
            _ = try await coordinator.abandon(sessionID: envelope.sessionId)
            XCTFail("Expected archive write failure")
        } catch StubError.write {
            XCTAssertFalse(removed)
        }
    }

    func testCleanupFailureRetriesWithoutRewritingAbandonedRecord() async throws {
        let envelope = try manualEnvelope(score: 2, totalScoreChanges: 1)
        var stored: ScoreboardRecord?
        var writeCount = 0
        var removeCount = 0
        let first = coordinator(
            envelope: envelope,
            recordLookup: { _ in stored },
            recordWriter: {
                writeCount += 1
                stored = $0
            },
            resumeRemover: { _ in
                removeCount += 1
                throw StubError.remove
            }
        )

        do {
            _ = try await first.abandon(sessionID: envelope.sessionId)
            XCTFail("Expected cleanup failure")
        } catch StubError.remove {
            XCTAssertEqual(stored?.status, .abandoned)
            XCTAssertEqual(writeCount, 1)
        }

        let retry = coordinator(
            envelope: envelope,
            recordLookup: { _ in stored },
            recordWriter: { _ in writeCount += 1 },
            resumeRemover: { _ in removeCount += 1 }
        )
        let result = try await retry.abandon(sessionID: envelope.sessionId)

        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(removeCount, 2)
        XCTAssertEqual(result, .archived(recordID: stored!.id, recordWritten: false))
    }

    func testArchiveIfExpiredUsesStartTimeAndLeavesBoundarySessionResumable() async throws {
        let envelope = try manualEnvelope(
            score: 1,
            totalScoreChanges: 1,
            startedAtMilliseconds: 1_000
        )
        var removed = false
        let coordinator = coordinator(
            envelope: envelope,
            recordLookup: { _ in nil },
            recordWriter: { _ in },
            resumeRemover: { _ in removed = true }
        )
        let boundary = Date(
            timeIntervalSince1970: TimeInterval(1_000 + 48 * 60 * 60 * 1_000) / 1_000
        )

        let retained = try await coordinator.archiveIfExpired(
            sessionID: envelope.sessionId,
            now: boundary
        )

        XCTAssertNil(retained)
        XCTAssertFalse(removed)
    }

    func testManualPayloadPreservesEveryExactCatalogGameType() throws {
        XCTAssertEqual(ScoreCore.GameType.allCases.count, 34)
        for exactType in ScoreCore.GameType.allCases {
            guard let appType = GameType(scoreCoreGameType: exactType) else {
                return XCTFail("Missing app mapping for \(exactType.rawValue)")
            }
            let id = UUID()
            let record = ScoreboardRecord(
                id: id.uuidString,
                gameType: appType,
                startTime: Date(timeIntervalSince1970: 100),
                team1Name: "A",
                team2Name: "B",
                team1FinalScore: 1,
                team2FinalScore: 0,
                totalScoreChanges: 1,
                projectConfiguration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(exactType.rawValue)
                ],
                status: .draft
            )
            let state = ManualScoreboardResumeState(record: record, scoreCoreGameType: exactType)
            let envelope = ResumeSessionEnvelope(
                sessionId: id,
                gameType: exactType,
                startedAtEpochMilliseconds: 100_000,
                updatedAtEpochMilliseconds: 101_000,
                participants: participants,
                scoreSummary: "1 : 0",
                payloadKind: .manualState,
                payload: try JSONEncoder().encode(state)
            )

            let archived = try XCTUnwrap(AbandonedResumeRecordBuilder.build(
                envelope: envelope,
                abandonedAt: Date(timeIntervalSince1970: 200)
            ))
            XCTAssertEqual(archived.status, .abandoned, exactType.rawValue)
            XCTAssertEqual(archived.resolvedScoreCoreGameType, exactType, exactType.rawValue)
        }
    }

    func testBundleAndBareSessionBuildersSupportPreciseRallyTennisAndTimerProgress() throws {
        var rallySeedState = RallyMatchEngine.initial(
            leftName: "A",
            rightName: "B",
            rules: .squash()
        )
        let rallySeed = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: .squash,
            ruleFamily: .s1,
            reducerType: "rally/v1",
            state: rallySeedState,
            participants: participants
        )
        rallySeedState.leftPoints = 1
        let rallyCurrent = ScoreSession<RallyMatchState, RallyMatchEvent>(
            sessionId: rallySeed.sessionId,
            gameType: .squash,
            ruleFamily: .s1,
            reducerType: "rally/v1",
            version: 1,
            state: rallySeedState,
            events: [.pointScored(side: .left, leftPoints: 1, rightPoints: 0)],
            participants: participants
        )
        let rallyBundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>(
            replaySeed: rallySeed,
            currentSession: rallyCurrent,
            undoFrames: [],
            timeline: []
        )
        let rallyEnvelope = envelope(
            sessionID: rallySeed.sessionId,
            gameType: .squash,
            payloadKind: .scoreSessionBundle,
            payload: try JSONEncoder().encode(rallyBundle)
        )
        let rallyRecord = try XCTUnwrap(AbandonedResumeRecordBuilder.build(
            envelope: rallyEnvelope,
            abandonedAt: Date(timeIntervalSince1970: 200)
        ))
        XCTAssertEqual(rallyRecord.resolvedScoreCoreGameType, .squash)

        var tennisState = TennisMatchState(leftName: "A", rightName: "B")
        tennisState.leftPoints = 1
        let tennisSession = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: .padel,
            ruleFamily: .s1,
            reducerType: "tennis/v1",
            version: 1,
            state: tennisState,
            events: [.pointScored(side: .left, left: 1, right: 0)],
            participants: participants
        )
        let tennisRecord = try XCTUnwrap(AbandonedResumeRecordBuilder.build(
            envelope: envelope(
                sessionID: tennisSession.sessionId,
                gameType: .padel,
                payloadKind: .scoreSession,
                payload: try JSONEncoder().encode(tennisSession)
            ),
            abandonedAt: Date(timeIntervalSince1970: 200)
        ))
        XCTAssertEqual(tennisRecord.resolvedScoreCoreGameType, .padel)

        let basketballBefore = BasketballMatchState(
            leftName: "A",
            rightName: "B",
            gameMode: .threeXThree
        )
        var basketballAfter = basketballBefore
        basketballAfter.gameTimeSeconds -= 1
        let basketballSession = ScoreSession<BasketballMatchState, BasketballMatchEvent>(
            gameType: .threeBasketball,
            ruleFamily: .s2,
            reducerType: "basketball/v1",
            version: 1,
            state: basketballAfter,
            events: [.stateChanged(
                at: 101_000,
                intent: .tickClock,
                before: basketballBefore,
                after: basketballAfter
            )],
            participants: participants
        )
        let timerRecord = try XCTUnwrap(AbandonedResumeRecordBuilder.build(
            envelope: envelope(
                sessionID: basketballSession.sessionId,
                gameType: .threeBasketball,
                payloadKind: .scoreSession,
                payload: try JSONEncoder().encode(basketballSession)
            ),
            abandonedAt: Date(timeIntervalSince1970: 200)
        ))
        XCTAssertEqual(timerRecord.status, .abandoned)
        XCTAssertEqual(timerRecord.team1FinalScore, 0)
        XCTAssertEqual(timerRecord.totalScoreChanges, 1)
        XCTAssertEqual(timerRecord.detailedActions?.last?.operationCode, "timer_progress")
    }

    func testAbandonedBundlePreservesAuxiliaryActionAndDetailedTimelines() throws {
        let initial = LineScoreState(leftName: "A", rightName: "B")
        var scored = initial
        scored.leftScore = 2
        let seed = ScoreSession<LineScoreState, LineScoreEvent>(
            gameType: .simpleScore,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: .simpleScore).reducerType,
            state: initial,
            participants: participants
        )
        let current = ScoreSession<LineScoreState, LineScoreEvent>(
            sessionId: seed.sessionId,
            gameType: .simpleScore,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: .simpleScore).reducerType,
            state: scored,
            events: [.scoreChanged(side: .left, delta: 2, left: 2, right: 0)],
            participants: participants
        )
        let detailed = DetailedScoreAction(
            type: .scoreChanged,
            epochMilliseconds: 100_500,
            team: .team1,
            scores: [2, 0],
            scoreChange: 2,
            operationCode: "preserved_aux_score"
        )
        let context = ScoreSessionRecordContext(
            actionLog: ["100500|snapshot|score_adjust|2,0"],
            detailedActions: [detailed],
            actionCount: 1
        )
        let bundle = ScoreSessionResumeBundle<LineScoreState, LineScoreEvent, LineScoreIntent>(
            replaySeed: seed,
            currentSession: current,
            undoFrames: [],
            timeline: [],
            auxiliaryPayload: context.encoded
        )
        let archived = try XCTUnwrap(AbandonedResumeRecordBuilder.build(
            envelope: envelope(
                sessionID: seed.sessionId,
                gameType: .simpleScore,
                payloadKind: .scoreSessionBundle,
                payload: try JSONEncoder().encode(bundle)
            ),
            abandonedAt: Date(timeIntervalSince1970: 200)
        ))

        XCTAssertEqual(archived.actions, context.actionLog)
        XCTAssertEqual(archived.totalScoreChanges, 1)
        XCTAssertEqual(archived.detailedActions?.first, detailed)
        XCTAssertEqual(archived.detailedActions?.last?.operationCode, "abandoned_snapshot")
    }

    func testFileStoreReturnsAbandonedRecordsAsHistoryButStillRejectsDrafts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResumeSessionLifecycleTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScoreboardRecordFileStore(rootURL: root)
        var abandoned = record(score: 1)
        abandoned.status = .abandoned
        try store.save(abandoned)

        XCTAssertEqual(store.loadRecords().map(\.status), [.abandoned])

        var draft = record(score: 1)
        draft.status = .draft
        XCTAssertThrowsError(try store.save(draft))
    }

    func testHomeResumeScannerDoesNotPruneOlderEntriesBehindUnreadableNewerEntry() async {
        let damagedNewer = resumeSummary(updatedAt: 300)
        let validFallback = resumeSummary(updatedAt: 200)
        let oldest = resumeSummary(updatedAt: 100)
        var abandoned: [UUID] = []

        let scanner = HomeResumeSessionScanner<String>(
            reconcileCommittedRecord: { _ in false },
            archiveIfExpired: { _ in nil },
            abandon: { sessionID in
                abandoned.append(sessionID)
                return .discardedWithoutProgress
            },
            loadCandidate: { entry in
                entry.sessionId == damagedNewer.sessionId ? nil : entry.sessionId.uuidString
            },
            onFailure: { _, _ in }
        )

        let outcome = await scanner.scan([damagedNewer, validFallback, oldest])

        XCTAssertEqual(outcome.candidate, validFallback.sessionId.uuidString)
        XCTAssertTrue(outcome.shouldReload)
        XCTAssertTrue(outcome.hasUnreadableEntry)
        XCTAssertTrue(
            abandoned.isEmpty,
            "A fallback may be shown, but older data must remain until the newer entry is resolved"
        )
    }

    func testHomeResumeScannerContinuesAfterSingleEntryLifecycleFailure() async {
        let missingEnvelope = resumeSummary(updatedAt: 300)
        let validFallback = resumeSummary(updatedAt: 200)
        var failures: [UUID] = []

        let scanner = HomeResumeSessionScanner<String>(
            reconcileCommittedRecord: { _ in false },
            archiveIfExpired: { sessionID in
                if sessionID == missingEnvelope.sessionId {
                    throw ResumeSessionLifecycleError.missingEnvelope(sessionID)
                }
                return nil
            },
            abandon: { _ in .discardedWithoutProgress },
            loadCandidate: { $0.sessionId.uuidString },
            onFailure: { _, entry in failures.append(entry.sessionId) }
        )

        let outcome = await scanner.scan([missingEnvelope, validFallback])

        XCTAssertEqual(outcome.candidate, validFallback.sessionId.uuidString)
        XCTAssertEqual(failures, [missingEnvelope.sessionId])
        XCTAssertTrue(outcome.shouldReload)
    }

    func testHomeResumeScannerValidatesCandidateBeforeContinuingPastOlderFailure() async {
        let newest = resumeSummary(updatedAt: 300)
        let brokenOlder = resumeSummary(updatedAt: 200)
        let oldest = resumeSummary(updatedAt: 100)
        var events: [String] = []

        let scanner = HomeResumeSessionScanner<String>(
            reconcileCommittedRecord: { _ in false },
            archiveIfExpired: { _ in nil },
            abandon: { sessionID in
                if sessionID == brokenOlder.sessionId {
                    events.append("abandon-broken")
                    throw ResumeSessionLifecycleError.missingEnvelope(sessionID)
                }
                events.append("abandon-oldest")
                return .discardedWithoutProgress
            },
            loadCandidate: { entry in
                events.append("validate-newest")
                return entry.sessionId.uuidString
            },
            onFailure: { _, _ in }
        )

        let outcome = await scanner.scan([newest, brokenOlder, oldest])

        XCTAssertEqual(outcome.candidate, newest.sessionId.uuidString)
        XCTAssertEqual(events, ["validate-newest", "abandon-broken", "abandon-oldest"])
        XCTAssertTrue(outcome.shouldReload)
    }

    private var participants: [SessionParticipant] {
        [
            .init(id: TeamID.team0.rawValue, name: "A", role: "team"),
            .init(id: TeamID.team1.rawValue, name: "B", role: "team")
        ]
    }

    private func resumeSummary(updatedAt: Int64) -> ResumeSessionSummary {
        let sessionID = UUID()
        return ResumeSessionSummary(
            sessionId: sessionID,
            gameType: .simpleScore,
            source: .phoneLocal,
            snapshotPath: "\(sessionID.uuidString).json",
            participants: participants,
            status: .live,
            updatedAtEpochMilliseconds: updatedAt
        )
    }

    private func record(score: Int) -> ScoreboardRecord {
        ScoreboardRecord(
            id: UUID().uuidString,
            gameType: .simpleScore,
            startTime: Date(timeIntervalSince1970: 100),
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: score,
            team2FinalScore: 0,
            totalScoreChanges: score == 0 ? 0 : 1,
            status: .draft
        )
    }

    private func manualEnvelope(
        score: Int,
        totalScoreChanges: Int,
        startedAtMilliseconds: Int64 = 100_000
    ) throws -> ResumeSessionEnvelope {
        let id = UUID()
        let source = ScoreboardRecord(
            id: id.uuidString,
            gameType: .simpleScore,
            startTime: Date(timeIntervalSince1970: TimeInterval(startedAtMilliseconds) / 1_000),
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: score,
            team2FinalScore: 0,
            totalScoreChanges: totalScoreChanges,
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(
                    ScoreCore.GameType.simpleScore.rawValue
                )
            ],
            status: .draft
        )
        let state = ManualScoreboardResumeState(record: source, scoreCoreGameType: .simpleScore)
        return ResumeSessionEnvelope(
            sessionId: id,
            gameType: .simpleScore,
            startedAtEpochMilliseconds: startedAtMilliseconds,
            updatedAtEpochMilliseconds: startedAtMilliseconds + 1_000,
            participants: participants,
            scoreSummary: "\(score) : 0",
            payloadKind: .manualState,
            payload: try JSONEncoder().encode(state)
        )
    }

    private func envelope(
        sessionID: UUID,
        gameType: ScoreCore.GameType,
        payloadKind: ResumePayloadKind,
        payload: Data
    ) -> ResumeSessionEnvelope {
        ResumeSessionEnvelope(
            sessionId: sessionID,
            gameType: gameType,
            startedAtEpochMilliseconds: 100_000,
            updatedAtEpochMilliseconds: 101_000,
            participants: participants,
            scoreSummary: "",
            payloadKind: payloadKind,
            payload: payload
        )
    }

    private func coordinator(
        envelope: ResumeSessionEnvelope,
        recordLookup: @escaping AbandonedResumeSessionCoordinator.RecordLookup,
        recordWriter: @escaping AbandonedResumeSessionCoordinator.RecordWriter,
        resumeRemover: @escaping AbandonedResumeSessionCoordinator.ResumeRemover
    ) -> AbandonedResumeSessionCoordinator {
        AbandonedResumeSessionCoordinator(
            envelopeLoader: { sessionID in
                sessionID == envelope.sessionId ? envelope : nil
            },
            recordLookup: recordLookup,
            recordWriter: recordWriter,
            resumeRemover: resumeRemover
        )
    }
}
