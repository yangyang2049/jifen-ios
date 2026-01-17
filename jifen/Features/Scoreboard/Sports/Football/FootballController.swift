//
//  FootballController.swift
//  jifen
//
//  Football scoreboard controller
//

import Foundation

class FootballController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .football,
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
