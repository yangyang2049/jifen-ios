import SwiftUI

enum ScoreboardExternalTemplate: String, Equatable {
    case twoSide
    case doublesCourt
    case teamCourt
    case multiGrid
    case cardTwoTeam
    case cardThreePlayer
    case cardTwoSeat
    case trainingCounter

    static func resolve(state: ScoreboardDisplayState) -> Self {
        switch state.layoutKind {
        case .twoSide: return .twoSide
        case .doublesCourt: return .doublesCourt
        case .teamCourt: return .teamCourt
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

nonisolated enum ScoreboardExternalSecondaryRowPolicy {
    static func shouldShow(
        secondaryText: String,
        gameType: String,
        eightBallHandicapRacks: Int,
        eightBallHandicapBeneficiary: String?
    ) -> Bool {
        if !secondaryText.isEmpty { return true }
        return gameType == "eight_ball"
            && eightBallHandicapRacks > 0
            && ["team1", "team2", "team_0", "team_1"].contains(eightBallHandicapBeneficiary ?? "")
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

enum DisplayServeIndicatorSizing {
    static func singles(baseSize: CGFloat, projection: ScoreboardExternalProjection) -> CGFloat {
        guard baseSize > 0 else { return 0 }
        return projection.isLocalProjection
            ? baseSize.clamped(36, 84)
            : baseSize.clamped(36, 64)
    }

    static func doubles(
        scoreFontSize: CGFloat,
        tennisDoubles: Bool,
        projection: ScoreboardExternalProjection
    ) -> CGFloat {
        let baseSize = scoreFontSize * (tennisDoubles ? 0.26 : 0.30)
        if projection.isLocalProjection {
            return baseSize.clamped(30, 64)
        }
        return baseSize.clamped(36, 64)
    }
}

enum ScoreboardExternalResultScorePresentation {
    static func score(
        forTeamID teamID: String,
        visualIndex: Int,
        state: ScoreboardDisplayState
    ) -> String {
        let team = state.teams.first(where: { $0.id == teamID })
        let finalScore = state.result?.finalScores?[teamID]
        switch state.sportString("resultScoreLevel") {
        case "sets":
            return "\(finalScore?.sets ?? team?.sets ?? 0)"
        case "games":
            return "\(finalScore?.games ?? team?.games ?? 0)"
        default:
            // Preserve display-only tennis values such as AD when the live
            // score and authoritative final numeric value describe the same
            // level. Older payloads without the explicit level also retain
            // their established points-only rendering.
            if let finalScore, finalScore.score != team?.score {
                return "\(finalScore.score)"
            }
            return state.displayScore(forVisualIndex: visualIndex)
        }
    }
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

struct DisplayTypographyTokens {
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

enum DisplayTypographyResolver {
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

    static func secondaryScoreScale(for viewport: CGSize, gameType: String) -> CGFloat {
        // 局分属于所有双边记分板的同一层级；此前乒羽网单独锁死为 1，
        // 导致同一投屏尺寸下明显小于排球。统一沿用大屏副分缩放。
        _ = gameType
        return secondaryScoreScale(for: viewport)
    }

    /// 双打姓名缩放（extensionDoublesNameScaleForViewport）。
    static func doublesNameScale(for viewport: CGSize) -> CGFloat {
        1 + (secondaryScoreScale(for: viewport) - 1) * 0.7
    }

    /// 单打投屏姓名不能明显小于同尺寸双打姓名；在大屏上从 40pt 基线
    /// 平滑提升到约 80pt，手机横屏基线保持不变。
    static func singlesNameScale(for viewport: CGSize) -> CGFloat {
        1 + (secondaryScoreScale(for: viewport) - 1) / 3
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

    static func tennisMainScoreWidth(fontSize: CGFloat) -> CGFloat {
        ScoreboardLayoutMetrics.tennisMainScoreColumnWidth(fontSize: fontSize)
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

enum ExternalTennisScoreProjection {
    static func hidesTransientCompletedGameOrdinal(
        rawScore: Int,
        isTieBreak: Bool,
        isDeuce: Bool,
        isLocalProjection: Bool
    ) -> Bool {
        // Both the phone scoreboard and the 1:1 synchronized receiver hide the
        // reducer's one-frame completed-game ordinal. TV projection follows the
        // same display contract; the context flag remains for wire compatibility.
        _ = isLocalProjection
        return rawScore == 4 && !isTieBreak && !isDeuce
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
    "foosball", "foosball_doubles", "archery_dual", "boxing"
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
    /// 九球追分统计（对齐安卓 buildSurfaceSide.chaseStats，空 = 不渲染追分带）。
    var chaseStats: [Int]
    var setsHex: String? = nil
    var gamesHex: String? = nil
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
    /// 九球追分带高度（对齐安卓 chaseStatsBandHeight：54 * 本机投屏 UI 缩放，54~92）。
    var chaseStatsBandHeight: CGFloat
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

    var onExit: (() -> Void)? = nil

    private var template: ScoreboardExternalTemplate {
        .resolve(state: state)
    }

    var body: some View {
        GeometryReader { proxy in
            let twoSideModel = resolvedTwoSideModel(viewport: proxy.size)
            let doublesModel = template == .doublesCourt ? buildDoublesModel(viewport: proxy.size) : nil
            ZStack {
                Color(hex: state.appearance.backgroundHex)
                templateBody(viewport: proxy.size, twoSideModel: twoSideModel, doublesModel: doublesModel)

                ScoreboardExternalKeyPointBadgeLayer(
                    state: state,
                    projection: projection,
                    viewport: proxy.size,
                    doublesModel: doublesModel,
                    twoSideModel: twoSideModel
                )

                if state.gameType == "pingpong" || state.gameType == "pingpong_doubles" {
                    ScoreboardExternalTableTennisMarkerLayer(
                        state: state,
                        projection: projection,
                        keyPointVisible: state.keyPoint != nil && state.result?.ended != true
                    )
                }

                snookerMatchTitleOverlay(viewport: proxy.size)

                topChrome

                if let rest = state.rest {
                    ScoreboardExternalRestOverlay(rest: rest, viewport: proxy.size, projection: projection)
                }
                if state.result?.ended == true {
                    resultOverlay(viewport: proxy.size)
                }
            }
            .clipped()
        }
        .accessibilityIdentifier("external_display_live_\(state.layoutKind.rawValue)")
    }

    // MARK: 斯诺克比赛抬头带（对齐安卓 DisplayMatchTitle：仅斯诺克且抬头非空时渲染）

    @ViewBuilder
    private func snookerMatchTitleOverlay(viewport: CGSize) -> some View {
        let matchTitle = (state.matchTitle ?? "").trimmingCharacters(in: .whitespaces)
        if state.gameType == "snooker", !matchTitle.isEmpty {
            let chromeAll = DisplayTypographyResolver.chromeScale(for: viewport)
            let isLarge = min(viewport.width, viewport.height) >= 600 || chromeAll > 1
            let isLocal = projection.isLocalProjection
            let multiplier = CGFloat(state.appearance.fontSizeMultipliers?["matchTitle"] ?? 1)
            let maximumSize: CGFloat = isLocal
                ? (isLarge ? 36 : 32)
                : ((isLarge ? 24 : 18) * chromeAll * multiplier)
                    .clamped((isLarge ? 14 : 12) * chromeAll, 54)
            let minimumSize: CGFloat = isLocal
                ? (isLarge ? 24 : 22)
                : (isLarge ? 14 : 12) * chromeAll
            let bandHeight: CGFloat = isLocal
                ? (isLarge ? 64 : 52) * chromeAll
                : (isLarge ? 64 : 56) * chromeAll
            Text(matchTitle)
                .font(displayFont(size: maximumSize, weight: .medium))
                .minimumScaleFactor(minimumSize / max(maximumSize, 1))
                .lineLimit(1)
                .foregroundStyle(Color(hex: state.appearance.style?.renderColor("matchTitle", slot: "side_center") ?? state.appearance.style?.renderColor("matchTitle", slot: "side_left") ?? "#FFFFFF"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(height: bandHeight)
                .padding(.horizontal, (isLarge ? 64 : 32) * chromeAll)
        }
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
    private func templateBody(
        viewport: CGSize,
        twoSideModel: DisplayTwoSideRenderModel?,
        doublesModel: DisplayDoublesRenderModel?
    ) -> some View {
        // 对齐安卓 DisplaySurfaceHost：CARD_TWO_SEAT / TRAINING_COUNTER 均复用 TwoSideSurface。
        switch template {
        case .twoSide, .cardTwoTeam, .cardTwoSeat, .trainingCounter:
            if let twoSideModel {
                DisplayTwoSideSurface(state: state, model: twoSideModel, projection: projection)
            }
        case .doublesCourt:
            if let doublesModel {
                DisplayDoublesCourtSurface(state: state, model: doublesModel, projection: projection)
            }
        case .teamCourt:
            teamCourtSurface(viewport: viewport)
        case .multiGrid:
            DisplayMultiGridSurface(state: state, viewport: viewport, cardStyle: false, projection: projection)
        case .cardThreePlayer:
            DisplayMultiGridSurface(state: state, viewport: viewport, cardStyle: true, projection: projection)
        }
    }

    private func resolvedTwoSideModel(viewport: CGSize) -> DisplayTwoSideRenderModel? {
        switch template {
        case .twoSide, .cardTwoTeam, .cardTwoSeat, .trainingCounter:
            buildTwoSideModel(viewport: viewport)
        default:
            nil
        }
    }

    /// The wire roster is team_0 A/B/C followed by team_1 A/B/C.
    private func teamCourtSurface(viewport: CGSize) -> some View {
        let roster: [String] = {
            if case .strings(let names) = state.sportState?["teamCourtPlayers"] { return names }
            return []
        }()
        let multipliers = projection.isLocalProjection ? [:] : (state.appearance.fontSizeMultipliers ?? [:])
        let preference = ScoreboardTypographyPreference(
            font: ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default,
            scoreMultiplier: multipliers["mainScore"] ?? 1,
            nameMultiplier: multipliers["playerName"] ?? multipliers["teamName"] ?? 1,
            secondaryMultiplier: multipliers["setGameScore"] ?? multipliers["setScore"] ?? 1
        )
        return ZStack {
            HStack(spacing: 0) {
                ForEach(0..<2) { visualIndex in
                    let logicalIndex = logicalTeam0(isOnScreenSide: visualIndex == 0) ? 0 : 1
                    let slot = visualIndex == 0 ? "side_left" : "side_right"
                    let team = state.teams.first { $0.id == "team_\(logicalIndex)" }
                    let names = Array(roster.dropFirst(logicalIndex * 3).prefix(3))
                    let panel = visualIndex == 0 ? state.appearance.leftPanelHex : state.appearance.rightPanelHex
                    TeamCourtScoreboardPanel(
                        names: names,
                        fallbackName: team?.name ?? "",
                        scoreText: state.displayScore(forVisualIndex: visualIndex),
                        setsText: "\(team?.sets ?? 0)",
                        panelSize: CGSize(width: viewport.width / 2, height: viewport.height),
                        preference: preference,
                        panelColor: Color(hex: panel),
                        nameColor: Color(hex: state.appearance.style?.renderColor("playerName", slot: slot) ?? "#FFFFFF"),
                        scoreColor: Color(hex: state.appearance.style?.renderColor("mainScore", slot: slot) ?? "#FFFFFF"),
                        setsColor: Color(hex: state.appearance.style?.renderColor("setScore", slot: slot) ?? "#FFFFFF")
                    )
                }
            }
            if let servingSide = state.sportString("servingSide") {
                let isLeft = servingSide == "left"
                let arrowSize = projection.isLocalProjection
                    ? min(viewport.height * 0.12, viewport.width * 0.06).clamped(36, 84)
                    : ScoreboardLayoutMetrics.serveIndicatorSize(
                        halfViewportSize: CGSize(width: viewport.width / 2, height: viewport.height)
                    )
                ServingTriangle(pointLeft: isLeft, colorHex: ScoreboardDisplayStyle.renderHex(state.appearance.style?.serverIndicatorColor ?? "#30D158"))
                    .frame(width: arrowSize, height: arrowSize)
                    .offset(x: isLeft ? -arrowSize / 2 : arrowSize / 2)
                    .allowsHitTesting(false)
            }
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
            ? DisplayTypographyResolver.secondaryScoreScale(for: viewport, gameType: gameType)
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
        let minimumMultiplier: CGFloat = isTablet ? 0.7 : 0.8
        let mainMultiplier = CGFloat(multipliers?["mainScore"] ?? 1).clamped(minimumMultiplier, 1.5)
        let nameMultiplier = CGFloat(multipliers?["teamName"] ?? multipliers?["playerName"] ?? 1).clamped(minimumMultiplier, 1.5)
        let secondaryMultiplier = CGFloat(
            multipliers?["setScore"] ?? multipliers?["gameScore"] ?? multipliers?["setGameScore"] ?? 1
        ).clamped(minimumMultiplier, 1.5)

        let projectedScoreFontSize: CGFloat = {
            switch statMode {
            case .tennis: return (tokens.score * 0.78 * mainMultiplier).clamped(56, 320)
            case .label: return (tokens.score * mainMultiplier).clamped(56, 480)
            default: return (tokens.score * mainMultiplier).clamped(48, 480)
            }
        }()
        let tennisNameScale: CGFloat = statMode == .tennis ? 1.16 : 1
        let centered = displayCenteredNameTypes.contains(gameType)
        let projectedNameFontSize: CGFloat = {
            let base = centered
                ? tokens.name * 1.08
                : tokens.name
            let projectionNameScale = projection.isLocalProjection
                ? DisplayTypographyResolver.singlesNameScale(for: viewport)
                : 1
            return (
                base * tennisNameScale * nameMultiplier * chrome * syncNameScale * projectionNameScale
            ).clamped(18, 96)
        }()
        let projectedSetsFontSize = (tokens.sets * secondaryMultiplier * secondaryScale).clamped(18, 160)
        let gamesMultiplier = CGFloat(multipliers?["gameScore"] ?? Double(secondaryMultiplier)).clamped(minimumMultiplier, 1.5)
        let projectedGamesFontSize = (tokens.games * gamesMultiplier * secondaryScale).clamped(18, 160)
        let projectedTennisSetsFontSize = (tokens.tennisSets * secondaryMultiplier * secondaryScale).clamped(18, 160)
        let projectedLabelStatFontSize = (tokens.labelStat * secondaryScale).clamped(14, 96)

        // The synchronized receiver is a button-free copy of the phone
        // scoreboard. Use the same measured typography resolver and profiles;
        // basketball keeps its dedicated receiver presentation by design.
        let usesPhoneTypography = !projection.isLocalProjection
            && gameType != "basketball"
            && gameType != "three_basketball"
        let phoneTypography: ScoreboardTypographyResult? = {
            guard usesPhoneTypography else { return nil }
            let profile: ScoreboardTypographyProfile
            if isTennisFamily {
                profile = .tennis
            } else if displayNeedsSetsTypes.contains(gameType) {
                profile = .rally
            } else if ["eight_ball", "nine_ball", "snooker", "guandan", "shengji"].contains(gameType) {
                profile = .twoSide
            } else {
                profile = .standard
            }
            let preference = ScoreboardTypographyPreference(
                font: ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default,
                scoreMultiplier: state.appearance.fontSizeMultipliers?["mainScore"] ?? 1,
                nameMultiplier: state.appearance.fontSizeMultipliers?["teamName"]
                    ?? state.appearance.fontSizeMultipliers?["playerName"] ?? 1,
                secondaryMultiplier: state.appearance.fontSizeMultipliers?["setGameScore"]
                    ?? state.appearance.fontSizeMultipliers?["setScore"]
                    ?? state.appearance.fontSizeMultipliers?["gameScore"] ?? 1
            )
            let panelSize = CGSize(width: viewport.width / 2, height: viewport.height)
            func resolve(_ side: DisplayTwoSideSideModel) -> ScoreboardTypographyResult {
                let secondary = [side.secondaryText, side.gamesText, side.setsText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                return ScoreboardTypographyResolver.resolve(
                    ScoreboardTypographyLayoutContext(
                        profile: profile,
                        containerSize: panelSize,
                        nameText: side.name,
                        scoreText: side.scoreText,
                        secondaryText: secondary,
                        preference: preference,
                        horizontalPadding: 20,
                        secondaryIsInline: isTennisFamily,
                        isLargeScreen: isTablet
                    )
                )
            }
            let leftTypography = resolve(left)
            let rightTypography = resolve(right)
            return ScoreboardTypographyResult(
                nameFontSize: min(leftTypography.nameFontSize, rightTypography.nameFontSize),
                scoreFontSize: min(leftTypography.scoreFontSize, rightTypography.scoreFontSize),
                secondaryFontSize: min(leftTypography.secondaryFontSize, rightTypography.secondaryFontSize),
                nameToScoreSpacing: min(leftTypography.nameToScoreSpacing, rightTypography.nameToScoreSpacing),
                mainToSecondarySpacing: min(leftTypography.mainToSecondarySpacing, rightTypography.mainToSecondarySpacing)
            )
        }()
        let baseScoreFontSize = phoneTypography?.scoreFontSize ?? projectedScoreFontSize
        let baseNameFontSize = phoneTypography?.nameFontSize ?? projectedNameFontSize
        let baseSetsFontSize = phoneTypography?.secondaryFontSize ?? projectedSetsFontSize
        let baseGamesFontSize = phoneTypography?.secondaryFontSize ?? projectedGamesFontSize
        let baseTennisSetsFontSize = phoneTypography?.secondaryFontSize ?? projectedTennisSetsFontSize
        let baseLabelStatFontSize = phoneTypography?.secondaryFontSize ?? projectedLabelStatFontSize

        // 顶部标题带（对齐安卓 titleBandHeight：仅斯诺克且真实比赛抬头非空时预留，
        // 其余项目名一律不渲染、不预留）。
        let matchTitle = (state.matchTitle ?? "").trimmingCharacters(in: .whitespaces)
        let hasMatchTitle = !matchTitle.isEmpty
        let chromeAll = DisplayTypographyResolver.chromeScale(for: viewport)
        let titleIsLarge = isTablet || chromeAll > 1
        let titleBandHeight: CGFloat = {
            guard isSnooker, hasMatchTitle else { return 0 }
            if projection.isLocalProjection {
                return (titleIsLarge ? 64 : 52) * chromeAll
            }
            return (titleIsLarge ? 64 : 56) * chromeAll
        }()
        let hasRemoteSnookerTitle = isSnooker && !projection.isLocalProjection && hasMatchTitle
        let baseNameScoreGap: CGFloat = phoneTypography?.nameToScoreSpacing ?? (hasRemoteSnookerTitle
            ? (baseScoreFontSize * 0.12).clamped(12, 30)
            : (baseScoreFontSize * 0.24).clamped(24, 60))
        let baseMainScoreSecondaryGap: CGFloat = hasRemoteSnookerTitle ? 0 : (isSnooker ? 2 : 8)

        // 垂直预算（对齐安卓 availableHeight/verticalScale）。
        let matchTimeScale = projection.isLocalProjection
            ? (min(viewport.width, viewport.height) / 360).clamped(1.5, 2)
            : chrome
        let chromeGap = 8 * chrome

        let matchClockTopInset: CGFloat = projection.isLocalProjection
            ? titleBandHeight + 12 * chrome + 12 * (chrome - 1)
            : titleBandHeight + 12 * chromeAll
        var nextTopInset = titleBandHeight
        if state.clock?.visible == true {
            nextTopInset = matchClockTopInset + 40 * matchTimeScale + chromeGap
        }

        // 顶部信息条（对齐安卓 SportInfoBadge：篮球节次/拳击回合/斯诺克局数/黑八目标）。
        // 对齐安卓 hasRealtimeBasketballClock：篮球实时时钟存在时，节次改由底部 BasketballClockPill 承载。
        var sportInfo = buildSportInfoBadge(gameType: gameType)
        if hasRealtimeBasketballClock {
            sportInfo.text = ""
        }
        let hasSportInfo = (!sportInfo.text.isEmpty || sportInfo.segments != nil || sportInfo.targetRacks != nil)
            && !isSnooker
        let sportInfoTopInset = hasSportInfo ? max(nextTopInset, titleBandHeight + 12 * chrome) : 0
        if hasSportInfo {
            let sportInfoHeight = max(tokens.meta * secondaryScale * 1.2, 18 * chrome) + 14 * chrome
            nextTopInset = sportInfoTopInset + sportInfoHeight + chromeGap
        } else if isSnooker, sportInfo.segments != nil {
            let inlineHeight = max(tokens.meta * 1.2, 18 * chrome) + 8 * chrome
            nextTopInset = max(nextTopInset, titleBandHeight + inlineHeight)
        }

        // 篮球犯规条（对齐安卓 BasketballFoulStrip）。
        let foulStrip = buildBasketballFoulStrip(gameType: gameType, chrome: chrome, secondaryScale: secondaryScale, tokens: tokens)
        let floatingEdgeInset = 16 * chrome + 12 * (chrome - 1)
        let basketballFoulTopInset = foulStrip.visible ? max(nextTopInset, floatingEdgeInset) : 0
        if foulStrip.visible {
            let foulHeight = max(foulStrip.labelSize, foulStrip.countSize) * 1.2 + 16 * chrome
            nextTopInset = basketballFoulTopInset + foulHeight + chromeGap
        }

        // 两种显示模式均为顶部信息条预留空间，避免放大后的队名与徽标重叠。
        let modelSportInfoTopInset = sportInfoTopInset
        let modelBasketballFoulTopInset = projection.isLocalProjection ? basketballFoulTopInset : 0
        let contentTopInset = nextTopInset

        // 本机投屏时为底部浮层预留高度（对齐安卓 contentBottomInset =
        // max(九球追分带, 篮球时钟条预留)）。
        let chaseStatsBandHeight: CGFloat = {
            guard gameType == "nine_ball" else { return 0 }
            guard projection.isLocalProjection else { return 54 }
            let uiScale = (min(viewport.width, viewport.height) / 360).clamped(1.5, 2)
            return (54 * uiScale).clamped(54, 92)
        }()
        let basketballClockReserve: CGFloat = {
            guard projection.isLocalProjection, hasRealtimeBasketballClock else { return 0 }
            let c = chrome.clamped(1, 1.5)
            let s = secondaryScale.clamped(1, 2)
            let clockRow = 21 * s * 1.2 + 20 * c
            let pauseRow = 42 * c
            let edge = 16 * c + 12 * (c - 1)
            return clockRow + pauseRow + edge + 8 * c
        }()
        let contentBottomInset = projection.isLocalProjection
            ? max(chaseStatsBandHeight, basketballClockReserve)
            : 0

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
        let baseTennisGap = min(32 * chrome, viewport.width * 0.025)
        let horizontalScale: CGFloat = {
            guard statMode == .tennis else { return 1 }
            let availableWidth = max(viewport.width / 2 - 24 - min(tokens.panelEdgeInset, viewport.width * 0.02), 1)
            return resolveTennisContentScale(
                availableWidth: availableWidth,
                scoreFontSize: baseScoreFontSize,
                gamesFontSize: baseGamesFontSize,
                setsFontSize: baseTennisSetsFontSize,
                showGames: sides.contains { $0.showGames },
                showSets: sides.contains { $0.showSets },
                baseGap: baseTennisGap
            )
        }()
        let contentScale = min(verticalScale, horizontalScale)

        return DisplayTwoSideRenderModel(
            left: left,
            right: right,
            statMode: statMode,
            scoreFontSize: baseScoreFontSize * contentScale,
            nameFontSize: baseNameFontSize * verticalScale,
            setsFontSize: baseSetsFontSize * contentScale,
            gamesFontSize: baseGamesFontSize * contentScale,
            tennisSetsFontSize: baseTennisSetsFontSize * contentScale,
            labelStatFontSize: baseLabelStatFontSize * contentScale,
            nameScoreGap: baseNameScoreGap * contentScale,
            mainScoreSecondaryGap: baseMainScoreSecondaryGap * contentScale,
            panelTopPadding: tokens.panelTopPadding,
            panelEdgeInset: min(tokens.panelEdgeInset, viewport.width * 0.02),
            nameMaxLines: 1,
            nameHorizontalPadding: projection.isLocalProjection ? (16 * chrome).clamped(16, 24) : 16,
            tennisContentGap: baseTennisGap * contentScale,
            tennisMainScoreWidth: DisplayTypographyResolver.tennisMainScoreWidth(
                fontSize: baseScoreFontSize * contentScale
            ),
            tennisSetScoreBoxSize: DisplayTypographyResolver.tennisSetScoreBoxSize(
                fontSize: baseTennisSetsFontSize * contentScale
            ),
            serverShowLeft: false,
            serverShowRight: false,
            arrowSize: 0,
            titleBandHeight: titleBandHeight,
            contentTopInset: contentTopInset,
            contentBottomInset: contentBottomInset,
            overlaySecondaryFontSize: tokens.meta * secondaryScale,
            overlayChromeScale: chrome.clamped(1, 1.5),
            floatingEdgeInset: floatingEdgeInset,
            sportInfoTopInset: modelSportInfoTopInset,
            sportInfoText: sportInfo.text,
            sportInfoSegments: sportInfo.segments,
            sportInfoTargetRacks: sportInfo.targetRacks,
            basketballFoulVisible: foulStrip.visible,
            basketballFoulLeftText: foulStrip.leftText,
            basketballFoulRightText: foulStrip.rightText,
            basketballFoulLabelSize: foulStrip.labelSize,
            basketballFoulCountSize: foulStrip.countSize,
            basketballFoulTopInset: modelBasketballFoulTopInset,
            basketballClockVisible: hasRealtimeBasketballClock,
            basketballClockScoreScale: secondaryScale,
            chaseStatsBandHeight: chaseStatsBandHeight
        ).applyingServerIndicator(
            state: state,
            gameType: gameType,
            arrowSize: projection.isLocalProjection
                ? DisplayServeIndicatorSizing.singles(
                    baseSize: baseScoreFontSize * contentScale * 0.30,
                    projection: projection
                )
                : ScoreboardLayoutMetrics.serveIndicatorSize(
                    halfViewportSize: CGSize(width: viewport.width / 2, height: viewport.height)
                )
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
        baseGap: CGFloat
    ) -> CGFloat {
        func groupWidth(_ scale: CGFloat) -> CGFloat {
            let mainWidth = DisplayTypographyResolver.tennisMainScoreWidth(
                fontSize: scoreFontSize * scale
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
        let slot = state.appearance.style?.slot(for: team?.id, fallback: isLeft ? "side_left" : "side_right") ?? (isLeft ? "side_left" : "side_right")
        let textHex = state.appearance.style?.renderColor("teamName", slot: slot) ?? (isLeft ? state.appearance.leftTextHex : state.appearance.rightTextHex)
        let mainHex = state.appearance.style?.renderColor("mainScore", slot: slot) ?? (isLeft ? state.appearance.leftMainTextHex : state.appearance.rightMainTextHex)
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

        // 九球追分计数（对齐安卓 buildNineBallChaseStats：twoSide 用逻辑玩家索引）。
        var chaseStats: [Int] = []
        if gameType == "nine_ball" {
            chaseStats = state.displayChaseCounts(playerIndex: isLogicalTeam0 ? 0 : 1)
        }

        // 棋类计时：主分显示格式化时钟（对齐安卓 CARD_TWO_SEAT → TwoSideSurface，
        // 控制端将 mm:ss 放入 sportState.leftClock/rightClock，按屏幕侧读取）。
        let isBoardSeatGame = ["xiangqi", "go", "chess", "checkers"].contains(gameType)
        let scoreText = isBoardSeatGame
            ? (state.sportString(isLeft ? "leftClock" : "rightClock") ?? "")
            : formattedTwoSideScore(
                gameType: gameType,
                isLeft: isLeft,
                isLogicalTeam0: isLogicalTeam0,
                rawScoreText: state.displayScore(forVisualIndex: isLeft ? 0 : 1),
                rawScore: team?.score ?? 0
            )

        return DisplayTwoSideSideModel(
            name: team?.name ?? "",
            scoreText: scoreText,
            secondaryText: secondaryText,
            setsText: "\(rawSets)",
            gamesText: "\(rawGames)",
            // 黑 8 让球时，非受让侧也保留同高第三行，避免两侧主分纵向错位。
            showSecondary: ScoreboardExternalSecondaryRowPolicy.shouldShow(
                secondaryText: secondaryText,
                gameType: gameType,
                eightBallHandicapRacks: sportNumber("eightBallHandicapRacks"),
                eightBallHandicapBeneficiary: state.sportString("eightBallHandicapBeneficiary")
            ),
            showSets: showSets,
            showGames: showGames,
            panelHex: state.appearance.style?.panelColor(slot: slot) ?? team?.color ?? panelHex,
            textHex: textHex,
            mainHex: mainHex,
            secondaryHex: secondaryHex,
            chaseStats: chaseStats,
            setsHex: state.appearance.style?.renderColor("setScore", slot: slot),
            gamesHex: state.appearance.style?.renderColor("gameScore", slot: slot)
        )
    }

    /// 追分短标签（对齐安卓 chase_chalk_*：大/小/九/胜/让/犯，计数顺序 = NineBallChaseKind.allCases）。
    static func displayChaseChalkLabel(forIndex index: Int) -> String {
        let keys = [
            "chase_chalk_big",
            "chase_chalk_small",
            "chase_chalk_golden",
            "chase_chalk_normal",
            "chase_chalk_ball_in_hand",
            "chase_chalk_foul"
        ]
        guard keys.indices.contains(index) else { return "" }
        let values = ["大", "小", "九", "胜", "让", "犯"]
        return NSLocalizedString(keys[index], value: values[index], comment: "")
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
        let isTieBreak = state.sportBoolValue("tennisIsTieBreak") == true
        let isDeuce = state.sportBoolValue("tennisIsDeuce") == true
        if isTieBreak { return "\(rawScore)" }
        if gameType == "soft_tennis" {
            let opponent = opponentScore(isLeft: isLeft)
            return formatSoftTennisPoint(rawScore, opponentScore: opponent)
        }
        if isDeuce {
            if state.sportString("tennisDeuceMode") == "no_ad" { return "40" }
            let advantage = state.sportString("tennisAdvantage")
            guard let advantage, !advantage.isEmpty, advantage != "none" else { return "40" }
            let advantageScreenSide = servingScreenSide(forTeam: advantage)
            let hasAdvantage = isLeft ? advantageScreenSide == "left" : advantageScreenSide == "right"
            return hasAdvantage ? "AD" : "40"
        }
        if ExternalTennisScoreProjection.hidesTransientCompletedGameOrdinal(
            rawScore: rawScore,
            isTieBreak: isTieBreak,
            isDeuce: isDeuce,
            isLocalProjection: projection.isLocalProjection
        ) {
            // Completed games can briefly publish ordinal 4 before games/sets
            // catch up. Do not flash a false AD during that transition.
            return "0"
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
            ? DisplayTypographyResolver.secondaryScoreScale(for: viewport, gameType: gameType)
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
        let minimumMultiplier: CGFloat = min(viewport.width, viewport.height) >= 600 ? 0.7 : 0.8
        let scoreMultiplier = CGFloat(multipliers?["mainScore"] ?? 1).clamped(minimumMultiplier, 1.5)
        let nameMultiplier = CGFloat(multipliers?["playerName"] ?? multipliers?["teamName"] ?? 1).clamped(minimumMultiplier, 1.5)
        let secondaryKey = "setGameScore"
        let secondaryMultiplier = CGFloat(
            multipliers?[secondaryKey] ?? multipliers?["setScore"] ?? multipliers?["setGameScore"] ?? 1
        ).clamped(minimumMultiplier, 1.5)

        let projectedScoreFontSize = (tokens.score * scoreMultiplier).clamped(48, 360)
        let projectedNameFontSize = (tokens.name * nameMultiplier * nameScale * syncNameScale).clamped(24, 80)
        let projectedGamesFontSize = (tokens.games * secondaryMultiplier * secondaryScale).clamped(18, 160)
        let projectedSetsFontSize = (tokens.sets * secondaryMultiplier * secondaryScale).clamped(18, 160)

        let left = buildDoublesSide(isLeft: true, gameType: gameType)
        let right = buildDoublesSide(isLeft: false, gameType: gameType)
        let phoneTypography: (score: CGFloat, name: CGFloat, secondary: CGFloat)? = {
            guard !projection.isLocalProjection else { return nil }
            let preference = ScoreboardTypographyPreference(
                font: ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default,
                scoreMultiplier: state.appearance.fontSizeMultipliers?["mainScore"] ?? 1,
                nameMultiplier: state.appearance.fontSizeMultipliers?["playerName"]
                    ?? state.appearance.fontSizeMultipliers?["teamName"] ?? 1,
                secondaryMultiplier: state.appearance.fontSizeMultipliers?["setGameScore"]
                    ?? state.appearance.fontSizeMultipliers?["setScore"] ?? 1
            )
            let halfSize = CGSize(width: viewport.width / 2, height: viewport.height)
            let longestName = [left.topName, left.bottomName, right.topName, right.bottomName]
                .max(by: { $0.count < $1.count }) ?? ""
            let name = ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: tennisDoubles ? .tennis : .rally,
                    containerSize: halfSize,
                    nameText: longestName,
                    scoreText: "",
                    preference: preference,
                    horizontalPadding: 8,
                    isLargeScreen: isTablet
                )
            ).nameFontSize
            let scoreRegion = CGSize(
                width: halfSize.width,
                height: ScoreboardLayoutMetrics.doublesScoreRegionHeight(panelHeight: halfSize.height)
            )
            func resolveScore(_ side: DisplayDoublesSideRenderModel) -> ScoreboardTypographyResult {
                ScoreboardTypographyResolver.resolve(
                    ScoreboardTypographyLayoutContext(
                        profile: tennisDoubles ? .tennis : .rally,
                        containerSize: scoreRegion,
                        nameText: "",
                        scoreText: side.scoreText,
                        secondaryText: side.setsText,
                        preference: preference,
                        horizontalPadding: 8,
                        secondaryIsInline: true,
                        referenceHeight: halfSize.height,
                        isLargeScreen: isTablet
                    )
                )
            }
            let leftScore = resolveScore(left)
            let rightScore = resolveScore(right)
            return (
                min(leftScore.scoreFontSize, rightScore.scoreFontSize),
                name,
                ScoreboardLayoutMetrics.doublesSecondaryScoreFontSize(
                    regularSize: min(leftScore.secondaryFontSize, rightScore.secondaryFontSize)
                )
            )
        }()
        let scoreFontSize = phoneTypography?.score ?? projectedScoreFontSize
        let nameFontSize = phoneTypography?.name ?? projectedNameFontSize
        let gamesFontSize = phoneTypography?.secondary ?? projectedGamesFontSize
        let setsFontSize = phoneTypography?.secondary ?? projectedSetsFontSize

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
            arrowSize: projection.isLocalProjection
                ? DisplayServeIndicatorSizing.doubles(
                    scoreFontSize: scoreFontSize,
                    tennisDoubles: tennisDoubles,
                    projection: projection
                )
                : ScoreboardLayoutMetrics.serveIndicatorSize(
                    halfViewportSize: CGSize(width: viewport.width / 2, height: viewport.height)
                ),
            nameMaxLines: 1,
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

        let styleSlot = state.appearance.style?.slot(for: team?.id, fallback: isLeft ? "side_left" : "side_right") ?? (isLeft ? "side_left" : "side_right")
        let secondaryKey = "setGameScore"
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
            panelHex: state.appearance.style?.panelColor(slot: styleSlot) ?? team?.color ?? (isLeft ? state.appearance.leftPanelHex : state.appearance.rightPanelHex),
            textHex: state.appearance.style?.renderColor("playerName", slot: styleSlot) ?? (isLeft ? state.appearance.leftTextHex : state.appearance.rightTextHex),
            mainHex: state.appearance.style?.renderColor("mainScore", slot: styleSlot) ?? (isLeft ? state.appearance.leftMainTextHex : state.appearance.rightMainTextHex),
            setsHex: state.appearance.style?.renderColor(secondaryKey, slot: styleSlot),
            gamesHex: state.appearance.style?.renderColor("setGameScore", slot: styleSlot),
            secondaryHex: state.appearance.style?.renderColor(secondaryKey, slot: styleSlot)
                ?? (isLeft ? state.appearance.leftSecondaryTextHex : state.appearance.rightSecondaryTextHex)
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
        let leftTeamID = logicalTeam0(isOnScreenSide: true) ? "team_0" : "team_1"
        let rightTeamID = logicalTeam0(isOnScreenSide: false) ? "team_0" : "team_1"
        let leftTeam = state.teams.first(where: { $0.id == leftTeamID })
        let rightTeam = state.teams.first(where: { $0.id == rightTeamID })
        return VStack(spacing: 10 * chrome) {
            Text(NSLocalizedString("cast_match_finished", value: "比赛结束", comment: ""))
                .font(displayFont(size: 32 * chrome, weight: .bold))
            if let leftTeam, let rightTeam {
                HStack(spacing: 28 * chrome) {
                    resultSide(
                        name: leftTeam.name,
                        score: ScoreboardExternalResultScorePresentation.score(
                            forTeamID: leftTeamID,
                            visualIndex: 0,
                            state: state
                        ),
                        chrome: chrome
                    )
                    Text(":")
                        .font(displayFont(size: 30 * chrome, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                    resultSide(
                        name: rightTeam.name,
                        score: ScoreboardExternalResultScorePresentation.score(
                            forTeamID: rightTeamID,
                            visualIndex: 1,
                            state: state
                        ),
                        chrome: chrome
                    )
                }
                .padding(.vertical, 6 * chrome)
            }
            Text(winnerName.map {
                String(format: NSLocalizedString("cast_winner_format", value: "%@ 获胜", comment: ""), $0)
            } ?? NSLocalizedString("cast_result_draw", value: "比赛结果已确认", comment: ""))
                .font(displayFont(size: 30 * chrome, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            if let onExit {
                Button(action: onExit) {
                    Text(NSLocalizedString("display_exit", value: "退出显示", comment: ""))
                        .font(.system(size: 18 * chrome, weight: .semibold))
                        .padding(.horizontal, 24).padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("display_result_exit")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 30 * chrome * 1.6)
        .padding(.vertical, 30 * chrome)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 15 * chrome))
        .shadow(color: .black.opacity(0.4), radius: 24)
    }

    private func resultSide(name: String, score: String, chrome: CGFloat) -> some View {
        VStack(spacing: 4 * chrome) {
            Text(name)
                .font(displayFont(size: 18 * chrome, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(score)
                .font(displayFont(size: 40 * chrome, weight: .bold))
                .monospacedDigit()
        }
        .frame(minWidth: 112 * chrome)
    }

    private func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        (ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default)
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
            // 顶部信息条（对齐安卓 SportInfoBadge：篮球节次/拳击回合/斯诺克局数/黑八目标）。
            if state.gameType == "snooker" {
                snookerInlineFrameInfo
            } else {
                sportInfoBadge
            }
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
                            .font(.system(size: model.overlaySecondaryFontSize * 0.72, weight: .medium))
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
    private var snookerInlineFrameInfo: some View {
        if let segments = model.sportInfoSegments {
            HStack(spacing: 8 * model.overlayChromeScale) {
                Text(segments.leading)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(segments.center)
                    .font(.system(size: model.overlaySecondaryFontSize * 0.72, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .fixedSize()
                Text(segments.trailing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: model.overlaySecondaryFontSize, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 24 * model.overlayChromeScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, model.titleBandHeight + 4 * model.overlayChromeScale)
            .allowsHitTesting(false)
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
        .overlay(alignment: .bottom) {
            // 九球追分带（对齐安卓 ChaseStatsStrip：面板底部整宽，黑 28% 底）。
            if !side.chaseStats.isEmpty {
                DisplayChaseStatsStrip(
                    stats: side.chaseStats,
                    bandHeight: model.chaseStatsBandHeight,
                    fontCode: state.appearance.fontCode
                )
            }
        }
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
            Spacer().frame(height: model.nameScoreGap)
            Text(side.scoreText)
                .font(scoreFont(size: model.scoreFontSize))
                .foregroundStyle(Color(hex: side.mainHex))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
            if side.showSecondary {
                if model.mainScoreSecondaryGap > 0 {
                    Spacer().frame(height: model.mainScoreSecondaryGap)
                }
                secondaryScore(side: side)
            }
            if side.showSets {
                Spacer().frame(height: (model.setsFontSize * 0.24).clamped(8, 20))
                Text(side.setsText)
                    .font(scoreFont(size: model.setsFontSize))
                    .foregroundStyle(Color(hex: side.setsHex ?? side.secondaryHex))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, max(0, 16 - model.panelEdgeInset) + model.panelEdgeInset * 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func secondaryScore(side: DisplayTwoSideSideModel) -> some View {
        let content = Text(side.secondaryText.isEmpty ? "0" : side.secondaryText)
            .font(scoreFont(size: snookerSecondaryFontSize))
            .foregroundStyle(side.secondaryText.isEmpty ? Color.clear : Color(hex: side.secondaryHex))
            .lineLimit(1)
        if state.gameType == "snooker" {
            content
                .frame(minWidth: snookerSecondaryFontSize * 1.45, minHeight: snookerSecondaryFontSize * 1.15)
                .padding(.horizontal, snookerSecondaryFontSize * 0.22)
                .background(Color.black.opacity(0.34), in: Capsule())
        } else {
            content
        }
    }

    /// 网球系面板：名称置顶，主分与局分/盘分同行（对齐安卓 TennisSideContent）。
    private func tennisPanel(side: DisplayTwoSideSideModel, isLeft: Bool) -> some View {
        let chrome = model.overlayChromeScale
        let nameTopPadding = max(model.panelTopPadding, 18 * chrome)
        let showMeta = side.showGames || side.showSets
        let gamesWidth = (model.gamesFontSize * 1.16).clamped(56, 180)
        let columnWidth = max(gamesWidth, side.showSets ? model.tennisSetScoreBoxSize : 0)
        return GeometryReader { proxy in
            let statsHeight = (side.showGames ? model.gamesFontSize * 1.2 : 0)
                + (side.showSets ? model.tennisSetScoreBoxSize : 0)
                + (side.showGames && side.showSets ? (model.gamesFontSize * 0.28).clamped(8, 18) : 0)
            let centerHeight = max(model.scoreFontSize * 1.2, statsHeight)
            let nameHeight = max(1, (proxy.size.height - centerHeight) / 2 - nameTopPadding - 8 * chrome)
            let fittedNameFont = min(model.nameFontSize, max(12, nameHeight / (CGFloat(model.nameMaxLines) * 1.2)))
            ZStack {
                Text(side.name)
                    .font(.system(size: fittedNameFont, weight: .bold))
                    .foregroundStyle(Color(hex: side.textHex))
                    .lineLimit(model.nameMaxLines)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, max(model.nameHorizontalPadding, 16))
                    .frame(height: nameHeight, alignment: .top)
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
                    .foregroundStyle(Color(hex: side.secondaryHex))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
            }
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
                    .foregroundStyle(Color(hex: side.gamesHex ?? side.secondaryHex))
                    .lineLimit(1)
            }
            if side.showSets {
                Text(side.setsText)
                    .font(scoreFont(size: model.tennisSetsFontSize))
                    .foregroundStyle(Color(hex: side.setsHex ?? side.secondaryHex))
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
                        ServingTriangle(pointLeft: true, colorHex: ScoreboardDisplayStyle.renderHex(state.appearance.style?.serverIndicatorColor ?? "#30D158"))
                            .frame(width: model.arrowSize, height: model.arrowSize)
                    }
                }
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    if model.serverShowRight {
                        ServingTriangle(pointLeft: false, colorHex: ScoreboardDisplayStyle.renderHex(state.appearance.style?.serverIndicatorColor ?? "#30D158"))
                            .frame(width: model.arrowSize, height: model.arrowSize)
                    }
                }
        }
    }

    private func scoreFont(size: CGFloat) -> Font {
        (ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default)
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

/// 追分粉笔条（对齐安卓 ChaseStatsStrip：黑 28% 底、SpaceEvenly 六列、
/// 标签白 72% 10*scale、数值白 Bold 15*scale，用比分字体）。
private struct DisplayChaseStatsStrip: View {
    let stats: [Int]
    let bandHeight: CGFloat
    var fontCode: String = ""

    var body: some View {
        let scale = (bandHeight / 54).clamped(1, 2)
        return HStack(spacing: 0) {
            ForEach(stats.indices, id: \.self) { index in
                VStack(spacing: 0) {
                    Text(ScoreboardExternalLiveView.displayChaseChalkLabel(forIndex: index))
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(stats[index])")
                        .font(displayScoreFont(size: 15 * scale))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 5 * scale)
        .frame(height: bandHeight)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.28))
        .clipped()
    }

    private func displayScoreFont(size: CGFloat) -> Font {
        guard !fontCode.isEmpty, let font = ScoreboardFont(displayCode: fontCode) else {
            return .system(size: size, weight: .bold)
        }
        return font.swiftUIFont(size: size, weight: .bold)
    }
}

/// 发球三角（对齐安卓 ServingTriangle：#30D158）。
private struct ServingTriangle: View {
    var pointLeft: Bool
    var colorHex: String = "#30D158"

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
            context.fill(path, with: .color(Color(hex: colorHex)))
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
    var setsHex: String? = nil
    var gamesHex: String? = nil
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, scoreGap)
                        .frame(height: proxy.size.height * nameRowWeight / (nameRowWeight * 2 + scoreSpacerWeight))
                    Color.clear
                        .frame(height: proxy.size.height * scoreSpacerWeight / (nameRowWeight * 2 + scoreSpacerWeight))
                    nameRow(
                        leftName: model.left.bottomName,
                        leftTextHex: model.left.textHex,
                        rightName: model.right.bottomName,
                        rightTextHex: model.right.textHex
                    )
                        .padding(.horizontal, 8)
                        .padding(.vertical, scoreGap)
                        .frame(height: proxy.size.height * nameRowWeight / (nameRowWeight * 2 + scoreSpacerWeight))
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
                GeometryReader { proxy in
                    tennisCluster(side: side, isLeft: isLeft, availableWidth: proxy.size.width)
                        .frame(maxHeight: .infinity)
                }
            } else {
                GeometryReader { proxy in
                    rallyCluster(side: side, isLeft: isLeft, availableWidth: proxy.size.width)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private func rallyCluster(side: DisplayDoublesSideRenderModel, isLeft: Bool, availableWidth: CGFloat) -> some View {
        let main = Text(side.scoreText)
            .font(scoreFont(size: model.scoreFontSize))
            .foregroundStyle(Color(hex: side.mainHex))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .frame(width: side.showSets ? availableWidth * 0.65 : availableWidth)
        let sets = Text(side.showSets ? side.setsText : "")
            .font(scoreFont(size: min(model.setsFontSize, availableWidth * 0.23)))
            .foregroundStyle(Color(hex: side.secondaryHex))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .frame(width: availableWidth * 0.27)
        return Group {
            if side.showSets {
                HStack(spacing: min(model.mainSecondarySpacing, availableWidth * 0.06)) {
                    if isLeft { main } else { sets }
                    if isLeft { sets } else { main }
                }
            } else {
                main
            }
        }
    }

    private func tennisCluster(side: DisplayDoublesSideRenderModel, isLeft: Bool, availableWidth: CGFloat) -> some View {
        let centerGap = min(model.isTablet ? 56.0 : 42.0, availableWidth * 0.10)
        let innerGroupWidth = min(model.isTablet ? 160.0 : 112.0, availableWidth * 0.30)
        let verticalGap: CGFloat = model.isTablet ? 40 : 8
        let boxSize = min(innerGroupWidth, max(model.setsFontSize * (model.isTablet ? 1.40 : 1.70), model.isTablet ? 88 : 60))
        let stats = VStack(spacing: verticalGap) {
            Text(side.gamesText)
                .font(scoreFont(size: model.gamesFontSize))
                .foregroundStyle(Color(hex: side.gamesHex ?? side.secondaryHex))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
            if side.showSets {
                Text(side.setsText)
                    .font(scoreFont(size: model.setsFontSize))
                    .foregroundStyle(Color(hex: side.setsHex ?? side.secondaryHex))
                    .lineLimit(1)
                .minimumScaleFactor(0.3)
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
            .minimumScaleFactor(0.3)
            .frame(maxWidth: .infinity)
        return HStack(spacing: 0) {
            if isLeft {
                main
                Spacer(minLength: min(model.mainSecondarySpacing, availableWidth * 0.04))
                stats
                Spacer(minLength: centerGap)
            } else {
                Spacer(minLength: centerGap)
                stats
                Spacer(minLength: min(model.mainSecondarySpacing, availableWidth * 0.04))
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
                ServingTriangle(pointLeft: model.serverPointLeft, colorHex: ScoreboardDisplayStyle.renderHex(state.appearance.style?.serverIndicatorColor ?? "#30D158"))
                    .frame(width: triangleSize, height: triangleSize)
                    .offset(x: xOffset, y: yOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scoreFont(size: CGFloat) -> Font {
        (ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default)
            .swiftUIFont(size: size, weight: .bold)
    }
}

// MARK: - multi_grid（对齐安卓 MultiGridSurface）；card_two_seat / training_counter 仍走 legacy

/// 对齐安卓 DisplayMultiGridSurface + MultiGridTile：
/// 固定深底 #111827、无幻影标题带、seamless 网格无间距/外边距、
/// winner 3pt #FBBF24 描边 + 左上 ★、姓名固定顶部、主分独立居中、字号按实际格宽派生。
private struct DisplayMultiGridSurface: View {
    let state: ScoreboardDisplayState
    let viewport: CGSize
    let cardStyle: Bool
    var projection: ScoreboardExternalProjection = .localProjection

    var body: some View {
        let players = LegacyExternalLayouts.resolvedPlayers(state)
        let layoutRows = Self.layoutRows(
            state: state,
            players: players,
            cardStyle: cardStyle,
            viewport: viewport,
            projection: projection
        )
        let seamless = Self.isSeamless(gameType: state.gameType, count: players.count)
        let gap: CGFloat = seamless ? 0 : 4
        let outer: CGFloat = seamless ? 0 : 4
        let rowCount = max(1, layoutRows.count)
        let cellHeight = max(1, (viewport.height - outer * 2 - gap * CGFloat(rowCount - 1)) / CGFloat(rowCount))
        // 九球追分带高度（对齐安卓 chaseStatsBandHeight，格内容高度 = 格高 - 追分带）。
        let chaseStatsBandHeight: CGFloat = {
            guard state.gameType == "nine_ball", players.count >= 3, players.count <= 4 else { return 0 }
            guard projection.isLocalProjection else { return 54 }
            let uiScale = (min(viewport.width, viewport.height) / 360).clamped(1.5, 2)
            return (54 * uiScale).clamped(54, 92)
        }()
        let winnerID = (state.result?.ended ?? false) ? state.result?.winnerID : nil
        let manualEnd = state.result?.manualEnd ?? false
        // 同步端沿用本机单行名称；电视端保留大屏 chrome 内边距。
        let isLocal = projection.isLocalProjection
        let chrome = DisplayTypographyResolver.chromeScale(for: viewport).clamped(1, 1.5)
        let nameMaxLines = 1
        let nameHorizontalPadding: CGFloat = isLocal ? (16 * chrome).clamped(16, 24) : 12

        return ZStack {
            Color(hex: "111827")
            VStack(spacing: gap) {
                ForEach(Array(layoutRows.enumerated()), id: \.offset) { _, row in
                    let columnCount = max(1, row.count)
                    let cellWidth = max(1, (viewport.width - outer * 2 - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount))
                    HStack(spacing: gap) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, playerIndex in
                            Group {
                                if let index = playerIndex, players.indices.contains(index) {
                                    let player = players[index]
                                    let typography = resolvedTypography(
                                        player: player,
                                        cellSize: CGSize(width: cellWidth, height: cellHeight),
                                        chaseStatsBandHeight: chaseStatsBandHeight
                                    )
                                    let slot = LegacyExternalLayouts.colorSlot(index: index, state: state)
                                    let styleSlot = state.appearance.style?.panels.first(where: { $0.participantId == player.id })?.slotKey
                                        ?? (state.gameType == "doudizhu" ? ["side_left", "side_center", "side_right"][index % 3] : "player_\(index)")
                                    let panelHex = state.appearance.style?.panelColor(slot: styleSlot)
                                    let scoreHex = state.appearance.style?.renderColor("mainScore", slot: styleSlot)
                                    let nameHex = state.appearance.style?.renderColor("playerName", slot: styleSlot)
                                        ?? state.appearance.style?.renderColor("teamName", slot: styleSlot)
                                    Self.GridTile(
                                        name: player.name,
                                        score: player.score ?? 0,
                                        chaseStats: state.displayChaseCounts(playerIndex: index),
                                        chaseStatsBandHeight: chaseStatsBandHeight,
                                        fontCode: state.appearance.fontCode,
                                        nameMaxLines: nameMaxLines,
                                        nameHorizontalPadding: nameHorizontalPadding,
                                        nameFont: typography.nameFontSize,
                                        scoreFont: typography.scoreFontSize,
                                        panelColor: Color(hex: panelHex ?? player.color ?? slot.panel),
                                        textColor: Color(hex: scoreHex ?? "#FFFFFF"),
                                        nameColor: Color(hex: nameHex ?? "#FFFFFF"),
                                        isWinner: !manualEnd && winnerID != nil && winnerID == player.id
                                    )
                                } else {
                                    Self.GridTile(
                                        name: "",
                                        score: 0,
                                        chaseStats: [],
                                        chaseStatsBandHeight: chaseStatsBandHeight,
                                        fontCode: state.appearance.fontCode,
                                        nameMaxLines: nameMaxLines,
                                        nameHorizontalPadding: nameHorizontalPadding,
                                        nameFont: 24,
                                        scoreFont: 48,
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

            if state.gameType == "uno", let target = state.sportInt("unoTargetScore"), target > 0 {
                unoTargetBadge(target: target)
            }
        }
    }

    private var typographyPreference: ScoreboardTypographyPreference {
        let multipliers = state.appearance.fontSizeMultipliers ?? [:]
        return ScoreboardTypographyPreference(
            font: ScoreboardFont(displayCode: state.appearance.fontCode) ?? .default,
            scoreMultiplier: multipliers["mainScore"] ?? 1,
            nameMultiplier: multipliers["playerName"] ?? multipliers["teamName"] ?? 1,
            secondaryMultiplier: multipliers["setGameScore"] ?? multipliers["setScore"] ?? multipliers["gameScore"] ?? 1
        )
    }

    private func resolvedTypography(
        player: ScoreboardDisplayPlayer,
        cellSize: CGSize,
        chaseStatsBandHeight: CGFloat
    ) -> ScoreboardTypographyResult {
        let profile: ScoreboardTypographyProfile
        let horizontalPadding: CGFloat
        let reservedHeight: CGFloat
        let scoreBaseScale: CGFloat
        switch state.gameType {
        case "doudizhu":
            profile = .doudizhu
            horizontalPadding = 16
            reservedHeight = 32
            scoreBaseScale = 0.85
        case "nine_ball":
            profile = .nineBall
            let compact = cellSize.height < 300 || cellSize.width < 230
            horizontalPadding = compact ? 8 : 14
            reservedHeight = compact ? 48 : 58
            scoreBaseScale = 1
        case "uno":
            profile = .uno
            horizontalPadding = 12
            reservedHeight = 44
            scoreBaseScale = 1
        default:
            profile = .multi
            horizontalPadding = 12
            reservedHeight = 20
            scoreBaseScale = 1
        }
        let detail = state.gameType == "nine_ball"
            ? state.displayChaseCounts(playerIndex: player.order).map(String.init).joined(separator: " ")
            : ""
        return ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: profile,
                containerSize: cellSize,
                nameText: player.name,
                scoreText: "\(player.score ?? 0)",
                secondaryText: detail,
                preference: typographyPreference,
                horizontalPadding: horizontalPadding,
                reservedHeight: reservedHeight + chaseStatsBandHeight,
                scoreBaseScale: scoreBaseScale,
                isLargeScreen: min(viewport.width, viewport.height) >= 600
            )
        )
    }

    private func unoTargetBadge(target: Int) -> some View {
        let text = String(
            format: NSLocalizedString("uno_target_badge", value: "目标 %d", comment: ""),
            target
        )
        let size = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .uno,
                containerSize: CGSize(width: min(viewport.width * 0.5, 320), height: max(80, viewport.height * 0.22)),
                nameText: "",
                scoreText: "",
                secondaryText: text,
                preference: typographyPreference,
                horizontalPadding: 20,
                isLargeScreen: min(viewport.width, viewport.height) >= 600
            )
        ).secondaryFontSize
        return VStack {
            Spacer()
            Text(text)
                .font(typographyPreference.font.swiftUIFont(size: max(13, size * 0.45), weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .padding(.bottom, ScoreboardConstants.buttonPadding)
        }
        .allowsHitTesting(false)
    }

    private static func layoutRows(
        state: ScoreboardDisplayState,
        players: [ScoreboardDisplayPlayer],
        cardStyle: Bool,
        viewport: CGSize,
        projection: ScoreboardExternalProjection
    ) -> [[Int?]] {
        if cardStyle {
            return [Array(players.indices).map(Optional.some)]
        }
        if state.gameType == "multi_scoreboard" || state.gameType == "uno" {
            return ScoreboardPlayerGridLayout.multiRows(
                playerCount: players.count,
                // 手机横竖屏偏好不能改变电视端布局；投屏按实际宽高决定。
                usesWideLayout: projection.isLocalProjection
                    ? viewport.width >= viewport.height
                    : state.orientation == .landscape
            )
        }
        if state.gameType == "nine_ball" {
            return ScoreboardPlayerGridLayout.nineBallRows(
                playerCount: players.count,
                containerSize: viewport,
                forceWide: players.count == 2
                    ? (projection.isLocalProjection ? true : state.orientation == .landscape)
                    : nil
            ).map { $0.map(Optional.some) }
        }
        let columns = max(1, state.sportInt("multiGridColumns") ?? (players.count <= 4 ? 2 : 3))
        return stride(from: 0, to: players.count, by: columns).map { start in
            let end = min(start + columns, players.count)
            return Array(start..<end).map(Optional.some)
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
        var chaseStats: [Int] = []
        var chaseStatsBandHeight: CGFloat = 0
        var fontCode: String = ""
        var nameMaxLines: Int = 1
        var nameHorizontalPadding: CGFloat = 0
        let nameFont: CGFloat
        let scoreFont: CGFloat
        let panelColor: Color
        let textColor: Color
        var nameColor: Color = .white
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
                } else if !chaseStats.isEmpty {
                    // 九球 3-4 人：姓名与主分作为一个整体，在追分条上方居中。
                    GeometryReader { proxy in
                        let availableHeight = max(1, proxy.size.height - chaseStatsBandHeight)
                        centeredParticipantContent(availableHeight: availableHeight)
                            .frame(maxWidth: .infinity)
                            .frame(height: availableHeight)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    DisplayChaseStatsStrip(
                        stats: chaseStats,
                        bandHeight: chaseStatsBandHeight,
                        fontCode: fontCode
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else {
                    GeometryReader { proxy in
                        centeredParticipantContent(availableHeight: proxy.size.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

        private func centeredParticipantContent(availableHeight: CGFloat) -> some View {
            let requestedNameHeight = nameFont * 1.2 * CGFloat(nameMaxLines)
            let requestedGap = (nameFont * 0.28).clamped(8, 22)
            let requestedScoreHeight = scoreFont * 1.02
            let requestedHeight = requestedNameHeight + requestedGap + requestedScoreHeight
            let contentScale = min(1, max(0.35, availableHeight / max(requestedHeight, 1)))
            let fittedName = max(12, nameFont * contentScale)
            let fittedScore = max(24, scoreFont * contentScale)

            return VStack(spacing: requestedGap * contentScale) {
                Text(name)
                    .font(scoreDisplayFont(size: fittedName, weight: .bold))
                    .foregroundStyle(nameColor)
                    .lineLimit(nameMaxLines)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, max(8, nameHorizontalPadding))
                Text("\(score)")
                    .font(scoreDisplayFont(size: fittedScore))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
            }
        }

        private func scoreDisplayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
            guard !fontCode.isEmpty, let font = ScoreboardFont(displayCode: fontCode) else {
                return .system(size: size, weight: weight)
            }
            return font.swiftUIFont(size: size, weight: weight)
        }
    }
}

/// multiGrid 玩家解析与配色槽位（对齐安卓 buildGridPlayer 的槽位回退）。
private enum LegacyExternalLayouts {
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
}

// MARK: - 计时 / 休息遮罩

/// 对齐安卓 MatchTimeDisplay：黑 32% 圆角卡（8*scale 圆角、14/6 内边距）；
/// 足球显示阶段徽章 + 主时间 + 补时，其余项目仅显示累计时间。
private struct ScoreboardExternalClockView: View {
    let clock: ScoreboardDisplayClock
    let fontCode: String
    let timeScale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let projectedMs = clock.projectedMilliseconds(
                atWallClockMilliseconds: Int64(context.date.timeIntervalSince1970 * 1_000)
            )
            let football = footballPresentation(projectedMs: projectedMs)
            let shouldPulse = !reduceMotion && !clock.isRunning && projectedMs == 0
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
            .phaseAnimator(shouldPulse ? [false, true] : [false]) { content, emphasized in
                content
                    .scaleEffect(shouldPulse ? (emphasized ? 1.03 : 0.97) : 1)
                    .opacity(shouldPulse ? (emphasized ? 1 : 0.78) : 1)
            } animation: { _ in
                .easeInOut(duration: 0.7)
            }
        }
    }

    private func font(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        (ScoreboardFont(displayCode: fontCode) ?? .default).swiftUIFont(size: size, weight: weight)
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

private struct ScoreboardExternalKeyPointBadgeLayer: View {
    let state: ScoreboardDisplayState
    let projection: ScoreboardExternalProjection
    let viewport: CGSize
    let doublesModel: DisplayDoublesRenderModel?
    let twoSideModel: DisplayTwoSideRenderModel?

    var body: some View {
        if let keyPoint = state.keyPoint, state.result?.ended != true {
            let isLeft = keyPoint.side == "left"
            let scale = projection.isLocalProjection
                ? ((min(viewport.width, viewport.height) / 360).clamped(1.5, 2) * 0.8)
                : 1
            let badgeWidth = 56 * scale
            let triangleSize = doublesModel?.arrowSize ?? twoSideModel?.arrowSize ?? 0
            let doublesTopRow: Bool? = if let doublesModel,
                                                  doublesModel.serverVisible,
                                                  doublesModel.serverPointLeft == isLeft {
                doublesModel.serverTopRow
            } else {
                nil
            }
            ScoreboardKeyPointBadge(kind: keyPoint.kind, gameType: state.gameType, scale: scale)
                .position(
                    x: ScoreboardServeGeometry.keyPointBadgeCenterX(
                        width: viewport.width,
                        isLeftSide: isLeft,
                        innerGap: 12 * scale,
                        badgeHalfWidth: badgeWidth / 2
                    ),
                    y: badgeCenterY(
                        doublesTopRow: doublesTopRow,
                        triangleSize: triangleSize,
                        scale: scale
                    )
                )
                .allowsHitTesting(false)
                .accessibilityIdentifier("external_key_point_badge")
        }
    }

    private func badgeCenterY(
        doublesTopRow: Bool?,
        triangleSize: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        if state.gameType == "foosball", let model = twoSideModel {
            // 桌上足球的局点/赛点属于局分区域，放在主分与底部局分之间。
            return min(
                viewport.height - 40 * scale,
                viewport.height / 2 + model.scoreFontSize * 0.50
            )
        }
        if doublesModel != nil && doublesTopRow == nil {
            return viewport.height / 2
        }
        return ScoreboardServeGeometry.keyPointBadgeCenterY(
            height: viewport.height,
            doublesTopRow: doublesTopRow,
            largeWindow: min(viewport.width, viewport.height) >= 600,
            triangleSize: triangleSize
        )
    }

}

private struct ScoreboardExternalTableTennisMarkerLayer: View {
    let state: ScoreboardDisplayState
    let projection: ScoreboardExternalProjection
    let keyPointVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            let scale = projection.isLocalProjection
                ? ((min(proxy.size.width, proxy.size.height) / 360).clamped(1.5, 2) * 0.8)
                : 1
            HStack(spacing: 34 * scale) {
                TableTennisAdministrativeCards(status: status(forScreenLeft: true), alignment: .trailing, scale: scale)
                TableTennisAdministrativeCards(status: status(forScreenLeft: false), alignment: .leading, scale: scale)
            }
            .frame(width: proxy.size.width, height: 24 * scale)
            .position(
                x: proxy.size.width / 2,
                y: ScoreboardServeGeometry.tableTennisCardsCenterY(
                    height: proxy.size.height,
                    keyPointVisible: keyPointVisible,
                    scale: scale
                )
            )
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("external_table_tennis_cards")
    }

    private func status(forScreenLeft screenLeft: Bool) -> TableTennisAdministrativeMarkerStatus {
        let team0OnLeft = state.sportString("team0ScreenSide") != "right"
        let logicalTeam0 = screenLeft == team0OnLeft
        let prefix = logicalTeam0 ? "tableTennisTeam0" : "tableTennisTeam1"
        return .init(
            timeoutUsed: state.sportBoolValue("\(prefix)TimeoutUsed") ?? false,
            hasYellowCard: state.sportBoolValue("\(prefix)Yellow") ?? false,
            redCardCount: state.sportInt("\(prefix)RedCount") ?? 0
        )
    }
}

private struct ScoreboardExternalRestOverlay: View {
    let rest: ScoreboardDisplayRest
    let viewport: CGSize
    let projection: ScoreboardExternalProjection

    var body: some View {
        // 1:1 对齐安卓显示端 OfficialBreakPill（showAction=false，scale=1f）：
        // 8% 黑遮罩保持比分可见，深色圆角卡 + 绿色 mm:ss 倒计时。
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = rest.projectedRemainingSeconds(
                atWallClockMilliseconds: Int64(context.date.timeIntervalSince1970 * 1_000)
            )
            let scale = projection.isLocalProjection
                ? DisplayTypographyResolver.chromeScale(for: viewport).clamped(1, 1.5)
                : 1
            let titleLines = officialBreakTitle.components(separatedBy: " · ")
            ZStack {
                Color.black.opacity(0.08).ignoresSafeArea()
                VStack(spacing: 10 * scale) {
                    VStack(spacing: 2 * scale) {
                        Text(titleLines[0])
                            .font(.system(size: 18 * scale, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                        if titleLines.count > 1 {
                            Text(titleLines.dropFirst().joined(separator: " · "))
                                .font(.system(size: 16 * scale, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    Text(rest.phase == "preparation" ? "\(remaining)" : officialBreakClock(remaining))
                        .font(.system(size: 44 * scale, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(red: 0x31 / 255, green: 0xD1 / 255, blue: 0x58 / 255))
                }
                .frame(minWidth: 156 * scale)
                .padding(.horizontal, 24 * scale)
                .padding(.vertical, 14 * scale)
                .background(
                    Color(red: 0x0C / 255, green: 0x0C / 255, blue: 0x0E / 255).opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 32 * scale, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 32 * scale, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: max(1, scale))
                }
                .shadow(color: .black.opacity(0.35), radius: 14 * scale, y: 6 * scale)
            }
        }
    }

    private var officialBreakTitle: String {
        if let title = rest.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
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

    /// 对齐安卓 buildNineBallChaseStats：优先 chasePlayerCounts[玩家]，2 人局回退 left/right。
    func displayChaseCounts(playerIndex: Int) -> [Int] {
        guard let sportState = sportState else { return [] }
        if case .integersArrays(let rows)? = sportState["chasePlayerCounts"] {
            if rows.indices.contains(playerIndex) { return rows[playerIndex] }
        }
        let fallbackKey = playerIndex == 0 ? "chaseLeftCounts" : "chaseRightCounts"
        if case .integers(let counts)? = sportState[fallbackKey] {
            return counts
        }
        return []
    }
}
