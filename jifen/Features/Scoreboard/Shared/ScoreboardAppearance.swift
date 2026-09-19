import Observation
import ScoreCore
import SwiftUI
import Combine

enum ScoreboardTheme: String, CaseIterable, Identifiable, Codable {
    case defaultTheme = "default"
    case proDark = "pro_dark"
    case electronic = "electronic"
    case retro = "retro"
    case brb = "brb"
    case wrb = "wrb"
    // 斗地主专属主题（ddz_*，独立命名空间，对齐安卓 SUPPORTED_DOUDIZHU_THEMES）。
    case ddzClassic = "ddz_classic"
    case ddzProDark = "ddz_pro_dark"
    case ddzElectronic = "ddz_electronic"
    case ddzRetro = "ddz_retro"
    case ddzBrb = "ddz_brb"
    case ddzWrb = "ddz_wrb"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .defaultTheme:
            return NSLocalizedString("scoreboard_theme_default", value: "默认", comment: "")
        case .proDark:
            return NSLocalizedString("scoreboard_theme_pro_dark", value: "专业深色", comment: "")
        case .electronic:
            return NSLocalizedString("scoreboard_theme_electronic", value: "电子屏", comment: "")
        case .retro:
            return NSLocalizedString("scoreboard_theme_retro", value: "复古", comment: "")
        case .brb:
            return NSLocalizedString("scoreboard_theme_brb", value: "黑红蓝", comment: "")
        case .wrb:
            return NSLocalizedString("scoreboard_theme_wrb", value: "白红蓝", comment: "")
        case .ddzClassic:
            return NSLocalizedString("theme_doudizhu_classic", value: "经典", comment: "")
        case .ddzProDark:
            return NSLocalizedString("theme_doudizhu_pro_dark", value: "专业深色", comment: "")
        case .ddzElectronic:
            return NSLocalizedString("theme_doudizhu_electronic", value: "电子屏", comment: "")
        case .ddzRetro:
            return NSLocalizedString("theme_doudizhu_retro", value: "复古", comment: "")
        case .ddzBrb:
            return NSLocalizedString("theme_doudizhu_brb", value: "黑红蓝", comment: "")
        case .ddzWrb:
            return NSLocalizedString("theme_doudizhu_wrb", value: "白红蓝", comment: "")
        }
    }

    /// 非斗地主项目的主题选项（对齐安卓 SUPPORTED_SCOREBOARD_THEMES）。
    static var genericOptions: [ScoreboardTheme] {
        [.defaultTheme, .proDark, .electronic, .retro, .brb, .wrb]
    }

    /// 斗地主项目的主题选项（对齐安卓 SUPPORTED_DOUDIZHU_THEMES）。
    static var doudizhuOptions: [ScoreboardTheme] {
        [.ddzClassic, .ddzProDark, .ddzElectronic, .ddzRetro, .ddzBrb, .ddzWrb]
    }

    /// 纯 `rawValue` 前缀判断，供 nonisolated 的样式代码（如 genericDefault）调用。
    nonisolated var isDoudizhuTheme: Bool { rawValue.hasPrefix("ddz_") }

    /// 斗地主主题码规范化：旧通用主题码迁移到 ddz_*，未知码回落经典斗地主（对齐安卓 doudizhuThemeOrDefault）。
    static func doudizhuNormalized(_ raw: String) -> ScoreboardTheme {
        switch raw {
        case "default", "ddz_classic", "": return .ddzClassic
        case "pro_dark": return .ddzProDark
        case "electronic": return .ddzElectronic
        case "retro": return .ddzRetro
        case "brb": return .ddzBrb
        case "wrb": return .ddzWrb
        default: return isDoudizhuCode(raw) ? (ScoreboardTheme(rawValue: raw) ?? .ddzClassic) : .ddzClassic
        }
    }

    private static func isDoudizhuCode(_ raw: String) -> Bool {
        ScoreboardTheme.doudizhuOptions.contains { $0.rawValue == raw }
    }

    // MARK: 主题基色（hex，1:1 对齐安卓 ui/theme/ScoreboardTheme.kt）

    /// 左侧面板底色。
    var leftPanelHex: String {
        switch self {
        case .defaultTheme, .ddzClassic: return "C62828"
        case .proDark: return "8E2428"
        case .ddzProDark: return "972828"
        case .wrb, .ddzWrb: return "FFFFFF"
        case .electronic, .retro, .brb, .ddzElectronic, .ddzRetro, .ddzBrb: return "000000"
        }
    }

    /// 右侧面板底色。
    var rightPanelHex: String {
        switch self {
        case .defaultTheme: return "007AFF"
        case .proDark, .ddzProDark: return "155A9C"
        case .ddzClassic: return "1565C0"
        case .wrb, .ddzWrb: return "FFFFFF"
        case .electronic, .retro, .brb, .ddzElectronic, .ddzRetro, .ddzBrb: return "000000"
        }
    }

    /// 中间面板底色（斗地主三栏 / 通用主题的 center 兜底）。
    var centerPanelHex: String {
        switch self {
        case .defaultTheme: return "1B5E20"
        case .proDark: return "15171A"
        case .ddzClassic: return "34C759"
        case .ddzProDark: return "1B1B1F"
        case .ddzWrb: return "FFFFFF"
        case .electronic, .retro, .brb, .wrb, .ddzElectronic, .ddzRetro, .ddzBrb: return "000000"
        }
    }

    /// 主分数前景色。
    var foregroundHex: String {
        switch self {
        case .proDark, .ddzProDark: return "F7F8FA"
        case .retro, .ddzRetro: return "00FF00"
        case .wrb, .ddzWrb: return "111111"
        case .defaultTheme, .electronic, .brb, .ddzClassic, .ddzElectronic, .ddzBrb: return "FFFFFF"
        }
    }

    /// 计分板本体背景（面板之外的底色）。
    var backgroundHex: String {
        switch self {
        case .wrb, .ddzWrb: return "FFFFFF"
        case .ddzProDark: return "15171A"
        default: return "000000"
        }
    }

    /// 计分板本体上的控制色（编辑名称输入框文字/边框、编辑±按钮底色等）。
    /// 对齐安卓 ScoreboardTheme.controlColor：默认白色；白底主题（wrb / 斗地主 wrb）
    /// 用深色 #111111，避免白字白底看不见。
    var controlColor: Color {
        switch self {
        case .wrb, .ddzWrb: return Color(hex: "111111")
        default: return .white
        }
    }

    var palette: ScoreboardPalette {
        // Aligned with HOS scoreboardTheme.ts
        switch self {
        case .defaultTheme:
            return ScoreboardPalette(
                background: .black,
                left: Color(hex: leftPanelHex),
                right: Color(hex: rightPanelHex),
                foreground: .white,
                secondary: .white.opacity(0.7),
                chrome: .black.opacity(0.28)
            )
        case .proDark:
            return ScoreboardPalette(
                background: .black,
                left: Color(hex: leftPanelHex),
                right: Color(hex: rightPanelHex),
                foreground: Color(hex: foregroundHex),
                secondary: Color(hex: foregroundHex).opacity(0.68),
                chrome: Color(hex: "111820").opacity(0.92)
            )
        case .electronic:
            return ScoreboardPalette(
                background: .black,
                left: .black,
                right: .black,
                foreground: .white,
                secondary: .white.opacity(0.72),
                chrome: .black.opacity(0.82)
            )
        case .retro:
            return ScoreboardPalette(
                background: .black,
                left: .black,
                right: .black,
                foreground: Color(hex: foregroundHex),
                secondary: Color(hex: foregroundHex).opacity(0.6),
                chrome: .black.opacity(0.9)
            )
        case .brb:
            return ScoreboardPalette(
                background: .black,
                left: .black,
                right: .black,
                foreground: .white,
                secondary: .white.opacity(0.7),
                chrome: .black.opacity(0.9)
            )
        case .wrb:
            return ScoreboardPalette(
                background: .white,
                left: .white,
                right: .white,
                foreground: Color(hex: foregroundHex),
                secondary: Color(hex: foregroundHex).opacity(0.7),
                chrome: .black.opacity(0.72),
                control: controlColor
            )
        case .ddzClassic:
            return ScoreboardPalette(
                background: .black,
                left: Color(hex: leftPanelHex),
                right: Color(hex: rightPanelHex),
                foreground: .white,
                secondary: .white.opacity(0.7),
                chrome: .black.opacity(0.28)
            )
        case .ddzProDark:
            return ScoreboardPalette(
                background: Color(hex: "15171A"),
                left: Color(hex: leftPanelHex),
                right: Color(hex: rightPanelHex),
                foreground: Color(hex: foregroundHex),
                secondary: Color(hex: foregroundHex).opacity(0.68),
                chrome: Color(hex: "111820").opacity(0.92)
            )
        case .ddzElectronic:
            return ScoreboardPalette(
                background: .black,
                left: .black,
                right: .black,
                foreground: .white,
                secondary: .white.opacity(0.72),
                chrome: .black.opacity(0.82)
            )
        case .ddzRetro:
            return ScoreboardPalette(
                background: .black,
                left: .black,
                right: .black,
                foreground: Color(hex: foregroundHex),
                secondary: Color(hex: foregroundHex).opacity(0.6),
                chrome: .black.opacity(0.9)
            )
        case .ddzBrb:
            return ScoreboardPalette(
                background: .black,
                left: .black,
                right: .black,
                foreground: .white,
                secondary: .white.opacity(0.7),
                chrome: .black.opacity(0.9)
            )
        case .ddzWrb:
            return ScoreboardPalette(
                background: .white,
                left: .white,
                right: .white,
                foreground: Color(hex: foregroundHex),
                secondary: Color(hex: foregroundHex).opacity(0.7),
                chrome: .black.opacity(0.72),
                control: controlColor
            )
        }
    }

    /// 主题迷你预览（对齐安卓 ic_theme_*：背景 + 左右侧 + 前景数字 "3 2"）。
    struct PreviewDescriptor: Equatable {
        var backgroundHex: String
        var leftHex: String?
        var centerHex: String?
        var rightHex: String?
        var seamHex: String?
        var leftDigitHex: String
        var centerDigitHex: String?
        var rightDigitHex: String
    }

    var previewDescriptor: PreviewDescriptor {
        switch self {
        case .defaultTheme:
            // 经典：左右面板铺满，白色数字（ic_theme_classic）。
            return .init(
                backgroundHex: leftPanelHex,
                leftHex: leftPanelHex, centerHex: nil, rightHex: rightPanelHex,
                seamHex: nil,
                leftDigitHex: "FFFFFF", centerDigitHex: nil, rightDigitHex: "FFFFFF"
            )
        case .proDark:
            // 专业深色：暗底 + 暗红/深蓝半区 + 暗色中缝 + 浅色数字（ic_theme_pro_dark）。
            return .init(
                backgroundHex: "15171A",
                leftHex: leftPanelHex, centerHex: nil, rightHex: rightPanelHex,
                seamHex: "15171A",
                leftDigitHex: "F7F8FA", centerDigitHex: nil, rightDigitHex: "F7F8FA"
            )
        case .electronic:
            // 电子屏：纯黑底 + 细缝 + 白色数字（ic_theme_electronic）。
            return .init(
                backgroundHex: "000000",
                leftHex: nil, centerHex: nil, rightHex: nil,
                seamHex: "1A1A1A",
                leftDigitHex: "FFFFFF", centerDigitHex: nil, rightDigitHex: "FFFFFF"
            )
        case .retro:
            // 复古：纯黑底 + 细缝 + 绿色数字（ic_theme_retro）。
            return .init(
                backgroundHex: "000000",
                leftHex: nil, centerHex: nil, rightHex: nil,
                seamHex: "1A1A1A",
                leftDigitHex: "00FF00", centerDigitHex: nil, rightDigitHex: "00FF00"
            )
        case .brb:
            // 黑红蓝：纯黑底 + 细缝 + 红/蓝数字（ic_theme_brb）。
            return .init(
                backgroundHex: "000000",
                leftHex: nil, centerHex: nil, rightHex: nil,
                seamHex: "1A1A1A",
                leftDigitHex: "FF0000", centerDigitHex: nil, rightDigitHex: "1E5BFF"
            )
        case .wrb:
            // 白红蓝：纯白底 + 浅缝 + 红/蓝数字（ic_theme_wrb）。
            return .init(
                backgroundHex: "FFFFFF",
                leftHex: nil, centerHex: nil, rightHex: nil,
                seamHex: "E5E5EA",
                leftDigitHex: "FF0000", centerDigitHex: nil, rightDigitHex: "1E5BFF"
            )
        case .ddzClassic:
            return .init(
                backgroundHex: leftPanelHex,
                leftHex: leftPanelHex, centerHex: centerPanelHex, rightHex: rightPanelHex,
                seamHex: nil,
                leftDigitHex: "FFFFFF", centerDigitHex: "FFFFFF", rightDigitHex: "FFFFFF"
            )
        case .ddzProDark:
            return .init(
                backgroundHex: leftPanelHex,
                leftHex: leftPanelHex, centerHex: centerPanelHex, rightHex: rightPanelHex,
                seamHex: nil,
                leftDigitHex: "FFFFFF", centerDigitHex: "FFFFFF", rightDigitHex: "FFFFFF"
            )
        case .ddzElectronic:
            return .init(
                backgroundHex: "000000",
                leftHex: nil, centerHex: nil, rightHex: nil,
                seamHex: "1A1A1A",
                leftDigitHex: "FFFFFF", centerDigitHex: "FFFFFF", rightDigitHex: "FFFFFF"
            )
        case .ddzRetro:
            return .init(
                backgroundHex: "000000",
                leftHex: nil, centerHex: nil, rightHex: nil,
                seamHex: "1A1A1A",
                leftDigitHex: "4CAF50", centerDigitHex: "4CAF50", rightDigitHex: "4CAF50"
            )
        case .ddzBrb:
            return .init(
                backgroundHex: "000000",
                leftHex: nil, centerHex: nil, rightHex: nil,
                seamHex: "1A1A1A",
                leftDigitHex: "FF0000", centerDigitHex: "34C759", rightDigitHex: "1E5BFF"
            )
        case .ddzWrb:
            return .init(
                backgroundHex: "FFFFFF",
                leftHex: nil, centerHex: nil, rightHex: nil,
                seamHex: "E5E5EA",
                leftDigitHex: "FF0000", centerDigitHex: "1B5E20", rightDigitHex: "1E5BFF"
            )
        }
    }

    /// Auxiliary button fill on colored team panels (HOS SCOREBOARD_AUXILIARY_BUTTON_BG).
    static let auxiliaryButtonBackground = Color.white.opacity(0.14)
    static let auxiliaryButtonBackgroundSubtle = Color.white.opacity(0.08)
}

struct ScoreboardPalette {
    let background: Color
    let left: Color
    let right: Color
    let foreground: Color
    let secondary: Color
    let chrome: Color
    var leftForeground: Color = .white
    var rightForeground: Color = .white
    var centerForeground: Color = .white
    /// 控制色：默认白；白底主题为深色（见 ScoreboardTheme.controlColor）。
    var control: Color = .white

    func applying(_ profile: ScoreboardStyleProfileV2) -> ScoreboardPalette {
        ScoreboardPalette(
            background: profile.background,
            left: profile.color(for: .team0),
            right: profile.color(for: .team1),
            foreground: profile.foreground,
            secondary: profile.foreground.opacity(0.7),
            chrome: chrome,
            leftForeground: profile.textColor(for: .team0),
            rightForeground: profile.textColor(for: .team1),
            centerForeground: profile.textColor(for: .center),
            control: ScoreboardTheme(rawValue: profile.themeCode)?.controlColor ?? .white
        )
    }

    func foreground(for slot: ScoreboardStyleSlot) -> Color {
        switch slot {
        case .team0: leftForeground
        case .team1: rightForeground
        case .center: centerForeground
        }
    }
}

/// Per-project V2 appearance values. Colors are persisted as hex strings so
/// the profile stays local, Codable, and independent of SwiftUI's Color type.
nonisolated struct ScoreboardStyleProfileV2: Codable, Equatable, Sendable {
    var themeCode: String
    var team0Hex: String
    var team1Hex: String
    var centerHex: String
    var team0TextHex: String
    var team1TextHex: String
    var centerTextHex: String
    var foregroundHex: String
    var backgroundHex: String
    var autoContrast: Bool
    /// V2 槽位化扩展（安卓互通字段）。nil = 尚未用新编辑器保存过，读旧扁平字段。
    var panels: [ScoreboardStylePanelV2]?
    var elements: [ScoreboardStyleElementV2]?
    var serverIndicatorColorHex: String?

    static func `default`(
        for styleID: ScoreboardStyleID,
        theme: ScoreboardTheme = .defaultTheme
    ) -> Self {
        guard let capabilities = ScoreboardStyleV2Registry.capabilities(for: styleID) else {
            // 未注册样式编辑的项目：维持旧扁平默认（无 V2 槽位数据）。
            return legacyFlatDefault(theme: theme)
        }
        if capabilities.slotKeys.contains(.sideCenter) {
            return doudizhuDefault(theme: theme, capabilities: capabilities)
        }
        return genericDefault(theme: theme, capabilities: capabilities)
    }

    /// 未注册样式编辑项目的旧扁平默认（历史行为，保持不变）。
    private static func legacyFlatDefault(theme: ScoreboardTheme) -> Self {
        let panels: (String, String, String, String, String)
        switch theme {
        case .defaultTheme:
            panels = ("FF3B30", "007AFF", "4CAF50", "FFFFFF", "000000")
        case .proDark:
            panels = ("972828", "007AFF", "4CAF50", "FFFFFF", "000000")
        case .electronic:
            panels = ("000000", "000000", "000000", "FFFFFF", "000000")
        case .retro:
            panels = ("000000", "000000", "000000", "4CAF50", "000000")
        case .brb:
            return Self(
                themeCode: theme.rawValue,
                team0Hex: "000000", team1Hex: "000000", centerHex: "000000",
                team0TextHex: "FF3B30", team1TextHex: "007AFF", centerTextHex: "4CAF50",
                foregroundHex: "FFFFFF", backgroundHex: "000000", autoContrast: false
            )
        case .wrb:
            return Self(
                themeCode: theme.rawValue,
                team0Hex: "FFFFFF", team1Hex: "FFFFFF", centerHex: "FFFFFF",
                team0TextHex: "FF3B30", team1TextHex: "007AFF", centerTextHex: "4CAF50",
                foregroundHex: "111111", backgroundHex: "FFFFFF", autoContrast: false
            )
        case .ddzClassic, .ddzProDark, .ddzElectronic, .ddzRetro, .ddzBrb, .ddzWrb:
            return legacyFlatDefault(theme: .defaultTheme)
        }
        return Self(
            themeCode: theme.rawValue,
            team0Hex: panels.0,
            team1Hex: panels.1,
            centerHex: panels.2,
            team0TextHex: panels.3,
            team1TextHex: panels.3,
            centerTextHex: panels.3,
            foregroundHex: panels.3,
            backgroundHex: panels.4,
            autoContrast: true
        )
    }

    /// 1:1 对齐安卓 defaultScoreboardStyleProfileV2（通用双侧项目）：
    /// V2 panels（左右槽位）+ 每槽位文字色 + 渲染键并集（brb/wrb）。
    private static func genericDefault(
        theme: ScoreboardTheme,
        capabilities: ScoreboardStyleEditCapabilities
    ) -> Self {
        // ddz_* 主题码不属于通用项目，回落 default（对齐安卓 SUPPORTED_SCOREBOARD_THEMES 校验）。
        let normalizedTheme: ScoreboardTheme = theme.isDoudizhuTheme ? .defaultTheme : theme
        let isBrbWrb = normalizedTheme == .brb || normalizedTheme == .wrb
        let leftPanel: String
        let rightPanel: String
        switch normalizedTheme {
        case .wrb:
            leftPanel = "FFFFFF"; rightPanel = "FFFFFF"
        case .brb:
            leftPanel = "000000"; rightPanel = "000000"
        default:
            leftPanel = normalizedTheme.leftPanelHex
            rightPanel = normalizedTheme.rightPanelHex
        }

        let slotTextColors = genericSlotTextColors(normalizedTheme, slotKeys: capabilities.slotKeys)
        // wrb/brb：可编辑键与渲染键的并集全部 MANUAL 红/蓝，避免白底回退白字不可见
        // （对齐安卓 brbWrbProfileElements + BRB_WRB_DISPLAY_ELEMENT_KEYS）。
        var elementKeys = capabilities.elementKeys
        if isBrbWrb {
            for key in [ScoreboardStyleElementKeyV2.teamName, .playerName, .mainScore, .gameScore, .setScore, .setGameScore]
            where !elementKeys.contains(key) {
                elementKeys.append(key)
            }
        }
        let elements = elementKeys.map { key in
            ScoreboardStyleElementV2(elementKey: key, textColors: slotTextColors)
        }

        var profile = Self(
            themeCode: normalizedTheme.rawValue,
            team0Hex: leftPanel,
            team1Hex: rightPanel,
            centerHex: normalizedTheme.centerPanelHex,
            team0TextHex: "FFFFFF",
            team1TextHex: "FFFFFF",
            centerTextHex: "FFFFFF",
            foregroundHex: normalizedTheme.foregroundHex,
            backgroundHex: normalizedTheme.backgroundHex,
            autoContrast: !isBrbWrb
        )
        profile.panels = [
            ScoreboardStylePanelV2(slotKey: .sideLeft, backgroundColorHex: leftPanel),
            ScoreboardStylePanelV2(slotKey: .sideRight, backgroundColorHex: rightPanel)
        ]
        profile.elements = elements
        profile.serverIndicatorColorHex = "30D158"
        profile.mirrorFlatTextFromElements()
        return profile
    }

    /// 通用主题的每槽位文字色（对齐安卓 brbWrbTextColors）：
    /// pro_dark 全槽位固定白字；brb/wrb 左红右蓝；其余 AUTO 自动对比。
    private static func genericSlotTextColors(
        _ theme: ScoreboardTheme,
        slotKeys: [ScoreboardStyleSlotKeyV2]
    ) -> [ScoreboardStyleTextColorV2] {
        if theme == .proDark {
            return slotKeys.map {
                ScoreboardStyleTextColorV2(slotKey: $0, colorMode: .manual, colorHex: "FFFFFF")
            }
        }
        if theme == .brb || theme == .wrb {
            return slotKeys.map {
                ScoreboardStyleTextColorV2(
                    slotKey: $0,
                    colorMode: .manual,
                    colorHex: $0 == .sideLeft ? "FF0000" : "1E5BFF"
                )
            }
        }
        return slotKeys.map {
            ScoreboardStyleTextColorV2(slotKey: $0, colorMode: .auto, colorHex: "FFFFFF")
        }
    }

    /// 1:1 对齐安卓 defaultDoudizhuStyleProfileV2：三面板（左/中/右）+ 每槽位文字色。
    private static func doudizhuDefault(
        theme: ScoreboardTheme,
        capabilities: ScoreboardStyleEditCapabilities
    ) -> Self {
        let normalizedTheme = ScoreboardTheme.doudizhuNormalized(theme.rawValue)
        let leftPanel = normalizedTheme.leftPanelHex
        let centerPanel = normalizedTheme.centerPanelHex
        let rightPanel = normalizedTheme.rightPanelHex

        var profile = Self(
            themeCode: normalizedTheme.rawValue,
            team0Hex: leftPanel,
            team1Hex: rightPanel,
            centerHex: centerPanel,
            team0TextHex: "FFFFFF",
            team1TextHex: "FFFFFF",
            centerTextHex: "FFFFFF",
            foregroundHex: normalizedTheme.foregroundHex,
            backgroundHex: normalizedTheme.backgroundHex,
            autoContrast: false
        )
        profile.panels = [
            ScoreboardStylePanelV2(slotKey: .sideLeft, backgroundColorHex: leftPanel),
            ScoreboardStylePanelV2(slotKey: .sideCenter, backgroundColorHex: centerPanel),
            ScoreboardStylePanelV2(slotKey: .sideRight, backgroundColorHex: rightPanel)
        ]
        profile.elements = capabilities.elementKeys.map { key in
            ScoreboardStyleElementV2(
                elementKey: key,
                textColors: capabilities.slotKeys.map { slot in
                    doudizhuSlotTextColor(normalizedTheme.rawValue, slot: slot, elementKey: key)
                }
            )
        }
        profile.serverIndicatorColorHex = "30D158"
        profile.mirrorFlatTextFromElements()
        return profile
    }

    /// 斗地主主题的每槽位文字色（对齐安卓 doudizhuSlotTextColor）：
    /// 专业深色固定白字，ddz_brb/ddz_wrb 左红/中绿/右蓝，ddz_retro 主分绿，其余走 AUTO。
    private static func doudizhuSlotTextColor(
        _ themeCode: String,
        slot: ScoreboardStyleSlotKeyV2,
        elementKey: ScoreboardStyleElementKeyV2
    ) -> ScoreboardStyleTextColorV2 {
        let manual: Bool
        switch themeCode {
        case "ddz_classic":
            manual = slot == .sideCenter && (elementKey == .teamName || elementKey == .mainScore)
        case "ddz_pro_dark", "ddz_brb", "ddz_wrb":
            manual = elementKey == .teamName || elementKey == .mainScore
        case "ddz_retro":
            manual = elementKey == .mainScore
        default:
            manual = false
        }
        guard manual else {
            return ScoreboardStyleTextColorV2(slotKey: slot, colorMode: .auto, colorHex: "FFFFFF")
        }
        let color: String
        switch themeCode {
        case "ddz_classic", "ddz_pro_dark":
            color = "FFFFFF"
        case "ddz_retro":
            color = "4CAF50"
        case "ddz_wrb":
            switch slot {
            case .sideLeft: color = "FF0000"
            case .sideCenter: color = "1B5E20"
            default: color = "1E5BFF"
            }
        default: // ddz_brb
            switch slot {
            case .sideLeft: color = "FF0000"
            case .sideCenter: color = "34C759"
            default: color = "1E5BFF"
            }
        }
        return ScoreboardStyleTextColorV2(slotKey: slot, colorMode: .manual, colorHex: color)
    }

    private enum CodingKeys: String, CodingKey {
        case themeCode, team0Hex, team1Hex, centerHex
        case team0TextHex, team1TextHex, centerTextHex
        case foregroundHex, backgroundHex, autoContrast
        case panels, elements
        case serverIndicatorColorHex = "serverIndicatorColor"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        themeCode = try values.decodeIfPresent(String.self, forKey: .themeCode) ?? ScoreboardTheme.defaultTheme.rawValue
        team0Hex = try values.decode(String.self, forKey: .team0Hex)
        team1Hex = try values.decode(String.self, forKey: .team1Hex)
        centerHex = try values.decode(String.self, forKey: .centerHex)
        foregroundHex = try values.decodeIfPresent(String.self, forKey: .foregroundHex) ?? "FFFFFF"
        backgroundHex = try values.decodeIfPresent(String.self, forKey: .backgroundHex) ?? "000000"
        autoContrast = try values.decodeIfPresent(Bool.self, forKey: .autoContrast) ?? true
        team0TextHex = try values.decodeIfPresent(String.self, forKey: .team0TextHex) ?? foregroundHex
        team1TextHex = try values.decodeIfPresent(String.self, forKey: .team1TextHex) ?? foregroundHex
        centerTextHex = try values.decodeIfPresent(String.self, forKey: .centerTextHex) ?? foregroundHex
        panels = try values.decodeIfPresent([ScoreboardStylePanelV2].self, forKey: .panels)
        elements = try values.decodeIfPresent([ScoreboardStyleElementV2].self, forKey: .elements)
        serverIndicatorColorHex = try values.decodeIfPresent(String.self, forKey: .serverIndicatorColorHex)
    }

    init(
        themeCode: String,
        team0Hex: String,
        team1Hex: String,
        centerHex: String,
        team0TextHex: String,
        team1TextHex: String,
        centerTextHex: String,
        foregroundHex: String,
        backgroundHex: String,
        autoContrast: Bool,
        panels: [ScoreboardStylePanelV2]? = nil,
        elements: [ScoreboardStyleElementV2]? = nil,
        serverIndicatorColorHex: String? = nil
    ) {
        self.themeCode = themeCode
        self.team0Hex = team0Hex
        self.team1Hex = team1Hex
        self.centerHex = centerHex
        self.team0TextHex = team0TextHex
        self.team1TextHex = team1TextHex
        self.centerTextHex = centerTextHex
        self.foregroundHex = foregroundHex
        self.backgroundHex = backgroundHex
        self.autoContrast = autoContrast
        self.panels = panels
        self.elements = elements
        self.serverIndicatorColorHex = serverIndicatorColorHex
    }

    func color(for slot: ScoreboardStyleSlot) -> Color {
        switch slot {
        case .team0: return Color(hex: team0Hex)
        case .team1: return Color(hex: team1Hex)
        case .center: return Color(hex: centerHex)
        }
    }

    var foreground: Color { Color(hex: foregroundHex) }
    var background: Color { Color(hex: backgroundHex) }

    func textColor(for slot: ScoreboardStyleSlot) -> Color {
        Color(hex: resolvedTextHex(for: slot))
    }

    func resolvedTextHex(for slot: ScoreboardStyleSlot) -> String {
        let configured: String
        switch slot {
        case .team0: configured = team0TextHex
        case .team1: configured = team1TextHex
        case .center: configured = centerTextHex
        }
        guard autoContrast else { return configured }
        return resolvedAutoTextHex(forSlot: ScoreboardStyleSlotKeyV2.legacySlot(for: slot))
    }

    func panelHex(for slot: ScoreboardStyleSlot) -> String {
        switch slot {
        case .team0: team0Hex
        case .team1: team1Hex
        case .center: centerHex
        }
    }

    nonisolated static func normalizedHex(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard raw.count == 6, raw.allSatisfy({ $0.isHexDigit }) else { return nil }
        return raw.uppercased()
    }

    static func autoTextHex(for background: String) -> String {
        guard let hex = normalizedHex(background), let value = Int(hex, radix: 16) else { return "FFFFFF" }
        func linear(_ channel: Int) -> Double {
            let component = Double(channel) / 255
            return component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((value >> 16) & 0xFF)
            + 0.7152 * linear((value >> 8) & 0xFF)
            + 0.0722 * linear(value & 0xFF)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast > whiteContrast ? "111111" : "FFFFFF"
    }

    // MARK: V2 槽位化访问（编辑器/渲染桥接）

    /// 是否包含新编辑器写入的数据。
    var hasV2StyleData: Bool {
        panels != nil || elements != nil || serverIndicatorColorHex != nil
    }

    /// 面板背景：优先 V2 panels，缺失回落旧扁平字段。
    func slotBackgroundHex(_ slotKey: ScoreboardStyleSlotKeyV2) -> String {
        if let panel = panels?.first(where: { $0.slotKey == slotKey }) {
            return panel.backgroundColorHex
        }
        guard let legacy = slotKey.legacySlot else { return "000000" }
        return panelHex(for: legacy)
    }

    /// 自动对比文字色（1:1 对齐安卓 resolvedAutoTextColor）：
    /// pro_dark 系固定白字；default 主题左右面板等于主题基色时固定白字
    /// （纯红/纯蓝上 WCAG 数学会误选黑色，与主题设计不符）。
    func resolvedAutoTextHex(forSlot slotKey: ScoreboardStyleSlotKeyV2) -> String {
        let background = slotBackgroundHex(slotKey)
        if themeCode == "pro_dark" || themeCode == "ddz_pro_dark" {
            return "FFFFFF"
        }
        if themeCode == "default" {
            let defaultBackground: String?
            switch slotKey {
            case .sideLeft: defaultBackground = panels == nil ? "FF3B30" : ScoreboardTheme.defaultTheme.leftPanelHex
            case .sideRight: defaultBackground = ScoreboardTheme.defaultTheme.rightPanelHex
            case .sideCenter: defaultBackground = panels == nil ? "4CAF50" : nil
            default: defaultBackground = nil
            }
            if let defaultBackground,
               Self.normalizedHex(background) == Self.normalizedHex(defaultBackground) {
                return "FFFFFF"
            }
        }
        return Self.autoTextHex(for: background)
    }

    /// 用 mainScore 元素的解析结果镜像旧扁平文字字段（默认样式构造辅助）。
    mutating func mirrorFlatTextFromElements() {
        func flatText(_ slotKey: ScoreboardStyleSlotKeyV2) -> String? {
            guard let color = elements?.first(where: { $0.elementKey == .mainScore })?
                .textColors.first(where: { $0.slotKey == slotKey }) else {
                return nil
            }
            return color.colorMode == .manual ? color.colorHex : resolvedAutoTextHex(forSlot: slotKey)
        }
        if let value = flatText(.sideLeft) { team0TextHex = value }
        if let value = flatText(.sideRight) { team1TextHex = value }
        if let value = flatText(.sideCenter) { centerTextHex = value }
    }

    /// 元素文字色解析：元素 manual 色优先；auto/缺失回落旧扁平 auto 对比。
    func resolvedElementTextHex(
        _ elementKey: ScoreboardStyleElementKeyV2,
        slotKey: ScoreboardStyleSlotKeyV2
    ) -> String {
        if let entry = elements?.first(where: { $0.elementKey == elementKey }),
           let color = entry.textColors.first(where: { $0.slotKey == slotKey }) {
            switch color.colorMode {
            case .manual:
                return color.colorHex
            case .auto:
                return resolvedAutoTextHex(forSlot: slotKey)
            }
        }
        guard let legacy = slotKey.legacySlot else {
            return resolvedAutoTextHex(forSlot: slotKey)
        }
        return resolvedTextHex(for: legacy)
    }

    /// 指定元素在指定槽位是否有手动色（供投屏/同步端逐元素配色）。
    func elementHasManualColor(
        _ elementKey: ScoreboardStyleElementKeyV2,
        slotKey: ScoreboardStyleSlotKeyV2
    ) -> Bool {
        guard let color = elements?.first(where: { $0.elementKey == elementKey })?
            .textColors.first(where: { $0.slotKey == slotKey }) else {
            return false
        }
        return color.colorMode == .manual
    }

    /// 设置面板背景；同时镜像旧扁平字段，保证未切换的旧渲染路径立即生效。
    func withPanelBackground(_ hex: String, for slotKey: ScoreboardStyleSlotKeyV2) -> Self {
        var copy = self
        let normalized = Self.normalizedHex(hex) ?? "FFFFFF"
        var list = copy.panels ?? []
        if let index = list.firstIndex(where: { $0.slotKey == slotKey }) {
            list[index].backgroundColorHex = normalized
        } else {
            list.append(ScoreboardStylePanelV2(slotKey: slotKey, backgroundColorHex: normalized))
        }
        copy.panels = list
        switch slotKey.legacySlot {
        case .team0: copy.team0Hex = normalized
        case .team1: copy.team1Hex = normalized
        case .center: copy.centerHex = normalized
        case .none: break
        }
        return copy
    }

    /// 设置元素在槽位上的文字颜色。
    func withElementTextColor(
        _ elementKey: ScoreboardStyleElementKeyV2,
        slotKey: ScoreboardStyleSlotKeyV2,
        mode: ScoreboardStyleColorModeV2,
        colorHex: String
    ) -> Self {
        var copy = self
        let normalized = Self.normalizedHex(colorHex) ?? "FFFFFF"
        var list = copy.elements ?? []
        let newColor = ScoreboardStyleTextColorV2(slotKey: slotKey, colorMode: mode, colorHex: normalized)
        guard let index = list.firstIndex(where: { $0.elementKey == elementKey }) else {
            list.append(ScoreboardStyleElementV2(elementKey: elementKey, textColors: [newColor]))
            copy.elements = list
            return copy
        }
        var colors = list[index].textColors
        if let colorIndex = colors.firstIndex(where: { $0.slotKey == slotKey }) {
            colors[colorIndex] = newColor
        } else {
            colors.append(newColor)
        }
        list[index].textColors = colors
        copy.elements = list
        return copy
    }

    /// 把元素文字配置传播到同侧其余元素（对齐安卓 applyTextColorToSameSide）。
    func applyingTextColorToSameSide(
        elementKey: ScoreboardStyleElementKeyV2,
        slotKey: ScoreboardStyleSlotKeyV2,
        capabilities: ScoreboardStyleEditCapabilities
    ) -> Self {
        guard let source = elements?.first(where: { $0.elementKey == elementKey })?
            .textColors.first(where: { $0.slotKey == slotKey }) else {
            return self
        }
        var copy = self
        for key in capabilities.sideElementKeys where key != elementKey {
            copy = copy.withElementTextColor(
                key,
                slotKey: slotKey,
                mode: source.colorMode,
                colorHex: source.colorHex
            )
        }
        return copy
    }

    /// 归一化：丢弃非法色值/空配置（保存前调用，对齐安卓 normalizeScoreboardStyleProfileV2）。
    func normalized() -> Self {
        var copy = self
        if var list = copy.panels {
            list = list.compactMap { panel in
                guard let hex = Self.normalizedHex(panel.backgroundColorHex) else { return nil }
                var cleaned = panel
                cleaned.backgroundColorHex = hex
                return cleaned
            }
            copy.panels = list.isEmpty ? nil : list
        }
        if var list = copy.elements {
            list = list.compactMap { entry in
                var cleaned = entry
                cleaned.textColors = entry.textColors.compactMap { color in
                    guard let hex = Self.normalizedHex(color.colorHex) else { return nil }
                    var cleanedColor = color
                    cleanedColor.colorHex = hex
                    return cleanedColor
                }
                return cleaned.textColors.isEmpty ? nil : cleaned
            }
            copy.elements = list.isEmpty ? nil : list
        }
        if let indicator = copy.serverIndicatorColorHex {
            copy.serverIndicatorColorHex = Self.normalizedHex(indicator)
        }
        return copy
    }
}

nonisolated enum ScoreboardStyleSlot: String, Codable, Sendable {
    case team0
    case team1
    case center
}

// MARK: - V2 槽位化样式模型（对齐安卓 ScoreboardStyleV2.kt）

/// camelCase ↔ snake_case（sideLeft ↔ side_left），兼容安卓 JSON 双写法。
private extension String {
    var snakeCased: String {
        map { $0.isUppercase ? "_\($0.lowercased())" : String($0) }.joined()
    }

    var camelCased: String {
        let parts = split(separator: "_", omittingEmptySubsequences: true)
        guard let first = parts.first else { return self }
        return parts.dropFirst().reduce(String(first)) {
            $0 + $1.prefix(1).uppercased() + $1.dropFirst()
        }
    }
}

/// 视觉槽位：双侧 + 中间（斗地主等）+ 多人布局 player_N。字符串与安卓互通。
nonisolated enum ScoreboardStyleSlotKeyV2: String, Codable, Sendable, CaseIterable {
    case sideLeft = "side_left"
    case sideCenter = "side_center"
    case sideRight = "side_right"
    case player0 = "player_0"
    case player1 = "player_1"
    case player2 = "player_2"
    case player3 = "player_3"
    case player4 = "player_4"
    case player5 = "player_5"
    case player6 = "player_6"
    case player7 = "player_7"
    case player8 = "player_8"

    /// 兼容安卓 camelCase / snake_case 双写法（sideLeft ↔ side_left）。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let value = Self.flexible(raw) {
            self = value
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown style slot key: \(raw)"
            ))
        }
    }

    nonisolated static func flexible(_ raw: String) -> Self? {
        if let value = Self(rawValue: raw) { return value }
        return Self(rawValue: raw.snakeCased)
    }

    /// 双侧槽位到既有 ScoreboardStyleSlot 的映射（渲染兼容旧扁平字段）。
    var legacySlot: ScoreboardStyleSlot? {
        switch self {
        case .sideLeft: return .team0
        case .sideRight: return .team1
        case .sideCenter: return .center
        default: return nil
        }
    }

    static func legacySlot(for slot: ScoreboardStyleSlot) -> Self {
        switch slot {
        case .team0: return .sideLeft
        case .team1: return .sideRight
        case .center: return .sideCenter
        }
    }
}

/// 可定制文字元素（对齐安卓 ScoreboardStyleElementKey）。
nonisolated enum ScoreboardStyleElementKeyV2: String, Codable, Sendable, CaseIterable {
    case matchTitle
    case teamName
    case playerName
    case mainScore
    case setScore
    case gameScore
    case setGameScore

    /// 兼容安卓 snake_case JSON（main_score ↔ mainScore）。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let value = Self(rawValue: raw) {
            self = value
        } else if let value = Self(rawValue: raw.camelCased) {
            self = value
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown style element key: \(raw)"
            ))
        }
    }
}

nonisolated enum ScoreboardStyleColorModeV2: String, Codable, Sendable {
    case auto
    case manual
}

/// 某元素在某个槽位上的文字颜色配置。
nonisolated struct ScoreboardStyleTextColorV2: Codable, Equatable, Sendable {
    var slotKey: ScoreboardStyleSlotKeyV2
    var colorMode: ScoreboardStyleColorModeV2
    /// colorMode == manual 时生效（不带 # 的 6 位大写 hex）。
    var colorHex: String

    init(slotKey: ScoreboardStyleSlotKeyV2, colorMode: ScoreboardStyleColorModeV2, colorHex: String) {
        self.slotKey = slotKey
        self.colorMode = colorMode
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey {
        case slotKey
        case colorMode
        case colorHex
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        slotKey = (try? values.decode(ScoreboardStyleSlotKeyV2.self, forKey: .slotKey)) ?? .sideLeft
        colorMode = (try? values.decode(ScoreboardStyleColorModeV2.self, forKey: .colorMode)) ?? .auto
        // 非法色值保留原样，交由 normalized() 统一清洗（对齐安卓 normalize 行为）。
        colorHex = (try? values.decodeIfPresent(String.self, forKey: .colorHex)) ?? "FFFFFF"
    }
}

nonisolated struct ScoreboardStylePanelV2: Codable, Equatable, Sendable {
    var slotKey: ScoreboardStyleSlotKeyV2
    var backgroundColorHex: String

    private enum CodingKeys: String, CodingKey {
        case slotKey
        case backgroundColorHex = "backgroundColor"
    }
}

nonisolated struct ScoreboardStyleElementV2: Codable, Equatable, Sendable {
    var elementKey: ScoreboardStyleElementKeyV2
    var textColors: [ScoreboardStyleTextColorV2]
}

/// 编辑能力（对齐安卓 ScoreboardStyleEditCapabilities）：按项目声明可编辑元素/槽位。
nonisolated struct ScoreboardStyleEditCapabilities: Sendable, Equatable {
    var elementKeys: [ScoreboardStyleElementKeyV2]
    var slotKeys: [ScoreboardStyleSlotKeyV2]
    var supportsServerIndicator: Bool
    var supportsTheme: Bool
    var supportsFont: Bool
    /// 跨槽位全局元素（如斯诺克 matchTitle），取色/传播时同时写左右。
    var globalElementKeys: Set<ScoreboardStyleElementKeyV2>

    var hasEditableBackground: Bool { !slotKeys.isEmpty }
    var sideElementKeys: [ScoreboardStyleElementKeyV2] {
        elementKeys.filter { !globalElementKeys.contains($0) }
    }
    func canEditBackground(_ slotKey: ScoreboardStyleSlotKeyV2) -> Bool {
        slotKeys.contains(slotKey)
    }

    static func capabilities(
        elementKeys: [ScoreboardStyleElementKeyV2],
        slotKeys: [ScoreboardStyleSlotKeyV2] = [.sideLeft, .sideRight],
        supportsServerIndicator: Bool = true,
        supportsTheme: Bool = true,
        supportsFont: Bool = true,
        globalElementKeys: Set<ScoreboardStyleElementKeyV2> = []
    ) -> Self {
        Self(
            elementKeys: elementKeys,
            slotKeys: slotKeys,
            supportsServerIndicator: supportsServerIndicator,
            supportsTheme: supportsTheme,
            supportsFont: supportsFont,
            globalElementKeys: globalElementKeys
        )
    }
}

/// 能力注册表：key = ScoreboardStyleID rawValue（单双打各自独立），1:1 对齐安卓 ScoreboardStyleV2Registry。
nonisolated enum ScoreboardStyleV2Registry {
    private static let setBased: [ScoreboardStyleElementKeyV2] = [.teamName, .mainScore, .setScore]
    private static let plain: [ScoreboardStyleElementKeyV2] = [.teamName, .mainScore]
    private static let doubles: [ScoreboardStyleElementKeyV2] = [.playerName, .mainScore, .setGameScore]
    private static let tennis: [ScoreboardStyleElementKeyV2] = [.teamName, .mainScore, .gameScore, .setScore]
    private static let flexibleSinglesAndDoubles: [ScoreboardStyleElementKeyV2] =
        [.teamName, .playerName, .mainScore, .gameScore, .setScore, .setGameScore]
    private static let setBasedOrDoubles: [ScoreboardStyleElementKeyV2] =
        [.teamName, .playerName, .mainScore, .setScore, .setGameScore]

    private static let capabilities: [String: ScoreboardStyleEditCapabilities] = {
        var map: [String: ScoreboardStyleEditCapabilities] = [:]
        for identifier in [
            "pingpong", "badminton", "volleyball", "air_volleyball",
            "beach_volleyball", "squash", "pickleball", "foosball"
        ] {
            map[identifier] = .capabilities(elementKeys: setBased)
        }
        map["shuttlecock"] = .capabilities(elementKeys: setBasedOrDoubles, supportsServerIndicator: false)
        map["doudizhu"] = .capabilities(
            elementKeys: plain,
            slotKeys: [.sideLeft, .sideCenter, .sideRight],
            supportsServerIndicator: false
        )
        for identifier in [
            "pingpong_doubles", "badminton_doubles", "tennis_doubles",
            "pickleball_doubles", "padel", "foosball_doubles"
        ] {
            map[identifier] = .capabilities(elementKeys: doubles)
        }
        map["soft_tennis"] = .capabilities(elementKeys: flexibleSinglesAndDoubles)
        map["tennis"] = .capabilities(elementKeys: tennis)
        map["archery_dual"] = .capabilities(elementKeys: setBased)
        map["snooker"] = .capabilities(
            elementKeys: [.matchTitle] + setBased,
            globalElementKeys: [.matchTitle]
        )
        map["guandan"] = .capabilities(elementKeys: plain)
        map["shengji"] = .capabilities(elementKeys: plain)
        for identifier in [
            "billiards", "football", "football_5v5", "boxing", "eight_ball", "simple_score"
        ] {
            map[identifier] = .capabilities(elementKeys: plain, supportsServerIndicator: false)
        }
        return map
    }()

    static func capabilities(for styleID: ScoreboardStyleID) -> ScoreboardStyleEditCapabilities? {
        capabilities[styleID.rawValue]
    }

    static func isEnabled(_ styleID: ScoreboardStyleID) -> Bool {
        capabilities[styleID.rawValue] != nil
    }

    static var enabledStyleIDs: Set<ScoreboardStyleID> {
        Set(capabilities.keys.map(ScoreboardStyleID.init(rawValue:)))
    }
}

/// 颜色数学（对齐安卓 ScoreboardStyleColorMath.kt）。
nonisolated enum ScoreboardStyleColorMath {
    /// WCAG 对比度（0...21）。
    static func contrastRatio(_ hexA: String, _ hexB: String) -> Double {
        func luminance(_ hex: String) -> Double? {
            guard let value = ScoreboardStyleProfileV2.normalizedHex(hex).flatMap({ Int($0, radix: 16) }) else {
                return nil
            }
            func linear(_ channel: Int) -> Double {
                let component = Double(channel) / 255
                return component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear((value >> 16) & 0xFF)
                + 0.7152 * linear((value >> 8) & 0xFF)
                + 0.0722 * linear(value & 0xFF)
        }
        guard let la = luminance(hexA), let lb = luminance(hexB) else { return 1 }
        let lighter = max(la, lb), darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// 元素面板红字警示阈值（安卓 styleIsReadableTextColor）。
    static func isReadableTextColor(_ textHex: String, on backgroundHex: String) -> Bool {
        contrastRatio(textHex, backgroundHex) >= 3.0
    }

    struct HSV {
        var hue: Double // 0...360
        var saturation: Double // 0...1
        var value: Double // 0...1
    }

    static func hsvToHex(_ hsv: HSV) -> String {
        let h = (hsv.hue.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let s = min(max(hsv.saturation, 0), 1)
        let v = min(max(hsv.value, 0), 1)
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let rgb: [Double]
        switch h {
        case 0..<1: rgb = [c, x, 0]
        case 1..<2: rgb = [x, c, 0]
        case 2..<3: rgb = [0, c, x]
        case 3..<4: rgb = [0, x, c]
        case 4..<5: rgb = [x, 0, c]
        default: rgb = [c, 0, x]
        }
        let hex = rgb.map { String(Int(round(($0 + m) * 255)), radix: 16) }
            .map { $0.count == 1 ? "0" + $0 : $0 }
            .joined()
        return hex.uppercased()
    }

    static func colorToHsv(_ hex: String) -> HSV? {
        guard let value = ScoreboardStyleProfileV2.normalizedHex(hex).flatMap({ Int($0, radix: 16) }) else {
            return nil
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        let maxValue = max(r, g, b), minValue = min(r, g, b)
        let delta = maxValue - minValue
        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maxValue == r {
            hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxValue == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        return HSV(
            hue: hue < 0 ? hue + 360 : hue,
            saturation: maxValue == 0 ? 0 : delta / maxValue,
            value: maxValue
        )
    }

    /// 色轮坐标 → hex：中心白、边缘饱和，角度即色相。pointX/pointY 相对半径归一（-1...1）。
    static func colorWheelPointToHex(pointX: Double, pointY: Double) -> String {
        let distance = sqrt(pointX * pointX + pointY * pointY)
        let normalized = min(distance, 1)
        var hue = atan2(pointY, pointX) * 180 / .pi
        if hue < 0 { hue += 360 }
        return hsvToHex(HSV(hue: hue, saturation: normalized, value: 1))
    }

    /// 线性插值两个 hex（t = 0...1）。
    static func mixHex(_ from: String, _ to: String, t: Double) -> String? {
        guard let a = ScoreboardStyleProfileV2.normalizedHex(from).flatMap({ Int($0, radix: 16) }),
              let b = ScoreboardStyleProfileV2.normalizedHex(to).flatMap({ Int($0, radix: 16) }) else {
            return nil
        }
        let clamped = min(max(t, 0), 1)
        func mix(_ shift: Int) -> Int {
            let ca = Double((a >> shift) & 0xFF)
            let cb = Double((b >> shift) & 0xFF)
            return Int(round(ca + (cb - ca) * clamped))
        }
        let hex = String(max(min(mix(16), 255), 0), radix: 16).leftPaddedTo(2)
            + String(max(min(mix(8), 255), 0), radix: 16).leftPaddedTo(2)
            + String(max(min(mix(0), 255), 0), radix: 16).leftPaddedTo(2)
        return hex.uppercased()
    }
}

private extension String {
    /// "f" → "0f"，用于拼 RGB hex。
    func leftPaddedTo(_ length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}

struct ScoreboardStyleIdentity: Equatable, Sendable {
    let slot: ScoreboardStyleSlot

    static func forTeam(_ team: TeamID) -> Self {
        Self(slot: team == .team0 ? .team0 : .team1)
    }

    static let center = Self(slot: .center)
}

enum ScoreboardFont: String, CaseIterable, Identifiable, Codable, Sendable {
    case `default` = "default"
    case monospaced = "monospaced"
    case sevenSegment = "seven_segment"
    case sports = "sports"

    /// Persisted iOS names remain compatible; transport names follow Android/HarmonyOS.
    init?(displayCode: String) {
        switch displayCode {
        case "digital", "harmony_digit": self = .monospaced
        case "teko": self = .sports
        default:
            guard let font = Self(rawValue: displayCode) else { return nil }
            self = font
        }
    }

    var wireCode: String {
        switch self {
        case .monospaced: "digital"
        case .sports: "teko"
        default: rawValue
        }
    }

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .default:
            return NSLocalizedString("scoreboard_font_default", value: "默认", comment: "")
        case .monospaced:
            return NSLocalizedString("scoreboard_font_monospaced", value: "等宽数字", comment: "")
        case .sevenSegment:
            return NSLocalizedString("scoreboard_font_seven_segment", value: "LED数字", comment: "")
        case .sports:
            return NSLocalizedString("scoreboard_font_sports", value: "运动", comment: "")
        }
    }

    var postScriptName: String? {
        switch self {
        case .default: return nil
        case .monospaced: return "Menlo-Bold"
        case .sevenSegment: return "Segment7"
        case .sports: return "Teko-Light_SemiBold"
        }
    }

    func swiftUIFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        switch self {
        case .default:
            return .system(size: size, weight: weight)
        case .monospaced:
            return .system(size: size, weight: weight, design: .monospaced)
        case .sevenSegment, .sports:
            if let postScriptName, UIFont(name: postScriptName, size: size) != nil {
                return .custom(postScriptName, size: size)
            }
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

nonisolated struct ScoreboardStyleID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    nonisolated init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(gameType: GameType) {
        self.init(rawValue: gameType.canonicalScoreboardIdentifier)
    }

    nonisolated init(scoreCoreGameType: ScoreCore.GameType) {
        self.init(rawValue: scoreCoreGameType.rawValue)
    }

    /// Launchable scoreboard entries. Timer tools intentionally do not
    /// participate in scoreboard typography storage.
    static let registeredEntryGameTypes: [GameType] = [
        .pingpong, .badminton, .shuttlecock, .squash, .tennis, .softTennis, .padel, .basketball, .basketballTraining, .threeBasketball,
        .football, .football5v5, .volleyball, .beachVolleyball, .airVolleyball,
        .archery, .boxing, .billiards, .eightBall, .nineBall, .snooker,
        .pickleball, .guandan, .doudizhu, .shengji, .uno, .foosball,
        .simpleScore, .multiScoreboard
    ]

    /// Includes the independent singles/doubles styles used by ScoreCore.
    static let registeredScoreboardStyles: Set<ScoreboardStyleID> = Set(
        ScoreCore.GameType.allCases.map(ScoreboardStyleID.init(scoreCoreGameType:))
    )
}

struct ScoreboardTypographyPreference: Codable, Equatable, Sendable {
    var font: ScoreboardFont
    var scoreMultiplier: Double
    var nameMultiplier: Double
    var secondaryMultiplier: Double
    var elementMultipliers: [String: Double]? = nil

    static func `default`(font: ScoreboardFont) -> ScoreboardTypographyPreference {
        ScoreboardTypographyPreference(
            font: font,
            scoreMultiplier: 1,
            nameMultiplier: 1,
            secondaryMultiplier: 1
        )
    }

    func multiplier(for metric: ScoreboardFontMetric) -> Double {
        switch metric {
        case .score: return scoreMultiplier
        case .name: return nameMultiplier
        case .secondary: return secondaryMultiplier
        }
    }

    mutating func setMultiplier(_ value: Double, for metric: ScoreboardFontMetric) {
        switch metric {
        case .score: scoreMultiplier = value
        case .name: nameMultiplier = value
        case .secondary: secondaryMultiplier = value
        }
    }

    func multiplier(for element: ScoreboardStyleElementKeyV2) -> Double {
        if let value = elementMultipliers?[element.rawValue] { return value }
        switch element {
        case .mainScore: return scoreMultiplier
        case .teamName, .playerName: return nameMultiplier
        case .setScore, .gameScore, .setGameScore, .matchTitle: return secondaryMultiplier
        }
    }

    var resolvedElementMultipliers: [String: Double] {
        Dictionary(uniqueKeysWithValues: ScoreboardStyleElementKeyV2.allCases.map { ($0.rawValue, multiplier(for: $0)) })
    }

    func resolved(for styleID: ScoreboardStyleID) -> ScoreboardTypographyPreference {
        var copy = self
        let keys = ScoreboardStyleV2Registry.capabilities(for: styleID)?.elementKeys ?? []
        copy.scoreMultiplier = multiplier(for: ScoreboardStyleElementKeyV2.mainScore)
        copy.nameMultiplier = multiplier(for: keys.contains(.playerName) && !keys.contains(.teamName) ? .playerName : .teamName)
        let secondary: ScoreboardStyleElementKeyV2 = keys.contains(.gameScore)
            ? .gameScore : (keys.contains(.setGameScore) && !keys.contains(.setScore) ? .setGameScore : .setScore)
        copy.secondaryMultiplier = multiplier(for: secondary)
        return copy
    }

    func normalized(isLargeScreen: Bool) -> ScoreboardTypographyPreference {
        var copy = self
        for metric in ScoreboardFontMetric.allCases {
            copy.setMultiplier(
                ScoreboardFontSizePolicy.normalized(multiplier(for: metric), isLargeScreen: isLargeScreen),
                for: metric
            )
        }
        copy.elementMultipliers = elementMultipliers?.mapValues {
            ScoreboardFontSizePolicy.normalized($0, isLargeScreen: isLargeScreen)
        }
        return copy
    }
}

@Observable
final class ScoreboardTypographySession {
    private(set) var styleID: ScoreboardStyleID
    private(set) var appliedPreference: ScoreboardTypographyPreference
    private(set) var previewPreference: ScoreboardTypographyPreference?
    private var resetRequested = false

    init(
        styleID: ScoreboardStyleID,
        preferences: PreferencesManager = .shared
    ) {
        self.styleID = styleID
        self.appliedPreference = preferences.scoreboardTypography(for: styleID)
    }

    var effectivePreference: ScoreboardTypographyPreference {
        (previewPreference ?? appliedPreference).resolved(for: styleID)
    }

    func switchStyleID(
        _ newStyleID: ScoreboardStyleID,
        preferences: PreferencesManager = .shared
    ) {
        guard styleID != newStyleID else {
            reload(preferences: preferences)
            return
        }
        styleID = newStyleID
        previewPreference = nil
        resetRequested = false
        appliedPreference = preferences.scoreboardTypography(for: newStyleID)
    }

    func reload(preferences: PreferencesManager = .shared) {
        guard previewPreference == nil else { return }
        appliedPreference = preferences.scoreboardTypography(for: styleID)
    }

    func beginPreview() {
        guard previewPreference == nil else { return }
        previewPreference = appliedPreference
        resetRequested = false
    }

    func updateFont(_ font: ScoreboardFont) {
        beginPreview()
        previewPreference?.font = font
        resetRequested = false
    }

    func updateMultiplier(_ value: Double, for metric: ScoreboardFontMetric, isLargeScreen: Bool) {
        beginPreview()
        previewPreference?.setMultiplier(
            ScoreboardFontSizePolicy.normalized(value, isLargeScreen: isLargeScreen),
            for: metric
        )
        resetRequested = false
    }

    func updateElementMultiplier(_ value: Double, for element: ScoreboardStyleElementKeyV2, isLargeScreen: Bool) {
        beginPreview()
        guard var preview = previewPreference else { return }
        if preview.elementMultipliers == nil {
            preview.elementMultipliers = preview.resolvedElementMultipliers
        }
        preview.elementMultipliers?[element.rawValue] = ScoreboardFontSizePolicy.normalized(value, isLargeScreen: isLargeScreen)
        previewPreference = preview
        resetRequested = false
    }

    func resetPreview(preferences: PreferencesManager = .shared) {
        previewPreference = .default(font: preferences.resolvedDefaultScoreboardFont)
        resetRequested = true
    }

    func cancelPreview() {
        previewPreference = nil
        resetRequested = false
    }

    func applyPreview(preferences: PreferencesManager = .shared) {
        guard let previewPreference else { return }
        if resetRequested {
            preferences.resetScoreboardTypography(for: styleID)
            appliedPreference = .default(font: preferences.resolvedDefaultScoreboardFont)
        } else {
            let normalized = previewPreference.normalized(isLargeScreen: Theme.usesPadLayout)
            preferences.setScoreboardTypography(normalized, for: styleID)
            appliedPreference = normalized
        }
        self.previewPreference = nil
        resetRequested = false
    }
}

struct ScoreboardAppearanceSnapshot: Equatable {
    let theme: ScoreboardTheme
    let styleProfileV2: ScoreboardStyleProfileV2
    let font: ScoreboardFont
    let keepScreenOn: Bool
    let immersiveMode: Bool
    let touchGuard: Bool
    let doubleTapSubtract: Bool

    static func current(
        styleID: ScoreboardStyleID? = nil,
        _ preferences: PreferencesManager = .shared
    ) -> ScoreboardAppearanceSnapshot {
        let resolvedStyleID = styleID ?? ScoreboardStyleID(rawValue: "default")
        let font = styleID.map { preferences.scoreboardTypography(for: $0).font }
            ?? preferences.resolvedDefaultScoreboardFont
        let profile = preferences.scoreboardStyleProfileV2(for: resolvedStyleID)
        let profileTheme = ScoreboardTheme(rawValue: profile.themeCode)
        return ScoreboardAppearanceSnapshot(
            theme: profileTheme ?? ScoreboardTheme(rawValue: preferences.scoreboardTheme) ?? .defaultTheme,
            styleProfileV2: profile,
            font: font,
            keepScreenOn: preferences.keepScoreboardScreenOn,
            // Immersive scoreboards remain a HarmonyOS-only capability.
            immersiveMode: false,
            touchGuard: preferences.scoreboardTouchGuardEnabled,
            doubleTapSubtract: preferences.scoreboardDoubleTapSubtractEnabled
        )
    }

    var palette: ScoreboardPalette {
        theme.palette.applying(styleProfileV2)
    }

    // MARK: V2 渲染取色（对齐安卓渲染读 profile 槽位化字段）

    /// 元素级文字色：V2 元素配置优先；缺失时回落面板级解析色（含 auto 对比）。
    /// slotKey 为逻辑侧（.sideLeft/.sideRight），渲染端负责换边重映射。
    func elementForeground(
        _ elementKey: ScoreboardStyleElementKeyV2,
        slotKey: ScoreboardStyleSlotKeyV2
    ) -> Color {
        Color(hex: styleProfileV2.resolvedElementTextHex(elementKey, slotKey: slotKey))
    }

    /// 元素是否配置过 V2 文字色。未配置时渲染端应保持旧默认（如 70% 透明度）。
    func hasElementColor(
        _ elementKey: ScoreboardStyleElementKeyV2,
        slotKey: ScoreboardStyleSlotKeyV2
    ) -> Bool {
        styleProfileV2.elements?.first(where: { $0.elementKey == elementKey })?
            .textColors.first(where: { $0.slotKey == slotKey }) != nil
    }

    /// 发球指示器颜色（未配置时回落默认绿 30D158）。
    var serverIndicatorColor: Color {
        Color(hex: styleProfileV2.serverIndicatorColorHex ?? "30D158")
    }
}

enum ScoreboardFontMetric: String, CaseIterable, Sendable {
    case score
    case name
    case secondary
}

enum ScoreboardFontSizePolicy {
    static let step = 0.05

    static func range(isLargeScreen: Bool) -> ClosedRange<Double> {
        isLargeScreen ? 0.7 ... 1.5 : 0.8 ... 1.5
    }

    static func normalized(_ value: Double, isLargeScreen: Bool) -> Double {
        let limits = range(isLargeScreen: isLargeScreen)
        let stepped = (value / step).rounded() * step
        return min(limits.upperBound, max(limits.lowerBound, stepped))
    }
}

struct ScoreboardDisplaySettingsView: View {
    @Environment(\.scoreboardMatchClockSession) private var matchClockSession
    let session: ScoreboardTypographySession
    let metrics: [ScoreboardFontMetric]
    var onClose: () -> Void
    @State private var matchTimeDraft = false

    private var isLargeScreen: Bool {
        Theme.usesPadLayout
    }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = Theme.scoreboardDisplaySettingsPanelWidth(
                availableWidth: proxy.size.width
            )
            // Transparent left tap-to-dismiss + semi-transparent right side panel.
            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: cancel)

                panelContent
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.black.opacity(0.68))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear {
            session.beginPreview()
            matchTimeDraft = matchClockSession?.isVisible ?? false
        }
        .onDisappear {
            // Applying clears the preview first; every other dismissal path is
            // a cancellation and must restore the applied preference.
            if session.previewPreference != nil {
                session.cancelPreview()
            }
        }
    }

    private var panelContent: some View {
        VStack(spacing: 18) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if matchClockSession != nil {
                        matchTimeSection
                    }
                    fontSection
                    fontSizeSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button(action: cancel) {
                    Text(NSLocalizedString("cancel", value: "取消", comment: ""))
                        .font(.system(size: isLargeScreen ? 20 : 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: isLargeScreen ? 56 : 48)
                        .background(Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: apply) {
                    Text(NSLocalizedString("apply", value: "应用", comment: ""))
                        .font(.system(size: isLargeScreen ? 20 : 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: isLargeScreen ? 56 : 48)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var matchTimeSection: some View {
        Toggle(isOn: $matchTimeDraft) {
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("show_match_time", value: "显示时间", comment: ""))
                    .font(.system(size: isLargeScreen ? 18 : 15, weight: .medium))
                Text(NSLocalizedString(
                    "scoreboard_match_time_this_game_only",
                    value: "仅影响本局；下次开局仍使用项目设置。",
                    comment: ""
                ))
                .font(.system(size: isLargeScreen ? 14 : 12))
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .tint(Theme.primary)
        .accessibilityIdentifier("scoreboard_match_time_toggle")
    }

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("scoreboard_font", value: "比分字体", comment: ""))
                .font(.system(size: isLargeScreen ? 20 : 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(ScoreboardFont.allCases) { font in
                    fontChip(font)
                }
            }
        }
    }

    private func fontChip(_ font: ScoreboardFont) -> some View {
        let selected = session.effectivePreference.font == font
        return Button {
            session.updateFont(font)
        } label: {
            VStack(spacing: 4) {
                Text("123")
                    .font(font.swiftUIFont(size: isLargeScreen ? 22 : 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(font.localizedTitle)
                    .font(.system(size: isLargeScreen ? 14 : 12))
                    .foregroundStyle(selected ? .white : .white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: isLargeScreen ? 78 : 66)
            .background(selected ? Color(hex: "34C759").opacity(0.28) : Color.white.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Theme.primary : Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("scoreboard_font_size", value: "字号调节", comment: ""))
                .font(.system(size: isLargeScreen ? 20 : 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                ForEach(metrics, id: \.rawValue) { metric in
                    fontSizeRow(metric)
                }
            }

            Button {
                session.resetPreview()
            } label: {
                Text(NSLocalizedString("scoreboard_font_size_reset", value: "恢复默认", comment: ""))
                    .font(.system(size: isLargeScreen ? 18 : 16, weight: .medium))
                    // HOS app.color.app_secondary_light
                    .foregroundStyle(Color(hex: "F7C948"))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .padding(.bottom, 2)
        }
    }

    private func fontSizeRow(_ metric: ScoreboardFontMetric) -> some View {
        let value = session.effectivePreference.multiplier(for: metric)
        return HStack(spacing: 12) {
            Text(metric.localizedTitle(styleID: session.styleID))
                .font(.system(size: isLargeScreen ? 20 : 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            adjustButton(systemName: "minus") {
                updateMetric(metric, delta: -ScoreboardFontSizePolicy.step)
            }

            Text(formatMultiplier(value))
                .font(.system(size: isLargeScreen ? 22 : 17, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: isLargeScreen ? 72 : 54)

            adjustButton(systemName: "plus") {
                updateMetric(metric, delta: ScoreboardFontSizePolicy.step)
            }
        }
        .frame(height: isLargeScreen ? 68 : 56)
        .padding(.horizontal, 4)
    }

    private func adjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        let size: CGFloat = isLargeScreen ? 52 : 40
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isLargeScreen ? 20 : 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func updateMetric(_ metric: ScoreboardFontMetric, delta: Double) {
        let current = session.effectivePreference.multiplier(for: metric)
        session.updateMultiplier(current + delta, for: metric, isLargeScreen: isLargeScreen)
    }

    private func formatMultiplier(_ value: Double) -> String {
        // Align with HOS formatScoreboardFontSizeMultiplier.
        let normalized = (value / ScoreboardFontSizePolicy.step).rounded() * ScoreboardFontSizePolicy.step
        let fractionDigits = Int(round(normalized * 100)) % 10 == 0 ? 1 : 2
        return normalized.formatted(.number.precision(.fractionLength(fractionDigits))) + "×"
    }

    private func cancel() {
        session.cancelPreview()
        onClose()
    }

    private func apply() {
        if let matchClockSession {
            matchClockSession.isVisible = matchTimeDraft
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        session.applyPreview()
        onClose()
    }
}

enum OfficialBreakOverlayPresentation {
    static func title(for state: OfficialBreakState) -> String {
        if state.phase == .preparation {
            return NSLocalizedString("official_break_prepare", value: "准备", comment: "")
        }
        if let title = state.title, !title.isEmpty {
            return title
        }
        switch state.kind {
        case .midGame:
            return NSLocalizedString("official_break_mid_game", value: "局中休息", comment: "")
        case .gameBreak:
            return NSLocalizedString("official_break_game", value: "局间休息", comment: "")
        case .setBreak:
            return NSLocalizedString("official_break_set", value: "盘间休息", comment: "")
        case .changeover:
            return NSLocalizedString("official_break_changeover", value: "换边休息", comment: "")
        case .timeout:
            return NSLocalizedString("timeout", value: "暂停", comment: "")
        case .medical:
            return NSLocalizedString("medical_timeout", value: "医疗暂停", comment: "")
        }
    }

    static func showsUndo(for _: OfficialBreakState) -> Bool { true }
}

struct OfficialBreakOverlay: View {
    @Binding var session: OfficialBreakSession
    var onComplete: (OfficialBreakAfterAction) -> Void
    var onCancel: () -> Void = {}
    var onVoiceCue: (OfficialBreakCue) -> Void = { _ in }
    @State private var tick = Date()
    @State private var completionDelivered = false
    @State private var emittedVoiceCues: Set<OfficialBreakCue> = []

    var body: some View {
        ZStack {
            if let state = session.state {
                // 1:1 对齐安卓 OfficialBreakPill：轻遮罩保持比分可见，深色圆角卡 + 绿色倒计时。
                ZStack {
                    Color.black.opacity(0.08).ignoresSafeArea()
                        .transition(.opacity)
                    officialBreakCard(state)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
                tick = now
                let previousRemaining = Int64((session.state?.remainingSeconds ?? 0) * 1_000)
                let completed = session.tick(nowMilliseconds: Int64(now.timeIntervalSince1970 * 1_000))
                if let current = session.state {
                    let currentRemaining = Int64(current.remainingSeconds * 1_000)
                    officialBreakCuesCrossed(
                        sport: current.sport,
                        previousRemainingMilliseconds: previousRemaining,
                        currentRemainingMilliseconds: currentRemaining
                    ).forEach(deliverVoiceCue)
                }
                if completed {
                    deliverVoiceCue(.complete)
                    completeOnce(state.afterAction)
                }
            }
            .onChange(of: state.startedWallClockMilliseconds) { _, _ in
                completionDelivered = false
                emittedVoiceCues = []
            }
        }
        }
        .animation(.easeInOut(duration: 0.2), value: session.state != nil)
    }

    private func officialBreakCard(_ state: OfficialBreakState) -> some View {
        let title = OfficialBreakOverlayPresentation.title(for: state)
        let titleLines = title.components(separatedBy: " · ")
        return VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(titleLines[0])
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if titleLines.count > 1 {
                    Text(titleLines.dropFirst().joined(separator: " · "))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            Text(String(format: "%02d:%02d", state.remainingSeconds / 60, state.remainingSeconds % 60))
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0x31 / 255, green: 0xD1 / 255, blue: 0x58 / 255))
            HStack(spacing: 8) {
                if OfficialBreakOverlayPresentation.showsUndo(for: state) {
                    Button(NSLocalizedString("undo", value: "撤销", comment: "")) {
                        if session.undo(), session.state == nil {
                            onCancel()
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .frame(minHeight: 36)
                    .background(Color.white.opacity(0.14), in: Capsule())
                }
                Button(NSLocalizedString("official_break_continue", value: "继续", comment: "")) {
                    let action = state.afterAction
                    deliverVoiceCue(.earlyResume)
                    session.skip()
                    completeOnce(action)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255))
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .frame(minHeight: 36)
                .background(Color.white.opacity(0.92), in: Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Color(red: 0x0C / 255, green: 0x0C / 255, blue: 0x0E / 255).opacity(0.8),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
    }

    private func completeOnce(_ action: OfficialBreakAfterAction) {
        guard !completionDelivered else { return }
        completionDelivered = true
        onComplete(action)
    }

    private func deliverVoiceCue(_ cue: OfficialBreakCue) {
        guard emittedVoiceCues.insert(cue).inserted else { return }
        onVoiceCue(cue)
    }
}

extension View {
    /// Harmony-style side panel overlay (not a system sheet).
    func scoreboardDisplaySettingsOverlay(
        isPresented: Binding<Bool>,
        session: ScoreboardTypographySession,
        metrics: [ScoreboardFontMetric]
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                ScoreboardDisplaySettingsView(session: session, metrics: metrics) {
                    isPresented.wrappedValue = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(300)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isPresented.wrappedValue)
    }
}

private extension ScoreboardFontMetric {
    func localizedTitle(styleID: ScoreboardStyleID) -> String {
        // 仅非样式编辑项目（篮球/3x3/九球/UNO/多分数板）会打开旧版字号面板。
        let isUnoOrMulti = styleID.rawValue == ScoreCore.GameType.uno.rawValue
            || styleID.rawValue == ScoreCore.GameType.multiScoreboard.rawValue
        switch self {
        case .score:
            if isUnoOrMulti {
                return NSLocalizedString("scoreboard_font_metric_main_score", value: "主分数", comment: "")
            }
            if usesTeamScorePanel(styleID) {
                return NSLocalizedString("scoreboard_font_metric_large_score", value: "大分数", comment: "")
            }
            return NSLocalizedString("scoreboard_font_metric_score", value: "主比分", comment: "")
        case .name:
            if isUnoOrMulti {
                return NSLocalizedString("scoreboard_font_metric_player_name", value: "选手名", comment: "")
            }
            if usesTeamScorePanel(styleID) {
                return NSLocalizedString("scoreboard_font_metric_team_name", value: "队名", comment: "")
            }
            return NSLocalizedString("scoreboard_font_metric_name", value: "名称", comment: "")
        case .secondary:
            switch styleID.rawValue {
            case ScoreCore.GameType.nineBall.rawValue:
                return NSLocalizedString(
                    "scoreboard_font_metric_nine_ball_secondary",
                    value: "追分详情",
                    comment: ""
                )
            default:
                return NSLocalizedString(
                    "scoreboard_font_metric_secondary",
                    value: "局分/盘分",
                    comment: ""
                )
            }
        }
    }

    /// 对齐安卓 fontSizePanelItems=TeamScore 的项目（篮球/3x3/九球）：队名 + 大分数。
    private func usesTeamScorePanel(_ styleID: ScoreboardStyleID) -> Bool {
        styleID.rawValue == ScoreCore.GameType.basketball.rawValue
            || styleID.rawValue == ScoreCore.GameType.threeBasketball.rawValue
            || styleID.rawValue == ScoreCore.GameType.nineBall.rawValue
    }
}

struct ImmersiveCornerRevealZones: View {
    let onReveal: () -> Void

    var body: some View {
        VStack {
            HStack {
                Spacer()
                revealButton
            }
            Spacer()
            HStack {
                revealButton
                Spacer()
                revealButton
            }
        }
        .padding(2)
    }

    private var revealButton: some View {
        Button(action: onReveal) {
            Color.clear.frame(width: 88, height: 88)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("scoreboard_show_controls", value: "显示计分板控制按钮", comment: ""))
    }
}
