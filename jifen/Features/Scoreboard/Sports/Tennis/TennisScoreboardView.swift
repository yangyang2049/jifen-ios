import LinkCore
import ScoreCore
import SwiftUI
import UIKit

private struct TennisTerminalGamePresentation: Equatable {
    let leftPointText: String
    let rightPointText: String
    let leftGames: Int
    let rightGames: Int
    let leftSets: Int
    let rightSets: Int
    let sidesSwapped: Bool
}

enum TennisTieBreakIndicatorLayout {
    static func topCenter(
        viewportSize: CGSize,
        safeAreaTop: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: viewportSize.width / 2,
            y: max(safeAreaTop, ScoreboardConstants.buttonPadding)
                + ScoreboardConstants.buttonSize / 2
        )
    }
}

private struct TennisTieBreakIndicator: View {
    let targetPoints: Int

    var body: some View {
        Text(targetPoints == 10
            ? NSLocalizedString("tennis_tiebreak_option_10", value: "抢十", comment: "")
            : NSLocalizedString("tennis_tiebreak_option_7", value: "抢七", comment: ""))
            .font(.system(size: Theme.usesPadLayout ? 14 : 12, weight: .semibold))
            .padding(.horizontal, Theme.usesPadLayout ? 12 : 10)
            .padding(.vertical, Theme.usesPadLayout ? 7 : 6)
            .background(Capsule().fill(Color(white: 0.34)))
            .foregroundStyle(.white)
            .allowsHitTesting(false)
            .accessibilityIdentifier("tennis_tiebreak_indicator")
    }
}

/// Tennis scoreboard driven by `TennisSessionStore` / ScoreCore reducer.
struct TennisScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    @State private var store: TennisSessionStore
    @State private var watchSessionId: UUID?
    @State private var showMenu = false
    @State private var showDisplaySettings = false
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession: ScoreboardTypographySession
    @State private var preferences = PreferencesManager.shared
    @State private var toastMessage: String?
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var exitConfirmDeadline: Date?
    @State private var manualFinishRequested = false
    @State private var isEditMode = false
    @State private var editLeftName = ""
    @State private var editRightName = ""
    @State private var editDoublesNames = ["", "", "", ""]
    @State private var flashSlots: Set<Int> = []
    @State private var flashActive = false
    @State private var flashTask: Task<Void, Never>?
    @State private var isStartingNewMatch = false
    @State private var terminalHold = ScoreboardTerminalHold<TennisTerminalGamePresentation>()
    @State private var didSpeakOpeningAnnouncement = false

    init(
        onNavigationBack: (() -> Void)? = nil,
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil
    ) {
        self.onNavigationBack = onNavigationBack
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed

        let setup = initialSetup
        let isDoubles = !(setup?.isSingles ?? true)
        let gameType: ScoreCore.GameType = isDoubles ? .tennisDoubles : .tennis
        let rules = TennisRuleSet(
            maxSets: setup?.maxSets ?? 3,
            tieBreakPoints: setup?.tieBreakPoints == 10 ? 10 : 7,
            gamesPerSet: setup?.gamesPerSet ?? 6,
            setScoringMode: setup?.setScoringMode == "tiebreak_only" ? .tiebreakOnly : .regular,
            matchCompletionMode: setup?.matchCompletionMode ?? .bestOf,
            usesNoAdScoring: setup?.tennisDeuceMode == "no_ad",
            autoChangeSides: setup?.autoChangeSides ?? true
        )
        let opening: MatchSide = setup?.servingSide == MatchSide.right.rawValue ? .right : .left
        let defaults = DefaultParticipantNames.resolve(for: .tennis, isSingles: !isDoubles)
        let left = resolvedScoreboardSetupName(
            setup?.team1Name,
            fallback: defaults.left
        )
        let right = resolvedScoreboardSetupName(
            setup?.team2Name,
            fallback: defaults.right
        )
        let doublesNames: [String]? = isDoubles ? [
            setup?.team1Player1Name ?? "",
            setup?.team2Player1Name ?? "",
            setup?.team1Player2Name ?? "",
            setup?.team2Player2Name ?? ""
        ] : nil
        var tennisState = TennisMatchState(
            leftName: left,
            rightName: right,
            rules: rules,
            openingServer: opening,
            doublesPlayerNames: doublesNames
        )
        if isDoubles {
            tennisState.leftName = tennisState.doublesTeamDisplayName(for: .left)
            tennisState.rightName = tennisState.doublesTeamDisplayName(for: .right)
        }
        _store = State(initialValue: TennisSessionStore(
            gameType: gameType,
            state: tennisState,
            voiceAnnouncementEnabled: setup?.voiceAnnouncement == true
        ))
        _typographySession = State(initialValue: ScoreboardTypographySession(
            styleID: ScoreboardStyleID(scoreCoreGameType: gameType)
        ))
        _watchSessionId = State(initialValue: setup?.linkedWatchSessionId)
    }

    private var linkScoringLocked: Bool {
        watchSessionId != nil
            && (watchLinkService.isFollower || watchLinkService.isAuthorityTransferPending)
    }
    private var terminalGamePresentation: TennisTerminalGamePresentation? { terminalHold.value }
    private var scoringLocked: Bool {
        terminalGamePresentation != nil || linkScoringLocked
    }

    private var linkedNewGameLabel: String {
        NSLocalizedString(
            "game_over_new_game_on_watch",
            value: "再来一场\n（请在手表端操作）",
            comment: ""
        )
    }

    private var finishedWinnerName: String {
        switch winnerSide(for: store.state) {
        case .left: store.state.leftName
        case .right: store.state.rightName
        case nil: ""
        }
    }

    private func winnerSide(for state: TennisMatchState) -> MatchSide? {
        let left = state.rules.setScoringMode == .tiebreakOnly ? state.leftPoints : state.leftSets
        let right = state.rules.setScoringMode == .tiebreakOnly ? state.rightPoints : state.rightSets
        return left == right ? nil : (left > right ? .left : .right)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let serveIndicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                halfViewportSize: CGSize(width: size.width / 2, height: size.height)
            )
            ZStack {
                HStack(spacing: 0) {
                    let halfSize = CGSize(width: size.width / 2, height: size.height)
                    half(.left, size: halfSize)
                    half(.right, size: halfSize)
                }
                if terminalGamePresentation == nil,
                   !isEditMode,
                   !store.state.finished {
                    if store.state.doublesPlayerNames == nil {
                        CenterLineServeIndicator(
                            isLeftServing: logicalSide(forScreen: .left) == store.state.servingSide,
                            triangleSize: serveIndicatorSize
                        )
                        .position(x: size.width / 2, y: size.height / 2)
                    } else if let isLeftServing = tennisDoublesServerIsLeftScreen,
                              let isTopRow = tennisDoublesServerIsTopRow {
                        CenterLineServeIndicator(
                            isLeftServing: isLeftServing,
                            triangleSize: serveIndicatorSize
                        )
                        .position(
                            x: size.width / 2,
                            y: ScoreboardServeGeometry.doublesAnchorY(
                                height: size.height,
                                topRow: isTopRow
                            )
                        )
                    }
                }
                if shouldShowChrome {
                    VStack {
                        HStack {
                            Spacer()
                            if (isEditMode || !store.state.finished), !scoringLocked {
                                Button(action: toggleEditMode) {
                                    Image(systemName: isEditMode ? "checkmark" : "pencil")
                                        .font(.system(size: ScoreboardConstants.buttonIconSize))
                                        .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                        .background(Circle().fill(
                                            isEditMode ? Color(hex: "00C853") : Color.black.opacity(0.35)
                                        ))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isEditMode
                                    ? NSLocalizedString("done", value: "完成", comment: "")
                                    : NSLocalizedString("edit", value: "编辑", comment: ""))
                                .accessibilityIdentifier("tennis_scoreboard_edit_button")
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.trailing, ScoreboardConstants.buttonPadding)
                        .padding(.top, ScoreboardConstants.buttonPadding)
                        Spacer()
                    }
                    .zIndex(2)
                }
                if terminalGamePresentation == nil, store.state.isTieBreak {
                    TennisTieBreakIndicator(targetPoints: store.state.rules.tieBreakPoints)
                        .position(TennisTieBreakIndicatorLayout.topCenter(
                            viewportSize: size,
                            safeAreaTop: proxy.safeAreaInsets.top
                        ))
                        .zIndex(3)
                }
                if terminalGamePresentation == nil, !isEditMode, !store.state.finished {
                    ScoreboardKeyPointBadgeLayer(
                        status: KeyPointResolver.tennis(snapshot: tennisKeyPointSnapshot(store.state)),
                        gameType: store.gameType,
                        sidesSwapped: store.state.sidesSwapped,
                        doublesTopRow: store.gameType == .tennisDoubles ? tennisDoublesServerIsTopRow : nil,
                        serveIndicatorSize: serveIndicatorSize
                    )
                }
                if showGameOverDialog {
                    GameOverDialog(
                        winnerName: finishedWinnerName,
                        gameType: GameType(scoreCoreGameType: store.gameType) ?? .tennis,
                        resultText: store.state.rules.setScoringMode == .tiebreakOnly
                            ? "\(store.state.leftPoints):\(store.state.rightPoints)"
                            : nil,
                        leftName: store.state.leftName,
                        rightName: store.state.rightName,
                        leftScore: store.state.rules.setScoringMode == .tiebreakOnly
                            ? store.state.leftPoints
                            : store.state.leftSets,
                        rightScore: store.state.rules.setScoringMode == .tiebreakOnly
                            ? store.state.rightPoints
                            : store.state.rightSets,
                        newGameLabel: scoringLocked ? linkedNewGameLabel : nil,
                        newGameDisabled: scoringLocked || isStartingNewMatch,
                        onNewGame: {
                            startNewMatch()
                        },
                        onRecords: {
                            store.persistSnapshot { success in
                                guard success else { return }
                                showFinishedRecordDetail = true
                            }
                        },
                        onShare: {
                            shareFinishedMatch()
                        },
                        onExit: {
                            store.persistSnapshot { success in
                                guard success else { return }
                                goBack()
                            }
                        }
                    )
                }
                MenuDialog(
                    isVisible: showMenu,
                    onClose: {
                        menuConfirm.clear()
                        showMenu = false
                    },
                    onMenuItemClick: handleMenu,
                    showEndGame: true,
                    items: menuItems,
                    analyticsGameType: GameType(scoreCoreGameType: store.gameType) ?? .tennis
                )
                if shouldShowChrome, !isEditMode, !showMenu, !showGameOverDialog {
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: requestBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .foregroundStyle(.white)
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(Circle().fill(Color.black.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(ScoreboardConstants.backButtonAccessibilityID)
                            .padding(.leading, ScoreboardConstants.buttonPadding)
                            .padding(.bottom, ScoreboardConstants.buttonPadding)
                            Spacer()
                            Button {
                                showMenu = true
                                revealImmersiveChrome()
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .foregroundStyle(.white)
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(Circle().fill(Color.black.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(NSLocalizedString("menu", value: "菜单", comment: "Menu"))
                            .accessibilityIdentifier("scoreboard_menu_button")
                            .padding(.trailing, ScoreboardConstants.buttonPadding)
                            .padding(.bottom, ScoreboardConstants.buttonPadding)
                        }
                    }
                    .zIndex(100)
                }
                if appearance.immersiveMode,
                   !chromeVisible,
                   !isEditMode,
                   !showGameOverDialog {
                    ImmersiveCornerRevealZones(onReveal: revealImmersiveChrome)
                }
                if let toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: toastMessage)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    guard !isEditMode else { return }
                    showMenu = true
                    revealImmersiveChrome()
                }
        )
        .onAppear {
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            onSetupConsumed?()
            if let id = initialResumeSessionId, let uuid = UUID(uuidString: id),
               let restored = TennisSessionStore(restoring: uuid) {
                store = restored
            }
            typographySession.switchStyleID(ScoreboardStyleID(scoreCoreGameType: store.gameType))
            syncEditNamesFromState()
            registerScoreboardSync()
            if let watchSessionId,
               let update = watchLinkService.attachPage(sessionId: watchSessionId),
               let tennis = update.snapshot.tennisState {
                Task {
                    _ = await store.applyAuthoritativeState(
                        tennis,
                        detailedActions: update.detailedActions,
                        revision: update.revision,
                        matchGeneration: update.matchGeneration,
                        persistFormalRecord: false
                    )
                }
            }
            revealImmersiveChrome()
            if store.state.finished { showGameOverDialog = true }
            speakOpeningAnnouncementIfNeeded()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: store.state) { _, state in
            if terminalGamePresentation == nil {
                publishCurrentTennisState()
            }
            if state.finished, !isEditMode {
                if terminalGamePresentation == nil { notifyLinkedFinishIfNeeded() }
            }
        }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId,
                  let update,
                  update.sessionId == watchSessionId,
                  let tennis = update.snapshot.tennisState else { return }
            let snapshotFinished = tennis.finished
            cancelTerminalGamePresentation()
            Task {
                let applied = await store.applyAuthoritativeState(
                    tennis,
                    detailedActions: update.detailedActions,
                    revision: update.revision,
                    matchGeneration: update.matchGeneration,
                    persistFormalRecord: false
                )
                if applied {
                    // Reactive to the linked device's finished flag (mirrors
                    // HarmonyOS: follower auto-shows the finish dialog when the
                    // received snapshot is finished, and dismisses it when a new
                    // unfinished match arrives after 再来一场).
                    showGameOverDialog = snapshotFinished
                }
            }
        }
        .onChange(of: watchLinkService.pendingTakeoverApplication) { _, pending in
            guard let watchSessionId,
                  let pending,
                  pending.sessionId == watchSessionId,
                  let state = pending.snapshot.tennisState else { return }
            cancelTerminalGamePresentation()
            Task {
                let applied = await store.applyAuthoritativeState(
                    state,
                    detailedActions: pending.detailedActions,
                    revision: pending.revision
                )
                if applied, state.finished { showGameOverDialog = true }
                watchLinkService.completePhoneTakeover(messageId: pending.messageId)
            }
        }
        .onChange(of: showMenu) { _, isOpen in
            if !isOpen { menuConfirm.clear() }
            updateImmersiveForBlocking()
        }
        .onChange(of: showDisplaySettings) { _, _ in
            updateImmersiveForBlocking()
        }
        .onChange(of: typographySession.effectivePreference) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: isEditMode) { _, _ in
            updateImmersiveForBlocking()
        }
        .onChange(of: showGameOverDialog) { _, _ in
            updateImmersiveForBlocking()
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.tennis.adjustableMetrics
        )
        .alert(
            NSLocalizedString("linked_score_watch_reclaim_title", value: "手表请求重新接管", comment: ""),
            isPresented: Binding(
                get: { watchLinkService.pendingReclaimRequest != nil },
                set: { presented in
                    if !presented, watchLinkService.pendingReclaimRequest != nil {
                        watchLinkService.resolveReclaimRequest(
                            accepted: false,
                            snapshot: nil,
                            detailedActions: []
                        )
                    }
                }
            )
        ) {
            Button(NSLocalizedString("linked_score_accept", value: "同意", comment: "")) {
                watchLinkService.resolveReclaimRequest(
                    accepted: true,
                    snapshot: .tennis(store.state),
                    detailedActions: store.actionTimeline
                )
            }
            Button(NSLocalizedString("linked_score_reject", value: "拒绝", comment: ""), role: .cancel) {
                watchLinkService.resolveReclaimRequest(
                    accepted: false,
                    snapshot: nil,
                    detailedActions: []
                )
            }
        } message: {
            Text(NSLocalizedString("linked_score_watch_reclaim_message", value: "是否允许手表在 5 秒内重新接管计分？", comment: ""))
        }
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: store.sessionId.uuidString)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ModalCloseButton { showFinishedRecordDetail = false }
                        }
                    }
            }
        }
        .onChange(of: store.persistenceFailureSignal) { _, signal in
            guard signal > 0 else { return }
            toastMessage = NSLocalizedString(
                "scoreboard_save_failed",
                value: "保存失败，请稍后重试",
                comment: "Scoreboard persistence failed"
            )
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            flashTask?.cancel()
            cancelTerminalGamePresentation()
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
            let skipPersist = watchSessionId != nil
                && (watchLinkService.isFollower || watchLinkService.finishedRecordId != nil)
            if let watchSessionId {
                watchLinkService.detachPage(sessionId: watchSessionId)
            }
            if !skipPersist {
                store.persistSnapshot()
            }
        }
    }

    @ViewBuilder
    private func half(_ screenSide: MatchSide, size: CGSize) -> some View {
        if store.state.doublesPlayerNames != nil {
            doublesHalf(screenSide, size: size)
        } else {
            singlesHalf(screenSide, size: size)
        }
    }

    private func singlesHalf(_ screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let isLeft = side == .left
        return ZStack {
            (isLeft ? appearance.theme.palette.left : appearance.theme.palette.right)
            if isEditMode {
                tennisSinglesEditContent(screenSide: screenSide, side: side, size: size)
            } else {
                tennisSinglesPlayContent(screenSide: screenSide, side: side, size: size)
            }
        }
        .foregroundStyle(appearance.theme.palette.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !store.state.finished, !scoringLocked else { return }
            handlePointWon(side)
        }
        .onTapGesture(count: 2) {
            guard !isEditMode, !store.state.finished,
                  appearance.doubleTapSubtract, !scoringLocked else { return }
            dispatch(.adjustPoints(side: side, delta: -1))
        }
        .gesture(scoreboardDragGesture(for: side))
    }

    private func tennisSinglesPlayContent(
        screenSide: MatchSide,
        side: MatchSide,
        size: CGSize
    ) -> some View {
        let name = side == .left ? store.state.leftName : store.state.rightName
        let typography = resolvedTennisTypography(side: side, name: name, size: size)
        let nameSize = typography.nameFontSize
        let nameRegionHeight = ScoreboardLayoutMetrics.tennisSinglesNameRegionHeight(
            panelHeight: size.height,
            nameFontSize: nameSize
        )

        return VStack(spacing: 0) {
            Text(name)
                .font(typographyPreference.font.swiftUIFont(size: nameSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 72)
                .frame(maxWidth: .infinity)
                .frame(height: nameRegionHeight, alignment: .bottom)
            Spacer(minLength: 0)
            tennisScoreRow(
                screenSide: screenSide,
                side: side,
                height: size.height * 0.56,
                panelSize: size
            )
            Spacer(minLength: 0)
            Color.clear
                .frame(height: nameRegionHeight)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tennisSinglesEditContent(screenSide: MatchSide, side: MatchSide, size: CGSize) -> some View {
        let isLeft = side == .left
        let points = store.state.scoreDisplay(for: side)
        let games = isLeft ? store.state.leftGames : store.state.rightGames
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let typography = resolvedTennisTypography(
            side: side,
            name: isLeft ? editLeftName : editRightName,
            size: size,
            scoreBaseScale: 0.72,
            reservedHeight: 80
        )
        let mainSize = ScoreboardLayoutMetrics.editMainScoreFontSize(
            regularSize: typography.scoreFontSize
        )
        let secondarySize = typography.secondaryFontSize * 0.72
        return VStack(spacing: Theme.usesPadLayout ? 16 : 8) {
            tennisSinglesEditNameField(side: side)

            tennisEditAdjustRow(
                label: "",
                value: points,
                fontSize: mainSize,
                canDecrement: (isLeft ? store.state.leftPoints : store.state.rightPoints) > 0,
                onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { adjustPointsInEdit(side: side, delta: 1) }
            )

            if store.state.rules.setScoringMode != .tiebreakOnly {
                tennisEditAdjustRow(
                    label: screenSide == .left
                        ? NSLocalizedString("tennis_game_score", value: "局分", comment: "")
                        : "",
                    value: "\(games)",
                    fontSize: secondarySize,
                    canDecrement: games > 0,
                    useSecondaryColor: true,
                    labelHorizontalOffset: ScoreboardLayoutMetrics.sharedCenterLabelHorizontalOffset(
                        halfViewportWidth: size.width,
                        sourceScreenSide: screenSide
                    ),
                    onDecrement: { dispatch(.adjustGames(side: side, delta: -1)) },
                    onIncrement: { adjustGamesInEdit(side: side, delta: 1) }
                )
                tennisEditAdjustRow(
                    label: screenSide == .left
                        ? NSLocalizedString("tennis_set_score", value: "盘分", comment: "")
                        : "",
                    value: "\(sets)",
                    fontSize: secondarySize,
                    canDecrement: sets > 0,
                    useSecondaryColor: true,
                    labelHorizontalOffset: ScoreboardLayoutMetrics.sharedCenterLabelHorizontalOffset(
                        halfViewportWidth: size.width,
                        sourceScreenSide: screenSide
                    ),
                    onDecrement: { dispatch(.adjustSets(side: side, delta: -1)) },
                    onIncrement: { adjustSetsInEdit(side: side, delta: 1) }
                )
            }
        }
        .padding(.horizontal, Theme.usesPadLayout ? 36 : 16)
        .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: size.height, isEditMode: true))
        .padding(.bottom, Theme.usesPadLayout ? 36 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func doublesHalf(_ screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let isLeft = side == .left
        let names = store.state.doublesPlayerNames ?? []
        let slots = tennisDoublesDisplaySlots(screenSide: screenSide, logicalSide: side)
        let serverSlot = store.state.finished
            ? nil
            : TennisDoublesServing.currentServerSlot(in: store.state)
        let receiverSlot = store.state.finished
            ? nil
            : TennisDoublesServing.currentReceiverSlot(in: store.state)
        let rowHeight = size.height / 3
        let longestName = names.max(by: { $0.count < $1.count }) ?? ""
        let nameFontSize = resolvedTennisTypography(
            side: side,
            name: longestName,
            size: CGSize(width: size.width, height: rowHeight),
            scoreText: "",
            secondaryText: "",
            referenceHeight: size.height
        ).nameFontSize

        return ZStack {
            isLeft ? appearance.theme.palette.left : appearance.theme.palette.right
            if isEditMode {
                tennisDoublesEditContent(
                    screenSide: screenSide,
                    side: side,
                    slots: slots,
                    size: size
                )
            } else {
                VStack(spacing: 0) {
                    tennisDoublesNameRow(
                        name: names.indices.contains(slots.top) ? names[slots.top] : "",
                        slot: slots.top,
                        isServer: serverSlot == slots.top,
                        isReceiver: receiverSlot == slots.top,
                        fontSize: nameFontSize,
                        height: rowHeight
                    )
                    Spacer(minLength: 0)
                    tennisDoublesNameRow(
                        name: names.indices.contains(slots.bottom) ? names[slots.bottom] : "",
                        slot: slots.bottom,
                        isServer: serverSlot == slots.bottom,
                        isReceiver: receiverSlot == slots.bottom,
                        fontSize: nameFontSize,
                        height: rowHeight
                    )
                }
                tennisScoreRow(
                    screenSide: screenSide,
                    side: side,
                    height: ScoreboardLayoutMetrics.doublesScoreRegionHeight(panelHeight: size.height),
                    panelSize: size
                )
            }
        }
        .foregroundStyle(appearance.theme.palette.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !store.state.finished, !scoringLocked else { return }
            handlePointWon(side)
        }
        .onTapGesture(count: 2) {
            guard !isEditMode, !store.state.finished,
                  appearance.doubleTapSubtract, !scoringLocked else { return }
            dispatch(.adjustPoints(side: side, delta: -1))
        }
        .gesture(scoreboardDragGesture(for: side))
    }

    private func tennisDoublesEditContent(
        screenSide: MatchSide,
        side: MatchSide,
        slots: (top: Int, bottom: Int),
        size: CGSize
    ) -> some View {
        let isLeft = side == .left
        let points = store.state.scoreDisplay(for: side)
        let games = displayedGames(for: side)
        let sets = displayedSets(for: side)
        let longestName = [
            editDoublesNames.indices.contains(slots.top) ? editDoublesNames[slots.top] : "",
            editDoublesNames.indices.contains(slots.bottom) ? editDoublesNames[slots.bottom] : ""
        ].max(by: { $0.count < $1.count }) ?? ""
        let typography = resolvedTennisTypography(
            side: side,
            name: longestName,
            size: size
        )
        let nameSpacing: CGFloat = Theme.usesPadLayout ? 8 : 4
        let topPadding = ScoreboardLayoutMetrics.nameTopPadding(
            panelHeight: size.height,
            isEditMode: true
        )
        let scoreboardScreenWidth = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let namesHeight = ScoreboardLayoutMetrics.doublesEditNamesRegionHeight(
            isLargeScreen: Theme.usesPadLayout,
            screenWidth: scoreboardScreenWidth
        )
        let hasSecondaryRows = store.state.rules.setScoringMode != .tiebreakOnly
        let editLayout = ScoreboardLayoutMetrics.tennisDoublesEditLayout(
            regularMainSize: typography.scoreFontSize,
            regularSecondarySize: typography.secondaryFontSize,
            panelHeight: size.height,
            namesRegionHeight: namesHeight,
            secondaryRowCount: hasSecondaryRows ? 2 : 0,
            isLargeScreen: Theme.usesPadLayout
        )

        return VStack(spacing: 0) {
            VStack(spacing: nameSpacing) {
                tennisDoublesEditNameField(
                    slot: slots.top
                )
                tennisDoublesEditNameField(
                    slot: slots.bottom
                )
            }
            .padding(.horizontal, Theme.usesPadLayout ? 12 : 8)
            .padding(.top, Theme.usesPadLayout ? 12 : 6)
            .frame(height: namesHeight, alignment: .top)

            VStack(spacing: editLayout.contentSpacing) {
                tennisEditAdjustRow(
                    label: "",
                    value: points,
                    fontSize: editLayout.mainFontSize,
                    canDecrement: (isLeft ? store.state.leftPoints : store.state.rightPoints) > 0,
                    controlSize: editLayout.controlVisualSize,
                    labelFontSize: editLayout.labelFontSize,
                    onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                    onIncrement: { adjustPointsInEdit(side: side, delta: 1) }
                )

                if hasSecondaryRows {
                    tennisEditAdjustRow(
                        label: screenSide == .left
                            ? NSLocalizedString("tennis_game_score", value: "局分", comment: "")
                            : "",
                        value: "\(games)",
                        fontSize: editLayout.secondaryFontSize,
                        canDecrement: games > 0,
                        useSecondaryColor: true,
                        controlSize: editLayout.controlVisualSize,
                        labelFontSize: editLayout.labelFontSize,
                        labelHorizontalOffset: ScoreboardLayoutMetrics.sharedCenterLabelHorizontalOffset(
                            halfViewportWidth: size.width,
                            sourceScreenSide: screenSide
                        ),
                        onDecrement: { dispatch(.adjustGames(side: side, delta: -1)) },
                        onIncrement: { adjustGamesInEdit(side: side, delta: 1) }
                    )
                    tennisEditAdjustRow(
                        label: screenSide == .left
                            ? NSLocalizedString("tennis_set_score", value: "盘分", comment: "")
                            : "",
                        value: "\(sets)",
                        fontSize: editLayout.secondaryFontSize,
                        canDecrement: sets > 0,
                        useSecondaryColor: true,
                        controlSize: editLayout.controlVisualSize,
                        labelFontSize: editLayout.labelFontSize,
                        labelHorizontalOffset: ScoreboardLayoutMetrics.sharedCenterLabelHorizontalOffset(
                            halfViewportWidth: size.width,
                            sourceScreenSide: screenSide
                        ),
                        onDecrement: { dispatch(.adjustSets(side: side, delta: -1)) },
                        onIncrement: { adjustSetsInEdit(side: side, delta: 1) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier(screenSide == .left
            ? "tennis_doubles_left_edit_panel"
            : "tennis_doubles_right_edit_panel")
    }

    private func tennisSinglesEditNameField(side: MatchSide) -> some View {
        ScoreboardNameEditorField(
            placeholder: NSLocalizedString("setup_player_name", value: "选手名称", comment: ""),
            text: side == .left ? $editLeftName : $editRightName,
            nameType: ScoreboardCommonNamePolicy.nameType(for: .tennis),
            scoreboardFont: typographyPreference.font,
            accessibilityIdentifier: side == .left
                ? "tennis_left_name_edit"
                : "tennis_right_name_edit"
        )
    }

    private func tennisDoublesEditNameField(
        slot: Int
    ) -> some View {
        let fallback = store.state.doublesPlayerNames?.indices.contains(slot) == true
            ? store.state.doublesPlayerNames?[slot] ?? ""
            : ""
        return ScoreboardNameEditorField(
            placeholder: NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""),
            text: Binding(
                get: {
                    guard editDoublesNames.indices.contains(slot) else { return fallback }
                    return editDoublesNames[slot]
                },
                set: { value in
                    guard editDoublesNames.indices.contains(slot) else { return }
                    editDoublesNames[slot] = value
                }
            ),
            nameType: .player,
            scoreboardFont: typographyPreference.font,
            accessibilityIdentifier: "tennis_doubles_player_\(slot)_edit"
        )
    }

    private func tennisEditAdjustRow(
        label: String,
        value: String,
        fontSize: CGFloat,
        canDecrement: Bool,
        useSecondaryColor: Bool = false,
        controlSize: CGFloat? = nil,
        labelFontSize: CGFloat? = nil,
        labelHorizontalOffset: CGFloat = 0,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        let labelFont = labelFontSize.map {
            Font.system(size: $0, weight: .bold)
        } ?? .caption.bold()
        return VStack(spacing: 2) {
            if !label.isEmpty {
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(appearance.theme.palette.secondary)
                    .offset(x: labelHorizontalOffset)
                    .zIndex(1)
            }
            HStack(spacing: Theme.usesPadLayout ? 20 : 10) {
                tennisEditControl(
                    systemName: "minus",
                    enabled: canDecrement,
                    size: controlSize,
                    action: onDecrement
                )
                Text(value)
                    .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
                    .foregroundStyle(useSecondaryColor
                        ? appearance.theme.palette.secondary
                        : appearance.theme.palette.foreground)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(minWidth: Theme.usesPadLayout ? 100 : 70)
                tennisEditControl(
                    systemName: "plus",
                    enabled: true,
                    size: controlSize,
                    action: onIncrement
                )
            }
        }
    }

    private func tennisEditControl(
        systemName: String,
        enabled: Bool,
        size: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let visualSize = size ?? (Theme.usesPadLayout ? 48 : 36)
        let hitTargetSize = size == nil
            ? visualSize
            : max(ScoreboardConstants.minimumTouchTarget, visualSize)
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Theme.usesPadLayout ? 22 : 17, weight: .bold))
                .foregroundStyle(appearance.theme.palette.foreground)
                .frame(width: visualSize, height: visualSize)
                .background(Circle().fill(Color.black.opacity(enabled ? 0.24 : 0.1)))
        }
        .frame(width: hitTargetSize, height: hitTargetSize)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    @ViewBuilder
    private func tennisScoreRow(
        screenSide: MatchSide,
        side: MatchSide,
        height: CGFloat,
        panelSize: CGSize
    ) -> some View {
        let games = displayedGames(for: side)
        let sets = displayedSets(for: side)
        let hasInlineSecondary = store.state.rules.setScoringMode != .tiebreakOnly
        let typography = resolvedTennisTypography(
            side: side,
            name: "",
            size: CGSize(width: panelSize.width, height: height),
            scoreBaseScale: ScoreboardLayoutMetrics.tennisMainScoreScale(
                hasInlineSecondary: hasInlineSecondary
            ),
            secondaryIsInline: hasInlineSecondary,
            referenceHeight: panelSize.height
        )
        let mainSize = typography.scoreFontSize
        let scoreSpacing = typography.mainToSecondarySpacing
        let centerLineClearance = ScoreboardLayoutMetrics.tennisCenterLineClearance(
            halfViewportSize: panelSize
        )
        let usesDoublesLayout = store.state.doublesPlayerNames != nil
        let doublesSecondaryColumnWidth = ScoreboardLayoutMetrics.doublesSecondaryColumnWidth(
            halfViewportWidth: panelSize.width
        )

        if !hasInlineSecondary {
            tennisMainScore(side: side, fontSize: mainSize)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else if usesDoublesLayout {
            HStack(spacing: 0) {
                if screenSide == .left {
                    tennisMainScore(side: side, fontSize: mainSize)
                        .frame(maxWidth: .infinity)
                    tennisInnerScoreColumn(
                        games: games,
                        sets: sets,
                        panelSize: CGSize(width: panelSize.width, height: height)
                    )
                    .frame(width: doublesSecondaryColumnWidth)
                } else {
                    tennisInnerScoreColumn(
                        games: games,
                        sets: sets,
                        panelSize: CGSize(width: panelSize.width, height: height)
                    )
                    .frame(width: doublesSecondaryColumnWidth)
                    tennisMainScore(side: side, fontSize: mainSize)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            HStack(spacing: scoreSpacing) {
                if screenSide == .left {
                    tennisMainScore(side: side, fontSize: mainSize)
                    tennisInnerScoreColumn(
                        games: games,
                        sets: sets,
                        panelSize: CGSize(width: panelSize.width, height: height)
                    )
                    .padding(.trailing, centerLineClearance)
                } else {
                    tennisInnerScoreColumn(
                        games: games,
                        sets: sets,
                        panelSize: CGSize(width: panelSize.width, height: height)
                    )
                    .padding(.leading, centerLineClearance)
                    tennisMainScore(side: side, fontSize: mainSize)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
    }

    private func tennisMainScore(side: MatchSide, fontSize: CGFloat) -> some View {
        Text(displayedPointText(for: side))
            .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
            .foregroundStyle(appearance.theme.palette.foreground)
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private func tennisInnerScoreColumn(
        games: Int,
        sets: Int,
        panelSize: CGSize
    ) -> some View {
        let usesPadLayout = Theme.usesPadLayout
        let baseSize = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .tennis,
                containerSize: CGSize(width: min(panelSize.width * 0.34, 150), height: panelSize.height),
                nameText: "",
                scoreText: "",
                secondaryText: "\(games) \(sets)",
                preference: typographyPreference,
                horizontalPadding: 8,
                isLargeScreen: usesPadLayout
            )
        ).secondaryFontSize
        let gameSize = min(baseSize * 1.55, usesPadLayout ? 120 : 90)
        let setSize = min(baseSize * 1.25, usesPadLayout ? 88 : 66)
        let setBoxSize = max(
            usesPadLayout ? 72 : 54,
            min(setSize * 1.34, usesPadLayout ? 126 : 92)
        )
        let setBoxRadius = usesPadLayout
            ? min(setBoxSize * 0.3, 28)
            : min(setBoxSize * 0.15, 24)

        return VStack(spacing: usesPadLayout ? 40 : 8) {
            Text("\(games)")
                .font(typographyPreference.font.swiftUIFont(size: gameSize, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)

            if store.state.leftSets > 0 || store.state.rightSets > 0 {
                Text("\(sets)")
                    .font(typographyPreference.font.swiftUIFont(size: setSize, weight: .bold))
                    .monospacedDigit()
                    .frame(width: setBoxSize, height: setBoxSize)
                    .background(Color.black.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: setBoxRadius, style: .continuous))
            }
        }
        .foregroundStyle(appearance.theme.palette.secondary)
        .frame(width: setBoxSize)
    }

    private func tennisDoublesDisplaySlots(
        screenSide: MatchSide,
        logicalSide: MatchSide
    ) -> (top: Int, bottom: Int) {
        var top = logicalSide == .left ? 0 : 1
        var bottom = logicalSide == .left ? 2 : 3
        if screenSide == .right {
            swap(&top, &bottom)
        }
        return (top, bottom)
    }

    private var tennisDoublesServerIsTopRow: Bool? {
        guard let serverSlot = TennisDoublesServing.currentServerSlot(in: store.state) else {
            return nil
        }
        let leftSlots = tennisDoublesDisplaySlots(
            screenSide: .left,
            logicalSide: logicalSide(forScreen: .left)
        )
        let rightSlots = tennisDoublesDisplaySlots(
            screenSide: .right,
            logicalSide: logicalSide(forScreen: .right)
        )
        if leftSlots.top == serverSlot || rightSlots.top == serverSlot {
            return true
        }
        if leftSlots.bottom == serverSlot || rightSlots.bottom == serverSlot {
            return false
        }
        return nil
    }

    private var tennisDoublesServerIsLeftScreen: Bool? {
        guard let serverSlot = TennisDoublesServing.currentServerSlot(in: store.state) else {
            return nil
        }
        let serverLogicalSide: MatchSide = serverSlot.isMultiple(of: 2) ? .left : .right
        return logicalSide(forScreen: .left) == serverLogicalSide
    }

    private func tennisDoublesNameRow(
        name: String,
        slot: Int,
        isServer: Bool,
        isReceiver: Bool,
        fontSize: CGFloat,
        height: CGFloat
    ) -> some View {
        let showFlash = flashSlots.contains(slot) && flashActive
        return ZStack {
            if showFlash {
                Color(red: 1, green: 215 / 255, blue: 0).opacity(0.45)
            }
            Text(name)
                .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
                .foregroundStyle(isReceiver
                    ? appearance.theme.palette.secondary
                    : appearance.theme.palette.foreground.opacity(isServer ? 1 : 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var tennisScoreMultiplier: CGFloat {
        CGFloat(typographyPreference.scoreMultiplier)
    }

    private var tennisNameMultiplier: CGFloat {
        CGFloat(typographyPreference.nameMultiplier)
    }

    private var tennisSecondaryMultiplier: CGFloat {
        CGFloat(typographyPreference.secondaryMultiplier)
    }

    private var typographyPreference: ScoreboardTypographyPreference {
        typographySession.effectivePreference
    }

    private func resolvedTennisTypography(
        side: MatchSide,
        name: String,
        size: CGSize,
        scoreText: String? = nil,
        secondaryText: String? = nil,
        scoreBaseScale: CGFloat = 1,
        reservedHeight: CGFloat = 0,
        secondaryIsInline: Bool = false,
        referenceHeight: CGFloat? = nil
    ) -> ScoreboardTypographyResult {
        let games = displayedGames(for: side)
        let sets = displayedSets(for: side)
        return ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .tennis,
                containerSize: size,
                nameText: name,
                scoreText: scoreText ?? displayedPointText(for: side),
                secondaryText: secondaryText ?? "\(max(games, sets))",
                preference: typographyPreference,
                horizontalPadding: 20,
                reservedHeight: reservedHeight,
                scoreBaseScale: scoreBaseScale,
                secondaryIsInline: secondaryIsInline,
                referenceHeight: referenceHeight,
                isLargeScreen: Theme.usesPadLayout
            )
        )
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || isEditMode || showDisplaySettings || showMenu
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode,
              !isEditMode,
              !showDisplaySettings,
              !showMenu,
              !showGameOverDialog else { return }
        let hideDelay: TimeInterval
        if let exitConfirmDeadline, Date() <= exitConfirmDeadline {
            hideDelay = max(exitConfirmDeadline.timeIntervalSinceNow, 0) + 0.05
        } else {
            hideDelay = 1.5
        }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !isEditMode,
                  !showDisplaySettings,
                  !showMenu,
                  !showGameOverDialog else { return }
            if let exitConfirmDeadline, Date() <= exitConfirmDeadline { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || isEditMode || showGameOverDialog || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }

    private func toggleEditMode() {
        guard !scoringLocked else { return }
        showMenu = false
        menuConfirm.clear()
        if isEditMode {
            commitEditNames()
            isEditMode = false
            if store.state.finished {
                showGameOverDialog = true
            }
        } else {
            guard !store.state.finished else { return }
            syncEditNamesFromState()
            isEditMode = true
        }
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        VibrationManager.shared.vibrateMedium()
        revealImmersiveChrome()
    }

    private func syncEditNamesFromState() {
        editLeftName = store.state.leftName
        editRightName = store.state.rightName
        if let names = store.state.doublesPlayerNames {
            editDoublesNames = (0..<4).map { index in
                names.indices.contains(index) ? names[index] : ""
            }
        } else {
            editDoublesNames = ["", "", "", ""]
        }
    }

    private func commitEditNames() {
        if store.state.doublesPlayerNames != nil {
            let current = store.state.doublesPlayerNames ?? []
            for slot in 0..<4 where editDoublesNames.indices.contains(slot) {
                let trimmed = editDoublesNames[slot].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let oldValue = current.indices.contains(slot) ? current[slot] : ""
                if trimmed != oldValue {
                    dispatch(.setDoublesPlayerName(slot: slot, name: trimmed))
                }
                editDoublesNames[slot] = trimmed
            }
            return
        }

        let left = editLeftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = editRightName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLeft = left.isEmpty ? store.state.leftName : left
        let resolvedRight = right.isEmpty ? store.state.rightName : right
        editLeftName = resolvedLeft
        editRightName = resolvedRight
        if resolvedLeft != store.state.leftName || resolvedRight != store.state.rightName {
            dispatch(.setNames(left: resolvedLeft, right: resolvedRight))
        }
    }

    private func adjustPointsInEdit(side: MatchSide, delta: Int) {
        guard store.state.canAdjustPoints(side: side, delta: delta) else {
            showToast(NSLocalizedString("scoreboard_main_score_overflow", value: "大分超限", comment: ""))
            return
        }
        dispatch(.adjustPoints(side: side, delta: delta))
    }

    private func adjustGamesInEdit(side: MatchSide, delta: Int) {
        guard store.state.canAdjustGames(side: side, delta: delta) else {
            showToast(NSLocalizedString("scoreboard_set_score_overflow", value: "局分超限", comment: ""))
            return
        }
        dispatch(.adjustGames(side: side, delta: delta))
    }

    private func adjustSetsInEdit(side: MatchSide, delta: Int) {
        guard store.state.canAdjustSets(side: side, delta: delta) else {
            showToast(NSLocalizedString("scoreboard_game_score_overflow", value: "盘分超限", comment: ""))
            return
        }
        dispatch(.adjustSets(side: side, delta: delta))
    }

    private func handlePointWon(_ side: MatchSide) {
        guard !scoringLocked else {
            showToast(NSLocalizedString("linked_score_watch_control_readonly_toast", value: "手表计分中，手机暂不能计分", comment: ""))
            return
        }
        dispatch(.pointWon(side))
        // 网球双打无位置轮转（发球人整个发球局固定，局间才换），得分时不闪烁。
    }

    private func runDoublesFlash(slots: Set<Int>) {
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            flashSlots = slots
            flashActive = false
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            for step in 0..<4 {
                flashActive = step.isMultiple(of: 2)
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            flashActive = false
            flashSlots = []
        }
    }

    private func scoreboardDragGesture(for side: MatchSide) -> some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                guard !isEditMode, !scoringLocked else { return }
                if value.translation.width < -50,
                   abs(value.translation.height) < 50 {
                    performUndo()
                } else if value.translation.height > 50,
                          abs(value.translation.width) < 50 {
                    guard !store.state.finished else { return }
                    let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                    guard points > 0 else { return }
                    dispatch(.adjustPoints(side: side, delta: -1))
                }
            }
    }

    private func dispatch(_ intent: TennisMatchIntent) {
        guard !scoringLocked else { return }
        let before = store.state
        store.send(intent) { events in
            handleEvents(events, before: before)
        }
        revealImmersiveChrome()
    }

    private func handleEvents(_ events: [TennisMatchEvent], before: TennisMatchState) {
        var sideToast: String?
        var finalPoints: (left: Int, right: Int)?
        var completedGames: (left: Int, right: Int)?
        var matchFinished = false
        var matchReset = false
        for event in events {
            switch event {
            case .pointScored(_, let left, let right):
                finalPoints = (left, right)
            case .gameCompleted(_, let leftGames, let rightGames, _):
                completedGames = (leftGames, rightGames)
            case .sidesExchanged:
                sideToast = NSLocalizedString("change_sides", value: "换边", comment: "")
            case .sidesExchangeReminder:
                sideToast = NSLocalizedString("please_change_sides_manually", value: "请手动换边", comment: "")
            case .matchFinished:
                matchFinished = true
            case .matchReset:
                matchReset = true
            default:
                break
            }
        }
        if let finalPoints, (completedGames != nil || matchFinished) {
            beginTerminalGamePresentation(
                finalPoints: finalPoints,
                completedGames: completedGames,
                previousState: before,
                sideToast: sideToast,
                matchFinished: matchFinished
            )
        } else {
            if let sideToast { showToast(sideToast) }
            if matchFinished { showGameOverDialog = true }
        }
        if matchReset {
            didSpeakOpeningAnnouncement = false
            speakOpeningAnnouncementIfNeeded()
        }
    }

    private func beginTerminalGamePresentation(
        finalPoints: (left: Int, right: Int),
        completedGames: (left: Int, right: Int)?,
        previousState: TennisMatchState,
        sideToast: String?,
        matchFinished: Bool
    ) {
        var pointState = previousState
        pointState.leftPoints = finalPoints.left
        pointState.rightPoints = finalPoints.right
        let presentation = TennisTerminalGamePresentation(
            leftPointText: pointState.scoreDisplay(for: .left),
            rightPointText: pointState.scoreDisplay(for: .right),
            leftGames: completedGames?.left ?? previousState.leftGames,
            rightGames: completedGames?.right ?? previousState.rightGames,
            leftSets: previousState.leftSets,
            rightSets: previousState.rightSets,
            sidesSwapped: previousState.sidesSwapped
        )
        terminalHold.begin(presentation) {
            publishCurrentTennisState()
            if let sideToast { showToast(sideToast) }
            if matchFinished {
                notifyLinkedFinishIfNeeded()
                showGameOverDialog = true
            }
        }
    }

    private func displayedPointText(for side: MatchSide) -> String {
        if let terminalGamePresentation {
            return side == .left
                ? terminalGamePresentation.leftPointText
                : terminalGamePresentation.rightPointText
        }
        return store.state.scoreDisplay(for: side)
    }

    private func displayedGames(for side: MatchSide) -> Int {
        if let terminalGamePresentation {
            return side == .left ? terminalGamePresentation.leftGames : terminalGamePresentation.rightGames
        }
        return side == .left ? store.state.leftGames : store.state.rightGames
    }

    private func displayedSets(for side: MatchSide) -> Int {
        if let terminalGamePresentation {
            return side == .left ? terminalGamePresentation.leftSets : terminalGamePresentation.rightSets
        }
        return side == .left ? store.state.leftSets : store.state.rightSets
    }

    private func cancelTerminalGamePresentation() {
        terminalHold.cancel()
    }

    private func publishCurrentTennisState() {
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        guard let watchSessionId, watchLinkService.isController else { return }
        watchLinkService.syncWatch(
            sessionId: watchSessionId,
            gameType: store.gameType,
            state: store.state,
            detailedActions: store.actionTimeline
        )
    }

    private func notifyLinkedFinishIfNeeded() {
        guard let watchSessionId, watchLinkService.isController else { return }
        watchLinkService.notifyMatchFinished(
            sessionId: watchSessionId,
            snapshot: .tennis(store.state),
            recordId: store.sessionId.uuidString,
            winnerSide: winnerSide(for: store.state),
            manualEnd: manualFinishRequested
        )
    }

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: { makeSyncDisplayState() },
            handleIntent: { intent in
                guard LocalScoreboardMutationPolicy.allowsMutation(
                    isEditing: isEditMode,
                    finished: store.state.finished,
                    scoringLocked: scoringLocked
                ) else { return }
                switch intent {
                case .addLeft:
                    handlePointWon(logicalSide(forScreen: .left))
                case .addRight:
                    handlePointWon(logicalSide(forScreen: .right))
                case .subtractLeft:
                    dispatch(.adjustPoints(side: logicalSide(forScreen: .left), delta: -1))
                case .subtractRight:
                    dispatch(.adjustPoints(side: logicalSide(forScreen: .right), delta: -1))
                case .undo:
                    performUndo()
                case .exchangeSides:
                    guard !isEditMode else { return }
                    dispatch(.exchangeSides)
                case .requestSnapshot: break
                }
            }
        )
    }

    private func makeSyncDisplayState() -> LocalScoreboardDisplayState {
        let state = store.state
        let leftSide = logicalSide(forScreen: .left)
        let rightSide = logicalSide(forScreen: .right)
        let appGameType = GameType(scoreCoreGameType: store.gameType) ?? .tennis
        return LocalScoreboardDisplayState(
            gameID: appGameType.canonicalScoreboardIdentifier,
            title: appGameType.displayName,
            leftName: leftSide == .left ? state.leftName : state.rightName,
            rightName: rightSide == .left ? state.leftName : state.rightName,
            leftScore: state.scoreDisplay(for: leftSide),
            rightScore: state.scoreDisplay(for: rightSide),
            leftDetail: tennisLocalSyncDetail(state: state, side: leftSide),
            rightDetail: tennisLocalSyncDetail(state: state, side: rightSide),
            themeID: appearance.theme.rawValue,
            fontID: typographyPreference.font.rawValue,
            scoreMultiplier: typographyPreference.scoreMultiplier,
            nameMultiplier: typographyPreference.nameMultiplier,
            secondaryMultiplier: typographyPreference.secondaryMultiplier,
            finished: state.finished,
            keyPoint: LocalScoreboardKeyPoint.syncValue(
                LocalScoreboardKeyPoint(
                    status: KeyPointResolver.tennis(snapshot: tennisKeyPointSnapshot(state)),
                    sidesSwapped: state.sidesSwapped
                ),
                finished: state.finished,
                isEditing: isEditMode
            ),
            revision: 0
        )
    }

    private func logicalSide(forScreen side: MatchSide) -> MatchSide {
        TeamScreenLayout(
            sidesSwapped: terminalGamePresentation?.sidesSwapped ?? store.state.sidesSwapped
        ).engineSide(onScreen: side)
    }

    private func tennisKeyPointSnapshot(_ state: TennisMatchState) -> TennisKeyPointSnapshot {
        TennisKeyPointSnapshot(
            leftPoints: state.leftPoints,
            rightPoints: state.rightPoints,
            leftGames: state.leftGames,
            rightGames: state.rightGames,
            leftSets: state.leftSets,
            rightSets: state.rightSets,
            maxSets: state.rules.maxSets,
            matchCompletionMode: state.rules.matchCompletionMode,
            isTieBreak: state.isTieBreak,
            tieBreakTarget: state.rules.tieBreakPoints,
            usesNoAdScoring: state.rules.usesNoAdScoring,
            finished: state.finished,
            gamesPerSet: state.rules.gamesPerSet,
            setScoringMode: state.rules.setScoringMode.rawValue
        )
    }

    private var menuItems: [ScoreboardMenuItem] {
        var extras: [ScoreboardMenuItem] = [
            ScoreboardMenuItem(
                title: store.voiceAnnouncementEnabled
                    ? NSLocalizedString("voice_announcement_on", value: "语音：开", comment: "")
                    : NSLocalizedString("voice_announcement_off", value: "语音：关", comment: ""),
                action: "voiceAnnouncement",
                group: .sync,
                icon: store.voiceAnnouncementEnabled ? "speaker.wave.2" : "speaker.slash",
                keepDialogOpen: true
            )
        ]
        extras.insert(contentsOf: WatchLinkMenuSupport.extraItems(
            entryEnabled: AppFeatureFlags.watchLinkEntryEnabled,
            sessionId: watchSessionId,
            isFollower: watchLinkService.isFollower,
            watchBackgrounded: watchLinkService.watchBackgrounded
        ), at: 0)
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            resetConfirming: menuConfirm.resetConfirming,
            exchangeConfirming: menuConfirm.exchangeConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            scoringEnabled: !linkScoringLocked,
            extraItems: extras
        )
    }

    private func handleMenu(_ action: String) {
        guard !isEditMode else { return }
        if linkScoringLocked,
           !ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked(action) {
            toastMessage = NSLocalizedString("linked_score_phone_follower", value: "当前由手表计分", comment: "")
            return
        }
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            performUndo()
        case ScoreboardMenuActionID.exchangeSide.rawValue:
            if menuConfirm.armOrConfirm(.exchangeSide) {
                dispatch(.exchangeSides)
                showMenu = false
            } else {
                toastMessage = ScoreboardMenuConfirmAction.exchangeSide.localizedToast
            }
        case "reset":
            if menuConfirm.armOrConfirm(.reset) {
                cancelTerminalGamePresentation()
                showGameOverDialog = false
                manualFinishRequested = false
                dispatch(.reset)
                showMenu = false
            } else {
                toastMessage = ScoreboardMenuConfirmAction.reset.localizedToast
            }
        case "endGame":
            if menuConfirm.armOrConfirm(.finish) {
                manualFinishRequested = true
                dispatch(.finish)
                showMenu = false
            } else {
                toastMessage = ScoreboardMenuConfirmAction.finish.localizedToast
            }
        case "voiceAnnouncement":
            store.voiceAnnouncementEnabled.toggle()
            if store.voiceAnnouncementEnabled {
                speakOpeningAnnouncementIfNeeded()
            } else {
                ScoreVoiceAnnouncer.shared.stop()
            }
        case "displaySettings":
            showDisplaySettings = true
            showMenu = false
        case "resync":
            watchLinkService.requestScoreResync()
            showMenu = false
        case "takeover":
            Task {
                if let id = watchSessionId {
                    if let update = watchLinkService.latestRemoteSnapshot,
                       update.sessionId == id,
                       let state = update.snapshot.tennisState {
                        _ = await store.applyAuthoritativeState(
                            state,
                            detailedActions: update.detailedActions,
                            revision: update.revision
                        )
                    }
                    do {
                        try await watchLinkService.takeover(sessionId: id)
                    } catch {
                        showToast(error.localizedDescription)
                    }
                }
                showMenu = false
            }
        case "forceTakeover":
            if let id = watchSessionId {
                watchLinkService.requestForceTakeoverConfirmation(id)
            }
            showMenu = false
        case "endLink":
            if let id = watchSessionId {
                watchLinkService.leaveSession(id)
                watchSessionId = nil
            }
            showMenu = false
        case "exit":
            if menuConfirm.armOrConfirm(.exit) {
                showMenu = false
                goBack()
            } else {
                toastMessage = ScoreboardMenuConfirmAction.exit.localizedToast
            }
        default:
            showMenu = false
        }
    }

    private func goBack() {
        cancelTerminalGamePresentation()
        store.flush {
            if let onNavigationBack {
                onNavigationBack()
            } else {
                dismiss()
            }
        }
    }

    private func requestBack() {
        let now = Date()
        if exitConfirmDeadline.map({ now <= $0 }) != true {
            exitConfirmDeadline = now.addingTimeInterval(2)
            showToast(NSLocalizedString("press_again_to_exit", value: "再按一次退出", comment: ""))
            revealImmersiveChrome()
            return
        }
        goBack()
    }

    private func performUndo() {
        guard !isEditMode, !linkScoringLocked else { return }
        cancelTerminalGamePresentation()
        revealImmersiveChrome()
        store.undo { success in
            showToast(success
                ? NSLocalizedString("undone", value: "已撤销", comment: "Undo done")
                : NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func speakOpeningAnnouncementIfNeeded() {
        guard store.voiceAnnouncementEnabled,
              !didSpeakOpeningAnnouncement,
              let payload = TennisVoiceAnnouncementMapper.openingPayload(
                gameType: store.gameType,
                state: store.state
              )
        else { return }
        didSpeakOpeningAnnouncement = true
        ScoreVoiceAnnouncer.shared.speak(payload)
    }

    private func shareFinishedMatch() {
        let left = store.state.rules.setScoringMode == .tiebreakOnly ? store.state.leftPoints : store.state.leftSets
        let right = store.state.rules.setScoringMode == .tiebreakOnly ? store.state.rightPoints : store.state.rightSets
        let text = "\(store.state.leftName) \(left) - \(right) \(store.state.rightName)"
        ScoreboardShareSupport.present(text: text)
    }

    private func startNewMatch() {
        guard !scoringLocked, !isStartingNewMatch else { return }
        isStartingNewMatch = true
        let finishedStore = store
        finishedStore.persistSnapshot { success in
            guard success else {
                isStartingNewMatch = false
                return
            }
            let freshStore = finishedStore.makeFreshMatchStore()
            freshStore.persistSnapshot { freshSaved in
                isStartingNewMatch = false
                guard freshSaved else { return }
                store = freshStore
                manualFinishRequested = false
                didSpeakOpeningAnnouncement = false
                isEditMode = false
                showMenu = false
                menuConfirm.clear()
                flashTask?.cancel()
                flashSlots = []
                flashActive = false
                showGameOverDialog = false
                syncEditNamesFromState()
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                if let watchSessionId {
                    let participantNames = freshStore.state.doublesPlayerNames
                        ?? [freshStore.state.leftName, freshStore.state.rightName]
                    watchLinkService.prepareControllerForNewMatch(
                        sessionId: watchSessionId,
                        gameType: freshStore.gameType,
                        snapshot: .tennis(freshStore.state),
                        participantNames: participantNames
                    )
                }
                speakOpeningAnnouncementIfNeeded()
            }
        }
    }
}

func tennisLocalSyncDetail(state: TennisMatchState, side: MatchSide) -> String? {
    guard state.rules.setScoringMode != .tiebreakOnly else { return nil }
    let sets = side == .left ? state.leftSets : state.rightSets
    let games = side == .left ? state.leftGames : state.rightGames
    return [
        String(format: NSLocalizedString("tennis_sync_sets_format", value: "%d 盘", comment: ""), sets),
        String(format: NSLocalizedString("tennis_sync_games_format", value: "%d 局", comment: ""), games)
    ].joined(separator: " · ")
}
