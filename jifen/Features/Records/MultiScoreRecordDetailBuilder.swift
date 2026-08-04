import Foundation
import RecordCore

enum MultiScoreRecordDetailEvent: Equatable {
    case scoreAdjustment(participantName: String?, delta: Int?)
    case matchStarted
    case matchFinished
    case reset
    case undo
    case stateChanged
}

struct MultiScoreRecordDetailRow: Identifiable, Equatable {
    let id: String
    let epochMilliseconds: Int64?
    let event: MultiScoreRecordDetailEvent
}

/// Builds the HarmonyOS-style multi-score history without rewriting persisted
/// records. Legacy intent strings retain the participant index, so they take
/// precedence over the less specific structured fallback.
enum MultiScoreRecordDetailBuilder {
    static func build(record: ScoreboardRecord) -> [MultiScoreRecordDetailRow] {
        let legacyRows = buildLegacyRows(record: record)
        if !legacyRows.isEmpty {
            return legacyRows
        }
        return buildStructuredRows(record: record)
    }

    private static func buildLegacyRows(record: ScoreboardRecord) -> [MultiScoreRecordDetailRow] {
        let participants = record.displayParticipants
        return record.actions.enumerated().compactMap { index, raw in
            let parsed = splitTimestamp(from: raw)
            let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, !body.hasPrefix("layout:") else { return nil }

            let event: MultiScoreRecordDetailEvent
            if let adjustment = parseAdjustment(body, participants: participants) {
                event = adjustment
            } else {
                switch body {
                case "reset": event = .reset
                case "undo": event = .undo
                case "finish": event = .matchFinished
                case "start": event = .matchStarted
                default: event = body.hasPrefix("adjust:") || body.hasPrefix("edit:")
                    ? .scoreAdjustment(participantName: nil, delta: nil)
                    : .stateChanged
                }
            }

            return MultiScoreRecordDetailRow(
                id: "legacy-\(index)-\(parsed.timestamp ?? -1)",
                epochMilliseconds: parsed.timestamp,
                event: event
            )
        }
    }

    private static func buildStructuredRows(record: ScoreboardRecord) -> [MultiScoreRecordDetailRow] {
        let participants = record.displayParticipants
        return (record.detailedActions ?? []).enumerated().compactMap { index, action in
            if action.operationCode?.hasPrefix("layout:") == true { return nil }

            let event: MultiScoreRecordDetailEvent
            switch action.type {
            case .matchStarted: event = .matchStarted
            case .matchFinished: event = .matchFinished
            case .reset: event = .reset
            case .undo: event = .undo
            case .scoreChanged:
                event = .scoreAdjustment(
                    participantName: participantName(for: action.team, participants: participants),
                    delta: action.scoreChange
                )
            default: event = .stateChanged
            }

            return MultiScoreRecordDetailRow(
                id: "structured-\(index)-\(action.id.uuidString)",
                epochMilliseconds: action.epochMilliseconds,
                event: event
            )
        }
    }

    private static func splitTimestamp(from raw: String) -> (timestamp: Int64?, body: String) {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let timestamp = Int64(parts[0]) else {
            return (nil, raw)
        }
        return (timestamp, String(parts[1]))
    }

    private static func parseAdjustment(
        _ body: String,
        participants: [ScoreboardRecordParticipant]
    ) -> MultiScoreRecordDetailEvent? {
        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "adjust" || parts[0] == "edit" else { return nil }
        guard let participantIndex = Int(parts[1]), let delta = Int(parts[2]) else {
            return .scoreAdjustment(participantName: nil, delta: nil)
        }
        let name = participants.indices.contains(participantIndex)
            ? participants[participantIndex].name
            : nil
        return .scoreAdjustment(participantName: name, delta: delta)
    }

    private static func participantName(
        for team: RecordTeam?,
        participants: [ScoreboardRecordParticipant]
    ) -> String? {
        let index: Int?
        switch team {
        case .team1: index = 0
        case .team2: index = 1
        case .team3: index = 2
        case .team4: index = 3
        case nil: index = nil
        }
        guard let index, participants.indices.contains(index) else { return nil }
        return participants[index].name
    }
}
