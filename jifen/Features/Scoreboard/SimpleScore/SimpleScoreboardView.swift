//
//  SimpleScoreboardView.swift
//  jifen
//
//  简单计分：左右两队，点击加分，支持撤销、编辑队名、保存记录。与鸿蒙 SimpleScorePage 对齐。
//

import SwiftUI

struct SimpleScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil
    @State private var controller: SimpleScoreboardController
    @State private var viewModel: BaseScoreViewModel
    @State private var responsiveScoreFontSize: CGFloat = 120

    init(initialSetup: SportsSetupResult? = nil, onSetupConsumed: (() -> Void)? = nil, onNavigationBack: (() -> Void)? = nil) {
        self.initialSetup = initialSetup
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let c = SimpleScoreboardController()
        _controller = State(initialValue: c)
        _viewModel = State(initialValue: BaseScoreViewModel(controller: c))
    }

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .simpleScore,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .team,
                    scoreTextProvider: { _, team in "\(team.score)" }
                ),
                onBack: {
                    saveRecordIfNeeded()
                    onNavigationBack?()
                    dismiss()
                }
            )
        }
        .navigationTitle(NSLocalizedString("game_simple_score", comment: "Simple Score"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            if let setup = initialSetup {
                if !setup.team1Name.isEmpty { viewModel.leftTeam.name = setup.team1Name }
                if !setup.team2Name.isEmpty { viewModel.rightTeam.name = setup.team2Name }
                onSetupConsumed?()
            }
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()
        }
        .onDisappear {
            saveRecordIfNeeded()
        }
    }

    private func calculateResponsiveScoreFontSize() -> CGFloat {
        let base: CGFloat = 120
        let w = UIScreen.main.bounds.width
        if w <= 0 { return base }
        let scale = 0.15
        return min(240, max(base, base + (CGFloat(w) - 400) * scale))
    }

    private func saveRecordIfNeeded() {
        guard !controller.isRecordSaved(), !controller.getGameActions().isEmpty else { return }
        let winner: String? = viewModel.leftTeam.score > viewModel.rightTeam.score ? "left" : (viewModel.rightTeam.score > viewModel.leftTeam.score ? "right" : nil)
        let start = controller.getGameStartTime()
        let end = Date()
        controller.saveScoreboardRecord(
            id: "simple_score_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
            endTime: end,
            duration: end.timeIntervalSince(start),
            team1Name: viewModel.leftTeam.name,
            team2Name: viewModel.rightTeam.name,
            team1FinalScore: viewModel.leftTeam.score,
            team2FinalScore: viewModel.rightTeam.score,
            winner: winner,
            totalScoreChanges: controller.getGameActions().count,
            extraData: [:]
        )
    }
}

#Preview {
    NavigationStack {
        SimpleScoreboardView()
    }
}
