import LinkCore
import PersistenceCore
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
    @State private var archiveSessionId = UUID()
    @State private var undoToastToken: UUID?
    private let archiveRepository = SessionArchiveRepository()

    init(
        initialState: EightBallState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil,
        resumedUndoStates: [EightBallState] = [],
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve()
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
                leftLabel: "\(WatchEightBallScorePresentation.displayedRacks(state: state, side: .left))",
                rightLabel: "\(WatchEightBallScorePresentation.displayedRacks(state: state, side: .right))",
                onLeft: { addRack(.left) },
                onRight: { addRack(.right) }
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
            if hasEightBallProgress {
                persistArchiveSnapshot()
            }
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
            persistArchiveSnapshot()
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
                        name: leftName,
                        handicap: handicapText(for: .left),
                        color: Color(hex: 0xE53935),
                        action: onLeft
                    )
                    scoreHalf(
                        rightLabel,
                        name: rightName,
                        handicap: handicapText(for: .right),
                        color: Color(hex: 0x1E88E5),
                        action: onRight
                    )
                }
            } else {
                VStack(spacing: 0) {
                    scoreHalf(
                        leftLabel,
                        name: leftName,
                        handicap: handicapText(for: .left),
                        color: Color(hex: 0xE53935),
                        action: onLeft
                    )
                    scoreHalf(
                        rightLabel,
                        name: rightName,
                        handicap: handicapText(for: .right),
                        color: Color(hex: 0x1E88E5),
                        action: onRight
                    )
                }
            }
        }
        .ignoresSafeArea()
        .disabled(!interactionsEnabled)
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
        publish(manualEnd: false)
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
            if state.finished {
                linkService.leaveSession()
            } else {
                linkService.exitScoreboardToHome()
            }
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

    private func persistArchiveSnapshot() {
        WatchSessionArchiveSupport.persist(
            repository: archiveRepository,
            sessionId: archiveSessionId,
            gameType: .eightBall,
            state: state,
            eventType: EightBallEvent.self,
            finished: state.finished,
            participants: [
                .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
                .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
            ],
            startedAt: matchStartTime
        )
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
}

struct WatchNineBallScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let linkedSessionId: UUID?
    @State private var state: NineBallChaseState
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var undoStack: [NineBallChaseState] = []
    @State private var eventPickerPlayer: Int?
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
    @State private var actionLog: WatchScoreActionLog
    @State private var archiveSessionId = UUID()
    @State private var undoToastToken: UUID?
    private let archiveRepository = SessionArchiveRepository()

    private static let playerColors: [Color] = [
        Color(hex: 0xE53935),
        Color(hex: 0x1E88E5),
        Color(hex: 0x43A047),
        Color(hex: 0x8E24AA)
    ]

    private static let eventPickerOrder: [NineBallChaseKind] = [
        .normalWin, .foul,
        .bigGold, .smallGold,
        .goldenNine, .ballInHand
    ]

    init(
        initialState: NineBallChaseState? = nil,
        linkedSessionId: UUID? = nil,
        resumedUndoStates: [NineBallChaseState] = [],
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.linkedSessionId = linkedSessionId
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
            playerLayout
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
            if let eventPickerPlayer {
                nineBallEventPicker(for: eventPickerPlayer)
            }
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreItems: (0..<state.playerCount).map {
                        WatchFinishedScoreItem(name: displayName(at: $0), score: String(playerPoints(at: $0)))
                    },
                    winnerText: nineBallWinnerText,
                    undoAvailable: finishUndoAvailable,
                    onUndo: undoFinishedNineBall,
                    onPlayAgain: restartMatch,
                    onExit: {
                        finalizeNineBall()
                        exitNineBall()
                    }
                )
            }
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirmNineBall(confirmation) }
                )
            }
        }
        .onAppear {
            if state.playerCount < 4 {
                scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            }
            if hasNineBallProgress {
                persistArchiveSnapshot()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            guard state.playerCount < 4 else { return }
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let remote = update.snapshot.nineBallState else { return }
            applyAuthoritativeNineBall(remote, detailedActions: update.detailedActions)
        }
        .onChange(of: linkService.pendingReclaimAcceptance) { _, pending in
            guard let linkedSessionId, let pending, pending.sessionId == linkedSessionId,
                  let remote = pending.snapshot.nineBallState else { return }
            applyAuthoritativeNineBall(remote, detailedActions: pending.detailedActions)
            linkService.completeReclaimAcceptance(messageId: pending.messageId)
        }
        .onChange(of: state) { _, _ in
            persistResumeSession()
            persistArchiveSnapshot()
        }
        .onDisappear {
            finishTask?.cancel()
            if state.finished { finalizeNineBall() }
            persistResumeSession()
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: menuGesturesEnabled,
            onMenu: { showMenu = true },
            onUndo: undo,
            onExit: exitNineBall
        )
        .watchUndoToast(token: $undoToastToken)
    }

    @ViewBuilder
    private var playerLayout: some View {
        switch state.playerCount {
        case 3:
            Group {
                if isHorizontal {
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            playerZone(index)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            playerZone(index)
                        }
                    }
                }
            }
            .ignoresSafeArea()
        case 4:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    playerZone(0)
                    playerZone(1)
                }
                HStack(spacing: 0) {
                    playerZone(2)
                    playerZone(3)
                }
            }
            .ignoresSafeArea()
        default:
            Group {
                if isHorizontal {
                    HStack(spacing: 0) {
                        playerZone(0)
                        playerZone(1)
                    }
                } else {
                    VStack(spacing: 0) {
                        playerZone(0)
                        playerZone(1)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private func playerZone(_ index: Int) -> some View {
        let scoreText = "\(playerPoints(at: index))"
        let baseScoreFont: CGFloat = state.playerCount == 4 ? 34 : (state.playerCount == 3 ? 40 : 56)
        let minimumScoreFont: CGFloat = state.playerCount == 4 ? 24 : (state.playerCount == 3 ? 28 : 38)
        let scoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: baseScoreFont,
            scoreText: scoreText,
            minimumSize: minimumScoreFont
        )
        let nameFont: CGFloat = state.playerCount > 2 ? 11 : 13
        return ZStack {
            Text(scoreText)
                .font(WatchScoreTypography.primaryScore(size: scoreFont))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(displayName(at: index))
                .font(.system(size: nameFont, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, state.playerCount > 2 ? 4 : 8)
                .padding(.top, state.playerCount == 4 ? 8 : (isHorizontal ? 28 : 8))
                .offset(y: WatchLayout.scoreboardNameVerticalOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(index < Self.playerColors.count ? Self.playerColors[index] : .gray)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressTapAfterLongPress else { return }
            eventPickerPlayer = index
        }
    }

    private func nineBallEventPicker(for player: Int) -> some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { eventPickerPlayer = nil }
            VStack(spacing: WatchLayout.isCompactScreen ? 3 : 7) {
                Text(displayName(at: player))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .padding(.bottom, 8)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: WatchLayout.isCompactScreen ? 5 : 7
                ) {
                    ForEach(Self.eventPickerOrder, id: \.rawValue) { kind in
                        Button {
                            eventPickerPlayer = nil
                            apply(.chaseEvent(player: player, kind: kind))
                        } label: {
                            VStack(spacing: 1) {
                                Text(nineBallEventTitle(kind))
                                    .font(.system(size: WatchLayout.isCompactScreen ? 11 : 12, weight: .semibold))
                                Text(nineBallEventPointText(kind, playerCount: state.playerCount))
                                    .font(WatchScoreTypography.secondaryScore(size: 10))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity, minHeight: WatchLayout.isCompactScreen ? 36 : 42)
                        }
                        .buttonStyle(.plain)
                        .background(kind == .foul ? WatchTheme.dangerRed : WatchTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                WatchMenuCloseButton { eventPickerPlayer = nil }
            }
            .padding(.horizontal, WatchLayout.isCompactScreen ? 8 : 12)
            .padding(.vertical, WatchLayout.isCompactScreen ? 4 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchTheme.overlayCard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func displayName(at index: Int) -> String {
        let fallback = String.localizedStringWithFormat(
            NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: ""),
            index + 1
        )
        return state.resolvedName(at: index, fallback: fallback)
    }

    private func apply(_ intent: NineBallChaseIntent) {
        guard !scoringLocked, !state.finished else { return }
        let timestamp = Date()
        actionLog.beginUndoableMutation()
        let result = NineBallChaseReducer().reduce(state: state, intent: intent, at: Int64(timestamp.timeIntervalSince1970 * 1_000))
        guard result.accepted else {
            actionLog.rejectUndoableMutation()
            return
        }
        undoStack.append(state)
        state = result.state
        if case .resetScores = intent {
            actionLog.reset(at: timestamp)
        } else {
            actionLog.append(contentsOf: WatchScoreActionProjector.nineBall(
                events: result.events, state: state, timestamp: timestamp
            ))
        }
        publish()
        if state.finished {
            beginNineBallFinish(manualEnd: false)
        }
    }

    private func finishMatch() {
        guard !state.finished else {
            beginNineBallFinish(manualEnd: true)
            return
        }
        undoStack.append(state)
        actionLog.beginUndoableMutation()
        state.finished = true
        let scores = Array(state.playerPoints.prefix(state.playerCount))
        let maximum = scores.max()
        let winningIndex = maximum.flatMap { value in
            scores.filter { $0 == value }.count == 1 ? scores.firstIndex(of: value) : nil
        }
        actionLog.appendGameEndIfNeeded(
            team1Score: playerPoints(at: 0),
            team2Score: playerPoints(at: 1),
            winner: winningIndex.flatMap { index in
                switch index {
                case 0: .team1
                case 1: .team2
                case 2: .team3
                case 3: .team4
                default: nil
                }
            }
        )
        publish()
        beginNineBallFinish(manualEnd: true)
    }

    private func publish() {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(.nineBall(state), detailedActions: actionLog.detailedActions)
    }

    private func winnerSide() -> MatchSide? {
        guard state.playerCount <= 2 else { return nil }
        let left = playerPoints(at: 0)
        let right = playerPoints(at: 1)
        if left == right { return nil }
        return left > right ? .left : .right
    }

    private func saveLocalRecordIfNeeded() {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return }
        let total = (0..<state.playerCount).reduce(0) { $0 + playerPoints(at: $1) }
        guard state.finished || total > 0 else { return }
        didSaveFinishedRecord = true
        let end = Date()
        let leftName = displayName(at: 0)
        let rightName = state.playerCount > 1 ? displayName(at: 1) : WatchDefaultTeamNames.resolve().right
        let leftScore = playerPoints(at: 0)
        let rightScore = state.playerCount > 1 ? playerPoints(at: 1) : 0
        let winnerName: String? = {
            if state.playerCount > 2 {
                let best = (0..<state.playerCount).max(by: { playerPoints(at: $0) < playerPoints(at: $1) })
                return best.map { displayName(at: $0) }
            }
            if leftScore == rightScore { return nil }
            return leftScore > rightScore ? leftName : rightName
        }()
        let record = WatchScoreboardRecord(
            id: "w_\(UUID().uuidString)",
            gameType: .nineBall,
            startTime: matchStartTime,
            endTime: end,
            duration: end.timeIntervalSince(matchStartTime),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: leftScore,
            team2FinalScore: rightScore,
            team1SetScore: leftScore,
            team2SetScore: rightScore,
            winner: winnerName,
            actions: actionLog.actions,
            totalScoreChanges: actionLog.scoreChangeCount,
            participants: (0..<state.playerCount).map {
                WatchRecordParticipant(name: displayName(at: $0), score: playerPoints(at: $0))
            },
            projectConfiguration: ["playerCount": String(state.playerCount)]
        )
        WatchRecordManager.shared.saveRecord(record)
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func undo() {
        guard !scoringLocked, let previous = undoStack.popLast() else { return }
        state = previous
        actionLog.undo(team1Score: playerPoints(at: 0), team2Score: playerPoints(at: 1))
        publish()
        undoToastToken = UUID()
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        resumeStore.clear()
        finishTask?.cancel()
        let result = NineBallChaseReducer().reduce(state: state, intent: .resetScores, at: nowMs())
        guard result.accepted else { return }
        undoStack.removeAll()
        state = result.state
        let restartedAt = Date()
        actionLog.reset(at: restartedAt)
        didSaveFinishedRecord = false
        matchStartTime = restartedAt
        showFinishedOverlay = false
        finishUndoAvailable = false
        publish()
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    private func playerPoints(at index: Int) -> Int {
        guard state.playerPoints.indices.contains(index) else { return 0 }
        return state.playerPoints[index]
    }

    private var interactionsEnabled: Bool {
        !scoringLocked && !state.finished && !showMenu && eventPickerPlayer == nil && confirmation == nil
            && !showFinishedOverlay
    }

    private var menuGesturesEnabled: Bool {
        !state.finished && !showMenu && eventPickerPlayer == nil && confirmation == nil
            && !showFinishedOverlay
    }

    private func applyAuthoritativeNineBall(
        _ remote: NineBallChaseState,
        detailedActions: [DetailedScoreAction]
    ) {
        actionLog.merge(detailedActions: detailedActions)
        state = remote
        undoStack.removeAll()
        eventPickerPlayer = nil
        if state.finished {
            beginNineBallRemoteFinishPresentation()
        } else {
            finishTask?.cancel()
            showFinishedOverlay = false
            finishUndoAvailable = false
            didSaveFinishedRecord = false
        }
    }

    private var compactNineBallScore: String {
        (0..<state.playerCount).map { "\(playerPoints(at: $0))" }.joined(separator: " · ")
    }

    private var nineBallWinnerText: String? {
        let scores = (0..<state.playerCount).map { playerPoints(at: $0) }
        guard let maximum = scores.max(),
              scores.filter({ $0 == maximum }).count == 1,
              let index = scores.firstIndex(of: maximum) else { return nil }
        return String.localizedStringWithFormat(
            NSLocalizedString("watch_winner_format", value: "%@ 获胜", comment: ""),
            displayName(at: index)
        )
    }

    private func nineBallEventTitle(_ kind: NineBallChaseKind) -> String {
        switch kind {
        case .bigGold: NSLocalizedString("nine_ball_big_gold", value: "大金", comment: "")
        case .smallGold: NSLocalizedString("nine_ball_small_gold", value: "小金", comment: "")
        case .goldenNine: NSLocalizedString("nine_ball_golden_nine", value: "金九", comment: "")
        case .normalWin: NSLocalizedString("nine_ball_normal_win", value: "普通胜", comment: "")
        case .ballInHand: NSLocalizedString("nine_ball_ball_in_hand", value: "自由球", comment: "")
        case .foul: NSLocalizedString("nine_ball_foul", value: "犯规", comment: "")
        }
    }

    private func nineBallEventPointText(_ kind: NineBallChaseKind, playerCount: Int) -> String {
        let value: Int
        switch kind {
        case .bigGold: value = state.config.bigGold
        case .smallGold: value = state.config.smallGold
        case .goldenNine: value = state.config.goldenNine
        case .normalWin: value = state.config.normalWin
        case .ballInHand: value = state.config.ballInHand
        case .foul: value = state.config.foul
        }
        if kind == .foul, playerCount > 2 { return "-\(value)" }
        return "+\(value)"
    }

    private func confirmNineBall(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish: finishMatch()
        case .reset: restartMatch()
        }
    }

    private func beginNineBallFinish(manualEnd: Bool) {
        finishTask?.cancel()
        showMenu = false
        eventPickerPlayer = nil
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
            finalizeNineBall(manualEnd: manualEnd)
        }
    }

    private func beginNineBallRemoteFinishPresentation() {
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            showFinishedOverlay = true
        }
    }

    private func finalizeNineBall(manualEnd: Bool = false) {
        guard state.finished, !didSaveFinishedRecord else { return }
        resumeStore.clear()
        if linkedSessionId != nil, linkService.isController {
            linkService.publishMatchFinished(
                snapshot: .nineBall(state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: winnerSide(),
                manualEnd: manualEnd,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: actionLog.scoreChangeCount,
                detailedActions: actionLog.detailedActions,
                participantNames: (0..<state.playerCount).map { displayName(at: $0) }
            )
            didSaveFinishedRecord = true
        } else {
            saveLocalRecordIfNeeded()
        }
    }

    private func undoFinishedNineBall() {
        guard finishUndoAvailable, let previous = undoStack.popLast() else { return }
        finishTask?.cancel()
        state = previous
        state.finished = false
        actionLog.undo(team1Score: playerPoints(at: 0), team2Score: playerPoints(at: 1))
        showFinishedOverlay = false
        finishUndoAvailable = false
        didSaveFinishedRecord = false
        publish()
        undoToastToken = UUID()
    }

    private func exitNineBall() {
        if linkedSessionId != nil {
            if state.finished {
                linkService.leaveSession()
            } else {
                linkService.exitScoreboardToHome()
            }
        }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        let scores = Array(state.playerPoints.prefix(state.playerCount))
        guard !state.finished,
              scores.contains(where: { $0 != 0 }) || !undoStack.isEmpty else {
            resumeStore.clear()
            return
        }
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: compactNineBallScore,
            emoji: "🎱",
            payload: .nineBall(
                state: state,
                undoStates: undoStack
            ),
            actionLog: actionLog,
            link: linkService.resumeContext
        ))
    }

    private var hasNineBallProgress: Bool {
        Array(state.playerPoints.prefix(state.playerCount)).contains(where: { $0 != 0 })
            || !undoStack.isEmpty || state.finished
    }

    private func persistArchiveSnapshot() {
        WatchSessionArchiveSupport.persist(
            repository: archiveRepository,
            sessionId: archiveSessionId,
            gameType: .nineBall,
            state: state,
            eventType: NineBallChaseEvent.self,
            finished: state.finished,
            participants: (0..<state.playerCount).map { index in
                .init(id: "player_\(index)", name: displayName(at: index), role: "player")
            },
            startedAt: matchStartTime
        )
    }
}

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
    @State private var archiveSessionId = UUID()
    @State private var undoToastToken: UUID?
    private let archiveRepository = SessionArchiveRepository()

    init(
        initialState: SnookerState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil,
        resumedUndoStates: [SnookerState] = [],
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve()
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
            if hasSnookerProgress {
                persistArchiveSnapshot()
            }
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
            persistArchiveSnapshot()
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

    private func scoreHalf(_ side: MatchSide) -> some View {
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
            snookerServerIndicator(for: side)
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

    private func snookerServerIndicator(for side: MatchSide) -> some View {
        let isLeft = side == .left
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
            .opacity(state.striker == side ? 1 : 0)
            .allowsHitTesting(false)
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
        publish()
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
            if state.finished {
                linkService.leaveSession()
            } else {
                linkService.exitScoreboardToHome()
            }
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

    private func persistArchiveSnapshot() {
        WatchSessionArchiveSupport.persist(
            repository: archiveRepository,
            sessionId: archiveSessionId,
            gameType: .snooker,
            state: state,
            eventType: SnookerEvent.self,
            finished: state.finished,
            participants: [
                .init(id: TeamID.team0.rawValue, name: leftName, role: "player"),
                .init(id: TeamID.team1.rawValue, name: rightName, role: "player")
            ],
            startedAt: matchStartTime
        )
    }
}
