import ScoreCore
import SwiftUI
import UIKit

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
    let onUndo: () -> Void
    let onReset: () -> Void
    let onExchange: (() -> Void)?
    let onBack: () -> Void
    var showEndGame: Bool = false
    var onEndGame: (() -> Void)? = nil
    var onEditCommit: ((String, String, String, String) -> Void)? = nil
    var extraMenuItems: [ScoreboardMenuItem] = []
    var onMenuAction: ((String) -> Void)? = nil
    /// Optional overlay between the halves (e.g. serve triangle). Drawn above panels.
    var seamOverlay: (() -> AnyView)? = nil
    /// Optional bottom bar (e.g. snooker balls).
    var bottomBar: (() -> AnyView)? = nil
    /// Optional top-center pill.
    var topCenter: (() -> AnyView)? = nil
    let center: () -> Center

    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var preferences = PreferencesManager.shared
    @State private var showDisplaySettings = false
    @State private var showLocalSync = false
    @State private var showMenu = false
    @State private var resetConfirming = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var isEditMode = false
    @State private var editLeftName = ""
    @State private var editRightName = ""
    @State private var editLeftScore = ""
    @State private var editRightScore = ""

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || showDisplaySettings || showLocalSync || showMenu
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
                        halfHeight: halfH,
                        action: onLeftTap
                    )
                    .frame(width: proxy.size.width / 2, height: halfH)

                    scorePanel(
                        isLeft: false,
                        name: rightName,
                        score: rightScore,
                        detail: rightDetail,
                        color: appearance.theme.palette.right,
                        halfHeight: halfH,
                        action: onRightTap
                    )
                    .frame(width: proxy.size.width / 2, height: halfH)
                }

                if let seamOverlay {
                    seamOverlay()
                }

                if let topCenter {
                    VStack {
                        topCenter()
                            .padding(.top, ScoreboardConstants.buttonPadding)
                        Spacer()
                    }
                }

                // Compact center hints (target text etc.) sit mid-bottom above optional bottom bar.
                VStack {
                    Spacer()
                    center()
                        .padding(.bottom, bottomBar == nil ? 72 : 90)
                }
                .allowsHitTesting(false)

                if let bottomBar {
                    VStack {
                        Spacer()
                        bottomBar()
                    }
                }

                if shouldShowChrome {
                    chromeOverlay
                }

                if appearance.immersiveMode && !chromeVisible {
                    ImmersiveCornerRevealZones(onReveal: revealImmersiveChrome)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
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
        .onChange(of: showMenu) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showLocalSync) { _, _ in updateImmersiveForBlocking() }
        .onDisappear {
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
        }
        .sheet(isPresented: $showDisplaySettings) { ScoreboardDisplaySettingsView(gameType: gameType) }
        .sheet(isPresented: $showLocalSync) { LocalSyncView() }
        .overlay {
            MenuDialog(
                isVisible: showMenu,
                onClose: { showMenu = false },
                onMenuItemClick: { action in
                    switch action {
                    case "undo": onUndo()
                    case "reset": handleReset()
                    case "exchangeSide": onExchange?()
                    case "endGame": onEndGame?()
                    case "displaySettings": showDisplaySettings = true
                    case "localSync": showLocalSync = true
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
                    resetConfirming: resetConfirming,
                    extraItems: extraMenuItems
                )
            )
        }
    }

    private func handleReset() {
        if resetConfirming {
            resetConfirming = false
            onReset()
            return
        }
        resetConfirming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            resetConfirming = false
        }
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !showDisplaySettings, !showLocalSync, !showMenu else { return }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !showDisplaySettings,
                  !showLocalSync,
                  !showMenu else { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || showLocalSync || !appearance.immersiveMode {
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
                    if onEditCommit != nil {
                        chromeButton(isEditMode ? "checkmark" : "pencil") { toggleEditMode() }
                    }
                }
                Spacer()
            }
            .padding(ScoreboardConstants.buttonPadding)

            VStack {
                Spacer()
                HStack {
                    chromeButton("chevron.left", action: onBack)
                    Spacer()
                    chromeButton("line.3.horizontal") { showMenu = true }
                }
            }
            .padding(ScoreboardConstants.buttonPadding)
        }
    }

    private func chromeButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: ScoreboardConstants.buttonIconSize))
                .foregroundColor(.white)
                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                .background(Circle().fill(Color.black.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    private func scorePanel(
        isLeft: Bool,
        name: String,
        score: String,
        detail: String?,
        color: Color,
        halfHeight: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        let mainSize = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: halfHeight)
            * (score.count >= 3 ? 0.72 : 1)
        let nameSize = ScoreboardLayoutMetrics.defaultTeamNameFontSize
        let topPad = ScoreboardLayoutMetrics.nameTopPadding(panelHeight: halfHeight)
        let setSize = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: halfHeight)

        return ZStack {
            color
            VStack(spacing: ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: halfHeight)) {
                if isEditMode {
                    TextField(
                        "0",
                        text: isLeft ? $editLeftScore : $editRightScore
                    )
                    .keyboardType(.numbersAndPunctuation)
                    .font(appearance.font.swiftUIFont(size: mainSize * 0.7))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                } else {
                    Text(score)
                        .font(appearance.font.swiftUIFont(size: mainSize))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(appearance.font.swiftUIFont(size: min(setSize, 36)))
                        .foregroundStyle(appearance.theme.palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                if isEditMode {
                    TextField(
                        NSLocalizedString("setup_team_name", value: "队伍名称", comment: ""),
                        text: isLeft ? $editLeftName : $editRightName
                    )
                    .font(.system(size: nameSize, weight: .bold))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .padding(.top, topPad)
                    .padding(.horizontal, 8)
                } else {
                    Text(name)
                        .font(.system(size: nameSize, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, topPad)
                        .padding(.horizontal, 8)
                }
                Spacer()
            }
        }
        .foregroundStyle(appearance.theme.palette.foreground)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !finished else { return }
            action()
        }
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
        } else {
            editLeftName = leftName
            editRightName = rightName
            editLeftScore = leftScore
            editRightScore = rightScore
            isEditMode = true
        }
    }
}


struct EightBallScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?

    @State private var state: EightBallState
    @State private var history: [EightBallState] = []
    @State private var actionLog: [String] = []
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var leftName: String
    @State private var rightName: String
    @State private var showGameFinishedOverlay = false
    private let reducer = EightBallReducer()

    init(
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let red = localizedSideRedName()
        let blue = localizedSideBlueName()
        var left = initialSetup?.team1Name.nonEmpty ?? red
        var right = initialSetup?.team2Name.nonEmpty ?? blue
        let beneficiary: MatchSide? = initialSetup?.eightBallHandicapBeneficiary == "team1" ? .left :
            (initialSetup?.eightBallHandicapBeneficiary == "team2" ? .right : nil)
        var initial = EightBallState.initial(
            targetPoints: initialSetup?.maxSets ?? 9,
            handicapRacks: initialSetup?.eightBallHandicapRacks ?? 0,
            handicapBeneficiary: beneficiary
        )
        var start = Date()
        var id = "eight_ball_\(Int(start.timeIntervalSince1970))"
        var actions = 0
        var showFinished = false

        if let initialRecordId,
           let draft = loadSpecializedDraft(recordId: initialRecordId, as: EightBallState.self) {
            initial = draft.state
            start = draft.record.startTime
            id = draft.record.id
            actions = max(draft.record.totalScoreChanges, 1)
            left = draft.record.team1Name
            right = draft.record.team2Name
            showFinished = draft.state.finished
        }

        _state = State(initialValue: initial)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _leftName = State(initialValue: left)
        _rightName = State(initialValue: right)
        _showGameFinishedOverlay = State(initialValue: showFinished)
    }

    var body: some View {
        ZStack {
            SpecializedScoreboardScaffold(
                gameType: .eightBall,
                leftName: leftName,
                rightName: rightName,
                leftScore: "\(logical(.left))",
                rightScore: "\(logical(.right))",
                leftDetail: String(format: NSLocalizedString("eight_ball_target_format", value: "抢 %d", comment: ""), state.targetPoints),
                rightDetail: String(format: NSLocalizedString("eight_ball_target_format", value: "抢 %d", comment: ""), state.targetPoints),
                finished: state.finished,
                onLeftTap: { send(.addRack(screenSide(.left))) },
                onRightTap: { send(.addRack(screenSide(.right))) },
                onUndo: undo,
                onReset: { send(.reset) },
                onExchange: { send(.exchangeSides) },
                onBack: exit,
                showEndGame: true,
                onEndGame: markFinished,
                onEditCommit: applyEdit
            ) {
                VStack(spacing: 6) {
                    Text(NSLocalizedString("eight_ball_tap_rack", value: "点击比分区记一局", comment: ""))
                    if state.handicapRacks > 0 {
                        Text(String(format: NSLocalizedString("eight_ball_handicap_summary", value: "让局 %d", comment: ""), state.handicapRacks))
                    }
                }
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
            }

            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: finishedWinnerName)
            }
        }
        .onAppear { onSetupConsumed?(); registerSync() }
        .onChange(of: state.finished) { _, finished in
            if finished { showGameFinishedOverlay = true }
        }
        .onChange(of: state) { _, _ in LocalScoreboardSyncCoordinator.shared.publishSnapshot() }
        .onDisappear { LocalScoreboardSyncCoordinator.shared.unregisterHost(); saveRecord() }
    }

    private var finishedWinnerName: String {
        if state.leftPoints > state.rightPoints { return leftName }
        if state.rightPoints > state.leftPoints { return rightName }
        return ""
    }

    private func logical(_ screen: MatchSide) -> Int {
        let side = screenSide(screen)
        return side == .left ? state.leftPoints : state.rightPoints
    }
    private func screenSide(_ screen: MatchSide) -> MatchSide { state.sidesSwapped ? screen.opposite : screen }
    private func send(_ intent: EightBallIntent) {
        let result = reducer.reduce(state: state, intent: intent, at: nowMilliseconds())
        guard result.accepted else { return }
        history.append(state); state = result.state; actionCount += 1
        actionLog.append(recordSnapshot(code: String(describing: intent), scores: [state.leftPoints, state.rightPoints]))
    }
    private func markFinished() {
        guard !state.finished else { return }
        history.append(state)
        var next = state
        next.finished = true
        state = next
        actionCount += 1
        actionLog.append(recordSnapshot(code: "finish", scores: [state.leftPoints, state.rightPoints]))
        showGameFinishedOverlay = true
    }
    private func applyEdit(left: String, right: String, leftScore: String, rightScore: String) {
        if !left.isEmpty { leftName = left }
        if !right.isEmpty { rightName = right }
        if let leftValue = Int(leftScore), let rightValue = Int(rightScore) {
            send(.adminAdjust(left: leftValue, right: rightValue))
            showGameFinishedOverlay = false
        }
    }
    private func undo() { guard let previous = history.popLast() else { return }; state = previous; actionCount = max(0, actionCount - 1); actionLog.append(recordSnapshot(code: "undo", scores: [state.leftPoints, state.rightPoints])); showGameFinishedOverlay = state.finished }
    private func exit() { saveRecord(); onNavigationBack?(); dismiss() }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            switch intent {
            case .addLeft: send(.addRack(screenSide(.left)))
            case .addRight: send(.addRack(screenSide(.right)))
            case .subtractLeft, .subtractRight, .undo: undo()
            case .exchangeSides: send(.exchangeSides)
            case .requestSnapshot: break
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        .init(gameID: GameType.eightBall.canonicalScoreboardIdentifier, title: GameType.eightBall.displayName,
              leftName: leftName, rightName: rightName,
              leftScore: "\(logical(.left))", rightScore: "\(logical(.right))",
              leftDetail: String.localizedStringWithFormat(NSLocalizedString("eight_ball_target_format", value: "抢 %d", comment: ""), state.targetPoints),
              rightDetail: String.localizedStringWithFormat(NSLocalizedString("eight_ball_target_format", value: "抢 %d", comment: ""), state.targetPoints),
              themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue, fontID: ScoreboardAppearanceSnapshot.current().font.rawValue, finished: state.finished, revision: 0)
    }
    private func saveRecord() {
        saveSpecializedRecord(
            id: recordID, gameType: .eightBall, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftPoints, right: state.rightPoints,
            actionCount: actionCount, actions: actionLog, finished: state.finished, snapshot: state
        )
    }
}

struct NineBallChaseScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?
    @State private var state: NineBallChaseState
    @State private var history: [NineBallChaseState] = []
    @State private var actionLog: [String] = []
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var preferences = PreferencesManager.shared
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var playerNames: [String]
    @State private var showMenu = false
    @State private var showDisplaySettings = false
    @State private var showLocalSync = false
    @State private var showGameFinishedOverlay = false
    @State private var resetConfirming = false
    @State private var settleConfirming = false
    @State private var showEditPanel = false
    @State private var editPlayerNames: [String] = []
    @State private var editPlayerScores: [String] = []
    private let reducer = NineBallChaseReducer()

    init(
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let config = NineBallChaseConfig(
            bigGold: initialSetup?.nineBallBigGold ?? 10, smallGold: initialSetup?.nineBallSmallGold ?? 7,
            goldenNine: initialSetup?.nineBallGoldenNine ?? 8, normalWin: initialSetup?.nineBallNormalWin ?? 4,
            ballInHand: initialSetup?.nineBallBallInHand ?? 1, foul: initialSetup?.nineBallFoul ?? 1
        )
        var initial = NineBallChaseState.initial(config: config, playerCount: initialSetup?.playerCount ?? 2)
        var start = Date()
        var id = "nine_ball_\(Int(start.timeIntervalSince1970))"
        var actions = 0
        var names = (0..<4).map { index in
            initialSetup?.playerNames?[safe: index]?.nonEmpty
                ?? String.localizedStringWithFormat(
                    NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: ""),
                    index + 1
                )
        }
        var showFinished = false

        if let initialRecordId,
           let draft = loadSpecializedDraft(recordId: initialRecordId, as: NineBallChaseState.self) {
            initial = draft.state
            start = draft.record.startTime
            id = draft.record.id
            actions = max(draft.record.totalScoreChanges, 1)
            showFinished = draft.state.finished
            if let stored = draft.record.extraData?["playerNames"]?.value as? [String], !stored.isEmpty {
                names = Array((stored + names).prefix(4))
            } else {
                names[0] = draft.record.team1Name
                names[1] = draft.record.team2Name
            }
        }

        _state = State(initialValue: initial)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _playerNames = State(initialValue: names)
        _showGameFinishedOverlay = State(initialValue: showFinished)
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                HStack(spacing: 8) {
                    ForEach(0..<state.playerCount, id: \.self) { player in
                        VStack(spacing: 10) {
                            Text(playerName(player)).font(.headline).lineLimit(1)
                            Text("\(state.playerPoints[player])")
                                .font(appearance.font.swiftUIFont(size: state.playerPoints[player].magnitude >= 100 ? 64 : 82))
                                .minimumScaleFactor(0.5)
                            ScrollView {
                                VStack(spacing: 6) {
                                    chaseButton(.bigGold, player: player)
                                    chaseButton(.smallGold, player: player)
                                    chaseButton(.goldenNine, player: player)
                                    chaseButton(.normalWin, player: player)
                                    chaseButton(.ballInHand, player: player)
                                    chaseButton(.foul, player: player)
                                }
                            }
                        }
                        .foregroundStyle(appearance.theme.palette.foreground)
                        .padding(10)
                        .frame(width: (proxy.size.width - CGFloat(state.playerCount - 1) * 8) / CGFloat(state.playerCount))
                        .frame(maxHeight: .infinity)
                        .background(player.isMultiple(of: 2) ? appearance.theme.palette.left : appearance.theme.palette.right)
                        .disabled(state.finished)
                    }
                }
                .overlay(alignment: .top) {
                    HStack {
                        Button(action: exit) { Image(systemName: "chevron.left") }
                        Button(action: undo) { Image(systemName: "arrow.uturn.backward") }
                        Spacer()
                        Button(action: openEditPanel) { Image(systemName: "pencil") }
                        Button { showMenu = true } label: { Image(systemName: "line.3.horizontal") }
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                }
            }
            .background(appearance.theme.palette.background).ignoresSafeArea()

            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: finishedWinnerName)
            }

            MenuDialog(
                isVisible: showMenu,
                onClose: { showMenu = false },
                onMenuItemClick: { action in
                    switch action {
                    case "undo": undo()
                    case "reset": confirmReset()
                    case "endGame": markFinished()
                    case "settleMatch": confirmSettle()
                    case "displaySettings": showDisplaySettings = true
                    case "localSync": showLocalSync = true
                    default: break
                    }
                },
                showEndGame: true,
                showExchangeSide: false,
                items: ScoreboardMenuItemBuilder.defaultItems(
                    showEndGame: true,
                    showExchangeSide: false,
                    showWhistle: true,
                    showScreenshot: true,
                    showSettleMatch: true,
                    resetConfirming: resetConfirming,
                    settleConfirming: settleConfirming
                )
            )
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar).lockOrientation(.landscape)
        .onAppear { onSetupConsumed?(); registerSync() }
        .onChange(of: preferences.scoreboardRevision) { _, _ in appearance = .current() }
        .onChange(of: state.finished) { _, finished in if finished { showGameFinishedOverlay = true } }
        .onChange(of: state) { _, _ in LocalScoreboardSyncCoordinator.shared.publishSnapshot() }
        .onDisappear { LocalScoreboardSyncCoordinator.shared.unregisterHost(); saveRecord() }
        .sheet(isPresented: $showDisplaySettings) { ScoreboardDisplaySettingsView(gameType: .nineBall) }
        .sheet(isPresented: $showLocalSync) { LocalSyncView() }
        .sheet(isPresented: $showEditPanel) { nineBallEditSheet }
    }

    private var finishedWinnerName: String {
        let active = Array(state.playerPoints.prefix(state.playerCount))
        guard let best = active.max(), active.filter({ $0 == best }).count == 1,
              let index = active.firstIndex(of: best) else { return "" }
        return playerName(index)
    }

    private func chaseButton(_ kind: NineBallChaseKind, player: Int) -> some View {
        Button { send(.chaseEvent(player: player, kind: kind)) } label: {
            Text(chaseTitle(kind)).font(.caption.weight(.medium)).frame(maxWidth: .infinity, minHeight: 30).background(.black.opacity(0.2)).clipShape(Capsule())
        }.buttonStyle(.plain)
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
        editPlayerNames = (0..<state.playerCount).map(playerName)
        editPlayerScores = state.playerPoints.prefix(state.playerCount).map { String($0) }
        showEditPanel = true
    }
    private var nineBallEditSheet: some View {
        NavigationStack {
            List {
                ForEach(0..<state.playerCount, id: \.self) { index in
                    HStack {
                        TextField(
                            NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""),
                            text: Binding(
                                get: { editPlayerNames[safe: index] ?? "" },
                                set: { if editPlayerNames.indices.contains(index) { editPlayerNames[index] = $0 } }
                            )
                        )
                        TextField(
                            "0",
                            text: Binding(
                                get: { editPlayerScores[safe: index] ?? "0" },
                                set: { if editPlayerScores.indices.contains(index) { editPlayerScores[index] = $0 } }
                            )
                        )
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("edit", value: "编辑", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", value: "取消", comment: "")) { showEditPanel = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", value: "完成", comment: "")) { applyPlayerEdits() }
                }
            }
        }
    }
    private func applyPlayerEdits() {
        history.append(state)
        for index in 0..<state.playerCount {
            if editPlayerNames.indices.contains(index) {
                let name = editPlayerNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { playerNames[index] = name }
            }
            if editPlayerScores.indices.contains(index), let score = Int(editPlayerScores[index]) {
                state.playerPoints[index] = min(9999, max(-9999, score))
            }
        }
        state.finished = false
        actionCount += 1
        showGameFinishedOverlay = false
        showEditPanel = false
    }
    private func send(_ intent: NineBallChaseIntent) {
        let result = reducer.reduce(state: state, intent: intent, at: nowMilliseconds())
        guard result.accepted else { return }
        history.append(state); state = result.state; actionCount += 1
        actionLog.append(recordSnapshot(code: String(describing: intent), scores: state.playerPoints))
    }
    private func markFinished() {
        guard !state.finished else { return }
        history.append(state)
        var next = state
        next.finished = true
        state = next
        actionCount += 1
        actionLog.append(recordSnapshot(code: "finish", scores: state.playerPoints))
        showGameFinishedOverlay = true
    }
    private func confirmReset() {
        if resetConfirming {
            resetConfirming = false
            send(.resetScores)
            showGameFinishedOverlay = false
            return
        }
        resetConfirming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            resetConfirming = false
        }
    }
    private func confirmSettle() {
        if settleConfirming {
            settleConfirming = false
            markFinished()
            showMenu = false
            return
        }
        settleConfirming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            settleConfirming = false
        }
    }
    private func undo() {
        guard let previous = history.popLast() else { return }
        state = previous
        actionCount = max(0, actionCount - 1)
        actionLog.append(recordSnapshot(code: "undo", scores: state.playerPoints))
        showGameFinishedOverlay = state.finished
    }
    private func exit() { saveRecord(); onNavigationBack?(); dismiss() }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            switch intent {
            case .addLeft: send(.chaseEvent(player: 0, kind: .normalWin))
            case .addRight: send(.chaseEvent(player: 1, kind: .normalWin))
            case .subtractLeft, .subtractRight, .undo: undo()
            default: break
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
            fontID: appearance.font.rawValue,
            finished: state.finished,
            revision: 0
        )
    }
    private func saveRecord() {
        saveSpecializedRecord(
            id: recordID, gameType: .nineBall, startedAt: startedAt,
            leftName: playerName(0), rightName: playerName(1),
            left: state.playerPoints[0], right: state.playerPoints[1],
            actionCount: actionCount, actions: actionLog, finished: state.finished, snapshot: state,
            extra: ["playerNames": Array(playerNames.prefix(state.playerCount))]
        )
    }
}

struct SnookerReducerScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?
    @State private var state: SnookerState
    @State private var history: [SnookerState] = []
    @State private var actionLog: [String] = []
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var leftName: String
    @State private var rightName: String
    @State private var showFoulPanel = false
    @State private var showSettlePanel = false
    @State private var foulSwitchTurn = true
    @State private var settleWinner: MatchSide = .left
    @State private var showGameFinishedOverlay = false
    private let reducer = SnookerReducer()

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
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let red = localizedSideRedName()
        let blue = localizedSideBlueName()
        var left = initialSetup?.team1Name.nonEmpty ?? red
        var right = initialSetup?.team2Name.nonEmpty ?? blue
        var initial = SnookerState.initial(
            striker: initialSetup?.servingSide == MatchSide.right.rawValue ? .right : .left,
            maxFrames: initialSetup?.maxSets ?? 1
        )
        var start = Date()
        var id = "snooker_\(Int(start.timeIntervalSince1970))"
        var actions = 0
        var showFinished = false

        if let initialRecordId,
           let draft = loadSpecializedDraft(recordId: initialRecordId, as: SnookerState.self) {
            initial = draft.state
            start = draft.record.startTime
            id = draft.record.id
            actions = max(draft.record.totalScoreChanges, 1)
            left = draft.record.team1Name
            right = draft.record.team2Name
            showFinished = draft.state.finished
        }

        _state = State(initialValue: initial)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _leftName = State(initialValue: left)
        _rightName = State(initialValue: right)
        _showGameFinishedOverlay = State(initialValue: showFinished)
    }

    var body: some View {
        ZStack {
            SpecializedScoreboardScaffold(
                gameType: .snooker,
                leftName: leftName,
                rightName: rightName,
                leftScore: "\(state.leftScore)",
                rightScore: "\(state.rightScore)",
                leftDetail: String(format: NSLocalizedString("snooker_break_format", value: "单杆 %d", comment: ""), state.leftBreak),
                rightDetail: String(format: NSLocalizedString("snooker_break_format", value: "单杆 %d", comment: ""), state.rightBreak),
                finished: state.finished,
                onLeftTap: {},
                onRightTap: {},
                onUndo: undo,
                onReset: resetMatch,
                onExchange: nil,
                onBack: exit,
                showEndGame: true,
                onEndGame: { send(.finishMatch) },
                onEditCommit: applyEdit,
                extraMenuItems: [
                    ScoreboardMenuItem(
                        title: NSLocalizedString("snooker_settle_frame", value: "结算本局", comment: ""),
                        action: "settleFrame",
                        group: .match,
                        icon: "flag"
                    )
                ],
                onMenuAction: { action in
                    if action == "settleFrame" {
                        settleWinner = state.leftScore >= state.rightScore ? .left : .right
                        showSettlePanel = true
                    }
                },
                seamOverlay: {
                    AnyView(
                        GeometryReader { geo in
                            CenterLineServeIndicator(
                                isLeftServing: state.striker == .left,
                                triangleSize: ScoreboardLayoutMetrics.isPad ? 42 : 36
                            )
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                        .allowsHitTesting(false)
                    )
                },
                bottomBar: { AnyView(snookerBottomBar) },
                topCenter: { AnyView(framePill) }
            ) {
                Group {
                    if state.frameCompletePending {
                        Button(NSLocalizedString("snooker_next_frame", value: "下一局", comment: "")) {
                            send(.confirmNextFrame)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "30D158"))
                    }
                }
            }

            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: finishedWinnerName)
            }
        }
        .onAppear { onSetupConsumed?(); registerSync() }
        .onChange(of: state.finished) { _, finished in if finished { showGameFinishedOverlay = true } }
        .onChange(of: state) { _, _ in LocalScoreboardSyncCoordinator.shared.publishSnapshot() }
        .onDisappear { LocalScoreboardSyncCoordinator.shared.unregisterHost(); saveRecord() }
        .sheet(isPresented: $showFoulPanel) { foulSheet }
        .sheet(isPresented: $showSettlePanel) { settleSheet }
    }

    private var finishedWinnerName: String {
        if state.leftFrames > state.rightFrames { return leftName }
        if state.rightFrames > state.leftFrames { return rightName }
        if state.leftScore > state.rightScore { return leftName }
        if state.rightScore > state.leftScore { return rightName }
        return ""
    }

    private var framePill: some View {
        Group {
            if state.maxFrames > 1 {
                HStack(spacing: 0) {
                    Text("\(state.leftFrames)").frame(width: 42)
                    Text(String(format: NSLocalizedString("snooker_current_frame_short", value: "第 %d/%d 局", comment: ""), state.currentFrame, state.maxFrames))
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(state.rightFrames)").frame(width: 42)
                }
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Capsule().fill(Color.black.opacity(0.35)))
            }
        }
    }

    private var snookerBottomBar: some View {
        HStack(spacing: 8) {
            ForEach(balls, id: \.points) { ball in
                let legal = isLegalSnookerBall(ball.points)
                Button {
                    guard legal else { return }
                    send(.potBall(points: ball.points))
                } label: {
                    Group {
                        if ball.points == 1 {
                            HStack(spacing: 0) {
                                Text("x")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(state.redBallsRemaining)")
                                    .font(.system(size: 18, weight: .bold))
                            }
                        } else {
                            Text(ball.label)
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(ball.color))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .opacity(legal ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(state.finished || !legal)
            }
            Button {
                foulSwitchTurn = true
                showFoulPanel = true
            } label: {
                Text(NSLocalizedString("snooker_foul_button", value: "犯规", comment: ""))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "FF453A"))
                    .frame(minWidth: 48, minHeight: 50)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .disabled(state.finished)
            Button { send(.handover) } label: {
                Text(NSLocalizedString("snooker_handover", value: "交杆", comment: ""))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 48, minHeight: 50)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .disabled(state.finished)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.2))
    }

    /// HOS legal-ball highlighting: red stage → red; color stage → any colour; clearance → expected colour only.
    private func isLegalSnookerBall(_ points: Int) -> Bool {
        switch state.nextBallStage {
        case .red:
            return points == 1 && state.redBallsRemaining > 0
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

    private var foulSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(NSLocalizedString("snooker_foul_row_title", value: "犯规罚分", comment: "")).font(.headline)
                HStack(spacing: 12) {
                    ForEach([4, 5, 6, 7], id: \.self) { pts in
                        Button("\(pts)") {
                            send(.foul(pointsToOpponent: pts, switchTurn: foulSwitchTurn))
                            showFoulPanel = false
                        }
                        .font(.title2.bold())
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color(hex: "FF3B30").opacity(0.85)))
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                    }
                }
                Picker("", selection: $foulSwitchTurn) {
                    Text(NSLocalizedString("snooker_foul_switch_turn", value: "换杆", comment: "")).tag(true)
                    Text(NSLocalizedString("snooker_foul_continue", value: "继续击球", comment: "")).tag(false)
                }
                .pickerStyle(.segmented)
                Spacer()
            }
            .padding(24)
            .navigationTitle(NSLocalizedString("snooker_foul_button", value: "犯规", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", value: "取消", comment: "")) { showFoulPanel = false }
                }
            }
        }
        .presentationDetents([.medium])
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
                    send(.settleFrame(winner: settleWinner))
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
                }
            }
        }
        .presentationDetents([.height(260)])
    }

    private func send(_ intent: SnookerIntent) {
        let result = reducer.reduce(state: state, intent: intent, at: nowMilliseconds())
        guard result.accepted else { return }
        history.append(state)
        state = result.state
        actionCount += 1
        actionLog.append(recordSnapshot(code: String(describing: intent), scores: [state.leftScore, state.rightScore], setScores: [state.leftFrames, state.rightFrames]))
        if state.finished { showGameFinishedOverlay = true }
    }
    private func undo() {
        guard let previous = history.popLast() else { return }
        state = previous
        actionCount = max(0, actionCount - 1)
        actionLog.append(recordSnapshot(code: "undo", scores: [state.leftScore, state.rightScore], setScores: [state.leftFrames, state.rightFrames]))
        showGameFinishedOverlay = state.finished
    }
    private func exit() { saveRecord(); onNavigationBack?(); dismiss() }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            switch intent {
            case .addLeft: send(.potBallAsSide(side: .left, points: 1))
            case .addRight: send(.potBallAsSide(side: .right, points: 1))
            case .subtractLeft, .subtractRight, .undo: undo()
            default: break
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        .init(
            gameID: GameType.snooker.canonicalScoreboardIdentifier,
            title: GameType.snooker.displayName,
            leftName: leftName,
            rightName: rightName,
            leftScore: "\(state.leftScore)",
            rightScore: "\(state.rightScore)",
            leftDetail: String.localizedStringWithFormat(NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), state.leftFrames),
            rightDetail: String.localizedStringWithFormat(NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), state.rightFrames),
            themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue,
            fontID: ScoreboardAppearanceSnapshot.current().font.rawValue,
            finished: state.finished,
            revision: 0
        )
    }
    private func resetMatch() {
        history.append(state)
        state = .initial(striker: state.firstBreaker, maxFrames: state.maxFrames)
        actionCount += 1
        actionLog.append(recordSnapshot(code: "reset", scores: [state.leftScore, state.rightScore], setScores: [state.leftFrames, state.rightFrames]))
        foulSwitchTurn = true
        showSettlePanel = false
        showFoulPanel = false
        showGameFinishedOverlay = false
    }
    private func applyEdit(left: String, right: String, leftScore: String, rightScore: String) {
        if !left.isEmpty { leftName = left }
        if !right.isEmpty { rightName = right }
        if let leftValue = Int(leftScore), let rightValue = Int(rightScore) {
            send(.adminCorrect(left: max(0, leftValue), right: max(0, rightValue), striker: state.striker))
            showGameFinishedOverlay = false
        }
    }
    private func saveRecord() {
        saveSpecializedRecord(
            id: recordID, gameType: .snooker, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftScore, right: state.rightScore,
            leftSets: state.leftFrames, rightSets: state.rightFrames,
            actionCount: actionCount, actions: actionLog, finished: state.finished, snapshot: state
        )
    }
}

struct ShengjiReducerScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialRecordId: String? = nil
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
    private let reducer = ShengjiTierReducer()
    private let levels = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

    init(
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let red = localizedSideRedName()
        let blue = localizedSideBlueName()
        var left = initialSetup?.team1Name.nonEmpty ?? red
        var right = initialSetup?.team2Name.nonEmpty ?? blue
        var initial = ShengjiTierState()
        var start = Date()
        var id = "shengji_\(Int(start.timeIntervalSince1970))"
        var actions = 0

        if let initialRecordId,
           let draft = loadSpecializedDraft(recordId: initialRecordId, as: ShengjiTierState.self) {
            initial = draft.state
            start = draft.record.startTime
            id = draft.record.id
            actions = max(draft.record.totalScoreChanges, 1)
            left = draft.record.team1Name
            right = draft.record.team2Name
        }

        _state = State(initialValue: initial)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _leftName = State(initialValue: left)
        _rightName = State(initialValue: right)
    }

    var body: some View {
        ZStack {
            SpecializedScoreboardScaffold(
                gameType: .shengji,
                leftName: leftName,
                rightName: rightName,
                leftScore: level(state.leftIndex),
                rightScore: level(state.rightIndex),
                leftDetail: state.dealer == .left ? NSLocalizedString("shengji_dealer", value: "庄家", comment: "") : nil,
                rightDetail: state.dealer == .right ? NSLocalizedString("shengji_dealer", value: "庄家", comment: "") : nil,
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
                bottomBar: { AnyView(shengjiBottomBar) }
            ) {
                Group {
                    if state.dealer == nil {
                        Text(NSLocalizedString("shengji_select_dealer", value: "先选庄家，再记升级", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
            }

            if state.finished {
                let winnerName = state.leftIndex >= state.maxTierIndex ? leftName : rightName
                GameFinishedOverlay(winnerName: winnerName)
            }
        }
        .onAppear { onSetupConsumed?(); registerSync() }
        .onChange(of: state) { _, _ in LocalScoreboardSyncCoordinator.shared.publishSnapshot() }
        .onDisappear { LocalScoreboardSyncCoordinator.shared.unregisterHost(); saveRecord() }
    }

    private var shengjiBottomBar: some View {
        Group {
            if state.dealer == nil {
                HStack(spacing: 12) {
                    Button(NSLocalizedString("shengji_claim_dealer_left", value: "红方抢庄", comment: "")) {
                        send(.claimDealer(.left))
                    }
                    Button(NSLocalizedString("shengji_claim_dealer_right", value: "蓝方抢庄", comment: "")) {
                        send(.claimDealer(.right))
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 18)
            } else if !state.finished {
                VStack(spacing: 10) {
                    HStack(spacing: 16) {
                        shengjiSideControls(side: .left, name: leftName)
                        shengjiSideControls(side: .right, name: rightName)
                    }
                    HStack(spacing: 10) {
                        Button(NSLocalizedString("shengji_red_minus_one", value: "红方 -1", comment: "")) {
                            send(.subtractLevels(side: .left, delta: 1))
                        }
                        Button(NSLocalizedString("shengji_blue_minus_one", value: "蓝方 -1", comment: "")) {
                            send(.subtractLevels(side: .right, delta: 1))
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                .padding(.bottom, 14)
            }
        }
    }

    private func shengjiSideControls(side: MatchSide, name: String) -> some View {
        let canTakeDealer = state.dealer != side
        return VStack(spacing: 6) {
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            HStack(spacing: 6) {
                if canTakeDealer {
                    Button(NSLocalizedString("shengji_take_dealer", value: "上台", comment: "")) {
                        send(.resolveRound(winner: side, delta: 0))
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }
                ForEach([1, 2, 3], id: \.self) { step in
                    Button("+\(step)") {
                        send(.resolveRound(winner: side, delta: step))
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption.weight(.bold))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func level(_ index: Int) -> String { levels[min(max(0, index), levels.count - 1)] }
    private func send(_ intent: ShengjiTierIntent) {
        let result = reducer.reduce(state: state, intent: intent, at: nowMilliseconds())
        guard result.accepted else { return }
        history.append(state)
        state = result.state
        actionCount += 1
        actionLog.append(recordSnapshot(code: String(describing: intent), scores: [state.leftIndex, state.rightIndex]))
    }
    private func undo() {
        guard let previous = history.popLast() else { return }
        state = previous
        actionCount = max(0, actionCount - 1)
        actionLog.append(recordSnapshot(code: "undo", scores: [state.leftIndex, state.rightIndex]))
    }
    private func resetMatch() {
        history.append(state)
        state = ShengjiTierState(maxTierIndex: state.maxTierIndex)
        actionCount += 1
        actionLog.append(recordSnapshot(code: "reset", scores: [state.leftIndex, state.rightIndex]))
    }
    private func finishMatch() {
        guard !state.finished else { return }
        history.append(state)
        state.finished = true
        actionCount += 1
        actionLog.append(recordSnapshot(code: "finish", scores: [state.leftIndex, state.rightIndex]))
    }
    private func applyEdit(left: String, right: String, leftScore: String, rightScore: String) {
        history.append(state)
        if !left.isEmpty { leftName = left }
        if !right.isEmpty { rightName = right }
        if let leftIndex = levels.firstIndex(of: leftScore.uppercased()) { state.leftIndex = leftIndex }
        if let rightIndex = levels.firstIndex(of: rightScore.uppercased()) { state.rightIndex = rightIndex }
        state.finished = state.leftIndex >= state.maxTierIndex || state.rightIndex >= state.maxTierIndex
        actionCount += 1
    }
    private func exit() { saveRecord(); onNavigationBack?(); dismiss() }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            switch intent {
            case .addLeft:
                if state.dealer == nil { send(.claimDealer(.left)) }
                else { send(.resolveRound(winner: .left, delta: 1)) }
            case .addRight:
                if state.dealer == nil { send(.claimDealer(.right)) }
                else { send(.resolveRound(winner: .right, delta: 1)) }
            case .subtractLeft: send(.subtractLevels(side: .left, delta: 1))
            case .subtractRight: send(.subtractLevels(side: .right, delta: 1))
            case .undo: undo()
            default: break
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        .init(
            gameID: GameType.shengji.canonicalScoreboardIdentifier,
            title: GameType.shengji.displayName,
            leftName: leftName,
            rightName: rightName,
            leftScore: level(state.leftIndex),
            rightScore: level(state.rightIndex),
            leftDetail: nil,
            rightDetail: nil,
            themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue,
            fontID: ScoreboardAppearanceSnapshot.current().font.rawValue,
            finished: state.finished,
            revision: 0
        )
    }
    private func saveRecord() {
        saveSpecializedRecord(
            id: recordID, gameType: .shengji, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftIndex, right: state.rightIndex,
            actionCount: actionCount, actions: actionLog, finished: state.finished, snapshot: state
        )
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

private func loadSpecializedDraft<State: Decodable>(
    recordId: String,
    as type: State.Type
) -> (record: ScoreboardRecord, state: State)? {
    guard let record = ScoreboardRecordManager.shared.getRecordById(recordId),
          record.status == .draft,
          let data = record.stateSnapshot,
          let state = try? JSONDecoder().decode(type, from: data) else {
        return nil
    }
    return (record, state)
}

private func saveSpecializedRecord<State: Encodable>(
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
    finished: Bool,
    snapshot: State,
    extra: [String: Any] = [:]
) {
    guard actionCount > 0 else { return }
    let end = Date()
    let winner = left == right ? nil : (left > right ? "left" : "right")
    let snapshotData = try? JSONEncoder().encode(snapshot)
    var extraData: [String: AnyCodable] = [
        "schemaVersion": AnyCodable(3),
        "canonicalGameType": AnyCodable(gameType.canonicalScoreboardIdentifier)
    ]
    for (key, value) in extra {
        extraData[key] = AnyCodable(value)
    }
    let record = ScoreboardRecord(
        id: id,
        gameType: gameType,
        startTime: startedAt,
        endTime: end,
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
        stateSnapshot: snapshotData,
        status: finished ? .finished : .draft
    )
    try? ScoreboardRecordManager.shared.saveScoreboardRecord(record)
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
