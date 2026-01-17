//
//  TennisScoreboardView.swift
//  jifen
//
//  Tennis scoreboard view
//

import SwiftUI

struct TennisScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var controller = TennisController()
    @State private var viewModel = TennisViewModel()
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
                    gameType: .tennis,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .team,
                    scoreTextProvider: { isLeft, _ in
                        viewModel.scoreDisplay(isLeft: isLeft)
                    }
                ),
                onBack: { dismiss() }
            )
            
            if viewModel.isTieBreak {
                TieBreakBadge()
            }
            
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
        .navigationTitle("网球")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()
            
            viewModel.setOnGameEndCallback { leftGames, rightGames, gameNumber in
                handleGameEnd(leftGames: leftGames, rightGames: rightGames, gameNumber: gameNumber)
            }
            
            viewModel.setOnSetEndCallback { data in
                handleSetEnd(data: data)
            }
            
            viewModel.setOnSideChangeCallback {
                handleSideChange()
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
    
    // MARK: - Game End Handler
    
    private func handleGameEnd(leftGames: Int, rightGames: Int, gameNumber: Int) {
        showToastMessage("第\(gameNumber)局结束，局分 \(leftGames)-\(rightGames)")
    }
    
    // MARK: - Set End Handler
    
    private func handleSetEnd(data: SetEndCallbackData) {
        isSetTransitioning = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showToastMessage("第\(data.setNumber)盘结束，\(data.winnerName)获胜，局分 \(data.finalLeftScore)-\(data.finalRightScore)")
            data.continueUpdate()
            
            if data.isGameFinished {
                showGameFinishedOverlay = true
                isSetTransitioning = false
                return
            }
            
            startRestCountdown(seconds: 120, message: "盘间休息") {
                if data.shouldChangeSides {
                    handleSideChange()
                }
                isSetTransitioning = false
            }
        }
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
        
                let leftGames = viewModel.leftTeam.games ?? 0
        
                let rightGames = viewModel.rightTeam.games ?? 0
        
                
        
                var winner: String? = nil
        
                if viewModel.gameFinished {
        
                    if leftSets > rightSets {
        
                        winner = "left"
        
                    } else if rightSets > leftSets {
        
                        winner = "right"
        
                    }
        
                }
        
                
        
                controller.saveScoreboardRecord(
        
                    id: "tennis_\(Int(controller.getGameStartTime().timeIntervalSince1970))_\(Int(endTime.timeIntervalSince1970))",
        
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
        
                    extraData: [
        
                        "finalLeftGames": leftGames,
        
                        "finalRightGames": rightGames,
        
                    ]
        
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
        
        
        
        private struct TieBreakBadge: View {
        
            var body: some View {
        
                VStack {
        
                    Text("抢七")
        
                        .font(.system(size: 16, weight: .bold))
        
                        .foregroundColor(.white)
        
                        .padding(.horizontal, 16)
        
                        .padding(.vertical, 8)
        
                        .background(
        
                            Capsule()
        
                                .fill(Color.black.opacity(0.6))
        
                        )
        
                        .padding(.top, 20)
        
                    
        
                    Spacer()
        
                }
        
            }
        
        }
        
        
        
        #Preview {
        
            TennisScoreboardView()
        
        }
        
        