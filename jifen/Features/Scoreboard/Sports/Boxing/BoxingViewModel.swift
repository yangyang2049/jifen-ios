//
//  BoxingViewModel.swift
//  jifen
//
//  拳击计分：总分 + 胜回合数，addRoundScore(leftPoints, rightPoints) 与鸿蒙对齐。
//

import Foundation

@Observable
class BoxingViewModel: BaseScoreViewModel {
    var currentRound: Int = 1
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
        guard !gameFinished else { return }
        saveFullStateToHistory()

        let left = max(0, leftPoints)
        let right = max(0, rightPoints)

        leftTeam.score += left
        rightTeam.score += right
        if left > right {
            leftTeam.sets = (leftTeam.sets ?? 0) + 1
        } else if right > left {
            rightTeam.sets = (rightTeam.sets ?? 0) + 1
        }
        currentRound += 1

        controller?.recordScoreAction(action: "round \(left)-\(right)")
        controller?.performVibration(type: .medium)
    }

    func adjustSets(isLeft: Bool, delta: Int) {
        saveFullStateToHistory()
        if isLeft {
            let v = (leftTeam.sets ?? 0) + delta
            leftTeam.sets = max(0, v)
        } else {
            let v = (rightTeam.sets ?? 0) + delta
            rightTeam.sets = max(0, v)
        }
        controller?.recordScoreAction(action: (isLeft ? "left" : "right") + " sets \(delta > 0 ? "+" : "")\(delta)")
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        saveFullStateToHistory()

        if isLeft {
            leftTeam.score += points
        } else {
            rightTeam.score += points
        }
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(points)")
        controller?.performVibration(type: .medium)
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        saveFullStateToHistory()

        if isLeft {
            leftTeam.score = max(0, leftTeam.score - points)
        } else {
            rightTeam.score = max(0, rightTeam.score - points)
        }
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(points)")
        controller?.performVibration(type: .light)
    }

    override func exchangeSides() {
        saveFullStateToHistory()

        let tempName = leftTeam.name
        let tempScore = leftTeam.score
        let tempSets = leftTeam.sets

        leftTeam.name = rightTeam.name
        leftTeam.score = rightTeam.score
        leftTeam.sets = rightTeam.sets

        rightTeam.name = tempName
        rightTeam.score = tempScore
        rightTeam.sets = tempSets

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
        leftTeam.score = 0
        rightTeam.score = 0
        leftTeam.sets = 0
        rightTeam.sets = 0
        currentRound = 1
        gameFinished = false
        controller?.clearHistory()
        fullStateHistory.removeAll()
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
}
