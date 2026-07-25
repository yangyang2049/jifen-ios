import LinkCore
import ScoreCore
import SwiftUI

/// Compact dual-side board for eight-ball / snooker-style rack or frame scoring on Watch.
struct WatchEightBallScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let linkedSessionId: UUID?
    let leftName: String
    let rightName: String
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

    init(
        initialState: EightBallState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil,
        resumedUndoStates: [EightBallState] = [],
        resumedStartTime: Date? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve()
        self.linkedSessionId = linkedSessionId
        self.leftName = leftName ?? defaults.left
        self.rightName = rightName ?? defaults.right
        _state = State(initialValue: initialState ?? .initial())
        _undoStack = State(initialValue: resumedUndoStates)
        _matchStartTime = State(initialValue: resumedStartTime ?? Date())
    }

    private var scoringLocked: Bool { linkedSessionId != nil && linkService.isFollower }
    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    var body: some View {
        ZStack {
            dualBoard(
                leftLabel: "\(state.leftPoints)",
                rightLabel: "\(state.rightPoints)",
                onLeft: { addRack(.left) },
                onRight: { addRack(.right) }
            )
            if !showMenu && !showFinishedOverlay {
                Text("\(state.targetPoints)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
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
                        undo()
                        showMenu = false
                    },
                    onFinish: {
                        showMenu = false
                        confirmation = .finish
                    },
                    onReset: {
                        showMenu = false
                        confirmation = .reset
                    }
                )
            }
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreText: "\(state.leftPoints) : \(state.rightPoints)",
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
            state = remote
            undoStack.removeAll()
            if state.finished {
                showFinishedOverlay = true
                finishUndoAvailable = false
            }
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
            enabled: interactionsEnabled,
            onMenu: { showMenu = true },
            onUndo: undo,
            onExit: exitEightBall
        )
    }

    private func addRack(_ side: MatchSide) {
        guard !scoringLocked, !state.finished else { return }
        let result = EightBallReducer().reduce(state: state, intent: .addRack(side), at: nowMs())
        guard result.accepted else { return }
        undoStack.append(state)
        state = result.state
        if state.finished {
            finishMatch(manual: false)
        } else {
            publish(manualEnd: false)
        }
    }

    private func finishMatch(manual: Bool) {
        if manual, !state.finished {
            state.finished = true
        }
        publish(manualEnd: manual)
        beginEightBallFinish(manualEnd: manual)
    }

    private func publish(manualEnd: Bool) {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(.eightBall(state))
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
            actions: [],
            totalScoreChanges: max(1, state.leftPoints + state.rightPoints),
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
        ZStack {
            Text(text)
                .font(.system(size: isHorizontal ? 56 : 62, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            VStack(spacing: 2) {
                Text(name)
                    .lineLimit(2)
                if let handicap {
                    Text(handicap)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.76))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 4)
            .padding(.bottom, isHorizontal ? 18 : 12)
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
        publish(manualEnd: false)
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        resumeStore.clear()
        finishTask?.cancel()
        let result = EightBallReducer().reduce(state: state, intent: .reset, at: nowMs())
        guard result.accepted else { return }
        undoStack.removeAll()
        state = result.state
        didSaveFinishedRecord = false
        matchStartTime = Date()
        showFinishedOverlay = false
        finishUndoAvailable = false
        publish(manualEnd: false)
    }

    private var interactionsEnabled: Bool {
        !scoringLocked && !showMenu && confirmation == nil && !showFinishedOverlay
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
        guard state.handicapBeneficiary == side, state.handicapRacks > 0 else { return nil }
        return String.localizedStringWithFormat(
            NSLocalizedString("watch_eight_ball_handicap_format", value: "让局 +%d", comment: ""),
            state.handicapRacks
        )
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
        showFinishedOverlay = true
        finishUndoAvailable = !undoStack.isEmpty
        finishTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                finishUndoAvailable = false
                finalizeEightBall(manualEnd: manualEnd)
            }
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
                totalScoreChanges: max(1, state.leftPoints + state.rightPoints)
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
        showFinishedOverlay = false
        finishUndoAvailable = false
        didSaveFinishedRecord = false
        publish(manualEnd: false)
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
            link: linkService.resumeContext
        ))
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

    private static let playerColors: [Color] = [
        Color(hex: 0xE53935),
        Color(hex: 0x1E88E5),
        Color(hex: 0x43A047),
        Color(hex: 0x8E24AA)
    ]

    init(
        initialState: NineBallChaseState? = nil,
        linkedSessionId: UUID? = nil,
        resumedUndoStates: [NineBallChaseState] = [],
        resumedStartTime: Date? = nil
    ) {
        self.linkedSessionId = linkedSessionId
        _state = State(initialValue: initialState ?? .initial())
        _undoStack = State(initialValue: resumedUndoStates)
        _matchStartTime = State(initialValue: resumedStartTime ?? Date())
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
                        undo()
                        showMenu = false
                    },
                    onFinish: {
                        showMenu = false
                        confirmation = .finish
                    },
                    onReset: {
                        showMenu = false
                        confirmation = .reset
                    }
                )
            }
            if let eventPickerPlayer {
                nineBallEventPicker(for: eventPickerPlayer)
            }
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreText: compactNineBallScore,
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
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let remote = update.snapshot.nineBallState else { return }
            state = remote
            undoStack.removeAll()
            if state.finished {
                showFinishedOverlay = true
                finishUndoAvailable = false
            }
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
            enabled: interactionsEnabled,
            onMenu: { showMenu = true },
            onUndo: undo,
            onExit: exitNineBall
        )
    }

    @ViewBuilder
    private var playerLayout: some View {
        switch state.playerCount {
        case 3:
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    playerZone(index)
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
        let scoreFont: CGFloat = state.playerCount == 4 ? 34 : (state.playerCount == 3 ? 40 : 56)
        let nameFont: CGFloat = state.playerCount > 2 ? 11 : 13
        return VStack(spacing: state.playerCount > 2 ? 4 : 6) {
            Text(displayName(at: index))
                .font(.system(size: nameFont, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(playerPoints(at: index))")
                .font(.system(size: scoreFont, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .offset(y: state.playerCount == 4 && index == 1 ? 18 : 0)
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
            VStack(spacing: WatchLayout.isCompactScreen ? 5 : 7) {
                Text(displayName(at: player))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: WatchLayout.isCompactScreen ? 5 : 7
                ) {
                    ForEach(NineBallChaseKind.allCases, id: \.rawValue) { kind in
                        Button {
                            eventPickerPlayer = nil
                            apply(.chaseEvent(player: player, kind: kind))
                        } label: {
                            VStack(spacing: 1) {
                                Text(nineBallEventTitle(kind))
                                    .font(.system(size: WatchLayout.isCompactScreen ? 11 : 12, weight: .semibold))
                                Text(nineBallEventPointText(kind, playerCount: state.playerCount))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity, minHeight: WatchLayout.isCompactScreen ? 30 : 36)
                        }
                        .buttonStyle(.plain)
                        .background(kind == .foul ? WatchTheme.dangerRed : WatchTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .padding(WatchLayout.isCompactScreen ? 8 : 12)
            .background(WatchTheme.overlayCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 12)
        }
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
        let result = NineBallChaseReducer().reduce(state: state, intent: intent, at: nowMs())
        guard result.accepted else { return }
        undoStack.append(state)
        state = result.state
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
        state.finished = true
        publish()
        beginNineBallFinish(manualEnd: true)
    }

    private func publish() {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(.nineBall(state))
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
            actions: [],
            totalScoreChanges: max(1, total),
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
        publish()
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        resumeStore.clear()
        finishTask?.cancel()
        let result = NineBallChaseReducer().reduce(state: state, intent: .resetScores, at: nowMs())
        guard result.accepted else { return }
        undoStack.removeAll()
        state = result.state
        didSaveFinishedRecord = false
        matchStartTime = Date()
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
        !scoringLocked && !showMenu && eventPickerPlayer == nil && confirmation == nil
            && !showFinishedOverlay
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
        showFinishedOverlay = true
        finishUndoAvailable = !undoStack.isEmpty
        finishTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                finishUndoAvailable = false
                finalizeNineBall(manualEnd: manualEnd)
            }
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
                totalScoreChanges: max(1, (0..<state.playerCount).reduce(0) { $0 + abs(playerPoints(at: $1)) })
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
        showFinishedOverlay = false
        finishUndoAvailable = false
        didSaveFinishedRecord = false
        publish()
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
            link: linkService.resumeContext
        ))
    }
}

struct WatchSnookerScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let linkedSessionId: UUID?
    let leftName: String
    let rightName: String
    @State private var state: SnookerState
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var undoStack: [SnookerState] = []
    @State private var scoringSide: MatchSide?
    @State private var showFrameSettlement = false
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false

    init(
        initialState: SnookerState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil,
        resumedUndoStates: [SnookerState] = [],
        resumedStartTime: Date? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve()
        self.linkedSessionId = linkedSessionId
        self.leftName = leftName ?? defaults.left
        self.rightName = rightName ?? defaults.right
        _state = State(initialValue: initialState ?? SnookerState.initial())
        _undoStack = State(initialValue: resumedUndoStates)
        _matchStartTime = State(initialValue: resumedStartTime ?? Date())
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
            if !showMenu && scoringSide == nil && !showFinishedOverlay {
                snookerStatusBadge
            }
            if showMenu {
                WatchScoreboardMenuOverlay(
                    onDismiss: { showMenu = false },
                    onUndo: {
                        undo()
                        showMenu = false
                    },
                    onFinish: {
                        showMenu = false
                        confirmation = .finish
                    },
                    onReset: {
                        showMenu = false
                        confirmation = .reset
                    }
                )
            }
            if let scoringSide {
                snookerScoringPanel(for: scoringSide)
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
                    scoreText: "\(state.leftFrames) : \(state.rightFrames)",
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
            state = remote
            undoStack.removeAll()
            if state.finished {
                showFinishedOverlay = true
                finishUndoAvailable = false
            }
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
            enabled: interactionsEnabled,
            onMenu: { showMenu = true },
            onUndo: undo,
            onExit: exitSnooker
        )
    }

    private func scoreHalf(_ side: MatchSide) -> some View {
        let isLeft = side == .left
        let score = isLeft ? state.leftScore : state.rightScore
        let frames = isLeft ? state.leftFrames : state.rightFrames
        let color = isLeft ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5)
        return ZStack {
            Text("\(score)")
                .font(.system(size: isHorizontal ? 56 : 62, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(String(
                format: NSLocalizedString("watch_snooker_frames_format", value: "局 %d", comment: ""),
                frames
            ))
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, isHorizontal ? 22 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressTapAfterLongPress else { return }
            scoringSide = side
        }
    }

    private var snookerStatusBadge: some View {
        VStack(spacing: 2) {
            Text(state.striker == .left ? leftName : rightName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text(String.localizedStringWithFormat(
                NSLocalizedString("watch_snooker_break_format", value: "单杆 %d", comment: ""),
                state.striker == .left ? state.leftBreak : state.rightBreak
            ))
            .font(.system(size: 10, weight: .medium, design: .rounded))
            Text(String.localizedStringWithFormat(
                NSLocalizedString("watch_snooker_reds_format", value: "红球 %d", comment: ""),
                state.redBallsRemaining
            ))
            .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func snookerScoringPanel(for side: MatchSide) -> some View {
        ZStack {
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
                            Button {
                                apply(.potBallAsSide(side: side, points: ball.rawValue))
                                scoringSide = nil
                            } label: {
                                VStack(spacing: 1) {
                                    Circle()
                                        .frame(width: 13, height: 13)
                                        .foregroundStyle(snookerBallColor(ball))
                                    Text("\(ball.rawValue)")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .buttonStyle(.plain)
                            .background(WatchTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                    HStack(spacing: 5) {
                        ForEach(4...7, id: \.self) { points in
                            Button("\(NSLocalizedString("watch_snooker_foul", value: "犯规", comment: "")) \(points)") {
                                apply(.foulFromSide(side: side, pointsToOpponent: points, switchTurn: true))
                                scoringSide = nil
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .buttonStyle(.bordered)
                            .tint(WatchTheme.dangerRed)
                        }
                    }
                    HStack(spacing: 6) {
                        Button(NSLocalizedString("watch_snooker_miss", value: "未进", comment: "")) {
                            apply(.missFromPanel(side))
                            scoringSide = nil
                        }
                        Button(NSLocalizedString("watch_snooker_handover", value: "交接", comment: "")) {
                            apply(.handoverFromPanel(side))
                            scoringSide = nil
                        }
                        Button(NSLocalizedString("watch_snooker_settle_frame", value: "结算本局", comment: "")) {
                            scoringSide = nil
                            showFrameSettlement = true
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.bordered)
                }
                .padding(8)
            }
        }
    }

    private var snookerFrameSettlementPanel: some View {
        ZStack {
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
                Button(rightName) {
                    showFrameSettlement = false
                    apply(.settleFrame(winner: .right))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x1E88E5))
                Button(NSLocalizedString("cancel", value: "取消", comment: "")) {
                    showFrameSettlement = false
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
        }
    }

    private var snookerNextFramePanel: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(spacing: 9) {
                Text(NSLocalizedString("watch_snooker_frame_finished", value: "本局结束", comment: ""))
                    .font(.headline)
                Text("\(state.leftFrames) : \(state.rightFrames)")
                    .font(.title3.monospacedDigit().weight(.bold))
                Button(NSLocalizedString("watch_snooker_next_frame", value: "下一局", comment: "")) {
                    apply(.confirmNextFrame)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.successGreen)
                Button(NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: "")) {
                    confirmation = .finish
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
        }
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

    private func apply(_ intent: SnookerIntent) {
        guard !scoringLocked, !showFinishedOverlay else { return }
        let result = SnookerReducer().reduce(state: state, intent: intent, at: nowMs())
        guard result.accepted else { return }
        undoStack.append(state)
        state = result.state
        publish()
        if state.finished {
            beginSnookerFinish(manualEnd: false)
        }
    }

    private func finishMatch() {
        let result = SnookerReducer().reduce(state: state, intent: .finishMatch, at: nowMs())
        state = result.state
        publish()
        if state.finished {
            beginSnookerFinish(manualEnd: true)
        }
    }

    private func publish() {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(.snooker(state))
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
            actions: [],
            totalScoreChanges: max(1, state.leftScore + state.rightScore),
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
        publish()
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        resumeStore.clear()
        finishTask?.cancel()
        undoStack.removeAll()
        state = .initial(striker: state.firstBreaker, maxFrames: state.maxFrames)
        didSaveFinishedRecord = false
        matchStartTime = Date()
        scoringSide = nil
        showFrameSettlement = false
        showFinishedOverlay = false
        finishUndoAvailable = false
        publish()
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    private var interactionsEnabled: Bool {
        !scoringLocked && !showMenu && scoringSide == nil && !showFrameSettlement
            && !state.frameCompletePending && confirmation == nil && !showFinishedOverlay
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
        scoringSide = nil
        showFrameSettlement = false
        showFinishedOverlay = true
        finishUndoAvailable = !undoStack.isEmpty
        finishTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                finishUndoAvailable = false
                finalizeSnooker(manualEnd: manualEnd)
            }
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
                totalScoreChanges: max(1, state.leftScore + state.rightScore)
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
        showFinishedOverlay = false
        finishUndoAvailable = false
        didSaveFinishedRecord = false
        publish()
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
            link: linkService.resumeContext
        ))
    }
}
