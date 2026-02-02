//
//  BasketballScoreboardView.swift
//  jifen
//
//  Basketball scoreboard view
//

import SwiftUI

struct BasketballScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    @State private var controller = BasketballController()
    @State private var viewModel = BasketballViewModel()
    @State private var showGameFinishedOverlay: Bool = false

    var body: some View {
        ZStack {
        ScoreboardTemplate(
            config: TemplateConfig(
                gameType: .basketball,
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

            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: viewModel.getWinnerName())
            }
        }
        .navigationTitle(NSLocalizedString("game_basketball", comment: "Basketball"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            
            // Hide tab bar
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = true
            }
        }
        .onChange(of: viewModel.gameFinished) { _, newValue in
            if newValue {
                showGameFinishedOverlay = true
            }
        }
        .onDisappear {
            // Save record when leaving (for incomplete games)
            print("[BasketballScoreboardView] 📤 View disappearing, saving record")
            viewModel.saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)

            // Show tab bar when leaving
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = false
            }
        }
    }
}

struct BasketballScoreboardView_Previews: PreviewProvider {
    static var previews: some View {
        BasketballScoreboardView()
    }
}
