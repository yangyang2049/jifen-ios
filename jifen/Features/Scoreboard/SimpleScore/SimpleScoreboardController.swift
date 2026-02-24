//
//  SimpleScoreboardController.swift
//  jifen
//
//  简易计分板控制器：仅左右两队、分数加减与撤销，与鸿蒙 SimpleScoreboardController 对齐。
//

import Foundation

class SimpleScoreboardController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .simpleScore,
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
