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
            // Unlock orientation to return to portrait
            OrientationLock.shared.unlock()
        }
    }
}

struct VolleyballScoreboardView_Previews: PreviewProvider {
    static var previews: some View {
        VolleyballScoreboardView()
    }
}
