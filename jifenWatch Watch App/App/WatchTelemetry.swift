import Foundation
import TelemetryDeck

enum WatchTelemetry {
    private static let lastForegroundKey = "watch_telemetry_last_foreground"

    private static let isEnabled: Bool = {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["JIFEN_WATCH_TELEMETRY_TEST"] == "1" else {
            return false
        }
        #endif

        let config = TelemetryDeck.Config(appID: "970CC686-8BB7-457C-B580-817A94CC3093")
        #if DEBUG
        config.testMode = true
        #endif
        config.sendNewSessionBeganSignal = false
        config.sessionStatsEnabled = false
        config.cacheLimit = 500
        TelemetryDeck.initialize(config: config)
        return true
    }()

    static func foregrounded() {
        guard isEnabled else { return }
        let defaults = UserDefaults.standard
        let now = Date()
        if let last = defaults.object(forKey: lastForegroundKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: now) {
            return
        }
        defaults.set(now, forKey: lastForegroundKey)
        TelemetryDeck.signal("Watch.foregrounded")
    }

    static func scoreboardOpened(isLinked: Bool, isResumed: Bool) {
        guard isEnabled else { return }
        TelemetryDeck.signal("Watch.scoreboardOpened", parameters: [
            "mode": isLinked ? "linked" : "standalone",
            "entry": isResumed ? "resume" : "new",
        ])
    }

    static func sessionSaved(gameType: WatchGameType, source: WatchRecordSource) {
        guard let sport = sportName(for: gameType), isEnabled else { return }
        TelemetryDeck.signal("Watch.sessionSaved", parameters: [
            "sport": sport,
            "source": source.rawValue,
        ])
    }

    private static func sportName(for gameType: WatchGameType) -> String? {
        switch gameType {
        case .pingpong: return "pingpong"
        case .badminton: return "badminton"
        case .shuttlecock: return "shuttlecock"
        case .squash: return "squash"
        case .foosball: return "foosball"
        case .tennis: return "tennis"
        case .pickleball: return "pickleball"
        case .archery: return "archery"
        case .eightBall: return "eight_ball"
        case .nineBall: return "nine_ball"
        case .snooker: return "snooker"
        case .football: return "football"
        case .football5v5: return "football_5v5"
        case .basketballTraining: return "basketball_training"
        case .counter: return nil
        }
    }
}
