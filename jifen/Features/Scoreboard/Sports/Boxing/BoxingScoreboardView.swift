//
//  BoxingScoreboardView.swift
//  jifen
//
//  拳击计分板：总分 + 胜回合数，通过「回合结束」弹窗输入本回合双方分数。
//

import SwiftUI

struct BoxingScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil
    @State private var controller = BoxingScoreboardController()
    @State private var viewModel = BoxingViewModel()
    @State private var responsiveScoreFontSize: CGFloat = 120
    @State private var showRoundDialog: Bool = false
    @State private var showGameFinishedOverlay = false
    @State private var roundLeftPoints: Int = 10
    @State private var roundRightPoints: Int = 10

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .boxing,
                    controller: controller,
                    viewModel: viewModel,
                    scoreFontSize: responsiveScoreFontSize,
                    nameType: .team,
                    scoreTextProvider: { _, team in "\(team.score)" },
                    showEndGame: true
                ),
                onBack: {
                    viewModel.saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
                    onNavigationBack?()
                    dismiss()
                }
            )

            if showGameFinishedOverlay {
                GameFinishedOverlay(winnerName: viewModel.getWinnerName())
            }

            VStack(spacing: 0) {
                roundTitle
                    .padding(.top, ScoreboardConstants.buttonPadding + 4)
                Spacer()
                centerAddRoundButton
                    .padding(.bottom, 96)
            }

            if showRoundDialog {
                BoxingRoundDialog(
                    leftTeamName: viewModel.leftTeam.name,
                    rightTeamName: viewModel.rightTeam.name,
                    leftScore: $roundLeftPoints,
                    rightScore: $roundRightPoints,
                    onConfirm: {
                        viewModel.addRoundScore(leftPoints: roundLeftPoints, rightPoints: roundRightPoints)
                        showRoundDialog = false
                    },
                    onCancel: {
                        showRoundDialog = false
                    }
                )
            }
        }
        .navigationTitle(NSLocalizedString("game_boxing", comment: "Boxing"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            viewModel.controller = controller
            if let setup = initialSetup {
                if !setup.team1Name.isEmpty { viewModel.leftTeam.name = setup.team1Name }
                if !setup.team2Name.isEmpty { viewModel.rightTeam.name = setup.team2Name }
                viewModel.setMaxRounds(setup.maxRounds ?? 3)
                onSetupConsumed?()
            }
            restoreDraftIfNeeded()
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()
        }
        .onChange(of: viewModel.gameFinished) { _, finished in
            if finished {
                showGameFinishedOverlay = true
                viewModel.saveGameRecordInRealTime(isGameFinished: true)
            }
        }
        .onDisappear {
            viewModel.saveGameRecordInRealTime(isGameFinished: viewModel.gameFinished)
        }
    }

    private var roundTitle: some View {
        Text(String(
            format: NSLocalizedString("boxing_round_progress", value: "%d / %d", comment: "Round N of max"),
            viewModel.currentRound,
            viewModel.maxRounds
        ))
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.yellow)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .cornerRadius(12)
    }

    private var centerAddRoundButton: some View {
        Button {
            roundLeftPoints = 10
            roundRightPoints = 10
            showRoundDialog = true
            controller.performVibration(type: .light)
        } label: {
            Text("+")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.2))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.gameFinished)
        .opacity(viewModel.gameFinished ? 0.45 : 1)
    }

    private func calculateResponsiveScoreFontSize() -> CGFloat {
        let base: CGFloat = 120
        let w = UIScreen.main.bounds.width
        if w <= 0 { return base }
        return min(240, max(base, base + (CGFloat(w) - 400) * 0.15))
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

        if let leftSets = record.extraData?["leftSets"]?.value as? Int {
            viewModel.leftTeam.sets = leftSets
        } else if let team1SetScore = record.team1SetScore {
            viewModel.leftTeam.sets = team1SetScore
        }
        if let rightSets = record.extraData?["rightSets"]?.value as? Int {
            viewModel.rightTeam.sets = rightSets
        } else if let team2SetScore = record.team2SetScore {
            viewModel.rightTeam.sets = team2SetScore
        }
        if let currentRound = record.extraData?["currentRound"]?.value as? Int {
            viewModel.currentRound = currentRound
        }
        if let maxRounds = record.extraData?["maxRounds"]?.value as? Int {
            viewModel.setMaxRounds(maxRounds)
        }
    }
}

private struct BoxingRoundDialog: View {
    let leftTeamName: String
    let rightTeamName: String
    @Binding var leftScore: Int
    @Binding var rightScore: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let scoreTopRow = [10, 9, 8]
    private let scoreBottomRow = [7, 6]

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                ZStack {
                    Text(NSLocalizedString("boxing_end_round", value: "回合结束", comment: ""))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    HStack {
                        Spacer()
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 48)

                HStack(spacing: 0) {
                    teamScoreSelector(
                        name: leftTeamName.isEmpty ? NSLocalizedString("watch_team_red", value: "红方", comment: "Red") : leftTeamName,
                        selected: $leftScore
                    )
                    .frame(maxWidth: .infinity)

                    teamScoreSelector(
                        name: rightTeamName.isEmpty ? NSLocalizedString("watch_team_blue", value: "蓝方", comment: "Blue") : rightTeamName,
                        selected: $rightScore
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 12) {
                    actionButton(
                        title: NSLocalizedString("cancel", comment: "Cancel"),
                        background: Color.white.opacity(0.1),
                        action: onCancel
                    )
                    actionButton(
                        title: NSLocalizedString("confirm", comment: "Confirm"),
                        background: Color(hex: "00C853"),
                        action: onConfirm
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(width: 480, height: 320)
            .background(Color.black.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 12)
            .onTapGesture { }
        }
    }

    @ViewBuilder
    private func teamScoreSelector(name: String, selected: Binding<Int>) -> some View {
        VStack(spacing: 8) {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(scoreTopRow, id: \.self) { value in
                        scoreButton(value: value, selected: selected)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(scoreBottomRow, id: \.self) { value in
                        scoreButton(value: value, selected: selected)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func scoreButton(value: Int, selected: Binding<Int>) -> some View {
        Button {
            selected.wrappedValue = value
        } label: {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(selected.wrappedValue == value ? Color(hex: "00C853") : Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func actionButton(title: String, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(background)
                .cornerRadius(22)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        BoxingScoreboardView()
    }
}
