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
    static let presets = [500, 700, 1000]
    static let allowedRange = 1...9999
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
        String(rawValue.filter(\.isNumber).prefix(4))
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
    
    private init() {}
    
    private let defaults = UserDefaults.standard
    private(set) var scoreboardRevision: UInt64 = 0
    
    // Vibration
    var vibrationEnabled: Bool {
        get {
            return defaults.bool(forKey: "vibration_enabled", defaultValue: true)
        }
        set {
            defaults.set(newValue, forKey: "vibration_enabled")
        }
    }
    
    // Sound
    var soundEnabled: Bool {
        get {
            return defaults.bool(forKey: "sound_enabled", defaultValue: true)
        }
        set {
            defaults.set(newValue, forKey: "sound_enabled")
        }
    }
    
    // Language
    var language: String {
        get {
            return defaults.string(forKey: "language") ?? "zh-CN"
        }
        set {
            defaults.set(newValue, forKey: "language")
        }
    }
    
    // Default font for scoreboards that do not have their own typography yet.
    var defaultScoreboardFont: String {
        get {
            return defaults.string(forKey: "scoreboard_default_font") ?? ScoreboardFont.default.rawValue
        }
        set {
            defaults.set(newValue, forKey: "scoreboard_default_font")
            notifyScoreboardPreferencesChanged()
        }
    }

    var scoreboardTheme: String {
        get { defaults.string(forKey: "scoreboard_theme") ?? ScoreboardTheme.defaultTheme.rawValue }
        set {
            defaults.set(newValue, forKey: "scoreboard_theme")
            notifyScoreboardPreferencesChanged()
        }
    }

    var forceIPadLandscape: Bool {
        get { defaults.bool(forKey: "scoreboard_force_ipad_landscape", defaultValue: false) }
        set {
            defaults.set(newValue, forKey: "scoreboard_force_ipad_landscape")
            notifyScoreboardPreferencesChanged()
        }
    }

    var keepScoreboardScreenOn: Bool {
        get { defaults.bool(forKey: "scoreboard_keep_screen_on", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "scoreboard_keep_screen_on")
            notifyScoreboardPreferencesChanged()
        }
    }

    var scoreboardImmersiveModeEnabled: Bool {
        get { defaults.bool(forKey: "scoreboard_immersive_mode", defaultValue: false) }
        set {
            defaults.set(newValue, forKey: "scoreboard_immersive_mode")
            notifyScoreboardPreferencesChanged()
        }
    }

    var scoreboardTouchGuardEnabled: Bool {
        get { defaults.bool(forKey: "scoreboard_touch_guard", defaultValue: false) }
        set {
            defaults.set(newValue, forKey: "scoreboard_touch_guard")
            notifyScoreboardPreferencesChanged()
        }
    }

    var scoreboardDoubleTapSubtractEnabled: Bool {
        get { defaults.bool(forKey: "scoreboard_double_tap_subtract", defaultValue: false) }
        set {
            defaults.set(newValue, forKey: "scoreboard_double_tap_subtract")
            notifyScoreboardPreferencesChanged()
        }
    }

    /// One-shot tip for the Setup “start on watch” split button (aligned with HOS).
    var linkedScoreWatchStartGuideShown: Bool {
        get { defaults.bool(forKey: "linked_score_watch_start_guide_popup_shown_v1", defaultValue: false) }
        set { defaults.set(newValue, forKey: "linked_score_watch_start_guide_popup_shown_v1") }
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

    var resolvedDefaultScoreboardFont: ScoreboardFont {
        ScoreboardFont(rawValue: defaultScoreboardFont) ?? .default
    }

    private func typographyKey(for styleID: ScoreboardStyleID) -> String {
        "scoreboard_typography_\(styleID.rawValue)"
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
