//
//  PickleballScoreboardController.swift
//  jifen
//
//  匹克球计分：11 分制、三局两胜、每球得分，与鸿蒙 PickleballScoreViewModel 对齐。
//

import Foundation

class PickleballScoreboardController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .pickleball,
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
