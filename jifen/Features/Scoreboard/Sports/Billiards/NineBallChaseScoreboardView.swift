import OSLog
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI
import UIKit

func nineBallLogicalPlayerIndex(
    forScreenIndex screenIndex: Int,
    playerCount: Int,
    sidesSwapped: Bool
) -> Int {
    guard playerCount == 2, sidesSwapped else { return screenIndex }
    return screenIndex == 0 ? 1 : 0
}

enum NineBallUndoPolicy {
    static func isAllowed(finished: Bool, gameOverPresented: Bool) -> Bool {
        !finished && !gameOverPresented
    }

    @discardableResult
    static func performIfAllowed(
        finished: Bool,
        gameOverPresented: Bool,
        undo: () -> Bool
    ) -> Bool {
        guard isAllowed(finished: finished, gameOverPresented: gameOverPresented) else {
            return false
        }
        return undo()
    }
}

/// The visible rack reviewed by a tap or confirmation. The store checks this
/// against its synchronous queue projection before reserving any undo frame.
struct NineBallTransferContext: Equatable {
    let ruleVersion: Int
    let roundNumber: Int
    let breakerPlayer: Int

    init(state: NineBallChaseState) {
        ruleVersion = state.ruleVersion
        roundNumber = state.roundNumber
        breakerPlayer = state.breakerPlayer
    }

    func matches(_ state: NineBallChaseState) -> Bool {
        (ruleVersion == 2 || ruleVersion == 3) && state.ruleVersion == ruleVersion
            && state.roundNumber == roundNumber && state.breakerPlayer == breakerPlayer
    }

    func validatedIntent(_ intent: NineBallChaseIntent, in state: NineBallChaseState) -> NineBallChaseIntent? {
        switch intent {
        case .chaseTransfer, .tournamentEvent: return matches(state) ? intent : nil
        default: return intent
        }
    }
}

private struct NineBallPendingTransfer: Equatable {
    let player: Int
    let kind: NineBallChaseKind
    let context: NineBallTransferContext
    var payer: Int?
    var continuePlayer: Int?

    var intent: NineBallChaseIntent {
        .chaseTransfer(player: player, kind: kind, payer: payer, continuePlayer: continuePlayer)
    }
}

struct NineBallChaseScoreboardView: View {
    @Environment(\.scoreboardEditAboveMenu) private var editAboveMenu
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?
    @State private var sessionStore: BilliardsSessionStore<NineBallChaseReducer>
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
    @State private var initialParticipantSelections: [String: ParticipantSelection]?
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
    @State private var pendingTransfer: NineBallPendingTransfer?
    @State private var correctingSmallGoldPayer = false
    @State private var showRules = false
    @State private var showBreakerPicker = false
    @State private var showBreakerIntro = false
    @State private var exitConfirmDeadline: Date?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var previousIdleTimerDisabled: Bool?
    @State private var manualFinishRequested = false
    @State private var isStartingNewMatch = false

    private var scoringLocked: Bool {
        false
    }

    private var hasChaseDialog: Bool {
        activeChasePlayer != nil || pendingTransfer != nil || showBreakerPicker || showBreakerIntro
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode
            || chromeVisible
            || showDisplaySettings
            || showMenu
            || showEditPanel
            || hasChaseDialog
    }

    private var nineBallMenuItems: [ScoreboardMenuItem] {
        ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: false,
            showWhistle: true,
            showScreenshot: true,
            showSettleMatch: true,
            resetConfirming: menuConfirm.resetConfirming,
            exchangeConfirming: menuConfirm.exchangeConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            settleConfirming: menuConfirm.settleConfirming,
            scoringEnabled: !scoringLocked,
            extraItems: state.usesRackRules ? [
                ScoreboardMenuItem(
                    title: NSLocalizedString("nine_ball_current_breaker", value: "本局开球人", comment: ""),
                    action: "nineBallBreaker",
                    group: .match,
                    iconAsset: "ic_snooker_cue",
                    enabled: !state.finished
                )
            ] : []
        )
    }

    private var nineBallActionRows: [[NineBallChaseKind]] {
        if state.isTournament { return [[.normalWin, .foul], [.bigGold, .smallGold]] }
        return state.ruleVersion == 1
            ? [[.normalWin, .foul], [.bigGold, .smallGold, .goldenNine, .ballInHand]]
            : [[.normalWin, .foul], [.bigGold, .smallGold, .goldenNine]]
    }

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
            playerNames: names,
            ruleVersion: 3,
            breakerPlayer: initialSetup?.nineBallBreakerPlayer ?? 0
        )
        var start = Date()
        var id = UUID().uuidString
        var actions = 0
        var restoredHistory: [NineBallChaseState] = []
        var restoredActionLog: [String] = []
        var restoredDetailedActions: [DetailedScoreAction] = []
        var showFinished = false
        var resumeBundle: BilliardsSessionStore<NineBallChaseReducer>.ResumeBundle?

        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let bundle = BilliardsSessionStore<NineBallChaseReducer>.decodeResumeBundle(sessionId: sessionId) {
            resumeBundle = bundle
            initial = bundle.currentSession.state
            start = bundle.currentSession.metadata.extras["startedAtEpochMilliseconds"]
                .flatMap(Int64.init)
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? start
            id = bundle.currentSession.metadata.extras["recordID"] ?? initialResumeSessionId
            let recordContext = ScoreSessionRecordContext.decode(bundle.auxiliaryPayload)
            restoredActionLog = recordContext?.actionLog ?? []
            restoredDetailedActions = recordContext?.detailedActions ?? []
            actions = recordContext?.actionCount ?? bundle.timeline.count
            restoredHistory = bundle.undoFrames.map(\.session.state)
            names = (0..<4).map { initial.resolvedName(at: $0, fallback: names[safe: $0]) }
            showFinished = initial.finished
        }

        let store = resumeBundle.map {
            BilliardsSessionStore(resumeBundle: $0, reducer: NineBallChaseReducer())
        } ?? BilliardsSessionStore(
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
        _initialParticipantSelections = State(initialValue: initialResumeSessionId == nil ? (initialSetup?.participantSelections ?? [:]) : nil)
    }

    private var state: NineBallChaseState { sessionStore.state }
    private func nineBallGridRows(containerSize: CGSize) -> [[Int]] {
        ScoreboardPlayerGridLayout.nineBallRows(
            playerCount: state.playerCount,
            containerSize: containerSize,
            forceWide: state.playerCount == 2 ? true : nil
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
                // Edit / done above the fixed bottom-right Menu slot
                VStack {
                    if editAboveMenu { Spacer() }
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
                                .foregroundColor((showEditPanel ? Theme.textOnPrimary : Color.white))
                                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                .background(Circle().fill(
                                    showEditPanel ? Theme.primary : Color.black.opacity(0.25)
                                ))
                        }
                        .buttonStyle(.plain)
                        .disabled(scoringLocked)
                        .accessibilityIdentifier("scoreboard_edit_button")
                        .accessibilityLabel(showEditPanel ? NSLocalizedString("done", value: "完成", comment: "") : NSLocalizedString("edit", value: "编辑", comment: ""))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, ScoreboardConstants.buttonPadding)
                    .padding(.bottom, editAboveMenu ? ScoreboardConstants.editButtonBottomPadding : 0)
                    .padding(.top, editAboveMenu ? 0 : ScoreboardConstants.buttonPadding)
                    if !editAboveMenu { Spacer() }
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
                    .allowsHitTesting(false)
            }
            if showGameOverDialog {
                GameOverDialog(
                    winnerName: finishedWinnerName,
                    gameType: .nineBall,
                    multiNames: (0..<state.playerCount).map { playerName($0) },
                    multiScores: Array(state.playerPoints.prefix(state.playerCount)),
                    newGameLabel: nil,
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
                    case ScoreboardMenuActionID.exchangeSide.rawValue:
                        if menuConfirm.armOrConfirm(.exchangeSide) {
                            send(.exchangeSides)
                        } else {
                            showNineBallToast(ScoreboardMenuConfirmAction.exchangeSide.localizedToast)
                        }
                    case "displaySettings": showDisplaySettings = true; showMenu = false
                    case "nineBallBreaker":
                        showMenu = false
                        showBreakerPicker = true
                    case "endLink":

                        showMenu = false
                    default: break
                    }
                },
                showEndGame: true,
                showExchangeSide: false,
                items: nineBallMenuItems,
                analyticsGameType: .nineBall
            )

            if let player = activeChasePlayer {
                nineBallActionDialog(player: player)
                    .zIndex(30)
            }
            if let pending = pendingTransfer {
                nineBallTransferDialog(pending)
                    .zIndex(40)
            }
            if showBreakerPicker {
                nineBallBreakerDialog
                    .zIndex(45)
            }
            if showBreakerIntro {
                nineBallBreakerIntro
                    .zIndex(50)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        .animation(.easeInOut(duration: 0.2), value: activeChasePlayer)
        .ignoresSafeArea(.all)
        .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
            guard !showEditPanel, !hasChaseDialog else { return }
            showMenu = true
            revealImmersiveChrome()
        })
        .simultaneousGesture(DragGesture(minimumDistance: 36).onEnded { value in
            guard !scoringLocked,
                  NineBallUndoPolicy.isAllowed(
                    finished: state.finished,
                    gameOverPresented: showGameOverDialog
                  ),
                  !showEditPanel,
                  !hasChaseDialog,
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
        .sheet(isPresented: $showRules) {
            NavigationStack { NineBallRulesView(folk: state.isTournament ? .init() : state.config,
                tournament: state.isTournament ? state.config : .init(ruleFamily: .tournament),
                presetFamily: state.isTournament ? .folk : .tournament) }
        }
        .registerParticipantSetupOnAppear(recordID: recordID, selections: initialParticipantSelections)
        .onAppear {
            onSetupConsumed?()
            typographySession.reload()
            registerSync()
            appearance = .current(styleID: typographySession.styleID)
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn

            revealImmersiveChrome()
            if state.usesRackRules,
               !UserDefaults.standard.bool(forKey: "nineBall14710BreakerIntroSeen") {
                showBreakerIntro = true
            }
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current(styleID: typographySession.styleID)
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: showMenu) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: activeChasePlayer) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: pendingTransfer) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showBreakerPicker) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showBreakerIntro) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: typographySession.effectivePreference) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: showEditPanel) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: state.finished) { _, finished in
            if finished {
                showGameOverDialog = true

            }
        }
        .onChange(of: state) { _, newState in
            if let pendingTransfer, !pendingTransfer.context.matches(newState) {
                self.pendingTransfer = nil
                showNineBallRetryToast()
            }
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()

        }
        .onChange(of: sessionStore.persistenceFailureSignal) { _, signal in
            if signal > 0 {
                showNineBallToast(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
            }
        }

        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()

            sessionStore.flush {
                _ = saveRecord()
            }
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
    }



    private var finishedWinnerName: String {
        let active = Array(state.playerPoints.prefix(state.playerCount))
        guard let best = active.max(), active.filter({ $0 == best }).count == 1,
              let index = active.firstIndex(of: best) else { return "" }
        return playerName(index)
    }

    private func logicalPlayer(forScreenIndex screenIndex: Int) -> Int {
        nineBallLogicalPlayerIndex(
            forScreenIndex: screenIndex,
            playerCount: state.playerCount,
            sidesSwapped: state.sidesSwapped
        )
    }

    private func playerBackground(_ screenIndex: Int) -> Color {
        let identityIndex = state.playerCount == 2 ? logicalPlayer(forScreenIndex: screenIndex) : screenIndex
        return switch identityIndex {
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
                            textColor: appearance.palette.control,
                            accessibilityIdentifier: "nine_ball_player_\(player)_name_editor"
                        )
                    } else {
                        HStack(spacing: compact ? 6 : 8) {
                            if state.usesRackRules {
                                Image("ic_snooker_cue")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
                                    .opacity(player == state.breakerPlayer ? 1 : 0)
                                    .accessibilityHidden(true)
                            }
                            Text(playerName(player))
                                .minimumScaleFactor(0.6)
                        }
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

                if !showEditPanel && !showDisplaySettings {
                    // 安卓 NineBallScoreScreen ChaseStatGrid（edgeToEdge 横排 3-4 人）：
                    // 3 列 × 2 行、1pt 缝隙、白 11% 直角格、标签 13pt/白 78%、数值 16pt Bold。
                    VStack(spacing: 1) {
                        chaseStatRow(player: player, kinds: Array(state.scoringKinds.prefix((state.scoringKinds.count + 1) / 2)))
                        chaseStatRow(player: player, kinds: Array(state.scoringKinds.dropFirst((state.scoringKinds.count + 1) / 2)))
                    }
                    // Statistics extend to the panel bottom; floating controls do not reserve a footer.
                    .padding(.bottom, 4)
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
            VibrationManager.shared.vibrateLight()
            activeChasePlayer = player
        }
        .accessibilityIdentifier("nine_ball_player_\(player)_tile")
        .accessibilityValue(state.usesRackRules && player == state.breakerPlayer
            ? NSLocalizedString("nine_ball_current_breaker", value: "本局开球人", comment: "") : "")
    }

    private func chaseStatRow(player: Int, kinds: [NineBallChaseKind]) -> some View {
        HStack(spacing: 1) {
            ForEach(kinds, id: \.self) { kind in
                let index = NineBallChaseKind.allCases.firstIndex(of: kind) ?? 0
                VStack(spacing: 0) {
                    Text(chaseTitle(kind))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(state.playerCounts[player][index])")
                        .font(typographySession.effectivePreference.font.swiftUIFont(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
                .background(.white.opacity(0.11))
                .accessibilityIdentifier("nine_ball_player_\(player)_count_\(kind.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func nineBallScoreContent(player: Int, scoreText: String, displayedScoreSize: CGFloat) -> some View {
        if showEditPanel {
            HStack(spacing: 12) {
                Button {
                    VibrationManager.shared.vibrateLight()
                    adjustEditingScore(player: player, delta: -1)
                } label: {
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
                Button {
                    VibrationManager.shared.vibrateLight()
                    adjustEditingScore(player: player, delta: 1)
                } label: {
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
                padPreferredWidth: 480
            )

            ZStack {
                Theme.scoreboardDialogScrim
                    .ignoresSafeArea()
                    .onTapGesture { activeChasePlayer = nil }

                AdaptiveSetupDialogLayout(maxHeight: max(150, proxy.size.height - 32)) {
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
                } content: { maxContentHeight in
                    AdaptiveSetupDialogScrollView(maxHeight: maxContentHeight, bottomClearance: 0) {
                        VStack(spacing: 10) {
                            ForEach(nineBallActionRows.indices, id: \.self) { rowIndex in
                                HStack(spacing: 10) {
                                    ForEach(nineBallActionRows[rowIndex], id: \.self) { kind in
                                        nineBallActionButton(kind, player: player)
                                    }
                                }
                            }
                            if state.scoringKinds.contains(.handoff) {
                                Button {
                                    beginChaseEvent(.handoff, player: player)
                                } label: {
                                    Label(chaseTitle(.handoff), systemImage: "arrow.left.arrow.right")
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .foregroundStyle(.white)
                                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                                }
                                .buttonStyle(.plain)
                                .disabled(scoringLocked || state.finished)
                                .accessibilityIdentifier("nine_ball_action_handoff")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                } actions: {
                    if state.usesRackRules {
                        Button {
                            activeChasePlayer = nil
                            showRules = true
                        } label: {
                            Text(nineBallText("nine_ball_rules_help", "Format guide"))
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("nine_ball_board_help")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
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
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("nine_ball_action_dialog")
            }
        }
    }

    private func nineBallActionButton(_ kind: NineBallChaseKind, player: Int) -> some View {
        Button {
            VibrationManager.shared.vibrateLight()
            beginChaseEvent(kind, player: player)
        } label: {
            VStack(spacing: 0) {
                Text(chaseTitle(kind))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(nineBallActionBandColor(kind))
                Text(ScoreAdditionTypography.attributedLabel(
                    chasePointDescription(kind, player: player),
                    numberFontSize: 16
                ))
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(nineBallActionBackground(kind))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(scoringLocked || state.finished || isChaseEventUnavailable(kind, player: player))
        .opacity(isChaseEventUnavailable(kind, player: player) ? 0.4 : 1)
        .accessibilityHint(isChaseEventUnavailable(kind, player: player)
            ? NSLocalizedString("nine_ball_correct_breaker_hint", value: "请更正本局开球人", comment: "") : "")
        .accessibilityIdentifier("nine_ball_action_\(kind.rawValue)")
    }

    private func nineBallDialog<Content: View>(
        title: String,
        identifier: String,
        onClose: (() -> Void)?,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        nineBallDialog(title: title, identifier: identifier, onClose: onClose, content: content) {
            EmptyView()
        }
    }

    private func nineBallDialog<Content: View, Actions: View>(
        title: String,
        identifier: String,
        onClose: (() -> Void)?,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        GeometryReader { proxy in
            let width = Theme.dialogWidth(availableWidth: proxy.size.width, phonePreferredWidth: 400, padPreferredWidth: 480)
            ZStack {
                Theme.scoreboardDialogScrim
                    .ignoresSafeArea()
                    .onTapGesture { onClose?() }
                AdaptiveSetupDialogLayout(maxHeight: max(150, proxy.size.height - 32)) {
                    ZStack {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, onClose == nil ? 18 : 48)
                        if let onClose {
                            HStack {
                                Spacer()
                                ScoreboardDialogCloseButton(action: onClose, accessibilityIdentifier: "\(identifier)_close")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 52)
                } content: { maxContentHeight in
                    AdaptiveSetupDialogScrollView(maxHeight: maxContentHeight, bottomClearance: 0) {
                        content().padding(.horizontal, 18).padding(.bottom, 17)
                    }
                } actions: {
                    actions()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)
                .background(Theme.scoreboardDialogSurface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .onTapGesture { }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier)
            }
        }
    }

    private var nineBallBreakerIntro: some View {
        nineBallDialog(
            title: String.localizedStringWithFormat(NSLocalizedString(
                "nine_ball_breaker_intro_title", value: "第 %1$d 局 · %2$@开球", comment: ""
            ), state.roundNumber, playerName(state.breakerPlayer)),
            identifier: "nine_ball_breaker_intro",
            onClose: nil
        ) {
            VStack(spacing: 16) {
                Image("ic_snooker_cue")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text(NSLocalizedString("nine_ball_breaker_intro_message", value: "球杆标记表示本局开球人，不代表当前击球人。", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            nineBallPrimaryButton(NSLocalizedString("got_it", value: "知道了", comment: "")) {
                UserDefaults.standard.set(true, forKey: "nineBall14710BreakerIntroSeen")
                showBreakerIntro = false
            }
            .accessibilityIdentifier("nine_ball_breaker_intro_ack")
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 17)
        }
    }

    private var nineBallBreakerDialog: some View {
        nineBallDialog(
            title: NSLocalizedString("nine_ball_current_breaker", value: "本局开球人", comment: ""),
            identifier: "nine_ball_breaker_dialog",
            onClose: { showBreakerPicker = false }
        ) {
            VStack(spacing: 8) {
                ForEach(0..<state.playerCount, id: \.self) { player in
                    Button {
                        send(.setBreaker(player: player))
                        showBreakerPicker = false
                    } label: {
                        HStack {
                            Text(playerName(player))
                            Spacer()
                            if player == state.breakerPlayer { Image(systemName: "checkmark") }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(player == state.breakerPlayer ? Color(hex: "83DA98") : .white)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("nine_ball_breaker_\(player)")
                }
            }
        }
    }

    private func nineBallTransferDialog(_ pending: NineBallPendingTransfer) -> some View {
        let preview = NineBallChaseReducer().reduce(state: state, intent: pending.intent, at: 0)
        let deltas = (0..<state.playerCount).map { preview.state.playerPoints[$0] - state.playerPoints[$0] }
        let singleSmall = pending.kind == .smallGold && !state.config.smallGoldAllPay
        return nineBallDialog(
            title: "\(playerName(pending.player)) · \(chaseTitle(pending.kind))",
            identifier: "nine_ball_transfer_dialog",
            onClose: { pendingTransfer = nil }
        ) {
            VStack(spacing: 10) {
                if pending.kind == .normalWin {
                    nineBallReviewLabel(NSLocalizedString("nine_ball_payer", value: "付分人", comment: ""))
                    nineBallPlayerOptions(pending, continuing: false)
                } else if singleSmall {
                    nineBallReviewLabel(NSLocalizedString("nine_ball_breaker_pays", value: "开球人付分", comment: ""))
                    HStack(spacing: 7) {
                        Text(playerName(pending.payer ?? state.breakerPlayer))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if preview.accepted {
                            Text("−\(state.config.smallGold)").foregroundStyle(Color(hex: "F09892"))
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.right").accessibilityHidden(true)
                            Spacer(minLength: 4)
                            Text(playerName(pending.player))
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text("+\(state.config.smallGold)").foregroundStyle(Color(hex: "83DA98"))
                        } else {
                            Spacer()
                        }
                        Button(NSLocalizedString("nine_ball_correct", value: "更正", comment: "")) {
                            correctingSmallGoldPayer.toggle()
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "83DA98"))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    if correctingSmallGoldPayer || !preview.accepted {
                        nineBallPlayerOptions(pending, continuing: false)
                    }
                } else if pending.kind == .handoff {
                    nineBallReviewLabel(NSLocalizedString("nine_ball_continue_player", value: "继续击球", comment: ""))
                    nineBallPlayerOptions(pending, continuing: true)
                }

                if !preview.accepted {
                    Text(NSLocalizedString("nine_ball_correct_breaker_hint", value: "请更正本局开球人", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "F09892"))
                } else if !singleSmall && pending.kind != .handoff {
                    HStack(spacing: 8) {
                        ForEach((0..<state.playerCount).filter { deltas[$0] != 0 }, id: \.self) { player in
                            VStack(spacing: 5) {
                                Text(playerName(player))
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(signedChaseDelta(deltas[player]))
                                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(deltas[player] > 0 ? Color(hex: "83DA98") : Color(hex: "F09892"))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 49)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }

                if preview.accepted && pending.kind.endsRack {
                    HStack {
                        Text(NSLocalizedString("nine_ball_next_breaker", value: "下局开球", comment: ""))
                            .foregroundStyle(Color.white.opacity(0.65))
                        Spacer()
                        Text(playerName(preview.state.breakerPlayer)).foregroundStyle(.white)
                    }
                    .font(.system(size: 12))
                    .padding(11)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
                nineBallPrimaryButton(String.localizedStringWithFormat(
                    NSLocalizedString("nine_ball_confirm_event_format", value: "确认%@", comment: ""), chaseTitle(pending.kind)
                )) {
                    let latest = NineBallChaseReducer().reduce(state: state, intent: pending.intent, at: 0)
                    guard latest.accepted else { return }
                    pendingTransfer = nil
                    send(pending.intent, expectedContext: pending.context)
                }
                .disabled(!preview.accepted)
                .opacity(preview.accepted ? 1 : 0.4)
                .accessibilityIdentifier("nine_ball_transfer_confirm")
                Button(NSLocalizedString("back", value: "返回", comment: "")) {
                    pendingTransfer = nil
                    activeChasePlayer = pending.player
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(minHeight: 26)
                .buttonStyle(.plain)
            }
        }
    }

    private func nineBallReviewLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nineBallPlayerOptions(_ pending: NineBallPendingTransfer, continuing: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach((0..<state.playerCount).filter { $0 != pending.player }, id: \.self) { player in
                let selected = (continuing ? pending.continuePlayer : pending.payer) == player
                Button {
                    if continuing { pendingTransfer?.continuePlayer = player }
                    else { pendingTransfer?.payer = player }
                } label: {
                    HStack(spacing: 4) {
                        Text(playerName(player)).lineLimit(1).minimumScaleFactor(0.6)
                        if selected { Image(systemName: "checkmark").font(.system(size: 10)) }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color(hex: "83DA98") : .white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.white.opacity(selected ? 0.13 : 0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Color(hex: "83DA98") : Color.white.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nine_ball_\(continuing ? "continue" : "payer")_\(player)")
            }
        }
    }

    private func nineBallPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textOnPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.primary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func signedChaseDelta(_ value: Int) -> String {
        value > 0 ? "+\(value)" : value < 0 ? "−\(-value)" : "0"
    }

    private func nineBallActionBackground(_ kind: NineBallChaseKind) -> Color {
        switch kind {
        case .normalWin:
            Color(hex: "30D158").opacity(0.45)
        case .foul:
            Color(hex: "D64F4F").opacity(0.45)
        default:
            Color.white.opacity(0.26)
        }
    }

    private func nineBallActionBandColor(_ kind: NineBallChaseKind) -> Color {
        switch kind {
        case .normalWin:
            Color(hex: "30D158").opacity(0.75)
        case .foul:
            Color(hex: "D64F4F").opacity(0.75)
        default:
            Color.white.opacity(0.42)
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
        case .handoff: return NSLocalizedString("nine_ball_no_score", value: "不计分", comment: "")
        }
        if state.isTournament {
            if kind == .foul {
                let points = state.rackFouls[player] == 2 ? state.config.thirdFoul : state.config.foul
                return String.localizedStringWithFormat(nineBallText("nine_ball_foul_opponent_points", "Opponent +%d"), points)
                    + (state.rackFouls[player] == 2 ? " · " + nineBallText("nine_ball_third_foul", "Third-foul loss") : "")
            }
            return "+\(value)"
        }
        if state.usesRackRules {
            if kind == .foul {
                return String.localizedStringWithFormat(NSLocalizedString(
                    state.playerCount == 2 ? "nine_ball_foul_transfer_opponent_format" : "nine_ball_foul_transfer_next_format",
                    value: state.playerCount == 2 ? "本人 −%1$d  对手 +%1$d" : "本人 −%1$d  下家 +%1$d",
                    comment: ""
                ), value)
            }
            let total = kind == .bigGold || kind == .goldenNine || (kind == .smallGold && state.config.smallGoldAllPay)
                ? value * (state.playerCount - 1) : value
            return "+\(total)"
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
        case .handoff: NSLocalizedString("nine_ball_handoff", value: "让杆", comment: "")
        }
    }

    private func isChaseEventUnavailable(_ kind: NineBallChaseKind, player: Int) -> Bool {
        guard state.usesRackRules else { return false }
        if kind == .bigGold { return player != state.breakerPlayer }
        if state.isTournament { return !state.scoringKinds.contains(kind) }
        return kind == .smallGold && state.playerCount == 2 && !state.config.smallGoldAllPay && player == state.breakerPlayer
    }

    private func beginChaseEvent(_ kind: NineBallChaseKind, player: Int) {
        guard !scoringLocked, !state.finished, !isChaseEventUnavailable(kind, player: player) else { return }
        if state.ruleVersion == 1 {
            send(.chaseEvent(player: player, kind: kind))
            activeChasePlayer = nil
            return
        }
        if state.isTournament {
            activeChasePlayer = nil
            send(.tournamentEvent(player: player, kind: kind), expectedContext: NineBallTransferContext(state: state))
            return
        }
        let pending = NineBallPendingTransfer(
            player: player,
            kind: kind,
            context: NineBallTransferContext(state: state),
            payer: kind == .smallGold && !state.config.smallGoldAllPay ? state.breakerPlayer
                : kind == .normalWin ? (player + state.playerCount - 1) % state.playerCount : nil,
            continuePlayer: kind == .handoff ? (player + state.playerCount - 1) % state.playerCount : nil
        )
        activeChasePlayer = nil
        if state.playerCount == 2 || kind == .foul {
            let preview = NineBallChaseReducer().reduce(state: state, intent: pending.intent, at: 0)
            guard preview.accepted else {
                showNineBallToast(NSLocalizedString("nine_ball_correct_breaker_hint", value: "请更正本局开球人", comment: ""))
                return
            }
            send(pending.intent, expectedContext: pending.context)
        } else {
            correctingSmallGoldPayer = kind == .smallGold && pending.payer == player
            pendingTransfer = pending
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
        editPlayerScores[player] = String(min(9_999, max(state.isTournament ? 0 : -9_999, current + delta)))
    }

    private func applyPlayerEdits() {
        guard !scoringLocked else {
            showEditPanel = false
            return
        }
        if state.isTournament && editPlayerScores.prefix(state.playerCount).contains(where: { Int($0).map { $0 < 0 } ?? true }) {
            showNineBallToast(nineBallText("nine_ball_nonnegative", "Tournament scores must be nonnegative integers."))
            return
        }
        let names = (0..<state.playerCount).map { index in
            let candidate = editPlayerNames[safe: index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return candidate.isEmpty ? playerName(index) : candidate
        }
        let scores = (0..<state.playerCount).map { index in
            min(9_999, max(-9_999, Int(editPlayerScores[safe: index] ?? "") ?? state.playerPoints[index]))
        }
        if !state.isTournament && state.usesRackRules && scores.reduce(0, +) != 0 {
            showNineBallToast(nineBallText("nine_ball_unbalanced_edit", "The edited scores do not total zero."))
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
    private func send(_ intent: NineBallChaseIntent, expectedContext: NineBallTransferContext? = nil) {
        guard !scoringLocked else { return }
        let transferContext: NineBallTransferContext?
        switch intent {
        case .chaseTransfer, .tournamentEvent: transferContext = expectedContext ?? NineBallTransferContext(state: state)
        default: transferContext = nil
        }
        sessionStore.sendDerived(
            { reservedState in
                guard let transferContext else { return intent }
                guard let validated = transferContext.validatedIntent(intent, in: reservedState) else {
                    pendingTransfer = nil
                    activeChasePlayer = nil
                    showNineBallRetryToast()
                    return nil
                }
                return validated
            },
            completion: { intent, _, next, events in
                actionCount += 1
                actionLog.append(ReducerScoreboardRecordPersistence.snapshot(code: String(describing: intent), scores: next.playerPoints))
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
                    case .chaseTransferred(let player, let kind, let deltas, let payer, let continuePlayer, let roundBefore, let breakerBefore, let nextBreaker):
                        var payload: [String: Any] = [
                            "ruleVersion": next.ruleVersion, "actor": player, "deltas": deltas,
                            "roundNumber": roundBefore, "breakerBefore": breakerBefore,
                            "nextBreaker": nextBreaker
                        ]
                        if let payer { payload["payer"] = payer }
                        if let continuePlayer { payload["continuePlayer"] = continuePlayer }
                        let payloadString = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
                            .flatMap { String(data: $0, encoding: .utf8) }
                        let summary: String
                        if kind == .handoff, let continuePlayer {
                            summary = String.localizedStringWithFormat(
                                NSLocalizedString("nine_ball_handoff_summary_format", value: "%1$@让杆，%2$@继续击球", comment: ""),
                                playerName(player), playerName(continuePlayer)
                            )
                        } else {
                            let changes = (0..<next.playerCount).filter { deltas[$0] != 0 }
                                .map { "\(playerName($0)) \(signedChaseDelta(deltas[$0]))" }.joined(separator: " · ")
                            let third = next.isTournament && kind == .foul && next.roundNumber > roundBefore
                            let label = third ? nineBallText("nine_ball_third_foul", "Third-foul loss") : chaseTitle(kind)
                            summary = "\(playerName(player)) · \(label)：\(changes)"
                        }
                        detailedActions.append(nineBallDetailedAction(
                            type: kind == .foul ? .foul : (kind == .handoff ? .stateChanged : .scoreChanged),
                            team: RecordTeam.allCases.indices.contains(player) ? RecordTeam.allCases[player] : nil,
                            delta: deltas[player], code: "nine_ball_\(next.isTournament ? "tournament" : "transfer")_\(kind.rawValue)",
                            roundNumber: roundBefore, payload: payloadString, summary: summary
                        ))
                        showNineBallToast(summary)
                    case .breakerChanged(let player):
                        let summary = String.localizedStringWithFormat(
                            NSLocalizedString("nine_ball_breaker_changed_format", value: "本局改为%@开球", comment: ""), playerName(player)
                        )
                        detailedActions.append(nineBallDetailedAction(
                            type: .stateChanged, code: "nine_ball_breaker_changed",
                            roundNumber: next.roundNumber, summary: summary
                        ))
                        showNineBallToast(summary)
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
                persistRecordContext()
            },
            afterFinalized: { _, _, next, _ in
                if next.finished { _ = saveRecord() }
            }
        )
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
        return NineBallUndoPolicy.performIfAllowed(
            finished: state.finished,
            gameOverPresented: showGameOverDialog
        ) {
            sessionStore.undo { success, restored in
                guard success else { return }
                actionLog = sessionStore.recordContext.actionLog
                detailedActions = sessionStore.recordContext.detailedActions
                actionCount = sessionStore.recordContext.actionCount
                showGameOverDialog = restored.finished
            }
        }
    }

    private func nineBallDetailedAction(
        type: DetailedScoreActionType,
        team: RecordTeam? = nil,
        delta: Int? = nil,
        code: String,
        roundNumber: Int? = nil,
        payload: String? = nil,
        summary: String? = nil
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
            epochMilliseconds: ReducerScoreboardRecordPersistence.nowMilliseconds(),
            team: team,
            scores: Array(state.playerPoints.prefix(state.playerCount)),
            roundNumber: roundNumber,
            scoreChange: delta,
            participants: participants,
            operationCode: code,
            operationPayload: payload,
            summary: summary
        )
    }

    private func persistRecordContext() {
        sessionStore.updateRecordContext(
            actionLog: actionLog,
            detailedActions: detailedActions,
            actionCount: actionCount
        )
    }
    private func showNineBallToast(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showToast = false }
    }
    private func showNineBallRetryToast() {
        showNineBallToast(NSLocalizedString("nine_ball_state_changed_retry", value: "对局已更新，请重新选择", comment: ""))
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
              !hasChaseDialog else { return }
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
                  !hasChaseDialog else { return }
            if let exitConfirmDeadline, Date() <= exitConfirmDeadline { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu
            || showDisplaySettings
            || showEditPanel
            || hasChaseDialog
            || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }

    private func exit() {
        sessionStore.flush {
            _ = saveRecord()
            performScoreboardExit(
                onNavigationBack: onNavigationBack,
                dismiss: dismiss
            )
        }
    }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: showEditPanel || hasChaseDialog,
                finished: state.finished,
                scoringLocked: scoringLocked
            ) else { return }
            switch intent {
            case .addLeft: beginChaseEvent(.normalWin, player: logicalPlayer(forScreenIndex: 0))
            case .addRight: beginChaseEvent(.normalWin, player: logicalPlayer(forScreenIndex: 1))
            case .subtractLeft, .subtractRight, .undo: _ = undo()
            case .exchangeSides: send(.exchangeSides)
            case .requestSnapshot: break
            }
        }
    }








    private func startNewMatch() {
        let previousIdentityRecord = recordID
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
            // Existing values can be explicit custom choices, including the old default of 8.
            let freshConfig = state.config
            let freshState = NineBallChaseState.initial(
                config: freshConfig,
                playerCount: state.playerCount,
                playerNames: activeNames,
                ruleVersion: 3,
                breakerPlayer: state.initialBreakerPlayer
            )
            let freshStore = BilliardsSessionStore(
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
                // 再来一局沿用原座位的人员绑定，否则新记录无法归到“我”名下，
                // “我的记录”会漏掉这一场（与台球/斗地主/射箭/拳击/多人计分一致）。
                ParticipantIdentityStore.shared.copySelections(from: previousIdentityRecord, to: newRecordID)
                playerNames = Array((activeNames + Array(repeating: "", count: 4)).prefix(4))
                actionCount = 0
                actionLog.removeAll()
                detailedActions.removeAll()
                editPlayerNames.removeAll()
                editPlayerScores.removeAll()
                activeChasePlayer = nil
                pendingTransfer = nil
                correctingSmallGoldPayer = false
                showBreakerPicker = false
                showBreakerIntro = !UserDefaults.standard.bool(forKey: "nineBall14710BreakerIntroSeen")
                showEditPanel = false
                manualFinishRequested = false
                showGameOverDialog = false
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()

            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        let leftPlayer = state.playerCount == 2 ? logicalPlayer(forScreenIndex: 0) : 0
        let rightPlayer = state.playerCount == 2 ? logicalPlayer(forScreenIndex: 1) : 1
        var compact = LocalScoreboardDisplayState(
            gameID: GameType.nineBall.canonicalScoreboardIdentifier,
            title: "",
            leftName: playerName(leftPlayer),
            rightName: playerName(rightPlayer),
            leftScore: "\(state.playerPoints[leftPlayer])",
            rightScore: "\(state.playerPoints[rightPlayer])",
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
        let displayPlayers = (0..<state.playerCount).map { index in
            ScoreboardDisplayPlayer(
                id: "player_\(index)",
                name: playerName(index),
                score: state.playerPoints[index],
                order: index
            )
        }
        compact.externalState = ScoreboardDisplayState.enriched(
            compact: compact,
            layoutKind: state.playerCount > 2 ? .multiGrid : .twoSide,
            orientation: .landscape,
            players: state.playerCount > 2 ? displayPlayers : nil,
            sportState: [
                "chaseRuleVersion": .integer(state.ruleVersion),
                "chaseRoundNumber": .integer(state.roundNumber),
                "chaseBreakerPlayer": .integer(state.breakerPlayer),
                "chasePlayerPoints": .integers(state.playerPoints),
                "chaseSmallGoldAllPay": .boolean(state.config.smallGoldAllPay),
                "chaseGoldRetainsBreak": .boolean(state.config.goldRetainsBreak),
                "chaseRuleFamily": .string(state.config.ruleFamily.rawValue),
                "chasePointScheme": .string(state.config.pointScheme.rawValue),
                "chaseBreakRule": .string(state.config.breakRule.rawValue),
                "chaseHandoffEnabled": .boolean(state.config.handoffEnabled),
                "chaseTotalRacks": .integer(state.config.totalRacks),
                "chaseRackFouls": .integers(state.rackFouls),
                "chasePlayerCount": .integer(state.playerCount),
                "chasePlayerNames": .strings((0..<state.playerCount).map(playerName)),
                "chasePoints": .integerMap([
                    "big_gold": state.config.bigGold,
                    "small_gold": state.config.smallGold,
                    "golden_nine": state.config.goldenNine,
                    "normal_win": state.config.normalWin,
                    "ball_in_hand": state.config.ballInHand,
                    "foul": state.config.foul,
                    "third_foul": state.config.thirdFoul
                ]),
                // 对齐安卓 NineBallScoreScreen：playerCounts 按逻辑玩家顺序，left/right 为 2 人局回退。
                "chasePlayerCounts": .integersArrays(state.playerCounts),
                "chaseLeftCounts": .integers(state.playerCounts.indices.contains(0) ? state.playerCounts[0] : []),
                "chaseRightCounts": .integers(state.playerCounts.indices.contains(1) ? state.playerCounts[1] : []),
                "multiGridColumns": .integer(state.playerCount > 2 ? state.playerCount : 2)
            ]
        )
        if let currentShooter = state.currentShooter {
            compact.externalState?.sportState?["chaseCurrentShooter"] = .integer(currentShooter)
        }
        if state.playerCount > 2 {
            compact.externalState?.teams = displayPlayers.map {
                ScoreboardDisplayTeam(id: $0.id, name: $0.name, score: $0.score ?? 0, order: $0.order)
            }
            if state.finished, let best = state.playerPoints.prefix(state.playerCount).max() {
                let winners = (0..<state.playerCount).filter { state.playerPoints[$0] == best }
                compact.externalState?.result = ScoreboardDisplayResult(
                    ended: true,
                    winnerID: winners.count == 1 ? "player_\(winners[0])" : "draw"
                )
            }
        }
        let multipliers = compact.externalState?.appearance.fontSizeMultipliers
        compact.externalState?.appearance = .init(
            snapshot: appearance,
            fontCode: typographySession.effectivePreference.font.rawValue
        )
        compact.externalState?.appearance.fontSizeMultipliers = multipliers
        return compact
    }
    @discardableResult
    private func saveRecord() -> Bool {
        if state.finished, sessionStore.hasCommittedFinishedRecord {
            return true
        }
        let activePlayers: [[String: Any]] = (0..<state.playerCount).map { index in
            ["name": playerName(index), "finalScore": state.playerPoints[index]]
        }
        let winnerIdentity: ScoreboardWinnerIdentity? = {
            guard state.finished,
                  let highestScore = state.playerPoints.prefix(state.playerCount).max() else {
                return nil
            }
            let leaders = (0..<state.playerCount).filter {
                state.playerPoints[$0] == highestScore
            }
            return leaders.count == 1 ? .participant(index: leaders[0]) : nil
        }()
        let success = ReducerScoreboardRecordPersistence.saveRecord(
            id: recordID, gameType: .nineBall, startedAt: startedAt,
            leftName: playerName(0), rightName: playerName(1),
            left: state.playerPoints[0], right: state.playerPoints[1],
            winnerIdentity: winnerIdentity,
            actionCount: actionCount, actions: actionLog, detailedActions: detailedActions, undoStates: sessionStore.undoStates, finished: state.finished, snapshot: state,
            sessionSnapshotData: sessionStore.encodedResumeBundle,
            extra: [
                "playerNames": Array(playerNames.prefix(state.playerCount)),
                "players": activePlayers,
                "chaseRuleVersion": state.ruleVersion,
                "chaseRoundNumber": state.roundNumber,
                "chaseBreakerPlayer": state.breakerPlayer,
                "chaseCurrentShooter": state.currentShooter as Any,
                "chasePlayerPoints": state.playerPoints,
                "chaseSmallGoldAllPay": state.config.smallGoldAllPay,
                "chaseGoldRetainsBreak": state.config.goldRetainsBreak,
                "chaseRuleFamily": state.config.ruleFamily.rawValue,
                "chaseRackFouls": state.rackFouls
            ],
            projectConfiguration: [
                "playerCount": state.playerCount,
                "nineBallBigGold": state.config.bigGold,
                "nineBallSmallGold": state.config.smallGold,
                "nineBallGoldenNine": state.config.goldenNine,
                "nineBallNormalWin": state.config.normalWin,
                "nineBallBallInHand": state.config.ballInHand,
                "nineBallFoul": state.config.foul,
                "nineBallRuleVersion": state.ruleVersion,
                "nineBallRoundNumber": state.roundNumber,
                "nineBallBreakerPlayer": state.breakerPlayer,
                "nineBallSmallGoldAllPay": state.config.smallGoldAllPay,
                "nineBallGoldRetainsBreak": state.config.goldRetainsBreak,
                "nineBallRuleFamily": state.config.ruleFamily.rawValue,
                "nineBallPointScheme": state.config.pointScheme.rawValue,
                "nineBallHandoffEnabled": state.config.handoffEnabled,
                "nineBallThirdFoul": state.config.thirdFoul,
                "nineBallBreakRule": state.config.breakRule.rawValue,
                "nineBallTotalRacks": state.config.totalRacks
            ],
            finishedSessionId: sessionStore.sessionId,
            finishedCommitCoordinator: sessionStore.finishedCommitCoordinator,
            replaceCommittedFinishedRecord: sessionStore.shouldReplaceCommittedFinishedRecord
        )
        if success, state.finished, actionCount > 0 {
            sessionStore.markFinishedRecordCommitted()
        }
        if !success {
            showNineBallToast(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
        }
        return success
    }
}


private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
