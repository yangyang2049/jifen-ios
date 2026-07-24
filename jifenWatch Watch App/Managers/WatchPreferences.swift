import Foundation

extension Notification.Name {
    static let watchScoreboardLayoutDidChange = Notification.Name("watch_scoreboard_layout_did_change")
}

final class WatchPreferences {
    static let shared = WatchPreferences()
    static let pinnedHomeItemIDsKey = "watch_pinned_home_item_ids"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var vibrationEnabled: Bool {
        get { defaults.object(forKey: "watch_vibration_enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "watch_vibration_enabled") }
    }

    var soundEnabled: Bool {
        get { defaults.object(forKey: "watch_sound_enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "watch_sound_enabled") }
    }

    /// Whether to show a brief between-set rest hint on rally/tennis boards. Default on (Harmony-aligned).
    var setBreakEnabled: Bool {
        get { defaults.object(forKey: "watch_set_break_enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "watch_set_break_enabled") }
    }

    /// Scoreboard layout: "horizontal" (left-right) or "vertical" (top-bottom). Default is horizontal.
    var scoreboardLayout: String {
        get { defaults.string(forKey: "watch_scoreboard_layout") ?? "horizontal" }
        set {
            let normalized = (newValue == "vertical") ? "vertical" : "horizontal"
            let current = defaults.string(forKey: "watch_scoreboard_layout") ?? "horizontal"
            guard current != normalized else { return }
            defaults.set(normalized, forKey: "watch_scoreboard_layout")
            NotificationCenter.default.post(name: .watchScoreboardLayoutDidChange, object: normalized)
        }
    }

    var pinnedHomeItemIDs: [String] {
        get { defaults.stringArray(forKey: Self.pinnedHomeItemIDsKey) ?? [] }
        set { defaults.set(newValue, forKey: Self.pinnedHomeItemIDsKey) }
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

    func int(forKey key: String, defaultValue: Int = 0) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.integer(forKey: key)
    }

    func setInt(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func allowedInt(forKey key: String, defaultValue: Int, allowed: [Int]) -> Int {
        let value = int(forKey: key, defaultValue: defaultValue)
        return allowed.contains(value) ? value : defaultValue
    }
}
