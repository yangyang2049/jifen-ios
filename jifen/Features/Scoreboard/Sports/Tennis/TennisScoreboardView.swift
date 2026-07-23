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
        let left = (setup?.team1Name.isEmpty == false) ? setup!.team1Name : NSLocalizedString("red_team", comment: "")
        let right = (setup?.team2Name.isEmpty == false) ? setup!.team2Name : NSLocalizedString("blue_team", comment: "")
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
        watchSessionId != nil && watchLinkService.isFollower
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
                VStack {
                    HStack {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .padding(10)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                        }
                        .accessibilityIdentifier(ScoreboardConstants.backButtonAccessibilityID)
                        Spacer()
                        Button { showMenu = true } label: {
                            Image(systemName: "line.3.horizontal")
                                .padding(10)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                    if store.state.rules.setScoringMode != .tiebreakOnly {
                        Text("\(store.state.leftSets) - \(store.state.rightSets) · \(store.state.leftGames):\(store.state.rightGames)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(.bottom, 16)
                    }
                }
                if store.state.isTieBreak {
                    Text(store.state.rules.tieBreakPoints == 10
                        ? NSLocalizedString("tennis_tiebreak_option_10", value: "抢十", comment: "")
                        : NSLocalizedString("tennis_tiebreak_option_7", value: "抢七", comment: ""))
                        .font(.caption.bold())
                        .padding(6)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(.white)
                }
                if !store.state.finished {
                    ScoreboardKeyPointBadgeLayer(
                        status: KeyPointResolver.tennis(snapshot: tennisKeyPointSnapshot(store.state)),
                        gameType: store.gameType,
                        sidesSwapped: store.state.sidesSwapped,
                        doublesTopRow: store.gameType == .tennisDoubles ? false : nil
                    )
                }
                if showGameOverDialog {
                    GameFinishedOverlay(
                        winnerName: finishedWinnerName,
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
                        onNewGame: {
                            showGameOverDialog = false
                            dispatch(.reset)
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
                            goBack()
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
        .disabled(scoringLocked)
        .onAppear {
            appearance = .current()
            onSetupConsumed?()
            if let id = initialRecordId, let uuid = UUID(uuidString: id),
               let restored = TennisSessionStore(restoring: uuid) {
                store = restored
            }
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
                watchLinkService.syncWatch(sessionId: watchSessionId, gameType: store.gameType, state: state)
            }
            if state.finished {
                showGameOverDialog = true
                if let watchSessionId, watchLinkService.isController {
                    let winner = winnerSide(for: state)
                    watchLinkService.notifyMatchFinished(
                        sessionId: watchSessionId,
                        snapshot: .tennis(state),
                        recordId: store.sessionId.uuidString,
                        winnerSide: winner,
                        manualEnd: false
                    )
                }
            }
        }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId,
                  let update,
                  update.sessionId == watchSessionId,
                  let tennis = update.snapshot.tennisState else { return }
            store.replaceDisplayedState(tennis)
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            gameType: GameType(scoreCoreGameType: store.gameType) ?? .tennis
        )
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
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            store.persistSnapshot()
            if let watchSessionId {
                watchLinkService.endWatchSession(watchSessionId)
            }
        }
    }

    private func half(_ screenSide: MatchSide, size: CGSize) -> some View {
        let side = store.state.sidesSwapped ? screenSide.opposite : screenSide
        let isLeft = side == .left
        return ZStack {
            (isLeft ? appearance.theme.palette.left : appearance.theme.palette.right)
            VStack(spacing: 8) {
                Text(isLeft ? store.state.doublesTeamDisplayName(for: .left) : store.state.doublesTeamDisplayName(for: .right))
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(store.state.scoreDisplay(for: side))
                    .font(appearance.font.swiftUIFont(size: min(size.height * 0.35, 120), weight: .bold))
                    .monospacedDigit()
                if store.state.servingSide == side {
                    Image(systemName: "circle.fill")
                        .font(.caption)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !scoringLocked else { return }
            dispatch(.pointWon(side))
        }
        .onTapGesture(count: 2) {
            guard appearance.doubleTapSubtract, !scoringLocked else { return }
            dispatch(.adjustPoints(side: side, delta: -1))
        }
    }

    private func dispatch(_ intent: TennisMatchIntent) {
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
                switch intent {
                case .addLeft: dispatch(.pointWon(logicalSide(forScreen: .left)))
                case .addRight: dispatch(.pointWon(logicalSide(forScreen: .right)))
                case .subtractLeft:
                    dispatch(.adjustPoints(side: logicalSide(forScreen: .left), delta: -1))
                case .subtractRight:
                    dispatch(.adjustPoints(side: logicalSide(forScreen: .right), delta: -1))
                case .undo: store.undo()
                case .exchangeSides: dispatch(.exchangeSides)
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
                isEditing: false
            ),
            revision: 0
        )
    }

    private func logicalSide(forScreen side: MatchSide) -> MatchSide {
        store.state.sidesSwapped ? side.opposite : side
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
        if AppFeatureFlags.watchLinkEntryEnabled, watchSessionId != nil {
            if watchLinkService.isFollower {
                extras.insert(
                    ScoreboardMenuItem(
                        title: NSLocalizedString("linked_score_takeover", value: "接管计分", comment: ""),
                        action: "takeover",
                        group: .sync,
                        icon: "applewatch"
                    ),
                    at: 0
                )
            }
            extras.insert(
                ScoreboardMenuItem(
                    title: NSLocalizedString("linked_score_end", value: "结束联动", comment: ""),
                    action: "endLink",
                    group: .sync,
                    icon: "xmark.circle"
                ),
                at: 0
            )
        }
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            resetConfirming: menuConfirm.resetConfirming,
            exchangeConfirming: menuConfirm.exchangeConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            extraItems: extras
        )
    }

    private func handleMenu(_ action: String) {
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            store.undo()
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
                dispatch(.reset)
                showMenu = false
            } else {
                toastMessage = ScoreboardMenuConfirmAction.reset.localizedToast
            }
        case "endGame":
            if menuConfirm.armOrConfirm(.finish) {
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
        case "takeover":
            Task {
                if let id = watchSessionId {
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
        if let onNavigationBack {
            onNavigationBack()
        } else {
            dismiss()
        }
    }

    private func shareFinishedMatch() {
        let left = store.state.rules.setScoringMode == .tiebreakOnly ? store.state.leftPoints : store.state.leftSets
        let right = store.state.rules.setScoringMode == .tiebreakOnly ? store.state.rightPoints : store.state.rightSets
        let text = "\(store.state.leftName) \(left) - \(right) \(store.state.rightName)"
        ScoreboardShareSupport.present(text: text)
    }
}

func tennisLocalSyncDetail(state: TennisMatchState, side: MatchSide) -> String? {
    guard state.rules.setScoringMode != .tiebreakOnly else { return nil }
    let sets = side == .left ? state.leftSets : state.rightSets
    let games = side == .left ? state.leftGames : state.rightGames
    return [
        String(format: NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), sets),
        String(format: NSLocalizedString("sync_games_format", value: "%d 盘", comment: ""), games)
    ].joined(separator: " · ")
}
