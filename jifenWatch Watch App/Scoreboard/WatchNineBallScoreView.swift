import LinkCore
import RecordCore
import ScoreCore
import SwiftUI

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
    @State private var undoToastToken: UUID?

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
        let player = logicalPlayer(forScreenIndex: index)
        let scoreText = "\(playerPoints(at: player))"
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

            Text(displayName(at: player))
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
        .background(player < Self.playerColors.count ? Self.playerColors[player] : .gray)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressTapAfterLongPress else { return }
            eventPickerPlayer = player
        }
    }

    private func logicalPlayer(forScreenIndex index: Int) -> Int {
        guard state.playerCount == 2, state.sidesSwapped else { return index }
        return index == 0 ? 1 : 0
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
        let rightName = state.playerCount > 1
            ? displayName(at: 1)
            : WatchDefaultTeamNames.resolve(for: .nineBall).right
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
        if linkedSessionId != nil {
            linkService.startNextMatch(snapshot: .nineBall(state))
        } else {
            publish()
        }
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
            linkService.exitScoreboardToHome()
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

}

