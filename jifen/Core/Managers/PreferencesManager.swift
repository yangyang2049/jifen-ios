//
//  PreferencesManager.swift
//  jifen
//
//  User preferences manager
//

import Foundation
import Observation
import ScoreCore

enum UnoTargetScorePolicy {
    static let presets = [300, 500, 700, 1000]
    static let allowedRange = 1...99999
    static let defaultScore = 500

    static func normalized(_ value: Int) -> Int {
        allowedRange.contains(value) ? value : defaultScore
    }

    static func initialSelection(for value: Int) -> (targetScore: Int, customText: String) {
        let targetScore = normalized(value)
        return (
            targetScore,
            presets.contains(targetScore) ? "" : String(targetScore)
        )
    }

    static func sanitizedInput(_ rawValue: String) -> String {
        String(rawValue.filter(\.isNumber).prefix(5))
    }

    static func customValue(from text: String) -> Int? {
        guard let value = Int(text), allowedRange.contains(value) else { return nil }
        return value
    }
}

/// User preferences manager
@Observable
class PreferencesManager {
    static let shared = PreferencesManager()

    private enum Key {
        static let vibration = "vibration_enabled"
        static let sound = "sound_enabled"
        static let officialBreaks = "official_breaks_enabled"
        static let language = "language"
        static let defaultFont = "scoreboard_default_font"
        static let theme = "scoreboard_theme"
        static let forceIPadLandscape = "scoreboard_force_ipad_landscape"
        static let iPadLandscapeHintShown = "scoreboard_ipad_landscape_hint_shown_v1"
        static let keepScreenOn = "scoreboard_keep_screen_on"
        static let immersiveMode = "scoreboard_immersive_mode"
        static let touchGuard = "scoreboard_touch_guard"
        static let doubleTapSubtract = "scoreboard_double_tap_subtract"
        static let doubleTapSubtractInitialized = "scoreboard_double_tap_subtract_initialized_v1"
        static let matchTimePrefix = "scoreboard_match_time_visible_v1_"
        static let typographyPrefix = "scoreboard_typography_"
        static let styleProfilePrefix = "scoreboard_style_v2_"
    }

    private let defaults: UserDefaults

    /// 样式编辑草稿预览（key = styleID.rawValue，仅内存，不参与持久化）。
    private var styleProfilePreviews: [String: ScoreboardStyleProfileV2] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    private(set) var scoreboardRevision: UInt64 = 0
    
    // Vibration
    var vibrationEnabled: Bool {
        get {
            return defaults.bool(forKey: Key.vibration, defaultValue: true)
        }
        set {
            defaults.set(newValue, forKey: Key.vibration)
        }
    }
    
    // Sound
    var soundEnabled: Bool {
        get {
            return defaults.bool(forKey: Key.sound, defaultValue: true)
        }
        set {
            defaults.set(newValue, forKey: Key.sound)
        }
    }

    var officialBreaksEnabled: Bool {
        get { defaults.bool(forKey: Key.officialBreaks, defaultValue: true) }
        set {
            defaults.set(newValue, forKey: Key.officialBreaks)
            notifyScoreboardPreferencesChanged()
        }
    }
    
    // Language
    var language: String {
        get {
            return defaults.string(forKey: Key.language) ?? "zh-CN"
        }
        set {
            defaults.set(newValue, forKey: Key.language)
        }
    }
    
    // Default font for scoreboards that do not have their own typography yet.
    var defaultScoreboardFont: String {
        get {
            return defaults.string(forKey: Key.defaultFont) ?? ScoreboardFont.default.rawValue
        }
        set {
            defaults.set(newValue, forKey: Key.defaultFont)
            notifyScoreboardPreferencesChanged()
        }
    }

    var scoreboardTheme: String {
        get { defaults.string(forKey: Key.theme) ?? ScoreboardTheme.defaultTheme.rawValue }
        set {
            defaults.set(newValue, forKey: Key.theme)
            notifyScoreboardPreferencesChanged()
        }
    }

    var forceIPadLandscape: Bool {
        get { defaults.bool(forKey: Key.forceIPadLandscape, defaultValue: false) }
        set {
            defaults.set(newValue, forKey: Key.forceIPadLandscape)
            notifyScoreboardPreferencesChanged()
        }
    }

    var hasShownIPadLandscapeHint: Bool {
        get { defaults.bool(forKey: Key.iPadLandscapeHintShown, defaultValue: false) }
        set { defaults.set(newValue, forKey: Key.iPadLandscapeHintShown) }
    }

    #if DEBUG
    func resetIPadOrientationPreferencesForUITestsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-UITestResetIPadOrientationPreferences") else {
            return
        }
        defaults.removeObject(forKey: Key.forceIPadLandscape)
        defaults.removeObject(forKey: Key.iPadLandscapeHintShown)
    }
    #endif

    var keepScoreboardScreenOn: Bool {
        get { defaults.bool(forKey: Key.keepScreenOn, defaultValue: true) }
        set {
            defaults.set(newValue, forKey: Key.keepScreenOn)
            notifyScoreboardPreferencesChanged()
        }
    }

    var scoreboardImmersiveModeEnabled: Bool {
        get { defaults.bool(forKey: Key.immersiveMode, defaultValue: false) }
        set {
            defaults.set(newValue, forKey: Key.immersiveMode)
            notifyScoreboardPreferencesChanged()
        }
    }

    var scoreboardTouchGuardEnabled: Bool {
        get { defaults.bool(forKey: Key.touchGuard, defaultValue: false) }
        set {
            defaults.set(newValue, forKey: Key.touchGuard)
            notifyScoreboardPreferencesChanged()
        }
    }

    var scoreboardDoubleTapSubtractEnabled: Bool {
        get { defaults.bool(forKey: Key.doubleTapSubtract, defaultValue: false) }
        set {
            defaults.set(newValue, forKey: Key.doubleTapSubtract)
            defaults.set(true, forKey: Key.doubleTapSubtractInitialized)
            notifyScoreboardPreferencesChanged()
        }
    }

    /// Android-compatible one-time migration. Fresh installs stay disabled;
    /// an existing legally-consented install without the initialization marker
    /// keeps the legacy enabled behavior.
    func migrateLegacyDoubleTapSubtractIfNeeded(hasLegalConsent: Bool) {
        guard defaults.object(forKey: Key.doubleTapSubtractInitialized) == nil else { return }
        if defaults.object(forKey: Key.doubleTapSubtract) == nil, hasLegalConsent {
            defaults.set(true, forKey: Key.doubleTapSubtract)
        }
        defaults.set(true, forKey: Key.doubleTapSubtractInitialized)
        notifyScoreboardPreferencesChanged()
    }

    func scoreboardMatchTimeVisible(for gameType: GameType) -> Bool {
        defaults.bool(
            forKey: Key.matchTimePrefix + matchTimePreferenceID(for: gameType),
            defaultValue: false
        )
    }

    func setScoreboardMatchTimeVisible(_ isVisible: Bool, for gameType: GameType) {
        defaults.set(isVisible, forKey: Key.matchTimePrefix + matchTimePreferenceID(for: gameType))
        notifyScoreboardPreferencesChanged()
    }

    /// Clears settings owned by this manager while making sure the retained
    /// legal-consent marker cannot be mistaken for an old install on relaunch.
    func resetToOfflineReleaseDefaults() {
        let exactKeys = [
            Key.vibration, Key.sound, Key.officialBreaks, Key.language,
            Key.defaultFont, Key.theme, Key.forceIPadLandscape, Key.iPadLandscapeHintShown,
            Key.keepScreenOn,
            Key.immersiveMode, Key.touchGuard, Key.doubleTapSubtract,
            "linked_score_watch_start_guide_popup_shown_v1",
            "simpleScoreCustomAdjustEnabled", "multiScoreboardCustomAdjustEnabled",
            "multiScoreboardPlayerCount", "unoPlayerCount", "unoTargetScore",
            "guandanSetupTripleA", "guandanSetupPassACondition",
            "guandanSetupTripleAFallbackRank", "scoreboard_style_v2_recent_colors"
        ]
        exactKeys.forEach { defaults.removeObject(forKey: $0) }
        for key in defaults.dictionaryRepresentation().keys where
            key.hasPrefix(Key.matchTimePrefix)
                || key.hasPrefix(Key.typographyPrefix)
                || key.hasPrefix(Key.styleProfilePrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: Key.doubleTapSubtractInitialized)
        notifyScoreboardPreferencesChanged()
    }



    /// Aligns with Android/HOS `simpleScoreCustomAdjustEnabled`.
    var simpleScoreCustomAdjustEnabled: Bool {
        get { defaults.bool(forKey: "simpleScoreCustomAdjustEnabled", defaultValue: false) }
        set { defaults.set(newValue, forKey: "simpleScoreCustomAdjustEnabled") }
    }

    /// Aligns with Android/HOS `multiScoreboardCustomAdjustEnabled`.
    var multiScoreboardCustomAdjustEnabled: Bool {
        get { defaults.bool(forKey: "multiScoreboardCustomAdjustEnabled", defaultValue: false) }
        set { defaults.set(newValue, forKey: "multiScoreboardCustomAdjustEnabled") }
    }

    var multiScoreboardPlayerCount: Int {
        get {
            let value = defaults.integer(forKey: "multiScoreboardPlayerCount")
            return (3...9).contains(value) ? value : 4
        }
        set { defaults.set(min(9, max(3, newValue)), forKey: "multiScoreboardPlayerCount") }
    }

    var unoPlayerCount: Int {
        get {
            let value = defaults.integer(forKey: "unoPlayerCount")
            return (2...10).contains(value) ? value : 4
        }
        set { defaults.set(min(10, max(2, newValue)), forKey: "unoPlayerCount") }
    }

    var unoTargetScore: Int {
        get {
            let value = defaults.integer(forKey: "unoTargetScore")
            return UnoTargetScorePolicy.normalized(value)
        }
        set { defaults.set(UnoTargetScorePolicy.normalized(newValue), forKey: "unoTargetScore") }
    }

    /// 掼蛋开局偏好（对齐 HOS guandanSetup*）
    var guandanSetupTripleA: Bool {
        get { defaults.bool(forKey: "guandanSetupTripleA", defaultValue: false) }
        set { defaults.set(newValue, forKey: "guandanSetupTripleA") }
    }

    var guandanSetupPassACondition: String {
        get {
            let value = defaults.string(forKey: "guandanSetupPassACondition") ?? "not_last"
            return (value == "double_up" || value == "not_last") ? value : "not_last"
        }
        set { defaults.set(newValue, forKey: "guandanSetupPassACondition") }
    }

    var guandanSetupTripleAFallbackRank: String {
        get {
            let value = defaults.string(forKey: "guandanSetupTripleAFallbackRank") ?? "2"
            return guandanRankOrder.contains(value) && value != "A" ? value : "2"
        }
        set { defaults.set(newValue, forKey: "guandanSetupTripleAFallbackRank") }
    }

    func scoreboardTypography(for styleID: ScoreboardStyleID) -> ScoreboardTypographyPreference {
        guard let encoded = defaults.data(forKey: typographyKey(for: styleID)),
              let preference = try? JSONDecoder().decode(ScoreboardTypographyPreference.self, from: encoded) else {
            return .default(font: resolvedDefaultScoreboardFont)
        }
        return preference.normalized(isLargeScreen: Theme.usesPadLayout)
    }

    func hasScoreboardTypography(for styleID: ScoreboardStyleID) -> Bool {
        defaults.data(forKey: typographyKey(for: styleID)) != nil
    }

    func setScoreboardTypography(
        _ preference: ScoreboardTypographyPreference,
        for styleID: ScoreboardStyleID
    ) {
        let normalized = preference.normalized(isLargeScreen: Theme.usesPadLayout)
        guard let encoded = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(encoded, forKey: typographyKey(for: styleID))
    }

    func resetScoreboardTypography(for styleID: ScoreboardStyleID) {
        defaults.removeObject(forKey: typographyKey(for: styleID))
    }

    /// Missing V2 profiles are intentionally returned in memory only. This
    /// keeps a first read from silently modifying an existing user's settings.
    func scoreboardStyleProfileV2(for styleID: ScoreboardStyleID) -> ScoreboardStyleProfileV2 {
        // 样式编辑中的草稿预览优先（内存态，实时预览用，不落盘）。
        if let preview = styleProfilePreviews[styleID.rawValue] {
            return preview
        }
        guard let encoded = defaults.data(forKey: styleProfileV2Key(for: styleID)),
              let profile = try? JSONDecoder().decode(ScoreboardStyleProfileV2.self, from: encoded) else {
            let theme = ScoreboardTheme(rawValue: scoreboardTheme) ?? .defaultTheme
            return .default(for: styleID, theme: theme)
        }
        return profile
    }

    /// 样式编辑草稿的内存预览：编辑中渲染层立即生效；保存/取消时清除。
    /// 对齐安卓「编辑中渲染取 draft」的行为。
    func setScoreboardStyleProfilePreview(
        _ profile: ScoreboardStyleProfileV2?,
        for styleID: ScoreboardStyleID
    ) {
        if let profile {
            styleProfilePreviews[styleID.rawValue] = profile
        } else {
            styleProfilePreviews.removeValue(forKey: styleID.rawValue)
        }
        notifyScoreboardPreferencesChanged()
    }

    func hasScoreboardStyleProfileV2(for styleID: ScoreboardStyleID) -> Bool {
        defaults.data(forKey: styleProfileV2Key(for: styleID)) != nil
    }

    func setScoreboardStyleProfileV2(_ profile: ScoreboardStyleProfileV2, for styleID: ScoreboardStyleID) {
        guard let encoded = try? JSONEncoder().encode(profile) else { return }
        defaults.set(encoded, forKey: styleProfileV2Key(for: styleID))
        notifyScoreboardPreferencesChanged()
    }

    func resetScoreboardStyleProfileV2(for styleID: ScoreboardStyleID) {
        defaults.removeObject(forKey: styleProfileV2Key(for: styleID))
        notifyScoreboardPreferencesChanged()
    }

    var scoreboardRecentStyleColors: [String] {
        get { defaults.stringArray(forKey: "scoreboard_style_v2_recent_colors") ?? [] }
        set { defaults.set(Array(newValue.prefix(8)), forKey: "scoreboard_style_v2_recent_colors") }
    }

    func rememberScoreboardStyleColors(_ colors: [String]) {
        var recent = scoreboardRecentStyleColors
        for raw in colors.reversed() {
            guard let color = ScoreboardStyleProfileV2.normalizedHex(raw) else { continue }
            recent.removeAll { $0.caseInsensitiveCompare(color) == .orderedSame }
            recent.insert(color, at: 0)
        }
        scoreboardRecentStyleColors = Array(recent.prefix(8))
    }

    var resolvedDefaultScoreboardFont: ScoreboardFont {
        ScoreboardFont(rawValue: defaultScoreboardFont) ?? .default
    }

    private func typographyKey(for styleID: ScoreboardStyleID) -> String {
        "scoreboard_typography_\(styleID.rawValue)"
    }

    private func styleProfileV2Key(for styleID: ScoreboardStyleID) -> String {
        "scoreboard_style_v2_\(styleID.rawValue)"
    }

    private func matchTimePreferenceID(for gameType: GameType) -> String {
        // The app-level ping-pong type intentionally represents both singles
        // and doubles. Volleyball variants keep their own raw identifiers.
        gameType.canonicalScoreboardIdentifier
    }

    private func notifyScoreboardPreferencesChanged() {
        scoreboardRevision &+= 1
    }
}

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
}
