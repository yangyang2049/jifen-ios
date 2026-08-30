//
//  FootballScoreboardController.swift
//  jifen
//
//  Football scoreboard controller
//

import Foundation
import ScoreCore

class FootballScoreboardController: BaseScoreboardController {
    init(gameType: ScoreCore.GameType = .football) {
        super.init(config: ScoreboardControllerConfig(
            gameType: GameType(scoreCoreGameType: gameType) ?? .football,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 50
        ))
    }

    override func getScoringOptions() -> [Int] {
        return [1] // Football: typically just +1 for goals
    }
}
