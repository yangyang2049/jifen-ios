//
//  PingPongScoreboardView.swift
//  jifen
//
//  Ping pong scoreboard view
//

import SwiftUI

struct PingPongScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var controller = PingPongController()
    @State private var viewModel = PingPongViewModel()
    @State private var isSetTransitioning: Bool = false
    @State private var showGameFinishedOverlay: Bool = false
    @State private var responsiveScoreFontSize: CGFloat = 120
    @State private var showRestOverlay: Bool = false
    @State private var restMessage: String = ""
    @State private var restRemaining: Int = 0
    @State private var restTimer: Timer? = nil
    @State private var showSettings: Bool = false
    @State private var settingsMaxSets: Int = 5
    @State private var settingsPointsPerSet: Int = 11
    @State private var settingsAutoChangeSides: Bool = true
    @State private var settingsApplied = false
    
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
                onBack: { dismiss() }
            )
            
            // Game finished overlay
            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: viewModel.getWinnerName())
            }
            
            if showRestOverlay {
                RestCountdownOverlay(message: restMessage, remainingSeconds: restRemaining)
            }
            
            // Toast message
            if showToast {
                ToastView(message: toastMessage)
                    .transition(.opacity.combined(with: .scale))
            }
            
            VStack {
                HStack {
                    Button(action: {
                        showSettings = true
                        controller.performVibration(type: .medium)
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.25))
                            )
                    }
                    .padding(.leading, ScoreboardConstants.buttonPadding)
                    .padding(.top, ScoreboardConstants.buttonPadding)
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .navigationTitle("乒乓球")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true) // ADDED BACK
        .toolbar(.hidden, for: .navigationBar) // ADDED BACK
        .preferredColorScheme(.dark)
        .lockOrientation(.landscape) // Lock to landscape mode
        .onAppear {
            viewModel.controller = controller
            applySettings()
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
            restTimer?.invalidate()
            restTimer = nil
            // Show tab bar when leaving
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = false
            }
            // Save game record before leaving
            saveGameRecord()
            // Unlock orientation to return to portrait (this will force portrait)
            OrientationLock.shared.unlock()
        }
        .onChange(of: viewModel.gameFinished) { oldValue, newValue in
            if newValue {
                showGameFinishedOverlay = true
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if !settingsApplied {
                showToastMessage("已撤销")
            }
            settingsApplied = false
        }) {
            PingPongSettingsSheet(
                maxSets: $settingsMaxSets,
                pointsPerSet: $settingsPointsPerSet,
                autoChangeSides: $settingsAutoChangeSides,
                onApply: {
                    settingsApplied = true
                    applySettings(resetGame: true)
                }
            )
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
        if viewModel.autoChangeSides {
            showToastMessage("换边")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                viewModel.exchangeSides()
            }
        } else {
            showToastMessage("请手动换边")
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

    // MARK: - Settings
    
    private func applySettings(resetGame: Bool = false) {
        viewModel.setConfig(
            maxSets: settingsMaxSets,
            pointsPerSet: settingsPointsPerSet,
            autoChangeSides: settingsAutoChangeSides
        )
        if resetGame {
            viewModel.reset()
            showGameFinishedOverlay = false
            showRestOverlay = false
            restTimer?.invalidate()
            restTimer = nil
            controller.gameStartTime = Date()
            controller.gameRecordSaved = false
            controller.gameActions = []
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
    
    // MARK: - Game Record Saving
    
    private func saveGameRecord() {
        // Check if already saved or no actions
        if controller.isRecordSaved() || controller.getGameActions().isEmpty {
            return
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(controller.getGameStartTime())
        let leftSets = viewModel.leftTeam.sets ?? 0
        let rightSets = viewModel.rightTeam.sets ?? 0
        
        // Only set winner if game is truly finished
        var winner: String? = nil
        if viewModel.gameFinished {
            if leftSets > rightSets {
                winner = "left"
            } else if rightSets > leftSets {
                winner = "right"
            }
        }
        
        // Save to controller with set scores
        controller.saveScoreboardRecord(
            id: "pingpong_\(Int(controller.getGameStartTime().timeIntervalSince1970))_\(Int(endTime.timeIntervalSince1970))",
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
                "maxSets": viewModel.maxSets,
                "pointsPerSet": viewModel.pointsPerSet,
                "autoChangeSides": viewModel.autoChangeSides
            ]
        )
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

private struct PingPongSettingsSheet: View {
    @Binding var maxSets: Int
    @Binding var pointsPerSet: Int
    @Binding var autoChangeSides: Bool
    let onApply: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("局数")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Picker("局数", selection: $maxSets) {
                        Text("3局2胜").tag(3)
                        Text("5局3胜").tag(5)
                        Text("7局4胜").tag(7)
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("每局分数")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Picker("每局分数", selection: $pointsPerSet) {
                        Text("11分").tag(11)
                        Text("21分").tag(21)
                    }
                    .pickerStyle(.segmented)
                }
                
                Toggle(isOn: $autoChangeSides) {
                    Text("自动换边")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: Theme.accentColor))
                
                Spacer()
                
                Button(action: {
                    onApply()
                    dismiss()
                }) {
                    Text("开始比赛")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.accentColor)
                        )
                }
            }
            .padding(24)
            .background(Theme.backgroundColor)
            .navigationTitle("乒乓球设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        PingPongScoreboardView()
    }
}
