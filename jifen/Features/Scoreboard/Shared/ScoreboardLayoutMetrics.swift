import CoreGraphics
import UIKit

/// Font/spacing curves aligned with HOS `helpers/baseMainScoreFontSize.ts`.
enum ScoreboardLayoutMetrics {
    private static let mainScoreBaseSize: CGFloat = 144
    private static let mainScoreBaseViewportHeight: CGFloat = 360
    private static let mainScoreViewportHeightScale: CGFloat = 0.2
    private static let mainScoreAccelerationReferenceHeight: CGFloat = 720
    private static let mainScoreMaxSize: CGFloat = 480

    private static let setScoreBaseSize: CGFloat = 58
    private static let setScoreViewportHeightScale: CGFloat = 0.05
    private static let setScoreAccelerationReferenceHeight: CGFloat = 720
    private static let setScoreMaxSize: CGFloat = 120

    private static let teamNameBaseSize: CGFloat = 36
    private static let teamNameViewportHeightScale: CGFloat = 0.05
    private static let teamNameMaxSize: CGFloat = 72

    private static let nameToMainGapBase: CGFloat = 24
    private static let nameToMainGapScale: CGFloat = 0.08
    private static let nameToMainGapMax: CGFloat = 64

    private static let mainToSetGapBase: CGFloat = 8
    private static let mainToSetGapScale: CGFloat = 0.025
    private static let mainToSetGapMax: CGFloat = 24

    static let playerGridNameHeightRatio: CGFloat = 0.075
    static let playerGridScoreRegionHeightRatio: CGFloat = 0.75
    static let playerGridScoreFontFillRatio: CGFloat = 0.85
    static let playerGridNameMaxSize: CGFloat = 72
    static let playerGridScoreMaxSize: CGFloat = 480

    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    static func clampRound(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(max, Swift.max(min, value.rounded()))
    }

    /// `halfViewportHeight` = one side panel's measured height (full height in landscape).
    static func mainScoreFontSize(halfViewportHeight: CGFloat) -> CGFloat {
        let extra = Swift.max(0, halfViewportHeight - mainScoreBaseViewportHeight)
        let accelerated = 1 + extra / mainScoreAccelerationReferenceHeight
        let responsive = mainScoreBaseSize + extra * mainScoreViewportHeightScale * accelerated
        return clampRound(responsive, min: mainScoreBaseSize, max: mainScoreMaxSize)
    }

    static func setScoreFontSize(halfViewportHeight: CGFloat) -> CGFloat {
        let extra = Swift.max(0, halfViewportHeight - mainScoreBaseViewportHeight)
        let accelerated = 1 + extra / setScoreAccelerationReferenceHeight
        return clampRound(
            setScoreBaseSize + extra * setScoreViewportHeightScale * accelerated,
            min: setScoreBaseSize,
            max: setScoreMaxSize
        )
    }

    static func teamNameFontSize(halfViewportHeight: CGFloat) -> CGFloat {
        let extra = Swift.max(0, halfViewportHeight - mainScoreBaseViewportHeight)
        return clampRound(
            teamNameBaseSize + extra * teamNameViewportHeightScale,
            min: teamNameBaseSize,
            max: teamNameMaxSize
        )
    }

    /// Phone template default when height curve isn't available yet.
    static var defaultTeamNameFontSize: CGFloat {
        isPad ? ScoreboardConstants.teamNameFontSizePad : ScoreboardConstants.teamNameFontSizePhone
    }

    static func nameToMainSpacing(halfViewportHeight: CGFloat) -> CGFloat {
        let extra = Swift.max(0, halfViewportHeight - mainScoreBaseViewportHeight)
        return clampRound(
            nameToMainGapBase + extra * nameToMainGapScale,
            min: nameToMainGapBase,
            max: nameToMainGapMax
        )
    }

    static func mainToSetSpacing(halfViewportHeight: CGFloat) -> CGFloat {
        let extra = Swift.max(0, halfViewportHeight - mainScoreBaseViewportHeight)
        return clampRound(
            mainToSetGapBase + extra * mainToSetGapScale,
            min: mainToSetGapBase,
            max: mainToSetGapMax
        )
    }

    static func nameTopPadding(panelHeight: CGFloat, isEditMode: Bool = false) -> CGFloat {
        let base = 20 + (panelHeight - 800) * 0.08
        let clamped = Swift.min(60, Swift.max(20, base))
        if isEditMode {
            return Swift.max(76, clamped)
        }
        return clamped
    }

    static func playerGridNameFontSize(cellHeight: CGFloat, baseSize: CGFloat = 16) -> CGFloat {
        clampRound(
            Swift.max(baseSize, cellHeight * playerGridNameHeightRatio),
            min: baseSize,
            max: playerGridNameMaxSize
        )
    }

    static func playerGridScoreFontSize(
        cellHeight: CGFloat,
        baseSize: CGFloat = 24,
        reservedHeight: CGFloat = 0,
        fontScale: CGFloat = 1
    ) -> CGFloat {
        let scale = Swift.max(0.1, fontScale)
        let target = Swift.max(
            baseSize,
            cellHeight * playerGridScoreRegionHeightRatio * playerGridScoreFontFillRatio
        ) * scale
        let remaining = Swift.max(1, cellHeight - Swift.max(0, reservedHeight))
        let verticalLimit = remaining * playerGridScoreFontFillRatio
        let safeMin = Swift.min(24, verticalLimit)
        return clampRound(Swift.min(target, verticalLimit), min: safeMin, max: playerGridScoreMaxSize)
    }

    /// Basketball center column width (HOS 160 / 180 / 200 by screen width).
    static func basketballCenterWidth(screenWidth: CGFloat) -> CGFloat {
        if screenWidth < 700 { return 160 }
        if screenWidth < 900 { return 180 }
        return 200
    }
}
