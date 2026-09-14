import OSLog
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI
import UIKit

func snookerNormalizedRecordCode(_ raw: String) -> String {
    (raw.split(separator: "|", omittingEmptySubsequences: false)[safe: 2].map(String.init) ?? raw)
        .lowercased()
}

func snookerFoulRecordTeam(fouler: MatchSide) -> RecordTeam {
    fouler == .left ? .team1 : .team2
}

struct SnookerScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?
    @State private var sessionStore: BilliardsSessionStore<SnookerReducer>
    @State private var actionLog: [String] = []
    @State private var detailedActions: [DetailedScoreAction] = []
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var leftName: String
    @State private var rightName: String
    @State private var matchTitle: String?
    @State private var matchTitleDraft: String
    @State private var showFoulPanel = false
    @State private var showSettlePanel = false
    @State private var showRecordPanel = false
    @State private var foulSwitchTurn = true
    @State private var settleWinner: MatchSide = .left
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var showPersistenceError = false
    @State private var manualFinishRequested = false
    @State private var scoreboardEditing = false
    @State private var isStartingNewMatch = false
    @State private var terminalFrameHold = ScoreboardTerminalHold<SnookerState>()
    @State private var typographyPreference = PreferencesManager.shared.scoreboardTypography(
        for: ScoreboardStyleID(gameType: .snooker)
    )
    // 对齐安卓 SnookerScoreScreen：点分数面板后底栏上下抖动提示。
    @State private var bottomBarAttentionTrigger = 0
    @State private var bottomBarShakeOffset: CGFloat = 0
    @State private var bottomBarShakeTask: Task<Void, Never>?

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

        let defaults = DefaultParticipantNames.resolve(for: .snooker)
        var left = initialSetup?.team1Name.nonEmpty ?? defaults.left
        var right = initialSetup?.team2Name.nonEmpty ?? defaults.right
        var title = ScoreboardMatchTitlePolicy.sanitize(initialSetup?.matchTitle)
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
        var restoredActionLog: [String] = []
        var restoredDetailedActions: [DetailedScoreAction] = []
        var showFinished = false
        var resumeBundle: BilliardsSessionStore<SnookerReducer>.ResumeBundle?

        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let bundle = BilliardsSessionStore<SnookerReducer>.decodeResumeBundle(sessionId: sessionId) {
            resumeBundle = bundle
            initial = bundle.currentSession.state
            start = bundle.currentSession.metadata.extras["startedAtEpochMilliseconds"]
                .flatMap(Int64.init)
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? start
            id = bundle.currentSession.metadata.extras["recordID"] ?? initialResumeSessionId
            title = ScoreboardMatchTitlePolicy.sanitize(
                bundle.currentSession.metadata.title
                    ?? bundle.currentSession.metadata.extras["matchTitle"]
                    ?? title
            )
            let recordContext = ScoreSessionRecordContext.decode(bundle.auxiliaryPayload)
            restoredActionLog = recordContext?.actionLog ?? []
            restoredDetailedActions = recordContext?.detailedActions ?? []
            actions = recordContext?.actionCount ?? bundle.timeline.count
            restoredHistory = bundle.undoFrames.map(\.session.state)
            if bundle.currentSession.participants.count >= 2 {
                left = bundle.currentSession.participants[0].name
                right = bundle.currentSession.participants[1].name
            }
            showFinished = initial.finished
        }

        let store = resumeBundle.map {
            BilliardsSessionStore(resumeBundle: $0, reducer: SnookerReducer())
        } ?? BilliardsSessionStore(
            gameType: .snooker,
            state: initial,
            reducer: SnookerReducer(),
            participants: [
                .init(id: TeamID.team0.rawValue, name: left, role: "team"),
                .init(id: TeamID.team1.rawValue, name: right, role: "team")
            ],
            startedAt: start,
            recordID: id,
            metadataTitle: title,
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
        _matchTitle = State(initialValue: title)
        _matchTitleDraft = State(initialValue: title ?? "")
        _showGameOverDialog = State(initialValue: showFinished)
    }

    private var state: SnookerState { sessionStore.state }
    private var displayedState: SnookerState { terminalFrameHold.value ?? state }



    private var scoringLocked: Bool {
        terminalFrameHold.value != nil || state.frameCompletePending
    }

    var body: some View {
        snookerContent
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            finishedRecordDetailPage
        }
        .onAppear {
            onSetupConsumed?()
            registerSync()

        }
        .onChange(of: state.finished) { _, finished in
            if finished, terminalFrameHold.value == nil {
                showGameOverDialog = true

            }
        }
        .onChange(of: state) { _, newState in
            if terminalFrameHold.value == nil {
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()

            }
        }
        .onChange(of: sessionStore.persistenceFailureSignal) { _, signal in
            if signal > 0 { showPersistenceError = true }
        }
        .onChange(of: bottomBarAttentionTrigger) { _, trigger in
            guard trigger > 0 else { return }
            runBottomBarShake()
        }

        .onDisappear {
            cancelTerminalFramePresentation()
            bottomBarShakeTask?.cancel()
            LocalScoreboardSyncCoordinator.shared.unregisterHost()

            sessionStore.flush {
                _ = saveRecord()
            }
        }
        .sheet(isPresented: $showSettlePanel) { settleSheet }
        .sheet(isPresented: $showRecordPanel) { snookerRecordSheet }
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
                        let left = state.maxFrames > 1 ? state.leftFrames : state.leftScore
                        let right = state.maxFrames > 1 ? state.rightFrames : state.rightScore
                        let scoreLine = "\(leftName) \(left) - \(right) \(rightName)"
                        ScoreboardShareSupport.present(
                            text: [matchTitle, scoreLine].compactMap { $0 }.joined(separator: "\n")
                        )
                    },
                    onExit: exit
                )
            }

            if state.frameCompletePending, let winner = state.pendingFrameWinner {
                snookerFrameResultOverlay(winner: winner)
                    .zIndex(50)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        .animation(.easeInOut(duration: 0.2), value: showFoulPanel)
    }

    private func snookerFrameResultOverlay(winner: MatchSide) -> some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("snooker_frame_result_title", value: "第 %d 局结束", comment: ""),
                    state.currentFrame
                ))
                .font(.headline.bold())

                Text("\(leftName) \(state.leftScore) : \(state.rightScore) \(rightName)")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text(String.localizedStringWithFormat(
                    NSLocalizedString("snooker_frame_winner_label", value: "本局胜方：%@", comment: ""),
                    winner == .left ? leftName : rightName
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(String.localizedStringWithFormat(
                    NSLocalizedString("snooker_frame_result_frames", value: "局分 %d : %d", comment: ""),
                    state.leftFrames,
                    state.rightFrames
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    confirmPendingFrame()
                } label: {
                    Text(NSLocalizedString("snooker_next_frame", value: "下一局", comment: ""))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("snooker_next_frame_button")
            }
            .foregroundStyle(.primary)
            .padding(22)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("snooker_frame_result_dialog")
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
        TwoSideScoreboardScaffold(
            gameType: .snooker,
            leftName: snookerName(onScreen: .left),
            rightName: snookerName(onScreen: .right),
            leftScore: "\(snookerValue(onScreen: .left, left: displayedState.leftScore, right: displayedState.rightScore))",
            rightScore: "\(snookerValue(onScreen: .right, left: displayedState.leftScore, right: displayedState.rightScore))",
            leftDetail: "\(snookerValue(onScreen: .left, left: displayedState.leftBreak, right: displayedState.rightBreak))",
            rightDetail: "\(snookerValue(onScreen: .right, left: displayedState.leftBreak, right: displayedState.rightBreak))",
            // 手机端当杆分数与大分数同行（外侧、底端对齐）；平板端保持在大分数下方。
            inlineSecondaryScore: !Theme.usesPadLayout,
            finished: displayedState.finished || terminalFrameHold.value != nil,
            // 对齐安卓 panelAttentionCallbacks.onTap：点击分数面板时底栏抖动提示。
            onLeftTap: { bottomBarAttentionTrigger += 1 },
            onRightTap: { bottomBarAttentionTrigger += 1 },
            onUndo: { undo() },
            onReset: { resetMatch() },
            // Android 3.1 removes the generic side-exchange action for snooker.
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
            scoringEnabled: true,
            onEditAdjust: { isLeft, delta in
                guard !scoringLocked else { return }
                adjustSnookerScore(side: snookerLogicalSide(onScreen: isLeft ? .left : .right), delta: delta)
            },
            extraMenuItems: [
                ScoreboardMenuItem(
                    title: NSLocalizedString("record", value: "记录", comment: ""),
                    action: "frameRecord",
                    group: .match,
                    icon: "list.bullet.rectangle",
                    backgroundColor: Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255).opacity(0.20),
                    sortOrder: 200
                ),
                ScoreboardMenuItem(
                    title: NSLocalizedString("snooker_settle_frame", value: "结算本局", comment: ""),
                    action: "settleFrame",
                    group: .match,
                    icon: "flag",
                    // 对齐安卓：浅绿高亮卡。
                    backgroundColor: Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255).opacity(0.20)
                )
            ] + [],
            onMenuAction: { action in
                switch action {
                case "frameRecord":
                    showRecordPanel = true
                case "settleFrame":
                    guard !scoringLocked else { return }
                    settleWinner = state.leftScore >= state.rightScore ? .left : .right
                    showSettlePanel = true

                default:
                    break
                }
            },
            seamOverlay: { indicatorColor in
                AnyView(
                    GeometryReader { geo in
                        let indicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                            halfViewportSize: CGSize(width: geo.size.width / 2, height: geo.size.height)
                        )
                        CenterLineServeIndicator(
                            isLeftServing: snookerLogicalSide(onScreen: .left) == displayedState.striker,
                            triangleSize: indicatorSize,
                            color: indicatorColor
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                )
            },
            bottomBar: { AnyView(snookerBottomBar) },
            panelContentBottomInset: Theme.usesPadLayout ? 112 : 86,
            topCenter: { preference, containerSize, appearance in
                AnyView(snookerTopCenter(preference: preference, containerSize: containerSize, appearance: appearance))
            },
            topCenterEditable: true,
            onEditModeChange: { editing in
                if editing {
                    matchTitleDraft = matchTitle ?? ""
                } else {
                    commitMatchTitle()
                }
                scoreboardEditing = editing
            },
            onTypographyChange: { preference in
                typographyPreference = preference
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            },
            sidesSwapped: displayedState.sidesSwapped
        ) { _, _ in
            EmptyView()
        }
    }

    private var snookerScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: displayedState.sidesSwapped)
    }

    private func snookerLogicalSide(onScreen screen: MatchSide) -> MatchSide {
        snookerScreenLayout.engineSide(onScreen: screen)
    }

    private func snookerName(onScreen screen: MatchSide) -> String {
        snookerLogicalSide(onScreen: screen) == .left ? leftName : rightName
    }

    private func snookerValue(onScreen screen: MatchSide, left: Int, right: Int) -> Int {
        snookerLogicalSide(onScreen: screen) == .left ? left : right
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
        let screenLeftFrames = snookerValue(onScreen: .left, left: displayedState.leftFrames, right: displayedState.rightFrames)
        let screenRightFrames = snookerValue(onScreen: .right, left: displayedState.leftFrames, right: displayedState.rightFrames)
        let detail = String(format: "%d %d/%d %d", screenLeftFrames, displayedState.currentFrame, displayedState.maxFrames, screenRightFrames)
        let secondarySize = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .twoSide,
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
                    Text("\(screenLeftFrames)").frame(width: 42)
                    Text(String(format: NSLocalizedString("snooker_current_frame_short", value: "第 %d/%d 局", comment: ""), displayedState.currentFrame, displayedState.maxFrames))
                        .font(preference.font.swiftUIFont(size: max(8, secondarySize * 0.68), weight: .semibold))
                    Text("\(screenRightFrames)").frame(width: 42)
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

    @ViewBuilder
    private func snookerTopCenter(
        preference: ScoreboardTypographyPreference,
        containerSize: CGSize,
        appearance: ScoreboardAppearanceSnapshot
    ) -> some View {
        VStack(spacing: 6) {
            if scoreboardEditing {
                TextField(
                    NSLocalizedString("match_title_placeholder", value: "例如：2026 城市公开赛", comment: ""),
                    text: Binding(
                        get: { matchTitleDraft },
                        set: { matchTitleDraft = ScoreboardMatchTitlePolicy.limitInput($0) }
                    )
                )
                .font(preference.font.swiftUIFont(size: Theme.usesPadLayout ? 18 : 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(width: max(150, min(360, containerSize.width * 0.44)), height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
                .accessibilityIdentifier("snooker_match_title_editor")
            } else if let matchTitle {
                Text(matchTitle)
                    .font(preference.font.swiftUIFont(size: (Theme.usesPadLayout ? 20 : 16) * preference.multiplier(for: ScoreboardStyleElementKeyV2.matchTitle), weight: .bold))
                    .foregroundStyle(matchTitleColor(appearance))
                    .styleElementSelectable(.matchTitle, slotKey: .sideCenter)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("snooker_match_title")
            }
            framePill(preference: preference, containerSize: containerSize)
        }
    }

    /// matchTitle 全局元素色：V2 已配置（.sideCenter 槽）时取元素色，否则保持白色。
    private func matchTitleColor(_ appearance: ScoreboardAppearanceSnapshot) -> Color {
        if appearance.hasElementColor(.matchTitle, slotKey: .sideCenter) {
            return appearance.elementForeground(.matchTitle, slotKey: .sideCenter)
        }
        return .white
    }

    private func commitMatchTitle() {
        let normalized = ScoreboardMatchTitlePolicy.sanitize(matchTitleDraft)
        guard normalized != matchTitle else { return }
        matchTitle = normalized
        matchTitleDraft = normalized ?? ""
        sessionStore.updateMetadataTitle(normalized)
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
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
        .offset(y: bottomBarShakeOffset)
    }

    /// 对齐安卓 SnookerBottomBar 的 attentionShake：垂直方向 2 轮衰减抖动，
    /// 每轮 -amp(50ms) → +amp(100ms) → 0(50ms)，振幅 0.75 → 0.585，
    /// 位移手机 5pt / 平板 6pt。
    private func runBottomBarShake() {
        bottomBarShakeTask?.cancel()
        bottomBarShakeOffset = 0
        let distance: CGFloat = Theme.usesPadLayout ? 6 : 5
        let amplitudes: [CGFloat] = [0.75, 0.585]
        bottomBarShakeTask = Task { @MainActor in
            for amplitude in amplitudes {
                withAnimation(.easeInOut(duration: 0.05)) { bottomBarShakeOffset = -amplitude * distance }
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.1)) { bottomBarShakeOffset = amplitude * distance }
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.05)) { bottomBarShakeOffset = 0 }
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
            }
        }
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
                    guard !scoringLocked else { return }
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
                .disabled(scoringLocked || displayedState.finished)
            }
            Button {
                guard !scoringLocked else { return }
                foulSwitchTurn = true
                showFoulPanel = true
            } label: {
                // 对齐安卓 snooker_foul_short：短文案 F/犯（16/20 Bold），完整文案作无障碍标签。
                Text(NSLocalizedString("snooker_foul_short", value: "犯", comment: ""))
                    .font(.system(size: Theme.usesPadLayout ? 20 : 16, weight: .bold))
                    .foregroundStyle(Color(hex: "FF453A"))
                    .frame(minWidth: controlSize, minHeight: controlSize)
                    .padding(.horizontal, actionHorizontalPadding)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("snooker_foul_button", value: "犯规", comment: ""))
            .accessibilityIdentifier("snooker_foul_button")
            .disabled(scoringLocked || displayedState.finished)
            Button {
                guard !scoringLocked else { return }
                send(.handover)
            } label: {
                // 对齐安卓 ic_menu_swap：交杆按钮用换手图标，无文字。
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: controlSize, minHeight: controlSize)
                    .padding(.horizontal, actionHorizontalPadding)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("snooker_handover", value: "交杆", comment: ""))
            .accessibilityIdentifier("snooker_action_handover")
            .disabled(scoringLocked || displayedState.finished)
        }
    }

    private func snookerControlFontSize(text: String, baseScale: CGFloat) -> CGFloat {
        ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .twoSide,
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

    /// Android 3.1 uses this only to highlight the expected ball. Referee
    /// exceptions remain manually recordable, so a dimmed ball is not disabled.
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
    }

    private func snookerRecordTitle(_ raw: String) -> String {
        let code = snookerNormalizedRecordCode(raw)
        if code.contains("potball") { return NSLocalizedString("snooker_record_pot", value: "进球", comment: "") }
        if code.contains("foul") { return NSLocalizedString("snooker_foul_button", value: "犯规", comment: "") }
        if code.contains("handover") { return NSLocalizedString("snooker_handover", value: "交杆", comment: "") }
        if code.contains("settleframe") { return NSLocalizedString("snooker_settle_frame", value: "结算本局", comment: "") }
        if code == "undo" { return NSLocalizedString("undone", value: "已撤销", comment: "") }
        if code == "reset" { return NSLocalizedString("has_been_reset", value: "已重置", comment: "") }
        if code.contains("admincorrect") { return NSLocalizedString("edit", value: "编辑", comment: "") }
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
        sessionStore.send(
            intent,
            completion: { previous, next, _ in
                projectAcceptedSnookerIntent(intent, previous: previous, next: next)
            },
            afterFinalized: { _, next, _ in
                if next.finished { _ = saveRecord() }
            }
        )
    }

    private func projectAcceptedSnookerIntent(
        _ intent: SnookerIntent,
        previous: SnookerState,
        next: SnookerState
    ) {
        actionCount += 1
        actionLog.append(ReducerScoreboardRecordPersistence.snapshot(
            code: String(describing: intent),
            scores: [next.leftScore, next.rightScore],
            setScores: [next.leftFrames, next.rightFrames]
        ))
        appendSnookerAction(intent, previousState: previous)
        if next.leftFrames != previous.leftFrames || next.rightFrames != previous.rightFrames {
            let winner: MatchSide = next.leftFrames > previous.leftFrames ? .left : .right
            detailedActions.append(snookerDetailedAction(
                type: .setFinished,
                team: winner == .left ? .team1 : .team2,
                code: "snooker_auto_settle_frame",
                setNumber: previous.currentFrame,
                scores: [next.leftScore, next.rightScore],
                setScores: [next.leftFrames, next.rightFrames]
            ))
        }
        persistRecordContext()
        if next.finished { showGameOverDialog = true }
    }

    private func confirmPendingFrame() {
        guard state.frameCompletePending else { return }
        sessionStore.send(.confirmNextFrame, completion: { _, next, _ in
            actionCount += 1
            actionLog.append(ReducerScoreboardRecordPersistence.snapshot(
                code: String(describing: SnookerIntent.confirmNextFrame),
                scores: [next.leftScore, next.rightScore],
                setScores: [next.leftFrames, next.rightFrames]
            ))
            persistRecordContext()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()

        })
    }

    private func settleCurrentFrame(winner: MatchSide) {
        guard !scoringLocked else { return }
        sessionStore.send(
            .settleFrame(winner: winner),
            completion: { previous, next, _ in
                actionCount += 1
                actionLog.append(ReducerScoreboardRecordPersistence.snapshot(
                    code: String(describing: SnookerIntent.settleFrame(winner: winner)),
                    scores: [previous.leftScore, previous.rightScore],
                    setScores: [next.leftFrames, next.rightFrames]
                ))
                appendSnookerAction(.settleFrame(winner: winner), previousState: previous)
                persistRecordContext()
                // The held terminal frame must be the exact authoritative
                // pre-settlement state, including any point queued just before
                // the settlement tap.
                terminalFrameHold.begin(previous) {
                    LocalScoreboardSyncCoordinator.shared.publishSnapshot()

                    if state.finished {
                        showGameOverDialog = true

                    }
                }
            },
            afterFinalized: { _, next, _ in
                if next.finished { _ = saveRecord() }
            }
        )
    }

    private func cancelTerminalFramePresentation() {
        terminalFrameHold.cancel()
    }

    private func undo() -> Bool {
        guard !state.frameCompletePending,
              (!state.finished || terminalFrameHold.value != nil) else { return false }
        cancelTerminalFramePresentation()
        return sessionStore.undo { success, restored in
            guard success else { return }
            actionLog = sessionStore.recordContext.actionLog
            detailedActions = sessionStore.recordContext.detailedActions
            actionCount = sessionStore.recordContext.actionCount
            showGameOverDialog = restored.finished
        }
    }
    private func exit() {
        cancelTerminalFramePresentation()
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
                isEditing: scoreboardEditing,
                finished: state.finished,
                scoringLocked: scoringLocked
            ) else { return }
            switch intent {
            case .addLeft: send(.potBallAsSide(side: snookerLogicalSide(onScreen: .left), points: 1))
            case .addRight: send(.potBallAsSide(side: snookerLogicalSide(onScreen: .right), points: 1))
            case .subtractLeft, .subtractRight, .undo: _ = undo()
            case .exchangeSides: send(.exchangeSides)
            default: break
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        let display = displayedState
        var snapshot = LocalScoreboardDisplayState(
            gameID: GameType.snooker.canonicalScoreboardIdentifier,
            title: matchTitle ?? "",
            leftName: snookerName(onScreen: .left),
            rightName: snookerName(onScreen: .right),
            leftScore: "\(snookerValue(onScreen: .left, left: display.leftScore, right: display.rightScore))",
            rightScore: "\(snookerValue(onScreen: .right, left: display.leftScore, right: display.rightScore))",
            leftDetail: String.localizedStringWithFormat(NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), snookerValue(onScreen: .left, left: display.leftFrames, right: display.rightFrames)),
            rightDetail: String.localizedStringWithFormat(NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), snookerValue(onScreen: .right, left: display.leftFrames, right: display.rightFrames)),
            themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue,
            fontID: typographyPreference.font.rawValue,
            scoreMultiplier: typographyPreference.scoreMultiplier,
            nameMultiplier: typographyPreference.nameMultiplier,
            secondaryMultiplier: typographyPreference.secondaryMultiplier,
            finished: display.finished,
            revision: 0,
            leftSets: snookerValue(onScreen: .left, left: display.leftFrames, right: display.rightFrames),
            rightSets: snookerValue(onScreen: .right, left: display.leftFrames, right: display.rightFrames)
        )
        // 显示端顶部信息条/单杆分（对齐安卓 snooker sportState 键，逻辑侧口径）。
        snapshot.externalState = ScoreboardDisplayState.enriched(
            compact: snapshot,
            layoutKind: .twoSide,
            sportState: [
                "snookerLeftBreak": .integer(display.leftBreak),
                "snookerRightBreak": .integer(display.rightBreak),
                "snookerMaxFrames": .integer(display.maxFrames),
                "currentSet": .integer(display.currentFrame),
                "team0ScreenSide": .string(display.sidesSwapped ? "right" : "left"),
                "servingTeam": .string(display.striker == .left ? "team_0" : "team_1")
            ]
        )
        return snapshot
    }
    private func resetMatch() {
        cancelTerminalFramePresentation()
        let resetState = SnookerState.initial(
            striker: state.firstBreaker,
            maxFrames: state.maxFrames
        )
        sessionStore.resetRuntime(to: resetState) { _ in
            actionLog = sessionStore.recordContext.actionLog
            detailedActions = sessionStore.recordContext.detailedActions
            actionCount = sessionStore.recordContext.actionCount
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        foulSwitchTurn = true
        showSettlePanel = false
        showFoulPanel = false
        showGameOverDialog = false
        manualFinishRequested = false
    }
    private func applyEditNames(left: String, right: String) {
        guard !scoringLocked else { return }
        for (screen, name) in [(MatchSide.left, left), (.right, right)] where !name.isEmpty {
            if snookerLogicalSide(onScreen: screen) == .left {
                leftName = name
            } else {
                rightName = name
            }
        }
        sessionStore.updateParticipants([
            .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
        ])
        actionCount += 1
        actionLog.append(ReducerScoreboardRecordPersistence.snapshot(code: "edit_names", scores: [state.leftScore, state.rightScore], setScores: [state.leftFrames, state.rightFrames]))
        detailedActions.append(snookerDetailedAction(type: .stateChanged, code: "snooker_edit_names"))
        persistRecordContext()
    }

    private func adjustSnookerScore(side: MatchSide, delta: Int) {
        guard delta != 0, !scoringLocked else { return }
        sessionStore.sendDerived(
            { current in
                let left = max(0, current.leftScore + (side == .left ? delta : 0))
                let right = max(0, current.rightScore + (side == .right ? delta : 0))
                guard left != current.leftScore || right != current.rightScore else { return nil }
                return .adminCorrect(left: left, right: right, striker: current.striker)
            },
            completion: { intent, previous, next, _ in
                projectAcceptedSnookerIntent(intent, previous: previous, next: next)
            },
            afterFinalized: { _, _, next, _ in
                if next.finished { _ = saveRecord() }
            }
        )
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
            type = .foul; team = snookerFoulRecordTeam(fouler: previousState.striker); delta = points
            code = "snooker_foul_\(points)_\(switchTurn ? "switch" : "continue")"
        case .foulFromSide(let side, let points, let switchTurn):
            type = .foul; team = snookerFoulRecordTeam(fouler: side); delta = points
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
        case .exchangeSides:
            type = .sideChanged; team = nil; delta = nil; code = "exchange_side"
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

    private func persistRecordContext() {
        sessionStore.updateRecordContext(
            actionLog: actionLog,
            detailedActions: detailedActions,
            actionCount: actionCount
        )
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
            epochMilliseconds: ReducerScoreboardRecordPersistence.nowMilliseconds(),
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
            let freshStore = BilliardsSessionStore(
                gameType: .snooker,
                state: freshState,
                reducer: SnookerReducer(),
                participants: [
                    .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
                ],
                startedAt: newStartedAt,
                recordID: newRecordID,
                metadataTitle: matchTitle
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

            }
        }
    }
    @discardableResult
    private func saveRecord() -> Bool {
        if state.finished, sessionStore.hasCommittedFinishedRecord {
            return true
        }
        var projectConfiguration: [String: AnyCodable] = [
            "maxSets": AnyCodable(state.maxFrames),
            "servingSide": AnyCodable(state.firstBreaker.rawValue)
        ]
        if let matchTitle {
            projectConfiguration["matchTitle"] = AnyCodable(matchTitle)
        }
        let success = ReducerScoreboardRecordPersistence.saveRecord(
            id: recordID, gameType: .snooker, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftScore, right: state.rightScore,
            leftSets: state.leftFrames, rightSets: state.rightFrames,
            actionCount: actionCount, actions: actionLog, detailedActions: detailedActions, undoStates: sessionStore.undoStates, finished: state.finished, snapshot: state,
            sessionSnapshotData: sessionStore.encodedResumeBundle,
            projectConfiguration: projectConfiguration,
            finishedSessionId: sessionStore.sessionId,
            finishedCommitCoordinator: sessionStore.finishedCommitCoordinator,
            replaceCommittedFinishedRecord: sessionStore.shouldReplaceCommittedFinishedRecord
        )
        if success, state.finished, actionCount > 0 {
            sessionStore.markFinishedRecordCommitted()
        }
        if !success { showPersistenceError = true }
        return success
    }
}


private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
