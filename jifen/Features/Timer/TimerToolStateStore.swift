import Foundation
import UserNotifications

enum StopwatchPolicy {
    static let maximumLapCount = 99
}

enum StopwatchPhase: String, Codable {
    case idle
    case running
    case paused
}

struct StopwatchPersistedState: Codable {
    var phase: StopwatchPhase = .idle
    var baseMilliseconds: Double = 0
    var runStartedAt: TimeInterval = 0
    var lapCumulativeMilliseconds: [Double] = []

    func elapsedMilliseconds(at date: Date = Date()) -> Double {
        guard phase == .running else { return max(0, baseMilliseconds) }
        return max(0, baseMilliseconds + date.timeIntervalSince1970 * 1_000 - runStartedAt)
    }
}

enum CountdownPhase: String, Codable {
    case idle
    case running
    case paused
    case ended
}

struct CountdownPersistedState: Codable {
    var phase: CountdownPhase = .idle
    var durationSeconds: Int = 30
    var lastDurationSeconds: Int = 30
    var endAt: TimeInterval = 0
    var remainingMilliseconds: Double = 0

    func remainingMilliseconds(at date: Date = Date()) -> Double {
        guard phase == .running else {
            if phase == .idle { return Double(durationSeconds) * 1_000 }
            return max(0, remainingMilliseconds)
        }
        return max(0, (endAt - date.timeIntervalSince1970) * 1_000)
    }
}

enum TimerToolStateStore {
    static let stopwatchKey = "timer.tool.stopwatch.state.v1"
    static let countdownKey = "timer.tool.countdown.state.v1"

    static func loadStopwatch(defaults: UserDefaults = .standard) -> StopwatchPersistedState {
        load(StopwatchPersistedState.self, key: stopwatchKey, defaults: defaults) ?? StopwatchPersistedState()
    }

    static func saveStopwatch(_ state: StopwatchPersistedState, defaults: UserDefaults = .standard) {
        save(state, key: stopwatchKey, defaults: defaults)
    }

    static func loadCountdown(defaults: UserDefaults = .standard) -> CountdownPersistedState {
        load(CountdownPersistedState.self, key: countdownKey, defaults: defaults) ?? CountdownPersistedState()
    }

    static func saveCountdown(_ state: CountdownPersistedState, defaults: UserDefaults = .standard) {
        save(state, key: countdownKey, defaults: defaults)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: stopwatchKey)
        defaults.removeObject(forKey: countdownKey)
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(
        _ value: T,
        key: String,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

final class CountdownNotificationManager {
    static let shared = CountdownNotificationManager()

    private let identifier = "timer.tool.countdown.finished"

    private init() {}

    func schedule(after seconds: TimeInterval) {
        guard seconds > 0, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let soundEnabled = PreferencesManager.shared.soundEnabled
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        ensureAuthorization(center: center) { [identifier, soundEnabled] granted in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString(
                "timer_countdown_notification_title",
                value: "倒计时结束",
                comment: "Countdown notification title"
            )
            content.body = NSLocalizedString(
                "timer_countdown_notification_content",
                value: "倒计时已结束，点按返回查看。",
                comment: "Countdown notification body"
            )
            if soundEnabled {
                content.sound = UNNotificationSound(
                    named: UNNotificationSoundName(rawValue: "ding.caf")
                )
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    func cancel() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func ensureAuthorization(center: UNUserNotificationCenter, completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in completion(granted) }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }
}
