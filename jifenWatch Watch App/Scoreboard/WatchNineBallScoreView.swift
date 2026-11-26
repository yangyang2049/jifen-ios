import LinkCore
import RecordCore
import ScoreCore
import SessionCore
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

struct WatchNineBallScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let linkedSessionId: UUID?
    @State private var lastAppliedRemoteRevision: UInt64?
    @State private var lastAppliedRemoteGeneration: UInt64?

    @State private var showRecordSaveFailure = false
    /// 通用同步宿主：比分、撤销栈、时间线与动作日志只有这一处真相。
    @State private var store: WatchReducerSessionStore<NineBallChaseReducer>
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var eventPickerPlayer: Int?
    @State private var pendingPlayerSelection: WatchNineBallPendingSelection?
    @State private var showBreakerPicker = false
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
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
        resumeBundle: WatchNineBallResumeBundle? = nil,
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.linkedSessionId = linkedSessionId
        let startedAt = resumedStartTime ?? Date()
        let binding = WatchBoardBindings.nineBall()
        let actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        if let resumeBundle {
            // 续玩只走标准 bundle：比分、撤销帧与时间线一并恢复。
            _store = State(initialValue: WatchReducerSessionStore(
                resumeBundle: resumeBundle,
                reducer: NineBallChaseReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        } else {
            let seed = initialState ?? NineBallChaseState.initial()
            let descriptor = ScoreboardKernelRegistry.descriptor(for: .nineBall)
            let session = ScoreSession<NineBallChaseState, NineBallChaseEvent>(
                gameType: .nineBall,
                ruleFamily: descriptor.ruleFamily,
                reducerType: descriptor.reducerType,
                state: seed,
                participants: (0..<seed.playerCount).map { index in
                    SessionParticipant(
                        id: "player_\(index)",
                        name: seed.resolvedName(at: index, fallback: "P\(index + 1)"),
                        role: "player"
                    )
                }
            )
            _store = State(initialValue: WatchReducerSessionStore(
                seedSession: session,
                reducer: NineBallChaseReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        }
        _matchStartTime = State(initialValue: startedAt)
    }

    private var state: NineBallChaseState { store.state }

    private var scoringLocked: Bool { linkedSessionId != nil && !linkService.canEditLinkedMatch }
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
                        WatchFinishedScoreItem(name: displayName(at: $0), score: playerPoints(at: $0))
                    },
                    undoAvailable: finishUndoAvailable,
                    canPlayAgain: !scoringLocked,
                    onUndo: undoFinishedNineBall,
                    onPlayAgain: restartMatch,
                    onExit: {
                        guard finalizeNineBall() else { return }
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
        .watchFinishSaveFailure(isPresented: $showRecordSaveFailure) { finalizeNineBall() }
        .onAppear {
            if state.playerCount < 4 {
                scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            guard state.playerCount < 4 else { return }
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot, initial: true) { previous, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  update.matchGeneration == linkService.activeHandle?.matchGeneration,
                  let remote = update.snapshot.nineBallState else { return }
            let acceptsScore = linkService.incomingSnapshot != nil
            if acceptsScore, update.beginsMatch(after: previous) {
                matchStartTime = Date()
                store.beginRemoteMatch(at: matchStartTime)
            }
            let historyChanged = store.mergeRemoteActions(update.detailedActions, removing: update.removedActionIDs)
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
            applyAuthoritativeNineBall(remote)
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
        let nameFont: CGFloat = state.playerCount > 2 ? 12 : 14
        let scoreLabel = Text(scoreText)
            .font(WatchScoreTypography.primaryScore(size: scoreFont))
            .monospacedDigit()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        let nameRow = HStack(spacing: 4) {
            if state.usesRackRules && player == state.breakerPlayer {
                let cueSize: CGFloat = state.playerCount > 2 ? 12 : 14
                Image("ic_snooker_cue")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cueSize, height: cueSize)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            Text(displayName(at: player))
                .font(.system(size: nameFont, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(isHorizontal ? 0.65 : 1)
        }
        return Group {
            if state.playerCount == 4 {
                // Reuse the clock clearance in every quadrant to align both rows.
                VStack(spacing: 0) {
                    nameRow
                        .padding(.horizontal, 4)
                        .padding(.top, WatchLayout.isCompactScreen ? 30 : 38)
                    Spacer(minLength: 2)
                    scoreLabel
                    Spacer(minLength: 4)
                }
            } else {
                WatchScoreboardFace(isHorizontal: isHorizontal, bottomInset: 4) {
                    nameRow
                        .padding(.horizontal, state.playerCount > 2 ? 4 : 8)
                } score: {
                    scoreLabel
                }
            }
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
                assetImage: "ic_snooker_cue",
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
        let compact = WatchLayout.isCompactScreen
        return ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { eventPickerPlayer = nil }
            VStack(spacing: compact ? 4 : 6) {
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
                .padding(.bottom, compact ? 3 : 8)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: compact ? 4 : 6
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
                                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                                Text(nineBallEventPointText(kind, for: player))
                                    .font(WatchScoreTypography.secondaryScore(size: 10))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity, minHeight: compact ? 34 : 40)
                        }
                        .buttonStyle(.plain)
                        .background(kind == .foul ? WatchTheme.dangerRed : WatchTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .disabled(unavailable)
                        .opacity(unavailable ? 0.35 : 1)
                    }
                }
                Button { eventPickerPlayer = nil } label: {
                    let closeSize: CGFloat = compact ? 32 : WatchLayout.overlayCloseButtonSize
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: closeSize))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .frame(width: closeSize, height: closeSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.top, compact ? 26 : 34)
            .padding(.bottom, compact ? 4 : 8)
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
        let compact = WatchLayout.isCompactScreen
        let rowHeight: CGFloat = compact ? (candidates.count <= 2 ? 36 : 32) : 36

        return ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { pendingPlayerSelection = nil }
            VStack(spacing: compact ? 4 : 6) {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(playerColor(at: pending.actor))
                            .frame(width: 7, height: 7)
                        Text("\(displayName(at: pending.actor)) · \(nineBallEventTitle(pending.kind))")
                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .lineLimit(1)
                }
                .padding(.bottom, compact ? 2 : 6)

                VStack(spacing: compact ? 4 : 6) {
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
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isRecommended ? WatchTheme.accent.opacity(0.12) : WatchTheme.card)
                                if isRecommended {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(WatchTheme.accent.opacity(0.55), lineWidth: 1.2)
                                }
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(playerColor(at: candidate))
                                        .frame(width: 7, height: 7)
                                    Text(displayName(at: candidate))
                                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
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
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                            .contentShape(Rectangle())
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
                        .font(.system(size: compact ? 30 : 36))
                        .foregroundStyle(WatchTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, compact ? 1 : 2)
            }
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.top, compact ? 26 : 34)
            .padding(.bottom, compact ? 4 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchTheme.overlayCard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var nineBallBreakerPicker: some View {
        let compact = WatchLayout.isCompactScreen
        let compactRowHeight: CGFloat = state.playerCount >= 4
            ? (compact ? 26 : 32)
            : (compact ? 32 : 36)
        let closeSize: CGFloat = (compact && state.playerCount >= 4) ? 28 : WatchLayout.overlayCloseButtonSize
        return ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { showBreakerPicker = false }
            VStack(spacing: compact ? 4 : 6) {
                Text(NSLocalizedString("nine_ball_current_breaker", value: "本局开球人", comment: ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.bottom, compact ? 2 : 6)
                VStack(spacing: state.playerCount >= 4 ? 4 : 6) {
                    ForEach(0..<state.playerCount, id: \.self) { player in
                        let isCurrent = player == state.breakerPlayer
                        Button {
                            apply(.setBreaker(player: player))
                            showBreakerPicker = false
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isCurrent ? WatchTheme.accent.opacity(0.16) : WatchTheme.card)
                                if isCurrent {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(WatchTheme.accent, lineWidth: 1.2)
                                }
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(playerColor(at: player))
                                        .frame(width: 7, height: 7)
                                    Text(displayName(at: player))
                                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
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
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: compactRowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { showBreakerPicker = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: closeSize))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .frame(width: closeSize, height: closeSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.top, compact ? 26 : 34)
            .padding(.bottom, compact ? 4 : 8)
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
        // 比分、撤销帧与动作日志投影（含 resetScores 清空日志）全部由宿主完成。
        guard case .accepted(_, _) = store.dispatch(intent) else { return }
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
        // `.finishMatch` 的完赛动作（含胜者）由 binding 投影进动作日志。
        guard case .accepted(_, _) = store.dispatch(.finishMatch) else { return }
        publish()
        beginNineBallFinish(manualEnd: true)
    }

    private func publish() {
        guard linkedSessionId != nil, linkService.canEditLinkedMatch else { return }
        linkService.publishSnapshot(.nineBall(state), detailedActions: store.actionLog.detailedActions)
    }

    private func winnerSide() -> MatchSide? {
        guard state.playerCount <= 2 else { return nil }
        let left = playerPoints(at: 0)
        let right = playerPoints(at: 1)
        if left == right { return nil }
        return left > right ? .left : .right
    }

    private func saveLocalRecordIfNeeded() -> Bool {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return true }
        guard hasNineBallProgress else { return true }
        return store.saveFinishedRecord(
            into: resumeStore,
            gameType: .nineBall,
            recordID: "w_\(UUID().uuidString)",
            endTime: Date(),
            participantNames: (0..<state.playerCount).map { displayName(at: $0) },
            totalScoreChanges: store.actionLog.scoreChangeCount
        )
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func undo() {
        guard !scoringLocked, store.undo() else { return }
        publish()
        undoToastToken = UUID()
    }

    private func restartMatch() {
        guard !scoringLocked, finalizeNineBall() else { return }
        resumeStore.clear()
        finishTask?.cancel()
        let restartedAt = Date()
        // `.resetScores` 已由 binding 的 resetsActionLog 清空动作日志与撤销栈。
        guard case .accepted(_, _) = store.dispatch(.resetScores, at: restartedAt) else { return }
        store.beginRemoteMatch(at: restartedAt)
        // 新一局重新允许落库与续玩草稿写入。
        store.clearSavedRecord()
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

    private func applyAuthoritativeNineBall(_ remote: NineBallChaseState) {
        // 对端权威状态是撤销/重放边界：安装后本机不再能撤销到旧历史。
        store.rebase(to: remote, status: remote.finished ? .finished : .live)
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
        finishUndoAvailable = store.canUndo
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

    @discardableResult
    private func finalizeNineBall(manualEnd: Bool = false) -> Bool {
        guard state.finished, !didSaveFinishedRecord, !scoringLocked else { return true }
        finishUndoAvailable = false
        let saved: Bool
        if linkedSessionId != nil {
            saved = linkService.publishMatchFinished(
                snapshot: .nineBall(state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: winnerSide(),
                manualEnd: manualEnd,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: store.actionLog.scoreChangeCount,
                detailedActions: store.actionLog.detailedActions,
                participantNames: (0..<state.playerCount).map { displayName(at: $0) }
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

    private func undoFinishedNineBall() {
        guard finishUndoAvailable else { return }
        finishTask?.cancel()
        // 完赛撤销窗内同样走宿主撤销：回到完赛前的比分与动作日志。
        guard store.undo() else { return }
        showFinishedOverlay = false
        finishUndoAvailable = false
        didSaveFinishedRecord = false
        publish()
        undoToastToken = UUID()
    }

    private func exitNineBall() {
        if let linkedSessionId { linkService.exitScoreboard(sessionId: linkedSessionId) }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        let scores = Array(state.playerPoints.prefix(state.playerCount))
        if state.finished {
            if didSaveFinishedRecord { resumeStore.clear() }
            return
        }
        guard scores.contains(where: { $0 != 0 }) || store.canUndo else {
            resumeStore.clear()
            return
        }
        _ = store.persistResumeSession(
            into: resumeStore,
            link: linkService.resumeContext,
            startedAt: matchStartTime,
            payload: .nineBall(bundle: store.resumeBundle())
        )
    }

    private var hasNineBallProgress: Bool {
        Array(state.playerPoints.prefix(state.playerCount)).contains(where: { $0 != 0 })
            || store.canUndo || state.finished
    }

}

