import SwiftUI

enum ScoreboardExternalTemplate: String, Equatable {
    case twoSide
    case doublesCourt
    case multiGrid
    case cardTwoTeam
    case cardThreePlayer
    case cardTwoSeat
    case trainingCounter

    static func resolve(state: ScoreboardDisplayState) -> Self {
        switch state.layoutKind {
        case .twoSide: return .twoSide
        case .doublesCourt: return .doublesCourt
        case .multiGrid: return .multiGrid
        case .trainingCounter: return .trainingCounter
        case .boardCard:
            switch state.gameType {
            case "guandan", "shengji": return .cardTwoTeam
            case "doudizhu": return .cardThreePlayer
            case "xiangqi", "go", "chess", "checkers": return .cardTwoSeat
            default: return (state.players?.count ?? 0) >= 3 ? .cardThreePlayer : .cardTwoTeam
            }
        }
    }
}

/// 投屏上下文：本机扩展屏 / 跨设备同步显示端。
/// 对齐安卓 DisplaySurfaceBuildOptions.isLocalProjection：两者的字号缩放、名称缩放
/// 与倍率应用规则均不同（安卓 DisplayTypographyResolver 注释）。
enum ScoreboardExternalProjection {
    case localProjection
    case synchronizedDisplay

    var isLocalProjection: Bool { self == .localProjection }
}

struct ScoreboardExternalDisplayRootView: View {
    @ObservedObject private var outputs = ScoreboardDisplayOutputs.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let state = outputs.displayState {
                ScoreboardExternalLiveView(state: state)
                    .id("\(state.gameType)-\(state.layoutKind.rawValue)")
            } else {
                ScoreboardExternalWaitingView()
            }

            if outputs.controllerAway, outputs.displayState != nil {
                controllerAwayOverlay
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("external_display_root")
    }

    private var controllerAwayOverlay: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "iphone.slash")
                Text(NSLocalizedString("cast_controller_away", value: "控制端暂离", comment: ""))
                    .fontWeight(.semibold)
            }
            .font(.system(size: 24))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.black.opacity(0.72), in: Capsule())
            .padding(.top, 24)
            Spacer()
        }
    }
}

/// 「投屏已就绪」等待面板（对齐安卓 CastScoreboardPresentation.ProjectionWaiting）：
/// APP 图标 + 标题/副标题 + 日期 + 横排翻页时钟（含秒）。
private struct ScoreboardExternalWaitingView: View {
    private static func projectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy.MM.dd · EEEE"
        return formatter.string(from: date)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                let scale = max(0.85, min(1.8, proxy.size.width / 1280))
                let isLandscape = proxy.size.width > proxy.size.height
                let horizontalPadding: CGFloat = 32 * scale
                let availableWidth = max(proxy.size.width - horizontalPadding * 2, 1)
                let digitPairGap: CGFloat = 6 * scale
                let groupGap: CGFloat = 28 * scale
                let fixedGapWidth = digitPairGap * 3 + groupGap * 2
                let baseCardWidth: CGFloat = (isLandscape ? 148 : 96) * scale
                let fittedCardWidth = max((availableWidth - fixedGapWidth) / 6, 40)
                let cardWidth = min(baseCardWidth, fittedCardWidth)
                let cardHeight = cardWidth * 1.5
                let iconSize = min(96 * scale, 128)

                VStack(spacing: 0) {
                    Spacer()
                    // 图标 + 标题 相对整体中心略微上移（对齐安卓 offset(y = -16*scale)）。
                    VStack(spacing: 0) {
                        AppLogoImage(size: iconSize)
                        Text(NSLocalizedString("cast_ready_title", value: "投屏已就绪", comment: ""))
                            .font(.system(size: 38 * scale, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12 * scale)
                        Text(NSLocalizedString("cast_ready_message", value: "请在控制端打开一个计分板", comment: ""))
                            .font(.system(size: 16 * scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24 * scale)
                            .padding(.top, 6 * scale)
                    }
                    .offset(y: -16 * scale)
                    Text(Self.projectionDate(context.date))
                        .font(.system(size: 16 * scale, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 72 * scale)
                    Color.clear.frame(height: 24 * scale)
                    // 横排翻页时钟（含时分秒，对齐安卓 FlipClockFace）。
                    FlipClockFace(
                        date: context.date,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        digitGap: digitPairGap,
                        groupGap: groupGap,
                        showShadow: true,
                        hideCenterSeam: false
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "071017"))
            }
        }
        .accessibilityIdentifier("external_display_waiting")
    }
}

// MARK: - 安卓 DisplayTypographyResolver 移植（display/ui/DisplayTypographyResolver.kt）

private struct DisplayTypographyTokens {
    var score: CGFloat
    var name: CGFloat
    var sets: CGFloat
    var games: CGFloat
    var tennisSets: CGFloat
    var badge: CGFloat
    var meta: CGFloat
    var hint: CGFloat
    var labelStat: CGFloat
    var panelTopPadding: CGFloat
    var panelEdgeInset: CGFloat
}

private enum DisplayTypographyResolver {
    // 安卓常量（DisplayTypographyResolver.kt）
    private static let primaryScoreMax: CGFloat = 480
    private static let primaryScoreMin: CGFloat = 72
    private static let primaryScoreWidthRatio: CGFloat = 0.52
    private static let primaryScoreFontFillRatio: CGFloat = 0.85

    private static let twoSideScoreBandRatio: CGFloat = 0.52
    private static let twoSideStatsBandRatio: CGFloat = 0.12
    private static let twoSideCompactStatsBandRatio: CGFloat = 0.18

    private static let doublesNameBandRatio: CGFloat = 0.20
    private static let doublesScoreBandRatio: CGFloat = 0.50
    private static let doublesStatsBandRatio: CGFloat = 0.10

    private static let twoSideNameFontSize: CGFloat = 40
    private static let nameFontScale: CGFloat = 1.16
    private static let nameFontMin: CGFloat = 22
    private static let lhName: CGFloat = 1.2

    /// 展示端浮层缩放：短边 360 基线，最多 1.5（displayChromeScaleForViewport）。
    static func chromeScale(for viewport: CGSize) -> CGFloat {
        let shortEdge = min(viewport.width, viewport.height)
        guard shortEdge > 0 else { return 1 }
        return (shortEdge / 360).clamped(1, 1.5)
    }

    /// 同步显示端名称缩放：手机横屏 0.78 基线，大屏恢复到 0.9
    /// （synchronizedDisplayNameScaleForViewport；本机投屏恒为 1）。
    static func synchronizedNameScale(for viewport: CGSize, isLocalProjection: Bool) -> CGFloat {
        guard !isLocalProjection else { return 1 }
        let shortEdge = min(viewport.width, viewport.height)
        guard shortEdge > 0 else { return 0.78 }
        let progress = ((shortEdge - 360) / 360).clamped(0, 1)
        return 0.78 + progress * 0.12
    }

    /// 扩展屏次级分数缩放（extensionSecondaryScoreScaleForViewport）。
    static func secondaryScoreScale(for viewport: CGSize) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0 else { return 1 }
        let heightProgress = ((viewport.height - 360) / 180).clamped(0, 1)
        let halfPanelProgress = ((viewport.width / 2 - 320) / 160).clamped(0, 1)
        return 1 + min(heightProgress, halfPanelProgress)
    }

    /// 双打姓名缩放（extensionDoublesNameScaleForViewport）。
    static func doublesNameScale(for viewport: CGSize) -> CGFloat {
        1 + (secondaryScoreScale(for: viewport) - 1) * 0.7
    }

    static func twoSideTokens(width: CGFloat, height: CGFloat, isPhone: Bool) -> DisplayTypographyTokens {
        let compactPhone = isPhone && height < width && height <= 500
        let statsBandRatio = compactPhone ? twoSideCompactStatsBandRatio : twoSideStatsBandRatio
        let scoreBand = height * twoSideScoreBandRatio
        let statsBand = height * statsBandRatio
        let score = primaryScoreSize(width: width, scoreBand: scoreBand, maxSize: primaryScoreMax)
        let tennisMeta = tennisMetaScoreSize(width: width, height: height)
        let sets: CGFloat = compactPhone
            ? clampRound(statsBand * 0.92, 48, 88)
            : clampRound(statsBand * 0.75, 28, 80)
        return baseTokens(
            score: score,
            name: twoSideNameFontSize,
            sets: sets,
            games: tennisMeta,
            tennisSets: tennisMeta,
            badge: clampRound(height * 0.038, 14, 30),
            meta: clampRound(height * 0.032, 12, 26),
            hint: clampRound(height * 0.028, 11, 18),
            labelStat: clampRound(statsBand * 0.68, 16, 32),
            panelTopPadding: compactPhone
                ? clampRound(height * 0.045, 16, 32)
                : clampRound(height * 0.02, 8, 20),
            panelEdgeInset: compactPhone ? clampRound(height * 0.10, 28, 52) : 0
        )
    }

    static func doublesTokens(width: CGFloat, height: CGFloat, tennisDoubles: Bool) -> DisplayTypographyTokens {
        let nameBand = height * doublesNameBandRatio
        let scoreBand = height * doublesScoreBandRatio
        let statsBand = height * doublesStatsBandRatio
        let score = primaryScoreSize(width: width, scoreBand: scoreBand, maxSize: primaryScoreMax)
        let tennisMeta = tennisMetaScoreSize(width: width, height: height)
        return baseTokens(
            score: score,
            name: clampRound(nameBand * 0.42 * nameFontScale, 24, 49),
            sets: tennisDoubles
                ? tennisMeta
                : clampRound(max(statsBand * 1.25, score * 0.42), 52, 108),
            games: tennisDoubles
                ? tennisMeta
                : clampRound(statsBand * 0.68, 22, 60),
            tennisSets: clampRound(statsBand * 0.55, 18, 44),
            badge: clampRound(height * 0.034, 14, 28),
            meta: clampRound(height * 0.030, 12, 24),
            hint: clampRound(height * 0.026, 11, 18),
            labelStat: clampRound(statsBand * 0.65, 14, 28),
            panelTopPadding: clampRound(height * 0.015, 6, 16),
            panelEdgeInset: 0
        )
    }

    static func tennisMainScoreWidth(fontSize: CGFloat, scoreText: String) -> CGFloat {
        let widthFactor: CGFloat = scoreText.count > 1 ? 1.78 : 1.45
        return (fontSize * widthFactor).clamped(108, 520)
    }

    static func tennisSetScoreBoxSize(fontSize: CGFloat) -> CGFloat {
        (fontSize * 1.70).clamped(60, 180)
    }

    private static func primaryScoreSize(width: CGFloat, scoreBand: CGFloat, maxSize: CGFloat) -> CGFloat {
        let byHeight = scoreBand * primaryScoreFontFillRatio
        let byWidth = (width / 2) * primaryScoreWidthRatio
        return clampRound(min(byHeight, byWidth), primaryScoreMin, maxSize)
    }

    /// displayTennisMetaScoreSize + tennisGamesScoreZoneBaseSize。
    private static func tennisMetaScoreSize(width: CGFloat, height: CGFloat) -> CGFloat {
        let halfPanelWidth = max(width / 2, 1)
        let quarterHeight = max(height, 1) / 4
        let mainFromHeight = quarterHeight / 1.15
        let mainFromWidth = halfPanelWidth * 0.48
        let main = min(mainFromHeight, mainFromWidth).clamped(80, 420)
        return (main * 0.34).clamped(44, 88).rounded(.up)
    }

    private static func baseTokens(
        score: CGFloat,
        name: CGFloat,
        sets: CGFloat,
        games: CGFloat,
        tennisSets: CGFloat,
        badge: CGFloat,
        meta: CGFloat,
        hint: CGFloat,
        labelStat: CGFloat,
        panelTopPadding: CGFloat,
        panelEdgeInset: CGFloat
    ) -> DisplayTypographyTokens {
        DisplayTypographyTokens(
            score: score,
            name: name,
            sets: sets,
            games: games,
            tennisSets: tennisSets,
            badge: badge,
            meta: meta,
            hint: hint,
            labelStat: labelStat,
            panelTopPadding: panelTopPadding,
            panelEdgeInset: panelEdgeInset
        )
    }

    private static func clampRound(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        value.rounded().clamped(minValue, maxValue)
    }
}

private extension CGFloat {
    func clamped(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, minValue), maxValue)
    }
}

// MARK: - 项目分类（对齐安卓 DisplaySurfaceAdapter 的 GameType 集合）

private let displayTennisFamilyTypes: Set<String> = ["tennis", "tennis_doubles", "soft_tennis", "padel"]
private let displayNeedsSetsTypes: Set<String> = [
    "volleyball", "beach_volleyball", "air_volleyball",
    "pingpong", "pingpong_doubles",
    "badminton", "badminton_doubles",
    "shuttlecock", "squash", "padel",
    "pickleball", "pickleball_doubles",
    "foosball", "foosball_doubles", "archery_dual"
]
private let displayNeedsTwoSideServerTypes: Set<String> = [
    "pingpong", "badminton", "squash",
    "volleyball", "beach_volleyball", "air_volleyball",
    "tennis", "soft_tennis", "pickleball",
    "foosball", "foosball_doubles", "archery_dual",
    "snooker", "guandan", "shengji"
]
private let displayCenteredNameTypes: Set<String> = ["three_basketball", "boxing", "guandan", "shengji"]

// MARK: - two_side 渲染模型（对齐安卓 DisplayTwoSideModel 构建逻辑）

private enum DisplayTwoSideStatMode {
    case tennis
    case label
    case largeSets
    case none
}

private struct DisplayTwoSideSideModel {
    var name: String
    var scoreText: String
    var secondaryText: String
    var setsText: String
    var gamesText: String
    var showSecondary: Bool
    var showSets: Bool
    var showGames: Bool
    var panelHex: String
    var textHex: String
    /// 主分文字色（逐元素，默认回滚 textHex）。
    var mainHex: String
    /// 盘/局分文字色（逐元素，默认回滚 textHex）。
    var secondaryHex: String
}

private struct DisplayTwoSideRenderModel {
    var left: DisplayTwoSideSideModel
    var right: DisplayTwoSideSideModel
    var statMode: DisplayTwoSideStatMode
    var scoreFontSize: CGFloat
    var nameFontSize: CGFloat
    var setsFontSize: CGFloat
    var gamesFontSize: CGFloat
    var tennisSetsFontSize: CGFloat
    var labelStatFontSize: CGFloat
    var nameScoreGap: CGFloat
    var mainScoreSecondaryGap: CGFloat
    var panelTopPadding: CGFloat
    var panelEdgeInset: CGFloat
    var nameMaxLines: Int
    var nameHorizontalPadding: CGFloat
    var tennisContentGap: CGFloat
    var tennisMainScoreWidth: CGFloat
    var tennisSetScoreBoxSize: CGFloat
    var serverShowLeft: Bool
    var serverShowRight: Bool
    var arrowSize: CGFloat
    // 顶部浮层（对齐安卓 SportInfoBadge / BasketballFoulStrip / 标题带）。
    var titleBandHeight: CGFloat
    var contentTopInset: CGFloat
    /// 底部浮层预留（对齐安卓 contentBottomInset：本机投屏时面板整体上移，避免角分压在篮球时钟/追分带上）。
    var contentBottomInset: CGFloat
    var overlaySecondaryFontSize: CGFloat
    var overlayChromeScale: CGFloat
    var floatingEdgeInset: CGFloat
    var sportInfoTopInset: CGFloat
    var sportInfoText: String
    var sportInfoSegments: DisplaySportInfoSegments?
    var sportInfoTargetRacks: Int?
    var basketballFoulVisible: Bool
    var basketballFoulLeftText: String
    var basketballFoulRightText: String
    var basketballFoulLabelSize: CGFloat
    var basketballFoulCountSize: CGFloat
    var basketballFoulTopInset: CGFloat
    var basketballClockVisible: Bool
    /// 篮球时钟条时间字号倍率（对齐安卓 surface.twoSide.secondaryScoreScale）。
    var basketballClockScoreScale: CGFloat
}

/// 顶部信息条三段式（对齐安卓 DisplaySportInfoSegmentsModel，斯诺克局数用）。
private struct DisplaySportInfoSegments {
    var leading: String
    var center: String
    var trailing: String
}

/// 直播态外接屏视图；同时被投屏（外部显示器）与跨设备同步显示端（RemoteDisplayView）复用。
struct ScoreboardExternalLiveView: View {
    let state: ScoreboardDisplayState
    var projection: ScoreboardExternalProjection = .localProjection

    private var template: ScoreboardExternalTemplate {
        .resolve(state: state)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: state.appearance.backgroundHex)
                templateBody(viewport: proxy.size)

                topChrome

                if let rest = state.rest {
                    ScoreboardExternalRestOverlay(rest: rest, viewport: proxy.size)
                }
                if state.result?.ended == true {
                    resultOverlay(viewport: proxy.size)
                }
            }
            .clipped()
        }
        .accessibilityIdentifier("external_display_live_\(state.layoutKind.rawValue)")
    }

    // MARK: 顶部浮层（标题/计时/进攻计时）

    private var topChrome: some View {
        GeometryReader { proxy in
            let chrome = DisplayTypographyResolver.chromeScale(for: proxy.size).clamped(1, 1.5)
            // 比赛时钟距顶（对齐安卓 matchClockTopInset = 12*scale + 12*(scale-1)）。
            // 顶部不再渲染项目名标题带（对齐安卓 DisplaySurfaceHost 仅在真实 matchTitle 非空时渲染，
            // iOS 各计分板同步快照统一使用 displayName 填充 title，故一律不展示）。
            let clockTopInset = 12 * chrome + 12 * (chrome - 1)
            ZStack(alignment: .top) {
                if let clock = state.clock, clock.visible {
                    ScoreboardExternalClockView(
                        clock: clock,
                        fontCode: state.appearance.fontCode,
                        timeScale: projection.isLocalProjection
                            ? (min(proxy.size.width, proxy.size.height) / 360).clamped(1.5, 2)
                            : DisplayTypographyResolver.chromeScale(for: proxy.size)
                    )
                    .padding(.top, clockTopInset)
                }
            }
        }
    }

    @ViewBuilder
    private func templateBody(viewport: CGSize) -> some View {
        switch template {
        case .twoSide, .cardTwoTeam:
            DisplayTwoSideSurface(state: state, model: buildTwoSideModel(viewport: viewport), projection: projection)
        case .doublesCourt:
            DisplayDoublesCourtSurface(state: state, model: buildDoublesModel(viewport: viewport), projection: projection)
        case .multiGrid:
            DisplayMultiGridSurface(state: state, viewport: viewport, cardStyle: false)
        case .cardThreePlayer:
            DisplayMultiGridSurface(state: state, viewport: viewport, cardStyle: true)
        case .cardTwoSeat:
            DisplayTwoSeatSurface(state: state)
        case .trainingCounter:
            DisplayTrainingCounterSurface(state: state)
        }
    }

    // MARK: two_side 模型构建（对齐安卓 DisplaySurfaceAdapter.buildTwoSide）

    private func buildTwoSideModel(viewport: CGSize) -> DisplayTwoSideRenderModel {
        let gameType = state.gameType
        let isTennisFamily = displayTennisFamilyTypes.contains(gameType)
        let isSnooker = gameType == "snooker"
        let chrome = projection.isLocalProjection
            ? DisplayTypographyResolver.chromeScale(for: viewport)
            : 1
        let syncNameScale = DisplayTypographyResolver.synchronizedNameScale(for: viewport, isLocalProjection: projection.isLocalProjection)
        let secondaryScale = projection.isLocalProjection
            ? DisplayTypographyResolver.secondaryScoreScale(for: viewport)
            : 1
        let isTablet = min(viewport.width, viewport.height) >= 600
        let isPhone = !isTablet

        let left = buildTwoSideSide(isLeft: true, gameType: gameType)
        let right = buildTwoSideSide(isLeft: false, gameType: gameType)
        let sides = [left, right]

        let statMode: DisplayTwoSideStatMode = {
            if isTennisFamily { return .tennis }
            if gameType == "guandan" || gameType == "shengji" { return .label }
            if left.showSets || right.showSets { return .largeSets }
            return .none
        }()

        let tokens = DisplayTypographyResolver.twoSideTokens(
            width: viewport.width,
            height: viewport.height,
            isPhone: isPhone
        )

        // 字号倍率：仅同步显示端应用（安卓 styleMultipliers.takeUnless { isLocalProjection }）。
        let multipliers = projection.isLocalProjection ? nil : state.appearance.fontSizeMultipliers
        let mainMultiplier = CGFloat(multipliers?["mainScore"] ?? 1)
        let nameMultiplier = CGFloat(multipliers?["teamName"] ?? multipliers?["playerName"] ?? 1)
        let secondaryMultiplier = CGFloat(
            multipliers?["setScore"] ?? multipliers?["gameScore"] ?? multipliers?["setGameScore"] ?? 1
        )

        let baseScoreFontSize: CGFloat = {
            switch statMode {
            case .tennis: return (tokens.score * 0.78 * mainMultiplier).clamped(56, 320)
            case .label: return (tokens.score * mainMultiplier).clamped(56, 480)
            default: return (tokens.score * mainMultiplier).clamped(48, 480)
            }
        }()
        let tennisNameScale: CGFloat = statMode == .tennis ? 1.16 : 1
        let centered = displayCenteredNameTypes.contains(gameType)
        let baseNameFontSize: CGFloat = {
            let base = centered
                ? tokens.name * 1.08
                : tokens.name
            return (base * tennisNameScale * nameMultiplier * chrome * syncNameScale).clamped(18, 96)
        }()
        let baseSetsFontSize = (tokens.sets * secondaryMultiplier * secondaryScale).clamped(18, 160)
        let baseGamesFontSize = (tokens.games * secondaryMultiplier * secondaryScale).clamped(18, 160)
        let baseTennisSetsFontSize = (tokens.tennisSets * secondaryMultiplier * secondaryScale).clamped(18, 160)
        let baseLabelStatFontSize = (tokens.labelStat * secondaryScale).clamped(14, 96)

        // 顶部不再预留标题带（对齐安卓：未渲染顶部 matchTitle 时不预留 displayMatchTitleBandHeight）。
        let baseNameScoreGap: CGFloat = (baseScoreFontSize * 0.24).clamped(24, 60)
        let baseMainScoreSecondaryGap: CGFloat = isSnooker ? 2 : 8

        // 垂直预算（对齐安卓 availableHeight/verticalScale）。
        let matchTimeScale = projection.isLocalProjection
            ? (min(viewport.width, viewport.height) / 360).clamped(1.5, 2)
            : chrome
        let chromeGap = 8 * chrome

        let matchClockTopInset = 12 * chrome + 12 * (chrome - 1)
        var nextTopInset: CGFloat = 0
        if state.clock?.visible == true {
            nextTopInset = matchClockTopInset + 40 * matchTimeScale + chromeGap
        }

        // 顶部信息条（对齐安卓 SportInfoBadge：篮球节次/拳击回合/斯诺克局数/黑八目标）。
        // 对齐安卓 hasRealtimeBasketballClock：篮球实时时钟存在时，节次改由底部 BasketballClockPill 承载。
        var sportInfo = buildSportInfoBadge(gameType: gameType)
        if hasRealtimeBasketballClock {
            sportInfo.text = ""
        }
        let hasSportInfo = !sportInfo.text.isEmpty || sportInfo.segments != nil || sportInfo.targetRacks != nil
        let sportInfoTopInset = hasSportInfo ? max(nextTopInset, 12 * chrome) : 0
        if hasSportInfo {
            let sportInfoHeight = max(tokens.meta * secondaryScale * 1.2, 18 * chrome) + 14 * chrome
            nextTopInset = sportInfoTopInset + sportInfoHeight + chromeGap
        }

        // 篮球犯规条（对齐安卓 BasketballFoulStrip）。
        let foulStrip = buildBasketballFoulStrip(gameType: gameType, chrome: chrome, secondaryScale: secondaryScale, tokens: tokens)
        let floatingEdgeInset = 16 * chrome + 12 * (chrome - 1)
        let basketballFoulTopInset = foulStrip.visible ? max(nextTopInset, floatingEdgeInset) : 0
        if foulStrip.visible {
            let foulHeight = max(foulStrip.labelSize, foulStrip.countSize) * 1.2 + 16 * chrome
            nextTopInset = basketballFoulTopInset + foulHeight + chromeGap
        }

        let contentTopInset = projection.isLocalProjection ? nextTopInset : 0
        // 本机投屏时为底部浮层（篮球时钟条/九球追分带）预留高度（对齐安卓 contentBottomInset）。
        let contentBottomInset: CGFloat = {
            guard projection.isLocalProjection else { return 0 }
            guard hasRealtimeBasketballClock else { return 0 }
            let c = chrome.clamped(1, 1.5)
            let s = secondaryScale.clamped(1, 2)
            let clockRow = 21 * s * 1.2 + 20 * c
            let pauseRow = 42 * c
            let edge = 16 * c + 12 * (c - 1)
            return clockRow + pauseRow + edge + 8 * c
        }()

        let availableHeight = max(
            viewport.height - contentTopInset - contentBottomInset - 16 * chrome,
            1
        )
        let baseScoreLineHeight = baseScoreFontSize * 1.02
        let baseNameLineHeight = baseNameFontSize * 1.2
        let anyShowSecondary = sides.contains { $0.showSecondary }
        let baseSecondaryHeight: CGFloat = {
            if isSnooker && anyShowSecondary {
                let baseCap: CGFloat = baseScoreFontSize >= 220 ? 48 : 42
                let enlarged = min(baseLabelStatFontSize * 1.32, baseCap * secondaryScale.clamped(1, 2))
                return max(enlarged, baseSetsFontSize) * 1.08 + baseMainScoreSecondaryGap
            }
            return anyShowSecondary ? baseLabelStatFontSize * 1.12 : 0
        }()
        let anyShowStats = sides.contains { $0.showSets || $0.showGames }
        let baseSetHeight: CGFloat = anyShowStats
            ? baseSetsFontSize * 1.1 + (baseSetsFontSize * 0.24).clamped(8, 20)
            : 0
        let baseVerticalContentHeight: CGFloat = {
            if statMode == .tennis {
                let statsHeight: CGFloat = {
                    guard sides.contains(where: { $0.showGames || $0.showSets }) else { return 0 }
                    let setPart: CGFloat = sides.contains { $0.showSets }
                        ? (baseGamesFontSize * 0.28).clamped(8, 18)
                            + DisplayTypographyResolver.tennisSetScoreBoxSize(fontSize: baseTennisSetsFontSize)
                        : 0
                    return baseGamesFontSize * 1.1 + setPart
                }()
                return baseNameLineHeight + tokens.panelTopPadding + max(baseScoreLineHeight, statsHeight) + 16 * chrome
            }
            return baseNameLineHeight + baseNameScoreGap + baseScoreLineHeight + baseSecondaryHeight + baseSetHeight
        }()
        let verticalScale = baseVerticalContentHeight > availableHeight
            ? (availableHeight / baseVerticalContentHeight).clamped(0.25, 1)
            : 1

        // 网球横向预算（对齐安卓 resolveTennisProjectionContentScale）。
        let baseTennisGap = 32 * chrome
        let longestScoreText = sides.map { $0.scoreText }.max(by: { $0.count < $1.count }) ?? "0"
        let horizontalScale: CGFloat = {
            guard statMode == .tennis else { return 1 }
            let availableWidth = max(viewport.width / 2 - 32 - tokens.panelEdgeInset, 1)
            return resolveTennisContentScale(
                availableWidth: availableWidth,
                scoreFontSize: baseScoreFontSize,
                gamesFontSize: baseGamesFontSize,
                setsFontSize: baseTennisSetsFontSize,
                showGames: sides.contains { $0.showGames },
                showSets: sides.contains { $0.showSets },
                baseGap: baseTennisGap,
                scoreText: longestScoreText
            )
        }()
        let contentScale = min(verticalScale, horizontalScale)

        return DisplayTwoSideRenderModel(
            left: left,
            right: right,
            statMode: statMode,
            scoreFontSize: baseScoreFontSize * contentScale,
            nameFontSize: baseNameFontSize * contentScale,
            setsFontSize: baseSetsFontSize * contentScale,
            gamesFontSize: baseGamesFontSize * contentScale,
            tennisSetsFontSize: baseTennisSetsFontSize * contentScale,
            labelStatFontSize: baseLabelStatFontSize * contentScale,
            nameScoreGap: baseNameScoreGap * contentScale,
            mainScoreSecondaryGap: baseMainScoreSecondaryGap * contentScale,
            panelTopPadding: tokens.panelTopPadding,
            panelEdgeInset: tokens.panelEdgeInset,
            nameMaxLines: projection.isLocalProjection ? 1 : 2,
            nameHorizontalPadding: projection.isLocalProjection ? (16 * chrome).clamped(16, 24) : 0,
            tennisContentGap: baseTennisGap * contentScale,
            tennisMainScoreWidth: DisplayTypographyResolver.tennisMainScoreWidth(
                fontSize: baseScoreFontSize * contentScale,
                scoreText: longestScoreText
            ),
            tennisSetScoreBoxSize: DisplayTypographyResolver.tennisSetScoreBoxSize(
                fontSize: baseTennisSetsFontSize * contentScale
            ),
            serverShowLeft: false,
            serverShowRight: false,
            arrowSize: 0,
            titleBandHeight: 0,
            contentTopInset: contentTopInset,
            contentBottomInset: contentBottomInset,
            overlaySecondaryFontSize: tokens.meta * secondaryScale,
            overlayChromeScale: chrome.clamped(1, 1.5),
            floatingEdgeInset: floatingEdgeInset,
            sportInfoTopInset: sportInfoTopInset,
            sportInfoText: sportInfo.text,
            sportInfoSegments: sportInfo.segments,
            sportInfoTargetRacks: sportInfo.targetRacks,
            basketballFoulVisible: foulStrip.visible,
            basketballFoulLeftText: foulStrip.leftText,
            basketballFoulRightText: foulStrip.rightText,
            basketballFoulLabelSize: foulStrip.labelSize,
            basketballFoulCountSize: foulStrip.countSize,
            basketballFoulTopInset: basketballFoulTopInset,
            basketballClockVisible: hasRealtimeBasketballClock,
            basketballClockScoreScale: secondaryScale
        ).applyingServerIndicator(
            state: state,
            gameType: gameType,
            arrowSize: baseScoreFontSize * contentScale * 0.30 > 0
                ? (baseScoreFontSize * contentScale * 0.30).clamped(30, 72)
                : 0
        )
    }

    /// 二分逼近（安卓 resolveTennisProjectionContentScale）。
    private func resolveTennisContentScale(
        availableWidth: CGFloat,
        scoreFontSize: CGFloat,
        gamesFontSize: CGFloat,
        setsFontSize: CGFloat,
        showGames: Bool,
        showSets: Bool,
        baseGap: CGFloat,
        scoreText: String
    ) -> CGFloat {
        func groupWidth(_ scale: CGFloat) -> CGFloat {
            let mainWidth = DisplayTypographyResolver.tennisMainScoreWidth(
                fontSize: scoreFontSize * scale,
                scoreText: scoreText
            )
            guard showGames || showSets else { return mainWidth }
            let setBox: CGFloat = showSets
                ? DisplayTypographyResolver.tennisSetScoreBoxSize(fontSize: setsFontSize * scale)
                : 0
            let gamesWidth: CGFloat = showGames ? (gamesFontSize * scale * 1.16).clamped(56, 180) : 0
            return mainWidth + baseGap * scale + max(setBox, gamesWidth)
        }
        guard availableWidth > 0 else { return 0.25 }
        if groupWidth(1) <= availableWidth { return 1 }
        var low: CGFloat = 0.25
        var high: CGFloat = 1
        for _ in 0..<20 {
            let candidate = (low + high) / 2
            if groupWidth(candidate) <= availableWidth {
                low = candidate
            } else {
                high = candidate
            }
        }
        return low
    }

    /// 单侧面板内容（对齐安卓 buildSurfaceSide）。
    private func buildTwoSideSide(isLeft: Bool, gameType: String) -> DisplayTwoSideSideModel {
        let isLogicalTeam0 = logicalTeam0(isOnScreenSide: isLeft)
        let team = state.teams.first(where: { $0.id == (isLogicalTeam0 ? "team_0" : "team_1") })
        let panelHex = isLeft ? state.appearance.leftPanelHex : state.appearance.rightPanelHex
        let textHex = isLeft ? state.appearance.leftTextHex : state.appearance.rightTextHex
        let mainHex = isLeft ? state.appearance.leftMainTextHex : state.appearance.rightMainTextHex
        let secondaryHex = isLeft ? state.appearance.leftSecondaryTextHex : state.appearance.rightSecondaryTextHex

        var secondaryText = ""
        switch gameType {
        case "snooker":
            secondaryText = "\(sportNumber(isLogicalTeam0 ? "snookerLeftBreak" : "snookerRightBreak"))"
        case "guandan":
            let failCount = sportNumber(isLogicalTeam0 ? "guandanLeftAFailCount" : "guandanRightAFailCount")
            if failCount > 0 {
                secondaryText = String(
                    format: NSLocalizedString("display_guandan_pass_a", value: "过A %d", comment: ""),
                    failCount
                )
            } else if sportBool("guandanTripleAEnabled") {
                secondaryText = NSLocalizedString("display_guandan_triple_a", value: "三A", comment: "")
            }
        case "eight_ball":
            let handicap = sportNumber("eightBallHandicapRacks")
            if handicap > 0 {
                let beneficiary = state.sportString("eightBallHandicapBeneficiary")
                let belongsToSide: Bool = {
                    switch beneficiary {
                    case "team1", "team_0": return isLogicalTeam0
                    case "team2", "team_1": return !isLogicalTeam0
                    default: return false
                    }
                }()
                secondaryText = belongsToSide ? "+\(handicap)" : ""
            }
        default:
            break
        }

        let tiebreakOnly = state.sportBoolValue("tennisTiebreakOnly") == true
        let isTennisFamily = displayTennisFamilyTypes.contains(gameType)
        let rawSets = team?.sets ?? 0
        let rawGames = team?.games ?? 0
        let anySetsVisible = (state.teams.first(where: { $0.id == "team_0" })?.sets ?? 0) > 0
            || (state.teams.first(where: { $0.id == "team_1" })?.sets ?? 0) > 0
        let showSets: Bool = {
            if gameType == "snooker" || tiebreakOnly { return false }
            if isTennisFamily { return anySetsVisible }
            return displayNeedsSetsTypes.contains(gameType)
        }()
        let showGames: Bool = !tiebreakOnly && isTennisFamily && (rawGames != 0 || team?.games != nil)

        return DisplayTwoSideSideModel(
            name: team?.name ?? "",
            scoreText: formattedTwoSideScore(
                gameType: gameType,
                isLeft: isLeft,
                isLogicalTeam0: isLogicalTeam0,
                rawScoreText: state.displayScore(forVisualIndex: isLeft ? 0 : 1),
                rawScore: team?.score ?? 0
            ),
            secondaryText: secondaryText,
            setsText: "\(rawSets)",
            gamesText: "\(rawGames)",
            showSecondary: !secondaryText.isEmpty,
            showSets: showSets,
            showGames: showGames,
            panelHex: team?.color ?? panelHex,
            textHex: textHex,
            mainHex: mainHex,
            secondaryHex: secondaryHex
        )
    }

    /// 主分文案（对齐安卓 formatTwoSideScoreText：网球系按原始分转换，其他项目透传）。
    private func formattedTwoSideScore(
        gameType: String,
        isLeft: Bool,
        isLogicalTeam0: Bool,
        rawScoreText: String,
        rawScore: Int
    ) -> String {
        let isTennisFamily = displayTennisFamilyTypes.contains(gameType)
        guard isTennisFamily else {
            if gameType == "guandan" {
                let rank = state.sportString(isLogicalTeam0 ? "guandanRedRank" : "guandanBlueRank")
                if let rank, !rank.isEmpty { return rank }
            }
            if gameType == "shengji" {
                let rank = state.sportString(isLogicalTeam0 ? "shengjiRedRank" : "shengjiBlueRank")
                if let rank, !rank.isEmpty { return rank }
            }
            return rawScoreText
        }
        // 有显示层覆盖（iOS 分享端已格式化）时直接使用。
        if state.sportString(isLeft ? "leftDisplayScore" : "rightDisplayScore") != nil {
            return rawScoreText
        }
        if state.sportBoolValue("tennisIsTieBreak") == true { return "\(rawScore)" }
        if gameType == "soft_tennis" {
            let opponent = opponentScore(isLeft: isLeft)
            return formatSoftTennisPoint(rawScore, opponentScore: opponent)
        }
        if state.sportBoolValue("tennisIsDeuce") == true {
            if state.sportString("tennisDeuceMode") == "no_ad" { return "40" }
            let advantage = state.sportString("tennisAdvantage")
            guard let advantage, !advantage.isEmpty, advantage != "none" else { return "40" }
            let advantageScreenSide = servingScreenSide(forTeam: advantage)
            let hasAdvantage = isLeft ? advantageScreenSide == "left" : advantageScreenSide == "right"
            return hasAdvantage ? "AD" : "40"
        }
        return formatTennisPointScore(rawScore)
    }

    private func formatTennisPointScore(_ score: Int) -> String {
        switch score {
        case 0: "0"
        case 1: "15"
        case 2: "30"
        case 3: "40"
        case 4: "AD"
        default: "--"
        }
    }

    private func formatSoftTennisPoint(_ score: Int, opponentScore: Int) -> String {
        if score <= 3 { return "\(score)" }
        if score - opponentScore == 1 { return "AD" }
        return "3"
    }

    private func opponentScore(isLeft: Bool) -> Int {
        let isOpponentTeam0 = logicalTeam0(isOnScreenSide: isLeft) == false
        let team = state.teams.first(where: { $0.id == (isOpponentTeam0 ? "team_0" : "team_1") })
        return team?.score ?? 0
    }

    // MARK: doubles 模型构建（对齐安卓 DisplaySurfaceAdapter.buildDoubles）

    private func buildDoublesModel(viewport: CGSize) -> DisplayDoublesRenderModel {
        let gameType = state.gameType
        let tennisDoubles = displayTennisFamilyTypes.contains(gameType)
        let isTablet = min(viewport.width, viewport.height) >= 600
        let chrome = projection.isLocalProjection
            ? DisplayTypographyResolver.chromeScale(for: viewport)
            : 1
        let syncNameScale = DisplayTypographyResolver.synchronizedNameScale(for: viewport, isLocalProjection: projection.isLocalProjection)
        let secondaryScale = projection.isLocalProjection
            ? DisplayTypographyResolver.secondaryScoreScale(for: viewport)
            : 1
        let nameScale = projection.isLocalProjection
            ? DisplayTypographyResolver.doublesNameScale(for: viewport)
            : 1

        let tokens = DisplayTypographyResolver.doublesTokens(
            width: viewport.width,
            height: viewport.height,
            tennisDoubles: tennisDoubles
        )
        let multipliers = projection.isLocalProjection ? nil : state.appearance.fontSizeMultipliers
        let scoreMultiplier = CGFloat(multipliers?["mainScore"] ?? 1)
        let nameMultiplier = CGFloat(multipliers?["playerName"] ?? multipliers?["teamName"] ?? 1)
        let secondaryMultiplier = CGFloat(
            multipliers?["setGameScore"] ?? multipliers?["setScore"] ?? multipliers?["gameScore"] ?? 1
        )

        let scoreFontSize = (tokens.score * scoreMultiplier).clamped(48, 360)
        let nameFontSize = (tokens.name * nameMultiplier * nameScale * syncNameScale).clamped(24, 80)
        let gamesFontSize = (tokens.games * secondaryMultiplier * secondaryScale).clamped(18, 160)
        let setsFontSize = (tokens.sets * secondaryMultiplier * secondaryScale).clamped(18, 160)

        let left = buildDoublesSide(isLeft: true, gameType: gameType)
        let right = buildDoublesSide(isLeft: false, gameType: gameType)

        // 发球指示（对齐安卓 doublesServerPlayer + DoublesServeIndicator）。
        var serverVisible = false
        var serverPointLeft = true
        var serverTopRow = true
        if state.result?.ended != true {
            let server = state.players?.first(where: { $0.isServer == true })
            if let server {
                serverVisible = true
                let teamID = server.teamID ?? "team_0"
                let team0Side = state.sportString("team0ScreenSide") == "right" ? "right" : "left"
                let screenSide = teamID == "team_1" ? (team0Side == "left" ? "right" : "left") : team0Side
                serverPointLeft = screenSide == "left"
                serverTopRow = server.slot != "bottom"
            } else if let side = state.sportString("servingSide") {
                serverVisible = displayNeedsTwoSideServerTypes.contains(gameType)
                serverPointLeft = side == "left"
                serverTopRow = true
            }
        }

        return DisplayDoublesRenderModel(
            left: left,
            right: right,
            useTennisLayout: tennisDoubles,
            serverVisible: serverVisible,
            serverPointLeft: serverPointLeft,
            serverTopRow: serverTopRow,
            scoreFontSize: scoreFontSize,
            scoreLineHeight: max(scoreFontSize * 1.02, scoreFontSize),
            nameFontSize: nameFontSize,
            nameLineHeight: max(nameFontSize * 1.2, nameFontSize),
            gamesFontSize: gamesFontSize,
            setsFontSize: setsFontSize,
            arrowSize: tennisDoubles ? (scoreFontSize * 0.26).clamped(24, 52) : (scoreFontSize * 0.30).clamped(30, 72),
            nameMaxLines: projection.isLocalProjection ? 1 : 2,
            nameHorizontalPadding: projection.isLocalProjection ? (16 * chrome).clamped(16, 24) : 8,
            nameCenterGutter: projection.isLocalProjection ? (tokens.badge + 12 * chrome) / 2 : 8,
            mainSecondarySpacing: projection.isLocalProjection ? min(64 * chrome, 96) : 32,
            isTablet: isTablet
        )
    }

    private func buildDoublesSide(isLeft: Bool, gameType: String) -> DisplayDoublesSideRenderModel {
        let isLogicalTeam0 = logicalTeam0(isOnScreenSide: isLeft)
        let teamID = isLogicalTeam0 ? "team_0" : "team_1"
        let team = state.teams.first(where: { $0.id == teamID })
        let players = state.players?.filter { $0.teamID == teamID }.sorted { $0.order < $1.order } ?? []
        let teamNameParts = (team?.name ?? "").components(separatedBy: CharacterSet(charactersIn: "/、&"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func name(for slot: String) -> String {
            if let player = players.first(where: { $0.slot == slot }), !player.name.isEmpty {
                return player.name
            }
            if players.count >= 2 {
                return slot == "top" ? players[0].name : players[1].name
            }
            return slot == "top" ? (teamNameParts.first ?? "") : (teamNameParts.dropFirst().first ?? "")
        }

        let tiebreakOnly = state.sportBoolValue("tennisTiebreakOnly") == true
        let isTennisFamily = displayTennisFamilyTypes.contains(gameType)
        let anySetsVisible = (state.teams.first(where: { $0.id == "team_0" })?.sets ?? 0) > 0
            || (state.teams.first(where: { $0.id == "team_1" })?.sets ?? 0) > 0
        let showSets: Bool = {
            if tiebreakOnly { return false }
            if isTennisFamily { return anySetsVisible }
            return displayNeedsSetsTypes.contains(gameType)
        }()
        let showGames: Bool = !tiebreakOnly && isTennisFamily && (team?.games != nil)

        return DisplayDoublesSideRenderModel(
            topName: name(for: "top"),
            bottomName: name(for: "bottom"),
            scoreText: formattedTwoSideScore(
                gameType: gameType,
                isLeft: isLeft,
                isLogicalTeam0: isLogicalTeam0,
                rawScoreText: state.displayScore(forVisualIndex: isLeft ? 0 : 1),
                rawScore: team?.score ?? 0
            ),
            setsText: "\(team?.sets ?? 0)",
            gamesText: "\(team?.games ?? 0)",
            showSets: showSets,
            showGames: showGames,
            panelHex: team?.color ?? (isLeft ? state.appearance.leftPanelHex : state.appearance.rightPanelHex),
            textHex: isLeft ? state.appearance.leftTextHex : state.appearance.rightTextHex,
            mainHex: isLeft ? state.appearance.leftMainTextHex : state.appearance.rightMainTextHex,
            secondaryHex: isLeft ? state.appearance.leftSecondaryTextHex : state.appearance.rightSecondaryTextHex
        )
    }

    // MARK: 通用小工具

    private func logicalTeam0(isOnScreenSide isLeft: Bool) -> Bool {
        (state.sportString("team0ScreenSide") == "right") != isLeft
    }

    private func sportNumber(_ key: String) -> Int {
        state.sportInt(key) ?? 0
    }

    private func sportBool(_ key: String) -> Bool {
        state.sportBoolValue(key) == true
    }

    /// 对齐安卓 hasRealtimeBasketballClock：篮球实时时钟锚点完整时，节次/时间由 BasketballClockPill 承载。
    private var hasRealtimeBasketballClock: Bool {
        guard state.gameType == "basketball" || state.gameType == "three_basketball" else { return false }
        return state.sportInt("basketballGameTime") != nil
            && state.sportInt("basketballShotTime") != nil
            && state.sportBoolValue("basketballGameRunning") != nil
            && state.sportBoolValue("basketballShotRunning") != nil
            && state.sportInt("basketballClockRevision") != nil
    }

    /// 顶部信息条文案（对齐安卓 buildSportInfoBadge）。
    private func buildSportInfoBadge(gameType: String)
        -> (text: String, segments: DisplaySportInfoSegments?, targetRacks: Int?) {
        switch gameType {
        case "basketball":
            let period = max(1, sportNumber("basketballCurrentPeriod"))
            if sportBool("basketballIsOT") {
                return (period > 4 ? "OT\(period - 4)" : "OT", nil, nil)
            }
            return (String(format: NSLocalizedString("display_basketball_period", value: "第 %d 节", comment: ""), period), nil, nil)
        case "three_basketball":
            return ("", nil, nil)
        case "boxing":
            let round = max(1, sportNumber("boxingCurrentRound"))
            let maxRounds = sportNumber("boxingMaxRounds")
            if maxRounds > 0 {
                return (String(
                    format: NSLocalizedString("boxing_round_progress", value: "第 %d/%d 回合", comment: ""),
                    round, maxRounds
                ), nil, nil)
            }
            return (String(format: NSLocalizedString("boxing_round_n", value: "第 %d 回合", comment: ""), round), nil, nil)
        case "snooker":
            let maxFrames = sportNumber("snookerMaxFrames")
            guard maxFrames > 1 else { return ("", nil, nil) }
            let current = min(max(1, sportNumber("currentSet")), maxFrames)
            let leftTeamID = logicalTeam0(isOnScreenSide: true) ? "team_0" : "team_1"
            let rightTeamID = leftTeamID == "team_0" ? "team_1" : "team_0"
            let leftFrames = state.teams.first(where: { $0.id == leftTeamID })?.sets ?? 0
            let rightFrames = state.teams.first(where: { $0.id == rightTeamID })?.sets ?? 0
            let center = String(
                format: NSLocalizedString("snooker_current_frame_short", value: "第 %d/%d 局", comment: ""),
                current, maxFrames
            )
            return ("", DisplaySportInfoSegments(
                leading: "\(leftFrames)",
                center: center,
                trailing: "\(rightFrames)"
            ), nil)
        case "eight_ball":
            let racks = sportNumber("eightBallTargetRacks")
            if racks > 0 { return ("", nil, racks) }
            return ("", nil, nil)
        default:
            return ("", nil, nil)
        }
    }

    /// 篮球犯规条（对齐安卓 buildBasketballFoulStrip）。
    private func buildBasketballFoulStrip(
        gameType: String,
        chrome: CGFloat,
        secondaryScale: CGFloat,
        tokens: DisplayTypographyTokens
    ) -> (visible: Bool, leftText: String, rightText: String, labelSize: CGFloat, countSize: CGFloat) {
        guard gameType == "basketball" || gameType == "three_basketball" else {
            return (false, "0", "0", 0, 0)
        }
        let logicalLeftFouls = sportNumber("basketballLeftFouls")
        let logicalRightFouls = sportNumber("basketballRightFouls")
        let team0OnLeft = state.sportString("team0ScreenSide") != "right"
        return (
            true,
            (team0OnLeft ? logicalLeftFouls : logicalRightFouls).description,
            (team0OnLeft ? logicalRightFouls : logicalLeftFouls).description,
            (tokens.meta * chrome).clamped(12, 30),
            (tokens.badge * secondaryScale).clamped(14, 48)
        )
    }

    private func servingScreenSide(forTeam teamID: String) -> String? {
        let team0Side = state.sportString("team0ScreenSide") == "right" ? "right" : "left"
        switch teamID.lowercased() {
        case "team_0": return team0Side
        case "team_1": return team0Side == "left" ? "right" : "left"
        default: return nil
        }
    }

    // MARK: 结束遮罩

    private func resultOverlay(viewport: CGSize) -> some View {
        let chrome = DisplayTypographyResolver.chromeScale(for: viewport)
        let winnerID = state.result?.winnerID
        let winnerName = state.teams.first(where: { $0.id == winnerID })?.name
        return VStack(spacing: 10 * chrome) {
            Text(NSLocalizedString("cast_match_finished", value: "比赛结束", comment: ""))
                .font(displayFont(size: 32 * chrome, weight: .bold))
            Text(winnerName.map {
                String(format: NSLocalizedString("cast_winner_format", value: "%@ 获胜", comment: ""), $0)
            } ?? NSLocalizedString("cast_result_draw", value: "比赛结果已确认", comment: ""))
                .font(displayFont(size: 30 * chrome, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 30 * chrome * 1.6)
        .padding(.vertical, 30 * chrome)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 15 * chrome))
        .shadow(color: .black.opacity(0.4), radius: 24)
    }

    private func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        (ScoreboardFont(rawValue: state.appearance.fontCode) ?? .default)
            .swiftUIFont(size: size, weight: weight)
    }
}

// MARK: - two_side 渲染（对齐安卓 DisplayTwoSideSurface / TwoSidePanel / TennisSideContent）

private struct DisplayTwoSideSurface: View {
    let state: ScoreboardDisplayState
    let model: DisplayTwoSideRenderModel
    let projection: ScoreboardExternalProjection

    @State private var basketballReceiptMs: Int64 = 0

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                panel(side: model.left, isLeft: true)
                panel(side: model.right, isLeft: false)
            }
            // 发球指示三角（对齐安卓 TwoSideServerIndicator）。
            serverIndicator
            // 关键分徽标。
            keyPointBadge
            // 顶部信息条（对齐安卓 SportInfoBadge：篮球节次/拳击回合/斯诺克局数/黑八目标）。
            sportInfoBadge
            // 篮球犯规条（对齐安卓 BasketballFoulStrip）。
            basketballFoulStrip
            // 篮球时钟条（对齐安卓 BasketballClockPill：底部居中）。
            basketballClockPill
        }
        .onChange(of: basketballClockRevision) { _ in
            // 记录锚点接收时刻，用于时钟投影（对齐安卓 anchorReceivedRealtimeMs）。
            basketballReceiptMs = Int64(Date().timeIntervalSince1970 * 1_000)
        }
    }

    @ViewBuilder
    private var sportInfoBadge: some View {
        let topPadding = model.sportInfoTopInset > 0
            ? model.sportInfoTopInset
            : (model.titleBandHeight > 0
                ? model.titleBandHeight + 8 * model.overlayChromeScale
                : max(model.panelTopPadding, 30 * model.overlayChromeScale))
        if !model.sportInfoText.isEmpty || model.sportInfoSegments != nil || model.sportInfoTargetRacks != nil {
            Group {
                if let segments = model.sportInfoSegments {
                    HStack(spacing: 8 * model.overlayChromeScale) {
                        Text(segments.leading)
                            .fontWeight(.bold)
                        Text(segments.center)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.64))
                        Text(segments.trailing)
                            .fontWeight(.bold)
                    }
                    .font(.system(size: model.overlaySecondaryFontSize, weight: .bold))
                } else if let racks = model.sportInfoTargetRacks {
                    HStack(spacing: 6 * model.overlayChromeScale) {
                        Image(systemName: "scope")
                            .font(.system(size: model.overlaySecondaryFontSize * 1.15, weight: .medium))
                        Text("\(racks)")
                            .font(.system(size: model.overlaySecondaryFontSize * 0.96, weight: .bold))
                        if !model.sportInfoText.isEmpty {
                            Text(model.sportInfoText)
                                .font(.system(size: model.overlaySecondaryFontSize * 0.88, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                } else {
                    Text(model.sportInfoText)
                        .font(.system(size: model.overlaySecondaryFontSize, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 14 * model.overlayChromeScale)
            .padding(.vertical, 7 * model.overlayChromeScale)
            .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 14 * model.overlayChromeScale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, topPadding)
        }
    }

    @ViewBuilder
    private var basketballFoulStrip: some View {
        if model.basketballFoulVisible {
            let placeAtTop = model.basketballFoulTopInset > 0 || model.basketballClockVisible
            HStack(spacing: 18 * model.overlayChromeScale) {
                Text(model.basketballFoulLeftText)
                    .font(.system(size: model.basketballFoulCountSize, weight: .bold))
                Text(NSLocalizedString("display_basketball_foul", value: "犯规", comment: ""))
                    .font(.system(size: model.basketballFoulLabelSize))
                    .foregroundStyle(.white.opacity(0.72))
                Text(model.basketballFoulRightText)
                    .font(.system(size: model.basketballFoulCountSize, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16 * model.overlayChromeScale)
            .padding(.vertical, 8 * model.overlayChromeScale)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14 * model.overlayChromeScale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placeAtTop ? .top : .bottom)
            .padding(.top, placeAtTop ? (model.basketballFoulTopInset > 0 ? model.basketballFoulTopInset : model.floatingEdgeInset) : 0)
            .padding(.bottom, placeAtTop ? 0 : 20 * model.overlayChromeScale)
        }
    }

    // MARK: 篮球时钟条（对齐安卓 BasketballClockPill：底部居中，节次 | 比赛时间 | 进攻时间）

    private var basketballClockRevision: Int {
        state.sportInt("basketballClockRevision") ?? 0
    }

    /// 对齐安卓 readBasketballClockAnchor。
    private var basketballClockAnchor: (
        gameSeconds: Int, shotSeconds: Int, gameRunning: Bool, shotRunning: Bool, clockStarted: Bool
    )? {
        guard state.gameType == "basketball" || state.gameType == "three_basketball" else { return nil }
        guard let game = state.sportInt("basketballGameTime"),
              let shot = state.sportInt("basketballShotTime"),
              let gameRunning = state.sportBoolValue("basketballGameRunning"),
              let shotRunning = state.sportBoolValue("basketballShotRunning") else {
            return nil
        }
        return (game, shot, gameRunning, shotRunning, state.sportBoolValue("basketballClockStarted") ?? true)
    }

    /// 对齐安卓 projectBasketballRemaining：按锚点接收时刻做秒级投影。
    private func projectedBasketballRemaining(_ anchorSeconds: Int, running: Bool, nowMs: Int64) -> Int {
        guard running, basketballReceiptMs > 0, nowMs > basketballReceiptMs else { return max(0, anchorSeconds) }
        let elapsedSeconds = Int((nowMs - basketballReceiptMs) / 1_000)
        return max(0, anchorSeconds - elapsedSeconds)
    }

    /// 对齐安卓 formatBasketballPeriod：OT 加时、3x3 常规阶段无节次文案。
    private var basketballPeriodText: String {
        let isOT = state.sportBoolValue("basketballIsOT") == true
        if isOT { return "OT" }
        if state.gameType == "three_basketball" { return "" }
        let period = max(1, state.sportInt("basketballCurrentPeriod") ?? 1)
        return ["1st", "2nd", "3rd", "4th"][min(period, 4) - 1]
    }

    @ViewBuilder
    private var basketballClockPill: some View {
        if let anchor = basketballClockAnchor {
            let chrome = model.overlayChromeScale
            let scoreScale = model.basketballClockScoreScale.clamped(1, 2)
            let periodText = basketballPeriodText
            let digits = periodText.prefix(while: { $0.isNumber })
            let suffix = periodText.dropFirst(digits.count)
            let showGameTime = state.gameType != "three_basketball"
                || state.sportBoolValue("basketballIsOT") != true
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let nowMs = Int64(context.date.timeIntervalSince1970 * 1_000)
                let gameRemaining = projectedBasketballRemaining(
                    anchor.gameSeconds, running: anchor.gameRunning, nowMs: nowMs
                )
                let shotRemaining = projectedBasketballRemaining(
                    anchor.shotSeconds, running: anchor.shotRunning, nowMs: nowMs
                )
                let urgent = shotRemaining <= 5
                let pulse: CGFloat = (1...5).contains(shotRemaining) && anchor.shotRunning
                    ? 1 + 0.035 * CGFloat(abs(sin(Double(nowMs) / 320.0)))
                    : 1
                VStack(spacing: 10 * chrome) {
                    if anchor.clockStarted,
                       state.result?.ended != true,
                       !anchor.gameRunning,
                       gameRemaining > 0 {
                        basketballPauseBar(chrome: chrome)
                    }
                    HStack(spacing: 12 * chrome) {
                        if !periodText.isEmpty {
                            if digits.isEmpty {
                                Text(periodText)
                                    .font(scoreFont(size: 16 * scoreScale))
                                    .foregroundStyle(.white.opacity(0.86))
                            } else {
                                // 数字与单位基线对齐（安卓 alignByBaseline）。
                                HStack(alignment: .firstTextBaseline, spacing: 1 * chrome) {
                                    Text(String(digits))
                                        .font(scoreFont(size: 20 * scoreScale))
                                        .foregroundStyle(.white.opacity(0.86))
                                    Text(String(suffix))
                                        .font(scoreFont(size: 13 * chrome))
                                        .foregroundStyle(.white.opacity(0.86))
                                }
                            }
                            Text("|")
                                .font(scoreFont(size: 16 * chrome))
                                .foregroundStyle(.white.opacity(0.32))
                        }
                        if showGameTime {
                            Text(String(format: "%02d:%02d", gameRemaining / 60, gameRemaining % 60))
                                .font(scoreFont(size: 21 * scoreScale))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            Text("|")
                                .font(scoreFont(size: 16 * chrome))
                                .foregroundStyle(.white.opacity(0.32))
                        }
                        Text(String(format: "%02d", max(0, shotRemaining)))
                            .font(scoreFont(size: 21 * scoreScale))
                            .foregroundStyle(
                                urgent
                                    ? Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
                                    : Color(red: 0xFD / 255, green: 0xE0 / 255, blue: 0x47 / 255)
                            )
                            .scaleEffect(pulse)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 18 * chrome)
                    .padding(.vertical, 10 * chrome)
                    .background(
                        Color(red: 0x0A / 255, green: 0x0C / 255, blue: 0x12 / 255).opacity(0.82),
                        in: RoundedRectangle(cornerRadius: 24 * chrome, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24 * chrome, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, model.floatingEdgeInset)
            }
        }
    }

    /// 暂停提示条：已开赛且时钟停走时显示在时间条上方（对齐安卓 BasketballPauseBar）。
    private func basketballPauseBar(chrome: CGFloat) -> some View {
        HStack(spacing: 7 * chrome) {
            HStack(spacing: 3 * chrome) {
                RoundedRectangle(cornerRadius: 1.5 * chrome)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 3.5 * chrome, height: 13 * chrome)
                RoundedRectangle(cornerRadius: 1.5 * chrome)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 3.5 * chrome, height: 13 * chrome)
            }
            Text(NSLocalizedString("display_basketball_clock_pause", value: "暂停", comment: ""))
                .font(scoreFont(size: 16 * chrome))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14 * chrome)
        .frame(height: 32 * chrome)
        .background(
            Color(red: 0xDA / 255, green: 0x2D / 255, blue: 0x20 / 255).opacity(0.92),
            in: RoundedRectangle(cornerRadius: 16 * chrome, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16 * chrome, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        )
    }

    private func panel(side: DisplayTwoSideSideModel, isLeft: Bool) -> some View {
        let edgeInset = model.panelEdgeInset
        let edge = EdgeInsets(
            top: model.contentTopInset,
            leading: isLeft ? edgeInset : 0,
            bottom: model.contentBottomInset,
            trailing: isLeft ? 0 : edgeInset
        )
        return Group {
            if model.statMode == .tennis {
                tennisPanel(side: side, isLeft: isLeft)
            } else {
                standardPanel(side: side)
            }
        }
        .padding(edge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: side.panelHex))
    }

    /// 常规面板：名称 → 主分 → 次级信息 → 局分 pill（对齐安卓 TwoSidePanel 非 TENNIS 分支）。
    private func standardPanel(side: DisplayTwoSideSideModel) -> some View {
        VStack(spacing: 0) {
            Text(side.name)
                .font(.system(size: model.nameFontSize, weight: .bold))
                .lineSpacing(max(0, model.nameFontSize * 1.2 - model.nameFontSize))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: side.textHex))
                .lineLimit(model.nameMaxLines)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, max(model.nameHorizontalPadding, 16))
            Spacer(minLength: model.nameScoreGap)
            Text(side.scoreText)
                .font(scoreFont(size: model.scoreFontSize))
                .foregroundStyle(Color(hex: side.mainHex))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
            if side.showSecondary {
                if model.mainScoreSecondaryGap > 0 {
                    Spacer(minLength: model.mainScoreSecondaryGap)
                }
                Text(side.secondaryText.isEmpty ? "0" : side.secondaryText)
                    .font(scoreFont(size: snookerSecondaryFontSize))
                    .foregroundStyle(
                        side.secondaryText.isEmpty ? Color.clear : Color(hex: side.secondaryHex).opacity(0.9)
                    )
                    .lineLimit(1)
            }
            if side.showSets {
                Spacer(minLength: (model.setsFontSize * 0.24).clamped(8, 20))
                Text(side.setsText)
                    .font(scoreFont(size: model.setsFontSize))
                    .foregroundStyle(Color(hex: side.secondaryHex).opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, max(0, 16 - model.panelEdgeInset) + model.panelEdgeInset * 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 网球系面板：名称置顶，主分与局分/盘分同行（对齐安卓 TennisSideContent）。
    private func tennisPanel(side: DisplayTwoSideSideModel, isLeft: Bool) -> some View {
        let chrome = DisplayTypographyResolver.chromeScaleDefault
        let nameTopPadding = max(model.panelTopPadding, 18 * chrome)
        let showMeta = side.showGames || side.showSets
        let gamesWidth = (model.gamesFontSize * 1.16).clamped(56, 180)
        let columnWidth = max(gamesWidth, side.showSets ? model.tennisSetScoreBoxSize : 0)
        return ZStack {
            Text(side.name)
                .font(.system(size: model.nameFontSize, weight: .bold))
                .foregroundStyle(Color(hex: side.textHex))
                .lineLimit(model.nameMaxLines)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, nameTopPadding)
            HStack(spacing: 0) {
                if isLeft {
                    tennisMainScore(side: side)
                    if showMeta {
                        Spacer(minLength: model.tennisContentGap)
                        tennisStatsColumn(side: side, columnWidth: columnWidth)
                    }
                } else {
                    if showMeta {
                        tennisStatsColumn(side: side, columnWidth: columnWidth)
                        Spacer(minLength: model.tennisContentGap)
                    }
                    tennisMainScore(side: side)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if side.showSecondary {
                Text(side.secondaryText)
                    .font(scoreFont(size: model.labelStatFontSize))
                    .foregroundStyle(Color(hex: side.secondaryHex).opacity(0.85))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
            }
        }
    }

    private func tennisMainScore(side: DisplayTwoSideSideModel) -> some View {
        Text(side.scoreText)
            .font(scoreFont(size: model.scoreFontSize))
            .foregroundStyle(Color(hex: side.mainHex))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: model.tennisMainScoreWidth)
    }

    private func tennisStatsColumn(side: DisplayTwoSideSideModel, columnWidth: CGFloat) -> some View {
        VStack(spacing: (model.gamesFontSize * 0.28).clamped(8, 18)) {
            if side.showGames {
                Text(side.gamesText)
                    .font(scoreFont(size: model.gamesFontSize))
                    .foregroundStyle(Color(hex: side.secondaryHex).opacity(0.85))
                    .lineLimit(1)
            }
            if side.showSets {
                Text(side.setsText)
                    .font(scoreFont(size: model.tennisSetsFontSize))
                    .foregroundStyle(Color(hex: side.secondaryHex).opacity(0.85))
                    .lineLimit(1)
                    .frame(
                        width: model.tennisSetScoreBoxSize,
                        height: model.tennisSetScoreBoxSize
                    )
                    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: model.tennisSetScoreBoxSize >= 88 ? 14 : 10))
            }
        }
        .frame(width: columnWidth)
    }

    /// 斯诺克单杆字号（对齐安卓 snookerBreakFontSize）。
    private var snookerSecondaryFontSize: CGFloat {
        let baseCap: CGFloat = model.scoreFontSize >= 220 ? 48 : 42
        let enlarged = min(model.labelStatFontSize * 1.32, baseCap)
        return max(enlarged, model.setsFontSize)
    }

    private var serverIndicator: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .trailing) {
                    if model.serverShowLeft {
                        ServingTriangle(pointLeft: true)
                            .frame(width: model.arrowSize, height: model.arrowSize)
                    }
                }
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    if model.serverShowRight {
                        ServingTriangle(pointLeft: false)
                            .frame(width: model.arrowSize, height: model.arrowSize)
                    }
                }
        }
    }

    @ViewBuilder
    private var keyPointBadge: some View {
        if let keyPoint = state.keyPoint, state.result?.ended != true {
            let isLeft = keyPoint.side == "left"
            VStack {
                Spacer()
                Text(keyPointTitle(keyPoint.kind))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.52), in: Capsule())
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, alignment: isLeft ? .leading : .trailing)
            .padding(.horizontal, 24)
            .allowsHitTesting(false)
        }
    }

    private func keyPointTitle(_ kind: String) -> String {
        switch kind {
        case "game": NSLocalizedString("key_point_game", value: "局点", comment: "")
        case "set": NSLocalizedString("key_point_set", value: "盘点", comment: "")
        case "match": NSLocalizedString("key_point_match", value: "赛点", comment: "")
        default: kind
        }
    }

    private func scoreFont(size: CGFloat) -> Font {
        (ScoreboardFont(rawValue: state.appearance.fontCode) ?? .default)
            .swiftUIFont(size: size, weight: .bold)
    }
}

private extension DisplayTwoSideRenderModel {
    /// 发球指示（对齐安卓 buildTwoSideServerIndicator）。
    func applyingServerIndicator(state: ScoreboardDisplayState, gameType: String, arrowSize: CGFloat) -> DisplayTwoSideRenderModel {
        var model = self
        model.arrowSize = arrowSize
        guard displayNeedsTwoSideServerTypes.contains(gameType), state.result?.ended != true else {
            model.serverShowLeft = false
            model.serverShowRight = false
            return model
        }
        let servingSide: String? = {
            if let team = state.sportString("servingTeam") {
                let team0Side = state.sportString("team0ScreenSide") == "right" ? "right" : "left"
                switch team.lowercased() {
                case "team_0": return team0Side
                case "team_1": return team0Side == "left" ? "right" : "left"
                default: return nil
                }
            }
            if let shooter = state.sportString("archeryCurrentShooter") {
                let team0Side = state.sportString("team0ScreenSide") == "right" ? "right" : "left"
                switch shooter.lowercased() {
                case "team_0": return team0Side
                case "team_1": return team0Side == "left" ? "right" : "left"
                default: return nil
                }
            }
            if let banker = state.sportString("guandanBankerTeam") ?? state.sportString("shengjiBankerTeam") {
                let team0Side = state.sportString("team0ScreenSide") == "right" ? "right" : "left"
                switch banker.lowercased() {
                case "team_0": return team0Side
                case "team_1": return team0Side == "left" ? "right" : "left"
                default: return nil
                }
            }
            // iOS 分享端直接给屏幕侧。
            return state.sportString("servingSide")
        }()
        model.serverShowLeft = servingSide == "left"
        model.serverShowRight = servingSide == "right"
        return model
    }
}

private extension DisplayTypographyResolver {
    /// 网球面板内部使用 chrome=1 的兜底常量（同步显示端恒为 1）。
    static var chromeScaleDefault: CGFloat { 1 }
}

/// 发球三角（对齐安卓 ServingTriangle：#30D158）。
private struct ServingTriangle: View {
    var pointLeft: Bool

    var body: some View {
        Canvas { context, size in
            var path = Path()
            if pointLeft {
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
            } else {
                path.move(to: CGPoint(x: size.width, y: size.height / 2))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size.height))
            }
            path.closeSubpath()
            context.fill(path, with: .color(Color(hex: "30D158")))
        }
    }
}

// MARK: - doubles 渲染模型与视图（对齐安卓 DisplayDoublesCourtSurface + Rally/TennisDoublesScoreboardBody）

private struct DisplayDoublesSideRenderModel {
    var topName: String
    var bottomName: String
    var scoreText: String
    var setsText: String
    var gamesText: String
    var showSets: Bool
    var showGames: Bool
    var panelHex: String
    var textHex: String
    /// 主分文字色（逐元素，默认回滚 textHex）。
    var mainHex: String
    /// 盘/局分文字色（逐元素，默认回滚 textHex）。
    var secondaryHex: String
}

private struct DisplayDoublesRenderModel {
    var left: DisplayDoublesSideRenderModel
    var right: DisplayDoublesSideRenderModel
    var useTennisLayout: Bool
    var serverVisible: Bool
    var serverPointLeft: Bool
    var serverTopRow: Bool
    var scoreFontSize: CGFloat
    var scoreLineHeight: CGFloat
    var nameFontSize: CGFloat
    var nameLineHeight: CGFloat
    var gamesFontSize: CGFloat
    var setsFontSize: CGFloat
    var arrowSize: CGFloat
    var nameMaxLines: Int
    var nameHorizontalPadding: CGFloat
    var nameCenterGutter: CGFloat
    var mainSecondarySpacing: CGFloat
    var isTablet: Bool

    /// 发球三角纵向偏移比例（serveIndicatorOffsetFraction）。
    var serveIndicatorOffsetFraction: CGFloat {
        let nameRowWeight: CGFloat = useTennisLayout ? (isTablet ? 0.72 : 0.70) : (isTablet ? 0.72 : 1)
        let scoreSpacerWeight: CGFloat = useTennisLayout ? (isTablet ? 1.72 : 1.80) : (isTablet ? 1.56 : 1)
        return (nameRowWeight + scoreSpacerWeight) / (2 * (2 * nameRowWeight + scoreSpacerWeight))
    }
}

private struct DisplayDoublesCourtSurface: View {
    let state: ScoreboardDisplayState
    let model: DisplayDoublesRenderModel
    let projection: ScoreboardExternalProjection

    var body: some View {
        GeometryReader { proxy in
            let scoreGap: CGFloat = model.isTablet ? 18 : 12
            let nameRowWeight: CGFloat = model.useTennisLayout ? (model.isTablet ? 0.72 : 0.70) : (model.isTablet ? 0.72 : 1)
            let scoreSpacerWeight: CGFloat = model.useTennisLayout ? (model.isTablet ? 1.72 : 1.80) : (model.isTablet ? 1.56 : 1)
            ZStack {
                // 背景双面板。
                HStack(spacing: 0) {
                    Color(hex: model.left.panelHex)
                    Color(hex: model.right.panelHex)
                }
                // 上下名称行 + 中部留白。
                VStack(spacing: 0) {
                    nameRow(
                        leftName: model.left.topName,
                        leftTextHex: model.left.textHex,
                        rightName: model.right.topName,
                        rightTextHex: model.right.textHex
                    )
                        .frame(height: proxy.size.height * nameRowWeight / (nameRowWeight * 2 + scoreSpacerWeight))
                        .padding(.horizontal, 8)
                        .padding(.vertical, scoreGap)
                    Color.clear
                        .frame(height: proxy.size.height * scoreSpacerWeight / (nameRowWeight * 2 + scoreSpacerWeight))
                    nameRow(
                        leftName: model.left.bottomName,
                        leftTextHex: model.left.textHex,
                        rightName: model.right.bottomName,
                        rightTextHex: model.right.textHex
                    )
                        .frame(height: proxy.size.height * nameRowWeight / (nameRowWeight * 2 + scoreSpacerWeight))
                        .padding(.horizontal, 8)
                        .padding(.vertical, scoreGap)
                }
                // 中部比分浮层（60% 高度）。
                HStack(spacing: 0) {
                    scoreCluster(side: model.left, isLeft: true)
                    scoreCluster(side: model.right, isLeft: false)
                }
                .frame(height: proxy.size.height * 0.60)
                .frame(maxWidth: .infinity)
                // 发球指示三角。
                serverIndicator(proxy: proxy)
                keyPointBadge
            }
        }
    }

    private func nameRow(
        leftName: String,
        leftTextHex: String,
        rightName: String,
        rightTextHex: String
    ) -> some View {
        HStack(spacing: 0) {
            doublesPlayerName(leftName, textHex: leftTextHex)
                .padding(.trailing, model.nameCenterGutter)
            doublesPlayerName(rightName, textHex: rightTextHex)
                .padding(.leading, model.nameCenterGutter)
        }
    }

    private func doublesPlayerName(_ name: String, textHex: String) -> some View {
        Text(name)
                .font(.system(size: model.nameFontSize, weight: .bold))
                .foregroundStyle(Color(hex: textHex))
                .lineLimit(model.nameMaxLines)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
    }

    /// 比分簇（对齐安卓 DoublesRallyScoreCluster / DoublesTennisScoreCluster）。
    @ViewBuilder
    private func scoreCluster(side: DisplayDoublesSideRenderModel, isLeft: Bool) -> some View {
        Group {
            if model.useTennisLayout {
                tennisCluster(side: side, isLeft: isLeft)
            } else {
                rallyCluster(side: side, isLeft: isLeft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private func rallyCluster(side: DisplayDoublesSideRenderModel, isLeft: Bool) -> some View {
        let main = Text(side.scoreText)
            .font(scoreFont(size: model.scoreFontSize))
            .foregroundStyle(Color(hex: side.mainHex))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
        let sets = Text(side.showSets ? side.setsText : "")
            .font(scoreFont(size: model.setsFontSize))
            .foregroundStyle(Color(hex: side.secondaryHex).opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
        return Group {
            if side.showSets {
                HStack(spacing: model.mainSecondarySpacing) {
                    if isLeft { main } else { sets }
                    if isLeft { sets } else { main }
                }
            } else {
                main
            }
        }
    }

    private func tennisCluster(side: DisplayDoublesSideRenderModel, isLeft: Bool) -> some View {
        let centerGap: CGFloat = model.isTablet ? 56 : 42
        let innerGroupWidth: CGFloat = model.isTablet ? 160 : 112
        let verticalGap: CGFloat = model.isTablet ? 40 : 8
        let boxSize = max(model.setsFontSize * (model.isTablet ? 1.40 : 1.70), model.isTablet ? 88 : 60)
        let stats = VStack(spacing: verticalGap) {
            Text(side.gamesText)
                .font(scoreFont(size: model.gamesFontSize))
                .foregroundStyle(Color(hex: side.secondaryHex).opacity(0.85))
                .lineLimit(1)
            if side.showSets {
                Text(side.setsText)
                    .font(scoreFont(size: model.setsFontSize))
                    .foregroundStyle(Color(hex: side.secondaryHex).opacity(0.85))
                    .lineLimit(1)
                    .frame(width: boxSize, height: boxSize)
                    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: model.isTablet ? 14 : 10))
            }
        }
        .frame(width: innerGroupWidth)
        let main = Text(side.scoreText)
            .font(scoreFont(size: model.scoreFontSize))
            .foregroundStyle(Color(hex: side.mainHex))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .frame(maxWidth: .infinity)
        return HStack(spacing: 0) {
            if isLeft {
                main
                Spacer(minLength: model.mainSecondarySpacing)
                stats
                Spacer(minLength: centerGap)
            } else {
                Spacer(minLength: centerGap)
                stats
                Spacer(minLength: model.mainSecondarySpacing)
                main
            }
        }
    }

    private func serverIndicator(proxy: GeometryProxy) -> some View {
        let triangleSize = model.arrowSize
        let xOffset: CGFloat = model.serverPointLeft ? -triangleSize / 2 : triangleSize / 2
        let yOffset = proxy.size.height * model.serveIndicatorOffsetFraction * (model.serverTopRow ? -1 : 1)
        return Group {
            if model.serverVisible {
                ServingTriangle(pointLeft: model.serverPointLeft)
                    .frame(width: triangleSize, height: triangleSize)
                    .offset(x: xOffset, y: yOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var keyPointBadge: some View {
        if let keyPoint = state.keyPoint, state.result?.ended != true {
            let leftVisible = keyPoint.side == "left"
            let rightVisible = keyPoint.side == "right"
            HStack(spacing: 0) {
                if leftVisible {
                    badge(kind: keyPoint.kind)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
                if rightVisible {
                    badge(kind: keyPoint.kind)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func badge(kind: String) -> some View {
        Text(keyPointTitle(kind))
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.52), in: Capsule())
    }

    private func keyPointTitle(_ kind: String) -> String {
        switch kind {
        case "game": NSLocalizedString("key_point_game", value: "局点", comment: "")
        case "set": NSLocalizedString("key_point_set", value: "盘点", comment: "")
        case "match": NSLocalizedString("key_point_match", value: "赛点", comment: "")
        default: kind
        }
    }

    private func scoreFont(size: CGFloat) -> Font {
        (ScoreboardFont(rawValue: state.appearance.fontCode) ?? .default)
            .swiftUIFont(size: size, weight: .bold)
    }
}

// MARK: - multi_grid（对齐安卓 MultiGridSurface）；card_two_seat / training_counter 仍走 legacy

/// 对齐安卓 DisplayMultiGridSurface + MultiGridTile：
/// 固定深底 #111827、无幻影标题带、seamless 网格无间距/外边距、
/// winner 3pt #FBBF24 描边 + 左上 ★、斗地主 name 置顶其余居中、字号按安卓 band 比例派生。
private struct DisplayMultiGridSurface: View {
    let state: ScoreboardDisplayState
    let viewport: CGSize
    let cardStyle: Bool

    var body: some View {
        let players = LegacyExternalLayouts.resolvedPlayers(state)
        let requestedColumns = state.sportInt("multiGridColumns")
        let columns = max(1, requestedColumns ?? (cardStyle ? 3 : (players.count <= 4 ? 2 : 3)))
        let rows = max(1, Int(ceil(Double(players.count) / Double(columns))))
        let seamless = Self.isSeamless(gameType: state.gameType, count: players.count)
        let gap: CGFloat = seamless ? 0 : 4
        let outer: CGFloat = seamless ? 0 : 4
        let cellWidth = max(1, (viewport.width - outer * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns))
        let cellHeight = max(1, (viewport.height - outer * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows))
        let scoreBand = max(8, cellHeight * 0.50)
        let nameBand = max(8, cellHeight * 0.30)
        let scoreFont = max(40, min(scoreBand * 0.88 / 1.02, cellWidth * 0.58))
        let nameFont = min(max(22, nameBand * 0.483), 42 * 1.16)
        let winnerID = (state.result?.ended ?? false) ? state.result?.winnerID : nil
        let manualEnd = state.result?.manualEnd ?? false

        return ZStack {
            Color(hex: "111827")
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { col in
                            let index = row * columns + col
                            Group {
                                if index < players.count {
                                    let player = players[index]
                                    let slot = LegacyExternalLayouts.colorSlot(index: index, state: state)
                                    Self.GridTile(
                                        name: player.name,
                                        score: player.score ?? 0,
                                        nameOnTop: cardStyle,
                                        nameFont: nameFont,
                                        scoreFont: scoreFont,
                                        panelColor: Color(hex: player.color ?? slot.panel),
                                        textColor: Color(hex: slot.text),
                                        isWinner: !manualEnd && winnerID != nil && winnerID == player.id
                                    )
                                } else {
                                    Self.GridTile(
                                        name: "",
                                        score: 0,
                                        nameOnTop: cardStyle,
                                        nameFont: nameFont,
                                        scoreFont: scoreFont,
                                        panelColor: Color(hex: "1F2937"),
                                        textColor: .white.opacity(0.6),
                                        placeholder: true,
                                        isWinner: false
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(outer)
        }
    }

    private static func isSeamless(gameType: String?, count: Int) -> Bool {
        switch gameType {
        case "multi_scoreboard", "uno", "doudizhu": return true
        case "nine_ball": return count >= 3 && count <= 4
        default: return false
        }
    }

    private struct GridTile: View {
        let name: String
        let score: Int
        let nameOnTop: Bool
        let nameFont: CGFloat
        let scoreFont: CGFloat
        let panelColor: Color
        let textColor: Color
        var placeholder = false
        var isWinner = false

        var body: some View {
            ZStack {
                panelColor
                if isWinner {
                    RoundedRectangle(cornerRadius: 0).strokeBorder(Color(hex: "FBBF24"), lineWidth: 3)
                }
                if placeholder {
                    Text("—")
                        .font(.system(size: scoreFont * 0.7, weight: .bold))
                        .foregroundStyle(textColor)
                } else if nameOnTop {
                    Text(name)
                        .font(.system(size: nameFont, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .padding(.top, max(14, nameFont * 0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Text("\(score)")
                        .font(.system(size: scoreFont, weight: .bold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 12) {
                        Text(name)
                            .font(.system(size: nameFont, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                        Text("\(score)")
                            .font(.system(size: scoreFont, weight: .bold))
                            .foregroundStyle(textColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                    }
                }
                if isWinner {
                    Text("★")
                        .font(.system(size: max(scoreFont * 0.28, 18), weight: .bold))
                        .foregroundStyle(Color(hex: "FBBF24"))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .clipped()
        }
    }
}

private struct DisplayTwoSeatSurface: View {
    let state: ScoreboardDisplayState

    var body: some View {
        LegacyExternalLayouts.twoSeat(state: state)
    }
}

private struct DisplayTrainingCounterSurface: View {
    let state: ScoreboardDisplayState

    var body: some View {
        LegacyExternalLayouts.training(state: state)
    }
}

/// 旧版座次（棋类）/训练计数布局（未按安卓重写的遗留实现）。
private enum LegacyExternalLayouts {
    static func twoSeat(state: ScoreboardDisplayState) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { index in
                let team = state.teams.indices.contains(index)
                    ? state.teams[index]
                    : ScoreboardDisplayTeam(id: "seat_\(index)", name: "", score: 0, order: index)
                let isLeft = index == 0
                VStack(spacing: 18) {
                    Text(team.name)
                        .font(font(state, size: 42, weight: .semibold))
                        .lineLimit(1)
                    Text(state.sportString(isLeft ? "leftClock" : "rightClock") ?? state.displayScore(forVisualIndex: index))
                        .font(font(state, size: 112))
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                    if state.sportString("activeSide") == (isLeft ? "left" : "right") {
                        Label(NSLocalizedString("cast_active_player", value: "计时中", comment: ""), systemImage: "play.fill")
                            .font(font(state, size: 30, weight: .semibold))
                    }
                }
                .foregroundStyle(Color(hex: isLeft ? state.appearance.leftTextHex : state.appearance.rightTextHex))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: isLeft ? state.appearance.leftPanelHex : state.appearance.rightPanelHex))
            }
        }
    }

    static func training(state: ScoreboardDisplayState) -> some View {
        VStack(spacing: 18) {
            Text(state.teams.first?.name ?? state.matchTitle ?? "")
                .font(font(state, size: 42, weight: .semibold))
            Text(state.displayScore(forVisualIndex: 0))
                .font(font(state, size: 210 * 1.15))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
        }
        .foregroundStyle(Color(hex: state.appearance.centerTextHex))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: state.appearance.centerPanelHex))
    }

    fileprivate static func resolvedPlayers(_ state: ScoreboardDisplayState) -> [ScoreboardDisplayPlayer] {
        if let players = state.players, !players.isEmpty { return players.sorted { $0.order < $1.order } }
        return state.teams.map {
            ScoreboardDisplayPlayer(id: $0.id, name: $0.name, score: $0.score, order: $0.order, color: $0.color)
        }
    }

    fileprivate static func colorSlot(index: Int, state: ScoreboardDisplayState) -> (panel: String, text: String) {
        switch index % 3 {
        case 0: (state.appearance.leftPanelHex, state.appearance.leftTextHex)
        case 1: (state.appearance.centerPanelHex, state.appearance.centerTextHex)
        default: (state.appearance.rightPanelHex, state.appearance.rightTextHex)
        }
    }

    private static func font(_ state: ScoreboardDisplayState, size: CGFloat, weight: Font.Weight = .bold) -> Font {
        (ScoreboardFont(rawValue: state.appearance.fontCode) ?? .default)
            .swiftUIFont(size: size, weight: weight)
    }
}

// MARK: - 计时 / 休息遮罩

/// 对齐安卓 MatchTimeDisplay：黑 32% 圆角卡（8*scale 圆角、14/6 内边距）；
/// 足球显示阶段徽章 + 主时间 + 补时，其余项目仅显示累计时间。
private struct ScoreboardExternalClockView: View {
    let clock: ScoreboardDisplayClock
    let fontCode: String
    let timeScale: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let projectedMs = clock.projectedMilliseconds(
                atWallClockMilliseconds: Int64(context.date.timeIntervalSince1970 * 1_000)
            )
            let football = footballPresentation(projectedMs: projectedMs)
            VStack(spacing: 2 * timeScale) {
                if let football {
                    HStack(spacing: 10 * timeScale) {
                        Text(stageLabel(football.half))
                            .font(font(size: 13 * timeScale, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8 * timeScale)
                            .padding(.vertical, 2 * timeScale)
                            .background(
                                stageColor(football.half),
                                in: RoundedRectangle(cornerRadius: 6 * timeScale)
                            )
                        Text(formatMilliseconds(football.mainElapsedMs))
                            .font(font(size: 22 * timeScale))
                        if football.injuryElapsedMs > 0 {
                            Text("+\(formatMilliseconds(football.injuryElapsedMs))")
                                .font(font(size: 16 * timeScale))
                                .foregroundStyle(Color(red: 0xFF / 255, green: 0xD1 / 255, blue: 0x66 / 255))
                        }
                    }
                } else {
                    Text(formatMilliseconds(projectedMs))
                        .font(font(size: 18 * timeScale))
                }
            }
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, 14 * timeScale)
            .padding(.vertical, 6 * timeScale)
            .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8 * timeScale))
        }
    }

    private func font(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        (ScoreboardFont(rawValue: fontCode) ?? .default).swiftUIFont(size: size, weight: weight)
    }

    /// 对齐安卓 resolveFootballClockPresentation：用数字字段投影足球阶段时钟。
    private func footballPresentation(projectedMs: Int64) -> (half: Int, mainElapsedMs: Int64, injuryElapsedMs: Int64)? {
        guard let half = clock.footballHalf, (1...4).contains(half),
              let halfLengthMs = clock.footballHalfLengthMs, halfLengthMs > 0 else {
            return nil
        }
        let injuryTargetMs = max(0, clock.footballInjuryTargetMs ?? 0)
        let totalLimitMs = halfLengthMs + injuryTargetMs
        let cappedElapsedMs = min(max(0, projectedMs), totalLimitMs)
        return (
            half: half,
            mainElapsedMs: min(cappedElapsedMs, halfLengthMs),
            injuryElapsedMs: max(0, cappedElapsedMs - halfLengthMs)
        )
    }

    /// 对齐安卓 footballStageLabel。
    private func stageLabel(_ half: Int) -> String {
        switch half {
        case 1: return "1H"
        case 2: return "2H"
        case 3: return "1T"
        default: return "2T"
        }
    }

    /// 对齐安卓 footballStageColor。
    private func stageColor(_ half: Int) -> Color {
        switch half {
        case 1: return Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
        case 2: return Color(red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255)
        case 3: return Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
        default: return Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
        }
    }

    private func formatMilliseconds(_ milliseconds: Int64) -> String {
        let total = max(0, milliseconds / 1_000)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ScoreboardExternalRestOverlay: View {
    let rest: ScoreboardDisplayRest
    let viewport: CGSize

    var body: some View {
        // 1:1 对齐安卓显示端 OfficialBreakPill（showAction=false，scale=1f）：
        // 8% 黑遮罩保持比分可见，深色圆角卡 + 绿色 mm:ss 倒计时。
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = rest.projectedRemainingSeconds(
                atWallClockMilliseconds: Int64(context.date.timeIntervalSince1970 * 1_000)
            )
            ZStack {
                Color.black.opacity(0.08).ignoresSafeArea()
                VStack(spacing: 10) {
                    Text(officialBreakTitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    Text(rest.phase == "preparation" ? "\(remaining)" : officialBreakClock(remaining))
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(red: 0x31 / 255, green: 0xD1 / 255, blue: 0x58 / 255))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Color(red: 0x0C / 255, green: 0x0C / 255, blue: 0x0E / 255).opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
            }
        }
    }

    private var officialBreakTitle: String {
        switch rest.kind {
        case "mid_game": return NSLocalizedString("official_break_mid_game", value: "局中休息", comment: "")
        case "set_break": return NSLocalizedString("official_break_set", value: "盘间休息", comment: "")
        case "changeover": return NSLocalizedString("official_break_changeover", value: "换边休息", comment: "")
        case "timeout": return NSLocalizedString("timeout", value: "暂停", comment: "")
        case "medical": return NSLocalizedString("medical_timeout", value: "医疗暂停", comment: "")
        default: return NSLocalizedString("official_break_game", value: "局间休息", comment: "")
        }
    }

    /// 对齐安卓 formatOfficialBreakClock：向上取整的 mm:ss。
    private func officialBreakClock(_ totalSeconds: Int) -> String {
        String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - sportState 布尔读取

private extension ScoreboardDisplayState {
    func sportBoolValue(_ key: String) -> Bool? {
        guard let value = sportState?[key] else { return nil }
        switch value {
        case .boolean(let value): return value
        case .string(let value): return value == "true"
        case .integer(let value): return value != 0
        default: return nil
        }
    }
}
