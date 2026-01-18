//
//  PingPongScoreboardView.swift
//  jifen
//
//  Ping pong scoreboard view
//

import SwiftUI

struct PingPongScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    @State private var controller = PingPongController()
    @State private var viewModel = PingPongViewModel()
    @State private var isSetTransitioning: Bool = false
    @State private var showGameFinishedOverlay: Bool = false
    @State private var responsiveScoreFontSize: CGFloat = 120
    @State private var showRestOverlay: Bool = false
    @State private var restMessage: String = ""
    @State private var restRemaining: Int = 0
    @State private var restTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .pingpong,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
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
            
            // Game finished overlay
            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: viewModel.getWinnerName())
            }
            
            if showRestOverlay {
                RestCountdownOverlay(message: restMessage, remainingSeconds: restRemaining) {
                    // Close button - skip to next set
                    restTimer?.invalidate()
                    restTimer = nil
                    showRestOverlay = false
                    // Trigger the completion callback immediately
                    startRestCountdown(seconds: 0, message: restMessage) {
                        // Skip side change check for close button - just continue
                        isSetTransitioning = false
                    }
                }
            }
            
            // Toast message
            if showToast {
                ToastView(message: toastMessage)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .navigationTitle(NSLocalizedString("game_pingpong", comment: "Ping Pong"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .lockOrientation(.landscape) // Lock to landscape mode
        .onAppear {
            viewModel.controller = controller
            // Calculate responsive font size
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()
            
            // Register set end callback
            viewModel.setOnSetEndCallback { data in
                handleSetEnd(data: data)
            }
            
            // Register deciding set sides change callback
            viewModel.setOnDecidingSetSidesChangeCallback {
                handleDecidingSetSidesChange()
            }
            
            // Hide tab bar
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = true
            }
        }
        .onDisappear {
            // Save record when leaving (for incomplete games)
            print("[PingPongScoreboardView] 📤 View disappearing, saving record")
            viewModel.saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)

            restTimer?.invalidate()
            restTimer = nil
            // Show tab bar when leaving
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = false
            }
            // Unlock orientation to return to portrait (this will force portrait)
            OrientationLock.shared.unlock()
        }
        .onChange(of: viewModel.gameFinished) { oldValue, newValue in
            if newValue {
                showGameFinishedOverlay = true
            }
        }
    }
    
    // MARK: - Set End Handler
    
    private func handleSetEnd(data: SetEndCallbackData) {
        isSetTransitioning = true
        
        // 1. Keep current score displayed for 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 2. Show set end toast
            showToastMessage("第\(data.setNumber)局结束，\(data.winnerName)获胜，比分 \(data.finalLeftScore)-\(data.finalRightScore)")
            
            // 3. Update state (score, sets, etc.)
            data.continueUpdate()
            
            // If game finished, show game finished overlay
            if data.isGameFinished {
                showGameFinishedOverlay = true
                isSetTransitioning = false
                return
            }
            
            startRestCountdown(seconds: 60, message: "局间休息") {
                if data.shouldChangeSides {
                    handleSideChange()
                }
                isSetTransitioning = false
            }
        }
    }
    
    private func handleDecidingSetSidesChange() {
        isSetTransitioning = true
        
        // 1. Keep current score displayed for 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            handleSideChange()
            isSetTransitioning = false
        }
    }

    private func handleSideChange() {
        showToastMessage("换边")
    }
    
    // MARK: - Responsive Font Size
    
    private func calculateResponsiveScoreFontSize() -> CGFloat {
        let baseSize: CGFloat = 96
        let baseWidth: CGFloat = 360
        let scaleFactor: CGFloat = 0.1
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let screenWidth = window.bounds.width
            let fontSize = baseSize + (screenWidth - baseWidth) * scaleFactor
            return max(baseSize, min(fontSize, 150))
        }
        
        return baseSize
    }

    // MARK: - Rest Countdown
    
    private func startRestCountdown(seconds: Int, message: String, onComplete: @escaping () -> Void) {
        restTimer?.invalidate()
        restRemaining = seconds
        restMessage = message
        showRestOverlay = true
        
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.restRemaining <= 1 {
                timer.invalidate()
                self.restTimer = nil
                self.showRestOverlay = false
                onComplete()
            } else {
                self.restRemaining -= 1
            }
        }
    }
    

    
    // MARK: - Toast Message
    
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    
    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }
}

#Preview {
    NavigationStack {
        PingPongScoreboardView()
    }
}
