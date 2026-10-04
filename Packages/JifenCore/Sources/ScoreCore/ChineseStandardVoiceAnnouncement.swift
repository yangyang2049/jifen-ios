import Foundation

/// Preserves the established Chinese officiating style as semantic templates.
/// All spoken wording is resolved by the host from ScoreVoice.strings.
enum ChineseStandardVoiceAnnouncementBuilder {
    static func build(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.gameType == .squash { return buildSquashZh(payload) }
        if payload.gameType == .shuttlecock { return buildShuttlecockZh(payload) }
        if payload.gameType == .softTennis { return buildSoftTennisZh(payload) }
        if payload.gameType == .padel { return buildPadelZh(payload) }
        switch payload.phase {
        case .breakStart, .breakWarning, .breakResume:
            return buildBreakZh(payload)
        case .opening:
            return buildOpeningZh(payload)
        case .scoreChange:
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisScoreChangeZh(payload)
            }
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisScoreChangeZh(payload)
            }
            if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
                return buildPickleballScoreChangeZh(payload)
            }
            return buildBadmintonScoreChangeZh(payload)
        case .gameEnd:
            return VoiceAnnouncementSupport.isTennis(payload.gameType) ? buildTennisGameEndZh(payload) : ""
        case .setEnd:
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisSetEndZh(payload, isMatchEnd: false)
            }
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisSetEndZh(payload)
            }
            if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
                return buildPickleballEndZh(payload, isMatchEnd: false)
            }
            return buildBadmintonSetEndZh(payload)
        case .matchEnd:
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisSetEndZh(payload, isMatchEnd: true)
            }
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisMatchEndZh(payload)
            }
            if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
                return buildPickleballEndZh(payload, isMatchEnd: true)
            }
            return buildBadmintonMatchEndZh(payload)
        case .sideChange:
            return "交换场地"
        }
    }

    private static func buildBreakZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.phase == .breakWarning {
            return switch payload.breakCue {
            case .twentySeconds: "20秒"
            case .halfTime: "休息过半"
            case .fifteenSeconds: "15秒"
            case .time: "时间到"
            case nil: ""
            }
        }
        if payload.phase == .breakStart {
            guard VoiceAnnouncementSupport.isPickleball(payload.gameType) else { return "" }
            let minutes = max(1, (payload.breakDurationSeconds ?? 0) / 60)
            if (payload.breakDurationSeconds ?? 0) >= 120 {
                return "局间休息，\(minutes)分钟"
            }
            var parts: [VoiceAnnouncementMessage] = []
            if payload.leftScore != 0 || payload.rightScore != 0 {
                parts.append(buildPickleballScoreChangeZh(payload))
            }
            parts.append("暂停")
            if payload.sideChange { parts.append("交换场地") }
            parts.append("\(minutes)分钟")
            return parts.voiceJoined(separator: "，")
        }
        guard payload.phase == .breakResume else { return "" }
        if VoiceAnnouncementSupport.isBadminton(payload.gameType) {
            let server = resolveServerSide(payload)
            return "\(sideFirstNumericZh(payload, server))，比赛继续"
        }
        if VoiceAnnouncementSupport.isPingpong(payload.gameType) || payload.gameType == .squash || payload.gameType == .shuttlecock {
            return "时间到，第\(payload.currentSet ?? 1)局，\(resolveServerName(payload))发球，0比0"
        }
        if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
            return "比赛继续，\(buildPickleballScoreChangeZh(payload))"
        }
        return "时间到"
    }

    private static func buildSquashZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .opening:
            let receiver = payload.receiverName ?? teamName(payload, resolveServerSide(payload).opposite)
            return "\(resolveServerName(payload))发球，\(receiver)接发，\(payload.maxSets ?? 5)局制，0比0"
        case .scoreChange:
            let server = resolveServerSide(payload)
            var line: VoiceAnnouncementMessage = sideFirstNumericZh(payload, server)
            if payload.serviceOver { line = "换发球，\(line)" }
            if payload.leftScore == 10, payload.rightScore == 10 {
                line += "，必须领先两分"
            } else if let point = payload.criticalPoint {
                let cue: VoiceAnnouncementMessage = point == .matchBall ? "赛点" : "局点"
                line += "，\(cue)"
            }
            return line
        case .setEnd: return buildBadmintonSetEndZh(payload)
        case .matchEnd: return buildBadmintonMatchEndZh(payload)
        case .sideChange: return "交换场地"
        case .breakStart, .breakWarning, .breakResume: return buildBreakZh(payload)
        case .gameEnd: return ""
        }
    }

    private static func buildShuttlecockZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .opening: return "\(resolveServerName(payload))发球，0比0"
        case .scoreChange: return sideFirstNumericZh(payload, resolveServerSide(payload))
        case .setEnd: return buildBadmintonSetEndZh(payload)
        case .matchEnd: return buildBadmintonMatchEndZh(payload)
        case .sideChange: return "交换场地"
        case .breakStart, .breakWarning, .breakResume: return buildBreakZh(payload)
        case .gameEnd: return ""
        }
    }

    private static func buildSoftTennisZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .opening:
            let games = payload.maxSets == 9 ? 9 : 7
            return "\(games)局制，比赛开始"
        case .scoreChange:
            if payload.leftScore == payload.rightScore,
               ((!payload.isTieBreak && payload.leftScore >= 3) || (payload.isTieBreak && payload.leftScore >= 6)) {
                return "平分"
            }
            if let advantage = softTennisAdvantage(payload) {
                return "\(teamName(payload, advantage))占先"
            }
            return sideFirstNumericZh(payload, resolveServerSide(payload))
        case .gameEnd:
            return "\(winnerNameZh(payload))胜本局，局分\(payload.leftScore)比\(payload.rightScore)"
        case .setEnd, .matchEnd:
            return "比赛结束，\(winnerNameZh(payload))胜，\(formatGameScoreByWinnerZh(.init(leftGames: payload.leftScore, rightGames: payload.rightScore), resolveWinnerSide(payload)))"
        case .sideChange: return "交换场地"
        case .breakStart, .breakWarning, .breakResume: return buildBreakZh(payload)
        }
    }

    private static func buildPadelZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.phase == .scoreChange, !payload.isTieBreak, payload.leftScore == 3, payload.rightScore == 3 {
            switch payload.tennisDeuceMode {
            case PadelDeuceMode.goldenPoint.rawValue: return "黄金分，接发方选择"
            case PadelDeuceMode.starPoint.rawValue:
                return switch min(2, max(0, payload.starPointReturnedAdvantages)) {
                case 0: "第一次平分"
                case 1: "第二次平分"
                default: "第三次平分，星点"
                }
            default: break
            }
        }
        return buildChineseAsTennisFamily(payload)
    }

    private static func buildChineseAsTennisFamily(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .opening: return "\(resolveServerName(payload))发球，比赛开始"
        case .scoreChange: return buildTennisScoreChangeZh(payload)
        case .gameEnd: return buildTennisGameEndZh(payload)
        case .setEnd: return buildTennisSetEndZh(payload, isMatchEnd: false)
        case .matchEnd: return buildTennisSetEndZh(payload, isMatchEnd: true)
        case .sideChange: return "交换场地"
        case .breakStart, .breakWarning, .breakResume: return buildBreakZh(payload)
        }
    }

    private static func buildOpeningZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if VoiceAnnouncementSupport.isTennis(payload.gameType), payload.isTieBreak {
            let format: VoiceAnnouncementMessage = payload.tieBreakTarget == 10 ? "抢十赛" : "抢七赛"
            return "\(format)开始，\(resolveServerName(payload))发球"
        }
        if VoiceAnnouncementSupport.isTennis(payload.gameType) {
            return "\(resolveServerName(payload))发球，比赛开始"
        }
        if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
            return buildPickleballScoreChangeZh(payload)
        }
        let server = resolveServerName(payload)
        if VoiceAnnouncementSupport.isBadminton(payload.gameType) {
            if let receiver = payload.receiverName, !receiver.isEmpty,
               payload.gameType == .badmintonDoubles {
                return "\(server)发球，\(receiver)接发，0比0，比赛开始"
            }
            return "\(server)发球，0比0，比赛开始"
        }
        return "\(server)发球，0比0"
    }

    private static func buildPickleballScoreChangeZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        let server = resolveServerSide(payload)
        let first = scoreOf(payload, server)
        let second = scoreOf(payload, server.opposite)
        let line: VoiceAnnouncementMessage = "\(first)比\(second)"
        if let number = payload.serverNumber, number == 1 || number == 2 {
            let label: VoiceAnnouncementMessage = number == 2 ? "二" : "一"
            let withServer: VoiceAnnouncementMessage = "\(line)，\(label)号"
            if payload.serviceOver { return "换发球，\(withServer)" }
            if payload.secondServer { return "第二发球，\(withServer)" }
            return withServer
        }
        if payload.serviceOver { return "换发球，\(line)" }
        if payload.secondServer { return "第二发球，\(line)" }
        return line
    }

    private static func buildBadmintonScoreChangeZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        let server = resolveServerSide(payload)
        let first = scoreOf(payload, server)
        let second = scoreOf(payload, server.opposite)
        let line: VoiceAnnouncementMessage
        if let criticalPoint = payload.criticalPoint {
            let cue: VoiceAnnouncementMessage = criticalPoint == .matchPoint ? "赛点" : "局点"
            line = "\(first)，\(cue)，\(second)"
        } else {
            line = numericScoreZh(first, second) + (payload.isInterval ? "，间歇" : "")
        }
        return payload.serviceOver ? "换发球，\(line)" : line
    }

    private static func buildBadmintonSetEndZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "本局结束" }
        let winnerName = winnerNameZh(payload)
        let setNumber = payload.currentSet ?? 1
        let gameScore = sideFirstNumericZh(payload, resolveWinnerSide(payload))
        var message: VoiceAnnouncementMessage = "本局结束，第\(formatSetNumberZh(setNumber))局由\(winnerName)获胜，\(gameScore)"
        if payload.leftSets == payload.rightSets, payload.leftSets > 0 {
            message += "，局分\(payload.leftSets)平"
        }
        return message
    }

    private static func buildBadmintonMatchEndZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "比赛结束" }
        let winnerName = winnerNameZh(payload)
        if payload.isManualEnd { return "比赛结束，\(winnerName)获胜" }
        let winnerSide = resolveWinnerSide(payload)
        return "本局结束，比赛由\(winnerName)获胜，\(buildMatchScoreListZh(payload, winnerSide))"
    }

    private static func buildTableTennisScoreChangeZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.leftScore == 0, payload.rightScore == 0 {
            let server = resolveServerName(payload)
            return "\(server)发球，0比0"
        }
        return sideFirstNumericZh(payload, resolveServerSide(payload))
    }

    private static func buildTableTennisSetEndZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "本局结束" }
        let winnerName = winnerNameZh(payload)
        let gameScore = sideFirstNumericZh(payload, resolveWinnerSide(payload))
        return "\(gameScore)，本局由\(winnerName)获胜"
    }

    private static func buildTableTennisMatchEndZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "比赛结束" }
        let winner = winnerNameZh(payload)
        let winnerSide = resolveWinnerSide(payload)
        if payload.isManualEnd {
            let sets = winnerSide == .left
                ? numericScoreZh(payload.leftSets, payload.rightSets)
                : numericScoreZh(payload.rightSets, payload.leftSets)
            return "比赛结束，\(winner)以\(sets)获胜"
        }
        let gameScore = sideFirstNumericZh(payload, winnerSide)
        let sets = winnerSide == .left
            ? numericScoreZh(payload.leftSets, payload.rightSets)
            : numericScoreZh(payload.rightSets, payload.leftSets)
        return "\(gameScore)，本局及比赛由\(winner)获胜；\(winner)以\(sets)获胜"
    }

    private static func buildPickleballEndZh(_ payload: VoiceAnnouncementPayload, isMatchEnd: Bool) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return isMatchEnd ? "比赛结束" : "本局结束" }
        if payload.isManualEnd { return "比赛结束，\(winnerNameZh(payload))胜" }
        let score = sideFirstNumericZh(payload, resolveWinnerSide(payload))
        let winner = winnerNameZh(payload)
        return isMatchEnd
            ? "得分，本局结束，比赛结束，\(score)，\(winner)胜"
            : "得分，本局结束，\(score)，\(winner)胜"
    }

    private static func buildTennisScoreChangeZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        payload.isTieBreak ? buildTennisTieBreakZh(payload) : buildTennisNormalPointZh(payload)
    }

    private static func buildTennisNormalPointZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        let leftScore = payload.leftScore
        let rightScore = payload.rightScore
        if leftScore >= 3, rightScore >= 3 {
            if leftScore == rightScore {
                return payload.tennisDeuceMode == "no_ad" ? "决胜分，接发方选择" : "平分"
            }
            let advantageSide: MatchSide = leftScore > rightScore ? .left : .right
            return "\(teamNameZh(payload, advantageSide))占先"
        }
        let serverSide = resolveServerSide(payload)
        let serverLabel = tennisPointLabelZh(scoreOf(payload, serverSide))
        let receiverLabel = tennisPointLabelZh(scoreOf(payload, serverSide.opposite))
        if serverLabel == receiverLabel {
            return "\(serverLabel)平"
        }
        return "\(serverLabel)比\(receiverLabel)"
    }

    private static func buildTennisTieBreakZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.leftScore == payload.rightScore {
            return "\(payload.leftScore)平"
        }
        let leaderSide: MatchSide = payload.leftScore > payload.rightScore ? .left : .right
        let leader = scoreOf(payload, leaderSide)
        let trailer = scoreOf(payload, leaderSide.opposite)
        return "\(leader)比\(trailer)，\(teamNameZh(payload, leaderSide))"
    }

    private static func buildTennisGameEndZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "本局结束" }
        let winnerName = winnerNameZh(payload)
        let leftGames = payload.leftScore
        let rightGames = payload.rightScore
        // Android: tied games + isTieBreak → entering TB (covers 6-6 and short-set 4-4).
        if leftGames == rightGames, payload.isTieBreak {
            return "\(winnerName)胜本局，局分\(leftGames)平，抢七"
        }
        if leftGames == rightGames {
            return "\(winnerName)胜本局，局分\(leftGames)平"
        }
        let leaderSide: MatchSide = leftGames > rightGames ? .left : .right
        let leaderGames = max(leftGames, rightGames)
        let trailingGames = min(leftGames, rightGames)
        let leaderName = teamNameZh(payload, leaderSide)
        let setNumber = payload.currentSet ?? 1
        return "本局由\(winnerName)获胜，\(leaderName)在第\(formatSetNumberZh(setNumber))盘以\(leaderGames)比\(trailingGames)领先"
    }

    private static func buildTennisSetEndZh(_ payload: VoiceAnnouncementPayload, isMatchEnd: Bool) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return isMatchEnd ? "比赛结束" : "本盘结束" }
        let winnerName = winnerNameZh(payload)
        let winnerSide = resolveWinnerSide(payload)
        if isMatchEnd {
            if payload.isManualEnd {
                let won = scoreOfSets(payload, winnerSide)
                let lost = scoreOfSets(payload, winnerSide.opposite)
                return "比赛结束，\(winnerName)以\(won)盘比\(lost)盘获胜"
            }
            if payload.isTieBreak, payload.leftSets == 0, payload.rightSets == 0 {
                return "比赛结束，\(sideFirstNumericZh(payload, winnerSide))，\(winnerName)胜"
            }
            let won = scoreOfSets(payload, winnerSide)
            let lost = scoreOfSets(payload, winnerSide.opposite)
            let setNumber = payload.currentSet ?? max(1, won + lost)
            let setLabel: VoiceAnnouncementMessage = setNumber > 1 && won == lost + 1
                ? "决胜盘"
                : "第\(formatSetNumberZh(setNumber))盘"
            return "本局、\(setLabel)及比赛由\(winnerName)获胜，\(winnerName)以\(won)盘比\(lost)盘获胜，\(buildMatchScoreListZh(payload, winnerSide))"
        }
        let setNumber = payload.currentSet ?? 1
        let setScore = formatGameScoreByWinnerZh(
            VoiceSetScore(leftGames: payload.leftScore, rightGames: payload.rightScore),
            winnerSide
        )
        return "\(winnerName)胜本局，并以\(setScore)赢得第\(formatSetNumberZh(setNumber))盘"
    }

    private static func teamNameZh(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> VoiceAnnouncementMessage {
        let names = side == .right ? payload.rightPlayerNames : payload.leftPlayerNames
        return names.isEmpty ? .verbatim(teamName(payload, side)) : names.map(VoiceAnnouncementMessage.verbatim).voiceJoined(separator: "和")
    }

    private static func winnerNameZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if let winnerName = payload.winnerName, !winnerName.isEmpty {
            return .verbatim(winnerName)
        }
        return teamNameZh(payload, resolveWinnerSide(payload))
    }

    private static func numericScoreZh(_ first: Int, _ second: Int) -> VoiceAnnouncementMessage {
        first == second ? "\(first)平" : "\(first)比\(second)"
    }

    private static func sideFirstNumericZh(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> VoiceAnnouncementMessage {
        numericScoreZh(scoreOf(payload, side), scoreOf(payload, side.opposite))
    }

    private static func formatSetNumberZh(_ setNumber: Int) -> VoiceAnnouncementMessage {
        let labels: [VoiceAnnouncementMessage] = ["零", "一", "二", "三", "四", "五"]
        if setNumber >= 1, setNumber < labels.count {
            return labels[setNumber]
        }
        return .verbatim(String(setNumber))
    }

    private static func formatGameScoreByWinnerZh(_ score: VoiceSetScore, _ winnerSide: MatchSide) -> VoiceAnnouncementMessage {
        winnerSide == .right
            ? numericScoreZh(score.rightGames, score.leftGames)
            : numericScoreZh(score.leftGames, score.rightGames)
    }

    private static func buildMatchScoreListZh(_ payload: VoiceAnnouncementPayload, _ winnerSide: MatchSide) -> VoiceAnnouncementMessage {
        resolveSetScoreList(payload)
            .map { formatGameScoreByWinnerZh($0, winnerSide) }
            .voiceJoined(separator: "、")
    }

    private static func tennisPointLabelZh(_ score: Int) -> VoiceAnnouncementMessage {
        switch score {
        case ...0: return "0"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }

    private static func softTennisAdvantage(_ payload: VoiceAnnouncementPayload) -> MatchSide? {
        let edge = payload.isTieBreak ? 7 : 4
        if payload.leftScore >= edge, payload.leftScore - payload.rightScore == 1 { return .left }
        if payload.rightScore >= edge, payload.rightScore - payload.leftScore == 1 { return .right }
        return nil
    }

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

    private static func hasWinner(_ payload: VoiceAnnouncementPayload) -> Bool {
        payload.winnerSide != nil || !(payload.winnerName?.isEmpty ?? true)
    }

    private static func resolveServerName(_ payload: VoiceAnnouncementPayload) -> String {
        if let serverName = payload.serverName, !serverName.isEmpty {
            return serverName
        }
        return teamName(payload, resolveServerSide(payload))
    }

    private static func scoreOfSets(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> Int {
        side == .right ? payload.rightSets : payload.leftSets
    }

    private static func scoreOf(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> Int {
        side == .right ? payload.rightScore : payload.leftScore
    }

    private static func resolveSetScoreList(_ payload: VoiceAnnouncementPayload) -> [VoiceSetScore] {
        if !payload.setScores.isEmpty { return payload.setScores }
        return [VoiceSetScore(leftGames: payload.leftScore, rightGames: payload.rightScore)]
    }
}

private extension Array where Element == VoiceAnnouncementMessage {
    func voiceJoined(separator: VoiceAnnouncementMessage) -> VoiceAnnouncementMessage { .joined(self, separator: separator) }
}
