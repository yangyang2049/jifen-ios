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
    @State private var preferences = PreferencesManager.shared
    @State private var toastMessage: String?
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
            ZStack {
                HStack(spacing: 0) {
                    half(.left, size: size)
                    half(.right, size: size)
                }
                if !isEditMode,
                   !store.state.finished,
                   store.state.doublesPlayerNames == nil {
                    CenterLineServeIndicator(
                        isLeftServing: logicalSide(forScreen: .left) == store.state.servingSide,
                        triangleSize: ScoreboardServeGeometry.triangleSize
                    )
                    .position(x: size.width / 2, y: size.height / 2)
                }
                VStack {
                    HStack {
                        if !isEditMode {
                            Button(action: goBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(Circle().fill(Color.black.opacity(0.35)))
                                    .frame(width: 64, height: 64)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(ScoreboardConstants.backButtonAccessibilityID)
                        }
                        Spacer()
                        if (isEditMode || !store.state.finished), !scoringLocked {
                            Button(action: toggleEditMode) {
                                Image(systemName: isEditMode ? "checkmark" : "pencil")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(Circle().fill(
                                        isEditMode ? Color(hex: "00C853") : Color.black.opacity(0.35)
                                    ))
                                    .frame(width: 64, height: 64)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isEditMode
                                ? NSLocalizedString("done", value: "完成", comment: "")
                                : NSLocalizedString("edit", value: "编辑", comment: ""))
                            .accessibilityIdentifier("tennis_scoreboard_edit_button")
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .zIndex(2)
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
                        doublesTopRow: store.gameType == .tennisDoubles ? tennisDoublesServerIsTopRow : nil
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
                    items: menuItems
                )
                if !isEditMode, !showMenu, !showGameOverDialog {
                    // Match the common scoreboard chrome: the operation menu lives at bottom right.
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                showMenu = true
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: ScoreboardConstants.buttonIconSize))
                                    .foregroundStyle(.white)
                                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                                    .background(Circle().fill(Color.black.opacity(0.35)))
                                    .frame(width: 64, height: 64)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(NSLocalizedString("menu", value: "菜单", comment: "Menu"))
                            .accessibilityIdentifier("scoreboard_menu_button")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .zIndex(100)
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
        .lockOrientation(.landscape)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    guard !isEditMode else { return }
                    showMenu = true
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
            onSetupConsumed?()
            if let id = initialRecordId, let uuid = UUID(uuidString: id),
               let restored = TennisSessionStore(restoring: uuid) {
                store = restored
            }
            syncEditNamesFromState()
            registerScoreboardSync()
            if store.state.finished { showGameOverDialog = true }
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
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
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            gameType: GameType(scoreCoreGameType: store.gameType) ?? .tennis
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
        let nameSize = ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: size.height)
            * tennisNameMultiplier

        return VStack(spacing: 0) {
            Text(name)
                .font(.system(size: nameSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 72)
                .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: size.height))
            Spacer(minLength: 0)
            tennisScoreRow(
                screenSide: screenSide,
                side: side,
                height: size.height * 0.56,
                panelHeight: size.height
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tennisSinglesEditContent(side: MatchSide, size: CGSize) -> some View {
        let isLeft = side == .left
        let points = store.state.scoreDisplay(for: side)
        let games = isLeft ? store.state.leftGames : store.state.rightGames
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let mainSize = ScoreboardLayoutMetrics.editMainScoreFontSize(
            regularSize: ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: size.height)
                * tennisScoreMultiplier * 0.72
        )
        let secondarySize = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: size.height)
            * tennisSecondaryMultiplier * 0.72
        let nameSize = ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: size.height)
            * tennisNameMultiplier * 0.72

        return VStack(spacing: Theme.usesPadLayout ? 16 : 8) {
            tennisSinglesEditNameField(side: side, fontSize: nameSize)

            tennisEditAdjustRow(
                label: NSLocalizedString("tennis_point_score", value: "小分", comment: ""),
                value: points,
                fontSize: mainSize,
                canDecrement: (isLeft ? store.state.leftPoints : store.state.rightPoints) > 0,
                onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { dispatch(.adjustPoints(side: side, delta: 1)) }
            )

            if store.state.rules.setScoringMode != .tiebreakOnly {
                tennisEditAdjustRow(
                    label: NSLocalizedString("tennis_game_score", value: "局分", comment: ""),
                    value: "\(games)",
                    fontSize: secondarySize,
                    canDecrement: games > 0,
                    useSecondaryColor: true,
                    onDecrement: { dispatch(.adjustGames(side: side, delta: -1)) },
                    onIncrement: { dispatch(.adjustGames(side: side, delta: 1)) }
                )
                tennisEditAdjustRow(
                    label: NSLocalizedString("tennis_set_score", value: "盘分", comment: ""),
                    value: "\(sets)",
                    fontSize: secondarySize,
                    canDecrement: sets > 0,
                    useSecondaryColor: true,
                    onDecrement: { dispatch(.adjustSets(side: side, delta: -1)) },
                    onIncrement: { dispatch(.adjustSets(side: side, delta: 1)) }
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
        let nameFontSize = (Theme.usesPadLayout ? 28.0 : 22.0) * tennisNameMultiplier

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
                        screenSide: screenSide,
                        fontSize: nameFontSize,
                        height: rowHeight
                    )
                    tennisScoreRow(
                        screenSide: screenSide,
                        side: side,
                        height: rowHeight,
                        panelHeight: size.height
                    )
                    tennisDoublesNameRow(
                        name: names.indices.contains(slots.bottom) ? names[slots.bottom] : "",
                        isServer: serverSlot == slots.bottom,
                        isReceiver: receiverSlot == slots.bottom,
                        screenSide: screenSide,
                        fontSize: nameFontSize,
                        height: rowHeight
                    )
                }
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
        let mainSize = ScoreboardLayoutMetrics.compactEditMainScoreFontSize(
            regularSize: ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: size.height)
                * tennisScoreMultiplier,
            rowHeight: size.height / 3
        )
        let secondarySize = ScoreboardLayoutMetrics.compactEditSecondaryScoreFontSize(
            regularSize: ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: size.height)
                * tennisSecondaryMultiplier,
            rowHeight: size.height / 3
        )
        let nameSize = (Theme.usesPadLayout ? 28.0 : 22.0) * tennisNameMultiplier

        return VStack(spacing: Theme.usesPadLayout ? 16 : 8) {
            VStack(spacing: Theme.usesPadLayout ? 10 : 6) {
                tennisDoublesEditNameField(slot: slots.top, fontSize: nameSize)
                tennisDoublesEditNameField(slot: slots.bottom, fontSize: nameSize)
            }

            tennisEditAdjustRow(
                label: NSLocalizedString("tennis_point_score", value: "小分", comment: ""),
                value: points,
                fontSize: mainSize,
                canDecrement: (isLeft ? store.state.leftPoints : store.state.rightPoints) > 0,
                onDecrement: { dispatch(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { dispatch(.adjustPoints(side: side, delta: 1)) }
            )

            if store.state.rules.setScoringMode != .tiebreakOnly {
                tennisEditAdjustRow(
                    label: NSLocalizedString("tennis_game_score", value: "局分", comment: ""),
                    value: "\(games)",
                    fontSize: secondarySize,
                    canDecrement: games > 0,
                    useSecondaryColor: true,
                    onDecrement: { dispatch(.adjustGames(side: side, delta: -1)) },
                    onIncrement: { dispatch(.adjustGames(side: side, delta: 1)) }
                )
                tennisEditAdjustRow(
                    label: NSLocalizedString("tennis_set_score", value: "盘分", comment: ""),
                    value: "\(sets)",
                    fontSize: secondarySize,
                    canDecrement: sets > 0,
                    useSecondaryColor: true,
                    onDecrement: { dispatch(.adjustSets(side: side, delta: -1)) },
                    onIncrement: { dispatch(.adjustSets(side: side, delta: 1)) }
                )
            }
        }
        .padding(.horizontal, Theme.usesPadLayout ? 36 : 16)
        .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: size.height, isEditMode: true))
        .padding(.bottom, Theme.usesPadLayout ? 36 : 12)
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
        .font(.system(size: fontSize, weight: .bold))
        .multilineTextAlignment(.center)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, Theme.usesPadLayout ? 10 : 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
        .accessibilityIdentifier(side == .left
            ? "tennis_left_name_edit"
            : "tennis_right_name_edit")
    }

    private func tennisDoublesEditNameField(slot: Int, fontSize: CGFloat) -> some View {
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
        .font(.system(size: fontSize, weight: .bold))
        .multilineTextAlignment(.center)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, Theme.usesPadLayout ? 10 : 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
        .accessibilityIdentifier("tennis_doubles_player_\(slot)_edit")
    }

    private func tennisEditAdjustRow(
        label: String,
        value: String,
        fontSize: CGFloat,
        canDecrement: Bool,
        useSecondaryColor: Bool = false,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(appearance.theme.palette.secondary)
            HStack(spacing: Theme.usesPadLayout ? 20 : 10) {
                tennisEditControl(systemName: "minus", enabled: canDecrement, action: onDecrement)
                Text(value)
                    .font(appearance.font.swiftUIFont(size: fontSize, weight: .bold))
                    .foregroundStyle(useSecondaryColor
                        ? appearance.theme.palette.secondary
                        : appearance.theme.palette.foreground)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(minWidth: Theme.usesPadLayout ? 100 : 70)
                tennisEditControl(systemName: "plus", enabled: true, action: onIncrement)
            }
        }
    }

    private func tennisEditControl(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let controlSize: CGFloat = Theme.usesPadLayout ? 48 : 36
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
        panelHeight: CGFloat
    ) -> some View {
        let isLeft = side == .left
        let games = isLeft ? store.state.leftGames : store.state.rightGames
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let mainSize = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: panelHeight)
            * tennisScoreMultiplier * 0.85

        if store.state.rules.setScoringMode == .tiebreakOnly {
            tennisMainScore(side: side, fontSize: mainSize)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else {
            HStack(spacing: 0) {
                if screenSide == .left {
                    tennisMainScore(side: side, fontSize: mainSize)
                        .frame(maxWidth: .infinity)
                    tennisInnerScoreColumn(games: games, sets: sets, panelHeight: panelHeight)
                    Color.clear.frame(width: Theme.usesPadLayout ? 56 : 42)
                } else {
                    Color.clear.frame(width: Theme.usesPadLayout ? 56 : 42)
                    tennisInnerScoreColumn(games: games, sets: sets, panelHeight: panelHeight)
                    tennisMainScore(side: side, fontSize: mainSize)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
    }

    private func tennisMainScore(side: MatchSide, fontSize: CGFloat) -> some View {
        Text(store.state.scoreDisplay(for: side))
            .font(appearance.font.swiftUIFont(size: fontSize, weight: .bold))
            .foregroundStyle(appearance.theme.palette.foreground)
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private func tennisInnerScoreColumn(
        games: Int,
        sets: Int,
        panelHeight: CGFloat
    ) -> some View {
        let usesPadLayout = Theme.usesPadLayout
        let baseSize = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: panelHeight)
            * tennisSecondaryMultiplier
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
                .font(appearance.font.swiftUIFont(size: gameSize, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)

            if store.state.leftSets > 0 || store.state.rightSets > 0 {
                Text("\(sets)")
                    .font(appearance.font.swiftUIFont(size: setSize, weight: .bold))
                    .monospacedDigit()
                    .frame(width: setBoxSize, height: setBoxSize)
                    .background(Color.black.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: setBoxRadius, style: .continuous))
            }
        }
        .foregroundStyle(appearance.theme.palette.secondary)
        .frame(width: usesPadLayout ? 120 : 88)
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

    private func tennisDoublesNameRow(
        name: String,
        isServer: Bool,
        isReceiver: Bool,
        screenSide: MatchSide,
        fontSize: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack {
            Text(name)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(isReceiver
                    ? appearance.theme.palette.secondary
                    : appearance.theme.palette.foreground.opacity(isServer ? 1 : 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 36)
            if isServer {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Color(hex: "30D158"))
                    .rotationEffect(.degrees(screenSide == .left ? 0 : 180))
                    .frame(
                        maxWidth: .infinity,
                        alignment: screenSide == .left ? .trailing : .leading
                    )
                    .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var tennisScoreMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: .tennis)[ScoreboardFontMetric.score.rawValue] ?? 1)
    }

    private var tennisNameMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: .tennis)[ScoreboardFontMetric.name.rawValue] ?? 1)
    }

    private var tennisSecondaryMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: .tennis)[ScoreboardFontMetric.secondary.rawValue] ?? 1)
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

    private func dispatch(_ intent: TennisMatchIntent) {
        guard !scoringLocked else { return }
        store.send(intent) { events in
            handleSideChangeToasts(events)
        }
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
            fontID: appearance.font.rawValue,
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

    private func performUndo() {
        guard !isEditMode, !scoringLocked else { return }
        store.undo { success in
            toastMessage = success
                ? NSLocalizedString("undone", value: "已撤销", comment: "Undo done")
                : NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: "")
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
