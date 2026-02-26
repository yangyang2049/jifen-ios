//
//  PickleballScoreboardView.swift
//  jifen
//
//  匹克球计分板：11 分制、三局两胜、每球得分。
//

import SwiftUI

struct PickleballScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil
    @State private var controller = PickleballScoreboardController()
    @State private var viewModel = PickleballViewModel()
    @State private var responsiveScoreFontSize: CGFloat = 120
    @State private var showGameFinishedOverlay: Bool = false
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .pickleball,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .team
                ),
                onBack: {
                    onNavigationBack?()
                    dismiss()
                }
            )
            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: viewModel.getWinnerName())
            }
            if showToast {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage)
                        .padding(.bottom, 24)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .navigationTitle(NSLocalizedString("game_pickleball", comment: "Pickleball"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            if let setup = initialSetup {
                if !setup.team1Name.isEmpty { viewModel.leftTeam.name = setup.team1Name }
                if !setup.team2Name.isEmpty { viewModel.rightTeam.name = setup.team2Name }
                onSetupConsumed?()
            }
            restoreDraftIfNeeded()
            viewModel.setConfig(maxSets: 3, normalSetPoints: 11)
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()
            viewModel.setOnSetEndCallback { data in
                showToastMessage(String(format: NSLocalizedString("pickleball_set_end", value: "第%d局结束，%@ 获胜 %d-%d", comment: ""), data.setNumber, data.winnerName, data.finalLeftScore, data.finalRightScore))
                data.continueUpdate()
                if data.isGameFinished {
                    showGameFinishedOverlay = true
                }
            }
        }
        .onDisappear {
            viewModel.saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
        }
        .onChange(of: viewModel.gameFinished) { _, newValue in
            if newValue { showGameFinishedOverlay = true }
        }
    }

    private func calculateResponsiveScoreFontSize() -> CGFloat {
        let base: CGFloat = 120
        let w = UIScreen.main.bounds.width
        if w <= 0 { return base }
        return min(240, max(base, base + (CGFloat(w) - 400) * 0.15))
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showToast = false }
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
        if let currentSet = record.extraData?["currentSet"]?.value as? Int {
            viewModel.currentSet = currentSet
        }
        if let currentLeftScore = record.extraData?["currentLeftScore"]?.value as? Int {
            viewModel.leftTeam.score = currentLeftScore
        }
        if let currentRightScore = record.extraData?["currentRightScore"]?.value as? Int {
            viewModel.rightTeam.score = currentRightScore
        }
    }
}

#Preview {
    NavigationStack {
        PickleballScoreboardView()
    }
}
