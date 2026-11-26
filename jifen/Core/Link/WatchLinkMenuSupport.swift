import Foundation
import LinkCore
import RecordCore
import ScoreCore

/// Shared Watch-link menu extras for phone scoreboards.
///
/// M3 起联动会话恒为 `.shared`：两端都能计分，只保留双向「同步积分」与
/// 「结束联动」，不再有接管、强制接管或手表后台提示。
enum WatchLinkMenuSupport {
    static func extraItems(
        entryEnabled: Bool,
        sessionId: UUID?
    ) -> [ScoreboardMenuItem] {
        guard entryEnabled, sessionId != nil else { return [] }
        return [
            ScoreboardMenuItem(
                title: NSLocalizedString("linked_score_resync", value: "同步积分", comment: ""),
                action: "resync",
                group: .sync,
                icon: "arrow.triangle.2.circlepath"
            ),
            ScoreboardMenuItem(
                title: NSLocalizedString("linked_score_end", value: "结束联动", comment: ""),
                action: "endLink",
                group: .sync,
                icon: "xmark.circle"
            )
        ]
    }
}

@MainActor
protocol PhoneLinkRecordSink {
    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID
    ) throws -> String
}

struct DefaultPhoneLinkRecordSink: PhoneLinkRecordSink {
    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID
    ) throws -> String {
        try LinkedMatchRecordIngestor.ingest(
            payload: payload,
            gameType: gameType,
            sessionId: matchId
        )
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
        let record = try makeRecord(payload: payload, gameType: gameType, sessionId: sessionId)
        try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        return record.id
    }

    @MainActor
    static func makeRecord(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        sessionId: UUID? = nil
    ) throws -> ScoreboardRecord {
        let id = payload.recordId.isEmpty
            ? "w_\((sessionId ?? UUID()).uuidString)"
            : payload.recordId
        let snapshot = payload.snapshot
        let canonical = MatchRecordProjector.canonicalRecord(
            id: id,
            kind: .sport(gameType),
            source: .linkedWatch,
            snapshot: snapshot,
            gameType: gameType,
            winnerSide: payload.winnerSide,
            startEpochMilliseconds: payload.startTimeEpochMilliseconds,
            endEpochMilliseconds: payload.endTimeEpochMilliseconds,
            durationSeconds: payload.durationSeconds,
            participantNames: WatchCanonicalRecordAdapter.participantNames(
                for: snapshot, announcedNames: payload.participantNames
            ),
            // The packed training state supplies the full shot history and counters.
            detailedActions: snapshot.basketballTrainingState == nil ? payload.detailedActions : [],
            totalScoreChanges: payload.totalScoreChanges
        )
        return try WatchCanonicalRecordAdapter.toScoreboardRecord(
            canonical, linkedSessionId: sessionId, linkedSnapshot: snapshot
        )
    }
}

/// Ingests auto-transferred standalone watch records into phone ScoreboardRecord storage.
enum WatchStandaloneRecordIngestor {
    @MainActor
    @discardableResult
    static func ingest(_ payload: WatchRecordTransferPayload) throws -> String {
        let record = try makeRecord(payload)
        try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        return record.id
    }

    @MainActor
    static func makeRecord(_ payload: WatchRecordTransferPayload) throws -> ScoreboardRecord {
        try WatchCanonicalRecordAdapter.toScoreboardRecord(payload)
    }
}

/// Converts Watch records to the released phone schema and preserves phone-only
/// resume metadata at the ingestion boundary.
@MainActor
enum WatchCanonicalRecordAdapter {
    static func toScoreboardRecord(
        _ record: CanonicalMatchRecord,
        linkedSessionId: UUID? = nil,
        linkedSnapshot: LinkedScoreboardSnapshot? = nil
    ) throws -> ScoreboardRecord {
        guard record.schemaVersion == CanonicalMatchRecord.currentSchemaVersion else {
            throw CocoaError(.coderReadCorrupt)
        }
        guard case .sport(let gameType) = record.kind else {
            throw LinkedRecordIngestError.unsupportedGameType("counter")
        }
        guard let appType = GameType(scoreCoreGameType: gameType) else {
            throw LinkedRecordIngestError.unsupportedGameType(gameType.rawValue)
        }
        let isLinked = linkedSnapshot != nil || linkedSessionId != nil
            || record.source == .linkedWatch || record.source == .linkedPhone
        let id = isLinked || record.id.hasPrefix("w_") ? record.id : "w_\(record.id)"
        let endTime = Date(timeIntervalSince1970: Double(record.endEpochMilliseconds) / 1_000)
        let training = appType == .basketballTraining ? record.basketballTraining : nil
        let counts = training?.counts
        let tiebreakOnly = linkedSnapshot?.tennisState?.rules.setScoringMode == .tiebreakOnly
            || (appType == .tennis && record.projectConfiguration["setScoringMode"] == "tiebreak_only")
        let hasNoSetLayer = [.football, .football5v5, .basketballTraining].contains(appType)
        let omitsSetScores = tiebreakOnly || hasNoSetLayer || (isLinked && [.nineBall, .eightBall].contains(appType))

        var extra: [String: AnyCodable] = [
            "syncFrom": AnyCodable("watch"),
            "watchSyncTime": AnyCodable(Int(Date().timeIntervalSince1970 * 1_000))
        ]
        if let linkedSessionId {
            extra["linkedSessionId"] = AnyCodable(linkedSessionId.uuidString)
        }
        if (!isLinked || appType == .nineBall), let players = record.participants, !players.isEmpty {
            extra["players"] = AnyCodable(players.map {
                ["name": $0.name, "finalScore": $0.score] as [String: Any]
            })
        }

        var actions = isLinked ? ["watch_link_finish"] : record.detailedActions.compactMap { $0.summary ?? $0.operationCode }
        if actions.isEmpty { actions = ["watch_auto_sync"] }
        var details = recordActions(
            record.detailedActions, omittingSecondaryScores: tiebreakOnly || (!isLinked && hasNoSetLayer)
        )
        var configuration: [String: AnyCodable]
        let stateSnapshot: Data?
        if let training, let counts {
            let mode = training.mode
            let shots = training.shots.map {
                ShotTrainingShot(id: UUID(), points: $0.points, made: $0.made, timestamp: $0.timestamp)
            }
            // Preserve the phone's training timeline and summary codes from the packed shots.
            let shotActions = training.detailedActions(endingAt: endTime)
            details = shotActions
            actions = shotActions.compactMap { action in
                guard let time = action.epochMilliseconds, let code = action.operationCode else { return nil }
                return "\(time)|\(code)"
            }
            extra.merge(ShotTrainingRecordMetadata.extraData(mode: mode, counts: counts)) { _, latest in latest }
            configuration = [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(gameType.rawValue),
                "basketballTrainingScoringMode": AnyCodable(mode.rawValue)
            ]
            stateSnapshot = try JSONEncoder().encode(ShotTrainingResumeState(
                mode: mode, shots: shots, finished: true, earlierCounts: training.earlierCounts
            ))
        } else if let linkedSnapshot {
            configuration = recordConfiguration(snapshot: linkedSnapshot, gameType: gameType)
            stateSnapshot = try JSONEncoder().encode(linkedSnapshot)
        } else {
            configuration = record.projectConfiguration.mapValues(AnyCodable.init)
            configuration[ScoreboardRecordConfiguration.Key.scoreCoreGameType] = AnyCodable(gameType.rawValue)
            configuration[ScoreboardRecordConfiguration.Key.isSingles] = AnyCodable(!gameType.isDoublesScoreboard)
            stateSnapshot = nil
        }

        let winner = appType == .nineBall
            ? participantWinner(record.winnerIdentity, participants: record.participants)
            : record.winnerIdentity
        return ScoreboardRecord(
            id: id,
            gameType: appType,
            startTime: training?.startTime ?? Date(timeIntervalSince1970: Double(record.startEpochMilliseconds) / 1_000),
            endTime: endTime,
            duration: training == nil ? record.durationSeconds : max(0, record.durationSeconds),
            team1Name: training == nil ? record.team1Name : NSLocalizedString("shot_training_miss", value: "未中", comment: ""),
            team2Name: training == nil ? record.team2Name : NSLocalizedString("shot_training_made", value: "命中", comment: ""),
            team1FinalScore: counts?.missed ?? record.team1FinalScore,
            team2FinalScore: counts?.made ?? record.team2FinalScore,
            team1SetScore: omitsSetScores ? nil : record.team1SetScore,
            team2SetScore: omitsSetScores ? nil : record.team2SetScore,
            winnerIdentity: training == nil ? winner : nil,
            actions: actions,
            detailedActions: details,
            setResults: training == nil ? ScoreboardRecordActionAdapter.setResults(from: details) : nil,
            totalScoreChanges: counts?.attempts ?? max(0, record.totalScoreChanges),
            extraData: extra,
            projectConfiguration: configuration,
            stateSnapshot: stateSnapshot,
            status: .finished
        )
    }

    /// Supplies the same localized names as the phone record path. Nine-ball
    /// player names are part of the live state and can change after setup.
    static func participantNames(for snapshot: LinkedScoreboardSnapshot, announcedNames: [String]) -> [String] {
        switch snapshot {
        case .nineBall(let state):
            return (0..<state.playerCount).map { index in
                let format = NSLocalizedString("multi_score_player_default_format", value: "选手 %d", comment: "")
                return state.resolvedName(at: index, fallback: String(format: format, index + 1))
            }
        case .eightBall, .snooker:
            let defaults = DefaultParticipantNames.resolve(for: snapshot.eightBallState == nil ? .snooker : .eightBall)
            return [defaults.left, defaults.right].enumerated().map { index, fallback in
                guard announcedNames.indices.contains(index) else { return fallback }
                let name = announcedNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? fallback : name
            }
        default:
            return announcedNames
        }
    }

    private static func participantWinner(
        _ identity: ScoreboardWinnerIdentity?, participants: [RecordParticipantScore]?
    ) -> ScoreboardWinnerIdentity? {
        guard let participants, !participants.isEmpty else { return identity }
        let index: Int?
        switch identity {
        case .participant(let participant): index = participant
        case .team(.team0): index = 0
        case .team(.team1): index = 1
        case nil: index = nil
        }
        if let index, participants.indices.contains(index) { return .participant(index: index) }
        guard let topScore = participants.map(\.score).max() else { return nil }
        let leaders = participants.indices.filter { participants[$0].score == topScore }
        return leaders.count == 1 ? .participant(index: leaders[0]) : nil
    }

    private static func recordConfiguration(
        snapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType
    ) -> [String: AnyCodable] {
        var configuration: [String: AnyCodable] = [
            ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(gameType.rawValue),
            ScoreboardRecordConfiguration.Key.isSingles: AnyCodable(!gameType.isDoublesScoreboard)
        ]
        switch snapshot {
        case .rally(let state):
            configuration.merge(
                ScoreboardRecordConfiguration.rally(
                    gameType: gameType,
                    state: state,
                    voiceAnnouncement: false
                ),
                uniquingKeysWith: { _, latest in latest }
            )
        case .tennis(let state):
            configuration.merge(
                ScoreboardRecordConfiguration.tennis(
                    gameType: gameType,
                    state: state,
                    voiceAnnouncement: false
                ),
                uniquingKeysWith: { _, latest in latest }
            )
        case .nineBall(let state):
            configuration["playerCount"] = AnyCodable(state.playerCount)
        case .snooker(let state):
            configuration["maxFrames"] = AnyCodable(state.maxFrames)
        case .football(let state):
            configuration["footballHalfLengthSeconds"] = AnyCodable(state.timer.halfLengthSeconds)
            configuration["showMatchTime"] = AnyCodable(true)
        case .archery, .eightBall, .basketballTraining:
            break
        }
        return configuration
    }

}

private func recordActions(
    _ actions: [DetailedScoreAction],
    omittingSecondaryScores: Bool
) -> [DetailedScoreAction] {
    guard omittingSecondaryScores else { return actions }
    return actions.map(ScoreActionProjector.omittingSecondaryScores(from:))
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
