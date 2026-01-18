//
//  FootballScoreboardView.swift
//  jifen
//
//  Football scoreboard view
//

import SwiftUI

struct FootballScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    @State private var controller = FootballController()
    @State private var viewModel = FootballViewModel()

    var body: some View {
        ScoreboardTemplate(
            config: TemplateConfig(
                gameType: .football,
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
        .navigationTitle(NSLocalizedString("game_football", comment: "Football"))
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
        .onDisappear {
            // Save record when leaving (for incomplete games)
            print("[FootballScoreboardView] 📤 View disappearing, saving record")
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

struct FootballScoreboardView_Previews: PreviewProvider {
    static var previews: some View {
        FootballScoreboardView()
    }
}
