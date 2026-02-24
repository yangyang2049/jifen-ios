import Foundation

extension Notification.Name {
    static let watchScoreboardLayoutDidChange = Notification.Name("watch_scoreboard_layout_did_change")
}

final class WatchPreferences {
    static let shared = WatchPreferences()

    private let defaults = UserDefaults.standard

    private init() {}

    var vibrationEnabled: Bool {
        get { defaults.object(forKey: "watch_vibration_enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "watch_vibration_enabled") }
    }

    var soundEnabled: Bool {
        get { defaults.object(forKey: "watch_sound_enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "watch_sound_enabled") }
    }

    var privacyAccepted: Bool {
        get { defaults.object(forKey: "watch_privacy_accepted") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "watch_privacy_accepted") }
    }

    /// Scoreboard layout: "vertical" (red top, blue bottom) or "horizontal" (red left, blue right)
    var scoreboardLayout: String {
        get { defaults.string(forKey: "watch_scoreboard_layout") ?? "vertical" }
        set {
            let normalized = (newValue == "horizontal") ? "horizontal" : "vertical"
            let current = defaults.string(forKey: "watch_scoreboard_layout") ?? "vertical"
            guard current != normalized else { return }
            defaults.set(normalized, forKey: "watch_scoreboard_layout")
            NotificationCenter.default.post(name: .watchScoreboardLayoutDidChange, object: normalized)
        }
    }

    func bool(forKey key: String, defaultValue: Bool = false) -> Bool {
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        return defaultValue
    }

    func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func string(forKey key: String, defaultValue: String = "") -> String {
        if let value = defaults.string(forKey: key) {
            return value
        }
        return defaultValue
    }

    func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
