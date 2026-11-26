import Combine
import LinkCore
import RecordCore
import ScoreCore
import SwiftUI

/// Watch-local football board.
///
/// Full-bleed two-side scoreboard with the match clock at the bottom.
/// 5-a-side shows a kick-off button before revealing its clock controls.
/// Scoring is one goal per tap; long-press opens the menu.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WatchResumeSessionStore.self) private var resumeStore
    @Environment(WatchLinkService.self) private var linkService

    private static let amber = Color(hex: 0xFFB340)

    let isFiveAside: Bool
    let halfLengthSeconds: Int
    /// Non-nil when this board follows a phone-started linked session.
    let linkedSessionId: UUID?

    @State private var lastAppliedRemoteRevision: UInt64?
    @State private var lastAppliedRemoteGeneration: UInt64?

    @State private var showRecordSaveFailure = false
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
                bottomControl
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
                        WatchFinishedScoreItem(name: leftName, score: leftScore),
                        WatchFinishedScoreItem(name: rightName, score: rightScore)
                    ],
                    undoAvailable: finishUndoAvailable,
                    canPlayAgain: !scoringLocked,
                    onUndo: undo,
                    onPlayAgain: restartMatch,
                    onExit: {
                        guard finalizeFinish() else { return }
                        exitBoard()
                    }
                )
            }

            confirmationOverlay
        }
        .watchFinishSaveFailure(isPresented: $showRecordSaveFailure) { finalizeFinish() }
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tickClock()
        }
        .onChange(of: linkService.latestSnapshot, initial: true) { previous, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  update.matchGeneration == linkService.activeHandle?.matchGeneration,
                  let remote = update.snapshot.footballState else { return }
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
            applyLinkedState(remote)
        }
        .onChange(of: linkService.pendingReclaimAcceptance) { _, pending in
            guard let linkedSessionId, let pending, pending.sessionId == linkedSessionId,
                  let remote = pending.snapshot.footballState else { return }
            actionLog.merge(detailedActions: pending.detailedActions)
            applyLinkedState(remote)
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
            GeometryReader { proxy in
                let halfHeight = proxy.size.height / 2
                VStack(spacing: 0) {
                    half(.left)
                        .frame(height: halfHeight)
                    half(.right)
                        .frame(height: halfHeight)
                }
            }
        }
    }

    private func half(_ side: MatchSide) -> some View {
        let isLeft = side == .left
        let name = isLeft ? leftName : rightName
        let score = isLeft ? leftScore : rightScore
        let scoreText = "\(score)"
        let verticalScoreSize: CGFloat = WatchLayout.cachedScreenWidth <= 176 ? 46 : 62
        let scoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 56 : verticalScoreSize,
            scoreText: scoreText,
            minimumSize: isHorizontal ? 40 : 44
        )
        let scoreLabel = Text(scoreText)
            .font(WatchScoreTypography.primaryScore(size: scoreFont))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        let nameLabel = Text(name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
            .minimumScaleFactor(isHorizontal ? 0.6 : 1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)

        return ZStack {
            scoreLabel
            nameLabel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, isHorizontal ? WatchLayout.scoreboardTopNameInset : 12)
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
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(clockTextColor)
            if clockSession.elapsedStoppageSeconds > 0 {
                Text(WatchFootballRules.formattedStoppage(
                    seconds: clockSession.elapsedStoppageSeconds
                ))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Self.amber)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: Capsule())
        .padding(.bottom, isHorizontal ? 18 : 0)
        .contentShape(Capsule())
        .onTapGesture(perform: handleClockTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(WatchFootballRules.stageTitle(clockSession.state.stage)) \(clockText)"
        )
        .accessibilityAddTraits(clockSession.periodCompleted ? [.isButton] : [])
    }

    /// 5-a-side after kick-off: the entire capsule toggles the clock.
    private var fiveV5ClockPanel: some View {
        Button(action: toggleClock) {
            HStack(spacing: 6) {
                halfBadge
                Text(clockText)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(clockTextColor)
                fiveV5ClockIcon
                    .frame(width: 24)
            }
            .padding(.horizontal, 16)
            .frame(height: isHorizontal ? 44 : 32)
            .background(Color.black.opacity(0.82), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            clockSession.state.isRunning
                ? NSLocalizedString("watch_football_pause", value: "暂停", comment: "")
                : NSLocalizedString("watch_football_resume", value: "继续", comment: "")
        )
        .accessibilityValue(
            "\(WatchFootballRules.stageTitle(clockSession.state.stage)) \(clockText)"
        )
        .padding(.bottom, isHorizontal ? 8 : 0)
    }

    @ViewBuilder
    private var fiveV5ClockIcon: some View {
        let isRunning = clockSession.state.isRunning
        let icon = Image(systemName: isRunning ? "pause.fill" : "play.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isRunning ? .white : WatchTheme.accent)

        if !isRunning, !clockSession.periodCompleted, interactionsEnabled, !reduceMotion {
            icon.phaseAnimator([1.0, 1.12]) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
        } else {
            icon
        }
    }

    /// 5-a-side before kick-off: no time at all, just a pulsing start button.
    private var kickOffButton: some View {
        Button(action: kickOff) {
            Image(systemName: "play.fill")
                .font(.system(size: isHorizontal ? 26 : 18, weight: .bold))
                .foregroundStyle(WatchTheme.accent)
                .scaleEffect(isHorizontal ? 1 : kickOffPulseScale)
                .frame(width: isHorizontal ? 64 : 32, height: isHorizontal ? 64 : 32)
                .background(Color(hex: 0x2C2C2E), in: Circle())
                .scaleEffect(isHorizontal ? kickOffPulseScale : 1)
        }
        .buttonStyle(.plain)
        .padding(.bottom, isHorizontal ? 10 : 0)
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
        switch menuAction {
        case .nextHalf:
            return [
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
            return [
                WatchMenuExtraAction(
                    id: "football_clock_toggle",
                    title: title,
                    systemImage: running ? "pause.fill" : "play.fill",
                    action: { showMenu = false; toggleClock() }
                )
            ]
        case .extraTime:
            return [
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
            return [
                WatchMenuExtraAction(
                    id: "football_stoppage",
                    title: title,
                    systemImage: "clock.badge.plus",
                    action: { showMenu = false; showStoppagePanel = true }
                )
            ]
        }
    }

    private var injuryPanel: some View {
        let compact = WatchLayout.isCompactScreen
        return WatchFullScreenOverlay(
            scrim: Color.black.opacity(0.76),
            onBackgroundTap: { showStoppagePanel = false }
        ) { _, _ in
            VStack(spacing: 0) {
                WatchDialogHeader(
                    title: NSLocalizedString("football_injury_title", value: "伤停补时", comment: ""),
                    onClose: { showStoppagePanel = false }
                ) {
                    Text(WatchFootballRules.formattedStoppage(
                        seconds: clockSession.currentStoppageSeconds
                    ))
                    .font(.system(size: compact ? 11 : 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(clockSession.currentStoppageSeconds > 0
                        ? WatchTheme.accent
                        : .white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.bottom, compact ? 8 : 12)

                VStack(spacing: compact ? 6 : 10) {
                    HStack(spacing: compact ? 12 : 14) {
                        injuryChip(15)
                        injuryChip(30)
                    }
                    HStack(spacing: compact ? 12 : 14) {
                        injuryChip(60)
                        injuryChip(90)
                    }
                }
                .padding(.bottom, compact ? 8 : 12)

                Button {
                    undoLastStoppage()
                } label: {
                    Text(NSLocalizedString(
                        "football_undo_stoppage",
                        value: "撤销最近一次补时",
                        comment: ""
                    ))
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 30 : 34)
                    .background(Color(hex: 0x2C2C2E), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(stoppageHistory.isEmpty)
                .opacity(stoppageHistory.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.top, compact ? 8 : 12)
            .padding(.bottom, compact ? 10 : 14)
            .frame(maxWidth: .infinity)
            .background(WatchTheme.overlayCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            .padding(.top, compact ? 24 : 32)
            .padding(.bottom, compact ? 4 : 8)
        }
    }

    private func injuryChip(_ seconds: Int) -> some View {
        let size: CGFloat = WatchLayout.isCompactScreen ? 36 : 46
        return Button {
            addStoppage(seconds)
        } label: {
            Text("+\(seconds)")
                .font(.system(size: WatchLayout.isCompactScreen ? 13 : 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(WatchTheme.accent, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var postRegulationPanel: some View {
        let compact = WatchLayout.isCompactScreen
        return WatchFullScreenOverlay(
            scrim: Color.black.opacity(0.76),
            onBackgroundTap: { showPostRegulationPanel = false }
        ) { _, _ in
            VStack(spacing: 0) {
                WatchDialogHeader(
                    title: NSLocalizedString(
                        "football_enter_extra_time_title",
                        value: "常规时间结束",
                        comment: ""
                    ),
                    onClose: { showPostRegulationPanel = false }
                )
                .padding(.bottom, compact ? 8 : 10)

                Text("\(leftScore) : \(rightScore)")
                    .font(.system(size: compact ? 20 : 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.bottom, compact ? 10 : 14)

                VStack(spacing: compact ? 6 : 8) {
                    Button {
                        showPostRegulationPanel = false
                        advanceStage()
                    } label: {
                        Text(NSLocalizedString("football_enter_extra_time", value: "进入加时赛", comment: ""))
                            .font(.system(size: compact ? 13 : 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 34 : 38)
                            .background(WatchTheme.successGreen, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showPostRegulationPanel = false
                        confirmation = .finish
                    } label: {
                        Text(NSLocalizedString("football_end_as_draw", value: "以平局结束", comment: ""))
                            .font(.system(size: compact ? 13 : 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 34 : 38)
                            .background(WatchTheme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.top, compact ? 10 : 12)
            .padding(.bottom, compact ? 12 : 14)
            .frame(maxWidth: .infinity)
            .background(WatchTheme.overlayCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            .padding(.top, compact ? 22 : 26)
            .padding(.bottom, compact ? 4 : 8)
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
            ScoreActionProjector.action(
                .scoreChanged,
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
            ScoreActionProjector.action(
                .scoreChanged,
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
        guard linkedSessionId != nil, linkService.canEditLinkedMatch else { return }
        linkService.publishSnapshot(
            .football(linkedSnapshot),
            detailedActions: actionLog.detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private func applyLinkedState(_ remote: LinkedFootballState) {
        pendingGoal?.task.cancel()
        pendingGoal = nil
        actionLog.clearUndoHistory()
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
            ScoreActionProjector.action(
                .stateChanged,
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
            ScoreActionProjector.action(
                .stateChanged,
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
            ScoreActionProjector.action(
                .periodFinished,
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
            ScoreActionProjector.action(
                .stateChanged,
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

    private func finishMatch() {
        guard !isFinished, !scoringLocked else { return }
        flushPendingGoal()
        finishTask?.cancel()
        clockSession.pause()
        isFinished = true
        let winner: MatchSide? = leftScore == rightScore ? nil : (leftScore > rightScore ? .left : .right)
        actionLog.append(contentsOf: [
            ScoreActionProjector.action(
                .matchFinished,
                code: "game_end",
                scores: (leftScore, rightScore),
                periodNumber: clockSession.state.stage,
                winner: winner
            )
        ])
        publishLinkedIfNeeded()
        finishUndoAvailable = !undoStack.isEmpty
        showFinishedOverlay = true
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.finishedUndoCountdown))
            guard !Task.isCancelled else { return }
            finishUndoAvailable = false
            finalizeFinish()
        }
    }

    @discardableResult
    private func finalizeFinish() -> Bool {
        guard isFinished, !didSaveRecord, !scoringLocked else { return true }
        finishUndoAvailable = false
        let saved: Bool
        if linkedSessionId != nil {
            let winner: MatchSide? = leftScore == rightScore ? nil : (leftScore > rightScore ? .left : .right)
            saved = linkService.publishMatchFinished(
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
            } else {
            saved = saveRecordIfNeeded()
        }
        guard saved else {
            showRecordSaveFailure = true
            return false
        }
        didSaveRecord = true
        resumeStore.clear()
        return true
    }

    private func saveRecordIfNeeded() -> Bool {
        guard !didSaveRecord else { return true }
        let clock = clockSession.snapshot()
        guard leftScore + rightScore > 0
                || clock.elapsedSeconds > 0
                || clock.stage > 1
                || !undoStack.isEmpty else {
            return true
        }
        let end = Date()
        guard let record = WatchScoreboardRecord(
            localSnapshot: .football(linkedSnapshot), gameType: gameType,
            id: recordID, startTime: matchStartTime, endTime: end,
            detailedActions: actionLog.detailedActions, totalScoreChanges: actionLog.scoreChangeCount
        ) else { return false }
        return resumeStore.saveFinishedRecord(record)
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
        guard !isFinished || finalizeFinish() else { return }
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
        if let linkedSessionId { linkService.exitScoreboard(sessionId: linkedSessionId) }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        guard !isFinished else {
            if didSaveRecord { resumeStore.clear() }
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
