//
//  ScoreboardTouchGuard.swift
//  jifen
//
//  触摸防误触：开启后只有面板中心区域接受计分点击，边缘误触不再计分。
//

import CoreGraphics
import Foundation
import ScoreCore

enum ScoreboardTouchGuard {
    /// 防误触生效时可点击区域相对面板的宽高比例（居中）。
    static let allowedFraction: CGFloat = 0.6

    /// - Parameters:
    ///   - location: 点击落在面板内的坐标。
    ///   - panelSize: 所在半区/面板的尺寸。
    ///   - gameType: 精确项目类型；命中 `disablesTouchGuard` 清单的项目永不启用防误触。
    ///   - enabled: 偏好开关（设置页「触摸防误触」）。
    static func isAllowed(
        location: CGPoint,
        panelSize: CGSize,
        gameType: ScoreCore.GameType?,
        enabled: Bool
    ) -> Bool {
        guard enabled else { return true }
        if let gameType, ScoreboardUsageHintHelper.disablesTouchGuard(gameType) {
            return true
        }
        let width = panelSize.width * allowedFraction
        let height = panelSize.height * allowedFraction
        return CGRect(
            x: (panelSize.width - width) / 2,
            y: (panelSize.height - height) / 2,
            width: width,
            height: height
        ).contains(location)
    }
}
