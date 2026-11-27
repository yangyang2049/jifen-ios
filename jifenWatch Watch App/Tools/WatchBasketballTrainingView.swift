import LinkCore
import LinkSync
import ScoreCore
import SessionCore
import RecordCore
import SwiftUI

struct WatchBasketballTrainingView: View {
    private struct PendingFinish {
        let endTime: Date
        let recordID: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(WatchResumeSessionStore.self) private var resumeStore
    @Environment(WatchLinkService.self) private var linkService

    let mode: ShotTrainingMode
    let linkedSessionId: UUID?

    @State private var showRecordSaveFailure = false
    @State private var pendingFinish: PendingFinish?
    /// 通用同步宿主：尝试记录、撤销与完赛门闩都在这里，取消保存后棋盘不锁死。
    @State private var store: WatchReducerSessionStore<ShotTrainingReducer>
    @State private var showMenu = false
    @State private var showEndDialog = false
    @State private var toastMessage: String?
    @State private var recentShotID: UUID?
    @State private var scoreboardLayout = "horizontal"
    @State private var suppressTapAfterLongPress = false
    @State private var showFreeGuide = false
    @State private var confirmation: WatchScoreboardConfirmation?

    init(
        mode: ShotTrainingMode,
        linkedSessionId: UUID? = nil,
        resumeBundle: WatchShotTrainingResumeBundle? = nil,
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.mode = mode
        self.linkedSessionId = linkedSessionId
        let startedAt = resumedStartTime ?? Date()
        let binding = WatchBoardBindings.shotTraining(mode: mode)
        let actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        if let resumeBundle {
            _store = State(initialValue: WatchReducerSessionStore(
                resumeBundle: resumeBundle,
                reducer: ShotTrainingReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        } else {
            let state = ShotTrainingState(mode: mode, startTime: startedAt)
            let session = ScoreSession<ShotTrainingState, ShotTrainingEvent>(
                gameType: .basketballTraining,
                ruleFamily: ScoreboardKernelRegistry.descriptor(for: .basketballTraining).ruleFamily,
                reducerType: ScoreboardKernelRegistry.descriptor(for: .basketballTraining).reducerType,
                state: state
            )
            _store = State(initialValue: WatchReducerSessionStore(
                seedSession: session,
                reducer: ShotTrainingReducer(),
                binding: binding,
                actionLog: actionLog,
                startedAt: startedAt
            ))
        }
    }

    // MARK: - 由 Reducer State 派生的展示口径

    private var history: [ShotTrainingShot] { store.state.shots }
    private var earlierCounts: ShotTrainingCounts { store.state.earlierCounts }
    private var startTime: Date { store.state.startTime }
    private var savedRecordID: String? { store.savedRecordID }
    private var showsFinishOverlay: Bool {
        showEndDialog || (linkedSessionId != nil && (store.isPendingLinkedFinish || store.isLinkedFinishConfirmed))
    }

    var body: some View {
        ZStack {
            board

            if showMenu {
                trainingMenuOverlay
            }
            if showsFinishOverlay { endOverlay }
            if showFreeGuide {
                freeGuideOverlay
            }
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    titleOverride: confirmation == .finish
                        ? NSLocalizedString(
                            "watch_training_finish_confirm_title",
                            value: "结束训练？",
                            comment: ""
                        )
                        : nil,
                    messageOverride: confirmation == .finish
                        ? NSLocalizedString(
                            "watch_training_finish_confirm_message",
                            value: "将结束并保存本次训练。",
                            comment: ""
                        )
                        : nil,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirmTraining(confirmation) }
                )
            }
            if let toastMessage {
                VStack {
                    Spacer()
                    WatchToastView(message: toastMessage)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: !showMenu && !showsFinishOverlay && confirmation == nil,
            onMenu: { showMenu = true },
            onUndo: undo,
            onExit: exitBoard
        )
        .watchFinishSaveFailure(
            isPresented: $showRecordSaveFailure,
            onCancel: cancelFinishTraining,
            retry: finishTraining
        )
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
            if mode == .free {
                showFreeGuide = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showFreeGuide = false
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .onChange(of: history) { _, _ in
            persistResumeSession()
        }
        .onDisappear {
            persistResumeSession()
        }
        .onChange(of: linkService.intentSync.update, initial: true) { _, update in
            applyLinkedUpdate(update)
        }
    }

    private var linkedHandle: LinkedMatchHandle? {
        guard let linkedSessionId, let handle = linkService.activeHandle, handle.sessionId == linkedSessionId else { return nil }
        return handle
    }

    private var linkedRecordSaved: Bool {
        guard let handle = linkedHandle, store.linkedIntentUpdate?.handle == handle else { return false }
        return store.isLinkedFinishConfirmed && savedRecordID == "w_\(handle.matchId.uuidString)"
    }

    private var scoringLocked: Bool {
        guard linkedSessionId != nil else { return false }
        guard let handle = linkedHandle, store.linkedIntentUpdate?.handle == handle else { return true }
        return !linkService.canEditLinkedMatch || store.isPendingLinkedFinish
    }

    private func applyLinkedUpdate(_ update: WatchLinkedIntentUpdate?) {
        guard let handle = linkedHandle, let update, update.handle == handle,
              case .basketballTraining(let state) = update.displayedSnapshot else { return }
        let previous = store.state
        if store.linkedIntentUpdate?.handle != handle {
            if store.isUsingLinkedIntents {
                let descriptor = ScoreboardKernelRegistry.descriptor(for: .basketballTraining)
                let startedAt = Date(timeIntervalSince1970: Double(update.startEpochMilliseconds) / 1_000)
                let seed = ScoreSession<ShotTrainingState, ShotTrainingEvent>(
                    gameType: .basketballTraining, ruleFamily: descriptor.ruleFamily,
                    reducerType: descriptor.reducerType, state: state,
                    status: state.finished ? .finished : .live
                )
                store = WatchReducerSessionStore(
                    seedSession: seed, reducer: ShotTrainingReducer(),
                    binding: WatchBoardBindings.shotTraining(mode: state.mode),
                    actionLog: WatchScoreActionLog(startedAt: startedAt), startedAt: startedAt
                )
            }
            store.attachLinkedMatch(handle, sync: linkService.intentSync, intent: LinkedScoreboardIntent.shotTraining) {
                if case .basketballTraining(let state) = $0 { return state }
                return nil
            }
            recentShotID = nil
        } else if !store.applyLinkedIntentUpdate(update) {
            return
        }
        if previous != state || showsFinishOverlay {
            confirmation = nil
            showMenu = false
            showFreeGuide = false
            recentShotID = nil
        }
        persistResumeSession()
    }

    private func cancelFinishTraining() {
        guard linkedSessionId == nil, pendingFinish != nil else { return }
        resumeStore.cancelPendingTrainingFinish(startedAt: startTime)
        pendingFinish = nil
        showRecordSaveFailure = false
        persistResumeSession()
    }

    private func exitBoard() {
        if let linkedSessionId { linkService.exitScoreboard(sessionId: linkedSessionId) }
        persistResumeSession()
        dismiss()
    }

    @ViewBuilder
    private var board: some View {
        if let points = mode.fixedPoints {
            fixedBoard(points: points)
        } else {
            freeBoard
        }
    }

    private var trainingMenuOverlay: some View {
        ZStack(alignment: .bottom) {
            WatchTheme.fullScreenScrim
                .ignoresSafeArea()
                .onTapGesture { showMenu = false }

            VStack(spacing: WatchLayout.isCompactScreen ? 5 : 6) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: WatchLayout.isCompactScreen ? 5 : 6
                ) {
                    WatchMenuGridButton(
                        title: NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                        systemImage: "arrow.uturn.backward"
                    ) {
                        guard !scoringLocked else { return }
                        showMenu = false
                        undo()
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                        systemImage: "arrow.counterclockwise"
                    ) {
                        guard !scoringLocked else { return }
                        showMenu = false
                        if linkedSessionId == nil {
                            confirmation = .reset
                        } else {
                            showToast(NSLocalizedString(
                                "linked_score_reset_unavailable", value: "联动计分期间请先结束本场，再开始新一局。", comment: ""
                            ))
                        }
                    }
                }
                if linkedHandle != nil {
                    WatchMenuGridButton(
                        title: NSLocalizedString("linked_score_resync", value: "Sync score", comment: ""),
                        systemImage: "arrow.clockwise"
                    ) {
                        showMenu = false
                        linkService.syncLinkedScores()
                    }
                }
                WatchMenuGridButton(
                    title: NSLocalizedString("watch_bb_end_training", value: "结束训练", comment: ""),
                    systemImage: "flag.checkered",
                    background: WatchTheme.dangerRed
                ) {
                    guard !scoringLocked else { return }
                    showMenu = false
                    confirmation = .finish
                }
                WatchMenuCloseButton { showMenu = false }
            }
            .padding(.horizontal, WatchLayout.isCompactScreen ? 20 : 26)
            .padding(.top, WatchLayout.isCompactScreen ? 8 : 12)
            .padding(.bottom, WatchLayout.isCompactScreen ? 5 : 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(WatchTheme.panelScrim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func fixedBoard(points: Int) -> some View {
        GeometryReader { proxy in
            let fullWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            Group {
                if scoreboardLayout == "horizontal" {
                    HStack(spacing: 0) {
                        trainingCell(
                            points: points,
                            made: false,
                            size: CGSize(width: fullWidth / 2, height: fullHeight)
                        )
                        trainingCell(
                            points: points,
                            made: true,
                            size: CGSize(width: fullWidth / 2, height: fullHeight)
                        )
                    }
                } else {
                    VStack(spacing: 0) {
                        trainingCell(
                            points: points,
                            made: false,
                            size: CGSize(width: fullWidth, height: fullHeight / 2),
                            verticalTopCell: true
                        )
                        trainingCell(
                            points: points,
                            made: true,
                            size: CGSize(width: fullWidth, height: fullHeight / 2)
                        )
                    }
                }
            }
            .frame(width: fullWidth, height: fullHeight)
            .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
            .overlay(alignment: scoreboardLayout == "vertical" ? .topLeading : .top) {
                if !showMenu && !showsFinishOverlay {
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("watch_training_point_value", value: "%d分", comment: ""),
                            points
                        )
                    )
                    .font(WatchScoreTypography.secondaryScore(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(WatchTheme.panelScrim)
                    .clipShape(Capsule())
                    .padding(
                        .top,
                        scoreboardLayout == "vertical"
                            ? max(6, (fullHeight / 2 - 27) / 2)  // 顶半格垂直居中：27pt ≈ 胶囊高度
                            : 6
                    )
                    .padding(.leading, scoreboardLayout == "vertical" ? 10 : 0)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if !scoringLocked && !showMenu && !showsFinishOverlay && confirmation == nil {
                    Button {
                        WatchHaptics.shared.play(.light)
                        confirmation = .finish
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(WatchTheme.successGreen)
                            .frame(width: 40, height: 40)
                            .background(WatchTheme.panelScrim)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        NSLocalizedString("watch_bb_end_training", value: "结束训练", comment: "")
                    )
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var freeBoard: some View {
        GeometryReader { proxy in
            let fullWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            Group {
                if scoreboardLayout == "horizontal" {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            trainingCell(points: 1, made: false, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 2, made: false, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 3, made: false, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                        }
                        VStack(spacing: 0) {
                            trainingCell(points: 1, made: true, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 2, made: true, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 3, made: true, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            trainingCell(points: 1, made: false, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 2, made: false, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 3, made: false, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                        }
                        HStack(spacing: 0) {
                            trainingCell(points: 1, made: true, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 2, made: true, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 3, made: true, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                        }
                    }
                }
            }
            .frame(width: fullWidth, height: fullHeight)
            .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
            .overlay {
                freeDivisionLines
                    .allowsHitTesting(false)
            }
            .overlay {
                freePointBadges
                    .allowsHitTesting(false)
            }
        }
    }

    private func trainingCell(
        points: Int,
        made: Bool,
        size: CGSize,
        verticalTopCell: Bool = false
    ) -> some View {
        let count = shotCount(points: points, made: made)
        let isRecent = recentShotID != nil && history.last?.id == recentShotID
            && history.last?.points == points
            && history.last?.made == made
        let outcome = made
            ? NSLocalizedString("watch_training_made", value: "命中", comment: "")
            : NSLocalizedString("watch_training_miss", value: "未中", comment: "")
        let pointsLabel = String.localizedStringWithFormat(
            NSLocalizedString("watch_training_point_value", value: "%d分", comment: ""),
            points
        )
        return Button {
            guard !showMenu, !showsFinishOverlay, confirmation == nil,
                  !suppressTapAfterLongPress else { return }
            addShot(points: points, made: made)
        } label: {
            // 竖板顶格：标签与大分数靠右，给左上角的「N分」胶囊让位，两者共用一条顶部中心线。
            VStack(spacing: 1) {
                if mode != .free {
                    Text(outcome)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                }
                Text("\(count)")
                    .font(WatchScoreTypography.primaryScore(size: mode == .free ? 30 : 64))
                    .foregroundStyle(.white)
            }
            .padding(.trailing, verticalTopCell ? 6 : 0)
            .padding(.leading, verticalTopCell ? 74 : 0)
            .offset(y: verticalTopCell ? 16 : 0)
            .frame(
                width: size.width,
                height: size.height,
                alignment: verticalTopCell ? .trailing : .center
            )
            .background(made ? WatchTheme.successGreen : Color(hex: 0xD84343))
            .overlay {
                if isRecent {
                    Color.white.opacity(0.14)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(scoringLocked)
        .accessibilityLabel(mode == .free ? "\(pointsLabel) \(outcome)" : outcome)
        .accessibilityValue(String(count))
        .accessibilityIdentifier("watch_training_\(made ? "made" : "miss")_\(points)")
    }

    private var endOverlay: some View {
        let compact = WatchLayout.isCompactScreen
        return WatchFullScreenOverlay(scrim: Color.black.opacity(0.76)) { _, _ in
            VStack(spacing: compact ? 5 : 8) {
                Text(store.isPendingLinkedFinish
                    ? NSLocalizedString("linked_score_pending_finish", value: "Waiting for sync", comment: "")
                    : NSLocalizedString("watch_bb_hit_rate", value: "命中率", comment: ""))
                    .font(.system(size: compact ? 12 : 14))
                    .foregroundStyle(WatchTheme.secondaryText)
                    .accessibilityIdentifier(store.isPendingLinkedFinish ? "linked_score_pending_finish" : "watch_training_hit_rate")
                Text(hitRateText)
                    .font(WatchScoreTypography.secondaryScore(
                        size: compact ? 17 : 19,
                        weight: .bold
                    ))
                    .foregroundStyle(WatchTheme.accent)
                if mode == .free {
                    VStack(spacing: 2) {
                        ForEach(1...3, id: \.self) { points in
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString(
                                    "watch_training_breakdown_format",
                                    value: "%d分  %d/%d",
                                    comment: ""
                                ),
                                points,
                                shotCount(points: points, made: true),
                                shotCount(points: points, made: true) + shotCount(points: points, made: false)
                            ))
                            .font(WatchScoreTypography.secondaryScore(size: 10))
                            .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                }
                VStack(spacing: compact ? 6 : 8) {
                    if linkedSessionId == nil || linkedRecordSaved {
                        Button {
                            restartAfterFinish()
                        } label: {
                            Text(NSLocalizedString("watch_bb_restart", value: "再来一次", comment: ""))
                                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: WatchLayout.overlayActionButtonWidth, height: compact ? 34 : 38)
                        }
                        .buttonStyle(.plain)
                        .background(WatchTheme.successGreen)
                        .clipShape(Capsule())
                        .disabled(scoringLocked)
                    } else if linkedHandle != nil {
                        WatchMenuGridButton(
                            title: NSLocalizedString("linked_score_resync", value: "Sync score", comment: ""),
                            systemImage: "arrow.clockwise"
                        ) {
                            linkService.syncLinkedScores()
                        }
                    }
                    Button {
                        exitBoard()
                    } label: {
                        Text(NSLocalizedString("exit", value: "退出", comment: ""))
                            .font(.system(size: compact ? 13 : 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(
                                width: WatchLayout.overlayActionButtonWidth,
                                height: compact ? 34 : 38
                            )
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .clipShape(Capsule())
                }
                .padding(.top, compact ? 4 : 8)
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.top, compact ? 22 : 28)
            .padding(.bottom, compact ? 8 : 12)
        }
    }

    private var totalAttempts: Int {
        earlierCounts.attempts + history.count
    }

    private var totalMade: Int {
        earlierCounts.made + history.lazy.filter(\.made).count
    }

    private var hitRateText: String {
        guard totalAttempts > 0 else { return "0/0 = 0%" }
        let percentage = Int((Double(totalMade) / Double(totalAttempts) * 100).rounded())
        return "\(totalMade)/\(totalAttempts) = \(percentage)%"
    }

    private func shotCount(points: Int, made: Bool) -> Int {
        earlierCounts.count(points: points, made: made)
            + history.lazy.filter { $0.points == points && $0.made == made }.count
    }

    private func addShot(points: Int, made: Bool) {
        guard !scoringLocked, pendingFinish == nil, !showsFinishOverlay, savedRecordID == nil else { return }
        guard case .accepted(_, _) = store.dispatch(.recordShot(points: points, made: made)) else { return }
        let shotID = store.state.shots.last?.id
        recentShotID = shotID
        WatchHaptics.shared.play(made ? .score : .strong)
        if let shotID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if recentShotID == shotID {
                    recentShotID = nil
                }
            }
        }
    }

    private func undo() {
        guard !scoringLocked, pendingFinish == nil, !showsFinishOverlay, savedRecordID == nil else { return }
        if linkedSessionId != nil {
            guard store.undo() else { return }
        } else {
            guard case .accepted(_, _) = store.dispatch(.undoLastShot) else { return }
        }
        recentShotID = nil
        WatchHaptics.shared.play(.undo)
        showToast(NSLocalizedString("watch_undo_toast", value: "已撤销", comment: ""))
    }

    private func reset() {
        guard linkedSessionId == nil, !scoringLocked, pendingFinish == nil, !showsFinishOverlay else { return }
        resumeStore.clear()
        store.clearSavedRecord()
        guard case .accepted(_, _) = store.dispatch(.reset) else { return }
        recentShotID = nil
    }

    private func restartAfterFinish() {
        guard !scoringLocked else { return }
        if linkedSessionId != nil {
            if linkedRecordSaved { store.requestLinkedNextMatch() }
            return
        }
        resumeStore.clear()
        store.clearSavedRecord()
        guard case .accepted(_, _) = store.dispatch(.reset) else { return }
        store.beginRemoteMatch(at: Date())
        recentShotID = nil
        showEndDialog = false
    }

    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == text {
                toastMessage = nil
            }
        }
    }

    private func finishTraining() {
        guard !scoringLocked else { return }
        guard savedRecordID == nil else {
            showEndDialog = true
            return
        }
        if linkedSessionId != nil {
            store.requestLinkedFinish()
            persistResumeSession()
            return
        }

        // Keep the live reducer state until the standalone record is saved.
        // The same record and finish time are reused when a write is retried.
        let finish = pendingFinish ?? PendingFinish(
            endTime: Date(),
            recordID: "watch-basketballTraining-\(UUID().uuidString)"
        )
        pendingFinish = finish
        let endTime = finish.endTime
        let candidate = ShotTrainingReducer().reduce(
            state: store.state, intent: .finish, at: epochMilliseconds(endTime)
        )
        guard candidate.accepted else {
            pendingFinish = nil
            return
        }
        let modeName = mode.fixedPoints.map(String.init) ?? "free"
        var misses = store.state.earlierCounts.missed
        var made = store.state.earlierCounts.made
        var actions = [
            DetailedScoreAction(
                type: .matchStarted,
                epochMilliseconds: epochMilliseconds(startTime),
                scores: [0, 0],
                operationCode: "training_start",
                summary: "training_start"
            )
        ]
        actions.append(contentsOf: store.state.shots.map { shot in
            if shot.made {
                made += 1
            } else {
                misses += 1
            }
            let code = trainingActionDescription(for: shot)
            return DetailedScoreAction(
                type: shot.made ? .scoreChanged : .stateChanged,
                epochMilliseconds: epochMilliseconds(shot.timestamp),
                team: shot.made ? .team2 : .team1,
                scores: [misses, made],
                scoreChange: shot.made ? shot.points : 0,
                operationCode: code,
                summary: code
            )
        })
        let percentage = totalAttempts == 0
            ? 0
            : Int((Double(made) / Double(totalAttempts) * 100).rounded())
        actions.append(
            DetailedScoreAction(
                type: .matchFinished,
                epochMilliseconds: epochMilliseconds(endTime),
                scores: [misses, made],
                operationCode: "training_finished",
                summary: "training_rate_\(percentage)"
            )
        )
        var projectConfiguration = [
            "type": "basketball_training",
            "gameMode": mode.fixedPoints.map { "\($0)pt" } ?? "free",
            "basketballTrainingMode": mode.fixedPoints == nil ? "mixed" : "fixed",
            "basketballTrainingScoringMode": mode.rawValue,
            "trainingMode": modeName
        ]
        if let fixedPoints = mode.fixedPoints {
            projectConfiguration["targetScore"] = String(fixedPoints)
        }
        guard let record = WatchScoreboardRecord(
            localSnapshot: .basketballTraining(candidate.state),
            gameType: .basketballTraining,
            id: finish.recordID,
            startTime: startTime,
            endTime: endTime,
            participantNames: [
                NSLocalizedString("watch_training_miss", value: "未中", comment: ""),
                NSLocalizedString("watch_training_made", value: "命中", comment: "")
            ],
            detailedActions: actions,
            totalScoreChanges: totalAttempts,
            additionalConfiguration: projectConfiguration
        ), resumeStore.saveFinishedRecord(record) else {
            showRecordSaveFailure = true
            return
        }
        resumeStore.clear()
        pendingFinish = nil
        _ = store.dispatch(.finish, at: endTime)
        store.markRecordSaved(finish.recordID)
        showEndDialog = true
    }

    /// 续玩统一走标准 bundle：出手历史与 earlierCounts 折叠都在 Reducer State 里。
    private func persistResumeSession() {
        if linkedSessionId != nil {
            guard let handle = linkedHandle, store.linkedIntentUpdate?.handle == handle,
                  let context = linkService.resumeContext, context.handle == handle else { return }
            if linkedRecordSaved {
                if resumeStore.session?.linkHandle == handle { resumeStore.clear() }
                return
            }
            guard totalAttempts > 0 || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed else { return }
            store.persistResumeSession(into: resumeStore, link: context, startedAt: startTime)
            return
        }
        guard !showEndDialog, savedRecordID == nil, totalAttempts > 0 else {
            resumeStore.clear()
            return
        }
        store.persistResumeSession(into: resumeStore, startedAt: startTime)
    }

    private func epochMilliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }

    private func trainingActionDescription(for shot: ShotTrainingShot) -> String {
        "training_\(shot.points)pt_\(shot.made ? "made" : "miss")"
    }

    private func confirmTraining(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish:
            finishTraining()
        case .reset:
            reset()
        }
    }

    private func pointBadge(_ points: Int) -> some View {
        Text("\(points)")
            .font(WatchScoreTypography.secondaryScore(size: 10, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.75))
            .frame(width: 18, height: 18)
            .background(Color.white.opacity(0.95))
            .clipShape(Circle())
    }

    @ViewBuilder
    private var freePointBadges: some View {
        if scoreboardLayout == "horizontal" {
            VStack(spacing: 0) {
                ForEach(1...3, id: \.self) { points in
                    pointBadge(points)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(1...3, id: \.self) { points in
                    pointBadge(points)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var freeDivisionLines: some View {
        if scoreboardLayout == "horizontal" {
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 1)
                Spacer()
            }
        } else {
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 1)
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 1)
                Spacer()
            }
        }
    }

    private var freeGuideOverlay: some View {
        ZStack {
            Color.black.opacity(0.50).ignoresSafeArea()

            Group {
                if scoreboardLayout == "horizontal" {
                    HStack(spacing: 0) {
                        freeGuideLabel(
                            NSLocalizedString("watch_training_miss", value: "未中", comment: "")
                        )
                        Rectangle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 1)
                        freeGuideLabel(
                            NSLocalizedString("watch_training_made", value: "命中", comment: "")
                        )
                    }
                } else {
                    VStack(spacing: 0) {
                        freeGuideLabel(
                            NSLocalizedString("watch_training_miss", value: "未中", comment: "")
                        )
                        Rectangle()
                            .fill(Color.white.opacity(0.28))
                            .frame(height: 1)
                        freeGuideLabel(
                            NSLocalizedString("watch_training_made", value: "命中", comment: "")
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func freeGuideLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
