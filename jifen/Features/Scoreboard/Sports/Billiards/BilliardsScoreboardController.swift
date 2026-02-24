//
//  BilliardsScoreboardController.swift
//  jifen
//
//  台球计分：左右两队，单球分值 6/7/8/9/10，与鸿蒙 BilliardsScoreViewModel 对齐。
//

import Foundation

class BilliardsScoreboardController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .billiards,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 50
        ))
    }

    override func getScoringOptions() -> [Int] {
        return [10, 9, 8, 7, 6]
    }
}
