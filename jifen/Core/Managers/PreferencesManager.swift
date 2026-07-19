//
//  PreferencesManager.swift
//  jifen
//
//  User preferences manager
//

import Foundation

extension Notification.Name {
    static let scoreboardPreferencesDidChange = Notification.Name("scoreboardPreferencesDidChange")
}

/// User preferences manager
class PreferencesManager {
    static let shared = PreferencesManager()
    
    private init() {
        migrateScoreboardPreferencesIfNeeded()
    }
    
    private let defaults = UserDefaults.standard
    
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
        NotificationCenter.default.post(name: .scoreboardPreferencesDidChange, object: nil)
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
