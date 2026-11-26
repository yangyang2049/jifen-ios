import Foundation
import LinkCore
import ScoreCore

enum WatchSetupSport: String, CaseIterable, Hashable {
    // Keep regulation basketball out of local setup. The Watch implementation
    // is retained solely for phone-initiated 3x3/5v5 linked sessions.
    case badminton
    case badmintonDoubles
    case pingpong
    case pingpongDoubles
    case tennis
    case tennisDoubles
    case pickleball
    case pickleballDoubles
    case shuttlecock
    case squash
    case foosball
    case archery
    case eightBall
    case nineBall
    case snooker
    case football
    case football5v5

    /// Watch-level game identity used for artwork and record mapping.
    var gameType: WatchGameType {
        switch self {
        case .badminton, .badmintonDoubles: return .badminton
        case .shuttlecock: return .shuttlecock
        case .squash: return .squash
        case .foosball: return .foosball
        case .pingpong, .pingpongDoubles: return .pingpong
        case .tennis, .tennisDoubles: return .tennis
        case .pickleball, .pickleballDoubles: return .pickleball
        case .archery: return .archery
        case .eightBall: return .eightBall
        case .nineBall: return .nineBall
        case .snooker: return .snooker
        case .football: return .football
        case .football5v5: return .football5v5
        }
    }

    var isFootball: Bool {
        self == .football || self == .football5v5
    }

    /// Phone defaults: 45 minutes per half for football, 20 for 5×5.
    var defaultFootballHalfLengthMinutes: Int {
        self == .football5v5 ? 20 : 45
    }

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
    var footballHalfLengthMinutes: Int
    /// 桌上足球：决胜局净胜 2 分（对齐手机 foosballWinByTwo）。
    var foosballWinByTwo: Bool = false
    /// 桌上足球：净胜 2 分时的封顶分（nil 表示不封顶）。
    var foosballScoreCap: Int? = nil
    /// 开球/发球方（对齐手机 servingSide："left" / "right"）。
    var servingSide: String = "left"

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
        footballHalfLengthMinutes = sport.defaultFootballHalfLengthMinutes
        foosballWinByTwo = false
        foosballScoreCap = nil
        servingSide = "left"

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
        case .shuttlecock:
            maxSets = preferences.allowedInt(
                forKey: "watchShuttlecockSetupMaxSets",
                defaultValue: 3,
                allowed: [1, 3, 5]
            )
            pointsPerSet = preferences.allowedInt(
                forKey: "watchShuttlecockSetupPointsPerSet",
                defaultValue: 21,
                allowed: [11, 15, 21]
            )
        case .squash:
            maxSets = preferences.allowedInt(
                forKey: "watchSquashSetupMaxSets",
                defaultValue: 5,
                allowed: [1, 3, 5, 7]
            )
            pointsPerSet = 11
        case .foosball:
            maxSets = preferences.allowedInt(
                forKey: "watchFoosballSetupMaxSets",
                defaultValue: 3,
                allowed: [1, 3, 5, 7]
            )
            pointsPerSet = preferences.allowedInt(
                forKey: "watchFoosballSetupPointsPerSet",
                defaultValue: 5,
                allowed: [5, 7, 8]
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
            let storedRacks = preferences.int(forKey: "watchEightBallSetupTargetRacks", defaultValue: 5)
            eightBallTargetRacks = Self.eightBallRackOptions.contains(storedRacks) ? storedRacks : 5
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
        case .football, .football5v5:
            maxSets = 0
            pointsPerSet = 0
            footballHalfLengthMinutes = Self.normalizedFootballHalfLengthMinutes(
                preferences.int(
                    forKey: Self.footballHalfLengthMinutesKey,
                    defaultValue: sport.defaultFootballHalfLengthMinutes
                )
            )
        case .archery, .nineBall:
            maxSets = 0
            pointsPerSet = 0
        }
    }

    var pingpongPointOptions: [Int] {
        let presets = [7, 9, 11, 15]
        // Keep a saved legacy value visible until the player chooses a new preset.
        return presets.contains(pointsPerSet) ? presets : (presets + [pointsPerSet]).sorted()
    }

    /// 「抢局」档位：数字即先赢几局（与手机端一致，对齐黑八 targetPoints 语义）。
    static let eightBallRackOptions = [3, 5, 7, 13]
    static let snookerFrameOptions = [1, 3, 5, 7, 9, 11, 15, 17, 19, 25, 33, 35]
    static let footballHalfLengthMinutesKey = "watchFootballSetupHalfLengthMinutes"
    /// Phone allows 1-90 minutes; the watch offers a compact chip set.
    static let footballHalfLengthMinuteOptions = [5, 10, 15, 20, 25, 30, 45, 60, 90]

    /// Keeps the sport's default (and the current selection) near the start of
    /// the horizontal chip row so the active value is visible without scrolling.
    static func footballHalfLengthOptions(for sport: WatchSetupSport) -> [Int] {
        let preferred = sport.defaultFootballHalfLengthMinutes
        return footballHalfLengthMinuteOptions.sorted {
            let left = abs($0 - preferred)
            let right = abs($1 - preferred)
            return left == right ? $0 < $1 : left < right
        }
    }

    static func normalizedFootballHalfLengthMinutes(_ minutes: Int) -> Int {
        let clamped = min(90, max(1, minutes))
        return footballHalfLengthMinuteOptions.min {
            abs($0 - clamped) < abs($1 - clamped)
        } ?? clamped
    }

    static func maxEightBallHandicap(for targetRacks: Int) -> Int {
        max(0, targetRacks - 1)
    }

    mutating func normalizeEightBallHandicap() {
        guard eightBallTargetRacks > 1 else {
            eightBallHandicapRacks = 0
            eightBallHandicapBeneficiary = .none
            return
        }
        let maximum = Self.maxEightBallHandicap(for: eightBallTargetRacks)
        let minimum = eightBallHandicapBeneficiary == .none ? 0 : 1
        eightBallHandicapRacks = min(maximum, max(minimum, eightBallHandicapRacks))
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
        case .shuttlecock:
            preferences.setInt(maxSets, forKey: "watchShuttlecockSetupMaxSets")
            preferences.setInt(pointsPerSet, forKey: "watchShuttlecockSetupPointsPerSet")
        case .squash:
            preferences.setInt(maxSets, forKey: "watchSquashSetupMaxSets")
        case .foosball:
            preferences.setInt(maxSets, forKey: "watchFoosballSetupMaxSets")
            preferences.setInt(pointsPerSet, forKey: "watchFoosballSetupPointsPerSet")
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
        case .football, .football5v5:
            preferences.setInt(footballHalfLengthMinutes, forKey: Self.footballHalfLengthMinutesKey)
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
    let footballHalfLengthSeconds: Int
    let foosballWinByTwo: Bool
    let foosballScoreCap: Int?
    let servingSide: String

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
        footballHalfLengthSeconds = max(60, draft.footballHalfLengthMinutes * 60)
        foosballWinByTwo = draft.foosballWinByTwo
        foosballScoreCap = draft.foosballScoreCap
        servingSide = draft.servingSide
    }
}

enum WatchSetupPayloadMapper {
    static func resolvedPlayerNames(_ config: WatchScoreboardLaunchConfig) -> [String] {
        let count = config.sport.isDoubles ? 4 : config.playerCount

        return (0..<count).map { index in
            let entered = config.playerNames.indices.contains(index)
                ? config.playerNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return entered.isEmpty
                ? WatchDefaultTeamNames.setupParticipantName(for: config.sport, index: index)
                : entered
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
                    openingReceiverSlotIndex: 3
                )
                : nil
        case .shuttlecock:
            gameType = .shuttlecock
            rules = .shuttlecock(maxSets: config.maxSets)
            rules.pointsToWinSet = config.pointsPerSet
            rules.decidingSetSideSwitchPoint = max(1, (config.pointsPerSet + 1) / 2)
        case .squash:
            gameType = .squash
            rules = .squash(maxSets: config.maxSets)
        case .foosball:
            gameType = .foosball
            rules = .foosball(maxSets: config.maxSets)
            rules.pointsToWinSet = config.pointsPerSet
            // 对齐手机 SportsSetupResult.foosballRules：净胜 2 分与封顶分只作用于决胜局。
            rules.finalSetWinByTwo = config.foosballWinByTwo
            rules.finalSetPointCap = config.foosballWinByTwo
                ? config.foosballScoreCap.flatMap {
                    ($0 >= config.pointsPerSet && $0 <= 99) ? $0 : nil
                }
                : nil
        case .pickleball, .pickleballDoubles:
            gameType = config.sport.isDoubles ? .pickleballDoubles : .pickleball
            rules = .pickleball(maxSets: config.maxSets)
            rules.pointsToWinSet = config.pickleballTargetScore
            rules.useRallyScoring = config.pickleballUseRallyScoring
            rules.nextSetServerModel = .alternateFromOpening
            doubles = config.sport.isDoubles
                ? .pickleball(playerNames: interleavedDoublesNames(names), servingTeam0: true)
                : nil
        default:
            return nil
        }

        rules.autoChangeSides = false
        let teamNames = resolvedTeamNames(names, sport: config.sport)
        return RallyMatchEngine.initial(
            leftName: teamNames.left,
            rightName: teamNames.right,
            rules: rules,
            openingServer: config.servingSide == "right" ? .right : .left,
            doubles: doubles
        )
    }

    static func tennisState(for config: WatchScoreboardLaunchConfig) -> TennisMatchState? {
        guard config.sport == .tennis || config.sport == .tennisDoubles else { return nil }
        let names = resolvedPlayerNames(config)
        let teamNames = resolvedTeamNames(names, sport: config.sport)
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

    static func footballClockState(for config: WatchScoreboardLaunchConfig) -> FootballTimerStateV2? {
        guard config.sport.isFootball else { return nil }
        return FootballTimerStateV2(halfLengthSeconds: max(60, config.footballHalfLengthSeconds))
    }

    static func footballGameType(for config: WatchScoreboardLaunchConfig) -> GameType? {
        guard config.sport.isFootball else { return nil }
        return config.sport == .football5v5 ? .football5v5 : .football
    }

    static func twoSideNames(for config: WatchScoreboardLaunchConfig) -> (left: String, right: String) {
        let names = resolvedPlayerNames(config)
        return resolvedTeamNames(names, sport: config.sport)
    }

    private static func interleavedDoublesNames(_ names: [String]) -> [String] {
        [names[0], names[2], names[1], names[3]]
    }

    private static func resolvedTeamNames(
        _ names: [String],
        sport: WatchSetupSport
    ) -> (left: String, right: String) {
        guard sport.isDoubles else { return (names[0], names[1]) }
        let sides = WatchDefaultTeamNames.doublesSideNames(for: sport, members: names)
        return (sides.left, sides.right)
    }
}
