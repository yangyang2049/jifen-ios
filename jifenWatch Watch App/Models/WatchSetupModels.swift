import Foundation
import LinkCore
import ScoreCore

enum WatchSetupSport: String, CaseIterable, Hashable {
    case badminton
    case badmintonDoubles
    case pingpong
    case pingpongDoubles
    case tennis
    case tennisDoubles
    case pickleball
    case pickleballDoubles
    case archery
    case eightBall
    case nineBall
    case snooker

    var isDoubles: Bool {
        switch self {
        case .badmintonDoubles, .pingpongDoubles, .tennisDoubles, .pickleballDoubles:
            return true
        default:
            return false
        }
    }

    var defaultPlayerCount: Int {
        isDoubles ? 4 : 2
    }

    var namesInitiallyExpanded: Bool {
        self == .archery || self == .nineBall
    }
}

enum WatchBasketballTrainingMode: String, CaseIterable, Hashable, Codable {
    case onePoint = "1"
    case twoPoint = "2"
    case threePoint = "3"
    case free

    var fixedPoints: Int? {
        Int(rawValue)
    }
}

enum WatchEightBallHandicapBeneficiary: String, CaseIterable, Hashable, Codable {
    case none
    case team1
    case team2
}

struct WatchSportsSetupDraft: Hashable {
    var sport: WatchSetupSport
    var playerCount: Int
    var playerNames: [String]
    var maxSets: Int
    var pointsPerSet: Int
    var tennisDeuceMode: String
    var pickleballTargetScore: Int
    var pickleballUseRallyScoring: Bool
    var eightBallTargetRacks: Int
    var eightBallHandicapRacks: Int
    var eightBallHandicapBeneficiary: WatchEightBallHandicapBeneficiary
    var snookerCustomFrames: String

    init(
        sport: WatchSetupSport,
        playerCount: Int? = nil,
        preferences: WatchPreferences = .shared
    ) {
        self.sport = sport
        self.playerCount = sport == .nineBall
            ? min(4, max(2, playerCount ?? 2))
            : sport.defaultPlayerCount
        playerNames = Array(repeating: "", count: max(4, self.playerCount))
        tennisDeuceMode = "advantage"
        pickleballTargetScore = 11
        pickleballUseRallyScoring = false
        eightBallTargetRacks = 5
        eightBallHandicapRacks = 0
        eightBallHandicapBeneficiary = .none
        snookerCustomFrames = ""

        switch sport {
        case .badminton, .badmintonDoubles:
            maxSets = preferences.allowedInt(
                forKey: "watchBadmintonSetupMaxSets",
                defaultValue: 3,
                allowed: [1, 3, 5]
            )
            pointsPerSet = preferences.allowedInt(
                forKey: "watchBadmintonSetupPointsPerSet",
                defaultValue: 21,
                allowed: [11, 15, 21]
            )
        case .pingpong, .pingpongDoubles:
            maxSets = preferences.allowedInt(
                forKey: "watchPingpongSetupMaxSets",
                defaultValue: 5,
                allowed: [1, 3, 5, 7]
            )
            pointsPerSet = preferences.allowedInt(
                forKey: "watchPingpongSetupPointsPerSet",
                defaultValue: 11,
                allowed: [5, 7, 9, 11, 15, 21]
            )
        case .tennis, .tennisDoubles:
            maxSets = preferences.allowedInt(
                forKey: "watchTennisSetupMaxSets",
                defaultValue: 3,
                allowed: [1, 3, 5]
            )
            pointsPerSet = 0
            let stored = preferences.string(
                forKey: "watchTennisSetupDeuceMode",
                defaultValue: "advantage"
            )
            tennisDeuceMode = ["advantage", "no_ad"].contains(stored) ? stored : "advantage"
        case .pickleball, .pickleballDoubles:
            maxSets = preferences.allowedInt(
                forKey: "watchPickleballSetupMaxSets",
                defaultValue: 3,
                allowed: [1, 3, 5]
            )
            pointsPerSet = 0
            pickleballTargetScore = preferences.allowedInt(
                forKey: "watchPickleballSetupTargetScore",
                defaultValue: 11,
                allowed: [11, 15, 21]
            )
            pickleballUseRallyScoring = preferences.bool(
                forKey: "watchPickleballSetupUseRallyScoring",
                defaultValue: false
            )
        case .eightBall:
            maxSets = 0
            pointsPerSet = 0
            eightBallTargetRacks = preferences.allowedInt(
                forKey: "watchEightBallSetupTargetRacks",
                defaultValue: 5,
                allowed: Self.eightBallRackOptions
            )
            let maximum = Self.maxEightBallHandicap(for: eightBallTargetRacks)
            eightBallHandicapRacks = preferences.allowedInt(
                forKey: "watchEightBallSetupHandicapRacks",
                defaultValue: 0,
                allowed: Array(0...maximum)
            )
            let rawBeneficiary = preferences.string(
                forKey: "watchEightBallSetupHandicapBeneficiary",
                defaultValue: WatchEightBallHandicapBeneficiary.none.rawValue
            )
            eightBallHandicapBeneficiary = WatchEightBallHandicapBeneficiary(rawValue: rawBeneficiary) ?? .none
            normalizeEightBallHandicap()
        case .snooker:
            maxSets = preferences.int(forKey: "watchSnookerSetupMaxSets", defaultValue: 1)
            if !(1...99).contains(maxSets) { maxSets = 1 }
            pointsPerSet = 0
            snookerCustomFrames = Self.snookerFrameOptions.contains(maxSets) ? "" : String(maxSets)
        case .archery, .nineBall:
            maxSets = 0
            pointsPerSet = 0
        }
    }

    static let eightBallRackOptions = [1, 3, 5, 7, 9, 11, 13, 15]
    static let snookerFrameOptions = [1, 3, 5, 7, 9, 11, 15, 17, 19, 25, 33, 35]

    static func maxEightBallHandicap(for targetRacks: Int) -> Int {
        min(5, max(0, targetRacks - 1))
    }

    mutating func normalizeEightBallHandicap() {
        guard eightBallTargetRacks > 1 else {
            eightBallHandicapRacks = 0
            eightBallHandicapBeneficiary = .none
            return
        }
        let maximum = Self.maxEightBallHandicap(for: eightBallTargetRacks)
        eightBallHandicapRacks = min(maximum, max(0, eightBallHandicapRacks))
    }

    func namesAreValid(whenExpanded namesExpanded: Bool) -> Bool {
        guard namesExpanded else { return true }
        let count = sport.isDoubles ? 4 : playerCount
        let values = playerNames.prefix(count).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let filled = values.filter { !$0.isEmpty }.count
        return filled == 0 || filled == values.count
    }

    func persistRules(to preferences: WatchPreferences = .shared) {
        switch sport {
        case .badminton, .badmintonDoubles:
            preferences.setInt(maxSets, forKey: "watchBadmintonSetupMaxSets")
            preferences.setInt(pointsPerSet, forKey: "watchBadmintonSetupPointsPerSet")
        case .pingpong, .pingpongDoubles:
            preferences.setInt(maxSets, forKey: "watchPingpongSetupMaxSets")
            preferences.setInt(pointsPerSet, forKey: "watchPingpongSetupPointsPerSet")
        case .tennis, .tennisDoubles:
            preferences.setInt(maxSets, forKey: "watchTennisSetupMaxSets")
            preferences.setString(tennisDeuceMode, forKey: "watchTennisSetupDeuceMode")
        case .pickleball, .pickleballDoubles:
            preferences.setInt(maxSets, forKey: "watchPickleballSetupMaxSets")
            preferences.setInt(pickleballTargetScore, forKey: "watchPickleballSetupTargetScore")
            preferences.setBool(
                pickleballUseRallyScoring,
                forKey: "watchPickleballSetupUseRallyScoring"
            )
        case .eightBall:
            preferences.setInt(eightBallTargetRacks, forKey: "watchEightBallSetupTargetRacks")
            preferences.setInt(eightBallHandicapRacks, forKey: "watchEightBallSetupHandicapRacks")
            preferences.setString(
                eightBallHandicapBeneficiary.rawValue,
                forKey: "watchEightBallSetupHandicapBeneficiary"
            )
        case .snooker:
            preferences.setInt(maxSets, forKey: "watchSnookerSetupMaxSets")
        case .archery, .nineBall:
            break
        }
    }
}

struct WatchScoreboardLaunchConfig: Hashable {
    let sport: WatchSetupSport
    let playerCount: Int
    let playerNames: [String]
    let maxSets: Int
    let pointsPerSet: Int
    let tennisDeuceMode: String
    let pickleballTargetScore: Int
    let pickleballUseRallyScoring: Bool
    let eightBallTargetRacks: Int
    let eightBallHandicapRacks: Int
    let eightBallHandicapBeneficiary: WatchEightBallHandicapBeneficiary

    init(draft: WatchSportsSetupDraft) {
        sport = draft.sport
        playerCount = draft.playerCount
        playerNames = draft.playerNames
        maxSets = draft.maxSets
        pointsPerSet = draft.pointsPerSet
        tennisDeuceMode = draft.tennisDeuceMode
        pickleballTargetScore = draft.pickleballTargetScore
        pickleballUseRallyScoring = draft.pickleballUseRallyScoring
        eightBallTargetRacks = draft.eightBallTargetRacks
        eightBallHandicapRacks = draft.eightBallHandicapRacks
        eightBallHandicapBeneficiary = draft.eightBallHandicapBeneficiary
    }
}

enum WatchSetupPayloadMapper {
    static func resolvedPlayerNames(_ config: WatchScoreboardLaunchConfig) -> [String] {
        let count = config.sport.isDoubles ? 4 : config.playerCount
        let fallbacks: [String]
        if config.sport.isDoubles {
            fallbacks = [
                localized("watch_setup_red_a", "红A"),
                localized("watch_setup_red_b", "红B"),
                localized("watch_setup_blue_a", "蓝A"),
                localized("watch_setup_blue_b", "蓝B")
            ]
        } else if config.sport == .nineBall {
            fallbacks = (1...count).map {
                String.localizedStringWithFormat(
                    NSLocalizedString("watch_setup_player_number", value: "选手 %d", comment: ""),
                    $0
                )
            }
        } else {
            fallbacks = [
                localized("watch_team_red", "红方"),
                localized("watch_team_blue", "蓝方")
            ]
        }

        return (0..<count).map { index in
            let entered = config.playerNames.indices.contains(index)
                ? config.playerNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return entered.isEmpty ? fallbacks[index] : entered
        }
    }

    static func rallyState(for config: WatchScoreboardLaunchConfig) -> RallyMatchState? {
        let names = resolvedPlayerNames(config)
        let gameType: GameType
        var rules: RallyRuleSet
        var doubles: RallyDoublesState?

        switch config.sport {
        case .badminton, .badmintonDoubles:
            gameType = config.sport.isDoubles ? .badmintonDoubles : .badminton
            rules = .badminton(maxSets: config.maxSets)
            rules.pointsToWinSet = config.pointsPerSet
            rules.pointCap = RallyRuleSet.badmintonPointCap(for: config.pointsPerSet)
            rules.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(
                for: gameType,
                pointsPerSet: config.pointsPerSet
            )
            doubles = config.sport.isDoubles
                ? .badminton(playerNames: interleavedDoublesNames(names), servingTeam0: true)
                : nil
        case .pingpong, .pingpongDoubles:
            gameType = config.sport.isDoubles ? .pingpongDoubles : .pingpong
            rules = .pingPong(maxSets: config.maxSets)
            rules.pointsToWinSet = config.pointsPerSet
            rules.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(
                for: gameType,
                pointsPerSet: config.pointsPerSet
            )
            doubles = config.sport.isDoubles
                ? .pingPong(
                    playerNames: interleavedDoublesNames(names),
                    openingServerSlotIndex: 0,
                    openingReceiverSlotIndex: 1
                )
                : nil
        case .pickleball, .pickleballDoubles:
            gameType = config.sport.isDoubles ? .pickleballDoubles : .pickleball
            rules = .pickleball(maxSets: config.maxSets)
            rules.pointsToWinSet = config.pickleballTargetScore
            rules.useRallyScoring = config.pickleballUseRallyScoring
            rules.nextSetServerModel = config.sport.isDoubles ? .alternateFromOpening : .opening
            doubles = config.sport.isDoubles
                ? .pickleball(playerNames: interleavedDoublesNames(names), servingTeam0: true)
                : nil
        default:
            return nil
        }

        rules.autoChangeSides = false
        let teamNames = resolvedTeamNames(names, doubles: config.sport.isDoubles)
        return RallyMatchEngine.initial(
            leftName: teamNames.left,
            rightName: teamNames.right,
            rules: rules,
            openingServer: .left,
            doubles: doubles
        )
    }

    static func tennisState(for config: WatchScoreboardLaunchConfig) -> TennisMatchState? {
        guard config.sport == .tennis || config.sport == .tennisDoubles else { return nil }
        let names = resolvedPlayerNames(config)
        let teamNames = resolvedTeamNames(names, doubles: config.sport.isDoubles)
        let rules = TennisRuleSet(
            maxSets: config.maxSets,
            usesNoAdScoring: config.tennisDeuceMode == "no_ad",
            autoChangeSides: false
        )
        return TennisMatchState(
            leftName: teamNames.left,
            rightName: teamNames.right,
            rules: rules,
            openingServer: .left,
            doublesPlayerNames: config.sport.isDoubles ? interleavedDoublesNames(names) : nil
        )
    }

    static func archeryState(for config: WatchScoreboardLaunchConfig) -> LinkedArcheryState? {
        guard config.sport == .archery else { return nil }
        let names = resolvedPlayerNames(config)
        return LinkedArcheryState(leftName: names[0], rightName: names[1])
    }

    static func eightBallState(for config: WatchScoreboardLaunchConfig) -> EightBallState? {
        guard config.sport == .eightBall else { return nil }
        let beneficiary: MatchSide?
        switch config.eightBallHandicapBeneficiary {
        case .team1: beneficiary = .left
        case .team2: beneficiary = .right
        case .none: beneficiary = nil
        }
        return .initial(
            targetPoints: config.eightBallTargetRacks,
            handicapRacks: beneficiary == nil ? 0 : config.eightBallHandicapRacks,
            handicapBeneficiary: beneficiary
        )
    }

    static func nineBallState(for config: WatchScoreboardLaunchConfig) -> NineBallChaseState? {
        guard config.sport == .nineBall else { return nil }
        return .initial(
            playerCount: min(4, max(2, config.playerCount)),
            playerNames: resolvedPlayerNames(config)
        )
    }

    static func snookerState(for config: WatchScoreboardLaunchConfig) -> SnookerState? {
        guard config.sport == .snooker else { return nil }
        return .initial(maxFrames: config.maxSets)
    }

    static func twoSideNames(for config: WatchScoreboardLaunchConfig) -> (left: String, right: String) {
        let names = resolvedPlayerNames(config)
        return resolvedTeamNames(names, doubles: config.sport.isDoubles)
    }

    private static func interleavedDoublesNames(_ names: [String]) -> [String] {
        [names[0], names[2], names[1], names[3]]
    }

    private static func resolvedTeamNames(
        _ names: [String],
        doubles: Bool
    ) -> (left: String, right: String) {
        guard doubles else { return (names[0], names[1]) }
        return ("\(names[0])/\(names[1])", "\(names[2])/\(names[3])")
    }

    private static func localized(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "")
    }
}
