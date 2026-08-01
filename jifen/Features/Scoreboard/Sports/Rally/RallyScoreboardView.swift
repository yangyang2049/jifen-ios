import LinkCore
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
}
import UIKit

struct RallyScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService

    let gameType: ScoreCore.GameType
    let onNavigationBack: (() -> Void)?
    let onPresented: () -> Void
    @State private var voiceAnnouncementEnabled: Bool
    @State private var store: RallySessionStore
    @State private var watchSessionId: UUID?
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var toastMessage: String?
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession: ScoreboardTypographySession
    @State private var preferences = PreferencesManager.shared
    @State private var showDisplaySettings = false
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
    @State private var resumeSaveGeneration = 0
    @State private var completedSetScores: [VoiceSetScore] = []
    @State private var didSpeakOpeningAnnouncement = false
    @State private var manualFinishRequested = false
    @State private var isStartingNewMatch = false

    init(
        leftName: String,
        rightName: String,
        gameType: ScoreCore.GameType,
        rules: RallyRuleSet,
        participants: [SessionParticipant]? = nil,
        openingServer: MatchSide = .left,
        voiceAnnouncementEnabled: Bool = false,
        initialWatchSessionId: UUID? = nil,
        initialResumeSessionId: String? = nil,
        onNavigationBack: (() -> Void)? = nil,
        onPresented: @escaping () -> Void = {}
    ) {
        self.onNavigationBack = onNavigationBack
        self.onPresented = onPresented
        _watchSessionId = State(initialValue: initialWatchSessionId)

        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let restoredStore = RallySessionStore(restoring: sessionId) {
            self.gameType = restoredStore.gameType
            _store = State(initialValue: restoredStore)
            _voiceAnnouncementEnabled = State(initialValue: voiceAnnouncementEnabled)
            _showGameOverDialog = State(initialValue: restoredStore.state.finished)
        } else {
            self.gameType = gameType
            let newStore = RallySessionStore(
                leftName: leftName,
                rightName: rightName,
                gameType: gameType,
                rules: rules,
                participants: participants,
                openingServer: openingServer,
                voiceAnnouncementEnabled: voiceAnnouncementEnabled
            )
            _store = State(initialValue: newStore)
            _voiceAnnouncementEnabled = State(initialValue: voiceAnnouncementEnabled)
        }
        _typographySession = State(initialValue: ScoreboardTypographySession(
            styleID: ScoreboardStyleID(scoreCoreGameType: self.gameType)
        ))
    }

    private var isDoubles: Bool { store.state.doubles != nil }
    private var isFoosballDoubles: Bool {
        guard let doubles = store.state.doubles else { return false }
        if case .foosball = doubles.rotation { return true }
        return gameType == .foosballDoubles
    }
    private var scoringLocked: Bool {
        watchSessionId != nil
            && (watchLinkService.isFollower || watchLinkService.isAuthorityTransferPending)
    }
    private var palette: ScoreboardPalette { appearance.theme.palette }
    private var linkedNewGameLabel: String {
        NSLocalizedString(
            "game_over_new_game_on_watch",
            value: "再来一场\n（请在手表端操作）",
            comment: ""
        )
    }

    /// 桌上足球无发球模型（对齐鸿蒙/安卓）。
    private var showsServeIndicator: Bool {
        switch gameType {
        case .foosball, .foosballDoubles: return false
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
                    if isFoosballDoubles {
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

                if !isEditMode && showsServeIndicator {
                    serveIndicatorOverlay(size: proxy.size, triangleSize: serveIndicatorSize)
                }

                if !isEditMode && !store.state.finished {
                    ScoreboardKeyPointBadgeLayer(
                        status: KeyPointResolver.rally(state: store.state),
                        gameType: gameType,
                        sidesSwapped: store.state.sidesSwapped,
                        doublesTopRow: keyPointDoublesTopRow,
                        serveIndicatorSize: serveIndicatorSize
                    )
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
                    showEndGame: true,
                    items: menuItems,
                    analyticsGameType: GameType(scoreCoreGameType: store.gameType) ?? .simpleScore
                )

                if showGameOverDialog {
                    let displayScores = RallyFinishedScorePresentation.scores(for: store.state)
                    GameOverDialog(
                        winnerName: finishedWinnerName,
                        gameType: GameType(scoreCoreGameType: store.gameType) ?? .simpleScore,
                        leftName: store.state.leftName,
                        rightName: store.state.rightName,
                        leftScore: displayScores.left,
                        rightScore: displayScores.right,
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
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
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
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            registerScoreboardSync()
            if let watchSessionId,
               let update = watchLinkService.attachPage(sessionId: watchSessionId),
               let rally = update.snapshot.rallyState {
                Task {
                    _ = await store.applyAuthoritativeState(
                        rally,
                        detailedActions: update.detailedActions,
                        revision: update.revision,
                        persistFormalRecord: false
                    )
                }
            }
            revealImmersiveChrome()
            if store.state.finished {
                showGameOverDialog = true
            }
            speakOpeningAnnouncementIfNeeded()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: store.state) { previous, state in
            if pendingDoublesFlash != nil,
               previous.leftPoints != state.leftPoints || previous.rightPoints != state.rightPoints {
                processPendingDoublesFlash()
            }
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            if let watchSessionId, watchLinkService.isController {
                watchLinkService.syncWatch(
                    sessionId: watchSessionId,
                    gameType: gameType,
                    state: state,
                    detailedActions: store.actionTimeline
                )
            }
            if state.finished {
                showGameOverDialog = true
                if let watchSessionId, watchLinkService.isController {
                    let winner: MatchSide? = state.leftSets == state.rightSets
                        ? nil
                        : (state.leftSets > state.rightSets ? .left : .right)
                    watchLinkService.notifyMatchFinished(
                        sessionId: watchSessionId,
                        snapshot: .rally(state),
                        recordId: store.sessionId.uuidString,
                        winnerSide: winner,
                        manualEnd: manualFinishRequested
                    )
                }
            }
            // Follower relies on LinkedMatchRecordIngestor; don't write a second phone record.
            if !(watchLinkService.isFollower && state.finished) {
                scheduleResumePersist(finished: state.finished)
            }
        }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId,
                  let update,
                  update.sessionId == watchSessionId,
                  let rally = update.snapshot.rallyState else { return }
            Task {
                _ = await store.applyAuthoritativeState(
                    rally,
                    detailedActions: update.detailedActions,
                    revision: update.revision,
                    persistFormalRecord: false
                )
            }
        }
        .onChange(of: watchLinkService.pendingTakeoverApplication) { _, pending in
            guard let watchSessionId,
                  let pending,
                  pending.sessionId == watchSessionId,
                  let state = pending.snapshot.rallyState else { return }
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
        .onChange(of: store.persistenceFailureSignal) { _, signal in
            guard signal > 0 else { return }
            showToast(NSLocalizedString(
                "scoreboard_save_failed",
                value: "保存失败，请稍后重试",
                comment: "Scoreboard persistence failed"
            ))
        }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveForBlocking() }
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
            flashTask?.cancel()
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
            // Capture before leave — ending the session clears follower role.
            let skipPersist = watchSessionId != nil
                && (watchLinkService.isFollower || watchLinkService.finishedRecordId != nil)
            if let watchSessionId {
                watchLinkService.detachPage(sessionId: watchSessionId)
            }
            // Linked follower finishes are ingested via matchFinished — do not write a resume or second record.
            if !skipPersist {
                store.persistSnapshot()
            }
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.rally.adjustableMetrics
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
                    snapshot: .rally(store.state),
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
    }

    // MARK: - Singles

    private func singlesHalf(screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let isLeft = side == .left
        let color = isLeft ? palette.left : palette.right

        return ZStack {
            color
            if isEditMode {
                singlesEditContent(side: side, size: size)
            } else {
                singlesPlayContent(side: side, size: size)
            }
        }
        .foregroundStyle(palette.foreground)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !store.state.finished else { return }
            handlePointWon(side)
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        performUndo()
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
                        dispatch(.adjustPoints(side: side, delta: -1))
                    }
                }
        )
    }

    private func singlesPlayContent(side: MatchSide, size: CGSize) -> some View {
        let isLeft = side == .left
        let name = scoreboardDisplayName(for: side)
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
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

        return VStack(spacing: 0) {
            Text(name)
                .font(typographyPreference.font.swiftUIFont(size: nameSize, weight: .bold))
                .lineLimit(isFoosballDoubles ? 2 : 1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
            Spacer().frame(height: nameToMain)
            Text("\(score)")
                .font(typographyPreference.font.swiftUIFont(size: mainSize))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer().frame(height: mainToSet)
            Text("\(sets)")
                .font(typographyPreference.font.swiftUIFont(size: setSize))
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                placeholder: NSLocalizedString("team_name", value: "队名", comment: ""),
                text: isLeft ? $editLeftName : $editRightName,
                nameType: .team,
                scoreboardFont: typographyPreference.font,
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

        return ZStack {
            color
            if isEditMode {
                foosballDoublesEditContent(side: side, size: size)
            } else {
                singlesPlayContent(side: side, size: size)
            }
        }
        .foregroundStyle(palette.foreground)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !store.state.finished else { return }
            handlePointWon(side)
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        performUndo()
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
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
        let joinedName = [editDoublesNames[slots.0], editDoublesNames[slots.1]].max(by: { $0.count < $1.count }) ?? ""
        let typography = resolvedTypography(
            name: joinedName,
            score: "\(score)",
            secondary: "\(sets)",
            size: size,
            reservedHeight: 48
        )
        let mainSize = ScoreboardLayoutMetrics.editMainScoreFontSize(
            regularSize: typography.scoreFontSize
        )
        let setSize = typography.secondaryFontSize
        let nameToMain = typography.nameToScoreSpacing
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: size.height))
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
        .foregroundStyle(palette.foreground)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !store.state.finished else { return }
            handlePointWon(side)
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        performUndo()
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
                        dispatch(.adjustPoints(side: side, delta: -1))
                    }
                }
        )
    }

    private func doublesPlayScoreRow(screenSide: MatchSide, side: MatchSide, height: CGFloat, panelSize: CGSize) -> some View {
        let isLeft = side == .left
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let typography = resolvedTypography(
            name: "",
            score: "\(score)",
            secondary: "\(sets)",
            size: CGSize(width: panelSize.width, height: height),
            secondaryIsInline: true,
            referenceHeight: panelSize.height
        )
        let mainSize = typography.scoreFontSize
        let setSize = typography.secondaryFontSize
        let scoreSpacing = typography.mainToSecondarySpacing

        return HStack(spacing: scoreSpacing) {
            if screenSide == .left {
                Text("\(score)")
                    .font(typographyPreference.font.swiftUIFont(size: mainSize))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("\(sets)")
                    .font(typographyPreference.font.swiftUIFont(size: setSize))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
            } else {
                Text("\(sets)")
                    .font(typographyPreference.font.swiftUIFont(size: setSize))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
                Text("\(score)")
                    .font(typographyPreference.font.swiftUIFont(size: mainSize))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
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
                    accessibilityIdentifier: "rally_doubles_player_\(slot)_editor"
                )
            } else {
                Text(name)
                    .font(typographyPreference.font.swiftUIFont(size: fontSize, weight: .bold))
                    .foregroundStyle(nameColor)
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
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Swift.min(20, size * 0.4), weight: .bold))
                .foregroundStyle(enabled ? palette.foreground.opacity(0.75) : palette.foreground.opacity(0.3))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.08)))
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
        let scoringSide: MatchSide
        let prevServingSide: MatchSide
    }

    private func handlePointWon(_ side: MatchSide) {
        // 仅羽毛球/匹克球双打有位置轮转，发球方得分时高亮该队两人以提示换位；
        // 乒乓球、桌上足球双打无轮转，不闪烁。
        if isDoubles, gameType == .badmintonDoubles || gameType == .pickleballDoubles {
            pendingDoublesFlash = PendingDoublesFlash(
                scoringSide: side,
                prevServingSide: store.state.servingSide
            )
        }
        dispatch(.pointWon(side))
        revealImmersiveChrome()
    }

    private func processPendingDoublesFlash() {
        guard let pending = pendingDoublesFlash else { return }
        pendingDoublesFlash = nil

        let slots: Set<Int>
        if pending.scoringSide == pending.prevServingSide {
            slots = pending.scoringSide == .left ? [0, 2] : [1, 3]
        } else if let newSlot = store.state.doubles?.serverSlotIndex {
            slots = [newSlot]
        } else {
            return
        }
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
        guard showsServeIndicator, let serverSlot = store.state.doubles?.serverSlotIndex else { return nil }
        return serverSlot == 0 || serverSlot == 1
    }

    @ViewBuilder
    private func serveIndicatorOverlay(size: CGSize, triangleSize: CGFloat) -> some View {
        let servingIsLeftScreen: Bool = {
            let serving = store.state.servingSide
            let leftLogical = logicalSide(forScreen: .left)
            return serving == leftLogical
        }()

        if isDoubles, let doubles = store.state.doubles {
            let serverSlot = doubles.serverSlotIndex
            let isTopRow = serverSlot == 0 || serverSlot == 1
            let serverNumberText = doubles.pickleballServerNumber.map(String.init) ?? ""
            let serverNumberSize = resolvedTypography(
                name: "",
                score: "",
                secondary: serverNumberText,
                size: CGSize(width: max(64, triangleSize * 2.4), height: max(80, triangleSize * 3)),
                secondaryBaseScale: 0.3
            ).secondaryFontSize
            ZStack {
                CenterLineServeIndicator(
                    isLeftServing: servingIsLeftScreen,
                    triangleSize: triangleSize
                )
                if let serverNumber = doubles.pickleballServerNumber {
                    Text("\(serverNumber)")
                        .font(typographyPreference.font.swiftUIFont(size: serverNumberSize, weight: .bold))
                        .foregroundStyle(palette.foreground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .offset(y: isTopRow ? triangleSize * 0.78 : -triangleSize * 0.78)
                }
            }
            .position(
                x: size.width / 2,
                y: ScoreboardServeGeometry.doublesAnchorY(height: size.height, topRow: isTopRow)
            )
            .allowsHitTesting(false)
        } else {
            CenterLineServeIndicator(
                isLeftServing: servingIsLeftScreen,
                triangleSize: triangleSize
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

    private var menuItems: [ScoreboardMenuItem] {
        var extras: [ScoreboardMenuItem] = []
        extras.append(contentsOf: WatchLinkMenuSupport.extraItems(
            entryEnabled: AppFeatureFlags.watchLinkEntryEnabled,
            sessionId: watchSessionId,
            isFollower: watchLinkService.isFollower,
            watchBackgrounded: watchLinkService.watchBackgrounded
        ))
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
            scoringEnabled: !scoringLocked,
            extraItems: extras
        )
    }

    private func handleMenuAction(_ action: String) {
        if scoringLocked,
           !ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked(action) {
            showToast(NSLocalizedString("linked_score_phone_follower", value: "当前由手表计分", comment: ""))
            return
        }
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            performUndo()
        case "exchangeSide":
            if menuConfirm.armOrConfirm(.exchangeSide) {
                dispatch(.exchangeSides)
            } else {
                showToast(ScoreboardMenuConfirmAction.exchangeSide.localizedToast)
            }
        case "reset":
            if menuConfirm.armOrConfirm(.reset) {
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
            showDisplaySettings = true
            showMenu = false
        case "voiceAnnouncement":
            voiceAnnouncementEnabled.toggle()
            store.voiceAnnouncementEnabled = voiceAnnouncementEnabled
            if voiceAnnouncementEnabled {
                speakOpeningAnnouncementIfNeeded()
            } else {
                ScoreVoiceAnnouncer.shared.stop()
            }
            scheduleResumePersist(finished: store.state.finished)
        case "resync":
            watchLinkService.requestScoreResync()
            showMenu = false
        case "takeover":
            Task {
                if let id = watchSessionId {
                    if let update = watchLinkService.latestRemoteSnapshot,
                       update.sessionId == id,
                       let state = update.snapshot.rallyState {
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
        default:
            break
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
             .pickleball, .pickleballDoubles:
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

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || isEditMode || !appearance.immersiveMode {
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
        default: .simpleScore
        }
    }

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: {
                let leftSide = logicalSide(forScreen: .left)
                let rightSide = logicalSide(forScreen: .right)
                return LocalScoreboardDisplayState(
                    gameID: appGameType.canonicalScoreboardIdentifier,
                    title: appGameType.displayName,
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
                case .addLeft: dispatch(.pointWon(logicalSide(forScreen: .left)))
                case .addRight: dispatch(.pointWon(logicalSide(forScreen: .right)))
                case .subtractLeft:
                    let side = logicalSide(forScreen: .left)
                    guard store.state.leftPoints > 0, !store.state.finished else { return }
                    dispatch(.adjustPoints(side: side, delta: -1))
                case .subtractRight:
                    let side = logicalSide(forScreen: .right)
                    guard store.state.rightPoints > 0, !store.state.finished else { return }
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
        store.teamScreenLayout.engineSide(onScreen: side)
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

    private func dispatch(_ intent: RallyMatchIntent) {
        guard !scoringLocked else { return }
        let before = store.state
        store.send(intent) { events in
            handleVoiceAnnouncement(before: before, events: events)
            handleEvents(events)
        }
    }

    private func handleEvents(_ events: [RallyMatchEvent]) {
        var setToast: String?
        var sideToast: String?
        var matchFinished = false

        for event in events {
            switch event {
            case .setCompleted(let winner, let setNumber, let leftPoints, let rightPoints, _, _):
                let winnerName = winner == .left ? store.state.leftName : store.state.rightName
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
            case .matchReset:
                completedSetScores = []
                didSpeakOpeningAnnouncement = false
                speakOpeningAnnouncementIfNeeded()
            }
        }

        if let setToast {
            showToast(setToast)
            if let sideToast {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                    showToast(sideToast)
                }
            }
        } else if let sideToast {
            showToast(sideToast)
        }

        if matchFinished {
            showGameOverDialog = true
            store.persistSnapshot()
        }
    }

    private func handleVoiceAnnouncement(before: RallyMatchState, events: [RallyMatchEvent]) {
        guard voiceAnnouncementEnabled,
              VoiceAnnouncementSupport.isSupported(gameType) else { return }

        // Append completed set first (Android / Harmony order), then flip history on exchange.
        for event in events {
            if case let .setCompleted(_, _, leftPoints, rightPoints, _, _) = event {
                completedSetScores.append(VoiceSetScore(leftGames: leftPoints, rightGames: rightPoints))
            }
        }
        let sideChanged = events.contains {
            if case .sidesExchanged = $0 { return true }
            return false
        }
        if sideChanged {
            completedSetScores = completedSetScores.map { $0.swapped() }
        }

        let payloads = RallyVoiceAnnouncementMapper.payloads(
            gameType: gameType,
            before: before,
            after: store.state,
            events: events,
            completedSetScores: completedSetScores
        )
        for payload in payloads {
            ScoreVoiceAnnouncer.shared.speak(payload)
        }
    }

    private func speakOpeningAnnouncementIfNeeded() {
        guard voiceAnnouncementEnabled,
              !didSpeakOpeningAnnouncement,
              let payload = RallyVoiceAnnouncementMapper.openingPayload(gameType: gameType, state: store.state)
        else { return }
        didSpeakOpeningAnnouncement = true
        ScoreVoiceAnnouncer.shared.speak(payload)
    }

    private var finishedWinnerName: String {
        if store.state.leftSets == store.state.rightSets { return "" }
        return store.state.leftSets > store.state.rightSets ? store.state.leftName : store.state.rightName
    }

    private func shareFinishedMatch() {
        let displayScores = RallyFinishedScorePresentation.scores(for: store.state)
        ScoreboardShareSupport.present(
            text: "\(store.state.leftName) \(displayScores.left) - \(displayScores.right) \(store.state.rightName)"
        )
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
                completedSetScores = []
                didSpeakOpeningAnnouncement = false
                pendingDoublesFlash = nil
                flashSlots.removeAll()
                showGameOverDialog = false
                syncEditNamesFromState()
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                if let watchSessionId {
                    let participantNames = freshStore.state.doubles?.playerNames
                        ?? [freshStore.state.leftName, freshStore.state.rightName]
                    watchLinkService.prepareControllerForNewMatch(
                        sessionId: watchSessionId,
                        gameType: gameType,
                        snapshot: .rally(freshStore.state),
                        participantNames: participantNames
                    )
                }
                speakOpeningAnnouncementIfNeeded()
            }
        }
    }

    private var hasMatchProgress: Bool {
        store.state.leftPoints > 0
            || store.state.rightPoints > 0
            || store.state.leftSets > 0
            || store.state.rightSets > 0
            || store.state.finished
    }

    private func scheduleResumePersist(finished: Bool) {
        guard finished || hasMatchProgress else { return }
        resumeSaveGeneration += 1
        let generation = resumeSaveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard generation == resumeSaveGeneration else { return }
            store.persistSnapshot()
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
        guard !isEditMode, !scoringLocked, !store.state.finished else { return }
        store.undo { success in
            if success {
                scheduleResumePersist(finished: store.state.finished)
                showToast(NSLocalizedString("undone", value: "已撤销", comment: ""))
            } else {
                showToast(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
            }
        }
    }
}
