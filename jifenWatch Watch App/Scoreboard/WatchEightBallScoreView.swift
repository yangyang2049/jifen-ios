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
    @State private var lastAppliedRemoteRevision: UInt64?
    @State private var lastAppliedRemoteGeneration: UInt64?

    @State private var showRecordSaveFailure = false
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
    private var showsTargetBadge: Bool { !showMenu && !showFinishedOverlay }
    private static let targetBadgeHeight: CGFloat = 24
    private static let targetClearance: CGFloat = targetBadgeHeight / 2 + 6

    var body: some View {
        ZStack {
            dualBoard(
                leftLabel: "\(eightBallPoints(onScreen: .left))",
                rightLabel: "\(eightBallPoints(onScreen: .right))",
                onLeft: { addRack(eightBallLogicalSide(onScreen: .left)) },
                onRight: { addRack(eightBallLogicalSide(onScreen: .right)) }
            )
            if showsTargetBadge {
                GeometryReader { proxy in
                    targetBadge.position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
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
                        WatchFinishedScoreItem(name: leftName, score: state.leftPoints),
                        WatchFinishedScoreItem(name: rightName, score: state.rightPoints)
                    ],
                    undoAvailable: finishUndoAvailable,
                    canPlayAgain: !scoringLocked,
                    onUndo: undoFinishedEightBall,
                    onPlayAgain: restartMatch,
                    onExit: {
                        guard finalizeEightBall() else { return }
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
        .watchFinishSaveFailure(isPresented: $showRecordSaveFailure) { finalizeEightBall() }
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot, initial: true) { previous, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  update.matchGeneration == linkService.activeHandle?.matchGeneration,
                  let remote = update.snapshot.eightBallState else { return }
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
            applyAuthoritativeEightBall(remote)
        }
        .onChange(of: linkService.pendingReclaimAcceptance) { _, pending in
            guard let linkedSessionId, let pending, pending.sessionId == linkedSessionId,
                  let remote = pending.snapshot.eightBallState else { return }
            actionLog.merge(detailedActions: pending.detailedActions)
            applyAuthoritativeEightBall(remote)
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

    private var targetBadge: some View {
        Text("\(state.targetPoints)")
            .font(WatchScoreTypography.secondaryScore(size: 17))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minWidth: Self.targetBadgeHeight)
            .frame(height: Self.targetBadgeHeight)
            .background(WatchTheme.panelScrim, in: Capsule())
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
        actionLog.append(contentsOf: ScoreActionProjector.eightBall(
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
        guard linkedSessionId != nil, linkService.canEditLinkedMatch else { return }
        linkService.publishSnapshot(
            .eightBall(state),
            detailedActions: actionLog.detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private func saveLocalRecordIfNeeded() -> Bool {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return true }
        guard state.finished || state.leftPoints + state.rightPoints > 0 else { return true }
        let end = Date()
        guard let record = WatchScoreboardRecord(
            localSnapshot: .eightBall(state), gameType: .eightBall,
            id: "w_\(UUID().uuidString)", startTime: matchStartTime, endTime: end,
            participantNames: [leftName, rightName],
            detailedActions: actionLog.detailedActions, totalScoreChanges: actionLog.scoreChangeCount
        ) else { return false }
        return resumeStore.saveFinishedRecord(record)
    }

    @ViewBuilder
    private func dualBoard(
        leftLabel: String,
        rightLabel: String,
        onLeft: @escaping () -> Void,
        onRight: @escaping () -> Void
    ) -> some View {
        let left = scoreHalf(.left, text: leftLabel, action: onLeft)
        let right = scoreHalf(.right, text: rightLabel, action: onRight)

        Group {
            if isHorizontal {
                HStack(spacing: 0) {
                    left
                    right
                }
            } else {
                VStack(spacing: 0) {
                    left
                    right
                }
            }
        }
        .ignoresSafeArea()
        .disabled(!interactionsEnabled)
    }

    private func eightBallLogicalSide(onScreen side: MatchSide) -> MatchSide {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped).engineSide(onScreen: side)
    }

    private func eightBallPoints(onScreen side: MatchSide) -> Int {
        WatchEightBallScorePresentation.displayedRacks(
            state: state,
            side: eightBallLogicalSide(onScreen: side)
        )
    }

    private func scoreHalf(
        _ screenSide: MatchSide,
        text: String,
        action: @escaping () -> Void
    ) -> some View {
        let logicalSide = eightBallLogicalSide(onScreen: screenSide)
        let name = logicalSide == .left ? leftName : rightName
        let handicap = handicapText(for: logicalSide)
        let color = logicalSide == .left ? WatchTheme.teamRed : WatchTheme.teamBlue
        let scoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 56 : 62,
            scoreText: text,
            minimumSize: isHorizontal ? 40 : 44
        )
        let scoreLabel = Text(text)
            .font(WatchScoreTypography.primaryScore(size: scoreFont))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        let nameLabel = Text(name)
            .font(.system(size: WatchScoreTypography.teamNameSize, weight: .semibold))
            .lineLimit(isHorizontal ? 2 : 1)
            .minimumScaleFactor(isHorizontal ? 0.65 : 1)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.9))

        return ZStack {
            // Both vertical names clear the target badge by the same distance.
            WatchScoreboardFace(
                isHorizontal: isHorizontal,
                topInset: Self.targetClearance,
                bottomInset: Self.targetClearance
            ) {
                nameLabel.padding(.horizontal, 8)
            } score: {
                if !isHorizontal, let handicap {
                    HStack(spacing: 4) {
                        Color.clear.frame(width: 34, height: 1)
                        scoreLabel.frame(maxWidth: .infinity)
                        handicapLabel(handicap).frame(width: 34)
                    }
                    .padding(.horizontal, 8)
                } else {
                    scoreLabel
                }
            }

            if isHorizontal, let handicap {
                handicapLabel(handicap)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
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

    private func handicapLabel(_ handicap: String) -> some View {
        Text(handicap)
            .font(WatchScoreTypography.secondaryScore(size: isHorizontal ? 20 : 17))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.65))
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
        guard !scoringLocked, finalizeEightBall() else { return }
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

    private func applyAuthoritativeEightBall(_ remote: EightBallState) {
        actionLog.clearUndoHistory()
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

    @discardableResult
    private func finalizeEightBall(manualEnd: Bool = false) -> Bool {
        guard state.finished, !didSaveFinishedRecord, !scoringLocked else { return true }
        finishUndoAvailable = false
        let saved: Bool
        if linkedSessionId != nil {
            saved = linkService.publishMatchFinished(
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
        if let linkedSessionId { linkService.exitScoreboard(sessionId: linkedSessionId) }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        if state.finished {
            if didSaveFinishedRecord { resumeStore.clear() }
            return
        }
        guard state.leftPoints != 0 || state.rightPoints != 0
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

