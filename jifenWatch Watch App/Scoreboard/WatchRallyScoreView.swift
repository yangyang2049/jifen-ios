import Observation
import LinkCore
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI


struct WatchRallyScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let gameType: GameType
    let rules: RallyRuleSet
    let linkedSessionId: UUID?
    @State private var showRecordSaveFailure = false
    @State private var store: WatchReducerSessionStore<RallyMatchReducer>
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didTransferFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var restState: WatchRestState?
    @State private var showSideExchangeToast = false
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var didFinalizeFinish = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
    @State private var manualFinishRequested = false
    @State private var restTriggers = WatchRestTriggerRegistry()
    @State private var sideExchangeTask: Task<Void, Never>?
    @State private var completedSetPresentation: WatchRallyCompletedSetPresentation?
    @State private var completedScoreTask: Task<Void, Never>?
    @State private var scoreEventToast: WatchScoreEventToastState?
    @State private var scoreEventToastTask: Task<Void, Never>?
    @State private var undoToastToken: UUID?

    init(
        gameType: GameType,
        rules: RallyRuleSet,
        initialState: RallyMatchState? = nil,
        linkedSessionId: UUID? = nil,
        resumeBundle: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>? = nil,
        resumedStartTime: Date? = nil,
        resumedRestState: WatchRestState? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.gameType = gameType
        self.rules = rules
        self.linkedSessionId = linkedSessionId
        let startedAt = resumedStartTime ?? Date()
        let binding = WatchBoardBindings.rally(gameType: gameType)
        let actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        // Priority: a resumeBundle only ever arrives from the explicit resume
        // flow (every fresh-launch path clears activeResumeSession first), so
        // it wins. Otherwise initialState (fresh phone Setup snapshot or local
        // setup) must be used as-is — never fall back to any historical state,
        // mirroring HarmonyOS, which discards the persisted session on every
        // non-resume scoreboard launch. Engine core and displayed state must
        // always come from the same source.
        if let resumeBundle {
            _store = State(initialValue: WatchReducerSessionStore(
                resumeBundle: resumeBundle,
                reducer: RallyMatchReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        } else {
            let defaults = WatchDefaultTeamNames.resolve(for: gameType)
            let seed = initialState ?? RallyMatchEngine.initial(
                leftName: defaults.left,
                rightName: defaults.right,
                rules: rules
            )
            let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
                gameType: gameType,
                ruleFamily: .s1,
                reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
                state: seed,
                participants: [
                    .init(id: TeamID.team0.rawValue, name: seed.leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: seed.rightName, role: "team")
                ]
            )
            _store = State(initialValue: WatchReducerSessionStore(
                seedSession: session,
                reducer: RallyMatchReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        }
        _matchStartTime = State(initialValue: startedAt)
        _restState = State(initialValue: resumedRestState)
    }

    private var scoringLocked: Bool {
        linkedSessionId != nil && !linkService.canEditLinkedMatch
    }

    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    var body: some View {
        ZStack {
            mainBoard
            if showSideExchangeToast {
                WatchSideExchangeToast()
                    .transition(.opacity)
            }
            if let scoreEventToast {
                WatchScoreEventToast(state: scoreEventToast)
                    .transition(.opacity)
            }
            if showMenu {
                WatchScoreboardMenuOverlay(
                    onDismiss: { showMenu = false },
                    onUndo: {
                        guard !scoringLocked else { return }
                        undoScoreboard()
                        showMenu = false
                    },
                    onFinish: {
                        guard !scoringLocked else { return }
                        showMenu = false
                        confirmation = .finish
                    },
                    onReset: {
                        guard !scoringLocked else { return }
                        showMenu = false
                        confirmation = .reset
                    }
                )
            }
            if let restState {
                WatchRestOverlay(
                    state: restState,
                    isReadOnly: scoringLocked,
                    onContinue: {
                        guard !scoringLocked else { return }
                        self.restState = nil
                        syncOfficialBreakState(nil)
                    },
                    onUndo: {
                        guard !scoringLocked else { return }
                        let triggerID = restState.triggerID
                        self.restState = nil
                        restTriggers.release(triggerID)
                        syncOfficialBreakState(nil)
                        undoScoreboard()
                    }
                )
            }
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreItems: [
                        WatchFinishedScoreItem(
                            name: store.state.leftName,
                            score: store.state.leftSets + store.state.rightSets > 0
                                ? store.state.leftSets
                                : store.state.leftPoints,
                            doublesNames: store.state.doubles?.playerNames,
                            side: .left
                        ),
                        WatchFinishedScoreItem(
                            name: store.state.rightName,
                            score: store.state.leftSets + store.state.rightSets > 0
                                ? store.state.rightSets
                                : store.state.rightPoints,
                            doublesNames: store.state.doubles?.playerNames,
                            side: .right
                        )
                    ],
                    winner: .side(finishedWinner),
                    undoAvailable: finishUndoAvailable,
                    canPlayAgain: !scoringLocked,
                    onUndo: undoFinish,
                    onPlayAgain: playAgain,
                    onExit: finishAndExit
                )
            }
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirm(confirmation) }
                )
            }
        }
        .ignoresSafeArea()
        .watchFinishSaveFailure(isPresented: $showRecordSaveFailure) { finalizeFinish() }
        .onAppear {
            if store.state.doubles == nil {
                scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            }
            store.onStateChanged = { [linkService] state, events in
                if linkedSessionId != nil {
                    guard linkService.canEditLinkedMatch else { return }
                    linkService.publishSnapshot(.rally(state), detailedActions: store.actionLog.detailedActions)
                }
                handle(events: events, state: state)
                persistResumeSession()
            }
            if store.state.finished {
                beginProvisionalFinish()
            } else if restState == nil, let remoteBreak = store.state.officialBreakState {
                restState = WatchRestState.fromOfficialBreak(remoteBreak)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            guard store.state.doubles == nil else { return }
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot, initial: true) { previous, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  update.matchGeneration == linkService.activeHandle?.matchGeneration,
                  let state = update.snapshot.rallyState else { return }
            let acceptsScore = linkService.incomingSnapshot != nil
            if acceptsScore, update.beginsMatch(after: previous) {
                matchStartTime = Date()
                store.beginRemoteMatch(at: matchStartTime)
            }
            let historyChanged = store.mergeRemoteActions(update.detailedActions, removing: update.removedActionIDs)
            guard acceptsScore else {
                if historyChanged { persistResumeSession() }
                return
            }
            guard update.matchGeneration == linkService.activeHandle?.matchGeneration else { return }
            let scoreApplied = store.applyAuthoritativeState(
                state, revision: update.revision, matchGeneration: update.matchGeneration
            )
            guard scoreApplied else {
                if historyChanged { persistResumeSession() }
                return
            }
            if state.finished {
                restState = nil
                beginRemoteFinishPresentation()
            } else {
                completedScoreTask?.cancel()
                completedScoreTask = nil
                completedSetPresentation = nil
                finishTask?.cancel()
                showFinishedOverlay = false
                finishUndoAvailable = false
                didFinalizeFinish = false
                restState = WatchRestState.fromOfficialBreak(state.officialBreakState)
            }
        }
        .onDisappear {
            finishTask?.cancel()
            sideExchangeTask?.cancel()
            completedScoreTask?.cancel()
            scoreEventToastTask?.cancel()
            if store.state.finished {
                finalizeFinish()
            }
            persistResumeSession()
        }
    }

    private var mainBoard: some View {
        Group {
            if store.state.doubles != nil {
                doublesBoard
            } else {
                GeometryReader { proxy in
                    let width = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
                    let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                    Group {
                        if isHorizontal {
                            HStack(spacing: 0) {
                                side(.left, size: CGSize(width: width / 2, height: height))
                                side(.right, size: CGSize(width: width / 2, height: height))
                            }
                            .frame(width: width, height: height)
                        } else {
                            VStack(spacing: 0) {
                                side(.left, size: CGSize(width: width, height: height / 2))
                                side(.right, size: CGSize(width: width, height: height / 2))
                            }
                            .frame(width: width, height: height)
                        }
                    }
                    .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
                }
                .ignoresSafeArea()
            }
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: interactionsEnabled,
            onMenu: { showMenu = true },
            onUndo: {
                guard !scoringLocked else { return }
                undoScoreboard()
            },
            onExit: exitBoard
        )
        .watchUndoToast(token: $undoToastToken)
    }

    private var doublesBoard: some View {
        let doubles = store.state.doubles
        let names = doubles?.playerNames ?? [
            store.state.leftName,
            store.state.rightName,
            store.state.leftName,
            store.state.rightName
        ]
        let layout = TeamScreenLayout(sidesSwapped: presentedSidesSwapped)
        let leftLogical = layout.engineSide(onScreen: .left)
        let rightLogical = layout.engineSide(onScreen: .right)
        return WatchDoublesBoard(
            left: doublesHalf(
                screenSide: .left,
                logicalSide: leftLogical,
                names: names
            ),
            right: doublesHalf(
                screenSide: .right,
                logicalSide: rightLogical,
                names: names
            )
        )
    }

    private func doublesHalf(
        screenSide: MatchSide,
        logicalSide: MatchSide,
        names: [String]
    ) -> WatchDoublesHalfModel {
        let isLeft = logicalSide == .left
        let fallbackTopIndex = isLeft ? 0 : 1
        let fallbackBottomIndex = isLeft ? 2 : 3
        let display = store.state.doubles.map {
            WatchDoublesDisplayState.resolve(
                doubles: $0,
                logicalSide: logicalSide,
                screenSide: screenSide
            )
        }
        let topIndex = display?.topPlayerIndex ?? fallbackTopIndex
        let bottomIndex = display?.bottomPlayerIndex ?? fallbackBottomIndex
        let points = presentedPoints(for: logicalSide)
        let sets = presentedSets(for: logicalSide)
        let showSets = store.state.leftSets + store.state.rightSets > 0 || store.state.currentSet > 1
        let servingPosition: WatchDoublesHalfModel.PlayerPosition? = {
            guard completedSetPresentation == nil,
                  store.state.servingSide == logicalSide,
                  let serverIsTop = display?.serverIsTop else { return nil }
            if case .foosball = store.state.doubles?.rotation {
                return nil
            }
            return serverIsTop ? .top : .bottom
        }()
        return WatchDoublesHalfModel(
            topName: names.indices.contains(topIndex) ? names[topIndex] : "",
            bottomName: names.indices.contains(bottomIndex) ? names[bottomIndex] : "",
            score: "\(points)",
            primaryMeta: showSets ? "\(sets)" : nil,
            secondaryMeta: nil,
            color: isLeft ? Color(hex: 0xD93A34) : Color(hex: 0x1F78D1),
            servingPosition: servingPosition,
            onTap: {
                guard interactionsEnabled, !suppressTapAfterLongPress else { return }
                store.dispatch(.pointWon(logicalSide))
            }
        )
    }

    private func side(_ screenSide: MatchSide, size: CGSize) -> some View {
        let layout = TeamScreenLayout(sidesSwapped: presentedSidesSwapped)
        let logicalSide = layout.engineSide(onScreen: screenSide)
        let isLeftTeam = logicalSide == .left
        let name = isLeftTeam ? store.state.leftName : store.state.rightName
        let points = presentedPoints(for: logicalSide)
        let sets = presentedSets(for: logicalSide)
        let isServing = completedSetPresentation == nil && store.state.servingSide == logicalSide
        let showSets = store.state.leftSets + store.state.rightSets > 0 || store.state.currentSet > 1
        let scoreText = "\(points)"
        let mainScoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 64 : 62,
            scoreText: scoreText,
            minimumSize: 42,
            availableWidth: size.width,
            horizontalPadding: 12
        )
        let scoreLabel = Text(scoreText)
            .font(WatchScoreTypography.primaryScore(size: mainScoreFont))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        let setLabel = Text("\(sets)")
            .font(WatchScoreTypography.secondaryScore(size: isHorizontal ? 20 : 22))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.65))

        return ZStack {
            WatchScoreboardFace(isHorizontal: isHorizontal) {
                Text(name)
                    .font(.system(size: WatchScoreTypography.teamNameSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(isHorizontal ? 2 : 1)
                    .minimumScaleFactor(isHorizontal ? 0.65 : 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } score: {
                if !isHorizontal, showSets {
                    HStack(spacing: 4) {
                        setLabel.frame(width: 32)
                        scoreLabel.frame(maxWidth: .infinity)
                        Color.clear.frame(width: 32, height: 1)
                    }
                    .padding(.horizontal, 8)
                } else {
                    scoreLabel
                }
            }

            if isHorizontal, showSets {
                setLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
                    .offset(y: WatchLayout.scoreboardMetaVerticalOffset)
            }

            if isServing {
                servingIndicator(screenSide: screenSide)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(isLeftTeam ? WatchTheme.teamRed : WatchTheme.teamBlue)
        .contentShape(Rectangle())
        // VoiceOver：整块面板读作「队名 比分」，双击即加分。
        // 此前面板对 VoiceOver 完全不可读（只暴露零散 Text）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityScoreLabel(
            name: name,
            points: points,
            sets: sets,
            showSets: showSets,
            isServing: isServing
        ))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard interactionsEnabled, !suppressTapAfterLongPress else { return }
            store.dispatch(.pointWon(logicalSide))
        }
        .onTapGesture {
            guard interactionsEnabled, !suppressTapAfterLongPress else { return }
            store.dispatch(.pointWon(logicalSide))
        }
    }

    /// 「A 11 分，2 局，发球中」这样的口语化描述。
    private func accessibilityScoreLabel(
        name: String,
        points: Int,
        sets: Int,
        showSets: Bool,
        isServing: Bool
    ) -> String {
        var parts = [name, String(
            format: NSLocalizedString("watch_a11y_points_format", value: "%d 分", comment: ""),
            points
        )]
        if showSets {
            parts.append(String(
                format: NSLocalizedString("watch_a11y_sets_format", value: "%d 局", comment: ""),
                sets
            ))
        }
        if isServing {
            parts.append(NSLocalizedString("watch_a11y_serving", value: "发球中", comment: ""))
        }
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private func servingIndicator(screenSide: MatchSide) -> some View {
        let direction: WatchServerIndicatorDirection = {
            if isHorizontal {
                return screenSide == .left ? .right : .left
            }
            return screenSide == .left ? .bottom : .top
        }()
        let alignment: Alignment = {
            if isHorizontal {
                return screenSide == .left ? .leading : .trailing
            }
            return screenSide == .left ? .top : .bottom
        }()
        WatchServerIndicator(
            direction: direction,
            size: WatchLayout.serverIndicatorSize,
            color: WatchTheme.accent
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(.vertical, isHorizontal ? 6 : 0)
            .padding(.horizontal, isHorizontal ? 0 : 6)
            .offset(y: WatchLayout.serverIndicatorVerticalOffset(isHorizontal: isHorizontal))
            .allowsHitTesting(false)
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private var interactionsEnabled: Bool {
        !scoringLocked
            && !store.state.finished
            && completedSetPresentation == nil
            && restState == nil
            && !showFinishedOverlay
            && confirmation == nil
            && !showMenu
    }

    private var scoreLine: String {
        if store.state.leftSets + store.state.rightSets > 0 {
            return "\(store.state.leftSets) - \(store.state.rightSets)"
        }
        return "\(store.state.leftPoints) : \(store.state.rightPoints)"
    }

    private var finishedWinner: MatchSide? {
        if let forfeitingSide = store.state.pingPongForfeitSide { return forfeitingSide.opposite }
        guard store.state.leftSets != store.state.rightSets else { return nil }
        return store.state.leftSets > store.state.rightSets ? .left : .right
    }

    private func handle(events: [RallyMatchEvent], state: RallyMatchState) {
        reconcileBadmintonMidGameRestTrigger(for: state)
        if let completed = WatchRallyCompletedSetPresentation.resolve(
            events: events,
            currentSidesSwapped: state.sidesSwapped
        ) {
            beginCompletedSetPresentation(completed, state: state)
            return
        }
        let sideExchangeRequested = events.contains { event in
            if case .sidesExchanged = event { return true }
            if case .sidesExchangeReminder = event { return true }
            return false
        }
        let handledMidGameBreak = events.contains { event in
            if case .pointScored = event { return true }
            return false
        } && beginBadmintonMidGameRestIfNeeded(
            state,
            followWithSideExchange: sideExchangeRequested
        )
        for event in events {
            switch event {
            case .setCompleted(_, let setNumber, _, _, _, _):
                guard !state.finished else { continue }
                beginBetweenSetRest(setNumber: setNumber)
            case .sidesExchanged, .sidesExchangeReminder:
                if !handledMidGameBreak {
                    showSideExchange()
                }
            case .pointScored:
                break
            case .matchFinished:
                beginProvisionalFinish()
            default:
                break
            }
        }
        if state.finished {
            beginProvisionalFinish()
        }
    }

    private var presentedSidesSwapped: Bool {
        completedSetPresentation?.sidesSwapped ?? store.state.sidesSwapped
    }

    private func presentedPoints(for side: MatchSide) -> Int {
        if let completedSetPresentation {
            return side == .left
                ? completedSetPresentation.leftPoints
                : completedSetPresentation.rightPoints
        }
        return side == .left ? store.state.leftPoints : store.state.rightPoints
    }

    private func presentedSets(for side: MatchSide) -> Int {
        if let completedSetPresentation {
            return side == .left
                ? completedSetPresentation.leftSets
                : completedSetPresentation.rightSets
        }
        return side == .left ? store.state.leftSets : store.state.rightSets
    }

    private func beginCompletedSetPresentation(
        _ presentation: WatchRallyCompletedSetPresentation,
        state: RallyMatchState
    ) {
        completedScoreTask?.cancel()
        sideExchangeTask?.cancel()
        scoreEventToastTask?.cancel()
        restState = nil
        showSideExchangeToast = false
        scoreEventToast = nil
        scoreEventToastTask = nil
        completedSetPresentation = presentation
        completedScoreTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            let didExchangeSides = presentation.sidesSwapped != state.sidesSwapped
            completedSetPresentation = nil
            completedScoreTask = nil
            if state.finished {
                beginProvisionalFinish()
            } else {
                if WatchPreferences.shared.setBreakEnabled {
                    beginBetweenSetRest(setNumber: presentation.setNumber)
                    if restState == nil, didExchangeSides {
                        showSideExchange()
                    }
                } else {
                    showCompletedSetToast(
                        presentation,
                        state: state,
                        followWithSideExchange: didExchangeSides
                    )
                }
            }
        }
    }

    private func beginRemoteFinishPresentation() {
        guard completedScoreTask == nil, !showFinishedOverlay else { return }
        completedScoreTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            completedScoreTask = nil
            beginProvisionalFinish()
        }
    }

    private func beginBetweenSetRest(setNumber: Int) {
        guard !scoringLocked,
              WatchPreferences.shared.setBreakEnabled,
              let duration = WatchRestPolicy.betweenSetDuration(for: gameType) else { return }
        let triggerID = "set-\(setNumber)"
        guard restTriggers.consume(triggerID) else { return }
        let nextRest = WatchRestState(
            kind: .betweenSets,
            title: NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: ""),
            durationSeconds: duration,
            triggerID: triggerID
        )
        restState = nextRest
        syncOfficialBreakState(nextRest)
    }

    @discardableResult
    private func beginBadmintonMidGameRestIfNeeded(
        _ state: RallyMatchState,
        followWithSideExchange: Bool
    ) -> Bool {
        guard !scoringLocked,
              gameType == .badminton || gameType == .badmintonDoubles else { return false }
        let point = WatchRestPolicy.badmintonMidGamePoint(
            pointsToWinSet: state.rules.pointsToWinSet
        )
        guard max(state.leftPoints, state.rightPoints) == point else { return false }
        let triggerID = badmintonMidGameTriggerID(setNumber: state.currentSet, point: point)
        guard restTriggers.consume(triggerID) else { return false }
        if WatchPreferences.shared.setBreakEnabled {
            let nextRest = WatchRestState(
                kind: .midGame,
                title: NSLocalizedString("watch_mid_game_rest", value: "局中休息", comment: ""),
                durationSeconds: 60,
                triggerID: triggerID
            )
            restState = nextRest
            syncOfficialBreakState(nextRest)
        } else {
            let leader: MatchSide = state.leftPoints > state.rightPoints ? .left : .right
            let leaderName = rallyDisplayName(for: leader, state: state)
            showScoreEventToast(
                WatchScoreEventToastState(
                    title: String.localizedStringWithFormat(
                        NSLocalizedString(
                            "watch_score_event_mid_game_title",
                            value: "第%d局 · 局中间歇",
                            comment: ""
                        ),
                        state.currentSet
                    ),
                    detail: String.localizedStringWithFormat(
                        NSLocalizedString(
                            "watch_score_event_mid_game_detail",
                            value: "%@领先 %d:%d · 局分 %d:%d",
                            comment: ""
                        ),
                        leaderName,
                        state.leftPoints,
                        state.rightPoints,
                        state.leftSets,
                        state.rightSets
                    )
                ),
                followWithSideExchange: followWithSideExchange
            )
        }
        return true
    }

    private func showCompletedSetToast(
        _ presentation: WatchRallyCompletedSetPresentation,
        state: RallyMatchState,
        followWithSideExchange: Bool
    ) {
        let winner: MatchSide = presentation.leftPoints > presentation.rightPoints ? .left : .right
        let winnerName = rallyDisplayName(for: winner, state: state)
        showScoreEventToast(
            WatchScoreEventToastState(
                title: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_set_title",
                        value: "第%d局结束",
                        comment: ""
                    ),
                    presentation.setNumber
                ),
                detail: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_set_detail",
                        value: "%@胜 %d:%d · 局分 %d:%d",
                        comment: ""
                    ),
                    winnerName,
                    presentation.leftPoints,
                    presentation.rightPoints,
                    presentation.leftSets,
                    presentation.rightSets
                )
            ),
            followWithSideExchange: followWithSideExchange
        )
    }

    private func rallyDisplayName(for side: MatchSide, state: RallyMatchState) -> String {
        guard let names = state.doubles?.playerNames, names.count >= 4 else {
            return side == .left ? state.leftName : state.rightName
        }
        let indices = side == .left ? [0, 2] : [1, 3]
        let playerNames = indices.map { names[$0] }.filter { !$0.isEmpty }
        return playerNames.isEmpty
            ? (side == .left ? state.leftName : state.rightName)
            : playerNames.joined(separator: " / ")
    }

    private func reconcileBadmintonMidGameRestTrigger(for state: RallyMatchState) {
        guard gameType == .badminton || gameType == .badmintonDoubles else { return }
        let point = WatchRestPolicy.badmintonMidGamePoint(
            pointsToWinSet: state.rules.pointsToWinSet
        )
        guard max(state.leftPoints, state.rightPoints) < point else { return }
        restTriggers.release(
            badmintonMidGameTriggerID(setNumber: state.currentSet, point: point)
        )
    }

    private func badmintonMidGameTriggerID(setNumber: Int, point: Int) -> String {
        "set-\(setNumber)-point-\(point)"
    }

    private func showSideExchange() {
        scoreEventToastTask?.cancel()
        scoreEventToastTask = nil
        scoreEventToast = nil
        sideExchangeTask?.cancel()
        showSideExchangeToast = true
        sideExchangeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showSideExchangeToast = false
        }
    }

    private func showScoreEventToast(
        _ toast: WatchScoreEventToastState,
        followWithSideExchange: Bool
    ) {
        sideExchangeTask?.cancel()
        showSideExchangeToast = false
        scoreEventToastTask?.cancel()
        scoreEventToast = toast
        scoreEventToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            scoreEventToast = nil
            scoreEventToastTask = nil
            if followWithSideExchange {
                showSideExchange()
            }
        }
    }

    private func beginProvisionalFinish() {
        guard !showFinishedOverlay else { return }
        sideExchangeTask?.cancel()
        scoreEventToastTask?.cancel()
        restState = nil
        showMenu = false
        showSideExchangeToast = false
        scoreEventToast = nil
        scoreEventToastTask = nil
        showFinishedOverlay = true
        finishUndoAvailable = !scoringLocked
        didFinalizeFinish = false
        finishTask?.cancel()
        guard !scoringLocked else { return }
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.finishedUndoCountdown))
            guard !Task.isCancelled else { return }
            finishUndoAvailable = false
            finalizeFinish()
        }
    }

    @discardableResult
    private func finalizeFinish() -> Bool {
        guard store.state.finished, !didFinalizeFinish, !scoringLocked else { return true }
        finishUndoAvailable = false
        let saved: Bool
        if linkedSessionId != nil {
            let winner: MatchSide? = store.state.leftSets == store.state.rightSets
                ? nil
                : (store.state.leftSets > store.state.rightSets ? .left : .right)
            saved = linkService.publishMatchFinished(
                snapshot: .rally(store.state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: winner,
                manualEnd: manualFinishRequested,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: store.actionLog.scoreChangeCount,
                detailedActions: store.actionLog.detailedActions
            )
        } else {
            saved = transferLocalFinishedRecordIfNeeded(store.state)
        }
        guard saved else {
            showRecordSaveFailure = true
            return false
        }
        didFinalizeFinish = true
        resumeStore.clear()
        return true
    }

    private func undoFinish() {
        guard finishUndoAvailable, !scoringLocked else { return }
        completedScoreTask?.cancel()
        completedScoreTask = nil
        completedSetPresentation = nil
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didFinalizeFinish = false
        undoScoreboard()
    }

    private func undoScoreboard() {
        guard store.undo() else { return }
        undoToastToken = UUID()
    }

    private func playAgain() {
        guard !scoringLocked else { return }
        guard finalizeFinish() else { return }
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didTransferFinishedRecord = false
        didFinalizeFinish = false
        manualFinishRequested = false
        restTriggers.reset()
        sideExchangeTask?.cancel()
        scoreEventToastTask?.cancel()
        completedScoreTask?.cancel()
        completedScoreTask = nil
        completedSetPresentation = nil
        showSideExchangeToast = false
        scoreEventToast = nil
        startFreshMatch()
    }

    private func finishAndExit() {
        guard finalizeFinish() else { return }
        exitBoard()
    }

    private func confirm(_ value: WatchScoreboardConfirmation) {
        guard !scoringLocked else {
            confirmation = nil
            return
        }
        confirmation = nil
        switch value {
        case .finish:
            manualFinishRequested = true
            store.dispatch(.finish)
        case .reset:
            resumeStore.clear()
            finishTask?.cancel()
            showFinishedOverlay = false
            restState = nil
            didTransferFinishedRecord = false
            didFinalizeFinish = false
            manualFinishRequested = false
            restTriggers.reset()
            sideExchangeTask?.cancel()
            scoreEventToastTask?.cancel()
            completedScoreTask?.cancel()
            completedScoreTask = nil
            completedSetPresentation = nil
            showSideExchangeToast = false
            scoreEventToast = nil
            startFreshMatch()
        }
    }

    private func startFreshMatch() {
        let timestamp = Date()
        let result = RallyMatchReducer().reduce(
            state: store.state,
            intent: .reset,
            at: Int64(timestamp.timeIntervalSince1970 * 1_000)
        )
        guard result.accepted else { return }
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
            state: result.state,
            participants: store.machine.currentSession.participants
        )
        let freshStore = WatchReducerSessionStore(
            seedSession: session,
            reducer: RallyMatchReducer(),
            binding: WatchBoardBindings.rally(gameType: gameType),
            actionLog: WatchScoreActionLog(startedAt: timestamp),
            startedAt: timestamp
        )
        freshStore.onStateChanged = { [linkService, weak freshStore] state, events in
            if linkedSessionId != nil {
                guard linkService.canEditLinkedMatch, let freshStore else { return }
                linkService.publishSnapshot(
                    .rally(state),
                    detailedActions: freshStore.actionLog.detailedActions
                )
            }
            handle(events: events, state: state)
            persistResumeSession()
        }
        store = freshStore
        matchStartTime = timestamp
        if linkedSessionId != nil {
            linkService.startNextMatch(
                snapshot: .rally(result.state),
                participantNames: result.state.doubles?.playerNames
                    ?? [result.state.leftName, result.state.rightName]
            )
        }
    }

    private func syncOfficialBreakState(_ rest: WatchRestState?) {
        guard linkedSessionId != nil, linkService.canEditLinkedMatch else { return }
        let mapped = rest?.officialBreakState(for: gameType)
        guard store.state.officialBreakState != mapped else { return }
        store.dispatchNonUndoable(.setOfficialBreakState(mapped))
    }

    private func exitBoard() {
        if let linkedSessionId { linkService.exitScoreboard(sessionId: linkedSessionId) }
        dismiss()
    }

    private func persistResumeSession() {
        if let linkedSessionId, linkService.activeSessionId != linkedSessionId {
            return
        }
        let state = store.state
        if state.finished {
            if didFinalizeFinish { resumeStore.clear() }
            return
        }
        guard state.leftPoints != 0 || state.rightPoints != 0
                || state.leftSets != 0 || state.rightSets != 0 else {
            resumeStore.clear()
            return
        }
        let bundle = store.resumeBundle()
        guard !store.state.finished else { return }
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: scoreLine,
            emoji: resumeEmoji,
            payload: .rally(
                gameType: gameType,
                bundle: bundle,
                restState: restState
            ),
            actionLog: store.actionLog,
            linkHandle: linkService.resumeContext?.handle
        ))
    }

    private var resumeEmoji: String {
        switch gameType {
        case .badminton, .badmintonDoubles, .shuttlecock: return "🏸"
        case .pingpong, .pingpongDoubles: return "🏓"
        case .pickleball, .pickleballDoubles: return "🏓"
        case .squash: return "🎾"
        case .foosball, .foosballDoubles: return "⚽"
        default: return "🏆"
        }
    }

    private func transferLocalFinishedRecordIfNeeded(_ state: RallyMatchState) -> Bool {
        guard !didTransferFinishedRecord else { return true }
        let end = Date()
        guard let record = WatchScoreboardRecord(
            localSnapshot: .rally(state), gameType: gameType,
            id: "w_\(UUID().uuidString)", startTime: matchStartTime, endTime: end,
            detailedActions: store.actionLog.detailedActions, totalScoreChanges: store.actionLog.scoreChangeCount
        ) else { return false }
        guard resumeStore.saveFinishedRecord(record) else { return false }
        didTransferFinishedRecord = true
        return true
    }
}
