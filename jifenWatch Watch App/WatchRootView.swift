import LinkCore
import SwiftUI
import ScoreCore
import SessionCore
import WatchKit

struct WatchRootView: View {
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var scoreboardRoute: WatchScoreboardRoute? = nil
    @State private var activeResumeSession: WatchResumeSession?
    @State private var linkedSetup: LinkedScoreboardSetup?
    @State private var linkedSessionId: UUID?
    @State private var confirmDeadline: Date?
    // Regenerated on every scoreboard launch. Applied as `.id(...)` to the pushed
    // destination so SwiftUI rebuilds the board (and its session store) from the
    // freshly received Setup instead of reusing a previously-mounted board's
    // @State — which could still carry a historical session's names.
    @State private var scoreboardLaunchID = UUID()

    private static let confirmTimeoutSeconds: TimeInterval = 20

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.background.ignoresSafeArea()
                WatchTabView(
                    scoreboardRoute: localScoreboardRoute,
                    onResume: resume
                )
            }
            .navigationDestination(item: $scoreboardRoute) { route in
                destinationView(for: route)
                    .id(scoreboardLaunchID)
            }
        }
        .accentColor(WatchTheme.accent)
        .overlay(alignment: .bottom) {
            if scoreboardRoute != nil, let linkedSessionId,
               linkService.activeSessionId == linkedSessionId,
               let notice = linkService.simultaneousEditNotice {
                WatchToastView(message: NSLocalizedString(
                    "linked_score_simultaneous_edit", value: "Both devices made changes. Check the score.", comment: ""
                ))
                .padding(.bottom, 8)
                .accessibilityIdentifier("linked_score_simultaneous_edit")
                .allowsHitTesting(false)
                .task(id: notice) {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    if linkService.simultaneousEditNotice == notice {
                        linkService.simultaneousEditNotice = nil
                    }
                }
            }
        }
        .alert(
            NSLocalizedString("linked_score_error_title", value: "联动失败", comment: ""),
            isPresented: Binding(
                get: { linkService.lastLinkErrorMessage != nil },
                set: { if !$0 { linkService.clearLinkError() } }
            )
        ) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) {
                linkService.clearLinkError()
            }
        } message: {
            Text(linkService.lastLinkErrorMessage ?? "")
        }
        .alert(
            NSLocalizedString("resume_persistence_error_title", value: "续玩保存失败", comment: ""),
            isPresented: Binding(
                get: { resumeStore.lastErrorMessage != nil },
                set: { if !$0 { resumeStore.clearError() } }
            )
        ) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) {
                resumeStore.clearError()
            }
        } message: {
            Text(resumeStore.lastErrorMessage ?? "")
        }
        .overlay {
            if let request = linkService.pendingConfirmRequest {
                WatchLinkedSetupConfirmationView(
                    setup: request.setup,
                    deadline: confirmDeadline,
                    timeout: Self.confirmTimeoutSeconds,
                    onDecline: linkService.rejectPendingSetup,
                    onAccept: linkService.acceptPendingSetup
                )
                .id(request.messageId)
            }
        }
        // initial: true 覆盖「本次视图首次构建时请求就已经处于 pending」的情形
        // （冷启动 / 悬浮层被 .id 重建），否则 confirmDeadline 会一直为 nil。
        .onChange(of: linkService.pendingConfirmRequest, initial: true) { _, request in
            if request != nil {
                confirmDeadline = Date().addingTimeInterval(Self.confirmTimeoutSeconds)
                WKInterfaceDevice.current().play(.notification)
            } else {
                confirmDeadline = nil
            }
        }
        .onChange(of: linkService.acceptedSetup) { _, request in
            guard let request, let route = WatchScoreboardRoute(linkedSetup: request.setup) else { return }
            // A pending resume session may still hold a stale team names bundle
            // (e.g. from a previously linked match). Drop only the local resume
            // cache here; linkService already holds the new context
            // (acceptPendingSetup → persistContext), so do NOT call
            // discardResumableSession/leaveSession — those would corrupt the
            // new session's control role. The regenerated scoreboardLaunchID
            // guarantees the board is rebuilt fresh from the received Setup.
            resumeStore.clear()
            activeResumeSession = nil
            linkedSetup = request.setup
            linkedSessionId = request.sessionId
            scoreboardLaunchID = UUID()
            scoreboardRoute = route
            linkService.clearAcceptedSetup()
        }
        .onChange(of: linkService.activeSessionId) { _, sessionId in
            if sessionId == nil, linkedSessionId != nil {
                // 联动会话已结束：清掉草稿与页面，回到手表首页。
                resumeStore.clear()
                linkedSetup = nil
                linkedSessionId = nil
                scoreboardRoute = nil
            }
        }
        .onChange(of: scoreboardRoute) { _, route in
            if route == nil {
                activeResumeSession = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                // 续玩写入是 750ms 防抖的；非活跃/挂起前必须落盘，否则最后一次
                // 得分的续玩状态会随 Task 一起被冻结丢失。
                resumeStore.flushPendingWrite()
            }
        }
        .onAppear {
            resumeStore.retryPendingFinishedRecords()
            restoreStoredLinkContextIfNeeded()
        }
    }

    private func resume(_ session: WatchResumeSession) {
        resumeStore.reload()
        guard let currentSession = resumeStore.session,
              currentSession.startedAt == session.startedAt else {
            resumeStore.clear()
            return
        }

        // 联动草稿只带 handle 引用：会话身份、revision 与权威快照一律来自
        // link/ 上下文。上下文缺失、损坏、错场或已完赛时不复活联动，也不把
        // 草稿当成独立比赛开启，直接回首页。
        if currentSession.linkHandle != nil {
            let live = linkService.resumeContext
            guard let context = resumeStore.linkContextForResume(live ?? linkService.storedLinkContext),
                  !context.completedMatchIds.contains(context.handle.matchId),
                  context.latestAuthoritativeSnapshot?.isFinished != true,
                  live != nil || linkService.restoreSuspendedSession(context) else {
                resumeStore.clear()
                linkedSetup = nil
                linkedSessionId = nil
                scoreboardRoute = nil
                return
            }
            // 用服务的最新权威状态重建要展示的草稿，避免旧草稿或旧磁盘副本回退比分。
            guard let snapshot = context.latestAuthoritativeSnapshot,
                  resumeStore.applyLinkedSnapshot(snapshot, context: context) else {
                resumeStore.clear()
                linkedSetup = nil
                linkedSessionId = nil
                scoreboardRoute = nil
                return
            }
            linkedSetup = context.setup
            linkedSessionId = context.sessionId
        } else {
            linkedSetup = nil
            linkedSessionId = nil
        }

        guard let displaySession = resumeStore.session,
              let route = WatchScoreboardRoute(resumeSession: displaySession) else {
            resumeStore.clear()
            linkedSetup = nil
            linkedSessionId = nil
            return
        }
        activeResumeSession = displaySession
        _ = resumeStore.consume()
        scoreboardLaunchID = UUID()
        scoreboardRoute = route
    }

    private func restoreStoredLinkContextIfNeeded() {
        // 已有活跃联动时只与它匹配，绝不拿旧磁盘上下文覆盖另一个 live handle；
        // 只有完全没有 live 会话时才读存储。
        let live = linkService.resumeContext
        guard live == nil,
              let context = resumeStore.linkContextForResume(linkService.storedLinkContext),
              !context.completedMatchIds.contains(context.handle.matchId),
              context.latestAuthoritativeSnapshot?.isFinished != true else { return }
        guard linkService.restoreSuspendedSession(context) else { return }
        linkedSetup = context.setup
        linkedSessionId = context.sessionId
    }

    @ViewBuilder
    private func destinationView(for route: WatchScoreboardRoute) -> some View {
        if case .setup(let sport, let playerCount) = route {
            WatchSportsSetupView(sport: sport, playerCount: playerCount) { config in
                startLocalScoreboard(.configured(config))
            }
        } else {
            scoreDestination(for: route)
                .watchScoreboardAlwaysOn()
                .ignoresSafeArea()
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func scoreDestination(for route: WatchScoreboardRoute) -> some View {
        switch route {
            case .setup:
                EmptyView()
            case .configured(let config):
                configuredDestination(config)
            case .pingpong(let maxSets):
                WatchPingPongScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route),
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .badminton(let maxSets):
                WatchBadmintonScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route),
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .tennis(let maxSets):
                WatchTennisScoreView(
                    maxSets: maxSets,
                    initialState: tennisInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route),
                    resumeBundle: tennisResumeBundle(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: tennisResumeRestState(),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .shuttlecock(let maxSets):
                WatchRallyScoreView(
                    gameType: .shuttlecock,
                    rules: .shuttlecock(maxSets: maxSets),
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId,
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .squash(let maxSets):
                WatchRallyScoreView(
                    gameType: .squash,
                    rules: .squash(maxSets: maxSets),
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId,
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .foosball(let maxSets):
                WatchRallyScoreView(
                    gameType: .foosball,
                    rules: .foosball(maxSets: maxSets),
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId,
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .foosballDoubles(let maxSets):
                WatchRallyScoreView(
                    gameType: .foosballDoubles,
                    rules: .foosball(maxSets: maxSets),
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId,
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .pickleball(let maxSets):
                WatchPickleballScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route),
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .archery:
                WatchArcheryScoreView(
                    initialState: archeryInitialState(),
                    linkedSessionId: linkedSessionId,
                    resumeBundle: archeryResumeBundle(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: archeryResumeRestState(),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .basketballTraining(let mode):
                WatchBasketballTrainingView(
                    mode: mode,
                    linkedSessionId: linkedSessionId,
                    resumeBundle: trainingResumeBundle(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .eightBall:
                WatchEightBallScoreView(
                    initialState: eightBallInitialState(),
                    linkedSessionId: linkedSessionId,
                    leftName: eightBallResumeNames()?.left ?? linkedBilliardsNames()?.left,
                    rightName: eightBallResumeNames()?.right ?? linkedBilliardsNames()?.right,
                    resumeBundle: eightBallResumeBundle(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .nineBall:
                WatchNineBallScoreView(
                    initialState: nineBallInitialState(),
                    linkedSessionId: linkedSessionId,
                    resumeBundle: nineBallResumeBundle(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .snooker:
                WatchSnookerScoreView(
                    initialState: snookerInitialState(),
                    linkedSessionId: linkedSessionId,
                    leftName: snookerResumeNames()?.left ?? linkedBilliardsNames()?.left,
                    rightName: snookerResumeNames()?.right ?? linkedBilliardsNames()?.right,
                    resumeBundle: snookerResumeBundle(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .football(let halfLengthSeconds):
                footballDestination(isFiveAside: false, halfLengthSeconds: halfLengthSeconds)
            case .football5v5(let halfLengthSeconds):
                footballDestination(isFiveAside: true, halfLengthSeconds: halfLengthSeconds)
            case .pingpongDoubles(let maxSets):
                WatchPingPongScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: .pingpong(maxSets: maxSets)),
                    linkedSessionId: linkedSessionId,
                    doublesGameType: .pingpongDoubles,
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .badmintonDoubles(let maxSets):
                WatchBadmintonScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: .badminton(maxSets: maxSets)),
                    linkedSessionId: linkedSessionId,
                    doublesGameType: .badmintonDoubles,
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .tennisDoubles(let maxSets):
                WatchTennisScoreView(
                    maxSets: maxSets,
                    initialState: tennisInitialState(for: .tennis(maxSets: maxSets)),
                    linkedSessionId: linkedSessionId,
                    isDoubles: true,
                    resumeBundle: tennisResumeBundle(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: tennisResumeRestState(),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .pickleballDoubles(let maxSets):
                WatchPickleballScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: .pickleball(maxSets: maxSets)),
                    linkedSessionId: linkedSessionId,
                    doublesGameType: .pickleballDoubles,
                    resumeBundle: rallyResumeBundle(for: route),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: rallyResumeRestState(for: route),
                    resumedActionLog: activeResumeSession?.actionLog
                )
        }
    }

    @ViewBuilder
    private func configuredDestination(_ config: WatchScoreboardLaunchConfig) -> some View {
        switch config.sport {
        case .pingpong, .pingpongDoubles:
            WatchPingPongScoreView(
                maxSets: config.maxSets,
                initialState: WatchSetupPayloadMapper.rallyState(for: config),
                doublesGameType: config.sport.isDoubles ? .pingpongDoubles : nil
            )
        case .badminton, .badmintonDoubles:
            WatchBadmintonScoreView(
                maxSets: config.maxSets,
                initialState: WatchSetupPayloadMapper.rallyState(for: config),
                doublesGameType: config.sport.isDoubles ? .badmintonDoubles : nil
            )
        case .tennis, .tennisDoubles:
            WatchTennisScoreView(
                maxSets: config.maxSets,
                initialState: WatchSetupPayloadMapper.tennisState(for: config),
                isDoubles: config.sport.isDoubles
            )
        case .pickleball, .pickleballDoubles:
            WatchPickleballScoreView(
                maxSets: config.maxSets,
                initialState: WatchSetupPayloadMapper.rallyState(for: config),
                doublesGameType: config.sport.isDoubles ? .pickleballDoubles : nil
            )
        case .shuttlecock:
            WatchRallyScoreView(
                gameType: .shuttlecock,
                rules: .shuttlecock(maxSets: config.maxSets),
                initialState: WatchSetupPayloadMapper.rallyState(for: config)
            )
        case .squash:
            WatchRallyScoreView(
                gameType: .squash,
                rules: .squash(maxSets: config.maxSets),
                initialState: WatchSetupPayloadMapper.rallyState(for: config)
            )
        case .foosball:
            WatchRallyScoreView(
                gameType: .foosball,
                rules: .foosball(maxSets: config.maxSets),
                initialState: WatchSetupPayloadMapper.rallyState(for: config)
            )
        case .archery:
            WatchArcheryScoreView(initialState: WatchSetupPayloadMapper.archeryState(for: config))
        case .eightBall:
            let names = WatchSetupPayloadMapper.twoSideNames(for: config)
            WatchEightBallScoreView(
                initialState: WatchSetupPayloadMapper.eightBallState(for: config),
                leftName: names.left,
                rightName: names.right
            )
        case .nineBall:
            WatchNineBallScoreView(initialState: WatchSetupPayloadMapper.nineBallState(for: config))
        case .snooker:
            let names = WatchSetupPayloadMapper.twoSideNames(for: config)
            WatchSnookerScoreView(
                initialState: WatchSetupPayloadMapper.snookerState(for: config),
                leftName: names.left,
                rightName: names.right
            )
        case .football, .football5v5:
            let names = WatchSetupPayloadMapper.twoSideNames(for: config)
            WatchFootballScoreView(
                isFiveAside: config.sport == .football5v5,
                halfLengthSeconds: config.footballHalfLengthSeconds,
                leftName: names.left,
                rightName: names.right
            )
        }
    }

    @ViewBuilder
    private func footballDestination(
        isFiveAside: Bool,
        halfLengthSeconds: Int
    ) -> some View {
        WatchFootballScoreView(
            isFiveAside: isFiveAside,
            halfLengthSeconds: halfLengthSeconds,
            leftName: LinkedSetupConfirmCopy.leftName(from: linkedSetup),
            rightName: LinkedSetupConfirmCopy.rightName(from: linkedSetup),
            resumeBundle: footballResumeBundle(),
            initialState: footballInitialState(),
            resumedStartTime: activeResumeSession?.startedAt,
            resumedActionLog: activeResumeSession?.actionLog,
            linkedSessionId: linkedSessionId
        )
    }

    /// 联动开局直接复用 Reducer State 快照（时钟锚点与补时历史一并带入）。
    private func footballInitialState() -> FootballMatchState? {
        linkedSetup?.initialSnapshot?.footballState
    }

    private var localScoreboardRoute: Binding<WatchScoreboardRoute?> {
        Binding(
            get: { scoreboardRoute },
            set: { route in
                guard let route else {
                    scoreboardRoute = nil
                    return
                }
                if case .setup = route {
                    scoreboardLaunchID = UUID()
                    scoreboardRoute = route
                } else {
                    startLocalScoreboard(route)
                }
            }
        )
    }

    private func startLocalScoreboard(_ route: WatchScoreboardRoute) {
        if let handle = resumeStore.session?.linkHandle {
            // 先匹配当前活跃上下文；只有完全没有 live 会话时才读存储。
            // 旧磁盘上下文绝不覆盖另一个 live handle，引用失效则不复活。
            let live = linkService.resumeContext
            let matched: WatchLinkResumeContext?
            if let live {
                matched = live.handle == handle ? live : nil
            } else {
                matched = resumeStore.linkContextForResume(linkService.storedLinkContext)
            }
            if let matched {
                if linkService.resumeContext == nil {
                    linkService.restoreSuspendedSession(matched)
                }
                linkService.discardResumableSession()
            }
        } else if linkedSessionId != nil {
            linkService.leaveSession()
        }
        resumeStore.clear()
        activeResumeSession = nil
        linkedSetup = nil
        linkedSessionId = nil
        scoreboardLaunchID = UUID()
        scoreboardRoute = route
    }

    private func rallyResumeBundle(
        for route: WatchScoreboardRoute
    ) -> ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>? {
        guard let activeResumeSession,
              case .rally(_, let bundle, _) = activeResumeSession.payload else {
            return nil
        }
        return bundle
    }

    private func rallyResumeRestState(for route: WatchScoreboardRoute) -> WatchRestState? {
        guard let activeResumeSession,
              case .rally(_, _, let restState) = activeResumeSession.payload else { return nil }
        return restState
    }

    private func tennisResumeBundle(
    ) -> ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>? {
        guard let activeResumeSession,
              case .tennis(_, let bundle, _) = activeResumeSession.payload else { return nil }
        return bundle
    }

    private func tennisResumeRestState() -> WatchRestState? {
        guard let activeResumeSession,
              case .tennis(_, _, let restState) = activeResumeSession.payload else { return nil }
        return restState
    }

    private func archeryResumeBundle() -> WatchArcheryResumeBundle? {
        guard let activeResumeSession,
              case .archery(let bundle, _) = activeResumeSession.payload else { return nil }
        return bundle
    }

    private func archeryResumeRestState() -> WatchRestState? {
        guard let activeResumeSession,
              case .archery(_, let restState) = activeResumeSession.payload else { return nil }
        return restState
    }

    private func eightBallResumeBundle() -> WatchEightBallResumeBundle? {
        guard let activeResumeSession,
              case .eightBall(let bundle, _, _) = activeResumeSession.payload else { return nil }
        return bundle
    }

    private func eightBallResumeNames() -> (left: String, right: String)? {
        guard let activeResumeSession,
              case .eightBall(_, let left, let right) = activeResumeSession.payload else { return nil }
        return (left, right)
    }

    private func nineBallResumeBundle() -> WatchNineBallResumeBundle? {
        guard let activeResumeSession,
              case .nineBall(let bundle) = activeResumeSession.payload else { return nil }
        return bundle
    }

    private func snookerResumeBundle() -> WatchSnookerResumeBundle? {
        guard let activeResumeSession,
              case .snooker(let bundle, _, _) = activeResumeSession.payload else { return nil }
        return bundle
    }

    private func snookerResumeNames() -> (left: String, right: String)? {
        guard let activeResumeSession,
              case .snooker(_, let left, let right) = activeResumeSession.payload else { return nil }
        return (left, right)
    }

    private func footballResumeBundle() -> WatchFootballResumeBundle? {
        guard let activeResumeSession,
              case .football(_, let bundle) = activeResumeSession.payload else { return nil }
        return bundle
    }

    private func trainingResumeBundle() -> WatchShotTrainingResumeBundle? {
        guard let activeResumeSession,
              case .basketballTraining(let bundle) = activeResumeSession.payload else { return nil }
        return bundle
    }

    private func linkedBilliardsNames() -> (left: String, right: String)? {
        guard let names = linkedSetup?.participantNames, names.count >= 2 else { return nil }
        let left = names[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let right = names[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return (left, right)
    }

    private func rallyInitialState(for route: WatchScoreboardRoute) -> RallyMatchState? {
        guard let linkedSetup else { return nil }
        if case .rally(let state)? = linkedSetup.initialSnapshot {
            switch (route, linkedSetup.gameType) {
            case (.pingpong(_), .pingpong), (.pingpong(_), .pingpongDoubles),
                 (.pingpongDoubles(_), .pingpongDoubles),
                 (.badminton(_), .badminton), (.badminton(_), .badmintonDoubles),
                 (.badmintonDoubles(_), .badmintonDoubles),
                 (.pickleball(_), .pickleball), (.pickleball(_), .pickleballDoubles),
                 (.pickleballDoubles(_), .pickleballDoubles),
                 (.shuttlecock(_), .shuttlecock),
                 (.squash(_), .squash),
                 (.foosball(_), .foosball), (.foosball(_), .foosballDoubles),
                 (.foosballDoubles(_), .foosballDoubles):
                return state
            default:
                return nil
            }
        }
        // Linked mode arrived without an embedded rally snapshot: still follow
        // the phone's Setup (participant names + configured max sets) instead of
        // any local default name.
        guard Self.isRallyGameType(linkedSetup.gameType) else { return nil }
        return linkedRallyInitialState()
    }

    private func linkedRallyInitialState() -> RallyMatchState? {
        guard let linkedSetup else { return nil }
        let names = linkedRallyNames() ?? (
            left: WatchDefaultTeamNames.fallback(for: linkedSetup.gameType).left,
            right: WatchDefaultTeamNames.fallback(for: linkedSetup.gameType).right
        )
        let maxSets = linkedSetup.maxSets ?? 5
        let rules = Self.rallyRuleSet(for: linkedSetup.gameType, maxSets: maxSets)
        return RallyMatchEngine.initial(
            leftName: names.left,
            rightName: names.right,
            rules: rules
        )
    }

    private func linkedRallyNames() -> (left: String, right: String)? {
        guard let names = linkedSetup?.participantNames, names.count >= 2 else { return nil }
        let left = names[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let right = names[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return (left, right)
    }

    private static func isRallyGameType(_ gameType: GameType) -> Bool {
        switch gameType {
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles,
             .pickleball, .pickleballDoubles,
             .shuttlecock, .squash, .foosball, .foosballDoubles:
            return true
        default:
            return false
        }
    }

    private static func rallyRuleSet(for gameType: GameType, maxSets: Int) -> RallyRuleSet {
        switch gameType {
        case .pingpong, .pingpongDoubles:
            return .pingPong(maxSets: maxSets)
        case .badminton, .badmintonDoubles:
            return .badminton(maxSets: maxSets)
        case .pickleball, .pickleballDoubles:
            return .pickleball(maxSets: maxSets)
        case .shuttlecock:
            return .shuttlecock(maxSets: maxSets)
        case .squash:
            return .squash(maxSets: maxSets)
        case .foosball, .foosballDoubles:
            return .foosball(maxSets: maxSets)
        default:
            return .pingPong(maxSets: maxSets)
        }
    }

    private func tennisInitialState(for route: WatchScoreboardRoute) -> TennisMatchState? {
        guard let linkedSetup,
              case .tennis(let state)? = linkedSetup.initialSnapshot else { return nil }
        switch (route, linkedSetup.gameType) {
        case (.tennis(_), .tennis), (.tennis(_), .tennisDoubles),
             (.tennisDoubles(_), .tennisDoubles):
            return state
        default:
            return nil
        }
    }

    private func archeryInitialState() -> ArcheryMatchState? {
        guard let linkedSetup, case .archery(let state)? = linkedSetup.initialSnapshot else { return nil }
        return state
    }

    private func eightBallInitialState() -> EightBallState? {
        guard let linkedSetup, case .eightBall(let state)? = linkedSetup.initialSnapshot else { return nil }
        return state
    }

    private func nineBallInitialState() -> NineBallChaseState? {
        guard let linkedSetup, case .nineBall(let state)? = linkedSetup.initialSnapshot else { return nil }
        return state
    }

    private func snookerInitialState() -> SnookerState? {
        guard let linkedSetup, case .snooker(let state)? = linkedSetup.initialSnapshot else { return nil }
        return state
    }

    /// 早期版本曾按 route 区分初始快照来源；现在所有链接会话共用同一
    /// sessionId，直接透传。
    private func linkedSessionId(for route: WatchScoreboardRoute) -> UUID? {
        linkedSessionId
    }
}

enum LinkedSetupConfirmCopy {
    enum Participants: Equatable {
        case none
        case opponents(left: [String], right: [String])
        case players([String])
    }

    static func participants(for setup: LinkedScoreboardSetup) -> Participants {
        switch setup.initialSnapshot {
        case .basketballTraining:
            return .none
        case .nineBall(let state) where state.playerCount > 2:
            return .players((0..<state.playerCount).map { state.resolvedName(at: $0) })
        case .rally(let state):
            return opponents(from: setup, doublesNames: state.doubles?.playerNames)
        case .tennis(let state):
            return opponents(from: setup, doublesNames: state.doublesPlayerNames)
        default:
            return opponents(from: setup, doublesNames: nil)
        }
    }

    private static func opponents(from setup: LinkedScoreboardSetup, doublesNames: [String]?) -> Participants {
        let left = leftName(from: setup)
        let right = rightName(from: setup)
        guard let doublesNames, doublesNames.count == 4 else {
            return .opponents(left: [left], right: [right])
        }
        return .opponents(
            left: teamNames(doublesNames[0], doublesNames[2], fallback: left),
            right: teamNames(doublesNames[1], doublesNames[3], fallback: right)
        )
    }

    private static func teamNames(_ first: String, _ second: String, fallback: String) -> [String] {
        let players = [first, second]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return players.isEmpty ? [fallback] : players
    }

    static func summary(for setup: LinkedScoreboardSetup) -> String {
        let title = sportTitle(for: setup.gameType)
        let mode: String?
        switch setup.gameType {
        case .foosball: mode = "1 × 1"
        case .foosballDoubles: mode = "2 × 2"
        default: mode = nil
        }
        return [title, mode, rulesText(from: setup)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    static func sportTitle(for gameType: GameType) -> String {
        switch gameType {
        case .badminton:
            return NSLocalizedString("linked_score_sport_badminton", value: "羽毛球单打", comment: "")
        case .badmintonDoubles:
            return NSLocalizedString("linked_score_sport_badminton_doubles", value: "羽毛球双打", comment: "")
        case .pingpong:
            return NSLocalizedString("linked_score_sport_pingpong", value: "乒乓球单打", comment: "")
        case .pingpongDoubles:
            return NSLocalizedString("linked_score_sport_pingpong_doubles", value: "乒乓球双打", comment: "")
        case .tennis:
            return NSLocalizedString("linked_score_sport_tennis", value: "网球单打", comment: "")
        case .tennisDoubles:
            return NSLocalizedString("linked_score_sport_tennis_doubles", value: "网球双打", comment: "")
        case .pickleball:
            return NSLocalizedString("linked_score_sport_pickleball", value: "匹克球单打", comment: "")
        case .pickleballDoubles:
            return NSLocalizedString("linked_score_sport_pickleball_doubles", value: "匹克球双打", comment: "")
        case .archeryDual:
            return NSLocalizedString("linked_score_sport_archery", value: "射箭", comment: "")
        case .eightBall:
            return NSLocalizedString("linked_score_sport_eight_ball", value: "黑八", comment: "")
        case .nineBall:
            return NSLocalizedString("linked_score_sport_nine_ball", value: "追分", comment: "")
        case .snooker:
            return NSLocalizedString("linked_score_sport_snooker", value: "斯诺克", comment: "")
        case .shuttlecock:
            return NSLocalizedString("linked_score_sport_shuttlecock", value: "毽子", comment: "")
        case .squash:
            return NSLocalizedString("linked_score_sport_squash", value: "壁球", comment: "")
        case .foosball, .foosballDoubles:
            return NSLocalizedString("linked_score_sport_foosball", value: "桌上足球", comment: "")
        case .basketballTraining:
            return WatchGameType.basketballTraining.displayName
        case .football:
            return NSLocalizedString("linked_score_sport_football", value: "足球", comment: "")
        case .football5v5:
            return NSLocalizedString("linked_score_sport_football_5v5", value: "五人制足球", comment: "")
        default:
            return gameType.rawValue
        }
    }

    static func leftName(from setup: LinkedScoreboardSetup?) -> String {
        guard let setup else {
            return NSLocalizedString("watch_team_red", value: "红方", comment: "")
        }
        let defaults = WatchDefaultTeamNames.fallback(for: setup.gameType)
        switch setup.initialSnapshot {
        case .basketballTraining:
            return NSLocalizedString("watch_training_miss", value: "未中", comment: "")
        case .rally(let state):
            if let names = state.doubles?.playerNames, names.count >= 4,
               [.pingpongDoubles, .badmintonDoubles, .pickleballDoubles, .foosballDoubles, .shuttlecock].contains(setup.gameType) {
                return doublesPair(
                    names[0], names[2],
                    fallback: participantName(setup, index: 0, fallback: state.leftName)
                )
            }
            let left = state.leftName.trimmingCharacters(in: .whitespacesAndNewlines)
            return left.isEmpty
                ? participantName(setup, index: 0, fallback: defaults.left)
                : left
        case .tennis(let state):
            return state.doublesTeamDisplayName(for: .left)
        case .archery(let state):
            return state.leftName
        case .nineBall(let state):
            if state.playerCount <= 2 {
                return state.resolvedName(
                    at: 0,
                    fallback: defaults.left
                )
            }
            return (0..<state.playerCount)
                .map { state.resolvedName(at: $0, fallback: "P\($0 + 1)") }
                .joined(separator: " · ")
        case .football(let state):
            let left = state.leftName.trimmingCharacters(in: .whitespacesAndNewlines)
            return left.isEmpty
                ? participantName(setup, index: 0, fallback: defaults.left)
                : left
        case .eightBall, .snooker:
            return participantName(
                setup,
                index: 0,
                fallback: defaults.left
            )
        case .none:
            return participantName(setup, index: 0, fallback: defaults.left)
        }
    }

    static func rightName(from setup: LinkedScoreboardSetup?) -> String {
        guard let setup else {
            return NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
        }
        let defaults = WatchDefaultTeamNames.fallback(for: setup.gameType)
        switch setup.initialSnapshot {
        case .basketballTraining:
            return NSLocalizedString("watch_training_made", value: "命中", comment: "")
        case .rally(let state):
            if let names = state.doubles?.playerNames, names.count >= 4,
               [.pingpongDoubles, .badmintonDoubles, .pickleballDoubles, .foosballDoubles, .shuttlecock].contains(setup.gameType) {
                return doublesPair(
                    names[1], names[3],
                    fallback: participantName(setup, index: 1, fallback: state.rightName)
                )
            }
            let right = state.rightName.trimmingCharacters(in: .whitespacesAndNewlines)
            return right.isEmpty
                ? participantName(setup, index: 1, fallback: defaults.right)
                : right
        case .tennis(let state):
            return state.doublesTeamDisplayName(for: .right)
        case .archery(let state):
            return state.rightName
        case .nineBall(let state):
            if state.playerCount <= 2 {
                return state.resolvedName(
                    at: 1,
                    fallback: defaults.right
                )
            }
            return String(
                format: NSLocalizedString("watch_nine_ball_players_format", value: "追分 · %d人", comment: ""),
                state.playerCount
            )
        case .football(let state):
            let right = state.rightName.trimmingCharacters(in: .whitespacesAndNewlines)
            return right.isEmpty
                ? participantName(setup, index: 1, fallback: defaults.right)
                : right
        case .eightBall, .snooker:
            return participantName(
                setup,
                index: 1,
                fallback: defaults.right
            )
        case .none:
            return participantName(setup, index: 1, fallback: defaults.right)
        }
    }

    private static func doublesPair(_ first: String, _ second: String, fallback: String) -> String {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty && !b.isEmpty { return "\(a) / \(b)" }
        if !a.isEmpty { return a }
        if !b.isEmpty { return b }
        return fallback
    }

    private static func participantName(
        _ setup: LinkedScoreboardSetup,
        index: Int,
        fallback: String
    ) -> String {
        let names = setup.participantNames
        guard names.indices.contains(index) else { return fallback }
        let name = names[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    private static func rulesText(from setup: LinkedScoreboardSetup) -> String? {
        switch setup.initialSnapshot {
        case .basketballTraining(let state):
            if let points = state.mode.fixedPoints {
                return String.localizedStringWithFormat(
                    NSLocalizedString("watch_training_point_value", value: "%d分", comment: ""),
                    points
                )
            }
            return NSLocalizedString("watch_bb_free", value: "自由模式", comment: "")
        case .rally(let state):
            return String(
                format: NSLocalizedString("linked_score_setup_rules", value: "%d局 · %d分", comment: ""),
                state.rules.maxSets,
                state.rules.pointsToWinSet
            )
        case .tennis(let state):
            if state.rules.setScoringMode == .tiebreakOnly {
                return state.rules.tieBreakPoints == 10
                    ? NSLocalizedString("watch_tiebreak_indicator_10", value: "抢十", comment: "")
                    : NSLocalizedString("watch_tiebreak_indicator_7", value: "抢七", comment: "")
            }
            return String.localizedStringWithFormat(
                NSLocalizedString("linked_score_setup_rules_sets", value: "%d盘", comment: ""),
                state.rules.maxSets
            )
        case .nineBall(let state):
            return String.localizedStringWithFormat(
                NSLocalizedString("watch_setup_player_count", value: "%d 人", comment: ""),
                state.playerCount
            )
        case .eightBall(let state):
            return raceToText(state.targetPoints)
        case .snooker(let state):
            return raceToText(SnookerState.framesToWin(state.maxFrames))
        default:
            if let maxSets = setup.maxSets {
                return String(
                    format: NSLocalizedString("linked_score_setup_rules_sets", value: "%d盘", comment: ""),
                    maxSets
                )
            }
            return nil
        }
    }

    private static func raceToText(_ target: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("linked_score_setup_race_to", value: "抢%d局", comment: ""),
            target
        )
    }
}
