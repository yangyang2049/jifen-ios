import LinkCore
import RecordCore
import ScoreCore
import SwiftUI

enum WatchNineBallSecondarySelectionMode: Equatable {
    case payer
    case continuePlayer
}

struct WatchNineBallPendingSelection: Equatable {
    let actor: Int
    let kind: NineBallChaseKind
    let mode: WatchNineBallSecondarySelectionMode
}

enum WatchNineBallSelectionPolicy {
    static func isEventUnavailable(
        _ kind: NineBallChaseKind,
        for player: Int,
        in state: NineBallChaseState
    ) -> Bool {
        guard state.usesRackRules else { return false }
        if kind == .bigGold { return player != state.breakerPlayer }
        if state.isTournament { return !state.scoringKinds.contains(kind) }
        return kind == .smallGold
            && state.playerCount == 2
            && !state.config.smallGoldAllPay
            && player == state.breakerPlayer
    }

    static func secondarySelectionMode(
        for kind: NineBallChaseKind,
        player: Int,
        in state: NineBallChaseState
    ) -> WatchNineBallSecondarySelectionMode? {
        guard state.usesRackRules, !state.isTournament, state.playerCount > 2 else {
            return nil
        }
        switch kind {
        case .normalWin:
            return .payer
        case .smallGold:
            return state.config.smallGoldAllPay ? nil : .payer
        case .handoff:
            return .continuePlayer
        default:
            return nil
        }
    }

    static func candidatePlayers(excluding actor: Int, in state: NineBallChaseState) -> [Int] {
        (0..<state.playerCount).filter { $0 != actor }
    }

    static func recommendedPlayer(
        for mode: WatchNineBallSecondarySelectionMode,
        kind: NineBallChaseKind,
        actor: Int,
        in state: NineBallChaseState
    ) -> Int {
        let count = max(2, state.playerCount)
        switch mode {
        case .payer:
            if kind == .smallGold, !state.config.smallGoldAllPay, actor != state.breakerPlayer {
                return state.breakerPlayer
            }
            return (actor + count - 1) % count
        case .continuePlayer:
            return (actor + 1) % count
        }
    }
}

private struct WatchCueStickIcon: View {
    var size: CGFloat = 11

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            var shaft = Path()
            shaft.move(to: CGPoint(x: w * 0.16, y: h * 0.84))
            shaft.addLine(to: CGPoint(x: w * 0.78, y: h * 0.22))
            context.stroke(
                shaft,
                with: .color(.white),
                style: StrokeStyle(lineWidth: max(1.4, size * 0.16), lineCap: .round)
            )
            var tip = Path()
            tip.move(to: CGPoint(x: w * 0.76, y: h * 0.24))
            tip.addLine(to: CGPoint(x: w * 0.88, y: h * 0.12))
            context.stroke(
                tip,
                with: .color(.white),
                style: StrokeStyle(lineWidth: max(2.0, size * 0.22), lineCap: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
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
    @State private var pendingPlayerSelection: WatchNineBallPendingSelection?
    @State private var showBreakerPicker = false
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
    @State private var actionLog: WatchScoreActionLog
    @State private var undoToastToken: UUID?

    private static let playerColors: [Color] = [
        WatchTheme.teamRed,
        WatchTheme.teamBlue,
        Color(hex: 0x43A047),
        Color(hex: 0x8E24AA)
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
                    } : nil,
                    extraActions: nineBallMenuExtraActions
                )
            }
            if let eventPickerPlayer {
                nineBallEventPicker(for: eventPickerPlayer)
            }
            if let pendingPlayerSelection {
                nineBallSecondaryPlayerPicker(pendingPlayerSelection)
            }
            if showBreakerPicker {
                nineBallBreakerPicker
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

            HStack(spacing: 3) {
                if state.usesRackRules && player == state.breakerPlayer {
                    WatchCueStickIcon(size: state.playerCount > 2 ? 9 : 11)
                        .padding(2.5)
                        .background(Color.white.opacity(0.22), in: Circle())
                }
                Text(displayName(at: player))
                    .font(.system(size: nameFont, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, state.playerCount > 2 ? 4 : 8)
            .padding(.top, state.playerCount == 4 ? 8 : (isHorizontal ? 28 : 8))
            .offset(y: WatchLayout.scoreboardNameVerticalOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(playerColor(at: player))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !suppressTapAfterLongPress else { return }
            eventPickerPlayer = player
        }
    }

    private func playerColor(at player: Int) -> Color {
        player < Self.playerColors.count ? Self.playerColors[player] : .gray
    }

    private var nineBallMenuExtraActions: [WatchMenuExtraAction] {
        guard state.usesRackRules, !scoringLocked, !state.finished else { return [] }
        return [
            WatchMenuExtraAction(
                id: "nineBallBreaker",
                title: NSLocalizedString("nine_ball_current_breaker", value: "本局开球人", comment: ""),
                systemImage: "line.diagonal",
                action: {
                    showMenu = false
                    showBreakerPicker = true
                }
            )
        ]
    }

    private func logicalPlayer(forScreenIndex index: Int) -> Int {
        guard state.playerCount == 2, state.sidesSwapped else { return index }
        return index == 0 ? 1 : 0
    }

    private func nineBallEventPicker(for player: Int) -> some View {
        let isBreaker = state.usesRackRules && player == state.breakerPlayer
        return ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { eventPickerPlayer = nil }
            VStack(spacing: WatchLayout.isCompactScreen ? 3 : 7) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(playerColor(at: player))
                        .frame(width: 7, height: 7)
                    Text(displayName(at: player))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    if isBreaker {
                        Text(NSLocalizedString("watch_nine_ball_breaker_badge", value: "开球", comment: ""))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x83DA98))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(WatchTheme.accent.opacity(0.22), in: Capsule())
                    }
                }
                .padding(.bottom, 6)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: WatchLayout.isCompactScreen ? 5 : 7
                ) {
                    // v2/v3 状态的合法事件与 v1 不同（ball_in_hand 并入 foul，
                    // 新增 handoff），按状态实际支持的事件渲染。
                    ForEach(state.scoringKinds, id: \.rawValue) { kind in
                        let unavailable = WatchNineBallSelectionPolicy.isEventUnavailable(
                            kind,
                            for: player,
                            in: state
                        )
                        Button {
                            handleEventSelection(kind, for: player)
                        } label: {
                            VStack(spacing: 1) {
                                Text(nineBallEventTitle(kind))
                                    .font(.system(size: WatchLayout.isCompactScreen ? 11 : 12, weight: .semibold))
                                Text(nineBallEventPointText(kind, for: player))
                                    .font(WatchScoreTypography.secondaryScore(size: 10))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity, minHeight: WatchLayout.isCompactScreen ? 36 : 42)
                        }
                        .buttonStyle(.plain)
                        .background(kind == .foul ? WatchTheme.dangerRed : WatchTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .disabled(unavailable)
                        .opacity(unavailable ? 0.35 : 1)
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

    private func handleEventSelection(_ kind: NineBallChaseKind, for player: Int) {
        eventPickerPlayer = nil
        if let mode = WatchNineBallSelectionPolicy.secondarySelectionMode(
            for: kind,
            player: player,
            in: state
        ) {
            pendingPlayerSelection = WatchNineBallPendingSelection(
                actor: player,
                kind: kind,
                mode: mode
            )
            return
        }
        apply(kind, for: player)
    }

    private func nineBallSecondaryPlayerPicker(_ pending: WatchNineBallPendingSelection) -> some View {
        let candidates = WatchNineBallSelectionPolicy.candidatePlayers(excluding: pending.actor, in: state)
        let recommended = WatchNineBallSelectionPolicy.recommendedPlayer(
            for: pending.mode,
            kind: pending.kind,
            actor: pending.actor,
            in: state
        )
        let subtitle: String = switch pending.mode {
        case .payer:
            NSLocalizedString("watch_nine_ball_select_payer", value: "选择付分人", comment: "")
        case .continuePlayer:
            NSLocalizedString("watch_nine_ball_select_continue", value: "选择继续击球人", comment: "")
        }
        let recommendedBadge: String = {
            switch pending.mode {
            case .payer:
                if pending.kind == .smallGold,
                   !state.config.smallGoldAllPay,
                   pending.actor != state.breakerPlayer {
                    return NSLocalizedString("watch_nine_ball_breaker_badge", value: "开球", comment: "")
                }
                return NSLocalizedString("watch_nine_ball_prev_player", value: "上家", comment: "")
            case .continuePlayer:
                return NSLocalizedString("watch_nine_ball_next_player", value: "下家", comment: "")
            }
        }()
        let payerCost: Int = pending.kind == .smallGold ? state.config.smallGold : state.config.normalWin
        let rowHeight: CGFloat = WatchLayout.isCompactScreen ? 34 : 38

        return ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { pendingPlayerSelection = nil }
            VStack(spacing: WatchLayout.isCompactScreen ? 4 : 6) {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(playerColor(at: pending.actor))
                            .frame(width: 7, height: 7)
                        Text("\(displayName(at: pending.actor)) · \(nineBallEventTitle(pending.kind))")
                            .font(.system(size: WatchLayout.isCompactScreen ? 11 : 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .lineLimit(1)
                }
                .padding(.bottom, 2)

                VStack(spacing: WatchLayout.isCompactScreen ? 5 : 6) {
                    ForEach(candidates, id: \.self) { candidate in
                        let isRecommended = candidate == recommended
                        Button {
                            pendingPlayerSelection = nil
                            switch pending.mode {
                            case .payer:
                                apply(.chaseTransfer(
                                    player: pending.actor,
                                    kind: pending.kind,
                                    payer: candidate,
                                    continuePlayer: nil
                                ))
                            case .continuePlayer:
                                apply(.chaseTransfer(
                                    player: pending.actor,
                                    kind: pending.kind,
                                    payer: nil,
                                    continuePlayer: candidate
                                ))
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(playerColor(at: candidate))
                                    .frame(width: 7, height: 7)
                                Text(displayName(at: candidate))
                                    .font(.system(size: WatchLayout.isCompactScreen ? 12 : 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                if isRecommended {
                                    Text(recommendedBadge)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0x83DA98))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(WatchTheme.accent.opacity(0.22), in: Capsule())
                                }
                                Spacer(minLength: 4)
                                if pending.mode == .payer {
                                    Text("-\(payerCost)")
                                        .font(WatchScoreTypography.secondaryScore(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0xF09892))
                                } else {
                                    Text(NSLocalizedString("watch_nine_ball_continue_badge", value: "接杆", comment: ""))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.white.opacity(0.12), in: Capsule())
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: rowHeight)
                            .background(
                                isRecommended ? WatchTheme.accent.opacity(0.12) : WatchTheme.card,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay {
                                if isRecommended {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(WatchTheme.accent.opacity(0.55), lineWidth: 1.2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    let actor = pending.actor
                    pendingPlayerSelection = nil
                    eventPickerPlayer = actor
                } label: {
                    Image(systemName: "arrow.backward.circle.fill")
                        .font(.system(size: WatchLayout.isCompactScreen ? 32 : 36))
                        .foregroundStyle(WatchTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, WatchLayout.isCompactScreen ? 8 : 12)
            .padding(.vertical, WatchLayout.isCompactScreen ? 6 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchTheme.overlayCard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var nineBallBreakerPicker: some View {
        let compactRowHeight: CGFloat = state.playerCount >= 4
            ? (WatchLayout.isCompactScreen ? 28 : 32)
            : (WatchLayout.isCompactScreen ? 34 : 38)
        return ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { showBreakerPicker = false }
            VStack(spacing: WatchLayout.isCompactScreen ? 4 : 6) {
                Text(NSLocalizedString("nine_ball_current_breaker", value: "本局开球人", comment: ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                VStack(spacing: state.playerCount >= 4 ? 4 : 6) {
                    ForEach(0..<state.playerCount, id: \.self) { player in
                        let isCurrent = player == state.breakerPlayer
                        Button {
                            apply(.setBreaker(player: player))
                            showBreakerPicker = false
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(playerColor(at: player))
                                    .frame(width: 7, height: 7)
                                Text(displayName(at: player))
                                    .font(.system(size: WatchLayout.isCompactScreen ? 12 : 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer(minLength: 4)
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(WatchTheme.accent)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: compactRowHeight)
                            .background(
                                isCurrent ? WatchTheme.accent.opacity(0.16) : WatchTheme.card,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay {
                                if isCurrent {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(WatchTheme.accent, lineWidth: 1.2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                WatchMenuCloseButton { showBreakerPicker = false }
            }
            .padding(.horizontal, WatchLayout.isCompactScreen ? 8 : 12)
            .padding(.vertical, WatchLayout.isCompactScreen ? 6 : 10)
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

    /// ScoreCore 2026-10「九球新规则」把默认开局升到 ruleVersion 2 后，v1 的
    /// `.chaseEvent` 意图会被 reducer 直接拒绝（"Rule v2 requires a transfer
    /// event"）。手表此前没有随手机端一起迁移，导致 v2 状态下所有计分按钮
    /// 静默失效（见 docs/audit/2026-11-24/watch-full-check.md P0）。这里按
    /// 状态的 ruleVersion 分派：v1 保持旧意图，v2/v3 走 `.chaseTransfer`。
    private func apply(_ kind: NineBallChaseKind, for player: Int) {
        guard state.ruleVersion != 1 else {
            apply(.chaseEvent(player: player, kind: kind))
            return
        }
        if state.isTournament {
            apply(.tournamentEvent(player: player, kind: kind))
            return
        }
        // transfer 语义里 nil 交给 reducer 默认推导（普通胜=上家付分、小金=开球者付分、
        // 双人让杆=对面继续）；默认推导会被拒绝时（胜者即开球者的小金、多人让杆）
        // 手表就地解析为“下一位玩家”，避免再弹一层选择页。
        var payer: Int?
        var continuePlayer: Int?
        if kind == .smallGold, !state.config.smallGoldAllPay, player == state.breakerPlayer {
            payer = (player + 1) % state.playerCount
        }
        if kind == .handoff, state.playerCount > 2 {
            continuePlayer = (player + 1) % state.playerCount
        }
        apply(.chaseTransfer(player: player, kind: kind, payer: payer, continuePlayer: continuePlayer))
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
        guard hasNineBallProgress else { return }
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
        !scoringLocked && !state.finished && !showMenu && eventPickerPlayer == nil
            && pendingPlayerSelection == nil && !showBreakerPicker
            && confirmation == nil && !showFinishedOverlay
    }

    private var menuGesturesEnabled: Bool {
        !state.finished && !showMenu && eventPickerPlayer == nil
            && pendingPlayerSelection == nil && !showBreakerPicker
            && confirmation == nil && !showFinishedOverlay
    }

    private func applyAuthoritativeNineBall(
        _ remote: NineBallChaseState,
        detailedActions: [DetailedScoreAction]
    ) {
        actionLog.merge(detailedActions: detailedActions)
        state = remote
        undoStack.removeAll()
        eventPickerPlayer = nil
        pendingPlayerSelection = nil
        showBreakerPicker = false
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
        case .handoff: NSLocalizedString("nine_ball_handoff", value: "让杆", comment: "")
        }
    }

    private func nineBallEventPointText(_ kind: NineBallChaseKind, for player: Int) -> String {
        if kind == .handoff {
            return NSLocalizedString("nine_ball_no_score", value: "不计分", comment: "")
        }
        let value: Int
        switch kind {
        case .bigGold: value = state.config.bigGold
        case .smallGold: value = state.config.smallGold
        case .goldenNine: value = state.config.goldenNine
        case .normalWin: value = state.config.normalWin
        case .ballInHand: value = state.config.ballInHand
        case .foul:
            if state.isTournament, state.rackFouls.indices.contains(player), state.rackFouls[player] == 2 {
                value = state.config.thirdFoul
            } else {
                value = state.config.foul
            }
        case .handoff: value = 0
        }
        if kind == .foul {
            if state.usesRackRules && !state.isTournament { return "-\(value)" }
            if !state.usesRackRules && state.playerCount > 2 { return "-\(value)" }
        }
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
        pendingPlayerSelection = nil
        showBreakerPicker = false
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

