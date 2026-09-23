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
    @Environment(\.scoreboardUsageHintCoordinator) private var usageHintCoordinator
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var forcedGameType: ScoreCore.GameType? = nil
    var usageHintCoordinatorOverride: ScoreboardUsageHintCoordinator? = nil

    @State private var store: TennisSessionStore
    @State private var showMenu = false
    @State private var showDisplaySettings = false
    @State private var styleEditorEntry = ScoreboardStyleEditorEntry()
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
    @State private var openingAnnouncementTask: Task<Void, Never>?
    @State private var officialBreakSession = OfficialBreakSession()
    @State private var pendingTapSide: MatchSide?
    @State private var pendingTapAt: Date = .distantPast
    @State private var tapGeneration = 0

    private let doubleTapWindow: TimeInterval = 0.24

    /// 对齐安卓 TennisScoreScreen：网球/网球双打走 240ms 挂起窗口，双击 = 减 1 分；
    /// 软式网球与板网球不在清单内，双击等价于两次加分。
    private var onePointDoubleTapEnabled: Bool {
        appearance.doubleTapSubtract
            && !scoringLocked
            && !showMenu
            && !showDisplaySettings
            && ScoreboardUsageHintHelper.supportsDoubleTapSubtract(store.gameType)
    }

    init(
        onNavigationBack: (() -> Void)? = nil,
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        forcedGameType: ScoreCore.GameType? = nil,
        usageHintCoordinatorOverride: ScoreboardUsageHintCoordinator? = nil
    ) {
        self.onNavigationBack = onNavigationBack
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.forcedGameType = forcedGameType
        self.usageHintCoordinatorOverride = usageHintCoordinatorOverride

        let setup = initialSetup
        let isDoubles = !(setup?.isSingles ?? true)
        let gameType: ScoreCore.GameType = forcedGameType ?? (isDoubles ? .tennisDoubles : .tennis)
        let rules: TennisRuleSet
        if gameType == .softTennis {
            rules = setup?.softTennisRules ?? .softTennis()
        } else if gameType == .padel {
            rules = setup?.padelRules ?? .padel()
        } else {
            rules = (setup ?? SportsSetupResult(team1Name: "", team2Name: "")).tennisRules
        }
        let opening: MatchSide = setup?.servingSide == MatchSide.right.rawValue ? .right : .left
        let defaults = DefaultParticipantNames.resolve(
            for: GameType(scoreCoreGameType: gameType) ?? .tennis,
            isSingles: !isDoubles
        )
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
    }


    private var terminalGamePresentation: TennisTerminalGamePresentation? { terminalHold.value }
    private var scoringLocked: Bool {
        isStyleEditing || terminalGamePresentation != nil || officialBreakSession.inputFrozen
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
                        // Edit labels extend from the left panel across the center seam.
                        .zIndex(isEditMode ? 1 : 0)
                    half(.right, size: halfSize)
                }
                if terminalGamePresentation == nil,
                   !isEditMode,
                   !store.state.finished {
                    if store.state.doublesPlayerNames == nil {
                        CenterLineServeIndicator(
                            isLeftServing: logicalSide(forScreen: .left) == store.state.servingSide,
                            triangleSize: serveIndicatorSize,
                            color: appearance.serverIndicatorColor
                        )
                        .position(x: size.width / 2, y: size.height / 2)
                    } else if let isLeftServing = tennisDoublesServerIsLeftScreen,
                              let isTopRow = tennisDoublesServerIsTopRow {
                        CenterLineServeIndicator(
                            isLeftServing: isLeftServing,
                            triangleSize: serveIndicatorSize,
                            color: appearance.serverIndicatorColor
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
                if terminalGamePresentation == nil, !isEditMode, !isStyleEditing, !showDisplaySettings, store.state.isTieBreak {
                    TennisTieBreakIndicator(targetPoints: store.state.rules.tieBreakPoints)
                        .position(TennisTieBreakIndicatorLayout.topCenter(
                            viewportSize: size,
                            safeAreaTop: proxy.safeAreaInsets.top
                        ))
                        .zIndex(3)
                }
                if terminalGamePresentation == nil, !isEditMode, !isStyleEditing, !showDisplaySettings, !store.state.finished {
                    ScoreboardKeyPointBadgeLayer(
                        status: KeyPointResolver.tennis(snapshot: tennisKeyPointSnapshot(store.state)),
                        gameType: store.gameType,
                        sidesSwapped: store.state.sidesSwapped,
                        doublesTopRow: store.state.doublesPlayerNames != nil ? tennisDoublesServerIsTopRow : nil,
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
                        newGameLabel: nil,
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
                    onUsageHint: { (usageHintCoordinator ?? usageHintCoordinatorOverride)?.presentFromMenu() },
                    showEndGame: true,
                    items: menuItems,
                    analyticsGameType: GameType(scoreCoreGameType: store.gameType) ?? .tennis
                )
                if officialBreakSupported, officialBreakSession.state != nil {
                    OfficialBreakOverlay(
                        session: $officialBreakSession,
                        onComplete: completeOfficialBreak,
                        onCancel: cancelOfficialBreak,
                        onVoiceCue: speakOfficialBreakCue
                    )
                    .zIndex(100)
                }
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
            .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    guard !isStyleEditing, !isEditMode else { return }
                    showMenu = true
                    revealImmersiveChrome()
                }
        )
        .onAppear {
            appearance = .current(styleID: ScoreboardStyleID(scoreCoreGameType: store.gameType))
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            onSetupConsumed?()
            if let id = initialResumeSessionId, let uuid = UUID(uuidString: id),
               let restored = TennisSessionStore(restoring: uuid) {
                store = restored
                didSpeakOpeningAnnouncement = true
            }
            if let savedBreak = store.state.officialBreakState {
                officialBreakSession = OfficialBreakSession(state: savedBreak)
                officialBreakSession.reconcileAfterRestore(
                    nowMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
                )
            }
            typographySession.switchStyleID(ScoreboardStyleID(scoreCoreGameType: store.gameType))
            syncEditNamesFromState()
            registerScoreboardSync()

            revealImmersiveChrome()
            if store.state.finished { showGameOverDialog = true }
            speakOpeningAnnouncementIfNeeded()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current(styleID: ScoreboardStyleID(scoreCoreGameType: store.gameType))
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            // 对齐安卓 LaunchedEffect(onePointDoubleTapEnabled)：开关关掉时立刻丢掉挂起的单击。
            if !onePointDoubleTapEnabled { cancelPendingTap() }
            revealImmersiveChrome()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: onePointDoubleTapEnabled) { _, _ in cancelPendingTap() }
        .onChange(of: store.state) { _, state in
            if terminalGamePresentation == nil {
                publishCurrentTennisState()
            }
            if state.finished, !isEditMode {
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
            cancelPendingTap()
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
        .scoreboardStyleEditorEntry(
            styleEditorEntry,
            typographySession: typographySession,
            onEditingChange: { _ in updateImmersiveForBlocking() }
        )
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
            cancelPendingTap()
            cancelPendingOpeningAnnouncement()
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            flashTask?.cancel()
            cancelTerminalGamePresentation()
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }

            store.persistSnapshot()
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
        let textColor = appearance.palette.foreground(for: isLeft ? .team0 : .team1)
        return ZStack {
            (isLeft ? appearance.palette.left : appearance.palette.right)
            if isEditMode {
                tennisSinglesEditContent(screenSide: screenSide, side: side, size: size)
            } else {
                tennisSinglesPlayContent(screenSide: screenSide, side: side, size: size)
            }
        }
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1)
                .onEnded { value in
                    guard isScoreTouchAllowed(location: value.location, panelSize: size) else { return }
                    handlePanelTap(side)
                }
        )
        .simultaneousGesture(scoreboardDragGesture(for: side))
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
                .foregroundStyle(appearance.elementForeground(
                    .teamName,
                    slotKey: side == .left ? .sideLeft : .sideRight
                ))
                .styleElementSelectable(.teamName, slotKey: side == .left ? .sideLeft : .sideRight)
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
        let textColor = appearance.palette.foreground(for: isLeft ? .team0 : .team1)
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
            isLeft ? appearance.palette.left : appearance.palette.right
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
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1)
                .onEnded { value in
                    guard isScoreTouchAllowed(location: value.location, panelSize: size) else { return }
                    handlePanelTap(side)
                }
        )
        .simultaneousGesture(scoreboardDragGesture(for: side))
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
        let scoreboardScreenWidth = max(AppScreen.bounds.width, AppScreen.bounds.height)
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
            textColor: appearance.palette.control,
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
            textColor: appearance.palette.control,
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
        let resolvedLabelFontSize = labelFontSize ?? (Theme.usesPadLayout ? 20 : 12)
        return HStack(spacing: Theme.usesPadLayout ? 20 : 10) {
            tennisEditControl(
                systemName: "minus",
                enabled: canDecrement,
                size: controlSize,
                action: onDecrement
            )
            Text(value)
                .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
                .foregroundStyle(useSecondaryColor
                    ? appearance.palette.secondary
                    : appearance.palette.foreground)
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
        .overlay {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: resolvedLabelFontSize, weight: .bold))
                    .foregroundStyle(appearance.palette.secondary)
                    .offset(x: labelHorizontalOffset)
                    .allowsHitTesting(false)
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
        return Button(action: {
            // 对齐安卓 ScoreEditAdjustRows：编辑面板 ± 按钮轻震反馈。
            VibrationManager.shared.vibrateLight()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: Theme.usesPadLayout ? 22 : 17, weight: .bold))
                .foregroundStyle(appearance.palette.foreground)
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
        let singlesMainScoreWidth = min(
            ScoreboardLayoutMetrics.tennisMainScoreColumnWidth(fontSize: mainSize),
            panelSize.width * 0.46
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
                        side: side,
                        mainFontSize: mainSize,
                        secondaryFontSize: typography.secondaryFontSize
                    )
                    .frame(width: doublesSecondaryColumnWidth)
                } else {
                    tennisInnerScoreColumn(
                        games: games,
                        sets: sets,
                        side: side,
                        mainFontSize: mainSize,
                        secondaryFontSize: typography.secondaryFontSize
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
                        .frame(width: singlesMainScoreWidth)
                    tennisInnerScoreColumn(
                        games: games,
                        sets: sets,
                        side: side,
                        mainFontSize: mainSize,
                        secondaryFontSize: typography.secondaryFontSize
                    )
                    .padding(.trailing, centerLineClearance)
                } else {
                    tennisInnerScoreColumn(
                        games: games,
                        sets: sets,
                        side: side,
                        mainFontSize: mainSize,
                        secondaryFontSize: typography.secondaryFontSize
                    )
                    .padding(.leading, centerLineClearance)
                    tennisMainScore(side: side, fontSize: mainSize)
                        .frame(width: singlesMainScoreWidth)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
    }

    private func tennisMainScore(side: MatchSide, fontSize: CGFloat) -> some View {
        Text(displayedPointText(for: side))
            .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
            .foregroundStyle(mainScoreColor(side: side))
            .styleElementSelectable(.mainScore, slotKey: side == .left ? .sideLeft : .sideRight)
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    /// 主比分色：V2 元素配置优先；未配置保持旧全局前景色。
    private func mainScoreColor(side: MatchSide) -> Color {
        let slotKey: ScoreboardStyleSlotKeyV2 = side == .left ? .sideLeft : .sideRight
        if appearance.hasElementColor(.mainScore, slotKey: slotKey) {
            return appearance.elementForeground(.mainScore, slotKey: slotKey)
        }
        return appearance.palette.foreground
    }

    private func tennisInnerScoreColumn(
        games: Int,
        sets: Int,
        side: MatchSide,
        mainFontSize: CGFloat,
        secondaryFontSize: CGFloat
    ) -> some View {
        let usesPadLayout = Theme.usesPadLayout
        // 安卓基准：局分 = halfPanelSecondaryScoreSp（与羽毛球辅分同公式）；
        // 盘分 = 主分 × 0.32，盒子 = 盘分 × 1.45（Pad 1.36）。
        let gameSize = secondaryFontSize
        let setSize = (mainFontSize * 0.32 / max(0.01, typographyPreference.scoreMultiplier)
            * typographyPreference.multiplier(for: store.state.doublesPlayerNames != nil ? ScoreboardStyleElementKeyV2.setGameScore : .setScore)).rounded()
        let setBoxSize = max(
            usesPadLayout ? 76 : 54,
            min(setSize * (usesPadLayout ? 1.36 : 1.45), usesPadLayout ? 126 : 92)
        )
        let setBoxRadius = usesPadLayout
            ? min(setBoxSize * 0.3, 28)
            : min(setBoxSize * 0.15, 24)

        // 元素级取色：V2 配置优先；未配置保持旧 secondary（70% 透明）。
        func elementColor(_ element: ScoreboardStyleElementKeyV2) -> Color {
            let slotKey: ScoreboardStyleSlotKeyV2 = side == .left ? .sideLeft : .sideRight
            return appearance.hasElementColor(element, slotKey: slotKey)
                ? appearance.elementForeground(element, slotKey: slotKey)
                : appearance.palette.secondary
        }

        return VStack(spacing: usesPadLayout ? 40 : 8) {
            Text("\(games)")
                .font(typographyPreference.font.swiftUIFont(size: gameSize, weight: .bold))
                .foregroundStyle(elementColor(.gameScore))
                .styleElementSelectable(store.state.doublesPlayerNames != nil ? .setGameScore : .gameScore, slotKey: side == .left ? .sideLeft : .sideRight)
                .monospacedDigit()
                .lineLimit(1)

            if store.state.leftSets > 0 || store.state.rightSets > 0 {
                Text("\(sets)")
                    .font(typographyPreference.font.swiftUIFont(size: setSize, weight: .bold))
                    .foregroundStyle(elementColor(.setScore))
                    .styleElementSelectable(store.state.doublesPlayerNames != nil ? .setGameScore : .setScore, slotKey: side == .left ? .sideLeft : .sideRight)
                    .monospacedDigit()
                    .frame(width: setBoxSize, height: setBoxSize)
                    .background(Color.black.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: setBoxRadius, style: .continuous))
            }
        }
        .foregroundStyle(appearance.palette.secondary)
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
                .foregroundStyle(appearance.hasElementColor(.playerName, slotKey: slot.isMultiple(of: 2) ? .sideLeft : .sideRight)
                    ? appearance.elementForeground(.playerName, slotKey: slot.isMultiple(of: 2) ? .sideLeft : .sideRight)
                    : (isReceiver ? appearance.palette.secondary : appearance.palette.foreground.opacity(isServer ? 1 : 0.85)))
                .styleElementSelectable(.playerName, slotKey: slot.isMultiple(of: 2) ? .sideLeft : .sideRight)
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

    private var isStyleEditing: Bool { styleEditorEntry.isEditing }

    private var shouldShowChrome: Bool {
        !isStyleEditing && (!appearance.immersiveMode || chromeVisible || isEditMode || showDisplaySettings || showMenu)
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode,
              !isEditMode,
              !showDisplaySettings,
              !showMenu,
              !showGameOverDialog,
              !isStyleEditing else { return }
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
                  !showGameOverDialog,
                  !isStyleEditing else { return }
            if let exitConfirmDeadline, Date() <= exitConfirmDeadline { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || isEditMode || showGameOverDialog || isStyleEditing || !appearance.immersiveMode {
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

        VibrationManager.shared.vibrateLight()
        dispatch(.pointWon(side))
        // 网球双打无位置轮转（发球人整个发球局固定，局间才换），得分时不闪烁。
    }

    private func commitPointWon(_ side: MatchSide) {
        guard !isStyleEditing, !isEditMode, !store.state.finished else { return }
        handlePointWon(side)
    }

    /// 对齐安卓 ScoreboardDoubleTapSubtractHandler：挂起窗口内同侧第二次点击 = 减 1 分，
    /// 异侧点击则先把挂起的这一次结算掉，再为新的半区重新挂起。
    private func handlePanelTap(_ side: MatchSide) {
        guard !isStyleEditing, !isEditMode, !store.state.finished else { return }
        guard onePointDoubleTapEnabled else {
            cancelPendingTap()
            handlePointWon(side)
            return
        }
        let now = Date()
        if let pendingSide = pendingTapSide {
            if pendingSide == side, now.timeIntervalSince(pendingTapAt) <= doubleTapWindow {
                cancelPendingTap()
                VibrationManager.shared.vibrateLight()
                dispatch(.adjustPoints(side: side, delta: -1))
                return
            }
            cancelPendingTap()
            handlePointWon(pendingSide)
        }
        pendingTapSide = side
        pendingTapAt = now
        tapGeneration += 1
        let generation = tapGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow) {
            guard generation == tapGeneration, pendingTapSide == side else { return }
            pendingTapSide = nil
            commitPointWon(side)
        }
    }

    private func cancelPendingTap() {
        tapGeneration += 1
        pendingTapSide = nil
    }

    private func isScoreTouchAllowed(location: CGPoint, panelSize: CGSize) -> Bool {
        ScoreboardTouchGuard.isAllowed(
            location: location,
            panelSize: panelSize,
            gameType: store.gameType,
            enabled: appearance.touchGuard
        )
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
                guard !isStyleEditing, !isEditMode, !scoringLocked else { return }
                // 滑动与点击互斥，先清掉挂起的单击再结算。
                cancelPendingTap()
                if value.translation.width < -50,
                   abs(value.translation.height) < 50 {
                    performUndo()
                } else if value.translation.height < -50,
                          abs(value.translation.width) < 50 {
                    // 对齐安卓上滑加分（scoreboardPanelSwipeGestures onAdd）。
                    guard !store.state.finished else { return }
                    handlePointWon(side)
                } else if value.translation.height > 50,
                          abs(value.translation.width) < 50 {
                    guard !store.state.finished else { return }
                    let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                    guard points > 0 else { return }
                    VibrationManager.shared.vibrateLight()
                    dispatch(.adjustPoints(side: side, delta: -1))
                }
            }
    }

    private func dispatch(_ intent: TennisMatchIntent) {
        guard !scoringLocked else { return }
        switch intent {
        case .pointWon:
            cancelPendingOpeningAnnouncement()
        case .adjustPoints, .adjustGames, .adjustSets, .exchangeSides, .reset:
            cancelPendingOpeningAnnouncement()
            ScoreVoiceAnnouncer.shared.cancelPendingScore()
        default:
            break
        }
        store.send(intent, onTransition: { before, after, events in
            handleEvents(events, before: before, after: after)
        })
        revealImmersiveChrome()
    }

    private func handleEvents(
        _ events: [TennisMatchEvent],
        before: TennisMatchState,
        after: TennisMatchState
    ) {
        var sideToast: String?
        var finalPoints: (left: Int, right: Int)?
        var completedGames: (left: Int, right: Int)?
        var matchFinished = false
        var matchReset = false
        var setCompleted = false
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
            case .setCompleted:
                setCompleted = true
            case .matchReset:
                matchReset = true
            case .officialBreakChanged:
                break
            default:
                break
            }
        }
        if preferences.officialBreaksEnabled, officialBreakSession.state == nil, !matchFinished {
            if setCompleted {
                switch store.gameType {
                case .padel:
                    startOfficialBreak(sport: .padel, kind: .setBreak, durationSeconds: 120, afterAction: .advanceAndExchange)
                case .softTennis:
                    break
                default:
                    startOfficialBreak(sport: .tennis, kind: .setBreak, durationSeconds: 120, afterAction: .advanceAndExchange)
                }
            } else if let completedGames,
                      (completedGames.left + completedGames.right).isMultiple(of: 2) == false,
                      store.gameType == .softTennis || completedGames.left + completedGames.right > 1 {
                let configuration: (OfficialBreakSport, Int) = switch store.gameType {
                case .softTennis: (.softTennis, 60)
                case .padel: (.padel, 90)
                default: (.tennis, 90)
                }
                startOfficialBreak(sport: configuration.0, kind: .changeover, durationSeconds: configuration.1, afterAction: .exchangeSides)
            } else if store.gameType == .softTennis,
                      after.isTieBreak,
                      let finalPoints {
                let totalPoints = finalPoints.left + finalPoints.right
                let shouldRest = totalPoints == 2 || (totalPoints > 2 && (totalPoints - 2).isMultiple(of: 4))
                if shouldRest {
                    startOfficialBreak(sport: .softTennis, kind: .changeover, durationSeconds: 60, afterAction: .exchangeSides)
                }
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
        var compact = LocalScoreboardDisplayState(
            gameID: store.gameType.rawValue,
            title: "",
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
            revision: 0,
            leftSets: leftSide == .left ? state.leftSets : state.rightSets,
            rightSets: rightSide == .left ? state.leftSets : state.rightSets,
            leftGames: leftSide == .left ? state.leftGames : state.rightGames,
            rightGames: rightSide == .left ? state.leftGames : state.rightGames
        )
        let isDoubles = state.doublesPlayerNames != nil
        var displayPlayers: [ScoreboardDisplayPlayer]?
        if let names = state.doublesPlayerNames {
            let leftSlots = tennisDoublesDisplaySlots(screenSide: .left, logicalSide: leftSide)
            let rightSlots = tennisDoublesDisplaySlots(screenSide: .right, logicalSide: rightSide)
            let serverSlot = TennisDoublesServing.currentServerSlot(in: state)
            func player(_ id: String, _ slot: Int, _ teamID: String, _ placement: String, _ order: Int) -> ScoreboardDisplayPlayer {
                ScoreboardDisplayPlayer(
                    id: id,
                    name: names.indices.contains(slot) ? names[slot] : "",
                    teamID: teamID,
                    slot: placement,
                    order: order,
                    isServer: serverSlot == slot
                )
            }
            displayPlayers = [
                player("left_top", leftSlots.top, "team_0", "top", 0),
                player("right_top", rightSlots.top, "team_1", "top", 1),
                player("left_bottom", leftSlots.bottom, "team_0", "bottom", 2),
                player("right_bottom", rightSlots.bottom, "team_1", "bottom", 3)
            ]
        }
        compact.externalState = ScoreboardDisplayState.enriched(
            compact: compact,
            layoutKind: isDoubles ? .doublesCourt : .twoSide,
            players: displayPlayers,
            sportState: tennisSyncSportState(state),
            rest: officialBreakSession.state.map(ScoreboardDisplayRest.init)
        )
        compact.externalState?.appearance = .init(
            snapshot: appearance,
            fontCode: typographyPreference.font.rawValue
        )
        compact.externalState?.appearance.fontSizeMultipliers = ScoreboardDisplayAppearance.multipliers(
            score: typographyPreference.scoreMultiplier,
            name: typographyPreference.nameMultiplier,
            secondary: typographyPreference.secondaryMultiplier
        )
        return compact
    }

    private func logicalSide(forScreen side: MatchSide) -> MatchSide {
        TeamScreenLayout(
            sidesSwapped: terminalGamePresentation?.sidesSwapped ?? store.state.sidesSwapped
        ).engineSide(onScreen: side)
    }

    /// 跨设备同播网球 sportState，对齐安卓 TennisScoreScreen cloudSportState 契约：
    /// 逻辑身份 team_0 = 引擎左方（与 team0ScreenSide 归一化一致），显示端据此还原占先/发球。
    private func tennisSyncSportState(_ state: TennisMatchState) -> [String: ScoreboardDisplayValue] {
        var sport: [String: ScoreboardDisplayValue] = [
            "team0ScreenSide": .string(state.sidesSwapped ? "right" : "left"),
            "servingTeam": .string(state.servingSide == .left ? "team_0" : "team_1"),
            "servingSide": .string(state.servingSide == logicalSide(forScreen: .left) ? "left" : "right"),
            "currentSet": .integer(state.currentSet),
            "tennisIsTieBreak": .boolean(state.isTieBreak),
            "tennisTiebreakOnly": .boolean(state.rules.setScoringMode == .tiebreakOnly),
            "resultScoreLevel": .string(state.rules.setScoringMode == .tiebreakOnly ? "score" :
                (state.rules.familyProfile == .softTennis ? "games" : "sets")),
            "tennisDeuceMode": .string(state.rules.usesNoAdScoring ? "no_ad" : "advantage"),
            "ruleProfileVersion": .integer(1),
            "competitionFormat": .string(state.doublesPlayerNames == nil ? "singles" : "doubles")
        ]
        if state.rules.familyProfile == .softTennis, let matchGames = state.rules.softTennisMatchGames {
            sport["softTennisMatchGames"] = .integer(matchGames)
        }
        if store.gameType == .padel {
            sport["padelDeuceMode"] = .string(state.rules.padelDeuceMode.rawValue)
            sport["starPointReturnedAdvantages"] = .integer(state.starPointReturnedAdvantages ?? 0)
        }
        // 平分/占先：点数序数 >=3 且分差 <=1；协议比分序号与引擎步进值一致（0/1/2/3/4）。
        let isDeuce = !state.isTieBreak
            && state.leftPoints >= 3 && state.rightPoints >= 3
            && abs(state.leftPoints - state.rightPoints) <= 1
        sport["tennisIsDeuce"] = .boolean(isDeuce)
        let advantage: String
        if isDeuce && state.leftPoints > state.rightPoints {
            advantage = "team_0"
        } else if isDeuce && state.rightPoints > state.leftPoints {
            advantage = "team_1"
        } else {
            advantage = "none"
        }
        sport["tennisAdvantage"] = .string(advantage)
        return sport
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
        let extras: [ScoreboardMenuItem] = [
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
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            resetConfirming: menuConfirm.resetConfirming,
            exchangeConfirming: menuConfirm.exchangeConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            scoringEnabled: true,
            extraItems: extras
        )
    }

    private func handleMenu(_ action: String) {
        guard !isEditMode else { return }

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
            store.setVoiceAnnouncementEnabled(!store.voiceAnnouncementEnabled)
            if store.voiceAnnouncementEnabled {
                speakOpeningAnnouncementIfNeeded()
            } else {
                cancelPendingOpeningAnnouncement()
                ScoreVoiceAnnouncer.shared.stop()
            }
        case "displaySettings":
            showMenu = false
            // 白名单项目打开新样式编辑器（对齐安卓 useStyleEditLabel 分叉）。
            if !styleEditorEntry.handleDisplaySettings(
                styleID: typographySession.styleID,
                typographySession: typographySession
            ) {
                showDisplaySettings = true
            }
        case "usageHint":
            showMenu = false
            (usageHintCoordinator ?? usageHintCoordinatorOverride)?.presentFromMenu()
        case "endLink":

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

    private var officialBreakSupported: Bool {
        [.tennis, .tennisDoubles, .softTennis, .padel].contains(store.gameType)
    }

    private func startOfficialBreak(
        sport: OfficialBreakSport,
        kind: OfficialBreakKind,
        durationSeconds: Int,
        afterAction: OfficialBreakAfterAction
    ) {
        guard preferences.officialBreaksEnabled,
              officialBreakSupported,
              officialBreakSession.state == nil else { return }
        officialBreakSession.begin(
            sport: sport,
            kind: kind,
            durationSeconds: durationSeconds,
            afterAction: afterAction,
            nowMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        store.setScoreInputFrozen(true)
        store.send(.setOfficialBreakState(officialBreakSession.state))
        speakOfficialBreakCue(.start)
    }

    private func completeOfficialBreak(_ action: OfficialBreakAfterAction) {
        _ = action
        officialBreakSession = OfficialBreakSession()
        store.setScoreInputFrozen(false)
        store.send(.setOfficialBreakState(nil))
    }

    private func cancelOfficialBreak() {
        officialBreakSession = OfficialBreakSession()
        store.setScoreInputFrozen(false)
        store.send(.setOfficialBreakState(nil))
        performUndo()
    }

    private func speakOfficialBreakCue(_ cue: OfficialBreakCue) {
        guard store.voiceAnnouncementEnabled,
              let breakState = officialBreakSession.state,
              OfficialBreakVoicePolicy.shouldSpeak(
                gameType: store.gameType,
                cue: cue,
                state: breakState,
                officialBreaksEnabled: preferences.officialBreaksEnabled
              ),
              let payload = OfficialBreakVoiceMapper.payload(
                gameType: store.gameType,
                cue: cue,
                state: breakState,
                leftName: store.state.leftName,
                rightName: store.state.rightName,
                leftScore: store.state.leftPoints,
                rightScore: store.state.rightPoints,
                servingSide: store.state.servingSide,
                serverName: tennisOfficialBreakServerName,
                currentSet: store.state.currentSet
              ) else { return }
        ScoreVoiceAnnouncer.shared.speak(payload)
    }

    private var tennisOfficialBreakServerName: String? {
        if let names = store.state.doublesPlayerNames,
           let slot = TennisDoublesServing.currentServerSlot(in: store.state),
           names.indices.contains(slot), !names[slot].isEmpty {
            return names[slot]
        }
        return store.state.servingSide == .left ? store.state.leftName : store.state.rightName
    }

    private func goBack() {
        cancelTerminalGamePresentation()

        store.flush {
            performScoreboardExit(
                onNavigationBack: onNavigationBack,
                dismiss: dismiss
            )
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
        guard !isStyleEditing, !isEditMode else { return }
        cancelTerminalGamePresentation()
        ScoreVoiceAnnouncer.shared.cancelPendingScore()
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
              openingAnnouncementTask == nil,
              TennisVoiceAnnouncementMapper.openingPayload(
                gameType: store.gameType,
                state: store.state
              ) != nil
        else { return }
        openingAnnouncementTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2_500))
            guard !Task.isCancelled,
                  store.voiceAnnouncementEnabled,
                  !didSpeakOpeningAnnouncement,
                  let payload = TennisVoiceAnnouncementMapper.openingPayload(
                    gameType: store.gameType,
                    state: store.state
                  )
            else {
                openingAnnouncementTask = nil
                return
            }
            didSpeakOpeningAnnouncement = true
            openingAnnouncementTask = nil
            ScoreVoiceAnnouncer.shared.speak(payload)
        }
    }

    private func cancelPendingOpeningAnnouncement() {
        openingAnnouncementTask?.cancel()
        openingAnnouncementTask = nil
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
