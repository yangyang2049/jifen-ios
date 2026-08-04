import LinkCore
import RecordCore
import ScoreCore
import SwiftUI

enum WatchEightBallScorePresentation {
    static func displayedRacks(state: EightBallState, side: MatchSide) -> Int {
        side == .left ? state.leftPoints : state.rightPoints
    }

    static func handicapText(state: EightBallState, side: MatchSide) -> String? {
        guard state.handicapBeneficiary == side, state.handicapRacks > 0 else { return nil }
        return "+\(state.handicapRacks)"
    }
}

/// Compact dual-side board for eight-ball / snooker-style rack or frame scoring on Watch.
struct WatchEightBallScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let linkedSessionId: UUID?
    @State private var leftName: String
    @State private var rightName: String
    @State private var state: EightBallState
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var undoStack: [EightBallState] = []
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
    @State private var actionLog: WatchScoreActionLog
    @State private var undoToastToken: UUID?

    init(
        initialState: EightBallState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil,
        resumedUndoStates: [EightBallState] = [],
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve(for: .eightBall)
        self.linkedSessionId = linkedSessionId
        _leftName = State(initialValue: leftName ?? defaults.left)
        _rightName = State(initialValue: rightName ?? defaults.right)
        _state = State(initialValue: initialState ?? .initial())
        _undoStack = State(initialValue: resumedUndoStates)
        let startedAt = resumedStartTime ?? Date()
        _matchStartTime = State(initialValue: startedAt)
        _actionLog = State(initialValue: resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt))
    }

    private var scoringLocked: Bool { linkedSessionId != nil && linkService.isFollower }
    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    var body: some View {
        ZStack {
            dualBoard(
                leftLabel: "\(eightBallPoints(onScreen: .left))",
                rightLabel: "\(eightBallPoints(onScreen: .right))",
                onLeft: { addRack(eightBallLogicalSide(onScreen: .left)) },
                onRight: { addRack(eightBallLogicalSide(onScreen: .right)) }
            )
            if !showMenu && !showFinishedOverlay {
                Text("\(state.targetPoints)")
                    .font(WatchScoreTypography.secondaryScore(size: 17))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.62))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
            }
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
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreItems: [
                        WatchFinishedScoreItem(name: leftName, score: String(state.leftPoints)),
                        WatchFinishedScoreItem(name: rightName, score: String(state.rightPoints))
                    ],
                    winnerText: eightBallWinnerText,
                    undoAvailable: finishUndoAvailable,
                    onUndo: undoFinishedEightBall,
                    onPlayAgain: restartMatch,
                    onExit: {
                        finalizeEightBall()
                        exitEightBall()
                    }
                )
            }
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirmEightBall(confirmation) }
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
                  let remote = update.snapshot.eightBallState else { return }
            applyAuthoritativeEightBall(remote, detailedActions: update.detailedActions)
        }
        .onChange(of: linkService.pendingReclaimAcceptance) { _, pending in
            guard let linkedSessionId, let pending, pending.sessionId == linkedSessionId,
                  let remote = pending.snapshot.eightBallState else { return }
            applyAuthoritativeEightBall(remote, detailedActions: pending.detailedActions)
            linkService.completeReclaimAcceptance(messageId: pending.messageId)
        }
        .onChange(of: state) { _, _ in
            persistResumeSession()
        }
        .onDisappear {
            finishTask?.cancel()
            if state.finished { finalizeEightBall() }
            persistResumeSession()
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: menuGesturesEnabled,
            onMenu: { showMenu = true },
            onUndo: undo,
            onExit: exitEightBall
        )
        .watchUndoToast(token: $undoToastToken)
    }

    private func addRack(_ side: MatchSide) {
        guard !scoringLocked, !state.finished else { return }
        let timestamp = Date()
        actionLog.beginUndoableMutation()
        let result = EightBallReducer().reduce(state: state, intent: .addRack(side), at: Int64(timestamp.timeIntervalSince1970 * 1_000))
        guard result.accepted else {
            actionLog.rejectUndoableMutation()
            return
        }
        undoStack.append(state)
        state = result.state
        actionLog.append(contentsOf: WatchScoreActionProjector.eightBall(
            events: result.events, state: state, timestamp: timestamp
        ))
        if state.finished {
            finishMatch(manual: false)
        } else {
            publish(manualEnd: false)
        }
    }

    private func finishMatch(manual: Bool) {
        if manual, !state.finished {
            undoStack.append(state)
            actionLog.beginUndoableMutation()
            state.finished = true
            actionLog.appendGameEndIfNeeded(
                team1Score: state.leftPoints,
                team2Score: state.rightPoints,
                winner: state.leftPoints == state.rightPoints ? nil : (state.leftPoints > state.rightPoints ? .team1 : .team2)
            )
        }
        publish(manualEnd: manual)
        beginEightBallFinish(manualEnd: manual)
    }

    private func publish(manualEnd: Bool) {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(
            .eightBall(state),
            detailedActions: actionLog.detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private func saveLocalRecordIfNeeded() {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return }
        guard state.finished || state.leftPoints + state.rightPoints > 0 else { return }
        didSaveFinishedRecord = true
        let end = Date()
        let winnerName: String? = {
            if state.leftPoints == state.rightPoints { return nil }
            return state.leftPoints > state.rightPoints ? leftName : rightName
        }()
        let record = WatchScoreboardRecord(
            id: "w_\(UUID().uuidString)",
            gameType: .eightBall,
            startTime: matchStartTime,
            endTime: end,
            duration: end.timeIntervalSince(matchStartTime),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: state.leftPoints,
            team2FinalScore: state.rightPoints,
            team1SetScore: state.leftPoints,
            team2SetScore: state.rightPoints,
            winner: winnerName,
            actions: actionLog.actions,
            totalScoreChanges: actionLog.scoreChangeCount,
            projectConfiguration: [
                "targetRacks": String(state.targetPoints),
                "handicapRacks": String(state.handicapRacks),
                "handicapBeneficiary": state.handicapBeneficiary?.rawValue ?? "none"
            ]
        )
        WatchRecordManager.shared.saveRecord(record)
    }

    @ViewBuilder
    private func dualBoard(
        leftLabel: String,
        rightLabel: String,
        onLeft: @escaping () -> Void,
        onRight: @escaping () -> Void
    ) -> some View {
        Group {
            if isHorizontal {
                HStack(spacing: 0) {
                    scoreHalf(
                        leftLabel,
                        name: eightBallName(onScreen: .left),
                        handicap: handicapText(for: eightBallLogicalSide(onScreen: .left)),
                        color: eightBallLogicalSide(onScreen: .left) == .left
                            ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5),
                        action: onLeft
                    )
                    scoreHalf(
                        rightLabel,
                        name: eightBallName(onScreen: .right),
                        handicap: handicapText(for: eightBallLogicalSide(onScreen: .right)),
                        color: eightBallLogicalSide(onScreen: .right) == .left
                            ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5),
                        action: onRight
                    )
                }
            } else {
                VStack(spacing: 0) {
                    scoreHalf(
                        leftLabel,
                        name: eightBallName(onScreen: .left),
                        handicap: handicapText(for: eightBallLogicalSide(onScreen: .left)),
                        color: eightBallLogicalSide(onScreen: .left) == .left
                            ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5),
                        action: onLeft
                    )
                    scoreHalf(
                        rightLabel,
                        name: eightBallName(onScreen: .right),
                        handicap: handicapText(for: eightBallLogicalSide(onScreen: .right)),
                        color: eightBallLogicalSide(onScreen: .right) == .left
                            ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5),
                        action: onRight
                    )
                }
            }
        }
        .ignoresSafeArea()
        .disabled(!interactionsEnabled)
    }

    private func eightBallLogicalSide(onScreen side: MatchSide) -> MatchSide {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped).engineSide(onScreen: side)
    }

    private func eightBallName(onScreen side: MatchSide) -> String {
        eightBallLogicalSide(onScreen: side) == .left ? leftName : rightName
    }

    private func eightBallPoints(onScreen side: MatchSide) -> Int {
        WatchEightBallScorePresentation.displayedRacks(
            state: state,
            side: eightBallLogicalSide(onScreen: side)
        )
    }

    private func scoreHalf(
        _ text: String,
        name: String,
        handicap: String?,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        let scoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 56 : 62,
            scoreText: text,
            minimumSize: isHorizontal ? 40 : 44
        )
        return ZStack {
            Text(text)
                .font(WatchScoreTypography.primaryScore(size: scoreFont))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 8)
                .padding(.top, isHorizontal ? 28 : 8)
                .offset(y: WatchLayout.scoreboardNameVerticalOffset)

            if let handicap {
                Text(handicap)
                    .font(WatchScoreTypography.secondaryScore(size: isHorizontal ? 20 : 22))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, isHorizontal ? 28 : 12)
                    .offset(y: WatchLayout.scoreboardMetaVerticalOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressTapAfterLongPress else { return }
            action()
        }
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func undo() {
        guard !scoringLocked, let previous = undoStack.popLast() else { return }
        state = previous
        actionLog.undo(team1Score: state.leftPoints, team2Score: state.rightPoints)
        publish(manualEnd: false)
        undoToastToken = UUID()
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        resumeStore.clear()
        finishTask?.cancel()
        let result = EightBallReducer().reduce(state: state, intent: .reset, at: nowMs())
        guard result.accepted else { return }
        undoStack.removeAll()
        state = result.state
        let restartedAt = Date()
        actionLog.reset(at: restartedAt)
        didSaveFinishedRecord = false
        matchStartTime = restartedAt
        showFinishedOverlay = false
        finishUndoAvailable = false
        if linkedSessionId != nil {
            linkService.startNextMatch(
                snapshot: .eightBall(state),
                participantNames: [leftName, rightName]
            )
        } else {
            publish(manualEnd: false)
        }
    }

    private var interactionsEnabled: Bool {
        !scoringLocked && !state.finished && !showMenu && confirmation == nil && !showFinishedOverlay
    }

    private var menuGesturesEnabled: Bool {
        !state.finished && !showMenu && confirmation == nil && !showFinishedOverlay
    }

    private func applyAuthoritativeEightBall(
        _ remote: EightBallState,
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
        if state.finished {
            beginEightBallRemoteFinishPresentation()
        } else {
            finishTask?.cancel()
            showFinishedOverlay = false
            finishUndoAvailable = false
            didSaveFinishedRecord = false
        }
    }

    private var eightBallWinnerText: String? {
        guard state.leftPoints != state.rightPoints else { return nil }
        let winner = state.leftPoints > state.rightPoints ? leftName : rightName
        return String.localizedStringWithFormat(
            NSLocalizedString("watch_winner_format", value: "%@ 获胜", comment: ""),
            winner
        )
    }

    private func handicapText(for side: MatchSide) -> String? {
        WatchEightBallScorePresentation.handicapText(state: state, side: side)
    }

    private func confirmEightBall(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish:
            finishMatch(manual: true)
        case .reset:
            restartMatch()
        }
    }

    private func beginEightBallFinish(manualEnd: Bool) {
        finishTask?.cancel()
        showMenu = false
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
            finalizeEightBall(manualEnd: manualEnd)
        }
    }

    private func beginEightBallRemoteFinishPresentation() {
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            showFinishedOverlay = true
        }
    }

    private func finalizeEightBall(manualEnd: Bool = false) {
        guard state.finished, !didSaveFinishedRecord else { return }
        resumeStore.clear()
        if linkedSessionId != nil, linkService.isController {
            linkService.publishMatchFinished(
                snapshot: .eightBall(state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: state.leftPoints == state.rightPoints
                    ? nil
                    : (state.leftPoints > state.rightPoints ? .left : .right),
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

    private func undoFinishedEightBall() {
        guard finishUndoAvailable, let previous = undoStack.popLast() else { return }
        finishTask?.cancel()
        state = previous
        state.finished = false
        actionLog.undo(team1Score: state.leftPoints, team2Score: state.rightPoints)
        showFinishedOverlay = false
        finishUndoAvailable = false
        didSaveFinishedRecord = false
        publish(manualEnd: false)
        undoToastToken = UUID()
    }

    private func exitEightBall() {
        if linkedSessionId != nil {
            linkService.exitScoreboardToHome()
        }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        guard !state.finished,
              state.leftPoints != 0 || state.rightPoints != 0
                || !undoStack.isEmpty else {
            resumeStore.clear()
            return
        }
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: "\(state.leftPoints) : \(state.rightPoints)",
            emoji: "🎱",
            payload: .eightBall(
                state: state,
                undoStates: undoStack,
                leftName: leftName,
                rightName: rightName
            ),
            actionLog: actionLog,
            link: linkService.resumeContext
        ))
    }

    private var hasEightBallProgress: Bool {
        state.leftPoints != 0 || state.rightPoints != 0 || !undoStack.isEmpty || state.finished
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
}

