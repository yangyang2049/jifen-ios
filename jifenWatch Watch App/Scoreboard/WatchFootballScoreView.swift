import Combine
import LinkCore
import RecordCore
import ScoreCore
import SwiftUI

/// Watch-local football board.
///
/// Layout follows the HarmonyOS watch board: a full-bleed two-side scoreboard
/// with the match clock at the bottom, so the top stays free for team names and
/// nothing sits behind a black bar. 11-a-side shows a compact clock pill;
/// 5-a-side waits for a centre kick-off button and then swaps to a full-width
/// clock panel. Scoring is one goal per tap; long-press opens the menu.
struct WatchFootballScoreView: View {
    private enum Confirmation {
        case finish
        case reset
        case advanceStage
    }

    /// Mirrors Harmony's single dynamic second-row menu action.
    private enum MenuAction {
        case nextHalf
        case pauseClock
        case extraTime
        case injury
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(WatchResumeSessionStore.self) private var resumeStore
    @Environment(WatchLinkService.self) private var linkService

    static let bottomPanelHeight: CGFloat = 46
    private static let amber = Color(hex: 0xFFB340)

    let isFiveAside: Bool
    let halfLengthSeconds: Int
    /// Non-nil when this board follows a phone-started linked session.
    let linkedSessionId: UUID?

    @State private var leftName: String
    @State private var rightName: String
    @State private var leftScore: Int
    @State private var rightScore: Int
    @State private var clockSession: FootballMatchClockSession
    @State private var kickedOff: Bool
    @State private var kickOffPulseScale: CGFloat = 1
    @State private var scoreboardLayout = "horizontal"
    @State private var showMenu = false
    @State private var showStoppagePanel = false
    @State private var showPostRegulationPanel = false
    @State private var confirmation: Confirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var isFinished = false
    @State private var didSaveRecord = false
    @State private var suppressTapAfterLongPress = false
    @State private var undoStack: [WatchFootballUndoState]
    @State private var actionLog: WatchScoreActionLog
    @State private var matchStartTime: Date
    @State private var recordID: String
    @State private var undoToastToken: UUID?
    @State private var stoppageHistory: [Int] = []
    /// Pending single tap: a second tap on the same side inside the window
    /// subtracts a goal instead (Harmony/phone double-tap semantics).
    @State private var pendingGoal: (side: MatchSide, task: Task<Void, Never>)?

    init(
        isFiveAside: Bool,
        halfLengthSeconds: Int,
        leftName: String? = nil,
        rightName: String? = nil,
        resumedState: WatchFootballState? = nil,
        resumedUndoStates: [WatchFootballUndoState] = [],
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil,
        linkedSessionId: UUID? = nil,
        linkedState: LinkedFootballState? = nil
    ) {
        let resolvedHalfLength = max(60, halfLengthSeconds)
        let gameType = WatchFootballRules.gameType(isFiveAside: isFiveAside)
        let defaults = WatchDefaultTeamNames.resolve(for: gameType)

        self.isFiveAside = isFiveAside
        self.halfLengthSeconds = resolvedHalfLength
        self.linkedSessionId = linkedSessionId
        _leftName = State(initialValue: leftName ?? defaults.left)
        _rightName = State(initialValue: rightName ?? defaults.right)

        if let resumedState {
            var session = FootballMatchClockSession(
                state: resumedState.clock,
                gameType: gameType
            )
            session.reconcileAfterRestore()
            _clockSession = State(initialValue: session)
            _leftScore = State(initialValue: resumedState.leftScore)
            _rightScore = State(initialValue: resumedState.rightScore)
            let derived = resumedState.clock.isRunning
                || resumedState.clock.elapsedSeconds > 0
                || resumedState.clock.stage > 1
            _kickedOff = State(initialValue: resumedState.kickedOff ?? derived)
        } else if let linkedState {
            var session = FootballMatchClockSession(state: linkedState.timer, gameType: gameType)
            session.reconcileAfterRestore()
            _clockSession = State(initialValue: session)
            _leftScore = State(initialValue: linkedState.leftScore)
            _rightScore = State(initialValue: linkedState.rightScore)
            _kickedOff = State(initialValue: linkedState.kickedOff)
            if !linkedState.leftName.isEmpty {
                _leftName = State(initialValue: linkedState.leftName)
            }
            if !linkedState.rightName.isEmpty {
                _rightName = State(initialValue: linkedState.rightName)
            }
            _isFinished = State(initialValue: linkedState.finished)
            _showFinishedOverlay = State(initialValue: linkedState.finished)
        } else {
            var session = FootballMatchClockSession(
                state: FootballTimerStateV2(halfLengthSeconds: resolvedHalfLength),
                gameType: gameType
            )
            session.resetForNewGame()
            _clockSession = State(initialValue: session)
            _leftScore = State(initialValue: 0)
            _rightScore = State(initialValue: 0)
            // 11-a-side walks the clock from the first whistle; 5-a-side waits
            // for the kick-off button in the middle of the dial.
            _kickedOff = State(initialValue: !isFiveAside)
        }

        _undoStack = State(initialValue: resumedUndoStates)
        let startedAt = resumedStartTime ?? Date()
        _matchStartTime = State(initialValue: startedAt)
        _actionLog = State(initialValue: resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt))
        _recordID = State(initialValue: "w_\(UUID().uuidString)")
    }

    private var gameType: GameType {
        WatchFootballRules.gameType(isFiveAside: isFiveAside)
    }

    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    private var clockText: String {
        WatchFootballRules.formattedClock(seconds: clockSession.mainDisplaySeconds)
    }

    var body: some View {
        ZStack {
            board
                .ignoresSafeArea()
                .disabled(!interactionsEnabled)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if isFiveAside, !kickedOff, !isHorizontal {
                    // Vertical layout: the bottom half owns the lower quarter of
                    // the dial, so the kick-off button centres instead of covering
                    // that team's score.
                    kickOffButton
                    Spacer(minLength: 0)
                } else {
                    bottomControl
                }
            }
            .ignoresSafeArea()
            .disabled(!interactionsEnabled)

            if showMenu {
                WatchScoreboardMenuOverlay(
                    onDismiss: { showMenu = false },
                    onUndo: {
                        guard !scoringLocked else { return }
                        showMenu = false
                        undo()
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
                        showMenu = false
                        linkService.requestReclaim()
                    } : nil,
                    extraActions: menuExtraActions
                )
            }

            if showStoppagePanel {
                injuryPanel
            }

            if showPostRegulationPanel {
                postRegulationPanel
            }

            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreItems: [
                        WatchFinishedScoreItem(name: leftName, score: "\(leftScore)"),
                        WatchFinishedScoreItem(name: rightName, score: "\(rightScore)")
                    ],
                    winnerText: winnerText,
                    undoAvailable: finishUndoAvailable,
                    onUndo: undo,
                    onPlayAgain: restartMatch,
                    onExit: {
                        finalizeFinish()
                        exitBoard()
                    }
                )
            }

            confirmationOverlay
        }
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tickClock()
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let remote = update.snapshot.footballState else { return }
            applyLinkedState(remote, detailedActions: update.detailedActions)
        }
        .onChange(of: linkService.pendingReclaimAcceptance) { _, pending in
            guard let linkedSessionId, let pending, pending.sessionId == linkedSessionId,
                  let remote = pending.snapshot.footballState else { return }
            applyLinkedState(remote, detailedActions: pending.detailedActions)
            linkService.completeReclaimAcceptance(messageId: pending.messageId)
        }
        .onDisappear {
            finishTask?.cancel()
            if !scoringLocked, !isFinished {
                flushPendingGoal()
            }
            if isFinished {
                finalizeFinish()
            }
            persistResumeSession()
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: menuGesturesEnabled,
            onMenu: { showMenu = true },
            onUndo: undo,
            onExit: exitBoard
        )
        .watchUndoToast(token: $undoToastToken)
    }

    // MARK: - Board

    @ViewBuilder
    private var board: some View {
        if isHorizontal {
            HStack(spacing: 0) {
                half(.left)
                half(.right)
            }
        } else {
            VStack(spacing: 0) {
                half(.left)
                half(.right)
            }
        }
    }

    private func half(_ side: MatchSide) -> some View {
        let isLeft = side == .left
        let name = isLeft ? leftName : rightName
        let score = isLeft ? leftScore : rightScore
        let scoreText = "\(score)"
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
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                // Vertical layout stacks two halves: lift the lower score above
                // the bottom clock so the digits are never clipped.
                .offset(y: -verticalScoreLift(for: side))

            Text(name)
                .font(.system(size: isHorizontal ? 12 : 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Keep the top-row name clear of the watchOS status time.
                .padding(.top, nameTopPadding(for: side))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isLeft ? WatchTheme.teamRed : WatchTheme.teamBlue)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressTapAfterLongPress else { return }
            handleHalfTap(side)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(scoreText)")
        .accessibilityHint(NSLocalizedString("football_goal_hint", value: "轻点加一球", comment: ""))
        .accessibilityAddTraits(.isButton)
    }

    private func nameTopPadding(for side: MatchSide) -> CGFloat {
        guard !isHorizontal else { return 26 }
        return side == .left ? 26 : 8
    }

    /// Height the bottom clock occupies over the board (0 when hidden).
    private var bottomControlInset: CGFloat {
        guard !isFinished else { return 0 }
        if isFiveAside {
            return kickedOff ? Self.bottomPanelHeight + 2 : 0
        }
        return 40
    }

    private func verticalScoreLift(for side: MatchSide) -> CGFloat {
        guard !isHorizontal, side == .right else { return 0 }
        return bottomControlInset / 2
    }

    // MARK: - Bottom clock

    @ViewBuilder
    private var bottomControl: some View {
        if !isFinished {
            if isFiveAside, !kickedOff {
                kickOffButton
            } else if isFiveAside {
                fiveV5ClockPanel
            } else {
                clockPill
            }
        }
    }

    private var halfBadge: some View {
        Text(WatchFootballRules.stageBadge(clockSession.state.stage))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(stageAccent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var clockTextColor: Color {
        if clockSession.periodCompleted { return Self.amber }
        if isFiveAside, !clockSession.state.isRunning { return .white.opacity(0.55) }
        return .white
    }

    private var stageAccent: Color {
        switch clockSession.state.stage {
        case 1: return Color(hex: 0x22C55E)
        case 2: return Color(hex: 0x38BDF8)
        case 3: return Color(hex: 0xF59E0B)
        default: return Color(hex: 0xF97316)
        }
    }

    /// 11-a-side: compact pill hugging the bottom edge.
    private var clockPill: some View {
        HStack(spacing: 6) {
            halfBadge
            Text(clockText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(clockTextColor)
            if clockSession.elapsedStoppageSeconds > 0 {
                Text(WatchFootballRules.formattedStoppage(
                    seconds: clockSession.elapsedStoppageSeconds
                ))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Self.amber)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: Capsule())
        .padding(.bottom, 18)
        .contentShape(Capsule())
        .onTapGesture(perform: handleClockTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(WatchFootballRules.stageTitle(clockSession.state.stage)) \(clockText)"
        )
        .accessibilityAddTraits(clockSession.periodCompleted ? [.isButton] : [])
    }

    /// 5-a-side after kick-off: full-width panel, the whole bar toggles the clock.
    private var fiveV5ClockPanel: some View {
        HStack(spacing: 6) {
            halfBadge
            Text(clockText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(clockTextColor)
            Image(systemName: clockSession.state.isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(clockSession.state.isRunning ? .white : WatchTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.bottomPanelHeight)
        .background(Color.black.opacity(0.82))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleClock)
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(WatchFootballRules.stageTitle(clockSession.state.stage)) \(clockText)"
        )
        .accessibilityAddTraits(.isButton)
    }

    /// 5-a-side before kick-off: no time at all, just a pulsing start button.
    private var kickOffButton: some View {
        Button(action: kickOff) {
            Image(systemName: "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(WatchTheme.accent)
                .frame(width: 64, height: 64)
                .background(Color(hex: 0x2C2C2E), in: Circle())
                .scaleEffect(kickOffPulseScale)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
        .accessibilityLabel(NSLocalizedString("watch_football_start", value: "开始", comment: ""))
        .onAppear(perform: startKickOffPulse)
    }

    private func startKickOffPulse() {
        kickOffPulseScale = 1
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            kickOffPulseScale = 1.1
        }
    }

    // MARK: - Panels

    private var menuAction: MenuAction {
        if clockSession.periodCompleted,
           clockSession.state.stage == 1 || clockSession.state.stage == 3 {
            return .nextHalf
        }
        if isFiveAside {
            return .pauseClock
        }
        if clockSession.periodCompleted,
           clockSession.state.stage == 2,
           leftScore == rightScore {
            return .extraTime
        }
        return .injury
    }

    private var menuExtraActions: [WatchMenuExtraAction] {
        guard !scoringLocked, !isFinished else { return [] }
        var actions: [WatchMenuExtraAction]
        switch menuAction {
        case .nextHalf:
            actions = [
                WatchMenuExtraAction(
                    id: "football_next_half",
                    title: NSLocalizedString("football_switch_half", value: "进入下半场", comment: ""),
                    systemImage: "forward.end",
                    background: WatchTheme.successGreen,
                    action: { showMenu = false; advanceStage() }
                )
            ]
        case .pauseClock:
            let running = clockSession.state.isRunning
            let title = running
                ? NSLocalizedString("watch_football_pause", value: "暂停", comment: "")
                : (kickedOff
                    ? NSLocalizedString("watch_football_resume", value: "继续", comment: "")
                    : NSLocalizedString("watch_football_start", value: "开始", comment: ""))
            actions = [
                WatchMenuExtraAction(
                    id: "football_clock_toggle",
                    title: title,
                    systemImage: running ? "pause.fill" : "play.fill",
                    action: { showMenu = false; toggleClock() }
                )
            ]
        case .extraTime:
            actions = [
                WatchMenuExtraAction(
                    id: "football_extra_time",
                    title: NSLocalizedString("football_enter_extra_time", value: "进入加时赛", comment: ""),
                    systemImage: "timer",
                    background: WatchTheme.successGreen,
                    action: { showMenu = false; showPostRegulationPanel = true }
                )
            ]
        case .injury:
            let stoppage = clockSession.currentStoppageSeconds
            let title = stoppage > 0
                ? "\(NSLocalizedString("football_injury_title", value: "伤停补时", comment: "")) "
                    + WatchFootballRules.formattedStoppage(seconds: stoppage)
                : NSLocalizedString("football_injury_title", value: "伤停补时", comment: "")
            actions = [
                WatchMenuExtraAction(
                    id: "football_stoppage",
                    title: title,
                    systemImage: "clock.badge.plus",
                    action: { showMenu = false; showStoppagePanel = true }
                )
            ]
        }
        actions.append(layoutToggleAction)
        return actions
    }

    /// In-board layout switch, mirroring Harmony's menu toggle.
    private var layoutToggleAction: WatchMenuExtraAction {
        let isVertical = !isHorizontal
        return WatchMenuExtraAction(
            id: "football_layout",
            title: isVertical
                ? NSLocalizedString("watch_layout_horizontal", value: "左右", comment: "")
                : NSLocalizedString("watch_layout_vertical", value: "上下", comment: ""),
            systemImage: isVertical ? "rectangle.split.2x1" : "rectangle.split.1x2",
            action: { showMenu = false; toggleLayout() }
        )
    }

    private func toggleLayout() {
        let next = isHorizontal ? "vertical" : "horizontal"
        WatchPreferences.shared.scoreboardLayout = next
        scoreboardLayout = next
        WatchHaptics.shared.play(.light)
    }

    private var injuryPanel: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showStoppagePanel = false }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(NSLocalizedString("football_injury_title", value: "伤停补时", comment: ""))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(WatchFootballRules.formattedStoppage(
                        seconds: clockSession.currentStoppageSeconds
                    ))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(clockSession.currentStoppageSeconds > 0
                        ? WatchTheme.accent
                        : .white.opacity(0.45))
                }

                HStack(spacing: 10) {
                    injuryChip(15)
                    injuryChip(30)
                }
                HStack(spacing: 10) {
                    injuryChip(60)
                    injuryChip(90)
                }

                Button(NSLocalizedString(
                    "football_undo_stoppage",
                    value: "撤销最近一次补时",
                    comment: ""
                )) {
                    undoLastStoppage()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color(hex: 0x2C2C2E), in: Capsule())
                .disabled(stoppageHistory.isEmpty)
                .opacity(stoppageHistory.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 172)
            .background(Color(hex: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func injuryChip(_ seconds: Int) -> some View {
        Button {
            addStoppage(seconds)
        } label: {
            Text("+\(seconds)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(WatchTheme.accent, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var postRegulationPanel: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showPostRegulationPanel = false }

            VStack(spacing: 10) {
                Text(NSLocalizedString(
                    "football_enter_extra_time_title",
                    value: "常规时间结束",
                    comment: ""
                ))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

                Text("\(leftScore) : \(rightScore)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Button(NSLocalizedString("football_enter_extra_time", value: "进入加时赛", comment: "")) {
                    showPostRegulationPanel = false
                    advanceStage()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.successGreen)
                .foregroundStyle(.white)
                .frame(width: WatchLayout.overlayActionButtonWidth)

                Button(NSLocalizedString("football_end_as_draw", value: "以平局结束", comment: "")) {
                    showPostRegulationPanel = false
                    confirmation = .finish
                }
                .buttonStyle(.bordered)
                .frame(width: WatchLayout.overlayActionButtonWidth)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(hex: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private var confirmationOverlay: some View {
        if let confirmation {
            WatchConfirmationOverlay(
                confirmation: confirmation == .reset ? .reset : .finish,
                titleOverride: confirmationTitle(confirmation),
                messageOverride: confirmationMessage(confirmation),
                onCancel: { self.confirmation = nil },
                onConfirm: { confirm(confirmation) }
            )
        }
    }

    private func confirmationTitle(_ value: Confirmation) -> String {
        switch value {
        case .finish:
            return NSLocalizedString("watch_finish_confirm_title", value: "结束比赛？", comment: "")
        case .reset:
            return NSLocalizedString("watch_reset_confirm_title", value: "重新开始？", comment: "")
        case .advanceStage:
            return NSLocalizedString("football_switch_half_title", value: "进入下半场？", comment: "")
        }
    }

    private func confirmationMessage(_ value: Confirmation) -> String {
        switch value {
        case .finish:
            return NSLocalizedString("watch_finish_confirm_message", value: "将结束并保存本场比赛。", comment: "")
        case .reset:
            return NSLocalizedString("watch_reset_confirm_message", value: "当前比分将被清空。", comment: "")
        case .advanceStage:
            return NSLocalizedString("football_switch_half_message", value: "上半场将暂停，且不能切回。", comment: "")
        }
    }

    private func confirm(_ value: Confirmation) {
        confirmation = nil
        switch value {
        case .finish: finishMatch()
        case .reset: restartMatch()
        case .advanceStage: advanceStage()
        }
    }

    // MARK: - State changes

    private static let doubleTapWindowMilliseconds = 260

    /// Single tap adds a goal after the double-tap window; a second tap on the
    /// same side inside the window subtracts one instead.
    private func handleHalfTap(_ side: MatchSide) {
        guard interactionsEnabled, !scoringLocked else { return }
        if let pendingGoal, pendingGoal.side == side {
            pendingGoal.task.cancel()
            self.pendingGoal = nil
            subtractGoal(side)
            return
        }
        flushPendingGoal()
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.doubleTapWindowMilliseconds))
            guard !Task.isCancelled else { return }
            pendingGoal = nil
            addGoal(side)
        }
        pendingGoal = (side, task)
    }

    private func flushPendingGoal() {
        guard let pendingGoal else { return }
        self.pendingGoal = nil
        pendingGoal.task.cancel()
        addGoal(pendingGoal.side)
    }

    private func subtractGoal(_ side: MatchSide) {
        guard interactionsEnabled, !scoringLocked else { return }
        let current = side == .left ? leftScore : rightScore
        guard current > 0 else { return }
        pushUndo()
        actionLog.beginUndoableMutation()
        if side == .left {
            leftScore -= 1
        } else {
            rightScore -= 1
        }
        actionLog.append(contentsOf: [
            WatchScoreActionProjector.action(
                .scoreSubtract,
                code: "football_goal_undo",
                side: side,
                scores: (leftScore, rightScore),
                delta: -1,
                periodNumber: clockSession.state.stage,
                footballPeriod: clockSession.state.stage,
                footballElapsedSeconds: clockSession.elapsedSecondsNow()
            )
        ])
        WatchHaptics.shared.play(.undo)
        persistResumeSession()
        publishLinkedIfNeeded()
    }

    private func addGoal(_ side: MatchSide) {
        guard interactionsEnabled, !scoringLocked else { return }
        pushUndo()
        actionLog.beginUndoableMutation()
        if side == .left {
            leftScore += 1
        } else {
            rightScore += 1
        }
        actionLog.append(contentsOf: [
            WatchScoreActionProjector.action(
                .scoreAdd,
                code: "football_goal",
                side: side,
                scores: (leftScore, rightScore),
                delta: 1,
                periodNumber: clockSession.state.stage,
                footballPeriod: clockSession.state.stage,
                footballElapsedSeconds: clockSession.elapsedSecondsNow()
            )
        ])
        WatchHaptics.shared.play(.light)
        persistResumeSession()
        publishLinkedIfNeeded()
    }

    // MARK: - Linked session

    private var scoringLocked: Bool {
        linkedSessionId != nil && linkService.isFollower
    }

    private var linkedSnapshot: LinkedFootballState {
        LinkedFootballState(
            leftName: leftName,
            rightName: rightName,
            leftScore: leftScore,
            rightScore: rightScore,
            timer: clockSession.snapshot(),
            kickedOff: kickedOff,
            finished: isFinished
        )
    }

    private func publishLinkedIfNeeded() {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(
            .football(linkedSnapshot),
            detailedActions: actionLog.detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private func applyLinkedState(
        _ remote: LinkedFootballState,
        detailedActions: [DetailedScoreAction]
    ) {
        pendingGoal?.task.cancel()
        pendingGoal = nil
        actionLog.merge(detailedActions: detailedActions)
        if !remote.leftName.isEmpty { leftName = remote.leftName }
        if !remote.rightName.isEmpty { rightName = remote.rightName }
        leftScore = remote.leftScore
        rightScore = remote.rightScore
        var session = FootballMatchClockSession(state: remote.timer, gameType: gameType)
        session.reconcileAfterRestore()
        clockSession = session
        kickedOff = remote.kickedOff
        undoStack.removeAll()
        stoppageHistory.removeAll()
        showStoppagePanel = false
        showPostRegulationPanel = false
        confirmation = nil
        if remote.finished {
            isFinished = true
            showFinishedOverlay = true
            finishUndoAvailable = false
            finishTask?.cancel()
        } else {
            isFinished = false
            showFinishedOverlay = false
            didSaveRecord = false
        }
    }

    private func pushUndo() {
        undoStack.append(
            WatchFootballUndoState(
                leftScore: leftScore,
                rightScore: rightScore,
                clock: clockSession.snapshot()
            )
        )
    }

    private func kickOff() {
        guard !isFinished, !kickedOff, !scoringLocked else { return }
        clockSession.start()
        kickedOff = true
        actionLog.append(contentsOf: [
            WatchScoreActionProjector.action(
                .resume,
                code: "football_clock_start",
                scores: (leftScore, rightScore),
                periodNumber: clockSession.state.stage
            )
        ])
        WatchHaptics.shared.play(.medium)
        persistResumeSession()
        publishLinkedIfNeeded()
    }

    private func toggleClock() {
        guard !isFinished, !scoringLocked else { return }
        guard kickedOff else {
            kickOff()
            return
        }
        let wasRunning = clockSession.state.isRunning
        clockSession.toggleRunning()
        guard clockSession.state.isRunning != wasRunning else { return }
        actionLog.append(contentsOf: [
            WatchScoreActionProjector.action(
                clockSession.state.isRunning ? .resume : .stop,
                code: clockSession.state.isRunning ? "football_clock_start" : "football_clock_pause",
                scores: (leftScore, rightScore),
                periodNumber: clockSession.state.stage
            )
        ])
        WatchHaptics.shared.play(.light)
        persistResumeSession()
        publishLinkedIfNeeded()
    }

    private func handleClockTap() {
        guard !isFinished, clockSession.periodCompleted else { return }
        switch clockSession.state.stage {
        case 1:
            confirmation = .advanceStage
        case 2:
            if !isFiveAside, leftScore == rightScore {
                showPostRegulationPanel = true
            } else {
                confirmation = .finish
            }
        case 3:
            advanceStage()
        default:
            confirmation = .finish
        }
    }

    private func advanceStage() {
        guard !isFinished, !scoringLocked, clockSession.advanceStage() else { return }
        stoppageHistory.removeAll()
        actionLog.append(contentsOf: [
            WatchScoreActionProjector.action(
                .periodEnd,
                code: "football_period_end",
                scores: (leftScore, rightScore),
                periodNumber: clockSession.state.stage
            )
        ])
        WatchHaptics.shared.play(.strong)
        persistResumeSession()
        publishLinkedIfNeeded()
    }

    private func addStoppage(_ seconds: Int) {
        guard !isFinished, !scoringLocked, clockSession.addStoppageSeconds(seconds) else { return }
        stoppageHistory.append(seconds)
        actionLog.append(contentsOf: [
            WatchScoreActionProjector.action(
                .stateChange,
                code: "football_stoppage_add",
                scores: (leftScore, rightScore),
                delta: seconds,
                periodNumber: clockSession.state.stage
            )
        ])
        persistResumeSession()
        publishLinkedIfNeeded()
    }

    private func undoLastStoppage() {
        guard !scoringLocked,
              let seconds = stoppageHistory.last,
              clockSession.undoStoppageSeconds(seconds) else { return }
        stoppageHistory.removeLast()
        persistResumeSession()
        publishLinkedIfNeeded()
    }

    private func tickClock() {
        guard !isFinished else { return }
        let wasCompleted = clockSession.periodCompleted
        _ = clockSession.refresh()
        if !wasCompleted, clockSession.periodCompleted {
            WatchHaptics.shared.play(.finish)
            persistResumeSession()
        }
    }

    // MARK: - Finish / reset / exit

    private var winnerText: String? {
        guard leftScore != rightScore else { return nil }
        let winner = leftScore > rightScore ? leftName : rightName
        return String.localizedStringWithFormat(
            NSLocalizedString("watch_winner_format", value: "%@ 获胜", comment: ""),
            winner
        )
    }

    private func finishMatch() {
        guard !isFinished, !scoringLocked else { return }
        flushPendingGoal()
        finishTask?.cancel()
        clockSession.pause()
        isFinished = true
        let winner: MatchSide? = leftScore == rightScore ? nil : (leftScore > rightScore ? .left : .right)
        actionLog.append(contentsOf: [
            WatchScoreActionProjector.action(
                .gameEnd,
                code: "game_end",
                scores: (leftScore, rightScore),
                periodNumber: clockSession.state.stage,
                winner: winner
            )
        ])
        publishLinkedIfNeeded()
        resumeStore.clear()
        finishUndoAvailable = !undoStack.isEmpty
        showFinishedOverlay = true
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.finishedUndoCountdown))
            guard !Task.isCancelled else { return }
            finishUndoAvailable = false
            finalizeFinish()
        }
    }

    private func finalizeFinish() {
        guard isFinished, !didSaveRecord else { return }
        resumeStore.clear()
        if linkedSessionId != nil, linkService.isController {
            let winner: MatchSide? = leftScore == rightScore ? nil : (leftScore > rightScore ? .left : .right)
            linkService.publishMatchFinished(
                snapshot: .football(linkedSnapshot),
                recordId: recordID,
                winnerSide: winner,
                manualEnd: true,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: actionLog.scoreChangeCount,
                detailedActions: actionLog.detailedActions,
                participantNames: [leftName, rightName]
            )
            didSaveRecord = true
        } else {
            saveRecordIfNeeded()
        }
    }

    private func saveRecordIfNeeded() {
        guard !didSaveRecord else { return }
        let clock = clockSession.snapshot()
        guard leftScore + rightScore > 0
                || clock.elapsedSeconds > 0
                || clock.stage > 1
                || !undoStack.isEmpty else {
            return
        }
        didSaveRecord = true
        let end = Date()
        let winnerName: String? = leftScore == rightScore
            ? nil
            : (leftScore > rightScore ? leftName : rightName)
        let record = WatchScoreboardRecord(
            id: recordID,
            gameType: WatchFootballRules.watchGameType(isFiveAside: isFiveAside),
            startTime: matchStartTime,
            endTime: end,
            duration: end.timeIntervalSince(matchStartTime),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: leftScore,
            team2FinalScore: rightScore,
            team1SetScore: 0,
            team2SetScore: 0,
            winner: winnerName,
            actions: actionLog.actions,
            totalScoreChanges: actionLog.scoreChangeCount,
            projectConfiguration: [
                "scoreCoreGameType": gameType.rawValue,
                "footballHalfLengthSeconds": String(halfLengthSeconds),
                "showMatchTime": "true"
            ]
        )
        WatchRecordManager.shared.saveRecord(record)
    }

    private func undo() {
        guard !scoringLocked, !isFinished || finishUndoAvailable else { return }
        guard let previous = undoStack.popLast() else { return }
        finishTask?.cancel()
        leftScore = previous.leftScore
        rightScore = previous.rightScore
        clockSession = FootballMatchClockSession(state: previous.clock, gameType: gameType)
        actionLog.undo(team1Score: leftScore, team2Score: rightScore)
        // Reopening a finished match must not leave the finished record behind;
        // re-finishing writes the same id again.
        if didSaveRecord {
            _ = WatchRecordManager.shared.deleteRecord(id: recordID)
        }
        isFinished = false
        didSaveRecord = false
        showFinishedOverlay = false
        finishUndoAvailable = false
        undoToastToken = UUID()
        persistResumeSession()
        publishLinkedIfNeeded()
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        if isFinished {
            finalizeFinish()
        }
        finishTask?.cancel()
        resumeStore.clear()
        undoStack.removeAll()
        leftScore = 0
        rightScore = 0
        var session = FootballMatchClockSession(
            state: FootballTimerStateV2(halfLengthSeconds: halfLengthSeconds),
            gameType: gameType
        )
        session.resetForNewGame()
        clockSession = session
        kickedOff = !isFiveAside
        kickOffPulseScale = 1
        let restartedAt = Date()
        actionLog.reset(at: restartedAt)
        matchStartTime = restartedAt
        recordID = "w_\(UUID().uuidString)"
        didSaveRecord = false
        isFinished = false
        showFinishedOverlay = false
        finishUndoAvailable = false
        stoppageHistory.removeAll()
        persistResumeSession()
        if linkedSessionId != nil {
            linkService.startNextMatch(
                snapshot: .football(linkedSnapshot),
                participantNames: [leftName, rightName]
            )
        }
    }

    private func exitBoard() {
        if linkedSessionId != nil {
            linkService.exitScoreboardToHome()
        }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        guard !isFinished else {
            resumeStore.clear()
            return
        }
        let clock = clockSession.snapshot()
        let hasProgress = leftScore + rightScore > 0
            || clock.elapsedSeconds > 0
            || clock.stage > 1
            || !undoStack.isEmpty
        guard hasProgress else {
            resumeStore.clear()
            return
        }
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: "\(leftScore) - \(rightScore)",
            emoji: "⚽",
            payload: .football(
                isFiveAside: isFiveAside,
                state: WatchFootballState(
                    leftScore: leftScore,
                    rightScore: rightScore,
                    clock: clock,
                    kickedOff: kickedOff
                ),
                undoStates: undoStack,
                leftName: leftName,
                rightName: rightName
            ),
            actionLog: actionLog,
            link: linkService.resumeContext
        ))
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private var interactionsEnabled: Bool {
        !isFinished
            && !scoringLocked
            && !showMenu
            && !showStoppagePanel
            && !showPostRegulationPanel
            && confirmation == nil
            && !showFinishedOverlay
    }

    private var menuGesturesEnabled: Bool {
        !isFinished
            && !showMenu
            && !showStoppagePanel
            && !showPostRegulationPanel
            && confirmation == nil
            && !showFinishedOverlay
    }
}
