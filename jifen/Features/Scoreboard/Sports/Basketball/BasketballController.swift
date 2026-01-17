//
//  BasketballController.swift
//  jifen
//
//  Basketball scoreboard controller
//

import Foundation

class BasketballController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .basketball,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 50
        ))
    }

    override func getScoringOptions() -> [Int] {
        return [1, 2, 3] // Basketball: free throw (1), 2-pointer (2), 3-pointer (3)
    }
}
