import SwiftUI
import ScoreCore
import UIKit

struct BasketballScoreboardView: View {
    @Environment(\.dismiss) private var dismiss

    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    @State private var store: BasketballSessionStore
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession: ScoreboardTypographySession
    @State private var preferences = PreferencesManager.shared
    @State private var showDisplaySettings = false
    @State private var showMenu = false
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var exitConfirmDeadline: Date?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var isEditMode = false
    @State private var timeoutPlayPulseGeneration = 0
    @State private var editLeftName = ""
    @State private var editRightName = ""
    @State private var editLeftScore = 0
    @State private var editRightScore = 0
    @State private var editLeftFouls = 0
    @State private var editRightFouls = 0
    @State private var editLeftTimeouts = 0
    @State private var editRightTimeouts = 0
    @State private var isStartingNewMatch = false

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

        let initialStyleID: ScoreboardStyleID
        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let restoredStore = BasketballSessionStore(restoring: sessionId) {
            _store = State(initialValue: restoredStore)
            _showGameOverDialog = State(initialValue: restoredStore.state.finished)
            initialStyleID = ScoreboardStyleID(gameType: restoredStore.state.gameMode == .threeXThree ? .threeBasketball : .basketball)
        } else {
            let gameMode: BasketballGameMode = initialSetup?.basketballMode == "three_x_three" ? .threeXThree : .fiveVFive
            let defaults = DefaultParticipantNames.resolve(
                for: gameMode == .threeXThree ? .threeBasketball : .basketball
            )
            let leftName = resolvedScoreboardSetupName(
                initialSetup?.team1Name,
                fallback: defaults.left
            )
            let rightName = resolvedScoreboardSetupName(
                initialSetup?.team2Name,
                fallback: defaults.right
            )
            let ruleSet: BasketballRuleSet = initialSetup?.basketballRuleSet == "nba" ? .nba : .fiba
            _store = State(initialValue: BasketballSessionStore(
                leftName: leftName,
                rightName: rightName,
                gameMode: gameMode,
                ruleSet: ruleSet
            ))
            initialStyleID = ScoreboardStyleID(gameType: gameMode == .threeXThree ? .threeBasketball : .basketball)
        }
        _typographySession = State(initialValue: ScoreboardTypographySession(styleID: initialStyleID))
    }

    /// The scoreboard fills the physical display with `ignoresSafeArea()`, so
    /// `GeometryProxy.safeAreaInsets` can transiently report zero in landscape.
    /// Keep a key-window fallback for the Dynamic Island / sensor-housing edge.
    private var activeWindowSafeAreaInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        return scene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets
            ?? scene?.windows.first?.safeAreaInsets
            ?? .zero
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                // During rotation SwiftUI may briefly report a width below the
                // fixed center-column target. Clamp every child width so that
                // the transitional layout never receives a negative frame.
                let availableW = max(0, proxy.size.width)
                let centerW = min(
                    availableW,
                    ScoreboardLayoutMetrics.basketballCenterWidth(screenWidth: availableW)
                )
                let sideW = max(0, (availableW - centerW) / 2)
                let sideSize = CGSize(width: sideW, height: proxy.size.height)
                let windowInsets = activeWindowSafeAreaInsets
                let leadingSafeInset = max(proxy.safeAreaInsets.leading, windowInsets.left)
                let trailingSafeInset = max(proxy.safeAreaInsets.trailing, windowInsets.right)
                HStack(spacing: 0) {
                    basketballSidePanel(
                        screenSide: .left,
                        panelSize: sideSize,
                        outerSafeAreaInset: leadingSafeInset
                    )
                    .frame(width: sideW)

                    Group {
                        if isEditMode || showDisplaySettings {
                            Color.black
                        } else {
                            BasketballCenterPanel(
                                state: store.state,
                                typography: typographyPreference,
                                timeoutPlayPulseGeneration: timeoutPlayPulseGeneration,
                                onToggleClock: {
                                    if store.state.timeoutActiveSide != nil {
                                        store.send(.endTimeout, recordsUndo: false)
                                    } else {
                                        store.send(.setClockRunning(!store.state.gameRunning))
                                    }
                                },
                                onResetGameClock: { store.send(.resetGameClock) },
                                onResetShotClock: { store.send(.resetShotClock(seconds: $0)) },
                                onAdvancePeriod: { store.send(.advanceToNextPeriod) },
                                onEnterOvertime: { store.send(.enterOvertime) },
                                onSelectPeriod: { store.send(.selectPeriod($0)) }
                            )
                        }
                    }
                    .frame(width: centerW)

                    basketballSidePanel(
                        screenSide: .right,
                        panelSize: sideSize,
                        outerSafeAreaInset: trailingSafeInset
                    )
                    .frame(width: sideW)
                }
                .background(Color.black)
            }

            if shouldShowChrome {
                chromeOverlay
            }

            if appearance.immersiveMode && !chromeVisible && !isEditMode {
                ImmersiveCornerRevealZones(onReveal: revealImmersiveChrome)
            }

            if showToast {
                ToastView(message: toastMessage)
                    .transition(.opacity.combined(with: .scale))
                    .allowsHitTesting(false)
            }

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: finishedWinnerName,
                    gameType: appGameType,
                    leftName: store.state.leftName,
                    rightName: store.state.rightName,
                    leftScore: store.state.leftScore,
                    rightScore: store.state.rightScore,
                    newGameDisabled: isStartingNewMatch,
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
                            back()
                        }
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        .animation(.easeInOut(duration: 0.2), value: showToast)
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        .onLongPressGesture(minimumDuration: 0.55) {
            guard !isEditMode else { return }
            showMenu = true
            revealImmersiveChrome()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode,
                          !store.state.finished,
                          value.translation.width < -50,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    store.undo { success in
                        showToastMessage(
                            success
                                ? NSLocalizedString("undone", value: "已撤销", comment: "Undo done")
                                : NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: "")
                        )
                    }
                }
        )
        .onAppear {
            onSetupConsumed?()
            typographySession.switchStyleID(ScoreboardStyleID(gameType: appGameType))
            store.startClock()
            appearance = .current(styleID: typographySession.styleID)
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            registerScoreboardSync()
            revealImmersiveChrome()
            if store.state.finished {
                showGameOverDialog = true
            }
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
        .onChange(of: store.state) { _, state in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            if state.finished {
                showGameOverDialog = true
            }
        }
        .onChange(of: store.state.timeoutRemainingSeconds) { previous, remaining in
            guard store.state.timeoutActiveSide != nil, previous > 0, remaining == 0 else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            showToastMessage(NSLocalizedString(
                "basketball_timeout_timeup",
                value: "暂停时间到，点中央播放键恢复比赛",
                comment: "Basketball timeout finished"
            ))
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current(styleID: typographySession.styleID)
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: typographySession.effectivePreference) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
            store.stopClock()
            store.persistSnapshot()
        }
        .overlay {
            MenuDialog(
                isVisible: showMenu,
                onClose: {
                    menuConfirm.clear()
                    showMenu = false
                },
                onMenuItemClick: handleMenuAction,
                showEndGame: true,
                resetConfirming: menuConfirm.resetConfirming,
                items: basketballMenuItems,
                analyticsGameType: store.state.gameMode == .threeXThree ? .threeBasketball : .basketball
            )
        }
        // Keep above MenuDialog so the side panel is not covered.
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.basketball.adjustableMetrics
        )
    }

    private var basketballMenuItems: [ScoreboardMenuItem] {
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: true,
            resetConfirming: menuConfirm.resetConfirming,
            exchangeConfirming: menuConfirm.exchangeConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            scoringEnabled: true
        )
    }

    private var chromeOverlay: some View {
        VStack {
            HStack {
                Spacer()
                chromeButton(systemName: isEditMode ? "checkmark" : "pencil") {
                    if isEditMode {
                        commitBasketballEdits()
                    } else {
                        beginBasketballEdit()
                    }
                }
                .disabled(store.state.finished || store.state.timeoutActiveSide != nil)
                .opacity(store.state.finished || store.state.timeoutActiveSide != nil ? 0.45 : 1)
                .padding(.trailing, ScoreboardConstants.buttonPadding)
                .padding(.top, ScoreboardConstants.buttonPadding)
            }
            Spacer()
            if !isEditMode {
                HStack {
                    chromeButton(systemName: "chevron.left", action: requestBack)
                        .padding(.leading, ScoreboardConstants.buttonPadding)
                        .padding(.bottom, ScoreboardConstants.buttonPadding)
                    Spacer()
                    chromeButton(systemName: "line.3.horizontal") {
                        showMenu = true
                    }
                    .padding(.trailing, ScoreboardConstants.buttonPadding)
                    .padding(.bottom, ScoreboardConstants.buttonPadding)
                }
            }
        }
        .allowsHitTesting(true)
    }

    private func chromeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            revealImmersiveChrome()
        }) {
            Image(systemName: systemName)
                .font(.system(size: ScoreboardConstants.buttonIconSize))
                .foregroundColor(.white)
                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                .background(Circle().fill(systemName == "checkmark" ? Theme.primary : Color.black.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(basketballChromeAccessibilityIdentifier(systemName))
        .modifier(ScoreboardBackButtonAccessibility(isBack: systemName == "chevron.left"))
    }

    private func basketballChromeAccessibilityIdentifier(_ systemName: String) -> String {
        switch systemName {
        case "line.3.horizontal": "scoreboard_menu_button"
        case "pencil", "checkmark": "scoreboard_edit_button"
        default: ScoreboardConstants.backButtonAccessibilityID
        }
    }

    @ViewBuilder
    private func basketballSidePanel(
        screenSide: MatchSide,
        panelSize: CGSize,
        outerSafeAreaInset: CGFloat
    ) -> some View {
        let isScreenLeft = screenSide == .left
        let color = logicalSide(forScreen: screenSide) == .left
            ? Color(hex: "C62828")
            : Color(hex: "007AFF")

        if isEditMode {
            BasketballEditTeamPanel(
                name: isScreenLeft ? $editLeftName : $editRightName,
                score: isScreenLeft ? $editLeftScore : $editRightScore,
                fouls: isScreenLeft ? $editLeftFouls : $editRightFouls,
                timeouts: isScreenLeft ? $editLeftTimeouts : $editRightTimeouts,
                color: color,
                typography: typographyPreference,
                panelSize: panelSize
            )
        } else {
            let logicalSide = logicalSide(forScreen: screenSide)
            BasketballTeamPanel(
                name: displayName(for: screenSide),
                score: displayScore(for: screenSide),
                fouls: displayFouls(for: screenSide),
                timeouts: displayTimeouts(for: screenSide),
                foulDisplayLimit: BasketballMatchEngine.foulDisplayLimit(store.state),
                bonusThreshold: BasketballMatchEngine.bonusThreshold(store.state),
                doubleBonusThreshold: BasketballMatchEngine.doubleBonusThreshold(store.state),
                color: color,
                isLeftSide: isScreenLeft,
                typography: typographyPreference,
                panelSize: panelSize,
                outerSafeAreaInset: outerSafeAreaInset,
                points: BasketballMatchEngine.scoringButtons(store.state),
                timeoutActiveSide: store.state.timeoutActiveSide,
                timeoutRemainingSeconds: store.state.timeoutRemainingSeconds,
                timeoutDurationSeconds: BasketballMatchEngine.timeoutDurationSeconds(store.state),
                logicalSide: logicalSide,
                onScore: {
                    VibrationManager.shared.vibrateLight()
                    store.send(.addPoints(side: logicalSide, points: $0))
                },
                onFoul: { store.addFoul(logicalSide) },
                onRemoveFoul: { store.send(.removeFoul(side: logicalSide)) },
                onTimeout: { store.send(.useTimeout(side: logicalSide)) },
                onRestoreTimeout: { store.send(.adjustTimeout(side: logicalSide, delta: 1)) },
                onTimeoutResumeHint: {
                    timeoutPlayPulseGeneration += 1
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showToastMessage(NSLocalizedString(
                        "basketball_timeout_resume_hint",
                        value: "点中央播放键恢复比赛",
                        comment: "Basketball timeout resume hint"
                    ))
                }
            )
        }
    }

    private func beginBasketballEdit() {
        guard !store.state.finished, store.state.timeoutActiveSide == nil else { return }
        editLeftName = displayName(for: .left)
        editRightName = displayName(for: .right)
        editLeftScore = displayScore(for: .left)
        editRightScore = displayScore(for: .right)
        editLeftFouls = displayFouls(for: .left)
        editRightFouls = displayFouls(for: .right)
        editLeftTimeouts = displayTimeouts(for: .left)
        editRightTimeouts = displayTimeouts(for: .right)
        if store.state.gameRunning {
            store.send(.setClockRunning(false), recordsUndo: false)
        }
        showMenu = false
        isEditMode = true
        revealImmersiveChrome()
    }

    private func commitBasketballEdits() {
        guard isEditMode else { return }
        let edits: [(MatchSide, String, Int, Int, Int)] = [
            (.left, editLeftName, editLeftScore, editLeftFouls, editLeftTimeouts),
            (.right, editRightName, editRightScore, editRightFouls, editRightTimeouts),
        ]
        for (screenSide, proposedName, proposedScore, proposedFouls, proposedTimeouts) in edits {
            let logical = logicalSide(forScreen: screenSide)
            let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != displayName(for: screenSide) {
                store.send(.rename(side: logical, name: trimmed))
            }
            let delta = max(0, proposedScore) - displayScore(for: screenSide)
            if delta != 0 {
                store.send(.adjustScore(side: logical, delta: delta))
            }
            // 对齐安卓编辑模式：犯规/暂停为原始意图修正，不扰动比赛时钟。
            let foulDelta = max(0, proposedFouls) - displayFouls(for: screenSide)
            if foulDelta != 0 {
                if foulDelta > 0 {
                    for _ in 0..<foulDelta {
                        store.addFoul(logical, stopClocks: false)
                    }
                } else {
                    for _ in 0..<(-foulDelta) {
                        store.send(.removeFoul(side: logical))
                    }
                }
            }
            let timeoutDelta = max(0, proposedTimeouts) - displayTimeouts(for: screenSide)
            if timeoutDelta != 0 {
                store.send(.adjustTimeout(side: logical, delta: timeoutDelta))
            }
        }
        isEditMode = false
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        revealImmersiveChrome()
    }

    private func displayName(for side: MatchSide) -> String {
        logicalSide(forScreen: side) == .left ? store.state.leftName : store.state.rightName
    }

    private func displayScore(for side: MatchSide) -> Int {
        logicalSide(forScreen: side) == .left ? store.state.leftScore : store.state.rightScore
    }

    private func displayFouls(for side: MatchSide) -> Int {
        logicalSide(forScreen: side) == .left ? store.state.leftFouls : store.state.rightFouls
    }

    private func displayTimeouts(for side: MatchSide) -> Int {
        logicalSide(forScreen: side) == .left ? store.state.leftTimeouts : store.state.rightTimeouts
    }

    private func logicalSide(forScreen side: MatchSide) -> MatchSide {
        store.teamScreenLayout.engineSide(onScreen: side)
    }

    private var appGameType: GameType {
        store.state.gameMode == .threeXThree ? .threeBasketball : .basketball
    }

    private var typographyPreference: ScoreboardTypographyPreference {
        typographySession.effectivePreference
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || isEditMode || showDisplaySettings || showMenu
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !isEditMode, !showDisplaySettings, !showMenu else { return }
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
                  !showMenu else { return }
            if let exitConfirmDeadline, Date() <= exitConfirmDeadline { return }
            chromeVisible = false
        }
    }

    private func handleMenuAction(_ action: String) {
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            store.undo { success in
                showToastMessage(
                    success
                        ? NSLocalizedString("undone", value: "已撤销", comment: "Undo done")
                        : NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: "")
                )
            }
        case ScoreboardMenuActionID.exchangeSide.rawValue:
            if menuConfirm.armOrConfirm(.exchangeSide) {
                store.send(.exchangeSides)
            } else {
                showConfirmToast(.exchangeSide)
            }
        case "reset":
            if menuConfirm.armOrConfirm(.reset) {
                showGameOverDialog = false
                store.send(.reset)
                showToastMessage(NSLocalizedString("has_been_reset", value: "已重置", comment: ""))
                showMenu = false
            } else {
                showConfirmToast(.reset)
            }
        case "endGame":
            if menuConfirm.armOrConfirm(.finish) {
                store.send(.finish)
                showGameOverDialog = true
                showMenu = false
            } else {
                showConfirmToast(.finish)
            }
        case "displaySettings":
            showDisplaySettings = true
            showMenu = false
        case "whistle":
            break
        default:
            break
        }
    }

    private func showConfirmToast(_ action: ScoreboardMenuConfirmAction) {
        showToastMessage(action.localizedToast)
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: {
                var compact = LocalScoreboardDisplayState(
                    gameID: appGameType.canonicalScoreboardIdentifier,
                    title: "",
                    leftName: displayName(for: .left),
                    rightName: displayName(for: .right),
                    leftScore: "\(displayScore(for: .left))",
                    rightScore: "\(displayScore(for: .right))",
                    leftDetail: basketballDetail(for: .left),
                    rightDetail: basketballDetail(for: .right),
                    themeID: appearance.theme.rawValue,
                    fontID: typographyPreference.font.rawValue,
                    scoreMultiplier: typographyPreference.scoreMultiplier,
                    nameMultiplier: typographyPreference.nameMultiplier,
                    secondaryMultiplier: typographyPreference.secondaryMultiplier,
                    finished: store.state.finished,
                    revision: 0
                )
                let leftSide = logicalSide(forScreen: .left)
                let rightSide = logicalSide(forScreen: .right)
                let screenLeftFouls = leftSide == .left ? store.state.leftFouls : store.state.rightFouls
                let screenRightFouls = rightSide == .left ? store.state.leftFouls : store.state.rightFouls
                let team0OnLeft = leftSide == .left
                let logicalLeftFouls = team0OnLeft ? screenLeftFouls : screenRightFouls
                let logicalRightFouls = team0OnLeft ? screenRightFouls : screenLeftFouls
                // 对齐安卓：篮球不发送通用 clock，节次/时间由显示端 BasketballClockPill 承载。
                compact.externalState = ScoreboardDisplayState.enriched(
                    compact: compact,
                    layoutKind: .twoSide,
                    sportState: [
                        "team0ScreenSide": .string(team0OnLeft ? "left" : "right"),
                        "basketballLeftFouls": .integer(logicalLeftFouls),
                        "basketballRightFouls": .integer(logicalRightFouls),
                        "basketballCurrentPeriod": .integer(store.state.currentPeriod),
                        "basketballIsOT": .boolean(store.state.isOvertime),
                        "basketballGameTime": .integer(store.state.gameTimeSeconds),
                        "basketballShotTime": .integer(store.state.shotTimeSeconds),
                        "basketballClockRevision": .integer(Int(Date().timeIntervalSince1970)),
                        "basketballGameRunning": .boolean(store.state.gameRunning),
                        "basketballShotRunning": .boolean(store.state.shotRunning),
                        "basketballClockStarted": .boolean(store.basketballClockStarted)
                    ]
                )
                let multipliers = compact.externalState?.appearance.fontSizeMultipliers
                compact.externalState?.appearance = .init(
                    snapshot: appearance,
                    fontCode: typographyPreference.font.rawValue
                )
                compact.externalState?.appearance.fontSizeMultipliers = multipliers
                return compact
            },
            handleIntent: { intent in
                guard LocalScoreboardMutationPolicy.allowsMutation(
                    isEditing: isEditMode,
                    finished: store.state.finished,
                    scoringLocked: false
                ) else { return }
                switch intent {
                case .addLeft: store.send(.addPoints(side: logicalSide(forScreen: .left), points: 1))
                case .addRight: store.send(.addPoints(side: logicalSide(forScreen: .right), points: 1))
                case .subtractLeft, .subtractRight, .undo: store.undo()
                case .exchangeSides: store.send(.exchangeSides)
                case .requestSnapshot: break
                }
            }
        )
    }

    private func basketballDetail(for side: MatchSide) -> String {
        let fouls = String.localizedStringWithFormat(
            NSLocalizedString("basketball_fouls_count", value: "Fouls %d", comment: ""),
            displayFouls(for: side)
        )
        let timeouts = String.localizedStringWithFormat(
            NSLocalizedString("basketball_timeout_remaining", value: "Timeout (%d)", comment: ""),
            displayTimeouts(for: side)
        )
        return "\(fouls) · \(timeouts)"
    }

    private func requestBack() {
        let now = Date()
        if exitConfirmDeadline.map({ now <= $0 }) != true {
            exitConfirmDeadline = now.addingTimeInterval(2)
            showToastMessage(NSLocalizedString("press_again_to_exit", value: "再按一次退出", comment: ""))
            VibrationManager.shared.vibrateHeavy()
            revealImmersiveChrome()
            return
        }
        exitConfirmDeadline = nil
        back()
    }

    private func back() {
        store.flush {
            if let onNavigationBack {
                onNavigationBack()
            } else {
                dismiss()
            }
        }
    }

    private var finishedWinnerName: String {
        guard store.state.finished else { return "" }
        if store.state.leftScore == store.state.rightScore { return "" }
        return store.state.leftScore > store.state.rightScore ? store.state.leftName : store.state.rightName
    }

    private func shareFinishedMatch() {
        let text = "\(store.state.leftName) \(store.state.leftScore) - \(store.state.rightScore) \(store.state.rightName)"
        ScoreboardShareSupport.present(text: text)
    }

    private func startNewMatch() {
        guard !isStartingNewMatch else { return }
        isStartingNewMatch = true
        let finishedStore = store
        finishedStore.stopClock()
        finishedStore.persistSnapshot { success in
            guard success else {
                isStartingNewMatch = false
                store.startClock()
                return
            }
            let freshStore = finishedStore.makeFreshMatchStore()
            freshStore.persistSnapshot { freshSaved in
                isStartingNewMatch = false
                guard freshSaved else {
                    store.startClock()
                    return
                }
                store = freshStore
                isEditMode = false
                showMenu = false
                menuConfirm.clear()
                showGameOverDialog = false
                editLeftName = displayName(for: .left)
                editRightName = displayName(for: .right)
                editLeftScore = displayScore(for: .left)
                editRightScore = displayScore(for: .right)
                store.startClock()
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            }
        }
    }
}

private struct BasketballEditTeamPanel: View {
    @Binding var name: String
    @Binding var score: Int
    @Binding var fouls: Int
    @Binding var timeouts: Int
    let color: Color
    let typography: ScoreboardTypographyPreference
    let panelSize: CGSize

    private var resolvedTypography: ScoreboardTypographyResult {
        ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .basketball,
                containerSize: panelSize,
                nameText: name,
                scoreText: "\(score)",
                secondaryText: "",
                preference: typography,
                horizontalPadding: 20,
                reservedHeight: 48,
                isLargeScreen: Theme.usesPadLayout
            )
        )
    }

    var body: some View {
        ZStack {
            color

            VStack(spacing: 18) {
                ScoreboardNameEditorField(
                    placeholder: NSLocalizedString("setup_team_name", value: "队伍名称", comment: ""),
                    text: $name,
                    nameType: ScoreboardCommonNamePolicy.nameType(for: .basketball),
                    scoreboardFont: typography.font
                )
                .padding(.horizontal, 16)

                HStack(spacing: 16) {
                    adjustButton(systemName: "minus") {
                        score = max(0, score - 1)
                    }
                    Text("\(score)")
                        .font(typography.font.swiftUIFont(
                            size: ScoreboardLayoutMetrics.editMainScoreFontSize(
                                regularSize: resolvedTypography.scoreFontSize
                            )
                        ))
                        .monospacedDigit()
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                    adjustButton(systemName: "plus") {
                        score = min(999, score + 1)
                    }
                }

                // 对齐安卓 BasketballScoreRouteScreen 编辑模式：底部「犯规/暂停」±调整行。
                HStack(spacing: 12) {
                    metricAdjust(
                        label: NSLocalizedString("basketball_fouls", value: "犯规", comment: ""),
                        value: fouls,
                        minusEnabled: fouls > 0
                    ) { fouls = max(0, fouls - 1) } plus: { fouls = min(99, fouls + 1) }
                        .frame(maxWidth: .infinity)
                    metricAdjust(
                        label: NSLocalizedString("basketball_timeout", value: "暂停", comment: ""),
                        value: timeouts,
                        minusEnabled: timeouts > 0
                    ) { timeouts = max(0, timeouts - 1) } plus: { timeouts = min(99, timeouts + 1) }
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 10)
            }
            .foregroundStyle(.white)
            .offset(y: ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: panelSize.height))
        }
    }

    /// 对齐安卓 BasketballEditMetricAdjust：标签 + 小号 ±调整行（值 22pt）。
    private func metricAdjust(
        label: String,
        value: Int,
        minusEnabled: Bool,
        minus: @escaping () -> Void,
        plus: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Button(action: minus) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(minusEnabled ? .white.opacity(0.8) : .white.opacity(0.3))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .disabled(!minusEnabled)
                Text("\(value)")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 34)
                Button(action: plus) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func adjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            // 对齐安卓 ScoreEditAdjustRows：编辑面板比分 ± 按钮轻震反馈。
            VibrationManager.shared.vibrateLight()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

private struct BasketballTeamPanel: View {
    let name: String
    let score: Int
    let fouls: Int
    let timeouts: Int
    let foulDisplayLimit: Int
    let bonusThreshold: Int
    let doubleBonusThreshold: Int
    let color: Color
    let isLeftSide: Bool
    let typography: ScoreboardTypographyPreference
    let panelSize: CGSize
    let outerSafeAreaInset: CGFloat
    let points: [Int]
    let timeoutActiveSide: MatchSide?
    let timeoutRemainingSeconds: Int
    let timeoutDurationSeconds: Int
    let logicalSide: MatchSide
    let onScore: (Int) -> Void
    let onFoul: () -> Void
    let onRemoveFoul: () -> Void
    let onTimeout: () -> Void
    let onRestoreTimeout: () -> Void
    let onTimeoutResumeHint: () -> Void

    @State private var timeoutPendingConfirmation = false

    private let bonusYellow = Color(hex: "FACC15")
    private let additionalOuterPadding: CGFloat = 8

    private var scoreButtonSize: CGFloat {
        guard Theme.usesPadLayout else { return 50 }
        let widthLimitedSize = panelSize.width * 0.3
        let heightLimitedSize = (panelSize.height - 96) / 3.25
        return min(72, max(44, min(widthLimitedSize, heightLimitedSize)))
    }

    private var scoreButtonFontSize: CGFloat {
        guard Theme.usesPadLayout else { return 16 }
        return min(22, max(15, 16 + (scoreButtonSize - 50) * 6 / 22))
    }

    private var scoreButtonSpacing: CGFloat {
        guard Theme.usesPadLayout else { return 10 }
        return min(16, max(8, 10 + (scoreButtonSize - 50) * 6 / 22))
    }

    private var resolvedTypography: ScoreboardTypographyResult {
        ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .basketball,
                containerSize: panelSize,
                nameText: name,
                scoreText: "\(score)",
                secondaryText: "\(fouls) \(timeouts)",
                preference: typography,
                horizontalPadding: 64 + outerSafeAreaInset,
                reservedHeight: 76,
                isLargeScreen: Theme.usesPadLayout
            )
        )
    }

    private var foulBonusLabel: String? {
        if doubleBonusThreshold > 0, fouls >= doubleBonusThreshold { return "DBL" }
        if fouls >= bonusThreshold { return "BONUS" }
        return nil
    }

    private var timeoutLocked: Bool { timeoutActiveSide != nil }
    private var isActiveTimeoutSide: Bool { timeoutActiveSide == logicalSide }

    private var timeoutTone: Color {
        guard isActiveTimeoutSide else { return .white.opacity(timeouts > 0 ? 0.9 : 0.5) }
        if timeoutRemainingSeconds == 0 { return Color(hex: "EF4444") }
        if timeoutRemainingSeconds <= Int(Double(timeoutDurationSeconds) * 0.2) {
            return Color(hex: "F0883E")
        }
        return .white.opacity(0.9)
    }

    var body: some View {
        ZStack {
            color

            HStack(spacing: 0) {
                if isLeftSide {
                    scoreButtons
                        .padding(.leading, outerSafeAreaInset + additionalOuterPadding)
                }

                Text("\(score)")
                    .font(typography.font.swiftUIFont(
                        size: resolvedTypography.scoreFontSize
                            * ScoreboardLayoutMetrics.threeDigitMainScoreScale(scoreText: "\(score)")
                    ))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)

                if !isLeftSide {
                    scoreButtons
                        .padding(.trailing, outerSafeAreaInset + additionalOuterPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Text(name)
                    .font(typography.font.swiftUIFont(
                        size: resolvedTypography.nameFontSize,
                        weight: .bold
                    ))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: panelSize.height))
                    .padding(.horizontal, 8)
                Spacer()
            }

            GeometryReader { geo in
                foulRow
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.84)
            }

            VStack {
                Spacer()
                HStack {
                    if isLeftSide { Spacer() }
                    timeoutChip
                        .padding(isLeftSide ? .trailing : .leading, 12)
                        .padding(.bottom, 12)
                    if !isLeftSide { Spacer() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: timeoutActiveSide) { _, _ in
            timeoutPendingConfirmation = false
        }
        .task(id: timeoutPendingConfirmation) {
            guard timeoutPendingConfirmation else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            timeoutPendingConfirmation = false
        }
    }

    private var scoreButtons: some View {
        VStack(spacing: scoreButtonSpacing) {
            ForEach(points, id: \.self) { point in
                Button(action: { onScore(point) }) {
                    Text("+\(point)")
                        .font(.system(size: scoreButtonFontSize, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: scoreButtonSize, height: scoreButtonSize)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(timeoutLocked)
        .opacity(timeoutLocked ? 0.45 : 1)
    }

    private var foulRow: some View {
        HStack(spacing: 8) {
            Text(String.localizedStringWithFormat(
                NSLocalizedString("basketball_fouls_count", value: "Fouls %d", comment: ""),
                fouls
            ))
                .font(typography.font.swiftUIFont(
                    size: min(18, max(12, resolvedTypography.secondaryFontSize * 0.35)),
                    weight: .semibold
                ))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                ForEach(0..<foulDisplayLimit, id: \.self) { index in
                    Circle()
                        .fill(index < fouls ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }

            if let label = foulBonusLabel {
                Text(label)
                    .font(typography.font.swiftUIFont(
                        size: min(16, max(11, resolvedTypography.secondaryFontSize * 0.34)),
                        weight: .bold
                    ))
                    .foregroundStyle(bonusYellow)
            }
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier(isLeftSide ? "basketball_left_foul_row" : "basketball_right_foul_row")
        .accessibilityValue("\(fouls)")
        .gesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in onRemoveFoul() }
                .exclusively(
                    before: TapGesture()
                        .onEnded { onFoul() }
                )
        )
        .allowsHitTesting(!timeoutLocked)
        .opacity(timeoutLocked ? 0.45 : 1)
    }

    private var timeoutChip: some View {
        Group {
            if isActiveTimeoutSide {
                HStack(spacing: 6) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(String(format: "%d:%02d", timeoutRemainingSeconds / 60, timeoutRemainingSeconds % 60))
                        .font(typography.font.swiftUIFont(size: 19, weight: .bold))
                        .monospacedDigit()
                }
            } else {
                Text(timeoutPendingConfirmation
                    ? NSLocalizedString("basketball_timeout_confirm", value: "确认暂停", comment: "Basketball timeout confirmation")
                    : String.localizedStringWithFormat(
                        NSLocalizedString("basketball_timeout_remaining", value: "Timeout (%d)", comment: ""),
                        timeouts
                    )
                )
                .font(typography.font.swiftUIFont(
                    size: min(16, max(12, resolvedTypography.secondaryFontSize * 0.3)),
                    weight: .semibold
                ))
            }
        }
        .foregroundStyle(timeoutTone)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(
                isActiveTimeoutSide || timeoutPendingConfirmation
                    ? timeoutTone.opacity(0.16)
                    : Color.white.opacity(0.14)
            )
        )
        .contentShape(Capsule())
        .accessibilityIdentifier(isLeftSide ? "basketball_timeout_left" : "basketball_timeout_right")
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard timeoutActiveSide == nil else {
                        onTimeoutResumeHint()
                        return
                    }
                    timeoutPendingConfirmation = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRestoreTimeout()
                }
                .exclusively(
                    before: TapGesture().onEnded {
                        if timeoutActiveSide != nil {
                            onTimeoutResumeHint()
                        } else if timeoutPendingConfirmation {
                            timeoutPendingConfirmation = false
                            onTimeout()
                        } else if timeouts > 0 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            timeoutPendingConfirmation = true
                        }
                    }
                )
        )
    }
}

private struct BasketballCenterPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: BasketballMatchState
    let typography: ScoreboardTypographyPreference
    let timeoutPlayPulseGeneration: Int
    let onToggleClock: () -> Void
    let onResetGameClock: () -> Void
    let onResetShotClock: (Int) -> Void
    let onAdvancePeriod: () -> Void
    let onEnterOvertime: () -> Void
    let onSelectPeriod: (Int) -> Void

    @State private var showPeriodPicker = false
    @State private var shotClockBlinkPhase = false
    @State private var clockControlPulseScale: CGFloat = 1

    private let centerBG = Color(hex: "111827")
    private let actionAccent = Theme.primary
    private let overtimePurple = Color(hex: "7C3AED")
    private let shotYellow = Color(hex: "FACC15")
    private let shotExpired = Color(hex: "EF4444")

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                let upperHeight = proxy.size.height * 2 / 3
                let resolvedTypography = ScoreboardTypographyResolver.resolve(
                    ScoreboardTypographyLayoutContext(
                        profile: .basketball,
                        containerSize: proxy.size,
                        nameText: periodTitle,
                        scoreText: clockText(state.gameTimeSeconds),
                        secondaryText: "\(state.shotTimeSeconds)",
                        preference: typography,
                        horizontalPadding: 12,
                        reservedHeight: proxy.size.height * 0.42,
                        scoreBaseScale: 0.72,
                        nameBaseScale: 0.72,
                        secondaryBaseScale: 0.72,
                        isLargeScreen: Theme.usesPadLayout
                    )
                )
                VStack(spacing: 0) {
                    upperZone(typography: resolvedTypography)
                        .frame(maxWidth: .infinity)
                        .frame(height: upperHeight, alignment: .top)

                    lowerZone(typography: resolvedTypography)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(0, proxy.size.height - upperHeight))
                }
            }
            .background(centerBG)

            if showPeriodPicker {
                periodPickerOverlay
            }
        }
        .onChange(of: state.timeoutActiveSide) { _, activeSide in
            if activeSide != nil { showPeriodPicker = false }
        }
    }

    private func upperZone(typography: ScoreboardTypographyResult) -> some View {
        VStack(spacing: showsPeriodActionButton ? 8 : 14) {
            if state.gameMode == .fiveVFive {
                Button {
                    showPeriodPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(periodTitle)
                            .font(self.typography.font.swiftUIFont(
                                size: max(16, typography.nameFontSize * 0.62),
                                weight: .bold
                            ))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .rotationEffect(.degrees(showPeriodPicker ? 180 : 0))
                    }
                    .frame(height: ScoreboardConstants.minimumTouchTarget)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.timeoutActiveSide != nil)
                .opacity(state.timeoutActiveSide == nil ? 1 : 0.45)
            } else {
                Text(periodTitle)
                    .font(self.typography.font.swiftUIFont(
                        size: max(16, typography.nameFontSize * 0.62),
                        weight: .bold
                    ))
                    .foregroundStyle(.white)
                    .frame(height: 40)
            }

            if showsGameClock {
                Text(clockText(state.gameTimeSeconds))
                    .font(typographyPreferenceFont(size: typography.scoreFontSize))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.5, perform: onResetGameClock)
                    .accessibilityIdentifier("basketball_game_clock")
            }

            if state.canAdvancePeriod && !state.isOvertime {
                periodActionButton(
                    title: NSLocalizedString("basketball_next_period", value: "Next Period", comment: ""),
                    color: actionAccent,
                    action: onAdvancePeriod
                )
            }
            if state.canAdvancePeriod && state.isOvertime {
                periodActionButton(
                    title: NSLocalizedString("basketball_extra_overtime", value: "Extra OT", comment: ""),
                    color: overtimePurple,
                    action: onAdvancePeriod
                )
            }
            if shouldShowEnterOvertime {
                periodActionButton(
                    title: NSLocalizedString("basketball_enter_overtime", value: "Overtime", comment: ""),
                    color: overtimePurple,
                    action: onEnterOvertime
                )
            }

            Button(action: onToggleClock) {
                Image(systemName: state.gameRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .scaleEffect(clockControlPulseScale)
            .accessibilityIdentifier("basketball_clock_toggle")
            .accessibilityLabel(NSLocalizedString(
                state.gameRunning ? "pause" : "resume",
                comment: "Basketball clock control"
            ))
            .onAppear { updateClockControlPulse() }
            .onChange(of: state.gameRunning) { _, _ in updateClockControlPulse() }
            .onChange(of: timeoutPlayPulseGeneration) { _, _ in pulseClockControlOnce() }
            .onChange(of: reduceMotion) { _, _ in updateClockControlPulse() }
        }
        .padding(.top, showsPeriodActionButton ? 8 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func lowerZone(typography: ScoreboardTypographyResult) -> some View {
        VStack(spacing: Theme.usesPadLayout ? 14 : 10) {
            Text("\(state.shotTimeSeconds)″")
                .font(typographyPreferenceFont(size: max(18, typography.secondaryFontSize * 0.56)))
                .monospacedDigit()
                .foregroundStyle(state.shotTimeSeconds <= 0 ? shotExpired : shotYellow)
                .opacity(state.shotTimeSeconds <= 0 ? (shotClockBlinkPhase ? 1 : 0.25) : 1)
                .animation(
                    state.shotTimeSeconds <= 0
                        ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                        : .default,
                    value: shotClockBlinkPhase
                )
                .onAppear { shotClockBlinkPhase = true }
                .onChange(of: state.shotTimeSeconds) { _, seconds in
                    if seconds <= 0 { shotClockBlinkPhase.toggle() }
                }

            HStack(spacing: Theme.usesPadLayout ? 12 : 10) {
                ForEach(shotOptions, id: \.self) { seconds in
                    Button {
                        onResetShotClock(seconds)
                    } label: {
                        Text("\(seconds)")
                            .font(.system(size: Theme.usesPadLayout ? 18 : 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(
                                width: shotButtonWidth,
                                height: Theme.usesPadLayout ? 56 : ScoreboardConstants.minimumTouchTarget
                            )
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var periodPickerOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Theme.scoreboardDialogScrim
                    .ignoresSafeArea()
                    .onTapGesture { showPeriodPicker = false }

                VStack(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(1...4, id: \.self) { period in
                            Button {
                                onSelectPeriod(period)
                                showPeriodPicker = false
                            } label: {
                                Text("Q\(period)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(state.currentPeriod == period && !state.isOvertime ? .white : .white.opacity(0.85))
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: ScoreboardConstants.minimumTouchTarget
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(state.currentPeriod == period && !state.isOvertime ? actionAccent : Color.white.opacity(0.12))
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(state.timeoutActiveSide != nil)
                        }
                    }

                    Button {
                        onEnterOvertime()
                        showPeriodPicker = false
                    } label: {
                        Text("OT")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(state.isOvertime ? .white : .white.opacity(0.85))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: ScoreboardConstants.minimumTouchTarget
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(state.isOvertime ? overtimePurple : Color.white.opacity(0.12))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(state.timeoutActiveSide != nil)
                }
                .padding(12)
                .frame(width: max(0, proxy.size.width - 16))
                .background(RoundedRectangle(cornerRadius: 12).fill(centerBG))
                .padding(.top, periodPickerTopPadding)
            }
        }
    }

    private func typographyPreferenceFont(size: CGFloat) -> Font {
        typography.font.swiftUIFont(size: size, weight: .bold)
    }

    /// The period chip is the visual anchor: top padding + 40pt chip + 8pt gap.
    private var periodPickerTopPadding: CGFloat {
        (showsPeriodActionButton ? 8 : 18) + 40 + 8
    }

    private func periodActionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 92, height: ScoreboardConstants.minimumTouchTarget)
                .background(RoundedRectangle(cornerRadius: 8).fill(color))
        }
        .buttonStyle(.plain)
        .disabled(state.timeoutActiveSide != nil)
        .opacity(state.timeoutActiveSide == nil ? 1 : 0.45)
    }

    private var shouldShowEnterOvertime: Bool {
        state.gameMode == .fiveVFive
            && !state.isOvertime
            && state.currentPeriod >= 4
            && state.gameTimeSeconds == 0
            && state.leftScore == state.rightScore
            && !state.finished
    }

    private var showsPeriodActionButton: Bool {
        state.canAdvancePeriod || shouldShowEnterOvertime
    }

    /// 三人篮球加时赛只走 12 秒进攻钟，比赛钟恒为 00:00 且不推进。
    /// 此时隐藏比赛钟：避免显示一个冻结的 00:00，也避免长按触发 resetGameClock
    /// （会 isOvertime=false 并把时钟灌回 10:00，等于静默退出加时）。与安卓一致。
    private var showsGameClock: Bool {
        !(state.gameMode == .threeXThree && state.isOvertime)
    }

    private var periodTitle: String {
        if state.isOvertime { return "OT" }
        return state.gameMode == .threeXThree ? "3x3" : "Q\(state.currentPeriod)"
    }

    private var shotOptions: [Int] {
        state.gameMode == .threeXThree ? [12] : [14, 24]
    }

    private var shotButtonWidth: CGFloat {
        if Theme.usesPadLayout {
            return shotOptions.count == 1 ? 96 : 68
        }
        return shotOptions.count == 1 ? 72 : 52
    }

    /// Matches Android and HarmonyOS: when the game clock is stopped, the play
    /// control gently breathes from 1.0x to 1.12x over 900ms to invite a tap.
    private func updateClockControlPulse() {
        guard !state.gameRunning, !reduceMotion else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                clockControlPulseScale = 1
            }
            return
        }

        clockControlPulseScale = 1
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            clockControlPulseScale = 1.12
        }
    }

    private func pulseClockControlOnce() {
        withAnimation(.easeOut(duration: 0.12)) {
            clockControlPulseScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            updateClockControlPulse()
        }
    }

    private func clockText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct BasketballScoreboardView_Previews: PreviewProvider {
    static var previews: some View {
        BasketballScoreboardView()
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
