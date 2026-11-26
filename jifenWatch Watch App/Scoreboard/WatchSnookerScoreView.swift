import LinkCore
import RecordCore
import ScoreCore
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
    @State private var lastAppliedRemoteRevision: UInt64?
    @State private var lastAppliedRemoteGeneration: UInt64?

    @State private var showRecordSaveFailure = false
    @State private var leftName: String
    @State private var rightName: String
    @State private var state: SnookerState
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var undoStack: [SnookerState] = []
    @State private var scoringSide: MatchSide?
    @State private var pendingFoul: PendingSnookerFoul?
    @State private var showFrameSettlement = false
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
    @State private var actionLog: WatchScoreActionLog
    @State private var undoToastToken: UUID?

    init(
        initialState: SnookerState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil,
        resumedUndoStates: [SnookerState] = [],
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve(for: .snooker)
        self.linkedSessionId = linkedSessionId
        _leftName = State(initialValue: leftName ?? defaults.left)
        _rightName = State(initialValue: rightName ?? defaults.right)
        _state = State(initialValue: initialState ?? SnookerState.initial())
        _undoStack = State(initialValue: resumedUndoStates)
        let startedAt = resumedStartTime ?? Date()
        _matchStartTime = State(initialValue: startedAt)
        _actionLog = State(initialValue: resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt))
    }

    private var scoringLocked: Bool { linkedSessionId != nil && linkService.isFollower }
    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

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
                        confirmation = .reset
                    },
                    onReclaim: scoringLocked ? {
                        linkService.requestReclaim()
                        showMenu = false
                    } : nil
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
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreItems: [
                        WatchFinishedScoreItem(name: leftName, score: state.maxFrames == 1 ? state.leftScore : state.leftFrames),
                        WatchFinishedScoreItem(name: rightName, score: state.maxFrames == 1 ? state.rightScore : state.rightFrames)
                    ],
                    undoAvailable: finishUndoAvailable,
                    canPlayAgain: !scoringLocked,
                    onUndo: undoFinishedSnooker,
                    onPlayAgain: restartMatch,
                    onExit: {
                        guard finalizeSnooker() else { return }
                        exitSnooker()
                    }
                )
            }
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
        .onChange(of: linkService.latestSnapshot, initial: true) { previous, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  update.matchGeneration == linkService.activeHandle?.matchGeneration,
                  let remote = update.snapshot.snookerState else { return }
            let acceptsScore = linkService.incomingSnapshot != nil
            if acceptsScore, linkService.controlRole == .shared, update.beginsMatch(after: previous) {
                matchStartTime = Date()
                actionLog.reset(at: matchStartTime)
            }
            let historyChanged = actionLog.merge(detailedActions: update.detailedActions, removing: update.removedActionIDs)
            let advancesScore = lastAppliedRemoteGeneration != update.matchGeneration
                || update.revision > (lastAppliedRemoteRevision ?? 0)
            let finishesCurrentScore = update.revision == lastAppliedRemoteRevision
                && update.snapshot.isFinished && previous?.snapshot.isFinished == false
            guard acceptsScore, advancesScore || finishesCurrentScore else {
                if historyChanged { persistResumeSession() }
                return
            }
            lastAppliedRemoteGeneration = update.matchGeneration
            lastAppliedRemoteRevision = update.revision
            applyAuthoritativeSnooker(remote)
        }
        .onChange(of: linkService.pendingReclaimAcceptance) { _, pending in
            guard let linkedSessionId, let pending, pending.sessionId == linkedSessionId,
                  let remote = pending.snapshot.snookerState else { return }
            actionLog.merge(detailedActions: pending.detailedActions)
            applyAuthoritativeSnooker(remote)
            linkService.completeReclaimAcceptance(messageId: pending.messageId)
        }
        .onChange(of: state) { _, _ in
            persistResumeSession()
        }
        .onDisappear {
            finishTask?.cancel()
            if state.finished { finalizeSnooker() }
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
        guard !scoringLocked, !showFinishedOverlay else { return }
        let timestamp = Date()
        actionLog.beginUndoableMutation()
        let result = SnookerReducer().reduce(state: state, intent: intent, at: Int64(timestamp.timeIntervalSince1970 * 1_000))
        guard result.accepted else {
            actionLog.rejectUndoableMutation()
            return
        }
        undoStack.append(state)
        state = result.state
        actionLog.append(contentsOf: ScoreActionProjector.snooker(
            intent: intent, events: result.events, state: state, timestamp: timestamp
        ))
        publish()
        if state.finished {
            beginSnookerFinish(manualEnd: false)
        }
    }

    private func finishMatch() {
        let timestamp = Date()
        actionLog.beginUndoableMutation()
        let result = SnookerReducer().reduce(
            state: state,
            intent: .finishMatch,
            at: Int64(timestamp.timeIntervalSince1970 * 1_000)
        )
        guard result.accepted else {
            actionLog.rejectUndoableMutation()
            return
        }
        undoStack.append(state)
        state = result.state
        actionLog.append(contentsOf: ScoreActionProjector.snooker(
            intent: .finishMatch, events: result.events, state: state, timestamp: timestamp
        ))
        publish()
        if state.finished {
            beginSnookerFinish(manualEnd: true)
        }
    }

    private func publish() {
        guard linkedSessionId != nil, linkService.canEditLinkedMatch else { return }
        linkService.publishSnapshot(
            .snooker(state),
            detailedActions: actionLog.detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private func saveLocalRecordIfNeeded() -> Bool {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return true }
        guard state.finished || state.leftScore + state.rightScore + state.leftFrames + state.rightFrames > 0 else { return true }
        let end = Date()
        guard let record = WatchScoreboardRecord(
            localSnapshot: .snooker(state), gameType: .snooker,
            id: "w_\(UUID().uuidString)", startTime: matchStartTime, endTime: end,
            participantNames: [leftName, rightName],
            detailedActions: actionLog.detailedActions, totalScoreChanges: actionLog.scoreChangeCount
        ) else { return false }
        return resumeStore.saveFinishedRecord(record)
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func undo() {
        guard !scoringLocked, let previous = undoStack.popLast() else { return }
        state = previous
        actionLog.undo(
            team1Score: state.leftScore,
            team2Score: state.rightScore,
            team1SetScore: state.leftFrames,
            team2SetScore: state.rightFrames
        )
        publish()
        undoToastToken = UUID()
    }

    private func restartMatch() {
        guard !scoringLocked, finalizeSnooker() else { return }
        resumeStore.clear()
        finishTask?.cancel()
        undoStack.removeAll()
        state = .initial(striker: state.firstBreaker, maxFrames: state.maxFrames)
        let restartedAt = Date()
        actionLog.reset(at: restartedAt)
        didSaveFinishedRecord = false
        matchStartTime = restartedAt
        pendingFoul = nil
        scoringSide = nil
        showFrameSettlement = false
        showFinishedOverlay = false
        finishUndoAvailable = false
        if linkedSessionId != nil {
            linkService.startNextMatch(
                snapshot: .snooker(state),
                participantNames: [leftName, rightName]
            )
        } else {
            publish()
        }
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    private var interactionsEnabled: Bool {
        !scoringLocked && !state.finished && !showMenu && scoringSide == nil && !showFrameSettlement
            && !state.frameCompletePending && confirmation == nil && !showFinishedOverlay
    }

    private var menuGesturesEnabled: Bool {
        !state.finished && !showMenu && scoringSide == nil && pendingFoul == nil && !showFrameSettlement
            && !state.frameCompletePending && confirmation == nil && !showFinishedOverlay
    }

    private func applyAuthoritativeSnooker(_ remote: SnookerState) {
        actionLog.clearUndoHistory()
        if let names = linkService.activeParticipantNames, names.count >= 2 {
            let remoteLeft = names[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteRight = names[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !remoteLeft.isEmpty { leftName = remoteLeft }
            if !remoteRight.isEmpty { rightName = remoteRight }
        }
        state = remote
        undoStack.removeAll()
        pendingFoul = nil
        scoringSide = nil
        showFrameSettlement = false
        if state.finished {
            beginSnookerRemoteFinishPresentation()
        } else {
            finishTask?.cancel()
            showFinishedOverlay = false
            finishUndoAvailable = false
            didSaveFinishedRecord = false
        }
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
        finishUndoAvailable = !undoStack.isEmpty
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
            finalizeSnooker(manualEnd: manualEnd)
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
    private func finalizeSnooker(manualEnd: Bool = false) -> Bool {
        guard state.finished, !didSaveFinishedRecord, !scoringLocked else { return true }
        finishUndoAvailable = false
        let saved: Bool
        if linkedSessionId != nil {
            saved = linkService.publishMatchFinished(
                snapshot: .snooker(state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: state.leftFrames == state.rightFrames
                    ? nil
                    : (state.leftFrames > state.rightFrames ? .left : .right),
                manualEnd: manualEnd,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: actionLog.scoreChangeCount,
                detailedActions: actionLog.detailedActions,
                participantNames: [leftName, rightName]
            )
        } else {
            saved = saveLocalRecordIfNeeded()
        }
        guard saved else {
            showRecordSaveFailure = true
            return false
        }
        didSaveFinishedRecord = true
        resumeStore.clear()
        return true
    }

    private func undoFinishedSnooker() {
        guard finishUndoAvailable, let previous = undoStack.popLast() else { return }
        finishTask?.cancel()
        state = previous
        actionLog.undo(
            team1Score: state.leftScore,
            team2Score: state.rightScore,
            team1SetScore: state.leftFrames,
            team2SetScore: state.rightFrames
        )
        showFinishedOverlay = false
        finishUndoAvailable = false
        didSaveFinishedRecord = false
        publish()
        undoToastToken = UUID()
    }

    private func exitSnooker() {
        if let linkedSessionId { linkService.exitScoreboard(sessionId: linkedSessionId) }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        if state.finished {
            if didSaveFinishedRecord { resumeStore.clear() }
            return
        }
        guard state.leftScore != 0 || state.rightScore != 0
                || state.leftFrames != 0 || state.rightFrames != 0
                || state.currentFrame > 1 || !undoStack.isEmpty else {
            resumeStore.clear()
            return
        }
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: "\(state.leftFrames)-\(state.rightFrames) / \(state.leftScore):\(state.rightScore)",
            emoji: "🎱",
            payload: .snooker(
                state: state,
                undoStates: undoStack,
                leftName: leftName,
                rightName: rightName
            ),
            actionLog: actionLog,
            link: linkService.resumeContext
        ))
    }

    private var hasSnookerProgress: Bool {
        state.leftScore != 0 || state.rightScore != 0
            || state.leftFrames != 0 || state.rightFrames != 0
            || state.currentFrame > 1 || !undoStack.isEmpty || state.finished
    }

}
