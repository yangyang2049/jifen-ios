//
//  BilliardsScoreboardController.swift
//  jifen
//
//  台球计分：左右半区 +1（对齐鸿蒙/安卓 S1 线分）。
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

    /// 台球不对半区暴露 +N 快捷按钮（与鸿蒙/安卓一致：点半区 +1）。
    override func getScoringOptions() -> [Int] {
        return []
    }
}
