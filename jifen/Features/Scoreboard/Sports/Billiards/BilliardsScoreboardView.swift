//
//  BilliardsScoreboardView.swift
//  jifen
//
//  台球：左右半区 +1，对齐鸿蒙/安卓 S1 线分（0…9999、草稿、结束比赛）。
//

import SwiftUI
import RecordCore
import ScoreCore

private struct LineScoreSessionArchive: Codable {
    var schemaVersion = 1
    let state: LineScoreState
    let undoHistory: [LineScoreViewModel.HistoryEntry]
    let intentTimeline: [String]
}

struct BilliardsScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller: BilliardsScoreboardController
    @State private var viewModel: LineScoreViewModel
    @State private var responsiveScoreFontSize: CGFloat = ScoreboardConstants.baseMainScoreFontSize
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false

    private var recordID: String {
        initialRecordId ?? "billiards_\(Int(controller.gameStartTime.timeIntervalSince1970))"
    }

    init(
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let c = BilliardsScoreboardController()
        _controller = State(initialValue: c)
        _viewModel = State(initialValue: LineScoreViewModel(controller: c, rules: .nonNegative))
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
                        showGameOverDialog = false
                        viewModel.reset()
                        controller.recordScoreAction(action: "reset")
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
            applyDefaultNamesIfNeeded()
            if let setup = initialSetup {
                if !setup.team1Name.isEmpty { viewModel.leftTeam.name = setup.team1Name }
                if !setup.team2Name.isEmpty { viewModel.rightTeam.name = setup.team2Name }
                onSetupConsumed?()
            }
            restoreDraftIfNeeded()
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

    private func applyDefaultNamesIfNeeded() {
        let red = NSLocalizedString("watch_team_red", value: "红方", comment: "")
        let blue = NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
        if viewModel.leftTeam.name == NSLocalizedString("red_team", comment: "") {
            viewModel.leftTeam.name = red
        }
        if viewModel.rightTeam.name == NSLocalizedString("blue_team", comment: "") {
            viewModel.rightTeam.name = blue
        }
        if viewModel.leftTeam.name.isEmpty { viewModel.leftTeam.name = red }
        if viewModel.rightTeam.name.isEmpty { viewModel.rightTeam.name = blue }
    }

    private func calculateResponsiveScoreFontSize(containerShortSide: CGFloat) -> CGFloat {
        ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: containerShortSide)
    }

    private func restoreDraftIfNeeded() {
        guard let recordId = initialRecordId,
              let record = ScoreboardRecordManager.shared.getRecordById(recordId),
              record.status == .draft else {
            return
        }

        controller.gameStartTime = record.startTime
        controller.gameActions = record.actions
        controller.gameRecordSaved = false

        if let data = record.stateSnapshot,
           let archive = try? JSONDecoder().decode(LineScoreSessionArchive.self, from: data) {
            controller.gameActions = archive.intentTimeline
            viewModel.restoreSession(state: archive.state, history: archive.undoHistory)
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

        let archive = LineScoreSessionArchive(
            state: viewModel.sessionState,
            undoHistory: viewModel.resumeHistory,
            intentTimeline: controller.getGameActions()
        )
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(archive)
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
            status: finished ? .finished : .draft
        )
        let detailed = ScoreboardRecordActionAdapter.actions(for: record)
        record.detailedActions = detailed
        record.setResults = ScoreboardRecordActionAdapter.setResults(from: detailed)
        do {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
            ScoreboardRecordsViewModel.shared.refreshRecords()
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
