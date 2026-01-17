//
//  VolleyballController.swift
//  jifen
//
//  Volleyball scoreboard controller
//

import Foundation

class VolleyballController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .volleyball,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 50
        ))
    }

    override func getScoringOptions() -> [Int] {
        return [1] // Volleyball: typically just +1 for points
    }
}
