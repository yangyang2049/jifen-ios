//
//  PingPongController.swift
//  jifen
//
//  Ping pong scoreboard controller
//

import Foundation

class PingPongController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .pingpong,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 50
        ))
    }
    
    override func getScoringOptions() -> [Int] {
        return [1] // Ping pong only has +1 scoring
    }
}

