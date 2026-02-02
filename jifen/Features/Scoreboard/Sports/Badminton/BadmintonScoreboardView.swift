//
//  BadmintonScoreboardView.swift
//  jifen
//
//  Badminton scoreboard view
//

import SwiftUI

struct BadmintonScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    @State private var controller = BadmintonController()
    @State private var viewModel = BadmintonViewModel()
    @State private var responsiveScoreFontSize: CGFloat = 120
    @State private var showGameFinishedOverlay: Bool = false
    @State private var isSetTransitioning: Bool = false
    
    @State private var showRestOverlay: Bool = false
    @State private var restMessage: String = ""
    @State private var restRemaining: Int = 0
    @State private var restTimer: Timer? = nil
    
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    
    
    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .badminton,
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
            
            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: viewModel.getWinnerName())
            }
            
            if showRestOverlay {
                RestCountdownOverlay(message: restMessage, remainingSeconds: restRemaining, onClose: {
                    restTimer?.invalidate()
                    restTimer = nil
                    showRestOverlay = false
                    startRestCountdown(seconds: 0, message: restMessage) { isSetTransitioning = false }
                }, onUndo: {
                    _ = viewModel.undo()
                    restTimer?.invalidate()
                    restTimer = nil
                    showRestOverlay = false
                    startRestCountdown(seconds: 0, message: restMessage) { isSetTransitioning = false }
                })
            }
            
            if showToast {
                ToastView(message: toastMessage)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .navigationTitle("羽毛球")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()
            
            viewModel.setOnSetEndCallback { data in
                handleSetEnd(data: data)
            }
            
            viewModel.setOnDecidingSetSidesChangeCallback {
                handleDecidingSetSidesChange()
            }
            
            viewModel.setOnMidGameRestCallback {
                handleMidGameRest()
            }
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = true
            }
        }
        .onDisappear {
            // Save record when leaving (for incomplete games)
            print("[BadmintonScoreboardView] 📤 View disappearing, saving record")
            viewModel.saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)

            restTimer?.invalidate()
            restTimer = nil

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = false
            }
        }
        .onChange(of: viewModel.gameFinished) { _, newValue in
            if newValue {
                showGameFinishedOverlay = true
            }
        }
    }
    
    // MARK: - Set End Handler
    
    private func handleSetEnd(data: SetEndCallbackData) {
        isSetTransitioning = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showToastMessage("第\(data.setNumber)局结束，\(data.winnerName)获胜，比分 \(data.finalLeftScore)-\(data.finalRightScore)")
            data.continueUpdate()
            
            if data.isGameFinished {
                showGameFinishedOverlay = true
                isSetTransitioning = false
                return
            }
            
            startRestCountdown(seconds: 120, message: "局间休息") {
                if data.shouldChangeSides {
                    handleSideChange()
                }
                isSetTransitioning = false
            }
        }
    }
    
    private func handleDecidingSetSidesChange() {
        isSetTransitioning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            handleSideChange()
            isSetTransitioning = false
        }
    }
    
    private func handleMidGameRest() {
        startRestCountdown(seconds: 60, message: "中场休息") {}
    }
    
    private func handleSideChange() {
        showToastMessage("换边")
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
        
            
        

        
            
        
            // MARK: - Toast Message
        
            
        
            private func showToastMessage(_ message: String) {
        
                toastMessage = message
        
                showToast = true
        
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        
                    showToast = false
        
                }
        
            }
        
        }
        
        
        
        #Preview {
        
            BadmintonScoreboardView()
        
        }
