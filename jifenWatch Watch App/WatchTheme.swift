import SwiftUI
import WatchKit

/// 小屏手表（42mm 及以下）布局常量，用于缩小边距与控件
struct WatchLayout {
    /// 屏幕宽度 ≤ 180pt 视为窄屏（38/40/41/42mm，44mm 及以上为 184+）
    static var isCompactScreen: Bool {
        WKInterfaceDevice.current().screenBounds.size.width <= 180
    }
    /// 屏幕宽度 ≤ 184pt 视为「内容窄屏」（含 44mm），用于记录行等易挤满的列表
    static var isNarrowForContent: Bool {
        WKInterfaceDevice.current().screenBounds.size.width <= 184
    }
    /// Tab 内左右边距
    static var tabHorizontalPadding: CGFloat { isCompactScreen ? 6 : 12 }
    /// 列表行（PillRow/PillButton）左右内边距
    static var pillRowHorizontalPadding: CGFloat { isCompactScreen ? 10 : 16 }
    /// 射箭加分面板外边距（上下左右一致，内容纵向居中）
    static var archeryScorePanelPadding: CGFloat { isCompactScreen ? 12 : 20 }
    /// 射箭加分面板内 VStack 间距（标题/网格/关闭）
    static var archeryScorePanelVStackSpacing: CGFloat { 12 }
    /// 射箭加分面板关闭按钮与网格的间距
    static var archeryScorePanelCloseTopPadding: CGFloat { 8 }
    /// 射箭加分面板按钮尺寸
    static var archeryScoreButtonSize: CGFloat { isCompactScreen ? 34 : 44 }
    /// 射箭加分面板数字字号
    static var archeryScoreButtonFontSize: CGFloat { isCompactScreen ? 13 : 16 }
    /// 射箭加分面板网格间距
    static var archeryScoreGridSpacing: CGFloat { isCompactScreen ? 1 : 2 }
    /// 射箭菜单 overlay 内边距
    static var archeryMenuPadding: CGFloat { isCompactScreen ? 8 : 12 }
    /// 射箭菜单按钮高度
    static var archeryMenuButtonHeight: CGFloat { isCompactScreen ? 44 : 52 }
    /// 射箭菜单图标字号
    static var archeryMenuIconSize: CGFloat { isCompactScreen ? 18 : 22 }
    /// 射箭暂停/结束 overlay 内边距
    static var archeryStoppedOverlayPadding: CGFloat { isCompactScreen ? 14 : 24 }
    /// 射箭暂停/结束 overlay 主按钮宽度
    static var archeryStoppedButtonWidth: CGFloat { isCompactScreen ? 130 : 160 }
    /// 射箭暂停/结束 overlay 次按钮宽度
    static var archeryStoppedButtonWidthSmall: CGFloat { isCompactScreen ? 110 : 140 }
    /// 射箭暂停/结束 overlay 按钮高度
    static var archeryStoppedButtonHeight: CGFloat { isCompactScreen ? 38 : 44 }
    /// 记录列表行左右内边距（含 44mm 窄屏时缩小，避免第一行被截断）
    static var recordRowHorizontalPadding: CGFloat { isNarrowForContent ? 10 : 16 }
    /// 记录列表行图标尺寸
    static var recordRowIconSize: CGFloat { isNarrowForContent ? 20 : 24 }
    /// 记录列表行图标与文字间距
    static var recordRowSpacing: CGFloat { isNarrowForContent ? 8 : 12 }
    /// 记录列表行首行（标题）字号，窄屏略小以协调
    static var recordRowTitleFontSize: CGFloat { isNarrowForContent ? 14 : 16 }
    /// 记录列表行第二行（时间）字号，与首行协调
    static var recordRowSubtitleFontSize: CGFloat { isNarrowForContent ? 10 : 12 }
    /// 记录列表行首行与第二行间距，窄屏两行都变小时加大避免挤在一起
    static var recordRowLineSpacing: CGFloat { isNarrowForContent ? 5 : 1 }
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
    static let successGreen = Color(hex: 0x4CAF50)
    static let warningOrange = Color(hex: 0xFF7043)
    static let dangerRed = Color(hex: 0xFF3B30)
}

struct WatchMenuGridButton: View {
    let title: String
    let systemImage: String
    var background: Color = WatchTheme.card
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: WatchLayout.isCompactScreen ? 15 : 18, weight: .semibold))
                Text(title)
                    .font(.system(size: WatchLayout.isCompactScreen ? 10 : 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: WatchLayout.isCompactScreen ? 48 : 56)
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
                .font(.system(size: WatchLayout.isCompactScreen ? 20 : 24))
                .foregroundStyle(WatchTheme.secondaryText)
                .frame(
                    width: WatchLayout.isCompactScreen ? 32 : 38,
                    height: WatchLayout.isCompactScreen ? 32 : 38
                )
        }
        .buttonStyle(.plain)
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
    static let pillHeight: CGFloat = 60
    static let recordPillHeight: CGFloat = 72
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
    static let undoCountdown: Double = 5.0
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
