import LinkCore
import OSLog
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI
import UIKit

private var linkedScoreboardNewGameLabel: String {
    NSLocalizedString(
        "game_over_new_game_on_watch",
        value: "再来一场\n（请在手表端操作）",
        comment: ""
    )
}

/// Two-side 50/50 scaffold aligned with HOS specialized boards (eight-ball / shengji / guandan).
struct SpecializedScoreboardScaffold<Center: View>: View {
    let gameType: GameType
    let leftName: String
    let rightName: String
    let leftScore: String
    let rightScore: String
    let leftDetail: String?
    let rightDetail: String?
    let finished: Bool
    let onLeftTap: () -> Void
    let onRightTap: () -> Void
    let onUndo: () -> Bool
    let onReset: () -> Void
    let onExchange: (() -> Void)?
    let onBack: () -> Void
    var showEndGame: Bool = false
    var onEndGame: (() -> Void)? = nil
    var onEditCommit: ((String, String, String, String) -> Void)? = nil
    /// Defaults to the shared game policy so a new specialized scoreboard
    /// cannot silently read the wrong common-name collection.
    var nameType: NameType? = nil
    var editingEnabled: Bool = true
    var scoringEnabled: Bool = true
    /// Optional step-based editor used by rank/score boards that mirror the
    /// badminton singles edit layout instead of accepting raw score text.
    var onEditAdjust: ((Bool, Int) -> Void)? = nil
    var extraMenuItems: [ScoreboardMenuItem] = []
    var onMenuAction: ((String) -> Void)? = nil
    /// Optional overlay between the halves (e.g. serve triangle). Drawn above panels.
    var seamOverlay: (() -> AnyView)? = nil
    /// Optional controls rendered directly below each side's main score.
    var panelAccessory: ((Bool) -> AnyView)? = nil
    /// Optional floating bottom dock (e.g. snooker balls).
    var bottomBar: (() -> AnyView)? = nil
    /// Optional top-center pill.
    var topCenter: ((ScoreboardTypographyPreference, CGSize) -> AnyView)? = nil
    var onEditModeChange: ((Bool) -> Void)? = nil
    var onTypographyChange: ((ScoreboardTypographyPreference) -> Void)? = nil
    let center: (ScoreboardTypographyPreference, CGSize) -> Center

    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession = ScoreboardTypographySession(
        styleID: ScoreboardStyleID(rawValue: "unconfigured")
    )
    @State private var preferences = PreferencesManager.shared
    @State private var showDisplaySettings = false
    @State private var showMenu = false
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var isEditMode = false
    @State private var editLeftName = ""
    @State private var editRightName = ""
    @State private var editLeftScore = ""
    @State private var editRightScore = ""
    @State private var exitConfirmDeadline: Date?
    @State private var showToast = false
    @State private var toastMessage = ""

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || showDisplaySettings || showMenu
    }

    private var resolvedNameType: NameType {
        nameType ?? ScoreboardCommonNamePolicy.nameType(for: gameType)
    }

    var body: some View {
        GeometryReader { proxy in
            let halfH = proxy.size.height
            ZStack {
                appearance.theme.palette.background.ignoresSafeArea()

                HStack(spacing: 0) {
                    scorePanel(
                        isLeft: true,
                        name: leftName,
                        score: leftScore,
                        detail: leftDetail,
                        color: appearance.theme.palette.left,
                        panelSize: CGSize(width: proxy.size.width / 2, height: halfH),
                        accessory: panelAccessory?(true),
                        action: onLeftTap
                    )
                    .frame(width: proxy.size.width / 2, height: halfH)
                    .accessibilityIdentifier("scoreboard_left_panel")

                    scorePanel(
                        isLeft: false,
                        name: rightName,
                        score: rightScore,
                        detail: rightDetail,
                        color: appearance.theme.palette.right,
                        panelSize: CGSize(width: proxy.size.width / 2, height: halfH),
                        accessory: panelAccessory?(false),
                        action: onRightTap
                    )
                    .frame(width: proxy.size.width / 2, height: halfH)
                    .accessibilityIdentifier("scoreboard_right_panel")
                }

                if !isEditMode, let seamOverlay {
                    seamOverlay()
                }

                if !isEditMode, let topCenter {
                    VStack {
                        topCenter(typographySession.effectivePreference, proxy.size)
                            .padding(.top, ScoreboardConstants.buttonPadding)
                        Spacer()
                    }
                }

                // Compact center hints (target text etc.) sit mid-bottom above optional bottom bar.
                if !isEditMode {
                    VStack {
                        Spacer()
                        center(typographySession.effectivePreference, proxy.size)
                            .padding(.bottom, bottomBar == nil ? 72 : 90)
                    }
                    .allowsHitTesting(false)
                }

                if !isEditMode, let bottomBar {
                    VStack {
                        Spacer()
                        bottomBar()
                    }
                    .zIndex(20)
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
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                guard !isEditMode else { return }
                showMenu = true
                revealImmersiveChrome()
            })
            .simultaneousGesture(DragGesture(minimumDistance: 36).onEnded { value in
                guard scoringEnabled,
                      !isEditMode,
                      value.translation.width < -60,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                if onUndo() {
                    showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: ""))
                } else {
                    showToastMessage(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
                }
            })
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.primary)
        .lockOrientation(.landscape)
        .onAppear {
            typographySession.switchStyleID(ScoreboardStyleID(gameType: gameType))
            onTypographyChange?(typographySession.effectivePreference)
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: showMenu) { _, isOpen in
            if !isOpen { menuConfirm.clear() }
            updateImmersiveForBlocking()
        }
        .onChange(of: showDisplaySettings) { _, presented in
            updateImmersiveForBlocking()
            if !presented {
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            }
        }
        .onChange(of: typographySession.effectivePreference) { _, preference in
            onTypographyChange?(preference)
        }
        .onDisappear {
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
        }
        .overlay {
            MenuDialog(
                isVisible: showMenu,
                onClose: {
                    menuConfirm.clear()
                    showMenu = false
                },
                onMenuItemClick: { action in
                    menuConfirm.prepare(forMenuAction: action)
                    switch action {
                    case "undo":
                        if onUndo() {
                            showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: "Undo done"))
                        } else {
                            showToastMessage(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
                        }
                    case "reset":
                        if menuConfirm.armOrConfirm(.reset) {
                            onReset()
                            showToastMessage(NSLocalizedString("has_been_reset", value: "已重置", comment: ""))
                            showMenu = false
                        } else {
                            showToastMessage(ScoreboardMenuConfirmAction.reset.localizedToast)
                        }
                    case "exchangeSide":
                        if menuConfirm.armOrConfirm(.exchangeSide) {
                            onExchange?()
                        } else {
                            showToastMessage(ScoreboardMenuConfirmAction.exchangeSide.localizedToast)
                        }
                    case "endGame":
                        if menuConfirm.armOrConfirm(.finish) {
                            onEndGame?()
                            showMenu = false
                        } else {
                            showToastMessage(ScoreboardMenuConfirmAction.finish.localizedToast)
                        }
                    case "displaySettings": showDisplaySettings = true; showMenu = false
                    default: onMenuAction?(action)
                    }
                },
                showEndGame: showEndGame,
                showExchangeSide: onExchange != nil,
                items: ScoreboardMenuItemBuilder.defaultItems(
                    showEndGame: showEndGame,
                    showExchangeSide: onExchange != nil,
                    showWhistle: true,
                    showScreenshot: true,
                    resetConfirming: menuConfirm.resetConfirming,
                    exchangeConfirming: menuConfirm.exchangeConfirming,
                    finishConfirming: menuConfirm.finishConfirming,
                    scoringEnabled: scoringEnabled,
                    extraItems: extraMenuItems
                ),
                analyticsGameType: gameType
            )
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: leftDetail == nil && rightDetail == nil
                ? [.name, .score]
                : ScoreboardTypographyProfile.specialized.adjustableMetrics
        )
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

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }

    private var chromeOverlay: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    if onEditCommit != nil, editingEnabled {
                        chromeButton(isEditMode ? "checkmark" : "pencil") { toggleEditMode() }
                    }
                }
                Spacer()
            }
            .padding(ScoreboardConstants.buttonPadding)

            if !isEditMode {
                VStack {
                    Spacer()
                    HStack {
                        chromeButton("chevron.left", action: requestBack)
                        Spacer()
                        chromeButton("line.3.horizontal") { showMenu = true }
                    }
                }
                .padding(ScoreboardConstants.buttonPadding)
            }
        }
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
        onBack()
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }

    private func chromeButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        let background = systemName == "checkmark" ? Theme.primary : Color.black.opacity(0.25)
        return Button(action: {
            action()
            revealImmersiveChrome()
        }) {
            Image(systemName: systemName)
                .font(.system(size: ScoreboardConstants.buttonIconSize))
                .foregroundColor(.white)
                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                .background(Circle().fill(background))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier(for: systemName))
        .modifier(ScoreboardBackButtonAccessibility(isBack: systemName == "chevron.left"))
    }

    private func accessibilityIdentifier(for systemName: String) -> String {
        switch systemName {
        case "chevron.left":
            return ScoreboardConstants.backButtonAccessibilityID
        case "line.3.horizontal":
            return "scoreboard_menu_button"
        case "pencil", "checkmark":
            return "scoreboard_edit_button"
        default:
            return "scoreboard_chrome_\(systemName.replacingOccurrences(of: ".", with: "_"))"
        }
    }

    private func scorePanel(
        isLeft: Bool,
        name: String,
        score: String,
        detail: String?,
        color: Color,
        panelSize: CGSize,
        accessory: AnyView?,
        action: @escaping () -> Void
    ) -> some View {
        let typography = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .specialized,
                containerSize: panelSize,
                nameText: name,
                scoreText: score,
                secondaryText: detail ?? "",
                preference: typographySession.effectivePreference,
                horizontalPadding: 20,
                reservedHeight: accessory == nil ? 0 : 44,
                scoreBaseScale: score.count >= 3 ? 0.72 : 1,
                isLargeScreen: Theme.usesPadLayout
            )
        )
        let mainSize = typography.scoreFontSize
        let nameSize = typography.nameFontSize
        let topPad = ScoreboardLayoutMetrics.nameTopPadding(panelHeight: panelSize.height)
        let setSize = typography.secondaryFontSize
        let mainToDetailSpacing = ScoreboardLayoutMetrics.mainToSetSpacing(
            halfViewportHeight: panelSize.height
        )
        let editOffset = isEditMode
            ? ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: panelSize.height)
            : 0

        return ZStack {
            color

            if isEditMode {
                VStack(spacing: typography.nameToScoreSpacing) {
                    if let onEditAdjust {
                        HStack(spacing: 16) {
                            editCircleButton(systemName: "minus") { onEditAdjust(isLeft, -1) }
                            Text(score)
                                .font(typographySession.effectivePreference.font.swiftUIFont(
                                    size: ScoreboardLayoutMetrics.editMainScoreFontSize(regularSize: mainSize)
                                ))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            editCircleButton(systemName: "plus") { onEditAdjust(isLeft, 1) }
                        }
                    } else {
                        TextField(
                            "0",
                            text: isLeft ? $editLeftScore : $editRightScore
                        )
                        .keyboardType(.numbersAndPunctuation)
                        .font(typographySession.effectivePreference.font.swiftUIFont(
                            size: ScoreboardLayoutMetrics.editMainScoreFontSize(regularSize: mainSize)
                        ))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: editOffset)

                VStack {
                    ScoreboardNameEditorField(
                        placeholder: resolvedNameType == .player
                            ? NSLocalizedString("setup_player_name", value: "选手名称", comment: "")
                            : NSLocalizedString("setup_team_name", value: "队伍名称", comment: ""),
                        text: isLeft ? $editLeftName : $editRightName,
                        nameType: resolvedNameType,
                        scoreboardFont: typographySession.effectivePreference.font
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, topPad)
                    .offset(y: editOffset)
                    Spacer()
                }
            } else {
                // Keep the complete label/score/detail cluster centered. This
                // matches the rally and standard templates and prevents a
                // top-pinned name from making the main score look too high.
                VStack(spacing: 0) {
                    Text(name)
                        .font(typographySession.effectivePreference.font.swiftUIFont(
                            size: nameSize,
                            weight: .bold
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 8)

                    Spacer().frame(height: typography.nameToScoreSpacing)

                    Text(score)
                        .font(typographySession.effectivePreference.font.swiftUIFont(size: mainSize))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)

                    if let accessory {
                        accessory
                            .padding(.top, 8)
                    }

                    if let detail {
                        Spacer().frame(height: mainToDetailSpacing)
                        Text(detail)
                            .font(typographySession.effectivePreference.font.swiftUIFont(size: setSize))
                            .foregroundStyle(appearance.theme.palette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(appearance.theme.palette.foreground)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !finished else { return }
            action()
        }
    }

    private func editCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(appearance.theme.palette.foreground.opacity(0.75))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func toggleEditMode() {
        if isEditMode {
            onEditCommit?(
                editLeftName.trimmingCharacters(in: .whitespacesAndNewlines),
                editRightName.trimmingCharacters(in: .whitespacesAndNewlines),
                editLeftScore.trimmingCharacters(in: .whitespacesAndNewlines),
                editRightScore.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            isEditMode = false
            onEditModeChange?(false)
        } else {
            editLeftName = leftName
            editRightName = rightName
            editLeftScore = leftScore
            editRightScore = rightScore
            isEditMode = true
            onEditModeChange?(true)
        }
    }
}

/// Compact per-side action used by the card scoreboards. Dimensions and
/// translucent treatment mirror the HarmonyOS auxiliary buttons.
@ViewBuilder
func scoreboardCardActionButton(
    _ title: String,
    width: CGFloat? = nil,
    action: @escaping () -> Void
) -> some View {
    let size: CGFloat = Theme.usesPadLayout ? 64 : 56
    Button(action: action) {
        Text(title)
            .font(.system(size: Theme.usesPadLayout ? 20 : 16, weight: .bold))
            .foregroundStyle(ScoreboardAppearanceSnapshot.current().theme.palette.foreground)
            .frame(width: width ?? size, height: size)
            .background(Capsule().fill(ScoreboardTheme.auxiliaryButtonBackgroundSubtle))
    }
    .buttonStyle(.plain)
}


struct EightBallScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    let initialSetup: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?

    @State private var sessionStore: SpecializedBilliardsSessionStore<EightBallReducer>
    @State private var actionLog: [String] = []
    @State private var detailedActions: [DetailedScoreAction] = []
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var leftName: String
    @State private var rightName: String
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var showPersistenceError = false
    @State private var watchSessionId: UUID?
    @State private var manualFinishRequested = false
    @State private var isStartingNewMatch = false
    @State private var scoreboardEditing = false
    @State private var overflowToastMessage: String?
    @State private var typographyPreference = PreferencesManager.shared.scoreboardTypography(
        for: ScoreboardStyleID(gameType: .eightBall)
    )

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let red = localizedSideRedName()
        let blue = localizedSideBlueName()
        var left = initialSetup?.team1Name.nonEmpty ?? red
        var right = initialSetup?.team2Name.nonEmpty ?? blue
        let target: Int
        let handicap: Int
        let beneficiary: MatchSide?
        if case let .some(.eightBall(targetRacks, handicapRacks, projectedBeneficiary)) = initialSetup?.billiardsConfiguration(for: .eightBall) {
            target = targetRacks
            handicap = handicapRacks
            beneficiary = projectedBeneficiary
        } else {
            target = 9
            handicap = 0
            beneficiary = nil
        }
        var initial = EightBallState.initial(
            targetPoints: target,
            handicapRacks: handicap,
            handicapBeneficiary: beneficiary
        )
        var start = Date()
        var id = UUID().uuidString
        var actions = 0
        var restoredHistory: [EightBallState] = []
        let restoredActionLog: [String] = []
        let restoredDetailedActions: [DetailedScoreAction] = []
        var showFinished = false
        var resumeBundle: SpecializedBilliardsSessionStore<EightBallReducer>.ResumeBundle?

        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let bundle = SpecializedBilliardsSessionStore<EightBallReducer>.decodeResumeBundle(sessionId: sessionId) {
            resumeBundle = bundle
            initial = bundle.currentSession.state
            start = bundle.currentSession.metadata.extras["startedAtEpochMilliseconds"]
                .flatMap(Int64.init)
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? start
            id = bundle.currentSession.metadata.extras["recordID"] ?? initialResumeSessionId
            actions = bundle.timeline.count
            restoredHistory = bundle.undoFrames.map(\.session.state)
            if bundle.currentSession.participants.count >= 2 {
                left = bundle.currentSession.participants[0].name
                right = bundle.currentSession.participants[1].name
            }
            showFinished = initial.finished
        }

        let store = resumeBundle.map {
            SpecializedBilliardsSessionStore(resumeBundle: $0, reducer: EightBallReducer())
        } ?? SpecializedBilliardsSessionStore(
            gameType: .eightBall,
            state: initial,
            reducer: EightBallReducer(),
            participants: [
                .init(id: TeamID.team0.rawValue, name: left, role: "team"),
                .init(id: TeamID.team1.rawValue, name: right, role: "team")
            ],
            startedAt: start,
            recordID: id,
            restoredUndoStates: restoredHistory
        )
        _sessionStore = State(initialValue: store)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _actionLog = State(initialValue: restoredActionLog)
        _detailedActions = State(initialValue: restoredDetailedActions)
        _leftName = State(initialValue: left)
        _rightName = State(initialValue: right)
        _showGameOverDialog = State(initialValue: showFinished)
        _watchSessionId = State(initialValue: initialSetup?.linkedWatchSessionId)
    }

    private var state: EightBallState { sessionStore.state }

    private var scoringLocked: Bool {
        watchSessionId != nil
            && (watchLinkService.isFollower || watchLinkService.isAuthorityTransferPending)
    }

    var body: some View {
        eightBallContent
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            finishedRecordDetailPage
        }
        .onAppear {
            onSetupConsumed?()
            registerSync()
            if let watchSessionId,
               let update = watchLinkService.attachPage(sessionId: watchSessionId),
               let remote = update.snapshot.eightBallState {
                detailedActions = update.detailedActions
                applyAuthoritativeEightBall(remote)
            }
        }
        .onChange(of: state.finished) { _, finished in
            if finished {
                showGameOverDialog = true
                notifyLinkedFinishIfNeeded()
            }
        }
        .onChange(of: state) { _, newState in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            publishWatchIfNeeded(newState)
        }
        .onChange(of: sessionStore.persistenceFailureSignal) { _, signal in
            if signal > 0 { showPersistenceError = true }
        }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId, let update, update.sessionId == watchSessionId,
                  let remote = update.snapshot.eightBallState else { return }
            detailedActions = update.detailedActions
            applyAuthoritativeEightBall(remote)
        }
        .onChange(of: watchLinkService.pendingTakeoverApplication) { _, pending in
            guard let watchSessionId, let pending, pending.sessionId == watchSessionId,
                  let remote = pending.snapshot.eightBallState else { return }
            detailedActions = pending.detailedActions
            applyAuthoritativeEightBall(remote)
            watchLinkService.completePhoneTakeover(messageId: pending.messageId)
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            let skipSave = watchSessionId != nil
                && (watchLinkService.isFollower || watchLinkService.finishedRecordId != nil)
            if let watchSessionId { watchLinkService.detachPage(sessionId: watchSessionId) }
            if !skipSave { saveRecord() }
        }
        .alert(
            NSLocalizedString("linked_score_watch_reclaim_title", value: "手表请求重新接管", comment: ""),
            isPresented: reclaimAlertPresented
        ) {
            Button(NSLocalizedString("linked_score_accept", value: "同意", comment: "")) {
                watchLinkService.resolveReclaimRequest(
                    accepted: true,
                    snapshot: .eightBall(state),
                    detailedActions: detailedActions
                )
            }
            Button(NSLocalizedString("linked_score_reject", value: "拒绝", comment: ""), role: .cancel) {
                rejectWatchReclaim()
            }
        } message: {
            Text(NSLocalizedString("linked_score_watch_reclaim_message", value: "是否允许手表在 5 秒内重新接管计分？", comment: ""))
        }
        .alert(
            NSLocalizedString("save_failed", value: "保存失败", comment: ""),
            isPresented: $showPersistenceError
        ) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
        }
    }

    private var eightBallContent: some View {
        ZStack {
            eightBallScaffold

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: finishedWinnerName,
                    gameType: .eightBall,
                    leftName: leftName,
                    rightName: rightName,
                    leftScore: state.leftPoints,
                    rightScore: state.rightPoints,
                    newGameLabel: scoringLocked ? linkedScoreboardNewGameLabel : nil,
                    newGameDisabled: scoringLocked || isStartingNewMatch,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        if !scoringLocked, !saveRecord() { return }
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(text: "\(leftName) \(state.leftPoints) - \(state.rightPoints) \(rightName)")
                    },
                    onExit: exit
                )
            }

            if let overflowToastMessage {
                VStack {
                    Spacer()
                    ToastView(message: overflowToastMessage)
                        .padding(.bottom, 72)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var finishedRecordDetailPage: some View {
        NavigationStack {
            ScoreboardRecordDetailPage(recordId: recordID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalCloseButton { showFinishedRecordDetail = false }
                    }
                }
        }
    }

    private var eightBallScaffold: some View {
        SpecializedScoreboardScaffold(
            gameType: .eightBall,
            leftName: leftName,
            rightName: rightName,
            leftScore: "\(logical(.left))",
            rightScore: "\(logical(.right))",
            leftDetail: nil,
            rightDetail: nil,
            finished: state.finished,
            onLeftTap: { guard !scoringLocked else { return }; send(.addRack(screenSide(.left))) },
            onRightTap: { guard !scoringLocked else { return }; send(.addRack(screenSide(.right))) },
            onUndo: { scoringLocked ? false : undo() },
            onReset: { guard !scoringLocked else { return }; send(.reset) },
            onExchange: { guard !scoringLocked else { return }; send(.exchangeSides) },
            onBack: exit,
            showEndGame: true,
            onEndGame: { guard !scoringLocked else { return }; markFinished() },
            onEditCommit: { left, right, leftScore, rightScore in
                guard !scoringLocked else { return }
                applyEditNames(left: left, right: right)
            },
            nameType: ScoreboardCommonNamePolicy.nameType(for: .eightBall),
            editingEnabled: !scoringLocked,
            scoringEnabled: !scoringLocked,
            onEditAdjust: { isLeft, delta in
                guard !scoringLocked else { return }
                adjustScore(onScreen: isLeft ? .left : .right, delta: delta)
            },
            extraMenuItems: WatchLinkMenuSupport.extraItems(
                entryEnabled: AppFeatureFlags.watchLinkEntryEnabled,
                sessionId: watchSessionId,
                isFollower: watchLinkService.isFollower,
                watchBackgrounded: watchLinkService.watchBackgrounded
            ),
            onMenuAction: handleWatchMenu,
            panelAccessory: { isLeft in
                AnyView(
                    Group {
                        if state.handicapRacks > 0, state.handicapBeneficiary == screenSide(isLeft ? .left : .right) {
                            Text("+\(state.handicapRacks)")
                                .font(typographyPreference.font.swiftUIFont(
                                    size: 28,
                                    weight: .bold
                                ))
                                .foregroundStyle(ScoreboardAppearanceSnapshot.current().theme.palette.foreground.opacity(0.6))
                                .accessibilityIdentifier(isLeft ? "eight_ball_left_handicap" : "eight_ball_right_handicap")
                        }
                    }
                )
            },
            topCenter: { preference, containerSize in
                AnyView(eightBallTargetPill(preference: preference, containerSize: containerSize))
            },
            onEditModeChange: { scoreboardEditing = $0 },
            onTypographyChange: { preference in
                typographyPreference = preference
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            }
        ) { _, _ in
            EmptyView()
        }
    }

    private func handleWatchMenu(_ action: String) {
        switch action {
        case "resync":
            watchLinkService.requestScoreResync()
        case "takeover":
            if let id = watchSessionId {
                Task {
                    do {
                        try await watchLinkService.takeover(sessionId: id)
                        publishWatchIfNeeded(state)
                    } catch {
                        showToastMessage(error.localizedDescription)
                    }
                }
            }
        case "forceTakeover":
            if let id = watchSessionId {
                watchLinkService.requestForceTakeoverConfirmation(id)
            }
        case "endLink":
            if let id = watchSessionId {
                watchLinkService.leaveSession(id)
                watchSessionId = nil
            }
        default:
            break
        }
    }

    private func showToastMessage(_ message: String) {
        overflowToastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if overflowToastMessage == message {
                overflowToastMessage = nil
            }
        }
    }

    private func publishWatchIfNeeded(_ state: EightBallState) {
        guard let watchSessionId, watchLinkService.isController else { return }
        watchLinkService.syncWatch(
            sessionId: watchSessionId,
            gameType: .eightBall,
            snapshot: .eightBall(state),
            detailedActions: detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private var finishedWinnerName: String {
        if state.leftPoints > state.rightPoints { return leftName }
        if state.rightPoints > state.leftPoints { return rightName }
        return ""
    }

    private func eightBallTargetPill(
        preference: ScoreboardTypographyPreference,
        containerSize: CGSize
    ) -> some View {
        let fontSize = specializedSecondarySize(
            text: "\(state.targetPoints)",
            preference: preference,
            containerSize: containerSize,
            baseScale: 0.32
        )
        return HStack(spacing: 8) {
            Text("\(state.targetPoints)")
                .accessibilityIdentifier("eight_ball_target")
        }
            .font(preference.font.swiftUIFont(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(minWidth: 132, minHeight: max(34, fontSize * 1.6))
            .background(Capsule().fill(Color.black.opacity(0.4)))
    }

    private func specializedSecondarySize(
        text: String,
        preference: ScoreboardTypographyPreference,
        containerSize: CGSize,
        baseScale: CGFloat
    ) -> CGFloat {
        ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .specialized,
                containerSize: CGSize(
                    width: max(132, min(320, containerSize.width * 0.32)),
                    height: containerSize.height
                ),
                nameText: "",
                scoreText: "",
                secondaryText: text,
                preference: preference,
                horizontalPadding: 12,
                secondaryBaseScale: baseScale,
                isLargeScreen: Theme.usesPadLayout
            )
        ).secondaryFontSize
    }

    private func logical(_ screen: MatchSide) -> Int {
        let side = screenSide(screen)
        return side == .left ? state.leftPoints : state.rightPoints
    }
    private func screenSide(_ screen: MatchSide) -> MatchSide {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped).engineSide(onScreen: screen)
    }
    private func send(_ intent: EightBallIntent) {
        guard !scoringLocked else { return }
        sessionStore.send(intent) { _, next, _ in
            actionCount += 1
            actionLog.append(recordSnapshot(code: String(describing: intent), scores: [next.leftPoints, next.rightPoints]))
            appendEightBallAction(intent)
            if next.finished {
                if case .finishMatch = intent {} else { manualFinishRequested = false }
                showGameOverDialog = true
            }
        }
    }
    private func markFinished() {
        guard !scoringLocked, !state.finished else { return }
        manualFinishRequested = true
        send(.finishMatch)
    }
    private func applyEditNames(left: String, right: String) {
        guard !scoringLocked else { return }
        if !left.isEmpty { leftName = left }
        if !right.isEmpty { rightName = right }
        sessionStore.updateParticipants([
            .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
        ])
        actionCount += 1
        actionLog.append(recordSnapshot(code: "edit_names", scores: [state.leftPoints, state.rightPoints]))
        detailedActions.append(DetailedScoreAction(
            type: .stateChanged,
            epochMilliseconds: nowMilliseconds(),
            scores: [state.leftPoints, state.rightPoints],
            operationCode: "eight_ball_edit_names"
        ))
    }

    private func adjustScore(onScreen screen: MatchSide, delta: Int) {
        let side = screenSide(screen)
        guard state.canAdjustRacks(side: side, delta: delta) else {
            if delta > 0 {
                showOverflowToast(NSLocalizedString("scoreboard_set_score_overflow", value: "局分超限", comment: ""))
            }
            return
        }
        let left = state.leftPoints + (side == .left ? delta : 0)
        let right = state.rightPoints + (side == .right ? delta : 0)
        send(.adminAdjust(left: left, right: right))
        showGameOverDialog = false
    }

    private func showOverflowToast(_ message: String) {
        overflowToastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if overflowToastMessage == message { overflowToastMessage = nil }
        }
    }
    private func undo() -> Bool {
        guard !scoringLocked else { return false }
        return sessionStore.undo { success, restored in
            guard success else { return }
            actionCount = max(0, actionCount - 1)
            actionLog.append(recordSnapshot(code: "undo", scores: [restored.leftPoints, restored.rightPoints]))
            detailedActions.append(DetailedScoreAction(
                type: .undo,
                epochMilliseconds: nowMilliseconds(),
                scores: [restored.leftPoints, restored.rightPoints],
                operationCode: "undo"
            ))
            showGameOverDialog = restored.finished
        }
    }

    private func appendEightBallAction(_ intent: EightBallIntent) {
        let type: DetailedScoreActionType
        let team: RecordTeam?
        let code: String
        switch intent {
        case .addRack(let side):
            type = .scoreChanged
            team = side == .left ? .team1 : .team2
            code = "eight_ball_rack"
        case .applyPot(let side, let ball):
            type = .scoreChanged
            team = side == .left ? .team1 : .team2
            code = "eight_ball_pot_\(ball)"
        case .adminAdjust:
            type = .stateChanged; team = nil; code = "eight_ball_edit"
        case .exchangeSides:
            type = .sideChanged; team = nil; code = "exchange_side"
        case .reset:
            type = .reset; team = nil; code = "reset"
        case .finishMatch:
            type = .matchFinished; team = nil; code = "finish"
        }
        detailedActions.append(DetailedScoreAction(
            type: type,
            epochMilliseconds: nowMilliseconds(),
            team: team,
            scores: [state.leftPoints, state.rightPoints],
            operationCode: code
        ))
    }
    private func exit() {
        sessionStore.flush {
            guard saveRecord() else { return }
            onNavigationBack?()
            dismiss()
        }
    }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: scoreboardEditing,
                finished: state.finished,
                scoringLocked: scoringLocked
            ) else { return }
            switch intent {
            case .addLeft: send(.addRack(screenSide(.left)))
            case .addRight: send(.addRack(screenSide(.right)))
            case .subtractLeft, .subtractRight, .undo: _ = undo()
            case .exchangeSides: send(.exchangeSides)
            case .requestSnapshot: break
            }
        }
    }

    private var reclaimAlertPresented: Binding<Bool> {
        Binding(
            get: { watchLinkService.pendingReclaimRequest != nil },
            set: { presented in
                if !presented, watchLinkService.pendingReclaimRequest != nil {
                    rejectWatchReclaim()
                }
            }
        )
    }

    private func rejectWatchReclaim() {
        watchLinkService.resolveReclaimRequest(accepted: false, snapshot: nil, detailedActions: [])
    }

    private func applyAuthoritativeEightBall(_ remote: EightBallState) {
        sessionStore.rebase(to: remote) { applied in
            showGameOverDialog = applied.finished
            manualFinishRequested = false
        }
    }

    private func notifyLinkedFinishIfNeeded() {
        guard let watchSessionId, watchLinkService.isController else { return }
        let winner: MatchSide? = state.leftPoints == state.rightPoints
            ? nil
            : (state.leftPoints > state.rightPoints ? .left : .right)
        watchLinkService.notifyMatchFinished(
            sessionId: watchSessionId,
            snapshot: .eightBall(state),
            recordId: recordID,
            winnerSide: winner,
            manualEnd: manualFinishRequested,
            startTime: startedAt,
            endTime: Date(),
            totalScoreChanges: actionCount,
            participantNames: [leftName, rightName]
        )
    }

    private func startNewMatch() {
        guard !scoringLocked, !isStartingNewMatch else { return }
        isStartingNewMatch = true
        let finishedStore = sessionStore
        finishedStore.persistSnapshot { persisted in
            guard persisted, saveRecord() else {
                isStartingNewMatch = false
                return
            }
            let newStartedAt = Date()
            let newRecordID = UUID().uuidString
            let freshState = EightBallState.initial(
                targetPoints: state.targetPoints,
                handicapRacks: state.handicapRacks,
                handicapBeneficiary: state.handicapBeneficiary
            )
            let freshStore = SpecializedBilliardsSessionStore(
                gameType: .eightBall,
                state: freshState,
                reducer: EightBallReducer(),
                participants: [
                    .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
                ],
                startedAt: newStartedAt,
                recordID: newRecordID
            )
            freshStore.persistSnapshot { freshSaved in
                isStartingNewMatch = false
                guard freshSaved else { return }
                sessionStore = freshStore
                startedAt = newStartedAt
                recordID = newRecordID
                actionCount = 0
                actionLog.removeAll()
                detailedActions.removeAll()
                manualFinishRequested = false
                scoreboardEditing = false
                showGameOverDialog = false
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                if let watchSessionId {
                    watchLinkService.prepareControllerForNewMatch(
                        sessionId: watchSessionId,
                        gameType: .eightBall,
                        snapshot: .eightBall(freshState),
                        participantNames: [leftName, rightName]
                    )
                }
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        return .init(gameID: GameType.eightBall.canonicalScoreboardIdentifier, title: GameType.eightBall.displayName,
              leftName: leftName, rightName: rightName,
              leftScore: "\(logical(.left))", rightScore: "\(logical(.right))",
              leftDetail: nil, rightDetail: nil,
              themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue,
              fontID: typographyPreference.font.rawValue,
              scoreMultiplier: typographyPreference.scoreMultiplier,
              nameMultiplier: typographyPreference.nameMultiplier,
              secondaryMultiplier: typographyPreference.secondaryMultiplier,
              finished: state.finished, revision: 0)
    }
    @discardableResult
    private func saveRecord() -> Bool {
        let success = saveSpecializedRecord(
            id: recordID, gameType: .eightBall, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftPoints, right: state.rightPoints,
            actionCount: actionCount, actions: actionLog, detailedActions: detailedActions, undoStates: sessionStore.undoStates, finished: state.finished, snapshot: state,
            sessionSnapshotData: sessionStore.encodedResumeBundle,
            projectConfiguration: [
                "maxSets": state.targetPoints,
                "eightBallHandicapRacks": state.handicapRacks,
                "eightBallHandicapBeneficiary": state.handicapBeneficiary == .left ? "team1" : (state.handicapBeneficiary == .right ? "team2" : "none")
            ]
        )
        if !success { showPersistenceError = true }
        return success
    }
}

struct NineBallChaseScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    let initialSetup: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?
    @State private var sessionStore: SpecializedBilliardsSessionStore<NineBallChaseReducer>
    @State private var actionLog: [String] = []
    @State private var detailedActions: [DetailedScoreAction] = []
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession = ScoreboardTypographySession(
        styleID: ScoreboardStyleID(gameType: .nineBall)
    )
    @State private var preferences = PreferencesManager.shared
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var playerNames: [String]
    @State private var showMenu = false
    @State private var showDisplaySettings = false
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var showEditPanel = false
    @State private var editPlayerNames: [String] = []
    @State private var editPlayerScores: [String] = []
    @State private var activeChasePlayer: Int?
    @State private var exitConfirmDeadline: Date?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var previousIdleTimerDisabled: Bool?
    @State private var watchSessionId: UUID?
    @State private var manualFinishRequested = false
    @State private var isStartingNewMatch = false

    private var scoringLocked: Bool {
        watchSessionId != nil
            && (watchLinkService.isFollower || watchLinkService.isAuthorityTransferPending)
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode
            || chromeVisible
            || showDisplaySettings
            || showMenu
            || showEditPanel
            || activeChasePlayer != nil
    }

    private let nineBallActionOrder: [NineBallChaseKind] = [
        .normalWin, .foul,
        .bigGold, .smallGold,
        .goldenNine, .ballInHand
    ]

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let projectedConfiguration = initialSetup?.billiardsConfiguration(for: .nineBall)
        let config: NineBallChaseConfig
        let projectedNames: [String]
        if case let .some(.nineBall(names, points)) = projectedConfiguration {
            config = points
            projectedNames = names
        } else {
            config = NineBallChaseConfig()
            projectedNames = []
        }
        var names = (0..<4).map { index in
            projectedNames[safe: index]?.nonEmpty ?? String.localizedStringWithFormat(
                NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: ""),
                index + 1
            )
        }
        var initial = NineBallChaseState.initial(
            config: config,
            playerCount: projectedNames.isEmpty ? 2 : projectedNames.count,
            playerNames: names
        )
        var start = Date()
        var id = UUID().uuidString
        var actions = 0
        var restoredHistory: [NineBallChaseState] = []
        let restoredActionLog: [String] = []
        let restoredDetailedActions: [DetailedScoreAction] = []
        var showFinished = false
        var resumeBundle: SpecializedBilliardsSessionStore<NineBallChaseReducer>.ResumeBundle?

        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let bundle = SpecializedBilliardsSessionStore<NineBallChaseReducer>.decodeResumeBundle(sessionId: sessionId) {
            resumeBundle = bundle
            initial = bundle.currentSession.state
            start = bundle.currentSession.metadata.extras["startedAtEpochMilliseconds"]
                .flatMap(Int64.init)
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? start
            id = bundle.currentSession.metadata.extras["recordID"] ?? initialResumeSessionId
            actions = bundle.timeline.count
            restoredHistory = bundle.undoFrames.map(\.session.state)
            names = (0..<4).map { initial.resolvedName(at: $0, fallback: names[safe: $0]) }
            showFinished = initial.finished
        }

        let store = resumeBundle.map {
            SpecializedBilliardsSessionStore(resumeBundle: $0, reducer: NineBallChaseReducer())
        } ?? SpecializedBilliardsSessionStore(
            gameType: .nineBall,
            state: initial,
            reducer: NineBallChaseReducer(),
            participants: (0..<initial.playerCount).map {
                .init(id: "player_\($0 + 1)", name: names[$0], role: "player")
            },
            startedAt: start,
            recordID: id,
            restoredUndoStates: restoredHistory
        )
        _sessionStore = State(initialValue: store)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _actionLog = State(initialValue: restoredActionLog)
        _detailedActions = State(initialValue: restoredDetailedActions)
        _playerNames = State(initialValue: names)
        _showGameOverDialog = State(initialValue: showFinished)
        _watchSessionId = State(initialValue: initialSetup?.linkedWatchSessionId)
    }

    private var state: NineBallChaseState { sessionStore.state }

    private func nineBallGridRows(containerSize: CGSize) -> [[Int]] {
        ScoreboardPlayerGridLayout.nineBallRows(
            playerCount: state.playerCount,
            containerSize: containerSize
        )
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let spacing: CGFloat = 0
                let rows = nineBallGridRows(containerSize: proxy.size)
                VStack(spacing: spacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        let cellWidth = (
                            proxy.size.width - spacing * CGFloat(max(0, row.count - 1))
                        ) / CGFloat(max(1, row.count))
                        let cellHeight = (
                            proxy.size.height - spacing * CGFloat(max(0, rows.count - 1))
                        ) / CGFloat(max(1, rows.count))
                        HStack(spacing: spacing) {
                            ForEach(row, id: \.self) { screenIndex in
                                nineBallPlayerColumn(
                                    player: logicalPlayer(forScreenIndex: screenIndex),
                                    screenIndex: screenIndex,
                                    width: cellWidth,
                                    height: cellHeight
                                )
                            }
                        }
                    }
                }
            }
            .background(appearance.theme.palette.background).ignoresSafeArea()

            if shouldShowChrome {
                // Top edit
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            guard !scoringLocked else { return }
                            if showEditPanel {
                                applyPlayerEdits()
                            } else {
                                openEditPanel()
                            }
                            revealImmersiveChrome()
                        }) {
                            Image(systemName: showEditPanel ? "checkmark" : "pencil")
                                .font(.system(size: ScoreboardConstants.buttonIconSize))
                                .foregroundColor(.white)
                                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                .background(Circle().fill(
                                    showEditPanel ? Theme.primary : Color.black.opacity(0.25)
                                ))
                        }
                        .buttonStyle(.plain)
                        .disabled(scoringLocked)
                        .accessibilityIdentifier("scoreboard_edit_button")
                    }
                    .foregroundStyle(.white)
                    .padding(ScoreboardConstants.buttonPadding)
                    Spacer()
                }

                // Bottom-left back + bottom-right menu
                if !showEditPanel {
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: requestBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .foregroundColor(.white)
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(Circle().fill(Color.black.opacity(0.25)))
                            }
                            .buttonStyle(.plain)
                            .modifier(ScoreboardBackButtonAccessibility(isBack: true))
                            .padding(.leading, ScoreboardConstants.buttonPadding)
                            .padding(.bottom, ScoreboardConstants.buttonPadding)

                            Spacer()

                            Button {
                                showMenu = true
                                revealImmersiveChrome()
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .foregroundColor(.white)
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(Circle().fill(Color.black.opacity(0.25)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("scoreboard_menu_button")
                            .padding(.trailing, ScoreboardConstants.buttonPadding)
                            .padding(.bottom, ScoreboardConstants.buttonPadding)
                        }
                    }
                }
            }

            if appearance.immersiveMode && !chromeVisible && !showEditPanel {
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
                    gameType: .nineBall,
                    multiNames: (0..<state.playerCount).map { playerName($0) },
                    multiScores: Array(state.playerPoints.prefix(state.playerCount)),
                    newGameLabel: scoringLocked ? linkedScoreboardNewGameLabel : nil,
                    newGameDisabled: scoringLocked || isStartingNewMatch,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        if !scoringLocked, !saveRecord() { return }
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        let names = (0..<state.playerCount).map { playerName($0) }
                        let scores = Array(state.playerPoints.prefix(state.playerCount))
                        let text = zip(names, scores).map { "\($0) \($1)" }.joined(separator: " · ")
                        ScoreboardShareSupport.present(text: text)
                    },
                    onExit: exit
                )
            }

            MenuDialog(
                isVisible: showMenu,
                onClose: {
                    menuConfirm.clear()
                    showMenu = false
                },
                onMenuItemClick: { action in
                    if scoringLocked,
                       !ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked(action) {
                        showMenu = false
                        return
                    }
                    menuConfirm.prepare(forMenuAction: action)
                    switch action {
                    case "undo":
                        if undo() {
                            showNineBallToast(NSLocalizedString("undone", value: "已撤销", comment: "Undo done"))
                        } else {
                            showNineBallToast(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
                        }
                    case "reset": confirmReset()
                    case "endGame": confirmFinish()
                    case "settleMatch": confirmSettle()
                    case "exchangeSides":
                        send(.exchangeSides)
                        showMenu = false
                    case "displaySettings": showDisplaySettings = true; showMenu = false
                    case "resync":
                        watchLinkService.requestScoreResync()
                        showMenu = false
                    case "takeover":
                        if let id = watchSessionId {
                            Task {
                                do {
                                    try await watchLinkService.takeover(sessionId: id)
                                    publishWatchIfNeeded(state)
                                } catch {
                                    showNineBallToast(error.localizedDescription)
                                }
                            }
                        }
                        showMenu = false
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
                    default: break
                    }
                },
                showEndGame: true,
                showExchangeSide: state.playerCount == 2,
                items: ScoreboardMenuItemBuilder.defaultItems(
                    showEndGame: true,
                    showExchangeSide: state.playerCount == 2,
                    showWhistle: true,
                    showScreenshot: true,
                    showSettleMatch: true,
                    resetConfirming: menuConfirm.resetConfirming,
                    finishConfirming: menuConfirm.finishConfirming,
                    settleConfirming: menuConfirm.settleConfirming,
                    scoringEnabled: !scoringLocked,
                    extraItems: WatchLinkMenuSupport.extraItems(
                        entryEnabled: AppFeatureFlags.watchLinkEntryEnabled,
                        sessionId: watchSessionId,
                        isFollower: watchLinkService.isFollower,
                        watchBackgrounded: watchLinkService.watchBackgrounded
                    )
                ),
                analyticsGameType: .nineBall
            )

            if let player = activeChasePlayer {
                nineBallActionDialog(player: player)
                    .zIndex(30)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
            guard !showEditPanel, activeChasePlayer == nil else { return }
            showMenu = true
            revealImmersiveChrome()
        })
        .simultaneousGesture(DragGesture(minimumDistance: 36).onEnded { value in
            guard !scoringLocked,
                  !showEditPanel,
                  activeChasePlayer == nil,
                  value.translation.width < -60,
                  abs(value.translation.width) > abs(value.translation.height) else { return }
            if undo() {
                showNineBallToast(NSLocalizedString("undone", value: "已撤销", comment: ""))
            } else {
                showNineBallToast(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
            }
        })
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            onSetupConsumed?()
            typographySession.reload()
            registerSync()
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            if let watchSessionId,
               let update = watchLinkService.attachPage(sessionId: watchSessionId),
               let remote = update.snapshot.nineBallState {
                detailedActions = update.detailedActions
                applyAuthoritativeNineBall(remote)
            }
            revealImmersiveChrome()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: showMenu) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: activeChasePlayer) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: typographySession.effectivePreference) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: showEditPanel) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: state.finished) { _, finished in
            if finished {
                showGameOverDialog = true
                notifyLinkedFinishIfNeeded()
            }
        }
        .onChange(of: state) { _, newState in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            publishWatchIfNeeded(newState)
        }
        .onChange(of: sessionStore.persistenceFailureSignal) { _, signal in
            if signal > 0 {
                showNineBallToast(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
            }
        }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId, let update, update.sessionId == watchSessionId,
                  let remote = update.snapshot.nineBallState else { return }
            detailedActions = update.detailedActions
            applyAuthoritativeNineBall(remote)
        }
        .onChange(of: watchLinkService.pendingTakeoverApplication) { _, pending in
            guard let watchSessionId, let pending, pending.sessionId == watchSessionId,
                  let remote = pending.snapshot.nineBallState else { return }
            detailedActions = pending.detailedActions
            applyAuthoritativeNineBall(remote)
            watchLinkService.completePhoneTakeover(messageId: pending.messageId)
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            let skipSave = watchSessionId != nil
                && (watchLinkService.isFollower || watchLinkService.finishedRecordId != nil)
            if let watchSessionId { watchLinkService.detachPage(sessionId: watchSessionId) }
            if !skipSave { saveRecord() }
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.nineBall.adjustableMetrics
        )
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: recordID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ModalCloseButton { showFinishedRecordDetail = false }
                        }
                    }
            }
        }
        .alert(
            NSLocalizedString("linked_score_watch_reclaim_title", value: "手表请求重新接管", comment: ""),
            isPresented: reclaimAlertPresented
        ) {
            Button(NSLocalizedString("linked_score_accept", value: "同意", comment: "")) {
                var snapshot = state
                snapshot.playerNames = Array((playerNames + Array(repeating: "", count: 4)).prefix(4))
                watchLinkService.resolveReclaimRequest(
                    accepted: true,
                    snapshot: .nineBall(snapshot),
                    detailedActions: detailedActions
                )
            }
            Button(NSLocalizedString("linked_score_reject", value: "拒绝", comment: ""), role: .cancel) {
                rejectWatchReclaim()
            }
        } message: {
            Text(NSLocalizedString("linked_score_watch_reclaim_message", value: "是否允许手表在 5 秒内重新接管计分？", comment: ""))
        }
    }

    private func publishWatchIfNeeded(_ state: NineBallChaseState) {
        guard let watchSessionId, watchLinkService.isController else { return }
        var snapshot = state
        snapshot.playerNames = Array((playerNames + Array(repeating: "", count: 4)).prefix(4))
        watchLinkService.syncWatch(
            sessionId: watchSessionId,
            gameType: .nineBall,
            snapshot: .nineBall(snapshot),
            detailedActions: detailedActions,
            participantNames: (0..<state.playerCount).map { playerName($0) }
        )
    }

    private var finishedWinnerName: String {
        let active = Array(state.playerPoints.prefix(state.playerCount))
        guard let best = active.max(), active.filter({ $0 == best }).count == 1,
              let index = active.firstIndex(of: best) else { return "" }
        return playerName(index)
    }

    private func logicalPlayer(forScreenIndex screenIndex: Int) -> Int {
        guard state.playerCount == 2, state.sidesSwapped else { return screenIndex }
        return screenIndex == 0 ? 1 : 0
    }

    private func playerBackground(_ screenIndex: Int) -> Color {
        switch screenIndex {
        case 0: appearance.theme.palette.left
        case 1: appearance.theme.palette.right
        case 2: Color(hex: "3DA447")
        default: Color(hex: "9B6B43")
        }
    }

    private func nineBallPlayerColumn(player: Int, screenIndex: Int, width: CGFloat, height: CGFloat) -> some View {
        let compact = height < 300 || width < 230
        let editOffset = showEditPanel
            ? ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: height)
            : 0
        let scoreText = displayedEditingScore(for: player)
        let detailText = state.playerCounts[player].map(String.init).joined(separator: " ")
        let typography = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .nineBall,
                containerSize: CGSize(width: width, height: height),
                nameText: playerName(player),
                scoreText: scoreText,
                secondaryText: detailText,
                preference: typographySession.effectivePreference,
                horizontalPadding: compact ? 8 : 14,
                reservedHeight: showEditPanel ? 44 : (compact ? 48 : 58),
                isLargeScreen: Theme.usesPadLayout
            )
        )
        let regularScoreSize = typography.scoreFontSize
        let displayedScoreSize = showEditPanel
            ? ScoreboardLayoutMetrics.editMainScoreFontSize(regularSize: regularScoreSize)
            : regularScoreSize
        return ZStack {
            VStack(spacing: 0) {
                Group {
                    if showEditPanel {
                        ScoreboardNameEditorField(
                            placeholder: NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""),
                            text: Binding(
                                get: { editPlayerNames[safe: player] ?? "" },
                                set: { if editPlayerNames.indices.contains(player) { editPlayerNames[player] = $0 } }
                            ),
                            nameType: ScoreboardCommonNamePolicy.nameType(for: .nineBall),
                            scoreboardFont: typographySession.effectivePreference.font,
                            accessibilityIdentifier: "nine_ball_player_\(player)_name_editor"
                        )
                    } else {
                        Text(playerName(player))
                    }
                }
                .font(typographySession.effectivePreference.font.swiftUIFont(
                    size: typography.nameFontSize,
                    weight: .semibold
                ))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, compact ? 12 : 20)
                .offset(y: editOffset)

                Spacer(minLength: 0)

                if !showEditPanel {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(Array(NineBallChaseKind.allCases.enumerated()), id: \.element) { index, kind in
                            VStack(spacing: 1) {
                                Text(chaseTitle(kind))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                Text("\(state.playerCounts[player][index])")
                                    .monospacedDigit()
                                    .fontWeight(.bold)
                            }
                            .font(typographySession.effectivePreference.font.swiftUIFont(
                                size: max(8, typography.secondaryFontSize * 0.22),
                                weight: .regular
                            ))
                            .frame(maxWidth: .infinity, minHeight: compact ? 30 : 36)
                            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .accessibilityIdentifier("nine_ball_player_\(player)_count_\(kind.rawValue)")
                        }
                    }
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.bottom, compact ? 8 : 14)
                }
            }

            nineBallScoreContent(player: player, scoreText: scoreText, displayedScoreSize: displayedScoreSize)
                .offset(y: (compact ? -4 : -8) + editOffset)
        }
        .foregroundStyle(appearance.theme.palette.foreground)
        .frame(width: width, height: height)
        .background(playerBackground(screenIndex))
        .contentShape(Rectangle())
        .onTapGesture {
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: showEditPanel,
                finished: state.finished,
                scoringLocked: scoringLocked
            ) else { return }
            activeChasePlayer = player
        }
        .accessibilityIdentifier("nine_ball_player_\(player)_tile")
    }

    @ViewBuilder
    private func nineBallScoreContent(player: Int, scoreText: String, displayedScoreSize: CGFloat) -> some View {
        if showEditPanel {
            HStack(spacing: 12) {
                Button { adjustEditingScore(player: player, delta: -1) } label: {
                    Image(systemName: "minus")
                        .frame(
                            width: ScoreboardConstants.minimumTouchTarget,
                            height: ScoreboardConstants.minimumTouchTarget
                        )
                        .background(.black.opacity(0.2), in: Capsule())
                }
                Text(scoreText)
                    .font(typographySession.effectivePreference.font.swiftUIFont(size: displayedScoreSize))
                    .minimumScaleFactor(0.42)
                    .lineLimit(1)
                    .monospacedDigit()
                Button { adjustEditingScore(player: player, delta: 1) } label: {
                    Image(systemName: "plus")
                        .frame(
                            width: ScoreboardConstants.minimumTouchTarget,
                            height: ScoreboardConstants.minimumTouchTarget
                        )
                        .background(.black.opacity(0.2), in: Capsule())
                }
            }
            .buttonStyle(.plain)
        } else {
            Text(scoreText)
                .font(typographySession.effectivePreference.font.swiftUIFont(size: displayedScoreSize))
                .minimumScaleFactor(0.42)
                .lineLimit(1)
                .monospacedDigit()
        }
    }

    private func nineBallActionDialog(player: Int) -> some View {
        GeometryReader { proxy in
            let dialogWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                phonePreferredWidth: 380,
                padPreferredWidth: 500
            )

            ZStack {
                Theme.scoreboardDialogScrim
                    .ignoresSafeArea()
                    .onTapGesture { activeChasePlayer = nil }

                VStack(spacing: 0) {
                    ZStack {
                        Text(playerName(player))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 52)

                        HStack {
                            Spacer()
                            ScoreboardDialogCloseButton(
                                action: { activeChasePlayer = nil },
                                accessibilityIdentifier: "nine_ball_action_close"
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 52)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                        spacing: 10
                    ) {
                        ForEach(nineBallActionOrder, id: \.self) { kind in
                            Button {
                                send(.chaseEvent(player: player, kind: kind))
                                activeChasePlayer = nil
                            } label: {
                                VStack(spacing: 4) {
                                    Text(chaseTitle(kind))
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(chasePointDescription(kind, player: player))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(nineBallActionBackground(kind))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(scoringLocked || state.finished)
                            .accessibilityIdentifier("nine_ball_action_\(kind.rawValue)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .frame(width: dialogWidth)
                .background(Theme.scoreboardDialogSurface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 32, x: 0, y: 12)
                .contentShape(Rectangle())
                .onTapGesture { }
                .accessibilityIdentifier("nine_ball_action_dialog")
            }
        }
    }

    private func nineBallActionBackground(_ kind: NineBallChaseKind) -> Color {
        switch kind {
        case .normalWin:
            Theme.primary
        case .foul:
            Color(hex: "E5484D")
        default:
            Theme.scoreboardDialogControl
        }
    }

    private func chasePointDescription(_ kind: NineBallChaseKind, player: Int) -> String {
        let value: Int
        switch kind {
        case .bigGold: value = state.config.bigGold
        case .smallGold: value = state.config.smallGold
        case .goldenNine: value = state.config.goldenNine
        case .normalWin: value = state.config.normalWin
        case .ballInHand: value = state.config.ballInHand
        case .foul: value = state.config.foul
        }
        if kind == .foul, state.playerCount > 2 { return "-\(value)" }
        if kind == .foul { return String.localizedStringWithFormat(NSLocalizedString("nine_ball_foul_opponent_points", value: "对手 +%d", comment: ""), value) }
        return "+\(value)"
    }
    private func chaseTitle(_ kind: NineBallChaseKind) -> String {
        switch kind {
        case .bigGold: NSLocalizedString("nine_ball_big_gold", value: "大金", comment: "")
        case .smallGold: NSLocalizedString("nine_ball_small_gold", value: "小金", comment: "")
        case .goldenNine: NSLocalizedString("nine_ball_golden_nine", value: "黄金九", comment: "")
        case .normalWin: NSLocalizedString("nine_ball_normal_win", value: "普胜", comment: "")
        case .ballInHand: NSLocalizedString("nine_ball_ball_in_hand", value: "自由球", comment: "")
        case .foul: NSLocalizedString("nine_ball_foul", value: "犯规", comment: "")
        }
    }
    private func playerName(_ index: Int) -> String {
        playerNames[safe: index] ?? String.localizedStringWithFormat(
            NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: ""), index + 1
        )
    }
    private func openEditPanel() {
        guard !showEditPanel else { return }
        editPlayerNames = (0..<state.playerCount).map(playerName)
        editPlayerScores = Array(state.playerPoints.prefix(state.playerCount)).map(String.init)
        showEditPanel = true
    }

    private func adjustEditingScore(player: Int, delta: Int) {
        guard showEditPanel, !scoringLocked, editPlayerScores.indices.contains(player) else { return }
        let current = Int(editPlayerScores[player]) ?? state.playerPoints[safe: player] ?? 0
        editPlayerScores[player] = String(min(9_999, max(-9_999, current + delta)))
    }

    private func applyPlayerEdits() {
        guard !scoringLocked else {
            showEditPanel = false
            return
        }
        let names = (0..<state.playerCount).map { index in
            let candidate = editPlayerNames[safe: index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return candidate.isEmpty ? playerName(index) : candidate
        }
        let scores = (0..<state.playerCount).map { index in
            min(9_999, max(-9_999, Int(editPlayerScores[safe: index] ?? "") ?? state.playerPoints[index]))
        }
        playerNames = Array((names + Array(playerNames.dropFirst(state.playerCount))).prefix(4))
        send(.adminCorrect(playerNames: names, playerPoints: scores))
        showGameOverDialog = false
        showEditPanel = false
    }

    private func displayedEditingScore(for player: Int) -> String {
        guard showEditPanel else { return "\(state.playerPoints[player])" }
        return editPlayerScores[safe: player] ?? "\(state.playerPoints[player])"
    }
    private func send(_ intent: NineBallChaseIntent) {
        guard !scoringLocked else { return }
        sessionStore.send(intent) { _, next, events in
            actionCount += 1
            actionLog.append(recordSnapshot(code: String(describing: intent), scores: next.playerPoints))
            for event in events {
                switch event {
                case .chaseApplied(let player, let scorePlayer, let kind, let delta):
                    detailedActions.append(nineBallDetailedAction(
                        type: kind == .foul ? .foul : .scoreChanged,
                        team: RecordTeam.allCases.indices.contains(scorePlayer)
                            ? RecordTeam.allCases[scorePlayer]
                            : nil,
                        delta: delta,
                        code: "nine_ball_\(kind.rawValue)_actor_\(player + 1)_score_\(scorePlayer + 1)"
                    ))
                case .sidesExchanged:
                    detailedActions.append(nineBallDetailedAction(type: .sideChanged, code: "exchange_side"))
                case .totalsAdjusted:
                    let type: DetailedScoreActionType
                    if case .resetScores = intent { type = .reset } else { type = .stateChanged }
                    detailedActions.append(nineBallDetailedAction(type: type, code: type == .reset ? "reset" : "nine_ball_edit"))
                    if case .adminCorrect = intent {
                        playerNames = (0..<4).map { next.resolvedName(at: $0, fallback: playerNames[safe: $0]) }
                        sessionStore.updateParticipants((0..<next.playerCount).map {
                            .init(id: "player_\($0 + 1)", name: playerNames[$0], role: "player")
                        })
                    }
                case .matchFinished:
                    detailedActions.append(nineBallDetailedAction(type: .matchFinished, code: "finish"))
                }
            }
        }
    }
    private func markFinished() {
        guard !scoringLocked, !state.finished else { return }
        manualFinishRequested = true
        send(.finishMatch)
    }
    private func confirmReset() {
        if menuConfirm.armOrConfirm(.reset) {
            send(.resetScores)
            showGameOverDialog = false
            showNineBallToast(NSLocalizedString("has_been_reset", value: "已重置", comment: ""))
            showMenu = false
            return
        }
        showNineBallToast(ScoreboardMenuConfirmAction.reset.localizedToast)
    }
    private func confirmFinish() {
        if menuConfirm.armOrConfirm(.finish) {
            markFinished()
            showMenu = false
            return
        }
        showNineBallToast(ScoreboardMenuConfirmAction.finish.localizedToast)
    }
    private func confirmSettle() {
        if menuConfirm.armOrConfirm(.settleMatch) {
            markFinished()
            showMenu = false
            return
        }
        showNineBallToast(ScoreboardMenuConfirmAction.settleMatch.localizedToast)
    }
    private func undo() -> Bool {
        guard !scoringLocked else { return false }
        return sessionStore.undo { success, restored in
            guard success else { return }
            actionCount = max(0, actionCount - 1)
            actionLog.append(recordSnapshot(code: "undo", scores: restored.playerPoints))
            detailedActions.append(nineBallDetailedAction(type: .undo, code: "undo"))
            showGameOverDialog = restored.finished
        }
    }

    private func nineBallDetailedAction(
        type: DetailedScoreActionType,
        team: RecordTeam? = nil,
        delta: Int? = nil,
        code: String
    ) -> DetailedScoreAction {
        let participants = (0..<state.playerCount).map { index in
            ParticipantScoreSnapshot(
                id: "player_\(index + 1)",
                name: playerName(index),
                score: state.playerPoints[index],
                role: state.playerCounts[index].map(String.init).joined(separator: ",")
            )
        }
        return DetailedScoreAction(
            type: type,
            epochMilliseconds: nowMilliseconds(),
            team: team,
            scores: Array(state.playerPoints.prefix(state.playerCount)),
            scoreChange: delta,
            participants: participants,
            operationCode: code
        )
    }
    private func showNineBallToast(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showToast = false }
    }
    private func requestBack() {
        let now = Date()
        if exitConfirmDeadline.map({ now <= $0 }) != true {
            exitConfirmDeadline = now.addingTimeInterval(2)
            toastMessage = NSLocalizedString("press_again_to_exit", value: "再按一次退出", comment: "")
            showToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showToast = false
            }
            VibrationManager.shared.vibrateHeavy()
            revealImmersiveChrome()
            return
        }
        exitConfirmDeadline = nil
        exit()
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode,
              !showDisplaySettings,
              !showMenu,
              !showEditPanel,
              activeChasePlayer == nil else { return }
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
                  !showMenu,
                  !showEditPanel,
                  activeChasePlayer == nil else { return }
            if let exitConfirmDeadline, Date() <= exitConfirmDeadline { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu
            || showDisplaySettings
            || showEditPanel
            || activeChasePlayer != nil
            || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }

    private func exit() {
        sessionStore.flush {
            guard saveRecord() else { return }
            onNavigationBack?()
            dismiss()
        }
    }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: showEditPanel,
                finished: state.finished,
                scoringLocked: scoringLocked
            ) else { return }
            switch intent {
            case .addLeft: send(.chaseEvent(player: 0, kind: .normalWin))
            case .addRight: send(.chaseEvent(player: 1, kind: .normalWin))
            case .subtractLeft, .subtractRight, .undo: _ = undo()
            default: break
            }
        }
    }

    private var reclaimAlertPresented: Binding<Bool> {
        Binding(
            get: { watchLinkService.pendingReclaimRequest != nil },
            set: { presented in
                if !presented, watchLinkService.pendingReclaimRequest != nil {
                    rejectWatchReclaim()
                }
            }
        )
    }

    private func rejectWatchReclaim() {
        watchLinkService.resolveReclaimRequest(accepted: false, snapshot: nil, detailedActions: [])
    }

    private func applyAuthoritativeNineBall(_ remote: NineBallChaseState) {
        sessionStore.rebase(to: remote) { applied in
            if applied.playerNames.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                playerNames = (0..<4).map { applied.resolvedName(at: $0, fallback: playerNames[safe: $0]) }
            }
            showGameOverDialog = applied.finished
            manualFinishRequested = false
        }
    }

    private func notifyLinkedFinishIfNeeded() {
        guard let watchSessionId, watchLinkService.isController else { return }
        let activeScores = Array(state.playerPoints.prefix(state.playerCount))
        let winner: MatchSide? = state.playerCount == 2 && activeScores.count >= 2 && activeScores[0] != activeScores[1]
            ? (activeScores[0] > activeScores[1] ? .left : .right)
            : nil
        var snapshot = state
        snapshot.playerNames = Array((playerNames + Array(repeating: "", count: 4)).prefix(4))
        watchLinkService.notifyMatchFinished(
            sessionId: watchSessionId,
            snapshot: .nineBall(snapshot),
            recordId: recordID,
            winnerSide: winner,
            manualEnd: manualFinishRequested,
            startTime: startedAt,
            endTime: Date(),
            totalScoreChanges: actionCount,
            participantNames: (0..<state.playerCount).map { playerName($0) }
        )
    }
    private func startNewMatch() {
        guard !scoringLocked, !isStartingNewMatch else { return }
        isStartingNewMatch = true
        let finishedStore = sessionStore
        finishedStore.persistSnapshot { persisted in
            guard persisted, saveRecord() else {
                isStartingNewMatch = false
                return
            }
            let newStartedAt = Date()
            let newRecordID = UUID().uuidString
            let activeNames = (0..<state.playerCount).map { playerName($0) }
            let freshState = NineBallChaseState.initial(
                config: state.config,
                playerCount: state.playerCount,
                playerNames: activeNames
            )
            let freshStore = SpecializedBilliardsSessionStore(
                gameType: .nineBall,
                state: freshState,
                reducer: NineBallChaseReducer(),
                participants: activeNames.indices.map {
                    .init(id: "player_\($0 + 1)", name: activeNames[$0], role: "player")
                },
                startedAt: newStartedAt,
                recordID: newRecordID
            )
            freshStore.persistSnapshot { freshSaved in
                isStartingNewMatch = false
                guard freshSaved else { return }
                sessionStore = freshStore
                startedAt = newStartedAt
                recordID = newRecordID
                playerNames = Array((activeNames + Array(repeating: "", count: 4)).prefix(4))
                actionCount = 0
                actionLog.removeAll()
                detailedActions.removeAll()
                editPlayerNames.removeAll()
                editPlayerScores.removeAll()
                activeChasePlayer = nil
                showEditPanel = false
                manualFinishRequested = false
                showGameOverDialog = false
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                if let watchSessionId {
                    watchLinkService.prepareControllerForNewMatch(
                        sessionId: watchSessionId,
                        gameType: .nineBall,
                        snapshot: .nineBall(freshState),
                        participantNames: activeNames
                    )
                }
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        .init(
            gameID: GameType.nineBall.canonicalScoreboardIdentifier,
            title: GameType.nineBall.displayName,
            leftName: playerName(0),
            rightName: playerName(1),
            leftScore: "\(state.playerPoints[0])",
            rightScore: "\(state.playerPoints[1])",
            leftDetail: nil,
            rightDetail: nil,
            themeID: appearance.theme.rawValue,
            fontID: typographySession.effectivePreference.font.rawValue,
            scoreMultiplier: typographySession.effectivePreference.scoreMultiplier,
            nameMultiplier: typographySession.effectivePreference.nameMultiplier,
            secondaryMultiplier: typographySession.effectivePreference.secondaryMultiplier,
            finished: state.finished,
            revision: 0
        )
    }
    @discardableResult
    private func saveRecord() -> Bool {
        let activePlayers: [[String: Any]] = (0..<state.playerCount).map { index in
            ["name": playerName(index), "finalScore": state.playerPoints[index]]
        }
        let success = saveSpecializedRecord(
            id: recordID, gameType: .nineBall, startedAt: startedAt,
            leftName: playerName(0), rightName: playerName(1),
            left: state.playerPoints[0], right: state.playerPoints[1],
            actionCount: actionCount, actions: actionLog, detailedActions: detailedActions, undoStates: sessionStore.undoStates, finished: state.finished, snapshot: state,
            sessionSnapshotData: sessionStore.encodedResumeBundle,
            extra: [
                "playerNames": Array(playerNames.prefix(state.playerCount)),
                "players": activePlayers
            ],
            projectConfiguration: [
                "playerCount": state.playerCount,
                "nineBallBigGold": state.config.bigGold,
                "nineBallSmallGold": state.config.smallGold,
                "nineBallGoldenNine": state.config.goldenNine,
                "nineBallNormalWin": state.config.normalWin,
                "nineBallBallInHand": state.config.ballInHand,
                "nineBallFoul": state.config.foul
            ]
        )
        if !success {
            showNineBallToast(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
        }
        return success
    }
}

struct SnookerReducerScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    let initialSetup: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?
    @State private var sessionStore: SpecializedBilliardsSessionStore<SnookerReducer>
    @State private var actionLog: [String] = []
    @State private var detailedActions: [DetailedScoreAction] = []
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var leftName: String
    @State private var rightName: String
    @State private var showFoulPanel = false
    @State private var showSettlePanel = false
    @State private var showRecordPanel = false
    @State private var foulSwitchTurn = true
    @State private var settleWinner: MatchSide = .left
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var showPersistenceError = false
    @State private var watchSessionId: UUID?
    @State private var manualFinishRequested = false
    @State private var scoreboardEditing = false
    @State private var isStartingNewMatch = false
    @State private var terminalFrameHold = ScoreboardTerminalHold<SnookerState>()
    @State private var typographyPreference = PreferencesManager.shared.scoreboardTypography(
        for: ScoreboardStyleID(gameType: .snooker)
    )

    private let balls: [(points: Int, color: Color, label: String)] = [
        (1, Color(hex: "FF3B30"), "1"),
        (2, Color(hex: "FFCC00"), "2"),
        (3, Color(hex: "34C759"), "3"),
        (4, Color(hex: "A2845E"), "4"),
        (5, Color(hex: "0A84FF"), "5"),
        (6, Color(hex: "FF2D55"), "6"),
        (7, Color(hex: "000000"), "7")
    ]

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let red = localizedSideRedName()
        let blue = localizedSideBlueName()
        var left = initialSetup?.team1Name.nonEmpty ?? red
        var right = initialSetup?.team2Name.nonEmpty ?? blue
        let maxFrames: Int
        let firstBreaker: MatchSide
        if case let .some(.snooker(projectedFrames, projectedBreaker)) = initialSetup?.billiardsConfiguration(for: .snooker) {
            maxFrames = projectedFrames
            firstBreaker = projectedBreaker
        } else {
            maxFrames = 1
            firstBreaker = .left
        }
        var initial = SnookerState.initial(striker: firstBreaker, maxFrames: maxFrames)
        var start = Date()
        var id = UUID().uuidString
        var actions = 0
        var restoredHistory: [SnookerState] = []
        let restoredActionLog: [String] = []
        let restoredDetailedActions: [DetailedScoreAction] = []
        var showFinished = false
        var resumeBundle: SpecializedBilliardsSessionStore<SnookerReducer>.ResumeBundle?

        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let bundle = SpecializedBilliardsSessionStore<SnookerReducer>.decodeResumeBundle(sessionId: sessionId) {
            resumeBundle = bundle
            initial = bundle.currentSession.state
            start = bundle.currentSession.metadata.extras["startedAtEpochMilliseconds"]
                .flatMap(Int64.init)
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? start
            id = bundle.currentSession.metadata.extras["recordID"] ?? initialResumeSessionId
            actions = bundle.timeline.count
            restoredHistory = bundle.undoFrames.map(\.session.state)
            if bundle.currentSession.participants.count >= 2 {
                left = bundle.currentSession.participants[0].name
                right = bundle.currentSession.participants[1].name
            }
            showFinished = initial.finished
        }

        let store = resumeBundle.map {
            SpecializedBilliardsSessionStore(resumeBundle: $0, reducer: SnookerReducer())
        } ?? SpecializedBilliardsSessionStore(
            gameType: .snooker,
            state: initial,
            reducer: SnookerReducer(),
            participants: [
                .init(id: TeamID.team0.rawValue, name: left, role: "team"),
                .init(id: TeamID.team1.rawValue, name: right, role: "team")
            ],
            startedAt: start,
            recordID: id,
            restoredUndoStates: restoredHistory
        )
        _sessionStore = State(initialValue: store)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _actionLog = State(initialValue: restoredActionLog)
        _detailedActions = State(initialValue: restoredDetailedActions)
        _leftName = State(initialValue: left)
        _rightName = State(initialValue: right)
        _showGameOverDialog = State(initialValue: showFinished)
        _watchSessionId = State(initialValue: initialSetup?.linkedWatchSessionId)
    }

    private var state: SnookerState { sessionStore.state }
    private var displayedState: SnookerState { terminalFrameHold.value ?? state }

    private var linkScoringLocked: Bool {
        watchSessionId != nil
            && (watchLinkService.isFollower || watchLinkService.isAuthorityTransferPending)
    }

    private var scoringLocked: Bool {
        terminalFrameHold.value != nil || linkScoringLocked
    }

    var body: some View {
        snookerContent
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            finishedRecordDetailPage
        }
        .onAppear {
            onSetupConsumed?()
            registerSync()
            if let watchSessionId,
               let update = watchLinkService.attachPage(sessionId: watchSessionId),
               let remote = update.snapshot.snookerState {
                detailedActions = update.detailedActions
                applyAuthoritativeSnooker(remote)
            }
        }
        .onChange(of: state.finished) { _, finished in
            if finished, terminalFrameHold.value == nil {
                showGameOverDialog = true
                notifyLinkedFinishIfNeeded()
            }
        }
        .onChange(of: state) { _, newState in
            if terminalFrameHold.value == nil {
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                publishWatchIfNeeded(newState)
            }
        }
        .onChange(of: sessionStore.persistenceFailureSignal) { _, signal in
            if signal > 0 { showPersistenceError = true }
        }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId, let update, update.sessionId == watchSessionId,
                  let remote = update.snapshot.snookerState else { return }
            detailedActions = update.detailedActions
            applyAuthoritativeSnooker(remote)
        }
        .onChange(of: watchLinkService.pendingTakeoverApplication) { _, pending in
            guard let watchSessionId, let pending, pending.sessionId == watchSessionId,
                  let remote = pending.snapshot.snookerState else { return }
            detailedActions = pending.detailedActions
            applyAuthoritativeSnooker(remote)
            watchLinkService.completePhoneTakeover(messageId: pending.messageId)
        }
        .onDisappear {
            cancelTerminalFramePresentation()
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            let skipSave = watchSessionId != nil
                && (watchLinkService.isFollower || watchLinkService.finishedRecordId != nil)
            if let watchSessionId { watchLinkService.detachPage(sessionId: watchSessionId) }
            if !skipSave { saveRecord() }
        }
        .sheet(isPresented: $showSettlePanel) { settleSheet }
        .sheet(isPresented: $showRecordPanel) { snookerRecordSheet }
        .alert(
            NSLocalizedString("linked_score_watch_reclaim_title", value: "手表请求重新接管", comment: ""),
            isPresented: reclaimAlertPresented
        ) {
            Button(NSLocalizedString("linked_score_accept", value: "同意", comment: "")) {
                watchLinkService.resolveReclaimRequest(
                    accepted: true,
                    snapshot: .snooker(state),
                    detailedActions: detailedActions
                )
            }
            Button(NSLocalizedString("linked_score_reject", value: "拒绝", comment: ""), role: .cancel) {
                rejectWatchReclaim()
            }
        } message: {
            Text(NSLocalizedString("linked_score_watch_reclaim_message", value: "是否允许手表在 5 秒内重新接管计分？", comment: ""))
        }
        .alert(
            NSLocalizedString("save_failed", value: "保存失败", comment: ""),
            isPresented: $showPersistenceError
        ) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
        }
    }

    private var snookerContent: some View {
        ZStack {
            snookerScaffold

            if showFoulPanel {
                snookerFoulOverlay
                    .zIndex(30)
            }

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: finishedWinnerName,
                    gameType: .snooker,
                    leftName: leftName,
                    rightName: rightName,
                    leftScore: state.maxFrames > 1 ? state.leftFrames : state.leftScore,
                    rightScore: state.maxFrames > 1 ? state.rightFrames : state.rightScore,
                    newGameLabel: scoringLocked ? linkedScoreboardNewGameLabel : nil,
                    newGameDisabled: scoringLocked || isStartingNewMatch,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        if !scoringLocked, !saveRecord() { return }
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        let left = state.maxFrames > 1 ? state.leftFrames : state.leftScore
                        let right = state.maxFrames > 1 ? state.rightFrames : state.rightScore
                        ScoreboardShareSupport.present(text: "\(leftName) \(left) - \(right) \(rightName)")
                    },
                    onExit: exit
                )
            }
        }
    }

    private var finishedRecordDetailPage: some View {
        NavigationStack {
            ScoreboardRecordDetailPage(recordId: recordID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalCloseButton { showFinishedRecordDetail = false }
                    }
                }
        }
    }

    private var snookerScaffold: some View {
        SpecializedScoreboardScaffold(
            gameType: .snooker,
            leftName: leftName,
            rightName: rightName,
            leftScore: "\(displayedState.leftScore)",
            rightScore: "\(displayedState.rightScore)",
            leftDetail: "\(displayedState.leftBreak)",
            rightDetail: "\(displayedState.rightBreak)",
            finished: displayedState.finished,
            onLeftTap: {},
            onRightTap: {},
            onUndo: { undo() },
            onReset: { resetMatch() },
            onExchange: nil,
            onBack: exit,
            showEndGame: true,
            onEndGame: {
                guard !scoringLocked else { return }
                manualFinishRequested = true
                send(.finishMatch)
            },
            onEditCommit: { left, right, leftScore, rightScore in
                guard !scoringLocked else { return }
                applyEditNames(left: left, right: right)
            },
            nameType: ScoreboardCommonNamePolicy.nameType(for: .snooker),
            editingEnabled: !scoringLocked,
            scoringEnabled: !linkScoringLocked,
            onEditAdjust: { isLeft, delta in
                guard !scoringLocked else { return }
                adjustSnookerScore(side: isLeft ? .left : .right, delta: delta)
            },
            extraMenuItems: [
                ScoreboardMenuItem(
                    title: NSLocalizedString("record", value: "记录", comment: ""),
                    action: "frameRecord",
                    group: .match,
                    icon: "list.bullet.rectangle"
                ),
                ScoreboardMenuItem(
                    title: NSLocalizedString("snooker_settle_frame", value: "结算本局", comment: ""),
                    action: "settleFrame",
                    group: .match,
                    icon: "flag"
                )
            ] + WatchLinkMenuSupport.extraItems(
                entryEnabled: AppFeatureFlags.watchLinkEntryEnabled,
                sessionId: watchSessionId,
                isFollower: watchLinkService.isFollower,
                watchBackgrounded: watchLinkService.watchBackgrounded
            ),
            onMenuAction: { action in
                switch action {
                case "frameRecord":
                    showRecordPanel = true
                case "settleFrame":
                    guard !scoringLocked else { return }
                    settleWinner = state.leftScore >= state.rightScore ? .left : .right
                    showSettlePanel = true
                case "resync":
                    watchLinkService.requestScoreResync()
                case "takeover":
                    if let id = watchSessionId {
                        Task {
                            do {
                                try await watchLinkService.takeover(sessionId: id)
                                publishWatchIfNeeded(state)
                            } catch {
                                showPersistenceError = true
                            }
                        }
                    }
                case "forceTakeover":
                    if let id = watchSessionId {
                        watchLinkService.requestForceTakeoverConfirmation(id)
                    }
                case "endLink":
                    if let id = watchSessionId {
                        watchLinkService.leaveSession(id)
                        watchSessionId = nil
                    }
                default:
                    break
                }
            },
            seamOverlay: {
                AnyView(
                    GeometryReader { geo in
                        let indicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                            halfViewportSize: CGSize(width: geo.size.width / 2, height: geo.size.height)
                        )
                        CenterLineServeIndicator(
                            isLeftServing: displayedState.striker == .left,
                            triangleSize: indicatorSize
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                )
            },
            bottomBar: { AnyView(snookerBottomBar) },
            topCenter: { preference, containerSize in
                AnyView(framePill(preference: preference, containerSize: containerSize))
            },
            onEditModeChange: { scoreboardEditing = $0 },
            onTypographyChange: { preference in
                typographyPreference = preference
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            }
        ) { _, _ in
            EmptyView()
        }
    }

    private func publishWatchIfNeeded(_ state: SnookerState) {
        guard let watchSessionId, watchLinkService.isController else { return }
        watchLinkService.syncWatch(
            sessionId: watchSessionId,
            gameType: .snooker,
            snapshot: .snooker(state),
            detailedActions: detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private var finishedWinnerName: String {
        if state.leftFrames > state.rightFrames { return leftName }
        if state.rightFrames > state.leftFrames { return rightName }
        if state.leftScore > state.rightScore { return leftName }
        if state.rightScore > state.leftScore { return rightName }
        return ""
    }

    private func framePill(
        preference: ScoreboardTypographyPreference,
        containerSize: CGSize
    ) -> some View {
        let detail = String(format: "%d %d/%d %d", displayedState.leftFrames, displayedState.currentFrame, displayedState.maxFrames, displayedState.rightFrames)
        let secondarySize = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .specialized,
                containerSize: CGSize(
                    width: max(150, min(360, containerSize.width * 0.38)),
                    height: containerSize.height
                ),
                nameText: "",
                scoreText: "",
                secondaryText: detail,
                preference: preference,
                horizontalPadding: 12,
                secondaryBaseScale: 0.3,
                isLargeScreen: Theme.usesPadLayout
            )
        ).secondaryFontSize
        return Group {
            if displayedState.maxFrames > 1 {
                HStack(spacing: 0) {
                    Text("\(displayedState.leftFrames)").frame(width: 42)
                    Text(String(format: NSLocalizedString("snooker_current_frame_short", value: "第 %d/%d 局", comment: ""), displayedState.currentFrame, displayedState.maxFrames))
                        .font(preference.font.swiftUIFont(size: max(8, secondarySize * 0.68), weight: .semibold))
                    Text("\(displayedState.rightFrames)").frame(width: 42)
                }
                .font(preference.font.swiftUIFont(size: secondarySize, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: max(34, secondarySize * 1.7))
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .accessibilityIdentifier("snooker_frame_status")
                .accessibilityValue("\(displayedState.leftFrames)|\(displayedState.currentFrame)|\(displayedState.maxFrames)|\(displayedState.rightFrames)")
            }
        }
    }

    private var snookerBottomBar: some View {
        let controlSize: CGFloat = Theme.usesPadLayout ? 50 : 44
        let spacing: CGFloat = Theme.usesPadLayout ? 8 : 6
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = Theme.usesPadLayout ? 10 : 8
        let actionHorizontalPadding: CGFloat = Theme.usesPadLayout ? 4 : 3

        return snookerBottomBarControls(
            controlSize: controlSize,
            spacing: spacing,
            actionHorizontalPadding: actionHorizontalPadding
        )
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.28))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        .padding(.bottom, 16)
    }

    private func snookerBottomBarControls(
        controlSize: CGFloat,
        spacing: CGFloat,
        actionHorizontalPadding: CGFloat
    ) -> some View {
        HStack(spacing: spacing) {
            ForEach(balls, id: \.points) { ball in
                let legal = isLegalSnookerBall(ball.points)
                Button {
                    guard !scoringLocked, legal else { return }
                    send(.potBall(points: ball.points))
                } label: {
                    Group {
                        if ball.points == 1 {
                            HStack(spacing: 0) {
                                Text("x")
                                    .font(typographyPreference.font.swiftUIFont(
                                        size: snookerControlFontSize(text: "x", baseScale: 0.18),
                                        weight: .bold
                                    ))
                                Text("\(displayedState.redBallsRemaining)")
                                    .font(typographyPreference.font.swiftUIFont(
                                        size: snookerControlFontSize(text: "\(displayedState.redBallsRemaining)", baseScale: 0.3),
                                        weight: .bold
                                    ))
                            }
                        } else {
                            Text(ball.label)
                                .font(typographyPreference.font.swiftUIFont(
                                    size: snookerControlFontSize(text: ball.label, baseScale: 0.34),
                                    weight: .bold
                                ))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: controlSize, height: controlSize)
                    .background(Circle().fill(ball.color))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .opacity(legal ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snooker_ball_\(ball.points)")
                .disabled(scoringLocked || displayedState.finished || !legal)
            }
            Button {
                guard !scoringLocked else { return }
                foulSwitchTurn = true
                showFoulPanel = true
            } label: {
                Text(NSLocalizedString("snooker_foul_button", value: "犯规", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "FF453A"))
                    .frame(minWidth: controlSize, minHeight: controlSize)
                    .padding(.horizontal, actionHorizontalPadding)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("snooker_foul_button")
            .disabled(scoringLocked || displayedState.finished)
            Button {
                guard !scoringLocked else { return }
                send(.handover)
            } label: {
                Text(NSLocalizedString("snooker_handover", value: "交杆", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: controlSize, minHeight: controlSize)
                    .padding(.horizontal, actionHorizontalPadding)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .disabled(scoringLocked || displayedState.finished)
        }
    }

    private func snookerControlFontSize(text: String, baseScale: CGFloat) -> CGFloat {
        ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .specialized,
                containerSize: CGSize(width: 50, height: 50),
                nameText: "",
                scoreText: "",
                secondaryText: text,
                preference: typographyPreference,
                horizontalPadding: 4,
                secondaryBaseScale: baseScale,
                isLargeScreen: Theme.usesPadLayout
            )
        ).secondaryFontSize
    }

    /// HOS legal-ball highlighting: red stage → red; color stage → any colour; clearance → expected colour only.
    private func isLegalSnookerBall(_ points: Int) -> Bool {
        switch displayedState.nextBallStage {
        case .red:
            return points == 1 && displayedState.redBallsRemaining > 0
        case .color:
            return points >= 2 && points <= 7
        case .yellow: return points == 2
        case .green: return points == 3
        case .brown: return points == 4
        case .blue: return points == 5
        case .pink: return points == 6
        case .black: return points == 7
        case .complete: return false
        }
    }

    private var snookerFoulOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                phonePreferredWidth: 320,
                padPreferredWidth: 420
            )

            ZStack {
                Theme.scoreboardDialogScrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissFoulPanel() }

                VStack(spacing: 12) {
                    Text(NSLocalizedString("snooker_foul_row_title", value: "犯规罚分", comment: ""))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)

                    Text(snookerFoulCurrentSideText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .padding(.horizontal, 10)

                    HStack(spacing: 8) {
                        snookerFoulTurnButton(
                            NSLocalizedString("snooker_foul_switch_turn", value: "换手", comment: ""),
                            switchTurn: true
                        )
                        snookerFoulTurnButton(
                            NSLocalizedString("snooker_foul_continue", value: "犯规方继续", comment: ""),
                            switchTurn: false
                        )
                    }

                    HStack(spacing: 8) {
                        ForEach([4, 5, 6, 7], id: \.self) { points in
                            snookerFoulPointButton(points)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .frame(width: panelWidth, height: 248)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.scoreboardDialogSurface)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    ScoreboardDialogCloseButton(
                        action: dismissFoulPanel,
                        accessibilityIdentifier: "snooker_foul_close"
                    )
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                }
                .onTapGesture {}
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    private var snookerFoulCurrentSideText: String {
        String(
            format: NSLocalizedString("snooker_foul_current_side", value: "当前方：%@", comment: ""),
            state.striker == .left ? leftName : rightName
        )
    }

    private func snookerFoulTurnButton(_ title: String, switchTurn: Bool) -> some View {
        let selected = foulSwitchTurn == switchTurn
        return Button {
            foulSwitchTurn = switchTurn
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.68))
                .frame(maxWidth: .infinity)
                .frame(height: ScoreboardConstants.minimumTouchTarget)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.2 : 0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func snookerFoulPointButton(_ points: Int) -> some View {
        Button {
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: scoreboardEditing,
                finished: state.finished,
                scoringLocked: scoringLocked
            ) else { return }
            send(.foul(pointsToOpponent: points, switchTurn: foulSwitchTurn))
            dismissFoulPanel()
        } label: {
            VStack(spacing: 2) {
                Text("+\(points)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "FF453A"))
                Text(snookerFoulBallLabel(points))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "D64F4F").opacity(0.24))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("snooker_foul_\(points)")
    }

    private func snookerFoulBallLabel(_ points: Int) -> String {
        switch points {
        case 5:
            NSLocalizedString("snooker_foul_label_5", value: "蓝", comment: "")
        case 6:
            NSLocalizedString("snooker_foul_label_6", value: "粉", comment: "")
        case 7:
            NSLocalizedString("snooker_foul_label_7", value: "黑", comment: "")
        default:
            NSLocalizedString("snooker_foul_label_4", value: "红/黄/绿/棕", comment: "")
        }
    }

    private func dismissFoulPanel() {
        showFoulPanel = false
    }

    private var settleSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(NSLocalizedString("snooker_settle_frame_title", value: "选择本局胜方", comment: "")).font(.headline)
                Picker("", selection: $settleWinner) {
                    Text(leftName).tag(MatchSide.left)
                    Text(rightName).tag(MatchSide.right)
                }
                .pickerStyle(.segmented)
                Button(NSLocalizedString("snooker_settle_frame", value: "结算本局", comment: "")) {
                    guard !scoringLocked else { return }
                    settleCurrentFrame(winner: settleWinner)
                    showSettlePanel = false
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(24)
            .navigationTitle(NSLocalizedString("snooker_settle_frame", value: "结算本局", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", value: "取消", comment: "")) { showSettlePanel = false }
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
        .environment(\.font, .body)
        .presentationDetents([.height(260)])
        .presentationBackground(Theme.dialogSurfaceBackground)
    }

    private var snookerRecordSheet: some View {
        NavigationStack {
            Group {
                if actionLog.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("record_empty", value: "暂无记录", comment: ""),
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    List(Array(actionLog.enumerated()).reversed(), id: \.offset) { _, raw in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snookerRecordTitle(raw))
                                .font(.body.weight(.medium))
                            Text(snookerRecordScore(raw))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("record", value: "记录", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ModalCloseButton { showRecordPanel = false }
                }
            }
        }
        .environment(\.font, .body)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.dialogSurfaceBackground)
    }

    private func snookerRecordTitle(_ raw: String) -> String {
        let code = raw.split(separator: "|", omittingEmptySubsequences: false)[safe: 2].map(String.init) ?? raw
        if code.contains("potBall") { return NSLocalizedString("snooker_record_pot", value: "进球", comment: "") }
        if code.contains("foul") { return NSLocalizedString("snooker_foul_button", value: "犯规", comment: "") }
        if code.contains("handover") { return NSLocalizedString("snooker_handover", value: "交杆", comment: "") }
        if code.contains("settleFrame") { return NSLocalizedString("snooker_settle_frame", value: "结算本局", comment: "") }
        if code == "undo" { return NSLocalizedString("undone", value: "已撤销", comment: "") }
        if code == "reset" { return NSLocalizedString("has_been_reset", value: "已重置", comment: "") }
        if code.contains("adminCorrect") { return NSLocalizedString("edit", value: "编辑", comment: "") }
        return code.replacingOccurrences(of: "_", with: " ")
    }

    private func snookerRecordScore(_ raw: String) -> String {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
        let scores = parts[safe: 3].map(String.init) ?? ""
        let frames = parts[safe: 4].map(String.init) ?? ""
        return frames.isEmpty ? scores : "\(scores)  ·  \(frames)"
    }

    private func send(_ intent: SnookerIntent) {
        guard !scoringLocked else { return }
        sessionStore.send(intent) { previous, next, _ in
            actionCount += 1
            actionLog.append(recordSnapshot(code: String(describing: intent), scores: [next.leftScore, next.rightScore], setScores: [next.leftFrames, next.rightFrames]))
            appendSnookerAction(intent, previousState: previous)
            if next.finished {
                showGameOverDialog = true
            }
        }
    }

    private func settleCurrentFrame(winner: MatchSide) {
        guard !scoringLocked else { return }
        let finalFrame = state
        sessionStore.send(.settleFrame(winner: winner)) { previous, next, _ in
            actionCount += 1
            actionLog.append(recordSnapshot(
                code: String(describing: SnookerIntent.settleFrame(winner: winner)),
                scores: [previous.leftScore, previous.rightScore],
                setScores: [next.leftFrames, next.rightFrames]
            ))
            appendSnookerAction(.settleFrame(winner: winner), previousState: previous)
            terminalFrameHold.begin(finalFrame) {
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                publishWatchIfNeeded(state)
                if state.finished {
                    showGameOverDialog = true
                    notifyLinkedFinishIfNeeded()
                }
            }
        }
    }

    private func cancelTerminalFramePresentation() {
        terminalFrameHold.cancel()
    }

    private func undo() -> Bool {
        guard !linkScoringLocked,
              (!state.finished || terminalFrameHold.value != nil) else { return false }
        cancelTerminalFramePresentation()
        return sessionStore.undo { success, restored in
            guard success else { return }
            actionCount = max(0, actionCount - 1)
            actionLog.append(recordSnapshot(code: "undo", scores: [restored.leftScore, restored.rightScore], setScores: [restored.leftFrames, restored.rightFrames]))
            detailedActions.append(snookerDetailedAction(type: .undo, code: "undo"))
            showGameOverDialog = restored.finished
        }
    }
    private func exit() {
        cancelTerminalFramePresentation()
        sessionStore.flush {
            guard saveRecord() else { return }
            onNavigationBack?()
            dismiss()
        }
    }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: scoreboardEditing,
                finished: state.finished,
                scoringLocked: scoringLocked
            ) else { return }
            switch intent {
            case .addLeft: send(.potBallAsSide(side: .left, points: 1))
            case .addRight: send(.potBallAsSide(side: .right, points: 1))
            case .subtractLeft, .subtractRight, .undo: _ = undo()
            default: break
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        let display = displayedState
        return .init(
            gameID: GameType.snooker.canonicalScoreboardIdentifier,
            title: GameType.snooker.displayName,
            leftName: leftName,
            rightName: rightName,
            leftScore: "\(display.leftScore)",
            rightScore: "\(display.rightScore)",
            leftDetail: String.localizedStringWithFormat(NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), display.leftFrames),
            rightDetail: String.localizedStringWithFormat(NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), display.rightFrames),
            themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue,
            fontID: typographyPreference.font.rawValue,
            scoreMultiplier: typographyPreference.scoreMultiplier,
            nameMultiplier: typographyPreference.nameMultiplier,
            secondaryMultiplier: typographyPreference.secondaryMultiplier,
            finished: display.finished,
            revision: 0
        )
    }
    private func resetMatch() {
        guard !linkScoringLocked else { return }
        cancelTerminalFramePresentation()
        send(.reset)
        foulSwitchTurn = true
        showSettlePanel = false
        showFoulPanel = false
        showGameOverDialog = false
        manualFinishRequested = false
    }
    private func applyEditNames(left: String, right: String) {
        guard !scoringLocked else { return }
        if !left.isEmpty { leftName = left }
        if !right.isEmpty { rightName = right }
        sessionStore.updateParticipants([
            .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
        ])
        actionCount += 1
        actionLog.append(recordSnapshot(code: "edit_names", scores: [state.leftScore, state.rightScore], setScores: [state.leftFrames, state.rightFrames]))
        detailedActions.append(snookerDetailedAction(type: .stateChanged, code: "snooker_edit_names"))
    }

    private func adjustSnookerScore(side: MatchSide, delta: Int) {
        let left = max(0, state.leftScore + (side == .left ? delta : 0))
        let right = max(0, state.rightScore + (side == .right ? delta : 0))
        send(.adminCorrect(left: left, right: right, striker: state.striker))
        showGameOverDialog = false
    }

    private func appendSnookerAction(_ intent: SnookerIntent, previousState: SnookerState) {
        let type: DetailedScoreActionType
        let team: RecordTeam?
        let delta: Int?
        let code: String
        var recordedScores: [Int]?
        var recordedSetScores: [Int]?
        switch intent {
        case .potBall(let points):
            type = .scoreChanged
            team = previousState.striker == .left ? .team1 : .team2
            delta = points
            code = "snooker_pot_\(points)"
        case .potBallAsSide(let side, let points):
            type = .scoreChanged
            team = side == .left ? .team1 : .team2
            delta = points
            code = "snooker_pot_\(points)"
        case .foul(let points, let switchTurn):
            type = .foul; team = previousState.striker == .left ? .team2 : .team1; delta = points
            code = "snooker_foul_\(points)_\(switchTurn ? "switch" : "continue")"
        case .foulFromSide(let side, let points, let switchTurn):
            type = .foul; team = side == .left ? .team2 : .team1; delta = points
            code = "snooker_foul_\(points)_\(switchTurn ? "switch" : "continue")"
        case .miss:
            type = .serveChanged; team = state.striker == .left ? .team1 : .team2; delta = nil; code = "snooker_miss"
        case .missFromPanel(let side):
            type = .serveChanged; team = side == .left ? .team2 : .team1; delta = nil; code = "snooker_miss"
        case .handover:
            type = .serveChanged; team = state.striker == .left ? .team1 : .team2; delta = nil; code = "snooker_handover"
        case .handoverFromPanel(let side):
            type = .serveChanged; team = side == .left ? .team2 : .team1; delta = nil; code = "snooker_handover"
        case .settleFrame(let winner):
            type = .setFinished; team = winner == .left ? .team1 : .team2; delta = nil; code = "snooker_settle_frame"
            recordedScores = [previousState.leftScore, previousState.rightScore]
            recordedSetScores = [state.leftFrames, state.rightFrames]
        case .adminCorrect:
            type = .stateChanged; team = nil; delta = nil; code = "snooker_edit"
        case .finishMatch:
            type = .matchFinished; team = nil; delta = nil; code = "finish"
        case .reset:
            type = .reset; team = nil; delta = nil; code = "reset"
        case .confirmStriker(let side):
            type = .serveChanged; team = side == .left ? .team1 : .team2; delta = nil; code = "snooker_striker"
        case .confirmNextFrame:
            return
        }
        detailedActions.append(snookerDetailedAction(
            type: type,
            team: team,
            delta: delta,
            code: code,
            setNumber: previousState.currentFrame,
            scores: recordedScores,
            setScores: recordedSetScores
        ))
    }

    private func snookerDetailedAction(
        type: DetailedScoreActionType,
        team: RecordTeam? = nil,
        delta: Int? = nil,
        code: String,
        setNumber: Int? = nil,
        scores: [Int]? = nil,
        setScores: [Int]? = nil
    ) -> DetailedScoreAction {
        DetailedScoreAction(
            type: type,
            epochMilliseconds: nowMilliseconds(),
            team: team,
            scores: scores ?? [state.leftScore, state.rightScore],
            setScores: setScores ?? [state.leftFrames, state.rightFrames],
            setNumber: setNumber ?? state.currentFrame,
            scoreChange: delta,
            winner: type == .setFinished ? team : nil,
            operationCode: code,
            summary: "reds=\(state.redBallsRemaining);stage=\(state.nextBallStage.rawValue);striker=\(state.striker.rawValue)"
        )
    }

    private var reclaimAlertPresented: Binding<Bool> {
        Binding(
            get: { watchLinkService.pendingReclaimRequest != nil },
            set: { presented in
                if !presented, watchLinkService.pendingReclaimRequest != nil {
                    rejectWatchReclaim()
                }
            }
        )
    }

    private func rejectWatchReclaim() {
        watchLinkService.resolveReclaimRequest(accepted: false, snapshot: nil, detailedActions: [])
    }

    private func applyAuthoritativeSnooker(_ remote: SnookerState) {
        cancelTerminalFramePresentation()
        sessionStore.rebase(to: remote) { applied in
            showFoulPanel = false
            showSettlePanel = false
            showGameOverDialog = applied.finished
            manualFinishRequested = false
        }
    }

    private func notifyLinkedFinishIfNeeded() {
        guard let watchSessionId, watchLinkService.isController else { return }
        let left = state.maxFrames > 1 ? state.leftFrames : state.leftScore
        let right = state.maxFrames > 1 ? state.rightFrames : state.rightScore
        let winner: MatchSide? = left == right ? nil : (left > right ? .left : .right)
        watchLinkService.notifyMatchFinished(
            sessionId: watchSessionId,
            snapshot: .snooker(state),
            recordId: recordID,
            winnerSide: winner,
            manualEnd: manualFinishRequested,
            startTime: startedAt,
            endTime: Date(),
            totalScoreChanges: actionCount,
            participantNames: [leftName, rightName]
        )
    }
    private func startNewMatch() {
        guard !scoringLocked, !isStartingNewMatch else { return }
        isStartingNewMatch = true
        let finishedStore = sessionStore
        finishedStore.persistSnapshot { persisted in
            guard persisted, saveRecord() else {
                isStartingNewMatch = false
                return
            }
            let newStartedAt = Date()
            let newRecordID = UUID().uuidString
            let freshState = SnookerState.initial(
                striker: state.firstBreaker,
                maxFrames: state.maxFrames
            )
            let freshStore = SpecializedBilliardsSessionStore(
                gameType: .snooker,
                state: freshState,
                reducer: SnookerReducer(),
                participants: [
                    .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
                ],
                startedAt: newStartedAt,
                recordID: newRecordID
            )
            freshStore.persistSnapshot { freshSaved in
                isStartingNewMatch = false
                guard freshSaved else { return }
                sessionStore = freshStore
                startedAt = newStartedAt
                recordID = newRecordID
                actionCount = 0
                actionLog.removeAll()
                detailedActions.removeAll()
                showFoulPanel = false
                showSettlePanel = false
                showRecordPanel = false
                foulSwitchTurn = true
                settleWinner = freshState.striker
                scoreboardEditing = false
                manualFinishRequested = false
                showGameOverDialog = false
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                if let watchSessionId {
                    watchLinkService.prepareControllerForNewMatch(
                        sessionId: watchSessionId,
                        gameType: .snooker,
                        snapshot: .snooker(freshState),
                        participantNames: [leftName, rightName]
                    )
                }
            }
        }
    }
    @discardableResult
    private func saveRecord() -> Bool {
        let success = saveSpecializedRecord(
            id: recordID, gameType: .snooker, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftScore, right: state.rightScore,
            leftSets: state.leftFrames, rightSets: state.rightFrames,
            actionCount: actionCount, actions: actionLog, detailedActions: detailedActions, undoStates: sessionStore.undoStates, finished: state.finished, snapshot: state,
            sessionSnapshotData: sessionStore.encodedResumeBundle,
            projectConfiguration: [
                "maxSets": state.maxFrames,
                "servingSide": state.firstBreaker.rawValue
            ]
        )
        if !success { showPersistenceError = true }
        return success
    }
}

struct ShengjiReducerScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?
    @State private var state: ShengjiTierState
    @State private var history: [ShengjiTierState] = []
    @State private var actionLog: [String] = []
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var leftName: String
    @State private var rightName: String
    @State private var showFinishedRecordDetail = false
    @State private var scoreboardEditing = false
    @State private var showGameOverDialog = false
    @State private var showPersistenceError = false
    @State private var typographyPreference = PreferencesManager.shared.scoreboardTypography(
        for: ScoreboardStyleID(gameType: .shengji)
    )
    private let reducer = ShengjiTierReducer()
    private let levels = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let red = localizedSideRedName()
        let blue = localizedSideBlueName()
        var left = initialSetup?.team1Name.nonEmpty ?? red
        var right = initialSetup?.team2Name.nonEmpty ?? blue
        var initial = ShengjiTierState()
        var start = Date()
        var id = ScoreboardRecordIdentity.next(prefix: GameType.shengji.canonicalScoreboardIdentifier)
        var actions = 0

        if let initialResumeSessionId,
           let resume = loadSpecializedResume(recordId: initialResumeSessionId, as: ShengjiTierState.self) {
            initial = resume.state
            start = resume.record.startTime
            id = resume.record.id
            actions = max(resume.record.totalScoreChanges, 1)
            left = resume.record.team1Name
            right = resume.record.team2Name
        }

        _state = State(initialValue: initial)
        _showGameOverDialog = State(initialValue: initial.finished)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _leftName = State(initialValue: left)
        _rightName = State(initialValue: right)
    }

    var body: some View {
        shengjiContent
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            finishedRecordDetailPage
        }
        .onAppear { onSetupConsumed?(); registerSync() }
        .onChange(of: state) { _, _ in LocalScoreboardSyncCoordinator.shared.publishSnapshot() }
        .onDisappear { LocalScoreboardSyncCoordinator.shared.unregisterHost(); saveRecord() }
        .alert(
            NSLocalizedString("save_failed", value: "保存失败", comment: ""),
            isPresented: $showPersistenceError
        ) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
        }
    }

    private var shengjiContent: some View {
        ZStack {
            shengjiScaffold

            if showGameOverDialog {
                let winnerName: String = switch state.winnerSide {
                case .left: leftName
                case .right: rightName
                case nil: ""
                }
                let winnerIndices: Set<Int> = switch state.winnerSide {
                case .left: [0]
                case .right: [1]
                case nil: []
                }
                GameOverDialog(
                    winnerName: winnerName,
                    gameType: .shengji,
                    resultText: "\(level(state.leftIndex)) - \(level(state.rightIndex))",
                    leftName: leftName,
                    rightName: rightName,
                    leftScoreText: level(state.leftIndex),
                    rightScoreText: level(state.rightIndex),
                    winnerIndices: winnerIndices,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        saveRecord()
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(text: "\(leftName) \(level(state.leftIndex)) - \(level(state.rightIndex)) \(rightName)")
                    },
                    onExit: exit
                )
            }
        }
    }

    private var finishedRecordDetailPage: some View {
        NavigationStack {
            ScoreboardRecordDetailPage(recordId: recordID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalCloseButton { showFinishedRecordDetail = false }
                    }
                }
        }
    }

    private var shengjiScaffold: some View {
        SpecializedScoreboardScaffold(
            gameType: .shengji,
            leftName: leftName,
            rightName: rightName,
            leftScore: level(state.leftIndex),
            rightScore: level(state.rightIndex),
            leftDetail: nil,
            rightDetail: nil,
            finished: state.finished,
            onLeftTap: {},
            onRightTap: {},
            onUndo: undo,
            onReset: resetMatch,
            onExchange: nil,
            onBack: exit,
            showEndGame: true,
            onEndGame: finishMatch,
            onEditCommit: applyEdit,
            onEditAdjust: { isLeft, delta in
                let side: MatchSide = isLeft ? .left : .right
                if delta < 0 {
                    send(.subtractLevels(side: side, delta: abs(delta)))
                } else {
                    send(.addLevels(side: side, delta: delta))
                }
            },
            seamOverlay: state.dealer == nil ? nil : {
                AnyView(
                    GeometryReader { geo in
                        let indicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                            halfViewportSize: CGSize(width: geo.size.width / 2, height: geo.size.height)
                        )
                        CenterLineServeIndicator(
                            isLeftServing: state.dealer == .left,
                            triangleSize: indicatorSize,
                            color: ScoreboardTheme.serverIndicatorColor
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                )
            },
            panelAccessory: { isLeft in
                AnyView(shengjiPanelActions(side: isLeft ? .left : .right))
            },
            onEditModeChange: { scoreboardEditing = $0 },
            onTypographyChange: { preference in
                typographyPreference = preference
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            }
        ) { _, _ in
            EmptyView()
        }
    }

    @ViewBuilder
    private func shengjiPanelActions(side: MatchSide) -> some View {
        if state.dealer == nil {
            scoreboardCardActionButton(
                NSLocalizedString("shengji_claim_dealer", value: "抢庄", comment: ""),
                width: Theme.usesPadLayout ? 104 : 88
            ) {
                send(.claimDealer(side))
            }
            .accessibilityIdentifier(side == .left ? "ui_test_shengji_left_banker" : "ui_test_shengji_right_banker")
        } else if !state.finished {
            HStack(spacing: 12) {
                if state.dealer != side {
                    scoreboardCardActionButton(
                        NSLocalizedString("shengji_take_dealer", value: "上台", comment: ""),
                        width: Theme.usesPadLayout ? 96 : 80
                    ) {
                        send(.resolveRound(winner: side, delta: 0))
                    }
                }
                ForEach([1, 2, 3], id: \.self) { step in
                    scoreboardCardActionButton("+\(step)") {
                        send(.resolveRound(winner: side, delta: step))
                    }
                }
            }
        }
    }

    private func level(_ index: Int) -> String { levels[min(max(0, index), levels.count - 1)] }
    private func send(_ intent: ShengjiTierIntent) {
        let result = reducer.reduce(state: state, intent: intent, at: nowMilliseconds())
        guard result.accepted else { return }
        history.append(state)
        let wasFinished = state.finished
        state = result.state
        actionCount += 1
        actionLog.append(recordSnapshot(code: String(describing: intent), scores: [state.leftIndex, state.rightIndex]))
        if state.finished, !wasFinished {
            showGameOverDialog = true
        }
    }
    private func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        state = previous
        actionCount = max(0, actionCount - 1)
        actionLog.append(recordSnapshot(code: "undo", scores: [state.leftIndex, state.rightIndex]))
        return true
    }
    private func resetMatch() {
        send(.reset)
        showGameOverDialog = false
    }
    private func startNewMatch() {
        saveRecord()
        state = ShengjiTierState(maxTierIndex: state.maxTierIndex)
        history.removeAll()
        actionLog.removeAll()
        actionCount = 0
        startedAt = Date()
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.shengji.canonicalScoreboardIdentifier)
        showGameOverDialog = false
    }
    private func finishMatch() {
        send(.finish)
    }
    private func applyEdit(left: String, right: String, leftScore: String, rightScore: String) {
        let previousState = state
        let previousLeftName = leftName
        let previousRightName = rightName
        let nextLeftIndex = levels.firstIndex(of: leftScore.uppercased()) ?? state.leftIndex
        let nextRightIndex = levels.firstIndex(of: rightScore.uppercased()) ?? state.rightIndex
        let result = reducer.reduce(
            state: state,
            intent: .adminCorrect(left: nextLeftIndex, right: nextRightIndex),
            at: nowMilliseconds()
        )
        guard result.accepted else { return }
        let next = result.state

        let nextLeftName = left.isEmpty ? leftName : left
        let nextRightName = right.isEmpty ? rightName : right
        let stateChanged = next != previousState
        let namesChanged = nextLeftName != previousLeftName || nextRightName != previousRightName
        guard stateChanged || namesChanged else { return }

        if stateChanged { history.append(previousState) }
        state = next
        leftName = nextLeftName
        rightName = nextRightName
        actionCount += 1
    }
    private func exit() { saveRecord(); onNavigationBack?(); dismiss() }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: scoreboardEditing,
                finished: state.finished,
                scoringLocked: false
            ) else { return }
            switch intent {
            case .addLeft:
                if state.dealer == nil { send(.claimDealer(.left)) }
                else { send(.resolveRound(winner: .left, delta: 1)) }
            case .addRight:
                if state.dealer == nil { send(.claimDealer(.right)) }
                else { send(.resolveRound(winner: .right, delta: 1)) }
            case .subtractLeft: send(.subtractLevels(side: .left, delta: 1))
            case .subtractRight: send(.subtractLevels(side: .right, delta: 1))
            case .undo: _ = undo()
            default: break
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        return .init(
            gameID: GameType.shengji.canonicalScoreboardIdentifier,
            title: GameType.shengji.displayName,
            leftName: leftName,
            rightName: rightName,
            leftScore: level(state.leftIndex),
            rightScore: level(state.rightIndex),
            leftDetail: nil,
            rightDetail: nil,
            themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue,
            fontID: typographyPreference.font.rawValue,
            scoreMultiplier: typographyPreference.scoreMultiplier,
            nameMultiplier: typographyPreference.nameMultiplier,
            secondaryMultiplier: typographyPreference.secondaryMultiplier,
            finished: state.finished,
            revision: 0
        )
    }
    @discardableResult
    private func saveRecord() -> Bool {
        let success = saveSpecializedRecord(
            id: recordID, gameType: .shengji, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftIndex, right: state.rightIndex,
            actionCount: actionCount, actions: actionLog, finished: state.finished, snapshot: state
        )
        if !success { showPersistenceError = true }
        return success
    }
}

private func nowMilliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

private func recordSnapshot(code: String, scores: [Int], setScores: [Int] = []) -> String {
    let normalizedCode = code
        .replacingOccurrences(of: "|", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    return "\(nowMilliseconds())|snapshot|\(normalizedCode)|\(scores.map(String.init).joined(separator: ","))|\(setScores.map(String.init).joined(separator: ","))"
}

private func localizedSideRedName() -> String {
    NSLocalizedString("watch_team_red", value: "红方", comment: "")
}

private func localizedSideBlueName() -> String {
    NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
}

private func localizedRedName() -> String { localizedSideRedName() }
private func localizedBlueName() -> String { localizedSideBlueName() }

private struct ReducerScoreboardStateSnapshot<State: Codable>: Codable {
    var schemaVersion: Int = 1
    let state: State
    let undoStates: [State]
    let intentTimeline: [String]
    let detailedActions: [DetailedScoreAction]
}

private func loadSpecializedResume<State: Codable>(
    recordId: String,
    as type: State.Type
) -> (record: ManualScoreboardResumeState, state: State, undoStates: [State], intentTimeline: [String], detailedActions: [DetailedScoreAction])? {
    guard let record = ManualResumeSessionStore.load(recordID: recordId),
          let data = record.stateSnapshot else {
        return nil
    }
    guard let state = try? JSONDecoder().decode(type, from: data) else { return nil }
    return (record, state, [], record.actions, record.detailedActions ?? [])
}

@MainActor
@discardableResult
private func saveSpecializedRecord<State: Codable>(
    id: String,
    gameType: GameType,
    startedAt: Date,
    leftName: String,
    rightName: String,
    left: Int,
    right: Int,
    leftSets: Int? = nil,
    rightSets: Int? = nil,
    actionCount: Int,
    actions: [String] = [],
    detailedActions: [DetailedScoreAction]? = nil,
    undoStates: [State]? = nil,
    finished: Bool,
    snapshot: State,
    sessionSnapshotData: Data? = nil,
    extra: [String: Any] = [:],
    projectConfiguration: [String: Any] = [:]
) -> Bool {
    guard actionCount > 0 else { return true }
    if !finished, gameType == .eightBall || gameType == .nineBall || gameType == .snooker {
        // These reducers already persist their complete ScoreSession bundle.
        // A second manual payload would overwrite the authoritative resume.
        return true
    }
    let end = Date()
    let winner = finished && left != right ? (left > right ? "left" : "right") : nil
    let snapshotData: Data
    do {
        if let sessionSnapshotData {
            snapshotData = sessionSnapshotData
        } else if let undoStates {
            snapshotData = try JSONEncoder().encode(ReducerScoreboardStateSnapshot(
                state: snapshot,
                undoStates: undoStates,
                intentTimeline: actions,
                detailedActions: detailedActions ?? []
            ))
        } else {
            snapshotData = try JSONEncoder().encode(snapshot)
        }
    } catch {
        specializedRecordLogger.error("Failed to encode specialized record \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        return false
    }
    var extraData: [String: AnyCodable] = [
        "schemaVersion": AnyCodable(4),
        "canonicalGameType": AnyCodable(gameType.canonicalScoreboardIdentifier)
    ]
    for (key, value) in extra {
        extraData[key] = AnyCodable(value)
    }
    var configuration: [String: AnyCodable] = [:]
    for (key, value) in projectConfiguration {
        configuration[key] = AnyCodable(value)
    }
    var record = ScoreboardRecord(
        id: id,
        gameType: gameType,
        startTime: startedAt,
        endTime: finished ? end : nil,
        duration: end.timeIntervalSince(startedAt),
        team1Name: leftName,
        team2Name: rightName,
        team1FinalScore: left,
        team2FinalScore: right,
        team1SetScore: leftSets,
        team2SetScore: rightSets,
        winner: winner,
        actions: actions,
        totalScoreChanges: actionCount,
        extraData: extraData,
        projectConfiguration: configuration.isEmpty ? nil : configuration,
        stateSnapshot: snapshotData,
        status: finished ? .finished : .draft
    )
    let resolvedDetailedActions = detailedActions?.isEmpty == false
        ? detailedActions!
        : ScoreboardRecordActionAdapter.actions(for: record)
    record.detailedActions = resolvedDetailedActions
    record.setResults = ScoreboardRecordActionAdapter.setResults(from: resolvedDetailedActions)
    do {
        try ScoreboardLifecyclePersistence.save(record, finished: finished)
        return true
    } catch {
        specializedRecordLogger.error("Failed to save specialized record \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        return false
    }
}

private let specializedRecordLogger = Logger(
    subsystem: "com.douhua.jifen.ios",
    category: "SpecializedRecordPersistence"
)

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
