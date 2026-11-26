import XCTest
import LinkCore
import LinkSync
import RecordCore
import ScoreCore
import SwiftUI
import UIKit
@testable import jifen

@MainActor
final class PhoneWatchLinkServiceTests: XCTestCase {
    func testPhoneAndWatchScoresFromSameBaseMergeAndDuplicateReturnsOriginalCommit() async throws {
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport)
        let handle = try await startBadminton(on: service, transport: transport)
        let seed = try XCTUnwrap(service.latestRemoteSnapshot?.snapshot.rallyState)
        let time = service.nowMs()
        let watchOp = operation(.rally(.pointWon(.right)), handle: handle, sequence: 1, at: time)
        let phone = try service.submitLocalIntent(.rally(.pointWon(.left)), sessionId: handle.sessionId, at: time)
        XCTAssertEqual(phone.op.baseRevision, watchOp.baseRevision)
        XCTAssertEqual(phone.committedRevision, 1)

        let submit = try watchFrame(.intentSubmit, handle: handle, sequence: 1, payload: watchOp)
        transport.deliver(submit)
        await waitUntil { self.commits(from: transport, opId: watchOp.opId).count == 1 }
        let committed = try XCTUnwrap(commits(from: transport, opId: watchOp.opId).first)
        XCTAssertEqual(committed.outcome, .accepted)
        XCTAssertEqual(committed.committedRevision, 2)
        let confirmed = try XCTUnwrap(service.latestRemoteSnapshot)
        XCTAssertEqual(confirmed.snapshot.rallyState?.leftPoints, 1)
        XCTAssertEqual(confirmed.snapshot.rallyState?.rightPoints, 1)
        XCTAssertEqual(confirmed.detailedActions.count, 2)
        let afterPhone = RallyMatchReducer().reduce(
            state: seed, intent: .pointWon(.left), at: phone.effectiveEpochMilliseconds
        ).state
        let replayed = RallyMatchReducer().reduce(
            state: afterPhone, intent: .pointWon(.right), at: committed.effectiveEpochMilliseconds
        ).state
        XCTAssertEqual(confirmed.snapshot, .rally(replayed))
        XCTAssertEqual(committed.stateHash, try LinkStateHash.snapshot(.rally(replayed)))

        for _ in 0..<3 { transport.deliver(submit) }
        await waitUntil { self.commits(from: transport, opId: watchOp.opId).count == 4 }
        XCTAssertEqual(commits(from: transport, opId: watchOp.opId), Array(repeating: committed, count: 4))
        XCTAssertEqual(service.latestRemoteSnapshot, confirmed)
    }

    func testRolloverAndRestartRejectOldOfflineScoresAndRetainOneFinishedRecord() async throws {
        let context = InMemoryLinkDataStore()
        let directory = makeIntentDirectory()
        let sink = RecordingPhoneLinkSink()
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport, context: context, sink: sink, directory: directory)
        let oldHandle = try await startBadminton(on: service, transport: transport)
        let score = try service.submitLocalIntent(.rally(.pointWon(.left)), sessionId: oldHandle.sessionId)
        let finish = try service.submitLocalIntent(.finish, sessionId: oldHandle.sessionId)
        let recordId = "w_\(oldHandle.matchId.uuidString)"
        XCTAssertEqual(score.committedRevision, 1)
        XCTAssertEqual(finish.outcome, .accepted)
        XCTAssertEqual(service.finishedRecordId, recordId)
        XCTAssertEqual(sink.matchIds, [oldHandle.matchId])
        XCTAssertEqual(sink.recorded.first?.recordId, recordId)
        XCTAssertEqual(sink.recorded.first?.snapshot.rallyState?.leftPoints, 1)

        try service.startNextIntentMatch(sessionId: oldHandle.sessionId)
        let newHandle = try XCTUnwrap(service.linkedResumeDescriptor?.handle)
        XCTAssertEqual(newHandle.sessionId, oldHandle.sessionId)
        XCTAssertEqual(newHandle.matchGeneration, oldHandle.matchGeneration + 1)
        XCTAssertNotEqual(newHandle.matchId, oldHandle.matchId)

        let reconnected = FakeWatchLinkTransport()
        let restored = makeService(transport: reconnected, context: context, sink: sink, directory: directory)
        XCTAssertEqual(restored.linkedResumeDescriptor?.handle, newHandle)
        let offline = [
            operation(.rally(.pointWon(.left)), handle: oldHandle, sequence: 1, at: score.effectiveEpochMilliseconds),
            operation(.rally(.pointWon(.right)), handle: oldHandle, sequence: 2, at: score.effectiveEpochMilliseconds),
            operation(.finish, handle: oldHandle, sequence: 3, at: score.effectiveEpochMilliseconds),
        ]
        for op in offline {
            reconnected.deliver(try watchFrame(.intentSubmit, handle: oldHandle, sequence: op.clientSeq, payload: op))
        }
        await waitUntil { offline.allSatisfy { !self.commits(from: reconnected, opId: $0.opId).isEmpty } }
        let results = try offline.map { try XCTUnwrap(commits(from: reconnected, opId: $0.opId).first) }
        XCTAssertEqual(results.map(\.committedRevision), [4, 5, 6])
        for result in results {
            XCTAssertEqual(result.outcome, .rejected)
            XCTAssertEqual(result.rejectionReason, LinkOperationRejectionReason.matchFinished.rawValue)
            XCTAssertEqual(result.stateHash, finish.stateHash)
        }
        let first = try XCTUnwrap(offline.first)
        reconnected.deliver(try watchFrame(.intentSubmit, handle: oldHandle, sequence: 4, payload: first))
        await waitUntil { self.commits(from: reconnected, opId: first.opId).count == 2 }
        XCTAssertEqual(commits(from: reconnected, opId: first.opId), [results[0], results[0]])

        let resync = LinkIntentRecoveryRequest(confirmedRevision: 0, pendingOperationIds: offline.map(\.opId))
        reconnected.deliver(try watchFrame(.resyncRequest, handle: oldHandle, sequence: 5, payload: resync))
        await waitUntil {
            !self.frames(.intentCheckpoint, from: reconnected, as: LinkIntentRecoveryPayload.self).isEmpty
        }
        let repaired = try XCTUnwrap(frames(.intentCheckpoint, from: reconnected, as: LinkIntentRecoveryPayload.self).last)
        XCTAssertEqual(repaired.handle, oldHandle)
        XCTAssertEqual(repaired.payload.checkpoint.watchResults, results.map(LinkProcessedOperation.init))
        XCTAssertEqual(repaired.payload.finishedPayload?.recordId, recordId)
        XCTAssertEqual(repaired.payload.checkpoint.snapshot, sink.recorded.first?.snapshot)
        XCTAssertEqual(repaired.payload.nextMatchHandle, newHandle)
        XCTAssertEqual(restored.linkedResumeDescriptor?.handle, newHandle)
        XCTAssertEqual(restored.linkedResumeDescriptor?.revision, 0)
        XCTAssertEqual(restored.linkedResumeDescriptor?.snapshot.rallyState?.leftPoints, 0)
        XCTAssertEqual(restored.linkedResumeDescriptor?.snapshot.rallyState?.rightPoints, 0)
        XCTAssertEqual(sink.matchIds, [oldHandle.matchId])
    }

    func testFinishRepairsFailedRecordProjectionBeforeReturningDurableReceipt() async throws {
        let sink = RecordingPhoneLinkSink()
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport, sink: sink)
        let handle = try await startBadminton(on: service, transport: transport)
        _ = try service.submitLocalIntent(.rally(.pointWon(.left)), sessionId: handle.sessionId)
        let opId = UUID()
        let time = service.nowMs()
        sink.failNextIngest = true
        XCTAssertThrowsError(try service.submitLocalIntent(.finish, sessionId: handle.sessionId, opId: opId, at: time))
        XCTAssertNil(service.finishedRecordId)
        await settleMainQueue()
        XCTAssertTrue(commits(from: transport, opId: opId).isEmpty)
        XCTAssertTrue(sink.matchIds.isEmpty)

        let receipt = try service.submitLocalIntent(.finish, sessionId: handle.sessionId, opId: opId, at: time)
        let retry = try service.submitLocalIntent(.finish, sessionId: handle.sessionId, opId: opId, at: time)
        XCTAssertEqual(receipt, retry)
        XCTAssertEqual(receipt.outcome, .accepted)
        XCTAssertEqual(receipt.committedRevision, 2)
        XCTAssertEqual(sink.matchIds, [handle.matchId])
        XCTAssertEqual(sink.recorded.first?.snapshot.rallyState?.leftPoints, 1)
        await waitUntil { self.commits(from: transport, opId: opId).count == 2 }
        XCTAssertEqual(commits(from: transport, opId: opId), [receipt, receipt])
    }

    func testRestoresConfirmedSnapshotAndActionsAfterProcessRestart() async throws {
        let context = InMemoryLinkDataStore()
        let directory = makeIntentDirectory()
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport, context: context, directory: directory)
        let handle = try await startBadminton(on: service, transport: transport)
        _ = try service.submitLocalIntent(.rally(.pointWon(.right)), sessionId: handle.sessionId)
        let confirmed = try XCTUnwrap(service.latestRemoteSnapshot)
        let restored = makeService(transport: FakeWatchLinkTransport(), context: context, directory: directory)
        XCTAssertEqual(restored.linkedResumeDescriptor?.handle, handle)
        XCTAssertEqual(restored.linkedResumeDescriptor?.revision, 1)
        XCTAssertEqual(restored.latestRemoteSnapshot, confirmed)
    }

    func testForegroundStatusRefreshCoalescesOverlappingQueries() async throws {
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport)
        let handle = try await startBadminton(on: service, transport: transport)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await waitUntil {
            service.statusContinuations.count >= 2
                && self.frames(.statusQuery, from: transport, as: EmptyLinkPayload.self).contains { $0.handle == handle }
        }
        let queries = frames(.statusQuery, from: transport, as: EmptyLinkPayload.self).filter { $0.handle == handle }
        let query = try XCTUnwrap(queries.first)
        XCTAssertEqual(queries.count, 1)
        XCTAssertGreaterThanOrEqual(service.statusContinuations.count, 2)
        XCTAssertEqual(service.pendingStatusCorrelationId, query.messageId)
        service.handleIncoming(try watchFrame(
            .statusResponse, handle: handle, sequence: 1, correlationId: query.messageId,
            payload: LinkStatusPayload(revision: query.sessionRevision)
        ))
        XCTAssertNil(service.pendingStatusCorrelationId)
        XCTAssertTrue(service.statusContinuations.isEmpty)
    }

    func testResumeDescriptorIsNilUntilHandshakeAcceptance() async throws {
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport)
        let handle = try await startBadminton(on: service, transport: transport, expectPendingDescriptor: true)
        XCTAssertEqual(service.linkedResumeDescriptor?.handle, handle)
    }

    func testSetupAcceptanceWithoutSharedIntentCapabilityIsRejected() async throws {
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport)
        let initial = RallyMatchEngine.initial(leftName: "Alice", rightName: "Bob", rules: .badminton())
        let setup = Task { try await service.startInteractiveOnWatch(gameType: .badminton, state: initial) }
        defer { setup.cancel() }
        await waitUntil { !self.frames(.setupRequest, from: transport, as: LinkedScoreboardSetup.self).isEmpty }
        let request = try XCTUnwrap(frames(.setupRequest, from: transport, as: LinkedScoreboardSetup.self).last)
        transport.deliver(try JSONEncoder().encode(LinkEnvelope(
            capabilities: LinkProtocol.capabilities.subtracting([.sharedIntentSync]),
            correlationId: request.messageId, sessionId: request.sessionId, matchId: request.matchId,
            matchGeneration: request.matchGeneration, kind: .setupAccepted, sender: .watch,
            senderSequence: 1, sessionRevision: 0, sentAtEpochMilliseconds: request.sentAtEpochMilliseconds,
            payload: EmptyLinkPayload()
        )))
        do {
            _ = try await setup.value
            XCTFail("Expected missing shared intent capability to abort setup")
        } catch let failure as PhoneWatchLinkService.InteractiveStartError {
            guard case .setupRejected = failure else {
                return XCTFail("Unexpected setup failure: \(failure)")
            }
        }
        XCTAssertEqual(service.lastSetupRejectionReason, .incompatibleProtocol)
        XCTAssertNil(service.linkedResumeDescriptor)
    }

    func testExitOnlyRetiresFinishedLinkedMatch() async throws {
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport)
        let handle = try await startBadminton(on: service, transport: transport)
        service.leaveSessionIfMatchFinished(handle.sessionId)
        XCTAssertEqual(service.linkedResumeDescriptor?.handle, handle)
        _ = try service.submitLocalIntent(.finish, sessionId: handle.sessionId)
        service.leaveSessionIfMatchFinished(handle.sessionId)
        await waitUntil {
            service.linkedResumeDescriptor == nil
                && !self.frames(.sessionLeft, from: transport, as: EmptyLinkPayload.self).isEmpty
        }
        XCTAssertNil(service.linkedResumeDescriptor)
        XCTAssertEqual(frames(.sessionLeft, from: transport, as: EmptyLinkPayload.self).last?.handle, handle)
    }

    func testWatchCanRequestCommonNamesBeforeLinking() async throws {
        let transport = FakeWatchLinkTransport()
        let service = makeService(transport: transport)
        let contextKey = WatchConnectivityTransport.commonNamesContextKey
        transport.receivedApplicationContext.removeValue(forKey: contextKey)
        let handle = LinkedMatchHandle(sessionId: UUID())
        transport.deliver(try watchFrame(
            .commonNamesSyncRequest, handle: handle, sequence: 1, payload: CommonNamesSyncRequestPayload()
        ))
        await waitUntil { transport.receivedApplicationContext[contextKey] != nil }
        let names = CommonNamesSyncSnapshot.fromApplicationContextValue(transport.receivedApplicationContext[contextKey])
        XCTAssertEqual(names?.schemaVersion, CommonNamesSyncSnapshot.currentSchemaVersion)
        XCTAssertNil(service.linkedResumeDescriptor)
    }

    private func startBadminton(
        on service: PhoneWatchLinkService,
        transport: FakeWatchLinkTransport,
        expectPendingDescriptor: Bool = false
    ) async throws -> LinkedMatchHandle {
        let initial = RallyMatchEngine.initial(leftName: "Alice", rightName: "Bob", rules: .badminton())
        let setup = Task {
            try await service.startInteractiveOnWatch(gameType: .badminton, state: initial, participantNames: ["Alice", "Bob"])
        }
        defer { setup.cancel() }
        await waitUntil { !self.frames(.setupRequest, from: transport, as: LinkedScoreboardSetup.self).isEmpty }
        let request = try XCTUnwrap(frames(.setupRequest, from: transport, as: LinkedScoreboardSetup.self).last)
        XCTAssertTrue(request.capabilities.contains(.sharedIntentSync))
        if expectPendingDescriptor { XCTAssertNil(service.linkedResumeDescriptor) }
        transport.deliver(try watchFrame(
            .setupAccepted, handle: request.handle, sequence: 1,
            correlationId: request.messageId, payload: EmptyLinkPayload()
        ))
        let sessionId = try await setup.value
        XCTAssertEqual(sessionId, request.sessionId)
        XCTAssertTrue(service.canEditLinkedMatch)
        return request.handle
    }

    private func makeIntentDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phone-link-test-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return directory
    }

    private func makeService(
        transport: FakeWatchLinkTransport,
        context: InMemoryLinkDataStore = InMemoryLinkDataStore(),
        sink: RecordingPhoneLinkSink? = nil,
        directory: URL? = nil
    ) -> PhoneWatchLinkService {
        PhoneWatchLinkService(
            transport: transport, contextStore: context, outboxStore: context, recordSink: sink ?? RecordingPhoneLinkSink(),
            intentDirectoryURL: directory ?? makeIntentDirectory()
        )
    }

    private func operation(
        _ intent: LinkedScoreboardIntent, handle: LinkedMatchHandle, sequence: UInt64, at time: Int64
    ) -> LinkOperation {
        LinkOperation(
            opId: UUID(), handle: handle, origin: .watch, clientSeq: sequence,
            baseRevision: 0, createdAtEpochMilliseconds: time, intent: intent
        )
    }

    private func watchFrame<Payload: Codable & Sendable>(
        _ kind: LinkMessageKind, handle: LinkedMatchHandle, sequence: UInt64,
        correlationId: UUID? = nil, payload: Payload
    ) throws -> Data {
        try JSONEncoder().encode(LinkEnvelope(
            correlationId: correlationId, sessionId: handle.sessionId, matchId: handle.matchId,
            matchGeneration: handle.matchGeneration, kind: kind, sender: .watch, senderSequence: sequence,
            sessionRevision: 0, sentAtEpochMilliseconds: 1_795_000_000_000, payload: payload
        ))
    }

    private func frames<Payload: Codable & Sendable>(
        _ kind: LinkMessageKind, from transport: FakeWatchLinkTransport, as _: Payload.Type
    ) -> [LinkEnvelope<Payload>] {
        transport.realtimeMessages
            .compactMap { try? JSONDecoder().decode(LinkEnvelope<Payload>.self, from: $0) }
            .filter { $0.kind == kind }
    }

    private func commits(from transport: FakeWatchLinkTransport, opId: UUID) -> [LinkOperationCommitPayload] {
        frames(.intentCommit, from: transport, as: LinkOperationCommitPayload.self)
            .map(\.payload).filter { $0.op.opId == opId }
    }

    func testStartupRecordLoadersRunOnlyWhenRequestedAndCoalesce() async {
        let scoreboardCounter = LockedInvocationCounter()
        let scoreboardVM = ScoreboardRecordsViewModel {
            scoreboardCounter.increment()
            return []
        }

        XCTAssertFalse(scoreboardVM.hasLoaded)
        scoreboardVM.ensureLoaded()
        scoreboardVM.ensureLoaded()
        // 冷启动的模拟器上主队列可能积压（Firebase 初始化等），轮询窗口放宽到 2s。
        for _ in 0..<200 where !scoreboardVM.hasLoaded {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(scoreboardVM.hasLoaded)
        XCTAssertEqual(scoreboardCounter.value, 1)

        var timerLoadCount = 0
        let timerVM = TimerRecordsViewModel {
            timerLoadCount += 1
            return []
        }
        XCTAssertFalse(timerVM.hasLoaded)
        timerVM.ensureLoaded()
        timerVM.ensureLoaded()
        // 与 scoreboard 段一致：加载在后台队列 + 主线程回填，必须轮询等待。
        for _ in 0..<200 where !timerVM.hasLoaded {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(timerVM.hasLoaded)
        XCTAssertEqual(timerLoadCount, 1)
    }


    func testRecordSummaryCacheRefreshesAfterExternalMutationNotification() async {
        let notificationCenter = NotificationCenter()
        let counter = LockedInvocationCounter()
        let viewModel = ScoreboardRecordsViewModel(
            summaryLoader: {
                counter.increment()
                return []
            },
            notificationCenter: notificationCenter
        )

        viewModel.ensureLoaded()
        for _ in 0..<50 where !viewModel.hasLoaded {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertEqual(counter.value, 1)

        notificationCenter.post(name: .scoreboardRecordsDidChange, object: nil)
        for _ in 0..<50 where counter.value < 2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(counter.value, 2)
    }


    func testQuickStartConfigurationDecodesOnce() throws {
        let suiteName = "QuickStartConfigManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persisted = QuickStartConfig(primarySport: .tennis, secondarySport: .boxing)
        defaults.set(try JSONEncoder().encode(persisted), forKey: "quick-start-test")

        let manager = QuickStartConfigManager(
            userDefaults: defaults,
            configKey: "quick-start-test"
        )
        manager.configureDefaultsIfNeeded(isLargeScreen: true, is2in1: false)
        manager.configureDefaultsIfNeeded(isLargeScreen: false, is2in1: false)

        XCTAssertEqual(manager.quickStartConfig, persisted)
        XCTAssertEqual(manager.configurationReadCount, 1)
    }


    func testLegacyTwoSlotQuickStartConfigurationDefaultsTertiaryToTennis() throws {
        let data = Data(#"{"primarySport":"tennis","secondarySport":"boxing"}"#.utf8)

        let decoded = try JSONDecoder().decode(QuickStartConfig.self, from: data)

        XCTAssertEqual(decoded.primarySport, .tennis)
        XCTAssertEqual(decoded.secondarySport, .boxing)
        XCTAssertEqual(decoded.tertiarySport, .tennis)
    }


    func testQuickStartNormalizesLegacyPingPongIdentifiersToTableTennis() throws {
        let legacy = Data(
            #"{"primarySport":"pingpong","secondarySport":"table_tennis"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(QuickStartConfig.self, from: legacy)
        XCTAssertEqual(decoded.primarySport, .pingpong)
        XCTAssertEqual(decoded.secondarySport, .pingpong)
        XCTAssertEqual(decoded.tertiarySport, .tennis)

        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: String]
        )
        XCTAssertEqual(encoded["primarySport"], "table_tennis")
        XCTAssertEqual(encoded["secondarySport"], "table_tennis")
    }


    func testQuickStartDefaultsMatchAndroidAndHarmony() {
        for config in [
            QuickStartConfig.defaultPhoneConfig,
            .defaultTabletConfig,
            .default2In1Config
        ] {
            XCTAssertEqual(config.primarySport, .basketball)
            XCTAssertEqual(config.secondarySport, .badminton)
            XCTAssertEqual(config.tertiarySport, .tennis)
        }
    }


    func testQuickStartSelectableGamesComeFromCatalogAndExcludeStopwatch() {
        XCTAssertEqual(
            QuickStartConfig.selectableGameTypes,
            GameCatalog.quickStartSelectableGameTypes.filter { $0 != .stopwatch }
        )
        XCTAssertFalse(QuickStartConfig.selectableGameTypes.contains(.stopwatch))
    }


    func testQuickStartLayoutUsesTwoSlotsForAllWindowSizes() {
        for sizeClass in [UserInterfaceSizeClass?.none, .compact, .regular] {
            XCTAssertFalse(
                QuickStartLayoutPolicy.showsTertiarySlot(horizontalSizeClass: sizeClass, isPad: true),
                "iPad \(String(describing: sizeClass)) 不应显示第三槽"
            )
            XCTAssertFalse(
                QuickStartLayoutPolicy.showsTertiarySlot(horizontalSizeClass: sizeClass, isPad: false),
                "iPhone \(String(describing: sizeClass)) 不应显示第三槽"
            )
        }
    }


    func testPhoneCanStartExactlyTheSupportedWatchScoreboards() {
        let supported = Set(
            ScoreCore.GameType.allCases.filter(PhoneWatchLinkService.phoneInteractiveStartSupported)
        )
        let expected: Set<ScoreCore.GameType> = [
            .pingpong, .pingpongDoubles,
            .badminton, .badmintonDoubles,
            .tennis, .tennisDoubles,
            .pickleball, .pickleballDoubles,
            .shuttlecock, .squash,
            .foosball, .foosballDoubles,
            .football, .football5v5,
            .archeryDual, .eightBall, .nineBall, .snooker, .basketballTraining
        ]

        XCTAssertEqual(supported, expected)
    }


    func testWatchLinkUIProjectGateMatchesServiceWhitelist() {
        let serviceSupported = Set(
            ScoreCore.GameType.allCases.filter(PhoneWatchLinkService.phoneInteractiveStartSupported)
        )
        for gameType in serviceSupported {
            guard let appType = jifen.GameType(scoreCoreGameType: gameType) else {
                XCTFail("服务白名单项目 \(gameType.rawValue) 缺少 App GameType 映射")
                continue
            }
            XCTAssertTrue(
                AppFeatureFlags.isWatchLinkSupportedProject(appType),
                "UI 项目开关必须放行 \(appType.rawValue)（服务层支持 \(gameType.rawValue)）"
            )
        }
        for appType in jifen.GameType.allCases where AppFeatureFlags.isWatchLinkSupportedProject(appType) {
            let serviceTypes = ScoreCore.GameType.allCases
                .filter { jifen.GameType(scoreCoreGameType: $0) == appType }
            let backed = serviceTypes.contains { PhoneWatchLinkService.phoneInteractiveStartSupported($0) }
            XCTAssertTrue(
                backed,
                "UI 项目开关放行了 \(appType.rawValue)，但服务层白名单不支持其任何 ScoreCore 类型"
            )
        }
    }


    func testCompactQuickStartSavePreservesTertiaryAndRegularSaveUpdatesIt() async throws {
        let suiteName = "QuickStartConfigManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "quick-start-three-slot-test"
        let initial = QuickStartConfig(
            primarySport: .basketball,
            secondarySport: .badminton,
            tertiarySport: .tennis
        )
        defaults.set(try JSONEncoder().encode(initial), forKey: key)
        let manager = QuickStartConfigManager(userDefaults: defaults, configKey: key)

        try await manager.setSports(primary: .football, secondary: .chess, tertiary: nil)
        XCTAssertEqual(manager.quickStartConfig.primarySport, .football)
        XCTAssertEqual(manager.quickStartConfig.secondarySport, .chess)
        XCTAssertEqual(manager.quickStartConfig.tertiarySport, .tennis)

        try await manager.setSports(primary: .football, secondary: .chess, tertiary: .boxing)
        XCTAssertEqual(manager.quickStartConfig.tertiarySport, .boxing)
        let storedData = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertEqual(
            try JSONDecoder().decode(QuickStartConfig.self, from: storedData),
            manager.quickStartConfig
        )
    }


    func testAnyCodableEncodesFixedWidthIntegersAndRoundTrips() throws {
        let payload: [String: AnyCodable] = [
            "int64": AnyCodable(Int64(1_795_525_320_665)),
            "int32": AnyCodable(Int32(42)),
            "uint64": AnyCodable(UInt64(99)),
            "float": AnyCodable(Float(1.5)),
            "int": AnyCodable(7)
        ]

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["int64"]?.value as? Int, 1_795_525_320_665)
        XCTAssertEqual(decoded["int32"]?.value as? Int, 42)
        XCTAssertEqual(decoded["uint64"]?.value as? Int, 99)
        XCTAssertEqual(decoded["int"]?.value as? Int, 7)
        XCTAssertEqual(decoded["float"]?.value as? Double ?? 0, 1.5, accuracy: 0.001)
    }


    func testStandaloneTrainingAcknowledgesOriginalWatchIDAfterSaving() throws {
        let watchID = "watch-basketballTraining-\(UUID().uuidString)"
        let phoneID = "w_\(watchID)"
        defer { _ = ScoreboardRecordManager.shared.deleteRecord(phoneID) }
        let transport = FakeWatchLinkTransport()
        let store = InMemoryLinkDataStore()
        let service = PhoneWatchLinkService(transport: transport, contextStore: store, outboxStore: store, intentDirectoryURL: makeIntentDirectory())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = WatchRecordTransferPayload(
            id: watchID, kind: .sport(.basketballTraining), source: .watchLocal,
            startEpochMilliseconds: 1_700_000_000_000, endEpochMilliseconds: 1_700_000_001_000,
            durationSeconds: 1, team1Name: "Miss", team2Name: "Made",
            team1FinalScore: 2, team2FinalScore: 1,
            detailedActions: [.init(type: .matchStarted, operationCode: "training_start")],
            totalScoreChanges: 3,
            basketballTraining: .init(
                mode: .fixed3, startTime: start,
                shots: [.init(points: 3, made: true, timestamp: start)],
                earlierCounts: .init(threeMiss: 2), finished: true
            )
        )
        let data = try JSONEncoder().encode(payload)
        service.receivePendingWatchRecords([data])
        service.handleWatchRecordTransfer(data)

        XCTAssertEqual(service.lastSyncedWatchRecordId, phoneID)
        XCTAssertEqual(transport.clearedWatchRecordIDBatches, [[watchID], [watchID]])
        let record = try XCTUnwrap(ScoreboardRecordManager.shared.getRecordById(phoneID))
        XCTAssertEqual(record.team1FinalScore, 2)
        XCTAssertEqual(record.team2FinalScore, 1)
        XCTAssertEqual(record.totalScoreChanges, 3)
        XCTAssertNil(record.team1SetScore)
        XCTAssertEqual(record.extraData?["threePointMiss"]?.value as? Int, 2)
        XCTAssertEqual(record.extraData?["gameMode"]?.value as? String, "3pt")
        XCTAssertEqual(record.detailedActions?.compactMap(\.operationCode), [
            "training_3pt_made", "training_rate_33"
        ])
        let snapshot = try XCTUnwrap(record.stateSnapshot)
        let resume = try JSONDecoder().decode(ShotTrainingResumeState.self, from: snapshot)
        XCTAssertEqual(resume.mode.rawValue, "fixed_3")
        XCTAssertEqual(resume.earlierCounts?.threeMiss, 2)
        XCTAssertEqual(resume.shots.map(\.points), [3])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        let shots = try XCTUnwrap(json["shots"] as? [[String: Any]])
        XCTAssertNotNil((shots.first?["id"] as? String).flatMap(UUID.init(uuidString:)))
    }


    func testCanonicalWatchRecordPreservesTypedWinnerWhenNamesMatch() throws {
        let canonical = CanonicalMatchRecord(
            id: "same-name",
            kind: .sport(.badminton),
            source: .watchLocal,
            startEpochMilliseconds: 1_700_000_000_000,
            endEpochMilliseconds: 1_700_000_010_000,
            durationSeconds: 10,
            team1Name: "相同队名",
            team2Name: "相同队名",
            team1FinalScore: 8,
            team2FinalScore: 11,
            winnerIdentity: .team(.team1)
        )
        let record = try WatchCanonicalRecordAdapter.toScoreboardRecord(canonical)
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ScoreboardRecord.self, from: encoded)
        XCTAssertEqual(decoded.id, "w_same-name")
        XCTAssertEqual(decoded.winner, "team_1")
        XCTAssertEqual(decoded.winnerIdentity, .team(.team1))
    }


    func testWatchStandaloneRecordIngestorEncodesAndPersistsAllStandaloneWatchSports() throws {
        struct StandaloneCase {
            let rawGameType: String
            let expectedAppType: jifen.GameType
            let team1Score: Int
            let team2Score: Int
            let team1Sets: Int
            let team2Sets: Int
            let participants: [RecordParticipantScore]?
            let config: [String: String]?
            let expectNilSetScores: Bool
        }

        let cases: [StandaloneCase] = [
            .init(rawGameType: "pingpong", expectedAppType: .pingpong, team1Score: 11, team2Score: 8, team1Sets: 2, team2Sets: 0, participants: nil, config: ["scoreCoreGameType": "pingpong"], expectNilSetScores: false),
            .init(rawGameType: "pingpong_doubles", expectedAppType: .pingpong, team1Score: 11, team2Score: 9, team1Sets: 2, team2Sets: 1, participants: [.init(name: "甲", score: 0), .init(name: "乙", score: 0), .init(name: "丙", score: 0), .init(name: "丁", score: 0)], config: ["scoreCoreGameType": "pingpong_doubles", "isDoubles": "true"], expectNilSetScores: false),
            .init(rawGameType: "badminton", expectedAppType: .badminton, team1Score: 21, team2Score: 17, team1Sets: 2, team2Sets: 0, participants: nil, config: ["scoreCoreGameType": "badminton"], expectNilSetScores: false),
            .init(rawGameType: "badminton_doubles", expectedAppType: .badminton, team1Score: 21, team2Score: 19, team1Sets: 2, team2Sets: 1, participants: [.init(name: "甲", score: 0), .init(name: "乙", score: 0), .init(name: "丙", score: 0), .init(name: "丁", score: 0)], config: ["scoreCoreGameType": "badminton_doubles", "isDoubles": "true"], expectNilSetScores: false),
            .init(rawGameType: "tennis", expectedAppType: .tennis, team1Score: 6, team2Score: 4, team1Sets: 2, team2Sets: 0, participants: nil, config: ["scoreCoreGameType": "tennis", "setScoringMode": "standard"], expectNilSetScores: false),
            .init(rawGameType: "tennis", expectedAppType: .tennis, team1Score: 7, team2Score: 5, team1Sets: 0, team2Sets: 0, participants: nil, config: ["scoreCoreGameType": "tennis", "setScoringMode": "tiebreak_only"], expectNilSetScores: true),
            .init(rawGameType: "tennis_doubles", expectedAppType: .tennis, team1Score: 6, team2Score: 3, team1Sets: 2, team2Sets: 0, participants: [.init(name: "甲", score: 0), .init(name: "乙", score: 0), .init(name: "丙", score: 0), .init(name: "丁", score: 0)], config: ["scoreCoreGameType": "tennis_doubles", "isDoubles": "true"], expectNilSetScores: false),
            .init(rawGameType: "pickleball", expectedAppType: .pickleball, team1Score: 11, team2Score: 7, team1Sets: 2, team2Sets: 0, participants: nil, config: ["scoreCoreGameType": "pickleball"], expectNilSetScores: false),
            .init(rawGameType: "pickleball_doubles", expectedAppType: .pickleball, team1Score: 11, team2Score: 6, team1Sets: 2, team2Sets: 0, participants: [.init(name: "甲", score: 0), .init(name: "乙", score: 0), .init(name: "丙", score: 0), .init(name: "丁", score: 0)], config: ["scoreCoreGameType": "pickleball_doubles", "isDoubles": "true"], expectNilSetScores: false),
            .init(rawGameType: "shuttlecock", expectedAppType: .shuttlecock, team1Score: 21, team2Score: 15, team1Sets: 2, team2Sets: 0, participants: nil, config: ["scoreCoreGameType": "shuttlecock"], expectNilSetScores: false),
            .init(rawGameType: "squash", expectedAppType: .squash, team1Score: 11, team2Score: 8, team1Sets: 3, team2Sets: 1, participants: nil, config: ["scoreCoreGameType": "squash"], expectNilSetScores: false),
            .init(rawGameType: "foosball", expectedAppType: .foosball, team1Score: 5, team2Score: 3, team1Sets: 2, team2Sets: 0, participants: nil, config: ["scoreCoreGameType": "foosball"], expectNilSetScores: false),
            .init(rawGameType: "foosball_doubles", expectedAppType: .foosball, team1Score: 5, team2Score: 4, team1Sets: 2, team2Sets: 1, participants: [.init(name: "甲", score: 0), .init(name: "乙", score: 0), .init(name: "丙", score: 0), .init(name: "丁", score: 0)], config: ["scoreCoreGameType": "foosball_doubles", "isDoubles": "true"], expectNilSetScores: false),
            .init(rawGameType: "archery", expectedAppType: .archery, team1Score: 28, team2Score: 25, team1Sets: 6, team2Sets: 2, participants: [.init(name: "红方", score: 6), .init(name: "蓝方", score: 2)], config: nil, expectNilSetScores: false),
            .init(rawGameType: "eight_ball", expectedAppType: .eightBall, team1Score: 5, team2Score: 3, team1Sets: 5, team2Sets: 3, participants: nil, config: ["targetRacks": "5"], expectNilSetScores: false),
            .init(rawGameType: "nine_ball", expectedAppType: .nineBall, team1Score: 10, team2Score: 6, team1Sets: 10, team2Sets: 6, participants: [.init(name: "甲", score: 10), .init(name: "乙", score: 6), .init(name: "丙", score: 4)], config: ["playerCount": "3"], expectNilSetScores: false),
            .init(rawGameType: "snooker", expectedAppType: .snooker, team1Score: 74, team2Score: 31, team1Sets: 3, team2Sets: 1, participants: nil, config: ["maxFrames": "5"], expectNilSetScores: false),
            .init(rawGameType: "football", expectedAppType: .football, team1Score: 2, team2Score: 1, team1Sets: 0, team2Sets: 0, participants: nil, config: ["footballHalfLengthSeconds": "2700"], expectNilSetScores: true),
            .init(rawGameType: "football_5v5", expectedAppType: .football5v5, team1Score: 4, team2Score: 2, team1Sets: 0, team2Sets: 0, participants: nil, config: ["footballHalfLengthSeconds": "1200"], expectNilSetScores: true)
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var savedIDs: [String] = []
        defer {
            for id in savedIDs {
                ScoreboardRecordManager.shared.deleteRecord(id)
            }
        }

        for (index, item) in cases.enumerated() {
            let recordId = "w_test_standalone_\(index)_\(UUID().uuidString)"
            let action = DetailedScoreAction(
                id: UUID(),
                type: .scoreChanged,
                epochMilliseconds: 1_700_000_005_000,
                team: .team1,
                scores: [item.team1Score, item.team2Score],
                setScores: [item.team1Sets, item.team2Sets],
                gameTimeSeconds: 17,
                operationPayload: "action-value"
            )
            let coreType = try XCTUnwrap(ScoreCore.GameType(rawValue: item.rawGameType == "archery" ? "archery_dual" : item.rawGameType))
            let payload = WatchRecordTransferPayload(
                id: recordId,
                kind: .sport(coreType),
                source: .watchLocal,
                startEpochMilliseconds: 1_700_000_000_000,
                endEpochMilliseconds: 1_700_000_120_000,
                durationSeconds: 120,
                team1Name: "红方",
                team2Name: "蓝方",
                team1FinalScore: item.team1Score,
                team2FinalScore: item.team2Score,
                team1SetScore: item.team1Sets,
                team2SetScore: item.team2Sets,
                winnerIdentity: .team(.team0),
                detailedActions: [action],
                totalScoreChanges: 1,
                participants: item.participants,
                projectConfiguration: item.config ?? [:]
            )

            let record = try WatchStandaloneRecordIngestor.makeRecord(payload)
            XCTAssertEqual(record.gameType, item.expectedAppType, "Unexpected GameType for \(item.rawGameType)")
            XCTAssertEqual(record.team1FinalScore, item.team1Score)
            XCTAssertEqual(record.team2FinalScore, item.team2Score)
            if item.expectNilSetScores {
                XCTAssertNil(record.team1SetScore, "Expected nil set score for \(item.rawGameType)")
                XCTAssertNil(record.team2SetScore, "Expected nil set score for \(item.rawGameType)")
            } else {
                XCTAssertEqual(record.team1SetScore, item.team1Sets)
                XCTAssertEqual(record.team2SetScore, item.team2Sets)
            }

            let encoded = try encoder.encode(record)
            let decoded = try decoder.decode(ScoreboardRecord.self, from: encoded)
            XCTAssertEqual(decoded.id, recordId)
            XCTAssertEqual(decoded.extraData?["syncFrom"]?.value as? String, "watch")
            XCTAssertNotNil(decoded.extraData?["watchSyncTime"]?.value as? Int)
            XCTAssertEqual(decoded.detailedActions?.first?.id, action.id)
            XCTAssertEqual(decoded.detailedActions?.first?.gameTimeSeconds, 17)
            XCTAssertEqual(decoded.detailedActions?.first?.operationPayload, "action-value")
            XCTAssertEqual(decoded.detailedActions?.first?.setScores, item.expectNilSetScores ? [] : action.setScores)

            // Verify end-to-end save into ScoreboardRecordManager on representative cases
            if index == 0 || index == cases.count - 1 {
                let persistedId = try WatchStandaloneRecordIngestor.ingest(payload)
                savedIDs.append(persistedId)
                let reloaded = try XCTUnwrap(ScoreboardRecordManager.shared.getRecordById(persistedId))
                XCTAssertEqual(reloaded.gameType, item.expectedAppType)
                XCTAssertEqual(reloaded.team1FinalScore, item.team1Score)
                XCTAssertEqual(reloaded.team2FinalScore, item.team2Score)
            }
        }
    }


    func testTypedSetupRejectedPayloadSurfacesReasonAndAbortsSetup() async throws {
        let store = InMemoryLinkDataStore()
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport, contextStore: store, outboxStore: store, recordSink: RecordingPhoneLinkSink(),
            intentDirectoryURL: makeIntentDirectory()
        )
        let initial = RallyMatchEngine.initial(leftName: "Alice", rightName: "Bob", rules: .badminton())
        let start = Task {
            try await service.startInteractiveOnWatch(gameType: .badminton, state: initial)
        }
        await waitUntil { !self.frames(.setupRequest, from: transport, as: LinkedScoreboardSetup.self).isEmpty }
        let setup = try XCTUnwrap(frames(.setupRequest, from: transport, as: LinkedScoreboardSetup.self).last)
        let rejection = LinkEnvelope(
            correlationId: setup.messageId,
            sessionId: setup.sessionId, matchId: setup.matchId,
            kind: .setupRejected, sender: .watch, senderSequence: 1, sessionRevision: 0,
            sentAtEpochMilliseconds: setup.sentAtEpochMilliseconds,
            payload: LinkSetupRejectedPayload(reason: .incompatibleProtocol)
        )
        service.handleIncoming(try JSONEncoder().encode(rejection))
        await settleMainQueue()
        XCTAssertEqual(service.lastSetupRejectionReason, .incompatibleProtocol)
        do {
            _ = try await start.value
            XCTFail("setup must fail")
        } catch let error as PhoneWatchLinkService.InteractiveStartError {
            guard case .setupRejected = error else {
                XCTFail("expected setupRejected, got \(error)")
                return
            }
        }
    }


    func testReceivedFileRecordPersistsThenSendsClearPendingAck() async throws {
        let store = InMemoryLinkDataStore()
        let transport = FakeWatchLinkTransport()
        let sink = RecordingPhoneLinkSink()
        _ = sink // 独立记录走 WatchStandaloneRecordIngestor，不经过该 sink
        let service = PhoneWatchLinkService(
            transport: transport, contextStore: store, outboxStore: store, recordSink: sink,
            intentDirectoryURL: makeIntentDirectory()
        )
        let recordID = "w_\(UUID().uuidString)"
        let actions = (0..<900).map { index in
            DetailedScoreAction(
                type: .scoreChanged, epochMilliseconds: Int64(1_700_000_000_000 + index * 10),
                team: .team1, scores: [index, 0], scoreChange: 1,
                operationCode: "watch_record_op_\(index)_\(UUID().uuidString)"
            )
        }
        let payload = WatchRecordTransferPayload(
            id: recordID, kind: .sport(.pingpong), source: .watchLocal,
            startEpochMilliseconds: 1_700_000_000_000,
            endEpochMilliseconds: 1_700_000_060_000,
            durationSeconds: 60, team1Name: "L", team2Name: "R",
            team1FinalScore: 11, team2FinalScore: 9, team1SetScore: 2, team2SetScore: 1,
            winnerIdentity: .team(.team0), detailedActions: actions, totalScoreChanges: 900
        )
        let data = try JSONEncoder().encode(payload)
        XCTAssertGreaterThan(data.count, 32_000, "构造超预算的独立记录载荷")
        service.handleReceivedFile(data, metadata: [
            WatchConnectivityTransport.transferFileKindKey: WatchTransferFileKind.watchRecord.rawValue
        ])
        await settleMainQueue()
        XCTAssertEqual(transport.clearedWatchRecordIDBatches, [[recordID]], "落库成功后 ACK 清手表队列")
    }


    private func finishedRallySnapshot() -> LinkedScoreboardSnapshot {
        var state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton()
        )
        state.leftPoints = 21
        state.rightPoints = 18
        state.leftSets = 2
        state.rightSets = 0
        state.finished = true
        return .rally(state)
    }


    private func settleMainQueue() async {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }


    private func waitUntil(
        timeoutMilliseconds: Int = 2_000,
        _ condition: @escaping () -> Bool
    ) async {
        var waited = 0
        while !condition(), waited < timeoutMilliseconds {
            try? await Task.sleep(nanoseconds: 20_000_000)
            waited += 20
        }
    }


    func testLinkedMatchRecordIngestorEncodesAllSevenSnapshotFamilies() throws {
        let rally = finishedRallySnapshot()
        var tennis = TennisMatchState(leftName: "Alice", rightName: "Bob", rules: .init())
        tennis.leftSets = 2
        tennis.rightSets = 0
        tennis.leftGames = 6
        tennis.rightGames = 4
        tennis.finished = true
        let archery = ArcheryMatchState(
            leftName: "红方",
            rightName: "蓝方",
            leftArrowSum: 29,
            rightArrowSum: 27,
            leftSetPoints: 6,
            rightSetPoints: 2,
            finished: true
        )
        var eightBall = EightBallState.initial(targetPoints: 5)
        eightBall.leftPoints = 5
        eightBall.rightPoints = 3
        eightBall.finished = true
        var nineBall = NineBallChaseState.initial(playerCount: 3, playerNames: ["甲", "乙", "改名的选手"])
        nineBall.playerPoints = [5, 8, 12, 0]
        nineBall.finished = true
        var snooker = SnookerState.initial(maxFrames: 5)
        snooker.leftScore = 71
        snooker.rightScore = 22
        snooker.leftFrames = 3
        snooker.rightFrames = 1
        snooker.finished = true
        let football = FootballMatchState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 2,
            rightScore: 1,
            timer: FootballTimerStateV2(halfLengthSeconds: 2700),
            kickedOff: true,
            finished: true
        )

        let families: [(ScoreCore.GameType, LinkedScoreboardSnapshot)] = [
            (.badminton, rally),
            (.tennis, .tennis(tennis)),
            (.archeryDual, .archery(archery)),
            (.eightBall, .eightBall(eightBall)),
            (.nineBall, .nineBall(nineBall)),
            (.snooker, .snooker(snooker)),
            (.football, .football(football))
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for (gameType, snapshot) in families {
            let matchId = UUID()
            let payload = LinkMatchFinishedPayload(
                snapshot: snapshot,
                recordId: "w_linked_\(matchId.uuidString)",
                winnerSide: gameType == .nineBall ? nil : .left,
                manualEnd: false,
                startTimeEpochMilliseconds: 1_700_000_000_000,
                endTimeEpochMilliseconds: 1_700_000_060_000,
                durationSeconds: 60,
                totalScoreChanges: 5,
                detailedActions: [
                    DetailedScoreAction(
                        id: UUID(),
                        type: gameType == .football ? .periodFinished : .scoreChanged,
                        epochMilliseconds: 1_700_000_010_000,
                        team: .team1,
                        scores: [1, 0],
                        periodNumber: gameType == .football ? 1 : nil,
                        operationCode: gameType == .football ? "football_period_end" : nil,
                        footballPeriod: gameType == .football ? 1 : nil,
                        footballElapsedSeconds: gameType == .football ? 2_700 : nil
                    )
                ],
                participantNames: ["甲", "乙", "丙"]
            )
            let record = try LinkedMatchRecordIngestor.makeRecord(
                payload: payload,
                gameType: gameType,
                sessionId: matchId
            )
            let encoded = try encoder.encode(record)
            let decoded = try decoder.decode(ScoreboardRecord.self, from: encoded)
            XCTAssertEqual(decoded.id, payload.recordId)
            XCTAssertEqual(decoded.detailedActions?.count, 1)
            XCTAssertNotNil(decoded.extraData?["watchSyncTime"]?.value as? Int)
            XCTAssertEqual(decoded.extraData?["linkedSessionId"]?.value as? String, matchId.uuidString)
            let snapshotData = try XCTUnwrap(decoded.stateSnapshot)
            XCTAssertEqual(try decoder.decode(LinkedScoreboardSnapshot.self, from: snapshotData), snapshot)
            if gameType == .football {
                XCTAssertNil(decoded.team1SetScore)
                XCTAssertNil(decoded.team2SetScore)
                XCTAssertEqual(decoded.setResults?.map(\.number), [1])
                XCTAssertEqual(decoded.setResults?.first?.titleCode, "football_period_end")
                XCTAssertEqual(decoded.detailedActions?.first?.footballElapsedSeconds, 2_700)
                XCTAssertEqual(decoded.projectConfiguration?["footballHalfLengthSeconds"]?.value as? Int, 2_700)
                XCTAssertEqual(decoded.projectConfiguration?["showMatchTime"]?.value as? Bool, true)
            }
            if gameType == .nineBall {
                XCTAssertEqual(decoded.winnerIdentity, .participant(index: 2))
                XCTAssertEqual(decoded.winner, "player_2")
                XCTAssertEqual(decoded.displayParticipants.map(\.name), ["甲", "乙", "改名的选手"])
                XCTAssertEqual(decoded.displayParticipants.map(\.score), [5, 8, 12])
                XCTAssertNil(decoded.team1SetScore)
            }
        }

    }

}

final class InMemoryLinkDataStore: @unchecked Sendable, LinkDataStore {
    private var values: [String: Data] = [:]
    private(set) var removalCounts: [String: Int] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) {
        values[key] = data
    }

    func removeObject(forKey key: String) {
        removalCounts[key, default: 0] += 1
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

private final class LockedInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

@MainActor
private final class RecordingPhoneLinkSink: PhoneLinkRecordSink {
    private(set) var matchIds: [UUID] = []
    private(set) var recorded: [LinkMatchFinishedPayload] = []
    var failNextIngest = false

    enum Failure: Error { case projectionInterrupted }

    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID
    ) throws -> String {
        if failNextIngest {
            failNextIngest = false
            throw Failure.projectionInterrupted
        }
        matchIds.append(matchId)
        recorded.append(payload)
        return payload.recordId
    }
}

final class FakeWatchLinkTransport: @unchecked Sendable, WatchLinkTransport {
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

    var automaticallyRespondToStatusQueries = false
    private let realtimeLock = NSLock()
    private var sentRealtimeMessages: [Data] = []
    var realtimeMessages: [Data] { realtimeLock.withLock { sentRealtimeMessages } }
    private(set) var publishedSnapshots: [Data] = []
    private(set) var durableMessages: [Data] = []

    func activate() {}

    func refreshStatus() {
        onStatusChange?(status)
    }

    func sendRealtime(_ data: Data) async throws {
        realtimeLock.withLock { sentRealtimeMessages.append(data) }
        guard automaticallyRespondToStatusQueries,
              let query = try? JSONDecoder().decode(
                  LinkEnvelope<EmptyLinkPayload>.self,
                  from: data
              ),
              query.kind == .statusQuery else {
            return
        }
        let response = LinkEnvelope(
            correlationId: query.messageId,
            sessionId: query.sessionId,
            matchId: query.matchId,
            matchGeneration: query.matchGeneration,
            kind: .statusResponse,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: query.sessionRevision,
            sentAtEpochMilliseconds: query.sentAtEpochMilliseconds + 1,
            payload: LinkStatusPayload(revision: query.sessionRevision)
        )
        onReceive?(try JSONEncoder().encode(response))
    }

    func publishLatestSnapshot(_ data: Data) throws {
        publishedSnapshots.append(data)
    }

    func enqueueDurable(_ data: Data) throws {
        durableMessages.append(data)
    }

    func sendInteractive(_ data: Data) throws {
        realtimeLock.withLock { sentRealtimeMessages.append(data) }
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
    private(set) var clearedWatchRecordIDBatches: [[String]] = []

    func clearPendingWatchRecords(ids: [String]) {
        clearedWatchRecordIDBatches.append(ids)
    }

    func deliver(_ data: Data) {
        onReceive?(data)
    }
}
