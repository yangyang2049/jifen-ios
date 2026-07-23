import Foundation

/// Prefer auto-synced phone common names; fall back to 红方/蓝方.
enum WatchDefaultTeamNames {
    static func resolve() -> (left: String, right: String) {
        let store = WatchCommonNamesStore.shared
        let candidates = store.players.isEmpty ? store.teams : store.players
        let fallbackLeft = NSLocalizedString("watch_team_red", value: "红方", comment: "Red")
        let fallbackRight = NSLocalizedString("watch_team_blue", value: "蓝方", comment: "Blue")
        guard !candidates.isEmpty else {
            return (fallbackLeft, fallbackRight)
        }
        let left = candidates[0]
        let right = candidates.count > 1 ? candidates[1] : fallbackRight
        return (left, right == left ? fallbackRight : right)
    }
}
