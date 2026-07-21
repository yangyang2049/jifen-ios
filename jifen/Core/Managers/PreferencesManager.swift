//
//  PreferencesManager.swift
//  jifen
//
//  User preferences manager
//

import Foundation
import Observation
import ScoreCore

/// User preferences manager
@Observable
class PreferencesManager {
    static let shared = PreferencesManager()
    
    private init() {
        migrateScoreboardPreferencesIfNeeded()
    }
    
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
    
    // Scoreboard Font
    var scoreboardFont: String {
        get {
            return defaults.string(forKey: "scoreboard_font") ?? "default"
        }
        set {
            defaults.set(newValue, forKey: "scoreboard_font")
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
            return [300, 500, 700, 1000].contains(value) ? value : 500
        }
        set { defaults.set(newValue, forKey: "unoTargetScore") }
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

    func fontSizeMultipliers(for gameType: GameType) -> [String: Double] {
        guard let encoded = defaults.data(forKey: fontSizeKey(for: gameType)),
              let values = try? JSONDecoder().decode([String: Double].self, from: encoded) else {
            return [:]
        }
        return values
    }

    func setFontSizeMultipliers(_ values: [String: Double], for gameType: GameType) {
        if let encoded = try? JSONEncoder().encode(values) {
            defaults.set(encoded, forKey: fontSizeKey(for: gameType))
            notifyScoreboardPreferencesChanged()
        }
    }

    private func fontSizeKey(for gameType: GameType) -> String {
        "scoreboard_font_sizes_v4_\(gameType.canonicalScoreboardIdentifier)"
    }

    private func migrateScoreboardPreferencesIfNeeded() {
        let migrationKey = "scoreboard_preferences_schema_version"
        guard defaults.integer(forKey: migrationKey) < 1 else { return }

        let legacyFontAliases = [
            "digital": ScoreboardFont.monospaced.rawValue,
            "seven_segment": ScoreboardFont.sevenSegment.rawValue,
            "teko": ScoreboardFont.sports.rawValue
        ]
        if let legacyFont = defaults.string(forKey: "scoreboard_font"),
           let canonicalFont = legacyFontAliases[legacyFont] {
            defaults.set(canonicalFont, forKey: "scoreboard_font")
        }
        defaults.set(1, forKey: migrationKey)
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
