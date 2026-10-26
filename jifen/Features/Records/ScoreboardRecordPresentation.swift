import Foundation
import RecordCore
import ScoreCore

/// Local and synced records share the same list labels and score hierarchy.
/// Foreign payloads stay opaque; their common envelope supplies the fallback.
struct RecordListPresentation {
    var gameType: GameType?
    var title: String
    var names: String?
    var time: String
    var project: String?
    var duration: TimeInterval?
    var score: String?
    var participantCount = 2
    var isLegacyNineBall = false
    var isSyncedFromWatch = false

    init(_ record: ScoreboardRecordSummary) {
        gameType = record.gameType
        title = record.displayMatchTitle
        if record.configuredMatchTitle != nil {
            let players = record.displayParticipants.map(\.name)
            names = players.isEmpty ? "\(record.team1Name) vs \(record.team2Name)" : players.joined(separator: " vs ")
        }
        time = record.time
        project = record.competitionDisplayName
        duration = record.duration
        score = record.displayScore()
        participantCount = max(2, record.displayParticipants.count)
        isLegacyNineBall = record.isLegacyNineBallRecord
        isSyncedFromWatch = record.isSyncedFromWatch
    }

    init(_ record: GameRecordSummary) {
        gameType = record.gameType
        title = record.title
        time = record.time
        duration = record.duration
        score = record.winner.map { "\($0) \(NSLocalizedString("wins", value: "获胜", comment: ""))" }
    }

    init(_ record: PersonalRecordEnvelope) {
        if let native = PersonalCloudRecordDecoder.scoreboard(record) {
            self = RecordListPresentation(ScoreboardRecordSummary(from: native))
            isSyncedFromWatch = isSyncedFromWatch || record.origin.sourceSystem == "watch"
            return
        }
        if let native = PersonalCloudRecordDecoder.timer(record) {
            self = RecordListPresentation(native)
            return
        }
        gameType = ScoreCore.GameType(rawValue: record.project).map { GameType(scoreCoreGameType: $0) }
            ?? GameType.allCases.first { $0.canonicalScoreboardIdentifier == record.project }
        let projectName = ScoreCore.GameType(rawValue: record.project)?.scoreboardDisplayName ?? gameType?.displayName
        project = projectName
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        time = formatter.string(from: Date(timeIntervalSince1970: Double(record.playedAt) / 1_000))
        duration = record.summary["durationMs"]?.integer.map { Double($0) / 1_000 }
        isSyncedFromWatch = record.origin.sourceSystem == "watch"

        var playerNames: [String] = []
        var playerScores: [String] = []
        if case .array(let players) = record.summary["players"] {
            for case .object(let player) in players {
                if let name = player["name"]?.string, !name.isEmpty { playerNames.append(name) }
                if let value = player["score"]?.integer { playerScores.append(String(value)) }
            }
        }
        if playerNames.isEmpty {
            let left = record.summary["leftName"]?.string
                ?? Self.sideName(record.participants, keys: ["side:0", "A"])
            let right = record.summary["rightName"]?.string
                ?? Self.sideName(record.participants, keys: ["side:1", "B"])
            playerNames = [left, right].compactMap { $0 }.filter { !$0.isEmpty }
            if playerNames.isEmpty { playerNames = record.participants.map(\.nameSnapshot).filter { !$0.isEmpty } }
        }
        let savedTitle = record.summary["title"]?.string.flatMap { $0.isEmpty || $0 == record.project ? nil : $0 }
        if record.kind == "timer" {
            title = projectName ?? savedTitle ?? identityText("record_detail", "记录详情")
            project = nil
        } else {
            let nameLine = playerNames.joined(separator: " vs ")
            title = nameLine.isEmpty ? (projectName ?? savedTitle ?? identityText("record_detail", "记录详情")) : nameLine
            if record.origin.sourceSystem == "group", let savedTitle {
                title = savedTitle
                names = nameLine.isEmpty ? nil : nameLine
            }
            if !playerScores.isEmpty {
                score = playerScores.joined(separator: " : ")
            } else if let left = record.summary["leftScore"]?.integer, let right = record.summary["rightScore"]?.integer {
                score = "\(left) : \(right)"
            }
            participantCount = max(2, playerNames.count)
        }
    }

    private static func sideName(_ participants: [PersonalWireParticipant], keys: Set<String>) -> String? {
        let names = participants.filter { $0.sideKey.map(keys.contains) == true }.map(\.nameSnapshot).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: " / ")
    }
}

/// Read-only label policy. Missing version metadata denotes the historical
/// cumulative rules; opening a record never replays it under current rules.
enum NineBallRecordRuleVersionPolicy {
    static func resolve(
        extraData: [String: AnyCodable]?,
        projectConfiguration: [String: AnyCodable]?,
        stateSnapshot: Data? = nil
    ) -> Int {
        if let version = version(extraData?["chaseRuleVersion"]?.value) { return version }
        if let version = version(projectConfiguration?["nineBallRuleVersion"]?.value) { return version }
        guard let stateSnapshot,
              let root = try? JSONSerialization.jsonObject(with: stateSnapshot) as? [String: Any] else {
            return 1
        }
        if let version = version(root["ruleVersion"]) { return version }
        if let state = root["state"] as? [String: Any], let version = version(state["ruleVersion"]) {
            return version
        }
        if let current = root["currentSession"] as? [String: Any],
           let state = current["state"] as? [String: Any],
           let version = version(state["ruleVersion"]) {
            return version
        }
        return 1
    }

    static var legacyLabel: String {
        NSLocalizedString("nine_ball_legacy_rules", value: "旧版规则", comment: "")
    }

    private static func version(_ raw: Any?) -> Int? {
        if let value = raw as? Int, value >= 1 { return value }
        if let value = raw as? String, let number = Int(value), number >= 1 { return number }
        return nil
    }
}

enum ScoreboardRecordDetailLayout: Equatable {
    case standard
    case multiScoreTimeline
}

enum ScoreboardRecordActionTitlePolicy {
    static func nineBallOperationTitle(operationCode: String?, summary: String?) -> String? {
        guard operationCode?.hasPrefix("nine_ball_transfer_") == true || operationCode?.hasPrefix("nine_ball_tournament_") == true || operationCode == "nine_ball_breaker_changed",
              let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return nil }
        return summary
    }

    static func tableTennisAdministrativeTitle(
        operationCode: String?,
        teamName: String?
    ) -> String? {
        let key: String
        switch operationCode?.lowercased() {
        case "yellow_card", "tt_yellow": key = "record_tt_yellow"
        case "red_card", "tt_red": key = "record_tt_red"
        case "timeout", "tt_timeout": key = "record_tt_timeout"
        case "medical_timeout", "tt_medical": key = "record_tt_medical"
        case "forfeit", "tt_forfeit": key = "record_tt_forfeit"
        // 羽毛球判罚：opCode 逐字对齐安卓 bd_*。
        case "bd_yellow": key = "record_bd_yellow"
        case "bd_red": key = "record_bd_red"
        case "bd_disqualify": key = "record_bd_disqualify"
        default: return nil
        }
        let fallbackName = teamName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = fallbackName.flatMap { $0.isEmpty ? nil : $0 }
            ?? NSLocalizedString("player", value: "选手", comment: "")
        let fallbackFormat: String = switch key {
        case "record_tt_yellow": "%@ 黄牌"
        case "record_tt_red": "%@ 红牌"
        case "record_tt_timeout": "%@ 暂停"
        case "record_tt_medical": "%@ 医疗暂停"
        case "record_bd_yellow": "%@ 黄牌"
        case "record_bd_red": "%@ 红牌（对方+1）"
        default: "%@ 取消比赛资格"
        }
        return String.localizedStringWithFormat(
            NSLocalizedString(key, value: fallbackFormat, comment: "Table tennis administrative record action"),
            resolvedName
        )
    }

    /// 投篮训练动作用跨端机器 token（`training_start` / `training_<1|2|3>pt_<made|miss>` /
    /// `training_rate_<n>`）表达，与安卓 `buildShotTrainingActions`、鸿蒙 `ShotTrainingScoreViewModel`
    /// 同口径；这里负责把 token 解析成本地化文案。
    static func shotTrainingTitle(operationCode: String?) -> String? {
        guard let code = operationCode else { return nil }
        if code == "training_start" {
            return NSLocalizedString("game_started", comment: "")
        }
        let ratePrefix = "training_rate_"
        if code.hasPrefix(ratePrefix), let rate = Int(code.dropFirst(ratePrefix.count)) {
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "record_training_end_rate",
                    value: "训练结束 · 命中率 %1$d%%",
                    comment: "Shot training finished record action"
                ),
                rate
            )
        }
        let isMade = code.hasSuffix("_made")
        guard isMade || code.hasSuffix("_miss") else { return nil }
        let suffix = isMade ? "_made" : "_miss"
        guard code.hasPrefix("training_") else { return nil }
        let pointsToken = code.dropFirst("training_".count).dropLast(suffix.count)
        guard pointsToken.hasSuffix("pt"),
              let points = Int(pointsToken.dropLast(2)),
              (1...3).contains(points) else { return nil }
        let outcome = NSLocalizedString(
            isMade ? "shot_training_made" : "shot_training_miss",
            value: isMade ? "命中" : "未中",
            comment: "Shot training outcome label"
        )
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "record_training_shot",
                value: "%1$d分%2$@",
                comment: "Shot training record action: points and outcome"
            ),
            points,
            outcome
        )
    }
}

enum DoudizhuRecordRole: Equatable {
    case landlord
    case farmer
}

struct DoudizhuRecordScoreDetail: Equatable {
    let team: RecordTeam
    let playerName: String
    let role: DoudizhuRecordRole?
    let scoreChange: Int?
    let isWinner: Bool
}

/// Android 3.1 `DoudizhuRecordDisplay` and
/// `ScoreboardDetailRecapBuilder` parity. The view only localizes these typed
/// values; score allocation and player identity stay testable here.
enum DoudizhuRecordDetailPolicy {
    static func scoreLine(for action: DetailedScoreAction) -> String? {
        scoreLine(scores: action.scores)
    }

    static func scoreLine(scores: [Int]) -> String? {
        guard scores.count >= 3 else { return nil }
        return scores.prefix(4).map { score in
            score > 0 ? "+\(score)" : "\(score)"
        }.joined(separator: " / ")
    }

    static func winnerNames(
        for action: DetailedScoreAction,
        record: ScoreboardRecord
    ) -> [String] {
        (action.winners ?? []).map { playerName(for: $0, action: action, record: record) }
    }

    static func scoreDetails(
        for action: DetailedScoreAction,
        record: ScoreboardRecord
    ) -> [DoudizhuRecordScoreDetail] {
        guard record.gameType == .doudizhu else { return [] }
        let winners = action.winners ?? []
        let losers = action.losers ?? []
        guard !winners.isEmpty, !losers.isEmpty else { return [] }

        let winnerDetails = winners.map { team in
            DoudizhuRecordScoreDetail(
                team: team,
                playerName: playerName(for: team, action: action, record: record),
                role: role(for: team, action: action),
                scoreChange: action.scoreChange,
                isWinner: true
            )
        }
        let loserChange: Int? = action.scoreChange.map { scoreChange in
            switch winners.count {
            case 1:
                return -scoreChange / max(1, losers.count)
            case let count where count > 1:
                return -scoreChange * winners.count
            default:
                return 0
            }
        }
        let loserDetails = losers.map { team in
            DoudizhuRecordScoreDetail(
                team: team,
                playerName: playerName(for: team, action: action, record: record),
                role: role(for: team, action: action),
                scoreChange: loserChange,
                isWinner: false
            )
        }
        return winnerDetails + loserDetails
    }

    static func signedScore(_ score: Int) -> String {
        score > 0 ? "+\(score)" : "\(score)"
    }

    private static func role(
        for team: RecordTeam,
        action: DetailedScoreAction
    ) -> DoudizhuRecordRole? {
        guard let landlord = action.landlord else { return nil }
        return landlord == team ? .landlord : .farmer
    }

    private static func playerName(
        for team: RecordTeam,
        action: DetailedScoreAction,
        record: ScoreboardRecord
    ) -> String {
        let index = RecordTeam.allCases.firstIndex(of: team) ?? 0
        if action.participants.indices.contains(index) {
            let name = action.participants[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        let participants = record.displayParticipants
        if participants.indices.contains(index) { return participants[index].name }
        switch team {
        case .team1: return record.team1Name
        case .team2: return record.team2Name
        case .team3, .team4:
            return "\(NSLocalizedString("player", value: "选手", comment: "")) \(index + 1)"
        }
    }
}

struct ScoreboardRecordProjectPolicy: Equatable {
    enum RecapKind: String {
        case sets, tennisSets, periods, rounds, frames, events, cardRounds, ranking
    }

    let trendAllowed: Bool
    let trendExcludesMultiParticipant: Bool
    let trendRequiresNonNegativeScores: Bool
    let recapKind: RecapKind

    var detailLayout: ScoreboardRecordDetailLayout {
        recapKind == .ranking ? .multiScoreTimeline : .standard
    }

    static func policy(for gameType: GameType) -> Self {
        switch gameType {
        // Trend visibility mirrors Android CHART_UNSUPPORTED_TYPES deny-list:
        // football/basketball/boxing/tennis/eight-ball/card games/multi-score
        // stay hidden; everything else shows when action data allows.
        case .pingpong, .badminton, .shuttlecock, .squash, .pickleball, .volleyball, .beachVolleyball,
             .airVolleyball, .foosball, .archery, .snooker:
            return .init(trendAllowed: true, trendExcludesMultiParticipant: true, trendRequiresNonNegativeScores: true, recapKind: .sets)
        case .basketball:
            return .init(trendAllowed: false, trendExcludesMultiParticipant: false, trendRequiresNonNegativeScores: false, recapKind: .periods)
        case .basketballTraining:
            return .init(trendAllowed: true, trendExcludesMultiParticipant: true, trendRequiresNonNegativeScores: true, recapKind: .events)
        case .threeBasketball:
            return .init(trendAllowed: false, trendExcludesMultiParticipant: false, trendRequiresNonNegativeScores: false, recapKind: .events)
        case .billiards, .nineBall, .simpleScore:
            return .init(trendAllowed: true, trendExcludesMultiParticipant: true, trendRequiresNonNegativeScores: true, recapKind: .events)
        case .tennis:
            return .init(trendAllowed: false, trendExcludesMultiParticipant: false, trendRequiresNonNegativeScores: false, recapKind: .tennisSets)
        case .softTennis, .padel:
            return .init(trendAllowed: true, trendExcludesMultiParticipant: true, trendRequiresNonNegativeScores: true, recapKind: .tennisSets)
        case .football, .football5v5:
            return .init(trendAllowed: false, trendExcludesMultiParticipant: false, trendRequiresNonNegativeScores: false, recapKind: .events)
        case .boxing:
            return .init(trendAllowed: false, trendExcludesMultiParticipant: false, trendRequiresNonNegativeScores: false, recapKind: .rounds)
        case .eightBall:
            return .init(trendAllowed: false, trendExcludesMultiParticipant: false, trendRequiresNonNegativeScores: false, recapKind: .frames)
        case .doudizhu, .guandan, .shengji, .uno:
            return .init(trendAllowed: false, trendExcludesMultiParticipant: false, trendRequiresNonNegativeScores: false, recapKind: .cardRounds)
        case .multiScoreboard:
            return .init(trendAllowed: false, trendExcludesMultiParticipant: false, trendRequiresNonNegativeScores: false, recapKind: .ranking)
        case .checkers, .counter, .stopwatch, .go, .xiangqi, .chess:
            return .init(trendAllowed: true, trendExcludesMultiParticipant: true, trendRequiresNonNegativeScores: true, recapKind: .events)
        }
    }

}

struct ScoreboardRecordRecapSection: Identifiable, Equatable {
    let id: String
    let title: String
    let number: Int?
    let resetGeneration: Int
    let result: RecordSetResult?
    let actions: [DetailedScoreAction]
}

struct ScoreboardRecordPresentation {
    let detailLayout: ScoreboardRecordDetailLayout
    let actions: [DetailedScoreAction]
    let trendTabs: [ScoreboardRecordTrendTab]
    let recap: [ScoreboardRecordRecapSection]
    let timelineSections: [ScoreboardRecordRecapSection]
    let multiScoreTimelineRows: [MultiScoreRecordDetailRow]
    let recapGroupingQuality: ScoreboardRecordRecapGroupingQuality
    let canShowTrend: Bool
    let isReliableForResume: Bool

    init(record: ScoreboardRecord) {
        let policy = ScoreboardRecordProjectPolicy.policy(for: record.gameType)
        detailLayout = policy.detailLayout
        let recordedActions: [DetailedScoreAction]
        if let detailedActions = record.detailedActions, !detailedActions.isEmpty {
            recordedActions = detailedActions
        } else {
            recordedActions = ScoreboardRecordActionAdapter.actions(for: record)
        }
        actions = record.isTennisTiebreakOnly
            ? recordedActions.filter { $0.type != .matchFinished }
            : recordedActions
        let recapBuild = ScoreboardRecordRecapBuilder.build(
            record: record,
            actions: actions,
            policy: policy
        )
        recap = recapBuild.sections
        timelineSections = recapBuild.sections
        trendTabs = ScoreboardRecordTrendBuilder.build(
            record: record,
            sections: recapBuild.sections,
            policy: policy
        )
        canShowTrend = !trendTabs.isEmpty
        multiScoreTimelineRows = policy.detailLayout == .multiScoreTimeline
            ? MultiScoreRecordDetailBuilder.build(record: record)
            : []
        recapGroupingQuality = recapBuild.quality
        isReliableForResume = record.status == .finished || record.stateSnapshot != nil
    }

}

enum ScoreboardRecordActionAdapter {
    static func setResults(from actions: [DetailedScoreAction]) -> [RecordSetResult] {
        actions.compactMap { action in
            guard action.type == .setFinished || action.type == .roundFinished || action.type == .periodFinished else { return nil }
            let number: Int
            switch action.type {
            case .setFinished:
                number = action.setNumber ?? action.gameNumber ?? 1
            case .roundFinished:
                number = action.roundNumber ?? 1
            case .periodFinished:
                number = action.periodNumber ?? 1
            default:
                return nil
            }
            return RecordSetResult(
                number: number,
                titleCode: action.operationCode,
                scores: action.scores,
                winner: action.winner ?? action.team,
                finishedAtEpochMilliseconds: action.epochMilliseconds
            )
        }
    }

    static func actions(for record: ScoreboardRecord) -> [DetailedScoreAction] {
        var result: [DetailedScoreAction] = [
            DetailedScoreAction(
                type: .matchStarted,
                epochMilliseconds: milliseconds(record.startTime),
                scores: [0, 0],
                summary: NSLocalizedString("game_started", comment: "")
            )
        ]
        var scores = [0, 0, 0, 0]
        var setScores = [0, 0, 0, 0]
        var setNumber = 1
        var roundNumber = 1
        let periodNumber = 1
        var multiScores = Array(repeating: 0, count: max(4, record.displayParticipants.count))

        for raw in record.actions {
            let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let timestamp = parts.first.flatMap(Int64.init)
            let body = timestamp == nil ? raw : parts.dropFirst().joined(separator: "|")

            if timestamp != nil, parts.count >= 2 {
                switch parts[1] {
                case "point", "score":
                    let side = parts.count > 2 ? parts[2] : ""
                    if parts.count > 3, let parsed = parsePair(parts[3]) { scores[0] = parsed.0; scores[1] = parsed.1 }
                    else { applySide(side, delta: 1, to: &scores) }
                    result.append(action(.scoreChanged, time: timestamp, side: side, scores: scores, sets: setScores, set: setNumber, round: roundNumber, period: periodNumber, delta: 1, raw: raw))
                    continue
                case "set":
                    if parts.count > 4, let parsed = parsePair(parts[4]) { setScores[0] = parsed.0; setScores[1] = parsed.1 }
                    result.append(action(.setFinished, time: timestamp, side: parts[safe: 2], scores: scores, sets: setScores, set: setNumber, raw: raw))
                    setNumber += 1
                    scores[0] = 0; scores[1] = 0
                    continue
                case "settleRound":
                    let deltas = parts[safe: 2]?.split(separator: ",").compactMap { Int($0) } ?? []
                    for index in deltas.indices where index < multiScores.count { multiScores[index] += deltas[index] }
                    result.append(DetailedScoreAction(type: .roundFinished, epochMilliseconds: timestamp, scores: Array(multiScores.prefix(4)), roundNumber: roundNumber, scoreChange: deltas.first, participants: participantSnapshots(record: record, scores: multiScores), operationCode: "settle_round", summary: raw))
                    roundNumber += 1
                    continue
                case "snapshot":
                    let code = parts[safe: 2] ?? "state"
                    let snapshotScores = parts[safe: 3]?.split(separator: ",").compactMap { Int($0) } ?? []
                    let snapshotSets = parts[safe: 4]?.split(separator: ",").compactMap { Int($0) } ?? []
                    let type: DetailedScoreActionType
                    if code == "undo" { type = .undo }
                    else if code == "reset" { type = .reset }
                    else if code == "finish" { type = .matchFinished }
                    else if code.contains("foul") { type = .foul }
                    else if code.contains("exchange") { type = .sideChanged }
                    else if code.contains("edit") || code.contains("name") { type = .stateChanged }
                    else if code.contains("settle") || code.contains("round") { type = .roundFinished }
                    else { type = .scoreChanged }
                    scores.replaceSubrange(0..<min(scores.count, snapshotScores.count), with: snapshotScores.prefix(scores.count))
                    if !snapshotSets.isEmpty { setScores.replaceSubrange(0..<min(setScores.count, snapshotSets.count), with: snapshotSets.prefix(setScores.count)) }
                    result.append(DetailedScoreAction(type: type, epochMilliseconds: timestamp, scores: snapshotScores, setScores: snapshotSets, setNumber: setNumber, roundNumber: roundNumber, periodNumber: periodNumber, operationCode: code, summary: code))
                    if type == .roundFinished { roundNumber += 1 }
                    continue
                case "reset": result.append(DetailedScoreAction(type: .reset, epochMilliseconds: timestamp, scores: scores, operationCode: "reset", summary: raw)); scores = [0, 0, 0, 0]; continue
                case "undo": result.append(DetailedScoreAction(type: .undo, epochMilliseconds: timestamp, scores: scores, operationCode: "undo", summary: raw)); continue
                case "finish": result.append(DetailedScoreAction(type: .matchFinished, epochMilliseconds: timestamp, scores: scores, operationCode: "finish", summary: raw)); continue
                default: break
                }
            }

            if let parsed = parseLineScoreDelta(body) {
                let previous = scores[parsed.index]
                let minimum = record.gameType == .simpleScore ? -9_999 : 0
                scores[parsed.index] = min(9_999, max(minimum, previous + parsed.delta))
                let appliedDelta = scores[parsed.index] - previous
                guard appliedDelta != 0 else { continue }
                result.append(DetailedScoreAction(
                    type: .scoreChanged,
                    epochMilliseconds: timestamp,
                    team: parsed.index == 0 ? .team1 : .team2,
                    scores: scores,
                    setScores: setScores,
                    setNumber: setNumber,
                    roundNumber: roundNumber,
                    periodNumber: periodNumber,
                    scoreChange: appliedDelta,
                    operationCode: "score_adjust",
                    summary: raw
                ))
            } else if let parsed = parseSideDelta(body) {
                scores[parsed.index] += parsed.delta
                result.append(DetailedScoreAction(type: .scoreChanged, epochMilliseconds: timestamp, team: parsed.index == 0 ? .team1 : .team2, scores: scores, setScores: setScores, setNumber: setNumber, roundNumber: roundNumber, periodNumber: periodNumber, scoreChange: parsed.delta, operationCode: "score_adjust", summary: raw))
            } else if body.hasPrefix("round "), let pair = parsePair(String(body.dropFirst(6))) {
                result.append(DetailedScoreAction(type: .roundFinished, epochMilliseconds: timestamp, scores: [pair.0, pair.1], roundNumber: roundNumber, operationCode: "boxing_round", summary: raw))
                roundNumber += 1
            } else if body.hasPrefix("adjust:") || body.hasPrefix("uno_round:") {
                let values = body.split(separator: ":").map(String.init)
                if values.count >= 3, let index = Int(values[1]), let delta = Int(values[2]), multiScores.indices.contains(index) {
                    multiScores[index] += delta
                    let type: DetailedScoreActionType = body.hasPrefix("uno_round:") ? .roundFinished : .scoreChanged
                    result.append(DetailedScoreAction(type: type, epochMilliseconds: timestamp, scores: Array(multiScores.prefix(4)), roundNumber: type == .roundFinished ? roundNumber : nil, scoreChange: delta, winner: type == .roundFinished ? recordTeam(index) : nil, participants: participantSnapshots(record: record, scores: multiScores), operationCode: values[0], summary: raw))
                    if type == .roundFinished { roundNumber += 1 }
                }
            } else if body == "reset" {
                result.append(DetailedScoreAction(type: .reset, epochMilliseconds: timestamp, scores: scores, operationCode: "reset", summary: raw))
                scores = [0, 0, 0, 0]
            } else if body == "exchangeSide" || body == "exchangeSides" {
                result.append(DetailedScoreAction(type: .sideChanged, epochMilliseconds: timestamp, scores: scores, operationCode: "exchange_side", summary: raw))
            } else if body == "undo" {
                result.append(DetailedScoreAction(type: .undo, epochMilliseconds: timestamp, scores: scores, operationCode: "undo", summary: raw))
            } else if !body.hasPrefix("layout:") {
                result.append(DetailedScoreAction(type: .stateChanged, epochMilliseconds: timestamp, scores: scores, operationCode: body.components(separatedBy: ":").first, summary: raw))
            }
        }

        if record.status == .finished, result.last?.type != .matchFinished {
            let endMilliseconds = record.endTime.map { Int64($0.timeIntervalSince1970 * 1_000) }
            result.append(DetailedScoreAction(type: .matchFinished, epochMilliseconds: endMilliseconds, scores: [record.team1FinalScore, record.team2FinalScore], setScores: [record.team1SetScore ?? 0, record.team2SetScore ?? 0], winner: record.resolvedWinnerRecordTeam, summary: NSLocalizedString("game_ended", comment: "")))
        }
        return result
    }

    private static func action(_ type: DetailedScoreActionType, time: Int64?, side: String?, scores: [Int], sets: [Int], set: Int? = nil, round: Int? = nil, period: Int? = nil, delta: Int? = nil, raw: String) -> DetailedScoreAction {
        let resolvedTeam: RecordTeam?
        switch side {
        case "left", "team1": resolvedTeam = .team1
        case "right", "team2": resolvedTeam = .team2
        case "team3": resolvedTeam = .team3
        case "team4": resolvedTeam = .team4
        default: resolvedTeam = nil
        }
        return DetailedScoreAction(type: type, epochMilliseconds: time, team: resolvedTeam, scores: scores, setScores: sets, setNumber: set, roundNumber: round, periodNumber: period, scoreChange: delta, operationCode: raw.split(separator: "|").dropFirst().first.map(String.init), summary: raw)
    }

    private static func parseSideDelta(_ raw: String) -> (index: Int, delta: Int)? {
        let parts = raw.split(separator: " ").map(String.init)
        guard parts.count >= 2, let delta = Int(parts[1]), parts[0] == "left" || parts[0] == "right" else { return nil }
        return (parts[0] == "left" ? 0 : 1, delta)
    }

    private static func parseLineScoreDelta(_ raw: String) -> (index: Int, delta: Int)? {
        let compact = raw.lowercased().filter { !$0.isWhitespace }
        let adjustPrefix = "adjust(side:"
        if compact.hasPrefix(adjustPrefix),
           let deltaMarker = compact.range(of: ",delta:") {
            let sideStart = compact.index(compact.startIndex, offsetBy: adjustPrefix.count)
            let sideToken = String(compact[sideStart..<deltaMarker.lowerBound])
            let deltaToken = String(compact[deltaMarker.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: ")"))
            guard let index = lineScoreSideIndex(sideToken),
                  let delta = Int(deltaToken) else {
                return nil
            }
            return (index, delta)
        }

        let pointPrefix = "pointwon("
        if compact.hasPrefix(pointPrefix), compact.hasSuffix(")") {
            let sideStart = compact.index(compact.startIndex, offsetBy: pointPrefix.count)
            let sideEnd = compact.index(before: compact.endIndex)
            let sideToken = String(compact[sideStart..<sideEnd])
            guard let index = lineScoreSideIndex(sideToken) else { return nil }
            return (index, 1)
        }
        return nil
    }

    private static func lineScoreSideIndex(_ token: String) -> Int? {
        if token.hasSuffix("left") { return 0 }
        if token.hasSuffix("right") { return 1 }
        return nil
    }

    private static func parsePair(_ raw: String) -> (Int, Int)? {
        let values = raw.split(separator: raw.contains(":") ? ":" : "-").compactMap { Int($0) }
        guard values.count == 2 else { return nil }
        return (values[0], values[1])
    }

    private static func applySide(_ side: String, delta: Int, to scores: inout [Int]) {
        if side == "left" || side == "team1" { scores[0] += delta }
        else if side == "right" || side == "team2" { scores[1] += delta }
    }

    private static func recordTeam(_ index: Int) -> RecordTeam? { RecordTeam.allCases[safe: index] }
    private static func milliseconds(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1_000) }

    private static func participantSnapshots(record: ScoreboardRecord, scores: [Int]) -> [ParticipantScoreSnapshot] {
        record.displayParticipants.enumerated().map { index, participant in
            ParticipantScoreSnapshot(id: String(index), name: participant.name, score: scores[safe: index] ?? participant.score)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
