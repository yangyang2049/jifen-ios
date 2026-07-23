import Foundation
import RecordCore

struct ScoreboardRecordProjectPolicy: Equatable {
    enum RecapKind: String {
        case sets, tennisSets, periods, rounds, frames, events, cardRounds, ranking
    }

    let trendAllowed: Bool
    let trendRequiresTwoPlayers: Bool
    let trendRequiresNonNegativeScores: Bool
    let recapKind: RecapKind

    static func policy(for gameType: GameType) -> Self {
        switch gameType {
        case .pingpong, .badminton, .pickleball, .volleyball, .beachVolleyball,
             .airVolleyball, .billiards, .foosball, .archery, .snooker:
            return .init(trendAllowed: true, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .sets)
        case .basketball:
            return .init(trendAllowed: true, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .periods)
        case .threeBasketball:
            return .init(trendAllowed: true, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .events)
        case .nineBall, .simpleScore:
            return .init(trendAllowed: true, trendRequiresTwoPlayers: true, trendRequiresNonNegativeScores: true, recapKind: .events)
        case .tennis:
            return .init(trendAllowed: false, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .tennisSets)
        case .football:
            return .init(trendAllowed: false, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .events)
        case .boxing:
            return .init(trendAllowed: false, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .rounds)
        case .eightBall:
            return .init(trendAllowed: false, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .frames)
        case .doudizhu, .guandan, .shengji, .uno:
            return .init(trendAllowed: false, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .cardRounds)
        case .multiScoreboard:
            return .init(trendAllowed: false, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .ranking)
        case .checkers, .counter, .stopwatch, .go, .xiangqi, .chess:
            return .init(trendAllowed: false, trendRequiresTwoPlayers: false, trendRequiresNonNegativeScores: false, recapKind: .events)
        }
    }
}

struct ScoreboardRecordTrendPoint: Identifiable, Equatable {
    let id: UUID
    let actionIndex: Int
    let left: Int
    let right: Int
    let segment: Int
    let period: Int?
}

struct ScoreboardRecordRecapSection: Identifiable, Equatable {
    let id: String
    let title: String
    let actions: [DetailedScoreAction]
}

struct ScoreboardRecordPresentation {
    let actions: [DetailedScoreAction]
    let trend: [ScoreboardRecordTrendPoint]
    let recap: [ScoreboardRecordRecapSection]
    let canShowTrend: Bool
    let isReliableForResume: Bool

    init(record: ScoreboardRecord) {
        let policy = ScoreboardRecordProjectPolicy.policy(for: record.gameType)
        actions = record.detailedActions ?? ScoreboardRecordActionAdapter.actions(for: record)
        trend = Self.makeTrend(actions: actions)
        let participants = record.displayParticipants
        let twoPlayerEligible = !policy.trendRequiresTwoPlayers || participants.isEmpty || participants.count == 2
        let nonNegativeEligible = !policy.trendRequiresNonNegativeScores || trend.allSatisfy { $0.left >= 0 && $0.right >= 0 }
        canShowTrend = policy.trendAllowed && twoPlayerEligible && nonNegativeEligible && trend.count >= 2
        recap = Self.makeRecap(actions: actions, setResults: record.setResults, policy: policy)
        isReliableForResume = record.status == .finished || record.stateSnapshot != nil
    }

    private static func makeTrend(actions: [DetailedScoreAction]) -> [ScoreboardRecordTrendPoint] {
        var segment = 0
        return actions.enumerated().compactMap { index, action in
            if action.type == .reset {
                segment += 1
                return nil
            }
            guard action.type == .scoreChanged, action.scores.count >= 2 else { return nil }
            return ScoreboardRecordTrendPoint(
                id: action.id,
                actionIndex: index,
                left: action.scores[0],
                right: action.scores[1],
                segment: segment,
                period: action.periodNumber
            )
        }
    }

    private static func makeRecap(
        actions: [DetailedScoreAction],
        setResults: [RecordSetResult]?,
        policy: ScoreboardRecordProjectPolicy
    ) -> [ScoreboardRecordRecapSection] {
        if let setResults, !setResults.isEmpty {
            return setResults.map { result in
                let matching = actions.filter { ($0.setNumber ?? $0.roundNumber ?? $0.periodNumber) == result.number }
                return .init(id: "result-\(result.id)", title: recapTitle(kind: policy.recapKind, number: result.number), actions: matching)
            }
        }

        var groups: [Int: [DetailedScoreAction]] = [:]
        for action in actions {
            let number = action.periodNumber ?? action.roundNumber ?? action.setNumber ?? 1
            groups[number, default: []].append(action)
        }
        return groups.keys.sorted().map { number in
            .init(id: "recap-\(number)", title: recapTitle(kind: policy.recapKind, number: number), actions: groups[number] ?? [])
        }
    }

    private static func recapTitle(kind: ScoreboardRecordProjectPolicy.RecapKind, number: Int) -> String {
        switch kind {
        case .sets: return String(format: NSLocalizedString("record_recap_set_format", value: "第 %d 局", comment: ""), number)
        case .tennisSets: return String(format: NSLocalizedString("record_recap_tennis_set_format", value: "第 %d 盘", comment: ""), number)
        case .periods: return String(format: NSLocalizedString("record_recap_period_format", value: "第 %d 节", comment: ""), number)
        case .rounds, .cardRounds: return String(format: NSLocalizedString("record_recap_round_format", value: "第 %d 回合", comment: ""), number)
        case .frames: return String(format: NSLocalizedString("record_recap_frame_format", value: "第 %d 局", comment: ""), number)
        case .events: return NSLocalizedString("record_recap_full_match", value: "全场事件", comment: "")
        case .ranking: return NSLocalizedString("record_recap_adjustments", value: "调整明细", comment: "")
        }
    }
}

enum ScoreboardRecordActionAdapter {
    static func setResults(from actions: [DetailedScoreAction]) -> [RecordSetResult] {
        actions.compactMap { action in
            guard action.type == .setFinished || action.type == .roundFinished || action.type == .periodFinished else { return nil }
            let number = action.setNumber ?? action.roundNumber ?? action.periodNumber ?? 1
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

            if let parsed = parseSideDelta(body) {
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
            } else if body == "exchangeSide" {
                result.append(DetailedScoreAction(type: .sideChanged, epochMilliseconds: timestamp, scores: scores, operationCode: "exchange_side", summary: raw))
            } else if body == "undo" {
                result.append(DetailedScoreAction(type: .undo, epochMilliseconds: timestamp, scores: scores, operationCode: "undo", summary: raw))
            } else if !body.hasPrefix("layout:") {
                result.append(DetailedScoreAction(type: .stateChanged, epochMilliseconds: timestamp, scores: scores, operationCode: body.components(separatedBy: ":").first, summary: raw))
            }
        }

        if record.status == .finished, result.last?.type != .matchFinished {
            let endMilliseconds = record.endTime.map { Int64($0.timeIntervalSince1970 * 1_000) }
            result.append(DetailedScoreAction(type: .matchFinished, epochMilliseconds: endMilliseconds, scores: [record.team1FinalScore, record.team2FinalScore], setScores: [record.team1SetScore ?? 0, record.team2SetScore ?? 0], winner: record.winner == "left" ? .team1 : (record.winner == "right" ? .team2 : nil), summary: NSLocalizedString("game_ended", comment: "")))
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
