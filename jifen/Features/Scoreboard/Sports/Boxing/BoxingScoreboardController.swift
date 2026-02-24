//
//  BoxingScoreboardController.swift
//  jifen
//
//  拳击计分：回合制，每回合输入双方分数，与鸿蒙 BoxingScoreViewModel 对齐。
//

import Foundation

class BoxingScoreboardController: BaseScoreboardController {
    init() {
        super.init(config: ScoreboardControllerConfig(
            gameType: .boxing,
            enableRecording: true,
            enableScreenshot: true,
            enableUndo: true,
            maxHistorySize: 50
        ))
    }

    override func getScoringOptions() -> [Int] {
        return [] // 拳击通过「回合结束」弹窗输入，不用快捷加分按钮
    }
}
