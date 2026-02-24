//
//  PickleballViewModel.swift
//  jifen
//
//  匹克球：11 分制、三局两胜、每球得分，先到 11 且领先 2 分胜一局。
//

import Foundation

private struct PickleballStateSnapshot {
    let leftScore: Int
    let rightScore: Int
    let leftSets: Int
    let rightSets: Int
    let currentSet: Int
}

@Observable
class PickleballViewModel: BaseScoreViewModel {
    var currentSet: Int = 1
    var maxSets: Int = 3
    var normalSetPoints: Int = 11
    var onSetEndCallback: ((SetEndCallbackData) -> Void)? = nil
    private var fullStateHistory: [PickleballStateSnapshot] = []

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        leftTeam.sets = 0
        rightTeam.sets = 0
    }

    func setConfig(maxSets: Int, normalSetPoints: Int) {
        self.maxSets = maxSets
        self.normalSetPoints = normalSetPoints
    }

    func setOnSetEndCallback(_ callback: @escaping (SetEndCallbackData) -> Void) {
        onSetEndCallback = callback
    }

    func getWinnerName() -> String {
        guard gameFinished else { return "" }
        let leftSets = leftTeam.sets ?? 0
        let rightSets = rightTeam.sets ?? 0
        if leftSets > rightSets { return leftTeam.name }
        if rightSets > leftSets { return rightTeam.name }
        return ""
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }

        let targetPoints = normalSetPoints
        if canWinSet(leftScore: leftTeam.score, rightScore: rightTeam.score, targetPoints: targetPoints) {
            checkSetWinner()
            return
        }

        saveFullStateHistory()
        controller?.pushHistory(left: leftTeam.score, right: rightTeam.score, leftSets: leftTeam.sets, rightSets: rightTeam.sets)

        if isLeft {
            leftTeam.score += points
        } else {
            rightTeam.score += points
        }

        controller?.performVibration(type: .light)
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(points)")
        checkSetWinner()
    }

    override func reset() {
        super.reset()
        currentSet = 1
        leftTeam.sets = 0
        rightTeam.sets = 0
        fullStateHistory.removeAll()
    }

    override func undo() -> Bool {
        guard let controller = controller, controller.undoEnabled else { return false }
        guard let state = fullStateHistory.popLast() else { return super.undo() }
        leftTeam.score = state.leftScore
        rightTeam.score = state.rightScore
        leftTeam.sets = state.leftSets
        rightTeam.sets = state.rightSets
        currentSet = state.currentSet
        controller.performVibration(type: .light)
        return true
    }

    private func checkSetWinner() {
        let targetPoints = normalSetPoints
        guard canWinSet(leftScore: leftTeam.score, rightScore: rightTeam.score, targetPoints: targetPoints) else { return }

        let setEndLeftScore = leftTeam.score
        let setEndRightScore = rightTeam.score
        let setNumber = currentSet
        let winnerName = leftTeam.score > rightTeam.score ? leftTeam.name : rightTeam.name
        let setsToWin = (maxSets + 1) / 2
        let newLeftSets = leftTeam.score > rightTeam.score ? (leftTeam.sets ?? 0) + 1 : (leftTeam.sets ?? 0)
        let newRightSets = rightTeam.score > leftTeam.score ? (rightTeam.sets ?? 0) + 1 : (rightTeam.sets ?? 0)
        let isGameFinished = newLeftSets >= setsToWin || newRightSets >= setsToWin

        if let callback = onSetEndCallback {
            let data = SetEndCallbackData(
                finalLeftScore: setEndLeftScore,
                finalRightScore: setEndRightScore,
                winnerName: winnerName,
                setNumber: setNumber,
                leftSets: newLeftSets,
                rightSets: newRightSets,
                leftGames: nil,
                rightGames: nil,
                shouldChangeSides: !isGameFinished,
                isGameFinished: isGameFinished,
                continueUpdate: {
                    self.doSetEndUpdate(
                        setEndLeftScore: setEndLeftScore,
                        setEndRightScore: setEndRightScore,
                        setNumber: setNumber,
                        newLeftSets: newLeftSets,
                        newRightSets: newRightSets,
                        isGameFinished: isGameFinished
                    )
                }
            )
            callback(data)
        } else {
            doSetEndUpdate(
                setEndLeftScore: setEndLeftScore,
                setEndRightScore: setEndRightScore,
                setNumber: setNumber,
                newLeftSets: newLeftSets,
                newRightSets: newRightSets,
                isGameFinished: isGameFinished
            )
        }
    }

    private func doSetEndUpdate(
        setEndLeftScore: Int,
        setEndRightScore: Int,
        setNumber: Int,
        newLeftSets: Int,
        newRightSets: Int,
        isGameFinished: Bool
    ) {
        leftTeam.sets = newLeftSets
        rightTeam.sets = newRightSets
        saveGameRecordInRealTime(isGameFinished: isGameFinished)
        if isGameFinished {
            gameFinished = true
            controller?.performVibration(type: .heavy)
        } else {
            currentSet += 1
            leftTeam.score = 0
            rightTeam.score = 0
            controller?.clearHistory()
            fullStateHistory.removeAll()
        }
    }

    func saveGameRecordInRealTime(isGameFinished: Bool) {
        let endTime = Date()
        let duration = endTime.timeIntervalSince(controller?.getGameStartTime() ?? Date())
        var winner: String? = nil
        if isGameFinished {
            if (leftTeam.sets ?? 0) > (rightTeam.sets ?? 0) { winner = "left" }
            else if (rightTeam.sets ?? 0) > (leftTeam.sets ?? 0) { winner = "right" }
        }
        controller?.saveScoreboardRecord(
            id: "pickleball_\(Int(controller?.getGameStartTime().timeIntervalSince1970 ?? 0))",
            endTime: endTime,
            duration: duration,
            team1Name: leftTeam.name,
            team2Name: rightTeam.name,
            team1FinalScore: leftTeam.sets ?? 0,
            team2FinalScore: rightTeam.sets ?? 0,
            team1SetScore: leftTeam.sets ?? 0,
            team2SetScore: rightTeam.sets ?? 0,
            winner: winner,
            totalScoreChanges: controller?.getGameActions().count ?? 0,
            extraData: [
                "currentSet": currentSet,
                "currentLeftScore": leftTeam.score,
                "currentRightScore": rightTeam.score
            ],
            status: isGameFinished ? .finished : .draft
        )
    }

    private func canWinSet(leftScore: Int, rightScore: Int, targetPoints: Int) -> Bool {
        let maxScore = max(leftScore, rightScore)
        let scoreDiff = abs(leftScore - rightScore)
        if maxScore < targetPoints { return false }
        return scoreDiff >= 2
    }

    func adjustScore(isLeft: Bool, delta: Int) {
        saveFullStateHistory()
        controller?.pushHistory(left: leftTeam.score, right: rightTeam.score, leftSets: leftTeam.sets, rightSets: rightTeam.sets)
        let cap = normalSetPoints + 10
        if isLeft {
            leftTeam.score = max(0, min(leftTeam.score + delta, cap))
        } else {
            rightTeam.score = max(0, min(rightTeam.score + delta, cap))
        }
        controller?.performVibration(type: .light)
    }

    func adjustSets(isLeft: Bool, delta: Int) {
        saveFullStateHistory()
        controller?.pushHistory(left: leftTeam.score, right: rightTeam.score, leftSets: leftTeam.sets, rightSets: rightTeam.sets)
        if isLeft {
            let v = (leftTeam.sets ?? 0) + delta
            leftTeam.sets = max(0, min(v, maxSets))
        } else {
            let v = (rightTeam.sets ?? 0) + delta
            rightTeam.sets = max(0, min(v, maxSets))
        }
        controller?.performVibration(type: .light)
    }

    private func saveFullStateHistory() {
        fullStateHistory.append(PickleballStateSnapshot(
            leftScore: leftTeam.score,
            rightScore: rightTeam.score,
            leftSets: leftTeam.sets ?? 0,
            rightSets: rightTeam.sets ?? 0,
            currentSet: currentSet
        ))
        if fullStateHistory.count > 50 { fullStateHistory.removeFirst() }
    }
}
