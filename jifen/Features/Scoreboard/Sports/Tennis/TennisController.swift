//
//  TennisController.swift
//  jifen
//
//  Tennis scoreboard controller
//

import Foundation

class TennisController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .tennis,
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
