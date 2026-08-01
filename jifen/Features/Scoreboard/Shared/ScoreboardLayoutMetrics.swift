import CoreGraphics
import Foundation
import ScoreCore

struct TennisDoublesEditLayoutMetrics: Equatable, Sendable {
    let mainFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let controlVisualSize: CGFloat
    let labelFontSize: CGFloat
    let contentSpacing: CGFloat
    let availableScoreHeight: CGFloat
    let estimatedContentHeight: CGFloat
}

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

    private static let inlineScoreGapBase: CGFloat = 28
    private static let inlineScoreGapBaseViewportWidth: CGFloat = 280
    private static let inlineScoreGapViewportWidthScale: CGFloat = 0.10
    private static let inlineScoreGapMax: CGFloat = 72

    private static let serveIndicatorBaseSize: CGFloat = 36
    private static let serveIndicatorViewportScale: CGFloat = 0.10
    private static let serveIndicatorMaxSize: CGFloat = 64
    private static let serveIndicatorStep: CGFloat = 4

    /// HarmonyOS uses the displayed main-score size as the source of truth and
    /// renders it at 70% while the inline +/- controls are visible.
    private static let editMainScoreScale: CGFloat = 0.7

    static let playerGridNameHeightRatio: CGFloat = 0.075
    static let playerGridScoreRegionHeightRatio: CGFloat = 0.75
    static let playerGridScoreFontFillRatio: CGFloat = 0.85
    static let playerGridNameMaxSize: CGFloat = 72
    static let playerGridScoreMaxSize: CGFloat = 480

    static func clampRound(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(max, Swift.max(min, value.rounded()))
    }

    /// Fits fixed-column controls inside a responsive card. The minimum is a
    /// compact-window fallback; normal phone and tablet widths keep the
    /// preferred visual size.
    static func fittedGridItemSize(
        containerWidth: CGFloat,
        columns: Int,
        spacing: CGFloat,
        horizontalPadding: CGFloat,
        preferredSize: CGFloat,
        minimumSize: CGFloat
    ) -> CGFloat {
        guard columns > 0 else { return 0 }
        let totalSpacing = CGFloat(max(0, columns - 1)) * spacing
        let fitted = (containerWidth - horizontalPadding * 2 - totalSpacing) / CGFloat(columns)
        return Swift.min(preferredSize, Swift.max(minimumSize, fitted.rounded(.down)))
    }

    /// `halfViewportHeight` = one side panel's measured height (full height in landscape).
    static func mainScoreFontSize(halfViewportHeight: CGFloat) -> CGFloat {
        let extra = Swift.max(0, halfViewportHeight - mainScoreBaseViewportHeight)
        let accelerated = 1 + extra / mainScoreAccelerationReferenceHeight
        let responsive = mainScoreBaseSize + extra * mainScoreViewportHeightScale * accelerated
        return clampRound(responsive, min: mainScoreBaseSize, max: mainScoreMaxSize)
    }

    static func editMainScoreFontSize(regularSize: CGFloat) -> CGFloat {
        (regularSize * editMainScoreScale).rounded()
    }

    /// HarmonyOS doubles edit mode keeps both player fields in a compact top
    /// band, leaving the remaining height to a centered two-row score editor.
    static func doublesEditNamesRegionHeight(
        isLargeScreen: Bool,
        screenWidth: CGFloat
    ) -> CGFloat {
        let fieldHeight = scoreboardNameEditorHeight(screenWidth: screenWidth)
        let fieldSpacing: CGFloat = isLargeScreen ? 8 : 4
        let topPadding: CGFloat = isLargeScreen ? 12 : 6
        let bottomPadding: CGFloat = isLargeScreen ? 8 : 4
        let fittedHeight = fieldHeight * 2 + fieldSpacing + topPadding + bottomPadding
        return Swift.max(isLargeScreen ? 138 : 0, fittedHeight)
    }

    static func doublesEditMainScoreFontSize(
        regularSize: CGFloat,
        isLargeScreen: Bool
    ) -> CGFloat {
        (regularSize * (isLargeScreen ? 0.86 : 0.70)).rounded()
    }

    static func doublesEditSecondaryScoreFontSize(
        regularSize: CGFloat,
        isLargeScreen: Bool
    ) -> CGFloat {
        (regularSize * (isLargeScreen ? 0.90 : 0.72)).rounded()
    }

    static func doublesEditControlSize(isLargeScreen: Bool) -> CGFloat {
        isLargeScreen ? 58 : ScoreboardConstants.minimumTouchTarget
    }

    static func tennisDoublesEditMainScoreFontSize(
        regularSize: CGFloat,
        isLargeScreen: Bool
    ) -> CGFloat {
        (regularSize * (isLargeScreen ? 0.62 : 0.50)).rounded()
    }

    static func tennisDoublesEditSecondaryScoreFontSize(
        regularSize: CGFloat,
        isLargeScreen: Bool
    ) -> CGFloat {
        (regularSize * (isLargeScreen ? 0.84 : 0.72)).rounded()
    }

    /// Keeps HarmonyOS edit sizes when they fit, then scales only score values
    /// and visible control circles on short landscape phones. Labels, minimum
    /// hit targets and inter-row spacing are included in the height budget.
    static func tennisDoublesEditLayout(
        regularMainSize: CGFloat,
        regularSecondarySize: CGFloat,
        panelHeight: CGFloat,
        namesRegionHeight: CGFloat,
        secondaryRowCount: Int,
        isLargeScreen: Bool
    ) -> TennisDoublesEditLayoutMetrics {
        let safeSecondaryRows = Swift.max(0, secondaryRowCount)
        let rowCount = 1 + safeSecondaryRows
        let desiredMain = tennisDoublesEditMainScoreFontSize(
            regularSize: regularMainSize,
            isLargeScreen: isLargeScreen
        )
        let desiredSecondary = tennisDoublesEditSecondaryScoreFontSize(
            regularSize: regularSecondarySize,
            isLargeScreen: isLargeScreen
        )
        let desiredControl = doublesEditControlSize(isLargeScreen: isLargeScreen)
        let labelFontSize: CGFloat = isLargeScreen ? 18 : 12
        let contentSpacing: CGFloat = isLargeScreen ? 8 : 5
        let labelToValueSpacing: CGFloat = 2
        let availableHeight = Swift.max(
            1,
            panelHeight
                - nameTopPadding(panelHeight: panelHeight, isEditMode: true)
                - namesRegionHeight
        )
        let minimumMainSize: CGFloat = isLargeScreen ? 48 : 36
        let minimumSecondarySize: CGFloat = isLargeScreen ? 28 : 22
        let minimumControlVisualSize: CGFloat = isLargeScreen
            ? ScoreboardConstants.minimumTouchTarget
            : 32

        func resolvedValues(scale: CGFloat) -> (
            main: CGFloat,
            secondary: CGFloat,
            control: CGFloat
        ) {
            (
                Swift.max(minimumMainSize, desiredMain * scale).rounded(),
                Swift.max(minimumSecondarySize, desiredSecondary * scale).rounded(),
                Swift.max(minimumControlVisualSize, desiredControl * scale).rounded()
            )
        }

        func estimatedHeight(scale: CGFloat) -> CGFloat {
            let values = resolvedValues(scale: scale)
            let hitTarget = Swift.max(ScoreboardConstants.minimumTouchTarget, values.control)
            let mainRowHeight = Swift.max(hitTarget, values.main * 1.06)
            let secondaryRowHeight = Swift.max(hitTarget, values.secondary * 1.08)
            let labelHeight = labelFontSize * 1.15
            let labelsAndInnerSpacing = CGFloat(rowCount) * (labelHeight + labelToValueSpacing)
            let betweenRows = CGFloat(Swift.max(0, rowCount - 1)) * contentSpacing
            return mainRowHeight
                + CGFloat(safeSecondaryRows) * secondaryRowHeight
                + labelsAndInnerSpacing
                + betweenRows
        }

        var scale: CGFloat = 1
        if estimatedHeight(scale: scale) > availableHeight {
            var lower: CGFloat = 0
            var upper: CGFloat = 1
            for _ in 0..<20 {
                let candidate = (lower + upper) / 2
                if estimatedHeight(scale: candidate) <= availableHeight {
                    lower = candidate
                } else {
                    upper = candidate
                }
            }
            scale = lower
        }

        let values = resolvedValues(scale: scale)
        return TennisDoublesEditLayoutMetrics(
            mainFontSize: values.main,
            secondaryFontSize: values.secondary,
            controlVisualSize: values.control,
            labelFontSize: labelFontSize,
            contentSpacing: contentSpacing,
            availableScoreHeight: availableHeight,
            estimatedContentHeight: estimatedHeight(scale: scale)
        )
    }

    /// Matches HarmonyOS `getStandardTeamNameFieldWidthVp`.
    static func scoreboardNameEditorWidth(screenWidth: CGFloat) -> CGFloat {
        if screenWidth >= 1_600 { return 360 }
        if screenWidth >= 1_400 { return 330 }
        if screenWidth >= 1_200 { return 300 }
        if screenWidth >= 900 { return 252 }
        if screenWidth >= 720 { return 220 }
        return 180
    }

    static func scoreboardNameEditorFontSize(screenWidth: CGFloat) -> CGFloat {
        if screenWidth >= 1_600 { return 24 }
        if screenWidth >= 1_400 { return 22 }
        if screenWidth >= 1_200 { return 20 }
        if screenWidth >= 900 { return 18 }
        if screenWidth >= 720 { return 17 }
        return 16
    }

    static func scoreboardNameEditorHeight(screenWidth: CGFloat) -> CGFloat {
        if screenWidth >= 1_600 { return 52 }
        if screenWidth >= 1_400 { return 48 }
        if screenWidth >= 1_200 { return 46 }
        return ScoreboardConstants.minimumTouchTarget
    }

    /// Three-row doubles layouts have substantially less vertical room than
    /// the standard two-panel template. Keep the phone result near 40/28,
    /// while allowing larger windows to scale up without exceeding the normal
    /// editing sizes.
    static func compactEditMainScoreFontSize(regularSize: CGFloat, rowHeight: CGFloat) -> CGFloat {
        Swift.min(
            editMainScoreFontSize(regularSize: regularSize),
            clampRound(rowHeight * 0.38, min: 40, max: 64)
        )
    }

    static func compactEditSecondaryScoreFontSize(regularSize: CGFloat, rowHeight: CGFloat) -> CGFloat {
        Swift.min(
            regularSize,
            clampRound(rowHeight * 0.27, min: 28, max: 44)
        )
    }

    static func compactEditControlSize(rowHeight: CGFloat) -> CGFloat {
        clampRound(
            (rowHeight - 8) / 2,
            min: ScoreboardConstants.minimumTouchTarget,
            max: 50
        )
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

    /// Horizontal spacing for layouts that place the main score and the
    /// set/game score on the same row. The measured half-panel width is used
    /// so iPad, Split View and resizable windows do not depend on device pixels.
    static func inlineMainToSecondarySpacing(halfViewportWidth: CGFloat) -> CGFloat {
        let extra = Swift.max(0, halfViewportWidth - inlineScoreGapBaseViewportWidth)
        return clampRound(
            inlineScoreGapBase + extra * inlineScoreGapViewportWidthScale,
            min: inlineScoreGapBase,
            max: inlineScoreGapMax
        )
    }

    /// Tennis places the point score and the game/set column on the same row.
    /// Its main score therefore needs a smaller baseline than rally sports,
    /// whose score can use the complete half-panel width.
    static func tennisMainScoreScale(hasInlineSecondary: Bool) -> CGFloat {
        hasInlineSecondary ? 0.78 : 1
    }

    /// High custom score caps can produce three- or four-digit rally scores.
    /// Compact them before applying the user's typography multiplier so every
    /// selected size keeps the same 25% safety reduction at three digits.
    static func threeDigitMainScoreScale(scoreText: String) -> CGFloat {
        scoreText.filter(\.isNumber).count >= 3 ? 0.75 : 1
    }

    /// Keeps the tennis game/set column clear of the center-line serve marker.
    /// The margin scales with the same measured viewport as the triangle so it
    /// remains useful in compact windows without becoming excessive on iPad.
    static func tennisCenterLineClearance(halfViewportSize: CGSize) -> CGFloat {
        let indicatorSize = serveIndicatorSize(halfViewportSize: halfViewportSize)
        return indicatorSize + Swift.max(12, indicatorSize * 0.25)
    }

    /// Singles uses matching top and bottom regions so its score row is truly
    /// centered in the complete panel rather than in the space below the name.
    static func tennisSinglesNameRegionHeight(panelHeight: CGFloat, nameFontSize: CGFloat) -> CGFloat {
        nameTopPadding(panelHeight: panelHeight) + max(1, nameFontSize) * 1.2
    }

    /// Doubles scoreboards render the score cluster over the middle of the
    /// court instead of confining it to the nominal middle third. Android uses
    /// a 60% overlay; this geometry curve keeps compact phones slightly tighter
    /// and reaches the same 60% allocation on tall tablet windows.
    static func doublesScoreRegionHeight(panelHeight: CGFloat) -> CGFloat {
        let growth = Swift.min(1, Swift.max(0, (panelHeight - 360) / 640))
        let ratio = 0.56 + growth * 0.04
        return max(1, panelHeight * ratio)
    }

    /// Serving triangle size derived from one side panel's measured viewport.
    /// Phones keep the existing 36pt baseline while larger panels scale in
    /// 4pt steps, keeping every scoreboard on the same geometry grid.
    static func serveIndicatorSize(halfViewportSize: CGSize) -> CGFloat {
        let shortEdge = Swift.min(halfViewportSize.width, halfViewportSize.height)
        let responsive = shortEdge * serveIndicatorViewportScale
        let stepped = (responsive / serveIndicatorStep).rounded() * serveIndicatorStep
        return Swift.min(serveIndicatorMaxSize, Swift.max(serveIndicatorBaseSize, stepped))
    }

    static func nameTopPadding(panelHeight: CGFloat, isEditMode: Bool = false) -> CGFloat {
        let base = 20 + (panelHeight - 800) * 0.08
        let clamped = Swift.min(60, Swift.max(20, base))
        if isEditMode {
            return Swift.max(76, clamped)
        }
        return clamped
    }

    /// Moves the complete edit-content group by the same amount as the team
    /// name. This preserves the normal name-to-score relationship while the
    /// top-right confirmation button is being avoided.
    static func editContentVerticalOffset(panelHeight: CGFloat) -> CGFloat {
        nameTopPadding(panelHeight: panelHeight, isEditMode: true)
            - nameTopPadding(panelHeight: panelHeight)
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
        fontScale: CGFloat = 1,
        fillRatio: CGFloat = playerGridScoreFontFillRatio
    ) -> CGFloat {
        let scale = Swift.max(0.1, fontScale)
        let safeFillRatio = Swift.max(0.1, fillRatio)
        let target = Swift.max(
            baseSize,
            cellHeight * playerGridScoreRegionHeightRatio * safeFillRatio
        ) * scale
        let remaining = Swift.max(1, cellHeight - Swift.max(0, reservedHeight))
        let verticalLimit = remaining * safeFillRatio
        let safeMin = Swift.min(24, verticalLimit)
        return clampRound(Swift.min(target, verticalLimit), min: safeMin, max: playerGridScoreMaxSize)
    }

    /// Basketball center column width (HOS 160 / 180 / 200 by screen width).
    static func basketballCenterWidth(screenWidth: CGFloat) -> CGFloat {
        if screenWidth < 700 { return 160 }
        if screenWidth < 900 { return 180 }
        return 200
    }

    /// Moves a label from the center of either half-panel onto the shared
    /// scoreboard center line without coupling it to a logical team side.
    static func sharedCenterLabelHorizontalOffset(
        halfViewportWidth: CGFloat,
        sourceScreenSide: MatchSide
    ) -> CGFloat {
        (sourceScreenSide == .left ? 1 : -1) * halfViewportWidth / 2
    }
}

enum ScoreboardTypographyProfile: Sendable {
    case standard
    case rally
    case tennis
    case basketball
    case specialized
    case doudizhu
    case nineBall
    case multi
    case uno

    var adjustableMetrics: [ScoreboardFontMetric] {
        switch self {
        case .doudizhu, .multi:
            return [.name, .score]
        default:
            return [.name, .score, .secondary]
        }
    }
}

struct ScoreboardTypographyLayoutContext: Sendable {
    let profile: ScoreboardTypographyProfile
    let containerSize: CGSize
    let nameText: String
    let scoreText: String
    var secondaryText: String = ""
    let preference: ScoreboardTypographyPreference
    var horizontalPadding: CGFloat = 16
    var reservedHeight: CGFloat = 0
    var scoreBaseScale: CGFloat = 1
    var nameBaseScale: CGFloat = 1
    var secondaryBaseScale: CGFloat = 1
    var secondaryIsInline: Bool = false
    /// Height used by the HarmonyOS typography curves. The measured container
    /// still supplies the hard width/height constraints. Doubles score rows use
    /// the complete half-panel height as their baseline and the overlay height
    /// as their rendering limit.
    var referenceHeight: CGFloat? = nil
    var isLargeScreen: Bool = false
}

struct ScoreboardTypographyResult: Equatable, Sendable {
    let nameFontSize: CGFloat
    let scoreFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let nameToScoreSpacing: CGFloat
    let mainToSecondarySpacing: CGFloat
}

/// Resolves scoreboard typography from the actual panel or grid-cell geometry.
/// Height determines the initial visual hierarchy; width and content length are
/// then hard constraints, so Split View, long names and multi-digit scores never
/// depend on device-model breakpoints.
enum ScoreboardTypographyResolver {
    static func resolve(_ context: ScoreboardTypographyLayoutContext) -> ScoreboardTypographyResult {
        let size = context.containerSize
        guard size.width > 0, size.height > 0 else {
            return ScoreboardTypographyResult(
                nameFontSize: 1,
                scoreFontSize: 1,
                secondaryFontSize: 1,
                nameToScoreSpacing: 0,
                mainToSecondarySpacing: 0
            )
        }

        let isGrid = context.profile == .doudizhu
            || context.profile == .nineBall
            || context.profile == .multi
            || context.profile == .uno
        let nameMinimum: CGFloat = context.isLargeScreen ? 16 : 12
        let scoreMinimum: CGFloat = context.isLargeScreen ? 30 : 24
        let secondaryMinimum: CGFloat = context.isLargeScreen ? 16 : 12
        let availableWidth = max(1, size.width - context.horizontalPadding * 2)
        let referenceHeight = max(1, context.referenceHeight ?? size.height)

        let requestedNameBase = isGrid
            ? ScoreboardLayoutMetrics.playerGridNameFontSize(
                cellHeight: size.height,
                baseSize: context.isLargeScreen ? 20 : 16
            )
            : ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: referenceHeight)
        let requestedName = requestedNameBase
            * context.nameBaseScale
            * CGFloat(context.preference.nameMultiplier)
        let nameSize = fitFontSizeByWidth(
            requested: requestedName,
            text: context.nameText,
            availableWidth: availableWidth,
            minimum: nameMinimum
        )

        let requestedSecondary = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: referenceHeight)
            * context.secondaryBaseScale
            * CGFloat(context.preference.secondaryMultiplier)
        let secondarySize = fitFontSizeByWidth(
            requested: requestedSecondary,
            text: context.secondaryText,
            availableWidth: availableWidth,
            minimum: secondaryMinimum
        )

        let baseGap = isGrid
            ? max(4, min(18, size.height * 0.035))
            : ScoreboardLayoutMetrics.nameToMainSpacing(halfViewportHeight: size.height)
        let profileReservedHeight: CGFloat
        switch context.profile {
        case .uno:
            profileReservedHeight = context.isLargeScreen ? 64 : 48
        case .nineBall:
            profileReservedHeight = context.isLargeScreen ? 44 : 34
        default:
            profileReservedHeight = 0
        }
        let hasName = !context.nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasScore = !context.scoreText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSecondary = !context.secondaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let mainToSecondarySpacing = context.secondaryIsInline && hasScore && hasSecondary
            ? ScoreboardLayoutMetrics.inlineMainToSecondarySpacing(halfViewportWidth: size.width)
            : 0
        let secondaryLineHeight = context.secondaryText.isEmpty || context.secondaryIsInline
            ? 0
            : secondarySize * 1.2
        let nameLineHeight = hasName ? nameSize * 1.2 : 0
        let nameScoreGap = hasName && hasScore ? baseGap : 0
        let reservedHeight = max(0, context.reservedHeight)
            + profileReservedHeight
            + nameLineHeight
            + secondaryLineHeight
            + nameScoreGap

        let requestedScoreBase: CGFloat
        if isGrid {
            let fillRatio: CGFloat = switch context.profile {
            case .uno, .multi: 0.7
            default: ScoreboardLayoutMetrics.playerGridScoreFontFillRatio
            }
            requestedScoreBase = ScoreboardLayoutMetrics.playerGridScoreFontSize(
                cellHeight: size.height,
                baseSize: scoreMinimum,
                reservedHeight: reservedHeight,
                fontScale: context.scoreBaseScale,
                fillRatio: fillRatio
            )
        } else {
            requestedScoreBase = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: referenceHeight)
                * context.scoreBaseScale
        }
        let requestedScore = requestedScoreBase * CGFloat(context.preference.scoreMultiplier)
        let inlineSecondaryWidth = context.secondaryIsInline && hasSecondary
            ? estimatedTextWidth(text: context.secondaryText, fontSize: secondarySize)
                + mainToSecondarySpacing
            : 0
        let widthLimitedScore = fitFontSizeByWidth(
            requested: requestedScore,
            text: context.scoreText,
            availableWidth: max(1, availableWidth - inlineSecondaryWidth),
            minimum: scoreMinimum
        )
        let verticalLimit = max(1, (size.height - reservedHeight) * 0.88)
        let scoreSize = max(1, min(widthLimitedScore, verticalLimit))

        let nameScale = min(1, nameSize / max(1, requestedName))
        let scoreScale = min(1, scoreSize / max(1, requestedScore))
        let compression = min(nameScale, scoreScale)
        let spacing = hasName && hasScore
            ? max(2, (baseGap * (0.4 + 0.6 * compression)).rounded())
            : 0

        return ScoreboardTypographyResult(
            nameFontSize: nameSize.rounded(),
            scoreFontSize: scoreSize.rounded(),
            secondaryFontSize: secondarySize.rounded(),
            nameToScoreSpacing: spacing,
            mainToSecondarySpacing: mainToSecondarySpacing
        )
    }

    private static func estimatedTextWidth(text: String, fontSize: CGFloat) -> CGFloat {
        let units = text.reduce(CGFloat.zero) { partial, character in
            partial + glyphWidthUnit(for: character)
        }
        return max(0, units * fontSize)
    }

    static func fitFontSizeByWidth(
        requested: CGFloat,
        text: String,
        availableWidth: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty else { return max(1, requested.rounded()) }
        let units = text.reduce(CGFloat.zero) { partial, character in
            partial + glyphWidthUnit(for: character)
        }
        let widthLimit = availableWidth / max(0.5, units)
        return max(1, min(requested, max(minimum, widthLimit))).rounded()
    }

    private static func glyphWidthUnit(for character: Character) -> CGFloat {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        if CharacterSet.decimalDigits.contains(scalar) { return 0.64 }
        if scalar.isASCII { return 0.58 }
        return 1
    }
}

enum ScoreboardPlayerGridLayout {
    static func nineBallRows(playerCount: Int, containerSize: CGSize) -> [[Int]] {
        let safeCount = min(4, max(2, playerCount))
        let indices = Array(0..<safeCount)
        let usesWideLayout = safeCount <= 2
            || containerSize.width >= containerSize.height * 0.9
        guard !usesWideLayout else { return [indices] }
        if safeCount == 3 {
            return indices.map { [$0] }
        }
        return [Array(indices.prefix(2)), Array(indices.dropFirst(2))]
    }

    static func multiRows(playerCount: Int, usesWideLayout: Bool) -> [[Int?]] {
        let safeCount = min(10, max(2, playerCount))
        let indices = Array(0..<safeCount)
        func row(_ range: Range<Int>) -> [Int?] {
            range.filter { indices.indices.contains($0) }.map { Optional(indices[$0]) }
        }
        if usesWideLayout {
            switch safeCount {
            case 2...4: return [indices.map(Optional.some)]
            case 5: return [row(0..<3), row(3..<5) + [nil]]
            case 6: return [row(0..<3), row(3..<6)]
            case 7: return [row(0..<4), row(4..<7) + [nil]]
            case 8: return [row(0..<4), row(4..<8)]
            case 9: return [row(0..<5), row(5..<9) + [nil]]
            case 10: return [row(0..<5), row(5..<10)]
            default: return [indices.map(Optional.some)]
            }
        }
        switch safeCount {
        case 2: return [[0], [1]]
        case 3: return [[0], [1], [2]]
        case 4: return [row(0..<2), row(2..<4)]
        case 5: return [row(0..<2), row(2..<5)]
        case 6: return [row(0..<3), row(3..<6)]
        case 7: return [row(0..<2), row(2..<5), row(5..<7)]
        case 8: return [row(0..<3), [3, nil, 4], row(5..<8)]
        case 9: return [row(0..<3), row(3..<6), row(6..<9)]
        case 10: return [row(0..<2), row(2..<4), row(4..<6), row(6..<8), row(8..<10)]
        default: return [indices.map(Optional.some)]
        }
    }
}
