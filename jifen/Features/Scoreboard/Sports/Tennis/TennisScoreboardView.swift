import LinkCore
import ScoreCore
import SwiftUI
import UIKit

/// Tennis scoreboard driven by `TennisSessionStore` / ScoreCore reducer.
struct TennisScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
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
    @State private var isStartingNewMatch = false

    init(
        onNavigationBack: (() -> Void)? = nil,
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil
    ) {
        self.onNavigationBack = onNavigationBack
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
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
        let left = resolvedScoreboardSetupName(
            setup?.team1Name,
            fallback: NSLocalizedString("red_team", comment: "")
        )
        let right = resolvedScoreboardSetupName(
            setup?.team2Name,
            fallback: NSLocalizedString("blue_team", comment: "")
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

    private var scoringLocked: Bool {
        watchSessionId != nil
            && (watchLinkService.isFollower || watchLinkService.isAuthorityTransferPending)
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
                if !isEditMode,
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
                if store.state.isTieBreak {
                    Text(store.state.rules.tieBreakPoints == 10
                        ? NSLocalizedString("tennis_tiebreak_option_10", value: "抢十", comment: "")
                        : NSLocalizedString("tennis_tiebreak_option_7", value: "抢七", comment: ""))
                        .font(.caption.bold())
                        .padding(6)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(.white)
                }
                if !isEditMode, !store.state.finished {
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode,
                          value.translation.width < -50,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    performUndo()
                }
        )
        .onAppear {
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            onSetupConsumed?()
            if let id = initialRecordId, let uuid = UUID(uuidString: id),
               let restored = TennisSessionStore(restoring: uuid) {
                store = restored
            }
            typographySession.switchStyleID(ScoreboardStyleID(scoreCoreGameType: store.gameType))
            syncEditNamesFromState()
            registerScoreboardSync()
            revealImmersiveChrome()
            if store.state.finished { showGameOverDialog = true }
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: store.state) { _, state in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            if let watchSessionId, watchLinkService.isController {
                watchLinkService.syncWatch(
                    sessionId: watchSessionId,
                    gameType: store.gameType,
                    state: state,
                    detailedActions: store.actionTimeline
                )
            }
            if state.finished, !isEditMode {
                showGameOverDialog = true
                if let watchSessionId, watchLinkService.isController {
                    let winner = winnerSide(for: state)
                    watchLinkService.notifyMatchFinished(
                        sessionId: watchSessionId,
                        snapshot: .tennis(state),
                        recordId: store.sessionId.uuidString,
                        winnerSide: winner,
                        manualEnd: manualFinishRequested
                    )
                }
            }
        }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId,
                  let update,
                  update.sessionId == watchSessionId,
                  let tennis = update.snapshot.tennisState else { return }
            Task {
                _ = await store.applyAuthoritativeState(
                    tennis,
                    detailedActions: update.detailedActions,
                    revision: update.revision
                )
            }
        }
        .onChange(of: watchLinkService.pendingTakeoverApplication) { _, pending in
            guard let watchSessionId,
                  let pending,
                  pending.sessionId == watchSessionId,
                  let state = pending.snapshot.tennisState else { return }
            Task {
                _ = await store.applyAuthoritativeState(
                    state,
                    detailedActions: pending.detailedActions,
                    revision: pending.revision
                )
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
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("done", value: "完成", comment: "")) {
                                showFinishedRecordDetail = false
                            }
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
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
            let skipPersist = watchSessionId != nil
                && (watchLinkService.isFollower || watchLinkService.finishedRecordId != nil)
            if let watchSessionId {
                watchLinkService.endWatchSession(watchSessionId)
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
        let side = store.teamScreenLayout.engineSide(onScreen: screenSide)
        let isLeft = side == .left
        return ZStack {
            (isLeft ? appearance.theme.palette.left : appearance.theme.palette.right)
            if isEditMode {
                tennisSinglesEditContent(side: side, size: size)
            } else {
                tennisSinglesPlayContent(screenSide: screenSide, side: side, size: size)
            }
        }
        .foregroundStyle(appearance.theme.palette.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !store.state.finished, !scoringLocked else { return }
            dispatch(.pointWon(side))
        }
        .onTapGesture(count: 2) {
            guard !isEditMode, !store.state.finished,
                  appearance.doubleTapSubtract, !scoringLocked else { return }
            dispatch(.adjustPoints(side: side, delta: -1))
        }
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

    private func tennisSinglesEditContent(side: MatchSide, size: CGSize) -> some View {
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
        let nameSize = typography.nameFontSize * 0.72

        return VStack(spacing: Theme.usesPadLayout ? 16 : 8) {
            tennisSinglesEditNameField(side: side, fontSize: nameSize)

            tennisEditAdjustRow(
                label: NSLocalizedString("tennis_point_score", value: "小分", comment: ""),
                value: points,
                fontSize: mainSize,
                canDecrement: (isLeft ? store.state.leftPoints : store.state.rightPoints) > 0,
                onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { adjustPointsInEdit(side: side, delta: 1) }
            )

            if store.state.rules.setScoringMode != .tiebreakOnly {
                tennisEditAdjustRow(
                    label: NSLocalizedString("tennis_game_score", value: "局分", comment: ""),
                    value: "\(games)",
                    fontSize: secondarySize,
                    canDecrement: games > 0,
                    useSecondaryColor: true,
                    onDecrement: { dispatch(.adjustGames(side: side, delta: -1)) },
                    onIncrement: { adjustGamesInEdit(side: side, delta: 1) }
                )
                tennisEditAdjustRow(
                    label: NSLocalizedString("tennis_set_score", value: "盘分", comment: ""),
                    value: "\(sets)",
                    fontSize: secondarySize,
                    canDecrement: sets > 0,
                    useSecondaryColor: true,
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
        let side = store.teamScreenLayout.engineSide(onScreen: screenSide)
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
                        isServer: serverSlot == slots.top,
                        isReceiver: receiverSlot == slots.top,
                        fontSize: nameFontSize,
                        height: rowHeight
                    )
                    Spacer(minLength: 0)
                    tennisDoublesNameRow(
                        name: names.indices.contains(slots.bottom) ? names[slots.bottom] : "",
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
            dispatch(.pointWon(side))
        }
        .onTapGesture(count: 2) {
            guard !isEditMode, !store.state.finished,
                  appearance.doubleTapSubtract, !scoringLocked else { return }
            dispatch(.adjustPoints(side: side, delta: -1))
        }
    }

    private func tennisDoublesEditContent(
        screenSide: MatchSide,
        side: MatchSide,
        slots: (top: Int, bottom: Int),
        size: CGSize
    ) -> some View {
        let isLeft = side == .left
        let points = store.state.scoreDisplay(for: side)
        let games = isLeft ? store.state.leftGames : store.state.rightGames
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let usesCompactHeight = size.height < 420
        let longestName = [
            editDoublesNames.indices.contains(slots.top) ? editDoublesNames[slots.top] : "",
            editDoublesNames.indices.contains(slots.bottom) ? editDoublesNames[slots.bottom] : ""
        ].max(by: { $0.count < $1.count }) ?? ""
        let typography = resolvedTennisTypography(
            side: side,
            name: longestName,
            size: CGSize(width: size.width, height: size.height / 3),
            reservedHeight: 16
        )
        let regularMainSize = ScoreboardLayoutMetrics.compactEditMainScoreFontSize(
            regularSize: typography.scoreFontSize,
            rowHeight: size.height / 3
        )
        let regularSecondarySize = ScoreboardLayoutMetrics.compactEditSecondaryScoreFontSize(
            regularSize: typography.secondaryFontSize,
            rowHeight: size.height / 3
        )
        let regularNameSize = typography.nameFontSize
        let mainSize = usesCompactHeight ? min(34, regularMainSize) : regularMainSize
        let secondarySize = usesCompactHeight ? min(24, regularSecondarySize) : regularSecondarySize
        let nameSize = usesCompactHeight
            ? min(28, max(20, (size.height * 0.07).rounded()))
            : regularNameSize
        let contentSpacing: CGFloat = usesCompactHeight ? 4 : (Theme.usesPadLayout ? 16 : 8)
        let nameSpacing: CGFloat = usesCompactHeight ? 3 : (Theme.usesPadLayout ? 10 : 6)
        let fieldVerticalPadding: CGFloat = usesCompactHeight ? 2 : (Theme.usesPadLayout ? 10 : 6)
        let controlSize: CGFloat? = usesCompactHeight ? 30 : nil
        let topPadding = usesCompactHeight
            ? CGFloat(52)
            : ScoreboardLayoutMetrics.nameTopPadding(panelHeight: size.height, isEditMode: true)
        let bottomPadding: CGFloat = usesCompactHeight ? 4 : (Theme.usesPadLayout ? 36 : 12)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: contentSpacing) {
                VStack(spacing: nameSpacing) {
                    tennisDoublesEditNameField(
                        slot: slots.top,
                        fontSize: nameSize,
                        verticalPadding: fieldVerticalPadding
                    )
                    tennisDoublesEditNameField(
                        slot: slots.bottom,
                        fontSize: nameSize,
                        verticalPadding: fieldVerticalPadding
                    )
                }

                tennisEditAdjustRow(
                    label: NSLocalizedString("tennis_point_score", value: "小分", comment: ""),
                    value: points,
                    fontSize: mainSize,
                    canDecrement: (isLeft ? store.state.leftPoints : store.state.rightPoints) > 0,
                    controlSize: controlSize,
                    onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                    onIncrement: { adjustPointsInEdit(side: side, delta: 1) }
                )

                if store.state.rules.setScoringMode != .tiebreakOnly {
                    tennisEditAdjustRow(
                        label: NSLocalizedString("tennis_game_score", value: "局分", comment: ""),
                        value: "\(games)",
                        fontSize: secondarySize,
                        canDecrement: games > 0,
                        useSecondaryColor: true,
                        controlSize: controlSize,
                        onDecrement: { dispatch(.adjustGames(side: side, delta: -1)) },
                        onIncrement: { adjustGamesInEdit(side: side, delta: 1) }
                    )
                    tennisEditAdjustRow(
                        label: NSLocalizedString("tennis_set_score", value: "盘分", comment: ""),
                        value: "\(sets)",
                        fontSize: secondarySize,
                        canDecrement: sets > 0,
                        useSecondaryColor: true,
                        controlSize: controlSize,
                        onDecrement: { dispatch(.adjustSets(side: side, delta: -1)) },
                        onIncrement: { adjustSetsInEdit(side: side, delta: 1) }
                    )
                }
            }
            .padding(.horizontal, Theme.usesPadLayout ? 36 : 16)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(!usesCompactHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier(screenSide == .left
            ? "tennis_doubles_left_edit_panel"
            : "tennis_doubles_right_edit_panel")
    }

    private func tennisSinglesEditNameField(side: MatchSide, fontSize: CGFloat) -> some View {
        TextField(
            NSLocalizedString("team_name", value: "队名", comment: ""),
            text: side == .left ? $editLeftName : $editRightName
        )
        .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
        .multilineTextAlignment(.center)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, Theme.usesPadLayout ? 10 : 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
        .accessibilityIdentifier(side == .left
            ? "tennis_left_name_edit"
            : "tennis_right_name_edit")
    }

    private func tennisDoublesEditNameField(
        slot: Int,
        fontSize: CGFloat,
        verticalPadding: CGFloat
    ) -> some View {
        let fallback = store.state.doublesPlayerNames?.indices.contains(slot) == true
            ? store.state.doublesPlayerNames?[slot] ?? ""
            : ""
        return TextField(
            NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""),
            text: Binding(
                get: {
                    guard editDoublesNames.indices.contains(slot) else { return fallback }
                    return editDoublesNames[slot]
                },
                set: { value in
                    guard editDoublesNames.indices.contains(slot) else { return }
                    editDoublesNames[slot] = value
                }
            )
        )
        .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
        .multilineTextAlignment(.center)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
        .accessibilityIdentifier("tennis_doubles_player_\(slot)_edit")
    }

    private func tennisEditAdjustRow(
        label: String,
        value: String,
        fontSize: CGFloat,
        canDecrement: Bool,
        useSecondaryColor: Bool = false,
        controlSize: CGFloat? = nil,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(appearance.theme.palette.secondary)
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
        let controlSize = size ?? (Theme.usesPadLayout ? 48 : 36)
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Theme.usesPadLayout ? 22 : 17, weight: .bold))
                .foregroundStyle(appearance.theme.palette.foreground)
                .frame(width: controlSize, height: controlSize)
                .background(Circle().fill(Color.black.opacity(enabled ? 0.24 : 0.1)))
        }
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
        let isLeft = side == .left
        let games = isLeft ? store.state.leftGames : store.state.rightGames
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
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

        if !hasInlineSecondary {
            tennisMainScore(side: side, fontSize: mainSize)
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
        Text(store.state.scoreDisplay(for: side))
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
        isServer: Bool,
        isReceiver: Bool,
        fontSize: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack {
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
        let isLeft = side == .left
        let games = isLeft ? store.state.leftGames : store.state.rightGames
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        return ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .tennis,
                containerSize: size,
                nameText: name,
                scoreText: scoreText ?? store.state.scoreDisplay(for: side),
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

    private func dispatch(_ intent: TennisMatchIntent) {
        guard !scoringLocked else { return }
        store.send(intent) { events in
            handleSideChangeToasts(events)
        }
        revealImmersiveChrome()
    }

    private func handleSideChangeToasts(_ events: [TennisMatchEvent]) {
        var sideToast: String?
        for event in events {
            switch event {
            case .sidesExchanged:
                sideToast = NSLocalizedString("change_sides", value: "换边", comment: "")
            case .sidesExchangeReminder:
                sideToast = NSLocalizedString("please_change_sides_manually", value: "请手动换边", comment: "")
            default:
                break
            }
        }
        if let sideToast {
            toastMessage = sideToast
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if toastMessage == sideToast {
                    toastMessage = nil
                }
            }
        }
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
                    dispatch(.pointWon(logicalSide(forScreen: .left)))
                case .addRight:
                    dispatch(.pointWon(logicalSide(forScreen: .right)))
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
        store.teamScreenLayout.engineSide(onScreen: side)
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
            scoringEnabled: !scoringLocked,
            extraItems: extras
        )
    }

    private func handleMenu(_ action: String) {
        guard !isEditMode else { return }
        if scoringLocked,
           !ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked(action) {
            toastMessage = NSLocalizedString("linked_score_phone_follower", value: "当前由手表计分", comment: "")
            return
        }
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            performUndo()
        case "exchangeSide":
            if menuConfirm.armOrConfirm(.exchangeSide) {
                dispatch(.exchangeSides)
                showMenu = false
            } else {
                toastMessage = ScoreboardMenuConfirmAction.exchangeSide.localizedToast
            }
        case "reset":
            if menuConfirm.armOrConfirm(.reset) {
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
            if !store.voiceAnnouncementEnabled {
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
                    try? await watchLinkService.takeover(sessionId: id)
                }
                showMenu = false
            }
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
        guard !isEditMode, !scoringLocked else { return }
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
                isEditMode = false
                showMenu = false
                menuConfirm.clear()
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
