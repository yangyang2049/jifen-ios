import Foundation
import ScoreCore

/// UI adapter for S1 line-score boards. All score transitions are delegated to
/// `LineScoreReducer`; the inherited team model only mirrors reducer state for
/// the legacy template while those screens are migrated.
@Observable
class LineScoreViewModel: BaseScoreViewModel {
    private let reducer = LineScoreReducer()
    private let rules: LineScoreRuleSet

    init(controller: BaseScoreboardController?, rules: LineScoreRuleSet) {
        self.rules = rules
        super.init(controller: controller, scoreRange: rules.minimum ... rules.maximum)
    }

    override func addScore(isLeft: Bool, points: Int) {
        dispatch(.adjust(side: isLeft ? .left : .right, delta: points))
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        dispatch(.adjust(side: isLeft ? .left : .right, delta: -points))
    }

    override func adjustScore(isLeft: Bool, delta: Int) {
        dispatch(.adjust(side: isLeft ? .left : .right, delta: delta))
    }

    override func exchangeSides() { dispatch(.exchangeSides) }
    override func endGame() { dispatch(.finish) }
    override func reset() { dispatch(.reset) }

    private func dispatch(_ intent: LineScoreIntent) {
        let before = state
        let result = reducer.reduce(
            state: before,
            intent: intent,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard result.accepted else { return }
        controller?.pushHistory(left: before.leftScore, right: before.rightScore)
        apply(result.state)
        controller?.recordScoreAction(action: String(describing: intent))
        controller?.performVibration(type: .light)
    }

    private var state: LineScoreState {
        .init(
            leftName: leftTeam.name,
            rightName: rightTeam.name,
            rules: rules,
            leftScore: leftTeam.score,
            rightScore: rightTeam.score,
            finished: gameFinished
        )
    }

    private func apply(_ state: LineScoreState) {
        leftTeam.name = state.leftName
        rightTeam.name = state.rightName
        leftTeam.score = state.leftScore
        rightTeam.score = state.rightScore
        gameFinished = state.finished
    }
}
