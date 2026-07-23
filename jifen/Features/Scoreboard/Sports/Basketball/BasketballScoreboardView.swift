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

        if let initialRecordId,
           let sessionId = UUID(uuidString: initialRecordId),
           let restoredStore = BasketballSessionStore(restoring: sessionId) {
            _store = State(initialValue: restoredStore)
            _showGameOverDialog = State(initialValue: restoredStore.state.finished)
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
        }
        _watchSessionId = State(initialValue: initialSetup?.linkedWatchSessionId)
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
                HStack(spacing: 0) {
                    BasketballTeamPanel(
                        name: displayName(for: .left),
                        score: displayScore(for: .left),
                        fouls: displayFouls(for: .left),
                        timeouts: displayTimeouts(for: .left),
                        foulDisplayLimit: BasketballMatchEngine.foulDisplayLimit(store.state),
                        bonusThreshold: BasketballMatchEngine.bonusThreshold(store.state),
                        doubleBonusThreshold: BasketballMatchEngine.doubleBonusThreshold(store.state),
                        color: logicalSide(forScreen: .left) == .left ? Color(hex: "C62828") : Color(hex: "007AFF"),
                        isLeftSide: true,
                        scoreboardFont: appearance.font,
                        scoreMultiplier: scoreMultiplier,
                        panelHeight: proxy.size.height,
                        points: BasketballMatchEngine.scoringButtons(store.state),
                        onScore: { guard !scoringLocked else { return }; store.send(.addPoints(side: logicalSide(forScreen: .left), points: $0)) },
                        onFoul: { guard !scoringLocked else { return }; store.send(.addFoul(side: logicalSide(forScreen: .left))) },
                        onRemoveFoul: { guard !scoringLocked else { return }; store.send(.removeFoul(side: logicalSide(forScreen: .left))) },
                        onTimeout: { guard !scoringLocked else { return }; store.send(.useTimeout(side: logicalSide(forScreen: .left))) }
                    )
                    .frame(width: sideW)

                    BasketballCenterPanel(
                        state: store.state,
                        onToggleClock: { guard !scoringLocked else { return }; store.send(.setClockRunning(!store.state.gameRunning)) },
                        onResetGameClock: { guard !scoringLocked else { return }; store.send(.resetGameClock) },
                        onResetShotClock: { guard !scoringLocked else { return }; store.send(.resetShotClock(seconds: $0)) },
                        onAdvancePeriod: { guard !scoringLocked else { return }; store.send(.advanceToNextPeriod) },
                        onEnterOvertime: { guard !scoringLocked else { return }; store.send(.enterOvertime) },
                        onSelectPeriod: { guard !scoringLocked else { return }; store.send(.selectPeriod($0)) }
                    )
                    .frame(width: centerW)

                    BasketballTeamPanel(
                        name: displayName(for: .right),
                        score: displayScore(for: .right),
                        fouls: displayFouls(for: .right),
                        timeouts: displayTimeouts(for: .right),
                        foulDisplayLimit: BasketballMatchEngine.foulDisplayLimit(store.state),
                        bonusThreshold: BasketballMatchEngine.bonusThreshold(store.state),
                        doubleBonusThreshold: BasketballMatchEngine.doubleBonusThreshold(store.state),
                        color: logicalSide(forScreen: .right) == .left ? Color(hex: "C62828") : Color(hex: "007AFF"),
                        isLeftSide: false,
                        scoreboardFont: appearance.font,
                        scoreMultiplier: scoreMultiplier,
                        panelHeight: proxy.size.height,
                        points: BasketballMatchEngine.scoringButtons(store.state),
                        onScore: { guard !scoringLocked else { return }; store.send(.addPoints(side: logicalSide(forScreen: .right), points: $0)) },
                        onFoul: { guard !scoringLocked else { return }; store.send(.addFoul(side: logicalSide(forScreen: .right))) },
                        onRemoveFoul: { guard !scoringLocked else { return }; store.send(.removeFoul(side: logicalSide(forScreen: .right))) },
                        onTimeout: { guard !scoringLocked else { return }; store.send(.useTimeout(side: logicalSide(forScreen: .right))) }
                    )
                    .frame(width: sideW)
                }
                .background(Color.black)
            }

            if shouldShowChrome {
                chromeOverlay
            }

            if appearance.immersiveMode && !chromeVisible {
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
                    leftName: store.state.leftName,
                    rightName: store.state.rightName,
                    leftScore: store.state.leftScore,
                    rightScore: store.state.rightScore,
                    onNewGame: {
                        showGameOverDialog = false
                        store.send(.reset)
                        showToastMessage(NSLocalizedString("has_been_reset", value: "已重置", comment: ""))
                    },
                    onRecords: {
                        store.persistSnapshot()
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        shareFinishedMatch()
                    },
                    onExit: {
                        store.persistSnapshot()
                        back()
                    }
                )
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        .onAppear {
            onSetupConsumed?()
            store.startClock()
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
                watchLinkService.syncWatch(sessionId: watchSessionId, state: state)
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
            store.replaceDisplayedState(basketball)
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
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
        .scoreboardDisplaySettingsOverlay(isPresented: $showDisplaySettings, gameType: appGameType)
    }

    private var scoringLocked: Bool {
        watchSessionId != nil && watchLinkService.isFollower
    }

    private var basketballMenuItems: [ScoreboardMenuItem] {
        var extras: [ScoreboardMenuItem] = []
        if AppFeatureFlags.watchLinkEntryEnabled, watchSessionId != nil {
            if watchLinkService.isFollower {
                extras.append(
                    ScoreboardMenuItem(
                        title: NSLocalizedString("linked_score_takeover", value: "接管计分", comment: ""),
                        action: "takeover",
                        group: .sync,
                        icon: "applewatch"
                    )
                )
            }
            extras.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("linked_score_end", value: "结束联动", comment: ""),
                    action: "endLink",
                    group: .sync,
                    icon: "xmark.circle"
                )
            )
        }
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: true,
            showScreenshot: false,
            resetConfirming: menuConfirm.resetConfirming,
            exchangeConfirming: menuConfirm.exchangeConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            extraItems: extras
        )
    }

    private var chromeOverlay: some View {
        VStack {
            Spacer()
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
                .background(Circle().fill(Color.black.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .modifier(ScoreboardBackButtonAccessibility(isBack: systemName == "chevron.left"))
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

    private var scoreMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: appGameType)[ScoreboardFontMetric.score.rawValue] ?? 1)
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || showDisplaySettings || showMenu
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !showDisplaySettings, !showMenu else { return }
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
        case "takeover":
            if let id = watchSessionId {
                Task {
                    try? await watchLinkService.takeover(sessionId: id)
                    watchLinkService.syncWatch(sessionId: id, state: store.state)
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
                    fontID: appearance.font.rawValue,
                    finished: store.state.finished,
                    revision: 0
                )
            },
            handleIntent: { intent in
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
        if let onNavigationBack {
            onNavigationBack()
        } else {
            dismiss()
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
    let scoreboardFont: ScoreboardFont
    let scoreMultiplier: CGFloat
    let panelHeight: CGFloat
    let points: [Int]
    let onScore: (Int) -> Void
    let onFoul: () -> Void
    let onRemoveFoul: () -> Void
    let onTimeout: () -> Void

    private let bonusYellow = Color(hex: "FACC15")

    private var scoreSize: CGFloat {
        ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: panelHeight) * scoreMultiplier
    }

    private var foulBonusLabel: String? {
        if doubleBonusThreshold > 0, fouls >= doubleBonusThreshold { return "DBL" }
        if fouls >= bonusThreshold { return "BONUS" }
        return nil
    }

    var body: some View {
        ZStack {
            color

            Text("\(score)")
                .font(scoreboardFont.swiftUIFont(size: scoreSize))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, 58)

            VStack {
                Text(name)
                    .font(.system(size: ScoreboardLayoutMetrics.defaultTeamNameFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: panelHeight))
                    .padding(.horizontal, 8)
                Spacer()
            }

            HStack {
                if isLeftSide {
                    scoreButtons
                        .padding(.leading, 32)
                    Spacer()
                } else {
                    Spacer()
                    scoreButtons
                        .padding(.trailing, 32)
                }
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
                            .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 14, weight: .semibold))
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
                    .font(.system(size: 12, weight: .bold))
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
    let onToggleClock: () -> Void
    let onResetGameClock: () -> Void
    let onResetShotClock: (Int) -> Void
    let onAdvancePeriod: () -> Void
    let onEnterOvertime: () -> Void
    let onSelectPeriod: (Int) -> Void

    @State private var showPeriodPicker = false
    @State private var shotClockBlinkPhase = false

    private let centerBG = Color(hex: "111827")
    private let actionBlue = Color(hex: "2563EB")
    private let overtimePurple = Color(hex: "7C3AED")
    private let shotYellow = Color(hex: "FACC15")
    private let shotExpired = Color(hex: "EF4444")

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                upperZone
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(2)

                lowerZone
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
            }
            .frame(maxHeight: .infinity)
            .background(centerBG)

            if showPeriodPicker {
                periodPickerOverlay
            }
        }
    }

    private var upperZone: some View {
        VStack(spacing: 10) {
            if state.gameMode == .fiveVFive {
                Button {
                    showPeriodPicker.toggle()
                } label: {
                    Text(periodTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            } else {
                Text(periodTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Button(action: onResetGameClock) {
                Text(clockText(state.gameTimeSeconds))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button(action: onToggleClock) {
                Image(systemName: state.gameRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

            if state.canAdvancePeriod && !state.isOvertime {
                periodActionButton(title: "下一节", color: actionBlue, action: onAdvancePeriod)
            }
            if state.canAdvancePeriod && state.isOvertime {
                periodActionButton(title: "再加时", color: overtimePurple, action: onAdvancePeriod)
            }
            if shouldShowEnterOvertime {
                periodActionButton(title: "进入加时", color: overtimePurple, action: onEnterOvertime)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var lowerZone: some View {
        VStack(spacing: 8) {
            Text("\(state.shotTimeSeconds)″")
                .font(.system(size: 30, weight: .bold, design: .monospaced))
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

            HStack(spacing: 6) {
                ForEach(shotOptions, id: \.self) { seconds in
                    Button("\(seconds)") { onResetShotClock(seconds) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var periodPickerOverlay: some View {
        ZStack {
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
                                .fill(state.currentPeriod == period && !state.isOvertime ? actionBlue : Color.white.opacity(0.12))
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
            .background(RoundedRectangle(cornerRadius: 12).fill(centerBG))
            .padding(.horizontal, 8)
        }
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
