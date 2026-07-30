import SwiftUI
import ScoreCore
import LinkCore
import UIKit

struct BasketballScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService

    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    @State private var store: BasketballSessionStore
    @State private var watchSessionId: UUID?
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
    @State private var editLeftName = ""
    @State private var editRightName = ""
    @State private var editLeftScore = 0
    @State private var editRightScore = 0
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

        let initialStyleID: ScoreboardStyleID
        if let initialRecordId,
           let sessionId = UUID(uuidString: initialRecordId),
           let restoredStore = BasketballSessionStore(restoring: sessionId) {
            _store = State(initialValue: restoredStore)
            _showGameOverDialog = State(initialValue: restoredStore.state.finished)
            initialStyleID = ScoreboardStyleID(gameType: restoredStore.state.gameMode == .threeXThree ? .threeBasketball : .basketball)
        } else {
            let leftName = resolvedScoreboardSetupName(
                initialSetup?.team1Name,
                fallback: NSLocalizedString("team_home", value: "主队", comment: "Home team")
            )
            let rightName = resolvedScoreboardSetupName(
                initialSetup?.team2Name,
                fallback: NSLocalizedString("team_away", value: "客队", comment: "Away team")
            )
            let gameMode: BasketballGameMode = initialSetup?.basketballMode == "three_x_three" ? .threeXThree : .fiveVFive
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
        _watchSessionId = State(initialValue: initialSetup?.linkedWatchSessionId)
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
                        if isEditMode {
                            Color.black
                        } else {
                            BasketballCenterPanel(
                                state: store.state,
                                typography: typographyPreference,
                                onToggleClock: { guard !scoringLocked else { return }; store.send(.setClockRunning(!store.state.gameRunning)) },
                                onResetGameClock: { guard !scoringLocked else { return }; store.send(.resetGameClock) },
                                onResetShotClock: { guard !scoringLocked else { return }; store.send(.resetShotClock(seconds: $0)) },
                                onAdvancePeriod: { guard !scoringLocked else { return }; store.send(.advanceToNextPeriod) },
                                onEnterOvertime: { guard !scoringLocked else { return }; store.send(.enterOvertime) },
                                onSelectPeriod: { guard !scoringLocked else { return }; store.send(.selectPeriod($0)) }
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
                            back()
                        }
                    }
                )
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
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
                    guard !scoringLocked,
                          !isEditMode,
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
            updateClockOwnership()
            appearance = .current()
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
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("done", value: "完成", comment: "")) {
                                showFinishedRecordDetail = false
                            }
                        }
                    }
            }
        }
        .onChange(of: store.state) { _, state in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            if let watchSessionId, watchLinkService.isController {
                watchLinkService.syncWatch(
                    sessionId: watchSessionId,
                    state: state,
                    detailedActions: store.actionTimeline
                )
            }
            if state.finished {
                showGameOverDialog = true
                store.persistSnapshot()
            }
        }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId,
                  let update,
                  update.sessionId == watchSessionId,
                  let basketball = update.snapshot.basketballState else { return }
            Task {
                _ = await store.applyAuthoritativeState(
                    basketball,
                    detailedActions: update.detailedActions,
                    revision: update.revision
                )
            }
        }
        .onChange(of: watchLinkService.isFollower) { _, _ in
            updateClockOwnership()
        }
        .onChange(of: watchLinkService.isAuthorityTransferPending) { _, _ in
            updateClockOwnership()
        }
        .onChange(of: watchSessionId) { _, _ in
            updateClockOwnership()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: typographySession.effectivePreference) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
            if let watchSessionId {
                watchLinkService.endWatchSession(watchSessionId)
            }
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
                items: basketballMenuItems
            )
        }
        // Keep above MenuDialog so the side panel is not covered.
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.basketball.adjustableMetrics
        )
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

    private func updateClockOwnership() {
        if scoringLocked {
            store.stopClock()
        } else {
            store.startClock()
        }
    }

    private var basketballMenuItems: [ScoreboardMenuItem] {
        let extras = WatchLinkMenuSupport.extraItems(
            entryEnabled: AppFeatureFlags.watchLinkEntryEnabled,
            sessionId: watchSessionId,
            isFollower: watchLinkService.isFollower,
            watchBackgrounded: watchLinkService.watchBackgrounded
        )
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: true,
            resetConfirming: menuConfirm.resetConfirming,
            exchangeConfirming: menuConfirm.exchangeConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            scoringEnabled: !scoringLocked,
            extraItems: extras
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
                .disabled(scoringLocked || store.state.finished)
                .opacity(scoringLocked || store.state.finished ? 0.45 : 1)
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
                color: color,
                typography: typographyPreference,
                panelSize: panelSize
            )
        } else {
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
                onScore: { guard !scoringLocked else { return }; store.send(.addPoints(side: logicalSide(forScreen: screenSide), points: $0)) },
                onFoul: { guard !scoringLocked else { return }; store.send(.addFoul(side: logicalSide(forScreen: screenSide))) },
                onRemoveFoul: { guard !scoringLocked else { return }; store.send(.removeFoul(side: logicalSide(forScreen: screenSide))) },
                onTimeout: { guard !scoringLocked else { return }; store.send(.useTimeout(side: logicalSide(forScreen: screenSide))) }
            )
        }
    }

    private func beginBasketballEdit() {
        guard !scoringLocked, !store.state.finished else { return }
        editLeftName = displayName(for: .left)
        editRightName = displayName(for: .right)
        editLeftScore = displayScore(for: .left)
        editRightScore = displayScore(for: .right)
        if store.state.gameRunning {
            store.send(.setClockRunning(false), recordsUndo: false)
        }
        showMenu = false
        isEditMode = true
        revealImmersiveChrome()
    }

    private func commitBasketballEdits() {
        guard isEditMode else { return }
        let edits: [(MatchSide, String, Int)] = [
            (.left, editLeftName, editLeftScore),
            (.right, editRightName, editRightScore),
        ]
        for (screenSide, proposedName, proposedScore) in edits {
            let logical = logicalSide(forScreen: screenSide)
            let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != displayName(for: screenSide) {
                store.send(.rename(side: logical, name: trimmed))
            }
            let delta = max(0, proposedScore) - displayScore(for: screenSide)
            if delta != 0 {
                store.send(.adjustScore(side: logical, delta: delta))
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
        if scoringLocked,
           !ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked(action) {
            showToastMessage(NSLocalizedString("linked_score_phone_follower", value: "当前由手表计分", comment: ""))
            return
        }
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
        case "exchangeSide":
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
                store.persistSnapshot()
                showMenu = false
            } else {
                showConfirmToast(.finish)
            }
        case "displaySettings":
            showDisplaySettings = true
            showMenu = false
        case "whistle":
            break
        case "resync":
            watchLinkService.requestScoreResync()
            showMenu = false
        case "takeover":
            if let id = watchSessionId {
                Task {
                    if let update = watchLinkService.latestRemoteSnapshot,
                       update.sessionId == id,
                       let state = update.snapshot.basketballState {
                        _ = await store.applyAuthoritativeState(
                            state,
                            detailedActions: update.detailedActions,
                            revision: update.revision
                        )
                    }
                    try? await watchLinkService.takeover(sessionId: id)
                    watchLinkService.syncWatch(
                        sessionId: id,
                        state: store.state,
                        detailedActions: store.actionTimeline
                    )
                }
            }
            showMenu = false
        case "endLink":
            if let id = watchSessionId {
                watchLinkService.leaveSession(id)
                watchSessionId = nil
            }
            showMenu = false
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
                LocalScoreboardDisplayState(
                    gameID: appGameType.canonicalScoreboardIdentifier,
                    title: appGameType.displayName,
                    leftName: displayName(for: .left),
                    rightName: displayName(for: .right),
                    leftScore: "\(displayScore(for: .left))",
                    rightScore: "\(displayScore(for: .right))",
                    leftDetail: "\(displayFouls(for: .left)) 犯规 · \(displayTimeouts(for: .left)) 暂停",
                    rightDetail: "\(displayFouls(for: .right)) 犯规 · \(displayTimeouts(for: .right)) 暂停",
                    themeID: appearance.theme.rawValue,
                    fontID: typographyPreference.font.rawValue,
                    scoreMultiplier: typographyPreference.scoreMultiplier,
                    nameMultiplier: typographyPreference.nameMultiplier,
                    secondaryMultiplier: typographyPreference.secondaryMultiplier,
                    finished: store.state.finished,
                    revision: 0
                )
            },
            handleIntent: { intent in
                guard LocalScoreboardMutationPolicy.allowsMutation(
                    isEditing: isEditMode,
                    finished: store.state.finished,
                    scoringLocked: scoringLocked
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
        guard !scoringLocked, !isStartingNewMatch else { return }
        isStartingNewMatch = true
        let finishedStore = store
        finishedStore.stopClock()
        finishedStore.persistSnapshot { success in
            guard success else {
                isStartingNewMatch = false
                updateClockOwnership()
                return
            }
            let freshStore = finishedStore.makeFreshMatchStore()
            freshStore.persistSnapshot { freshSaved in
                isStartingNewMatch = false
                guard freshSaved else {
                    updateClockOwnership()
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
                updateClockOwnership()
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                if let watchSessionId {
                    let gameType: ScoreCore.GameType = freshStore.state.gameMode == .threeXThree
                        ? .threeBasketball
                        : .basketball
                    watchLinkService.prepareControllerForNewMatch(
                        sessionId: watchSessionId,
                        gameType: gameType,
                        snapshot: .basketball(freshStore.state),
                        participantNames: [freshStore.state.leftName, freshStore.state.rightName]
                    )
                }
            }
        }
    }
}

private struct BasketballEditTeamPanel: View {
    @Binding var name: String
    @Binding var score: Int
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

            VStack(spacing: 24) {
                TextField(
                    NSLocalizedString("setup_team_name", value: "队伍名称", comment: ""),
                    text: $name
                )
                .font(typography.font.swiftUIFont(
                    size: resolvedTypography.nameFontSize,
                    weight: .bold
                ))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
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
            }
            .foregroundStyle(.white)
            .offset(y: ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: panelSize.height))
        }
    }

    private func adjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
    let onScore: (Int) -> Void
    let onFoul: () -> Void
    let onRemoveFoul: () -> Void
    let onTimeout: () -> Void

    private let bonusYellow = Color(hex: "FACC15")
    private let additionalOuterPadding: CGFloat = 8

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

    var body: some View {
        ZStack {
            color

            HStack(spacing: 0) {
                if isLeftSide {
                    scoreButtons
                        .padding(.leading, outerSafeAreaInset + additionalOuterPadding)
                }

                Text("\(score)")
                    .font(typography.font.swiftUIFont(size: resolvedTypography.scoreFontSize))
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
                    Button(action: onTimeout) {
                        Text("暂停 \(timeouts)")
                            .font(typography.font.swiftUIFont(
                                size: max(12, resolvedTypography.secondaryFontSize * 0.34),
                                weight: .semibold
                            ))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .padding(isLeftSide ? .trailing : .leading, 12)
                    .padding(.bottom, 12)
                    if !isLeftSide { Spacer() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scoreButtons: some View {
        VStack(spacing: 10) {
            ForEach(points, id: \.self) { point in
                Button(action: { onScore(point) }) {
                    Text("+\(point)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var foulRow: some View {
        HStack(spacing: 8) {
            Text("犯规 \(fouls)")
                .font(typography.font.swiftUIFont(
                    size: max(12, resolvedTypography.secondaryFontSize * 0.4),
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
                        size: max(11, resolvedTypography.secondaryFontSize * 0.34),
                        weight: .bold
                    ))
                    .foregroundStyle(bonusYellow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFoul)
        .onLongPressGesture(minimumDuration: 0.35, perform: onRemoveFoul)
    }
}

private struct BasketballCenterPanel: View {
    let state: BasketballMatchState
    let typography: ScoreboardTypographyPreference
    let onToggleClock: () -> Void
    let onResetGameClock: () -> Void
    let onResetShotClock: (Int) -> Void
    let onAdvancePeriod: () -> Void
    let onEnterOvertime: () -> Void
    let onSelectPeriod: (Int) -> Void

    @State private var showPeriodPicker = false
    @State private var shotClockBlinkPhase = false

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
                    .frame(height: 40)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            } else {
                Text(periodTitle)
                    .font(self.typography.font.swiftUIFont(
                        size: max(16, typography.nameFontSize * 0.62),
                        weight: .bold
                    ))
                    .foregroundStyle(.white)
                    .frame(height: 40)
            }

            Button(action: onResetGameClock) {
                Text(clockText(state.gameTimeSeconds))
                    .font(typographyPreferenceFont(size: typography.scoreFontSize))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if state.canAdvancePeriod && !state.isOvertime {
                periodActionButton(title: "下一节", color: actionAccent, action: onAdvancePeriod)
            }
            if state.canAdvancePeriod && state.isOvertime {
                periodActionButton(title: "再加时", color: overtimePurple, action: onAdvancePeriod)
            }
            if shouldShowEnterOvertime {
                periodActionButton(title: "进入加时", color: overtimePurple, action: onEnterOvertime)
            }

            Button(action: onToggleClock) {
                Image(systemName: state.gameRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, showsPeriodActionButton ? 8 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func lowerZone(typography: ScoreboardTypographyResult) -> some View {
        VStack(spacing: 10) {
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

            HStack(spacing: 10) {
                ForEach(shotOptions, id: \.self) { seconds in
                    Button {
                        onResetShotClock(seconds)
                    } label: {
                        Text("\(seconds)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: shotOptions.count == 1 ? 72 : 52, height: 36)
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
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { showPeriodPicker = false }

                VStack(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(1...4, id: \.self) { period in
                            Button("Q\(period)") {
                                onSelectPeriod(period)
                                showPeriodPicker = false
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(state.currentPeriod == period && !state.isOvertime ? .white : .white.opacity(0.85))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(state.currentPeriod == period && !state.isOvertime ? actionAccent : Color.white.opacity(0.12))
                            )
                            .buttonStyle(.plain)
                        }
                    }

                    Button("OT") {
                        onEnterOvertime()
                        showPeriodPicker = false
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(state.isOvertime ? .white : .white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(state.isOvertime ? overtimePurple : Color.white.opacity(0.12))
                    )
                    .buttonStyle(.plain)
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
                .frame(width: 92, height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(color))
        }
        .buttonStyle(.plain)
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

    private var periodTitle: String {
        if state.isOvertime { return "OT" }
        return state.gameMode == .threeXThree ? "3x3" : "Q\(state.currentPeriod)"
    }

    private var shotOptions: [Int] {
        state.gameMode == .threeXThree ? [12] : [14, 24]
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
