import XCTest
import LinkCore
import RecordCore
import ScoreCore
import SwiftUI
import UIKit
@testable import jifen

@MainActor
final class PhoneWatchLinkServiceTests: XCTestCase {
    func testSharedLinkLetsPhoneScoreAndAcceptWatchEditsWithoutAHandOff() async throws {
        let store = InMemoryLinkDataStore()
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport, contextStore: store, outboxStore: store, recordSink: RecordingPhoneLinkSink()
        )
        let initial = RallyMatchEngine.initial(leftName: "Alice", rightName: "Bob", rules: .badminton())
        let start = Task {
            try await service.startInteractiveOnWatch(gameType: .badminton, state: initial)
        }
        await settleMainQueue()
        let setup = try XCTUnwrap(transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: $0)
        }.first { $0.kind == .setupRequest })
        XCTAssertEqual(setup.supportsSharedEditing, true)
        service.handleIncoming(try JSONEncoder().encode(LinkEnvelope(
            supportsSharedEditing: true, correlationId: setup.messageId,
            sessionId: setup.sessionId, matchId: setup.matchId, kind: .setupAccepted,
            sender: .watch, senderSequence: 1, sessionRevision: 0,
            sentAtEpochMilliseconds: setup.sentAtEpochMilliseconds, payload: EmptyLinkPayload()
        )))
        let sessionId = try await start.value
        XCTAssertTrue(service.canEditLinkedMatch)
        XCTAssertFalse(service.isFollower)

        var first = initial
        first.leftPoints = 1
        service.syncWatch(sessionId: sessionId, gameType: .badminton, state: first)
        XCTAssertNil(service.incomingSnapshot)

        var concurrent = initial
        concurrent.rightPoints = 1
        let remoteSetup = LinkedScoreboardSetup(
            gameType: .badminton, maxSets: initial.rules.maxSets, initialSnapshot: .rally(concurrent)
        )
        let watchEdit = try JSONEncoder().encode(LinkEnvelope(
            baseSnapshotRevision: 0, sessionId: sessionId, matchId: setup.matchId,
            kind: .stateSnapshot, sender: .watch, senderSequence: 2, sessionRevision: 2,
            sentAtEpochMilliseconds: service.nowMs(), payload: remoteSetup
        ))
        service.handleIncoming(watchEdit)
        XCTAssertEqual(service.incomingSnapshot?.snapshot, .rally(concurrent))
        let notice = try XCTUnwrap(service.simultaneousEditNotice)
        service.handleIncoming(watchEdit)
        XCTAssertEqual(service.simultaneousEditNotice, notice)
        await settleMainQueue()
        let phoneEdit = try XCTUnwrap(transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: $0)
        }.last { $0.kind == .stateSnapshot })
        XCTAssertEqual(phoneEdit.sessionRevision, 1)
        XCTAssertEqual(phoneEdit.baseSnapshotRevision, 0)
        XCTAssertTrue(transport.publishedSnapshots.isEmpty, "A superseded edit only travels in realtime")
        service.syncWatch(sessionId: sessionId, gameType: .badminton, state: concurrent)
        XCTAssertEqual(service.activeSession?.revision, 2, "Applying a watch snapshot must not echo it")

        concurrent.leftPoints = 1
        service.syncWatch(sessionId: sessionId, gameType: .badminton, state: concurrent)
        XCTAssertEqual(service.activeSession?.revision, 3)
        let restored = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(), contextStore: store, outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        XCTAssertEqual(restored.linkedResumeDescriptor?.role, .shared)
        XCTAssertEqual(restored.linkedResumeDescriptor?.snapshot, .rally(concurrent))
        XCTAssertNil(restored.incomingSnapshot)
    }

    func testRestoresFollowerRoleAndLatestSnapshotAfterProcessRestart() throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 6, authorityEpoch: 3)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")

        let service = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        let restored = try XCTUnwrap(service.linkedResumeDescriptor)
        XCTAssertEqual(restored.handle, fixture.handle)
        XCTAssertEqual(restored.role, .phoneFollower)
        XCTAssertEqual(restored.authorityEpoch, 3)
        XCTAssertEqual(restored.revision, 6)
        XCTAssertEqual(restored.snapshot, fixture.snapshot)
    }

    func testForceTakeoverUsesCorrelatedStatusAndRaisesAuthorityEpoch() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 4, authorityEpoch: 7)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        transport.automaticallyRespondToStatusQueries = true
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        try await service.forceTakeover(sessionId: fixture.handle.sessionId)

        let current = try XCTUnwrap(service.linkedResumeDescriptor)
        XCTAssertEqual(current.role, .phoneController)
        XCTAssertEqual(current.authorityEpoch, 8)
        XCTAssertEqual(current.revision, 5)
        XCTAssertEqual(current.snapshot, fixture.snapshot)
        XCTAssertEqual(transport.publishedSnapshots.count, 1)

        let persistedData = try XCTUnwrap(store.data(forKey: "phone_link_context"))
        let persisted = try JSONDecoder().decode(PhoneLinkResumeContext.self, from: persistedData)
        XCTAssertEqual(persisted.role, .phoneController)
        XCTAssertEqual(persisted.authorityEpoch, 8)
    }

    func testForegroundStatusRefreshCoalescesOverlappingQueries() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 4, authorityEpoch: 7)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        NotificationCenter.default.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        await settleMainQueue()

        let queries = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: $0)
        }.filter { $0.kind == .statusQuery }
        let query = try XCTUnwrap(queries.first)
        XCTAssertEqual(queries.count, 1)

        let response = LinkEnvelope(
            correlationId: query.messageId,
            sessionId: query.sessionId,
            matchId: query.matchId,
            matchGeneration: query.matchGeneration,
            authorityEpoch: query.authorityEpoch,
            kind: .statusResponse,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: query.sessionRevision,
            sentAtEpochMilliseconds: query.sentAtEpochMilliseconds + 1,
            payload: LinkStatusPayload(
                role: .watchController,
                revision: query.sessionRevision
            )
        )
        transport.deliver(try JSONEncoder().encode(response))
        await settleMainQueue()

        XCTAssertEqual(service.linkedResumeDescriptor?.role, .phoneFollower)
    }

    func testResumeDescriptorIsNilWhileSetupHandshakeIsPending() async throws {
        let store = InMemoryLinkDataStore()
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton()
        )
        let snapshot = LinkedScoreboardSnapshot.rally(state)

        let setupTask = Task {
            try await service.startInteractiveSession(
                gameType: .badminton,
                maxSets: state.rules.maxSets,
                initialSnapshot: snapshot,
                participantNames: ["Alice", "Bob"]
            )
        }
        try await settleMainQueue()

        // The setup request is in flight but the watch has not accepted yet —
        // no session exists, so no resume descriptor (no Resume GameBar).
        XCTAssertNil(service.linkedResumeDescriptor)

        let request = try XCTUnwrap(
            transport.realtimeMessages.compactMap {
                try? JSONDecoder().decode(
                    LinkEnvelope<LinkedScoreboardSetup>.self,
                    from: $0
                )
            }.first { $0.kind == .setupRequest }
        )
        let accepted = LinkEnvelope<EmptyLinkPayload>(
            correlationId: request.messageId,
            sessionId: request.sessionId,
            matchId: request.matchId,
            matchGeneration: request.matchGeneration,
            authorityEpoch: 0,
            kind: .setupAccepted,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: 0,
            sentAtEpochMilliseconds: request.sentAtEpochMilliseconds + 1,
            payload: EmptyLinkPayload()
        )
        transport.deliver(try JSONEncoder().encode(accepted))
        await settleMainQueue()

        // Watch accepted: the session is established and the descriptor appears.
        let descriptor = try XCTUnwrap(service.linkedResumeDescriptor)
        XCTAssertEqual(descriptor.handle.sessionId, request.sessionId)
        _ = await setupTask.result
    }

    func testLeaveSessionIfMatchFinishedEndsFinishedLinkedSession() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 4, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        // Watch reports the match finished: the session lifecycle becomes
        // `.matchFinished` and the descriptor surfaces (GameBar visible).
        transport.deliver(try JSONEncoder().encode(
            finishedEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 5, snapshot: fixture.snapshot)
        ))
        await settleMainQueue()
        XCTAssertNotNil(service.linkedResumeDescriptor)

        // Exiting the finished scoreboard ends the session, so no stale
        // GameBar is left behind on Home.
        service.leaveSessionIfMatchFinished(fixture.handle.sessionId)
        await settleMainQueue()
        XCTAssertNil(service.linkedResumeDescriptor)
    }

    func testLeaveSessionIfMatchFinishedKeepsUnfinishedLinkedSession() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 4, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        await settleMainQueue()

        // Mid-match exit must keep the session so the user can re-attach.
        XCTAssertNotNil(service.linkedResumeDescriptor)
        service.leaveSessionIfMatchFinished(fixture.handle.sessionId)
        await settleMainQueue()
        XCTAssertNotNil(service.linkedResumeDescriptor)
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

    /// 首页快捷开始已改为全窗口双槽（左侧一张卡 + 右侧两张卡），
    /// 不再按宽度显示第三槽；用例对齐当前产品口径。
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

    /// UI 开关（设置弹窗的「在手表开始」按钮）与服务层白名单必须一致：
    /// UI 放行而服务拒绝时，用户会看到与真实原因无关的“Apple Watch 未连接”。
    /// 见 docs/audit/2026-11-24/watch-full-check.md P1-1。
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

    func testRetrySchedulerStaysIdleWithoutWorkAndStartsForRestoredOutbox() throws {
        let idleStore = InMemoryLinkDataStore()
        let idleService = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: idleStore,
            outboxStore: idleStore,
            recordSink: RecordingPhoneLinkSink()
        )
        XCTAssertFalse(idleService.hasScheduledRetryForTesting)

        let pendingStore = InMemoryLinkDataStore()
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let outbox = LinkDurableOutbox(items: [
            .init(
                messageId: UUID(),
                handle: handle,
                data: Data([1]),
                lastSentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
            )
        ])
        pendingStore.set(
            try JSONEncoder().encode(outbox),
            forKey: "phone_link_terminal_outbox"
        )
        let pendingService = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: pendingStore,
            outboxStore: pendingStore,
            recordSink: RecordingPhoneLinkSink()
        )
        XCTAssertTrue(pendingService.hasScheduledRetryForTesting)
    }

    func testLegacyLinkCleanupRunsOnlyOnce() {
        let store = InMemoryLinkDataStore()
        let legacyKeys = [
            "phone_link_context_v1",
            "phone_link_terminal_outbox_v1",
            "phone_link_pending_ack_v1"
        ]
        legacyKeys.forEach { store.set(Data([1]), forKey: $0) }

        _ = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        legacyKeys.forEach { XCTAssertNil(store.data(forKey: $0)) }

        legacyKeys.forEach { store.set(Data([2]), forKey: $0) }
        _ = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        legacyKeys.forEach {
            XCTAssertEqual(store.data(forKey: $0), Data([2]))
            XCTAssertEqual(store.removalCounts[$0], 1)
        }
    }

    func testWatchControllerTwoMatchesCreateExactlyTwoRecords() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 0, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let sink = RecordingPhoneLinkSink()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: sink
        )

        let secondHandle = fixture.handle.nextMatch()
        let secondState = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton()
        )
        let secondSnapshot = LinkedScoreboardSnapshot.rally(secondState)
        let nextMatch = LinkEnvelope(
            sessionId: secondHandle.sessionId,
            matchId: secondHandle.matchId,
            matchGeneration: secondHandle.matchGeneration,
            authorityEpoch: 2,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: 2,
            sessionRevision: 1,
            sentAtEpochMilliseconds: 2_000,
            payload: LinkedScoreboardSetup(
                gameType: .badminton,
                maxSets: secondState.rules.maxSets,
                initialSnapshot: secondSnapshot,
                participantNames: ["Alice", "Bob"]
            )
        )
        transport.deliver(try JSONEncoder().encode(nextMatch))
        await settleMainQueue()

        // A durable finish from the previous match may arrive after the new one starts.
        let firstFinished = finishedEnvelope(
            handle: fixture.handle,
            authorityEpoch: 2,
            revision: 1,
            snapshot: fixture.snapshot
        )
        transport.deliver(try JSONEncoder().encode(firstFinished))
        await settleMainQueue()
        XCTAssertNil(service.finishedRecordId)
        service.leaveSessionIfMatchFinished(secondHandle.sessionId)
        XCTAssertEqual(service.linkedResumeDescriptor?.handle, secondHandle)

        let secondFinished = finishedEnvelope(
            handle: secondHandle,
            authorityEpoch: 2,
            revision: 2,
            snapshot: secondSnapshot
        )
        let secondFinishedData = try JSONEncoder().encode(secondFinished)
        transport.deliver(secondFinishedData)
        transport.deliver(secondFinishedData)
        await settleMainQueue()

        XCTAssertEqual(sink.matchIds, [fixture.handle.matchId, secondHandle.matchId])
        XCTAssertEqual(Set(sink.matchIds).count, 2)
        XCTAssertEqual(service.linkedResumeDescriptor?.handle, secondHandle)
    }

    func testFinishedSnapshotSurvivesMatchFinishedFirstInterleaving() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 0, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        let finished = finishedRallySnapshot()

        // transferUserInfo (matchFinished) can arrive before the final
        // sendMessageData snapshot. The phone accepts rev 3 first...
        transport.deliver(try JSONEncoder().encode(
            finishedEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 3, snapshot: finished)
        ))
        await settleMainQueue()
        XCTAssertEqual(service.latestRemoteSnapshot?.revision, 3)
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot.rallyState?.finished, true)

        // ...so the final snapshot (rev 2, finished) arrives as
        // duplicateOrOlder. Mirroring HarmonyOS it must still be surfaced
        // rather than dropped, so the finish signal can never be lost.
        transport.deliver(try JSONEncoder().encode(
            snapshotEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 2, snapshot: finished)
        ))
        await settleMainQueue()

        let latest = try XCTUnwrap(service.latestRemoteSnapshot)
        XCTAssertEqual(latest.revision, 2)
        XCTAssertEqual(latest.snapshot.rallyState?.finished, true)
    }

    func testUnfinishedDuplicateSnapshotDoesNotOverrideFinishedSignal() async throws {
        let store = InMemoryLinkDataStore()
        let fixture = makeContext(revision: 0, authorityEpoch: 2)
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        // The watch reports the match finished first...
        transport.deliver(try JSONEncoder().encode(
            finishedEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 3, snapshot: finishedRallySnapshot())
        ))
        await settleMainQueue()
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot.rallyState?.finished, true)

        // A stale unfinished retry (rev 2, e.g. a lost ACK replayed) is
        // duplicateOrOlder — surfacing it would wrongly dismiss the finish
        // dialog. Only finished duplicates are surfaced.
        transport.deliver(try JSONEncoder().encode(
            snapshotEnvelope(handle: fixture.handle, authorityEpoch: 2, revision: 2, snapshot: fixture.snapshot)
        ))
        await settleMainQueue()

        let latest = try XCTUnwrap(service.latestRemoteSnapshot)
        XCTAssertEqual(latest.revision, 3)
        XCTAssertEqual(latest.snapshot.rallyState?.finished, true)
    }

    // MARK: - Detailed action incremental merge

    func testMergeDetailedActionsKeepsConcurrentLocalActionsAndDeduplicates() {
        let store = InMemoryLinkDataStore()
        let service = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
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

        // Watch snapshot overlaps localOld and adds a concurrent remote action.
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
            [localOld.id, watchNew.id, localNew.id],
            "Union by id keeps concurrent remote actions, dedups overlaps, sorts by epoch"
        )
    }

    func testMergeDetailedActionsKeepsLocalActionsWhenIncomingIsEmpty() {
        let store = InMemoryLinkDataStore()
        let service = PhoneWatchLinkService(
            transport: FakeWatchLinkTransport(),
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        let local = DetailedScoreAction(
            id: UUID(), type: .scoreChanged, epochMilliseconds: 1_000,
            team: .team1, scores: [1, 0]
        )
        service.mergeDetailedActions([local])
        service.mergeDetailedActions(nil)
        service.mergeDetailedActions([])

        XCTAssertEqual(service.mergedDetailedActions.map(\.id), [local.id])
    }

    func testFootballTakeoverAcknowledgementAppliesAuthoritativeFootballSnapshot() async throws {
        let store = InMemoryLinkDataStore()
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let initialFootball = LinkedFootballState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 1,
            rightScore: 0,
            timer: FootballTimerStateV2(halfLengthSeconds: 2700),
            kickedOff: true,
            finished: false
        )
        let setup = LinkedScoreboardSetup(
            gameType: .football,
            maxSets: nil,
            initialSnapshot: .football(initialFootball),
            participantNames: ["主队", "客队"]
        )
        let context = PhoneLinkResumeContext(
            handle: handle,
            setup: setup,
            role: .phoneFollower,
            authorityEpoch: 1,
            revision: 2,
            latestAuthoritativeSnapshot: .football(initialFootball),
            detailedActions: [],
            completedMatchIds: [],
            pendingTerminalMessageIds: []
        )
        store.set(try JSONEncoder().encode(context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        transport.refreshStatus()

        try await service.takeover(sessionId: handle.sessionId)
        await settleMainQueue()

        let takeoverRequest = try XCTUnwrap(
            transport.realtimeMessages.compactMap {
                try? JSONDecoder().decode(
                    LinkEnvelope<LinkAuthorityTransferPayload>.self,
                    from: $0
                )
            }.first { $0.kind == .takeoverByPhone }
        )

        let updatedFootball = LinkedFootballState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 2,
            rightScore: 1,
            timer: FootballTimerStateV2(halfLengthSeconds: 2700),
            kickedOff: true,
            finished: false
        )
        let ack = LinkEnvelope(
            correlationId: takeoverRequest.messageId,
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: 2,
            kind: .acknowledgement,
            sender: .watch,
            senderSequence: 3,
            sessionRevision: 3,
            sentAtEpochMilliseconds: 5_000,
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: takeoverRequest.messageId,
                acknowledgedRevision: 3,
                authoritativeSnapshot: .football(updatedFootball)
            )
        )
        transport.deliver(try JSONEncoder().encode(ack))
        await settleMainQueue()

        XCTAssertEqual(service.pendingTakeoverApplication?.snapshot, .football(updatedFootball))
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot, .football(updatedFootball))
        XCTAssertEqual(service.controlRole, .phoneController)
    }

    func testTrainingTakeoverAppliesLastWatchShotBeforeUnlockingScoring() async throws {
        let store = InMemoryLinkDataStore()
        let handle = LinkedMatchHandle(sessionId: UUID())
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let firstShot = LinkedShotTrainingShot(points: 2, made: true, timestamp: startedAt.addingTimeInterval(1))
        let lastShot = LinkedShotTrainingShot(points: 3, made: false, timestamp: startedAt.addingTimeInterval(2))
        let stalledSnapshot = LinkedScoreboardSnapshot.basketballTraining(
            .init(mode: .free, startTime: startedAt, shots: [firstShot])
        )
        let latestSnapshot = LinkedScoreboardSnapshot.basketballTraining(
            .init(mode: .free, startTime: startedAt, shots: [firstShot, lastShot])
        )
        let context = PhoneLinkResumeContext(
            handle: handle,
            setup: .init(gameType: .basketballTraining, initialSnapshot: stalledSnapshot),
            role: .phoneFollower, authorityEpoch: 0, revision: 1,
            latestAuthoritativeSnapshot: stalledSnapshot, detailedActions: [],
            completedMatchIds: [], pendingTerminalMessageIds: []
        )
        store.set(try JSONEncoder().encode(context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(transport: transport, contextStore: store, outboxStore: store)
        try await service.takeover(sessionId: handle.sessionId)
        let request = try XCTUnwrap(transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkAuthorityTransferPayload>.self, from: $0)
        }.first { $0.kind == .takeoverByPhone })
        XCTAssertEqual(request.payload.snapshot, stalledSnapshot)

        // The watch's second shot only arrives in the takeover acknowledgement.
        let ack = LinkEnvelope(
            correlationId: request.messageId, sessionId: handle.sessionId, matchId: handle.matchId,
            matchGeneration: handle.matchGeneration, authorityEpoch: 1,
            kind: .acknowledgement, sender: .watch, senderSequence: 2,
            sessionRevision: 2, sentAtEpochMilliseconds: 2_000,
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: request.messageId, acknowledgedRevision: 2,
                authoritativeSnapshot: latestSnapshot
            )
        )
        service.handleIncoming(try JSONEncoder().encode(ack))
        let pending = try XCTUnwrap(service.pendingTakeoverApplication)
        XCTAssertTrue(service.isController)
        XCTAssertTrue(service.isAuthorityTransferPending)
        XCTAssertEqual(pending.snapshot.basketballTrainingState?.shots, [firstShot, lastShot])
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot, latestSnapshot)

        service.completePhoneTakeover(messageId: pending.messageId)
        XCTAssertFalse(service.isAuthorityTransferPending)
        let restored = PhoneWatchLinkService(transport: FakeWatchLinkTransport(), contextStore: store, outboxStore: store)
        XCTAssertEqual(restored.linkedResumeDescriptor?.snapshot, latestSnapshot)
    }

    func testPhoneCanStartNextMatchBeforeWatchAcknowledgesPreviousMatch() async throws {
        var fixture = makeContext(revision: 1, authorityEpoch: 1)
        fixture.context.role = .phoneController
        fixture.context.peerSupportsCompressedFinish = true
        let store = InMemoryLinkDataStore()
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(transport: transport, contextStore: store, outboxStore: store)
        var state = try XCTUnwrap(fixture.snapshot.rallyState)
        state.leftPoints = 21
        state.finished = true
        service.notifyMatchFinished(
            sessionId: fixture.handle.sessionId, snapshot: .rally(state),
            recordId: "first", winnerSide: .left, manualEnd: true, recordAlreadySaved: true
        )
        let oldFinish = try XCTUnwrap(service.terminalOutbox.items.first)
        service.prepareControllerForNewMatch(
            sessionId: fixture.handle.sessionId, gameType: .badminton, snapshot: fixture.snapshot
        )
        let next = try XCTUnwrap(service.activeSession?.handle)
        await settleMainQueue()
        XCTAssertEqual(next.matchGeneration, fixture.handle.matchGeneration + 1)
        XCTAssertEqual(transport.publishedSnapshots.count, 1)
        XCTAssertEqual(transport.durableMessages, [oldFinish.data])
        let ack = LinkEnvelope(
            correlationId: oldFinish.messageId, sessionId: fixture.handle.sessionId, matchId: fixture.handle.matchId,
            matchGeneration: fixture.handle.matchGeneration, authorityEpoch: 1, kind: .recordAcknowledgement,
            sender: .watch, senderSequence: 8, sessionRevision: 2, sentAtEpochMilliseconds: 6_000,
            payload: LinkAcknowledgementPayload(acknowledgedMessageId: oldFinish.messageId, acknowledgedRevision: 2)
        )
        service.handleIncoming(try JSONEncoder().encode(ack))
        XCTAssertTrue(service.terminalOutbox.isEmpty)
        XCTAssertEqual(service.activeSession?.handle, next)
        XCTAssertNil(service.finishedRecordId)
    }

    func testNewWatchFinishCanArriveBeforeItsSnapshotAndOlderTerminalCanArriveLast() async throws {
        let fixture = makeContext(revision: 2, authorityEpoch: 1)
        let store = InMemoryLinkDataStore()
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let sink = RecordingPhoneLinkSink()
        let service = PhoneWatchLinkService(transport: transport, contextStore: store, outboxStore: store, recordSink: sink)
        let next = fixture.handle.nextMatch()
        var state = try XCTUnwrap(fixture.snapshot.rallyState)
        state.leftPoints = 21
        state.finished = true
        func finish(_ handle: LinkedMatchHandle, epoch: UInt64 = 1) -> LinkEnvelope<LinkMatchFinishedPayload> {
            LinkEnvelope(
                sessionId: handle.sessionId, matchId: handle.matchId, matchGeneration: handle.matchGeneration,
                authorityEpoch: epoch, kind: .matchFinished, sender: .watch,
                senderSequence: 4, sessionRevision: 3, sentAtEpochMilliseconds: 4_000,
                payload: LinkMatchFinishedPayload(snapshot: .rally(state), recordId: handle.matchId.uuidString)
            )
        }
        let nextFinish = finish(next)
        service.handleIncoming(LinkFinishedEncoding.encode(finish(next, epoch: 0), compress: true))
        XCTAssertTrue(sink.matchIds.isEmpty)
        service.handleIncoming(LinkFinishedEncoding.encode(nextFinish, compress: true))
        XCTAssertEqual(service.activeSession?.handle, next)
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot, .rally(state))
        let lateSnapshot = LinkEnvelope(
            sessionId: next.sessionId, matchId: next.matchId, matchGeneration: next.matchGeneration,
            authorityEpoch: 1, kind: .stateSnapshot, sender: .watch,
            senderSequence: 5, sessionRevision: 4, sentAtEpochMilliseconds: 4_010,
            payload: fixture.context.setup
        )
        service.handleIncoming(try JSONEncoder().encode(lateSnapshot))
        service.handleIncoming(LinkFinishedEncoding.encode(finish(fixture.handle), compress: true))
        service.handleIncoming(LinkFinishedEncoding.encode(nextFinish, compress: true))
        await settleMainQueue()

        XCTAssertEqual(sink.matchIds, [next.matchId, fixture.handle.matchId])
        XCTAssertEqual(service.activeSession?.handle, next)
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot, .rally(state))
        let recordAcks = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: $0)
        }.filter { $0.kind == .recordAcknowledgement }
        XCTAssertEqual(recordAcks.filter { $0.handle == next }.count, 2)
        XCTAssertEqual(recordAcks.filter { $0.handle == fixture.handle }.count, 1)
    }

    func testDelayedWatchFinishPersistsAfterNewSessionAndRestart() async throws {
        let store = InMemoryLinkDataStore()
        let old = makeContext(revision: 2, authorityEpoch: 1)
        store.set(try JSONEncoder().encode(old.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(transport: transport, contextStore: store, outboxStore: store)
        let training = LinkedScoreboardSnapshot.basketballTraining(.init(mode: .fixed2))
        let start = Task {
            try await service.startInteractiveOnWatch(snapshot: training, gameType: .basketballTraining)
        }
        defer { start.cancel() }
        await settleMainQueue()
        let setup = try XCTUnwrap(transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: $0)
        }.first { $0.kind == .setupRequest })
        let accepted = LinkEnvelope(
            supportsCompressedFinish: true,
            correlationId: setup.messageId, sessionId: setup.sessionId, matchId: setup.matchId,
            matchGeneration: setup.matchGeneration, kind: .setupAccepted,
            sender: .watch, senderSequence: 1, sessionRevision: 0, sentAtEpochMilliseconds: 3_000,
            payload: EmptyLinkPayload()
        )
        service.handleIncoming(try JSONEncoder().encode(accepted))
        let newSessionID = try await start.value
        XCTAssertNotEqual(newSessionID, old.handle.sessionId)

        let recordID = "w_late_\(UUID().uuidString)"
        let records = ScoreboardRecordManager.shared
        defer { _ = records.deleteRecord(recordID) }
        var badminton = try XCTUnwrap(old.snapshot.rallyState)
        badminton.leftPoints = 21
        badminton.rightPoints = 10
        badminton.leftSets = 2
        badminton.finished = true
        let finished = LinkEnvelope(
            sessionId: old.handle.sessionId, matchId: old.handle.matchId,
            matchGeneration: old.handle.matchGeneration, authorityEpoch: 1,
            kind: .matchFinished, sender: .watch, senderSequence: 3,
            sessionRevision: 3, sentAtEpochMilliseconds: 3_100,
            payload: LinkMatchFinishedPayload(
                snapshot: .rally(badminton), recordId: recordID, winnerSide: .left,
                startTimeEpochMilliseconds: 1_700_000_000_000, endTimeEpochMilliseconds: 1_700_000_060_000,
                durationSeconds: 60
            )
        )
        let data = try JSONEncoder().encode(finished)
        let receiver = FakeWatchLinkTransport()
        let restored = PhoneWatchLinkService(transport: receiver, contextStore: store, outboxStore: store)
        restored.handleIncoming(data)
        let record = try XCTUnwrap(records.getRecordById(recordID))
        XCTAssertEqual(record.gameType, .badminton)
        XCTAssertEqual(record.team1FinalScore, 21)
        XCTAssertEqual(restored.linkedResumeDescriptor?.handle, setup.handle)
        XCTAssertEqual(restored.latestRemoteSnapshot?.snapshot, training)
        XCTAssertNil(restored.finishedRecordId)
        await settleMainQueue()
        let ack = try XCTUnwrap(receiver.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: $0)
        }.first { $0.kind == .recordAcknowledgement })
        XCTAssertEqual(ack.handle, old.handle)
        XCTAssertEqual(ack.correlationId, finished.messageId)

        // A lost acknowledgement can trigger another delivery, even after relaunch.
        XCTAssertTrue(records.deleteRecord(recordID))
        let retryTransport = FakeWatchLinkTransport()
        let restarted = PhoneWatchLinkService(transport: retryTransport, contextStore: store, outboxStore: store)
        restarted.handleIncoming(data)
        XCTAssertNil(records.getRecordById(recordID))
        await settleMainQueue()
        XCTAssertTrue(retryTransport.realtimeMessages.contains {
            let ack = try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: $0)
            return ack?.kind == .recordAcknowledgement && ack?.correlationId == finished.messageId
        })
    }

    func testPhoneSnapshotStripsDetailedActionsFromApplicationContextAndPreservesOnEmptyReceive() async throws {
        let store = InMemoryLinkDataStore()
        var fixture = makeContext(revision: 2, authorityEpoch: 1)
        fixture.context.role = .phoneController
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )

        let action = DetailedScoreAction(
            id: UUID(),
            type: .scoreChanged,
            epochMilliseconds: 1_500,
            team: .team1,
            scores: [1, 0]
        )
        service.sendSnapshotIfController(
            sessionId: fixture.handle.sessionId,
            gameType: .badminton,
            snapshot: fixture.snapshot,
            detailedActions: [action]
        )
        await settleMainQueue()

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

        // Receiver path: follower receiving a stripped applicationContext snapshot
        // must keep already-merged detailedActions on both mergedDetailedActions and setup.
        let followerStore = InMemoryLinkDataStore()
        var followerFixture = makeContext(revision: 2, authorityEpoch: 1)
        followerFixture.context.detailedActions = [action]
        followerStore.set(try JSONEncoder().encode(followerFixture.context), forKey: "phone_link_context")
        let followerTransport = FakeWatchLinkTransport()
        let followerService = PhoneWatchLinkService(
            transport: followerTransport,
            contextStore: followerStore,
            outboxStore: followerStore,
            recordSink: RecordingPhoneLinkSink()
        )

        let strippedIncoming = snapshotEnvelope(
            handle: followerFixture.handle,
            authorityEpoch: 1,
            revision: 3,
            snapshot: followerFixture.snapshot
        )
        followerTransport.deliver(try JSONEncoder().encode(strippedIncoming))
        await settleMainQueue()

        XCTAssertEqual(followerService.mergedDetailedActions.map(\.id), [action.id])
        XCTAssertEqual(followerService.activeSession?.setup.detailedActions.map(\.id), [action.id])
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
        let service = PhoneWatchLinkService(transport: transport, contextStore: store, outboxStore: store)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = WatchRecordTransferPayload(
            id: watchID, gameType: "basketballTraining",
            startTimeEpochMilliseconds: 1_700_000_000_000, endTimeEpochMilliseconds: 1_700_000_001_000,
            durationSeconds: 1, team1Name: "Miss", team2Name: "Made",
            team1FinalScore: 0, team2FinalScore: 1, team1SetScore: 0, team2SetScore: 0,
            winner: nil, actions: [], totalScoreChanges: 1,
            basketballTraining: .init(
                mode: .fixed3, startTime: start,
                shots: [.init(points: 3, made: true, timestamp: start)], finished: true
            )
        )
        let data = try JSONEncoder().encode(payload)
        service.receivePendingWatchRecords([data])
        service.handleWatchRecordTransfer(data)

        XCTAssertEqual(service.lastSyncedWatchRecordId, phoneID)
        XCTAssertEqual(transport.clearedWatchRecordIDBatches, [[watchID], [watchID]])
        XCTAssertEqual(ScoreboardRecordManager.shared.getRecordById(phoneID)?.team2FinalScore, 1)
    }

    func testWatchStandaloneRecordIngestorEncodesAndPersistsAllStandaloneWatchSports() throws {
        struct StandaloneCase {
            let rawGameType: String
            let expectedAppType: jifen.GameType
            let team1Score: Int
            let team2Score: Int
            let team1Sets: Int
            let team2Sets: Int
            let participants: [WatchRecordParticipantPayload]?
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
                setScores: [item.team1Sets, item.team2Sets]
            )
            let payload = WatchRecordTransferPayload(
                id: recordId,
                gameType: item.rawGameType,
                startTimeEpochMilliseconds: 1_700_000_000_000,
                endTimeEpochMilliseconds: 1_700_000_120_000,
                durationSeconds: 120,
                team1Name: "红方",
                team2Name: "蓝方",
                team1FinalScore: item.team1Score,
                team2FinalScore: item.team2Score,
                team1SetScore: item.team1Sets,
                team2SetScore: item.team2Sets,
                winner: "红方",
                actions: ["score_add"],
                detailedActions: [action],
                totalScoreChanges: 1,
                participants: item.participants,
                projectConfiguration: item.config
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

    func testLinkedMatchRecordIngestorEncodesAllSevenSnapshotFamiliesAndPhoneFinishesRealtimeWhenReachable() async throws {
        let rally = finishedRallySnapshot()
        var tennis = TennisMatchState(leftName: "Alice", rightName: "Bob", rules: .init())
        tennis.leftSets = 2
        tennis.rightSets = 0
        tennis.leftGames = 6
        tennis.rightGames = 4
        tennis.finished = true
        let archery = LinkedArcheryState(
            leftName: "红方",
            rightName: "蓝方",
            leftSetPoints: 6,
            rightSetPoints: 2,
            leftArrowSum: 29,
            rightArrowSum: 27,
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
        let football = LinkedFootballState(
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
                winnerSide: .left,
                manualEnd: false,
                startTimeEpochMilliseconds: 1_700_000_000_000,
                endTimeEpochMilliseconds: 1_700_000_060_000,
                durationSeconds: 60,
                totalScoreChanges: 5,
                detailedActions: [
                    DetailedScoreAction(
                        id: UUID(),
                        type: .scoreChanged,
                        epochMilliseconds: 1_700_000_010_000,
                        team: .team1,
                        scores: [1, 0]
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
        }

        // Phone notifyMatchFinished should enqueue durable AND deliver realtime when reachable.
        let store = InMemoryLinkDataStore()
        var fixture = makeContext(revision: 2, authorityEpoch: 2)
        fixture.context.role = .phoneController
        store.set(try JSONEncoder().encode(fixture.context), forKey: "phone_link_context")
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: store,
            outboxStore: store,
            recordSink: RecordingPhoneLinkSink()
        )
        service.notifyMatchFinished(
            sessionId: fixture.handle.sessionId,
            snapshot: rally,
            recordId: "phone-record-1",
            winnerSide: .left,
            manualEnd: false
        )
        service.leaveSessionIfMatchFinished(fixture.handle.sessionId)
        XCTAssertNil(service.linkedResumeDescriptor)
        XCTAssertTrue(service.terminalOutbox.contains(sessionId: fixture.handle.sessionId, matchId: fixture.handle.matchId))
        await settleMainQueue()
        XCTAssertEqual(transport.durableMessages.count, 1)
        let realtimeFinished = transport.realtimeMessages.compactMap {
            try? JSONDecoder().decode(LinkEnvelope<LinkMatchFinishedPayload>.self, from: $0)
        }.filter { $0.kind == .matchFinished }
        XCTAssertEqual(realtimeFinished.count, 1)
        XCTAssertEqual(realtimeFinished.first?.payload.recordId, "phone-record-1")
    }

    private func makeContext(
        revision: UInt64,
        authorityEpoch: UInt64
    ) -> (
        handle: LinkedMatchHandle,
        snapshot: LinkedScoreboardSnapshot,
        context: PhoneLinkResumeContext
    ) {
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton()
        )
        let snapshot = LinkedScoreboardSnapshot.rally(state)
        let setup = LinkedScoreboardSetup(
            gameType: .badminton,
            maxSets: state.rules.maxSets,
            initialSnapshot: snapshot,
            participantNames: ["Alice", "Bob"]
        )
        return (
            handle,
            snapshot,
            PhoneLinkResumeContext(
                handle: handle,
                setup: setup,
                role: .phoneFollower,
                authorityEpoch: authorityEpoch,
                revision: revision,
                latestAuthoritativeSnapshot: snapshot,
                detailedActions: [],
                completedMatchIds: [],
                pendingTerminalMessageIds: []
            )
        )
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

    private func snapshotEnvelope(
        handle: LinkedMatchHandle,
        authorityEpoch: UInt64,
        revision: UInt64,
        snapshot: LinkedScoreboardSnapshot
    ) -> LinkEnvelope<LinkedScoreboardSetup> {
        LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: authorityEpoch,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: revision,
            sessionRevision: revision,
            sentAtEpochMilliseconds: Int64(revision) * 1_000,
            payload: LinkedScoreboardSetup(
                gameType: .badminton,
                maxSets: snapshot.rallyState?.rules.maxSets ?? 3,
                initialSnapshot: snapshot,
                participantNames: ["Alice", "Bob"]
            )
        )
    }

    private func finishedEnvelope(
        handle: LinkedMatchHandle,
        authorityEpoch: UInt64,
        revision: UInt64,
        snapshot: LinkedScoreboardSnapshot
    ) -> LinkEnvelope<LinkMatchFinishedPayload> {
        LinkEnvelope(
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: authorityEpoch,
            kind: .matchFinished,
            sender: .watch,
            senderSequence: revision,
            sessionRevision: revision,
            sentAtEpochMilliseconds: Int64(revision) * 1_000,
            payload: LinkMatchFinishedPayload(
                snapshot: snapshot,
                recordId: "watch-\(handle.matchId.uuidString)",
                startTimeEpochMilliseconds: 1_000,
                endTimeEpochMilliseconds: 2_000,
                durationSeconds: 1,
                totalScoreChanges: 1,
                participantNames: ["Alice", "Bob"]
            )
        )
    }

    func testSwitchingFromFinishedBadmintonToTennisDoublesClearsStaleSessionStateAndFollowsWatch() async throws {
        let transport = FakeWatchLinkTransport()
        let service = PhoneWatchLinkService(
            transport: transport,
            contextStore: InMemoryLinkDataStore(),
            outboxStore: InMemoryLinkDataStore(),
            recordSink: RecordingPhoneLinkSink()
        )

        // 1. Start and finish Match 1 (Badminton) without disconnecting.
        let badmintonInitial = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton(maxSets: 3)
        )
        let session1Task = Task {
            try await service.startInteractiveOnWatch(
                gameType: .badminton,
                state: badmintonInitial,
                participantNames: ["Alice", "Bob"]
            )
        }
        var req1: LinkEnvelope<LinkedScoreboardSetup>?
        for _ in 0..<25 {
            req1 = transport.realtimeMessages.reversed().compactMap {
                try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: $0)
            }.first { $0.kind == .setupRequest && $0.payload.gameType == .badminton }
            if req1 != nil { break }
            await settleMainQueue()
        }
        let unwrappedReq1 = try XCTUnwrap(req1)
        transport.deliver(try JSONEncoder().encode(LinkEnvelope(
            correlationId: unwrappedReq1.messageId,
            sessionId: unwrappedReq1.sessionId,
            matchId: unwrappedReq1.matchId,
            matchGeneration: unwrappedReq1.matchGeneration,
            authorityEpoch: unwrappedReq1.authorityEpoch,
            kind: .setupAccepted,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: 0,
            sentAtEpochMilliseconds: 100,
            payload: EmptyLinkPayload()
        )))
        let session1Id = try await session1Task.value

        var finishedBadminton = badmintonInitial
        finishedBadminton.leftSets = 2
        finishedBadminton.finished = true
        let handle1 = try XCTUnwrap(service.activeSession?.handle)
        let badmintonAction = DetailedScoreAction(
            id: UUID(),
            type: .scoreChanged,
            epochMilliseconds: 1_000,
            team: .team1,
            scores: [21, 10]
        )
        transport.deliver(try JSONEncoder().encode(LinkEnvelope(
            sessionId: session1Id,
            matchId: handle1.matchId,
            matchGeneration: handle1.matchGeneration,
            authorityEpoch: 0,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: 2,
            sessionRevision: 1,
            sentAtEpochMilliseconds: 1_000,
            payload: LinkedScoreboardSetup(
                gameType: .badminton,
                maxSets: 3,
                initialSnapshot: .rally(finishedBadminton),
                detailedActions: [badmintonAction],
                participantNames: ["Alice", "Bob"]
            )
        )))
        await settleMainQueue()
        service.watchBackgrounded = true

        // 2. Switch directly to Match 2 (Tennis Doubles) while S1 is still active.
        let tennisDoublesInitial = TennisMatchState(
            leftName: "P1 / P2",
            rightName: "P3 / P4",
            rules: TennisRuleSet(maxSets: 3),
            openingServer: .left,
            doublesPlayerNames: ["P1", "P3", "P2", "P4"]
        )
        let session2Task = Task {
            try await service.startInteractiveOnWatch(
                gameType: .tennisDoubles,
                state: tennisDoublesInitial,
                participantNames: ["P1", "P3", "P2", "P4"]
            )
        }
        var req2: LinkEnvelope<LinkedScoreboardSetup>?
        for _ in 0..<25 {
            req2 = transport.realtimeMessages.reversed().compactMap {
                try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: $0)
            }.first { $0.kind == .setupRequest && $0.payload.gameType == .tennisDoubles }
            if req2 != nil { break }
            await settleMainQueue()
        }
        let unwrappedReq2 = try XCTUnwrap(req2)
        transport.deliver(try JSONEncoder().encode(LinkEnvelope(
            correlationId: unwrappedReq2.messageId,
            sessionId: unwrappedReq2.sessionId,
            matchId: unwrappedReq2.matchId,
            matchGeneration: unwrappedReq2.matchGeneration,
            authorityEpoch: unwrappedReq2.authorityEpoch,
            kind: .setupAccepted,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: 0,
            sentAtEpochMilliseconds: 2_000,
            payload: EmptyLinkPayload()
        )))
        let session2Id = try await session2Task.value

        XCTAssertNotEqual(session1Id, session2Id)
        XCTAssertFalse(service.watchBackgrounded)
        XCTAssertFalse(service.isAuthorityTransferPending)
        XCTAssertTrue(service.mergedDetailedActions.isEmpty)

        // 3. Watch scores a point + triggers a set break in Tennis Doubles; Phone updates.
        var scoredTennis = tennisDoublesInitial
        scoredTennis.leftPoints = 1
        scoredTennis.officialBreakState = OfficialBreakState(
            sport: .tennis,
            kind: .setBreak,
            durationSeconds: 120,
            nowMilliseconds: 3_000
        )
        let handle2 = try XCTUnwrap(service.activeSession?.handle)
        transport.deliver(try JSONEncoder().encode(LinkEnvelope(
            sessionId: session2Id,
            matchId: handle2.matchId,
            matchGeneration: handle2.matchGeneration,
            authorityEpoch: 0,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: 2,
            sessionRevision: 1,
            sentAtEpochMilliseconds: 3_000,
            payload: LinkedScoreboardSetup(
                gameType: .tennisDoubles,
                maxSets: 3,
                initialSnapshot: .tennis(scoredTennis),
                participantNames: ["P1", "P3", "P2", "P4"]
            )
        )))
        await settleMainQueue()

        XCTAssertEqual(service.latestRemoteSnapshot?.sessionId, session2Id)
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot.tennisState?.leftPoints, 1)
        XCTAssertEqual(service.latestRemoteSnapshot?.snapshot.tennisState?.officialBreakState?.kind, .setBreak)
    }

    private func settleMainQueue() async {
        try? await Task.sleep(nanoseconds: 20_000_000)
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

    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID
    ) throws -> String {
        matchIds.append(matchId)
        return "record-\(matchId.uuidString)"
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
    var onCommonNameUsageData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationsData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationAckData: (@Sendable (Data) -> Void)?
    var onCatchUpRequest: (@Sendable () -> Void)?
    var onClearPendingRequest: (@Sendable ([String]) -> Void)?
    var onPendingRecords: (@Sendable ([Data]) -> Void)?

    var automaticallyRespondToStatusQueries = false
    private(set) var realtimeMessages: [Data] = []
    private(set) var publishedSnapshots: [Data] = []
    private(set) var durableMessages: [Data] = []

    func activate() {}

    func refreshStatus() {
        onStatusChange?(status)
    }

    func sendRealtime(_ data: Data) async throws {
        realtimeMessages.append(data)
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
            authorityEpoch: query.authorityEpoch,
            kind: .statusResponse,
            sender: .watch,
            senderSequence: 1,
            sessionRevision: query.sessionRevision,
            sentAtEpochMilliseconds: query.sentAtEpochMilliseconds + 1,
            payload: LinkStatusPayload(
                role: .watchController,
                revision: query.sessionRevision
            )
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
    private(set) var clearedWatchRecordIDBatches: [[String]] = []

    func clearPendingWatchRecords(ids: [String]) {
        clearedWatchRecordIDBatches.append(ids)
    }

    func deliver(_ data: Data) {
        onReceive?(data)
    }
}
