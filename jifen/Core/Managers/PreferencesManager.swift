//
//  PreferencesManager.swift
//  jifen
//
//  User preferences manager
//

import Foundation

/// User preferences manager
class PreferencesManager {
    static let shared = PreferencesManager()
    
    private init() {}
    
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
        }
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

