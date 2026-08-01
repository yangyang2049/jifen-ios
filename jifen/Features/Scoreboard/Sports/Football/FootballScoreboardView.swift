//
//  FootballScoreboardView.swift
//  jifen
//
//  Football scoreboard view
//

import ScoreCore
import SwiftUI
import UIKit

struct FootballScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    @State private var controller: FootballScoreboardController
    @State private var viewModel: FootballViewModel
    @State private var showGameOverDialog: Bool = false
    @State private var showFinishedRecordDetail = false
    @State private var recordID: String

    init(
        onNavigationBack: (() -> Void)? = nil,
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil
    ) {
        self.onNavigationBack = onNavigationBack
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        let controller = FootballScoreboardController()
        _controller = State(initialValue: controller)
        _viewModel = State(initialValue: FootballViewModel(controller: controller))
        _recordID = State(initialValue: ScoreboardRecordIdentity.initial(
            prefix: GameType.football.canonicalScoreboardIdentifier,
            resuming: initialResumeSessionId
        ))
    }

    var body: some View {
        ZStack {
        ScoreboardTemplate(
            config: TemplateConfig(
                gameType: .football,
                controller: controller,
                viewModel: viewModel,
                scoreFontSize: 120,
                nameType: .team,
                showSettleMatch: true
            ),
            onBack: {
                if let onNavigationBack = onNavigationBack {
                    onNavigationBack()
                } else {
                    dismiss()
                }
                }
            )

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: viewModel.getWinnerName(),
                    gameType: .football,
                    leftName: viewModel.leftTeam.name,
                    rightName: viewModel.rightTeam.name,
                    leftScore: viewModel.leftTeam.score,
                    rightScore: viewModel.rightTeam.score,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        viewModel.saveGameRecordInRealTime(
                            recordID: recordID,
                            isGameFinished: viewModel.gameFinished
                        )
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(
                            text: "\(viewModel.leftTeam.name) \(viewModel.leftTeam.score) - \(viewModel.rightTeam.score) \(viewModel.rightTeam.name)"
                        )
                    },
                    onExit: {
                        viewModel.saveGameRecordInRealTime(
                            recordID: recordID,
                            isGameFinished: viewModel.gameFinished
                        )
                        if let onNavigationBack {
                            onNavigationBack()
                        } else {
                            dismiss()
                        }
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
        .navigationTitle(NSLocalizedString("game_football", comment: "Football"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            if let setup = initialSetup {
                viewModel.leftTeam.name = setup.team1Name.isEmpty
                    ? NSLocalizedString("team_home", comment: "")
                    : setup.team1Name
                viewModel.rightTeam.name = setup.team2Name.isEmpty
                    ? NSLocalizedString("team_away", comment: "")
                    : setup.team2Name
                onSetupConsumed?()
            }
            restoreResumeIfNeeded()
            // Hide tab bar
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = true
            }
        }
        .onChange(of: viewModel.gameFinished) { _, newValue in
            if newValue {
                showGameOverDialog = true
                viewModel.saveGameRecordInRealTime(recordID: recordID, isGameFinished: true)
            }
        }
        .onDisappear {
            // Save record when leaving (for incomplete games)
            #if DEBUG
            print("[FootballScoreboardView] 📤 View disappearing, saving record")
            #endif
            viewModel.saveGameRecordInRealTime(
                recordID: recordID,
                isGameFinished: viewModel.gameFinished
            )

            // Show tab bar when leaving
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = false
            }
        }
    }

    private func startNewMatch() {
        viewModel.saveGameRecordInRealTime(recordID: recordID, isGameFinished: true)

        let freshState = viewModel.makeFreshMatchState()
        controller.beginNewMatch()
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.football.canonicalScoreboardIdentifier)
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
}

struct FootballScoreboardView_Previews: PreviewProvider {
    static var previews: some View {
        FootballScoreboardView()
    }
}
