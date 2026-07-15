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
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
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
    @State private var isEditMode: Bool = false

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .badminton,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .player,
                    isDoublesModeProvider: { !viewModel.isSingles },
                    contentOverlayProvider: { isEditMode in
                        if isEditMode || viewModel.gameFinished {
                            return AnyView(EmptyView())
                        }
                        return AnyView(serveIndicator(isLeftServing: viewModel.isLeftServing))
                    },
                    onEditModeChange: { isEditMode = $0 }
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
                    let success = viewModel.undo()
                    if success { showToastMessage(NSLocalizedString("undone", value: "已撤销", comment: "Undo done")) }
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
        .navigationTitle(NSLocalizedString("game_badminton", comment: "Badminton"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            if let setup = initialSetup {
                viewModel.leftTeam.name = setup.team1Name.isEmpty ? NSLocalizedString("red_team", comment: "") : setup.team1Name
                viewModel.rightTeam.name = setup.team2Name.isEmpty ? NSLocalizedString("blue_team", comment: "") : setup.team2Name
                if let autoChange = setup.autoChangeSides {
                    viewModel.autoChangeSides = autoChange
                }
                if let singles = setup.isSingles {
                    viewModel.isSingles = singles
                }
                onSetupConsumed?()
            }
            restoreDraftIfNeeded()
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
            #if DEBUG
            print("[BadmintonScoreboardView] 📤 View disappearing, saving record")
            #endif
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

    private func restoreDraftIfNeeded() {
        guard let recordId = initialRecordId,
              let record = ScoreboardRecordManager.shared.getRecordById(recordId),
              record.status == .draft else {
            return
        }

        controller.gameStartTime = record.startTime
        controller.gameActions = record.actions
        controller.gameRecordSaved = false

        viewModel.leftTeam.name = record.team1Name
        viewModel.rightTeam.name = record.team2Name
        viewModel.leftTeam.sets = record.team1SetScore ?? record.team1FinalScore
        viewModel.rightTeam.sets = record.team2SetScore ?? record.team2FinalScore

        if let isSingles = record.extraData?["isSingles"]?.value as? Bool {
            viewModel.isSingles = isSingles
        }
        if let autoChangeSides = record.extraData?["autoChangeSides"]?.value as? Bool {
            viewModel.autoChangeSides = autoChangeSides
        }
        if let currentSet = record.extraData?["currentSet"]?.value as? Int {
            viewModel.currentSet = currentSet
        }
        if let currentLeftScore = record.extraData?["currentLeftScore"]?.value as? Int {
            viewModel.leftTeam.score = currentLeftScore
        }
        if let currentRightScore = record.extraData?["currentRightScore"]?.value as? Int {
            viewModel.rightTeam.score = currentRightScore
        }
        if let isLeftServing = record.extraData?["isLeftServing"]?.value as? Bool {
            viewModel.isLeftServing = isLeftServing
        }
    }
    
    // MARK: - Set End Handler
    
    private func handleSetEnd(data: SetEndCallbackData) {
        isSetTransitioning = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showToastMessage(String(format: NSLocalizedString("set_ended_winner", value: "第%d局结束，%@获胜，比分 %d-%d", comment: "Set end toast"), data.setNumber, data.winnerName, data.finalLeftScore, data.finalRightScore))
            data.continueUpdate()
            
            if data.isGameFinished {
                showGameFinishedOverlay = true
                isSetTransitioning = false
                return
            }
            
            startRestCountdown(seconds: 120, message: String(format: NSLocalizedString("rest_title_set_end", value: "第%d局结束", comment: ""), data.setNumber)) {
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
        startRestCountdown(seconds: 60, message: String(format: NSLocalizedString("rest_title_mid_game", value: "第%d局 · 局中间隙", comment: ""), viewModel.currentSet)) {}
    }
    
    private func handleSideChange() {
        showToastMessage(NSLocalizedString("change_sides", comment: ""))
    }

    private func serveIndicator(isLeftServing: Bool) -> some View {
        CenterLineServeIndicator(isLeftServing: isLeftServing)
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
