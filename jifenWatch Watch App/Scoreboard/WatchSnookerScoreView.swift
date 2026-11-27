import LinkCore
import LinkSync
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI

enum WatchSnookerBallAvailability {
    static func isAvailable(_ ball: SnookerBall, in state: SnookerState) -> Bool {
        switch state.nextBallStage {
        case .red:
            return ball == .red && state.redBallsRemaining > 0
        case .color:
            return ball != .red
        case .yellow:
            return ball == .yellow
        case .green:
            return ball == .green
        case .brown:
            return ball == .brown
        case .blue:
            return ball == .blue
        case .pink:
            return ball == .pink
        case .black:
            return ball == .black
        case .complete:
            return false
        }
    }
}

private struct PendingSnookerFoul: Equatable {
    let side: MatchSide
    let points: Int
}

struct WatchSnookerScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let linkedSessionId: UUID?
    @State private var linkedMatchHandle: LinkedMatchHandle?

    @State private var showRecordSaveFailure = false
    @State private var leftName: String
    @State private var rightName: String
    /// 通用同步宿主：比分、撤销栈、时间线与动作日志只有这一处真相。
    @State private var store: WatchReducerSessionStore<SnookerReducer>
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var localRecordID = "w_\(UUID().uuidString)"
    @State private var scoreboardLayout: String = "horizontal"
    @State private var scoringSide: MatchSide?
    @State private var pendingFoul: PendingSnookerFoul?
    @State private var showFrameSettlement = false
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
    @State private var undoToastToken: UUID?

    init(
        initialState: SnookerState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil,
        resumeBundle: WatchSnookerResumeBundle? = nil,
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve(for: .snooker)
        let resolvedLeft = leftName ?? defaults.left
        let resolvedRight = rightName ?? defaults.right
        self.linkedSessionId = linkedSessionId
        _leftName = State(initialValue: resolvedLeft)
        _rightName = State(initialValue: resolvedRight)
        let startedAt = resumedStartTime ?? Date()
        let binding = WatchBoardBindings.snooker()
        let actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        if let resumeBundle {
            // 续玩只走标准 bundle：比分、撤销帧与时间线一并恢复。
            _store = State(initialValue: WatchReducerSessionStore(
                resumeBundle: resumeBundle,
                reducer: SnookerReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        } else {
            let seed = initialState ?? SnookerState.initial()
            let descriptor = ScoreboardKernelRegistry.descriptor(for: .snooker)
            let session = ScoreSession<SnookerState, SnookerEvent>(
                gameType: .snooker,
                ruleFamily: descriptor.ruleFamily,
                reducerType: descriptor.reducerType,
                state: seed,
                participants: [
                    .init(id: TeamID.team0.rawValue, name: resolvedLeft, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: resolvedRight, role: "team")
                ]
            )
            _store = State(initialValue: WatchReducerSessionStore(
                seedSession: session,
                reducer: SnookerReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        }
        _matchStartTime = State(initialValue: startedAt)
    }

    private var state: SnookerState { store.state }

    private var linkedMatchUnavailable: Bool {
        guard linkedSessionId != nil else { return false }
        guard let linkedMatchHandle, linkedMatchHandle == linkService.activeHandle,
              store.linkedIntentUpdate?.handle == linkedMatchHandle else { return true }
        return !linkService.canEditLinkedMatch
    }

    private var scoringLocked: Bool {
        linkedMatchUnavailable || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed
    }

    private var canPlayAgain: Bool {
        guard linkedSessionId != nil else { return true }
        guard let handle = linkedMatchHandle, !linkedMatchUnavailable, store.isLinkedFinishConfirmed else { return false }
        return store.savedRecordID == "w_\(handle.matchId.uuidString)"
            && !linkService.intentSync.hasPendingOperations(for: handle)
    }

    private var linkedMenuActions: [WatchMenuExtraAction] {
        guard linkedSessionId != nil, !linkedMatchUnavailable else { return [] }
        return [
            WatchMenuExtraAction(
                id: "sync-linked-scores",
                title: NSLocalizedString("linked_score_resync", value: "Sync score", comment: ""),
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                showMenu = false
                linkService.syncLinkedScores()
            },
            WatchMenuExtraAction(
                id: "end-score-link",
                title: NSLocalizedString("linked_score_end", value: "End link", comment: ""),
                systemImage: "link.badge.minus"
            ) {
                guard !store.isPendingLinkedFinish else { return }
                showMenu = false
                linkService.leaveSession()
            }
        ]
    }
    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    private var pendingFinishUndoAction: (() -> Void)? {
        guard store.canUndo else { return nil }
        return { undo() }
    }

    @ViewBuilder
    private var finishLayer: some View {
        if store.isPendingLinkedFinish {
            WatchLinkedFinishWaitingOverlay(onSync: { linkService.syncLinkedScores() }, onUndo: pendingFinishUndoAction)
        } else if showFinishedOverlay {
            WatchFinishedOverlay(
                title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                scoreItems: [
                    WatchFinishedScoreItem(name: leftName, score: state.maxFrames == 1 ? state.leftScore : state.leftFrames),
                    WatchFinishedScoreItem(name: rightName, score: state.maxFrames == 1 ? state.rightScore : state.rightFrames)
                ],
                undoAvailable: linkedSessionId == nil && finishUndoAvailable,
                canPlayAgain: canPlayAgain,
                onUndo: undoFinishedSnooker,
                onPlayAgain: restartMatch,
                onExit: {
                    if linkedSessionId == nil, !finalizeSnooker() { return }
                    exitSnooker()
                }
            )
        }
    }

    var body: some View {
        ZStack {
            Group {
                if isHorizontal {
                    HStack(spacing: 0) {
                        scoreHalf(.left)
                        scoreHalf(.right)
                    }
                } else {
                    GeometryReader { proxy in
                        let halfHeight = proxy.size.height / 2
                        VStack(spacing: 0) {
                            scoreHalf(.left)
                                .frame(height: halfHeight)
                            scoreHalf(.right)
                                .frame(height: halfHeight)
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .disabled(!interactionsEnabled)
            if showMenu {
                WatchScoreboardMenuOverlay(
                    onDismiss: { showMenu = false },
                    onUndo: {
                        guard !scoringLocked else { return }
                        undo()
                        showMenu = false
                    },
                    onFinish: {
                        guard !scoringLocked else { return }
                        showMenu = false
                        confirmation = .finish
                    },
                    onReset: {
                        guard !scoringLocked else { return }
                        showMenu = false
                        if linkedSessionId == nil {
                            confirmation = .reset
                        } else {
                            restartMatch()
                        }
                    },
                    extraActions: linkedMenuActions
                )
            }
            if let scoringSide {
                snookerScoringPanel(for: scoringSide)
            }
            if let pendingFoul {
                snookerFoulTurnPanel(pendingFoul)
            }
            if showFrameSettlement {
                snookerFrameSettlementPanel
            }
            if state.frameCompletePending {
                snookerNextFramePanel
            }
            finishLayer
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirmSnooker(confirmation) }
                )
            }
        }
        .watchFinishSaveFailure(isPresented: $showRecordSaveFailure) { finalizeSnooker() }
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.intentSync.update, initial: true) { _, update in
            applyLinkedUpdate(update)
        }
        .onChange(of: state) { _, _ in
            persistResumeSession()
        }
        .onDisappear {
            finishTask?.cancel()
            if linkedSessionId == nil, state.finished { finalizeSnooker() }
            persistResumeSession()
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: menuGesturesEnabled,
            onMenu: { showMenu = true },
            onUndo: undo,
            onExit: exitSnooker
        )
        .watchUndoToast(token: $undoToastToken)
    }

    private func scoreHalf(_ screenSide: MatchSide) -> some View {
        let isLeftScreen = screenSide == .left
        let side = snookerLogicalSide(onScreen: isLeftScreen ? .left : .right)
        let isLeft = side == .left
        let name = isLeft ? leftName : rightName
        let score = isLeft ? state.leftScore : state.rightScore
        let scoreText = "\(score)"
        let frames = isLeft ? state.leftFrames : state.rightFrames
        let color = isLeft ? WatchTheme.teamRed : WatchTheme.teamBlue
        let scoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 56 : 62,
            scoreText: scoreText,
            minimumSize: isHorizontal ? 40 : 44
        )
        let frameScore = Text("\(frames)")
            .font(WatchScoreTypography.secondaryScore(size: 14))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))
        let scoreLabel = Text(scoreText)
            .font(WatchScoreTypography.primaryScore(size: scoreFont))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)

        return ZStack {
            WatchScoreboardFace(isHorizontal: isHorizontal) {
                Text(name)
                    .font(.system(size: WatchScoreTypography.teamNameSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(isHorizontal ? 0.6 : 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } score: {
                if !isHorizontal, state.maxFrames > 1 {
                    VStack(spacing: 0) {
                        scoreLabel.frame(maxHeight: .infinity)
                        frameScore.padding(.bottom, 6)
                    }
                } else {
                    scoreLabel
                }
            }
            if isHorizontal, state.maxFrames > 1 {
                frameScore
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 22)
                    .offset(y: WatchLayout.scoreboardMetaVerticalOffset)
            }
            snookerServerIndicator(onScreen: screenSide, logicalSide: side)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressTapAfterLongPress else { return }
            // Tapping either half opens the current striker's panel. This matches
            // the phone and HarmonyOS behavior and prevents scoring for the wrong side.
            scoringSide = state.striker
        }
    }

    private func snookerServerIndicator(onScreen screenSide: MatchSide, logicalSide: MatchSide) -> some View {
        let isLeft = screenSide == .left
        let direction: WatchServerIndicatorDirection = isHorizontal
            ? (isLeft ? .right : .left)
            : (isLeft ? .bottom : .top)
        let alignment: Alignment = isHorizontal
            ? (isLeft ? .leading : .trailing)
            : (isLeft ? .top : .bottom)
        let insets = EdgeInsets(
            top: alignment == .top ? 0 : 12,
            leading: alignment == .leading ? 0 : 12,
            bottom: alignment == .bottom ? 0 : 12,
            trailing: alignment == .trailing ? 0 : 12
        )

        return WatchServerIndicator(
            direction: direction,
            size: WatchLayout.serverIndicatorSize,
            color: WatchTheme.accent
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(insets)
            .offset(y: WatchLayout.serverIndicatorVerticalOffset(isHorizontal: isHorizontal))
            .opacity(state.striker == logicalSide ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func snookerLogicalSide(onScreen side: MatchSide) -> MatchSide {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped).engineSide(onScreen: side)
    }

    private func snookerScoringPanel(for side: MatchSide) -> some View {
        let compact = WatchLayout.isCompactScreen
        return WatchFullScreenOverlay(scrim: WatchTheme.overlayCard) { _, _ in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: compact ? 8 : 10) {
                        Text(side == .left ? leftName : rightName)
                            .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible()), count: 4),
                            spacing: 5
                        ) {
                            ForEach(SnookerBall.allCases, id: \.rawValue) { ball in
                                let isAvailable = WatchSnookerBallAvailability.isAvailable(ball, in: state)
                                Button {
                                    apply(.potBallAsSide(side: side, points: ball.rawValue))
                                    scoringSide = nil
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(snookerBallColor(ball))
                                        Text("\(ball.rawValue)")
                                            .font(.system(
                                                size: compact ? 14 : 16,
                                                weight: .bold
                                            ))
                                            .foregroundStyle(snookerBallTextColor(ball))
                                    }
                                    .frame(
                                        width: WatchLayout.snookerBallButtonSize,
                                        height: WatchLayout.snookerBallButtonSize
                                    )
                                    .frame(maxWidth: .infinity)
                                    .opacity(isAvailable ? 1 : 0.45)
                                }
                                .buttonStyle(.plain)
                                .disabled(!isAvailable)
                            }
                        }
                        HStack(spacing: 4) {
                            ForEach(4...7, id: \.self) { points in
                                Button {
                                    pendingFoul = PendingSnookerFoul(side: side, points: points)
                                } label: {
                                    Text("\(NSLocalizedString("watch_snooker_foul", value: "犯规", comment: "")) \(points)")
                                        .font(.system(size: compact ? 9 : 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: compact ? 28 : 32)
                                        .background(WatchTheme.dangerRed.opacity(0.82), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 6) {
                            Button {
                                apply(.handoverFromPanel(side))
                                scoringSide = nil
                            } label: {
                                Text(NSLocalizedString("watch_snooker_handover", value: "换手", comment: ""))
                                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: compact ? 32 : 36)
                                    .background(WatchTheme.card, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            Button {
                                scoringSide = nil
                                showFrameSettlement = true
                            } label: {
                                Text(NSLocalizedString("watch_snooker_settle_frame", value: "结算本局", comment: ""))
                                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: compact ? 32 : 36)
                                    .background(WatchTheme.card, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, compact ? 26 : 34)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)

                WatchMenuCloseButton { scoringSide = nil }
                    .padding(.top, 4)
                    .padding(.bottom, compact ? 6 : 8)
                    .frame(maxWidth: .infinity)
                    .background(WatchTheme.overlayCard)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func snookerFoulTurnPanel(_ foul: PendingSnookerFoul) -> some View {
        let compact = WatchLayout.isCompactScreen
        return WatchFullScreenOverlay(scrim: WatchTheme.overlayCard) { _, _ in
            ZStack(alignment: .bottom) {
                VStack(spacing: compact ? 6 : 8) {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("watch_snooker_foul_selected_format", value: "犯规 +%d", comment: ""),
                        foul.points
                    ))
                    .font(.headline)
                    .foregroundStyle(.white)

                    Text(NSLocalizedString("watch_snooker_foul_next_turn", value: "下一杆", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))

                    Button {
                        commitFoul(foul, switchTurn: true)
                    } label: {
                        Text(NSLocalizedString("watch_snooker_foul_switch_turn", value: "换手", comment: ""))
                            .font(.system(size: compact ? 13 : 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 36 : 40)
                            .background(WatchTheme.dangerRed, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(width: WatchLayout.overlayActionButtonWidth)

                    Button {
                        commitFoul(foul, switchTurn: false)
                    } label: {
                        Text(NSLocalizedString("watch_snooker_foul_continue", value: "继续击球", comment: ""))
                            .font(.system(size: compact ? 13 : 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 36 : 40)
                            .background(WatchTheme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(width: WatchLayout.overlayActionButtonWidth)
                }
                .padding(.horizontal, 8)
                .padding(.top, compact ? 22 : 28)
                .padding(.bottom, WatchLayout.overlayCloseButtonSize + 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                WatchMenuCloseButton { pendingFoul = nil }
                    .padding(.bottom, compact ? 6 : 8)
            }
        }
    }

    private func commitFoul(_ foul: PendingSnookerFoul, switchTurn: Bool) {
        guard !scoringLocked, !state.finished else {
            pendingFoul = nil
            scoringSide = nil
            return
        }
        apply(.foulFromSide(side: foul.side, pointsToOpponent: foul.points, switchTurn: switchTurn))
        pendingFoul = nil
        scoringSide = nil
    }

    private var snookerFrameSettlementPanel: some View {
        let compact = WatchLayout.isCompactScreen
        return WatchFullScreenOverlay(scrim: WatchTheme.overlayCard) { _, _ in
            VStack(spacing: 0) {
                Spacer(minLength: compact ? 30 : 38)

                VStack(spacing: compact ? 8 : 12) {
                    Text(NSLocalizedString("watch_snooker_choose_frame_winner", value: "选择本局胜者", comment: ""))
                        .font(.system(size: compact ? 14 : 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.bottom, compact ? 2 : 4)

                    Button {
                        showFrameSettlement = false
                        apply(.settleFrame(winner: .left))
                    } label: {
                        Text(leftName)
                            .font(.system(size: compact ? 13 : 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 36 : 42)
                            .background(WatchTheme.teamRed, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(width: WatchLayout.overlayActionButtonWidth)

                    Button {
                        showFrameSettlement = false
                        apply(.settleFrame(winner: .right))
                    } label: {
                        Text(rightName)
                            .font(.system(size: compact ? 13 : 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 36 : 42)
                            .background(WatchTheme.teamBlue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(width: WatchLayout.overlayActionButtonWidth)
                }

                Spacer(minLength: compact ? 6 : 10)

                WatchMenuCloseButton { showFrameSettlement = false }
                    .accessibilityLabel(NSLocalizedString("cancel", value: "取消", comment: ""))
                    .padding(.bottom, compact ? 6 : 10)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var snookerNextFramePanel: some View {
        let compact = WatchLayout.isCompactScreen
        return WatchFullScreenOverlay(scrim: WatchTheme.overlayCard) { _, _ in
            VStack(spacing: compact ? 8 : 11) {
                Text(NSLocalizedString("watch_snooker_frame_finished", value: "本局结束", comment: ""))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(state.leftFrames) : \(state.rightFrames)")
                    .font(WatchScoreTypography.primaryScore(size: compact ? 20 : 22))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.bottom, compact ? 2 : 6)
                Button {
                    apply(.confirmNextFrame)
                } label: {
                    Text(NSLocalizedString("watch_snooker_next_frame", value: "下一局", comment: ""))
                        .font(.system(size: compact ? 14 : 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: compact ? 36 : 40)
                        .background(WatchTheme.successGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(width: WatchLayout.overlayActionButtonWidth)
                Button {
                    confirmation = .finish
                } label: {
                    Text(NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""))
                        .font(.system(size: compact ? 14 : 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: compact ? 36 : 40)
                        .background(WatchTheme.card, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(width: WatchLayout.overlayActionButtonWidth)
            }
            .padding(.horizontal, 14)
            .padding(.top, compact ? 24 : 30)
            .padding(.bottom, 12)
        }
    }

    private func snookerBallColor(_ ball: SnookerBall) -> Color {
        switch ball {
        case .red: WatchTheme.teamRed
        case .yellow: Color(hex: 0xFDD835)
        case .green: Color(hex: 0x43A047)
        case .brown: Color(hex: 0x795548)
        case .blue: WatchTheme.teamBlue
        case .pink: Color(hex: 0xEC407A)
        case .black: .black
        }
    }

    private func snookerBallTextColor(_ ball: SnookerBall) -> Color {
        switch ball {
        case .yellow, .green, .pink: .black
        case .red, .brown, .blue, .black: .white
        }
    }

    private func apply(_ intent: SnookerIntent) {
        guard !scoringLocked, !state.finished, case .accepted = store.dispatch(intent) else { return }
        if linkedSessionId == nil, state.finished { beginSnookerFinish(manualEnd: false) }
    }

    private func finishMatch() {
        guard !scoringLocked, !state.finished else { return }
        if linkedSessionId != nil {
            if store.requestLinkedFinish() { persistResumeSession() }
            return
        }
        guard case .accepted = store.dispatch(.finishMatch) else { return }
        beginSnookerFinish(manualEnd: true)
    }

    private func saveLocalRecordIfNeeded() -> Bool {
        guard linkedSessionId == nil, store.savedRecordID == nil else { return true }
        guard state.finished || state.leftScore + state.rightScore + state.leftFrames + state.rightFrames > 0 else { return true }
        return store.saveFinishedRecord(
            into: resumeStore,
            gameType: .snooker,
            recordID: localRecordID,
            endTime: Date(),
            participantNames: [leftName, rightName],
            totalScoreChanges: store.actionLog.scoreChangeCount
        )
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func undo() {
        guard !linkedMatchUnavailable, !store.isLinkedFinishConfirmed, store.undo() else { return }
        undoToastToken = UUID()
    }

    private func restartMatch() {
        if linkedSessionId != nil {
            if canPlayAgain {
                store.requestLinkedNextMatch()
            } else if !scoringLocked, !state.finished {
                linkService.lastLinkErrorMessage = NSLocalizedString(
                    "linked_score_reset_unavailable",
                    value: "Finish this match before starting a new one.",
                    comment: "Live linked matches cannot be reset"
                )
            }
            return
        }
        guard finalizeSnooker() else { return }
        resumeStore.clear()
        finishTask?.cancel()
        let restartedAt = Date()
        // `.reset` 已由 binding 的 resetsActionLog 清空动作日志与撤销栈。
        guard case .accepted(_, _) = store.dispatch(.reset, at: restartedAt) else { return }
        store.beginRemoteMatch(at: restartedAt)
        // 新一局重新允许落库与续玩草稿写入。
        store.clearSavedRecord()
        localRecordID = "w_\(UUID().uuidString)"
        matchStartTime = restartedAt
        pendingFoul = nil
        scoringSide = nil
        showFrameSettlement = false
        showFinishedOverlay = false
        finishUndoAvailable = false
    }

    private var interactionsEnabled: Bool {
        !scoringLocked && !state.finished && !showMenu && scoringSide == nil && !showFrameSettlement
            && !state.frameCompletePending && confirmation == nil && !showFinishedOverlay
    }

    private var menuGesturesEnabled: Bool {
        !store.isPendingLinkedFinish && !state.finished && !showMenu && scoringSide == nil && pendingFoul == nil && !showFrameSettlement
            && !state.frameCompletePending && confirmation == nil && !showFinishedOverlay
    }

    private func applyLinkedUpdate(_ update: WatchLinkedIntentUpdate?) {
        guard let linkedSessionId, let update, update.handle.sessionId == linkedSessionId,
              update.handle == linkService.activeHandle, case .snooker = update.displayedSnapshot else { return }
        let previous = state
        let wasConfirmed = store.isLinkedFinishConfirmed
        if let linkedMatchHandle {
            guard linkedMatchHandle == update.handle else { return }
            store.applyLinkedIntentUpdate(update)
        } else {
            linkedMatchHandle = update.handle
            store.attachLinkedMatch(
                update.handle, sync: linkService.intentSync, intent: { .snooker($0) },
                state: { $0.snookerState }
            )
        }
        guard store.linkedIntentUpdate?.presentationSequence == update.presentationSequence else { return }
        matchStartTime = store.startedAt
        if let names = linkService.activeParticipantNames, names.count >= 2 {
            let remoteLeft = names[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteRight = names[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !remoteLeft.isEmpty { leftName = remoteLeft }
            if !remoteRight.isEmpty { rightName = remoteRight }
        }
        if previous != state || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed {
            showMenu = false
            confirmation = nil
            pendingFoul = nil
            scoringSide = nil
            showFrameSettlement = false
        }
        if store.isPendingLinkedFinish {
            finishTask?.cancel()
            showFinishedOverlay = false
            finishUndoAvailable = false
        } else if store.isLinkedFinishConfirmed {
            if !wasConfirmed { beginSnookerRemoteFinishPresentation() }
        } else if showFinishedOverlay || previous.finished {
            finishTask?.cancel()
            showFinishedOverlay = false
            finishUndoAvailable = false
        }
        persistResumeSession()
    }

    private func confirmSnooker(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish: finishMatch()
        case .reset: restartMatch()
        }
    }

    private func beginSnookerFinish(manualEnd: Bool) {
        finishTask?.cancel()
        showMenu = false
        pendingFoul = nil
        scoringSide = nil
        showFrameSettlement = false
        finishUndoAvailable = store.canUndo
        showFinishedOverlay = manualEnd
        finishTask = Task { @MainActor in
            if !manualEnd {
                try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
                guard !Task.isCancelled else { return }
                showFinishedOverlay = true
            }
            try? await Task.sleep(for: .seconds(WatchTiming.finishedUndoCountdown))
            guard !Task.isCancelled else { return }
            finishUndoAvailable = false
            finalizeSnooker()
        }
    }

    private func beginSnookerRemoteFinishPresentation() {
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            showFinishedOverlay = true
        }
    }

    @discardableResult
    private func finalizeSnooker() -> Bool {
        guard linkedSessionId == nil, state.finished, store.savedRecordID == nil else { return true }
        finishUndoAvailable = false
        guard saveLocalRecordIfNeeded() else {
            showRecordSaveFailure = true
            return false
        }
        resumeStore.clear()
        return true
    }

    private func undoFinishedSnooker() {
        guard linkedSessionId == nil, finishUndoAvailable else { return }
        finishTask?.cancel()
        // 完赛撤销窗内同样走宿主撤销：回到完赛前的比分与动作日志。
        guard store.undo() else { return }
        showFinishedOverlay = false
        finishUndoAvailable = false
        undoToastToken = UUID()
    }

    private func exitSnooker() {
        guard !store.isPendingLinkedFinish else { return }
        if let handle = linkedMatchHandle, handle == linkService.activeHandle {
            linkService.exitScoreboard(sessionId: handle.sessionId)
        }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        let context: WatchLinkResumeContext?
        if linkedSessionId != nil {
            guard let handle = linkedMatchHandle, handle == linkService.activeHandle,
                  let linkedContext = linkService.resumeContext, linkedContext.handle == handle else { return }
            if store.savedRecordID == "w_\(handle.matchId.uuidString)" {
                if resumeStore.session?.linkHandle == handle { resumeStore.clear() }
                return
            }
            context = linkedContext
        } else {
            if state.finished {
                if store.savedRecordID != nil, resumeStore.session?.linkHandle == nil { resumeStore.clear() }
                return
            }
            context = nil
        }
        guard hasSnookerProgress || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed else {
            if linkedSessionId == nil, resumeStore.session?.linkHandle == nil { resumeStore.clear() }
            return
        }
        store.persistResumeSession(
            into: resumeStore, link: context, startedAt: matchStartTime,
            payload: .snooker(bundle: store.resumeBundle(), leftName: leftName, rightName: rightName)
        )
    }

    private var hasSnookerProgress: Bool {
        state.leftScore != 0 || state.rightScore != 0
            || state.leftFrames != 0 || state.rightFrames != 0
            || state.currentFrame > 1 || store.canUndo || state.finished
    }

}
