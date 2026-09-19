//
//  Theme.swift
//  jifen
//
//  App theme and colors
//

import SwiftUI

struct Theme {
    enum DialogWidthRole {
        case setup
        case scoreboardMenu
        case gameOver
        case informational
        case scoreAdjustment
        case scoreboardDisplaySettings
    }

    /// Use the system-reported device idiom for iPad-specific layouts.
    /// Window dimensions and size classes intentionally do not affect this decision.
    static var usesPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // System semantic colors automatically follow appearance and accessibility contrast.
    static let backgroundColor = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    /// 主页面内容卡片的统一底色。深色值取自计分/计时 Grid 当前的视觉层级，
    /// 使用不透明动态色以避免 iPad Stage Manager 小窗口下 Material 或系统层级变化导致撞色。
    static let appCardBackground = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 32 / 255, green: 32 / 255, blue: 34 / 255, alpha: 1) // #202022
        }
        return .white
    })
    /// 自适应 Dialog / Sheet 底色；浅色保持白色，深色使用系统二级背景，
    /// 避免自定义弹窗与纯黑页面背景融为一体。
    static let dialogSurfaceBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground
    })
    /// Dialog / Sheet 内选项格、输入区、取消按钮的统一灰色。
    /// 浅色跟随系统分段 Toggle 的 tertiary fill；深色继续保留现有 secondary fill 对比度。
    static let dialogControlBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemFill : .tertiarySystemFill
    })
    /// Scoreboard overlays stay dark regardless of the app/system appearance,
    /// matching the in-game operation menu against bright scoreboard panels.
    static let scoreboardDialogSurface = Color(hex: "2C2C2E")
    static let scoreboardDialogControl = Color(hex: "3A3A3C")
    static let scoreboardDialogTextPrimary = Color.white
    static let scoreboardDialogTextSecondary = Color(hex: "98989D")
    static let scoreboardDialogScrim = Color.black.opacity(0.45)
    /// 普通页面控件仍保留 secondary gray；Dialog / Sheet 请使用 dialogControlBackground。
    static let controlBackground = Color(uiColor: .secondarySystemFill)
    /// 页面级文本输入框统一底色：不透明动态色。深色用 #2C2C2E 从近黑页面底色中明确抬升，
    /// 避免 secondarySystemFill 半透明叠色导致"输入框融进背景 + 描边显脏"的问题。
    static let inputFieldBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
            : UIColor(red: 229 / 255, green: 229 / 255, blue: 234 / 255, alpha: 1)
    })
    /// 同一 tint 底色、深浅双 alpha 的着色背景。收口视图里
    /// `colorScheme == .dark ? tint.opacity(a) : tint.opacity(b)` 的一次性写法。
    static func tintedFill(_ tint: Color, lightAlpha: Double, darkAlpha: Double) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(tint).resolvedColor(with: traits).withAlphaComponent(
                traits.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            )
        })
    }
    /// 一个角色深浅各指一个值（等价于颜色 json 里的 light/dark 双值）；
    /// 视图侧永远只引用这一个 token，不再出现 colorScheme 分支。
    static func adaptive(_ light: Color, _ dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark).resolvedColor(with: traits)
                : UIColor(light).resolvedColor(with: traits)
        })
    }
    /// 仅浅色模式生效的环境阴影；深色近黑背景上黑阴影不可见，直接返回 clear。
    static func lightModeShadow(_ opacity: Double) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .clear : UIColor.black.withAlphaComponent(opacity)
        })
    }
    /// 悬浮在内容之上的浮层通用阴影；深色改用白色微光保持可感知。
    static let overlayShadow = Color(uiColor: UIColor { traits in
        (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black).withAlphaComponent(0.1)
    })
    /// 悬浮按钮等浮层控件的默认图标色。
    static let floatingIconColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.85)
            : UIColor.black.withAlphaComponent(0.7)
    })
    /// 卡片内轻量控件（关闭/取消小圆钮）的安静底色。
    static let quietChipFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : .tertiarySystemFill
    })
    /// 首页快速开始编辑槽位卡底色（未选中）：直接用系统表面色。
    static let editSlotFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemFill : .systemBackground
    })
    /// 编辑槽位卡选中态：主色浅着色，深浅都可见，替代原先深色下与未选中无差别的中性灰。
    static var editSlotSelectedFill: Color {
        tintedFill(accentColor, lightAlpha: 0.12, darkAlpha: 0.12)
    }
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let divider = Color(uiColor: .separator)
    /// 与鸿蒙端一致：浅色 #4CAF50，深色 #30D158。
    static let accentColor = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 48 / 255, green: 209 / 255, blue: 88 / 255, alpha: 1)
        }
        return UIColor(red: 76 / 255, green: 175 / 255, blue: 80 / 255, alpha: 1)
    })
    static let goldText = Color("GoldText")
    static let positiveText = Color("PositiveText")
    static let warningText = Color("WarningText")
    static let destructiveText = Color("DestructiveText")

    // Additional colors derived from HarmonyOS UI
    static let primary = accentColor // Map HarmonyOS 'primary' to existing accentColor
    static let primaryDark = Color(hex: "248A3D")
    static let black = Color.black
    static let textOnPrimary = Color.white // Assuming text on primary is white
    static let transparent = Color.clear

    // HarmonyOS specific colors from the provided code
    static let homeButtonShadow = Color.black.opacity(0.2) // Approximated
    static let homePrimaryCardOrange = Color(hex: "#F97316")
    static let homeSecondaryCardGreen = Color(hex: "#30D158") // Approximated, used in HarmonyOS quickStart config
    static let homeEditButtonGreen = Color(hex: "#30D158") // Used for save button
    static let homeCardDark = appCardBackground
    static let homeCardLight = cardBackground
    static let homeOverlayBorder = Color.primary.opacity(0.1)
    static let homeDividerLight = Color.primary.opacity(0.2)
    static let homeOverlayBorderLight = Color.primary.opacity(0.1)
    static let homeShadowLight = Color.black.opacity(0.05) // Approximated
    static let homeTextDisabledDark = Color.secondary.opacity(0.7)
    static let homeTextDisabledLight = Color.secondary.opacity(0.7)
    static let homeOverlayWhite = Color.white // Used for text in QuickStartGrid new game button
    static let homeOverlayDark = Color.black.opacity(0.3) // Used for new game button circle plus icon
    static let homeCardTextPrimary = Color.white
    static let homeCardTextSecondary = Color.white.opacity(0.78)
    static let homeCardTextTertiary = Color.white.opacity(0.62)
    /// 首页卡片与计分、计时、我的、记录详情共用同一表面色。
    static let homeNeutralCardBackground = appCardBackground
    static let homeNeutralCardTextPrimary = Color(uiColor: .label)
    static let homeNeutralCardTextSecondary = Color(uiColor: .secondaryLabel)
    static let homeNeutralCardTextTertiary = Color(uiColor: .tertiaryLabel)
    static let homeNeutralCardDivider = Color(uiColor: .separator)
    static let homeBackgroundLight = backgroundColor
    /// Setup dialogs and modal panels share the same white/dark system surface.
    static let homeDialogBackground = dialogSurfaceBackground

    static let toolWhistleRed = Color(hex: "#EF4444") // Example tool color
    static let toolRankingsIndigo = Color(hex: "#6366F1") // Example tool color
    static let toolGray = Color(hex: "#6B7280") // Example tool color
    static let surface = appCardBackground

    // Spacing
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
    
    static let xs: CGFloat = 4 // Extra small spacing
    static let sm: CGFloat = 8 // Small spacing
    static let md: CGFloat = 16 // Medium spacing
    static let lg: CGFloat = 24 // Large spacing

    // Main-tab layout metrics. Keep semantic roles separate from the generic spacing scale.
    static var pageHorizontalInset: CGFloat { usesPadLayout ? 24 : 16 }
    /// 普通二、三级列表页在 iPad 上的正文宽度。
    static var secondaryPageContentMaxWidth: CGFloat { usesPadLayout ? 760 : .infinity }
    /// 表单、记录详情、积分表等需要保持阅读聚焦的内容宽度。
    static let focusedContentMaxWidth: CGFloat = 600
    /// 登录类页面的正文宽度：ASAuthorizationAppleIDButton 内部自带 width <= 375（Apple 规范），
    /// 整栏收到 375 后，同级的账号密码登录/输入框/协议条与它等宽，也不会再和 UIKit 约束打架。
    static let authContentMaxWidth: CGFloat = 375
    /// “我的”Tab 及其下级页面共用的正文宽度，避免 iPad 导航时内容宽度跳变。
    static var meTabContentMaxWidth: CGFloat { secondaryPageContentMaxWidth }

    /// Custom card dialogs keep their compact phone proportions, while iPad
    /// gets a wider reading/control area. The available-width clamp also keeps
    /// them usable in iPad Split View and Stage Manager narrow windows.
    static func dialogWidth(
        availableWidth: CGFloat,
        role: DialogWidthRole
    ) -> CGFloat {
        let widths = dialogPreferredWidths(role: role)
        return dialogWidth(
            availableWidth: availableWidth,
            phonePreferredWidth: widths.phone,
            padPreferredWidth: widths.pad
        )
    }

    private static func dialogPreferredWidths(
        role: DialogWidthRole
    ) -> (phone: CGFloat, pad: CGFloat) {
        switch role {
        case .setup: (340, 480)
        case .scoreboardMenu: (320, 480)
        case .gameOver: (360, 480)
        case .informational: (360, 480)
        case .scoreAdjustment: (600, 600)
        case .scoreboardDisplaySettings: (360, 480)
        }
    }

    static func dialogWidth(
        availableWidth: CGFloat,
        phonePreferredWidth: CGFloat,
        padPreferredWidth: CGFloat
    ) -> CGFloat {
        let preferredWidth = usesPadLayout ? padPreferredWidth : phonePreferredWidth
        let horizontalInset: CGFloat = usesPadLayout && availableWidth >= 600 ? 40 : 16
        return max(0, min(preferredWidth, availableWidth - horizontalInset * 2))
    }

    static func dialogPreferredWidth(role: DialogWidthRole) -> CGFloat {
        let widths = dialogPreferredWidths(role: role)
        return usesPadLayout ? widths.pad : widths.phone
    }

    static func scoreboardDisplaySettingsPanelWidth(availableWidth: CGFloat) -> CGFloat {
        let preferredWidth = dialogWidth(
            availableWidth: availableWidth,
            role: .scoreboardDisplaySettings
        )
        return usesPadLayout ? min(preferredWidth, availableWidth * 0.46) : preferredWidth
    }

    static let sectionSpacing: CGFloat = 24
    static let sectionContentSpacing: CGFloat = 12
    static let gridSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let compactCardPadding: CGFloat = 12
    static let recordRowVerticalPadding: CGFloat = 12
    static let tabContentBottomPadding: CGFloat = 24

    // Corner Radius
    static let cornerRadius: CGFloat = 12
    static let xl: CGFloat = 22 // Extra large corner radius, specifically for ToolItem
    static let xxl: CGFloat = 24 // Extra extra large corner radius

    // Font Sizes (Approximated from HarmonyOS code, not directly mapping)
    static let fontCaption: CGFloat = 12
    static let fontBody2: CGFloat = 14
    static let fontBody1: CGFloat = 16
    static let fontH5: CGFloat = 18
    static let fontH4: CGFloat = 20
    static let fontH3: CGFloat = 24

    /// Menu 里 role=.destructive 只会染文字，图标仍跟 tint；预着色保证垃圾桶为红。
    static let redTrashIcon: UIImage = {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let base = UIImage(systemName: "trash", withConfiguration: config) ?? UIImage()
        return base.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
    }()

}

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red, green, blue: Double
        switch hexSanitized.count {
        case 6: // RGB (24-bit)
            red = Double((rgb & 0xFF0000) >> 16) / 255.0
            green = Double((rgb & 0x00FF00) >> 8) / 255.0
            blue = Double(rgb & 0x0000FF) / 255.0
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
        case 8: // ARGB (32-bit)
            let alpha = Double((rgb & 0xFF000000) >> 24) / 255.0
            red = Double((rgb & 0x00FF0000) >> 16) / 255.0
            green = Double((rgb & 0x0000FF00) >> 8) / 255.0
            blue = Double(rgb & 0x000000FF) / 255.0
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        default:
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1.0)
        }
    }
}
