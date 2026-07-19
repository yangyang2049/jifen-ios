import SwiftUI

enum ScoreboardTheme: String, CaseIterable, Identifiable, Codable {
    case defaultTheme = "default"
    case proDark = "pro_dark"
    case electronic = "electronic"
    case retro = "retro"

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
}

enum ScoreboardFont: String, CaseIterable, Identifiable, Codable {
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

struct ScoreboardAppearanceSnapshot: Equatable {
    let theme: ScoreboardTheme
    let font: ScoreboardFont
    let keepScreenOn: Bool
    let immersiveMode: Bool
    let touchGuard: Bool
    let doubleTapSubtract: Bool

    static func current(_ preferences: PreferencesManager = .shared) -> ScoreboardAppearanceSnapshot {
        ScoreboardAppearanceSnapshot(
            theme: ScoreboardTheme(rawValue: preferences.scoreboardTheme) ?? .defaultTheme,
            font: ScoreboardFont(rawValue: preferences.scoreboardFont) ?? .default,
            keepScreenOn: preferences.keepScoreboardScreenOn,
            immersiveMode: preferences.scoreboardImmersiveModeEnabled,
            touchGuard: preferences.scoreboardTouchGuardEnabled,
            doubleTapSubtract: preferences.scoreboardDoubleTapSubtractEnabled
        )
    }
}

enum ScoreboardFontMetric: String, CaseIterable {
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
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFont: ScoreboardFont
    @State private var draftValues: [String: Double]
    private let gameType: GameType

    init(gameType: GameType) {
        self.gameType = gameType
        _selectedFont = State(initialValue: ScoreboardFont(rawValue: PreferencesManager.shared.scoreboardFont) ?? .default)
        _draftValues = State(initialValue: PreferencesManager.shared.fontSizeMultipliers(for: gameType))
    }

    private var isLargeScreen: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("scoreboard_font", value: "比分字体", comment: ""))
                            .font(.headline)
                        Picker("", selection: $selectedFont) {
                            ForEach(ScoreboardFont.allCases) { font in
                                Text(font.localizedTitle).tag(font)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(NSLocalizedString("scoreboard_font_size", value: "字号", comment: ""))
                                .font(.headline)
                            Spacer()
                            Button(NSLocalizedString("reset", value: "重置", comment: "")) {
                                draftValues = [:]
                            }
                        }
                        ForEach(ScoreboardFontMetric.allCases, id: \.rawValue) { metric in
                            ScoreboardFontSizeAdjustmentRow(
                                title: metric.localizedTitle,
                                value: multiplierBinding(for: metric),
                                isLargeScreen: isLargeScreen
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.backgroundColor)
            .navigationTitle(NSLocalizedString("scoreboard_display_settings", value: "显示设置", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", value: "取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("apply", value: "应用", comment: "")) {
                        PreferencesManager.shared.scoreboardFont = selectedFont.rawValue
                        PreferencesManager.shared.setFontSizeMultipliers(draftValues, for: gameType)
                        dismiss()
                    }
                }
            }
        }
    }

    private func multiplierBinding(for metric: ScoreboardFontMetric) -> Binding<Double> {
        Binding(
            get: { draftValues[metric.rawValue] ?? 1 },
            set: { draftValues[metric.rawValue] = ScoreboardFontSizePolicy.normalized($0, isLargeScreen: isLargeScreen) }
        )
    }
}

private struct ScoreboardFontSizeAdjustmentRow: View {
    let title: String
    @Binding var value: Double
    let isLargeScreen: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { value = ScoreboardFontSizePolicy.normalized(value - ScoreboardFontSizePolicy.step, isLargeScreen: isLargeScreen) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            Text(value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 0.1) == 0 ? 1 : 2))) + "×")
                .monospacedDigit()
                .frame(width: 54)
            Button { value = ScoreboardFontSizePolicy.normalized(value + ScoreboardFontSizePolicy.step, isLargeScreen: isLargeScreen) } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 16))
        .frame(minHeight: 44)
    }
}

private extension ScoreboardFontMetric {
    var localizedTitle: String {
        switch self {
        case .score: return NSLocalizedString("scoreboard_font_metric_score", value: "主比分", comment: "")
        case .name: return NSLocalizedString("scoreboard_font_metric_name", value: "名称", comment: "")
        case .secondary: return NSLocalizedString("scoreboard_font_metric_secondary", value: "局分/盘分", comment: "")
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
