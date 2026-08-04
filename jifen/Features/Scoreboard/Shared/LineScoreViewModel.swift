import Foundation
import ScoreCore

struct LineScoreResumeState: Codable {
    var schemaVersion = 2
    let state: LineScoreState
    let undoHistory: [LineScoreViewModel.HistoryEntry]
    let intentTimeline: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, state, undoHistory, intentTimeline
    }

    init(
        schemaVersion: Int = 2,
        state: LineScoreState,
        undoHistory: [LineScoreViewModel.HistoryEntry],
        intentTimeline: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.undoHistory = undoHistory
        self.intentTimeline = intentTimeline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        state = try container.decode(LineScoreState.self, forKey: .state)
        undoHistory = try container.decodeIfPresent(
            [LineScoreViewModel.HistoryEntry].self,
            forKey: .undoHistory
        ) ?? []
        intentTimeline = try container.decodeIfPresent([String].self, forKey: .intentTimeline) ?? []
    }
}

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
    private let defaultNames: ParticipantNamePair
    private var stateHistory: [HistoryEntry] = []
    var sessionState: LineScoreState { state }
    var resumeHistory: [HistoryEntry] { stateHistory }

    func makeFreshMatchState() -> LineScoreState {
        reducer.reduce(
            state: state,
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        ).state
    }

    func restoreSession(state: LineScoreState, history: [HistoryEntry]) {
        stateHistory = Array(history.suffix(50))
        apply(state)
        controller?.clearHistory()
        for entry in stateHistory {
            controller?.pushHistory(left: entry.state.leftScore, right: entry.state.rightScore)
        }
    }

    func restoreSession(_ resumeState: LineScoreResumeState) {
        let requiresMigration = resumeState.schemaVersion < 2
        let state = requiresMigration
            ? resumeState.state.normalizedFromLegacyPhysicalSideSwap()
            : resumeState.state
        let history = requiresMigration
            ? resumeState.undoHistory.map {
                HistoryEntry(
                    state: $0.state.normalizedFromLegacyPhysicalSideSwap(),
                    restoresNames: $0.restoresNames
                )
            }
            : resumeState.undoHistory
        restoreSession(state: state, history: history)
    }

    init(
        controller: BaseScoreboardController?,
        rules: LineScoreRuleSet,
        defaultNames: ParticipantNamePair = DefaultParticipantNames.resolve(for: .simpleScore)
    ) {
        self.rules = rules
        self.defaultNames = defaultNames
        super.init(controller: controller, scoreRange: rules.minimum ... rules.maximum)
        leftTeam.name = defaultNames.left
        rightTeam.name = defaultNames.right
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
        let fallback = isLeft ? defaultNames.left : defaultNames.right
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
        recordSnapshot(code: "undo")
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
        recordSnapshot(code: operationCode(for: intent))
        controller?.performVibration(type: .light)
    }

    private func operationCode(for intent: LineScoreIntent) -> String {
        switch intent {
        case .pointWon, .adjust:
            return "score_adjust"
        case .setNames:
            return "edit_names"
        case .exchangeSides:
            return "exchange_side"
        case .finish:
            return "finish"
        case .reset:
            return "reset"
        }
    }

    private func recordSnapshot(code: String) {
        controller?.recordScoreAction(
            action: "snapshot|\(code)|\(leftTeam.score),\(rightTeam.score)"
        )
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

private extension LineScoreState {
    func normalizedFromLegacyPhysicalSideSwap() -> Self {
        guard sidesSwapped else { return self }
        var next = self
        swap(&next.leftName, &next.rightName)
        swap(&next.leftScore, &next.rightScore)
        return next
    }
}
