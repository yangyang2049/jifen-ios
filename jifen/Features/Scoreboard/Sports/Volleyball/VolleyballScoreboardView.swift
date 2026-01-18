//
//  VolleyballScoreboardView.swift
//  jifen
//
//  Volleyball scoreboard view
//

import SwiftUI

struct VolleyballScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var controller = VolleyballController()
    @State private var viewModel = VolleyballViewModel()

    var body: some View {
        ScoreboardTemplate(
            config: TemplateConfig(
                gameType: .volleyball,
                controller: controller,
                viewModel: viewModel,
                scoreFontSize: 120,
                nameType: .team
            ),
            onBack: { dismiss() }
        )
        .navigationTitle(NSLocalizedString("game_volleyball", comment: "Volleyball"))
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
