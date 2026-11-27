import LinkCore
import LinkSync
import RecordCore
import ScoreCore
import SessionCore
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
    @State private var linkedMatchHandle: LinkedMatchHandle?

    @State private var showRecordSaveFailure = false
    @State private var leftName: String
    @State private var rightName: String
    /// 通用同步宿主：比分、撤销栈、时间线与动作日志只有这一处真相。
    @State private var store: WatchReducerSessionStore<EightBallReducer>
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var localRecordID = "w_\(UUID().uuidString)"
    @State private var scoreboardLayout: String = "horizontal"
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
    @State private var undoToastToken: UUID?

    init(
        initialState: EightBallState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil,
        resumeBundle: WatchEightBallResumeBundle? = nil,
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve(for: .eightBall)
        let resolvedLeft = leftName ?? defaults.left
        let resolvedRight = rightName ?? defaults.right
        self.linkedSessionId = linkedSessionId
        _leftName = State(initialValue: resolvedLeft)
        _rightName = State(initialValue: resolvedRight)
        let startedAt = resumedStartTime ?? Date()
        let binding = WatchBoardBindings.eightBall()
        let actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        if let resumeBundle {
            // 续玩只走标准 bundle：比分、撤销帧与时间线一并恢复。
            _store = State(initialValue: WatchReducerSessionStore(
                resumeBundle: resumeBundle,
                reducer: EightBallReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        } else {
            let seed = initialState ?? EightBallState.initial()
            let descriptor = ScoreboardKernelRegistry.descriptor(for: .eightBall)
            let session = ScoreSession<EightBallState, EightBallEvent>(
                gameType: .eightBall,
                ruleFamily: descriptor.ruleFamily,
                reducerType: descriptor.reducerType,
                state: seed,
                participants: [
                    .init(id: TeamID.team0.rawValue, name: resolvedLeft, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: resolvedRight, role: "team")
                ]
            )
            _store = State(initialValue: WatchReducerSessionStore(
                seedSession: session,
                reducer: EightBallReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        }
        _matchStartTime = State(initialValue: startedAt)
    }

    private var state: EightBallState { store.state }
    private var linkedMatchUnavailable: Bool {
        guard linkedSessionId != nil else { return false }
        guard let linkedMatchHandle, linkedMatchHandle == linkService.activeHandle,
              store.linkedIntentUpdate?.handle == linkedMatchHandle else { return true }
        return !linkService.canEditLinkedMatch
    }

    private var scoringLocked: Bool {
        linkedMatchUnavailable || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed
    }

    private var canPlayAgain: Bool {
        guard linkedSessionId != nil else { return true }
        guard let handle = linkedMatchHandle, !linkedMatchUnavailable, store.isLinkedFinishConfirmed else { return false }
        return store.savedRecordID == "w_\(handle.matchId.uuidString)"
            && !linkService.intentSync.hasPendingOperations(for: handle)
    }

    private var linkedMenuActions: [WatchMenuExtraAction] {
        guard linkedSessionId != nil, !linkedMatchUnavailable else { return [] }
        return [
            WatchMenuExtraAction(
                id: "sync-linked-scores",
                title: NSLocalizedString("linked_score_resync", value: "Sync score", comment: ""),
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                showMenu = false
                linkService.syncLinkedScores()
            },
            WatchMenuExtraAction(
                id: "end-score-link",
                title: NSLocalizedString("linked_score_end", value: "End link", comment: ""),
                systemImage: "link.badge.minus"
            ) {
                guard !store.isPendingLinkedFinish else { return }
                showMenu = false
                linkService.leaveSession()
            }
        ]
    }
    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }
    private var showsTargetBadge: Bool { !showMenu && !showFinishedOverlay && !store.isPendingLinkedFinish }
    private static let targetBadgeHeight: CGFloat = 24
    private static let targetClearance: CGFloat = targetBadgeHeight / 2 + 6

    private var pendingFinishUndoAction: (() -> Void)? {
        guard store.canUndo else { return nil }
        return { undo() }
    }

    @ViewBuilder
    private var finishLayer: some View {
        if store.isPendingLinkedFinish {
            WatchLinkedFinishWaitingOverlay(onSync: { linkService.syncLinkedScores() }, onUndo: pendingFinishUndoAction)
        } else if showFinishedOverlay {
            WatchFinishedOverlay(
                title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                scoreItems: [
                    WatchFinishedScoreItem(name: leftName, score: state.leftPoints),
                    WatchFinishedScoreItem(name: rightName, score: state.rightPoints)
                ],
                undoAvailable: linkedSessionId == nil && finishUndoAvailable,
                canPlayAgain: canPlayAgain,
                onUndo: undoFinishedEightBall,
                onPlayAgain: restartMatch,
                onExit: {
                    if linkedSessionId == nil, !finalizeEightBall() { return }
                    exitEightBall()
                }
            )
        }
    }

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
                        if linkedSessionId == nil {
                            confirmation = .reset
                        } else {
                            restartMatch()
                        }
                    },
                    extraActions: linkedMenuActions
                )
            }
            finishLayer
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
        .onChange(of: linkService.intentSync.update, initial: true) { _, update in
            applyLinkedUpdate(update)
        }
        .onChange(of: state) { _, _ in
            persistResumeSession()
        }
        .onDisappear {
            finishTask?.cancel()
            if linkedSessionId == nil, state.finished { finalizeEightBall() }
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
        guard !scoringLocked, !state.finished, case .accepted = store.dispatch(.addRack(side)) else { return }
        if linkedSessionId == nil, state.finished { beginEightBallFinish(manualEnd: false) }
    }

    private func finishMatch() {
        guard !scoringLocked, !state.finished else { return }
        if linkedSessionId != nil {
            if store.requestLinkedFinish() { persistResumeSession() }
            return
        }
        guard case .accepted = store.dispatch(.finishMatch) else { return }
        beginEightBallFinish(manualEnd: true)
    }

    private func saveLocalRecordIfNeeded() -> Bool {
        guard linkedSessionId == nil, store.savedRecordID == nil else { return true }
        guard state.finished || state.leftPoints + state.rightPoints > 0 else { return true }
        return store.saveFinishedRecord(
            into: resumeStore,
            gameType: .eightBall,
            recordID: localRecordID,
            endTime: Date(),
            participantNames: [leftName, rightName],
            totalScoreChanges: store.actionLog.scoreChangeCount
        )
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
        guard !linkedMatchUnavailable, !store.isLinkedFinishConfirmed, store.undo() else { return }
        undoToastToken = UUID()
    }

    private func restartMatch() {
        if linkedSessionId != nil {
            if canPlayAgain {
                store.requestLinkedNextMatch()
            } else if !scoringLocked, !state.finished {
                linkService.lastLinkErrorMessage = NSLocalizedString(
                    "linked_score_reset_unavailable",
                    value: "Finish this match before starting a new one.",
                    comment: "Live linked matches cannot be reset"
                )
            }
            return
        }
        guard finalizeEightBall() else { return }
        resumeStore.clear()
        finishTask?.cancel()
        let restartedAt = Date()
        // `.reset` 已由 binding 的 resetsActionLog 清空动作日志与撤销栈。
        guard case .accepted(_, _) = store.dispatch(.reset, at: restartedAt) else { return }
        store.beginRemoteMatch(at: restartedAt)
        // 新一局重新允许落库与续玩草稿写入。
        store.clearSavedRecord()
        localRecordID = "w_\(UUID().uuidString)"
        matchStartTime = restartedAt
        showFinishedOverlay = false
        finishUndoAvailable = false
    }

    private var interactionsEnabled: Bool {
        !scoringLocked && !state.finished && !showMenu && confirmation == nil && !showFinishedOverlay
    }

    private var menuGesturesEnabled: Bool {
        !store.isPendingLinkedFinish && !state.finished && !showMenu && confirmation == nil && !showFinishedOverlay
    }

    private func applyLinkedUpdate(_ update: WatchLinkedIntentUpdate?) {
        guard let linkedSessionId, let update, update.handle.sessionId == linkedSessionId,
              update.handle == linkService.activeHandle, case .eightBall = update.displayedSnapshot else { return }
        let previous = state
        let wasConfirmed = store.isLinkedFinishConfirmed
        if let linkedMatchHandle {
            guard linkedMatchHandle == update.handle else { return }
            store.applyLinkedIntentUpdate(update)
        } else {
            linkedMatchHandle = update.handle
            store.attachLinkedMatch(
                update.handle, sync: linkService.intentSync, intent: { .eightBall($0) },
                state: { $0.eightBallState }
            )
        }
        guard store.linkedIntentUpdate?.presentationSequence == update.presentationSequence else { return }
        matchStartTime = store.startedAt
        if let names = linkService.activeParticipantNames, names.count >= 2 {
            let remoteLeft = names[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteRight = names[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !remoteLeft.isEmpty { leftName = remoteLeft }
            if !remoteRight.isEmpty { rightName = remoteRight }
        }
        if previous != state || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed {
            showMenu = false
            confirmation = nil
        }
        if store.isPendingLinkedFinish {
            finishTask?.cancel()
            showFinishedOverlay = false
            finishUndoAvailable = false
        } else if store.isLinkedFinishConfirmed {
            if !wasConfirmed { beginEightBallRemoteFinishPresentation() }
        } else if showFinishedOverlay || previous.finished {
            finishTask?.cancel()
            showFinishedOverlay = false
            finishUndoAvailable = false
        }
        persistResumeSession()
    }

    private func handicapText(for side: MatchSide) -> String? {
        WatchEightBallScorePresentation.handicapText(state: state, side: side)
    }

    private func confirmEightBall(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish:
            finishMatch()
        case .reset:
            restartMatch()
        }
    }

    private func beginEightBallFinish(manualEnd: Bool) {
        finishTask?.cancel()
        showMenu = false
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
            finalizeEightBall()
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
    private func finalizeEightBall() -> Bool {
        guard linkedSessionId == nil, state.finished, store.savedRecordID == nil else { return true }
        finishUndoAvailable = false
        guard saveLocalRecordIfNeeded() else {
            showRecordSaveFailure = true
            return false
        }
        resumeStore.clear()
        return true
    }

    private func undoFinishedEightBall() {
        guard linkedSessionId == nil, finishUndoAvailable else { return }
        finishTask?.cancel()
        // 完赛撤销窗内同样走宿主撤销：回到完赛前的比分与动作日志。
        guard store.undo() else { return }
        showFinishedOverlay = false
        finishUndoAvailable = false
        undoToastToken = UUID()
    }

    private func exitEightBall() {
        guard !store.isPendingLinkedFinish else { return }
        if let handle = linkedMatchHandle, handle == linkService.activeHandle {
            linkService.exitScoreboard(sessionId: handle.sessionId)
        }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        let context: WatchLinkResumeContext?
        if linkedSessionId != nil {
            guard let handle = linkedMatchHandle, handle == linkService.activeHandle,
                  let linkedContext = linkService.resumeContext, linkedContext.handle == handle else { return }
            if store.savedRecordID == "w_\(handle.matchId.uuidString)" {
                if resumeStore.session?.linkHandle == handle { resumeStore.clear() }
                return
            }
            context = linkedContext
        } else {
            if state.finished {
                if store.savedRecordID != nil, resumeStore.session?.linkHandle == nil { resumeStore.clear() }
                return
            }
            context = nil
        }
        guard hasEightBallProgress || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed else {
            if linkedSessionId == nil, resumeStore.session?.linkHandle == nil { resumeStore.clear() }
            return
        }
        store.persistResumeSession(
            into: resumeStore, link: context, startedAt: matchStartTime,
            payload: .eightBall(bundle: store.resumeBundle(), leftName: leftName, rightName: rightName)
        )
    }

    private var hasEightBallProgress: Bool {
        state.leftPoints != 0 || state.rightPoints != 0 || store.canUndo || state.finished
    }
}

