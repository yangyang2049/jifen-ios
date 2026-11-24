import SwiftUI
import WatchKit

/// Apple Watch 两档布局：40/41/新款 42/44mm 为窄屏，45/46/49mm 为宽屏。
/// 使用逻辑宽度判断，避免新款 42mm（187pt）比 44mm SE（184pt）更宽造成误判。
struct WatchLayout {
    static let narrowScreenMaximumWidth: CGFloat = 190
    /// 屏幕尺寸整机不变；缓存一次，避免每次布局都走 WKInterfaceDevice 查询。
    static let cachedScreenWidth: CGFloat = WKInterfaceDevice.current().screenBounds.width
    /// 计分板发球/当前选手的三角指示器尺寸，单打和双打统一。
    static let serverIndicatorSize: CGFloat = 10
    /// Avoid the system clock by moving scoreboard names down consistently.
    static let scoreboardNameVerticalOffset: CGFloat = 8
    /// Horizontal indicators follow the lowered names; vertical indicators stay flush to the top/bottom edge.
    static func serverIndicatorVerticalOffset(isHorizontal: Bool) -> CGFloat {
        isHorizontal ? scoreboardNameVerticalOffset : 0
    }
    /// Balance the name adjustment by moving set/frame metadata upward.
    static let scoreboardMetaVerticalOffset: CGFloat = -8
    /// 计分板全屏 Overlay 的可见关闭按钮尺寸。
    static let overlayCloseButtonSize: CGFloat = 40
    /// 首页等非全屏 Dialog 的可见关闭图标尺寸。
    static let dialogCloseIconSize: CGFloat = 20

    static func overlayActionButtonWidth(for width: CGFloat) -> CGFloat {
        isNarrowScreen(width: width) ? 134 : 144
    }

    static func isNarrowScreen(width: CGFloat) -> Bool {
        width <= narrowScreenMaximumWidth
    }

    static func pageHorizontalPadding(for width: CGFloat) -> CGFloat {
        isNarrowScreen(width: width) ? 6 : 12
    }

    static func pillRowHorizontalPadding(for width: CGFloat) -> CGFloat {
        isNarrowScreen(width: width) ? 12 : 16
    }

    static func recordRowHorizontalPadding(for width: CGFloat) -> CGFloat {
        isNarrowScreen(width: width) ? 12 : 16
    }

    static func cardContentPadding(for width: CGFloat) -> CGFloat {
        isNarrowScreen(width: width) ? 12 : 14
    }

    static func archeryScorePanelHorizontalPadding(for width: CGFloat) -> CGFloat {
        isNarrowScreen(width: width) ? 2 : 4
    }

    static func archeryScoreButtonSize(for width: CGFloat) -> CGFloat {
        let horizontalPadding = archeryScorePanelHorizontalPadding(for: width)
        let gridSpacing: CGFloat = isNarrowScreen(width: width) ? 2 : 3
        let availableWidth = width - horizontalPadding * 2 - gridSpacing * 3
        let maximumSize: CGFloat = isNarrowScreen(width: width) ? 42 : 46
        return min(maximumSize, floor(availableWidth / 4))
    }

    static func snookerBallButtonSize(for width: CGFloat) -> CGFloat {
        let availableWidth = width - 16 - 5 * 3
        let maximumSize: CGFloat = isNarrowScreen(width: width) ? 38 : 42
        return min(maximumSize, floor(availableWidth / 4))
    }

    /// 屏幕宽度 ≤ 190pt 视为窄屏。
    static var isCompactScreen: Bool {
        isNarrowScreen(width: cachedScreenWidth)
    }

    /// 记录行等易挤满的内容与页面使用同一套两档判断。
    static var isNarrowForContent: Bool {
        isCompactScreen
    }

    /// Overlay 主操作按钮使用明确宽度，避免随屏幕宽度被横向拉满。
    static var overlayActionButtonWidth: CGFloat {
        overlayActionButtonWidth(for: cachedScreenWidth)
    }

    /// Tab、列表、表单和详情页统一左右边距。
    static var pageHorizontalPadding: CGFloat {
        pageHorizontalPadding(for: cachedScreenWidth)
    }

    /// 列表行（PillRow/PillButton）左右内边距
    static var pillRowHorizontalPadding: CGFloat {
        pillRowHorizontalPadding(for: cachedScreenWidth)
    }
    /// 二、三级页面普通内容卡片内边距。
    static var cardContentPadding: CGFloat {
        cardContentPadding(for: cachedScreenWidth)
    }
    /// 射箭加分 Overlay 独立使用极小横向边距，不跟随普通页面边距。
    static var archeryScorePanelHorizontalPadding: CGFloat {
        archeryScorePanelHorizontalPadding(for: cachedScreenWidth)
    }
    /// 射箭加分面板纵向留白。
    static var archeryScorePanelVerticalPadding: CGFloat {
        cachedScreenWidth <= 176 ? 2 : (isCompactScreen ? 4 : 6)
    }
    /// 射箭加分面板内 VStack 间距（标题/网格/关闭）
    static var archeryScorePanelVStackSpacing: CGFloat {
        cachedScreenWidth <= 176 ? 2 : (isCompactScreen ? 4 : 6)
    }
    /// 射箭加分面板名称与分数网格的额外间距。
    static var archeryScoreTitleBottomPadding: CGFloat {
        cachedScreenWidth <= 176 ? 6 : (isCompactScreen ? 8 : 10)
    }
    /// 射箭加分面板关闭按钮与网格的间距
    static var archeryScorePanelCloseTopPadding: CGFloat { isCompactScreen ? 0 : 4 }
    /// 射箭加分面板按钮尺寸
    static var archeryScoreButtonSize: CGFloat {
        archeryScoreButtonSize(for: cachedScreenWidth)
    }
    /// 射箭加分面板数字字号
    static var archeryScoreButtonFontSize: CGFloat { isCompactScreen ? 15 : 17 }
    /// 射箭加分面板网格间距
    static var archeryScoreGridSpacing: CGFloat { isCompactScreen ? 2 : 3 }
    /// 斯诺克进球按钮直径，尽量填满四列网格。
    static var snookerBallButtonSize: CGFloat {
        snookerBallButtonSize(for: cachedScreenWidth)
    }
    /// 射箭菜单 overlay 内边距
    static var archeryMenuPadding: CGFloat { isCompactScreen ? 8 : 12 }
    /// 射箭菜单按钮高度
    static var archeryMenuButtonHeight: CGFloat { isCompactScreen ? 44 : 52 }
    /// 射箭菜单图标字号
    static var archeryMenuIconSize: CGFloat { isCompactScreen ? 18 : 22 }
    /// 射箭结束 overlay 内边距
    static var archeryStoppedOverlayPadding: CGFloat { isCompactScreen ? 14 : 24 }
    /// 射箭结束 overlay 主按钮宽度
    static var archeryStoppedButtonWidth: CGFloat { isCompactScreen ? 130 : 160 }
    /// 射箭结束 overlay 按钮高度
    static var archeryStoppedButtonHeight: CGFloat { isCompactScreen ? 38 : 44 }
    /// 记录列表行左右内边距（含 44mm 窄屏时缩小，避免第一行被截断）
    static var recordRowHorizontalPadding: CGFloat {
        recordRowHorizontalPadding(for: cachedScreenWidth)
    }
    /// 记录列表行图标尺寸（emoji 兜底与 3D 图共用，避免图片被外层 frame 裁切）
    static var recordRowIconSize: CGFloat { isNarrowForContent ? 20 : 22 }
    /// 首页列表行项目图标（与手机端 3D 图标同源）。3D 图在手表上按 20/22pt
    /// 显示，与鸿蒙手表 28vp 在同一比例区间，再大就会顶满 52pt 的胶囊行。
    static var pillIconSize: CGFloat { isCompactScreen ? 20 : 22 }
    /// 记录列表行图标与文字间距
    static var recordRowSpacing: CGFloat { isNarrowForContent ? 8 : 12 }
    /// 记录列表行首行（标题）字号，窄屏略小以协调
    static var recordRowTitleFontSize: CGFloat { isNarrowForContent ? 14 : 16 }
    /// 记录列表行第二行（时间）字号，与首行协调
    static var recordRowSubtitleFontSize: CGFloat { isNarrowForContent ? 10 : 12 }
    /// 记录列表行首行与第二行间距，窄屏两行都变小时加大避免挤在一起
    static var recordRowLineSpacing: CGFloat { isNarrowForContent ? 5 : 1 }
}

/// Main scoreboard number sizing shared by every sport.
/// Mirrors the HarmonyOS rule: compact screens lose 2pt, then text with three
/// or more characters shrinks by 18% for every character after the second.
struct WatchScoreTypography {
    static let compactBaseReduction: CGFloat = 2
    static let extraCharacterScale: CGFloat = 0.82
    static let averageCharacterWidthRatio: CGFloat = 0.66

    /// Primary standalone scoreboard values.
    static func primaryScore(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Supporting values such as sets, games, frames and handicaps.
    static func secondaryScore(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func adaptiveFontSize(
        baseSize: CGFloat,
        scoreText: String,
        minimumSize: CGFloat,
        screenWidth: CGFloat,
        availableWidth: CGFloat? = nil,
        horizontalPadding: CGFloat = 12
    ) -> CGFloat {
        let compactBase = baseSize - (WatchLayout.isNarrowScreen(width: screenWidth) ? compactBaseReduction : 0)
        let characterCount = max(scoreText.count, 1)
        var result = compactBase

        if characterCount >= 3 {
            result *= CGFloat(pow(Double(extraCharacterScale), Double(characterCount - 2)))
        }

        if let availableWidth, availableWidth > horizontalPadding {
            let widthLimitedSize = (availableWidth - horizontalPadding)
                / (CGFloat(characterCount) * averageCharacterWidthRatio)
            result = min(result, widthLimitedSize)
        }

        return max(minimumSize, result).rounded()
    }

    static func adaptiveFontSize(
        baseSize: CGFloat,
        scoreText: String,
        minimumSize: CGFloat,
        availableWidth: CGFloat? = nil,
        horizontalPadding: CGFloat = 12
    ) -> CGFloat {
        adaptiveFontSize(
            baseSize: baseSize,
            scoreText: scoreText,
            minimumSize: minimumSize,
            screenWidth: WatchLayout.cachedScreenWidth,
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding
        )
    }
}

struct WatchTheme {
    static let background = Color(hex: 0x000000)
    static let card = Color(hex: 0x2C2C2E)
    static let primaryText = Color(hex: 0xFFFFFF)
    static let secondaryText = Color(hex: 0x8E8E93)
    static let accent = Color(hex: 0x30D158)
    static let listItemBackground = Color(hex: 0x222222)
    static let overlayCard = Color(hex: 0x1C1C1E)
    static let timerAccent = Color(hex: 0x39FF14)
    static let resumeBar = Color(hex: 0x124A1E)
    static let successGreen = Color(hex: 0x4CAF50)
    static let warningOrange = Color(hex: 0xFF7043)
    static let dangerRed = Color(hex: 0xFF3B30)
    /// 计分板红/蓝双方主色。此前在 7 个计分板里硬编码 32 处，
    /// 改配色需逐处修改；此处统一为唯一定义。
    static let teamRed = Color(hex: 0xE53935)
    static let teamBlue = Color(hex: 0x1E88E5)

    /// 轻微填充：次级胶囊/按钮/描边的底色（此前散落 7 处 0.08）。
    static let subtleFill = Color.white.opacity(0.08)
    /// 弹层/面板的深色底（此前散落 8 处 0.62）。
    static let panelScrim = Color.black.opacity(0.62)
    /// 全屏遮罩，用于覆盖计分板（此前散落 3 处 0.5）。
    static let fullScreenScrim = Color.black.opacity(0.5)
}

struct WatchMenuGridButton: View {
    let title: String
    let systemImage: String
    var assetImage: String? = nil
    var background: Color = WatchTheme.card
    let action: () -> Void

    var body: some View {
        let iconSize: CGFloat = WatchLayout.isCompactScreen ? 15 : 17
        Button(action: action) {
            VStack(spacing: 3) {
                if let assetImage {
                    Image(assetImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: WatchLayout.isCompactScreen ? 14 : 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: WatchLayout.isCompactScreen ? 9 : 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: WatchLayout.isCompactScreen ? 42 : 46)
            .background(background)
            .clipShape(RoundedRectangle(
                cornerRadius: WatchLayout.isCompactScreen ? 10 : 12,
                style: .continuous
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WatchMenuCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: WatchLayout.overlayCloseButtonSize))
                .foregroundStyle(WatchTheme.secondaryText)
                .frame(
                    width: WatchLayout.overlayCloseButtonSize,
                    height: WatchLayout.overlayCloseButtonSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct WatchDialogCloseButton: View {
    var touchTargetSize: CGFloat = WatchLayout.overlayCloseButtonSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: WatchLayout.dialogCloseIconSize))
                .foregroundStyle(WatchTheme.secondaryText)
                .frame(
                    width: touchTargetSize,
                    height: touchTargetSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 卡片式弹层统一顶栏：左标题（可附状态徽标）+ 右上角关闭钮，避免标题与关闭钮挤压。
struct WatchDialogHeader<Accessory: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    init(
        title: String,
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.onClose = onClose
        self.accessory = accessory
    }

    var body: some View {
        let compact = WatchLayout.isCompactScreen
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundStyle(WatchTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            accessory()

            Spacer(minLength: 4)

            WatchDialogCloseButton(touchTargetSize: compact ? 24 : 26, action: onClose)
                .accessibilityLabel(NSLocalizedString("cancel", value: "取消", comment: ""))
        }
        .padding(.leading, 4)
    }
}

struct WatchMetrics {
    static let pagePadding = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    static let navBarHeight: CGFloat = 32
    static let indicatorSpacing: CGFloat = 5
    static let activeIndicator: CGFloat = 6
    static let inactiveIndicator: CGFloat = 4
    static let cardRadius: CGFloat = 12
    static let pillRadius: CGFloat = 30
    static let pillHeight: CGFloat = 52
}

struct WatchAnimations {
    static let coinFlip: Double = 2.0
    static let delayStart: Double = 0.2
    static let fingerFeedback: Double = 0.18
    static let swapChipFade: Double = 0.22
}

struct WatchTiming {
    static let longPressThreshold: Double = 0.5
    static let hintDelay: Double = 1.2
    /// Keep the just-scored result visible before a rest or finished overlay replaces the board.
    static let completedScoreVisibility: Double = 0.8
    static let finishedUndoCountdown: Double = 3.0
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
