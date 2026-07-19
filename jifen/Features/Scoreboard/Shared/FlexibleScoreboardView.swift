import SwiftUI

final class FlexibleScoreboardController: BaseScoreboardController {
    private let scoringOptions: [Int]

    init(gameType: GameType, scoringOptions: [Int]) {
        self.scoringOptions = scoringOptions
        super.init(config: ScoreboardControllerConfig(gameType: gameType))
    }

    override func getScoringOptions() -> [Int] {
        scoringOptions
    }
}

final class FlexibleScoreViewModel: BaseScoreViewModel {
    private let targetScore: Int?

    init(controller: BaseScoreboardController, scoreRange: ClosedRange<Int>, targetScore: Int?) {
        self.targetScore = targetScore
        super.init(controller: controller, scoreRange: scoreRange)
    }

    override func addScore(isLeft: Bool, points: Int) {
        super.addScore(isLeft: isLeft, points: points)
        guard let targetScore else { return }
        if leftTeam.score >= targetScore || rightTeam.score >= targetScore {
            gameFinished = true
        }
    }

    override func endGame() {
        gameFinished = true
    }
}

struct FlexibleScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let gameType: GameType
    var initialSetup: SportsSetupResult? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var controller: FlexibleScoreboardController
    @State private var viewModel: FlexibleScoreViewModel

    init(
        gameType: GameType,
        scoringOptions: [Int] = [1],
        scoreRange: ClosedRange<Int> = 0 ... 9_999,
        targetScore: Int? = nil,
        initialSetup: SportsSetupResult? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.gameType = gameType
        self.initialSetup = initialSetup
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let controller = FlexibleScoreboardController(gameType: gameType, scoringOptions: scoringOptions)
        _controller = State(initialValue: controller)
        _viewModel = State(initialValue: FlexibleScoreViewModel(
            controller: controller,
            scoreRange: scoreRange,
            targetScore: targetScore
        ))
    }

    var body: some View {
        ScoreboardTemplate(
            config: TemplateConfig(
                gameType: gameType,
                controller: controller,
                viewModel: viewModel,
                scoreFontSize: 120,
                nameType: .team,
                showEndGame: true,
                onEndGame: viewModel.endGame
            ),
            onBack: exit
        )
        .navigationTitle(gameType.displayName)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            if let initialSetup {
                if !initialSetup.team1Name.isEmpty { viewModel.leftTeam.name = initialSetup.team1Name }
                if !initialSetup.team2Name.isEmpty { viewModel.rightTeam.name = initialSetup.team2Name }
                onSetupConsumed?()
            }
        }
        .onChange(of: viewModel.leftTeam.score) { _, _ in announceIfNeeded() }
        .onChange(of: viewModel.rightTeam.score) { _, _ in announceIfNeeded() }
        .onDisappear(perform: saveRecordIfNeeded)
    }

    private func announceIfNeeded() {
        guard initialSetup?.voiceAnnouncement == true else { return }
        ScoreVoiceAnnouncer.shared.announce(left: viewModel.leftTeam.score, right: viewModel.rightTeam.score)
    }

    private func exit() {
        saveRecordIfNeeded()
        OrientationLock.shared.unlock()
        onNavigationBack?()
        dismiss()
    }

    private func saveRecordIfNeeded() {
        guard !controller.isRecordSaved(), !controller.getGameActions().isEmpty else { return }
        let start = controller.getGameStartTime()
        let end = Date()
        let winner = viewModel.leftTeam.score == viewModel.rightTeam.score
            ? nil
            : (viewModel.leftTeam.score > viewModel.rightTeam.score ? "left" : "right")
        controller.saveScoreboardRecord(
            id: "\(gameType.canonicalScoreboardIdentifier)_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
            endTime: end,
            duration: end.timeIntervalSince(start),
            team1Name: viewModel.leftTeam.name,
            team2Name: viewModel.rightTeam.name,
            team1FinalScore: viewModel.leftTeam.score,
            team2FinalScore: viewModel.rightTeam.score,
            winner: winner,
            totalScoreChanges: controller.getGameActions().count,
            extraData: ["schemaVersion": 3, "canonicalGameType": gameType.canonicalScoreboardIdentifier],
            status: viewModel.gameFinished ? .finished : .draft
        )
    }
}
