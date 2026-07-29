import Foundation
import ScoreCore

/// UI adapter for S1 line-score boards. All score transitions are delegated to
/// `LineScoreReducer`; the inherited team model only mirrors reducer state for
/// the legacy template while those screens are migrated.
@Observable
class LineScoreViewModel: BaseScoreViewModel {
    struct HistoryEntry: Codable {
        let state: LineScoreState
        let restoresNames: Bool
    }

    private let reducer = LineScoreReducer()
    private let rules: LineScoreRuleSet
    private var stateHistory: [HistoryEntry] = []
    private var sidesSwapped = false

    var sessionState: LineScoreState { state }
    var resumeHistory: [HistoryEntry] { stateHistory }

    func restoreSession(state: LineScoreState, history: [HistoryEntry]) {
        stateHistory = Array(history.suffix(50))
        apply(state)
        controller?.clearHistory()
        for entry in stateHistory {
            controller?.pushHistory(left: entry.state.leftScore, right: entry.state.rightScore)
        }
    }

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

    override func confirmEditName(isLeft: Bool) {
        guard editState.editingSide == (isLeft ? .left : .right) else { return }
        let input = editState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = NSLocalizedString(isLeft ? "red_team" : "blue_team", comment: "")
        let resolved = input.isEmpty ? fallback : input
        dispatch(.setNames(
            left: isLeft ? resolved : leftTeam.name,
            right: isLeft ? rightTeam.name : resolved
        ))
        editState.editingSide = nil
        editState.currentInput = ""
    }

    override func undo() -> Bool {
        guard controller?.undoEnabled ?? false,
              let entry = stateHistory.popLast() else { return false }
        _ = controller?.popHistory()
        var previous = entry.state
        if !entry.restoresNames {
            previous.leftName = leftTeam.name
            previous.rightName = rightTeam.name
        }
        apply(previous)
        controller?.performVibration(type: .light)
        return true
    }

    private func dispatch(_ intent: LineScoreIntent) {
        let before = state
        let result = reducer.reduce(
            state: before,
            intent: intent,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard result.accepted else { return }
        let restoresNames: Bool
        switch intent {
        case .exchangeSides, .setNames, .reset:
            restoresNames = true
        default:
            restoresNames = false
        }
        stateHistory.append(.init(state: before, restoresNames: restoresNames))
        if stateHistory.count > 50 { stateHistory.removeFirst() }
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
            sidesSwapped: sidesSwapped,
            finished: gameFinished
        )
    }

    private func apply(_ state: LineScoreState) {
        leftTeam.name = state.leftName
        rightTeam.name = state.rightName
        leftTeam.score = state.leftScore
        rightTeam.score = state.rightScore
        sidesSwapped = state.sidesSwapped
        gameFinished = state.finished
    }
}
