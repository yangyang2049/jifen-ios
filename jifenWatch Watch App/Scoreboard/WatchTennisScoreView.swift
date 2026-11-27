import LinkCore
import LinkSync
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI

struct WatchTennisScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let maxSets: Int
    let linkedSessionId: UUID?
    let isDoubles: Bool
    @State private var showRecordSaveFailure = false
    @State private var linkedMatchHandle: LinkedMatchHandle?
    @State private var store: WatchReducerSessionStore<TennisMatchReducer>
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var localRecordID = "w_\(UUID().uuidString)"
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
    @State private var completedSetPresentation: WatchTennisCompletedSetPresentation?
    @State private var completedScoreTask: Task<Void, Never>?
    @State private var scoreEventToast: WatchScoreEventToastState?
    @State private var scoreEventToastTask: Task<Void, Never>?
    @State private var undoToastToken: UUID?

    init(
        maxSets: Int,
        initialState: TennisMatchState? = nil,
        linkedSessionId: UUID? = nil,
        isDoubles: Bool = false,
        resumeBundle: ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>? = nil,
        resumedStartTime: Date? = nil,
        resumedRestState: WatchRestState? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.maxSets = maxSets
        self.linkedSessionId = linkedSessionId
        self.isDoubles = isDoubles
        let gameType: GameType = isDoubles ? .tennisDoubles : .tennis
        let defaults = WatchDefaultTeamNames.resolve(for: gameType)
        let seed = resumeBundle?.currentSession.state ?? initialState ?? TennisMatchState(
            leftName: defaults.left,
            rightName: defaults.right,
            rules: TennisRuleSet(maxSets: maxSets)
        )
        let startedAt = resumedStartTime ?? Date()
        _store = State(initialValue: Self.makeStore(
            gameType: gameType, isDoubles: isDoubles, state: seed, resumeBundle: resumeBundle,
            resumedActionLog: resumedActionLog, startedAt: startedAt
        ))
        _matchStartTime = State(initialValue: startedAt)
        _restState = State(initialValue: resumedRestState)
    }

    private var gameType: GameType { isDoubles ? .tennisDoubles : .tennis }

    private static func makeStore(
        gameType: GameType,
        isDoubles: Bool,
        state: TennisMatchState,
        resumeBundle: ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>? = nil,
        resumedActionLog: WatchScoreActionLog? = nil,
        startedAt: Date
    ) -> WatchReducerSessionStore<TennisMatchReducer> {
        let binding = WatchBoardBindings.tennis(gameType: gameType, isDoubles: isDoubles)
        var actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        if state.rules.setScoringMode == .tiebreakOnly {
            actionLog.omitSecondaryScores()
        }
        if let resumeBundle {
            return WatchReducerSessionStore(
                resumeBundle: resumeBundle, reducer: TennisMatchReducer(),
                binding: binding, actionLog: actionLog, startedAt: startedAt
            )
        }
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: [
                .init(id: TeamID.team0.rawValue, name: state.leftName, role: "team"),
                .init(id: TeamID.team1.rawValue, name: state.rightName, role: "team")
            ]
        )
        return WatchReducerSessionStore(
            seedSession: session, reducer: TennisMatchReducer(), binding: binding,
            actionLog: actionLog, startedAt: startedAt
        )
    }

    private var linkedState: WatchLinkedMatchState {
        WatchLinkedMatchState(
            board: .racket, linkedSessionId: linkedSessionId,
            handle: linkedMatchHandle, linkService: linkService, store: store
        )
    }

    private var linkedMatchUnavailable: Bool { linkedState.isUnavailable }
    private var scoringLocked: Bool { linkedState.scoringLocked }
    private var canPlayAgain: Bool { linkedState.canPlayAgain }

    private var linkedMenuActions: [WatchMenuExtraAction] {
        linkedState.menuActions { showMenu = false }
    }

    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    private var pendingFinishUndoAction: (() -> Void)? {
        guard store.canUndo else { return nil }
        return { undoScoreboard() }
    }

    @ViewBuilder
    private var finishLayer: some View {
        if store.isPendingLinkedFinish, completedSetPresentation == nil {
            WatchLinkedFinishWaitingOverlay(
                onSync: { linkService.syncLinkedScores() },
                onUndo: pendingFinishUndoAction
            )
        } else if showFinishedOverlay {
            WatchFinishedOverlay(
                title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                scoreItems: [
                    WatchFinishedScoreItem(
                        name: store.state.leftName,
                        score: store.state.rules.setScoringMode == .tiebreakOnly
                            ? store.state.leftPoints
                            : store.state.leftSets,
                        doublesNames: store.state.doublesPlayerNames,
                        side: .left
                    ),
                    WatchFinishedScoreItem(
                        name: store.state.rightName,
                        score: store.state.rules.setScoringMode == .tiebreakOnly
                            ? store.state.rightPoints
                            : store.state.rightSets,
                        doublesNames: store.state.doublesPlayerNames,
                        side: .right
                    )
                ],
                undoAvailable: finishUndoAvailable,
                canPlayAgain: canPlayAgain,
                onUndo: undoFinish,
                onPlayAgain: playAgain,
                onExit: finishAndExit
            )
        }
    }

    var body: some View {
        scoreboardLayers
            .ignoresSafeArea()
            .watchFinishSaveFailure(isPresented: $showRecordSaveFailure) { finalizeFinish() }
            .onAppear {
                if !isDoubles {
                    scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
                }
                guard linkedSessionId == nil else { return }
                bindStateChanges()
                if store.state.finished {
                    beginProvisionalFinish()
                } else if restState == nil, let remoteBreak = store.state.officialBreakState {
                    restState = WatchRestState.fromOfficialBreak(remoteBreak)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
                guard !isDoubles else { return }
                scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            }
            .onChange(of: linkService.intentSync.update, initial: true) { _, update in
                applyLinkedUpdate(update)
            }
            .onDisappear {
                finishTask?.cancel()
                sideExchangeTask?.cancel()
                completedScoreTask?.cancel()
                scoreEventToastTask?.cancel()
                if linkedSessionId == nil, store.state.finished { finalizeFinish() }
                persistResumeSession()
                store.onStateChanged = nil
            }
    }

    private var scoreboardLayers: some View {
        ZStack {
            mainBoard
            if store.state.isTieBreak && !showMenu && restState == nil && !showFinishedOverlay {
                VStack {
                    Text(store.state.rules.tieBreakPoints == 10
                        ? NSLocalizedString("watch_tiebreak_indicator_10", value: "抢十", comment: "")
                        : NSLocalizedString("watch_tiebreak_indicator_7", value: "抢七", comment: ""))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.32))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.top, 8)
            }
            if showSideExchangeToast {
                WatchSideExchangeToast()
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
                        confirmation = linkedSessionId == nil ? .reset : .finish
                    },
                    extraActions: linkedMenuActions
                )
            }
            if let restState {
                WatchRestOverlay(
                    state: restState,
                    isReadOnly: scoringLocked,
                    onContinue: {
                        _ = updateOfficialBreak(nil)
                    },
                    onUndo: {
                        guard !scoringLocked, performUndoScoreboard() else { return }
                        if updateOfficialBreak(nil) { restTriggers.release(restState.triggerID) }
                    }
                )
            }
            finishLayer
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirm(confirmation) }
                )
            }
        }
    }

    private var mainBoard: some View {
        Group {
            if isDoubles, store.state.doublesPlayerNames != nil {
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
        let names = store.state.doublesPlayerNames ?? [
            store.state.leftName,
            store.state.rightName,
            store.state.leftName,
            store.state.rightName
        ]
        let layout = TeamScreenLayout(sidesSwapped: presentedSidesSwapped)
        let serverSlot = tennisDoublesServerSlot(state: store.state)
        return WatchDoublesBoard(
            left: tennisDoublesHalf(
                screenSide: .left,
                logicalSide: layout.engineSide(onScreen: .left),
                names: names,
                serverSlot: serverSlot
            ),
            right: tennisDoublesHalf(
                screenSide: .right,
                logicalSide: layout.engineSide(onScreen: .right),
                names: names,
                serverSlot: serverSlot
            )
        )
    }

    private func tennisDoublesHalf(
        screenSide: MatchSide,
        logicalSide: MatchSide,
        names: [String],
        serverSlot: Int
    ) -> WatchDoublesHalfModel {
        let isLeft = logicalSide == .left
        var topIndex = isLeft ? 0 : 1
        var bottomIndex = isLeft ? 2 : 3
        if screenSide == .right {
            swap(&topIndex, &bottomIndex)
        }
        let hasGames = store.state.rules.setScoringMode != .tiebreakOnly
            && presentedGamesTotal > 0
        let hasSets = store.state.rules.setScoringMode != .tiebreakOnly
            && presentedSetsTotal > 0
        let servingPosition: WatchDoublesHalfModel.PlayerPosition? = {
            guard completedSetPresentation == nil,
                  store.state.servingSide == logicalSide else { return nil }
            return serverSlot == bottomIndex ? .bottom : .top
        }()
        return WatchDoublesHalfModel(
            topName: names.indices.contains(topIndex) ? names[topIndex] : "",
            bottomName: names.indices.contains(bottomIndex) ? names[bottomIndex] : "",
            score: store.state.scoreDisplay(for: logicalSide),
            primaryMeta: hasGames
                ? "\(presentedGames(for: logicalSide))"
                : nil,
            secondaryMeta: hasSets
                ? "\(presentedSets(for: logicalSide))"
                : nil,
            color: isLeft ? Color(hex: 0xD93A34) : Color(hex: 0x1F78D1),
            servingPosition: servingPosition,
            onTap: {
                guard interactionsEnabled, !suppressTapAfterLongPress else { return }
                dispatchScore(.pointWon(logicalSide))
            }
        )
    }

    private func side(_ screenSide: MatchSide, size: CGSize) -> some View {
        let logical = TeamScreenLayout(sidesSwapped: presentedSidesSwapped).engineSide(onScreen: screenSide)
        let isLeftTeam = logical == .left
        let name = isLeftTeam
            ? store.state.doublesTeamDisplayName(for: .left)
            : store.state.doublesTeamDisplayName(for: .right)
        let pointText = store.state.scoreDisplay(for: logical)
        let sets = presentedSets(for: logical)
        let games = presentedGames(for: logical)
        let isServing = completedSetPresentation == nil && store.state.servingSide == logical
        let showMeta = store.state.rules.setScoringMode != .tiebreakOnly
        let hasSets = showMeta && presentedSetsTotal > 0
        let hasGames = showMeta && presentedGamesTotal > 0
        let mainScoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 48 : 52,
            scoreText: pointText,
            minimumSize: 34,
            availableWidth: size.width,
            horizontalPadding: 12
        )
        let scoreLabel = Text(pointText)
            .font(WatchScoreTypography.primaryScore(size: mainScoreFont))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)

        return ZStack {
            WatchScoreboardFace(isHorizontal: isHorizontal) {
                VStack(spacing: 3) {
                    Text(name)
                        .font(.system(size: WatchScoreTypography.teamNameSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(isHorizontal ? 2 : 1)
                        .minimumScaleFactor(isHorizontal ? 0.65 : 1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .frame(minHeight: isHorizontal && hasSets ? 26 : nil, alignment: .top)
                    if isHorizontal, hasSets {
                        tennisSetDots(count: sets, vertical: false)
                    }
                }
            } score: {
                if !isHorizontal, hasSets || hasGames {
                    HStack(spacing: 4) {
                        ZStack {
                            if hasGames {
                                Text("\(games)")
                                    .font(WatchScoreTypography.secondaryScore(size: 24))
                                    .monospacedDigit()
                            }
                        }
                        .frame(width: 32)
                        scoreLabel.frame(maxWidth: .infinity)
                        ZStack {
                            if hasSets {
                                tennisSetDots(count: sets, vertical: true)
                            }
                        }
                        .frame(width: 32)
                    }
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 16)
                } else {
                    scoreLabel
                }
            }

            if isHorizontal {
                if hasGames {
                    Text("\(games)")
                        .font(WatchScoreTypography.secondaryScore(size: 20))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 40)
                        .offset(y: WatchLayout.scoreboardMetaVerticalOffset)
                }
            }

            if isServing {
                servingIndicator(screenSide: screenSide)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(isLeftTeam ? WatchTheme.teamRed : WatchTheme.teamBlue)
        .contentShape(Rectangle())
        // VoiceOver：与抢分板同口径，整块面板读作「队名 比分」。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityScoreLabel(
            name: name,
            pointsText: pointText,
            sets: sets,
            isServing: isServing
        ))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard interactionsEnabled, !suppressTapAfterLongPress else { return }
            dispatchScore(.pointWon(logical))
        }
        .onTapGesture {
            guard interactionsEnabled, !suppressTapAfterLongPress else { return }
            dispatchScore(.pointWon(logical))
        }
    }

    private func accessibilityScoreLabel(
        name: String,
        pointsText: String,
        sets: Int,
        isServing: Bool
    ) -> String {
        var parts = [name, pointsText]
        parts.append(String(
            format: NSLocalizedString("watch_a11y_sets_format", value: "%d 局", comment: ""),
            sets
        ))
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

    @ViewBuilder
    private func tennisSetDots(count: Int, vertical: Bool) -> some View {
        if vertical {
            VStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 10, height: 10)
                }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 8, height: 8)
                }
            }
        }
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

    private func tennisDoublesServerSlot(state: TennisMatchState) -> Int {
        TennisDoublesServing.currentServerSlot(in: state)
            ?? (state.servingSide == .left ? 0 : 1)
    }

    private func handle(events: [TennisMatchEvent], state: TennisMatchState) {
        if let completed = WatchTennisCompletedSetPresentation.resolve(
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
        var handledGameCompletion = false
        for event in events {
            switch event {
            case .setCompleted(_, let setNumber, _, _, _, _):
                guard !state.finished else { continue }
                beginBetweenSetRest(setNumber: setNumber)
            case .gameCompleted(let winner, let leftGames, let rightGames, _):
                guard !WatchPreferences.shared.setBreakEnabled else { continue }
                handledGameCompletion = true
                showCompletedGameToast(
                    winner: winner,
                    leftGames: leftGames,
                    rightGames: rightGames,
                    state: state,
                    followWithSideExchange: sideExchangeRequested
                )
            case .sidesExchanged, .sidesExchangeReminder:
                if !handledGameCompletion {
                    showSideExchange()
                }
            case .matchFinished:
                if manualFinishRequested {
                    beginProvisionalFinish()
                } else {
                    beginAutomaticFinishPresentation()
                }
            default:
                break
            }
        }
        if state.finished, !showFinishedOverlay, completedScoreTask == nil {
            manualFinishRequested ? beginProvisionalFinish() : beginAutomaticFinishPresentation()
        }
    }

    private var presentedSidesSwapped: Bool {
        completedSetPresentation?.sidesSwapped ?? store.state.sidesSwapped
    }

    private var presentedGamesTotal: Int {
        if let completedSetPresentation {
            return completedSetPresentation.leftGames + completedSetPresentation.rightGames
        }
        return store.state.leftGames + store.state.rightGames
    }

    private var presentedSetsTotal: Int {
        if let completedSetPresentation {
            return completedSetPresentation.leftSets + completedSetPresentation.rightSets
        }
        return store.state.leftSets + store.state.rightSets
    }

    private func presentedGames(for side: MatchSide) -> Int {
        if let completedSetPresentation {
            return side == .left
                ? completedSetPresentation.leftGames
                : completedSetPresentation.rightGames
        }
        return side == .left ? store.state.leftGames : store.state.rightGames
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
        _ presentation: WatchTennisCompletedSetPresentation,
        state: TennisMatchState
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

    private func beginAutomaticFinishPresentation() {
        guard completedScoreTask == nil, !showFinishedOverlay else { return }
        completedScoreTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            completedScoreTask = nil
            beginProvisionalFinish()
        }
    }

    private func beginBetweenSetRest(setNumber: Int) {
        guard !scoringLocked, WatchPreferences.shared.setBreakEnabled else { return }
        let triggerID = "tennis-set-\(setNumber)"
        guard restTriggers.consume(triggerID) else { return }
        let nextRest = WatchRestState(
            kind: .betweenSets,
            title: NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: ""),
            durationSeconds: 120,
            triggerID: triggerID
        )
        if !updateOfficialBreak(nextRest) { restTriggers.release(triggerID) }
    }

    private func showCompletedGameToast(
        winner: MatchSide,
        leftGames: Int,
        rightGames: Int,
        state: TennisMatchState,
        followWithSideExchange: Bool
    ) {
        showScoreEventToast(
            WatchScoreEventToastState(
                title: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_tennis_game_title",
                        value: "第%d局结束",
                        comment: ""
                    ),
                    leftGames + rightGames
                ),
                detail: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_tennis_game_detail",
                        value: "%@胜 · 局分 %d:%d",
                        comment: ""
                    ),
                    state.doublesTeamDisplayName(for: winner),
                    leftGames,
                    rightGames
                )
            ),
            followWithSideExchange: followWithSideExchange
        )
    }

    private func showCompletedSetToast(
        _ presentation: WatchTennisCompletedSetPresentation,
        state: TennisMatchState,
        followWithSideExchange: Bool
    ) {
        let winner: MatchSide = presentation.leftGames > presentation.rightGames ? .left : .right
        showScoreEventToast(
            WatchScoreEventToastState(
                title: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_tennis_set_title",
                        value: "第%d盘结束",
                        comment: ""
                    ),
                    presentation.setNumber
                ),
                detail: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_tennis_set_detail",
                        value: "%@胜 %d:%d · 盘分 %d:%d",
                        comment: ""
                    ),
                    state.doublesTeamDisplayName(for: winner),
                    presentation.leftGames,
                    presentation.rightGames,
                    presentation.leftSets,
                    presentation.rightSets
                )
            ),
            followWithSideExchange: followWithSideExchange
        )
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
        guard !showFinishedOverlay, linkedSessionId == nil || store.isLinkedFinishConfirmed else { return }
        sideExchangeTask?.cancel()
        scoreEventToastTask?.cancel()
        restState = nil
        showMenu = false
        showSideExchangeToast = false
        scoreEventToast = nil
        scoreEventToastTask = nil
        showFinishedOverlay = true
        if linkedSessionId != nil {
            finishUndoAvailable = false
            didFinalizeFinish = store.savedRecordID != nil
            return
        }
        finishUndoAvailable = !scoringLocked && store.canUndo
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
        if linkedSessionId != nil {
            guard !linkedMatchUnavailable, store.isLinkedFinishConfirmed else { return false }
            if store.savedRecordID == nil {
                linkService.intentSync.retryPendingAfterReconnect()
                store.applyLinkedIntentUpdate(linkService.intentSync.update)
            }
            guard store.savedRecordID != nil else {
                showRecordSaveFailure = true
                return false
            }
            didFinalizeFinish = true
            if resumeStore.session?.linkHandle == linkedMatchHandle { resumeStore.clear() }
            return true
        }
        guard store.state.finished, !didFinalizeFinish else { return true }
        finishUndoAvailable = false
        let saved = store.saveFinishedRecord(
            into: resumeStore, gameType: gameType, recordID: localRecordID, endTime: Date()
        )
        guard saved else {
            showRecordSaveFailure = true
            return false
        }
        didFinalizeFinish = true
        resumeStore.clear()
        return true
    }

    private func undoFinish() {
        guard finishUndoAvailable, !scoringLocked, store.undo() else { return }
        completedScoreTask?.cancel()
        completedScoreTask = nil
        completedSetPresentation = nil
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didFinalizeFinish = false
        undoToastToken = UUID()
    }

    private func undoScoreboard() {
        performUndoScoreboard()
    }

    @discardableResult
    private func performUndoScoreboard() -> Bool {
        if linkedSessionId != nil {
            let previous = store.state
            guard !linkedMatchUnavailable, !store.isLinkedFinishConfirmed,
                  store.undoLinked(), store.state != previous else { return false }
            if !store.state.finished {
                resetLinkedFinishPresentation()
                restState = WatchRestState.fromOfficialBreak(store.state.officialBreakState)
            }
            persistResumeSession()
        } else if !store.undo() {
            return false
        }
        undoToastToken = UUID()
        return true
    }

    private func playAgain() {
        if linkedSessionId != nil {
            guard canPlayAgain else { return }
            store.requestLinkedNextMatch()
            return
        }
        guard !scoringLocked else { return }
        guard finalizeFinish() else { return }
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
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
        if linkedSessionId != nil {
            if store.requestLinkedFinish() { persistResumeSession() }
            return
        }
        switch value {
        case .finish:
            manualFinishRequested = true
            if case .rejected = store.dispatch(.finish) {
                manualFinishRequested = false
            }
        case .reset:
            resumeStore.clear()
            finishTask?.cancel()
            showFinishedOverlay = false
            restState = nil
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
        let result = TennisMatchReducer().reduce(
            state: store.state,
            intent: .reset,
            at: Int64(timestamp.timeIntervalSince1970 * 1_000)
        )
        guard result.accepted else { return }
        store.onStateChanged = nil
        store = Self.makeStore(
            gameType: gameType, isDoubles: isDoubles, state: result.state, startedAt: timestamp
        )
        bindStateChanges()
        matchStartTime = timestamp
        localRecordID = "w_\(UUID().uuidString)"
    }

    private func bindStateChanges() {
        store.onStateChanged = { state, events in
            handle(events: events, state: state)
            persistResumeSession()
        }
    }

    private func dispatchScore(_ intent: TennisMatchIntent) {
        if linkedSessionId != nil {
            guard !scoringLocked else { return }
            guard case .accepted(let session, let events) = store.dispatch(intent) else { return }
            handle(events: events, state: session.state)
            persistResumeSession()
        } else {
            store.dispatch(intent)
        }
    }

    private func applyLinkedUpdate(_ update: WatchLinkedIntentUpdate?) {
        guard let linkedSessionId, let update, update.handle.sessionId == linkedSessionId,
              update.handle == linkService.activeHandle,
              update.displayedSnapshot.tennisState != nil else { return }
        let previous = store.state
        let wasAttached = linkedMatchHandle != nil
        if let linkedMatchHandle {
            guard linkedMatchHandle == update.handle else { return }
            store.applyLinkedIntentUpdate(update)
        } else {
            linkedMatchHandle = update.handle
            store.attachLinkedMatch(
                update.handle, sync: linkService.intentSync,
                intent: { .tennis($0) }, state: { $0.tennisState }
            )
        }
        guard store.linkedIntentUpdate?.presentationSequence == update.presentationSequence else { return }
        matchStartTime = store.startedAt

        if store.isPendingLinkedFinish {
            showMenu = false
            confirmation = nil
            restState = nil
        } else if store.isLinkedFinishConfirmed {
            restState = nil
            showMenu = false
            confirmation = nil
            finishTask?.cancel()
            finishUndoAvailable = false
            didFinalizeFinish = store.savedRecordID != nil
            if didFinalizeFinish { showRecordSaveFailure = false }
            beginAutomaticFinishPresentation()
        } else {
            if previous.finished || showFinishedOverlay {
                resetLinkedFinishPresentation()
            }
            if !wasAttached || previous.officialBreakState != store.state.officialBreakState {
                restState = WatchRestState.fromOfficialBreak(store.state.officialBreakState)
            }
        }
        persistResumeSession()
    }

    private func resetLinkedFinishPresentation() {
        completedScoreTask?.cancel()
        completedScoreTask = nil
        completedSetPresentation = nil
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didFinalizeFinish = false
    }

    @discardableResult
    private func updateOfficialBreak(_ rest: WatchRestState?) -> Bool {
        guard !scoringLocked else { return false }
        let mapped = rest?.officialBreakState(for: gameType)
        if linkedSessionId != nil, store.state.officialBreakState != mapped {
            guard case .accepted = store.dispatchNonUndoable(.setOfficialBreakState(mapped)) else { return false }
        }
        restState = rest
        persistResumeSession()
        return true
    }

    private func exitBoard() {
        guard !store.isPendingLinkedFinish else { return }
        if let linkedSessionId {
            guard !linkedMatchUnavailable else { return }
            linkService.exitScoreboard(sessionId: linkedSessionId)
        }
        dismiss()
    }

    private func persistResumeSession() {
        WatchRacketResumeDraft.persist(
            into: resumeStore,
            linkedSessionId: linkedSessionId,
            handle: linkedMatchHandle,
            activeHandle: linkService.activeHandle,
            isFinished: store.state.finished,
            didFinalizeFinish: didFinalizeFinish,
            hasProgress: hasTennisProgress,
            startedAt: matchStartTime,
            scoreLine: store.scoreLine,
            emoji: store.binding.emoji,
            actionLog: store.actionLog,
            payload: {
                .tennis(isDoubles: isDoubles, bundle: store.resumeBundle(), restState: restState)
            }
        )
    }

    private var hasTennisProgress: Bool {
        let state = store.state
        return state.leftPoints != 0 || state.rightPoints != 0
            || state.leftGames != 0 || state.rightGames != 0
            || state.leftSets != 0 || state.rightSets != 0
    }
}
