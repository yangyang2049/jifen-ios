import Foundation
import RecordCore
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
    var object: [String: PersonalJSON]? { if case .object(let value) = self { return value }; return nil }
    var array: [PersonalJSON]? { if case .array(let value) = self { return value }; return nil }
    var numeric: Double? {
        switch self { case .integer(let value): return Double(value); case .number(let value): return value; default: return nil }
    }
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

struct PersonalHistoricalNameCandidate: Identifiable {
    var id: String
    var name: String
    var seats: [PersonalHistoricalSeat] = []
    var records: [RecordsTabRecordItem] = []
    var recordCount: Int { records.count }
}

enum PersonalHistoricalNames {
    static func candidates(records: [ScoreboardRecord], cloudRecords: [PersonalRecordEnvelope],
                           identity: ParticipantIdentityStore, cloud: PersonalRecordsCloudSync,
                           initialName: String? = nil) -> [PersonalHistoricalNameCandidate] {
        let native = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let visible = RecordListSource.visibleRecords(scoreboard: records.map { ScoreboardRecordSummary(from: $0) },
            timers: [], cloudRecords: cloudRecords, identity: identity, cloud: cloud)
        var names: [String: PersonalHistoricalNameCandidate] = [:]
        var order: [String] = []
        for item in visible {
            let library: String, recordKey: String, seats: [PersonalRecordSeat]
            switch item {
            case .scoreboard(let summary):
                guard let record = native[summary.id], record.groupMatchContext == nil else { continue }
                library = identity.libraryId(for: record.id); recordKey = record.id
                seats = PersonalRecordAdapter.seats(record, identity: identity)
            case .cloud(let record):
                guard record.kind == "score", record.participantMode == "individual",
                      record.origin.sourceSystem != "group", !record.libraryId.hasPrefix("group:") else { continue }
                if let game = ScoreCore.GameType(rawValue: record.project).flatMap({ GameType(scoreCoreGameType: $0) }),
                   !PersonalRecordAdapter.supportsPerson(game) { continue }
                library = record.libraryId; recordKey = record.recordKey
                seats = record.participants.filter { $0.kind == "PERSON" }.map {
                    .init(id: $0.seatKey, name: $0.nameSnapshot, side: $0.sideKey, personRef: $0.personRef)
                }
            case .timer: continue
            }
            for seat in seats {
                let key = ParticipantIdentityRules.normalizedName(seat.name)
                guard !key.isEmpty else { continue }
                if names[key] == nil {
                    names[key] = .init(id: key, name: seat.name)
                    order.append(key)
                }
                names[key]?.seats.append(.init(libraryId: library, recordKey: recordKey, seat: seat))
                if names[key]?.records.last?.id != item.id { names[key]?.records.append(item) }
            }
        }
        if let initialName {
            let key = ParticipantIdentityRules.normalizedName(initialName)
            if !key.isEmpty && names[key] == nil {
                names[key] = .init(id: key, name: initialName)
                order.insert(key, at: 0)
            }
        }
        return order.compactMap { names[$0] }
    }
}

/// Decode into the existing presentation models without importing a foreign
/// record into the local store or reinterpreting its replay snapshot.
enum PersonalCloudRecordDecoder {
    static func gameType(_ record: PersonalRecordEnvelope) -> GameType? {
        ScoreCore.GameType(rawValue: record.project).flatMap { GameType(scoreCoreGameType: $0) }
            ?? GameType.allCases.first { $0.canonicalScoreboardIdentifier == record.project }
    }

    static func scoreboard(_ record: PersonalRecordEnvelope) -> ScoreboardRecord? {
        guard record.kind == "score", let game = gameType(record) else { return nil }
        var payload = record.nativePayload
        // The common annotation is authoritative, and another device's local
        // audio path must never be opened against this device's file system.
        payload["note"] = record.note.map(PersonalJSON.string) ?? .null
        payload["voiceNote"] = .null
        for (common, native) in [("leftScore", "team1FinalScore"), ("rightScore", "team2FinalScore"),
                                 ("leftName", "team1Name"), ("rightName", "team2Name")] {
            if let value = record.summary[common], value != .null { payload[native] = value }
        }
        if record.origin.platform == "ios", let native: ScoreboardRecord = decode(payload),
           native.id == record.recordKey, native.gameType == game {
            return native
        }

        let foreign = ["android", "harmonyos", "harmony"].contains(record.origin.platform)
            && record.origin.nativeSchemaVersion == 1
        let data = record.nativePayload
        guard foreign, let nativeLeft = int(data["team1FinalScore"]), let nativeRight = int(data["team2FinalScore"]) else { return nil }
        var extra = foreign ? data["extraData"]?.object ?? [:] : [:]
        var players = (data["players"]?.array ?? extra["players"]?.array ?? record.summary["players"]?.array ?? []).compactMap { value -> PersonalJSON? in
            guard var player = value.object else { return nil }
            if player["score"] == nil { player["score"] = player["finalScore"] }
            return .object(player)
        }
        if players.isEmpty, data["team3Name"]?.string != nil,
           [.doudizhu, .nineBall, .uno, .multiScoreboard].contains(game) {
            players = (1...4).compactMap { index in
                guard let name = data["team\(index)Name"]?.string, let score = data["team\(index)FinalScore"] else { return nil }
                return .object(["name": .string(name), "score": score])
            }
        }
        if !players.isEmpty { extra["players"] = .array(players) }
        let detailed = foreign ? (data["actions"]?.array ?? []).compactMap { action($0, game: game) } : []
        let explicitSets = foreign ? (data["sets"]?.array ?? []).compactMap { value -> RecordSetResult? in
            guard let set = value.object, let number = int(set["setNumber"]),
                  let left = int(set["team1Score"]), let right = int(set["team2Score"]) else { return nil }
            return .init(number: number, scores: [left, right], winner: team(set["winner"]))
        } : []
        let sets = explicitSets.isEmpty ? ScoreboardRecordActionAdapter.setResults(from: detailed) : explicitSets
        let start = foreign ? data["startTime"]?.numeric.map { Date(timeIntervalSince1970: $0 / 1_000) } : nil
        let end = foreign ? data["endTime"]?.numeric.map { Date(timeIntervalSince1970: $0 / 1_000) } : nil
        let duration = record.summary["durationMs"]?.numeric ?? (foreign ? data["duration"]?.numeric : nil)
        let participants = record.participants.map(\.nameSnapshot)
        var result = ScoreboardRecord(id: record.recordKey, gameType: game,
            startTime: start ?? Date(timeIntervalSince1970: Double(record.playedAt) / 1_000), endTime: end,
            duration: duration.map { $0 / 1_000 },
            team1Name: record.summary["leftName"]?.string ?? data["team1Name"]?.string ?? participants.first ?? game.displayName,
            team2Name: record.summary["rightName"]?.string ?? data["team2Name"]?.string ?? participants.dropFirst().first ?? "",
            team1FinalScore: int(record.summary["leftScore"]) ?? nativeLeft,
            team2FinalScore: int(record.summary["rightScore"]) ?? nativeRight,
            team1SetScore: int(data["team1SetScore"]), team2SetScore: int(data["team2SetScore"]),
            winnerIdentity: winner(data["winner"], hasPlayers: !players.isEmpty),
            detailedActions: detailed, setResults: sets,
            totalScoreChanges: int(data["totalScoreChanges"]) ?? detailed.filter { $0.type == .scoreChanged }.count,
            extraData: decode(extra), note: record.note,
            status: data["status"]?.string.flatMap(ScoreboardRecordStatus.init(rawValue:)) ?? .finished)
        // Foreign snapshot formats remain opaque. Only their recorded values
        // feed the recap; they cannot become an iOS resumable session.
        result.schemaVersion = foreign ? 4 : 1
        return result
    }

    static func timer(_ record: PersonalRecordEnvelope) -> GameRecordSummary? {
        guard record.kind == "timer", let game = gameType(record) else { return nil }
        if record.origin.platform == "ios", let native: GameRecordSummary = decode(record.nativePayload), native.id == record.recordKey {
            return native
        }
        var result = GameRecordSummary(id: record.recordKey, gameType: game, timestamp: Double(record.playedAt) / 1_000,
            duration: record.summary["durationMs"]?.numeric.map { $0 / 1_000 })
        let data = record.nativePayload
        guard ["android", "harmonyos", "harmony"].contains(record.origin.platform),
              record.origin.nativeSchemaVersion == 1, data["id"]?.string == record.recordKey else { return result }
        if result.duration == nil { result.duration = data["duration"]?.numeric.map { $0 / 1_000 } }
        func playerName(_ value: PersonalJSON?) -> String? {
            switch value?.string {
            case "PLAYER1": return BoardTimerParticipantNames.name(for: game, playerID: 1)
            case "PLAYER2": return BoardTimerParticipantNames.name(for: game, playerID: 2)
            default: return nil
            }
        }
        result.winner = playerName(data["winner"])
        let start = data["startTime"]?.numeric ?? Double(record.playedAt)
        // Preserve actual snapshots only; foreign clock configuration cannot become an iOS session.
        result.actions = data["actions"]?.array?.enumerated().compactMap { index, value -> TimerActionRecord? in
            guard let action = value.object, let timestamp = action["timestamp"]?.numeric,
                  timestamp.isFinite, timestamp >= start else { return nil }
            let type: TimerActionType
            switch action["actionType"]?.string {
            case "GAME_START": type = .start
            case "GAME_PAUSE": type = .pause
            case "GAME_RESUME": type = .resume
            case "PLAYER_SWITCH": type = .move
            case "TIMEOUT": type = .timeout
            case "GAME_END": type = .gameEnd
            default: return nil
            }
            func remaining(_ key: String) -> Int? {
                guard let value = action[key]?.numeric, value.isFinite, value >= 0 else { return nil }
                return Int(exactly: ceil(value / 1_000))
            }
            return .init(id: "\(record.recordKey):foreign:\(index)", elapsed: (timestamp - start) / 1_000,
                type: type, actor: type == .gameEnd ? result.winner : playerName(action["fromPlayer"]),
                leftRemaining: remaining("player1Time"), rightRemaining: remaining("player2Time"))
        }
        return result
    }

    static func replaySetup(_ native: ScoreboardRecord, envelope: PersonalRecordEnvelope,
                            identity: ParticipantIdentityStore) -> SportsSetupResult? {
        guard envelope.origin.platform == "ios", native.id == envelope.recordKey, native.groupMatchContext == nil,
              identity.readableLibraryIds.contains(envelope.libraryId) else { return nil }
        var setup = ScoreboardRecordConfiguration.setup(from: native, identity: identity)
        // A same-ID local record can belong to a different merged library.
        // Carry only the current person's explicit cloud seat or scoped claim.
        setup.participantSelections = nil
        let seats = PersonalRecordAdapter.seatDescriptors(native)
        let claims = identity.personalSeats(for: envelope.recordKey, libraryId: envelope.libraryId,
            matchingSeatNames: Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.name) }))
        var selections: [String: ParticipantSelection] = [:]
        for seat in seats {
            let explicit = envelope.participants.contains {
                $0.kind == "PERSON" && $0.seatKey == seat.id && $0.nameSnapshot == seat.name && $0.personRef == identity.person
            }
            if explicit || (claims.count == 1 && claims.contains(seat.id)) {
                selections[seat.id] = .init(name: seat.name, personRef: identity.person)
            }
        }
        setup.participantSelections = selections.isEmpty ? nil : selections
        return setup
    }

    private static func action(_ value: PersonalJSON, game: GameType) -> DetailedScoreAction? {
        guard let data = value.object, let code = data["actionType"]?.string,
              let left = int(data["team1Score"]), let right = int(data["team2Score"]) else { return nil }
        let type: DetailedScoreActionType
        switch code {
        case "GAME_START": type = .matchStarted
        case "GAME_END": type = .matchFinished
        case "SCORE_ADD", "SCORE_SUBTRACT", "EDIT_SCORE", "SCORE_CHANGE":
            type = data["foulAdd"] == .bool(true) || data["foulRemove"] == .bool(true) ? .foul : .scoreChanged
        case "SET_END":
            type = game == .boxing ? .roundFinished : [.basketball, .threeBasketball].contains(game) ? .periodFinished : .setFinished
        case "GAME_RESET": type = .reset
        case "UNDO": type = .undo
        default: type = .stateChanged
        }
        let participants = (data["participantsSnapshot"]?.array ?? []).compactMap { value -> ParticipantScoreSnapshot? in
            guard let player = value.object, let name = player["name"]?.string, let score = int(player["score"]) else { return nil }
            return .init(id: player["playerId"]?.integer.map(String.init) ?? name, name: name, score: score)
        }
        var scores = [left, right]
        for index in 3...4 { if let score = int(data["team\(index)Score"]), scores.count == index - 1 { scores.append(score) } }
        let sets: [Int]
        if let left = int(data["team1SetScore"]), let right = int(data["team2SetScore"]) { sets = [left, right] }
        else { sets = [] }
        return .init(type: type, epochMilliseconds: data["timestamp"]?.integer,
            team: team(data["team"]), scores: scores, setScores: sets,
            setNumber: int(data["setNumber"]), gameNumber: int(data["gameNumberInSet"]), roundNumber: int(data["roundNumber"]),
            periodNumber: [.basketball, .threeBasketball].contains(game) ? int(data["setNumber"]) : nil,
            scoreChange: int(data["scoreChange"]), winner: code == "SET_END" ? team(data["team"]) : nil,
            landlord: team(data["landlord"]),
            winners: data["winners"]?.array.map { $0.compactMap(team) }, losers: data["losers"]?.array.map { $0.compactMap(team) },
            farmers: data["farmers"]?.array.map { $0.compactMap(team) }, participants: participants,
            operationCode: data["cardRecordOpCode"]?.string, operationPayload: data["cardRecordPayload"]?.string,
            summary: data["description"]?.string, footballPeriod: int(data["footballPeriod"]), footballElapsedSeconds: int(data["footballElapsedSeconds"]))
    }

    private static func int(_ value: PersonalJSON?) -> Int? { value?.numeric.flatMap(Int.init(exactly:)) }
    private static func team(_ value: PersonalJSON?) -> RecordTeam? {
        value?.string.flatMap { RecordTeam(rawValue: $0.lowercased()) }
    }
    private static func winner(_ value: PersonalJSON?, hasPlayers: Bool) -> ScoreboardWinnerIdentity? {
        guard let team = team(value), let index = RecordTeam.allCases.firstIndex(of: team) else { return nil }
        if hasPlayers || index > 1 { return .participant(index: index) }
        return .team(index == 0 ? .team0 : .team1)
    }
    private static func decode<T: Decodable>(_ value: [String: PersonalJSON]) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
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

    static func isMine(_ record: PersonalRecordEnvelope, identity: ParticipantIdentityStore? = nil) -> Bool {
        guard record.kind == "score", record.participantMode == "individual", record.deleted != true else { return false }
        if record.origin.sourceSystem == "group" && !record.libraryId.hasPrefix("group:") { return false }
        let identity = identity ?? .shared
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
