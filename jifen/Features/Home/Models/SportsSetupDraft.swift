import Foundation
import ScoreCore

/// Mutable form values for the phone sports-setup flow.
///
/// Presentation-only state such as alerts, sheets and progress indicators stays
/// in `SportsSetupDialogView`; this value contains only data that contributes to
/// validation or the resulting `SportsSetupResult`.
struct SportsSetupDraft: Equatable {
    var team1Name = ""
    var team2Name = ""

    var selectedMaxSets = 0
    var selectedPointsPerSet = 0
    var regularTieBreakPoints = 7
    var matchTieBreakPoints = 7
    var tennisGamesPerSet = 6
    var tennisSetScoringMode = "regular"
    var matchCompletionMode: MatchCompletionMode = .bestOf
    var customMaxSetsText = ""
    var customPointsText = ""

    var autoChangeSides = true
    var isSingles = true
    var basketballRuleSet = "fiba"
    var customFoosballScoreCapText = ""
    var tennisDeuceMode = "advantage"
    var servingSide: MatchSide = .left
    var voiceAnnouncement = false

    var pickleballTargetScore = 11
    var pickleballScoreCap: Int?
    var pickleballUseRallyScoring = false
    var foosballWinByTwo = false
    var foosballScoreCap: Int?
    var eightBallHandicapMode = "none"
    var eightBallHandicapRacks = 0

    var team1Player1Name = ""
    var team1Player2Name = ""
    var team2Player1Name = ""
    var team2Player2Name = ""
}

extension SportsSetupDraft {
    mutating func initialize(
        gameType: GameType,
        initialSetup: SportsSetupResult?,
        initialMaxSets: Int?,
        initialPointsPerSet: Int?,
        initialTieBreakPoints: Int?
    ) {
        let setup = initialSetup
        isSingles = setup?.isSingles ?? (gameType != .foosball)
        let modeDefaults = DefaultParticipantNames.resolve(for: gameType, isSingles: isSingles)
        team1Name = setup?.team1Name ?? modeDefaults.left
        team2Name = setup?.team2Name ?? modeDefaults.right
        if isSingles {
            syncDoublesPlayerNamesFromTeamNames()
        } else if setup == nil {
            applyDefaultDoublesMembers()
        } else {
            syncDoublesPlayerNamesFromTeamNames()
            team1Player1Name = setup?.team1Player1Name ?? team1Player1Name
            team1Player2Name = setup?.team1Player2Name ?? team1Player2Name
            team2Player1Name = setup?.team2Player1Name ?? team2Player1Name
            team2Player2Name = setup?.team2Player2Name ?? team2Player2Name
        }

        selectedMaxSets = setup?.maxSets ?? initialMaxSets ?? Self.defaultMaxSets(for: gameType) ?? 0
        customMaxSetsText = frameCountPresets(for: gameType).contains(selectedMaxSets) ? "" : (
            selectedMaxSets > 0 ? String(selectedMaxSets) : ""
        )
        selectedPointsPerSet = setup?.pointsPerSet
            ?? initialPointsPerSet
            ?? Self.defaultPointsPerSet(for: gameType)
            ?? 0
        customPointsText = pointPresets(for: gameType).contains(selectedPointsPerSet)
            ? ""
            : String(selectedPointsPerSet)
        tennisGamesPerSet = setup?.gamesPerSet == 4 ? 4 : 6
        tennisSetScoringMode = setup?.setScoringMode == "tiebreak_only" ? "tiebreak_only" : "regular"
        let restoredTieBreakPoints = setup?.tieBreakPoints
            ?? initialTieBreakPoints
            ?? Self.defaultTieBreakPoints(for: gameType)
            ?? 7
        if tennisSetScoringMode == "tiebreak_only" {
            matchTieBreakPoints = restoredTieBreakPoints == 10 ? 10 : 7
            regularTieBreakPoints = 7
        } else {
            regularTieBreakPoints = restoredTieBreakPoints == 10 ? 10 : 7
            matchTieBreakPoints = 7
        }
        matchCompletionMode = setup?.matchCompletionMode ?? .bestOf
        autoChangeSides = setup?.autoChangeSides ?? true
        basketballRuleSet = setup?.basketballRuleSet ?? "fiba"
        tennisDeuceMode = setup?.tennisDeuceMode ?? "advantage"
        servingSide = setup?.servingSide == MatchSide.right.rawValue ? .right : .left
        voiceAnnouncement = setup?.voiceAnnouncement ?? false
        pickleballTargetScore = setup?.targetScore ?? 11
        pickleballScoreCap = setup?.scoreCap
        pickleballUseRallyScoring = setup?.useRallyScoring ?? false
        foosballWinByTwo = setup?.winByTwo ?? false
        foosballScoreCap = setup?.scoreCap
        customFoosballScoreCapText = ""
        eightBallHandicapMode = setup?.eightBallHandicapBeneficiary ?? "none"
        eightBallHandicapRacks = setup?.eightBallHandicapRacks ?? 0
        if gameType == .eightBall, selectedMaxSets > 1, eightBallHandicapMode != "none" {
            eightBallHandicapRacks = min(max(1, eightBallHandicapRacks), selectedMaxSets - 1)
        }
        syncPickleballTargetForSets(gameType: gameType)
    }

    mutating func syncPickleballTargetForSets(gameType: GameType) {
        guard gameType == .pickleball else { return }
        let next = selectedMaxSets == 1 ? 15 : 11
        pickleballTargetScore = next
        if next != 11 {
            pickleballScoreCap = nil
        }
    }

    mutating func applyDefaultsWhenSwitchingToDoubles(
        gameType: GameType,
        configuredLeftName: String,
        configuredRightName: String
    ) {
        let currentLeft = team1Name.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentRight = team2Name.trimmingCharacters(in: .whitespacesAndNewlines)
        let singlesDefaults = DefaultParticipantNames.resolve(for: gameType)
        let defaults = DefaultParticipantNames.doublesMembers

        let left = DefaultParticipantNames.doublesMembersAfterModeSwitch(
            currentSideName: currentLeft,
            existingFirst: team1Player1Name,
            existingSecond: team1Player2Name,
            singlesDefaultName: singlesDefaults.left,
            configuredDefaultName: configuredLeftName,
            defaultFirst: defaults[0],
            defaultSecond: defaults[1]
        )
        let right = DefaultParticipantNames.doublesMembersAfterModeSwitch(
            currentSideName: currentRight,
            existingFirst: team2Player1Name,
            existingSecond: team2Player2Name,
            singlesDefaultName: singlesDefaults.right,
            configuredDefaultName: configuredRightName,
            defaultFirst: defaults[2],
            defaultSecond: defaults[3]
        )
        team1Player1Name = left.first
        team1Player2Name = left.second
        team2Player1Name = right.first
        team2Player2Name = right.second
        team1Name = buildDoublesTeamName(left.first, left.second, gameType: gameType)
        team2Name = buildDoublesTeamName(right.first, right.second, gameType: gameType)
    }

    mutating func applyDefaultsWhenSwitchingToSingles(gameType: GameType) {
        let currentMembers = [
            team1Player1Name,
            team1Player2Name,
            team2Player1Name,
            team2Player2Name
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let singlesDefaults = DefaultParticipantNames.resolve(for: gameType)
        if DefaultParticipantNames.areDefaultDoublesMembers(currentMembers) {
            team1Name = singlesDefaults.left
            team2Name = singlesDefaults.right
            return
        }

        team1Name = currentMembers[0].isEmpty ? singlesDefaults.left : currentMembers[0]
        team2Name = currentMembers[2].isEmpty ? singlesDefaults.right : currentMembers[2]
    }

    mutating func applyDefaultDoublesMembers() {
        let defaults = DefaultParticipantNames.doublesMembers
        team1Player1Name = defaults[0]
        team1Player2Name = defaults[1]
        team2Player1Name = defaults[2]
        team2Player2Name = defaults[3]
    }

    mutating func syncDoublesPlayerNamesFromTeamNames() {
        let left = Self.splitDoublesTeamName(team1Name)
        let right = Self.splitDoublesTeamName(team2Name)
        team1Player1Name = left.first
        team1Player2Name = left.second
        team2Player1Name = right.first
        team2Player2Name = right.second
    }

    func buildDoublesTeamName(_ player1: String, _ player2: String, gameType: GameType) -> String {
        let first = player1.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = player2.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty && !second.isEmpty {
            return gameType == .foosball ? "\(first)/\(second)" : "\(first) / \(second)"
        }
        return first.isEmpty ? second : first
    }

    func pointPresets(for gameType: GameType) -> [Int] {
        if gameType == .pingpong { return [5, 7, 9, 11, 15, 21] }
        if gameType == .foosball { return [5, 7, 8] }
        return [21, 15, 11]
    }

    var matchCompletionPresets: [Int] {
        matchCompletionMode == .playAll ? [1, 2, 3, 4, 5] : [1, 3, 5, 7]
    }

    func frameCountPresets(for gameType: GameType) -> [Int] {
        switch gameType {
        case .eightBall, .billiards:
            return [1, 3, 5, 7, 9, 11]
        case .snooker:
            return [1, 3, 5, 7, 9, 11, 15, 17, 19, 25, 33, 35]
        default:
            return matchCompletionPresets
        }
    }

    func hasValidPointsPerSet(for gameType: GameType) -> Bool {
        guard gameType == .pingpong || gameType == .badminton || gameType == .foosball else {
            return true
        }
        let maximum = gameType == .foosball ? 99 : 999
        return (1...maximum).contains(selectedPointsPerSet)
    }

    func hasValidFoosballScoreCap(for gameType: GameType) -> Bool {
        guard gameType == .foosball, foosballWinByTwo, let foosballScoreCap else {
            return true
        }
        return (selectedPointsPerSet...99).contains(foosballScoreCap)
    }

    var hasValidMatchCompletionSets: Bool {
        guard (1...99).contains(selectedMaxSets) else { return false }
        return matchCompletionMode == .playAll || !selectedMaxSets.isMultiple(of: 2)
    }

    func makeResult(gameType: GameType, usesDoublesPlayerInputs: Bool) -> SportsSetupResult {
        let resolvedTeam1Name = usesDoublesPlayerInputs
            ? buildDoublesTeamName(team1Player1Name, team1Player2Name, gameType: gameType)
            : team1Name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTeam2Name = usesDoublesPlayerInputs
            ? buildDoublesTeamName(team2Player1Name, team2Player2Name, gameType: gameType)
            : team2Name.trimmingCharacters(in: .whitespacesAndNewlines)

        var result = SportsSetupResult(
            team1Name: resolvedTeam1Name,
            team2Name: resolvedTeam2Name,
            team1Player1Name: usesDoublesPlayerInputs
                ? team1Player1Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            team1Player2Name: usesDoublesPlayerInputs
                ? team1Player2Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            team2Player1Name: usesDoublesPlayerInputs
                ? team2Player1Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            team2Player2Name: usesDoublesPlayerInputs
                ? team2Player2Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
        )

        switch gameType {
        case .basketball:
            result.basketballMode = "five_v_five"
            result.basketballRuleSet = basketballRuleSet
        case .boxing:
            result.maxRounds = selectedMaxSets > 0 ? selectedMaxSets : 3
        case .pingpong:
            result.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 5
            result.matchCompletionMode = matchCompletionMode
            result.pointsPerSet = selectedPointsPerSet > 0 ? selectedPointsPerSet : 11
            result.autoChangeSides = autoChangeSides
            result.isSingles = isSingles
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
        case .tennis:
            result.maxSets = tennisSetScoringMode == "tiebreak_only"
                ? 1
                : (selectedMaxSets > 0 ? selectedMaxSets : 3)
            result.matchCompletionMode = tennisSetScoringMode == "tiebreak_only" ? .bestOf : matchCompletionMode
            result.tieBreakPoints = tennisSetScoringMode == "tiebreak_only"
                ? matchTieBreakPoints
                : regularTieBreakPoints
            result.gamesPerSet = tennisGamesPerSet
            result.setScoringMode = tennisSetScoringMode
            result.autoChangeSides = autoChangeSides
            result.isSingles = isSingles
            result.tennisDeuceMode = tennisDeuceMode
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
        case .badminton:
            result.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 3
            result.matchCompletionMode = matchCompletionMode
            result.autoChangeSides = autoChangeSides
            result.isSingles = isSingles
            result.pointsPerSet = selectedPointsPerSet > 0 ? selectedPointsPerSet : 21
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
        case .pickleball:
            result.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 3
            result.matchCompletionMode = matchCompletionMode
            result.isSingles = isSingles
            result.targetScore = pickleballTargetScore
            result.winByTwo = true
            result.scoreCap = pickleballTargetScore == 11 ? pickleballScoreCap : nil
            result.useRallyScoring = pickleballUseRallyScoring
            result.autoChangeSides = autoChangeSides
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
        case .foosball:
            result.isSingles = isSingles
            result.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 3
            result.matchCompletionMode = matchCompletionMode
            result.pointsPerSet = selectedPointsPerSet > 0 ? selectedPointsPerSet : 5
            result.targetScore = result.pointsPerSet
            result.winByTwo = foosballWinByTwo
            result.scoreCap = foosballWinByTwo ? foosballScoreCap : nil
            result.servingSide = servingSide.rawValue
        case .volleyball, .beachVolleyball, .airVolleyball:
            result.autoChangeSides = autoChangeSides
            result.servingSide = servingSide.rawValue
        case .snooker:
            result.maxSets = selectedMaxSets > 0 ? selectedMaxSets : 1
            result.servingSide = servingSide.rawValue
        case .eightBall:
            let target = selectedMaxSets > 0 ? selectedMaxSets : 9
            result.maxSets = target
            let handicap = eightBallHandicapMode == "none"
                ? 0
                : min(eightBallHandicapRacks, max(0, target - 1))
            result.eightBallHandicapRacks = handicap
            result.eightBallHandicapBeneficiary = handicap > 0 ? eightBallHandicapMode : "none"
        case .archery:
            result.servingSide = servingSide.rawValue
        default:
            break
        }

        return result
    }

    private static func splitDoublesTeamName(_ value: String) -> (first: String, second: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", "") }
        let parts = trimmed
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.count >= 2 ? (parts[0], parts[1]) : (trimmed, "")
    }

    private static func defaultMaxSets(for gameType: GameType) -> Int? {
        switch gameType {
        case .pingpong: return 5
        case .badminton, .pickleball, .boxing, .foosball, .tennis: return 3
        case .snooker: return 1
        case .eightBall: return 9
        default: return nil
        }
    }

    private static func defaultPointsPerSet(for gameType: GameType) -> Int? {
        switch gameType {
        case .pingpong: return 11
        case .badminton: return 21
        case .foosball: return 5
        default: return nil
        }
    }

    private static func defaultTieBreakPoints(for gameType: GameType) -> Int? {
        gameType == .tennis ? 7 : nil
    }
}
