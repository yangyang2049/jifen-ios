import LinkCore
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
    @State private var lastAppliedRemoteRevision: UInt64?
    @State private var lastAppliedRemoteGeneration: UInt64?

    @State private var showRecordSaveFailure = false
    @State private var leftName: String
    @State private var rightName: String
    /// 通用同步宿主：比分、撤销栈、时间线与动作日志只有这一处真相。
    @State private var store: WatchReducerSessionStore<EightBallReducer>
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
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
    private var scoringLocked: Bool { linkedSessionId != nil && !linkService.canEditLinkedMatch }
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
                    }
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
            applyAuthoritativeEightBall(remote)
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
        // 比分、撤销帧与动作日志投影全部由宿主同步完成。
        guard case .accepted(_, _) = store.dispatch(.addRack(side)) else { return }
        if state.finished {
            finishMatch(manual: false)
        } else {
            publish(manualEnd: false)
        }
    }

    private func finishMatch(manual: Bool) {
        if manual, !state.finished {
            guard case .accepted(_, _) = store.dispatch(.finishMatch) else { return }
        }
        publish(manualEnd: manual)
        beginEightBallFinish(manualEnd: manual)
    }

    private func publish(manualEnd: Bool) {
        guard linkedSessionId != nil, linkService.canEditLinkedMatch else { return }
        linkService.publishSnapshot(
            .eightBall(state),
            detailedActions: store.actionLog.detailedActions,
            participantNames: [leftName, rightName]
        )
    }

    private func saveLocalRecordIfNeeded() -> Bool {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return true }
        guard state.finished || state.leftPoints + state.rightPoints > 0 else { return true }
        return store.saveFinishedRecord(
            into: resumeStore,
            gameType: .eightBall,
            recordID: "w_\(UUID().uuidString)",
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
        guard !scoringLocked, store.undo() else { return }
        publish(manualEnd: false)
        undoToastToken = UUID()
    }

    private func restartMatch() {
        guard !scoringLocked, finalizeEightBall() else { return }
        resumeStore.clear()
        finishTask?.cancel()
        let restartedAt = Date()
        // `.reset` 已由 binding 的 resetsActionLog 清空动作日志与撤销栈。
        guard case .accepted(_, _) = store.dispatch(.reset, at: restartedAt) else { return }
        store.beginRemoteMatch(at: restartedAt)
        // 新一局重新允许落库与续玩草稿写入。
        store.clearSavedRecord()
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
        if let names = linkService.activeParticipantNames, names.count >= 2 {
            let remoteLeft = names[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteRight = names[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !remoteLeft.isEmpty { leftName = remoteLeft }
            if !remoteRight.isEmpty { rightName = remoteRight }
        }
        // 对端权威状态是撤销/重放边界：安装后本机不再能撤销到旧历史。
        store.rebase(to: remote, status: remote.finished ? .finished : .live)
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
                totalScoreChanges: store.actionLog.scoreChangeCount,
                detailedActions: store.actionLog.detailedActions,
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
        guard finishUndoAvailable else { return }
        finishTask?.cancel()
        // 完赛撤销窗内同样走宿主撤销：回到完赛前的比分与动作日志。
        guard store.undo() else { return }
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
                || store.canUndo else {
            resumeStore.clear()
            return
        }
        _ = store.persistResumeSession(
            into: resumeStore,
            link: linkService.resumeContext,
            startedAt: matchStartTime,
            payload: .eightBall(
                bundle: store.resumeBundle(),
                leftName: leftName,
                rightName: rightName
            )
        )
    }

    private var hasEightBallProgress: Bool {
        state.leftPoints != 0 || state.rightPoints != 0 || store.canUndo || state.finished
    }
}

