import Combine
import LinkCore
import LinkSync
import RecordCore
import ScoreCore
import SessionCore
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
    let linkedSessionId: UUID?

    @State private var linkedHandle: LinkedMatchHandle?

    @State private var showRecordSaveFailure = false
    /// 通用同步宿主：比分、时钟锚点、补时历史、撤销栈与动作日志只有这一处真相。
    @State private var store: WatchReducerSessionStore<FootballMatchReducer>
    /// 1 秒只读刷新锚点，仅驱动显示（不改状态、不入撤销栈、不发联动帧）。
    @State private var clockNowMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    @State private var kickOffPulseScale: CGFloat = 1
    @State private var scoreboardLayout = "horizontal"
    @State private var showMenu = false
    @State private var showStoppagePanel = false
    @State private var showPostRegulationPanel = false
    @State private var confirmation: Confirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var didSaveRecord = false
    @State private var suppressTapAfterLongPress = false
    @State private var matchStartTime: Date
    @State private var recordID: String
    @State private var undoToastToken: UUID?
    /// Pending single tap: a second tap on the same side inside the window
    /// subtracts a goal instead (Harmony/phone double-tap semantics).
    @State private var pendingGoal: (side: MatchSide, task: Task<Void, Never>)?

    init(
        isFiveAside: Bool,
        halfLengthSeconds: Int,
        leftName: String? = nil,
        rightName: String? = nil,
        resumeBundle: WatchFootballResumeBundle? = nil,
        initialState: FootballMatchState? = nil,
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil,
        linkedSessionId: UUID? = nil
    ) {
        let resolvedHalfLength = max(60, halfLengthSeconds)
        let gameType = WatchFootballRules.gameType(isFiveAside: isFiveAside)
        let defaults = WatchDefaultTeamNames.resolve(for: gameType)

        self.isFiveAside = isFiveAside
        self.halfLengthSeconds = resolvedHalfLength
        self.linkedSessionId = linkedSessionId

        let startedAt = resumedStartTime ?? Date()
        let binding = WatchBoardBindings.football(isFiveAside: isFiveAside)
        let actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        let restoredState: FootballMatchState

        if let resumeBundle {
            // 续玩只走标准 bundle：时钟锚点、分秒余量与补时历史全部随之恢复。
            restoredState = resumeBundle.currentSession.state
            _store = State(initialValue: WatchReducerSessionStore(
                resumeBundle: resumeBundle,
                reducer: FootballMatchReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        } else {
            let seed: FootballMatchState
            if let initialState {
                seed = initialState
            } else {
                seed = FootballMatchReducer.initial(
                    leftName: leftName ?? defaults.left,
                    rightName: rightName ?? defaults.right,
                    isFiveAside: isFiveAside,
                    halfLengthSeconds: resolvedHalfLength,
                    at: Int64((startedAt.timeIntervalSince1970 * 1_000).rounded())
                )
            }
            restoredState = seed
            let session = ScoreSession<FootballMatchState, FootballMatchEvent>(
                gameType: gameType,
                ruleFamily: .s1,
                reducerType: ScoreboardKernelRegistry.footballReducerType(for: gameType) ?? "football/v1",
                state: seed,
                participants: [
                    .init(id: TeamID.team0.rawValue, name: seed.leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: seed.rightName, role: "team")
                ]
            )
            _store = State(initialValue: WatchReducerSessionStore(
                seedSession: session,
                reducer: FootballMatchReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        }

        _showFinishedOverlay = State(initialValue: restoredState.finished)
        _matchStartTime = State(initialValue: startedAt)
        _recordID = State(initialValue: "w_\(UUID().uuidString)")
    }

    // MARK: - 由 Reducer State 派生的展示口径

    private var state: FootballMatchState { store.state }
    private var leftName: String { state.leftName }
    private var rightName: String { state.rightName }
    private var leftScore: Int { state.leftScore }
    private var rightScore: Int { state.rightScore }
    private var kickedOff: Bool { state.kickedOff }
    private var isFinished: Bool { state.finished }
    private var stoppageHistory: [Int] { state.stoppageHistory }
    private var clockStage: Int { state.timer.stage }
    private var clockRunning: Bool { state.timer.isRunning }
    private var elapsedNow: Int { state.displayElapsedSeconds(at: clockNowMilliseconds) }
    private var mainClockSeconds: Int { state.mainDisplaySeconds(at: clockNowMilliseconds) }
    private var stoppageElapsedSeconds: Int { state.stoppageElapsedSeconds(at: clockNowMilliseconds) }
    private var periodCompleted: Bool { state.isPeriodCompleted(at: clockNowMilliseconds) }
    private var currentStoppageSeconds: Int { state.currentStoppageSeconds }

    private var gameType: GameType {
        WatchFootballRules.gameType(isFiveAside: isFiveAside)
    }

    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    private var clockText: String {
        WatchFootballRules.formattedClock(seconds: mainClockSeconds)
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
                        guard linkedSessionId == nil, !scoringLocked else { return }
                        showMenu = false
                        confirmation = .reset
                    },
                    extraActions: menuExtraActions
                )
            }

            if showStoppagePanel {
                injuryPanel
            }

            if showPostRegulationPanel {
                postRegulationPanel
            }

            if presentsFinishOverlay {
                WatchFinishedOverlay(
                    title: store.isPendingLinkedFinish
                        ? NSLocalizedString("linked_score_pending_finish", value: "Waiting for sync", comment: "")
                        : NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreItems: [
                        WatchFinishedScoreItem(name: leftName, score: leftScore),
                        WatchFinishedScoreItem(name: rightName, score: rightScore)
                    ],
                    undoAvailable: linkedSessionId == nil && finishUndoAvailable,
                    canPlayAgain: linkedSessionId == nil ? !scoringLocked : canStartLinkedNextMatch,
                    onUndo: undo,
                    onPlayAgain: restartMatch,
                    onExit: {
                        guard finalizeFinish() else { return }
                        exitBoard()
                    }
                )
                .overlay(alignment: .topTrailing) {
                    if hasCurrentLinkedMatch, store.savedRecordID == nil {
                        linkedFinishSyncButton
                    }
                }
            }

            confirmationOverlay
        }
        .watchFinishSaveFailure(isPresented: $showRecordSaveFailure) { finalizeFinish() }
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            applyLinkedIntentUpdate(linkService.intentSync.update)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tickClock()
        }
        .onChange(of: linkService.intentSync.update) { _, update in
            applyLinkedIntentUpdate(update)
        }
        .onDisappear {
            finishTask?.cancel()
            if !scoringLocked, !isFinished {
                flushPendingGoal()
            } else {
                cancelPendingGoal()
            }
            if linkedSessionId == nil, isFinished {
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
        Text(WatchFootballRules.stageBadge(clockStage))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(stageAccent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var clockTextColor: Color {
        if periodCompleted { return Self.amber }
        if isFiveAside, !clockRunning { return .white.opacity(0.55) }
        return .white
    }

    private var stageAccent: Color {
        switch clockStage {
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
            if stoppageElapsedSeconds > 0 {
                Text(WatchFootballRules.formattedStoppage(
                    seconds: stoppageElapsedSeconds
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
            "\(WatchFootballRules.stageTitle(clockStage)) \(clockText)"
        )
        .accessibilityAddTraits(periodCompleted ? [.isButton] : [])
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
            clockRunning
                ? NSLocalizedString("watch_football_pause", value: "暂停", comment: "")
                : NSLocalizedString("watch_football_resume", value: "继续", comment: "")
        )
        .accessibilityValue(
            "\(WatchFootballRules.stageTitle(clockStage)) \(clockText)"
        )
        .padding(.bottom, isHorizontal ? 8 : 0)
    }

    @ViewBuilder
    private var fiveV5ClockIcon: some View {
        let isRunning = clockRunning
        let icon = Image(systemName: isRunning ? "pause.fill" : "play.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isRunning ? .white : WatchTheme.accent)

        if !isRunning, !periodCompleted, interactionsEnabled, !reduceMotion {
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
        if periodCompleted,
           clockStage == 1 || clockStage == 3 {
            return .nextHalf
        }
        if isFiveAside {
            return .pauseClock
        }
        if periodCompleted,
           clockStage == 2,
           leftScore == rightScore {
            return .extraTime
        }
        return .injury
    }

    private var menuExtraActions: [WatchMenuExtraAction] {
        var actions = footballMenuActions
        if hasCurrentLinkedMatch {
            actions.append(WatchMenuExtraAction(
                id: "football_sync_scores", title: linkedSyncLabel, systemImage: "arrow.clockwise", action: {
                    showMenu = false
                    syncLinkedScores()
                }
            ))
        }
        return actions
    }

    private var footballMenuActions: [WatchMenuExtraAction] {
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
            let running = clockRunning
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
            let stoppage = currentStoppageSeconds
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
                        seconds: currentStoppageSeconds
                    ))
                    .font(.system(size: compact ? 11 : 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(currentStoppageSeconds > 0
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

    /// 记分动作只走 Reducer：时钟先按锚点结算，进球分钟随事件一起投影。
    private func subtractGoal(_ side: MatchSide) {
        guard interactionsEnabled, !scoringLocked else { return }
        guard case .accepted(_, _) = store.dispatch(.subtractGoal(side: side)) else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        WatchHaptics.shared.play(.undo)
        persistResumeSession()
    }

    private func addGoal(_ side: MatchSide) {
        guard interactionsEnabled, !scoringLocked else { return }
        guard case .accepted(_, _) = store.dispatch(.goal(side: side)) else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        WatchHaptics.shared.play(.light)
        persistResumeSession()
    }

    private static func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    // MARK: - Linked session

    private var hasCurrentLinkedMatch: Bool {
        guard let linkedHandle else { return false }
        return linkedHandle == linkService.activeHandle && linkService.intentSync.update?.handle == linkedHandle
    }

    private var scoringLocked: Bool {
        guard linkedSessionId != nil else { return false }
        return !hasCurrentLinkedMatch || !store.isUsingLinkedIntents
            || !linkService.canEditLinkedMatch || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed
    }

    private var presentsFinishOverlay: Bool {
        if linkedSessionId != nil { return store.isPendingLinkedFinish || store.isLinkedFinishConfirmed }
        return showFinishedOverlay
    }

    private var canStartLinkedNextMatch: Bool {
        guard let linkedHandle, hasCurrentLinkedMatch, linkService.canEditLinkedMatch,
              store.isLinkedFinishConfirmed, store.savedRecordID != nil else { return false }
        return !linkService.intentSync.hasPendingOperations(for: linkedHandle)
    }

    private var linkedSyncLabel: String {
        NSLocalizedString("linked_score_resync", value: "Sync score", comment: "")
    }

    private var linkedFinishSyncButton: some View {
        Button(action: syncLinkedScores) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 6)
        .accessibilityLabel(linkedSyncLabel)
        .accessibilityIdentifier("watch_football_sync_scores")
    }

    private func syncLinkedScores() {
        guard hasCurrentLinkedMatch else { return }
        linkService.syncLinkedScores()
    }

    private func applyLinkedIntentUpdate(_ update: WatchLinkedIntentUpdate?) {
        guard let linkedSessionId, let update, update.handle.sessionId == linkedSessionId,
              update.handle == linkService.activeHandle, linkService.activeGameType == gameType,
              update.displayedSnapshot.footballState?.isFiveAside == isFiveAside else { return }
        if let linkedHandle {
            guard update.handle == linkedHandle else { return }
            guard store.applyLinkedIntentUpdate(update)
                    || store.linkedIntentUpdate?.presentationSequence == update.presentationSequence else { return }
        } else {
            linkedHandle = update.handle
            store.attachLinkedMatch(update.handle, sync: linkService.intentSync, intent: LinkedScoreboardIntent.football) {
                $0.footballState
            }
        }
        clockNowMilliseconds = Self.nowMilliseconds()
        if store.isPendingLinkedFinish || store.isLinkedFinishConfirmed {
            cancelPendingGoal()
            showMenu = false
            showStoppagePanel = false
            showPostRegulationPanel = false
            confirmation = nil
        }
        if store.savedRecordID != nil, resumeStore.session?.linkHandle == update.handle {
            resumeStore.clear()
        } else {
            persistResumeSession()
        }
    }

    private func cancelPendingGoal() {
        pendingGoal?.task.cancel()
        pendingGoal = nil
    }

    private func kickOff() {
        guard !isFinished, !kickedOff, !scoringLocked else { return }
        guard case .accepted(_, _) = store.dispatch(.kickOff) else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        WatchHaptics.shared.play(.medium)
        persistResumeSession()
    }

    private func toggleClock() {
        guard !isFinished, !scoringLocked else { return }
        guard kickedOff else {
            kickOff()
            return
        }
        guard case .accepted(_, _) = store.dispatch(.toggleClock) else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        WatchHaptics.shared.play(.light)
        persistResumeSession()
    }

    private func handleClockTap() {
        guard !isFinished, periodCompleted else { return }
        switch clockStage {
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
        guard !isFinished, !scoringLocked else { return }
        guard case .accepted(_, _) = store.dispatch(.advanceStage) else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        WatchHaptics.shared.play(.strong)
        persistResumeSession()
    }

    private func addStoppage(_ seconds: Int) {
        guard !isFinished, !scoringLocked else { return }
        guard case .accepted(_, _) = store.dispatch(.addStoppage(seconds: seconds)) else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        persistResumeSession()
    }

    private func undoLastStoppage() {
        guard !scoringLocked else { return }
        guard case .accepted(_, _) = store.dispatch(.undoLastStoppage) else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        persistResumeSession()
    }

    /// 1 秒只读刷新：只推进显示锚点，不写状态、不入撤销栈、不发联动帧。
    private func tickClock() {
        guard !isFinished else { return }
        let wasCompleted = periodCompleted
        clockNowMilliseconds = Self.nowMilliseconds()
        if !wasCompleted, periodCompleted {
            WatchHaptics.shared.play(.finish)
            persistResumeSession()
        }
    }

    // MARK: - Finish / reset / exit

    private func finishMatch() {
        guard !isFinished, !scoringLocked else { return }
        flushPendingGoal()
        if linkedSessionId != nil {
            if store.requestLinkedFinish() { applyLinkedIntentUpdate(linkService.intentSync.update) }
            return
        }
        finishTask?.cancel()
        guard case .accepted(_, _) = store.dispatch(.finish) else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        finishUndoAvailable = store.canUndo
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
        // The linked coordinator writes the confirmed record under the match ID.
        guard linkedSessionId == nil else { return true }
        guard isFinished, store.savedRecordID == nil, !didSaveRecord, !scoringLocked else { return true }
        finishUndoAvailable = false
        guard saveRecordIfNeeded() else {
            showRecordSaveFailure = true
            return false
        }
        didSaveRecord = true
        store.markRecordSaved(recordID)
        resumeStore.clear()
        return true
    }

    private func saveRecordIfNeeded() -> Bool {
        guard store.savedRecordID == nil, !didSaveRecord else { return true }
        guard state.leftScore + state.rightScore > 0
                || state.timer.elapsedSeconds > 0
                || state.timer.stage > 1
                || store.canUndo else {
            return true
        }
        let end = Date()
        guard let record = WatchScoreboardRecord(
            localSnapshot: .football(state), gameType: gameType,
            id: recordID, startTime: matchStartTime, endTime: end,
            detailedActions: store.actionLog.detailedActions, totalScoreChanges: store.actionLog.scoreChangeCount
        ) else { return false }
        guard resumeStore.saveFinishedRecord(record) else { return false }
        store.markRecordSaved(recordID)
        return true
    }

    private func undo() {
        guard !scoringLocked, !isFinished || finishUndoAvailable else { return }
        if linkedSessionId != nil {
            guard let target = store.linkedIntentUpdate?.latestUndoableOperationId,
                  store.undoLinked(targetOpId: target) else { return }
            undoToastToken = UUID()
            applyLinkedIntentUpdate(linkService.intentSync.update)
            return
        }
        finishTask?.cancel()
        guard store.undo() else { return }
        clockNowMilliseconds = Self.nowMilliseconds()
        // Reopening a finished match must not leave the finished record behind;
        // re-finishing writes the same id again.
        if didSaveRecord {
            _ = WatchRecordManager.shared.deleteRecord(id: recordID)
        }
        store.clearSavedRecord()
        didSaveRecord = false
        showFinishedOverlay = false
        finishUndoAvailable = false
        undoToastToken = UUID()
        persistResumeSession()
    }

    private func restartMatch() {
        if linkedSessionId != nil {
            guard canStartLinkedNextMatch else { return }
            _ = store.requestLinkedNextMatch()
            return
        }
        guard !scoringLocked else { return }
        guard !isFinished || finalizeFinish() else { return }
        finishTask?.cancel()
        resumeStore.clear()
        let restartedAt = Date()
        guard case .accepted(_, _) = store.dispatch(.reset(halfLengthSeconds: halfLengthSeconds), at: restartedAt) else {
            return
        }
        store.beginRemoteMatch(at: restartedAt)
        store.clearSavedRecord()
        clockNowMilliseconds = Self.nowMilliseconds()
        kickOffPulseScale = 1
        matchStartTime = restartedAt
        recordID = "w_\(UUID().uuidString)"
        didSaveRecord = false
        showFinishedOverlay = false
        finishUndoAvailable = false
        persistResumeSession()
    }

    private func exitBoard() {
        if hasCurrentLinkedMatch, let linkedHandle {
            if !scoringLocked { flushPendingGoal() }
            persistResumeSession()
            linkService.exitScoreboard(sessionId: linkedHandle.sessionId)
        } else if linkedSessionId == nil {
            persistResumeSession()
        }
        dismiss()
    }

    /// 续玩草稿统一走标准 bundle：状态、撤销帧与时间线一次性持久化。
    private func persistResumeSession() {
        if linkedSessionId != nil {
            guard hasCurrentLinkedMatch, let linkedHandle, let context = linkService.resumeContext,
                  context.handle == linkedHandle, !store.isPendingLinkedFinish, !store.isLinkedFinishConfirmed else { return }
            _ = store.persistResumeSession(into: resumeStore, link: context, startedAt: store.startedAt)
            return
        }
        guard !isFinished else {
            if store.savedRecordID != nil { resumeStore.clear() }
            return
        }
        let hasProgress = state.leftScore + state.rightScore > 0
            || state.timer.elapsedSeconds > 0
            || state.timer.stage > 1
            || store.canUndo
        guard hasProgress else {
            resumeStore.clear()
            return
        }
        _ = store.persistResumeSession(
            into: resumeStore,
            startedAt: matchStartTime,
            payload: .football(isFiveAside: isFiveAside, bundle: store.resumeBundle())
        )
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
            && !presentsFinishOverlay
    }

    private var menuGesturesEnabled: Bool {
        !isFinished
            && !showMenu
            && !showStoppagePanel
            && !showPostRegulationPanel
            && confirmation == nil
            && !presentsFinishOverlay
    }
}
