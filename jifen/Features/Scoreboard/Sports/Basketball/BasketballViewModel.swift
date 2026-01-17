//
//  BasketballViewModel.swift
//  jifen
//
//  Basketball scoreboard view model
//

import Foundation

@Observable
class BasketballViewModel: BaseScoreViewModel {
    var leftFouls: Int = 0
    var rightFouls: Int = 0

    private var foulsHistory: [(leftFouls: Int, rightFouls: Int)] = []

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        self.leftTeam = TeamData(name: "主队", score: 0)
        self.rightTeam = TeamData(name: "客队", score: 0)
    }

    // MARK: - Basketball-specific methods

    func addFoul(isLeft: Bool) {
        // Save fouls history
        foulsHistory.append((leftFouls: leftFouls, rightFouls: rightFouls))
        if foulsHistory.count > 50 {
            foulsHistory.removeFirst()
        }

        if isLeft {
            leftFouls += 1
        } else {
            rightFouls += 1
        }

        // Record action
        controller?.recordScoreAction(action: "\(isLeft ? leftTeam.name : rightTeam.name) 犯规 +1")
    }

    func removeFoul(isLeft: Bool) {
        let currentFouls = isLeft ? leftFouls : rightFouls
        if currentFouls <= 0 {
            return
        }

        // Save fouls history
        foulsHistory.append((leftFouls: leftFouls, rightFouls: rightFouls))
        if foulsHistory.count > 50 {
            foulsHistory.removeFirst()
        }

        if isLeft {
            leftFouls -= 1
        } else {
            rightFouls -= 1
        }

        // Record action
        controller?.recordScoreAction(action: "\(isLeft ? leftTeam.name : rightTeam.name) 犯规 -1")
    }

    func undoFouls() -> Bool {
        if foulsHistory.isEmpty {
            return false
        }

        let lastFouls = foulsHistory.removeLast()
        leftFouls = lastFouls.leftFouls
        rightFouls = lastFouls.rightFouls

        return true
    }

    // MARK: - Overrides

    override func undo() -> Bool {
        // Try to undo fouls first
        if undoFouls() {
            controller?.performVibration(type: .medium)
            return true
        }

        // Fall back to score undo
        return super.undo()
    }

    override func reset() {
        super.reset()
        leftFouls = 0
        rightFouls = 0
        foulsHistory.removeAll()
    }

    func getScoringOptions() -> [Int] {
        return [1, 2, 3] // Basketball: free throw (1), 2-pointer (2), 3-pointer (3)
    }
    
    // NOTE: These methods are not overriding because the superclass methods are not open.
    // They are shadowing the base implementations to provide custom behavior.

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        
        // Save history before change
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets,
            leftGames: leftTeam.games,
            rightGames: rightTeam.games
        )
        
        if isLeft {
            leftTeam.score += points
        } else {
            rightTeam.score += points
        }
        
        // Record action
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(points)")
        
        // Basketball-specific vibration
        let vibrationType: VibrationType = points >= 3 ? .medium : .light
        controller?.performVibration(type: vibrationType)
    }
    
    override func subtractScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        
        // Save history before change
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets,
            leftGames: leftTeam.games,
            rightGames: rightTeam.games
        )
        
        if isLeft {
            leftTeam.score = max(0, leftTeam.score - points)
        } else {
            rightTeam.score = max(0, rightTeam.score - points)
        }
        
        // Record action
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(points)")

        controller?.performVibration(type: .light)
    }
}
