import Foundation

// MARK: - Models

public enum VoiceAnnouncementPhase: String, Sendable {
    case scoreChange = "score_change"
    case gameEnd = "game_end"
    case setEnd = "set_end"
    case matchEnd = "match_end"
    case sideChange = "side_change"
}

public enum VoiceAnnouncementLanguage: String, Sendable {
    case zhCN = "zh-CN"
    case enUS = "en-US"
}

public struct VoiceSetScore: Equatable, Sendable {
    public var leftGames: Int
    public var rightGames: Int

    public init(leftGames: Int, rightGames: Int) {
        self.leftGames = leftGames
        self.rightGames = rightGames
    }

    public func swapped() -> VoiceSetScore {
        VoiceSetScore(leftGames: rightGames, rightGames: leftGames)
    }
}

public struct VoiceAnnouncementPayload: Equatable, Sendable {
    public var gameType: GameType
    public var phase: VoiceAnnouncementPhase
    public var leftTeamName: String
    public var rightTeamName: String
    public var leftScore: Int
    public var rightScore: Int
    public var leftSets: Int
    public var rightSets: Int
    public var currentSet: Int?
    public var scoringSide: MatchSide?
    public var serverSide: MatchSide?
    public var winnerSide: MatchSide?
    public var winnerName: String?
    public var serverName: String?
    public var serviceOver: Bool
    public var isTieBreak: Bool
    public var tennisDeuceMode: String?
    public var setScores: [VoiceSetScore]

    public init(
        gameType: GameType,
        phase: VoiceAnnouncementPhase,
        leftTeamName: String,
        rightTeamName: String,
        leftScore: Int,
        rightScore: Int,
        leftSets: Int = 0,
        rightSets: Int = 0,
        currentSet: Int? = nil,
        scoringSide: MatchSide? = nil,
        serverSide: MatchSide? = nil,
        winnerSide: MatchSide? = nil,
        winnerName: String? = nil,
        serverName: String? = nil,
        serviceOver: Bool = false,
        isTieBreak: Bool = false,
        tennisDeuceMode: String? = nil,
        setScores: [VoiceSetScore] = []
    ) {
        self.gameType = gameType
        self.phase = phase
        self.leftTeamName = leftTeamName
        self.rightTeamName = rightTeamName
        self.leftScore = leftScore
        self.rightScore = rightScore
        self.leftSets = leftSets
        self.rightSets = rightSets
        self.currentSet = currentSet
        self.scoringSide = scoringSide
        self.serverSide = serverSide
        self.winnerSide = winnerSide
        self.winnerName = winnerName
        self.serverName = serverName
        self.serviceOver = serviceOver
        self.isTieBreak = isTieBreak
        self.tennisDeuceMode = tennisDeuceMode
        self.setScores = setScores
    }
}

public enum VoiceAnnouncementSupport {
    public static func isSupported(_ gameType: GameType) -> Bool {
        isBadminton(gameType) || isPingpong(gameType) || isTennis(gameType)
    }

    public static func isBadminton(_ gameType: GameType) -> Bool {
        gameType == .badminton || gameType == .badmintonDoubles
    }

    public static func isPingpong(_ gameType: GameType) -> Bool {
        gameType == .pingpong || gameType == .pingpongDoubles
    }

    public static func isTennis(_ gameType: GameType) -> Bool {
        gameType == .tennis || gameType == .tennisDoubles
    }
}

// MARK: - Message builder (BWF / ITTF / ITF — aligned with HarmonyOS)

public enum VoiceAnnouncementMessageBuilder {
    public static func build(
        _ payload: VoiceAnnouncementPayload,
        language: VoiceAnnouncementLanguage = .zhCN
    ) -> String {
        language == .enUS ? buildEnglish(payload) : buildChinese(payload)
    }

    // —— Chinese ——

    private static func buildChinese(_ payload: VoiceAnnouncementPayload) -> String {
        switch payload.phase {
        case .scoreChange:
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisScoreChangeZh(payload)
            }
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisScoreChangeZh(payload)
            }
            return buildBadmintonScoreChangeZh(payload)
        case .gameEnd:
            return VoiceAnnouncementSupport.isTennis(payload.gameType) ? buildTennisGameEndZh(payload) : ""
        case .setEnd:
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisSetEndZh(payload, isMatchEnd: false)
            }
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildRallySetEndZh(payload)
            }
            return buildRallySetEndZh(payload)
        case .matchEnd:
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisSetEndZh(payload, isMatchEnd: true)
            }
            return buildRallyMatchEndZh(payload)
        case .sideChange:
            return "交换场地"
        }
    }

    // —— English ——

    private static func buildEnglish(_ payload: VoiceAnnouncementPayload) -> String {
        switch payload.phase {
        case .scoreChange:
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisScoreChangeEn(payload)
            }
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisScoreChangeEn(payload)
            }
            return buildBadmintonScoreChangeEn(payload)
        case .gameEnd:
            return VoiceAnnouncementSupport.isTennis(payload.gameType) ? buildTennisGameEndEn(payload) : ""
        case .setEnd:
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisSetEndEn(payload, isMatchEnd: false)
            }
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisSetEndEn(payload)
            }
            return buildRallySetEndEn(payload)
        case .matchEnd:
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisSetEndEn(payload, isMatchEnd: true)
            }
            return buildRallyMatchEndEn(payload)
        case .sideChange:
            return "Change ends"
        }
    }

    // —— Badminton BWF ——

    private static func buildBadmintonScoreChangeZh(_ payload: VoiceAnnouncementPayload) -> String {
        let line = sideFirstNumericZh(payload, resolveServerSide(payload))
        return payload.serviceOver ? "换发球，\(line)" : line
    }

    private static func buildBadmintonScoreChangeEn(_ payload: VoiceAnnouncementPayload) -> String {
        let line = sideFirstNumericEn(payload, resolveServerSide(payload))
        return payload.serviceOver ? "Service over, \(line)" : line
    }

    // —— Rally set / match ——

    private static func buildRallySetEndZh(_ payload: VoiceAnnouncementPayload) -> String {
        let winnerName = getWinnerName(payload)
        let setNumber = payload.currentSet ?? 1
        let gameScore = sideFirstNumericZh(payload, resolveWinnerSide(payload))
        var message = "第\(formatSetNumberZh(setNumber))局，\(winnerName)胜，\(gameScore)"
        if payload.leftSets == payload.rightSets, payload.leftSets > 0 {
            message += "，局分\(payload.leftSets)平"
        }
        return message
    }

    private static func buildRallySetEndEn(_ payload: VoiceAnnouncementPayload) -> String {
        let winnerName = getWinnerName(payload)
        let setNumber = payload.currentSet ?? 1
        let ordinal = formatSetNumberEn(setNumber)
        let gameScore = sideFirstNumericEn(payload, resolveWinnerSide(payload))
        var message = "\(capitalizeFirst(ordinal)) game won by \(winnerName), \(gameScore)"
        if payload.leftSets == payload.rightSets, payload.leftSets > 0 {
            message += payload.leftSets == 1 ? ". One game all" : ". \(payload.leftSets) games all"
        }
        return message
    }

    private static func buildRallyMatchEndZh(_ payload: VoiceAnnouncementPayload) -> String {
        let winnerName = getWinnerName(payload)
        let winnerSide = resolveWinnerSide(payload)
        return "比赛结束，\(winnerName)胜，\(buildMatchScoreListZh(payload, winnerSide))"
    }

    private static func buildRallyMatchEndEn(_ payload: VoiceAnnouncementPayload) -> String {
        let winnerName = getWinnerName(payload)
        let winnerSide = resolveWinnerSide(payload)
        return "Match won by \(winnerName), \(buildMatchScoreListEn(payload, winnerSide))"
    }

    // —— Table tennis ITTF ——

    private static func buildTableTennisScoreChangeZh(_ payload: VoiceAnnouncementPayload) -> String {
        if payload.leftScore == 0, payload.rightScore == 0 {
            let server = resolveServerName(payload)
            return "\(server)发球，0比0"
        }
        return sideFirstNumericZh(payload, resolveServerSide(payload))
    }

    private static func buildTableTennisScoreChangeEn(_ payload: VoiceAnnouncementPayload) -> String {
        if payload.leftScore == 0, payload.rightScore == 0 {
            let server = resolveServerName(payload)
            return "\(server) to serve, love all"
        }
        return sideFirstNumericEn(payload, resolveServerSide(payload))
    }

    private static func buildTableTennisSetEndEn(_ payload: VoiceAnnouncementPayload) -> String {
        let winnerName = getWinnerName(payload)
        let setNumber = payload.currentSet ?? 1
        let gameScore = sideFirstNumericEn(payload, resolveWinnerSide(payload))
        var message = "Game \(setNumber) won by \(winnerName), \(gameScore)"
        if payload.leftSets == payload.rightSets, payload.leftSets > 0 {
            message += payload.leftSets == 1 ? ". One game all" : ". \(payload.leftSets) games all"
        }
        return message
    }

    // —— Tennis ITF (step points 0/1/2/3…) ——

    private static func buildTennisScoreChangeZh(_ payload: VoiceAnnouncementPayload) -> String {
        payload.isTieBreak ? buildTennisTieBreakZh(payload) : buildTennisNormalPointZh(payload)
    }

    private static func buildTennisScoreChangeEn(_ payload: VoiceAnnouncementPayload) -> String {
        payload.isTieBreak ? buildTennisTieBreakEn(payload) : buildTennisNormalPointEn(payload)
    }

    private static func buildTennisNormalPointZh(_ payload: VoiceAnnouncementPayload) -> String {
        let leftScore = payload.leftScore
        let rightScore = payload.rightScore
        if leftScore >= 3, rightScore >= 3 {
            if leftScore == rightScore {
                return payload.tennisDeuceMode == "no_ad" ? "决胜分，接发方选择" : "平分"
            }
            let advantageSide: MatchSide = leftScore > rightScore ? .left : .right
            return "\(teamName(payload, advantageSide))占先"
        }
        let serverSide = resolveServerSide(payload)
        let serverLabel = tennisPointLabelZh(scoreOf(payload, serverSide))
        let receiverLabel = tennisPointLabelZh(scoreOf(payload, serverSide.opposite))
        if serverLabel == receiverLabel {
            return "\(serverLabel)平"
        }
        return "\(serverLabel)比\(receiverLabel)"
    }

    private static func buildTennisNormalPointEn(_ payload: VoiceAnnouncementPayload) -> String {
        let leftScore = payload.leftScore
        let rightScore = payload.rightScore
        if leftScore >= 3, rightScore >= 3 {
            if leftScore == rightScore {
                return payload.tennisDeuceMode == "no_ad"
                    ? "Deciding point, receiver's choice"
                    : "Deuce"
            }
            let advantageSide: MatchSide = leftScore > rightScore ? .left : .right
            return "Advantage \(teamName(payload, advantageSide))"
        }
        let serverSide = resolveServerSide(payload)
        let serverLabel = tennisPointLabelEn(scoreOf(payload, serverSide))
        let receiverLabel = tennisPointLabelEn(scoreOf(payload, serverSide.opposite))
        if serverLabel == receiverLabel {
            return "\(capitalizeFirst(serverLabel))-all"
        }
        return "\(capitalizeFirst(serverLabel))-\(receiverLabel)"
    }

    private static func buildTennisTieBreakZh(_ payload: VoiceAnnouncementPayload) -> String {
        if payload.leftScore == payload.rightScore {
            return "\(payload.leftScore)平"
        }
        let leaderSide: MatchSide = payload.leftScore > payload.rightScore ? .left : .right
        let leader = scoreOf(payload, leaderSide)
        let trailer = scoreOf(payload, leaderSide.opposite)
        return "\(leader)比\(trailer)，\(teamName(payload, leaderSide))"
    }

    private static func buildTennisTieBreakEn(_ payload: VoiceAnnouncementPayload) -> String {
        if payload.leftScore == payload.rightScore {
            return "\(payload.leftScore)-all"
        }
        let leaderSide: MatchSide = payload.leftScore > payload.rightScore ? .left : .right
        let leader = scoreOf(payload, leaderSide)
        let trailer = scoreOf(payload, leaderSide.opposite)
        let leaderLabel = leader == 0 ? "zero" : String(leader)
        let trailerLabel = trailer == 0 ? "zero" : String(trailer)
        return "\(leaderLabel)-\(trailerLabel) \(teamName(payload, leaderSide))"
    }

    private static func buildTennisGameEndZh(_ payload: VoiceAnnouncementPayload) -> String {
        let winnerName = getWinnerName(payload)
        let leftGames = payload.leftScore
        let rightGames = payload.rightScore
        if leftGames == 6, rightGames == 6 {
            return "\(winnerName)胜本局，局分6平，抢七"
        }
        if leftGames == rightGames {
            return "\(winnerName)胜本局，局分\(leftGames)平"
        }
        let leaderSide: MatchSide = leftGames > rightGames ? .left : .right
        let leaderGames = max(leftGames, rightGames)
        let trailingGames = min(leftGames, rightGames)
        let leaderName = teamName(payload, leaderSide)
        return "\(winnerName)胜本局，\(leaderName) \(leaderGames)比\(trailingGames)领先"
    }

    private static func buildTennisGameEndEn(_ payload: VoiceAnnouncementPayload) -> String {
        let winnerName = getWinnerName(payload)
        let leftGames = payload.leftScore
        let rightGames = payload.rightScore
        if leftGames == 6, rightGames == 6 {
            return "Game \(winnerName). 6 games all. Tie-break"
        }
        if leftGames == rightGames {
            return "Game \(winnerName). \(leftGames) games all"
        }
        let leaderSide: MatchSide = leftGames > rightGames ? .left : .right
        let leaderGames = max(leftGames, rightGames)
        let trailingGames = min(leftGames, rightGames)
        let leaderName = teamName(payload, leaderSide)
        return "Game \(winnerName). \(leaderName) leads \(leaderGames) games to \(trailingGames)"
    }

    private static func buildTennisSetEndZh(_ payload: VoiceAnnouncementPayload, isMatchEnd: Bool) -> String {
        let winnerName = getWinnerName(payload)
        let winnerSide = resolveWinnerSide(payload)
        if isMatchEnd {
            return "比赛结束，\(winnerName)胜，\(buildMatchScoreListZh(payload, winnerSide))"
        }
        let setNumber = payload.currentSet ?? 1
        let setScore = formatGameScoreByWinnerZh(
            VoiceSetScore(leftGames: payload.leftScore, rightGames: payload.rightScore),
            winnerSide
        )
        return "\(winnerName)胜第\(formatSetNumberZh(setNumber))盘，\(setScore)"
    }

    private static func buildTennisSetEndEn(_ payload: VoiceAnnouncementPayload, isMatchEnd: Bool) -> String {
        let winnerName = getWinnerName(payload)
        let winnerSide = resolveWinnerSide(payload)
        if isMatchEnd {
            return "Game, set and match \(winnerName), \(buildMatchScoreListEn(payload, winnerSide))"
        }
        let setNumber = payload.currentSet ?? 1
        let setScore = formatGameScoreByWinnerEn(
            VoiceSetScore(leftGames: payload.leftScore, rightGames: payload.rightScore),
            winnerSide
        )
        return "Game and \(formatSetNumberEn(setNumber)) set \(winnerName), \(setScore)"
    }

    // —— Helpers ——

    private static func resolveServerSide(_ payload: VoiceAnnouncementPayload) -> MatchSide {
        payload.serverSide ?? .left
    }

    private static func resolveWinnerSide(_ payload: VoiceAnnouncementPayload) -> MatchSide {
        if let winnerSide = payload.winnerSide { return winnerSide }
        return payload.rightScore > payload.leftScore ? .right : .left
    }

    private static func teamName(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> String {
        side == .right ? payload.rightTeamName : payload.leftTeamName
    }

    private static func getWinnerName(_ payload: VoiceAnnouncementPayload) -> String {
        if let winnerName = payload.winnerName, !winnerName.isEmpty {
            return winnerName
        }
        return teamName(payload, resolveWinnerSide(payload))
    }

    private static func resolveServerName(_ payload: VoiceAnnouncementPayload) -> String {
        if let serverName = payload.serverName, !serverName.isEmpty {
            return serverName
        }
        return teamName(payload, resolveServerSide(payload))
    }

    private static func scoreOf(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> Int {
        side == .right ? payload.rightScore : payload.leftScore
    }

    private static func numericScoreZh(_ first: Int, _ second: Int) -> String {
        first == second ? "\(first)平" : "\(first)比\(second)"
    }

    private static func numericScoreEn(_ first: Int, _ second: Int) -> String {
        first == second ? "\(first)-all" : "\(first)-\(second)"
    }

    private static func sideFirstNumericZh(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> String {
        numericScoreZh(scoreOf(payload, side), scoreOf(payload, side.opposite))
    }

    private static func sideFirstNumericEn(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> String {
        numericScoreEn(scoreOf(payload, side), scoreOf(payload, side.opposite))
    }

    private static func formatSetNumberZh(_ setNumber: Int) -> String {
        let labels = ["零", "一", "二", "三", "四", "五"]
        if setNumber >= 1, setNumber < labels.count {
            return labels[setNumber]
        }
        return String(setNumber)
    }

    private static func formatSetNumberEn(_ setNumber: Int) -> String {
        let labels = ["", "first", "second", "third", "fourth", "fifth"]
        if setNumber >= 1, setNumber < labels.count {
            return labels[setNumber]
        }
        return "\(setNumber)th"
    }

    private static func formatGameScoreByWinnerZh(_ score: VoiceSetScore, _ winnerSide: MatchSide) -> String {
        winnerSide == .right
            ? numericScoreZh(score.rightGames, score.leftGames)
            : numericScoreZh(score.leftGames, score.rightGames)
    }

    private static func formatGameScoreByWinnerEn(_ score: VoiceSetScore, _ winnerSide: MatchSide) -> String {
        winnerSide == .right
            ? numericScoreEn(score.rightGames, score.leftGames)
            : numericScoreEn(score.leftGames, score.rightGames)
    }

    private static func resolveSetScoreList(_ payload: VoiceAnnouncementPayload) -> [VoiceSetScore] {
        if !payload.setScores.isEmpty { return payload.setScores }
        return [VoiceSetScore(leftGames: payload.leftScore, rightGames: payload.rightScore)]
    }

    private static func buildMatchScoreListZh(_ payload: VoiceAnnouncementPayload, _ winnerSide: MatchSide) -> String {
        resolveSetScoreList(payload)
            .map { formatGameScoreByWinnerZh($0, winnerSide) }
            .joined(separator: "、")
    }

    private static func buildMatchScoreListEn(_ payload: VoiceAnnouncementPayload, _ winnerSide: MatchSide) -> String {
        resolveSetScoreList(payload)
            .map { formatGameScoreByWinnerEn($0, winnerSide) }
            .joined(separator: ", ")
    }

    private static func tennisPointLabelZh(_ score: Int) -> String {
        switch score {
        case ...0: return "0"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }

    private static func tennisPointLabelEn(_ score: Int) -> String {
        switch score {
        case ...0: return "love"
        case 1: return "fifteen"
        case 2: return "thirty"
        default: return "forty"
        }
    }

    private static func capitalizeFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}

// MARK: - Rally event → payloads (aligned with Android VoiceAnnouncementEventMapper)

public enum RallyVoiceAnnouncementMapper {
    public static func payloads(
        gameType: GameType,
        before: RallyMatchState,
        after: RallyMatchState,
        events: [RallyMatchEvent],
        completedSetScores: [VoiceSetScore]
    ) -> [VoiceAnnouncementPayload] {
        guard VoiceAnnouncementSupport.isSupported(gameType),
              VoiceAnnouncementSupport.isBadminton(gameType) || VoiceAnnouncementSupport.isPingpong(gameType)
        else {
            return []
        }

        let point = events.compactMap { event -> (MatchSide, Int, Int)? in
            if case let .pointScored(side, left, right) = event {
                return (side, left, right)
            }
            return nil
        }.last

        let setEnd = events.compactMap { event -> (MatchSide, Int, Int, Int, Int, Int)? in
            if case let .setCompleted(winner, setNumber, leftPoints, rightPoints, leftSets, rightSets) = event {
                return (winner, setNumber, leftPoints, rightPoints, leftSets, rightSets)
            }
            return nil
        }.last

        let matchEnd = events.contains {
            if case .matchFinished = $0 { return true }
            return false
        }
        let sideChanged = events.contains {
            if case .sidesExchanged = $0 { return true }
            return false
        }
        let sideReminder = events.contains {
            if case .sidesExchangeReminder = $0 { return true }
            return false
        }

        // Manual exchange-only intent.
        if point == nil, setEnd == nil, !matchEnd {
            if sideChanged || sideReminder {
                return [sideChangePayload(gameType: gameType, state: before)]
            }
            return []
        }

        guard let point else { return [] }

        let namesState = sideChanged ? before : after
        let servingSideAfterPoint: MatchSide = sideChanged ? after.servingSide.opposite : after.servingSide
        let serviceOver: Bool = {
            if VoiceAnnouncementSupport.isPingpong(gameType) {
                return before.servingSide != servingSideAfterPoint
            }
            if VoiceAnnouncementSupport.isBadminton(gameType) {
                return before.servingSide != point.0
            }
            return false
        }()

        let leftAtEnd = setEnd?.2 ?? point.1
        let rightAtEnd = setEnd?.3 ?? point.2

        let main: VoiceAnnouncementPayload
        if matchEnd, let setEnd {
            main = basePayload(
                gameType: gameType,
                phase: .matchEnd,
                state: namesState,
                leftScore: leftAtEnd,
                rightScore: rightAtEnd,
                leftSets: setEnd.4,
                rightSets: setEnd.5,
                currentSet: setEnd.1,
                winnerSide: setEnd.0,
                setScores: completedSetScores
            )
        } else if let setEnd {
            main = basePayload(
                gameType: gameType,
                phase: .setEnd,
                state: namesState,
                leftScore: leftAtEnd,
                rightScore: rightAtEnd,
                leftSets: setEnd.4,
                rightSets: setEnd.5,
                currentSet: setEnd.1,
                winnerSide: setEnd.0,
                setScores: completedSetScores
            )
        } else {
            main = basePayload(
                gameType: gameType,
                phase: .scoreChange,
                state: namesState,
                leftScore: point.1,
                rightScore: point.2,
                leftSets: before.leftSets,
                rightSets: before.rightSets,
                scoringSide: point.0,
                serverSide: servingSideAfterPoint,
                serviceOver: serviceOver
            )
        }

        var result = [main]
        if (sideChanged || sideReminder), setEnd == nil, !matchEnd {
            result.append(sideChangePayload(gameType: gameType, state: namesState))
        }
        return result
    }

    public static func openingPayload(gameType: GameType, state: RallyMatchState) -> VoiceAnnouncementPayload? {
        guard VoiceAnnouncementSupport.isPingpong(gameType),
              state.leftPoints == 0,
              state.rightPoints == 0,
              state.leftSets == 0,
              state.rightSets == 0,
              !state.finished
        else {
            return nil
        }
        return basePayload(
            gameType: gameType,
            phase: .scoreChange,
            state: state,
            leftScore: 0,
            rightScore: 0,
            leftSets: 0,
            rightSets: 0,
            serverSide: state.servingSide
        )
    }

    private static func sideChangePayload(gameType: GameType, state: RallyMatchState) -> VoiceAnnouncementPayload {
        basePayload(
            gameType: gameType,
            phase: .sideChange,
            state: state,
            leftScore: state.leftPoints,
            rightScore: state.rightPoints,
            leftSets: state.leftSets,
            rightSets: state.rightSets
        )
    }

    private static func basePayload(
        gameType: GameType,
        phase: VoiceAnnouncementPhase,
        state: RallyMatchState,
        leftScore: Int,
        rightScore: Int,
        leftSets: Int,
        rightSets: Int,
        currentSet: Int? = nil,
        scoringSide: MatchSide? = nil,
        serverSide: MatchSide? = nil,
        winnerSide: MatchSide? = nil,
        serviceOver: Bool = false,
        setScores: [VoiceSetScore] = []
    ) -> VoiceAnnouncementPayload {
        let resolvedWinner = winnerSide
        let winnerName: String? = {
            guard let resolvedWinner else { return nil }
            return resolvedWinner == .left ? state.leftName : state.rightName
        }()
        return VoiceAnnouncementPayload(
            gameType: gameType,
            phase: phase,
            leftTeamName: state.leftName,
            rightTeamName: state.rightName,
            leftScore: leftScore,
            rightScore: rightScore,
            leftSets: leftSets,
            rightSets: rightSets,
            currentSet: currentSet,
            scoringSide: scoringSide,
            serverSide: serverSide,
            winnerSide: winnerSide,
            winnerName: winnerName,
            serviceOver: serviceOver,
            setScores: setScores
        )
    }
}
