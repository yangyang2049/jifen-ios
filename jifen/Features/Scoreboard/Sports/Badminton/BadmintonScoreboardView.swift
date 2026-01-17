//
//  BadmintonScoreboardView.swift
//  jifen
//
//  Badminton scoreboard view
//

import SwiftUI

struct BadmintonScoreboardView: View {
    @Environment(\.dismiss) var dismiss
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
                onBack: { dismiss() }
            )
            
            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: viewModel.getWinnerName())
            }
            
            if showRestOverlay {
                RestCountdownOverlay(message: restMessage, remainingSeconds: restRemaining)
            }
            
            if showToast {
                ToastView(message: toastMessage)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .navigationTitle("羽毛球")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true) // ADDED BACK
        .toolbar(.hidden, for: .navigationBar) // ADDED BACK
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
            restTimer?.invalidate()
            restTimer = nil
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = false
            }
            
            saveGameRecord()
            OrientationLock.shared.unlock()
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
        if viewModel.autoChangeSides {
            showToastMessage("换边")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                viewModel.exchangeSides()
            }
        } else {
            showToastMessage("请手动换边")
        }
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
        
            
        
            // MARK: - Game Record Saving
        
            
        
            private func saveGameRecord() {
        
                if controller.isRecordSaved() || controller.getGameActions().isEmpty {
        
                    return
        
                }
        
                
        
                let endTime = Date()
        
                let duration = endTime.timeIntervalSince(controller.getGameStartTime())
        
                let leftSets = viewModel.leftTeam.sets ?? 0
        
                let rightSets = viewModel.rightTeam.sets ?? 0
        
                
        
                var winner: String? = nil
        
                if viewModel.gameFinished {
        
                    if leftSets > rightSets {
        
                        winner = "left"
        
                    } else if rightSets > leftSets {
        
                        winner = "right"
        
                    }
        
                }
        
                
        
                controller.saveScoreboardRecord(
        
                    id: "badminton_\(Int(controller.getGameStartTime().timeIntervalSince1970))_\(Int(endTime.timeIntervalSince1970))",
        
                    endTime: endTime,
        
                    duration: duration,
        
                    team1Name: viewModel.leftTeam.name,
        
                    team2Name: viewModel.rightTeam.name,
        
                    team1FinalScore: leftSets,
        
                    team2FinalScore: rightSets,
        
                    team1SetScore: leftSets,
        
                    team2SetScore: rightSets,
        
                    winner: winner,
        
                    totalScoreChanges: controller.getGameActions().count,
        
                    extraData: [:]
        
                )
        
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
        
        