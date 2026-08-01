import Observation
import ScoreCore
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

    /// The 23 launchable scoreboard entries. Timer tools intentionally do not
    /// participate in scoreboard typography storage.
    static let registeredEntryGameTypes: [GameType] = [
        .pingpong, .badminton, .tennis, .basketball, .threeBasketball,
        .football, .volleyball, .beachVolleyball, .airVolleyball,
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
    let font: ScoreboardFont
    let keepScreenOn: Bool
    let immersiveMode: Bool
    let touchGuard: Bool
    let doubleTapSubtract: Bool

    static func current(
        styleID: ScoreboardStyleID? = nil,
        _ preferences: PreferencesManager = .shared
    ) -> ScoreboardAppearanceSnapshot {
        let font = styleID.map { preferences.scoreboardTypography(for: $0).font }
            ?? preferences.resolvedDefaultScoreboardFont
        return ScoreboardAppearanceSnapshot(
            theme: ScoreboardTheme(rawValue: preferences.scoreboardTheme) ?? .defaultTheme,
            font: font,
            keepScreenOn: preferences.keepScoreboardScreenOn,
            immersiveMode: preferences.scoreboardImmersiveModeEnabled,
            touchGuard: preferences.scoreboardTouchGuardEnabled,
            doubleTapSubtract: preferences.scoreboardDoubleTapSubtractEnabled
        )
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
    let session: ScoreboardTypographySession
    let metrics: [ScoreboardFontMetric]
    var onClose: () -> Void

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
        .onAppear { session.beginPreview() }
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
        session.applyPreview()
        onClose()
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
