import Foundation
import LinkCore
import ScoreCore

/// Shared Watch-link menu extras for phone scoreboards.
enum WatchLinkMenuSupport {
    static func extraItems(
        entryEnabled: Bool,
        sessionId: UUID?,
        isFollower: Bool
    ) -> [ScoreboardMenuItem] {
        guard entryEnabled, sessionId != nil else { return [] }
        var items: [ScoreboardMenuItem] = []
        if isFollower {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("linked_score_takeover", value: "接管计分", comment: ""),
                    action: "takeover",
                    group: .sync,
                    icon: "applewatch"
                )
            )
        }
        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("linked_score_end", value: "结束联动", comment: ""),
                action: "endLink",
                group: .sync,
                icon: "xmark.circle"
            )
        )
        return items
    }
}

/// Persist a finished Watch-linked match onto the phone record store.
enum LinkedMatchRecordIngestor {
    @MainActor
    @discardableResult
    static func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        sessionId: UUID? = nil
    ) throws -> String {
        guard let appType = GameType(scoreCoreGameType: gameType) else {
            throw LinkedRecordIngestError.unsupportedGameType(gameType.rawValue)
        }
        let projected = project(snapshot: payload.snapshot, gameType: appType, winnerSide: payload.winnerSide)
        let endMs = payload.endTimeEpochMilliseconds ?? Int64(Date().timeIntervalSince1970 * 1000)
        let startMs = payload.startTimeEpochMilliseconds ?? (endMs - 60_000)
        let start = Date(timeIntervalSince1970: Double(startMs) / 1000)
        let end = Date(timeIntervalSince1970: Double(endMs) / 1000)
        let duration = payload.durationSeconds ?? max(1, end.timeIntervalSince(start))
        let scoreChanges = max(1, payload.totalScoreChanges ?? 1)
        var extra: [String: AnyCodable] = [
            "syncFrom": AnyCodable("watch"),
            "watchSyncTime": AnyCodable(Int64(Date().timeIntervalSince1970 * 1000))
        ]
        if let sessionId {
            extra["linkedSessionId"] = AnyCodable(sessionId.uuidString)
        }
        if case .nineBall(let state) = payload.snapshot {
            extra["players"] = AnyCodable((0..<state.playerCount).map { index in
                [
                    "name": state.resolvedName(
                        at: index,
                        fallback: String(
                            format: NSLocalizedString(
                                "multi_score_player_default_format",
                                value: "选手 %d",
                                comment: ""
                            ),
                            index + 1
                        )
                    ),
                    "finalScore": state.playerPoints[index]
                ] as [String: Any]
            })
        }
        let recordId = payload.recordId.isEmpty
            ? (sessionId.map { "w_\($0.uuidString)" } ?? "w_\(UUID().uuidString)")
            : payload.recordId
        var record = ScoreboardRecord(
            id: recordId,
            gameType: appType,
            startTime: start,
            endTime: end,
            duration: duration,
            team1Name: projected.leftName,
            team2Name: projected.rightName,
            team1FinalScore: projected.leftScore,
            team2FinalScore: projected.rightScore,
            team1SetScore: projected.leftSets,
            team2SetScore: projected.rightSets,
            winner: projected.winner,
            actions: ["watch_link_finish"],
            totalScoreChanges: scoreChanges,
            extraData: extra,
            status: .finished
        )
        if let data = try? JSONEncoder().encode(payload.snapshot) {
            record.stateSnapshot = data
        }
        try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        return recordId
    }

    private struct Projection {
        var leftName: String
        var rightName: String
        var leftScore: Int
        var rightScore: Int
        var leftSets: Int?
        var rightSets: Int?
        var winner: String?
    }

    private static func project(
        snapshot: LinkedScoreboardSnapshot,
        gameType: GameType,
        winnerSide: MatchSide?
    ) -> Projection {
        let winner: String? = {
            switch winnerSide {
            case .left: return "left"
            case .right: return "right"
            case nil: return nil
            }
        }()
        switch snapshot {
        case .basketball(let state):
            return .init(
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftScore,
                rightScore: state.rightScore,
                leftSets: nil,
                rightSets: nil,
                winner: winner
            )
        case .rally(let state):
            return .init(
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftPoints,
                rightScore: state.rightPoints,
                leftSets: state.leftSets,
                rightSets: state.rightSets,
                winner: winner
            )
        case .tennis(let state):
            return .init(
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftGames,
                rightScore: state.rightGames,
                leftSets: state.leftSets,
                rightSets: state.rightSets,
                winner: winner
            )
        case .archery(let state):
            return .init(
                leftName: state.leftName,
                rightName: state.rightName,
                leftScore: state.leftArrowSum,
                rightScore: state.rightArrowSum,
                leftSets: state.leftSetPoints,
                rightSets: state.rightSetPoints,
                winner: winner
            )
        case .eightBall(let state):
            return .init(
                leftName: NSLocalizedString("watch_team_red", value: "红方", comment: ""),
                rightName: NSLocalizedString("watch_team_blue", value: "蓝方", comment: ""),
                leftScore: state.leftPoints,
                rightScore: state.rightPoints,
                leftSets: nil,
                rightSets: nil,
                winner: winner
            )
        case .nineBall(let state):
            return .init(
                leftName: state.resolvedName(
                    at: 0,
                    fallback: String(
                        format: NSLocalizedString(
                            "multi_score_player_default_format",
                            value: "选手 %d",
                            comment: ""
                        ),
                        1
                    )
                ),
                rightName: state.resolvedName(
                    at: 1,
                    fallback: String(
                        format: NSLocalizedString(
                            "multi_score_player_default_format",
                            value: "选手 %d",
                            comment: ""
                        ),
                        2
                    )
                ),
                leftScore: state.leftPoints,
                rightScore: state.rightPoints,
                leftSets: nil,
                rightSets: nil,
                winner: winner
            )
        case .snooker(let state):
            return .init(
                leftName: NSLocalizedString("watch_team_red", value: "红方", comment: ""),
                rightName: NSLocalizedString("watch_team_blue", value: "蓝方", comment: ""),
                leftScore: state.leftScore,
                rightScore: state.rightScore,
                leftSets: state.leftFrames,
                rightSets: state.rightFrames,
                winner: winner
            )
        }
    }
}

/// Ingests auto-transferred standalone watch records into phone ScoreboardRecord storage.
enum WatchStandaloneRecordIngestor {
    @MainActor
    @discardableResult
    static func ingest(_ payload: WatchRecordTransferPayload) throws -> String {
        guard let gameType = mapGameType(payload.gameType) else {
            throw LinkedRecordIngestError.unsupportedGameType(payload.gameType)
        }
        let rawId = payload.id.hasPrefix("w_") ? payload.id : "w_\(payload.id)"
        let start = Date(timeIntervalSince1970: Double(payload.startTimeEpochMilliseconds) / 1000)
        let end = Date(timeIntervalSince1970: Double(payload.endTimeEpochMilliseconds) / 1000)
        let winnerSide: String? = {
            guard let winner = payload.winner, !winner.isEmpty else { return nil }
            if winner == payload.team1Name { return "left" }
            if winner == payload.team2Name { return "right" }
            if winner == "left" || winner == "right" { return winner }
            return nil
        }()
        var extraData: [String: AnyCodable] = [
            "syncFrom": AnyCodable("watch"),
            "watchSyncTime": AnyCodable(Int64(Date().timeIntervalSince1970 * 1000))
        ]
        if let participants = payload.participants, !participants.isEmpty {
            extraData["players"] = AnyCodable(participants.map {
                ["name": $0.name, "finalScore": $0.score] as [String: Any]
            })
        }
        let projectConfiguration = payload.projectConfiguration?.mapValues(AnyCodable.init)
        let record = ScoreboardRecord(
            id: rawId,
            gameType: gameType,
            startTime: start,
            endTime: end,
            duration: payload.durationSeconds,
            team1Name: payload.team1Name,
            team2Name: payload.team2Name,
            team1FinalScore: payload.team1FinalScore,
            team2FinalScore: payload.team2FinalScore,
            team1SetScore: payload.team1SetScore,
            team2SetScore: payload.team2SetScore,
            winner: winnerSide,
            actions: payload.actions.isEmpty ? ["watch_auto_sync"] : payload.actions,
            totalScoreChanges: max(1, payload.totalScoreChanges),
            extraData: extraData,
            projectConfiguration: projectConfiguration,
            status: .finished
        )
        try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        return rawId
    }

    private static func mapGameType(_ raw: String) -> GameType? {
        switch raw {
        case "pingpong": return .pingpong
        case "badminton": return .badminton
        case "tennis": return .tennis
        case "pickleball": return .pickleball
        case "archery", "archery_dual": return .archery
        case "eight_ball", "eightBall": return .eightBall
        case "nine_ball", "nineBall": return .nineBall
        case "snooker": return .snooker
        // Phone has no basketball-training scoreboard yet — keep watch-only.
        case "basketballTraining": return nil
        default:
            return GameType(rawValue: raw)
        }
    }
}

private enum LinkedRecordIngestError: LocalizedError {
    case unsupportedGameType(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedGameType(let value):
            return String(
                format: NSLocalizedString(
                    "linked_score_unsupported_record_type",
                    value: "无法同步不支持的手表记录类型：%@",
                    comment: ""
                ),
                value
            )
        }
    }
}
