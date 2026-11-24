import XCTest
import LinkCore
import RecordCore
import ScoreCore
import SessionCore
@testable import jifenWatch_Watch_App

@MainActor
final class WatchLinkServiceTests: XCTestCase {
    func testMergeDetailedActionsKeepsConcurrentLocalActionsAndDeduplicates() {
        let service = WatchLinkService(
            transport: WatchLinkTestTransport(),
            contextStore: WatchLinkTestDataStore(),
            outboxStore: WatchLinkTestDataStore()
        )

        let localOld = DetailedScoreAction(
            id: UUID(), type: .scoreChanged, epochMilliseconds: 1_000,
            team: .team1, scores: [1, 0]
        )
        let localNew = DetailedScoreAction(
            id: UUID(), type: .scoreChanged, epochMilliseconds: 3_000,
            team: .team2, scores: [1, 1]
        )
        service.mergeDetailedActions([localOld, localNew])

        let watchNew = DetailedScoreAction(
            id: UUID(), type: .scoreChanged, epochMilliseconds: 2_000,
            team: .team1, scores: [2, 1]
        )
        let replayedLocalOld = DetailedScoreAction(
            id: localOld.id, type: .scoreChanged, epochMilliseconds: 1_000,
            team: .team1, scores: [1, 0]
        )
        service.mergeDetailedActions([replayedLocalOld, watchNew])

        XCTAssertEqual(
            service.mergedDetailedActions.map(\.id),
            [localOld.id, watchNew.id, localNew.id]
        )
    }

    func testWatchLinkRejectsMismatchedModeBeforeShowingConfirmation() async throws {
        let store = WatchLinkTestDataStore()
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
                    LinkEnvelope<EmptyLinkPayload>.self,
                    from: $0
                )
            }.last
        )
        XCTAssertEqual(rejection.kind, .setupRejected)
        XCTAssertEqual(rejection.correlationId, envelope.messageId)
    }

    func testWatchLinkNextMatchCreatesFreshIdentityAndRevision() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store
        )
        let setup = makeWatchLinkSetup()
        transport.deliver(try JSONEncoder().encode(setup.envelope))
        await settleWatchLinkService()
        service.acceptPendingSetup()
        let firstHandle = try XCTUnwrap(service.resumeContext?.handle)

        service.startNextMatch(snapshot: setup.snapshot)
        await settleWatchLinkService()

        let next = try XCTUnwrap(service.resumeContext)
        XCTAssertEqual(next.handle.sessionId, firstHandle.sessionId)
        XCTAssertEqual(next.handle.matchGeneration, firstHandle.matchGeneration + 1)
        XCTAssertNotEqual(next.handle.matchId, firstHandle.matchId)
        XCTAssertEqual(next.revision, 1)
        XCTAssertEqual(next.role, .watchController)
        XCTAssertEqual(transport.publishedSnapshots.count, 1)
    }

    func testWatchLinkTakeoverIsCorrelatedIdempotentAndRestoresFollower() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store
        )
        let setup = makeWatchLinkSetup()
        transport.deliver(try JSONEncoder().encode(setup.envelope))
        await settleWatchLinkService()
        service.acceptPendingSetup()
        let handle = try XCTUnwrap(service.resumeContext?.handle)
        let takeover = LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: 0,
            kind: .takeoverByPhone,
            sender: .phone,
            senderSequence: 2,
            sessionRevision: 0,
            sentAtEpochMilliseconds: 2,
            payload: LinkAuthorityTransferPayload(
                snapshot: setup.snapshot,
                baseRevision: 0
            )
        )
        let takeoverData = try JSONEncoder().encode(takeover)

        transport.deliver(takeoverData)
        await settleWatchLinkService()
        transport.deliver(takeoverData)
        await settleWatchLinkService()

        let context = try XCTUnwrap(service.resumeContext)
        XCTAssertEqual(context.role, .watchFollower)
        XCTAssertEqual(context.authorityEpoch, 1)
        let acknowledgements = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(
                LinkEnvelope<LinkAcknowledgementPayload>.self,
                from: $0
            )
        }.filter { $0.correlationId == takeover.messageId }
        XCTAssertEqual(acknowledgements.count, 2)
        XCTAssertTrue(acknowledgements.allSatisfy { $0.authorityEpoch == 1 })

        let restored = WatchLinkService(
            transport: WatchLinkTestTransport(),
            contextStore: store,
            outboxStore: store
        )
        XCTAssertEqual(restored.resumeContext?.role, .watchFollower)
        XCTAssertEqual(restored.resumeContext?.authorityEpoch, 1)
        XCTAssertEqual(restored.resumeContext?.handle, handle)
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
        let football11 = LinkedFootballState(
            leftName: "主队",
            rightName: "客队",
            timer: FootballTimerStateV2(halfLengthSeconds: 2700)
        )
        let football5 = LinkedFootballState(
            leftName: "主队",
            rightName: "客队",
            timer: FootballTimerStateV2(halfLengthSeconds: 1200),
            kickedOff: false
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
        let suiteName = "WatchLinkServiceTests.Resume.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchResumeSessionStore(defaults: defaults)
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let initialFootball = LinkedFootballState(
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
        let linkContext = WatchLinkResumeContext(
            handle: handle,
            setup: setup,
            role: .watchFollower,
            authorityEpoch: 1,
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
            payload: .football(
                isFiveAside: false,
                state: WatchFootballState(
                    leftScore: 0,
                    rightScore: 0,
                    clock: initialFootball.timer,
                    kickedOff: true
                ),
                undoStates: [],
                leftName: "红队",
                rightName: "蓝队"
            ),
            link: linkContext
        ))

        let remoteFootball = LinkedFootballState(
            leftName: "红队",
            rightName: "蓝队",
            leftScore: 2,
            rightScore: 1,
            timer: FootballTimerStateV2(halfLengthSeconds: 2700),
            kickedOff: true,
            finished: false
        )
        store.applyLinkedSnapshot(.football(remoteFootball), context: linkContext)

        let updated = try XCTUnwrap(store.session)
        XCTAssertEqual(updated.scoreLine, "2 - 1")
        if case .football(let isFiveAside, let state, _, let leftName, let rightName) = updated.payload {
            XCTAssertFalse(isFiveAside)
            XCTAssertEqual(state.leftScore, 2)
            XCTAssertEqual(state.rightScore, 1)
            XCTAssertEqual(leftName, "红队")
            XCTAssertEqual(rightName, "蓝队")
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

    func testWatchPublishSnapshotStripsDetailedActionsFromApplicationContextAndPreservesOnEmptyReceive() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store
        )
        let setup = makeWatchLinkSetup()
        transport.deliver(try JSONEncoder().encode(setup.envelope))
        await settleWatchLinkService()
        service.acceptPendingSetup()

        let action = DetailedScoreAction(
            id: UUID(),
            type: .scoreChanged,
            epochMilliseconds: 2_000,
            team: .team1,
            scores: [1, 0]
        )
        service.publishSnapshot(setup.snapshot, detailedActions: [action])
        await settleWatchLinkService()

        let contextEnvelope = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: try XCTUnwrap(transport.publishedSnapshots.last)
        )
        let realtimeEnvelope = try JSONDecoder().decode(
            LinkEnvelope<LinkedScoreboardSetup>.self,
            from: try XCTUnwrap(transport.realtimeMessages.last)
        )
        XCTAssertTrue(contextEnvelope.payload.detailedActions.isEmpty)
        XCTAssertEqual(realtimeEnvelope.payload.detailedActions.map(\.id), [action.id])

        // Transfer to phone controller, then receive a stripped applicationContext
        // snapshot with detailedActions == []; local merged actions must be preserved.
        let handle = try XCTUnwrap(service.resumeContext?.handle)
        let takeover = LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: 0,
            kind: .takeoverByPhone,
            sender: .phone,
            senderSequence: 2,
            sessionRevision: 1,
            sentAtEpochMilliseconds: 2_500,
            payload: LinkAuthorityTransferPayload(snapshot: setup.snapshot, baseRevision: 1)
        )
        transport.deliver(try JSONEncoder().encode(takeover))
        await settleWatchLinkService()

        let strippedFromPhone = LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: 1,
            kind: .stateSnapshot,
            sender: .phone,
            senderSequence: 3,
            sessionRevision: 2,
            sentAtEpochMilliseconds: 3_000,
            payload: LinkedScoreboardSetup(
                gameType: .badminton,
                maxSets: 3,
                initialSnapshot: setup.snapshot,
                detailedActions: [],
                participantNames: ["甲", "乙"]
            )
        )
        transport.deliver(try JSONEncoder().encode(strippedFromPhone))
        await settleWatchLinkService()

        XCTAssertEqual(service.mergedDetailedActions.map(\.id), [action.id])
        XCTAssertEqual(service.activeSetup?.detailedActions.map(\.id), [action.id])
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

private final class WatchLinkTestDataStore: @unchecked Sendable, LinkDataStore {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) {
        values[key] = data
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }
}

private final class WatchLinkTestTransport: @unchecked Sendable, WatchLinkTransport {
    var status = WatchConnectivityStatus(
        isSupported: true,
        isActivated: true,
        isPaired: true,
        isWatchAppInstalled: true,
        isReachable: true
    )
    var receivedApplicationContext: [String: Any] = [:]
    var isReachable: Bool { status.isReachable }

    var onReceive: (@Sendable (Data) -> Void)?
    var onSendError: (@Sendable (Error) -> Void)?
    var onStatusChange: (@Sendable (WatchConnectivityStatus) -> Void)?
    var onApplicationContext: (@Sendable ([String: Any]) -> Void)?
    var onWatchRecordData: (@Sendable (Data) -> Void)?
    var onCommonNameUsageData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationsData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationAckData: (@Sendable (Data) -> Void)?
    var onCatchUpRequest: (@Sendable () -> Void)?
    var onClearPendingRequest: (@Sendable ([String]) -> Void)?
    var onPendingRecords: (@Sendable ([Data]) -> Void)?

    private(set) var realtimeMessages: [Data] = []
    private(set) var publishedSnapshots: [Data] = []
    private(set) var durableMessages: [Data] = []

    func activate() {}
    func refreshStatus() { onStatusChange?(status) }

    func sendRealtime(_ data: Data) async throws {
        realtimeMessages.append(data)
    }

    func publishLatestSnapshot(_ data: Data) throws {
        publishedSnapshots.append(data)
    }

    func enqueueDurable(_ data: Data) throws {
        durableMessages.append(data)
    }

    func sendInteractive(_ data: Data) throws {
        realtimeMessages.append(data)
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        receivedApplicationContext.merge(context) { _, latest in latest }
    }

    func transferWatchRecord(_ data: Data) throws {}
    func transferCommonNameUsage(_ data: Data) throws {}
    func transferCommonNameMutations(_ data: Data) throws {}
    func transferCommonNameMutationAcknowledgement(_ data: Data) throws {}
    func requestPendingWatchRecords() {}
    func sendPendingWatchRecords(_ datas: [Data]) {}
    func clearPendingWatchRecords(ids: [String]) {}

    func deliver(_ data: Data) {
        onReceive?(data)
    }
}
