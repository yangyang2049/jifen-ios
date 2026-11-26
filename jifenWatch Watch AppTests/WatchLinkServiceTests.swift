import Foundation
import XCTest
import LinkCore
import LinkSync
import RecordCore
import ScoreCore
import SessionCore
@testable import jifenWatch_Watch_App

@MainActor
final class WatchLinkServiceTests: XCTestCase {
    /// WatchResumeSessionStore 的文件存储测试目录（每用例独立临时目录）。
    private func makeResumeStoreDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchLinkServiceTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testWatchLinkRejectsMismatchedModeBeforeShowingConfirmation() async throws {
        let directory = makeResumeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileLinkDataStore(directoryURL: directory)
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store
        )
        let state = RallyMatchEngine.initial(
            leftName: "甲",
            rightName: "乙",
            rules: .badminton()
        )
        let envelope = LinkEnvelope(
            sessionId: UUID(),
            kind: .setupRequest,
            sender: .phone,
            senderSequence: 1,
            sessionRevision: 0,
            sentAtEpochMilliseconds: 1,
            payload: LinkedScoreboardSetup(
                gameType: .badmintonDoubles,
                maxSets: state.rules.maxSets,
                initialSnapshot: .rally(state),
                participantNames: ["甲", "乙"]
            )
        )

        transport.deliver(try JSONEncoder().encode(envelope))
        await settleWatchLinkService()

        XCTAssertNil(service.pendingConfirmRequest)
        let rejection = try XCTUnwrap(
            transport.realtimeMessages.compactMap {
                try? JSONDecoder().decode(
                    LinkEnvelope<LinkSetupRejectedPayload>.self,
                    from: $0
                )
            }.last
        )
        XCTAssertEqual(rejection.payload.reason, .unsupportedSport)
        XCTAssertEqual(rejection.kind, .setupRejected)
        XCTAssertEqual(rejection.correlationId, envelope.messageId)
    }

    func testSetupNegotiatesKnownCapabilitiesAndRejectsUnsupportedProtocol() async throws {
        let directory = makeResumeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileLinkDataStore(directoryURL: directory)
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(transport: transport, contextStore: store, outboxStore: store)
        let fixture = makeWatchLinkSetup()
        let offered = LinkProtocol.requiredCapabilities.union([
            .fileTransfer, LinkCapability(rawValue: "futureCapability")
        ])
        func request(version: Int, capabilities: Set<LinkCapability>) -> LinkEnvelope<LinkedScoreboardSetup> {
            LinkEnvelope(
                protocolVersion: version, capabilities: capabilities, sessionId: UUID(),
                kind: .setupRequest, sender: .phone, senderSequence: 1,
                sessionRevision: 0, sentAtEpochMilliseconds: 1,
                payload: LinkedScoreboardSetup(
                    gameType: .badminton, initialSnapshot: fixture.snapshot, capabilities: capabilities
                )
            )
        }

        for invalid in [
            request(version: LinkProtocol.currentVersion + 1, capabilities: offered),
            request(version: LinkProtocol.currentVersion, capabilities: offered.subtracting([.sharedIntentSync]))
        ] {
            service.receive(try JSONEncoder().encode(invalid))
            await settleWatchLinkService()
            XCTAssertNil(service.pendingConfirmRequest)
            let refusal = try JSONDecoder().decode(
                LinkEnvelope<LinkSetupRejectedPayload>.self,
                from: try XCTUnwrap(transport.realtimeMessages.last)
            )
            XCTAssertEqual(refusal.correlationId, invalid.messageId)
            XCTAssertEqual(refusal.payload.reason, .incompatibleProtocol)
        }

        let valid = request(version: LinkProtocol.currentVersion, capabilities: offered)
        service.receive(try JSONEncoder().encode(valid))
        let negotiated = offered.intersection(LinkProtocol.capabilities)
        XCTAssertEqual(service.pendingConfirmRequest?.peerCapabilities, negotiated)
        service.acceptPendingSetup()
        await settleWatchLinkService()
        let response = try JSONDecoder().decode(
            LinkEnvelope<EmptyLinkPayload>.self,
            from: try XCTUnwrap(transport.realtimeMessages.last)
        )
        XCTAssertEqual(response.kind, .setupAccepted)
        XCTAssertEqual(response.correlationId, valid.messageId)
        XCTAssertEqual(response.capabilities, negotiated)
        XCTAssertTrue(service.peerSupportsFileTransfer)
        XCTAssertTrue(service.canEditLinkedMatch)
    }

    func testWatchLinkAcceptsNewlyUnlockedSportsAndValidatesDoublesContracts() {
        let squashState = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .squash())
        let shuttlecockSingles = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .shuttlecock())
        var shuttlecockDoubles = RallyMatchEngine.initial(leftName: "甲/丙", rightName: "乙/丁", rules: .shuttlecock())
        shuttlecockDoubles.doubles = .badminton(playerNames: ["甲", "乙", "丙", "丁"], servingTeam0: true)
        var shuttlecockInvalidDoubles = shuttlecockSingles
        shuttlecockInvalidDoubles.doubles = .badminton(playerNames: ["甲", "乙", "丙", "丁"], servingTeam0: true)
        shuttlecockInvalidDoubles.doubles?.playerNames = ["甲", "乙"]
        let foosballSingles = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .foosball())
        var foosballDoubles = RallyMatchEngine.initial(leftName: "甲/丙", rightName: "乙/丁", rules: .foosball())
        foosballDoubles.doubles = .foosball(playerNames: ["甲", "乙", "丙", "丁"])
        let football11 = FootballMatchState(
            leftName: "主队",
            rightName: "客队",
            timer: FootballTimerStateV2(halfLengthSeconds: 2700)
        )
        let football5 = FootballMatchState(
            leftName: "主队",
            rightName: "客队",
            timer: FootballTimerStateV2(halfLengthSeconds: 1200),
            isFiveAside: true, kickedOff: false
        )

        let validSetups: [LinkedScoreboardSetup] = [
            .init(gameType: .squash, maxSets: 5, initialSnapshot: .rally(squashState), participantNames: ["甲", "乙"]),
            .init(gameType: .shuttlecock, maxSets: 3, initialSnapshot: .rally(shuttlecockSingles), participantNames: ["甲", "乙"]),
            .init(gameType: .shuttlecock, maxSets: 3, initialSnapshot: .rally(shuttlecockDoubles), participantNames: ["甲", "乙", "丙", "丁"]),
            .init(gameType: .foosball, maxSets: 3, initialSnapshot: .rally(foosballSingles), participantNames: ["甲", "乙"]),
            .init(gameType: .foosballDoubles, maxSets: 3, initialSnapshot: .rally(foosballDoubles), participantNames: ["甲", "乙", "丙", "丁"]),
            .init(gameType: .football, maxSets: nil, initialSnapshot: .football(football11), participantNames: ["主队", "客队"]),
            .init(gameType: .football5v5, maxSets: nil, initialSnapshot: .football(football5), participantNames: ["主队", "客队"])
        ]
        for setup in validSetups {
            XCTAssertTrue(
                WatchLinkService.isValidLinkedSetup(setup),
                "Expected valid linked setup for \(setup.gameType.rawValue)"
            )
            XCTAssertNotNil(
                WatchScoreboardRoute(linkedSetup: setup),
                "Expected WatchScoreboardRoute for \(setup.gameType.rawValue)"
            )
        }

        XCTAssertEqual(
            WatchScoreboardRoute(linkedSetup: validSetups[4]),
            .foosballDoubles(maxSets: 3)
        )
        XCTAssertEqual(
            WatchScoreboardRoute(linkedSetup: validSetups[5]),
            .football(halfLengthSeconds: 2700)
        )
        XCTAssertEqual(
            WatchScoreboardRoute(linkedSetup: validSetups[6]),
            .football5v5(halfLengthSeconds: 1200)
        )

        XCTAssertFalse(WatchLinkService.isValidLinkedSetup(
            .init(gameType: .foosball, maxSets: 3, initialSnapshot: .rally(foosballDoubles), participantNames: ["甲", "乙", "丙", "丁"])
        ))
        XCTAssertFalse(WatchLinkService.isValidLinkedSetup(
            .init(gameType: .foosballDoubles, maxSets: 3, initialSnapshot: .rally(foosballSingles), participantNames: ["甲", "乙"])
        ))
        XCTAssertFalse(WatchLinkService.isValidLinkedSetup(
            .init(gameType: .shuttlecock, maxSets: 3, initialSnapshot: .rally(shuttlecockInvalidDoubles), participantNames: ["甲", "乙"])
        ))
    }

    func testWatchResumeSessionSupportsNewlyUnlockedSportsAndAppliesLinkedFootballSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchLinkServiceTests.Resume.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WatchResumeSessionStore(directoryURL: directory)
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let initialFootball = FootballMatchState(
            leftName: "红队",
            rightName: "蓝队",
            leftScore: 0,
            rightScore: 0,
            timer: FootballTimerStateV2(halfLengthSeconds: 2700),
            kickedOff: true,
            finished: false
        )
        let setup = LinkedScoreboardSetup(
            gameType: .football,
            maxSets: nil,
            initialSnapshot: .football(initialFootball),
            participantNames: ["红队", "蓝队"]
        )
        var linkContext = WatchLinkResumeContext(
            handle: handle,
            setup: setup,
            revision: 1,
            latestAuthoritativeSnapshot: .football(initialFootball),
            detailedActions: [],
            completedMatchIds: [],
            pendingTerminalMessageIds: []
        )
        store.save(WatchResumeSession(
            startedAt: Date(),
            scoreLine: "0 - 0",
            emoji: "⚽",
            payload: .football(isFiveAside: false, bundle: footballBundle(initialFootball)),
            linkHandle: linkContext.handle
        ))

        let remoteFootball = FootballMatchState(
            leftName: "红队",
            rightName: "蓝队",
            leftScore: 2,
            rightScore: 1,
            timer: FootballTimerStateV2(halfLengthSeconds: 2700),
            kickedOff: true,
            finished: false
        )
        linkContext.revision += 1
        linkContext.latestAuthoritativeSnapshot = .football(remoteFootball)
        store.applyLinkedSnapshot(.football(remoteFootball), context: linkContext)

        let updated = try XCTUnwrap(store.session)
        XCTAssertEqual(updated.scoreLine, "2 - 1")
        if case .football(let isFiveAside, let bundle) = updated.payload {
            let state = bundle.currentSession.state
            XCTAssertFalse(isFiveAside)
            XCTAssertEqual(state.leftScore, 2)
            XCTAssertEqual(state.rightScore, 1)
            XCTAssertEqual(state.leftName, "红队")
            XCTAssertEqual(state.rightName, "蓝队")
        } else {
            XCTFail("Expected .football resume payload")
        }

        let expectedResumeGameTypes: [(ScoreCore.GameType, WatchGameType)] = [
            (.shuttlecock, .shuttlecock),
            (.squash, .squash),
            (.foosball, .foosball),
            (.foosballDoubles, .foosball)
        ]
        for (rallyType, expectedWatchGameType) in expectedResumeGameTypes {
            let rallyState = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .badminton())
            let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
                gameType: rallyType,
                ruleFamily: .s1,
                reducerType: ScoreboardKernelRegistry.descriptor(for: rallyType).reducerType,
                state: rallyState
            )
            let bundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>(
                replaySeed: session,
                currentSession: session,
                undoFrames: [],
                timeline: []
            )
            let payload = WatchResumePayload.rally(gameType: rallyType, bundle: bundle, restState: nil)
            XCTAssertEqual(payload.gameType, expectedWatchGameType)
        }
    }

    func testTrainingLinkRoutesAndReturnsTheWatchRecord() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let state = LinkedShotTrainingState(
            mode: .fixed2,
            startTime: start,
            shots: [
                .init(points: 2, made: true, timestamp: start),
                .init(points: 2, made: false, timestamp: start.addingTimeInterval(1))
            ],
            finished: true
        )
        let snapshot = LinkedScoreboardSnapshot.basketballTraining(state)
        let setup = LinkedScoreboardSetup(gameType: .basketballTraining, initialSnapshot: snapshot)
        XCTAssertTrue(WatchLinkService.isValidLinkedSetup(setup))
        XCTAssertEqual(WatchScoreboardRoute(linkedSetup: setup), .basketballTraining(mode: .fixed2))
        XCTAssertFalse(WatchLinkService.isValidLinkedSetup(.init(gameType: .football, initialSnapshot: snapshot)))
        let matchId = UUID()
        let record = try XCTUnwrap(WatchLinkedRecordIngestor.makeRecord(
            payload: .init(
                snapshot: snapshot, recordId: "w_\(matchId.uuidString)", winnerSide: nil, manualEnd: true,
                startTimeEpochMilliseconds: 1_700_000_000_000, endTimeEpochMilliseconds: 1_700_000_005_000,
                durationSeconds: 5, totalScoreChanges: 2
            ),
            gameType: .basketballTraining,
            matchId: matchId
        ))
        XCTAssertEqual(record.totalScoreChanges, 2)
        XCTAssertEqual(record.basketballTrainingDetails?.counts.count(points: 2, made: true), 1)
        XCTAssertEqual(record.basketballTrainingDetails?.counts.count(points: 2, made: false), 1)
        let transfer = try XCTUnwrap(WatchRecordManager.shared.transferPayload(for: record))
        XCTAssertEqual(transfer.basketballTraining, state)
        XCTAssertEqual(transfer.detailedActions, record.actions)
    }

    func testSuspendedTrainingFollowsPhoneShotsAndPersistsUpdatedTotals() throws {
        let now = Date()
        let resumeStore = WatchResumeSessionStore(directoryURL: makeResumeStoreDirectory(), now: { now })
        let state = LinkedShotTrainingState(
            mode: .free,
            startTime: now,
            shots: [.init(points: 3, made: true, timestamp: now)],
            earlierCounts: .init(twoMiss: 1)
        )
        let snapshot = LinkedScoreboardSnapshot.basketballTraining(state)
        let context = WatchLinkResumeContext(
            handle: LinkedMatchHandle(sessionId: UUID()),
            setup: .init(gameType: .basketballTraining, initialSnapshot: snapshot),
            revision: 2,
            latestAuthoritativeSnapshot: snapshot,
            detailedActions: [],
            completedMatchIds: [],
            pendingTerminalMessageIds: []
        )
        let training = ScoreSession<ShotTrainingState, ShotTrainingEvent>(
            gameType: .basketballTraining, ruleFamily: ScoreboardKernelRegistry.descriptor(for: .basketballTraining).ruleFamily,
            reducerType: ScoreboardKernelRegistry.descriptor(for: .basketballTraining).reducerType,
            state: ShotTrainingState(mode: .free, startTime: now)
        )
        resumeStore.save(.init(
            startedAt: now, scoreLine: "0/1 = 0%", emoji: "🏀",
            payload: .basketballTraining(bundle: .init(
                replaySeed: training, currentSession: training, undoFrames: [], timeline: []
            )),
            linkHandle: context.handle
        ))

        resumeStore.applyLinkedSnapshot(snapshot, context: context)
        resumeStore.reload()

        let resumed = try XCTUnwrap(resumeStore.session)
        XCTAssertEqual(resumed.scoreLine, "1/2 = 50%")
        guard case .basketballTraining(let bundle) = resumed.payload else {
            return XCTFail("Expected a training resume payload")
        }
        let restoredState = bundle.currentSession.state
        XCTAssertEqual(restoredState.mode, .free)
        XCTAssertEqual(restoredState.shots.first?.points, 3)
        XCTAssertEqual(restoredState.earlierCounts.twoMiss, 1)
    }

    func testWatchLinkedRecordIngestorProjectsAllEighteenLinkedTypesAndRoundTrips() throws {
        var rallySingles = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .badminton())
        rallySingles.leftPoints = 21
        rallySingles.rightPoints = 18
        rallySingles.leftSets = 2
        rallySingles.rightSets = 0
        rallySingles.finished = true

        var rallyDoubles = RallyMatchEngine.initial(leftName: "甲/丙", rightName: "乙/丁", rules: .badminton())
        rallyDoubles.doubles = .badminton(playerNames: ["甲", "乙", "丙", "丁"], servingTeam0: true)
        rallyDoubles.leftPoints = 21
        rallyDoubles.rightPoints = 19
        rallyDoubles.leftSets = 2
        rallyDoubles.rightSets = 1
        rallyDoubles.finished = true

        var tennisSingles = TennisMatchState(leftName: "甲", rightName: "乙", rules: .init())
        tennisSingles.leftSets = 2
        tennisSingles.rightSets = 0
        tennisSingles.leftGames = 6
        tennisSingles.rightGames = 4
        tennisSingles.finished = true

        var tennisDoubles = TennisMatchState(
            leftName: "甲/丙",
            rightName: "乙/丁",
            rules: .init(),
            doublesPlayerNames: ["甲", "乙", "丙", "丁"]
        )
        tennisDoubles.leftSets = 2
        tennisDoubles.rightSets = 1
        tennisDoubles.leftGames = 6
        tennisDoubles.rightGames = 3
        tennisDoubles.finished = true

        let archery = ArcheryMatchState(
            leftName: "红方",
            rightName: "蓝方",
            leftArrowSum: 29,
            rightArrowSum: 25,
            leftSetPoints: 6,
            rightSetPoints: 2,
            finished: true
        )
        var eightBall = EightBallState.initial(targetPoints: 5)
        eightBall.leftPoints = 5
        eightBall.rightPoints = 3
        eightBall.finished = true
        var nineBall = NineBallChaseState.initial(playerCount: 3, playerNames: ["甲", "乙", "丙"])
        nineBall.playerPoints = [12, 8, 5, 0]
        nineBall.finished = true
        var snooker = SnookerState.initial(maxFrames: 5)
        snooker.leftScore = 71
        snooker.rightScore = 22
        snooker.leftFrames = 3
        snooker.rightFrames = 1
        snooker.finished = true
        let football11 = FootballMatchState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 2,
            rightScore: 1,
            timer: FootballTimerStateV2(halfLengthSeconds: 2700),
            kickedOff: true,
            finished: true
        )
        let football5 = FootballMatchState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 4,
            rightScore: 2,
            timer: FootballTimerStateV2(halfLengthSeconds: 1200),
            isFiveAside: true, kickedOff: true,
            finished: true
        )

        let cases: [(ScoreCore.GameType, WatchGameType, LinkedScoreboardSnapshot)] = [
            (.pingpong, .pingpong, .rally(rallySingles)),
            (.pingpongDoubles, .pingpong, .rally(rallyDoubles)),
            (.badminton, .badminton, .rally(rallySingles)),
            (.badmintonDoubles, .badminton, .rally(rallyDoubles)),
            (.tennis, .tennis, .tennis(tennisSingles)),
            (.tennisDoubles, .tennis, .tennis(tennisDoubles)),
            (.pickleball, .pickleball, .rally(rallySingles)),
            (.pickleballDoubles, .pickleball, .rally(rallyDoubles)),
            (.shuttlecock, .shuttlecock, .rally(rallySingles)),
            (.squash, .squash, .rally(rallySingles)),
            (.foosball, .foosball, .rally(rallySingles)),
            (.foosballDoubles, .foosball, .rally(rallyDoubles)),
            (.archeryDual, .archery, .archery(archery)),
            (.eightBall, .eightBall, .eightBall(eightBall)),
            (.nineBall, .nineBall, .nineBall(nineBall)),
            (.snooker, .snooker, .snooker(snooker)),
            (.football, .football, .football(football11)),
            (.football5v5, .football5v5, .football(football5))
        ]
        XCTAssertEqual(cases.count, 18)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for (scoreCoreType, expectedWatchType, snapshot) in cases {
            let matchId = UUID()
            let action = DetailedScoreAction(
                id: UUID(),
                type: .scoreChanged,
                epochMilliseconds: 1_700_000_010_000,
                team: .team1,
                scores: [1, 0]
            )
            let payload = LinkMatchFinishedPayload(
                snapshot: snapshot,
                recordId: "w_linked_\(matchId.uuidString)",
                winnerSide: .left,
                manualEnd: false,
                startTimeEpochMilliseconds: 1_700_000_000_000,
                endTimeEpochMilliseconds: 1_700_000_060_000,
                durationSeconds: 60,
                totalScoreChanges: 3,
                detailedActions: [action],
                participantNames: ["甲", "乙", "丙"]
            )
            let record = try XCTUnwrap(
                WatchLinkedRecordIngestor.makeRecord(
                    payload: payload,
                    gameType: scoreCoreType,
                    matchId: matchId
                ),
                "Expected WatchScoreboardRecord for \(scoreCoreType.rawValue)"
            )
            XCTAssertEqual(record.id, payload.recordId)
            XCTAssertEqual(record.gameType, expectedWatchType)
            XCTAssertEqual(record.actions.count, 1)
            XCTAssertEqual(record.actions.first?.id, action.id)
            XCTAssertEqual(record.projectConfiguration?["scoreCoreGameType"], scoreCoreType.rawValue)

            let roundTripped = try decoder.decode(
                WatchScoreboardRecord.self,
                from: try encoder.encode(record)
            )
            XCTAssertEqual(roundTripped.id, record.id)
            XCTAssertEqual(roundTripped.gameType, expectedWatchType)
        }
    }

    func testWatchLinkedRecordIngestorSavesToWatchRecordManagerWithoutStandaloneTransfer() throws {
        let matchId = UUID()
        let recordId = "w_test_linked_persist_\(matchId.uuidString)"
        let previousHandler = WatchRecordManager.shared.recordTransferHandler
        var transferCalled = false
        WatchRecordManager.shared.recordTransferHandler = { _ in
            transferCalled = true
        }
        defer {
            WatchRecordManager.shared.recordTransferHandler = previousHandler
            _ = WatchRecordManager.shared.deleteRecord(id: recordId)
        }

        var state = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .badminton())
        state.leftPoints = 21
        state.rightPoints = 14
        state.leftSets = 2
        state.rightSets = 0
        state.finished = true
        let payload = LinkMatchFinishedPayload(
            snapshot: .rally(state),
            recordId: recordId,
            winnerSide: .left,
            manualEnd: false,
            startTimeEpochMilliseconds: 1_700_000_000_000,
            endTimeEpochMilliseconds: 1_700_000_060_000,
            durationSeconds: 60,
            totalScoreChanges: 2,
            detailedActions: [],
            participantNames: ["甲", "乙"]
        )

        let savedId = WatchLinkedRecordIngestor.ingest(
            payload: payload,
            gameType: .badminton,
            matchId: matchId,
            syncState: .sent
        )
        XCTAssertEqual(savedId, recordId)
        XCTAssertFalse(transferCalled, "Linked match ingest must NOT trigger standalone transferToPhone")
        let stored = try XCTUnwrap(WatchRecordManager.shared.getRecord(id: recordId))
        XCTAssertEqual(stored.gameType, .badminton)
        XCTAssertEqual(stored.team1SetScore, 2)
        XCTAssertEqual(stored.team2SetScore, 0)
        XCTAssertEqual(stored.winnerIdentity, .team(.team0))
        XCTAssertEqual(stored.winnerName, "甲")
        XCTAssertEqual(WatchRecordManager.shared.syncState(for: recordId), .sent)
    }

    func testOfflineWatchFinishRestoresQueueAndReplaysExistingOperationIDsInOrder() async throws {
        let directory = makeResumeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = makeWatchLinkSetup()
        let handle = fixture.envelope.handle
        let sink = RecordingWatchLinkSink()
        let offline = WatchLinkTestTransport()
        offline.setReachable(false)
        let pending: [LinkOperation]
        do {
            let watch = makeService(directory: directory, transport: offline, sink: sink)
            try open(fixture.envelope, on: watch)
            pending = try queueOfflineFinish(on: watch, handle: handle)
            let update = try XCTUnwrap(watch.intentSync.update)
            XCTAssertTrue(update.isPendingFinish)
            XCTAssertEqual(update.displayedSnapshot.rallyState?.rightPoints, 2)
            XCTAssertEqual(update.confirmedSnapshot.rallyState?.rightPoints, 0)
            XCTAssertNil(update.savedRecordID)
            XCTAssertTrue(offline.operations.isEmpty)
            XCTAssertTrue(sink.ingested.isEmpty)
        }

        let reconnected = WatchLinkTestTransport()
        reconnected.setReachable(false)
        let watch = makeService(directory: directory, transport: reconnected, sink: sink)
        XCTAssertEqual(watch.activeHandle, handle)
        XCTAssertEqual(watch.intentSync.update?.startEpochMilliseconds, fixture.envelope.sentAtEpochMilliseconds)
        XCTAssertEqual(watch.intentSync.update?.isPendingFinish, true)
        XCTAssertEqual(watch.intentSync.update?.displayedSnapshot.rallyState?.rightPoints, 2)
        XCTAssertNil(watch.intentSync.update?.savedRecordID)

        reconnected.setReachable(true)
        await waitFor { reconnected.operations.count >= pending.count }
        XCTAssertEqual(Array(reconnected.operations.prefix(pending.count)), pending)
        XCTAssertEqual(reconnected.operations.prefix(pending.count).map(\.clientSeq), [1, 2, 3])

        let host = try WatchTestHost(launch: fixture.envelope)
        for operation in pending {
            let commit = try host.process(operation)
            XCTAssertEqual(commit.outcome, .accepted)
            try deliverCommit(commit, to: watch)
        }
        let update = try XCTUnwrap(watch.intentSync.update)
        XCTAssertFalse(update.isPendingFinish)
        XCTAssertEqual(update.confirmedSnapshot, host.snapshot)
        XCTAssertEqual(update.confirmedSnapshot.rallyState?.rightPoints, 2)
        XCTAssertEqual(update.savedRecordID, "w_\(handle.matchId.uuidString)")
        XCTAssertFalse(watch.intentSync.hasPendingOperations(for: handle))
        XCTAssertEqual(sink.ingested.map(\.matchId), [handle.matchId])
    }

    func testPhoneFirstFinishRecoveryPersistsExactHistoryBeforeAcknowledgingAndCountsOnlyScores() async throws {
        let directory = makeResumeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = makeWatchLinkSetup()
        let handle = fixture.envelope.handle
        let sink = RecordingWatchLinkSink()
        sink.canPersist = false
        let transport = WatchLinkTestTransport()
        transport.setReachable(false)
        let host = try WatchTestHost(launch: fixture.envelope)
        let opening = try host.phone(.rally(.pointWon(.left)))
        let finish = try host.phone(.finish)
        let payload: LinkIntentRecoveryPayload
        do {
            let watch = makeService(directory: directory, transport: transport, sink: sink)
            try open(fixture.envelope, on: watch)
            let pending = try queueOfflineFinish(on: watch, handle: handle)
            let late = try pending.map { try host.process($0) }
            XCTAssertTrue(late.allSatisfy {
                $0.rejectionReason == LinkOperationRejectionReason.matchFinished.rawValue
            })
            payload = try host.recovery(results: late, terminalCommit: finish)
            XCTAssertTrue(payload.finishedPayload?.detailedActions.isEmpty == true)
            XCTAssertEqual(payload.detailedActions, opening.deltaActions + finish.deltaActions)

            let frame = phoneFrame(.intentCheckpoint, handle: handle, revision: payload.checkpoint.committedRevision, payload: payload)
            try transport.deliverIntentFile(JSONEncoder().encode(frame))
            await waitFor { sink.attemptedRecordIDs.count == 1 }
            XCTAssertEqual(watch.intentSync.update?.confirmedSnapshot, host.snapshot)
            XCTAssertEqual(watch.intentSync.update?.excludedScoringOperationCount, 2)
            XCTAssertNil(watch.intentSync.update?.savedRecordID)
            XCTAssertFalse(watch.intentSync.hasPendingOperations(for: handle))
            XCTAssertFalse(transport.acknowledged(frame.messageId))
        }

        sink.canPersist = true
        let retry = WatchLinkTestTransport()
        retry.setReachable(false)
        let restored = makeService(directory: directory, transport: retry, sink: sink)
        let recordID = "w_\(handle.matchId.uuidString)"
        XCTAssertEqual(restored.intentSync.update?.savedRecordID, recordID)
        XCTAssertEqual(restored.intentSync.update?.excludedScoringOperationCount, 2)
        XCTAssertEqual(sink.ingested.map(\.recordId), [recordID])
        XCTAssertEqual(sink.payloads.first?.detailedActions, payload.detailedActions)
        XCTAssertEqual(sink.payloads.first?.endTimeEpochMilliseconds, finish.effectiveEpochMilliseconds)

        let duplicate = phoneFrame(.intentCheckpoint, handle: handle, revision: payload.checkpoint.committedRevision, payload: payload)
        try retry.deliverIntentFile(JSONEncoder().encode(duplicate))
        await waitFor { retry.acknowledged(duplicate.messageId) }
        XCTAssertTrue(retry.acknowledged(duplicate.messageId))
        XCTAssertEqual(restored.intentSync.update?.excludedScoringOperationCount, 2)
        XCTAssertEqual(restored.intentSync.update?.confirmedSnapshot.rallyState?.leftPoints, 1)
        XCTAssertEqual(restored.intentSync.update?.confirmedSnapshot.rallyState?.rightPoints, 0)
        XCTAssertEqual(sink.ingested.map(\.recordId), [recordID])
    }

    func testWrongHandleAndGapKeepPendingUntilCheckpointHasMatchingReceipts() async throws {
        let directory = makeResumeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = makeWatchLinkSetup()
        let handle = fixture.envelope.handle
        let stillPending: LinkOperation
        let confirmedRevision: UInt64
        do {
            let transport = WatchLinkTestTransport()
            let watch = makeService(directory: directory, transport: transport)
            try open(fixture.envelope, on: watch)
            let local = try watch.intentSync.submit(
                .rally(.pointWon(.right)), handle: handle, createdAtEpochMilliseconds: 1_100
            )
            stillPending = try watch.intentSync.submit(
                .rally(.pointWon(.right)), handle: handle, createdAtEpochMilliseconds: 1_200
            )
            let host = try WatchTestHost(launch: fixture.envelope)
            let first = try host.phone(.rally(.pointWon(.left)))
            let skipped = try host.process(local)
            let gapped = try host.phone(.rally(.pointWon(.left)))
            confirmedRevision = gapped.committedRevision

            let wrongHandle = LinkedMatchHandle(
                sessionId: handle.sessionId, matchId: UUID(), matchGeneration: handle.matchGeneration
            )
            try deliver(phoneFrame(
                .intentCommit, handle: wrongHandle, revision: first.committedRevision, payload: first
            ), to: watch)
            XCTAssertEqual(watch.intentSync.update?.committedRevision, 0)
            XCTAssertTrue(watch.intentSync.hasPendingOperations(for: handle))

            let badHash = LinkOperationCommitPayload(
                committedRevision: first.committedRevision, op: first.op, outcome: first.outcome,
                effectiveEpochMilliseconds: first.effectiveEpochMilliseconds, timeWasClamped: first.timeWasClamped,
                stateHash: first.stateHash ^ 1, authoritativeSnapshot: first.authoritativeSnapshot
            )
            try deliverCommit(badHash, to: watch)
            XCTAssertEqual(watch.intentSync.update?.committedRevision, 0)
            XCTAssertTrue(watch.intentSync.hasPendingOperations(for: handle))
            try deliverCommit(first, to: watch)
            try deliverCommit(gapped, to: watch)
            XCTAssertEqual(watch.intentSync.update?.committedRevision, first.committedRevision)
            await waitFor {
                transport.recoveryRequests.contains { $0.payload.pendingOperationIds == [local.opId, stillPending.opId] }
            }
            XCTAssertTrue(transport.recoveryRequests.contains {
                $0.handle == handle && $0.payload.pendingOperationIds == [local.opId, stillPending.opId]
            })

            let missingReceipt = try host.recovery(results: [])
            try deliver(phoneFrame(
                .intentCheckpoint, handle: handle, revision: missingReceipt.checkpoint.committedRevision, payload: missingReceipt
            ), to: watch)
            XCTAssertEqual(watch.intentSync.update?.committedRevision, first.committedRevision)
            XCTAssertTrue(watch.intentSync.hasPendingOperations(for: handle))

            let complete = try host.recovery(results: [skipped])
            try deliver(phoneFrame(
                .intentCheckpoint, handle: handle, revision: complete.checkpoint.committedRevision, payload: complete
            ), to: watch)
            XCTAssertEqual(watch.intentSync.update?.committedRevision, confirmedRevision)
            XCTAssertEqual(watch.intentSync.update?.confirmedSnapshot, host.snapshot)
            XCTAssertEqual(watch.intentSync.update?.confirmedSnapshot.rallyState?.rightPoints, 1)
            XCTAssertEqual(watch.intentSync.update?.displayedSnapshot.rallyState?.rightPoints, 2)
            transport.setReachable(false)
            await settleWatchLinkService()
        }

        let restartedTransport = WatchLinkTestTransport()
        let restarted = makeService(directory: directory, transport: restartedTransport)
        XCTAssertEqual(restarted.activeHandle, handle)
        XCTAssertEqual(restarted.intentSync.update?.committedRevision, confirmedRevision)
        XCTAssertEqual(restarted.intentSync.update?.displayedSnapshot.rallyState?.rightPoints, 2)
        await waitFor { !restartedTransport.operations.isEmpty }
        XCTAssertEqual(restartedTransport.operations.first, stillPending)
    }

    func testPendingFinishBlocksFreshSetupAndRolloverKeepsOldQueueAfterRestart() async throws {
        let directory = makeResumeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = makeWatchLinkSetup()
        let handle = fixture.envelope.handle
        let next = handle.nextMatch()
        let sink = RecordingWatchLinkSink()
        let host = try WatchTestHost(launch: fixture.envelope)
        _ = try host.phone(.rally(.pointWon(.left)))
        let finish = try host.phone(.finish)
        let rollover = try host.phone(.nextMatch(matchId: next.matchId, matchGeneration: next.matchGeneration))
        XCTAssertEqual(rollover.outcome, .accepted)
        let pending: [LinkOperation]
        do {
            let transport = WatchLinkTestTransport()
            transport.setReachable(false)
            let watch = makeService(directory: directory, transport: transport, sink: sink)
            try open(fixture.envelope, on: watch)
            pending = try queueOfflineFinish(on: watch, handle: handle)
            transport.setReachable(true)

            // The exact setup retransmission must not reset a durable score.
            try deliver(fixture.envelope, to: watch)
            XCTAssertNil(watch.pendingConfirmRequest)
            XCTAssertEqual(watch.intentSync.update?.displayedSnapshot.rallyState?.rightPoints, 2)

            let fresh = makeWatchLinkSetup().envelope
            try deliver(fresh, to: watch)
            XCTAssertNil(watch.pendingConfirmRequest)
            XCTAssertEqual(watch.activeHandle, handle)
            await waitFor {
                transport.setupRejections.contains {
                    $0.correlationId == fresh.messageId && $0.payload.detail == "finish_pending"
                }
            }
            XCTAssertTrue(transport.setupRejections.contains {
                $0.correlationId == fresh.messageId && $0.payload.detail == "finish_pending"
            })

            let start = phoneFrame(.matchStarted, handle: next, revision: 0, at: 2_000, payload: fixture.envelope.payload)
            try deliver(start, to: watch)
            XCTAssertEqual(watch.activeHandle, next)
            XCTAssertEqual(watch.acceptedSetup?.handle, next)
            XCTAssertTrue(watch.intentSync.hasPendingOperations(for: handle))
            XCTAssertEqual(watch.intentSync.update?.displayedSnapshot.rallyState?.rightPoints, 0)
            transport.setReachable(false)
            await settleWatchLinkService()
        }

        let reconnected = WatchLinkTestTransport()
        reconnected.setReachable(false)
        let restored = makeService(directory: directory, transport: reconnected, sink: sink)
        XCTAssertEqual(restored.activeHandle, next)
        XCTAssertTrue(restored.intentSync.hasPendingOperations(for: handle))
        reconnected.setReachable(true)
        await waitFor { reconnected.operations.filter { $0.handle == handle }.count >= pending.count }
        XCTAssertEqual(Array(reconnected.operations.filter { $0.handle == handle }.prefix(pending.count)), pending)

        let late = try pending.map { try host.process($0, isActiveMatch: false) }
        let recovery = try host.recovery(results: late, terminalCommit: finish)
        try deliver(phoneFrame(.intentCheckpoint, handle: handle, revision: recovery.checkpoint.committedRevision, payload: recovery), to: restored)
        XCTAssertEqual(restored.activeHandle, next)
        XCTAssertEqual(restored.intentSync.update?.committedRevision, 0)
        XCTAssertEqual(restored.intentSync.retiredFinishUpdate?.handle, handle)
        XCTAssertEqual(restored.intentSync.retiredFinishUpdate?.excludedScoringOperationCount, 2)
        XCTAssertEqual(sink.ingested.map(\.matchId), [handle.matchId])
        XCTAssertFalse(restored.intentSync.hasPendingOperations(for: handle))
    }

    func testOfflineQueueAgeLimitKeepsExistingScoreAndReservesFinish() throws {
        let directory = makeResumeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = WatchLinkTestTransport()
        transport.setReachable(false)
        let watch = makeService(directory: directory, transport: transport)
        let fixture = makeWatchLinkSetup()
        let handle = fixture.envelope.handle
        try open(fixture.envelope, on: watch)
        let first = try watch.intentSync.submit(
            .rally(.pointWon(.left)), handle: handle, createdAtEpochMilliseconds: 1_100
        )
        let later: Int64 = first.createdAtEpochMilliseconds + 7 * 24 * 60 * 60 * 1_000 + 1
        XCTAssertThrowsError(try watch.intentSync.submit(
            .rally(.pointWon(.right)), handle: handle, createdAtEpochMilliseconds: later
        )) { XCTAssertEqual($0 as? WatchReplayQueueError, .queueTooOld) }

        let finish = try watch.intentSync.submit(.finish, handle: handle, createdAtEpochMilliseconds: later)
        XCTAssertEqual(finish.clientSeq, 2)
        XCTAssertEqual(watch.intentSync.update?.displayedSnapshot.rallyState?.leftPoints, 1)
        XCTAssertEqual(watch.intentSync.update?.displayedSnapshot.rallyState?.rightPoints, 0)
        XCTAssertEqual(watch.intentSync.update?.isPendingFinish, true)
    }

    func testStandaloneRecordTransferAndAcknowledgementDoNotRequireLinkedSession() async throws {
        let directory = makeResumeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = WatchRecordTransferPayload(
            id: "watch-standalone-\(UUID().uuidString)", kind: .sport(.badminton), source: .watchLocal,
            startEpochMilliseconds: 1_000, endEpochMilliseconds: 2_000, durationSeconds: 1,
            team1Name: "甲", team2Name: "乙", team1FinalScore: 1, team2FinalScore: 0
        )
        do {
            let transport = WatchLinkTestTransport()
            transport.setReachable(false)
            let watch = makeService(directory: directory, transport: transport)
            watch.transferFinishedRecord(payload)
            XCTAssertNil(watch.activeHandle)
            XCTAssertEqual(watch.pendingWatchRecords, [payload])
            let frame = try XCTUnwrap(transport.standaloneRecords.first)
            XCTAssertEqual(try JSONDecoder().decode(WatchRecordTransferPayload.self, from: frame), payload)
            XCTAssertTrue(transport.operations.isEmpty)
        }

        let transport = WatchLinkTestTransport()
        transport.setReachable(false)
        let watch = makeService(directory: directory, transport: transport)
        XCTAssertEqual(watch.pendingWatchRecords, [payload])
        transport.deliverStandaloneRecordAcknowledgement([payload.id])
        await waitFor { watch.pendingWatchRecords.isEmpty }
        XCTAssertTrue(watch.pendingWatchRecords.isEmpty)
        XCTAssertNil(watch.activeHandle)
    }

    private func footballBundle(
        _ state: FootballMatchState
    ) -> ScoreSessionResumeBundle<FootballMatchState, FootballMatchEvent, FootballMatchIntent> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .football)
        let session = ScoreSession<FootballMatchState, FootballMatchEvent>(
            gameType: .football, ruleFamily: descriptor.ruleFamily, reducerType: descriptor.reducerType, state: state
        )
        return .init(replaySeed: session, currentSession: session, undoFrames: [], timeline: [])
    }

    private func makeService(
        directory: URL, transport: WatchLinkTestTransport, sink: RecordingWatchLinkSink? = nil
    ) -> WatchLinkService {
        let store = FileLinkDataStore(directoryURL: directory)
        return WatchLinkService(
            transport: transport, contextStore: store, outboxStore: store,
            recordSink: sink ?? RecordingWatchLinkSink(), intentStore: store
        )
    }

    private func open(_ setup: LinkEnvelope<LinkedScoreboardSetup>, on watch: WatchLinkService) throws {
        try deliver(setup, to: watch)
        XCTAssertEqual(watch.pendingConfirmRequest?.handle, setup.handle)
        watch.acceptPendingSetup()
        XCTAssertEqual(watch.activeHandle, setup.handle)
    }

    private func queueOfflineFinish(on watch: WatchLinkService, handle: LinkedMatchHandle) throws -> [LinkOperation] {
        [
            try watch.intentSync.submit(.rally(.pointWon(.right)), handle: handle, createdAtEpochMilliseconds: 1_100),
            try watch.intentSync.submit(.rally(.pointWon(.right)), handle: handle, createdAtEpochMilliseconds: 1_200),
            try watch.intentSync.submit(.finish, handle: handle, createdAtEpochMilliseconds: 1_300)
        ]
    }

    private func deliverCommit(_ result: LinkOperationCommitPayload, to watch: WatchLinkService) throws {
        try deliver(phoneFrame(.intentCommit, handle: result.op.handle, revision: result.committedRevision, payload: result), to: watch)
    }

    private func deliver<Value: Codable & Sendable>(_ frame: LinkEnvelope<Value>, to watch: WatchLinkService) throws {
        watch.receive(try JSONEncoder().encode(frame))
    }

    private func phoneFrame<Value: Codable & Sendable>(
        _ kind: LinkMessageKind, handle: LinkedMatchHandle,
        revision: UInt64, at timestamp: Int64 = 1_500, payload: Value
    ) -> LinkEnvelope<Value> {
        LinkEnvelope(
            sessionId: handle.sessionId, matchId: handle.matchId, matchGeneration: handle.matchGeneration,
            kind: kind, sender: .phone, senderSequence: revision + 1, sessionRevision: revision,
            sentAtEpochMilliseconds: timestamp, payload: payload
        )
    }

    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Expected service work was not observed", file: file, line: line)
    }

    private func makeWatchLinkSetup() -> (
        envelope: LinkEnvelope<LinkedScoreboardSetup>,
        snapshot: LinkedScoreboardSnapshot
    ) {
        let state = RallyMatchEngine.initial(
            leftName: "甲",
            rightName: "乙",
            rules: .badminton()
        )
        let snapshot = LinkedScoreboardSnapshot.rally(state)
        let handle = LinkedMatchHandle(sessionId: UUID())
        return (
            LinkEnvelope(
                sessionId: handle.sessionId,
                matchId: handle.matchId,
                matchGeneration: handle.matchGeneration,
                kind: .setupRequest,
                sender: .phone,
                senderSequence: 1,
                sessionRevision: 0,
                sentAtEpochMilliseconds: 1,
                payload: LinkedScoreboardSetup(
                    gameType: .badminton,
                    maxSets: state.rules.maxSets,
                    initialSnapshot: snapshot,
                    participantNames: ["甲", "乙"]
                )
            ),
            snapshot
        )
    }

    private func settleWatchLinkService() async {
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}

@MainActor
private final class RecordingWatchLinkSink: WatchLinkRecordSink {
    struct Entry: Equatable {
        let recordId: String
        let gameType: ScoreCore.GameType
        let matchId: UUID
        let syncState: WatchRecordSyncState
        let actionCount: Int
    }

    private(set) var ingested: [Entry] = []
    private(set) var payloads: [LinkMatchFinishedPayload] = []
    private(set) var attemptedRecordIDs: [String] = []
    private(set) var markedSyncedRecordIds: [String] = []
    var canPersist = true

    @discardableResult
    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        syncState: WatchRecordSyncState
    ) -> String? {
        let id = payload.recordId.isEmpty ? "w_\(matchId.uuidString)" : payload.recordId
        attemptedRecordIDs.append(id)
        guard canPersist else { return nil }
        payloads.append(payload)
        ingested.append(.init(
            recordId: id,
            gameType: gameType,
            matchId: matchId,
            syncState: syncState,
            actionCount: payload.detailedActions.count
        ))
        return id
    }

    func markSynced(recordId: String) {
        markedSyncedRecordIds.append(recordId)
    }
}

/// Drives the real Phone sequencer without using WatchConnectivity's iOS process.
@MainActor
private final class WatchTestHost {
    private let launch: LinkEnvelope<LinkedScoreboardSetup>
    private let adapter: LinkedReducerAdapter
    private var sequencer: PhoneHostSequencer<LinkedReducerState>
    private var receipts: [UUID: LinkOperationCommitPayload] = [:]
    private var ordered: [LinkOperationCommitPayload] = []

    init(launch: LinkEnvelope<LinkedScoreboardSetup>) throws {
        self.launch = launch
        let snapshot = try XCTUnwrap(launch.payload.initialSnapshot)
        let adapter = LinkedReducerAdapter()
        self.adapter = adapter
        let state = try XCTUnwrap(adapter.state(gameType: launch.payload.gameType, from: snapshot))
        sequencer = PhoneHostSequencer(
            checkpoint: PhoneHostCheckpoint(
                handle: launch.handle, state: state, initialEpochMilliseconds: launch.sentAtEpochMilliseconds
            ),
            snapshot: adapter.snapshot, isFinished: adapter.isFinished, transition: adapter.transition
        )
    }

    var snapshot: LinkedScoreboardSnapshot { adapter.snapshot(sequencer.checkpoint.state) }

    func phone(_ intent: LinkedScoreboardIntent) throws -> LinkOperationCommitPayload {
        let checkpoint = sequencer.checkpoint
        return try process(LinkOperation(
            opId: UUID(), handle: launch.handle, origin: .phone,
            clientSeq: checkpoint.phoneClientSeq + 1, baseRevision: checkpoint.committedRevision,
            createdAtEpochMilliseconds: checkpoint.effectiveEpochMilliseconds + 100, intent: intent
        ))
    }

    func process(_ op: LinkOperation, isActiveMatch: Bool = true) throws -> LinkOperationCommitPayload {
        let known = receipts
        let result = try sequencer.process(
            op, from: op.origin, phoneClockReferenceEpochMilliseconds: op.createdAtEpochMilliseconds,
            isActiveMatch: isActiveMatch, lookup: { known[$0] }, persist: { _, _ in }
        )
        if receipts.updateValue(result, forKey: op.opId) == nil { ordered.append(result) }
        return result
    }

    func recovery(
        results: [LinkOperationCommitPayload], terminalCommit: LinkOperationCommitPayload? = nil
    ) throws -> LinkIntentRecoveryPayload {
        let checkpoint = try sequencer.authoritativeCheckpoint(watchResults: results)
        let actions = ordered.flatMap(\.deltaActions)
        let finished: LinkMatchFinishedPayload?
        if let terminalCommit {
            finished = LinkMatchFinishedPayload(
                snapshot: checkpoint.snapshot, recordId: "w_\(launch.handle.matchId.uuidString)",
                manualEnd: terminalCommit.op.intent == .finish,
                startTimeEpochMilliseconds: launch.sentAtEpochMilliseconds,
                endTimeEpochMilliseconds: terminalCommit.effectiveEpochMilliseconds,
                durationSeconds: Double(terminalCommit.effectiveEpochMilliseconds - launch.sentAtEpochMilliseconds) / 1_000,
                totalScoreChanges: actions.filter { $0.type != .undo }.count,
                detailedActions: [], participantNames: launch.payload.participantNames
            )
        } else {
            finished = nil
        }
        return LinkIntentRecoveryPayload(
            checkpoint: checkpoint, detailedActions: actions,
            nextMatchHandle: sequencer.checkpoint.nextMatchHandle, finishedPayload: finished
        )
    }
}

private final class WatchLinkTestTransport: @unchecked Sendable, WatchLinkTransport {
    private let lock = NSLock()
    private var storedStatus = WatchLinkTestTransport.status(reachable: true)
    private var storedContext: [String: Any] = [:]
    private var realtime: [Data] = []
    private var durable: [Data] = []
    private var files: [(data: Data, metadata: [String: Any])] = []
    private var records: [Data] = []

    var status: WatchConnectivityStatus { lock.withLock { storedStatus } }
    var receivedApplicationContext: [String: Any] { lock.withLock { storedContext } }
    var isReachable: Bool { status.isReachable }
    var realtimeMessages: [Data] { lock.withLock { realtime } }
    var standaloneRecords: [Data] { lock.withLock { records } }

    var onReceive: (@Sendable (Data) -> Void)?
    var onSendError: (@Sendable (Error) -> Void)?
    var onStatusChange: (@Sendable (WatchConnectivityStatus) -> Void)?
    var onApplicationContext: (@Sendable ([String: Any]) -> Void)?
    var onWatchRecordData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationsData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationAckData: (@Sendable (Data) -> Void)?
    var onCatchUpRequest: (@Sendable () -> Void)?
    var onClearPendingRequest: (@Sendable ([String]) -> Void)?
    var onPendingRecords: (@Sendable ([Data]) -> Void)?
    var onReceivedFile: (@Sendable (Data, [String: Any]) -> Void)?
    let supportsFileTransfer = true

    private static func status(reachable: Bool) -> WatchConnectivityStatus {
        WatchConnectivityStatus(
            isSupported: true, isActivated: true, isPaired: true,
            isWatchAppInstalled: true, isReachable: reachable
        )
    }

    func setReachable(_ reachable: Bool) {
        let next = Self.status(reachable: reachable)
        lock.withLock { storedStatus = next }
        onStatusChange?(next)
    }

    var operations: [LinkOperation] {
        envelopes(LinkOperation.self, kind: .intentSubmit).map(\.payload)
    }

    var recoveryRequests: [LinkEnvelope<LinkIntentRecoveryRequest>] {
        envelopes(LinkIntentRecoveryRequest.self, kind: .resyncRequest)
    }

    var setupRejections: [LinkEnvelope<LinkSetupRejectedPayload>] {
        envelopes(LinkSetupRejectedPayload.self, kind: .setupRejected)
    }

    func acknowledged(_ messageId: UUID) -> Bool {
        envelopes(LinkAcknowledgementPayload.self, kind: .acknowledgement).contains {
            $0.correlationId == messageId && $0.payload.acknowledgedMessageId == messageId
        }
    }

    private func envelopes<Value: Codable & Sendable>(
        _ type: Value.Type, kind: LinkMessageKind
    ) -> [LinkEnvelope<Value>] {
        let frames = lock.withLock { realtime + durable + files.map(\.data) }
        return frames.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<Value>.self, from: $0)
        }.filter { $0.kind == kind }
    }

    func activate() {}
    func refreshStatus() { onStatusChange?(status) }

    func sendRealtime(_ data: Data) async throws {
        try lock.withLock {
            guard storedStatus.isReachable else { throw WatchConnectivityTransportError.peerNotReachable }
            realtime.append(data)
        }
    }

    func publishLatestSnapshot(_ data: Data) throws {}

    func enqueueDurable(_ data: Data) throws {
        lock.withLock { durable.append(data) }
    }

    func sendInteractive(_ data: Data) throws {
        lock.withLock { realtime.append(data) }
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        lock.withLock { storedContext.merge(context) { _, latest in latest } }
    }

    func transferWatchRecord(_ data: Data) throws {
        lock.withLock { records.append(data) }
    }

    func transferFileData(_ data: Data, metadata: [String: Any]) throws {
        lock.withLock { files.append((data, metadata)) }
    }

    func transferCommonNameMutations(_ data: Data) throws {}
    func transferCommonNameMutationAcknowledgement(_ data: Data) throws {}
    func requestPendingWatchRecords() {}
    func sendPendingWatchRecords(_ datas: [Data]) {}
    func clearPendingWatchRecords(ids: [String]) {}

    func deliver(_ data: Data) {
        onReceive?(data)
    }

    func deliverStandaloneRecordAcknowledgement(_ ids: [String]) {
        onClearPendingRequest?(ids)
    }

    func deliverIntentFile(_ data: Data) {
        onReceivedFile?(data, [
            WatchConnectivityTransport.transferFileKindKey: WatchTransferFileKind.intentFrame.rawValue
        ])
    }
}
