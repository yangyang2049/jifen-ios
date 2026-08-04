import Foundation
import ScoreCore

struct WatchParticipantNamePair: Equatable {
    let left: String
    let right: String
    let members: [String]?

    init(left: String, right: String, members: [String]? = nil) {
        self.left = left
        self.right = right
        self.members = members
    }
}

/// Prefer auto-synced phone common names, then use the sport-specific canonical labels.
enum WatchDefaultTeamNames {
    @MainActor
    static func resolve(for gameType: GameType) -> WatchParticipantNamePair {
        let store = WatchCommonNamesStore.shared
        let candidates = usesTeamCommonNames(gameType) ? store.teams : store.players
        let fallback = fallback(for: gameType)
        guard !candidates.isEmpty else {
            return fallback
        }
        let left = candidates[0]
        let right = candidates.count > 1 ? candidates[1] : fallback.right
        return WatchParticipantNamePair(
            left: left,
            right: right == left ? fallback.right : right
        )
    }

    static func fallback(for gameType: GameType) -> WatchParticipantNamePair {
        switch gameType {
        case .basketball, .threeBasketball,
             .volleyball, .beachVolleyball, .airVolleyball,
             .guandan, .shengji:
            return localizedPair("team_a", "Team A", "team_b", "Team B")
        case .football:
            return localizedPair("team_home", "Home", "team_away", "Away")
        case .archeryDual:
            return localizedPair("archer_a", "Archer A", "archer_b", "Archer B")
        case .pingpong, .badminton, .tennis, .pickleball, .foosball,
             .billiards, .eightBall, .snooker:
            return localizedPair("player_a", "Player A", "player_b", "Player B")
        case .pingpongDoubles, .badmintonDoubles, .tennisDoubles,
             .pickleballDoubles, .foosballDoubles:
            let members = doublesMembers
            let separator = gameType == .foosballDoubles ? "/" : " / "
            return WatchParticipantNamePair(
                left: "\(members[0])\(separator)\(members[1])",
                right: "\(members[2])\(separator)\(members[3])",
                members: members
            )
        case .boxing, .simpleScore:
            return localizedPair("watch_team_red", "Red", "watch_team_blue", "Blue")
        case .nineBall, .doudizhu, .uno, .multiScoreboard:
            return numberedPlayerPair()
        }
    }

    static func fallback(for sport: WatchSetupSport) -> WatchParticipantNamePair {
        if sport.isDoubles {
            return doublesSideNames(for: sport, members: doublesMembers)
        }
        return WatchParticipantNamePair(
            left: setupParticipantName(for: sport, index: 0),
            right: setupParticipantName(for: sport, index: 1)
        )
    }

    static func setupParticipantName(for sport: WatchSetupSport, index: Int) -> String {
        if sport.isDoubles, doublesMembers.indices.contains(index) {
            return doublesMembers[index]
        }
        if sport == .archery {
            return index == 0
                ? NSLocalizedString("archer_a", value: "Archer A", comment: "")
                : NSLocalizedString("archer_b", value: "Archer B", comment: "")
        }
        if sport == .nineBall || index > 1 {
            return numberedPlayerName(index: index)
        }
        return index == 0
            ? NSLocalizedString("player_a", value: "Player A", comment: "")
            : NSLocalizedString("player_b", value: "Player B", comment: "")
    }

    static var doublesMembers: [String] {
        [
            NSLocalizedString("watch_setup_red_a", value: "Red A", comment: ""),
            NSLocalizedString("watch_setup_red_b", value: "Red B", comment: ""),
            NSLocalizedString("watch_setup_blue_a", value: "Blue A", comment: ""),
            NSLocalizedString("watch_setup_blue_b", value: "Blue B", comment: "")
        ]
    }

    static func doublesSideNames(
        for sport: WatchSetupSport,
        members: [String]
    ) -> WatchParticipantNamePair {
        guard sport.isDoubles, members.count >= 4 else {
            return WatchParticipantNamePair(
                left: members.first ?? "",
                right: members.count > 1 ? members[1] : ""
            )
        }
        return WatchParticipantNamePair(
            left: "\(members[0]) / \(members[1])",
            right: "\(members[2]) / \(members[3])",
            members: Array(members.prefix(4))
        )
    }

    private static func usesTeamCommonNames(_ gameType: GameType) -> Bool {
        switch gameType {
        case .football, .basketball, .threeBasketball,
             .volleyball, .airVolleyball, .beachVolleyball,
             .guandan, .shengji, .simpleScore:
            return true
        default:
            return false
        }
    }

    private static func numberedPlayerPair() -> WatchParticipantNamePair {
        WatchParticipantNamePair(
            left: numberedPlayerName(index: 0),
            right: numberedPlayerName(index: 1)
        )
    }

    private static func numberedPlayerName(index: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("watch_setup_player_number", value: "Player %d", comment: ""),
            index + 1
        )
    }

    private static func localizedPair(
        _ leftKey: String,
        _ leftFallback: String,
        _ rightKey: String,
        _ rightFallback: String
    ) -> WatchParticipantNamePair {
        WatchParticipantNamePair(
            left: NSLocalizedString(leftKey, value: leftFallback, comment: ""),
            right: NSLocalizedString(rightKey, value: rightFallback, comment: "")
        )
    }
}
