//
//  TennisScoreboardView.swift
//  jifen
//
//  Tennis scoreboard view
//

import SwiftUI

struct TennisScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
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
    @State private var isEditMode: Bool = false

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .tennis,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .player,
                    isDoublesModeProvider: { !viewModel.isSingles },
                    scoreTextProvider: { isLeft, _ in
                        viewModel.scoreDisplay(isLeft: isLeft)
                    },
                    contentOverlayProvider: { isEditMode in
                        if isEditMode || viewModel.gameFinished {
                            return AnyView(EmptyView())
                        }
                        return AnyView(serveIndicator(isLeftServing: viewModel.isLeftServing()))
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

            if viewModel.isTieBreak {
                TieBreakBadge()
            }
            
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
        .navigationTitle(NSLocalizedString("game_tennis", comment: "Tennis"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            if let setup = initialSetup {
                viewModel.leftTeam.name = setup.team1Name.isEmpty ? NSLocalizedString("red_team", comment: "") : setup.team1Name
                viewModel.rightTeam.name = setup.team2Name.isEmpty ? NSLocalizedString("blue_team", comment: "") : setup.team2Name
                if let maxSets = setup.maxSets, let autoChange = setup.autoChangeSides {
                    viewModel.setConfig(maxSets: maxSets, autoChangeSides: autoChange)
                }
                if let tbp = setup.tieBreakPoints {
                    viewModel.tieBreakTarget = tbp
                }
                if let singles = setup.isSingles {
                    viewModel.isSingles = singles
                }
                onSetupConsumed?()
            }
            restoreDraftIfNeeded()
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
            // Save record when leaving (for incomplete games)
            #if DEBUG
            print("[TennisScoreboardView] 📤 View disappearing, saving record")
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

        if let maxSets = record.extraData?["maxSets"]?.value as? Int {
            viewModel.maxSets = maxSets
        }
        if let tieBreakPoints = record.extraData?["tieBreakPoints"]?.value as? Int {
            viewModel.tieBreakTarget = tieBreakPoints
        }
        if let autoChangeSides = record.extraData?["autoChangeSides"]?.value as? Bool {
            viewModel.autoChangeSides = autoChangeSides
        }
        if let isSingles = record.extraData?["isSingles"]?.value as? Bool {
            viewModel.isSingles = isSingles
        }
        if let currentSet = record.extraData?["currentSet"]?.value as? Int {
            viewModel.currentSet = currentSet
        }
        if let finalLeftGames = record.extraData?["finalLeftGames"]?.value as? Int {
            viewModel.leftTeam.games = finalLeftGames
        }
        if let finalRightGames = record.extraData?["finalRightGames"]?.value as? Int {
            viewModel.rightTeam.games = finalRightGames
        }
        if let currentLeftScore = record.extraData?["currentLeftScore"]?.value as? Int {
            viewModel.leftTeam.score = currentLeftScore
        }
        if let currentRightScore = record.extraData?["currentRightScore"]?.value as? Int {
            viewModel.rightTeam.score = currentRightScore
        }
        if let isTieBreak = record.extraData?["isTieBreak"]?.value as? Bool {
            viewModel.isTieBreak = isTieBreak
        }
    }
    
    // MARK: - Game End Handler
    
    private func handleGameEnd(leftGames: Int, rightGames: Int, gameNumber: Int) {
        showToastMessage(String(format: NSLocalizedString("tennis_game_end_toast", value: "第%d局结束，局分 %d-%d", comment: ""), gameNumber, leftGames, rightGames))
    }
    
    // MARK: - Set End Handler
    
    private func handleSetEnd(data: SetEndCallbackData) {
        isSetTransitioning = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showToastMessage(String(format: NSLocalizedString("tennis_set_end_toast", value: "第%d盘结束，%@获胜，局分 %d-%d", comment: ""), data.setNumber, data.winnerName, data.finalLeftScore, data.finalRightScore))
            data.continueUpdate()
            
            if data.isGameFinished {
                showGameFinishedOverlay = true
                isSetTransitioning = false
                return
            }
            
            startRestCountdown(seconds: 120, message: NSLocalizedString("set_break_tennis", value: "盘间休息", comment: "")) {
                if data.shouldChangeSides {
                    handleSideChange()
                }
                isSetTransitioning = false
            }
        }
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
        
                    Text(NSLocalizedString("tennis_tiebreak", value: "抢七", comment: ""))
        
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
