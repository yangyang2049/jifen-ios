import Foundation

struct ParticipantNamePair: Equatable {
    let left: String
    let right: String
    let members: [String]?

    init(left: String, right: String, members: [String]? = nil) {
        self.left = left
        self.right = right
        self.members = members
    }
}

struct ParticipantMemberPair: Equatable {
    let first: String
    let second: String
}

/// Canonical participant labels for new scoreboards and missing-name fallbacks.
/// Stored/custom names are resolved before this policy is consulted.
enum DefaultParticipantNames {
    static func resolve(for gameType: GameType, isSingles: Bool = true) -> ParticipantNamePair {
        if !isSingles, supportsDoublesMembers(gameType) {
            return doublesSideNames(for: gameType)
        }

        switch gameType {
        case .basketball, .threeBasketball,
             .volleyball, .beachVolleyball, .airVolleyball,
             .guandan, .shengji:
            return localizedPair("team_a", "Team A", "team_b", "Team B")
        case .football:
            return localizedPair("team_home", "Home", "team_away", "Away")
        case .archery:
            return localizedPair("archer_a", "Archer A", "archer_b", "Archer B")
        case .pingpong, .badminton, .tennis, .pickleball, .foosball,
             .billiards, .eightBall, .snooker:
            return localizedPair("player_a", "Player A", "player_b", "Player B")
        case .boxing, .simpleScore, .counter:
            return localizedPair("watch_team_red", "Red", "watch_team_blue", "Blue")
        case .nineBall, .doudizhu, .uno, .multiScoreboard:
            return localizedPair("player1_name", "Player 1", "player2_name", "Player 2")
        case .go:
            return localizedPair("timer_black_player", "Black", "timer_white_player", "White")
        case .xiangqi, .checkers:
            return localizedPair("timer_red_player", "Red", "timer_black_player", "Black")
        case .chess:
            return localizedPair("timer_white_player", "White", "timer_black_player", "Black")
        case .stopwatch:
            return localizedPair("watch_team_red", "Red", "watch_team_blue", "Blue")
        }
    }

    static var doublesMembers: [String] {
        [
            NSLocalizedString("doubles_red_a", value: "Red A", comment: ""),
            NSLocalizedString("doubles_red_b", value: "Red B", comment: ""),
            NSLocalizedString("doubles_blue_a", value: "Blue A", comment: ""),
            NSLocalizedString("doubles_blue_b", value: "Blue B", comment: "")
        ]
    }

    static func doublesSideNames(for gameType: GameType) -> ParticipantNamePair {
        let members = doublesMembers
        let separator = gameType == .foosball ? "/" : " / "
        return ParticipantNamePair(
            left: "\(members[0])\(separator)\(members[1])",
            right: "\(members[2])\(separator)\(members[3])",
            members: members
        )
    }

    static func areDefaultDoublesMembers(_ names: [String]) -> Bool {
        names == doublesMembers
    }

    /// Restores a doubles pair after visiting singles mode without discarding
    /// the hidden second member. A newly edited singles name still replaces
    /// the first member when the user switches back to doubles.
    static func doublesMembersAfterModeSwitch(
        currentSideName: String,
        existingFirst: String,
        existingSecond: String,
        singlesDefaultName: String,
        configuredDefaultName: String,
        defaultFirst: String,
        defaultSecond: String
    ) -> ParticipantMemberPair {
        let current = trimmed(currentSideName)
        let previousFirst = trimmed(existingFirst)
        let previousSecond = trimmed(existingSecond)
        let parsedCurrent = splitDoublesName(current)
        let currentIsDefault = current.isEmpty
            || current == trimmed(singlesDefaultName)
            || current == trimmed(configuredDefaultName)

        if !previousSecond.isEmpty {
            let currentRepresentsPreviousPair = parsedCurrent.first == previousFirst
                && parsedCurrent.second == previousSecond
            if !parsedCurrent.second.isEmpty && !currentRepresentsPreviousPair {
                return parsedCurrent
            }

            let first = currentIsDefault
                || current == previousFirst
                || currentRepresentsPreviousPair
                ? previousFirst
                : current
            return ParticipantMemberPair(
                first: first.isEmpty ? defaultFirst : first,
                second: previousSecond
            )
        }

        if currentIsDefault {
            return ParticipantMemberPair(first: defaultFirst, second: defaultSecond)
        }
        return ParticipantMemberPair(
            first: parsedCurrent.first.isEmpty ? defaultFirst : parsedCurrent.first,
            second: parsedCurrent.second.isEmpty ? defaultSecond : parsedCurrent.second
        )
    }

    private static func supportsDoublesMembers(_ gameType: GameType) -> Bool {
        switch gameType {
        case .pingpong, .badminton, .tennis, .pickleball, .foosball:
            return true
        default:
            return false
        }
    }

    private static func splitDoublesName(_ value: String) -> ParticipantMemberPair {
        let parts = value
            .split(separator: "/")
            .map { trimmed(String($0)) }
            .filter { !$0.isEmpty }
        return ParticipantMemberPair(
            first: parts.first ?? value,
            second: parts.count > 1 ? parts[1] : ""
        )
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func localizedPair(
        _ leftKey: String,
        _ leftFallback: String,
        _ rightKey: String,
        _ rightFallback: String
    ) -> ParticipantNamePair {
        ParticipantNamePair(
            left: NSLocalizedString(leftKey, value: leftFallback, comment: ""),
            right: NSLocalizedString(rightKey, value: rightFallback, comment: "")
        )
    }
}
