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
        }
    }

    var palette: ScoreboardPalette {
        // Aligned with HOS scoreboardTheme.ts
        switch self {
        case .defaultTheme:
            return ScoreboardPalette(
                background: .black,
                left: Color(hex: "FF3B30"),
                right: Color(hex: "007AFF"),
                foreground: .white,
                secondary: .white.opacity(0.7),
                chrome: .black.opacity(0.28)
            )
        case .proDark:
            return ScoreboardPalette(
                background: .black,
                left: Color(hex: "972828"),
                right: Color(hex: "007AFF"),
                foreground: .white,
                secondary: .white.opacity(0.7),
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
                foreground: Color(hex: "4CAF50"),
                secondary: Color(hex: "4CAF50").opacity(0.6),
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
                foreground: Color(hex: "111111"),
                secondary: Color(hex: "111111").opacity(0.7),
                chrome: .black.opacity(0.72)
            )
        }
    }

    /// Auxiliary button fill on colored team panels (HOS SCOREBOARD_AUXILIARY_BUTTON_BG).
    static let auxiliaryButtonBackground = Color.white.opacity(0.14)
    static let auxiliaryButtonBackgroundSubtle = Color.white.opacity(0.08)
    static let serverIndicatorColor = Color(hex: "30D158")
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
            centerForeground: profile.textColor(for: .center)
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
struct ScoreboardStyleProfileV2: Codable, Equatable, Sendable {
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

    static func `default`(
        for styleID: ScoreboardStyleID,
        theme: ScoreboardTheme = .defaultTheme
    ) -> Self {
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

    private enum CodingKeys: String, CodingKey {
        case themeCode, team0Hex, team1Hex, centerHex
        case team0TextHex, team1TextHex, centerTextHex
        case foregroundHex, backgroundHex, autoContrast
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
        autoContrast: Bool
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
        return Self.autoTextHex(for: panelHex(for: slot))
    }

    func panelHex(for slot: ScoreboardStyleSlot) -> String {
        switch slot {
        case .team0: team0Hex
        case .team1: team1Hex
        case .center: centerHex
        }
    }

    static func normalizedHex(_ value: String) -> String? {
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
}

enum ScoreboardStyleSlot: String, Codable, Sendable {
    case team0
    case team1
    case center
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

struct ScoreboardStyleID: RawRepresentable, Hashable, Codable, Sendable {
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
        .pingpong, .badminton, .shuttlecock, .squash, .tennis, .softTennis, .padel, .basketball, .threeBasketball,
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

    func normalized(isLargeScreen: Bool) -> ScoreboardTypographyPreference {
        var copy = self
        for metric in ScoreboardFontMetric.allCases {
            copy.setMultiplier(
                ScoreboardFontSizePolicy.normalized(multiplier(for: metric), isLargeScreen: isLargeScreen),
                for: metric
            )
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
        previewPreference ?? appliedPreference
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
            immersiveMode: preferences.scoreboardImmersiveModeEnabled,
            touchGuard: preferences.scoreboardTouchGuardEnabled,
            doubleTapSubtract: preferences.scoreboardDoubleTapSubtractEnabled
        )
    }

    var palette: ScoreboardPalette {
        theme.palette.applying(styleProfileV2)
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
    @State private var styleDraft = ScoreboardStyleProfileV2.default(
        for: ScoreboardStyleID(rawValue: "default")
    )
    @State private var recentColors: [String] = []
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
            styleDraft = PreferencesManager.shared.scoreboardStyleProfileV2(for: session.styleID)
            recentColors = PreferencesManager.shared.scoreboardRecentStyleColors
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
                    styleSection
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

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("scoreboard_style_editor", value: "样式与颜色", comment: ""))
                .font(.system(size: isLargeScreen ? 20 : 16, weight: .medium))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ScoreboardTheme.allCases) { theme in
                        let selected = styleDraft.themeCode == theme.rawValue
                        Button {
                            styleDraft = .default(for: session.styleID, theme: theme)
                        } label: {
                            Text(theme.localizedTitle)
                                .font(.system(size: isLargeScreen ? 16 : 13, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: isLargeScreen ? 42 : 36)
                                .background(selected ? Theme.primary.opacity(0.45) : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(spacing: 9) {
                styleColorRow(
                    title: NSLocalizedString("scoreboard_style_team0", value: "左侧面板", comment: ""),
                    value: binding(for: .team0, text: false)
                )
                styleColorRow(
                    title: NSLocalizedString("scoreboard_style_team1", value: "右侧面板", comment: ""),
                    value: binding(for: .team1, text: false)
                )
                if session.styleID.rawValue == GameType.doudizhu.canonicalScoreboardIdentifier {
                    styleColorRow(
                        title: NSLocalizedString("scoreboard_style_center", value: "中间面板", comment: ""),
                        value: binding(for: .center, text: false)
                    )
                }
            }

            if !recentColors.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(NSLocalizedString("scoreboard_style_recent_colors", value: "最近使用", comment: ""))
                        .font(.system(size: isLargeScreen ? 15 : 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    HStack(spacing: 8) {
                        ForEach(recentColors, id: \.self) { color in
                            Button {
                                styleDraft.team0Hex = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: isLargeScreen ? 34 : 28, height: isLargeScreen ? 34 : 28)
                                    .overlay(Circle().stroke(Color.white.opacity(0.4)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("#\(color)")
                        }
                    }
                }
            }

            Toggle(
                NSLocalizedString("scoreboard_style_auto_contrast", value: "自动选择高对比文字", comment: ""),
                isOn: $styleDraft.autoContrast
            )
            .font(.system(size: isLargeScreen ? 17 : 14, weight: .medium))
            .foregroundStyle(.white)
            .tint(Theme.primary)

            if !styleDraft.autoContrast {
                VStack(spacing: 9) {
                    styleColorRow(
                        title: NSLocalizedString("scoreboard_style_team0_text", value: "左侧文字", comment: ""),
                        value: binding(for: .team0, text: true)
                    )
                    styleColorRow(
                        title: NSLocalizedString("scoreboard_style_team1_text", value: "右侧文字", comment: ""),
                        value: binding(for: .team1, text: true)
                    )
                    if session.styleID.rawValue == GameType.doudizhu.canonicalScoreboardIdentifier {
                        styleColorRow(
                            title: NSLocalizedString("scoreboard_style_center_text", value: "中间文字", comment: ""),
                            value: binding(for: .center, text: true)
                        )
                    }
                }
            }

            Button {
                let theme = ScoreboardTheme(rawValue: PreferencesManager.shared.scoreboardTheme) ?? .defaultTheme
                styleDraft = .default(for: session.styleID, theme: theme)
            } label: {
                Text(NSLocalizedString("scoreboard_style_reset", value: "恢复默认样式", comment: ""))
                    .font(.system(size: isLargeScreen ? 18 : 16, weight: .medium))
                    .foregroundStyle(Color(hex: "F7C948"))
            }
            .buttonStyle(.plain)
        }
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

    private func styleColorRow(title: String, value: Binding<String>) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(hex: ScoreboardStyleProfileV2.normalizedHex(value.wrappedValue) ?? "000000"))
                .frame(width: isLargeScreen ? 42 : 34, height: isLargeScreen ? 42 : 34)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.35)))
            Text(title)
                .font(.system(size: isLargeScreen ? 16 : 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("RRGGBB", text: value)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: isLargeScreen ? 16 : 13, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: isLargeScreen ? 112 : 92, height: isLargeScreen ? 42 : 34)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu {
            ForEach(recentColors, id: \.self) { color in
                Button("#\(color)") { value.wrappedValue = color }
            }
        }
    }

    private func binding(for slot: ScoreboardStyleSlot, text: Bool) -> Binding<String> {
        Binding {
            switch (slot, text) {
            case (.team0, false): styleDraft.team0Hex
            case (.team1, false): styleDraft.team1Hex
            case (.center, false): styleDraft.centerHex
            case (.team0, true): styleDraft.team0TextHex
            case (.team1, true): styleDraft.team1TextHex
            case (.center, true): styleDraft.centerTextHex
            }
        } set: { newValue in
            let sanitized = String(newValue.filter(\.isHexDigit).prefix(6)).uppercased()
            switch (slot, text) {
            case (.team0, false): styleDraft.team0Hex = sanitized
            case (.team1, false): styleDraft.team1Hex = sanitized
            case (.center, false): styleDraft.centerHex = sanitized
            case (.team0, true): styleDraft.team0TextHex = sanitized
            case (.team1, true): styleDraft.team1TextHex = sanitized
            case (.center, true): styleDraft.centerTextHex = sanitized
            }
        }
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
        let fallback = ScoreboardStyleProfileV2.default(
            for: session.styleID,
            theme: ScoreboardTheme(rawValue: styleDraft.themeCode) ?? .defaultTheme
        )
        styleDraft.team0Hex = ScoreboardStyleProfileV2.normalizedHex(styleDraft.team0Hex) ?? fallback.team0Hex
        styleDraft.team1Hex = ScoreboardStyleProfileV2.normalizedHex(styleDraft.team1Hex) ?? fallback.team1Hex
        styleDraft.centerHex = ScoreboardStyleProfileV2.normalizedHex(styleDraft.centerHex) ?? fallback.centerHex
        styleDraft.team0TextHex = ScoreboardStyleProfileV2.normalizedHex(styleDraft.team0TextHex) ?? fallback.team0TextHex
        styleDraft.team1TextHex = ScoreboardStyleProfileV2.normalizedHex(styleDraft.team1TextHex) ?? fallback.team1TextHex
        styleDraft.centerTextHex = ScoreboardStyleProfileV2.normalizedHex(styleDraft.centerTextHex) ?? fallback.centerTextHex
        let preferences = PreferencesManager.shared
        preferences.setScoreboardStyleProfileV2(styleDraft, for: session.styleID)
        preferences.rememberScoreboardStyleColors([
            styleDraft.team0Hex, styleDraft.team1Hex, styleDraft.centerHex,
            styleDraft.team0TextHex, styleDraft.team1TextHex, styleDraft.centerTextHex
        ])
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
        if let state = session.state {
            ZStack {
                Color.black.opacity(0.78).ignoresSafeArea()
                VStack(spacing: 18) {
                    Label(OfficialBreakOverlayPresentation.title(for: state), systemImage: "pause.circle.fill")
                    .font(.title2.weight(.semibold))
                    Text(state.phase == .preparation
                         ? NSLocalizedString("official_break_prepare", value: "准备", comment: "")
                         : NSLocalizedString("official_break_countdown", value: "休息倒计时", comment: ""))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(String(format: "%02d:%02d", state.remainingSeconds / 60, state.remainingSeconds % 60))
                        .font(.system(size: 76, weight: .bold, design: .monospaced))
                    HStack(spacing: 12) {
                        Button(NSLocalizedString("official_break_skip", value: "跳过", comment: "")) {
                            let action = state.afterAction
                            deliverVoiceCue(.earlyResume)
                            session.skip()
                            completeOnce(action)
                        }
                        .buttonStyle(.bordered)
                        if OfficialBreakOverlayPresentation.showsUndo(for: state) {
                            Button(NSLocalizedString("undo", value: "撤销", comment: "")) {
                                if session.undo(), session.state == nil {
                                    onCancel()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        Button(NSLocalizedString("done", value: "完成", comment: "")) {
                            let action = state.afterAction
                            deliverVoiceCue(.earlyResume)
                            session.skip()
                            completeOnce(action)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .foregroundStyle(.white)
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        switch self {
        case .score: return NSLocalizedString("scoreboard_font_metric_score", value: "主比分", comment: "")
        case .name: return NSLocalizedString("scoreboard_font_metric_name", value: "名称", comment: "")
        case .secondary:
            switch styleID.rawValue {
            case ScoreCore.GameType.basketball.rawValue, ScoreCore.GameType.threeBasketball.rawValue:
                return NSLocalizedString(
                    "scoreboard_font_metric_basketball_secondary",
                    value: "计时/犯规",
                    comment: ""
                )
            case ScoreCore.GameType.nineBall.rawValue:
                return NSLocalizedString(
                    "scoreboard_font_metric_nine_ball_secondary",
                    value: "追分详情",
                    comment: ""
                )
            case ScoreCore.GameType.uno.rawValue:
                return NSLocalizedString(
                    "scoreboard_font_metric_uno_secondary",
                    value: "目标/分差",
                    comment: ""
                )
            case ScoreCore.GameType.boxing.rawValue:
                return NSLocalizedString(
                    "scoreboard_font_metric_boxing_secondary",
                    value: "回合信息",
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
