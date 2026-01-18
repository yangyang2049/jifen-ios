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

    private var setHistory: [(leftSets: Int, rightSets: Int, currentSet: Int)] = []

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        self.leftTeam = TeamData(name: "红队", score: 0, sets: 0)
        self.rightTeam = TeamData(name: "蓝队", score: 0, sets: 0)
    }

    // MARK: - Volleyball-specific methods

    private var leftSets: Int { leftTeam.sets ?? 0 }
    private var rightSets: Int { rightTeam.sets ?? 0 }

    func addSet(isLeft: Bool) {
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

        controller?.performVibration(type: .medium)
    }

    func removeSet(isLeft: Bool) {
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

        return true
    }

    // MARK: - Overrides

    override func addScore(isLeft: Bool, points: Int) {
        super.addScore(isLeft: isLeft, points: points)

        // Check for set win (simplified volleyball rules)
        let requiredPoints = currentSet == 5 ? 15 : 25 // 5th set is to 15
        let score = isLeft ? leftTeam.score : rightTeam.score
        let opponentScore = isLeft ? rightTeam.score : leftTeam.score

        if score >= requiredPoints && score - opponentScore >= 2 {
            // Set win
            addSet(isLeft: isLeft)
        }

        controller?.performVibration(type: .light)
    }

    func adjustScore(isLeft: Bool, delta: Int) {
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
        return super.undo()
    }

    override func reset() {
        super.reset()
        leftTeam.sets = 0
        rightTeam.sets = 0
        currentSet = 1
        gameFinished = false
        setHistory.removeAll()
    }

    func getScoringOptions() -> [Int] {
        return [1] // Volleyball: typically just +1 for points
    }

    // MARK: - Real-time Record Saving

    func saveGameRecordInRealTime(isGameFinished: Bool = false) {
        print("[VolleyballViewModel] 💾 Saving volleyball record in real-time (isGameFinished: \(isGameFinished))")
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
            id: "volleyball_\(Int(controller?.getGameStartTime().timeIntervalSince1970 ?? 0))_\(Int(endTime.timeIntervalSince1970))",
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
            extraData: [:]
        )
        print("[VolleyballViewModel] ✅ Volleyball record saved successfully")
    }
}
