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
                    VStack(spacing: 0) {
                        scoreHalf(.left)
                        scoreHalf(.right)
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
                        WatchFinishedScoreItem(name: leftName, score: String(state.leftFrames)),
                        WatchFinishedScoreItem(name: rightName, score: String(state.rightFrames))
                    ],
                    winnerText: snookerWinnerText,
                    undoAvailable: finishUndoAvailable,
                    onUndo: undoFinishedSnooker,
                    onPlayAgain: restartMatch,
                    onExit: {
                        finalizeSnooker()
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
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let remote = update.snapshot.snookerState else { return }
            applyAuthoritativeSnooker(remote, detailedActions: update.detailedActions)
        }
        .onChange(of: linkService.pendingReclaimAcceptance) { _, pending in
            guard let linkedSessionId, let pending, pending.sessionId == linkedSessionId,
                  let remote = pending.snapshot.snookerState else { return }
            applyAuthoritativeSnooker(remote, detailedActions: pending.detailedActions)
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
        let color = isLeft ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5)
        let scoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 56 : 62,
            scoreText: scoreText,
            minimumSize: isHorizontal ? 40 : 44
        )
        return ZStack {
            Text(scoreText)
                .font(WatchScoreTypography.primaryScore(size: scoreFont))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, isHorizontal ? 28 : 8)
                .offset(y: WatchLayout.scoreboardNameVerticalOffset)
            if state.maxFrames > 1 {
                Text("\(frames)")
                    .font(WatchScoreTypography.secondaryScore(size: 14))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, isHorizontal ? 22 : 16)
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
        let closeButtonSize = WatchLayout.overlayCloseButtonSize
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.84)
                .ignoresSafeArea()
                .onTapGesture { scoringSide = nil }
            ScrollView {
                VStack(spacing: WatchLayout.isCompactScreen ? 6 : 8) {
                    Text(side == .left ? leftName : rightName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
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
                                            size: WatchLayout.isCompactScreen ? 14 : 16,
                                            weight: .bold,
                                            design: .rounded
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
                    HStack(spacing: 5) {
                        ForEach(4...7, id: \.self) { points in
                            Button("\(NSLocalizedString("watch_snooker_foul", value: "犯规", comment: "")) \(points)") {
                                pendingFoul = PendingSnookerFoul(side: side, points: points)
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .buttonStyle(.bordered)
                            .tint(WatchTheme.dangerRed)
                        }
                    }
                    HStack(spacing: 6) {
                        Button {
                            apply(.handoverFromPanel(side))
                            scoringSide = nil
                        } label: {
                            Text(NSLocalizedString("watch_snooker_handover", value: "换手", comment: ""))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        Button {
                            scoringSide = nil
                            showFrameSettlement = true
                        } label: {
                            Text(NSLocalizedString("watch_snooker_settle_frame", value: "结算本局", comment: ""))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, closeButtonSize + 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchTheme.overlayCard)

            WatchMenuCloseButton { scoringSide = nil }
                .padding(.bottom, WatchLayout.isCompactScreen ? 4 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func snookerFoulTurnPanel(_ foul: PendingSnookerFoul) -> some View {
        ZStack(alignment: .bottom) {
            WatchTheme.overlayCard
                .ignoresSafeArea()

            VStack(spacing: WatchLayout.isCompactScreen ? 6 : 8) {
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
                        .frame(maxWidth: .infinity, minHeight: WatchLayout.isCompactScreen ? 36 : 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.dangerRed)
                .frame(width: WatchLayout.overlayActionButtonWidth)

                Button {
                    commitFoul(foul, switchTurn: false)
                } label: {
                    Text(NSLocalizedString("watch_snooker_foul_continue", value: "继续击球", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: WatchLayout.isCompactScreen ? 36 : 42)
                }
                .buttonStyle(.bordered)
                .frame(width: WatchLayout.overlayActionButtonWidth)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, WatchLayout.overlayCloseButtonSize + 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            WatchMenuCloseButton { pendingFoul = nil }
                .padding(.bottom, WatchLayout.isCompactScreen ? 4 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(NSLocalizedString("watch_snooker_choose_frame_winner", value: "选择本局胜者", comment: ""))
                    .font(.headline)
                Button(leftName) {
                    showFrameSettlement = false
                    apply(.settleFrame(winner: .left))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0xE53935))
                .frame(width: WatchLayout.overlayActionButtonWidth)
                Button(rightName) {
                    showFrameSettlement = false
                    apply(.settleFrame(winner: .right))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x1E88E5))
                .frame(width: WatchLayout.overlayActionButtonWidth)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchTheme.overlayCard)

            WatchMenuCloseButton { showFrameSettlement = false }
                .accessibilityLabel(NSLocalizedString("cancel", value: "取消", comment: ""))
                .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var snookerNextFramePanel: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(spacing: 9) {
                Text(NSLocalizedString("watch_snooker_frame_finished", value: "本局结束", comment: ""))
                    .font(.headline)
                Text("\(state.leftFrames) : \(state.rightFrames)")
                    .font(WatchScoreTypography.primaryScore(size: 20))
                    .monospacedDigit()
                Button(NSLocalizedString("watch_snooker_next_frame", value: "下一局", comment: "")) {
                    apply(.confirmNextFrame)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.successGreen)
                .frame(width: WatchLayout.overlayActionButtonWidth)
                Button(NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: "")) {
                    confirmation = .finish
                }
                .buttonStyle(.bordered)
                .frame(width: WatchLayout.overlayActionButtonWidth)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchTheme.overlayCard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func snookerBallColor(_ ball: SnookerBall) -> Color {
        switch ball {
        case .red: Color(hex: 0xE53935)
        case .yellow: Color(hex: 0xFDD835)
        case .green: Color(hex: 0x43A047)
        case .brown: Color(hex: 0x795548)
        case .blue: Color(hex: 0x1E88E5)
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
        actionLog.append(contentsOf: WatchScoreActionProjector.snooker(
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
        actionLog.append(contentsOf: WatchScoreActionProjector.snooker(
            intent: .finishMatch, events: result.events, state: state, timestamp: timestamp
        ))
        publish()
        if state.finished {
            beginSnookerFinish(manualEnd: true)
        }
    }

    private func publish() {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(
            .snooker(state),
            detailedActions: actionLog.detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private func saveLocalRecordIfNeeded() {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return }
        guard state.finished || state.leftScore + state.rightScore + state.leftFrames + state.rightFrames > 0 else { return }
        didSaveFinishedRecord = true
        let end = Date()
        let winnerName: String? = {
            if state.leftFrames != state.rightFrames {
                return state.leftFrames > state.rightFrames ? leftName : rightName
            }
            if state.leftScore == state.rightScore { return nil }
            return state.leftScore > state.rightScore ? leftName : rightName
        }()
        let record = WatchScoreboardRecord(
            id: "w_\(UUID().uuidString)",
            gameType: .snooker,
            startTime: matchStartTime,
            endTime: end,
            duration: end.timeIntervalSince(matchStartTime),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: state.leftScore,
            team2FinalScore: state.rightScore,
            team1SetScore: state.leftFrames,
            team2SetScore: state.rightFrames,
            winner: winnerName,
            actions: actionLog.actions,
            totalScoreChanges: actionLog.scoreChangeCount,
            projectConfiguration: ["maxFrames": String(state.maxFrames)]
        )
        WatchRecordManager.shared.saveRecord(record)
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
        guard !scoringLocked else { return }
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

    private func applyAuthoritativeSnooker(
        _ remote: SnookerState,
        detailedActions: [DetailedScoreAction]
    ) {
        actionLog.merge(detailedActions: detailedActions)
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

    private var snookerWinnerText: String? {
        guard state.leftFrames != state.rightFrames else { return nil }
        let winner = state.leftFrames > state.rightFrames ? leftName : rightName
        return String.localizedStringWithFormat(
            NSLocalizedString("watch_winner_format", value: "%@ 获胜", comment: ""),
            winner
        )
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

    private func finalizeSnooker(manualEnd: Bool = false) {
        guard state.finished, !didSaveFinishedRecord else { return }
        resumeStore.clear()
        if linkedSessionId != nil, linkService.isController {
            linkService.publishMatchFinished(
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
            didSaveFinishedRecord = true
        } else {
            saveLocalRecordIfNeeded()
        }
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
        if linkedSessionId != nil {
            linkService.exitScoreboardToHome()
        }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        guard !state.finished,
              state.leftScore != 0 || state.rightScore != 0
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
