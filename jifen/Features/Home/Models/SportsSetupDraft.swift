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
    var participantSelections: [String: ParticipantSelection] = [:]

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
    var showMatchTime = false
    var competitionFormat: CompetitionFormat = .singles
    var softTennisMatchGames = 7
    var padelDeuceMode: PadelDeuceMode = .starPoint
    var footballHalfLengthSeconds = 45 * 60
    var matchTitleEnabled = false
    var matchTitle = ""

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
    var team1Player3Name = ""
    var team2Player3Name = ""
}

extension SportsSetupDraft {
    private static func defaultCompetitionFormat(for gameType: GameType, isSingles: Bool) -> CompetitionFormat {
        switch gameType {
        case .shuttlecock:
            return .team
        case .softTennis, .padel:
            return .doubles
        case .squash:
            return .singles
        default:
            return isSingles ? .singles : .doubles
        }
    }

    mutating func initialize(
        gameType: GameType,
        initialSetup: SportsSetupResult?,
        initialMaxSets: Int?,
        initialPointsPerSet: Int?,
        initialTieBreakPoints: Int?,
        preferences: PreferencesManager = .shared
    ) {
        participantSelections = initialSetup?.participantSelections ?? [:]
        let setup = initialSetup
        let defaultSingles = gameType != .foosball && gameType != .shuttlecock && gameType != .softTennis && gameType != .padel
        isSingles = setup?.isSingles
            ?? setup?.competitionFormat.map { $0 == .singles }
            ?? defaultSingles
        competitionFormat = setup?.competitionFormat ?? Self.defaultCompetitionFormat(for: gameType, isSingles: isSingles)
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
        if gameType == .shuttlecock, competitionFormat == .team {
            let defaults = DefaultParticipantNames.shuttlecockTeamMembers
            team1Player1Name = setup?.team1Player1Name ?? defaults[0]
            team1Player2Name = setup?.team1Player2Name ?? defaults[1]
            team1Player3Name = setup?.team1Player3Name ?? defaults[2]
            team2Player1Name = setup?.team2Player1Name ?? defaults[3]
            team2Player2Name = setup?.team2Player2Name ?? defaults[4]
            team2Player3Name = setup?.team2Player3Name ?? defaults[5]
        }

        selectedMaxSets = (gameType == .boxing ? setup?.maxRounds : setup?.maxSets)
            ?? initialMaxSets
            ?? Self.defaultMaxSets(for: gameType)
            ?? 0
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
        showMatchTime = setup?.showMatchTime ?? (
            ScoreboardMatchTimePolicy.loadsSportsSetupPreference(for: gameType)
                ? preferences.scoreboardMatchTimeVisible(for: gameType)
                : false
        )
        softTennisMatchGames = [7, 9].contains(setup?.softTennisMatchGames ?? 7) ? (setup?.softTennisMatchGames ?? 7) : 7
        padelDeuceMode = setup?.padelDeuceMode ?? .starPoint
        let defaultFootballLength = gameType == .football5v5 ? 20 * 60 : 45 * 60
        footballHalfLengthSeconds = min(90 * 60, max(60, setup?.footballHalfLengthSeconds ?? defaultFootballLength))
        matchTitle = ScoreboardMatchTitlePolicy.limitInput(setup?.matchTitle ?? "")
        matchTitleEnabled = ScoreboardMatchTitlePolicy.sanitize(setup?.matchTitle) != nil
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
        if setup == nil {
            syncPickleballTargetForSets(gameType: gameType)
        }
    }

    mutating func syncPickleballTargetForSets(gameType: GameType) {
        guard gameType == .pickleball else { return }
        let next = selectedMaxSets == 1 ? 15 : 11
        pickleballTargetScore = next
        if next != 11 {
            pickleballScoreCap = nil
        }
    }

    mutating func selectMatchCompletionPreset(_ sets: Int, gameType: GameType) {
        selectedMaxSets = sets
        customMaxSetsText = ""
        syncPickleballTargetForSets(gameType: gameType)
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
            return "\(first)/\(second)"
        }
        return first.isEmpty ? second : first
    }

    func pointPresets(for gameType: GameType) -> [Int] {
        if gameType == .pingpong { return [5, 7, 9, 11] }
        if gameType == .foosball { return [5, 7, 8] }
        return [11, 15, 21]
    }

    /// 对齐安卓 `setupMaxSetsPresets`：每个分支固定 4 个预设。
    /// 「4 预设 + 自定义铅笔 chip」在手机内容宽下仍是一行，点开输入框后也不会换行；
    /// 打满模式原先的第 5 个预设（5 局）改由自定义输入承接，1~99 的可选范围不变。
    func matchCompletionPresets(for gameType: GameType) -> [Int] {
        if gameType == .foosball { return [1, 3, 5, 7] }
        return matchCompletionMode == .playAll ? [1, 2, 3, 4] : [1, 3, 5, 7]
    }

    func frameCountPresets(for gameType: GameType) -> [Int] {
        switch gameType {
        case .eightBall, .billiards:
            return [1, 3, 5, 7, 9, 11]
        case .snooker:
            return [1, 3, 5, 7, 9, 11, 15, 17, 19, 25, 33, 35]
        default:
            return matchCompletionPresets(for: gameType)
        }
    }

    func hasValidPointsPerSet(for gameType: GameType) -> Bool {
        guard gameType == .pingpong || gameType == .badminton || gameType == .shuttlecock || gameType == .foosball else {
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

    /// 数值类约束在开赛时静默纠正（对齐安卓 `SetupInputCorrection`），不再红字拦截。
    /// 不静默改名：个人项目的同名提示、重复身份拦截由调用方处理。

    /// 奇数局是否为硬约束（经典模式「五局三胜」、斯诺克帧数）。
    func requiresOddSets(for gameType: GameType) -> Bool {
        // 网球抢七制只用 1 盘，不读局数，纠正与提示都无意义。
        if gameType == .tennis, tennisSetScoringMode == "tiebreak_only" { return false }
        let supportsBestOf = [.pingpong, .badminton, .tennis, .squash, .pickleball, .foosball].contains(gameType)
        return (supportsBestOf && matchCompletionMode == .bestOf) || gameType == .snooker
    }

    /// 「开赛时会被纠正」的局数原始值；用于判断是否要给一次提示。
    func oddSetsCorrectionApplied(for gameType: GameType) -> (raw: Int, corrected: Int)? {
        guard requiresOddSets(for: gameType) else { return nil }
        let raw = selectedMaxSets
        guard (1...99).contains(raw), raw.isMultiple(of: 2) else { return nil }
        return (raw, min(99, raw + 1))
    }

    /// 开赛时最终使用的局数：偶数局向上取奇数，其余情况保持原值。
    func correctedMaxSets(for gameType: GameType) -> Int {
        let fallback = Self.defaultMaxSets(for: gameType) ?? 3
        let raw = selectedMaxSets > 0 ? String(selectedMaxSets) : nil
        return SetupInputCorrection.sets(raw, oddOnly: requiresOddSets(for: gameType), fallback: fallback)
    }

    func makeResult(gameType: GameType, usesDoublesPlayerInputs: Bool, voiceSupported: Bool = SportsVoiceSupport.isSupported) -> SportsSetupResult {
        let usesTeamPlayerInputs = gameType == .shuttlecock && competitionFormat == .team
        let usesNamedPlayerInputs = usesDoublesPlayerInputs || usesTeamPlayerInputs
        let resolvedTeam1Name = usesTeamPlayerInputs
            ? buildCompetitionTeamName([team1Player1Name, team1Player2Name, team1Player3Name])
            : (usesDoublesPlayerInputs
                ? buildDoublesTeamName(team1Player1Name, team1Player2Name, gameType: gameType)
                : team1Name.trimmingCharacters(in: .whitespacesAndNewlines))
        let resolvedTeam2Name = usesTeamPlayerInputs
            ? buildCompetitionTeamName([team2Player1Name, team2Player2Name, team2Player3Name])
            : (usesDoublesPlayerInputs
                ? buildDoublesTeamName(team2Player1Name, team2Player2Name, gameType: gameType)
                : team2Name.trimmingCharacters(in: .whitespacesAndNewlines))

        // 数值输入在下发引擎前统一夹到合法区间（对齐安卓 SetupInputCorrection）。
        let resolvedMaxSets = correctedMaxSets(for: gameType)
        let pointsMaximum = gameType == .foosball ? 99 : 999
        let resolvedPointsPerSet = SetupInputCorrection.pointsPerSet(
            selectedPointsPerSet > 0 ? String(selectedPointsPerSet) : nil,
            max: pointsMaximum,
            fallback: Self.defaultPointsPerSet(for: gameType) ?? 11
        )
        let resolvedFoosballScoreCap = SetupInputCorrection.scoreCap(
            foosballScoreCap.map(String.init),
            pointsPerSet: resolvedPointsPerSet,
            enabled: foosballWinByTwo
        )

        var result = SportsSetupResult(
            team1Name: resolvedTeam1Name,
            team2Name: resolvedTeam2Name,
            team1Player1Name: usesNamedPlayerInputs
                ? team1Player1Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            team1Player2Name: usesNamedPlayerInputs
                ? team1Player2Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            team2Player1Name: usesNamedPlayerInputs
                ? team2Player1Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            team2Player2Name: usesNamedPlayerInputs
                ? team2Player2Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            team1Player3Name: usesTeamPlayerInputs
                ? team1Player3Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            team2Player3Name: usesTeamPlayerInputs
                ? team2Player3Name.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
        )

        switch gameType {
        case .basketball:
            result.basketballMode = "five_v_five"
            result.basketballRuleSet = basketballRuleSet
        case .boxing:
            result.maxRounds = SetupInputCorrection.boxingRounds(selectedMaxSets > 0 ? String(selectedMaxSets) : nil, fallback: 3)
        case .pingpong:
            result.maxSets = resolvedMaxSets
            result.matchCompletionMode = matchCompletionMode
            result.pointsPerSet = resolvedPointsPerSet
            result.autoChangeSides = autoChangeSides
            result.isSingles = isSingles
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
            if ScoreboardMatchTimePolicy.includesSportsSetupValue(
                for: gameType,
                isSingles: isSingles
            ) {
                result.showMatchTime = showMatchTime
            }
        case .tennis:
            result.maxSets = tennisSetScoringMode == "tiebreak_only" ? 1 : resolvedMaxSets
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
        case .softTennis:
            result.maxSets = 1
            result.matchCompletionMode = .bestOf
            result.gamesPerSet = 4
            result.tieBreakPoints = 7
            result.tennisDeuceMode = "advantage"
            result.softTennisMatchGames = [7, 9].contains(softTennisMatchGames) ? softTennisMatchGames : 7
            result.competitionFormat = isSingles ? .singles : .doubles
            result.isSingles = isSingles
            result.autoChangeSides = autoChangeSides
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
            result.ruleProfileVersion = 1
        case .padel:
            result.maxSets = resolvedMaxSets
            result.matchCompletionMode = .bestOf
            result.gamesPerSet = 6
            result.tieBreakPoints = 7
            result.tennisDeuceMode = padelDeuceMode.rawValue
            result.competitionFormat = .doubles
            result.isSingles = false
            result.padelDeuceMode = padelDeuceMode
            result.autoChangeSides = autoChangeSides
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
            result.ruleProfileVersion = 1
        case .badminton:
            result.maxSets = resolvedMaxSets
            result.matchCompletionMode = matchCompletionMode
            result.autoChangeSides = autoChangeSides
            result.isSingles = isSingles
            result.pointsPerSet = resolvedPointsPerSet
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
        case .shuttlecock:
            result.maxSets = 3
            result.matchCompletionMode = .bestOf
            result.pointsPerSet = resolvedPointsPerSet
            result.competitionFormat = competitionFormat
            result.isSingles = competitionFormat == .singles
            result.autoChangeSides = autoChangeSides
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
            result.ruleProfileVersion = 1
        case .squash:
            result.maxSets = resolvedMaxSets
            result.matchCompletionMode = matchCompletionMode
            result.competitionFormat = .singles
            result.isSingles = true
            result.autoChangeSides = autoChangeSides
            result.servingSide = servingSide.rawValue
            result.voiceAnnouncement = voiceAnnouncement
            result.ruleProfileVersion = 1
        case .football, .football5v5:
            result.footballHalfLengthSeconds = footballHalfLengthSeconds
            result.showMatchTime = true
            result.ruleProfileVersion = 1
        case .pickleball:
            result.maxSets = resolvedMaxSets
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
            result.maxSets = resolvedMaxSets
            result.matchCompletionMode = matchCompletionMode
            result.pointsPerSet = resolvedPointsPerSet
            result.targetScore = result.pointsPerSet
            result.winByTwo = foosballWinByTwo
            result.scoreCap = resolvedFoosballScoreCap
            result.servingSide = servingSide.rawValue
        case .volleyball, .beachVolleyball, .airVolleyball:
            result.autoChangeSides = autoChangeSides
            result.servingSide = servingSide.rawValue
            result.showMatchTime = showMatchTime
        case .snooker:
            result.maxSets = resolvedMaxSets
            result.servingSide = servingSide.rawValue
            result.matchTitle = matchTitleEnabled ? ScoreboardMatchTitlePolicy.sanitize(matchTitle) : nil
        case .eightBall:
            // 目标局与让局都静默纠正（对齐安卓 normalizeEightBallHandicapRacks）。
            let target = SetupInputCorrection.billiardsTarget(
                selectedMaxSets > 0 ? String(selectedMaxSets) : nil,
                fallback: Self.defaultMaxSets(for: .eightBall) ?? 9
            )
            result.maxSets = target
            let beneficiaryValid = eightBallHandicapMode == "team1" || eightBallHandicapMode == "team2"
            let handicap = (!beneficiaryValid || target <= 1)
                ? 0
                : min(max(eightBallHandicapRacks, 1), target - 1)
            result.eightBallHandicapRacks = handicap
            result.eightBallHandicapBeneficiary = handicap > 0 ? eightBallHandicapMode : "none"
        case .archery:
            result.servingSide = servingSide.rawValue
        default:
            break
        }

        // 语音播报开关统一写入：矩阵包含该功能的项目才输出（对齐安卓）。
        if SportsSetupMatchFeature.features(for: gameType, isSingles: isSingles)
            .contains(.voiceAnnouncement) {
            result.voiceAnnouncement = voiceSupported && voiceAnnouncement
        }

        let identity = validParticipantSelections(gameType: gameType)
        result.participantSelections = identity.isEmpty ? nil : identity
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

    private func buildCompetitionTeamName(_ names: [String]) -> String {
        names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    static func defaultMaxSets(for gameType: GameType) -> Int? {
        switch gameType {
        case .pingpong: return 5
        case .badminton, .shuttlecock, .pickleball, .boxing, .foosball, .tennis, .padel: return 3
        case .squash: return 5
        case .snooker: return 1
        case .eightBall: return 9
        default: return nil
        }
    }

    private static func defaultPointsPerSet(for gameType: GameType) -> Int? {
        switch gameType {
        case .pingpong: return 11
        case .badminton, .shuttlecock: return 21
        case .foosball: return 5
        default: return nil
        }
    }

    private static func defaultTieBreakPoints(for gameType: GameType) -> Int? {
        gameType == .tennis ? 7 : nil
    }
}

/// 对齐安卓 `SetupInputCorrection`：自定义输入不再红字报错 + 禁用「开始」，
/// 而是在开赛时把输入夹到合法区间，让「开始」始终可用。
///
/// 每条规则都返回**最终会传给引擎的值**，调用方不需要再二次判断合法性。
nonisolated enum SetupInputCorrection {
    /// 通用数字区间：空 / 非数字 / 0 都回落到 `fallback`。
    /// 0 视为「还没填」而不是「最小值 1」，否则用户清空后点开始会静默变成 1 局/1 分。
    static func numberInRange(_ raw: String?, _ range: ClosedRange<Int>, fallback: Int) -> Int {
        guard let parsed = Int(raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              parsed > 0 else { return fallback }
        return min(max(parsed, range.lowerBound), range.upperBound)
    }

    /// 局数（1...99）。`oddOnly` 为 true 时向上取奇数（经典模式「五局三胜」这类赛制要求奇数局），
    /// 99 已是上限时回落到 99，避免夹到 100 越界。
    static func sets(_ raw: String?, oddOnly: Bool, fallback: Int) -> Int {
        let bounded = numberInRange(raw, 1...99, fallback: fallback)
        guard oddOnly, bounded.isMultiple(of: 2) else { return bounded }
        return bounded >= 99 ? 99 : bounded + 1
    }

    /// 每局分数：羽毛球/乒乓球 1...999，桌上足球 1...99。
    static func pointsPerSet(_ raw: String?, max: Int, fallback: Int) -> Int {
        numberInRange(raw, 1...max, fallback: fallback)
    }

    /// 桌上足球分差上限：必须不小于目标分、且不超过 99。
    /// 未开启「末局净胜两分」时没有上限，返回 nil。
    static func scoreCap(_ raw: String?, pointsPerSet: Int, enabled: Bool) -> Int? {
        guard enabled else { return nil }
        let lower = min(max(pointsPerSet, 1), 99)
        return numberInRange(raw, lower...99, fallback: lower)
    }

    /// 台球目标局/分：1...99。
    static func billiardsTarget(_ raw: String?, fallback: Int) -> Int {
        numberInRange(raw, 1...99, fallback: fallback)
    }

    /// 九球追分各项分值：1...99。
    static func nineBallPoint(_ raw: String?, fallback: Int) -> Int {
        numberInRange(raw, 1...99, fallback: fallback)
    }

    /// 拳击回合数：1...99（非预设时使用）。
    static func boxingRounds(_ raw: String?, fallback: Int) -> Int {
        numberInRange(raw, 1...99, fallback: fallback)
    }
}
