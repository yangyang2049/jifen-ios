//
//  ArcheryScoreboardView.swift
//  jifen
//
//  射箭计分板：使用标准 PVP 模板布局，保留射箭局分规则（先到 6 分胜、5:5 一箭决胜）。
//

import LinkCore
import RecordCore
import ScoreCore
import SwiftUI

private let archeryArrowsPerSetNormal = 3
private let archeryArrowsPerSetShootoff = 1
private let archerySetPointsToWin = 6
private let archerySetPointsWin = 2
private let archerySetPointsTie = 1
private let archerySetEndOverlayDelay: TimeInterval = 1.2

private let archeryScoreGrid: [[Int?]] = [
    [10, 9, 8, 7],
    [6, 5, 4, 3],
    [2, 1, 0, -1]
]

struct ArcheryScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller = ArcheryScoreboardController()
    @State private var viewModel = ArcheryViewModel()
    @State private var responsiveScoreFontSize: CGFloat = 120
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var recordID: String
    @State private var watchSessionId: UUID?
    @State private var manualFinishRequested = false
    @State private var toastMessage: String?

    @State private var showArrowPicker = false
    @State private var showSetEndOverlay = false
    @State private var showClosestToCenter = false
    @State private var pendingSetNumber = 0
    @State private var pendingSetLeftScore = 0
    @State private var pendingSetRightScore = 0
    @State private var pendingContinueUpdate: (() -> Void)? = nil
    @State private var pendingClosestContinue: ((Bool) -> Void)? = nil

    private var scoringLocked: Bool {
        watchSessionId != nil
            && (watchLinkService.isFollower || watchLinkService.isAuthorityTransferPending)
    }

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        _recordID = State(initialValue: ScoreboardRecordIdentity.initial(
            prefix: GameType.archery.canonicalScoreboardIdentifier,
            resuming: initialResumeSessionId
        ))
    }

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .archery,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: ScoreboardCommonNamePolicy.nameType(for: .archery),
                    scoreTextProvider: { _, team in "\(team.score)" },
                    tapToAddEnabled: false,
                    contentOverlayProvider: { isEditMode in
                        AnyView(ArcheryMiddleLayer(
                            viewModel: viewModel,
                            showArrowPicker: $showArrowPicker,
                            controller: controller,
                            isEditMode: isEditMode,
                            scoringLocked: scoringLocked
                        ))
                    },
                    onEditModeChange: { editing in
                        if editing {
                            showArrowPicker = false
                            showSetEndOverlay = false
                            showClosestToCenter = false
                        }
                    },
                    showEndGame: true,
                    onEndGame: {
                        guard !scoringLocked else { return }
                        manualFinishRequested = true
                        viewModel.endGame()
                    },
                    extraMenuItemsProvider: {
                        WatchLinkMenuSupport.extraItems(
                            entryEnabled: AppFeatureFlags.watchLinkEntryEnabled,
                            sessionId: watchSessionId,
                            isFollower: watchLinkService.isFollower,
                            watchBackgrounded: watchLinkService.watchBackgrounded
                        )
                    },
                    onMenuAction: { action in
                        switch action {
                        case "resync":
                            watchLinkService.requestScoreResync()
                        case "takeover":
                            if let id = watchSessionId {
                                Task {
                                    do {
                                        try await watchLinkService.takeover(sessionId: id)
                                        publishWatchIfNeeded()
                                    } catch {
                                        showToast(error.localizedDescription)
                                    }
                                }
                            }
                        case "forceTakeover":
                            if let id = watchSessionId {
                                watchLinkService.requestForceTakeoverConfirmation(id)
                            }
                        case "endLink":
                            if let id = watchSessionId {
                                watchLinkService.leaveSession(id)
                                watchSessionId = nil
                            }
                        default:
                            break
                        }
                    },
                    scoringEnabledProvider: { !viewModel.mutationLocked }
                ),
                onBack: {
                    saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                    onNavigationBack?()
                    dismiss()
                }
            )

            if showArrowPicker {
                archeryScorePicker
            }

            if showSetEndOverlay {
                setEndOverlay
            }

            if showClosestToCenter {
                closestToCenterOverlay
            }

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: viewModel.getWinnerName(),
                    gameType: .archery,
                    leftName: viewModel.leftTeam.name,
                    rightName: viewModel.rightTeam.name,
                    leftScore: viewModel.leftTeam.sets ?? 0,
                    rightScore: viewModel.rightTeam.sets ?? 0,
                    newGameLabel: scoringLocked ? NSLocalizedString(
                        "game_over_new_game_on_watch",
                        value: "再来一场\n（请在手表端操作）",
                        comment: ""
                    ) : nil,
                    newGameDisabled: scoringLocked,
                    onNewGame: {
                        guard !scoringLocked else { return }
                        startNewMatch()
                    },
                    onRecords: {
                        saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        shareFinishedMatch()
                    },
                    onExit: {
                        saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                        onNavigationBack?()
                        dismiss()
                    }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .padding(.bottom, 72)
                    .allowsHitTesting(false)
            }
        }
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: recordID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ModalCloseButton { showFinishedRecordDetail = false }
                        }
                    }
            }
        }
        .navigationTitle(NSLocalizedString("project_archery", value: "Archery", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            watchSessionId = initialSetup?.linkedWatchSessionId
            viewModel.controller = controller
            viewModel.mutationLocked = scoringLocked
            if let setup = initialSetup {
                let defaults = DefaultParticipantNames.resolve(for: .archery)
                let left = resolvedScoreboardSetupName(setup.team1Name, fallback: defaults.left)
                let right = resolvedScoreboardSetupName(setup.team2Name, fallback: defaults.right)
                let openingIsLeft = setup.servingSide != MatchSide.right.rawValue
                viewModel.configureOpening(leftName: left, rightName: right, openingIsLeft: openingIsLeft)
                onSetupConsumed?()
            }
            restoreResumeIfNeeded()
            if let watchSessionId,
               let update = watchLinkService.attachPage(sessionId: watchSessionId),
               let remote = update.snapshot.archeryState {
                applyRemoteArchery(remote)
            }
            viewModel.setOnSetEndCallback { data in
                handleSetEnd(data: data)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            responsiveScoreFontSize = calculateResponsiveScoreFontSize(containerWidth: width)
        }
        .onChange(of: viewModel.gameFinished) { _, finished in
            if finished {
                showGameOverDialog = true
                if !watchLinkService.isFollower {
                    saveGameRecordInRealTime(isGameFinished: true)
                }
                publishWatchIfNeeded(finished: true)
                notifyLinkedFinishIfNeeded()
            }
        }
        .onChange(of: viewModel.match) { _, state in
            if !state.finished, !watchLinkService.isFollower {
                saveGameRecordInRealTime()
            }
        }
        .onChange(of: viewModel.leftTeam.score) { _, _ in publishWatchIfNeeded() }
        .onChange(of: viewModel.rightTeam.score) { _, _ in publishWatchIfNeeded() }
        .onChange(of: viewModel.leftTeam.sets) { _, _ in publishWatchIfNeeded() }
        .onChange(of: viewModel.rightTeam.sets) { _, _ in publishWatchIfNeeded() }
        .onChange(of: watchLinkService.latestRemoteSnapshot) { _, update in
            guard let watchSessionId, let update, update.sessionId == watchSessionId,
                  let remote = update.snapshot.archeryState else { return }
            applyRemoteArchery(remote)
        }
        .onChange(of: watchLinkService.pendingTakeoverApplication) { _, pending in
            guard let watchSessionId, let pending, pending.sessionId == watchSessionId,
                  let remote = pending.snapshot.archeryState else { return }
            applyRemoteArchery(remote)
            watchLinkService.completePhoneTakeover(messageId: pending.messageId)
        }
        .onChange(of: watchLinkService.isFollower) { _, _ in
            viewModel.mutationLocked = scoringLocked
        }
        .onChange(of: watchLinkService.isAuthorityTransferPending) { _, _ in
            viewModel.mutationLocked = scoringLocked
        }
        .onDisappear {
            let skipSave = watchSessionId != nil
                && (watchLinkService.isFollower || watchLinkService.finishedRecordId != nil)
            if let watchSessionId { watchLinkService.detachPage(sessionId: watchSessionId) }
            if !skipSave {
                saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
            }
        }
        .alert(
            NSLocalizedString("linked_score_watch_reclaim_title", value: "手表请求重新接管", comment: ""),
            isPresented: reclaimAlertPresented
        ) {
            Button(NSLocalizedString("linked_score_accept", value: "同意", comment: "")) {
                watchLinkService.resolveReclaimRequest(
                    accepted: true,
                    snapshot: .archery(viewModel.linkedSnapshot()),
                    detailedActions: []
                )
            }
            Button(NSLocalizedString("linked_score_reject", value: "拒绝", comment: ""), role: .cancel) {
                rejectWatchReclaim()
            }
        } message: {
            Text(reclaimMessage)
        }
    }

    private var reclaimMessage: String {
        NSLocalizedString(
            "linked_score_watch_reclaim_message",
            value: "是否允许手表在 5 秒内重新接管计分？",
            comment: ""
        )
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private var archeryScorePicker: some View {
        GeometryReader { proxy in
            let dialogWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                phonePreferredWidth: 380,
                padPreferredWidth: 420
            )
            let scoreButtonSize = ScoreboardLayoutMetrics.fittedGridItemSize(
                containerWidth: dialogWidth,
                columns: 4,
                spacing: 10,
                horizontalPadding: 16,
                preferredSize: Theme.usesPadLayout ? 80 : 60,
                minimumSize: ScoreboardConstants.minimumTouchTarget
            )

            ZStack {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
                .onTapGesture { showArrowPicker = false }

            VStack(spacing: 0) {
                // 标题栏与 X 按钮对齐羽毛球菜单（MenuDialog）：标题整体居中，X 在右侧圆底
                ZStack {
                    Text(currentShooterName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    HStack {
                        Spacer()
                        ScoreboardDialogCloseButton(
                            action: { showArrowPicker = false },
                            accessibilityIdentifier: "archery_arrow_picker_close"
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)
                .frame(height: 48)

                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(archeryScoreGrid[row].indices, id: \.self) { col in
                                let value = archeryScoreGrid[row][col]
                                Button {
                                    guard !scoringLocked else {
                                        showToast(NSLocalizedString("linked_score_watch_control_readonly_toast", value: "手表计分中，手机暂不能计分", comment: ""))
                                        return
                                    }
                                    viewModel.recordArrow(value: value == -1 ? nil : value)
                                    showArrowPicker = false
                                } label: {
                                    Text(value == -1 ? "M" : "\(value ?? 0)")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(value == -1 ? .white : .black)
                                        .frame(width: scoreButtonSize, height: scoreButtonSize)
                                        .background(value == -1 ? Color.orange : Color.white.opacity(0.9))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: dialogWidth)
            .background(Theme.scoreboardDialogSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.3), radius: 32, x: 0, y: 12)
            .onTapGesture { }
        }
        }
    }

    private var setEndOverlay: some View {
        GeometryReader { proxy in
            let dialogWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                phonePreferredWidth: 328,
                padPreferredWidth: 420
            )

            ZStack {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text(String(format: NSLocalizedString("watch_set_end_format", value: "第 %d 局结束", comment: ""), pendingSetNumber))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                TwoSideScoreResultRow(
                    leftName: viewModel.leftTeam.name,
                    rightName: viewModel.rightTeam.name,
                    leftScore: "\(pendingSetLeftScore)",
                    rightScore: "\(pendingSetRightScore)",
                    leftNameColor: Color(hex: "DC143C"),
                    rightNameColor: Color(hex: "1E90FF"),
                    leftScoreColor: .white,
                    rightScoreColor: .white,
                    separatorColor: .white.opacity(0.7),
                    nameFont: .system(size: 14),
                    scoreFont: .system(size: 26, weight: .bold),
                    separatorFont: .system(size: 20, weight: .bold),
                    sideSpacing: 3,
                    columnSpacing: 12
                )
                .frame(width: max(0, dialogWidth - 48))
            }
            .padding(24)
            .background(Theme.scoreboardDialogSurface)
            .cornerRadius(16)
        }
        }
    }

    private var closestToCenterOverlay: some View {
        GeometryReader { proxy in
            let dialogWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                phonePreferredWidth: max(0, proxy.size.width - 80),
                padPreferredWidth: 480
            )

            ZStack {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text(NSLocalizedString("archery_closest_title", value: "一箭决胜 · 近心", comment: ""))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text(String(
                    format: NSLocalizedString("archery_closest_message", value: "双方同环 %d，请选择更近心的一方", comment: ""),
                    pendingSetLeftScore
                ))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button {
                        showClosestToCenter = false
                        pendingClosestContinue?(true)
                        pendingClosestContinue = nil
                    } label: {
                        Text(viewModel.leftTeam.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(hex: "DC143C"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    Button {
                        showClosestToCenter = false
                        pendingClosestContinue?(false)
                        pendingClosestContinue = nil
                    } label: {
                        Text(viewModel.rightTeam.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(hex: "1E90FF"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showClosestToCenter = false
                    pendingClosestContinue = nil
                    viewModel.repeatShootOff()
                } label: {
                    Text(NSLocalizedString("archery_repeat_shoot_off", value: "距离相同，继续加赛", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(width: dialogWidth)
            .background(Theme.scoreboardDialogSurface)
            .cornerRadius(16)
        }
        }
    }

    private var currentShooterName: String {
        viewModel.currentShooterIsLeft ? viewModel.leftTeam.name : viewModel.rightTeam.name
    }

    private func handleSetEnd(data: SetEndCallbackData) {
        pendingSetNumber = data.setNumber
        pendingSetLeftScore = data.finalLeftScore
        pendingSetRightScore = data.finalRightScore

        if viewModel.needsClosestToCenterDecision(
            leftArrowScore: data.finalLeftScore,
            rightArrowScore: data.finalRightScore
        ) {
            if data.finalLeftScore == 0 && data.finalRightScore == 0 {
                showSetEndOverlay = true
                DispatchQueue.main.asyncAfter(deadline: .now() + archerySetEndOverlayDelay) {
                    showSetEndOverlay = false
                    viewModel.repeatShootOff()
                }
                return
            }
            pendingClosestContinue = { leftWins in
                self.viewModel.applyClosestToCenter(leftWins: leftWins)
            }
            showClosestToCenter = true
            return
        }

        showSetEndOverlay = true
        pendingContinueUpdate = data.continueUpdate
        DispatchQueue.main.asyncAfter(deadline: .now() + archerySetEndOverlayDelay) {
            showSetEndOverlay = false
            pendingContinueUpdate?()
            pendingContinueUpdate = nil
        }
    }

    private func calculateResponsiveScoreFontSize(containerWidth: CGFloat) -> CGFloat {
        let base: CGFloat = 120
        guard containerWidth > 0 else { return base }
        return min(240, max(base, base + (containerWidth - 400) * 0.15))
    }

    private func startNewMatch() {
        saveGameRecordInRealTime(isGameFinished: true)
        controller.beginNewMatch()
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.archery.canonicalScoreboardIdentifier)
        viewModel.startNewMatch()
        manualFinishRequested = false
        showArrowPicker = false
        showSetEndOverlay = false
        showClosestToCenter = false
        pendingContinueUpdate = nil
        pendingClosestContinue = nil
        showGameOverDialog = false
        if let watchSessionId, watchLinkService.isController {
            watchLinkService.prepareControllerForNewMatch(
                sessionId: watchSessionId,
                gameType: .archeryDual,
                snapshot: .archery(viewModel.linkedSnapshot()),
                participantNames: [viewModel.leftTeam.name, viewModel.rightTeam.name]
            )
        } else {
            publishWatchIfNeeded()
        }
    }

    private func restoreResumeIfNeeded() {
        guard let recordId = initialResumeSessionId,
              let record = ManualResumeSessionStore.load(recordID: recordId) else {
            return
        }

        recordID = record.id
        controller.gameStartTime = record.startTime
        controller.gameActions = record.actions
        controller.gameRecordSaved = false

        if let data = record.stateSnapshot,
           let resumeState = try? JSONDecoder().decode(ArcheryResumeState.self, from: data) {
            controller.gameActions = resumeState.intentTimeline
            viewModel.restoreSession(resumeState)
            return
        }

        viewModel.leftTeam.name = record.team1Name
        viewModel.rightTeam.name = record.team2Name

        if let leftRingScore = record.extraData?["leftRingScore"]?.value as? Int,
           let rightRingScore = record.extraData?["rightRingScore"]?.value as? Int {
            // keep names already set
            _ = leftRingScore
            _ = rightRingScore
        }
        viewModel.restoreMatchFields(
            leftRingScore: record.extraData?["leftRingScore"]?.value as? Int,
            rightRingScore: record.extraData?["rightRingScore"]?.value as? Int,
            leftSets: record.extraData?["leftSets"]?.value as? Int,
            rightSets: record.extraData?["rightSets"]?.value as? Int,
            currentSet: record.extraData?["currentSet"]?.value as? Int,
            arrowsPerSet: record.extraData?["arrowsPerSet"]?.value as? Int,
            arrowsLeftThisSet: record.extraData?["arrowsLeftThisSet"]?.value as? Int,
            arrowsRightThisSet: record.extraData?["arrowsRightThisSet"]?.value as? Int,
            currentShooterIsLeft: record.extraData?["currentShooterIsLeft"]?.value as? Bool,
            openingShooterIsLeft: record.extraData?["openingShooterIsLeft"]?.value as? Bool,
            sidesSwapped: record.extraData?["sidesSwapped"]?.value as? Bool
        )
    }

    private func publishWatchIfNeeded(finished: Bool = false) {
        guard let watchSessionId, watchLinkService.isController else { return }
        let snapshot = viewModel.linkedSnapshot(finished: finished)
        watchLinkService.syncWatch(
            sessionId: watchSessionId,
            gameType: .archeryDual,
            snapshot: .archery(snapshot)
        )
    }

    private func applyRemoteArchery(_ remote: LinkedArcheryState) {
        viewModel.applyRemote(remote)
        manualFinishRequested = false
        // Reactive to the linked device's finished flag (mirrors HarmonyOS:
        // follower auto-shows the finish dialog when the received snapshot is
        // finished, and dismisses it when a new unfinished match arrives after
        // 再来一场). Setting both directions, not just true.
        showGameOverDialog = remote.finished
    }

    private var reclaimAlertPresented: Binding<Bool> {
        Binding(
            get: { watchLinkService.pendingReclaimRequest != nil },
            set: { presented in
                if !presented, watchLinkService.pendingReclaimRequest != nil {
                    rejectWatchReclaim()
                }
            }
        )
    }

    private func rejectWatchReclaim() {
        watchLinkService.resolveReclaimRequest(accepted: false, snapshot: nil, detailedActions: [])
    }

    private func notifyLinkedFinishIfNeeded() {
        guard let watchSessionId, watchLinkService.isController else { return }
        let state = viewModel.match
        watchLinkService.notifyMatchFinished(
            sessionId: watchSessionId,
            snapshot: .archery(viewModel.linkedSnapshot(finished: true)),
            recordId: recordID,
            winnerSide: state.winnerSide,
            manualEnd: manualFinishRequested,
            startTime: controller.getGameStartTime(),
            endTime: Date(),
            totalScoreChanges: controller.getGameActions().count
        )
    }

    private func saveGameRecordInRealTime(isGameFinished: Bool = false) {
        let hasProgress = !controller.getGameActions().isEmpty
            || viewModel.leftTeam.score != 0
            || viewModel.rightTeam.score != 0
            || (viewModel.leftTeam.sets ?? 0) != 0
            || (viewModel.rightTeam.sets ?? 0) != 0
            || isGameFinished
            || viewModel.gameFinished
        guard hasProgress else { return }

        let finished = isGameFinished || viewModel.gameFinished
        let start = controller.getGameStartTime()
        let end = Date()

        var winner: String?
        if finished {
            let leftSets = viewModel.leftTeam.sets ?? 0
            let rightSets = viewModel.rightTeam.sets ?? 0
            if leftSets > rightSets {
                winner = TeamID.team0.rawValue
            } else if rightSets > leftSets {
                winner = TeamID.team1.rawValue
            }
        }

        let resumeState = ArcheryResumeState(
            state: viewModel.match,
            undoHistory: viewModel.resumeHistory,
            intentTimeline: controller.getGameActions(),
            detailedActions: viewModel.detailedActions
        )
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(resumeState)
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "Failed to encode archery record \(recordID)"
            )
            return
        }

        controller.saveScoreboardRecord(
            id: recordID,
            endTime: end,
            duration: end.timeIntervalSince(start),
            team1Name: viewModel.leftTeam.name,
            team2Name: viewModel.rightTeam.name,
            team1FinalScore: viewModel.leftTeam.sets ?? 0,
            team2FinalScore: viewModel.rightTeam.sets ?? 0,
            team1SetScore: viewModel.leftTeam.sets,
            team2SetScore: viewModel.rightTeam.sets,
            winner: winner,
            totalScoreChanges: controller.getGameActions().count,
            extraData: [
                "currentSet": viewModel.currentSet,
                "arrowsPerSet": viewModel.arrowsPerSet,
                "arrowsLeftThisSet": viewModel.arrowsLeftThisSet,
                "arrowsRightThisSet": viewModel.arrowsRightThisSet,
                "currentShooterIsLeft": viewModel.currentShooterIsLeft,
                "openingShooterIsLeft": viewModel.openingShooterIsLeft,
                "sidesSwapped": viewModel.match.sidesSwapped,
                "leftRingScore": viewModel.leftTeam.score,
                "rightRingScore": viewModel.rightTeam.score,
                "leftSets": viewModel.leftTeam.sets ?? 0,
                "rightSets": viewModel.rightTeam.sets ?? 0
            ],
            detailedActions: viewModel.detailedActions,
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: ScoreCore.GameType.archeryDual.rawValue
            ],
            stateSnapshot: snapshotData,
            isFinished: finished
        )
    }

    private func shareFinishedMatch() {
        let text = "\(viewModel.leftTeam.name) \(viewModel.leftTeam.sets ?? 0) - \(viewModel.rightTeam.sets ?? 0) \(viewModel.rightTeam.name)"
        ScoreboardShareSupport.present(text: text)
    }
}

private class ArcheryScoreboardController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .archery,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 80
        ))
    }

    override func getScoringOptions() -> [Int] {
        []
    }
}

/// 需为 internal 以便 ScoreboardTemplate 通过 ScoreViewModelProtocol 派发调用 adjustSets（private 时协议走默认空实现，局分 +/- 不生效）
@Observable
class ArcheryViewModel: BaseScoreViewModel, ScoreEditGuarding {
    private var sessionStore: ArcherySessionStore
    private var onSetEndCallback: ((SetEndCallbackData) -> Void)? = nil
    private var lastEvents: [ArcheryMatchEvent] = []
    private(set) var detailedActions: [DetailedScoreAction] = []
    var mutationLocked = false

    var match: ArcheryMatchState { sessionStore.state }
    var teamScreenLayout: TeamScreenLayout { sessionStore.teamScreenLayout }
    var sessionId: UUID { sessionStore.sessionId }
    var resumeHistory: [ArcheryMatchState] { sessionStore.resumeHistory }

    var currentSet: Int { match.currentSet }
    var currentShooterIsLeft: Bool {
        get { match.currentShooterIsLeft }
        set { _ = apply(.selectShooter(isLeft: newValue), recordHistory: false) }
    }
    var openingShooterIsLeft: Bool { match.openingShooterIsLeft }
    var arrowsLeftThisSet: Int { match.arrowsLeftThisSet }
    var arrowsRightThisSet: Int { match.arrowsRightThisSet }
    var arrowsPerSet: Int { match.arrowsPerSet }

    override init(controller: BaseScoreboardController? = nil) {
        let defaults = DefaultParticipantNames.resolve(for: .archery)
        sessionStore = ArcherySessionStore(
            leftName: defaults.left,
            rightName: defaults.right
        )
        super.init(controller: controller)
        syncTeamsFromMatch()
    }

    func setOnSetEndCallback(_ callback: @escaping (SetEndCallbackData) -> Void) {
        onSetEndCallback = callback
    }

    func configureOpening(leftName: String, rightName: String, openingIsLeft: Bool) {
        sessionStore.configureOpening(leftName: leftName, rightName: rightName, openingIsLeft: openingIsLeft)
        syncTeamsFromMatch()
    }

    func restoreSession(_ resumeState: ArcheryResumeState) {
        let requiresMigration = resumeState.schemaVersion < 2
        sessionStore.restoreRecordState(
            requiresMigration ? resumeState.state.normalizedFromLegacyPhysicalSideSwap() : resumeState.state,
            undoHistory: requiresMigration
                ? resumeState.undoHistory.map { $0.normalizedFromLegacyPhysicalSideSwap() }
                : resumeState.undoHistory
        )
        detailedActions = resumeState.detailedActions
        syncTeamsFromMatch()
    }

    func startNewMatch() {
        let reset = ArcheryMatchReducer().reduce(
            state: match,
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        ).state
        sessionStore = ArcherySessionStore(state: reset)
        lastEvents.removeAll()
        detailedActions.removeAll()
        syncTeamsFromMatch()
    }

    func applyRemote(_ remote: LinkedArcheryState) {
        var next = match
        remote.applying(to: &next)
        sessionStore.rebase(to: next)
        syncTeamsFromMatch()
    }

    func linkedSnapshot(finished: Bool = false) -> LinkedArcheryState {
        var snap = LinkedArcheryState(match: match)
        if finished { snap.finished = true }
        return snap
    }

    func recordArrow(value: Int?) {
        guard !mutationLocked else { return }
        let shooter = match.currentShooter
        guard apply(.recordArrow(side: nil, value: value)) else { return }
        let label = value.map(String.init) ?? "M"
        controller?.recordScoreAction(action: "archery_arrow_\(shooter.rawValue)_\(label)")
        controller?.performVibration(type: .light)
        handlePostReduceUI()
    }

    func repeatShootOff() {
        guard !mutationLocked, apply(.repeatShootOff, recordHistory: false) else { return }
        controller?.recordScoreAction(action: "archery_repeat_shoot_off")
        syncTeamsFromMatch()
    }

    override func adjustScore(isLeft: Bool, delta: Int) {
        guard !mutationLocked else { return }
        _ = apply(.adjustArrowSum(side: isLeft ? .left : .right, delta: delta))
    }

    func canAdjustMainScore(isLeft: Bool, delta: Int) -> Bool {
        match.canAdjustArrowSum(side: isLeft ? .left : .right, delta: delta)
    }

    func canAdjustSetScore(isLeft: Bool, delta: Int) -> Bool {
        match.canAdjustSetPoints(side: isLeft ? .left : .right, delta: delta)
    }

    func adjustSetPoints(isLeft: Bool, delta: Int) {
        guard !mutationLocked else { return }
        _ = apply(.adjustSetPoints(side: isLeft ? .left : .right, delta: delta))
    }

    func adjustSets(isLeft: Bool, delta: Int) {
        adjustSetPoints(isLeft: isLeft, delta: delta)
    }

    func getWinnerDisplayText() -> String {
        let name = getWinnerName()
        if name.isEmpty {
            return NSLocalizedString("draw_result", value: "平局", comment: "")
        }
        return String(format: NSLocalizedString("winner_named_format", value: "%@ 获胜", comment: ""), name)
    }

    func getWinnerName() -> String {
        guard match.finished, let side = match.winnerSide else { return "" }
        return side == .left ? match.leftName : match.rightName
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !mutationLocked, !match.finished else { return }
        let side: MatchSide? = editState.isEditMode ? (isLeft ? .left : .right) : nil
        if !editState.isEditMode {
            guard isLeft == match.currentShooterIsLeft else { return }
        }
        _ = apply(.recordArrow(side: side, value: points))
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(max(0, points))")
        controller?.performVibration(type: .light)
        handlePostReduceUI()
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        guard !mutationLocked, !match.finished else { return }
        _ = apply(.adjustArrowSum(side: isLeft ? .left : .right, delta: -max(0, points)))
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(max(0, points))")
        controller?.performVibration(type: .light)
    }

    override func undo() -> Bool {
        guard !mutationLocked else { return false }
        guard sessionStore.undo() else { return false }
        syncTeamsFromMatch()
        detailedActions.append(DetailedScoreAction(
            type: .undo,
            epochMilliseconds: Self.nowMilliseconds(),
            scores: [match.leftArrowSum, match.rightArrowSum],
            setScores: [match.leftSetPoints, match.rightSetPoints],
            setNumber: match.currentSet,
            operationCode: "archery_undo"
        ))
        controller?.performVibration(type: .light)
        return true
    }

    override func exchangeSides() {
        guard !mutationLocked, !match.finished else { return }
        _ = apply(.exchangeSides)
        controller?.performVibration(type: .medium)
    }

    override func reset() {
        guard !mutationLocked else { return }
        super.reset()
        _ = apply(.reset, recordHistory: false)
        sessionStore.clearHistory()
    }

    func needsClosestToCenterDecision(leftArrowScore: Int, rightArrowScore: Int) -> Bool {
        match.needsClosestToCenter
            && match.leftArrowSum == leftArrowScore
            && match.rightArrowSum == rightArrowScore
    }

    func applyClosestToCenter(leftWins: Bool) {
        guard !mutationLocked else { return }
        _ = apply(.completeSet(closestToCenterWinner: leftWins ? .left : .right), recordHistory: false)
        if match.finished {
            gameFinished = true
            controller?.performVibration(type: .heavy)
        }
        syncTeamsFromMatch()
    }

    func continuePendingSetEnd() {
        guard !mutationLocked else { return }
        guard match.setCompletionPending, !match.closestToCenterPending else { return }
        _ = apply(.completeSet(closestToCenterWinner: nil), recordHistory: false)
        if match.finished {
            gameFinished = true
            controller?.performVibration(type: .heavy)
        }
        syncTeamsFromMatch()
    }

    override func endGame() {
        guard !mutationLocked else { return }
        guard apply(.finish) else { return }
        syncTeamsFromMatch()
    }

    @discardableResult
    private func apply(_ intent: ArcheryMatchIntent, recordHistory: Bool = true) -> Bool {
        let before = match
        let result = sessionStore.apply(intent, recordHistory: recordHistory)
        guard result.accepted else { return false }
        lastEvents = result.events
        appendDetailedActions(
            events: result.events,
            before: before,
            after: result.state,
            at: Self.nowMilliseconds()
        )
        syncTeamsFromMatch()
        return true
    }

    private static func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    /// Records engine-owned boundaries so recap grouping never has to infer
    /// the current end/set for records written by this version of the app.
    private func appendDetailedActions(
        events: [ArcheryMatchEvent],
        before: ArcheryMatchState,
        after: ArcheryMatchState,
        at milliseconds: Int64
    ) {
        for event in events {
            let action: DetailedScoreAction
            switch event {
            case .arrowScored(let side, let points, let left, let right):
                action = .init(
                    type: .scoreChanged,
                    epochMilliseconds: milliseconds,
                    team: side == .left ? .team1 : .team2,
                    scores: [left, right],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: before.currentSet,
                    scoreChange: points,
                    operationCode: "archery_arrow"
                )
            case .arrowMissed(let side, let left, let right):
                action = .init(
                    type: .scoreChanged,
                    epochMilliseconds: milliseconds,
                    team: side == .left ? .team1 : .team2,
                    scores: [left, right],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: before.currentSet,
                    scoreChange: 0,
                    operationCode: "archery_miss"
                )
            case .setReady(let number, let left, let right, let pendingLeft, let pendingRight):
                action = .init(
                    type: .stateChanged,
                    epochMilliseconds: milliseconds,
                    scores: [left, right],
                    setScores: [pendingLeft, pendingRight],
                    setNumber: number,
                    operationCode: "archery_set_ready"
                )
            case .closestToCenterRequired(let number, let tiedScore):
                action = .init(
                    type: .stateChanged,
                    epochMilliseconds: milliseconds,
                    scores: [tiedScore, tiedScore],
                    setScores: [before.leftSetPoints, before.rightSetPoints],
                    setNumber: number,
                    operationCode: "archery_closest_to_center"
                )
            case .shootOffRepeated(let number):
                action = .init(
                    type: .stateChanged,
                    epochMilliseconds: milliseconds,
                    scores: [after.leftArrowSum, after.rightArrowSum],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: number,
                    operationCode: "archery_shoot_off_repeated"
                )
            case .setCompleted(let number, let winner, let leftSets, let rightSets):
                action = .init(
                    type: .setFinished,
                    epochMilliseconds: milliseconds,
                    team: winner.map { $0 == .left ? .team1 : .team2 },
                    scores: [before.leftArrowSum, before.rightArrowSum],
                    setScores: [leftSets, rightSets],
                    setNumber: number,
                    winner: winner.map { $0 == .left ? .team1 : .team2 },
                    operationCode: "archery_set_completed"
                )
            case .matchFinished(let winner):
                action = .init(
                    type: .matchFinished,
                    epochMilliseconds: milliseconds,
                    scores: [after.leftArrowSum, after.rightArrowSum],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: max(1, max(before.pendingSetNumber, before.currentSet)),
                    winner: winner.map { $0 == .left ? .team1 : .team2 },
                    operationCode: "finish"
                )
            case .arrowSumAdjusted(let side, let delta):
                action = .init(
                    type: .scoreChanged,
                    epochMilliseconds: milliseconds,
                    team: side == .left ? .team1 : .team2,
                    scores: [after.leftArrowSum, after.rightArrowSum],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: after.currentSet,
                    scoreChange: delta,
                    operationCode: "archery_adjust_arrow_sum"
                )
            case .setPointsAdjusted(let side, let delta):
                action = .init(
                    type: .stateChanged,
                    epochMilliseconds: milliseconds,
                    team: side == .left ? .team1 : .team2,
                    scores: [after.leftArrowSum, after.rightArrowSum],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: after.currentSet,
                    scoreChange: delta,
                    operationCode: "archery_adjust_set_points"
                )
            case .namesChanged:
                action = .init(
                    type: .stateChanged,
                    epochMilliseconds: milliseconds,
                    scores: [after.leftArrowSum, after.rightArrowSum],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: after.currentSet,
                    operationCode: "archery_edit_names"
                )
            case .openingShooterChanged, .shooterSelected:
                action = .init(
                    type: .stateChanged,
                    epochMilliseconds: milliseconds,
                    scores: [after.leftArrowSum, after.rightArrowSum],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: after.currentSet,
                    operationCode: "archery_shooter_changed"
                )
            case .sidesExchanged:
                action = .init(
                    type: .sideChanged,
                    epochMilliseconds: milliseconds,
                    scores: [after.leftArrowSum, after.rightArrowSum],
                    setScores: [after.leftSetPoints, after.rightSetPoints],
                    setNumber: after.currentSet,
                    operationCode: "exchange_sides"
                )
            case .matchReset:
                action = .init(
                    type: .reset,
                    epochMilliseconds: milliseconds,
                    scores: [0, 0],
                    setScores: [0, 0],
                    operationCode: "reset"
                )
            }
            detailedActions.append(action)
        }
    }

    private func handlePostReduceUI() {
        for event in lastEvents {
            switch event {
            case .closestToCenterRequired(let setNumber, _):
                let data = SetEndCallbackData(
                    finalLeftScore: match.leftArrowSum,
                    finalRightScore: match.rightArrowSum,
                    winnerName: NSLocalizedString("draw_result", value: "平局", comment: ""),
                    setNumber: setNumber,
                    leftSets: match.leftSetPoints,
                    rightSets: match.rightSetPoints,
                    leftGames: nil,
                    rightGames: nil,
                    shouldChangeSides: false,
                    isGameFinished: false,
                    continueUpdate: { [weak self] in
                        self?.applyClosestToCenter(leftWins: true)
                    }
                )
                onSetEndCallback?(data)
            case .setReady(let setNumber, let leftArrow, let rightArrow, let pendingLeft, let pendingRight):
                let winnerName: String
                if leftArrow > rightArrow {
                    winnerName = match.leftName
                } else if rightArrow > leftArrow {
                    winnerName = match.rightName
                } else {
                    winnerName = NSLocalizedString("draw_result", value: "平局", comment: "")
                }
                let isMatchFinished = pendingLeft >= match.rules.setPointsToWin || pendingRight >= match.rules.setPointsToWin
                let data = SetEndCallbackData(
                    finalLeftScore: leftArrow,
                    finalRightScore: rightArrow,
                    winnerName: winnerName,
                    setNumber: setNumber,
                    leftSets: pendingLeft,
                    rightSets: pendingRight,
                    leftGames: nil,
                    rightGames: nil,
                    shouldChangeSides: false,
                    isGameFinished: isMatchFinished,
                    continueUpdate: { [weak self] in
                        self?.continuePendingSetEnd()
                    }
                )
                onSetEndCallback?(data)
            case .matchFinished:
                gameFinished = true
                controller?.performVibration(type: .heavy)
            case .shootOffRepeated:
                break
            default:
                break
            }
        }
    }

    private func syncTeamsFromMatch() {
        leftTeam.name = match.leftName
        rightTeam.name = match.rightName
        leftTeam.score = match.leftArrowSum
        rightTeam.score = match.rightArrowSum
        leftTeam.sets = match.leftSetPoints
        rightTeam.sets = match.rightSetPoints
        sidesSwapped = match.sidesSwapped
        gameFinished = match.finished
    }

    func restoreMatchFields(
        leftRingScore: Int?,
        rightRingScore: Int?,
        leftSets: Int?,
        rightSets: Int?,
        currentSet: Int?,
        arrowsPerSet: Int?,
        arrowsLeftThisSet: Int?,
        arrowsRightThisSet: Int?,
        currentShooterIsLeft: Bool?,
        openingShooterIsLeft: Bool?,
        sidesSwapped: Bool? = nil
    ) {
        var next = match
        if let leftRingScore { next.leftArrowSum = leftRingScore }
        if let rightRingScore { next.rightArrowSum = rightRingScore }
        if let leftSets { next.leftSetPoints = leftSets }
        if let rightSets { next.rightSetPoints = rightSets }
        if let currentSet { next.currentSet = max(1, currentSet) }
        if let arrowsPerSet { next.arrowsPerSet = max(1, arrowsPerSet) }
        if let arrowsLeftThisSet { next.arrowsLeftThisSet = max(0, arrowsLeftThisSet) }
        if let arrowsRightThisSet { next.arrowsRightThisSet = max(0, arrowsRightThisSet) }
        if let currentShooterIsLeft { next.currentShooterIsLeft = currentShooterIsLeft }
        if let openingShooterIsLeft { next.openingShooterIsLeft = openingShooterIsLeft }
        if let sidesSwapped { next.sidesSwapped = sidesSwapped }
        sessionStore.replaceDisplayedState(next)
        syncTeamsFromMatch()
    }
}

/// 射箭中间层：发球箭头 + 左右半区点击，仅比左右半区高一层，由 Template 插在按钮与菜单之下；编辑模式下不显示、不响应，与羽毛球等共用模板行为一致
private struct ArcheryMiddleLayer: View {
    var viewModel: ArcheryViewModel
    @Binding var showArrowPicker: Bool
    var controller: ArcheryScoreboardController
    var isEditMode: Bool
    var scoringLocked: Bool = false

    var body: some View {
        Group {
            if !isEditMode && !viewModel.gameFinished && !scoringLocked {
                GeometryReader { geo in
                    let indicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                        halfViewportSize: CGSize(width: geo.size.width / 2, height: geo.size.height)
                    )
                    CenterLineServeIndicator(
                        isLeftServing: viewModel.teamScreenLayout.screenSide(
                            of: viewModel.currentShooterIsLeft ? .team0 : .team1
                        ) == .left,
                        triangleSize: indicatorSize
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .allowsHitTesting(false)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: geo.size.width / 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.currentShooterIsLeft = viewModel.teamScreenLayout.engineSide(onScreen: .left) == .left
                                showArrowPicker = true
                                controller.performVibration(type: .light)
                            }
                        Color.clear
                            .frame(width: geo.size.width / 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.currentShooterIsLeft = viewModel.teamScreenLayout.engineSide(onScreen: .right) == .left
                                showArrowPicker = true
                                controller.performVibration(type: .light)
                            }
                    }
                }
                .padding(.top, 80)
                .padding(.bottom, 88)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ArcheryScoreboardView()
    }
}
