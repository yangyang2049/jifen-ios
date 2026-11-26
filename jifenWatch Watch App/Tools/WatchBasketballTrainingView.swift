import LinkCore
import ScoreCore
import RecordCore
import SwiftUI

struct WatchBasketballTrainingView: View {
    private enum PendingFinish {
        case standalone
        case linked(LinkedMatchHandle)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(WatchResumeSessionStore.self) private var resumeStore
    @Environment(WatchLinkService.self) private var linkService

    let mode: ShotTrainingMode
    let linkedSessionId: UUID?

    @State private var showRecordSaveFailure = false
    @State private var pendingFinish: PendingFinish?
    @State private var earlierCounts: ShotTrainingCounts
    @State private var history: [ShotTrainingShot] = []
    @State private var startTime = Date()
    @State private var savedRecordID: String?
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
        resumedHistory: [ShotTrainingShot] = [],
        resumedStartTime: Date? = nil,
        resumedEarlierCounts: ShotTrainingCounts = .init()
    ) {
        self.mode = mode
        self.linkedSessionId = linkedSessionId
        _earlierCounts = State(initialValue: resumedEarlierCounts)
        _history = State(initialValue: resumedHistory)
        _startTime = State(initialValue: resumedStartTime ?? Date())
    }

    var body: some View {
        ZStack {
            board

            if showMenu {
                trainingMenuOverlay
            }
            if showEndDialog {
                endOverlay
            }
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
            enabled: !showMenu && !showEndDialog && confirmation == nil,
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
            if isLinked,
               let state = linkService.resumeContext?.latestAuthoritativeSnapshot?.basketballTrainingState {
                applyLinkedState(state)
            }
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
        .onChange(of: linkService.incomingSnapshot, initial: true) { _, update in
            guard isLinked, let update, update.sessionId == linkedSessionId,
                  let state = update.snapshot.basketballTrainingState else { return }
            applyLinkedState(state)
        }
        .onChange(of: linkService.publishedFinishedMatchIds) { _, _ in
            applyRecoveredLinkedFinish()
        }
        .onChange(of: linkService.pendingReclaimAcceptance, initial: true) { _, pending in
            guard isLinked, let pending, pending.sessionId == linkedSessionId,
                  let state = pending.snapshot.basketballTrainingState else { return }
            applyLinkedState(state)
            linkService.completeReclaimAcceptance(messageId: pending.messageId)
        }
    }

    private var isLinked: Bool {
        linkedSessionId != nil && linkedSessionId == linkService.activeSessionId
    }

    private var scoringLocked: Bool {
        linkedSessionId != nil && (!isLinked || !linkService.canEditLinkedMatch)
    }

    private func linkedSnapshot(finished: Bool = false) -> LinkedScoreboardSnapshot {
        .basketballTraining(.init(
            mode: mode,
            startTime: startTime,
            shots: history,
            earlierCounts: earlierCounts,
            finished: finished || showEndDialog
        ))
    }

    private func applyLinkedState(_ state: ShotTrainingState) {
        history = state.shots
        earlierCounts = state.earlierCounts
        startTime = state.startTime
        showEndDialog = state.finished
        savedRecordID = state.finished ? linkService.activeHandle.map { "w_\($0.matchId.uuidString)" } : nil
        confirmation = nil
        recentShotID = nil
        persistResumeSession()
    }

    private func publishLinkedTraining() {
        guard isLinked, linkService.canEditLinkedMatch else { return }
        linkService.publishSnapshot(linkedSnapshot())
    }

    private func cancelFinishTraining() {
        applyRecoveredLinkedFinish()
        switch pendingFinish {
        case .linked(let handle):
            linkService.cancelPendingTrainingFinish(handle: handle)
        case .standalone:
            resumeStore.cancelPendingTrainingFinish(startedAt: startTime)
        case nil:
            return
        }
        pendingFinish = nil
    }

    private func applyRecoveredLinkedFinish() {
        guard isLinked, case .linked(let handle) = pendingFinish, handle == linkService.activeHandle,
              linkService.publishedFinishedMatchIds.contains(handle.matchId),
              let state = linkService.latestSnapshot?.snapshot.basketballTrainingState, state.finished else { return }
        pendingFinish = nil
        showRecordSaveFailure = false
        applyLinkedState(state)
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
                if scoringLocked {
                    WatchMenuGridButton(
                        title: NSLocalizedString("linked_score_watch_reclaim", value: "手表接管", comment: ""),
                        systemImage: "applewatch"
                    ) {
                        showMenu = false
                        linkService.requestReclaim()
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: WatchLayout.isCompactScreen ? 5 : 6
                    ) {
                        WatchMenuGridButton(
                            title: NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                            systemImage: "arrow.uturn.backward"
                        ) {
                            showMenu = false
                            undo()
                        }
                        WatchMenuGridButton(
                            title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                            systemImage: "arrow.counterclockwise"
                        ) {
                            showMenu = false
                            confirmation = .reset
                        }
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_bb_end_training", value: "结束训练", comment: ""),
                        systemImage: "flag.checkered",
                        background: WatchTheme.dangerRed
                    ) {
                        showMenu = false
                        confirmation = .finish
                    }
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
                if !showMenu && !showEndDialog {
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
                if !scoringLocked && !showMenu && !showEndDialog && confirmation == nil {
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
            guard !showMenu, !showEndDialog, confirmation == nil,
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
                Text(NSLocalizedString("watch_bb_hit_rate", value: "命中率", comment: ""))
                    .font(.system(size: compact ? 12 : 14))
                    .foregroundStyle(WatchTheme.secondaryText)
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
                    Button {
                        restartAfterFinish()
                    } label: {
                        Text(NSLocalizedString("watch_bb_restart", value: "再来一次", comment: ""))
                            .font(.system(size: compact ? 13 : 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(
                                width: WatchLayout.overlayActionButtonWidth,
                                height: compact ? 34 : 38
                            )
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.successGreen)
                    .clipShape(Capsule())
                    .disabled(scoringLocked)
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
        guard !scoringLocked, pendingFinish == nil, !showEndDialog else { return }
        let shot = ShotTrainingShot(id: UUID(), points: points, made: made, timestamp: Date())
        history.append(shot)
        publishLinkedTraining()
        recentShotID = shot.id
        WatchHaptics.shared.play(made ? .score : .strong)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if recentShotID == shot.id {
                recentShotID = nil
            }
        }
    }

    private func undo() {
        guard !scoringLocked, pendingFinish == nil, !showEndDialog, history.popLast() != nil else { return }
        publishLinkedTraining()
        recentShotID = nil
        WatchHaptics.shared.play(.undo)
        showToast(NSLocalizedString("watch_undo_toast", value: "已撤销", comment: ""))
    }

    private func reset() {
        guard !scoringLocked, pendingFinish == nil, !showEndDialog else { return }
        resumeStore.clear()
        history = []
        earlierCounts = .init()
        recentShotID = nil
        publishLinkedTraining()
    }

    private func restartAfterFinish() {
        guard !scoringLocked else { return }
        resumeStore.clear()
        history = []
        earlierCounts = .init()
        startTime = Date()
        savedRecordID = nil
        recentShotID = nil
        showEndDialog = false
        if isLinked {
            linkService.startNextMatch(snapshot: linkedSnapshot())
        }
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
        let endTime = Date()
        if isLinked {
            guard linkService.canEditLinkedMatch, let handle = linkService.activeHandle else { return }
            pendingFinish = .linked(handle)
            let recordID = "w_\(handle.matchId.uuidString)"
            guard linkService.publishMatchFinished(
                snapshot: linkedSnapshot(finished: true),
                recordId: recordID,
                winnerSide: nil,
                manualEnd: true,
                startTime: startTime,
                endTime: endTime,
                totalScoreChanges: totalAttempts
            ) else {
                showRecordSaveFailure = true
                return
            }
            pendingFinish = nil
            savedRecordID = recordID
            showEndDialog = true
            resumeStore.clear()
            return
        }
        pendingFinish = .standalone
        let modeName = mode.fixedPoints.map(String.init) ?? "free"
        var misses = earlierCounts.missed
        var made = earlierCounts.made
        var actions = [
            DetailedScoreAction(
                type: .matchStarted,
                epochMilliseconds: epochMilliseconds(startTime),
                scores: [0, 0],
                operationCode: "training_start",
                summary: "training_start"
            )
        ]
        actions.append(contentsOf: history.map { shot in
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
        let recordID = "watch-basketballTraining-\(UUID().uuidString)"
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
            localSnapshot: linkedSnapshot(finished: true),
            gameType: .basketballTraining,
            id: recordID,
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
        savedRecordID = recordID
        showEndDialog = true
    }

    private func persistResumeSession() {
        guard linkedSessionId == nil || isLinked else { return }
        guard !showEndDialog, savedRecordID == nil, totalAttempts > 0 else {
            resumeStore.clear()
            return
        }
        resumeStore.save(WatchResumeSession(
            startedAt: startTime,
            scoreLine: hitRateText,
            emoji: "🏀",
            payload: .basketballTraining(
                mode: mode,
                history: history,
                earlierCounts: earlierCounts
            ),
            link: isLinked ? linkService.resumeContext : nil
        ))
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
