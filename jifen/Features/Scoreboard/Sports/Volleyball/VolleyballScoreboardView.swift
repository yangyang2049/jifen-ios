//
//  VolleyballScoreboardView.swift
//  jifen
//
//  Volleyball scoreboard view
//

import SwiftUI

struct VolleyballScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    @State private var controller = VolleyballController()
    @State private var viewModel = VolleyballViewModel()
    @State private var showGameFinishedOverlay: Bool = false

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .volleyball,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: 120,
                    nameType: .team
                ),
                onBack: {
                    if let onNavigationBack = onNavigationBack {
                        onNavigationBack()
                    } else {
                        dismiss()
                    }
                }
            )

            if !viewModel.gameFinished {
                serveIndicator
            }

            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: viewModel.getWinnerName())
            }
        }
        .navigationTitle(NSLocalizedString("game_volleyball", comment: "Volleyball"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .lockOrientation(.landscape)
        .onChange(of: viewModel.gameFinished) { _, newValue in
            if newValue {
                showGameFinishedOverlay = true
            }
        }
        .onAppear {
            viewModel.controller = controller
            if let setup = initialSetup {
                viewModel.leftTeam.name = setup.team1Name.isEmpty ? NSLocalizedString("red_team", comment: "") : setup.team1Name
                viewModel.rightTeam.name = setup.team2Name.isEmpty ? NSLocalizedString("blue_team", comment: "") : setup.team2Name
                onSetupConsumed?()
            }
            restoreDraftIfNeeded()
            // Hide tab bar
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = true
            }
        }
        .onDisappear {
            // Save record when leaving (for incomplete games)
            #if DEBUG
            print("[VolleyballScoreboardView] 📤 View disappearing, saving record")
            #endif
            viewModel.saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)

            // Show tab bar when leaving
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = false
            }
        }
    }

    private var serveIndicator: some View {
        CenterLineServeIndicator(isLeftServing: viewModel.isLeftServing)
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

        viewModel.leftTeam.name = record.team1Name
        viewModel.rightTeam.name = record.team2Name
        viewModel.leftTeam.sets = record.team1SetScore ?? record.team1FinalScore
        viewModel.rightTeam.sets = record.team2SetScore ?? record.team2FinalScore
        if let currentLeftScore = record.extraData?["currentLeftScore"]?.value as? Int {
            viewModel.leftTeam.score = currentLeftScore
        }
        if let currentRightScore = record.extraData?["currentRightScore"]?.value as? Int {
            viewModel.rightTeam.score = currentRightScore
        }
        if let isLeftServing = record.extraData?["isLeftServing"]?.value as? Bool {
            viewModel.isLeftServing = isLeftServing
        }
    }
}

struct VolleyballScoreboardView_Previews: PreviewProvider {
    static var previews: some View {
        VolleyballScoreboardView()
    }
}
