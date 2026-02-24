//
//  VolleyballViewModel.swift
//  jifen
//
//  Volleyball scoreboard view model
//

import Foundation

@Observable
class VolleyballViewModel: BaseScoreViewModel {
    var currentSet: Int = 1
    var maxSets: Int = 5  // Best of 5 sets
    var isLeftServing: Bool = true

    private var setHistory: [(leftSets: Int, rightSets: Int, currentSet: Int)] = []
    private var serveHistory: [Bool] = []

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        self.leftTeam = TeamData(name: NSLocalizedString("red_team", comment: "Red Team"), score: 0, sets: 0)
        self.rightTeam = TeamData(name: NSLocalizedString("blue_team", comment: "Blue Team"), score: 0, sets: 0)
    }

    // MARK: - Volleyball-specific methods

    private var leftSets: Int { leftTeam.sets ?? 0 }
    private var rightSets: Int { rightTeam.sets ?? 0 }

    func addSet(isLeft: Bool) {
        pushServeHistory()
        // Save set history
        setHistory.append((leftSets: leftSets, rightSets: rightSets, currentSet: currentSet))
        if setHistory.count > 50 {
            setHistory.removeFirst()
        }

        if isLeft {
            leftTeam.sets = (leftTeam.sets ?? 0) + 1
        } else {
            rightTeam.sets = (rightTeam.sets ?? 0) + 1
        }

        // Check if game is finished (first to 3 sets)
        let setsToWin = (maxSets + 1) / 2
        if leftSets >= setsToWin || rightSets >= setsToWin {
            gameFinished = true
            // Save record in real-time when game finishes
            saveGameRecordInRealTime(isGameFinished: true)
            controller?.performVibration(type: .heavy)
            return
        }

        // Start new set
        currentSet += 1
        leftTeam.score = 0
        rightTeam.score = 0
        // Alternate first server for next set
        isLeftServing.toggle()

        controller?.performVibration(type: .medium)
    }

    func removeSet(isLeft: Bool) {
        pushServeHistory()
        let currentSets = isLeft ? leftSets : rightSets
        if currentSets <= 0 {
            return
        }

        // Save set history
        setHistory.append((leftSets: leftSets, rightSets: rightSets, currentSet: currentSet))
        if setHistory.count > 50 {
            setHistory.removeFirst()
        }

        if isLeft {
            leftTeam.sets = (leftTeam.sets ?? 0) - 1
        } else {
            rightTeam.sets = (rightTeam.sets ?? 0) - 1
        }

        // Go back to previous set
        currentSet = max(1, currentSet - 1)

        controller?.performVibration(type: .medium)
    }

    func undoSets() -> Bool {
        if setHistory.isEmpty {
            return false
        }

        let lastSets = setHistory.removeLast()
        leftTeam.sets = lastSets.leftSets
        rightTeam.sets = lastSets.rightSets
        currentSet = lastSets.currentSet
        gameFinished = false
        restoreServeFromHistory()

        return true
    }

    // MARK: - Overrides

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        pushServeHistory()

        // In rally-point scoring, serve changes when receiving team wins the rally.
        if isLeft != isLeftServing {
            isLeftServing = isLeft
        }

        // If set is already won (e.g. by rapid tap), do not add more points
        let requiredPoints = currentSet == 5 ? 15 : 25 // 5th set is to 15
        let myScore = isLeft ? leftTeam.score : rightTeam.score
        let oppScore = isLeft ? rightTeam.score : leftTeam.score
        if myScore >= requiredPoints && myScore - oppScore >= 2 {
            return
        }

        super.addScore(isLeft: isLeft, points: points)

        // Check for set win (simplified volleyball rules)
        let score = isLeft ? leftTeam.score : rightTeam.score
        let opponentScore = isLeft ? rightTeam.score : leftTeam.score
        if score >= requiredPoints && score - opponentScore >= 2 {
            addSet(isLeft: isLeft)
        }

        controller?.performVibration(type: .light)
    }

    func adjustScore(isLeft: Bool, delta: Int) {
        pushServeHistory()

        // Save history before change
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets,
            leftGames: leftTeam.games,
            rightGames: rightTeam.games
        )

        // Adjust score
        if isLeft {
            leftTeam.score = max(0, leftTeam.score + delta)
        } else {
            rightTeam.score = max(0, rightTeam.score + delta)
        }

        controller?.performVibration(type: .light)
    }

    override func undo() -> Bool {
        // Try to undo sets first
        if undoSets() {
            controller?.performVibration(type: .medium)
            return true
        }

        // Fall back to score undo
        let undone = super.undo()
        if undone {
            restoreServeFromHistory()
        }
        return undone
    }

    override func reset() {
        pushServeHistory()
        super.reset()
        leftTeam.sets = 0
        rightTeam.sets = 0
        currentSet = 1
        isLeftServing = true
        gameFinished = false
        setHistory.removeAll()
    }

    override func exchangeSides() {
        pushServeHistory()
        super.exchangeSides()
        // Keep service ownership on the same team after side swap.
        isLeftServing.toggle()
    }

    func getScoringOptions() -> [Int] {
        return [1] // Volleyball: typically just +1 for points
    }

    func getWinnerName() -> String {
        guard gameFinished else { return "" }
        if leftSets > rightSets { return leftTeam.name }
        if rightSets > leftSets { return rightTeam.name }
        return ""
    }

    private func pushServeHistory() {
        serveHistory.append(isLeftServing)
        if serveHistory.count > 100 {
            serveHistory.removeFirst()
        }
    }

    private func restoreServeFromHistory() {
        guard let previous = serveHistory.popLast() else { return }
        isLeftServing = previous
    }

    // MARK: - Real-time Record Saving

    func saveGameRecordInRealTime(isGameFinished: Bool = false) {
        #if DEBUG
        print("[VolleyballViewModel] 💾 Saving volleyball record in real-time (isGameFinished: \(isGameFinished))")
        #endif
        let endTime = Date()
        let duration = endTime.timeIntervalSince(controller?.getGameStartTime() ?? Date())

        var winner: String? = nil
        if isGameFinished || gameFinished {
            if leftSets > rightSets {
                winner = "left"
            } else if rightSets > leftSets {
                winner = "right"
            }
        }

        controller?.saveScoreboardRecord(
            id: "volleyball_\(Int(controller?.getGameStartTime().timeIntervalSince1970 ?? 0))",
            endTime: endTime,
            duration: duration,
            team1Name: leftTeam.name,
            team2Name: rightTeam.name,
            team1FinalScore: leftSets,
            team2FinalScore: rightSets,
            team1SetScore: leftSets,
            team2SetScore: rightSets,
            winner: winner,
            totalScoreChanges: controller?.getGameActions().count ?? 0,
            extraData: [
                "currentLeftScore": leftTeam.score,
                "currentRightScore": rightTeam.score,
                "isLeftServing": isLeftServing
            ],
            status: (isGameFinished || gameFinished) ? .finished : .draft
        )
        #if DEBUG
        print("[VolleyballViewModel] ✅ Volleyball record saved successfully")
        #endif
    }
}
