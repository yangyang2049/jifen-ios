import Foundation
import LinkCore
import Observation

/// Mirror of phone common names, filled automatically via WatchConnectivity application context.
@MainActor
@Observable
final class WatchCommonNamesStore {
    static let shared = WatchCommonNamesStore()

    private let teamsKey = "watch_common_team_names"
    private let playersKey = "watch_common_player_names"
    private let updatedAtKey = "watch_common_names_updated_at"
    private let defaults = UserDefaults.standard

    private(set) var teams: [String] = []
    private(set) var players: [String] = []
    private(set) var updatedAtEpochMilliseconds: Int64 = 0

    private init() {
        teams = defaults.stringArray(forKey: teamsKey) ?? []
        players = defaults.stringArray(forKey: playersKey) ?? []
        updatedAtEpochMilliseconds = Int64(defaults.integer(forKey: updatedAtKey))
    }

    func apply(_ snapshot: CommonNamesSyncSnapshot) {
        if snapshot.updatedAtEpochMilliseconds > 0,
           snapshot.updatedAtEpochMilliseconds < updatedAtEpochMilliseconds {
            return
        }
        teams = snapshot.teams
        players = snapshot.players
        updatedAtEpochMilliseconds = snapshot.updatedAtEpochMilliseconds
        defaults.set(teams, forKey: teamsKey)
        defaults.set(players, forKey: playersKey)
        defaults.set(Int(updatedAtEpochMilliseconds), forKey: updatedAtKey)
    }

    func names(isTeam: Bool) -> [String] {
        isTeam ? teams : players
    }
}
