//
//  BoxingViewModel.swift
//  jifen
//
//  拳击计分：总分 + 胜回合数，addRoundScore(leftPoints, rightPoints) 与鸿蒙对齐。
//

import Foundation
import ScoreCore

@Observable
class BoxingViewModel: BaseScoreViewModel {
    private let reducer = BoxingMatchReducer()
    var currentRound: Int = 1
    var maxRounds: Int = 3
    private var fullStateHistory: [BoxingState] = []

    private struct BoxingState {
        let leftScore: Int
        let rightScore: Int
        let leftSets: Int
        let rightSets: Int
        let currentRound: Int
    }

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        leftTeam.sets = 0
        rightTeam.sets = 0
    }

    /// 结束一回合：累加双方本回合分数，胜方回合数 +1
    func addRoundScore(leftPoints: Int, rightPoints: Int) {
        guard !gameFinished, currentRound <= maxRounds else { return }
        saveFullStateToHistory()
        let result = reduce(.submitRound(left: leftPoints, right: rightPoints))
        guard result.accepted else { _ = fullStateHistory.popLast(); return }
        apply(result.state)

        controller?.recordScoreAction(action: "round \(max(0, leftPoints))-\(max(0, rightPoints))")
        controller?.performVibration(type: .medium)
    }

    func setMaxRounds(_ rounds: Int) {
        maxRounds = max(1, min(rounds, 99))
    }

    func getWinnerName() -> String {
        guard gameFinished else { return "" }
        let leftSets = leftTeam.sets ?? 0
        let rightSets = rightTeam.sets ?? 0
        if leftSets > rightSets { return leftTeam.name }
        if rightSets > leftSets { return rightTeam.name }
        return ""
    }

    func saveGameRecordInRealTime(isGameFinished: Bool = false) {
        let hasProgress = !(controller?.getGameActions().isEmpty ?? true)
            || leftTeam.score != 0
            || rightTeam.score != 0
            || (leftTeam.sets ?? 0) != 0
            || (rightTeam.sets ?? 0) != 0
            || isGameFinished
            || gameFinished
        guard hasProgress else { return }

        let finished = isGameFinished || gameFinished
        let start = controller?.getGameStartTime() ?? Date()
        let end = Date()

        var winner: String?
        if finished {
            let leftSets = leftTeam.sets ?? 0
            let rightSets = rightTeam.sets ?? 0
            if leftSets > rightSets {
                winner = "left"
            } else if rightSets > leftSets {
                winner = "right"
            }
        }

        controller?.saveScoreboardRecord(
            id: "boxing_\(Int(start.timeIntervalSince1970))",
            endTime: end,
            duration: end.timeIntervalSince(start),
            team1Name: leftTeam.name,
            team2Name: rightTeam.name,
            team1FinalScore: leftTeam.score,
            team2FinalScore: rightTeam.score,
            team1SetScore: leftTeam.sets,
            team2SetScore: rightTeam.sets,
            winner: winner,
            totalScoreChanges: controller?.getGameActions().count ?? 0,
            extraData: [
                "currentRound": currentRound,
                "maxRounds": maxRounds,
                "leftSets": leftTeam.sets ?? 0,
                "rightSets": rightTeam.sets ?? 0
            ],
            status: finished ? .finished : .draft
        )
    }

    func adjustSets(isLeft: Bool, delta: Int) {
        saveFullStateToHistory()
        apply(reduce(.adjust(
            leftTotal: leftTeam.score,
            rightTotal: rightTeam.score,
            currentRound: currentRound,
            leftRoundsWon: max(0, (leftTeam.sets ?? 0) + (isLeft ? delta : 0)),
            rightRoundsWon: max(0, (rightTeam.sets ?? 0) + (isLeft ? 0 : delta))
        )).state)
        controller?.recordScoreAction(action: (isLeft ? "left" : "right") + " sets \(delta > 0 ? "+" : "")\(delta)")
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        saveFullStateToHistory()
        let result = reduce(.addPoints(side: isLeft ? .left : .right, points: points))
        guard result.accepted else { _ = fullStateHistory.popLast(); return }
        apply(result.state)
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(points)")
        controller?.performVibration(type: .medium)
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        saveFullStateToHistory()
        let result = reduce(.adjust(
            leftTotal: max(0, leftTeam.score - (isLeft ? points : 0)),
            rightTotal: max(0, rightTeam.score - (isLeft ? 0 : points)),
            currentRound: currentRound,
            leftRoundsWon: leftTeam.sets ?? 0,
            rightRoundsWon: rightTeam.sets ?? 0
        ))
        apply(result.state)
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(points)")
        controller?.performVibration(type: .light)
    }

    override func exchangeSides() {
        saveFullStateToHistory()
        apply(reduce(.exchangeSides).state)
        controller?.performVibration(type: .medium)
    }

    override func undo() -> Bool {
        guard controller?.undoEnabled ?? true else { return false }
        guard let state = fullStateHistory.popLast() else { return false }

        _ = controller?.popHistory()
        leftTeam.score = state.leftScore
        rightTeam.score = state.rightScore
        leftTeam.sets = state.leftSets
        rightTeam.sets = state.rightSets
        currentRound = state.currentRound

        controller?.performVibration(type: .light)
        return true
    }

    override func reset() {
        saveFullStateToHistory()
        apply(reduce(.reset).state)
        controller?.clearHistory()
        fullStateHistory.removeAll()
    }

    override func endGame() {
        apply(reduce(.finish).state)
    }

    private func saveFullStateToHistory() {
        fullStateHistory.append(
            BoxingState(
                leftScore: leftTeam.score,
                rightScore: rightTeam.score,
                leftSets: leftTeam.sets ?? 0,
                rightSets: rightTeam.sets ?? 0,
                currentRound: currentRound
            )
        )
        if fullStateHistory.count > 50 {
            fullStateHistory.removeFirst()
        }

        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets
        )
    }

    private func reduce(_ intent: BoxingMatchIntent) -> ReduceResult<BoxingMatchState, BoxingMatchEvent> {
        reducer.reduce(state: coreState, intent: intent, at: Int64(Date().timeIntervalSince1970 * 1_000))
    }

    private var coreState: BoxingMatchState {
        .init(
            leftName: leftTeam.name,
            rightName: rightTeam.name,
            maxRounds: maxRounds,
            leftTotal: leftTeam.score,
            rightTotal: rightTeam.score,
            leftRoundsWon: leftTeam.sets ?? 0,
            rightRoundsWon: rightTeam.sets ?? 0,
            currentRound: currentRound,
            finished: gameFinished
        )
    }

    private func apply(_ state: BoxingMatchState) {
        leftTeam.name = state.leftName
        rightTeam.name = state.rightName
        leftTeam.score = state.leftTotal
        rightTeam.score = state.rightTotal
        leftTeam.sets = state.leftRoundsWon
        rightTeam.sets = state.rightRoundsWon
        currentRound = state.currentRound
        maxRounds = state.maxRounds
        gameFinished = state.finished
    }
}
