import Foundation
import ScoreCore

nonisolated enum PersonalJSON: Codable, Hashable, Sendable {
    case null, bool(Bool), integer(Int64), number(Double), string(String)
    case array([PersonalJSON]), object([String: PersonalJSON])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([PersonalJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: PersonalJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var integer: Int64? { if case .integer(let value) = self { return value }; return nil }
}

nonisolated struct PersonalWireParticipant: Codable, Sendable {
    var seatKey: String
    var kind: String
    var nameSnapshot: String
    var personRef: ParticipantPersonRef?
    var sideKey: String?
}

nonisolated struct PersonalRecordOrigin: Codable, Sendable {
    var platform = "ios"
    var nativeSchemaVersion: Int
    var sessionId: String?
    var sourceSystem: String?
}

nonisolated struct PersonalRecordEnvelope: Codable, Sendable {
    var libraryId: String
    var recordKey: String
    var kind: String
    var project: String
    var playedAt: Int64
    var schemaVersion = 1
    var participantMode: String
    var participants: [PersonalWireParticipant]
    var summary: [String: PersonalJSON]
    var origin: PersonalRecordOrigin
    var nativePayload: [String: PersonalJSON]
    var note: String?
    var assetIds: [String]
    var id: String?
    var revision: Int?
    var updatedAt: Int64?
    var deleted: Bool?

    enum CodingKeys: String, CodingKey {
        case libraryId, recordKey, kind, project, playedAt, schemaVersion, participantMode, participants, summary, origin, nativePayload, note, assetIds, id, revision, updatedAt, deleted
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(libraryId, forKey: .libraryId); try c.encode(recordKey, forKey: .recordKey)
        try c.encode(kind, forKey: .kind); try c.encode(project, forKey: .project); try c.encode(playedAt, forKey: .playedAt)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(participantMode, forKey: .participantMode)
        try c.encode(participants, forKey: .participants); try c.encode(summary, forKey: .summary)
        try c.encode(origin, forKey: .origin); try c.encode(nativePayload, forKey: .nativePayload)
        // Explicit null deletes a known annotation; omission would preserve an old cloud value.
        try c.encode(note, forKey: .note); try c.encode(assetIds, forKey: .assetIds)
        try c.encodeIfPresent(id, forKey: .id); try c.encodeIfPresent(revision, forKey: .revision)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt); try c.encodeIfPresent(deleted, forKey: .deleted)
    }
}

enum PersonalRecordAdapter {
    static func supportsPerson(_ game: GameType) -> Bool {
        ScoreboardCommonNamePolicy.nameType(for: game) == .player && game != .basketballTraining && game != .stopwatch
    }

    /// Record-only seat metadata can be built once with the list summaries.
    /// Identity resolution stays live so linking/unlinking names updates filters.
    static func seatDescriptors(_ record: ScoreboardRecord) -> [PersonalRecordSeat] {
        guard supportsPerson(record.gameType) else { return [] }
        let data = (record.projectConfiguration ?? [:]).merging(record.extraData ?? [:], uniquingKeysWith: { _, rhs in rhs })
        guard (data["competitionFormat"]?.value as? String) != "team" else { return [] }
        func text(_ key: String) -> String? {
            (data[key]?.value as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        var result: [PersonalRecordSeat] = []
        if text("team1Player1Name") != nil || text("team2Player1Name") != nil {
            for side in 0..<2 {
                for position in 0..<3 {
                    if let name = text("team\(side + 1)Player\(position + 1)Name") {
                        result.append(.init(id: "side:\(side):player:\(position)", name: name, side: "side:\(side)"))
                    }
                }
            }
        } else if [.doudizhu, .uno, .multiScoreboard, .nineBall].contains(record.gameType), !record.displayParticipants.isEmpty {
            result = record.displayParticipants.enumerated().map { .init(id: "player:\($0.offset)", name: $0.element.name) }
        } else {
            result = [.init(id: "side:0", name: record.team1Name, side: "side:0"),
                      .init(id: "side:1", name: record.team2Name, side: "side:1")]
        }
        return result
    }

    static func seats(_ record: ScoreboardRecord, identity: ParticipantIdentityStore? = nil) -> [PersonalRecordSeat] {
        let identity = identity ?? .shared
        var result = seatDescriptors(record)
        let selected = identity.selections(for: record.id)
        for index in result.indices {
            if let selection = selected[result[index].id], selection.name == result[index].name {
                result[index].personRef = selection.personRef
            }
        }
        // Group participation is read from confirmed group results. A private
        // backup must not count an unconfirmed or later revoked group result.
        if record.groupMatchContext != nil {
            for index in result.indices { result[index].personRef = nil }
        }
        return result
    }

    static func isMine(_ record: ScoreboardRecord) -> Bool {
        guard record.groupMatchContext == nil else { return false }
        let names = Dictionary(uniqueKeysWithValues: seatDescriptors(record).map { ($0.id, $0.name) })
        return !names.isEmpty && ParticipantIdentityStore.shared.personalSeats(for: record.id, matchingSeatNames: names).count == 1
    }

    static func isMine(_ summary: ScoreboardRecordSummary, identity: ParticipantIdentityStore) -> Bool {
        guard summary.groupGameID == nil, let seats = summary.personalRecordSeatNames, !seats.isEmpty else { return false }
        return identity.personalSeats(for: summary.id, matchingSeatNames: seats).intersection(Set(seats.keys)).count == 1
    }

    static func isMine(_ record: PersonalRecordEnvelope) -> Bool {
        guard record.kind == "score", record.participantMode == "individual", record.deleted != true else { return false }
        if record.origin.sourceSystem == "group" && !record.libraryId.hasPrefix("group:") { return false }
        let identity = ParticipantIdentityStore.shared
        let valid = Set(record.participants.filter { $0.kind == "PERSON" }.map(\.seatKey))
        var mine = Set(record.participants.filter { $0.kind == "PERSON" && $0.personRef == identity.person }.map(\.seatKey))
        mine.formUnion(identity.personalSeats(for: record.recordKey, libraryId: record.libraryId))
        return mine.intersection(valid).count == 1
    }

    static func envelope(_ record: ScoreboardRecord, identity: ParticipantIdentityStore? = nil) throws -> PersonalRecordEnvelope {
        let identity = identity ?? .shared
        let seats = seats(record, identity: identity)
        var payload = try JSONDecoder().decode([String: PersonalJSON].self, from: JSONEncoder().encode(record))
        payload["note"] = record.note.map(PersonalJSON.string) ?? .null
        if record.voiceNote == nil { payload["voiceNote"] = .null }
        var summary: [String: PersonalJSON] = ["title": .string(record.gameType.displayName), "leftName": .string(record.team1Name), "rightName": .string(record.team2Name),
            "leftScore": .integer(Int64(record.team1FinalScore)), "rightScore": .integer(Int64(record.team2FinalScore)),
            "durationMs": .integer(Int64((record.duration ?? 0) * 1_000))]
        if !record.displayParticipants.isEmpty {
            summary["players"] = .array(record.displayParticipants.enumerated().map { index, participant in
                .object(["seatKey": .string("player:\(index)"), "name": .string(participant.name), "score": .integer(Int64(participant.score))])
            })
        }
        if let gameId = record.groupMatchContext?.gameID { summary["groupGameId"] = .string(gameId) }
        return .init(libraryId: identity.libraryId(for: record.id), recordKey: record.id,
                     kind: "score", project: record.resolvedScoreCoreGameType?.rawValue ?? record.gameType.canonicalScoreboardIdentifier,
                     playedAt: Int64(record.startTime.timeIntervalSince1970 * 1_000),
                     participantMode: !seats.isEmpty ? "individual" : "team",
                     participants: seats.isEmpty ? [.init(seatKey: "side:0", kind: "TEAM", nameSnapshot: record.team1Name, sideKey: "side:0"),
                                                    .init(seatKey: "side:1", kind: "TEAM", nameSnapshot: record.team2Name, sideKey: "side:1")]
                        : seats.map { .init(seatKey: $0.id, kind: "PERSON", nameSnapshot: $0.name, personRef: $0.personRef, sideKey: $0.side) },
                     summary: summary,
                     origin: .init(nativeSchemaVersion: record.schemaVersion,
                                   sessionId: record.syncMetadata?["sessionId"], sourceSystem: record.groupMatchContext != nil ? "group" : record.isSyncedFromWatch ? "watch" : nil),
                     nativePayload: payload, note: record.note, assetIds: [])
    }

    static func envelope(_ record: GameRecordSummary, identity: ParticipantIdentityStore? = nil) throws -> PersonalRecordEnvelope {
        let identity = identity ?? .shared
        return .init(libraryId: identity.libraryId(for: record.id), recordKey: record.id,
              kind: "timer", project: record.gameType.canonicalScoreboardIdentifier,
              playedAt: Int64(record.timestamp * 1_000), participantMode: "none", participants: [],
              summary: ["title": .string(record.gameType.displayName), "durationMs": .integer(Int64((record.duration ?? 0) * 1_000))],
              origin: .init(nativeSchemaVersion: 1),
              nativePayload: try JSONDecoder().decode([String: PersonalJSON].self, from: JSONEncoder().encode(record)), assetIds: [])
    }
}
