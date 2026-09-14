import ScoreCore
import SessionCore
import SwiftUI

func decodeRallyStateSnapshot(_ data: Data) -> RallyMatchState? {
    let decoder = JSONDecoder()
    return (try? decoder.decode(RallyMatchState.self, from: data))
        ?? (try? decoder.decode(ScoreSession<RallyMatchState, RallyMatchEvent>.self, from: data))?.state
        ?? (try? decoder.decode(
            ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self,
            from: data
        ))?.currentSession.state
}

enum RallyFinishedScorePresentation {
    static func scores(for state: RallyMatchState) -> (left: Int, right: Int) {
        if state.rules.maxSets == 1 {
            return (state.leftPoints, state.rightPoints)
        }
        if state.leftSets > 0 || state.rightSets > 0 {
            return (state.leftSets, state.rightSets)
        }
        return (state.leftPoints, state.rightPoints)
    }

    static func winnerSide(for state: RallyMatchState) -> MatchSide? {
        if let forfeitingSide = state.pingPongForfeitSide {
            return forfeitingSide.opposite
        }
        guard state.leftSets != state.rightSets else { return nil }
        return state.leftSets > state.rightSets ? .left : .right
    }
}

/// Resolves a controller-side subtract action through the current screen layout,
/// then validates the score that belongs to that logical team.
func rallyLocalSubtractSide(
    onScreen screenSide: MatchSide,
    state: RallyMatchState,
    presentedSidesSwapped: Bool? = nil
) -> MatchSide? {
    guard !state.finished else { return nil }
    let logicalSide = TeamScreenLayout(
        sidesSwapped: presentedSidesSwapped ?? state.sidesSwapped
    ).engineSide(onScreen: screenSide)
    guard RallyMatchEngine.score(for: logicalSide, in: state) > 0 else { return nil }
    return logicalSide
}

private struct RallyTerminalSetPresentation: Equatable {
    let leftPoints: Int
    let rightPoints: Int
    let leftSets: Int
    let rightSets: Int
    let sidesSwapped: Bool
}

enum RallyDoublesFlashResolver {
    static func slots(
        previous: RallyDoublesState?,
        current: RallyDoublesState?
    ) -> Set<Int> {
        guard let previous, let current else { return [] }

        var rotatedSlots: Set<Int> = []
        switch (previous.rotation, current.rotation) {
        case let (.badminton(before), .badminton(after)):
            if before.team0CourtOrderSwapped != after.team0CourtOrderSwapped {
                rotatedSlots.formUnion([0, 2])
            }
            if before.team1CourtOrderSwapped != after.team1CourtOrderSwapped {
                rotatedSlots.formUnion([1, 3])
            }
        case let (.pickleball(before), .pickleball(after)):
            if before.team0PartnersSwapped != after.team0PartnersSwapped {
                rotatedSlots.formUnion([0, 2])
            }
            if before.team1PartnersSwapped != after.team1PartnersSwapped {
                rotatedSlots.formUnion([1, 3])
            }
        default:
            return []
        }

        if !rotatedSlots.isEmpty { return rotatedSlots }
        guard previous.serverSlotIndex != current.serverSlotIndex else { return [] }
        return [current.serverSlotIndex]
    }
}
import UIKit

struct TableTennisAdministrativeMarkerStatus: Equatable {
    let timeoutUsed: Bool
    let hasYellowCard: Bool
    let redCardCount: Int
}

enum TableTennisAdministrativeMarkerPolicy {
    static func displayedRedCardCount(_ count: Int) -> Int {
        min(2, max(0, count))
    }
}

struct TableTennisAdministrativeCards: View {
    let status: TableTennisAdministrativeMarkerStatus
    var alignment: Alignment = .center
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 3 * scale) {
            if status.timeoutUsed { card(color: .white) }
            if status.hasYellowCard { card(color: .yellow) }
            ForEach(0..<TableTennisAdministrativeMarkerPolicy.displayedRedCardCount(status.redCardCount), id: \.self) { _ in
                card(color: .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func card(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2 * scale)
            .fill(color)
            .overlay {
                RoundedRectangle(cornerRadius: 2 * scale)
                    .stroke(.black.opacity(0.22), lineWidth: max(0.75, scale * 0.75))
            }
            .frame(width: 14 * scale, height: 21 * scale)
    }
}

enum RallyDisplayProjectionResolver {
    static func teamCourtRoster(gameType: ScoreCore.GameType, state: RallyMatchState) -> [String]? {
        guard gameType == .shuttlecock,
              state.competitionFormat == .team,
              let names = state.competitionPlayerNames,
              names.count >= 6 else { return nil }
        return Array(names.prefix(6))
    }
}

/// Pure six-player team presentation shared by the phone scoreboard and the
/// synchronized receiver. Interaction remains owned by the phone panel.
struct TeamCourtScoreboardPanel: View {
    let names: [String]
    let fallbackName: String
    let scoreText: String
    let setsText: String
    let panelSize: CGSize
    let preference: ScoreboardTypographyPreference
    let panelColor: Color
    let nameColor: Color
    let scoreColor: Color
    let setsColor: Color

    var body: some View {
        let visibleNames = names.isEmpty ? [fallbackName] : names
        let longestName = visibleNames.max(by: { $0.count < $1.count }) ?? ""
        let firstPass = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: panelSize,
                nameText: longestName,
                scoreText: scoreText,
                secondaryText: setsText,
                preference: preference,
                horizontalPadding: 16,
                isLargeScreen: min(panelSize.width, panelSize.height) >= 600
            )
        )
        let extraNameHeight = CGFloat(max(0, visibleNames.count - 1)) * (firstPass.nameFontSize * 1.2 + 6)
        let typography = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: panelSize,
                nameText: longestName,
                scoreText: scoreText,
                secondaryText: setsText,
                preference: preference,
                horizontalPadding: 16,
                reservedHeight: extraNameHeight,
                isLargeScreen: min(panelSize.width, panelSize.height) >= 600
            )
        )
        return VStack(spacing: 0) {
            VStack(spacing: 6) {
                ForEach(Array(visibleNames.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(preference.font.swiftUIFont(size: typography.nameFontSize, weight: .bold))
                        .foregroundStyle(nameColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            Spacer().frame(height: typography.nameToScoreSpacing)
            Text(scoreText)
                .font(preference.font.swiftUIFont(size: typography.scoreFontSize))
                .foregroundStyle(scoreColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer().frame(height: ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: panelSize.height))
            Text(setsText)
                .font(preference.font.swiftUIFont(size: typography.secondaryFontSize))
                .foregroundStyle(setsColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(width: panelSize.width, height: panelSize.height)
        .background(panelColor)
    }
}

struct RallyScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scoreboardUsageHintCoordinator) private var usageHintCoordinator
    @Environment(\.scoreboardMatchClockSession) private var matchClockSession

    let gameType: ScoreCore.GameType
    let onNavigationBack: (() -> Void)?
    let onPresented: () -> Void
    let usageHintCoordinatorOverride: ScoreboardUsageHintCoordinator?
    @State private var voiceAnnouncementEnabled: Bool
    @State private var store: RallySessionStore
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var toastMessage: String?
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession: ScoreboardTypographySession
    @State private var preferences = PreferencesManager.shared
    @State private var showDisplaySettings = false
    @State private var styleEditorEntry = ScoreboardStyleEditorEntry()
    @State private var showMenu = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var exitConfirmDeadline: Date?
    @State private var isEditMode = false
    @State private var editLeftName = ""
    @State private var editRightName = ""
    @State private var editDoublesNames: [String] = Array(repeating: "", count: 4)
    @State private var pendingDoublesFlash: PendingDoublesFlash?
    @State private var flashSlots: Set<Int> = []
    @State private var flashActive = false
    @State private var flashTask: Task<Void, Never>?
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var didSpeakOpeningAnnouncement = false
    @State private var openingAnnouncementTask: Task<Void, Never>?
    @State private var manualFinishRequested = false
    @State private var isStartingNewMatch = false
    @State private var terminalHold = ScoreboardTerminalHold<RallyTerminalSetPresentation>()
    @State private var officialBreakSession = OfficialBreakSession()
    @State private var showPingPongPauseDialog = false
    @State private var showPingPongMedicalDialog = false
    @State private var showPingPongCardsDialog = false
    @State private var pingPongPenaltySelectedSide: MatchSide?
    @State private var showPingPongPenaltyConfirmation = false
    @State private var pendingTapSide: MatchSide?
    @State private var pendingTapAt: Date = .distantPast
    @State private var tapGeneration = 0

    init(
        leftName: String,
        rightName: String,
        gameType: ScoreCore.GameType,
        rules: RallyRuleSet,
        participants: [SessionParticipant]? = nil,
        competitionFormat: CompetitionFormat? = nil,
        competitionPlayerNames: [String]? = nil,
        openingServer: MatchSide = .left,
        voiceAnnouncementEnabled: Bool = false,
        showMatchTimeEnabled: Bool = false,
        initialResumeSessionId: String? = nil,
        onNavigationBack: (() -> Void)? = nil,
        onPresented: @escaping () -> Void = {},
        usageHintCoordinatorOverride: ScoreboardUsageHintCoordinator? = nil
    ) {
        self.onNavigationBack = onNavigationBack
        self.onPresented = onPresented
        self.usageHintCoordinatorOverride = usageHintCoordinatorOverride

        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let restoredStore = RallySessionStore(restoring: sessionId) {
            self.gameType = restoredStore.gameType
            _store = State(initialValue: restoredStore)
            _voiceAnnouncementEnabled = State(initialValue: restoredStore.voiceAnnouncementEnabled)
            _showGameOverDialog = State(initialValue: restoredStore.state.finished)
            _officialBreakSession = State(initialValue: OfficialBreakSession(state: restoredStore.state.officialBreakState))
            _didSpeakOpeningAnnouncement = State(initialValue: true)
        } else {
            self.gameType = gameType
            let newStore = RallySessionStore(
                leftName: leftName,
                rightName: rightName,
                gameType: gameType,
                rules: rules,
                participants: participants,
                competitionFormat: competitionFormat,
                competitionPlayerNames: competitionPlayerNames,
                openingServer: openingServer,
                voiceAnnouncementEnabled: voiceAnnouncementEnabled,
                showMatchTimeEnabled: showMatchTimeEnabled
            )
            _store = State(initialValue: newStore)
            _voiceAnnouncementEnabled = State(initialValue: voiceAnnouncementEnabled)
            _officialBreakSession = State(initialValue: OfficialBreakSession())
        }
        _typographySession = State(initialValue: ScoreboardTypographySession(
            styleID: ScoreboardStyleID(scoreCoreGameType: self.gameType)
        ))
    }

    private let doubleTapWindow: TimeInterval = 0.24

    /// 对齐安卓 S1DualSideScoreRouteScreen：只有「单击 = 1 分」的 Rally 项目才把双击映射成减 1 分，
    /// 其余项目双击等价于两次加分。判定复用使用说明的双击减分清单（两者在 Rally 承载的项目上一致）。
    private var onePointDoubleTapEnabled: Bool {
        appearance.doubleTapSubtract
            && !scoringLocked
            && ScoreboardUsageHintHelper.supportsDoubleTapSubtract(gameType)
    }

    private func commitPointWon(_ side: MatchSide) {
        guard !isEditMode, !store.state.finished else { return }
        handlePointWon(side)
    }

    /// 对齐安卓 ScoreboardDoubleTapSubtractHandler：挂起窗口内同侧第二次点击 = 减 1 分，
    /// 异侧点击则先把挂起的这一次结算掉，再为新的半区重新挂起。
    private func handlePanelTap(_ side: MatchSide) {
        guard !isEditMode, !store.state.finished else { return }
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
            gameType: gameType,
            enabled: appearance.touchGuard
        )
    }

    private var isDoubles: Bool { store.state.doubles != nil }
    private var teamCourtRoster: [String]? {
        RallyDisplayProjectionResolver.teamCourtRoster(gameType: gameType, state: store.state)
    }
    private var primaryNameType: NameType {
        ScoreboardCommonNamePolicy.rallyNameType(for: gameType)
    }
    private var isFoosballDoubles: Bool {
        guard let doubles = store.state.doubles else { return false }
        if case .foosball = doubles.rotation { return true }
        return gameType == .foosballDoubles
    }
    private var terminalSetPresentation: RallyTerminalSetPresentation? { terminalHold.value }

    private var scoringLocked: Bool {
        isStyleEditing || terminalSetPresentation != nil || officialBreakSession.inputFrozen
    }
    private var palette: ScoreboardPalette { appearance.palette }
    private var activeUsageHintCoordinator: ScoreboardUsageHintCoordinator? {
        usageHintCoordinator ?? usageHintCoordinatorOverride
    }


    /// Legacy foosball sessions keep their previous no-indicator behavior.
    private var showsServeIndicator: Bool {
        switch gameType {
        case .foosball, .foosballDoubles:
            return store.state.rules.servingModel == .concedingSideServes
        default: return true
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let halfH = proxy.size.height
            let serveIndicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                halfViewportSize: CGSize(width: proxy.size.width / 2, height: halfH)
            )
            ZStack {
                palette.background.ignoresSafeArea()

                HStack(spacing: 0) {
                    if teamCourtRoster != nil, !isEditMode {
                        teamCourtHalf(screenSide: .left, size: CGSize(width: proxy.size.width / 2, height: halfH))
                        teamCourtHalf(screenSide: .right, size: CGSize(width: proxy.size.width / 2, height: halfH))
                    } else if isFoosballDoubles {
                        foosballDoublesHalf(screenSide: .left, size: CGSize(width: proxy.size.width / 2, height: halfH))
                        foosballDoublesHalf(screenSide: .right, size: CGSize(width: proxy.size.width / 2, height: halfH))
                    } else if isDoubles {
                        doublesHalf(screenSide: .left, size: CGSize(width: proxy.size.width / 2, height: halfH))
                        doublesHalf(screenSide: .right, size: CGSize(width: proxy.size.width / 2, height: halfH))
                    } else {
                        singlesHalf(screenSide: .left, size: CGSize(width: proxy.size.width / 2, height: halfH))
                        singlesHalf(screenSide: .right, size: CGSize(width: proxy.size.width / 2, height: halfH))
                    }
                }

                if !isEditMode && !store.state.finished && showsServeIndicator && terminalSetPresentation == nil {
                    serveIndicatorOverlay(size: proxy.size, triangleSize: serveIndicatorSize)
                }

                if !isEditMode && !isStyleEditing && !showDisplaySettings && !store.state.finished && terminalSetPresentation == nil {
                    ScoreboardKeyPointBadgeLayer(
                        status: KeyPointResolver.rally(state: store.state),
                        gameType: gameType,
                        sidesSwapped: store.state.sidesSwapped,
                        doublesTopRow: keyPointDoublesTopRow,
                        serveIndicatorSize: serveIndicatorSize
                    )
                }

                if !isEditMode && !isStyleEditing && !showDisplaySettings && [.pingpong, .pingpongDoubles].contains(gameType) {
                    pingPongAdministrativeMarkerOverlay
                }

                if shouldShowChrome {
                    chromeOverlay
                }

                if appearance.immersiveMode && !chromeVisible && !isEditMode {
                    ImmersiveCornerRevealZones(onReveal: revealImmersiveChrome)
                }

                MenuDialog(
                    isVisible: showMenu,
                    onClose: {
                        menuConfirm.clear()
                        showMenu = false
                    },
                    onMenuItemClick: handleMenuAction,
                    onUsageHint: { activeUsageHintCoordinator?.presentFromMenu() },
                    showEndGame: true,
                    items: menuItems,
                    analyticsGameType: GameType(scoreCoreGameType: store.gameType) ?? .simpleScore
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

                if showGameOverDialog {
                    let displayScores = RallyFinishedScorePresentation.scores(for: store.state)
                    GameOverDialog(
                        winnerName: finishedWinnerName,
                        gameType: GameType(scoreCoreGameType: store.gameType) ?? .simpleScore,
                        leftName: store.state.leftName,
                        rightName: store.state.rightName,
                        leftScore: displayScores.left,
                        rightScore: displayScores.right,
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
                                if let onNavigationBack {
                                    onNavigationBack()
                                } else {
                                    dismiss()
                                }
                            }
                        }
                    )
                }

                if let toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: toastMessage)
                            .padding(.bottom, 40)
                    }
                    .transition(.opacity.combined(with: .scale))
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
            .animation(.easeInOut(duration: 0.2), value: toastMessage)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    guard !isEditMode else { return }
                    showMenu = true
                    revealImmersiveChrome()
                }
        )
        .onAppear {
            onPresented()
            typographySession.switchStyleID(ScoreboardStyleID(scoreCoreGameType: gameType))
            appearance = .current(styleID: ScoreboardStyleID(scoreCoreGameType: gameType))
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            registerScoreboardSync()

            revealImmersiveChrome()
            if store.state.finished {
                showGameOverDialog = true
            }
            if let savedBreak = store.state.officialBreakState {
                officialBreakSession = OfficialBreakSession(state: savedBreak)
                officialBreakSession.reconcileAfterRestore(
                    nowMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
                )
            }
            speakOpeningAnnouncementIfNeeded()
            bindMatchClock()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current(styleID: ScoreboardStyleID(scoreCoreGameType: gameType))
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            // 对齐安卓 LaunchedEffect(onePointDoubleTapEnabled)：开关关掉时立刻丢掉挂起的单击。
            if !onePointDoubleTapEnabled { cancelPendingTap() }
            revealImmersiveChrome()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: onePointDoubleTapEnabled) { _, _ in cancelPendingTap() }
        .onChange(of: store.state) { _, state in
            if terminalSetPresentation == nil {
                publishCurrentRallyState()
            }
        }

        .onChange(of: showMenu) { _, isOpen in
            if !isOpen { menuConfirm.clear() }
            updateImmersiveForBlocking()
        }
        .onChange(of: store.persistenceFailureSignal) { _, signal in
            guard signal > 0 else { return }
            showToast(NSLocalizedString(
                "scoreboard_save_failed",
                value: "保存失败，请稍后重试",
                comment: "Scoreboard persistence failed"
            ))
        }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveForBlocking() }
        .scoreboardStyleEditorEntry(
            styleEditorEntry,
            typographySession: typographySession,
            onEditingChange: { _ in updateImmersiveForBlocking() }
        )
        .onChange(of: typographySession.effectivePreference) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: isEditMode) { _, editing in
            if editing {
                syncEditNamesFromState()
            } else if !isFoosballDoubles {
                commitSinglesNamesIfNeeded()
            }
            updateImmersiveForBlocking()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onDisappear {
            cancelPendingOpeningAnnouncement()
            flashTask?.cancel()
            cancelTerminalSetPresentation()
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }

            store.persistSnapshot()
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.rally.adjustableMetrics
        )
        .confirmationDialog(
            NSLocalizedString("timeout", value: "暂停", comment: ""),
            isPresented: $showPingPongPauseDialog,
            titleVisibility: .visible
        ) {
            Button(pingPongAdministrativeChoiceTitle(.timeout, side: .left)) {
                dispatch(.pingPongAdministrativeAction(type: .timeout, side: .left))
            }
            .disabled(!pingPongTimeoutAvailable(side: .left))
            Button(pingPongAdministrativeChoiceTitle(.timeout, side: .right)) {
                dispatch(.pingPongAdministrativeAction(type: .timeout, side: .right))
            }
            .disabled(!pingPongTimeoutAvailable(side: .right))
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        }
        .confirmationDialog(
            NSLocalizedString("medical_timeout", value: "医疗暂停", comment: ""),
            isPresented: $showPingPongMedicalDialog,
            titleVisibility: .visible
        ) {
            Button(pingPongAdministrativeChoiceTitle(.medicalTimeout, side: .left)) {
                dispatch(.pingPongAdministrativeAction(type: .medicalTimeout, side: .left))
            }
            Button(pingPongAdministrativeChoiceTitle(.medicalTimeout, side: .right)) {
                dispatch(.pingPongAdministrativeAction(type: .medicalTimeout, side: .right))
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        }
        .confirmationDialog(
            NSLocalizedString("select_player", value: "选择选手", comment: ""),
            isPresented: $showPingPongCardsDialog,
            titleVisibility: .visible
        ) {
            Button(pingPongPenaltySelectionTitle(side: .left)) { selectPingPongPenaltySide(.left) }
            Button(pingPongPenaltySelectionTitle(side: .right)) { selectPingPongPenaltySide(.right) }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        }
        .confirmationDialog(
            pingPongPenaltyConfirmationTitle,
            isPresented: $showPingPongPenaltyConfirmation,
            titleVisibility: .visible
        ) {
            Button(pingPongPenaltyConfirmButtonTitle, role: pingPongPenaltyConfirmationRole) {
                confirmPingPongPenalty()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {
                pingPongPenaltySelectedSide = nil
            }
        }
    }

    // MARK: - Singles

    private func teamCourtHalf(screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let logicalIndex = side == .left ? 0 : 1
        let names = Array((teamCourtRoster ?? []).dropFirst(logicalIndex * 3).prefix(3))
        let slotKey: ScoreboardStyleSlotKeyV2 = side == .left ? .sideLeft : .sideRight
        let panel = side == .left ? palette.left : palette.right
        let fallback = side == .left ? store.state.leftName : store.state.rightName
        let score = side == .left ? store.state.leftPoints : store.state.rightPoints
        let sets = side == .left ? store.state.leftSets : store.state.rightSets

        return TeamCourtScoreboardPanel(
            names: names,
            fallbackName: fallback,
            scoreText: "\(score)",
            setsText: "\(sets)",
            panelSize: size,
            preference: typographyPreference,
            panelColor: panel,
            nameColor: appearance.elementForeground(.playerName, slotKey: slotKey),
            scoreColor: appearance.elementForeground(.mainScore, slotKey: slotKey),
            setsColor: setsColor(slotKey: slotKey)
        )
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1)
                .onEnded { value in
                    guard isScoreTouchAllowed(location: value.location, panelSize: size) else { return }
                    handlePanelTap(side)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    cancelPendingTap()
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        performUndo()
                    } else if value.translation.height < -50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        handlePointWon(side)
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
                        VibrationManager.shared.vibrateLight()
                        dispatch(.adjustPoints(side: side, delta: -1))
                    }
                }
        )
    }

    private func singlesHalf(screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let isLeft = side == .left
        let color = isLeft ? palette.left : palette.right
        let textColor = palette.foreground(for: isLeft ? .team0 : .team1)

        return ZStack {
            color
            if isEditMode {
                singlesEditContent(side: side, size: size)
            } else {
                singlesPlayContent(side: side, size: size)
            }
        }
        .foregroundStyle(textColor)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1)
                .onEnded { value in
                    guard isScoreTouchAllowed(location: value.location, panelSize: size) else { return }
                    handlePanelTap(side)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    cancelPendingTap()
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        performUndo()
                    } else if value.translation.height < -50 && abs(value.translation.width) < 50 {
                        // 对齐安卓上滑加分（scoreboardPanelSwipeGestures onAdd）；
                        // 滑动与点击互斥，先清掉挂起的单击再立即结算。
                        guard !store.state.finished else { return }
                        handlePointWon(side)
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
                        VibrationManager.shared.vibrateLight()
                        dispatch(.adjustPoints(side: side, delta: -1))
                    }
                }
        )
    }

    private func singlesPlayContent(side: MatchSide, size: CGSize) -> some View {
        let name = scoreboardDisplayName(for: side)
        let score = displayedPoints(for: side)
        let sets = displayedSets(for: side)
        let typography = resolvedTypography(
            name: name,
            score: "\(score)",
            secondary: "\(sets)",
            size: size
        )
        let mainSize = typography.scoreFontSize
        let setSize = typography.secondaryFontSize
        let nameSize = typography.nameFontSize
        let nameToMain = typography.nameToScoreSpacing
        let mainToSet = ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: size.height)
        // 元素级取色（V2 槽位配置优先；未配置时回落面板级解析色）。
        let slotKey: ScoreboardStyleSlotKeyV2 = side == .left ? .sideLeft : .sideRight

        let nameElement: ScoreboardStyleElementKeyV2 = isFoosballDoubles ? .playerName : .teamName
        let secondaryElement: ScoreboardStyleElementKeyV2 = isFoosballDoubles ? .setGameScore : .setScore
        return VStack(spacing: 0) {
            Text(name)
                .font(typographyPreference.font.swiftUIFont(size: nameSize, weight: .bold))
                .foregroundStyle(appearance.elementForeground(nameElement, slotKey: slotKey))
                .styleElementSelectable(nameElement, slotKey: slotKey)
                .lineLimit(isFoosballDoubles ? 2 : 1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
            Spacer().frame(height: nameToMain)
            Text("\(score)")
                .font(typographyPreference.font.swiftUIFont(size: mainSize))
                .foregroundStyle(appearance.elementForeground(.mainScore, slotKey: slotKey))
                .styleElementSelectable(.mainScore, slotKey: slotKey)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer().frame(height: mainToSet)
            Text("\(sets)")
                .font(typographyPreference.font.swiftUIFont(size: setSize))
                .foregroundStyle(setsColor(slotKey: slotKey, element: secondaryElement))
                .styleElementSelectable(secondaryElement, slotKey: slotKey)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 局分色：V2 配置优先；未配置保持旧默认（面板解析色 70% 透明）。
    private func setsColor(slotKey: ScoreboardStyleSlotKeyV2, element: ScoreboardStyleElementKeyV2 = .setScore) -> Color {
        if appearance.hasElementColor(element, slotKey: slotKey) {
            return appearance.elementForeground(element, slotKey: slotKey)
        }
        return palette.foreground(for: slotKey.legacySlot == .team0 ? .team0 : .team1).opacity(0.7)
    }

    private func singlesEditContent(side: MatchSide, size: CGSize) -> some View {
        let isLeft = side == .left
        let name = isLeft ? editLeftName : editRightName
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let typography = resolvedTypography(
            name: name,
            score: "\(score)",
            secondary: "\(sets)",
            size: size,
            reservedHeight: 32
        )
        let mainSize = ScoreboardLayoutMetrics.editMainScoreFontSize(
            regularSize: typography.scoreFontSize
        )
        let setSize = typography.secondaryFontSize
        let nameToMain = typography.nameToScoreSpacing
        let mainToSet = ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: size.height)

        return VStack(spacing: 0) {
            ScoreboardNameEditorField(
                placeholder: primaryNameType == .player
                    ? NSLocalizedString("setup_player_name", value: "选手名称", comment: "")
                    : NSLocalizedString("team_name", value: "队名", comment: ""),
                text: isLeft ? $editLeftName : $editRightName,
                nameType: primaryNameType,
                scoreboardFont: typographyPreference.font,
                textColor: palette.control,
                onSubmit: commitSinglesNamesIfNeeded,
                onSelection: { _ in commitSinglesNamesIfNeeded() },
                accessibilityIdentifier: isLeft
                    ? "rally_left_name_editor"
                    : "rally_right_name_editor"
            )
            .padding(.horizontal, 16)

            Spacer().frame(height: nameToMain)

            editAdjustRow(
                value: score,
                fontSize: mainSize,
                useSecondaryColor: false,
                canDecrement: score > 0,
                onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { adjustPointsInEdit(side: side, delta: 1) }
            )

            Spacer().frame(height: mainToSet)

            editAdjustRow(
                value: sets,
                fontSize: setSize,
                useSecondaryColor: true,
                canDecrement: sets > 0,
                onDecrement: { dispatch(.adjustSets(side: side, delta: -1)) },
                onIncrement: { adjustSetsInEdit(side: side, delta: 1) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: size.height))
    }

    // MARK: - Foosball doubles

    /// Foosball 2V2 keeps the normal two-panel scoreboard in play mode. Only
    /// edit mode expands each joined team name into its two player fields.
    private func foosballDoublesHalf(screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let color = side == .left ? palette.left : palette.right
        let textColor = palette.foreground(for: side == .left ? .team0 : .team1)

        return ZStack {
            color
            if isEditMode {
                foosballDoublesEditContent(side: side, size: size)
            } else {
                singlesPlayContent(side: side, size: size)
            }
        }
        .foregroundStyle(textColor)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1)
                .onEnded { value in
                    guard isScoreTouchAllowed(location: value.location, panelSize: size) else { return }
                    handlePanelTap(side)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    cancelPendingTap()
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        performUndo()
                    } else if value.translation.height < -50 && abs(value.translation.width) < 50 {
                        // 对齐安卓上滑加分（scoreboardPanelSwipeGestures onAdd）；
                        // 滑动与点击互斥，先清掉挂起的单击再立即结算。
                        guard !store.state.finished else { return }
                        handlePointWon(side)
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
                        VibrationManager.shared.vibrateLight()
                        dispatch(.adjustPoints(side: side, delta: -1))
                    }
                }
        )
    }

    private func foosballDoublesEditContent(side: MatchSide, size: CGSize) -> some View {
        let isLeft = side == .left
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let slots = isLeft ? (0, 2) : (1, 3)
        let topInset = ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: size.height)
        let fieldHeight = ScoreboardLayoutMetrics.scoreboardNameEditorHeight(screenWidth: max(size.width * 2, size.height))
        let nameToMain: CGFloat = 16
        let typography = resolvedTypography(
            name: "",
            score: "\(score)",
            secondary: "\(sets)",
            size: CGSize(width: size.width, height: max(1, size.height - topInset - 16)),
            reservedHeight: fieldHeight * 2 + 6 + nameToMain
        )
        let mainSize = ScoreboardLayoutMetrics.editMainScoreFontSize(
            regularSize: typography.scoreFontSize
        )
        let setSize = typography.secondaryFontSize
        let mainToSet = ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: size.height)

        return VStack(spacing: 0) {
            VStack(spacing: 6) {
                foosballDoublesEditNameField(slot: slots.0)
                foosballDoublesEditNameField(slot: slots.1)
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: nameToMain)

            editAdjustRow(
                value: score,
                fontSize: mainSize,
                useSecondaryColor: false,
                canDecrement: score > 0,
                onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { adjustPointsInEdit(side: side, delta: 1) }
            )

            Spacer().frame(height: mainToSet)

            editAdjustRow(
                value: sets,
                fontSize: setSize,
                useSecondaryColor: true,
                canDecrement: sets > 0,
                onDecrement: { dispatch(.adjustSets(side: side, delta: -1)) },
                onIncrement: { adjustSetsInEdit(side: side, delta: 1) }
            )
        }
        .padding(.top, topInset)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func foosballDoublesEditNameField(slot: Int) -> some View {
        let fallback = store.state.doubles?.playerName(at: slot) ?? ""
        return ScoreboardNameEditorField(
            placeholder: NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""),
            text: Binding(
                get: {
                    guard editDoublesNames.indices.contains(slot) else { return fallback }
                    return editDoublesNames[slot]
                },
                set: { newValue in
                    guard editDoublesNames.indices.contains(slot) else { return }
                    editDoublesNames[slot] = newValue
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !scoringLocked else { return }
                    dispatch(.setDoublesPlayerName(slot: slot, name: trimmed))
                }
            ),
            nameType: .player,
            scoreboardFont: typographyPreference.font,
            textColor: palette.control,
            accessibilityIdentifier: "foosball_doubles_player_\(slot)_editor"
        )
    }

    private func scoreboardDisplayName(for side: MatchSide) -> String {
        guard isFoosballDoubles, let doubles = store.state.doubles else {
            return side == .left ? store.state.leftName : store.state.rightName
        }
        let slots = side == .left ? (0, 2) : (1, 3)
        return FoosballScoreboardView.joinFoosballNames(
            doubles.playerName(at: slots.0) ?? "",
            doubles.playerName(at: slots.1) ?? ""
        )
    }

    // MARK: - Doubles

    private func doublesHalf(screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let isLeft = side == .left
        let color = isLeft ? palette.left : palette.right
        let textColor = palette.foreground(for: isLeft ? .team0 : .team1)
        let editTopInset = isEditMode
            ? ScoreboardLayoutMetrics.nameTopPadding(panelHeight: size.height, isEditMode: true)
            : 0
        let scoreboardScreenWidth = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let editNamesHeight = ScoreboardLayoutMetrics.doublesEditNamesRegionHeight(
            isLargeScreen: Theme.usesPadLayout,
            screenWidth: scoreboardScreenWidth
        )
        let editFieldHeight = ScoreboardLayoutMetrics.scoreboardNameEditorHeight(
            screenWidth: scoreboardScreenWidth
        )
        let scoreRowHeight = isEditMode
            ? max(1, size.height - editTopInset - editNamesHeight)
            : size.height / 3
        let (topName, bottomName) = doublesCornerNames(screenSide: screenSide)
        let topSlot = doublesTopSlot(screenSide: screenSide)
        let bottomSlot = doublesBottomSlot(screenSide: screenSide)

        return ZStack {
            color
            if isEditMode {
                VStack(spacing: 0) {
                    VStack(spacing: Theme.usesPadLayout ? 10 : 4) {
                        doublesNameCell(
                            name: topName,
                            slot: topSlot,
                            fontSize: doublesNameFontSize(panelSize: size),
                            height: editFieldHeight
                        )
                        doublesNameCell(
                            name: bottomName,
                            slot: bottomSlot,
                            fontSize: doublesNameFontSize(panelSize: size),
                            height: editFieldHeight
                        )
                    }
                    .padding(.horizontal, Theme.usesPadLayout ? 12 : 8)
                    .padding(.top, Theme.usesPadLayout ? 12 : 6)
                    .frame(height: editNamesHeight, alignment: .top)

                    doublesEditScoreRow(
                        screenSide: screenSide,
                        side: side,
                        height: scoreRowHeight,
                        panelSize: size
                    )
                }
                .padding(.top, editTopInset)
                .frame(height: size.height, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    doublesNameCell(
                        name: topName,
                        slot: topSlot,
                        fontSize: doublesNameFontSize(panelSize: size),
                        height: size.height / 3
                    )
                    Spacer(minLength: 0)
                    doublesNameCell(
                        name: bottomName,
                        slot: bottomSlot,
                        fontSize: doublesNameFontSize(panelSize: size),
                        height: size.height / 3
                    )
                }
                doublesPlayScoreRow(
                    screenSide: screenSide,
                    side: side,
                    height: ScoreboardLayoutMetrics.doublesScoreRegionHeight(panelHeight: size.height),
                    panelSize: size
                )
            }
        }
        .foregroundStyle(textColor)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 1)
                .onEnded { value in
                    guard isScoreTouchAllowed(location: value.location, panelSize: size) else { return }
                    handlePanelTap(side)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    cancelPendingTap()
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        performUndo()
                    } else if value.translation.height < -50 && abs(value.translation.width) < 50 {
                        // 对齐安卓上滑加分（scoreboardPanelSwipeGestures onAdd）；
                        // 滑动与点击互斥，先清掉挂起的单击再立即结算。
                        guard !store.state.finished else { return }
                        handlePointWon(side)
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
                        VibrationManager.shared.vibrateLight()
                        dispatch(.adjustPoints(side: side, delta: -1))
                    }
                }
        )
    }

    private func doublesPlayScoreRow(screenSide: MatchSide, side: MatchSide, height: CGFloat, panelSize: CGSize) -> some View {
        let score = displayedPoints(for: side)
        let sets = displayedSets(for: side)
        let typography = resolvedTypography(
            name: "",
            score: "\(score)",
            secondary: "\(sets)",
            size: CGSize(width: panelSize.width, height: height),
            secondaryIsInline: true,
            referenceHeight: panelSize.height
        )
        let mainSize = typography.scoreFontSize
        let setSize = ScoreboardLayoutMetrics.doublesSecondaryScoreFontSize(
            regularSize: typography.secondaryFontSize
        )
        let secondaryColumnWidth = ScoreboardLayoutMetrics.doublesSecondaryColumnWidth(
            halfViewportWidth: panelSize.width
        )
        // 元素级取色（V2 槽位配置优先；未配置时回落旧默认）。
        let slotKey: ScoreboardStyleSlotKeyV2 = side == .left ? .sideLeft : .sideRight
        let scoreColor = appearance.elementForeground(.mainScore, slotKey: slotKey)
        let setsColor: Color = appearance.hasElementColor(.setGameScore, slotKey: slotKey)
            ? appearance.elementForeground(.setGameScore, slotKey: slotKey)
            : palette.secondary

        return HStack(spacing: 0) {
            if screenSide == .left {
                Text("\(score)")
                    .font(typographyPreference.font.swiftUIFont(size: mainSize))
                    .foregroundStyle(scoreColor)
                        .styleElementSelectable(.mainScore, slotKey: slotKey)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Text("\(sets)")
                    .font(typographyPreference.font.swiftUIFont(size: setSize))
                    .monospacedDigit()
                    .foregroundStyle(setsColor)
                        .styleElementSelectable(.setGameScore, slotKey: slotKey)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(width: secondaryColumnWidth)
            } else {
                Text("\(sets)")
                    .font(typographyPreference.font.swiftUIFont(size: setSize))
                    .monospacedDigit()
                    .foregroundStyle(setsColor)
                        .styleElementSelectable(.setGameScore, slotKey: slotKey)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(width: secondaryColumnWidth)
                Text("\(score)")
                    .font(typographyPreference.font.swiftUIFont(size: mainSize))
                    .foregroundStyle(scoreColor)
                        .styleElementSelectable(.mainScore, slotKey: slotKey)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func doublesEditScoreRow(
        screenSide: MatchSide,
        side: MatchSide,
        height: CGFloat,
        panelSize: CGSize
    ) -> some View {
        let isLeft = side == .left
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let typography = resolvedTypography(
            name: "",
            score: "\(score)",
            secondary: "\(sets)",
            size: panelSize
        )
        let mainSize = ScoreboardLayoutMetrics.doublesEditMainScoreFontSize(
            regularSize: typography.scoreFontSize,
            isLargeScreen: Theme.usesPadLayout
        )
        let setSize = ScoreboardLayoutMetrics.doublesEditSecondaryScoreFontSize(
            regularSize: typography.secondaryFontSize,
            isLargeScreen: Theme.usesPadLayout
        )
        let controlSize = ScoreboardLayoutMetrics.doublesEditControlSize(
            isLargeScreen: Theme.usesPadLayout
        )

        return VStack(spacing: Theme.usesPadLayout ? 10 : 5) {
            editAdjustRow(
                value: score,
                fontSize: mainSize,
                useSecondaryColor: false,
                canDecrement: score > 0,
                controlSize: controlSize,
                spacing: Theme.usesPadLayout ? 20 : 10,
                valueMinWidth: Theme.usesPadLayout ? 72 : 48,
                onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { adjustPointsInEdit(side: side, delta: 1) }
            )
            editAdjustRow(
                value: sets,
                fontSize: setSize,
                useSecondaryColor: true,
                canDecrement: sets > 0,
                controlSize: controlSize,
                spacing: Theme.usesPadLayout ? 18 : 8,
                valueMinWidth: Theme.usesPadLayout ? 40 : 28,
                onDecrement: { dispatch(.adjustSets(side: side, delta: -1)) },
                onIncrement: { adjustSetsInEdit(side: side, delta: 1) }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func doublesNameCell(name: String, slot: Int, fontSize: CGFloat, height: CGFloat) -> some View {
        let doubles = store.state.doubles
        let isServer = doubles?.serverSlotIndex == slot
        let isReceiver = doubles?.receiverSlotIndex == slot
        let nameColor: Color = {
            let key: ScoreboardStyleSlotKeyV2 = slot.isMultiple(of: 2) ? .sideLeft : .sideRight
            if appearance.hasElementColor(.playerName, slotKey: key) {
                return appearance.elementForeground(.playerName, slotKey: key)
            }
            if isServer { return palette.foreground }
            if isReceiver { return palette.secondary }
            return palette.foreground.opacity(0.85)
        }()
        let showFlash = flashSlots.contains(slot) && flashActive
        let flashColor = Color(red: 1, green: 215 / 255, blue: 0).opacity(0.45)

        return ZStack {
            if showFlash {
                flashColor
            }
            if isEditMode {
                ScoreboardNameEditorField(
                    placeholder: NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""),
                    text: Binding(
                        get: {
                            guard editDoublesNames.indices.contains(slot) else { return name }
                            return editDoublesNames[slot]
                        },
                        set: { newValue in
                            guard editDoublesNames.indices.contains(slot) else { return }
                            editDoublesNames[slot] = newValue
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                guard !scoringLocked else { return }
                                dispatch(.setDoublesPlayerName(slot: slot, name: trimmed))
                            }
                        }
                    ),
                    nameType: .player,
                    scoreboardFont: typographyPreference.font,
                    textColor: palette.control,
                    accessibilityIdentifier: "rally_doubles_player_\(slot)_editor"
                )
            } else {
                Text(name)
                    .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
                    .foregroundStyle(nameColor)
                    .styleElementSelectable(.playerName, slotKey: slot.isMultiple(of: 2) ? .sideLeft : .sideRight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func doublesNameFontSize(panelSize: CGSize) -> CGFloat {
        let longestName = store.state.doubles?.playerNames.max(by: { $0.count < $1.count }) ?? ""
        return resolvedTypography(
            name: longestName,
            score: "",
            secondary: "",
            size: panelSize
        ).nameFontSize
    }

    private func doublesTopSlot(screenSide: MatchSide) -> Int {
        doublesDisplaySlots(screenSide: screenSide).top
    }

    private func doublesBottomSlot(screenSide: MatchSide) -> Int {
        doublesDisplaySlots(screenSide: screenSide).bottom
    }

    private func doublesCornerNames(screenSide: MatchSide) -> (String, String) {
        guard let doubles = store.state.doubles else { return ("", "") }
        let slots = doublesDisplaySlots(screenSide: screenSide)
        return (
            doubles.playerName(at: slots.top) ?? "",
            doubles.playerName(at: slots.bottom) ?? ""
        )
    }

    private func doublesDisplaySlots(screenSide: MatchSide) -> (top: Int, bottom: Int) {
        let logical = logicalSide(forScreen: screenSide)
        guard let doubles = store.state.doubles else {
            return logical == .left ? (0, 2) : (1, 3)
        }
        let display = RallyDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: logical,
            screenSide: screenSide,
            appliesCourtOrder: !isEditMode
        )
        return (display.topPlayerIndex, display.bottomPlayerIndex)
    }

    // MARK: - Edit helpers

    private func editAdjustRow(
        value: Int,
        fontSize: CGFloat,
        useSecondaryColor: Bool,
        canDecrement: Bool,
        controlSize: CGFloat = 50,
        spacing: CGFloat = 16,
        valueMinWidth: CGFloat = 0,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: spacing) {
            editCircleButton(
                systemName: "minus",
                enabled: canDecrement,
                size: controlSize,
                action: onDecrement
            )
            Text("\(value)")
                .font(typographyPreference.font.swiftUIFont(size: fontSize))
                .monospacedDigit()
                .foregroundStyle(useSecondaryColor ? palette.secondary : palette.foreground)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(minWidth: valueMinWidth)
            editCircleButton(
                systemName: "plus",
                enabled: true,
                size: controlSize,
                action: onIncrement
            )
        }
    }

    private func editCircleButton(
        systemName: String,
        enabled: Bool,
        size: CGFloat = 50,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            // 对齐安卓 ScoreEditAdjustRows：编辑面板 ± 按钮轻震反馈。
            VibrationManager.shared.vibrateLight()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: Swift.min(20, size * 0.4), weight: .bold))
                .foregroundStyle(enabled ? palette.foreground.opacity(0.75) : palette.foreground.opacity(0.3))
                .frame(width: size, height: size)
                // 对齐安卓 ScoreEditAdjustRows：按钮底色用主题控制色（白底主题为深色）。
                .background(Circle().fill(palette.control.opacity(0.12)))
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    private func syncEditNamesFromState() {
        editLeftName = store.state.leftName
        editRightName = store.state.rightName
        if let doubles = store.state.doubles {
            editDoublesNames = (0..<4).map { doubles.playerName(at: $0) ?? "" }
        }
    }

    private func commitSinglesNamesIfNeeded() {
        let left = editLeftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = editRightName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return }
        if left != store.state.leftName || right != store.state.rightName {
            guard !scoringLocked else { return }
            dispatch(.setNames(left: left, right: right))
        }
    }

    // MARK: - Doubles flash

    private struct PendingDoublesFlash {
        let previousDoubles: RallyDoublesState
    }

    private func handlePointWon(_ side: MatchSide) {

        // 仅羽毛球/匹克球双打有位置轮转，发球方得分时高亮该队两人以提示换位；
        // 乒乓球、桌上足球双打无轮转，不闪烁。
        if let doubles = store.state.doubles,
           gameType == .badmintonDoubles || gameType == .pickleballDoubles {
            pendingDoublesFlash = PendingDoublesFlash(previousDoubles: doubles)
        }
        VibrationManager.shared.vibrateLight()
        dispatch(.pointWon(side), onApplied: processPendingDoublesFlash)
        revealImmersiveChrome()
    }

    private func processPendingDoublesFlash() {
        guard let pending = pendingDoublesFlash else { return }
        pendingDoublesFlash = nil
        let slots = RallyDoublesFlashResolver.slots(
            previous: pending.previousDoubles,
            current: store.state.doubles
        )
        guard !slots.isEmpty else { return }
        runDoublesFlash(slots: slots)
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

    // MARK: - Serve indicator

    private var keyPointDoublesTopRow: Bool? {
        guard showsServeIndicator,
              !isFoosballDoubles,
              let doubles = store.state.doubles else { return nil }
        return doublesServerIsTopRow(doubles)
    }

    private func doublesServerIsTopRow(_ doubles: RallyDoublesState) -> Bool {
        let servingScreenSide: MatchSide = logicalSide(forScreen: .left) == store.state.servingSide
            ? .left
            : .right
        let servingLogicalSide = logicalSide(forScreen: servingScreenSide)
        let display = RallyDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: servingLogicalSide,
            screenSide: servingScreenSide
        )
        return display.serverIsTop ?? (doubles.serverSlotIndex == 0 || doubles.serverSlotIndex == 1)
    }

    @ViewBuilder
    private func serveIndicatorOverlay(size: CGSize, triangleSize: CGFloat) -> some View {
        let servingIsLeftScreen: Bool = {
            let serving = store.state.servingSide
            let leftLogical = logicalSide(forScreen: .left)
            return serving == leftLogical
        }()

        if isDoubles, !isFoosballDoubles, let doubles = store.state.doubles {
            let isTopRow = doublesServerIsTopRow(doubles)
            CenterLineServeIndicator(
                isLeftServing: servingIsLeftScreen,
                triangleSize: triangleSize,
                color: appearance.serverIndicatorColor
            )
            .position(
                x: size.width / 2,
                y: ScoreboardServeGeometry.doublesAnchorY(height: size.height, topRow: isTopRow)
            )
            .allowsHitTesting(false)
        } else {
            CenterLineServeIndicator(
                isLeftServing: servingIsLeftScreen,
                triangleSize: triangleSize,
                color: appearance.serverIndicatorColor
            )
                .position(x: size.width / 2, y: size.height / 2)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Chrome

    private var chromeOverlay: some View {
        ZStack {
            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    chromeButton(
                        systemName: isEditMode ? "checkmark" : "pencil",
                        background: isEditMode ? Color(hex: "00C853") : Color.black.opacity(0.25)
                    ) {
                        if isEditMode && !isFoosballDoubles {
                            commitSinglesNamesIfNeeded()
                        }
                        isEditMode.toggle()
                        VibrationManager.shared.vibrateMedium()
                    }
                }
                Spacer()
            }
            .padding(.trailing, ScoreboardConstants.buttonPadding)
            .padding(.top, ScoreboardConstants.buttonPadding)

            if !isEditMode {
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
            }
        }
        .allowsHitTesting(true)
    }

    private func chromeButton(
        systemName: String,
        background: Color = Color.black.opacity(0.25),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
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
        .accessibilityIdentifier(scoreboardChromeAccessibilityID(systemName))
        .modifier(ScoreboardBackButtonAccessibility(isBack: systemName == "chevron.left"))
    }

    private func scoreboardChromeAccessibilityID(_ systemName: String) -> String {
        switch systemName {
        case "chevron.left": ScoreboardConstants.backButtonAccessibilityID
        case "line.3.horizontal": "scoreboard_menu_button"
        case "pencil", "checkmark": "scoreboard_edit_button"
        default: "scoreboard_chrome_\(systemName.replacingOccurrences(of: ".", with: "_"))"
        }
    }

    /// 对齐安卓 S1DualSideScoreRouteScreen.supportsMatchTime：Rally 类项目中仅
    /// 乒乓球单打/毽球/壁球/排球/沙滩排球/气排球提供"显示/隐藏比赛时间"菜单项。
    private static func supportsMatchClockToggle(_ gameType: GameType) -> Bool {
        [.pingpong, .shuttlecock, .squash, .volleyball, .beachVolleyball, .airVolleyball]
            .contains(gameType)
    }

    private var menuItems: [ScoreboardMenuItem] {
        var extras: [ScoreboardMenuItem] = []
        extras.append(contentsOf: [])
        if VoiceAnnouncementSupport.isSupported(gameType) {
            extras.append(
                ScoreboardMenuItem(
                    title: voiceAnnouncementEnabled
                        ? NSLocalizedString("voice_announcement_on", value: "语音：开", comment: "")
                        : NSLocalizedString("voice_announcement_off", value: "语音：关", comment: ""),
                    action: "voiceAnnouncement",
                    group: .sync,
                    icon: voiceAnnouncementEnabled ? "speaker.wave.2" : "speaker.slash",
                    keepDialogOpen: true
                )
            )
        }
        // 对齐安卓 S1DualSideScoreRouteScreen supportsMatchTime：乒乓球(单打)/毽球/壁球/三种排球
        // 的"显示/隐藏比赛时间"菜单项（双打不支持，与安卓一致）。
        if Self.supportsMatchClockToggle(appGameType) {
            let visible = matchClockSession?.isVisible ?? store.showMatchTimeEnabled
            extras.append(
                ScoreboardMenuItem(
                    title: visible
                        ? NSLocalizedString("hide_match_time", value: "隐藏时间", comment: "")
                        : NSLocalizedString("show_match_time", value: "显示时间", comment: ""),
                    action: "toggleMatchTime",
                    group: .tools,
                    icon: "clock",
                    keepDialogOpen: true
                )
            )
        }
        if [.pingpong, .pingpongDoubles].contains(gameType) {
            extras.append(contentsOf: pingPongAdministrativeMenuItems)
        }
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: true,
            showWhistle: true,
            showScreenshot: true,
            showDisplaySettings: true,
            showSettleMatch: gameType == .foosball || gameType == .foosballDoubles,
            resetConfirming: menuConfirm.resetConfirming,
            exchangeConfirming: menuConfirm.exchangeConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            settleConfirming: menuConfirm.settleConfirming,
            scoringEnabled: true,
            extraItems: extras
        )
    }

    private func handleMenuAction(_ action: String) {

        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            performUndo()
        case ScoreboardMenuActionID.exchangeSide.rawValue:
            if menuConfirm.armOrConfirm(.exchangeSide) {
                dispatch(.exchangeSides)
            } else {
                showToast(ScoreboardMenuConfirmAction.exchangeSide.localizedToast)
            }
        case "reset":
            if menuConfirm.armOrConfirm(.reset) {
                cancelTerminalSetPresentation()
                showGameOverDialog = false
                manualFinishRequested = false
                dispatch(.reset)
                showToast(NSLocalizedString("has_been_reset", value: "已重置", comment: ""))
                showMenu = false
            } else {
                showToast(ScoreboardMenuConfirmAction.reset.localizedToast)
            }
        case "endGame":
            if menuConfirm.armOrConfirm(.finish) {
                manualFinishRequested = true
                finishMatch()
                showMenu = false
            } else {
                showToast(ScoreboardMenuConfirmAction.finish.localizedToast)
            }
        case "settleMatch":
            if menuConfirm.armOrConfirm(.settleMatch) {
                manualFinishRequested = true
                finishMatch()
                showMenu = false
            } else {
                showToast(ScoreboardMenuConfirmAction.settleMatch.localizedToast)
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
            activeUsageHintCoordinator?.presentFromMenu()
        case "voiceAnnouncement":
            voiceAnnouncementEnabled.toggle()
            store.setVoiceAnnouncementEnabled(voiceAnnouncementEnabled)
            if voiceAnnouncementEnabled {
                speakOpeningAnnouncementIfNeeded()
            } else {
                cancelPendingOpeningAnnouncement()
                ScoreVoiceAnnouncer.shared.stop()
            }
        case "pingpongPause":
            showPingPongPauseDialog = true
        case "pingpongMedical":
            showPingPongMedicalDialog = true
        case "pingpongCards":
            showPingPongCardsDialog = true
        case "toggleMatchTime":
            guard let session = matchClockSession else { break }
            session.isVisible.toggle()
            PreferencesManager.shared.setScoreboardMatchTimeVisible(session.isVisible, for: appGameType)
        case "endLink":

            showMenu = false
        default:
            break
        }
    }

    private var officialBreakSupported: Bool {
        [
            .badminton, .badmintonDoubles,
            .pingpong, .pingpongDoubles,
            .pickleball, .pickleballDoubles,
            .squash, .shuttlecock
        ].contains(gameType)
    }

    private func startOfficialBreak(
        sport: OfficialBreakSport,
        kind: OfficialBreakKind,
        durationSeconds: Int,
        afterAction: OfficialBreakAfterAction,
        source: OfficialBreakSource = .official,
        title: String? = nil,
        requiresPreference: Bool = true
    ) {
        guard (!requiresPreference || preferences.officialBreaksEnabled),
              officialBreakSession.state == nil else { return }
        officialBreakSession.begin(
            sport: sport,
            kind: kind,
            durationSeconds: durationSeconds,
            source: source,
            afterAction: afterAction,
            title: title,
            nowMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        store.setScoreInputFrozen(true)
        store.send(.setOfficialBreakState(officialBreakSession.state))
        speakOfficialBreakCue(.start)
    }

    private func completeOfficialBreak(_ action: OfficialBreakAfterAction) {
        // Scoring reducers emit completion after advancing the period/court;
        // consume the deferred action without applying the transition twice.
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
        guard voiceAnnouncementEnabled,
              let breakState = officialBreakSession.state,
              OfficialBreakVoicePolicy.shouldSpeak(
                gameType: gameType,
                cue: cue,
                state: breakState,
                officialBreaksEnabled: preferences.officialBreaksEnabled
              ),
              let payload = OfficialBreakVoiceMapper.payload(
                gameType: gameType,
                cue: cue,
                state: breakState,
                leftName: store.state.leftName,
                rightName: store.state.rightName,
                leftScore: store.state.leftPoints,
                rightScore: store.state.rightPoints,
                servingSide: store.state.servingSide,
                serverName: store.state.doubles?.serverName,
                serverNumber: store.state.doubles?.pickleballServerNumber,
                currentSet: store.state.currentSet
              ) else { return }
        ScoreVoiceAnnouncer.shared.speak(payload)
    }

    private var pingPongAdministrativeMenuItems: [ScoreboardMenuItem] {
        [
            ScoreboardMenuItem(
                title: NSLocalizedString("timeout", value: "暂停", comment: ""),
                action: "pingpongPause",
                group: .match,
                customText: "Ⅱ",
                sortOrder: 20
            ),
            ScoreboardMenuItem(
                title: NSLocalizedString("medical_timeout", value: "医疗暂停", comment: ""),
                action: "pingpongMedical",
                group: .match,
                customText: "+",
                sortOrder: 25
            ),
            ScoreboardMenuItem(
                title: NSLocalizedString("tool_red_yellow_card", value: "红黄牌", comment: ""),
                action: "pingpongCards",
                group: .match,
                customText: "🟨🟥",
                customTextScale: 0.72,
                sortOrder: 30
            )
        ]
    }

    private func pingPongTimeoutAvailable(side: MatchSide) -> Bool {
        !store.state.pingPongAdministrativeStatus(for: side).timeoutUsed
    }

    private func pingPongAdministrativeChoiceTitle(
        _ type: PingPongAdministrativeActionType,
        side: MatchSide
    ) -> String {
        let action: String = switch type {
        case .timeout: NSLocalizedString("timeout", value: "暂停", comment: "")
        case .medicalTimeout: NSLocalizedString("medical_timeout", value: "医疗暂停", comment: "")
        case .yellowCard: NSLocalizedString("yellow_card", value: "黄牌", comment: "")
        case .redCard: NSLocalizedString("red_card", value: "红牌", comment: "")
        case .forfeit: NSLocalizedString("confirm_forfeit", value: "确认判负", comment: "")
        }
        let name = side == .left ? store.state.leftName : store.state.rightName
        return "\(name) · \(action)"
    }

    private var pingPongAdministrativeMarkerOverlay: some View {
        GeometryReader { proxy in
            let keyPointVisible = KeyPointResolver.rally(state: store.state) != nil
            HStack(spacing: 34) {
                TableTennisAdministrativeCards(
                    status: pingPongMarkerStatus(forScreen: .left),
                    alignment: .trailing
                )
                TableTennisAdministrativeCards(
                    status: pingPongMarkerStatus(forScreen: .right),
                    alignment: .leading
                )
            }
            .frame(width: proxy.size.width, height: 24)
            .position(
                x: proxy.size.width / 2,
                y: ScoreboardServeGeometry.tableTennisCardsCenterY(
                    height: proxy.size.height,
                    keyPointVisible: keyPointVisible
                )
            )
        }
        .allowsHitTesting(false)
    }

    private func pingPongMarkerStatus(forScreen screenSide: MatchSide) -> TableTennisAdministrativeMarkerStatus {
        let logicalSide = TeamScreenLayout(sidesSwapped: store.state.sidesSwapped).engineSide(onScreen: screenSide)
        let status = store.state.pingPongAdministrativeStatus(for: logicalSide)
        return .init(
            timeoutUsed: status.timeoutUsed,
            hasYellowCard: status.hasYellowCard,
            redCardCount: status.redCardCount
        )
    }

    private func selectPingPongPenaltySide(_ side: MatchSide) {
        pingPongPenaltySelectedSide = side
        DispatchQueue.main.async { showPingPongPenaltyConfirmation = true }
    }

    private func pingPongPenaltySelectionTitle(side: MatchSide) -> String {
        let name = side == .left ? store.state.leftName : store.state.rightName
        return "\(name) · \(pingPongPenaltyActionDescription(for: side))"
    }

    private var pingPongPenaltyConfirmationTitle: String {
        guard let side = pingPongPenaltySelectedSide else { return "" }
        let name = side == .left ? store.state.leftName : store.state.rightName
        return "\(name) · \(pingPongPenaltyActionDescription(for: side))"
    }

    private var pingPongPenaltyConfirmButtonTitle: String {
        guard let side = pingPongPenaltySelectedSide else {
            return NSLocalizedString("confirm", value: "确认", comment: "")
        }
        return store.state.pingPongPenaltyStage(for: side) == .report
            ? NSLocalizedString("confirm_forfeit", value: "确认判负", comment: "")
            : NSLocalizedString("confirm", value: "确认", comment: "")
    }

    private var pingPongPenaltyConfirmationRole: ButtonRole? {
        guard let side = pingPongPenaltySelectedSide,
              store.state.pingPongPenaltyStage(for: side) == .report else { return nil }
        return .destructive
    }

    private func pingPongPenaltyActionDescription(for side: MatchSide) -> String {
        switch store.state.pingPongPenaltyStage(for: side) {
        case .yellow:
            return NSLocalizedString("yellow_card", value: "黄牌", comment: "")
        case .firstRed:
            return NSLocalizedString("first_red_penalty", value: "黄红牌，对手 +1", comment: "")
        case .secondRed:
            return NSLocalizedString("second_red_penalty", value: "第二张红牌，对手 +2", comment: "")
        case .report:
            return NSLocalizedString("report_referee_forfeit", value: "报告裁判并确认判负", comment: "")
        }
    }

    private func confirmPingPongPenalty() {
        guard let side = pingPongPenaltySelectedSide else { return }
        let stage = store.state.pingPongPenaltyStage(for: side)
        pingPongPenaltySelectedSide = nil
        if let actionType = stage.administrativeActionType {
            dispatch(.pingPongAdministrativeAction(type: actionType, side: side))
        } else {
            dispatch(.pingPongForfeit(side: side))
        }
    }

    // MARK: - Multipliers / chrome state

    private var scoreMultiplier: CGFloat {
        CGFloat(typographyPreference.scoreMultiplier)
    }

    private var nameMultiplier: CGFloat {
        CGFloat(typographyPreference.nameMultiplier)
    }

    private var secondaryMultiplier: CGFloat {
        CGFloat(typographyPreference.secondaryMultiplier)
    }

    private var typographyPreference: ScoreboardTypographyPreference {
        typographySession.effectivePreference
    }

    private var usesThreeDigitMainScoreCompaction: Bool {
        switch gameType {
        case .pingpong, .pingpongDoubles,
             .badminton, .badmintonDoubles,
             .pickleball, .pickleballDoubles,
             .volleyball, .beachVolleyball, .airVolleyball,
             .foosball, .foosballDoubles:
            true
        default:
            false
        }
    }

    private func resolvedTypography(
        name: String,
        score: String,
        secondary: String,
        size: CGSize,
        scoreBaseScale: CGFloat = 1,
        secondaryBaseScale: CGFloat = 1,
        reservedHeight: CGFloat = 0,
        secondaryIsInline: Bool = false,
        referenceHeight: CGFloat? = nil
    ) -> ScoreboardTypographyResult {
        let contentScale = usesThreeDigitMainScoreCompaction
            ? ScoreboardLayoutMetrics.threeDigitMainScoreScale(scoreText: score)
            : 1
        return ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: size,
                nameText: name,
                scoreText: score,
                secondaryText: secondary,
                preference: typographyPreference,
                horizontalPadding: 16,
                reservedHeight: reservedHeight,
                scoreBaseScale: scoreBaseScale * contentScale,
                secondaryBaseScale: secondaryBaseScale,
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
        guard appearance.immersiveMode, !isEditMode, !showDisplaySettings, !showMenu, !isStyleEditing else { return }
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
                  !isStyleEditing else { return }
            if let exitConfirmDeadline, Date() <= exitConfirmDeadline { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || isEditMode || isStyleEditing || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }

    private var appGameType: GameType {
        switch gameType {
        case .pingpong, .pingpongDoubles: .pingpong
        case .badminton, .badmintonDoubles: .badminton
        case .tennis, .tennisDoubles: .tennis
        case .pickleball, .pickleballDoubles: .pickleball
        case .volleyball: .volleyball
        case .airVolleyball: .airVolleyball
        case .beachVolleyball: .beachVolleyball
        case .foosball, .foosballDoubles: .foosball
        case .shuttlecock: .shuttlecock
        case .squash: .squash
        default: .simpleScore
        }
    }

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: {
                let leftSide = logicalSide(forScreen: .left)
                let rightSide = logicalSide(forScreen: .right)
                var compact = LocalScoreboardDisplayState(
                    gameID: store.gameType.rawValue,
                    title: "",
                    leftName: leftSide == .left ? store.state.leftName : store.state.rightName,
                    rightName: rightSide == .left ? store.state.leftName : store.state.rightName,
                    leftScore: "\(leftSide == .left ? store.state.leftPoints : store.state.rightPoints)",
                    rightScore: "\(rightSide == .left ? store.state.leftPoints : store.state.rightPoints)",
                    leftDetail: String(format: NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), leftSide == .left ? store.state.leftSets : store.state.rightSets),
                    rightDetail: String(format: NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), rightSide == .left ? store.state.leftSets : store.state.rightSets),
                    themeID: appearance.theme.rawValue,
                    fontID: typographyPreference.font.rawValue,
                    scoreMultiplier: typographyPreference.scoreMultiplier,
                    nameMultiplier: typographyPreference.nameMultiplier,
                    secondaryMultiplier: typographyPreference.secondaryMultiplier,
                    finished: store.state.finished,
                    keyPoint: LocalScoreboardKeyPoint.syncValue(
                        LocalScoreboardKeyPoint(
                            status: KeyPointResolver.rally(state: store.state),
                            sidesSwapped: store.state.sidesSwapped
                        ),
                        finished: store.state.finished,
                        isEditing: isEditMode
                    ),
                    revision: 0,
                    leftSets: leftSide == .left ? store.state.leftSets : store.state.rightSets,
                    rightSets: rightSide == .left ? store.state.leftSets : store.state.rightSets
                )
                let teamCourtNames = RallyDisplayProjectionResolver.teamCourtRoster(
                    gameType: gameType,
                    state: store.state
                )
                let layout: ScoreboardDisplayLayoutKind = teamCourtNames != nil
                    ? .teamCourt
                    : (isDoubles ? .doublesCourt : .twoSide)
                var displayPlayers: [ScoreboardDisplayPlayer]?
                if layout == .doublesCourt, let doubles = store.state.doubles {
                    let leftNames = doublesCornerNames(screenSide: .left)
                    let rightNames = doublesCornerNames(screenSide: .right)
                    let servingIsLeft = store.state.servingSide == leftSide
                    let serverIsTop = doublesServerIsTopRow(doubles)
                    displayPlayers = [
                        .init(id: "left_top", name: leftNames.0, teamID: "team_0", slot: "top", order: 0, isServer: servingIsLeft && serverIsTop),
                        .init(id: "right_top", name: rightNames.0, teamID: "team_1", slot: "top", order: 1, isServer: !servingIsLeft && serverIsTop),
                        .init(id: "left_bottom", name: leftNames.1, teamID: "team_0", slot: "bottom", order: 2, isServer: servingIsLeft && !serverIsTop),
                        .init(id: "right_bottom", name: rightNames.1, teamID: "team_1", slot: "bottom", order: 3, isServer: !servingIsLeft && !serverIsTop)
                    ]
                }
                var sportState: [String: ScoreboardDisplayValue] = [
                    "team0ScreenSide": .string(store.state.sidesSwapped ? "right" : "left"),
                    "servingSide": .string(store.state.servingSide == leftSide ? "left" : "right"),
                    "resultScoreLevel": .string(store.state.rules.maxSets == 1 ? "score" : "sets")
                ]
                if [.pingpong, .pingpongDoubles].contains(gameType) {
                    let team0Status = store.state.pingPongAdministrativeStatus(for: .left)
                    let team1Status = store.state.pingPongAdministrativeStatus(for: .right)
                    sportState.merge([
                        "tableTennisTeam0TimeoutUsed": .boolean(team0Status.timeoutUsed),
                        "tableTennisTeam0Yellow": .boolean(team0Status.hasYellowCard),
                        "tableTennisTeam0RedCount": .integer(team0Status.redCardCount),
                        "tableTennisTeam1TimeoutUsed": .boolean(team1Status.timeoutUsed),
                        "tableTennisTeam1Yellow": .boolean(team1Status.hasYellowCard),
                        "tableTennisTeam1RedCount": .integer(team1Status.redCardCount)
                    ]) { _, new in new }
                }
                if let teamCourtNames {
                    sportState["competitionFormat"] = .string("team")
                    sportState["teamCourtPlayers"] = .strings(teamCourtNames)
                }
                compact.externalState = ScoreboardDisplayState.enriched(
                    compact: compact,
                    layoutKind: layout,
                    players: displayPlayers,
                    sportState: sportState,
                    rest: officialBreakSession.state.map(ScoreboardDisplayRest.init)
                )
                if store.state.finished,
                   store.state.pingPongForfeitSide != nil,
                   let winnerSide = RallyFinishedScorePresentation.winnerSide(for: store.state),
                   var result = compact.externalState?.result {
                    result.winnerID = winnerSide == .left ? "team_0" : "team_1"
                    compact.externalState?.result = result
                }
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
            },
            handleIntent: { intent in
                guard LocalScoreboardMutationPolicy.allowsMutation(
                    isEditing: isEditMode,
                    finished: store.state.finished,
                    scoringLocked: scoringLocked
                ) else { return }
                switch intent {
                case .addLeft: dispatch(.pointWon(logicalSide(forScreen: .left)))
                case .addRight: dispatch(.pointWon(logicalSide(forScreen: .right)))
                case .subtractLeft:
                    guard let side = rallyLocalSubtractSide(
                        onScreen: .left,
                        state: store.state,
                        presentedSidesSwapped: terminalSetPresentation?.sidesSwapped
                    ) else { return }
                    dispatch(.adjustPoints(side: side, delta: -1))
                case .subtractRight:
                    guard let side = rallyLocalSubtractSide(
                        onScreen: .right,
                        state: store.state,
                        presentedSidesSwapped: terminalSetPresentation?.sidesSwapped
                    ) else { return }
                    dispatch(.adjustPoints(side: side, delta: -1))
                case .undo:
                    performUndo()
                case .exchangeSides: dispatch(.exchangeSides)
                case .requestSnapshot: break
                }
            }
        )
    }

    private func logicalSide(forScreen side: MatchSide) -> MatchSide {
        TeamScreenLayout(
            sidesSwapped: terminalSetPresentation?.sidesSwapped ?? store.state.sidesSwapped
        ).engineSide(onScreen: side)
    }

    private func requestBack() {
        let now = Date()
        if exitConfirmDeadline.map({ now <= $0 }) != true {
            exitConfirmDeadline = now.addingTimeInterval(2)
            showToast(NSLocalizedString("press_again_to_exit", value: "再按一次退出", comment: ""))
            revealImmersiveChrome()
            return
        }
        back()
    }

    private func back() {
        cancelTerminalSetPresentation()
        OrientationLock.shared.unlock()

        store.flush {
            if let onNavigationBack {
                onNavigationBack()
            } else {
                dismiss()
            }
        }
    }

    private func finishMatch() {
        dispatch(.finish)
    }

    private func adjustPointsInEdit(side: MatchSide, delta: Int) {
        let current = side == .left ? store.state.leftPoints : store.state.rightPoints
        let opponent = side == .left ? store.state.rightPoints : store.state.leftPoints
        guard store.state.rules.allowsPointAdjustment(
            currentScore: current,
            opponentScore: opponent,
            setNumber: store.state.currentSet,
            delta: delta
        ) else {
            showToast(NSLocalizedString("scoreboard_main_score_overflow", value: "大分超限", comment: ""))
            return
        }
        dispatch(.adjustPoints(side: side, delta: delta))
    }

    private func adjustSetsInEdit(side: MatchSide, delta: Int) {
        let left = store.state.leftSets + (side == .left ? delta : 0)
        let right = store.state.rightSets + (side == .right ? delta : 0)
        guard store.state.rules.matchCompletionMode.allowsSetScore(
            maxSets: store.state.rules.maxSets,
            leftSets: left,
            rightSets: right
        ) else {
            showToast(NSLocalizedString("scoreboard_set_score_overflow", value: "局分超限", comment: ""))
            return
        }
        dispatch(.adjustSets(side: side, delta: delta))
    }

    private func dispatch(
        _ intent: RallyMatchIntent,
        onApplied: (() -> Void)? = nil
    ) {
        guard !scoringLocked else { return }
        switch intent {
        case .pointWon:
            cancelPendingOpeningAnnouncement()
        case .adjustPoints, .adjustSets, .exchangeSides, .reset:
            cancelPendingOpeningAnnouncement()
            ScoreVoiceAnnouncer.shared.cancelPendingScore()
        default:
            break
        }
        store.send(intent, onTransition: { before, after, events in
            handleVoiceAnnouncement(before: before, after: after, events: events)
            handleEvents(events, before: before, after: after)
            onApplied?()
        })
    }

    private func handleEvents(
        _ events: [RallyMatchEvent],
        before: RallyMatchState,
        after: RallyMatchState
    ) {
        var setToast: String?
        var sideToast: String?
        var matchFinished = false
        var terminalScore: (left: Int, right: Int)?

        for event in events {
            switch event {
            case .setCompleted(let winner, let setNumber, let leftPoints, let rightPoints, _, _):
                terminalScore = (leftPoints, rightPoints)
                let winnerName = winner == .left ? after.leftName : after.rightName
                setToast = String(
                    format: NSLocalizedString("set_ended_winner", value: "第%d局结束，%@获胜，比分 %d-%d", comment: ""),
                    setNumber,
                    winnerName,
                    leftPoints,
                    rightPoints
                )
            case .sidesExchanged:
                sideToast = NSLocalizedString("change_sides", value: "换边", comment: "")
            case .sidesExchangeReminder:
                sideToast = NSLocalizedString("please_change_sides_manually", value: "请手动换边", comment: "")
            case .matchFinished:
                matchFinished = true
            case .pointScored, .pointsAdjusted, .sideOut:
                break
            case .pingPongAdministrativeAction(let action):
                let label: String
                switch action.type {
                case .timeout: label = NSLocalizedString("timeout", value: "暂停", comment: "")
                case .medicalTimeout: label = NSLocalizedString("medical_timeout", value: "医疗暂停", comment: "")
                case .yellowCard: label = NSLocalizedString("yellow_card", value: "黄牌", comment: "")
                case .redCard: label = NSLocalizedString("red_card", value: "红牌", comment: "")
                case .forfeit: label = NSLocalizedString("confirm_forfeit", value: "确认判负", comment: "")
                }
                sideToast = label
                if action.type == .timeout || action.type == .medicalTimeout {
                    startOfficialBreak(
                        sport: .pingpong,
                        kind: action.type == .timeout ? .timeout : .medical,
                        durationSeconds: action.type == .timeout ? 60 : 600,
                        afterAction: .none,
                        source: .administrative,
                        title: pingPongAdministrativeChoiceTitle(action.type, side: action.side),
                        requiresPreference: false
                    )
                }
            case .officialBreakChanged:
                break
            case .matchReset:
                didSpeakOpeningAnnouncement = false
                speakOpeningAnnouncementIfNeeded()
            }
        }

        if preferences.officialBreaksEnabled, officialBreakSession.state == nil {
            let completedSet = events.contains { event in
                if case .setCompleted = event { return true }
                return false
            }
            if completedSet, !matchFinished {
                switch gameType {
                case .badminton, .badmintonDoubles:
                    startOfficialBreak(sport: .badminton, kind: .gameBreak, durationSeconds: 120, afterAction: .advanceAndExchange)
                case .pingpong, .pingpongDoubles:
                    startOfficialBreak(sport: .pingpong, kind: .gameBreak, durationSeconds: 60, afterAction: .advanceAndExchange)
                case .pickleball, .pickleballDoubles:
                    startOfficialBreak(sport: .pickleball, kind: .gameBreak, durationSeconds: 120, afterAction: .advanceAndExchange)
                case .squash:
                    startOfficialBreak(sport: .squash, kind: .gameBreak, durationSeconds: 90, afterAction: .advancePeriod)
                case .shuttlecock:
                    startOfficialBreak(sport: .shuttlecock, kind: .gameBreak, durationSeconds: 60, afterAction: .advanceAndExchange)
                default: break
                }
            } else if events.contains(where: { event in
                if case .pointScored = event { return true }
                return false
            }) {
                let midpoint = max(1, (after.rules.target(for: after.currentSet) + 1) / 2)
                let reachedMidpoint = max(after.leftPoints, after.rightPoints) == midpoint
                    && max(before.leftPoints, before.rightPoints) < midpoint
                if reachedMidpoint, [.badminton, .badmintonDoubles].contains(gameType) {
                    let action: OfficialBreakAfterAction = after.currentSet == after.rules.maxSets
                        ? .exchangeSides
                        : .none
                    startOfficialBreak(sport: .badminton, kind: .midGame, durationSeconds: 60, afterAction: action)
                } else if reachedMidpoint,
                          [.pickleball, .pickleballDoubles].contains(gameType),
                          after.currentSet == after.rules.maxSets {
                    startOfficialBreak(sport: .pickleball, kind: .midGame, durationSeconds: 60, afterAction: .exchangeSides)
                }
            }
        }

        if let terminalScore {
            beginTerminalSetPresentation(
                score: terminalScore,
                previousState: before,
                setToast: setToast,
                sideToast: sideToast,
                matchFinished: matchFinished
            )
        } else if let sideToast {
            showToast(sideToast)
            if matchFinished {
                showGameOverDialog = true
            }
        } else if matchFinished {
            showGameOverDialog = true
        }
    }

    private func beginTerminalSetPresentation(
        score: (left: Int, right: Int),
        previousState: RallyMatchState,
        setToast: String?,
        sideToast: String?,
        matchFinished: Bool
    ) {
        let presentation = RallyTerminalSetPresentation(
            leftPoints: score.left,
            rightPoints: score.right,
            leftSets: previousState.leftSets,
            rightSets: previousState.rightSets,
            sidesSwapped: previousState.sidesSwapped
        )
        terminalHold.begin(presentation) {
            publishCurrentRallyState()
            // 决胜局直接交给比赛结果面板，避免“本局结束” toast 与结果重复。
            if !matchFinished {
                if let setToast {
                    showToast(setToast)
                }
                if let sideToast {
                    showToast(sideToast)
                }
            }
            if matchFinished {

                showGameOverDialog = true
            }
        }
    }

    private func displayedPoints(for side: MatchSide) -> Int {
        if let terminalSetPresentation {
            return side == .left ? terminalSetPresentation.leftPoints : terminalSetPresentation.rightPoints
        }
        return side == .left ? store.state.leftPoints : store.state.rightPoints
    }

    private func displayedSets(for side: MatchSide) -> Int {
        if let terminalSetPresentation {
            return side == .left ? terminalSetPresentation.leftSets : terminalSetPresentation.rightSets
        }
        return side == .left ? store.state.leftSets : store.state.rightSets
    }

    private func cancelTerminalSetPresentation() {
        terminalHold.cancel()
    }

    private func publishCurrentRallyState() {
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }



    private func handleVoiceAnnouncement(
        before: RallyMatchState,
        after: RallyMatchState,
        events: [RallyMatchEvent]
    ) {
        guard voiceAnnouncementEnabled,
              VoiceAnnouncementSupport.isSupported(gameType) else { return }

        let payloads = RallyVoiceAnnouncementMapper.payloads(
            gameType: gameType,
            before: before,
            after: after,
            events: events,
            completedSetScores: store.completedSetScores
        )
        ScoreVoiceAnnouncer.shared.speak(payloads)
    }

    private func speakOpeningAnnouncementIfNeeded() {
        guard voiceAnnouncementEnabled,
              !didSpeakOpeningAnnouncement,
              openingAnnouncementTask == nil,
              RallyVoiceAnnouncementMapper.openingPayload(gameType: gameType, state: store.state) != nil
        else { return }
        openingAnnouncementTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2_500))
            guard !Task.isCancelled,
                  voiceAnnouncementEnabled,
                  !didSpeakOpeningAnnouncement,
                  let payload = RallyVoiceAnnouncementMapper.openingPayload(gameType: gameType, state: store.state)
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

    private var finishedWinnerName: String {
        switch RallyFinishedScorePresentation.winnerSide(for: store.state) {
        case .left: store.state.leftName
        case .right: store.state.rightName
        case nil: ""
        }
    }

    private func shareFinishedMatch() {
        let displayScores = RallyFinishedScorePresentation.scores(for: store.state)
        ScoreboardShareSupport.present(
            text: "\(store.state.leftName) \(displayScores.left) - \(displayScores.right) \(store.state.rightName)"
        )
    }

    private func startNewMatch() {
        guard !scoringLocked, !isStartingNewMatch else { return }
        cancelTerminalSetPresentation()
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
                bindMatchClock()
                manualFinishRequested = false
                didSpeakOpeningAnnouncement = false
                pendingDoublesFlash = nil
                flashSlots.removeAll()
                showGameOverDialog = false
                syncEditNamesFromState()
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()

                speakOpeningAnnouncementIfNeeded()
            }
        }
    }

    private func bindMatchClock() {
        guard let matchClockSession else { return }
        let boundStore = store
        matchClockSession.bind(
            startedAt: boundStore.startedAt,
            isVisible: boundStore.showMatchTimeEnabled
        ) { [weak boundStore] visible in
            boundStore?.setShowMatchTimeEnabled(visible)
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

    private func performUndo() {
        guard !isEditMode,
              (!store.state.finished || terminalSetPresentation != nil) else { return }
        cancelTerminalSetPresentation()
        ScoreVoiceAnnouncer.shared.cancelPendingScore()
        store.undo { success in
            if success {
                showToast(NSLocalizedString("undone", value: "已撤销", comment: ""))
            } else {
                showToast(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
            }
        }
    }
}
