//
//  GuandanScoreboardView.swift
//  jifen
//
//  掼蛋计分板：使用标准 PVP 模板布局，保留左右队伍分数与等级展示。
//

import SwiftUI

private let guandanLevels = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "王"]

struct GuandanScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    var initialSetup: SportsSetupResult? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller = GuandanScoreboardController()
    @State private var viewModel = GuandanViewModel()
    @State private var responsiveScoreFontSize: CGFloat = 120

    var body: some View {
        ZStack {
            ScoreboardTemplate(
                config: TemplateConfig(
                    gameType: .guandan,
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

            VStack(spacing: 0) {
                levelControlBar
                    .padding(.top, ScoreboardConstants.buttonPadding + 2)
                Spacer()
            }
        }
        .navigationTitle(NSLocalizedString("game_guandan", comment: "Guandan"))
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
                onSetupConsumed?()
            }
            responsiveScoreFontSize = calculateResponsiveScoreFontSize()
        }
        .onDisappear {
            saveRecordIfNeeded()
        }
    }

    private var levelControlBar: some View {
        HStack(spacing: 14) {
            Button {
                viewModel.levelDown()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(viewModel.canLevelDown ? .white : .white.opacity(0.35))
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.25))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canLevelDown)

            VStack(spacing: 0) {
                Text(NSLocalizedString("guandan_level", value: "等级", comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Text(viewModel.levelDisplay)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(minWidth: 84)

            Button {
                viewModel.levelUp()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(viewModel.canLevelUp ? .white : .white.opacity(0.35))
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.25))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canLevelUp)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
        .cornerRadius(14)
    }

    private func calculateResponsiveScoreFontSize() -> CGFloat {
        let base: CGFloat = 120
        let width = UIScreen.main.bounds.width
        if width <= 0 { return base }
        return min(240, max(base, base + (CGFloat(width) - 400) * 0.15))
    }

    private func saveRecordIfNeeded() {
        guard !controller.isRecordSaved(), !controller.getGameActions().isEmpty else { return }

        let winner: String? = viewModel.leftTeam.score > viewModel.rightTeam.score
            ? "left"
            : (viewModel.rightTeam.score > viewModel.leftTeam.score ? "right" : nil)

        let start = controller.getGameStartTime()
        let end = Date()

        controller.saveScoreboardRecord(
            id: "guandan_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
            endTime: end,
            duration: end.timeIntervalSince(start),
            team1Name: viewModel.leftTeam.name,
            team2Name: viewModel.rightTeam.name,
            team1FinalScore: viewModel.leftTeam.score,
            team2FinalScore: viewModel.rightTeam.score,
            winner: winner,
            totalScoreChanges: controller.getGameActions().count,
            extraData: [
                "level": viewModel.levelIndex,
                "levelLabel": viewModel.levelDisplay
            ]
        )
    }
}

private class GuandanScoreboardController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .guandan,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 80
        ))
    }

    override func getScoringOptions() -> [Int] {
        [1]
    }
}

private struct GuandanSnapshot {
    let leftName: String
    let rightName: String
    let leftScore: Int
    let rightScore: Int
    let levelIndex: Int
}

@Observable
private class GuandanViewModel: BaseScoreViewModel {
    var levelIndex: Int = 0

    private var snapshots: [GuandanSnapshot] = []

    var canLevelUp: Bool {
        levelIndex < guandanLevels.count - 1
    }

    var canLevelDown: Bool {
        levelIndex > 0
    }

    var levelDisplay: String {
        guard guandanLevels.indices.contains(levelIndex) else {
            return guandanLevels.first ?? "2"
        }
        return guandanLevels[levelIndex]
    }

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        leftTeam.name = NSLocalizedString("left_team", value: "左队", comment: "")
        rightTeam.name = NSLocalizedString("right_team", value: "右队", comment: "")
    }

    func levelUp() {
        guard canLevelUp else { return }
        saveSnapshot()
        levelIndex += 1
        controller?.recordScoreAction(action: "level +1")
        controller?.performVibration(type: .light)
    }

    func levelDown() {
        guard canLevelDown else { return }
        saveSnapshot()
        levelIndex -= 1
        controller?.recordScoreAction(action: "level -1")
        controller?.performVibration(type: .light)
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }

        saveSnapshot()

        if isLeft {
            leftTeam.score += max(0, points)
        } else {
            rightTeam.score += max(0, points)
        }

        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(max(0, points))")
        controller?.performVibration(type: .light)
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }

        saveSnapshot()

        if isLeft {
            leftTeam.score = max(0, leftTeam.score - max(0, points))
        } else {
            rightTeam.score = max(0, rightTeam.score - max(0, points))
        }

        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(max(0, points))")
        controller?.performVibration(type: .light)
    }

    override func undo() -> Bool {
        guard let snapshot = snapshots.popLast() else { return false }

        leftTeam.name = snapshot.leftName
        rightTeam.name = snapshot.rightName
        leftTeam.score = snapshot.leftScore
        rightTeam.score = snapshot.rightScore
        levelIndex = snapshot.levelIndex

        controller?.performVibration(type: .light)
        return true
    }

    override func exchangeSides() {
        saveSnapshot()

        let tempName = leftTeam.name
        let tempScore = leftTeam.score

        leftTeam.name = rightTeam.name
        leftTeam.score = rightTeam.score

        rightTeam.name = tempName
        rightTeam.score = tempScore

        controller?.performVibration(type: .medium)
    }

    override func reset() {
        super.reset()
        levelIndex = 0
        snapshots.removeAll()
    }

    private func saveSnapshot() {
        snapshots.append(GuandanSnapshot(
            leftName: leftTeam.name,
            rightName: rightTeam.name,
            leftScore: leftTeam.score,
            rightScore: rightTeam.score,
            levelIndex: levelIndex
        ))

        if snapshots.count > 100 {
            snapshots.removeFirst()
        }
    }
}

#Preview {
    NavigationStack {
        GuandanScoreboardView()
    }
}
