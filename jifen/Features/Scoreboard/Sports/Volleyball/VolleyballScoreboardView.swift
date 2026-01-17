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
        ZStack {
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

            // Sets information overlay
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        // Current set number
                        Text("第\(viewModel.currentSet)局")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)

                        // Sets won by each team
                        HStack(spacing: 20) {
                            Text("\(viewModel.leftTeam.name): \(viewModel.leftTeam.sets ?? 0)")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(6)

                            Text("\(viewModel.rightTeam.name): \(viewModel.rightTeam.sets ?? 0)")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.bottom, 40)
                    .padding(.trailing, 20)
                }
            }
        }
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
