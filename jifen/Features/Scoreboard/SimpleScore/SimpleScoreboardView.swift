//
//  SimpleScoreboardView.swift
//  jifen
//
//  简单计分：左右两队；对齐鸿蒙/安卓 SimpleScore（草稿、结束比赛、自定义加减分）。
//

import ScoreCore
import SwiftUI

struct SimpleScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller: SimpleScoreboardController
    @State private var viewModel: LineScoreViewModel
    @State private var responsiveScoreFontSize: CGFloat = ScoreboardConstants.baseMainScoreFontSize
    @State private var customAdjustEnabled: Bool
    @State private var adjustTargetIsLeft: Bool?
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var recordID: String

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
        let c = SimpleScoreboardController()
        _controller = State(initialValue: c)
        _viewModel = State(initialValue: LineScoreViewModel(
            controller: c,
            rules: .freeCounter,
            defaultNames: DefaultParticipantNames.resolve(for: .simpleScore)
        ))
        _recordID = State(initialValue: ScoreboardRecordIdentity.initial(
            prefix: GameType.simpleScore.canonicalScoreboardIdentifier,
            resuming: initialResumeSessionId
        ))
        let enabled = initialSetup?.multiScoreCustomAdjustEnabled
            ?? PreferencesManager.shared.simpleScoreCustomAdjustEnabled
        _customAdjustEnabled = State(initialValue: enabled)
    }

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .simpleScore,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: ScoreboardCommonNamePolicy.nameType(for: .simpleScore),
                    scoreTextProvider: { _, team in "\(team.score)" },
                    onEditModeChange: { editing in
                        if editing { adjustTargetIsLeft = nil }
                    },
                    showEndGame: true,
                    showSettleMatch: true,
                    onScorePanelTap: customAdjustEnabled
                        ? { isLeft in
                            guard !viewModel.gameFinished else { return }
                            adjustTargetIsLeft = isLeft
                        }
                        : nil
                ),
                onBack: {
                    saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                    onNavigationBack?()
                    dismiss()
                }
            )

            if let isLeft = adjustTargetIsLeft {
                ScoreCustomAdjustPanel(
                    targetName: isLeft ? viewModel.leftTeam.name : viewModel.rightTeam.name,
                    currentScore: isLeft ? viewModel.leftTeam.score : viewModel.rightTeam.score,
                    onDismiss: { adjustTargetIsLeft = nil },
                    onAdjust: { delta in
                        viewModel.adjustScore(isLeft: isLeft, delta: delta)
                        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                    }
                )
            }

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: winnerName,
                    gameType: .simpleScore,
                    leftName: viewModel.leftTeam.name,
                    rightName: viewModel.rightTeam.name,
                    leftScore: viewModel.leftTeam.score,
                    rightScore: viewModel.rightTeam.score,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        saveGameRecordInRealTime(isGameFinished: true)
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(
                            text: "\(viewModel.leftTeam.name) \(viewModel.leftTeam.score) - \(viewModel.rightTeam.score) \(viewModel.rightTeam.name)"
                        )
                    },
                    onExit: {
                        saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                        onNavigationBack?()
                        dismiss()
                    }
                )
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
        .navigationTitle(NSLocalizedString("game_simple_score", comment: "Simple Score"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            if let setup = initialSetup {
                if !setup.team1Name.isEmpty { viewModel.leftTeam.name = setup.team1Name }
                if !setup.team2Name.isEmpty { viewModel.rightTeam.name = setup.team2Name }
                if let flag = setup.multiScoreCustomAdjustEnabled {
                    customAdjustEnabled = flag
                }
                onSetupConsumed?()
            }
            restoreResumeIfNeeded()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            min(proxy.size.width, proxy.size.height)
        } action: { shortSide in
            responsiveScoreFontSize = calculateResponsiveScoreFontSize(containerShortSide: shortSide)
        }
        .onChange(of: viewModel.gameFinished) { _, finished in
            if finished {
                showGameOverDialog = true
                saveGameRecordInRealTime(isGameFinished: true)
            }
        }
        .onDisappear {
            saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
        }
    }

    private var winnerName: String {
        guard viewModel.gameFinished else { return "" }
        if viewModel.leftTeam.score > viewModel.rightTeam.score { return viewModel.leftTeam.name }
        if viewModel.rightTeam.score > viewModel.leftTeam.score { return viewModel.rightTeam.name }
        return ""
    }

    private func calculateResponsiveScoreFontSize(containerShortSide: CGFloat) -> CGFloat {
        ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: containerShortSide)
    }

    private func startNewMatch() {
        saveGameRecordInRealTime(isGameFinished: true)

        let freshState = viewModel.makeFreshMatchState()
        controller.beginNewMatch()
        recordID = ScoreboardRecordIdentity.next(
            prefix: GameType.simpleScore.canonicalScoreboardIdentifier
        )
        viewModel.restoreSession(state: freshState, history: [])
        adjustTargetIsLeft = nil
        showGameOverDialog = false
    }

    private func restoreResumeIfNeeded() {
        guard let recordId = initialResumeSessionId,
              let record = ManualResumeSessionStore.load(recordID: recordId) else {
            return
        }

        controller.gameStartTime = record.startTime
        controller.gameActions = record.actions
        controller.gameRecordSaved = false

        if let data = record.stateSnapshot,
           let resumeState = try? JSONDecoder().decode(LineScoreResumeState.self, from: data) {
            controller.gameActions = resumeState.intentTimeline
            viewModel.restoreSession(resumeState)
            if let flag = record.extraData?["multiScoreCustomAdjustEnabled"]?.value as? Bool {
                customAdjustEnabled = flag
            }
            return
        }

        viewModel.leftTeam.name = record.team1Name
        viewModel.rightTeam.name = record.team2Name
        viewModel.leftTeam.score = record.team1FinalScore
        viewModel.rightTeam.score = record.team2FinalScore

        if let flag = record.extraData?["multiScoreCustomAdjustEnabled"]?.value as? Bool {
            customAdjustEnabled = flag
        }
    }

    private func saveGameRecordInRealTime(isGameFinished: Bool = false) {
        let hasProgress = !controller.getGameActions().isEmpty
            || viewModel.leftTeam.score != 0
            || viewModel.rightTeam.score != 0
            || isGameFinished
            || viewModel.gameFinished
        guard hasProgress else { return }

        let finished = isGameFinished || viewModel.gameFinished
        let endTime = Date()
        let start = controller.getGameStartTime()
        var winner: String?
        if finished {
            if viewModel.leftTeam.score > viewModel.rightTeam.score {
                winner = "left"
            } else if viewModel.rightTeam.score > viewModel.leftTeam.score {
                winner = "right"
            }
        }

        let resumeState = LineScoreResumeState(
            state: viewModel.sessionState,
            undoHistory: viewModel.resumeHistory,
            intentTimeline: controller.getGameActions()
        )
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(resumeState)
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "Failed to encode simple score record \(recordID)"
            )
            return
        }

        controller.saveScoreboardRecord(
            id: recordID,
            endTime: endTime,
            duration: endTime.timeIntervalSince(start),
            team1Name: viewModel.leftTeam.name,
            team2Name: viewModel.rightTeam.name,
            team1FinalScore: viewModel.leftTeam.score,
            team2FinalScore: viewModel.rightTeam.score,
            winner: winner,
            totalScoreChanges: controller.getGameActions().count,
            extraData: [
                "multiScoreCustomAdjustEnabled": customAdjustEnabled
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: ScoreCore.GameType.simpleScore.rawValue,
                "minimumScore": LineScoreRuleSet.freeCounter.minimum,
                "maximumScore": LineScoreRuleSet.freeCounter.maximum
            ],
            stateSnapshot: snapshotData,
            isFinished: finished
        )
    }
}

#Preview {
    NavigationStack {
        SimpleScoreboardView()
    }
}
