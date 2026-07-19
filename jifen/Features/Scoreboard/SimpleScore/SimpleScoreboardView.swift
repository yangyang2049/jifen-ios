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
    @State private var responsiveScoreFontSize: CGFloat = ScoreboardConstants.baseMainScoreFontSize

    init(initialSetup: SportsSetupResult? = nil, onSetupConsumed: (() -> Void)? = nil, onNavigationBack: (() -> Void)? = nil) {
        self.initialSetup = initialSetup
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let c = SimpleScoreboardController()
        _controller = State(initialValue: c)
        _viewModel = State(initialValue: BaseScoreViewModel(controller: c, scoreRange: Int.min ... Int.max))
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
        let halfH = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: halfH)
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
