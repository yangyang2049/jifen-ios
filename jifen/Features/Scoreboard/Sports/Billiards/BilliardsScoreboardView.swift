//
//  BilliardsScoreboardView.swift
//  jifen
//
//  台球：左右半区 +1，对齐鸿蒙/安卓 S1 线分（0…9999、草稿、结束比赛）。
//

import SwiftUI
import RecordCore
import ScoreCore

enum BilliardsRecordIdentity {
    static func initial(resuming recordID: String?) -> String {
        recordID ?? UUID().uuidString
    }

    static func next() -> String {
        UUID().uuidString
    }
}

struct BilliardsScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller: BilliardsScoreboardController
    @State private var viewModel: LineScoreViewModel
    @State private var responsiveScoreFontSize: CGFloat = ScoreboardConstants.baseMainScoreFontSize
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
        let c = BilliardsScoreboardController()
        _controller = State(initialValue: c)
        _viewModel = State(initialValue: LineScoreViewModel(controller: c, rules: .nonNegative))
        _recordID = State(initialValue: BilliardsRecordIdentity.initial(resuming: initialResumeSessionId))
    }

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .billiards,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .team,
                    scoreTextProvider: { _, team in "\(team.score)" },
                    showEndGame: true,
                    showSettleMatch: true
                ),
                onBack: {
                    saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                    onNavigationBack?()
                    dismiss()
                }
            )

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: winnerName,
                    gameType: .billiards,
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
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("done", value: "完成", comment: "")) {
                                showFinishedRecordDetail = false
                            }
                        }
                    }
            }
        }
        .navigationTitle(NSLocalizedString("game_billiards", comment: "Billiards"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.applyStandardTeamNamesIfNeeded()
            if let setup = initialSetup {
                if !setup.team1Name.isEmpty { viewModel.leftTeam.name = setup.team1Name }
                if !setup.team2Name.isEmpty { viewModel.rightTeam.name = setup.team2Name }
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
        // Preserve the completed match before switching identity. A new match
        // must not reuse the resumed/timestamp-derived record or its undo log.
        saveGameRecordInRealTime(isGameFinished: true)

        let freshState = viewModel.makeFreshMatchState()
        controller.beginNewMatch()
        recordID = BilliardsRecordIdentity.next()
        viewModel.restoreSession(state: freshState, history: [])
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
            viewModel.restoreSession(state: resumeState.state, history: resumeState.undoHistory)
            return
        }

        viewModel.leftTeam.name = record.team1Name
        viewModel.rightTeam.name = record.team2Name
        viewModel.leftTeam.score = record.team1FinalScore
        viewModel.rightTeam.score = record.team2FinalScore
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
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to encode billiards record \(recordID)")
            return
        }
        var record = ScoreboardRecord(
            id: recordID,
            gameType: .billiards,
            startTime: start,
            endTime: endTime,
            duration: endTime.timeIntervalSince(start),
            team1Name: viewModel.leftTeam.name,
            team2Name: viewModel.rightTeam.name,
            team1FinalScore: viewModel.leftTeam.score,
            team2FinalScore: viewModel.rightTeam.score,
            winner: winner,
            actions: controller.getGameActions(),
            totalScoreChanges: controller.getGameActions().count,
            extraData: [
                "schemaVersion": AnyCodable(4),
                "canonicalGameType": AnyCodable(GameType.billiards.canonicalScoreboardIdentifier)
            ],
            projectConfiguration: [
                "minimumScore": AnyCodable(0),
                "maximumScore": AnyCodable(9_999)
            ],
            stateSnapshot: snapshotData,
            status: .finished
        )
        let detailed = ScoreboardRecordActionAdapter.actions(for: record)
        record.detailedActions = detailed
        record.setResults = ScoreboardRecordActionAdapter.setResults(from: detailed)
        do {
            try ScoreboardLifecyclePersistence.save(record, finished: finished)
            if finished {
                ScoreboardRecordsViewModel.shared.refreshRecords()
            }
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to save billiards record \(recordID)")
        }
    }
}

#Preview {
    NavigationStack {
        BilliardsScoreboardView()
    }
}
