//
//  BilliardsScoreboardView.swift
//  jifen
//
//  台球计分板：左右两队，点击加分（6/7/8/9/10），支持撤销、编辑队名、保存记录。
//

import SwiftUI

struct BilliardsScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var onSetupConsumed: (() -> Void)? = nil
    @State private var controller = BilliardsScoreboardController()
    @State private var viewModel = BaseScoreViewModel()
    @State private var responsiveScoreFontSize: CGFloat = 120

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .billiards,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .team,
                    scoreTextProvider: { _, team in "\(team.score)" }
                ),
                onBack: {
                    saveRecordIfNeeded()
                    dismiss()
                }
            )
        }
        .navigationTitle(NSLocalizedString("game_billiards", comment: "Billiards"))
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
        return min(240, max(base, base + (CGFloat(w) - 400) * 0.15))
    }

    private func saveRecordIfNeeded() {
        guard !controller.isRecordSaved(), !controller.getGameActions().isEmpty else { return }
        let winner: String? = viewModel.leftTeam.score > viewModel.rightTeam.score ? "left" : (viewModel.rightTeam.score > viewModel.leftTeam.score ? "right" : nil)
        let start = controller.getGameStartTime()
        let end = Date()
        controller.saveScoreboardRecord(
            id: "billiards_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
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
        BilliardsScoreboardView()
    }
}
