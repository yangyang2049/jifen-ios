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
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil
    @State private var controller: BoxingScoreboardController
    @State private var viewModel: BoxingViewModel
    @State private var typographySession = ScoreboardTypographySession(
        styleID: ScoreboardStyleID(gameType: .boxing)
    )
    @State private var scoreboardSize: CGSize = .zero
    @State private var showRoundDialog: Bool = false
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var roundLeftPoints: Int = 10
    @State private var roundRightPoints: Int = 10
    @State private var isEditing = false
    @State private var recordID: String

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let controller = BoxingScoreboardController()
        _controller = State(initialValue: controller)
        _viewModel = State(initialValue: BoxingViewModel(controller: controller))
        _recordID = State(initialValue: ScoreboardRecordIdentity.initial(
            prefix: GameType.boxing.canonicalScoreboardIdentifier,
            resuming: initialResumeSessionId
        ))
    }

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .boxing,
                    controller: controller,
                    viewModel: viewModel,
                    nameType: .team,
                    scoreTextProvider: { _, team in "\(team.score)" },
                    onEditModeChange: { isEditing = $0 },
                    showEndGame: true
                ),
                typographySession: typographySession,
                onBack: {
                    viewModel.saveGameRecordInRealTime(
                        recordID: recordID,
                        isGameFinished: viewModel.gameFinished
                    )
                    onNavigationBack?()
                    dismiss()
                }
            )

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: viewModel.getWinnerName(),
                    gameType: .boxing,
                    leftName: viewModel.leftTeam.name,
                    rightName: viewModel.rightTeam.name,
                    leftScore: viewModel.leftTeam.score,
                    rightScore: viewModel.rightTeam.score,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        viewModel.saveGameRecordInRealTime(
                            recordID: recordID,
                            isGameFinished: viewModel.gameFinished
                        )
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(
                            text: "\(viewModel.leftTeam.name) \(viewModel.leftTeam.score) - \(viewModel.rightTeam.score) \(viewModel.rightTeam.name)"
                        )
                    },
                    onExit: {
                        viewModel.saveGameRecordInRealTime(
                            recordID: recordID,
                            isGameFinished: viewModel.gameFinished
                        )
                        onNavigationBack?()
                        dismiss()
                    }
                )
            }

            if !isEditing {
                VStack(spacing: 0) {
                    roundTitle
                        .padding(.top, ScoreboardConstants.buttonPadding + 4)
                    Spacer()
                    centerAddRoundButton
                        .padding(.bottom, 96)
                }
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
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: recordID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("done", value: "完成", comment: "")) {
                                showFinishedRecordDetail = false
                            }
                        }
                    }
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
            restoreResumeIfNeeded()
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            scoreboardSize = size
        }
        .onChange(of: viewModel.gameFinished) { _, finished in
            if finished {
                showGameOverDialog = true
                viewModel.saveGameRecordInRealTime(recordID: recordID, isGameFinished: true)
            }
        }
        .onDisappear {
            viewModel.saveGameRecordInRealTime(
                recordID: recordID,
                isGameFinished: viewModel.gameFinished
            )
        }
    }

    private var roundTitle: some View {
        let text = String(
            format: NSLocalizedString("boxing_round_progress", value: "%d / %d", comment: "Round N of max"),
            viewModel.currentRound,
            viewModel.maxRounds
        )
        let typography = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .standard,
                containerSize: CGSize(
                    width: max(120, scoreboardSize.width * 0.32),
                    height: max(1, scoreboardSize.height)
                ),
                nameText: "",
                scoreText: "",
                secondaryText: text,
                preference: typographySession.effectivePreference,
                horizontalPadding: 16,
                secondaryBaseScale: 0.42,
                isLargeScreen: Theme.usesPadLayout
            )
        )
        return Text(text)
            .font(typographySession.effectivePreference.font.swiftUIFont(
                size: typography.secondaryFontSize,
                weight: .bold
            ))
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

    private func startNewMatch() {
        viewModel.saveGameRecordInRealTime(recordID: recordID, isGameFinished: true)
        controller.beginNewMatch()
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.boxing.canonicalScoreboardIdentifier)
        viewModel.startNewMatch()
        roundLeftPoints = 10
        roundRightPoints = 10
        showRoundDialog = false
        showGameOverDialog = false
    }

    private func restoreResumeIfNeeded() {
        guard let recordId = initialResumeSessionId,
              let record = ManualResumeSessionStore.load(recordID: recordId) else {
            return
        }

        controller.gameStartTime = record.startTime
        controller.gameActions = record.actions
        controller.gameRecordSaved = false

        if let data = record.stateSnapshot,
           let resumeState = try? JSONDecoder().decode(BoxingResumeState.self, from: data) {
            controller.gameActions = resumeState.intentTimeline
            viewModel.restoreSession(resumeState)
            return
        }

        viewModel.restoreLegacyMatch(
            leftName: record.team1Name,
            rightName: record.team2Name,
            leftScore: record.team1FinalScore,
            rightScore: record.team2FinalScore,
            leftSets: (record.extraData?["leftSets"]?.value as? Int) ?? record.team1SetScore ?? 0,
            rightSets: (record.extraData?["rightSets"]?.value as? Int) ?? record.team2SetScore ?? 0,
            currentRound: (record.extraData?["currentRound"]?.value as? Int) ?? 1,
            maxRounds: (record.extraData?["maxRounds"]?.value as? Int) ?? 3
        )
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
        GeometryReader { proxy in
            let dialogWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                phonePreferredWidth: 480,
                padPreferredWidth: 560
            )
            let scoreButtonSize = ScoreboardLayoutMetrics.fittedGridItemSize(
                containerWidth: dialogWidth / 2,
                columns: 3,
                spacing: 6,
                horizontalPadding: 4,
                preferredSize: 56,
                minimumSize: ScoreboardConstants.minimumTouchTarget
            )

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
                        selected: $leftScore,
                        buttonSize: scoreButtonSize
                    )
                    .frame(maxWidth: .infinity)

                    teamScoreSelector(
                        name: rightTeamName.isEmpty ? NSLocalizedString("watch_team_blue", value: "蓝方", comment: "Blue") : rightTeamName,
                        selected: $rightScore,
                        buttonSize: scoreButtonSize
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
            .frame(width: dialogWidth, height: 320)
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
    }

    @ViewBuilder
    private func teamScoreSelector(name: String, selected: Binding<Int>, buttonSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(scoreTopRow, id: \.self) { value in
                        scoreButton(value: value, selected: selected, size: buttonSize)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(scoreBottomRow, id: \.self) { value in
                        scoreButton(value: value, selected: selected, size: buttonSize)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func scoreButton(value: Int, selected: Binding<Int>, size: CGFloat) -> some View {
        Button {
            selected.wrappedValue = value
        } label: {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
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
