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

struct NineBallChaseScoreboardView: View {
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
    @State private var manualFinishRequested = false
    @State private var isStartingNewMatch = false

    private var scoringLocked: Bool {
        false
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode
            || chromeVisible
            || showDisplaySettings
            || showMenu
            || showEditPanel
            || activeChasePlayer != nil
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
            extraItems: []
        )
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
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        .animation(.easeInOut(duration: 0.2), value: showToast)
        .animation(.easeInOut(duration: 0.2), value: activeChasePlayer)
        .ignoresSafeArea(.all)
        .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
            guard !showEditPanel, activeChasePlayer == nil else { return }
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
            appearance = .current(styleID: typographySession.styleID)
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn

            revealImmersiveChrome()
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

                if !showEditPanel && !showDisplaySettings {
                    // 安卓 NineBallScoreScreen ChaseStatGrid（edgeToEdge 横排 3-4 人）：
                    // 3 列 × 2 行、1pt 缝隙、白 11% 直角格、标签 13pt/白 78%、数值 16pt Bold。
                    VStack(spacing: 1) {
                        chaseStatRow(player: player, kinds: Array(NineBallChaseKind.allCases.prefix(3)))
                        chaseStatRow(player: player, kinds: Array(NineBallChaseKind.allCases.suffix(3)))
                    }
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

                                VibrationManager.shared.vibrateLight()
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
        sessionStore.send(
            intent,
            completion: { _, next, events in
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
            afterFinalized: { _, next, _ in
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
            epochMilliseconds: ReducerScoreboardRecordPersistence.nowMilliseconds(),
            team: team,
            scores: Array(state.playerPoints.prefix(state.playerCount)),
            scoreChange: delta,
            participants: participants,
            operationCode: code
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
        OrientationLock.shared.unlock()

        sessionStore.flush {
            _ = saveRecord()
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
            case .addLeft: send(.chaseEvent(player: logicalPlayer(forScreenIndex: 0), kind: .normalWin))
            case .addRight: send(.chaseEvent(player: logicalPlayer(forScreenIndex: 1), kind: .normalWin))
            case .subtractLeft, .subtractRight, .undo: _ = undo()
            case .exchangeSides: send(.exchangeSides)
            case .requestSnapshot: break
            }
        }
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
                "chasePlayerCount": .integer(state.playerCount),
                // 对齐安卓 NineBallScoreScreen：playerCounts 按逻辑玩家顺序，left/right 为 2 人局回退。
                "chasePlayerCounts": .integersArrays(state.playerCounts),
                "chaseLeftCounts": .integers(state.playerCounts.indices.contains(0) ? state.playerCounts[0] : []),
                "chaseRightCounts": .integers(state.playerCounts.indices.contains(1) ? state.playerCounts[1] : []),
                "multiGridColumns": .integer(state.playerCount > 2 ? state.playerCount : 2)
            ]
        )
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
