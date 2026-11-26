import XCTest
import LinkCore
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

    func testCancelFailedTrainingFinishLetsNextFinishSendUpdatedTraining() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let sink = RecordingWatchLinkSink()
        let service = WatchLinkService(transport: transport, contextStore: store, outboxStore: store, recordSink: sink)
        let handle = LinkedMatchHandle(sessionId: UUID())
        let setup = LinkedScoreboardSetup(
            gameType: .basketballTraining, maxSets: 1,
            initialSnapshot: .basketballTraining(.init(mode: .fixed2))
        )
        let request = LinkEnvelope(
            supportsCompressedFinish: true,
            sessionId: handle.sessionId, matchId: handle.matchId, kind: .setupRequest,
            sender: .phone, senderSequence: 1, sessionRevision: 0,
            sentAtEpochMilliseconds: service.nowMs(), payload: setup
        )
        service.receive(try JSONEncoder().encode(request))
        service.acceptPendingSetup()
        XCTAssertEqual(service.activeHandle, handle)

        func finish(attempts: Int) -> Bool {
            service.publishMatchFinished(
                snapshot: .basketballTraining(.init(
                    mode: .fixed2, earlierCounts: .init(twoMade: attempts), finished: true
                )),
                recordId: "training", winnerSide: nil, manualEnd: true, totalScoreChanges: attempts
            )
        }
        sink.canPersist = false
        XCTAssertFalse(finish(attempts: 1))
        XCTAssertEqual(service.terminalOutbox.items.first?.pendingLocalRecord?.payload.totalScoreChanges, 1)
        XCTAssertTrue(transport.durableMessages.isEmpty)

        service.cancelPendingTrainingFinish(handle: handle)
        XCTAssertTrue(service.terminalOutbox.isEmpty)
        XCTAssertTrue(service.publishedFinishedMatchIds.isEmpty)

        sink.canPersist = true
        XCTAssertTrue(finish(attempts: 2))
        // Cancellation cannot remove a finish that already persisted and is awaiting ACK.
        service.cancelPendingTrainingFinish(handle: handle)
        await settleWatchLinkService()
        let terminalMessages = transport.durableMessages.compactMap { LinkFinishedEncoding.decode($0) }
        XCTAssertEqual(terminalMessages.count, 1)
        let terminal = try XCTUnwrap(terminalMessages.first)
        XCTAssertEqual(terminal.payload.totalScoreChanges, 2)
        XCTAssertTrue(service.terminalOutbox.contains(sessionId: handle.sessionId, matchId: handle.matchId))
        XCTAssertEqual(sink.ingested.count, 1)
    }

    func testSharedLinkAcceptsPhoneScoresAndKeepsWatchEditingEnabled() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let sink = RecordingWatchLinkSink()
        let service = WatchLinkService(transport: transport, contextStore: store, outboxStore: store, recordSink: sink)
        let start = makeWatchLinkSetup(supportsSharedEditing: true)
        service.receive(try JSONEncoder().encode(start.envelope))
        service.acceptPendingSetup()
        await settleWatchLinkService()
        let accepted = try XCTUnwrap(transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: $0)
        }.first { $0.kind == .setupAccepted })
        XCTAssertEqual(accepted.supportsSharedEditing, true)
        XCTAssertTrue(service.canEditLinkedMatch)
        XCTAssertFalse(service.isFollower)

        var phoneState = try XCTUnwrap(start.snapshot.rallyState)
        phoneState.leftPoints = 1
        func setup(for state: RallyMatchState) -> LinkedScoreboardSetup {
            .init(gameType: .badminton, maxSets: state.rules.maxSets, initialSnapshot: .rally(state))
        }
        service.receive(try JSONEncoder().encode(LinkEnvelope(
            baseSnapshotRevision: 0, sessionId: accepted.sessionId, matchId: accepted.matchId,
            kind: .stateSnapshot, sender: .phone, senderSequence: 2,
            sessionRevision: 1, sentAtEpochMilliseconds: service.nowMs(), payload: setup(for: phoneState)
        )))
        XCTAssertEqual(service.incomingSnapshot?.snapshot, .rally(phoneState))
        XCTAssertTrue(service.canEditLinkedMatch)

        var watchState = phoneState
        watchState.rightPoints = 1
        service.publishSnapshot(.rally(watchState))
        await settleWatchLinkService()
        let watchEdit = try XCTUnwrap(transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: $0)
        }.last { $0.kind == .stateSnapshot })
        XCTAssertEqual(watchEdit.sessionRevision, 4)
        XCTAssertEqual(watchEdit.baseSnapshotRevision, 1)
        XCTAssertNil(service.incomingSnapshot)
        XCTAssertNil(service.simultaneousEditNotice)

        phoneState.leftPoints = 2
        service.receive(try JSONEncoder().encode(LinkEnvelope(
            baseSnapshotRevision: 1, sessionId: accepted.sessionId, matchId: accepted.matchId,
            kind: .stateSnapshot, sender: .phone, senderSequence: 3,
            sessionRevision: 3, sentAtEpochMilliseconds: service.nowMs(), payload: setup(for: phoneState)
        )))
        XCTAssertEqual(service.latestSnapshot?.snapshot, .rally(watchState))
        XCTAssertNotNil(service.simultaneousEditNotice)

        let restored = WatchLinkService(
            transport: WatchLinkTestTransport(), contextStore: store, outboxStore: store, recordSink: sink
        )
        XCTAssertEqual(restored.controlRole, .shared)
        XCTAssertEqual(restored.latestSnapshot?.snapshot, .rally(watchState))
        XCTAssertNil(restored.incomingSnapshot)
    }

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

    func testWatchCanStartNextMatchWithEarlierTerminalStillAwaitingACK() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let sink = RecordingWatchLinkSink()
        let service = WatchLinkService(transport: transport, contextStore: store, outboxStore: store, recordSink: sink)
        let start = makeWatchLinkSetup()
        service.receive(try JSONEncoder().encode(start.envelope))
        service.acceptPendingSetup()
        let first = try XCTUnwrap(service.activeHandle)
        var state = try XCTUnwrap(start.snapshot.rallyState)
        state.leftPoints = 21
        state.finished = true

        sink.canPersist = false
        XCTAssertFalse(service.publishMatchFinished(snapshot: .rally(state), recordId: "first", winnerSide: .left, manualEnd: true))
        let staged = try XCTUnwrap(service.terminalOutbox.items.first)
        XCTAssertNotNil(staged.pendingLocalRecord)
        XCTAssertFalse(service.publishedFinishedMatchIds.contains(first.matchId))
        await settleWatchLinkService()
        XCTAssertTrue(transport.durableMessages.isEmpty)

        let recoveredTransport = WatchLinkTestTransport()
        let recovered = WatchLinkService(transport: recoveredTransport, contextStore: store, outboxStore: store, recordSink: sink)
        sink.canPersist = true
        XCTAssertTrue(recovered.publishMatchFinished(snapshot: .rally(state), recordId: "changed", winnerSide: .left, manualEnd: true))
        XCTAssertEqual(sink.ingested.map(\.recordId), ["first"])
        recovered.startNextMatch(snapshot: start.snapshot)
        let next = try XCTUnwrap(recovered.activeHandle)
        XCTAssertEqual(next.matchGeneration, first.matchGeneration + 1)
        XCTAssertEqual(recovered.terminalOutbox.items.map(\.handle), [first])
        await settleWatchLinkService()
        XCTAssertEqual(recoveredTransport.publishedSnapshots.count, 1)
        XCTAssertEqual(recoveredTransport.durableMessages.first.flatMap(LinkFinishedEncoding.decode)?.messageId, staged.messageId)

        let ack = LinkEnvelope(
            correlationId: staged.messageId, sessionId: first.sessionId, matchId: first.matchId,
            matchGeneration: first.matchGeneration, kind: .recordAcknowledgement, sender: .phone,
            senderSequence: 8, sessionRevision: 1, sentAtEpochMilliseconds: 6_000,
            payload: LinkAcknowledgementPayload(acknowledgedMessageId: staged.messageId, acknowledgedRevision: 1)
        )
        recovered.receive(try JSONEncoder().encode(ack))
        XCTAssertEqual(recovered.activeHandle, next)
        XCTAssertTrue(recovered.terminalOutbox.isEmpty)
        XCTAssertEqual(sink.markedSyncedRecordIds, ["first"])
    }

    func testNextPhoneFinishCanArriveBeforeSnapshotAndRetiredSessionDoesNotReopen() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let sink = RecordingWatchLinkSink()
        let fixture = makeWatchLinkSetup()
        let first = fixture.envelope.handle
        let context = WatchLinkResumeContext(
            handle: first, setup: fixture.envelope.payload, role: .watchFollower,
            authorityEpoch: 1, revision: 2, latestAuthoritativeSnapshot: fixture.snapshot,
            detailedActions: [], completedMatchIds: [], pendingTerminalMessageIds: []
        )
        store.set(try JSONEncoder().encode(context), forKey: "watch_link_context")
        let service = WatchLinkService(transport: transport, contextStore: store, outboxStore: store, recordSink: sink)
        let next = first.nextMatch()
        var state = try XCTUnwrap(fixture.snapshot.rallyState)
        state.leftPoints = 21
        state.finished = true
        func finish(_ handle: LinkedMatchHandle) -> Data {
            LinkFinishedEncoding.encode(LinkEnvelope(
                sessionId: handle.sessionId, matchId: handle.matchId, matchGeneration: handle.matchGeneration,
                authorityEpoch: 1, kind: .matchFinished, sender: .phone, senderSequence: 4,
                sessionRevision: 3, sentAtEpochMilliseconds: 4_000,
                payload: LinkMatchFinishedPayload(snapshot: .rally(state), recordId: handle.matchId.uuidString)
            ), compress: true)
        }

        service.receive(finish(next))
        XCTAssertEqual(service.activeHandle, next)
        XCTAssertEqual(service.latestSnapshot?.snapshot, .rally(state))
        let lateSnapshot = LinkEnvelope(
            sessionId: next.sessionId, matchId: next.matchId, matchGeneration: next.matchGeneration,
            authorityEpoch: 1, kind: .stateSnapshot, sender: .phone,
            senderSequence: 5, sessionRevision: 4, sentAtEpochMilliseconds: 4_010,
            payload: fixture.envelope.payload
        )
        service.receive(try JSONEncoder().encode(lateSnapshot))
        XCTAssertEqual(service.latestSnapshot?.snapshot, .rally(state))
        service.endLocalSession()
        let third = next.nextMatch()
        service.receive(finish(third))
        service.receive(finish(first))
        service.receive(finish(third))
        await settleWatchLinkService()

        XCTAssertNil(service.activeHandle)
        XCTAssertEqual(sink.ingested.map(\.matchId), [next.matchId, third.matchId, first.matchId])
        let acks = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: $0)
        }.filter { $0.kind == .recordAcknowledgement }
        XCTAssertEqual(acks.filter { $0.handle == third }.count, 2)
    }

    func testSetupNegotiatesKnownCapabilitiesAndRejectsUnsupportedProtocol() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(transport: transport, contextStore: store, outboxStore: store)
        let fixture = makeWatchLinkSetup()
        let offered = LinkProtocol.requiredCapabilities.union([
            .deltaActions, LinkCapability(rawValue: "futureCapability")
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
            request(version: LinkProtocol.currentVersion, capabilities: offered.subtracting([.correlatedRequests]))
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
        let negotiated = LinkProtocol.requiredCapabilities.union([.deltaActions])
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
        XCTAssertTrue(service.peerSupportsDeltaActions)
        XCTAssertFalse(service.peerSupportsFileTransfer)
    }

    func testTrainingRejectsPhoneWithoutFinishSupport() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(transport: transport, contextStore: store, outboxStore: store)
        let setup = LinkEnvelope(
            sessionId: UUID(), kind: .setupRequest, sender: .phone, senderSequence: 1,
            sessionRevision: 0, sentAtEpochMilliseconds: 1,
            payload: LinkedScoreboardSetup(gameType: .basketballTraining, initialSnapshot: .basketballTraining(.init(mode: .free)))
        )
        service.receive(try JSONEncoder().encode(setup))
        await settleWatchLinkService()
        XCTAssertNil(service.pendingConfirmRequest)
        XCTAssertTrue(transport.realtimeMessages.contains { data in
            (try? JSONDecoder().decode(LinkEnvelopeHead.self, from: data))?.kind == .setupRejected
        })
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
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchLinkServiceTests.Resume.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WatchResumeSessionStore(directoryURL: directory)
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

        // A same-revision realtime frame can supply additional actions after
        // the checkpoint has already set the score revision.
        let nextAction = DetailedScoreAction(
            type: .scoreChanged, epochMilliseconds: 3_500,
            team: .team2, scores: [1, 1]
        )
        var delta = LinkEnvelopeEncoding.checkpointEnvelope(strippedFromPhone)
        delta.payload.isDeltaActions = true
        delta.payload.detailedActions = [nextAction]
        let data = try JSONEncoder().encode(delta)
        transport.deliver(data)
        transport.deliver(data)
        await settleWatchLinkService()

        XCTAssertEqual(service.mergedDetailedActions.map(\.id), [action.id, nextAction.id])
        let acknowledgements = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: $0)
        }.filter { $0.kind == .acknowledgement && $0.correlationId == delta.messageId }
        XCTAssertEqual(acknowledgements.count, 2)

        // The same-revision correction arrives after the score-only checkpoint.
        var correction = LinkEnvelopeEncoding.checkpointEnvelope(strippedFromPhone)
        correction.payload.isDeltaActions = false
        correction.payload.removedActionIDs = [nextAction.id]
        service.receive(try JSONEncoder().encode(correction))
        service.receive(data)
        XCTAssertEqual(service.mergedDetailedActions.map(\.id), [action.id])
        XCTAssertEqual(service.latestSnapshot?.snapshot, setup.snapshot)
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
        XCTAssertEqual(WatchScoreboardRoute(linkedSetup: setup), .basketballTraining(mode: .twoPoint))
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
        XCTAssertEqual(record.basketballTrainingDetails?.count(points: 2, made: true), 1)
        XCTAssertEqual(record.basketballTrainingDetails?.count(points: 2, made: false), 1)
        let transfer = try XCTUnwrap(WatchRecordManager.shared.transferPayload(for: record))
        XCTAssertEqual(transfer.basketballTraining, state)
        XCTAssertTrue(transfer.actions.isEmpty)
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
            role: .watchFollower,
            authorityEpoch: 1,
            revision: 2,
            latestAuthoritativeSnapshot: snapshot,
            detailedActions: [],
            completedMatchIds: [],
            pendingTerminalMessageIds: []
        )
        resumeStore.save(.init(
            startedAt: now,
            scoreLine: "0/1 = 0%",
            emoji: "🏀",
            payload: .basketballTraining(mode: .free, history: []),
            link: context
        ))

        resumeStore.applyLinkedSnapshot(snapshot, context: context)
        resumeStore.reload()

        let resumed = try XCTUnwrap(resumeStore.session)
        XCTAssertEqual(resumed.scoreLine, "1/2 = 50%")
        guard case .basketballTraining(let mode, let shots, let earlierCounts) = resumed.payload else {
            return XCTFail("Expected a training resume payload")
        }
        XCTAssertEqual(mode, .free)
        XCTAssertEqual(shots.first?.points, 3)
        XCTAssertEqual(earlierCounts?.twoMiss, 1)
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

        let archery = LinkedArcheryState(
            leftName: "红方",
            rightName: "蓝方",
            leftSetPoints: 6,
            rightSetPoints: 2,
            leftArrowSum: 29,
            rightArrowSum: 25,
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
        let football11 = LinkedFootballState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 2,
            rightScore: 1,
            timer: FootballTimerStateV2(halfLengthSeconds: 2700),
            kickedOff: true,
            finished: true
        )
        let football5 = LinkedFootballState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 4,
            rightScore: 2,
            timer: FootballTimerStateV2(halfLengthSeconds: 1200),
            kickedOff: true,
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
            XCTAssertEqual(record.actions.first?.id, action.id.uuidString)
            XCTAssertEqual(record.projectConfiguration?["scoreCoreGameType"], scoreCoreType.rawValue)

            let roundTripped = try decoder.decode(
                WatchScoreboardRecord.self,
                from: try encoder.encode(record)
            )
            XCTAssertEqual(roundTripped.id, record.id)
            XCTAssertEqual(roundTripped.gameType, expectedWatchType)
        }
    }

    func testWatchLinkPersistsLinkedRecordWhenPhoneFinishesAndIsIdempotent() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let sink = RecordingWatchLinkSink()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: sink
        )
        let setup = makeWatchLinkSetup()
        transport.deliver(try JSONEncoder().encode(setup.envelope))
        await settleWatchLinkService()
        service.acceptPendingSetup()
        let handle = try XCTUnwrap(service.resumeContext?.handle)

        var finishedState = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .badminton())
        finishedState.leftPoints = 21
        finishedState.rightPoints = 15
        finishedState.leftSets = 2
        finishedState.rightSets = 0
        finishedState.finished = true
        let action = DetailedScoreAction(
            id: UUID(),
            type: .scoreChanged,
            epochMilliseconds: 1_700_000_010_000,
            team: .team1,
            scores: [21, 15],
            setScores: [2, 0]
        )
        let finishedEnvelope = LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: 1,
            kind: .matchFinished,
            sender: .phone,
            senderSequence: 3,
            sessionRevision: 2,
            sentAtEpochMilliseconds: 1_700_000_060_000,
            payload: LinkMatchFinishedPayload(
                snapshot: .rally(finishedState),
                recordId: "phone-finished-record",
                winnerSide: .left,
                manualEnd: false,
                startTimeEpochMilliseconds: 1_700_000_000_000,
                endTimeEpochMilliseconds: 1_700_000_060_000,
                durationSeconds: 60,
                totalScoreChanges: 1,
                detailedActions: [action],
                participantNames: ["甲", "乙"]
            )
        )
        let encoded = try JSONEncoder().encode(finishedEnvelope)
        sink.canPersist = false
        transport.deliver(encoded)
        await settleWatchLinkService()
        XCTAssertFalse(service.publishedFinishedMatchIds.contains(handle.matchId))
        service.exitScoreboard(sessionId: handle.sessionId)
        XCTAssertTrue(service.pendingSessionEnds.isEmpty)
        XCTAssertFalse(transport.realtimeMessages.contains { data in
            (try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: data))?.kind
                == .recordAcknowledgement
        })
        sink.canPersist = true
        transport.deliver(encoded)
        await settleWatchLinkService()
        // Duplicate delivery (e.g. realtime + transferUserInfo) must not persist twice.
        transport.deliver(encoded)
        await settleWatchLinkService()

        XCTAssertEqual(sink.ingested.count, 1)
        XCTAssertEqual(sink.ingested.first?.recordId, "phone-finished-record")
        XCTAssertEqual(sink.ingested.first?.syncState, .sent)
        XCTAssertEqual(sink.ingested.first?.actionCount, 1)

        let recordAcks = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: $0)
        }.filter { $0.kind == .recordAcknowledgement && $0.correlationId == finishedEnvelope.messageId }
        XCTAssertEqual(recordAcks.count, 2)
    }

    func testDelayedPhoneFinishPersistsAfterNewSessionAndRestart() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let previousHandler = WatchRecordManager.shared.recordTransferHandler
        let service = WatchLinkService(transport: transport, contextStore: store, outboxStore: store)
        let old = makeWatchLinkSetup().envelope
        service.receive(try JSONEncoder().encode(old))
        service.acceptPendingSetup()

        let training = LinkedScoreboardSnapshot.basketballTraining(.init(mode: .free))
        let newSetup = LinkEnvelope(
            supportsCompressedFinish: true,
            sessionId: UUID(), kind: .setupRequest, sender: .phone, senderSequence: 1,
            sessionRevision: 0, sentAtEpochMilliseconds: 3_000,
            payload: LinkedScoreboardSetup(gameType: .basketballTraining, initialSnapshot: training)
        )
        service.receive(try JSONEncoder().encode(newSetup))
        service.acceptPendingSetup()
        XCTAssertEqual(service.activeHandle, newSetup.handle)

        let records = WatchRecordManager.shared
        let recordID = "w_late_\(UUID().uuidString)"
        defer {
            _ = records.deleteRecord(id: recordID)
            records.recordTransferHandler = previousHandler
        }
        var badminton = try XCTUnwrap(old.payload.initialSnapshot?.rallyState)
        badminton.leftPoints = 21
        badminton.rightPoints = 14
        badminton.leftSets = 2
        badminton.finished = true
        let finished = LinkEnvelope(
            sessionId: old.sessionId, matchId: old.matchId, matchGeneration: old.matchGeneration,
            authorityEpoch: 1, kind: .matchFinished, sender: .phone, senderSequence: 3,
            sessionRevision: 3, sentAtEpochMilliseconds: 3_100,
            payload: LinkMatchFinishedPayload(
                snapshot: .rally(badminton), recordId: recordID, winnerSide: .left,
                startTimeEpochMilliseconds: 1_700_000_000_000, endTimeEpochMilliseconds: 1_700_000_060_000,
                durationSeconds: 60
            )
        )
        let data = try JSONEncoder().encode(finished)
        let receiver = WatchLinkTestTransport()
        let restored = WatchLinkService(transport: receiver, contextStore: store, outboxStore: store)
        restored.receive(data)
        let record = try XCTUnwrap(records.getRecord(id: recordID))
        XCTAssertEqual(record.gameType, .badminton)
        XCTAssertEqual(record.team1FinalScore, 21)
        XCTAssertEqual(records.syncState(for: recordID), .sent)
        XCTAssertEqual(restored.activeHandle, newSetup.handle)
        XCTAssertEqual(restored.resumeContext?.latestAuthoritativeSnapshot, training)
        XCTAssertFalse(restored.publishedFinishedMatchIds.contains(old.matchId))
        await settleWatchLinkService()
        let ack = try XCTUnwrap(receiver.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: $0)
        }.first { $0.kind == .recordAcknowledgement })
        XCTAssertEqual(ack.handle, old.handle)
        XCTAssertEqual(ack.correlationId, finished.messageId)

        XCTAssertTrue(records.deleteRecord(id: recordID))
        let retryTransport = WatchLinkTestTransport()
        let restarted = WatchLinkService(transport: retryTransport, contextStore: store, outboxStore: store)
        restarted.receive(data)
        XCTAssertNil(records.getRecord(id: recordID))
        await settleWatchLinkService()
        XCTAssertTrue(retryTransport.realtimeMessages.contains {
            let ack = try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: $0)
            return ack?.kind == .recordAcknowledgement && ack?.correlationId == finished.messageId
        })
    }

    func testWatchLinkPersistsLinkedRecordWhenWatchFinishesAndMarksSyncedOnRecordAck() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let sink = RecordingWatchLinkSink()
        let service = WatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: sink
        )
        let setup = makeWatchLinkSetup()
        transport.deliver(try JSONEncoder().encode(setup.envelope))
        await settleWatchLinkService()
        service.acceptPendingSetup()
        let handle = try XCTUnwrap(service.resumeContext?.handle)

        var finishedState = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .badminton())
        finishedState.leftPoints = 21
        finishedState.rightPoints = 16
        finishedState.leftSets = 2
        finishedState.rightSets = 0
        finishedState.finished = true
        let action = DetailedScoreAction(
            id: UUID(),
            type: .scoreChanged,
            epochMilliseconds: 1_700_000_010_000,
            team: .team1,
            scores: [21, 16],
            setScores: [2, 0]
        )

        service.publishMatchFinished(
            snapshot: .rally(finishedState),
            recordId: "w_watch_finished_1",
            winnerSide: .left,
            manualEnd: false,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_060),
            totalScoreChanges: 1,
            detailedActions: [action]
        )
        service.exitScoreboard(sessionId: handle.sessionId)
        XCTAssertTrue(service.terminalOutbox.contains(sessionId: handle.sessionId, matchId: handle.matchId))
        XCTAssertEqual(service.activeSessionId, handle.sessionId)
        await settleWatchLinkService()

        XCTAssertEqual(sink.ingested.count, 1)
        XCTAssertEqual(sink.ingested.first?.recordId, "w_watch_finished_1")
        XCTAssertEqual(sink.ingested.first?.syncState, .pending)
        XCTAssertEqual(transport.durableMessages.count, 1)

        let realtimeFinished = try XCTUnwrap(
            transport.realtimeMessages.compactMap {
                try? JSONDecoder().decode(LinkEnvelope<LinkMatchFinishedPayload>.self, from: $0)
            }.first { $0.kind == .matchFinished }
        )
        XCTAssertEqual(realtimeFinished.payload.recordId, "w_watch_finished_1")

        let phoneAck = LinkEnvelope(
            correlationId: realtimeFinished.messageId,
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: realtimeFinished.authorityEpoch,
            kind: .recordAcknowledgement,
            sender: .phone,
            senderSequence: 4,
            sessionRevision: realtimeFinished.sessionRevision,
            sentAtEpochMilliseconds: 1_700_000_061_000,
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: realtimeFinished.messageId,
                acknowledgedRevision: realtimeFinished.sessionRevision
            )
        )
        transport.deliver(try JSONEncoder().encode(phoneAck))
        await settleWatchLinkService()

        XCTAssertEqual(sink.markedSyncedRecordIds, ["w_watch_finished_1"])
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
        XCTAssertEqual(stored.winner, "甲")
        XCTAssertEqual(WatchRecordManager.shared.syncState(for: recordId), .sent)
    }

    private func makeWatchLinkSetup(supportsSharedEditing: Bool? = nil) -> (
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
                supportsSharedEditing: supportsSharedEditing,
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
    private(set) var markedSyncedRecordIds: [String] = []
    var canPersist = true

    @discardableResult
    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        syncState: WatchRecordSyncState
    ) -> String? {
        guard canPersist else { return nil }
        let id = payload.recordId.isEmpty ? "w_\(matchId.uuidString)" : payload.recordId
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

    func setOrThrow(_ data: Data, forKey key: String) throws {
        values[key] = data
    }

    @discardableResult
    func removeOrThrow(forKey key: String) throws -> Bool {
        let existed = values[key] != nil
        values.removeValue(forKey: key)
        return existed
    }
}

/// R3 真实入口回归（手表侧，一次同步，之后只驱动 ACK / 重连）：
/// 3000 条动作超预算 → publishSnapshot 的实时帧只带上裁剪后动作；
extension WatchLinkServiceTests {
    func testOversizedPublishSnapshotKeepsDebtAcrossAcksRetriesAndReconnect() async throws {
        let store = WatchLinkTestDataStore()
        let transport = WatchLinkTestTransport()
        let service = WatchLinkService(
            transport: transport, contextStore: store, outboxStore: store
        )
        let setup = makeWatchLinkSetup(supportsSharedEditing: true)
        transport.deliver(try JSONEncoder().encode(setup.envelope))
        await settleWatchLinkService()
        service.acceptPendingSetup()

        let allActions = (0..<3000).map { index in
            DetailedScoreAction(
                type: .scoreChanged, epochMilliseconds: 1_000 + Int64(index),
                team: .team1, scores: [index, 0], scoreChange: 1,
                operationCode: "oversize_watch_op_\(index)"
            )
        }
        // 唯一一次真实同步。
        service.publishSnapshot(setup.snapshot, detailedActions: allActions)
        await settleWatchLinkService()
        typealias SnapshotFrame = LinkEnvelope<LinkedScoreboardSetup>
        func frames() -> [SnapshotFrame] {
            transport.realtimeMessages.compactMap {
                try? JSONDecoder().decode(SnapshotFrame.self, from: $0)
            }.filter { $0.kind == .stateSnapshot }
        }
        let realtime = try XCTUnwrap(frames().last)
        XCTAssertEqual(frames().count, 1)
        let onWire = realtime.payload.detailedActions
        XCTAssertFalse(onWire.isEmpty)
        XCTAssertLessThan(onWire.count, allActions.count)

        func ack(_ envelope: LinkEnvelope<LinkedScoreboardSetup>, sequence: UInt64) {
            transport.deliver(try! JSONEncoder().encode(LinkEnvelope(
                correlationId: envelope.messageId, sessionId: realtime.sessionId,
                matchId: realtime.matchId, matchGeneration: realtime.matchGeneration,
                kind: .acknowledgement, sender: .phone, senderSequence: sequence,
                sessionRevision: envelope.sessionRevision,
                sentAtEpochMilliseconds: realtime.sentAtEpochMilliseconds + 1,
                payload: LinkAcknowledgementPayload(
                    acknowledgedMessageId: envelope.messageId,
                    acknowledgedRevision: envelope.sessionRevision
                )
            )))
        }
        func setReachable(_ reachable: Bool) {
            transport.status = WatchConnectivityStatus(
                isSupported: true, isActivated: true, isPaired: true,
                isWatchAppInstalled: true, isReachable: reachable
            )
            transport.onStatusChange?(transport.status)
        }

        // The first batch's ACK arrives after the transport became unreachable.
        setReachable(false)
        await settleWatchLinkService()
        ack(realtime, sequence: 2)
        await settleWatchLinkService()
        let remaining = allActions.count - onWire.count
        XCTAssertEqual(service.deltaActionTracker.pendingDeltaActions(of: allActions).count, remaining)
        XCTAssertEqual(frames().count, 1)

        // A duplicate ACK cannot retire the queued second batch.
        let queued = try XCTUnwrap(service.pendingAck.pending)
        XCTAssertNotEqual(queued.messageId, realtime.messageId)
        ack(realtime, sequence: 3)
        await settleWatchLinkService()
        XCTAssertEqual(service.pendingAck.pending?.messageId, queued.messageId)
        XCTAssertEqual(service.deltaActionTracker.pendingDeltaActions(of: allActions).count, remaining)

        // Reconnect immediately retries the queued batch. Each subsequent real
        // frame ACK must produce the next frame without another score update.
        setReachable(true)
        var delivered = Set(onWire.map(\.id))
        for batch in 1...40 {
            guard delivered.count < allActions.count else { break }
            for _ in 0..<100 where frames().count <= batch {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let sent = frames()
            guard sent.count > batch else {
                XCTFail("No history batch after ACK or reconnect")
                return
            }
            let next = sent[batch]
            if batch == 1 { XCTAssertEqual(next.messageId, queued.messageId) }
            XCTAssertEqual(next.sessionRevision, realtime.sessionRevision)
            XCTAssertEqual(next.payload.initialSnapshot, realtime.payload.initialSnapshot)
            XCTAssertEqual(next.payload.isDeltaActions, true)
            XCTAssertFalse(next.payload.detailedActions.isEmpty)
            for action in next.payload.detailedActions {
                XCTAssertTrue(delivered.insert(action.id).inserted)
            }
            ack(next, sequence: UInt64(batch) + 10)
            await settleWatchLinkService()
        }
        XCTAssertEqual(delivered, Set(allActions.map(\.id)))
        XCTAssertTrue(service.deltaActionTracker.pendingDeltaActions(of: allActions).isEmpty)
        XCTAssertNil(service.pendingAck.pending)

        // Clearing the action log can exceed the realtime budget even when
        // there are no additions. All removal IDs still need an ACK.
        let firstRemovalBatch = frames().count
        service.publishSnapshot(setup.snapshot, detailedActions: [])
        let expectedRemovals = Set(allActions.map(\.id))
        var removals = Set<UUID>()
        for batch in 0..<10 {
            guard removals != expectedRemovals else { break }
            let index = firstRemovalBatch + batch
            for _ in 0..<100 where frames().count <= index {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let sent = frames()
            guard sent.count > index else {
                XCTFail("No remaining removal batch after ACK")
                return
            }
            let next = sent[index]
            XCTAssertEqual(next.payload.isDeltaActions, false)
            XCTAssertTrue(next.payload.detailedActions.isEmpty)
            let wireRemovals = try XCTUnwrap(next.payload.removedActionIDs)
            XCTAssertFalse(wireRemovals.isEmpty)
            for id in wireRemovals {
                XCTAssertTrue(removals.insert(id).inserted)
            }
            ack(next, sequence: UInt64(batch) + 100)
            await settleWatchLinkService()
        }
        XCTAssertEqual(removals, expectedRemovals)
        XCTAssertTrue(service.mergedDetailedActions.isEmpty)
        XCTAssertNil(service.pendingAck.pending)
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
    var supportsFileTransfer = true
    var onReceivedFile: (@Sendable (Data, [String: Any]) -> Void)?
    var transferredFiles: [(data: Data, metadata: [String: Any])] = []

    func transferFileData(_ data: Data, metadata: [String: Any]) throws {
        transferredFiles.append((data, metadata))
    }

    func transferCommonNameMutations(_ data: Data) throws {}
    func transferCommonNameMutationAcknowledgement(_ data: Data) throws {}
    func requestPendingWatchRecords() {}
    func sendPendingWatchRecords(_ datas: [Data]) {}
    func clearPendingWatchRecords(ids: [String]) {}

    func deliver(_ data: Data) {
        onReceive?(data)
    }
}
