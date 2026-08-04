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
            }
        }
        .accentColor(WatchTheme.accent)
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
            if linkService.pendingConfirmRequest != nil {
                linkConfirmOverlay
            }
        }
        .onChange(of: linkService.pendingConfirmRequest) { _, request in
            if request != nil {
                confirmDeadline = Date().addingTimeInterval(Self.confirmTimeoutSeconds)
                WKInterfaceDevice.current().play(.notification)
            } else {
                confirmDeadline = nil
            }
        }
        .onChange(of: linkService.acceptedSetup) { _, request in
            #if DEBUG
            print("[WATCH] onChange acceptedSetup fired request=\(request != nil) request.setup.initialSnapshot=\(request?.setup.initialSnapshot.map { String(describing: $0) } ?? "<nil>")")
            #endif
            guard let request, let route = WatchScoreboardRoute(linkedSetup: request.setup) else { return }
            // A pending resume session may still hold a stale team names bundle
            // (e.g. from a previously linked match). WatchRallySessionStore.init
            // prefers resumeBundle over initialState, so a stale bundle would
            // override the freshly received phone Setup names. Drop only the
            // local resume cache here; linkService already holds the new
            // context (acceptPendingSetup → persistContext), so do NOT call
            // discardResumableSession/leaveSession — those would corrupt the
            // new session's control role.
            resumeStore.clear()
            activeResumeSession = nil
            linkedSetup = request.setup
            linkedSessionId = request.sessionId
            scoreboardRoute = route
            linkService.clearAcceptedSetup()
        }
        .onChange(of: linkService.controlRole) { _, role in
            if role == nil, linkedSessionId != nil {
                // Phone left — return home if still on linked board.
                resumeStore.clear()
                linkedSetup = nil
                linkedSessionId = nil
                scoreboardRoute = nil
            } else if role == .watchFollower,
                      resumeStore.session == nil,
                      scoreboardRoute == nil {
                // Resume was discarded: the phone owns the still-live linked
                // session, while watch navigation is now fully local.
                linkedSetup = nil
                linkedSessionId = nil
            }
        }
        .onChange(of: scoreboardRoute) { _, route in
            if route == nil {
                activeResumeSession = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                linkService.notifyBackgrounded()
            }
        }
        .onAppear {
            restoreStoredLinkContextIfNeeded()
        }
    }

    private func resume(_ session: WatchResumeSession) {
        resumeStore.reload()
        guard let currentSession = resumeStore.session,
              currentSession.startedAt == session.startedAt,
              let route = WatchScoreboardRoute(resumeSession: currentSession) else {
            resumeStore.clear()
            return
        }
        if let context = currentSession.link {
            linkService.restoreSuspendedSession(context)
            linkedSetup = context.setup
            linkedSessionId = context.sessionId
        } else {
            linkedSetup = nil
            linkedSessionId = nil
        }
        activeResumeSession = currentSession
        _ = resumeStore.consume()
        scoreboardRoute = route
    }

    private func restoreStoredLinkContextIfNeeded() {
        guard linkService.resumeContext == nil,
              let context = resumeStore.session?.link else { return }
        linkService.restoreSuspendedSession(context)
        linkedSetup = context.setup
        linkedSessionId = context.sessionId
    }

    private var linkConfirmOverlay: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = remainingConfirmSeconds(at: context.date)
            let progress = remaining / Self.confirmTimeoutSeconds

            ZStack {
                WatchTheme.background.ignoresSafeArea()

                // Rectangular timeout ring hugging the watch screen edges
                // (Harmony uses a circle for round watches; Apple Watch is a rounded square).
                GeometryReader { proxy in
                    let lineWidth: CGFloat = 3
                    let ringInset = lineWidth / 2
                    // GeometryReader is bounded by safe area; add insets back so
                    // the ring fills the full screen and hugs the edges.
                    let width = proxy.size.width
                        + proxy.safeAreaInsets.leading
                        + proxy.safeAreaInsets.trailing
                    let height = proxy.size.height
                        + proxy.safeAreaInsets.top
                        + proxy.safeAreaInsets.bottom
                    let cornerRadius = min(width, height) * 0.28
                    let ring = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: ringInset)
                    let clampedProgress = max(0, min(1, progress))
                    let trimStart = 0.25
                    let trimEnd = trimStart + clampedProgress
                    let progressStroke = StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )

                    ZStack {
                        ring
                            .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                        ring
                            .trim(from: trimStart, to: min(1, trimEnd))
                            .stroke(
                                WatchTheme.accent.opacity(0.82),
                                style: progressStroke
                            )

                        if trimEnd > 1 {
                            ring
                                .trim(from: 0, to: trimEnd - 1)
                                .stroke(
                                    WatchTheme.accent.opacity(0.82),
                                    style: progressStroke
                                )
                        }
                    }
                    .frame(width: width, height: height)
                    .offset(
                        x: -proxy.safeAreaInsets.leading,
                        y: -proxy.safeAreaInsets.top
                    )
                    .animation(.linear(duration: 0.1), value: progress)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text(NSLocalizedString(
                            "linked_score_phone_started_scoreboard",
                            value: "手机已发起计分",
                            comment: ""
                        ))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .multilineTextAlignment(.center)

                        Text(confirmSportTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WatchTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 3) {
                            confirmNameColumn(
                                name: confirmLeftName,
                                accent: Color(hex: 0xFF453A).opacity(0.72)
                            )
                            Text("vs")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WatchTheme.secondaryText)
                                .frame(width: 24)
                            confirmNameColumn(
                                name: confirmRightName,
                                accent: Color(hex: 0x0A84FF).opacity(0.72)
                            )
                        }

                        if let rules = confirmRulesText {
                            Text(rules)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WatchTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.top, 8)

                    Spacer(minLength: 8)

                    HStack(spacing: 22) {
                        Button {
                            linkService.rejectPendingSetup()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(WatchTheme.primaryText)
                                .frame(width: 50, height: 50)
                                .background(WatchTheme.listItemBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("linked_score_reject", value: "拒绝", comment: ""))

                        Button {
                            linkService.acceptPendingSetup()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 50, height: 50)
                                .background(WatchTheme.accent)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("linked_score_accept", value: "接受", comment: ""))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
            .onChange(of: remaining) { _, value in
                if value <= 0, linkService.pendingConfirmRequest != nil {
                    linkService.rejectPendingSetup()
                }
            }
        }
    }

    private func remainingConfirmSeconds(at date: Date) -> TimeInterval {
        guard let confirmDeadline else { return Self.confirmTimeoutSeconds }
        return max(0, confirmDeadline.timeIntervalSince(date))
    }

    private var confirmSportTitle: String {
        guard let gameType = linkService.pendingConfirmRequest?.setup.gameType else {
            return NSLocalizedString("linked_score_confirm_title", value: "手机请求联动计分", comment: "")
        }
        return LinkedSetupConfirmCopy.sportTitle(for: gameType)
    }

    private var confirmLeftName: String {
        LinkedSetupConfirmCopy.leftName(from: linkService.pendingConfirmRequest?.setup)
    }

    private var confirmRightName: String {
        LinkedSetupConfirmCopy.rightName(from: linkService.pendingConfirmRequest?.setup)
    }

    private var confirmRulesText: String? {
        LinkedSetupConfirmCopy.rulesText(from: linkService.pendingConfirmRequest?.setup)
    }

    private func confirmNameColumn(name: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3, height: 30)
            Text(name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WatchTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func destinationView(for route: WatchScoreboardRoute) -> some View {
        if case .setup(let sport, let playerCount) = route {
            WatchSportsSetupView(sport: sport, playerCount: playerCount) { config in
                scoreboardRoute = .configured(config)
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
                    resumedState: archeryResumeState(),
                    resumedUndoStates: archeryResumeUndoStates(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedRestState: archeryResumeRestState(),
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .basketballTraining(let mode):
                WatchBasketballTrainingView(
                    mode: mode,
                    resumedHistory: trainingResumeHistory(),
                    resumedStartTime: activeResumeSession?.startedAt
                )
            case .eightBall:
                WatchEightBallScoreView(
                    initialState: eightBallResumeState() ?? eightBallInitialState(),
                    linkedSessionId: linkedSessionId,
                    leftName: eightBallResumeNames()?.left ?? linkedBilliardsNames()?.left,
                    rightName: eightBallResumeNames()?.right ?? linkedBilliardsNames()?.right,
                    resumedUndoStates: eightBallResumeUndoStates(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .nineBall:
                WatchNineBallScoreView(
                    initialState: nineBallResumeState() ?? nineBallInitialState(),
                    linkedSessionId: linkedSessionId,
                    resumedUndoStates: nineBallResumeUndoStates(),
                    resumedStartTime: activeResumeSession?.startedAt,
                    resumedActionLog: activeResumeSession?.actionLog
                )
            case .snooker:
                WatchSnookerScoreView(
                    initialState: snookerResumeState() ?? snookerInitialState(),
                    linkedSessionId: linkedSessionId,
                    leftName: snookerResumeNames()?.left ?? linkedBilliardsNames()?.left,
                    rightName: snookerResumeNames()?.right ?? linkedBilliardsNames()?.right,
                    resumedUndoStates: snookerResumeUndoStates(),
                    resumedStartTime: activeResumeSession?.startedAt
                )
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
        }
    }

    private var localScoreboardRoute: Binding<WatchScoreboardRoute?> {
        Binding(
            get: { scoreboardRoute },
            set: { route in
                if let context = resumeStore.session?.link {
                    if linkService.resumeContext == nil {
                        linkService.restoreSuspendedSession(context)
                    }
                    linkService.discardResumableSession(reason: .newScoreboardStart)
                } else if linkedSessionId != nil {
                    linkService.leaveSession()
                }
                resumeStore.clear()
                activeResumeSession = nil
                linkedSetup = nil
                linkedSessionId = nil
                scoreboardRoute = route
            }
        )
    }

    private func rallyResumeBundle(
        for route: WatchScoreboardRoute
    ) -> ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>? {
        guard let activeResumeSession,
              case .rally(_, let bundle, _) = activeResumeSession.payload else {
            #if DEBUG
            print("[WATCH] rallyResumeBundle route=\(route) -> nil (activeResumeSession nil or non-rally)")
            #endif
            return nil
        }
        #if DEBUG
        print("[WATCH] rallyResumeBundle route=\(route) -> STALE BUNDLE leftName=\(bundle.currentSession.state.leftName) rightName=\(bundle.currentSession.state.rightName)")
        #endif
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

    private func archeryResumeState() -> ArcheryMatchState? {
        guard let activeResumeSession,
              case .archery(let state, _, _) = activeResumeSession.payload else { return nil }
        return state
    }

    private func archeryResumeUndoStates() -> [ArcheryMatchState] {
        guard let activeResumeSession,
              case .archery(_, let states, _) = activeResumeSession.payload else { return [] }
        return states
    }

    private func archeryResumeRestState() -> WatchRestState? {
        guard let activeResumeSession,
              case .archery(_, _, let restState) = activeResumeSession.payload else { return nil }
        return restState
    }

    private func eightBallResumeState() -> EightBallState? {
        guard let activeResumeSession,
              case .eightBall(let state, _, _, _) = activeResumeSession.payload else { return nil }
        return state
    }

    private func eightBallResumeUndoStates() -> [EightBallState] {
        guard let activeResumeSession,
              case .eightBall(_, let states, _, _) = activeResumeSession.payload else { return [] }
        return states
    }

    private func eightBallResumeNames() -> (left: String, right: String)? {
        guard let activeResumeSession,
              case .eightBall(_, _, let left, let right) = activeResumeSession.payload else { return nil }
        return (left, right)
    }

    private func nineBallResumeState() -> NineBallChaseState? {
        guard let activeResumeSession,
              case .nineBall(let state, _) = activeResumeSession.payload else { return nil }
        return state
    }

    private func nineBallResumeUndoStates() -> [NineBallChaseState] {
        guard let activeResumeSession,
              case .nineBall(_, let states) = activeResumeSession.payload else { return [] }
        return states
    }

    private func snookerResumeState() -> SnookerState? {
        guard let activeResumeSession,
              case .snooker(let state, _, _, _) = activeResumeSession.payload else { return nil }
        return state
    }

    private func snookerResumeUndoStates() -> [SnookerState] {
        guard let activeResumeSession,
              case .snooker(_, let states, _, _) = activeResumeSession.payload else { return [] }
        return states
    }

    private func snookerResumeNames() -> (left: String, right: String)? {
        guard let activeResumeSession,
              case .snooker(_, _, let left, let right) = activeResumeSession.payload else { return nil }
        return (left, right)
    }

    private func trainingResumeHistory() -> [WatchBasketballTrainingShot] {
        guard let activeResumeSession,
              case .basketballTraining(_, let history) = activeResumeSession.payload else { return [] }
        return history
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
        #if DEBUG
        print("[WATCH] rallyInitialState route=\(route) linkedSetup.gameType=\(linkedSetup.gameType) linkedSetup.participantNames=\(linkedSetup.participantNames) initialSnapshot.kind=\(linkedSetup.initialSnapshot.map { String(describing: $0).prefix(40) } ?? "<nil>")")
        #endif
        if case .rally(let state)? = linkedSetup.initialSnapshot {
            switch (route, linkedSetup.gameType) {
            case (.pingpong(_), .pingpong), (.pingpong(_), .pingpongDoubles),
                 (.pingpongDoubles(_), .pingpongDoubles),
                 (.badminton(_), .badminton), (.badminton(_), .badmintonDoubles),
                 (.badmintonDoubles(_), .badmintonDoubles),
                 (.pickleball(_), .pickleball), (.pickleball(_), .pickleballDoubles),
                 (.pickleballDoubles(_), .pickleballDoubles):
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
             .pickleball, .pickleballDoubles:
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

    private func archeryInitialState() -> LinkedArcheryState? {
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

    private func linkedSessionId(for route: WatchScoreboardRoute) -> UUID? {
        guard rallyInitialState(for: route) != nil
                || tennisInitialState(for: route) != nil else {
            return linkedSessionId
        }
        return linkedSessionId
    }
}

private enum LinkedSetupConfirmCopy {
    static func sportTitle(for gameType: GameType) -> String {
        switch gameType {
        case .badminton:
            return NSLocalizedString("linked_score_sport_badminton", value: "🏸 羽毛球单打", comment: "")
        case .badmintonDoubles:
            return NSLocalizedString("linked_score_sport_badminton_doubles", value: "🏸 羽毛球双打", comment: "")
        case .pingpong:
            return NSLocalizedString("linked_score_sport_pingpong", value: "🏓 乒乓球单打", comment: "")
        case .pingpongDoubles:
            return NSLocalizedString("linked_score_sport_pingpong_doubles", value: "🏓 乒乓球双打", comment: "")
        case .tennis:
            return NSLocalizedString("linked_score_sport_tennis", value: "🎾 网球单打", comment: "")
        case .tennisDoubles:
            return NSLocalizedString("linked_score_sport_tennis_doubles", value: "🎾 网球双打", comment: "")
        case .pickleball:
            return NSLocalizedString("linked_score_sport_pickleball", value: "🏓 匹克球单打", comment: "")
        case .pickleballDoubles:
            return NSLocalizedString("linked_score_sport_pickleball_doubles", value: "🏓 匹克球双打", comment: "")
        case .archeryDual:
            return NSLocalizedString("linked_score_sport_archery", value: "🏹 射箭", comment: "")
        case .eightBall:
            return NSLocalizedString("linked_score_sport_eight_ball", value: "🎱 黑八", comment: "")
        case .nineBall:
            return NSLocalizedString("linked_score_sport_nine_ball", value: "🎱 追分", comment: "")
        case .snooker:
            return NSLocalizedString("linked_score_sport_snooker", value: "🎱 斯诺克", comment: "")
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
        case .rally(let state):
            if let names = state.doubles?.playerNames, names.count >= 4,
               [.pingpongDoubles, .badmintonDoubles, .pickleballDoubles].contains(setup.gameType) {
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
        case .rally(let state):
            if let names = state.doubles?.playerNames, names.count >= 4,
               [.pingpongDoubles, .badmintonDoubles, .pickleballDoubles].contains(setup.gameType) {
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

    static func rulesText(from setup: LinkedScoreboardSetup?) -> String? {
        guard let setup else { return nil }
        switch setup.initialSnapshot {
        case .rally(let state):
            return String(
                format: NSLocalizedString("linked_score_setup_rules", value: "%d局 | %d分", comment: ""),
                state.rules.maxSets,
                state.rules.pointsToWinSet
            )
        case .tennis(let state):
            return String(
                format: NSLocalizedString("linked_score_setup_rules_sets", value: "%d盘", comment: ""),
                state.rules.maxSets
            )
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
}
