import Foundation
import OSLog
import RecordCore
import ScoreCore
import SessionCore

enum ReducerScoreboardRecordPersistence {
    static func nowMilliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    static func snapshot(code: String, scores: [Int], setScores: [Int] = []) -> String {
        let normalizedCode = normalizedOperationCode(code)
        return "\(nowMilliseconds())|snapshot|\(normalizedCode)|\(scores.map(String.init).joined(separator: ","))|\(setScores.map(String.init).joined(separator: ","))"
    }

    static func normalizedOperationCode(_ code: String) -> String {
        let sanitized = code.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        return String(sanitized)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
    }

    struct StateSnapshot<State: Codable>: Codable {
        var schemaVersion: Int = 1
        let state: State
        let undoStates: [State]
        let intentTimeline: [String]
        let detailedActions: [DetailedScoreAction]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case state
            case undoStates
            case intentTimeline
            case detailedActions
        }

        init(
            schemaVersion: Int = 1,
            state: State,
            undoStates: [State],
            intentTimeline: [String],
            detailedActions: [DetailedScoreAction]
        ) {
            self.schemaVersion = schemaVersion
            self.state = state
            self.undoStates = undoStates
            self.intentTimeline = intentTimeline
            self.detailedActions = detailedActions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            state = try container.decode(State.self, forKey: .state)
            undoStates = try container.decodeIfPresent([State].self, forKey: .undoStates) ?? []
            intentTimeline = try container.decodeIfPresent([String].self, forKey: .intentTimeline) ?? []
            detailedActions = try container.decodeIfPresent([DetailedScoreAction].self, forKey: .detailedActions) ?? []
        }
    }

    struct DecodedStateSnapshot<State> {
        let state: State
        let undoStates: [State]
        let intentTimeline: [String]
        let detailedActions: [DetailedScoreAction]
        let isWrapped: Bool
    }

    /// Reads the complete reducer snapshot first, then falls back to the raw
    /// state written by pre-wrapper builds. Keeping this as the single decoder
    /// also lets record winner resolution inspect the authoritative final state.
    static func decodeSnapshot<State: Codable>(
        _ data: Data,
        as type: State.Type
    ) -> DecodedStateSnapshot<State>? {
        if let snapshot = try? JSONDecoder().decode(StateSnapshot<State>.self, from: data),
           snapshot.schemaVersion >= 1 {
            return DecodedStateSnapshot(
                state: snapshot.state,
                undoStates: snapshot.undoStates,
                intentTimeline: snapshot.intentTimeline,
                detailedActions: snapshot.detailedActions,
                isWrapped: true
            )
        }
        guard let state = try? JSONDecoder().decode(type, from: data) else { return nil }
        return DecodedStateSnapshot(
            state: state,
            undoStates: [],
            intentTimeline: [],
            detailedActions: [],
            isWrapped: false
        )
    }

    static func loadResume<State: Codable>(
        recordId: String,
        as type: State.Type
    ) -> (record: ManualScoreboardResumeState, state: State, undoStates: [State], intentTimeline: [String], detailedActions: [DetailedScoreAction])? {
        guard let record = ManualResumeSessionStore.load(recordID: recordId),
              let data = record.stateSnapshot else {
            return nil
        }
        guard let snapshot = decodeSnapshot(data, as: type) else { return nil }
        return (
            record,
            snapshot.state,
            snapshot.undoStates,
            snapshot.intentTimeline.isEmpty ? record.actions : snapshot.intentTimeline,
            snapshot.detailedActions.isEmpty ? (record.detailedActions ?? []) : snapshot.detailedActions
        )
    }

    @MainActor
    @discardableResult
    static func saveRecord<State: Codable>(
        id: String,
        gameType: GameType,
        startedAt: Date,
        leftName: String,
        rightName: String,
        left: Int,
        right: Int,
        leftSets: Int? = nil,
        rightSets: Int? = nil,
        winnerIdentity: ScoreboardWinnerIdentity? = nil,
        actionCount: Int,
        actions: [String] = [],
        detailedActions: [DetailedScoreAction]? = nil,
        undoStates: [State]? = nil,
        finished: Bool,
        snapshot: State,
        sessionSnapshotData: Data? = nil,
        extra: [String: Any] = [:],
        projectConfiguration: [String: Any] = [:],
        finishedSessionId: UUID? = nil,
        finishedCommitCoordinator: FinishedSessionCommitCoordinator? = nil
    ) -> Bool {
        guard actionCount > 0 else { return true }
        if !finished, gameType == .eightBall || gameType == .nineBall || gameType == .snooker {
            // These reducers already persist their complete ScoreSession bundle.
            // A second manual payload would overwrite the authoritative resume.
            return true
        }
        let end = Date()
        let resolvedWinnerIdentity: ScoreboardWinnerIdentity? = winnerIdentity
            ?? (finished && left != right ? .team(left > right ? .team0 : .team1) : nil)
        let winner = resolvedWinnerIdentity?.legacyToken
        let snapshotData: Data
        do {
            if let sessionSnapshotData {
                snapshotData = sessionSnapshotData
            } else if let undoStates {
                snapshotData = try JSONEncoder().encode(StateSnapshot(
                    state: snapshot,
                    undoStates: undoStates,
                    intentTimeline: actions,
                    detailedActions: detailedActions ?? []
                ))
            } else {
                snapshotData = try JSONEncoder().encode(snapshot)
            }
        } catch {
            logger.error("Failed to encode reducer scoreboard record \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
        var extraData: [String: AnyCodable] = [
            "schemaVersion": AnyCodable(ScoreboardRecord.currentSchemaVersion),
            "canonicalGameType": AnyCodable(gameType.canonicalScoreboardIdentifier)
        ]
        for (key, value) in extra {
            extraData[key] = AnyCodable(value)
        }
        var configuration: [String: AnyCodable] = [:]
        for (key, value) in projectConfiguration {
            configuration[key] = AnyCodable(value)
        }
        var record = ScoreboardRecord(
            id: id,
            gameType: gameType,
            startTime: startedAt,
            endTime: finished ? end : nil,
            duration: end.timeIntervalSince(startedAt),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: left,
            team2FinalScore: right,
            team1SetScore: leftSets,
            team2SetScore: rightSets,
            winner: winner,
            winnerIdentity: resolvedWinnerIdentity,
            actions: actions,
            totalScoreChanges: actionCount,
            extraData: extraData,
            projectConfiguration: configuration.isEmpty ? nil : configuration,
            stateSnapshot: snapshotData,
            status: finished ? .finished : .draft
        )
        let resolvedDetailedActions = detailedActions?.isEmpty == false
            ? detailedActions!
            : ScoreboardRecordActionAdapter.actions(for: record)
        record.detailedActions = resolvedDetailedActions
        record.setResults = ScoreboardRecordActionAdapter.setResults(from: resolvedDetailedActions)
        do {
            if finished,
               let finishedCommitCoordinator,
               let sessionId = finishedSessionId ?? ManualResumeSessionStore.sessionID(for: id) {
                let recordCommit = try finishedCommitCoordinator.commitRecord(
                    record,
                    sessionId: sessionId
                )
                Task {
                    let result = await finishedCommitCoordinator.cleanupResume(after: recordCommit)
                    if let cleanupError = result.cleanupError {
                        ScoreboardPersistenceFailureReporter.report(
                            cleanupError,
                            context: "Failed to clean finished reducer resume \(sessionId.uuidString)"
                        )
                    }
                }
            } else {
                try ScoreboardLifecyclePersistence.save(record, finished: finished)
            }
            return true
        } catch {
            logger.error("Failed to save reducer scoreboard record \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private static let logger = Logger(
        subsystem: "com.douhua.jifen.ios",
        category: "ReducerScoreboardRecordPersistence"
    )
}
