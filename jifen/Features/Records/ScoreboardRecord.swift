//
//  ScoreboardRecord.swift
//  jifen
//
//  Scoreboard record data models
//

import Foundation
import RecordCore
import ScoreCore
import SessionCore

enum ScoreboardRecordStatus: String, Codable {
    case draft
    case abandoned
    case finished

    var isHistorical: Bool {
        self != .draft
    }
}

/// Stable winner identity for record schema v5.
///
/// `winner` remains in the payload as a legacy compatibility token. New code
/// must read this typed identity (or `resolvedWinnerIdentity`) so participant
/// names, localized labels, and screen placement never become identifiers.
enum ScoreboardWinnerIdentity: Codable, Equatable {
    case team(TeamID)
    case participant(index: Int)

    private enum Kind: String, Codable {
        case team
        case participant
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case teamID
        case participantIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .team:
            self = .team(try container.decode(TeamID.self, forKey: .teamID))
        case .participant:
            let index = try container.decode(Int.self, forKey: .participantIndex)
            guard index >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .participantIndex,
                    in: container,
                    debugDescription: "Winner participant index must be non-negative"
                )
            }
            self = .participant(index: index)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .team(let teamID):
            try container.encode(Kind.team, forKey: .kind)
            try container.encode(teamID, forKey: .teamID)
        case .participant(let index):
            try container.encode(Kind.participant, forKey: .kind)
            try container.encode(index, forKey: .participantIndex)
        }
    }

    var teamID: TeamID? {
        guard case .team(let teamID) = self else { return nil }
        return teamID
    }

    /// Canonical compatibility token written beside the typed schema-v5 value.
    /// Older clients can keep reading `winner` without depending on a localized
    /// participant name or the current screen placement.
    var legacyToken: String {
        switch self {
        case .team(let teamID): return teamID.rawValue
        case .participant(let index): return "player_\(index)"
        }
    }

    static func fromStableLegacyToken(_ token: String?) -> ScoreboardWinnerIdentity? {
        guard let raw = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return nil
        }
        if let teamID = TeamID.fromLegacyWinnerToken(raw) {
            return .team(teamID)
        }
        guard raw.hasPrefix("player_"),
              let index = Int(raw.dropFirst("player_".count)),
              index >= 0 else {
            return nil
        }
        return .participant(index: index)
    }

    var recordTeam: RecordTeam? {
        switch self {
        case .team(.team0), .participant(index: 0): return .team1
        case .team(.team1), .participant(index: 1): return .team2
        case .participant(index: 2): return .team3
        case .participant(index: 3): return .team4
        case .participant: return nil
        }
    }
}

// MARK: - Scoreboard Record

struct ScoreboardRecord: Codable, Identifiable {
    static let currentSchemaVersion = 5

    var schemaVersion: Int = Self.currentSchemaVersion
    let id: String
    let gameType: GameType
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval?
    let team1Name: String
    let team2Name: String
    var team1FinalScore: Int
    var team2FinalScore: Int
    var team1SetScore: Int?
    var team2SetScore: Int?
    /// Legacy compatibility token. Schema v5 uses `winnerIdentity` as the
    /// authoritative value; old names and left/right/red/blue tokens remain
    /// readable through `resolvedWinnerIdentity`.
    var winner: String?
    var winnerIdentity: ScoreboardWinnerIdentity?
    var winnerTeamID: TeamID? {
        get { resolvedWinnerIdentity?.teamID }
        set {
            winnerIdentity = newValue.map(ScoreboardWinnerIdentity.team)
            winner = winnerIdentity?.legacyToken
        }
    }
    var actions: [String] // Simplified action strings
    /// Schema v4 actions. `actions` is retained for old clients and recovery.
    var detailedActions: [DetailedScoreAction]?
    var setResults: [RecordSetResult]?
    var totalScoreChanges: Int
    var extraData: [String: AnyCodable]?
    var projectConfiguration: [String: AnyCodable]?
    var stateSnapshot: Data?
    var syncMetadata: [String: String]?
    /// Optional user-authored local annotation. It is deliberately outside
    /// the score snapshot so editing it never changes replay semantics.
    var note: String?
    /// 本地语音笔记（相对路径 + 时长），与安卓 ScoreboardRecordVoiceNote 对齐。
    var voiceNote: ScoreboardRecordVoiceNote?
    /// 结果纠错留痕：改比分前的原始分值。nil 表示从未纠错。
    var correction: RecordScoreCorrection?
    var status: ScoreboardRecordStatus = .finished
    
    enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case gameType
        case startTime
        case endTime
        case duration
        case team1Name
        case team2Name
        case team1FinalScore
        case team2FinalScore
        case team1SetScore
        case team2SetScore
        case winner
        case winnerIdentity
        case actions
        case detailedActions
        case setResults
        case totalScoreChanges
        case extraData
        case projectConfiguration
        case stateSnapshot
        case syncMetadata
        case note
        case voiceNote
        case correction
        case status
    }

    init(
        id: String,
        gameType: GameType,
        startTime: Date,
        endTime: Date? = nil,
        duration: TimeInterval? = nil,
        team1Name: String,
        team2Name: String,
        team1FinalScore: Int,
        team2FinalScore: Int,
        team1SetScore: Int? = nil,
        team2SetScore: Int? = nil,
        winner: String? = nil,
        winnerIdentity: ScoreboardWinnerIdentity? = nil,
        actions: [String] = [],
        detailedActions: [DetailedScoreAction]? = nil,
        setResults: [RecordSetResult]? = nil,
        totalScoreChanges: Int,
        extraData: [String: AnyCodable]? = nil,
        projectConfiguration: [String: AnyCodable]? = nil,
        stateSnapshot: Data? = nil,
        syncMetadata: [String: String]? = nil,
        note: String? = nil,
        voiceNote: ScoreboardRecordVoiceNote? = nil,
        correction: RecordScoreCorrection? = nil,
        status: ScoreboardRecordStatus = .finished
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.gameType = gameType
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.team1Name = team1Name
        self.team2Name = team2Name
        self.team1FinalScore = team1FinalScore
        self.team2FinalScore = team2FinalScore
        self.team1SetScore = team1SetScore
        self.team2SetScore = team2SetScore
        self.winnerIdentity = winnerIdentity
        self.winner = winner ?? winnerIdentity?.legacyToken
        self.actions = actions
        self.detailedActions = detailedActions
        self.setResults = setResults
        self.totalScoreChanges = totalScoreChanges
        self.extraData = extraData
        self.projectConfiguration = projectConfiguration
        self.stateSnapshot = stateSnapshot
        self.syncMetadata = syncMetadata
        self.note = note
        self.voiceNote = voiceNote
        self.correction = correction
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(String.self, forKey: .id)
        gameType = try container.decode(GameType.self, forKey: .gameType)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        team1Name = try container.decode(String.self, forKey: .team1Name)
        team2Name = try container.decode(String.self, forKey: .team2Name)
        team1FinalScore = try container.decode(Int.self, forKey: .team1FinalScore)
        team2FinalScore = try container.decode(Int.self, forKey: .team2FinalScore)
        team1SetScore = try container.decodeIfPresent(Int.self, forKey: .team1SetScore)
        team2SetScore = try container.decodeIfPresent(Int.self, forKey: .team2SetScore)
        let decodedWinner = try container.decodeIfPresent(String.self, forKey: .winner)
        let decodedWinnerIdentity = try container.decodeIfPresent(ScoreboardWinnerIdentity.self, forKey: .winnerIdentity)
        winnerIdentity = decodedWinnerIdentity
        winner = decodedWinner ?? decodedWinnerIdentity?.legacyToken
        actions = try container.decodeIfPresent([String].self, forKey: .actions) ?? []
        detailedActions = try container.decodeIfPresent([DetailedScoreAction].self, forKey: .detailedActions)
        setResults = try container.decodeIfPresent([RecordSetResult].self, forKey: .setResults)
        totalScoreChanges = try container.decode(Int.self, forKey: .totalScoreChanges)
        extraData = try container.decodeIfPresent([String: AnyCodable].self, forKey: .extraData)
        projectConfiguration = try container.decodeIfPresent([String: AnyCodable].self, forKey: .projectConfiguration)
        stateSnapshot = try container.decodeIfPresent(Data.self, forKey: .stateSnapshot)
        syncMetadata = try container.decodeIfPresent([String: String].self, forKey: .syncMetadata)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        voiceNote = try container.decodeIfPresent(ScoreboardRecordVoiceNote.self, forKey: .voiceNote)
        correction = try container.decodeIfPresent(RecordScoreCorrection.self, forKey: .correction)
        status = try container.decodeIfPresent(ScoreboardRecordStatus.self, forKey: .status) ?? .finished
    }
}

/// 结果纠错留痕：记录纠错前的原始比分，供详情页展示「原比分」与后续审计。
struct RecordScoreCorrection: Codable, Equatable {
    var correctedAt: Date
    var previousTeam1FinalScore: Int
    var previousTeam2FinalScore: Int
    var previousTeam1SetScore: Int?
    var previousTeam2SetScore: Int?
}

enum ScoreboardRecordCorrection {
    /// 结果纠错变换：修改最终比分/局分并按展示层级（局分优先，其次当局分，
    /// 平局无胜者）重算胜者。首次纠错把原始分值写入 `correction` 留痕；
    /// `stateSnapshot`、`detailedActions` 等回放语义字段保持原样。
    static func applied(
        to record: ScoreboardRecord,
        correctedAt: Date = Date(),
        team1FinalScore: Int,
        team2FinalScore: Int,
        team1SetScore: Int?,
        team2SetScore: Int?
    ) -> ScoreboardRecord {
        var corrected = record
        if corrected.correction == nil {
            corrected.correction = RecordScoreCorrection(
                correctedAt: correctedAt,
                previousTeam1FinalScore: record.team1FinalScore,
                previousTeam2FinalScore: record.team2FinalScore,
                previousTeam1SetScore: record.team1SetScore,
                previousTeam2SetScore: record.team2SetScore
            )
        }
        corrected.team1FinalScore = team1FinalScore
        corrected.team2FinalScore = team2FinalScore
        corrected.team1SetScore = team1SetScore
        corrected.team2SetScore = team2SetScore

        if let set1 = corrected.team1SetScore, let set2 = corrected.team2SetScore, set1 != set2 {
            corrected.winnerTeamID = set1 > set2 ? .team0 : .team1
        } else if team1FinalScore != team2FinalScore {
            corrected.winnerTeamID = team1FinalScore > team2FinalScore ? .team0 : .team1
        } else {
            corrected.winnerIdentity = nil
            corrected.winner = nil
        }
        return corrected
    }
}

/// 本地语音笔记元数据：只存相对路径与时长，音频文件由 ScoreboardRecordManager 管理。
struct ScoreboardRecordVoiceNote: Codable, Equatable {
    var relativePath: String
    var durationMs: Int
}

enum ScoreboardRecordVoiceNoteLimits {
    static let minimumDurationMs = 2_000
    static let maximumDurationMs = 60_000

    static func isDurationValid(_ durationMs: Int) -> Bool {
        durationMs >= minimumDurationMs && durationMs <= maximumDurationMs
    }
}

enum ScoreboardRecordNote {
    static let maximumUnicodeScalars = 300

    /// Trims whitespace first, then truncates only at Character boundaries.
    /// This preserves extended grapheme clusters such as emoji plus skin-tone
    /// modifiers and flags instead of splitting their scalar sequence.
    static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var result = ""
        var scalarCount = 0
        for character in trimmed {
            let nextCount = character.unicodeScalars.count
            guard scalarCount + nextCount <= maximumUnicodeScalars else { break }
            result.append(character)
            scalarCount += nextCount
        }
        return result.isEmpty ? nil : result
    }
}

/// Current-format state for scoreboards that do not yet use a `ScoreSession`
/// reducer. This is deliberately separate from `ScoreboardRecord`: resumable
/// state is not a history record and never enters the finished-record store.
struct ManualScoreboardResumeState: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let recordId: String
    let gameType: GameType
    let scoreCoreGameType: ScoreCore.GameType
    let startTime: Date
    let updatedAt: Date
    let team1Name: String
    let team2Name: String
    var team1FinalScore: Int
    var team2FinalScore: Int
    var team1SetScore: Int?
    var team2SetScore: Int?
    var winner: String?
    var winnerIdentity: ScoreboardWinnerIdentity?
    var actions: [String]
    var detailedActions: [DetailedScoreAction]?
    var setResults: [RecordSetResult]?
    var totalScoreChanges: Int
    var extraData: [String: AnyCodable]?
    var projectConfiguration: [String: AnyCodable]?
    var stateSnapshot: Data?

    var id: String { recordId }

    init(record: ScoreboardRecord, scoreCoreGameType: ScoreCore.GameType) {
        schemaVersion = Self.currentSchemaVersion
        recordId = record.id
        gameType = record.gameType
        self.scoreCoreGameType = scoreCoreGameType
        startTime = record.startTime
        updatedAt = record.endTime ?? Date()
        team1Name = record.team1Name
        team2Name = record.team2Name
        team1FinalScore = record.team1FinalScore
        team2FinalScore = record.team2FinalScore
        team1SetScore = record.team1SetScore
        team2SetScore = record.team2SetScore
        winner = record.winner
        winnerIdentity = record.winnerIdentity
        actions = record.actions
        detailedActions = record.detailedActions
        setResults = record.setResults
        totalScoreChanges = record.totalScoreChanges
        extraData = record.extraData
        projectConfiguration = record.projectConfiguration
        stateSnapshot = record.stateSnapshot
    }
}

// MARK: - Scoreboard Record Summary

struct ScoreboardRecordSummary: Codable, Identifiable, Equatable {
    let id: String
    let gameType: GameType
    let date: String // YYYY-MM-DD
    let time: String // HH:mm
    let timestamp: TimeInterval
    var duration: TimeInterval?
    let team1Name: String
    let team2Name: String
    let team1FinalScore: Int
    let team2FinalScore: Int
    var team1SetScore: Int?
    var team2SetScore: Int?
    var winner: String?
    var winnerIdentity: ScoreboardWinnerIdentity?
    var extraData: [String: AnyCodable]?
    var projectConfiguration: [String: AnyCodable]?
    /// Exact ScoreCore type for mode-aware labels and filters. App `GameType`
    /// intentionally keeps its historical family-level raw values.
    var scoreCoreGameTypeRawValue: String?
    
    // Convert from full record
    init(from record: ScoreboardRecord) {
        self.id = record.id
        self.gameType = record.gameType
        self.timestamp = record.startTime.timeIntervalSince1970
        
        // Format date（同年不显示年份，与 Watch、鸿蒙一致）
        let dateFormatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(record.startTime, equalTo: Date(), toGranularity: .year) {
            dateFormatter.dateFormat = "MM-dd"
        } else {
            dateFormatter.dateFormat = "yyyy-MM-dd"
        }
        self.date = dateFormatter.string(from: record.startTime)
        
        // Format time
        dateFormatter.dateFormat = "HH:mm"
        self.time = dateFormatter.string(from: record.startTime)
        
        self.duration = record.duration
        self.team1Name = record.team1Name
        self.team2Name = record.team2Name
        self.team1FinalScore = record.team1FinalScore
        self.team2FinalScore = record.team2FinalScore
        self.team1SetScore = record.team1SetScore
        self.team2SetScore = record.team2SetScore
        self.winner = record.winner
        self.winnerIdentity = record.winnerIdentity
        self.extraData = record.extraData
        self.projectConfiguration = record.projectConfiguration
        self.scoreCoreGameTypeRawValue = record.resolvedScoreCoreGameType?.rawValue
    }
    
    // Equatable conformance
    static func == (lhs: ScoreboardRecordSummary, rhs: ScoreboardRecordSummary) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Scoreboard Record Group

struct ScoreboardRecordGroup: Identifiable {
    let id: String
    let date: String
    let displayDate: String
    var records: [ScoreboardRecordSummary]
}

// MARK: - Multi-participant record display

struct ScoreboardRecordParticipant: Equatable {
    let name: String
    let score: Int
}

extension ScoreboardRecord {
    /// Standalone or linked finishes that originated on Apple Watch.
    var isSyncedFromWatch: Bool {
        if let syncFrom = extraData?["syncFrom"]?.value as? String, syncFrom == "watch" {
            return true
        }
        return false
    }

    var displayParticipants: [ScoreboardRecordParticipant] {
        scoreboardRecordParticipants(gameType: gameType, from: extraData)
    }

    /// Schema-v5 winner first, followed by lossless project state and finally
    /// legacy tokens/names. Ambiguous names intentionally resolve to nil.
    var resolvedWinnerIdentity: ScoreboardWinnerIdentity? {
        if let winnerIdentity { return winnerIdentity }

        switch gameType {
        case .guandan:
            let state = stateSnapshot.flatMap { data in
                (try? JSONDecoder().decode(GuandanResumeState.self, from: data))?.state
                    ?? ReducerScoreboardRecordPersistence.decodeSnapshot(data, as: GuandanMatchState.self)?.state
            }
            if let state,
               let winner = state.finalWinner {
                return .team(winner == .red ? .team0 : .team1)
            }
            // 跨端回退：安卓记录无 stateSnapshot blob，但 extraData 已摊平 guandanFinalWinner
            // （"red"/"blue"，与安卓 sideToRb 取值一致），据此恢复胜者身份。
            if let finalWinnerRaw = scoreboardString(mergedProjectConfiguration["guandanFinalWinner"]),
               finalWinnerRaw == "red" || finalWinnerRaw == "blue" {
                return .team(finalWinnerRaw == "red" ? .team0 : .team1)
            }
        case .shengji:
            if let stateSnapshot,
               let state = ReducerScoreboardRecordPersistence.decodeSnapshot(
                   stateSnapshot,
                   as: ShengjiTierState.self
               )?.state,
               let winner = state.winnerSide {
                return .team(winner == .left ? .team0 : .team1)
            }
        case .doudizhu:
            break
        default:
            break
        }

        if let stableIdentity = ScoreboardWinnerIdentity.fromStableLegacyToken(winner) {
            return stableIdentity
        }

        let participants = winnerResolutionParticipants
        if !participants.isEmpty {
            if let index = uniqueLeaderIndex(participants.map(\.score)) {
                return .participant(index: index)
            }
            if let rawWinner = normalizedLegacyWinner,
               let index = uniqueIndex(in: participants.map(\.name), matching: rawWinner) {
                return .participant(index: index)
            }
            return nil
        }

        guard let rawWinner = normalizedLegacyWinner else { return nil }
        if rawWinner == team1Name, rawWinner != team2Name { return .team(.team0) }
        if rawWinner == team2Name, rawWinner != team1Name { return .team(.team1) }
        return nil
    }

    var resolvedWinnerName: String? {
        switch resolvedWinnerIdentity {
        case .team(.team0): return team1Name
        case .team(.team1): return team2Name
        case .participant(let index):
            let participants = winnerResolutionParticipants
            return participants.indices.contains(index) ? participants[index].name : nil
        case nil:
            return nil
        }
    }

    var resolvedWinnerRecordTeam: RecordTeam? {
        resolvedWinnerIdentity?.recordTeam
    }

    private var normalizedLegacyWinner: String? {
        guard let value = winner?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var winnerResolutionParticipants: [ScoreboardRecordParticipant] {
        let participants = displayParticipants
        guard participants.isEmpty,
              gameType == .doudizhu,
              let stateSnapshot,
              let state = try? JSONDecoder().decode(DoudizhuResumeState.self, from: stateSnapshot) else {
            return participants
        }
        return state.names.indices.map { index in
            ScoreboardRecordParticipant(
                name: state.names[index],
                score: state.scores.indices.contains(index) ? state.scores[index] : 0
            )
        }
    }

    var mergedProjectConfiguration: [String: AnyCodable] {
        var result = extraData ?? [:]
        for (key, value) in projectConfiguration ?? [:] {
            result[key] = value
        }
        return result
    }

    var tennisSnapshotState: TennisMatchState? {
        guard gameType == .tennis, let stateSnapshot else { return nil }
        return Self.inferTennisState(from: stateSnapshot)
    }

    var tennisSetScoringMode: TennisSetScoringMode? {
        guard gameType == .tennis else { return nil }
        if let raw = scoreboardString(mergedProjectConfiguration["setScoringMode"]),
           let mode = TennisSetScoringMode(rawValue: raw) {
            return mode
        }
        return tennisSnapshotState?.rules.setScoringMode
    }

    var tennisTieBreakPoints: Int? {
        guard gameType == .tennis else { return nil }
        return scoreboardInt(mergedProjectConfiguration["tieBreakPoints"])
            ?? tennisSnapshotState?.rules.tieBreakPoints
    }

    var isTennisTiebreakOnly: Bool {
        tennisSetScoringMode == .tiebreakOnly
    }

    /// Tiebreak-only tennis has no games layer. Old records may still contain
    /// zero-valued set-score fields, but they must not be presented as Games.
    var shouldDisplaySecondaryScore: Bool {
        guard gameType != .football, gameType != .football5v5 else { return false }
        return !isTennisTiebreakOnly && team1SetScore != nil && team2SetScore != nil
    }

    /// 详情页与分享卡片的"大比分"优先展示局分（几局几胜）或盘分（网球几盘几胜）；
    /// 当记录没有局分结构（如台球/篮球/简单计分，或网球仅抢七）时退回小分/总分。
    /// 与 `shouldDisplaySecondaryScore` 共用同一判定，保证大比分与历史副标题语义一致。
    var primaryScore: (left: Int, right: Int, usesSetScore: Bool) {
        if shouldDisplaySecondaryScore,
           let leftSets = team1SetScore,
           let rightSets = team2SetScore {
            return (leftSets, rightSets, true)
        }
        return (team1FinalScore, team2FinalScore, false)
    }

    var resolvedScoreCoreGameType: ScoreCore.GameType? {
        let configuration = mergedProjectConfiguration
        if let raw = scoreboardString(configuration[ScoreboardRecordConfiguration.Key.scoreCoreGameType]),
           let type = ScoreCore.GameType(rawValue: raw) {
            return type
        }
        if let singles = scoreboardBool(configuration[ScoreboardRecordConfiguration.Key.isSingles]) {
            return gameType.scoreCoreGameType(isSingles: singles)
        }
        if let doubles = scoreboardBool(configuration["isDoubles"]) {
            return gameType.scoreCoreGameType(isSingles: !doubles)
        }
        if let stateSnapshot, let inferred = Self.inferScoreCoreGameType(from: stateSnapshot, family: gameType) {
            return inferred
        }
        return gameType.supportsSinglesAndDoubles ? nil : gameType.scoreCoreGameType
    }

    var competitionDisplayName: String {
        resolvedScoreCoreGameType?.scoreboardDisplayName ?? gameType.displayName
    }

    var configuredMatchTitle: String? {
        guard gameType == .snooker else { return nil }
        return ScoreboardMatchTitlePolicy.sanitize(
            scoreboardString(mergedProjectConfiguration["matchTitle"])
        )
    }

    var displayMatchTitle: String {
        if let configuredMatchTitle { return configuredMatchTitle }
        let names = displayParticipants.map(\.name)
        return names.isEmpty ? "\(team1Name) vs \(team2Name)" : names.joined(separator: " vs ")
    }

    func displayScore(separator: String = " : ") -> String {
        if let hierarchy = hierarchyScoreLine(separator: separator) {
            return hierarchy
        }
        return finalScoreLine(separator: separator)
    }

    /// Points-only line ("当局分"). Resume payloads keep this level because the
    /// user is resuming the game in progress, not the finished sets.
    func finalScoreLine(separator: String = " : ") -> String {
        let scores = displayParticipants.map { String($0.score) }
        return scores.isEmpty ? "\(team1FinalScore)\(separator)\(team2FinalScore)" : scores.joined(separator: separator)
    }

    /// Result display hierarchy aligned with Android `ScoreboardRecordDisplay`:
    /// 盘分/局分 first, falling back to 当局分 ("依次下降").
    func hierarchyScoreLine(separator: String = " : ") -> String? {
        ScoreboardRecordScoreHierarchy.line(
            gameType: gameType,
            team1SetScore: team1SetScore,
            team2SetScore: team2SetScore,
            team1FinalScore: team1FinalScore,
            team2FinalScore: team2FinalScore,
            isTennisTiebreakOnly: isTennisTiebreakOnly,
            separator: separator
        )
    }
}

extension ScoreboardRecordSummary {
    var isSyncedFromWatch: Bool {
        if let syncFrom = extraData?["syncFrom"]?.value as? String, syncFrom == "watch" {
            return true
        }
        return false
    }

    var displayParticipants: [ScoreboardRecordParticipant] {
        scoreboardRecordParticipants(gameType: gameType, from: extraData)
    }

    var resolvedWinnerIdentity: ScoreboardWinnerIdentity? {
        if let winnerIdentity { return winnerIdentity }
        let rawWinner = winner?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stableIdentity = ScoreboardWinnerIdentity.fromStableLegacyToken(rawWinner) {
            return stableIdentity
        }

        let participants = displayParticipants
        if !participants.isEmpty {
            if let index = uniqueLeaderIndex(participants.map(\.score)) {
                return .participant(index: index)
            }
            if let rawWinner, !rawWinner.isEmpty,
               let index = uniqueIndex(in: participants.map(\.name), matching: rawWinner) {
                return .participant(index: index)
            }
            return nil
        }

        guard let rawWinner, !rawWinner.isEmpty else { return nil }
        if rawWinner == team1Name, rawWinner != team2Name { return .team(.team0) }
        if rawWinner == team2Name, rawWinner != team1Name { return .team(.team1) }
        return nil
    }

    var resolvedWinnerName: String? {
        switch resolvedWinnerIdentity {
        case .team(.team0): return team1Name
        case .team(.team1): return team2Name
        case .participant(let index):
            let participants = displayParticipants
            return participants.indices.contains(index) ? participants[index].name : nil
        case nil:
            return nil
        }
    }

    var mergedProjectConfiguration: [String: AnyCodable] {
        var result = extraData ?? [:]
        for (key, value) in projectConfiguration ?? [:] {
            result[key] = value
        }
        return result
    }

    var resolvedScoreCoreGameType: ScoreCore.GameType? {
        let configuration = mergedProjectConfiguration
        if let scoreCoreGameTypeRawValue,
           let type = ScoreCore.GameType(rawValue: scoreCoreGameTypeRawValue) {
            return type
        }
        if let raw = scoreboardString(configuration[ScoreboardRecordConfiguration.Key.scoreCoreGameType]),
           let type = ScoreCore.GameType(rawValue: raw) {
            return type
        }
        if let singles = scoreboardBool(configuration[ScoreboardRecordConfiguration.Key.isSingles]) {
            return gameType.scoreCoreGameType(isSingles: singles)
        }
        if let doubles = scoreboardBool(configuration["isDoubles"]) {
            return gameType.scoreCoreGameType(isSingles: !doubles)
        }
        return gameType.supportsSinglesAndDoubles ? nil : gameType.scoreCoreGameType
    }

    var competitionDisplayName: String {
        resolvedScoreCoreGameType?.scoreboardDisplayName ?? gameType.displayName
    }

    var configuredMatchTitle: String? {
        guard gameType == .snooker else { return nil }
        return ScoreboardMatchTitlePolicy.sanitize(
            scoreboardString(mergedProjectConfiguration["matchTitle"])
        )
    }

    var displayMatchTitle: String {
        if let configuredMatchTitle { return configuredMatchTitle }
        let names = displayParticipants.map(\.name)
        return names.isEmpty ? "\(team1Name) vs \(team2Name)" : names.joined(separator: " vs ")
    }

    func displayScore(separator: String = " : ") -> String {
        if let left = team1SetScore, let right = team2SetScore,
           let hierarchy = ScoreboardRecordScoreHierarchy.line(
               gameType: gameType,
               team1SetScore: left,
               team2SetScore: right,
               team1FinalScore: team1FinalScore,
               team2FinalScore: team2FinalScore,
               isTennisTiebreakOnly: scoreboardString(mergedProjectConfiguration["setScoringMode"]) == TennisSetScoringMode.tiebreakOnly.rawValue,
               separator: separator
           ) {
            return hierarchy
        }
        let scores = displayParticipants.map { String($0.score) }
        return scores.isEmpty ? "\(team1FinalScore)\(separator)\(team2FinalScore)" : scores.joined(separator: separator)
    }
}

/// Shared result-score hierarchy, mirrored from Android
/// `helpers/ScoreboardRecordDisplay.kt`: racket/volley families show the
/// 盘分/局分 level when it is populated, otherwise fall back to 当局分.
enum ScoreboardRecordScoreHierarchy {
    static func prefersSetScore(_ gameType: GameType) -> Bool {
        switch gameType {
        case .badminton, .shuttlecock, .squash, .padel,
             .pingpong, .volleyball, .airVolleyball, .beachVolleyball,
             .tennis, .pickleball, .foosball:
            return true
        default:
            return false
        }
    }

    static func line(
        gameType: GameType,
        team1SetScore: Int?,
        team2SetScore: Int?,
        team1FinalScore: Int,
        team2FinalScore: Int,
        isTennisTiebreakOnly: Bool,
        separator: String
    ) -> String? {
        guard prefersSetScore(gameType), !isTennisTiebreakOnly,
              let left = team1SetScore, let right = team2SetScore else { return nil }
        guard left + right > 0 || team1FinalScore + team2FinalScore == 0 else { return nil }
        return "\(left)\(separator)\(right)"
    }
}

enum ScoreboardRecordConfiguration {
    enum Key {
        static let scoreCoreGameType = "scoreCoreGameType"
        static let isSingles = "isSingles"
    }

    static func rally(
        gameType: ScoreCore.GameType,
        state: RallyMatchState,
        voiceAnnouncement: Bool,
        showMatchTime: Bool = false,
        competitionFormat: CompetitionFormat? = nil,
        competitionPlayerNames: [String]? = nil
    ) -> [String: AnyCodable] {
        let rules = state.rules
        var result: [String: AnyCodable] = [
            Key.scoreCoreGameType: AnyCodable(gameType.rawValue),
            Key.isSingles: AnyCodable(!gameType.isDoublesScoreboard),
            "maxSets": AnyCodable(rules.maxSets),
            "matchCompletionMode": AnyCodable(rules.matchCompletionMode.rawValue),
            "pointsPerSet": AnyCodable(rules.pointsToWinSet),
            "autoChangeSides": AnyCodable(rules.autoChangeSides),
            "servingSide": AnyCodable(state.openingServerSide.rawValue),
            "voiceAnnouncementEnabled": AnyCodable(voiceAnnouncement),
            "showMatchTime": AnyCodable(showMatchTime),
            "targetScore": AnyCodable(rules.pointsToWinSet),
            "winByTwo": AnyCodable(rules.finalSetWinByTwo ?? rules.winByTwo),
            "useRallyScoring": AnyCodable(rules.useRallyScoring)
        ]
        result["ruleProfileVersion"] = AnyCodable(1)
        let resolvedFormat = competitionFormat ?? {
            if gameType == .shuttlecock {
                return state.doubles == nil ? CompetitionFormat.team : .doubles
            }
            return gameType.isDoublesScoreboard ? .doubles : .singles
        }()
        result["competitionFormat"] = AnyCodable(resolvedFormat.rawValue)
        if let cap = rules.finalSetPointCap ?? rules.pointCap {
            result["scoreCap"] = AnyCodable(cap)
        }
        if let names = state.doubles?.playerNames, names.count >= 4 {
            result["team1Player1Name"] = AnyCodable(names[0])
            result["team2Player1Name"] = AnyCodable(names[1])
            result["team1Player2Name"] = AnyCodable(names[2])
            result["team2Player2Name"] = AnyCodable(names[3])
        }
        if let names = competitionPlayerNames, names.count >= 6 {
            result["team1Player1Name"] = AnyCodable(names[0])
            result["team1Player2Name"] = AnyCodable(names[1])
            result["team1Player3Name"] = AnyCodable(names[2])
            result["team2Player1Name"] = AnyCodable(names[3])
            result["team2Player2Name"] = AnyCodable(names[4])
            result["team2Player3Name"] = AnyCodable(names[5])
        }
        return result
    }

    static func tennis(
        gameType: ScoreCore.GameType,
        state: TennisMatchState,
        voiceAnnouncement: Bool
    ) -> [String: AnyCodable] {
        let rules = state.rules
        var result: [String: AnyCodable] = [
            Key.scoreCoreGameType: AnyCodable(gameType.rawValue),
            Key.isSingles: AnyCodable(state.doublesPlayerNames == nil),
            "maxSets": AnyCodable(rules.maxSets),
            "matchCompletionMode": AnyCodable(rules.matchCompletionMode.rawValue),
            "tieBreakPoints": AnyCodable(rules.tieBreakPoints),
            "setScoringMode": AnyCodable(rules.setScoringMode.rawValue),
            "autoChangeSides": AnyCodable(rules.autoChangeSides),
            "tennisDeuceMode": AnyCodable(
                rules.familyProfile == .padel
                    ? rules.padelDeuceMode.rawValue
                    : (rules.usesNoAdScoring ? "no_ad" : "advantage")
            ),
            "ruleProfileVersion": AnyCodable(1),
            "servingSide": AnyCodable(state.openingServerSide.rawValue),
            "voiceAnnouncementEnabled": AnyCodable(voiceAnnouncement)
        ]
        if rules.setScoringMode != .tiebreakOnly {
            result["gamesPerSet"] = AnyCodable(rules.gamesPerSet)
        }
        if rules.familyProfile == .softTennis {
            result["softTennisMatchGames"] = AnyCodable(rules.softTennisMatchGames ?? 7)
        }
        result["competitionFormat"] = AnyCodable(
            state.doublesPlayerNames == nil ? CompetitionFormat.singles.rawValue : CompetitionFormat.doubles.rawValue
        )
        if let names = state.doublesPlayerNames, names.count >= 4 {
            result["team1Player1Name"] = AnyCodable(names[0])
            result["team2Player1Name"] = AnyCodable(names[1])
            result["team1Player2Name"] = AnyCodable(names[2])
            result["team2Player2Name"] = AnyCodable(names[3])
        }
        return result
    }

    static func setup(from record: ScoreboardRecord) -> SportsSetupResult {
        let data = record.mergedProjectConfiguration
        var setup = SportsSetupResult(team1Name: record.team1Name, team2Name: record.team2Name)
        let tennisState = record.tennisSnapshotState
        setup.maxSets = scoreboardInt(data["maxSets"]) ?? tennisState?.rules.maxSets
        setup.pointsPerSet = scoreboardInt(data["pointsPerSet"] ?? data["targetScore"])
        setup.tieBreakPoints = scoreboardInt(data["tieBreakPoints"])
            ?? tennisState?.rules.tieBreakPoints
        setup.gamesPerSet = scoreboardInt(data["gamesPerSet"])
            ?? (tennisState?.rules.setScoringMode == .regular ? tennisState?.rules.gamesPerSet : nil)
        setup.setScoringMode = scoreboardString(data["setScoringMode"])
            ?? tennisState?.rules.setScoringMode.rawValue
        if let completion = scoreboardString(data["matchCompletionMode"]) {
            setup.matchCompletionMode = MatchCompletionMode(rawValue: completion)
        } else if let completion = tennisState?.rules.matchCompletionMode {
            setup.matchCompletionMode = completion
        }
        setup.autoChangeSides = scoreboardBool(data["autoChangeSides"])
            ?? tennisState?.rules.autoChangeSides
        setup.isSingles = scoreboardBool(data[Key.isSingles])
        if setup.isSingles == nil, let doubles = scoreboardBool(data["isDoubles"]) {
            setup.isSingles = !doubles
        }
        if setup.isSingles == nil, let type = record.resolvedScoreCoreGameType {
            setup.isSingles = !type.isDoublesScoreboard
        }
        setup.team1Player1Name = scoreboardString(data["team1Player1Name"])
        setup.team1Player2Name = scoreboardString(data["team1Player2Name"])
        setup.team2Player1Name = scoreboardString(data["team2Player1Name"])
        setup.team2Player2Name = scoreboardString(data["team2Player2Name"])
        setup.team1Player3Name = scoreboardString(data["team1Player3Name"])
        setup.team2Player3Name = scoreboardString(data["team2Player3Name"])
        setup.basketballMode = scoreboardString(data["basketballMode"])
        setup.basketballRuleSet = scoreboardString(data["basketballRuleSet"])
        setup.tennisDeuceMode = scoreboardString(data["tennisDeuceMode"])
            ?? tennisState.map { $0.rules.usesNoAdScoring ? "no_ad" : "advantage" }
        setup.servingSide = scoreboardString(data["servingSide"])
            ?? tennisState?.openingServerSide.rawValue
        setup.voiceAnnouncement = scoreboardBool(data["voiceAnnouncementEnabled"]) ?? scoreboardBool(data["voiceAnnouncement"])
        setup.targetScore = scoreboardInt(data["targetScore"] ?? data["unoTargetScore"])
        setup.winByTwo = scoreboardBool(data["winByTwo"])
        setup.scoreCap = scoreboardInt(data["scoreCap"])
        setup.useRallyScoring = scoreboardBool(data["useRallyScoring"])
        if let raw = scoreboardString(data["competitionFormat"]) {
            setup.competitionFormat = CompetitionFormat(rawValue: raw)
        }
        setup.softTennisMatchGames = scoreboardInt(data["softTennisMatchGames"])
        if let raw = scoreboardString(data["padelDeuceMode"] ?? data["tennisDeuceMode"]) {
            setup.padelDeuceMode = PadelDeuceMode(rawValue: raw)
        }
        setup.ruleProfileVersion = scoreboardInt(data["ruleProfileVersion"])
        setup.footballHalfLengthSeconds = scoreboardInt(data["footballHalfLengthSeconds"])
        setup.showMatchTime = scoreboardBool(data["showMatchTime"])
        setup.matchTitle = ScoreboardMatchTitlePolicy.sanitize(scoreboardString(data["matchTitle"]))
        setup.maxRounds = scoreboardInt(data["maxRounds"])
        setup.eightBallHandicapRacks = scoreboardInt(data["eightBallHandicapRacks"])
        setup.eightBallHandicapBeneficiary = scoreboardString(data["eightBallHandicapBeneficiary"])
        setup.multiScoreCustomAdjustEnabled = scoreboardBool(data["multiScoreCustomAdjustEnabled"])
        setup.guandanTripleA = scoreboardBool(data["guandanTripleAEnabled"]) ?? scoreboardBool(data["guandanTripleA"])
        setup.guandanPassACondition = scoreboardString(data["guandanPassACondition"])
        setup.guandanTripleAFallbackRank = scoreboardString(data["guandanTripleAFallbackRank"])
        setup.playerNames = record.displayParticipants.map(\.name)
        setup.playerCount = setup.playerNames?.isEmpty == false ? setup.playerNames?.count : scoreboardInt(data["playerCount"])
        setup.nineBallBigGold = scoreboardInt(data["nineBallBigGold"])
        setup.nineBallSmallGold = scoreboardInt(data["nineBallSmallGold"])
        setup.nineBallGoldenNine = scoreboardInt(data["nineBallGoldenNine"])
        setup.nineBallNormalWin = scoreboardInt(data["nineBallNormalWin"])
        setup.nineBallBallInHand = scoreboardInt(data["nineBallBallInHand"])
        setup.nineBallFoul = scoreboardInt(data["nineBallFoul"])
        return setup
    }
}

extension GameType {
    var supportsSinglesAndDoubles: Bool {
        switch self {
        case .pingpong, .badminton, .tennis, .pickleball, .foosball, .softTennis, .padel, .shuttlecock: return true
        default: return false
        }
    }

    func scoreCoreGameType(isSingles: Bool) -> ScoreCore.GameType? {
        switch self {
        case .pingpong: return isSingles ? .pingpong : .pingpongDoubles
        case .badminton: return isSingles ? .badminton : .badmintonDoubles
        case .tennis: return isSingles ? .tennis : .tennisDoubles
        case .pickleball: return isSingles ? .pickleball : .pickleballDoubles
        case .foosball: return isSingles ? .foosball : .foosballDoubles
        case .shuttlecock: return .shuttlecock
        case .squash: return .squash
        case .softTennis: return .softTennis
        case .padel: return .padel
        case .football5v5: return .football5v5
        default: return scoreCoreGameType
        }
    }
}

extension ScoreCore.GameType {
    var isDoublesScoreboard: Bool {
        switch self {
        case .pingpongDoubles, .badmintonDoubles, .tennisDoubles, .pickleballDoubles, .foosballDoubles:
            return true
        default:
            return false
        }
    }

    var scoreboardDisplayName: String {
        switch self {
        case .pingpong: return NSLocalizedString("game_pingpong_singles", value: "乒乓球单打", comment: "")
        case .pingpongDoubles: return NSLocalizedString("game_pingpong_doubles", value: "乒乓球双打", comment: "")
        case .badminton: return NSLocalizedString("game_badminton_singles", value: "羽毛球单打", comment: "")
        case .badmintonDoubles: return NSLocalizedString("game_badminton_doubles", value: "羽毛球双打", comment: "")
        case .tennis: return NSLocalizedString("game_tennis_singles", value: "网球单打", comment: "")
        case .tennisDoubles: return NSLocalizedString("game_tennis_doubles", value: "网球双打", comment: "")
        case .pickleball: return NSLocalizedString("game_pickleball_singles", value: "匹克球单打", comment: "")
        case .pickleballDoubles: return NSLocalizedString("game_pickleball_doubles", value: "匹克球双打", comment: "")
        case .foosball: return NSLocalizedString("game_foosball_singles", value: "桌上足球单打", comment: "")
        case .foosballDoubles: return NSLocalizedString("game_foosball_doubles", value: "桌上足球双打", comment: "")
        case .shuttlecock: return NSLocalizedString("game_shuttlecock", value: "毽球", comment: "")
        case .squash: return NSLocalizedString("game_squash", value: "壁球", comment: "")
        case .softTennis: return NSLocalizedString("game_soft_tennis", value: "软式网球", comment: "")
        case .padel: return NSLocalizedString("game_padel", value: "板网球", comment: "")
        case .football5v5: return NSLocalizedString("game_football_5v5", value: "5×5 足球", comment: "")
        default: return scoreboardAppGameType(for: self)?.displayName ?? rawValue
        }
    }
}

private extension ScoreboardRecord {
    static func inferTennisState(from data: Data) -> TennisMatchState? {
        if let bundle = try? JSONDecoder().decode(
            ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self,
            from: data
        ) {
            return bundle.currentSession.state
        }
        if let session = try? JSONDecoder().decode(
            ScoreSession<TennisMatchState, TennisMatchEvent>.self,
            from: data
        ) {
            return session.state
        }
        return nil
    }

    static func inferScoreCoreGameType(from data: Data, family: GameType) -> ScoreCore.GameType? {
        if family == .tennis {
            if let bundle = try? JSONDecoder().decode(
                ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self,
                from: data
            ) {
                return bundle.currentSession.gameType
            }
            if let session = try? JSONDecoder().decode(ScoreSession<TennisMatchState, TennisMatchEvent>.self, from: data) {
                return session.gameType
            }
        }
        if [.pingpong, .badminton, .pickleball, .foosball].contains(family) {
            if let bundle = try? JSONDecoder().decode(
                ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self,
                from: data
            ) {
                return bundle.currentSession.gameType
            }
            if let session = try? JSONDecoder().decode(ScoreSession<RallyMatchState, RallyMatchEvent>.self, from: data) {
                return session.gameType
            }
        }
        return nil
    }
}

private func scoreboardString(_ value: AnyCodable?) -> String? {
    value?.value as? String
}

func scoreboardBool(_ value: AnyCodable?) -> Bool? {
    if let bool = value?.value as? Bool { return bool }
    if let int = value?.value as? Int { return int != 0 }
    if let string = value?.value as? String { return (string as NSString).boolValue }
    return nil
}

private func uniqueIndex(in values: [String], matching target: String) -> Int? {
    let matches = values.indices.filter { values[$0] == target }
    return matches.count == 1 ? matches[0] : nil
}

private func uniqueLeaderIndex(_ scores: [Int]) -> Int? {
    guard let best = scores.max() else { return nil }
    let leaders = scores.indices.filter { scores[$0] == best }
    return leaders.count == 1 ? leaders[0] : nil
}

private func scoreboardInt(_ value: AnyCodable?) -> Int? {
    if let int = value?.value as? Int { return int }
    if let double = value?.value as? Double { return Int(double) }
    if let string = value?.value as? String { return Int(string) }
    return nil
}

private func scoreboardAppGameType(for type: ScoreCore.GameType) -> GameType? {
    GameType(scoreCoreGameType: type)
}

private func scoreboardRecordParticipants(gameType: GameType, from extraData: [String: AnyCodable]?) -> [ScoreboardRecordParticipant] {
    guard gameType == .multiScoreboard || gameType == .uno || gameType == .doudizhu || gameType == .nineBall else {
        return []
    }
    guard let rawPlayers = extraData?["players"]?.value else { return [] }
    let values: [Any]
    if let array = rawPlayers as? [Any] {
        values = array
    } else if let array = rawPlayers as? [AnyCodable] {
        values = array.map(\.value)
    } else {
        return []
    }

    return values.compactMap { raw in
        let value = (raw as? AnyCodable)?.value ?? raw
        let dictionary: [String: Any]
        if let decoded = value as? [String: Any] {
            dictionary = decoded
        } else if let wrapped = value as? [String: AnyCodable] {
            dictionary = wrapped.mapValues(\.value)
        } else {
            return nil
        }
        guard let name = dictionary["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let rawScore = dictionary["finalScore"] ?? dictionary["score"] ?? 0
        let score: Int
        if let int = rawScore as? Int { score = int }
        else if let double = rawScore as? Double { score = Int(double) }
        else if let string = rawScore as? String { score = Int(string) ?? 0 }
        else if let wrapped = rawScore as? AnyCodable, let int = wrapped.value as? Int { score = int }
        else { score = 0 }
        return ScoreboardRecordParticipant(name: name, score: score)
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let wrapped as AnyCodable:
            try container.encode(wrapped)
        case let array as [AnyCodable]:
            try container.encode(array)
        case let dictionary as [String: AnyCodable]:
            try container.encode(dictionary)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}
