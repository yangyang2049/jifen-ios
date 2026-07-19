//
//  BilliardsScoreboardView.swift
//  jifen
//
//  台球：左右半区 +1，对齐鸿蒙/安卓 S1 线分（0…9999、草稿、结束比赛）。
//

import SwiftUI

struct BilliardsScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller: BilliardsScoreboardController
    @State private var viewModel: BaseScoreViewModel
    @State private var responsiveScoreFontSize: CGFloat = ScoreboardConstants.baseMainScoreFontSize
    @State private var showGameFinishedOverlay = false

    private static let scoreRange = 0 ... 9999

    init(
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let c = BilliardsScoreboardController()
        _controller = State(initialValue: c)
        _viewModel = State(initialValue: BaseScoreViewModel(controller: c, scoreRange: Self.scoreRange))
    }

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .billiards,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .team,
                    scoreTextProvider: { _, team in "\(team.score)" },
                    showEndGame: true,
                    showSettleMatch: true
                ),
                onBack: {
                    saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                    onNavigationBack?()
                    dismiss()
                }
            )

            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: winnerName)
            }
        }
        .navigationTitle(NSLocalizedString("game_billiards", comment: "Billiards"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            applyDefaultNamesIfNeeded()
            if let setup = initialSetup {
                if !setup.team1Name.isEmpty { viewModel.leftTeam.name = setup.team1Name }
                if !setup.team2Name.isEmpty { viewModel.rightTeam.name = setup.team2Name }
                onSetupConsumed?()
            }
            restoreDraftIfNeeded()
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()
        }
        .onChange(of: viewModel.gameFinished) { _, finished in
            if finished {
                showGameFinishedOverlay = true
                saveGameRecordInRealTime(isGameFinished: true)
            }
        }
        .onDisappear {
            saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
        }
    }

    private var winnerName: String {
        guard viewModel.gameFinished else { return "" }
        if viewModel.leftTeam.score > viewModel.rightTeam.score { return viewModel.leftTeam.name }
        if viewModel.rightTeam.score > viewModel.leftTeam.score { return viewModel.rightTeam.name }
        return ""
    }

    private func applyDefaultNamesIfNeeded() {
        let red = NSLocalizedString("watch_team_red", value: "红方", comment: "")
        let blue = NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
        if viewModel.leftTeam.name == NSLocalizedString("red_team", comment: "") {
            viewModel.leftTeam.name = red
        }
        if viewModel.rightTeam.name == NSLocalizedString("blue_team", comment: "") {
            viewModel.rightTeam.name = blue
        }
        if viewModel.leftTeam.name.isEmpty { viewModel.leftTeam.name = red }
        if viewModel.rightTeam.name.isEmpty { viewModel.rightTeam.name = blue }
    }

    private func calculateResponsiveScoreFontSize() -> CGFloat {
        let halfH = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: halfH)
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
        viewModel.leftTeam.score = record.team1FinalScore
        viewModel.rightTeam.score = record.team2FinalScore
    }

    private func saveGameRecordInRealTime(isGameFinished: Bool = false) {
        let hasProgress = !controller.getGameActions().isEmpty
            || viewModel.leftTeam.score != 0
            || viewModel.rightTeam.score != 0
            || isGameFinished
            || viewModel.gameFinished
        guard hasProgress else { return }

        let finished = isGameFinished || viewModel.gameFinished
        let endTime = Date()
        let start = controller.getGameStartTime()
        var winner: String?
        if finished {
            if viewModel.leftTeam.score > viewModel.rightTeam.score {
                winner = "left"
            } else if viewModel.rightTeam.score > viewModel.leftTeam.score {
                winner = "right"
            }
        }

        controller.saveScoreboardRecord(
            id: "billiards_\(Int(start.timeIntervalSince1970))",
            endTime: endTime,
            duration: endTime.timeIntervalSince(start),
            team1Name: viewModel.leftTeam.name,
            team2Name: viewModel.rightTeam.name,
            team1FinalScore: viewModel.leftTeam.score,
            team2FinalScore: viewModel.rightTeam.score,
            winner: winner,
            totalScoreChanges: controller.getGameActions().count,
            extraData: [:],
            status: finished ? .finished : .draft
        )
    }
}

#Preview {
    NavigationStack {
        BilliardsScoreboardView()
    }
}
