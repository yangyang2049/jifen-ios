//
//  BadmintonController.swift
//  jifen
//
//  Badminton scoreboard controller
//

import Foundation

class BadmintonController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .badminton,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 50
        ))
    }
    
    override func getScoringOptions() -> [Int] {
        return [1]
    }
}
