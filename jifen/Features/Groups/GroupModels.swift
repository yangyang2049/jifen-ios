import Foundation
import ScoreCore

nonisolated enum GroupSport: String, Codable, CaseIterable, Identifiable, Sendable {
    case badminton, tableTennis = "table_tennis", tennis, pickleball
    var id: String { rawValue }
    var gameType: GameType { switch self { case .badminton: .badminton; case .tableTennis: .pingpong; case .tennis: .tennis; case .pickleball: .pickleball } }
    @MainActor var title: String { gameType.displayName }
}
nonisolated enum GroupFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case singles, doubles
    var id: String { rawValue }
    var seatsPerSide: Int { self == .singles ? 1 : 2 }
    var title: String { groupText(rawValue, self == .singles ? "Singles" : "Doubles") }
}
nonisolated func groupText(_ key: String, _ fallback: String) -> String { NSLocalizedString("group_" + key, value: fallback, comment: "Groups") }

nonisolated struct ScoreGroup: Codable, Identifiable, Sendable, Hashable {
    var id: String; var groupNo: String; var name: String; var description: String; var sport: GroupSport
    var status: String; var joinPolicy: String; var ownerMemberId: String; var memberLimit: Int
    var createdAt: Int64; var updatedAt: Int64; var revision: Int64
    var memberCount: Int?; var myRole: String?; var currentMonthMatchCount: Int?; var activeMemberCount30d: Int?
    var groupType: String? = nil
    var isCoach: Bool? = nil
    var dissolveAt: Int64? = nil
    var pendingName: String? = nil
    var pendingDescription: String? = nil
    var nameModerationStatus: String? = nil
    var descriptionModerationStatus: String? = nil
    var nameModerationReviewReason: String? = nil
    var descriptionModerationReviewReason: String? = nil
    var isActive: Bool { status == "active" }
    var isCoaching: Bool { groupType == "coaching" }
}
nonisolated struct GroupMember: Codable, Identifiable, Sendable, Equatable {
    var id: String; var groupId: String; var kind: String; var role: String; var status: String
    var displayName: String; var accountId: String; var joinedAt: Int64
    var avatarUrl: String? = nil
    var isVip: Bool? = nil
    var removedAt: Int64? = nil
    var pendingDisplayName: String? = nil
    var displayNameModerationStatus: String? = nil
    var displayNameModerationReviewReason: String? = nil
    var groupRevision: Int64? = nil
}
nonisolated struct GroupJoinRequest: Codable, Identifiable, Sendable {
    var id: String; var groupId: String; var groupNo: String; var groupName: String; var sport: GroupSport
    var accountId: String; var displayName: String; var status: String; var message: String; var createdAt: Int64; var decidedAt: Int64?
    var avatarUrl: String? = nil
    var groupAvailability: String? = nil
    var joinPolicy: String? = nil
}
nonisolated struct GroupPreview: Codable, Sendable {
    var groupNo: String; var name: String; var description: String; var sport: GroupSport?
    var memberCount: Int; var joinPolicy: String; var availability: String
    var groupType: String? = nil
    var groupId: String? = nil
    var status: String? = nil
    var memberLimit: Int? = nil
    var requestId: String? = nil
    var requestStatus: String? = nil

    // 查无此组时服务端返回 availability=not_found 且 sport/joinPolicy 为空串，合成解码会因枚举无空 case 抛错
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupNo = try c.decodeIfPresent(String.self, forKey: .groupNo) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        sport = GroupSport(rawValue: try c.decodeIfPresent(String.self, forKey: .sport) ?? "")
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        joinPolicy = try c.decodeIfPresent(String.self, forKey: .joinPolicy) ?? ""
        availability = try c.decodeIfPresent(String.self, forKey: .availability) ?? ""
        groupType = try c.decodeIfPresent(String.self, forKey: .groupType)
        groupId = try c.decodeIfPresent(String.self, forKey: .groupId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        memberLimit = try c.decodeIfPresent(Int.self, forKey: .memberLimit)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
        requestStatus = try c.decodeIfPresent(String.self, forKey: .requestStatus)
    }
}
nonisolated struct GroupActivity: Codable, Identifiable, Sendable {
    var id: String; var groupId: String; var title: String; var startsAt: Int64; var place: String; var capacity: Int
    var note: String; var format: GroupFormat; var status: String; var creatorMemberId: String
    var registeredMemberIds: [String]; var gameId: String; var createdAt: Int64; var revision: Int64
    var matchMode: String? = nil
    var activityType: String? = nil
    var timingMode: String? = nil
    var registrationClosesAt: Int64? = nil
    var sessionCount: Int? = nil
    var completedSessionCount: Int? = nil
    var startedGameCount: Int? = nil
    var pendingTitle: String? = nil
    var titleModerationStatus: String? = nil
    var titleModerationReviewReason: String? = nil
    var isMulti: Bool { matchMode == "multi" }
    /// 直接排赛（无需报名，直接从在组成员选人）；服务端缺省即 signup。
    var isDirect: Bool { activityType == "direct" }
    /// 排赛时间模式：`sequence` 按顺序（时间待定/接上一场）、`estimated` 预计时间。
    var isSequenced: Bool { timingMode == "sequence" }
    var canCancel: Bool { status == "recruiting" && gameId.isEmpty && (startedGameCount ?? 0) == 0 }
    func canEdit(at now: Int64) -> Bool { status == "recruiting" && startsAt > now && gameId.isEmpty && (completedSessionCount ?? 0) == 0 && (startedGameCount ?? 0) == 0 }
    func registrationOpen(at now: Int64) -> Bool { ["recruiting", "in_progress"].contains(status) && (registrationClosesAt ?? startsAt) > now }
    var registrationOpen: Bool { registrationOpen(at: Int64(Date().timeIntervalSince1970 * 1000)) }
    var date: Date { Date(timeIntervalSince1970: Double(startsAt) / 1000) }
}
nonisolated struct GroupSeat: Codable, Sendable, Equatable {
    var memberId: String; var side: String; var seat: Int; var displayName: String? = nil
}
nonisolated struct GroupScore: Codable, Sendable, Equatable { var a: Int; var b: Int }
nonisolated struct GroupResult: Codable, Identifiable, Sendable {
    var id: String; var groupId: String; var activityId: String; var gameId: String; var format: GroupFormat; var sport: GroupSport
    var bestOf: Int?; var setScore: GroupScore; var sets: [GroupScore]?; var winnerSide: String?; var outcome: String?
    var rules: GroupMatchRules?; var participants: [GroupSeat]; var playedAt: Int64
    var submitterMemberId: String; var confirmedByMemberId: String; var status: String; var source: String; var reason: String
    var createdAt: Int64; var revision: Int64
    var activitySessionId: String? = nil
    var confirmationMode: String? = nil
    var canAuthorityConfirm: Bool? = nil
    var date: Date { Date(timeIntervalSince1970: Double(playedAt) / 1000) }
}
nonisolated struct GroupRanking: Codable, Identifiable, Sendable {
    var memberId: String; var displayName: String; var games: Int; var wins: Int; var losses: Int; var draws: Int?
    var setsWon: Int; var setsLost: Int; var winRateText: String; var rank: Int
    var id: String { memberId }
}
nonisolated struct GroupStats: Codable, Sendable { var confirmedMatchCount: Int; var currentMonthMatchCount: Int; var activeMemberCount30d: Int; var lastCompletedAt: Int64 }
nonisolated struct GroupPage<Item: Codable & Sendable>: Codable, Sendable { var items: [Item]; var nextCursor: String? }
nonisolated struct GroupJoinOutcome: Decodable, Sendable { var kind: String; var groupId: String?; var requestId: String? }
nonisolated struct GroupGameSnapshot: Decodable, Sendable { var gameId: String; var groupId: String; var activityId: String; var clientSessionId: String; var format: GroupFormat; var state: String; var rules: GroupMatchRules?; var participants: [GroupSeat]?; var trainingSessionId: String? = nil; var activitySessionId: String? = nil; var creatorMemberId: String? = nil }
nonisolated extension GroupGameSnapshot {
    func hasValidFrozenConfiguration(groupID: String, gameID: String, sport: GroupSport) -> Bool {
        guard groupId == groupID, gameId == gameID,
              let rules, rules.isValid, rules.sport == sport,
              let participants, participants.count == format.seatsPerSide * 2,
              Set(participants.map(\.memberId)).count == participants.count else { return false }
        let expected = Set(["A", "B"].flatMap { side in
            (0..<format.seatsPerSide).map { "\(side):\($0)" }
        })
        guard participants.allSatisfy({ !$0.memberId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
        return Set(participants.map { "\($0.side):\($0.seat)" }) == expected
    }
}
nonisolated struct GroupGameResponse: Decodable, Sendable { var gameId: String; var clientSessionId: String }
nonisolated struct GroupCapabilities: Codable, Sendable {
    var groupNoLength: Int; var nameMin: Int; var nameMax: Int; var descriptionMax: Int
    var memberLimitDefault: Int; var memberLimitMax: Int; var ruleSchemaVersion: Int?; var supportsDraws: Bool?
    var sports: [GroupSportCapability]? = nil
    var groupTypes: [String]? = nil
    var allowedActions: [String]? = nil
    var minClientContractVersion: Int? = nil
    var supportsActivityLineup: Bool? = nil
    var activitySessionMax: Int? = nil
    var activityMemberSessionMax: Int? = nil
    var trainingSessionMax: Int? = nil
    var trainingMemberSessionMax: Int? = nil
    func allows(_ action: String) -> Bool { (minClientContractVersion ?? 1) <= 1 && (allowedActions?.contains(action) ?? true) }
    func sport(_ sport: GroupSport) -> GroupSportCapability? { guard (minClientContractVersion ?? 1) <= 1, (ruleSchemaVersion ?? 1) == 1 else { return nil }; return sports?.first { $0.sport == sport } }
}

nonisolated struct GroupMatchRules: Codable, Hashable, Sendable {
    var version = 1
    var sport: GroupSport
    var maxSets: Int
    var matchCompletionMode: String
    var pointsToWinSet: Int
    var pointCap: Int?
    var winByTwo: Bool
    var useRallyScoring: Bool
    var gamesPerSet: Int
    var tieBreakPoints: Int
    var setScoringMode: String
    var usesNoAdScoring: Bool

    private enum CodingKeys: String, CodingKey {
        case version, sport, maxSets, matchCompletionMode, pointsToWinSet, pointCap, winByTwo, useRallyScoring, gamesPerSet, tieBreakPoints, setScoringMode, usesNoAdScoring
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version); try c.encode(sport, forKey: .sport)
        try c.encode(maxSets, forKey: .maxSets); try c.encode(matchCompletionMode, forKey: .matchCompletionMode)
        try c.encode(pointsToWinSet, forKey: .pointsToWinSet); try c.encode(pointCap, forKey: .pointCap)
        try c.encode(winByTwo, forKey: .winByTwo); try c.encode(useRallyScoring, forKey: .useRallyScoring)
        try c.encode(gamesPerSet, forKey: .gamesPerSet); try c.encode(tieBreakPoints, forKey: .tieBreakPoints)
        try c.encode(setScoringMode, forKey: .setScoringMode); try c.encode(usesNoAdScoring, forKey: .usesNoAdScoring)
    }

    var isValid: Bool {
        version == 1 && (1...99).contains(maxSets) && (1...999).contains(pointsToWinSet)
        && ["best_of", "play_all"].contains(matchCompletionMode)
        && (matchCompletionMode == "play_all" || maxSets % 2 == 1)
        && (pointCap == nil || (pointCap! >= pointsToWinSet && pointCap! <= 9999))
        && [4, 6].contains(gamesPerSet) && [7, 10].contains(tieBreakPoints)
        && ["regular", "tiebreak_only"].contains(setScoringMode)
        && (sport != .tennis || setScoringMode != "tiebreak_only" || (maxSets == 1 && matchCompletionMode == "best_of"))
    }
    func terminalSet(_ score: GroupScore) -> Bool {
        let high = max(score.a, score.b), low = min(score.a, score.b)
        guard low >= 0, high != low else { return false }
        if sport == .tennis && setScoringMode == "regular" {
            return (high == gamesPerSet && low <= gamesPerSet - 2) || (high == gamesPerSet + 1 && (low == gamesPerSet - 1 || low == gamesPerSet))
        }
        let target = sport == .tennis ? tieBreakPoints : pointsToWinSet
        let cap = sport == .tennis ? nil : pointCap
        let two = sport == .tennis || winByTwo
        if high < target || (cap != nil && high > cap!) { return false }
        func ended(_ h: Int) -> Bool { (cap != nil && h >= cap!) || (h >= target && (!two || h - low >= 2)) }
        return ended(high) && !ended(high - 1)
    }
    func validResult(_ score: GroupScore, sets: [GroupScore]?) -> Bool {
        guard isValid, score.a >= 0, score.b >= 0 else { return false }
        let need = maxSets / 2 + 1
        if matchCompletionMode == "play_all" {
            guard score.a + score.b == maxSets else { return false }
        } else {
            guard max(score.a, score.b) == need, min(score.a, score.b) < need, score.a + score.b <= maxSets else { return false }
        }
        guard let sets, !sets.isEmpty else { return true }
        guard sets.count == score.a + score.b else { return false }
        var a = 0, b = 0
        for set in sets {
            if matchCompletionMode == "best_of" && (a == need || b == need) { return false }
            guard terminalSet(set) else { return false }
            if set.a > set.b { a += 1 } else { b += 1 }
        }
        return a == score.a && b == score.b
    }
}

extension GroupMatchRules {
    @MainActor func setup(format: GroupFormat) -> SportsSetupResult {
        var value = SportsSetupResult(team1Name: "A", team2Name: "B")
        value.groupMatchRules = self
        value.maxSets = maxSets; value.matchCompletionMode = matchCompletionMode == "play_all" ? .playAll : .bestOf
        value.isSingles = format == .singles; value.pointsPerSet = pointsToWinSet
        value.targetScore = pointsToWinSet; value.scoreCap = pointCap; value.winByTwo = winByTwo; value.useRallyScoring = useRallyScoring
        value.gamesPerSet = gamesPerSet; value.tieBreakPoints = tieBreakPoints; value.setScoringMode = setScoringMode
        value.tennisDeuceMode = usesNoAdScoring ? "no_ad" : "advantage"
        return value
    }
    @MainActor init(sport: GroupSport, setup: SportsSetupResult) {
        if let rules = setup.groupMatchRules, rules.sport == sport { self = rules; return }
        self.sport = sport
        maxSets = setup.maxSets ?? (sport == .tableTennis ? 5 : 3)
        matchCompletionMode = (setup.matchCompletionMode ?? .bestOf).rawValue
        let rally = setup.badmintonRules
        pointsToWinSet = sport == .badminton ? rally.pointsToWinSet : sport == .tableTennis ? (setup.pointsPerSet ?? 11) : sport == .pickleball ? (setup.targetScore ?? 11) : (setup.gamesPerSet ?? 6)
        pointCap = sport == .badminton ? rally.pointCap : sport == .pickleball ? setup.scoreCap : nil
        winByTwo = sport == .pickleball ? (setup.winByTwo ?? true) : true
        useRallyScoring = setup.useRallyScoring ?? false
        gamesPerSet = setup.gamesPerSet ?? 6; tieBreakPoints = setup.tieBreakPoints ?? 7
        setScoringMode = setup.setScoringMode ?? "regular"; usesNoAdScoring = setup.tennisDeuceMode == "no_ad"
    }
}

nonisolated enum GroupQRPayload {
    struct Payload: Codable { var type = "JIFEN_GROUP"; var v = 1; var groupNo: String }
    static func validNumber(_ raw: String) -> Bool { GroupInvitationLink.validNumber(raw) }
    static func formatted(_ number: String) -> String {
        let split = number.count / 2
        return String(number.prefix(split)) + " " + String(number.dropFirst(split))
    }
    static func encode(_ number: String, regionCode: String? = Locale.current.region?.identifier, localization: String = Bundle.main.preferredLocalizations.first ?? "en") -> String {
        GroupInvitationLink.joinURL(groupNo: number, regionCode: regionCode, localization: localization)?.absoluteString ?? ""
    }
    static func parse(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if validNumber(text) { return text }
        if let url = URL(string: text), let number = GroupInvitationLink.groupNumber(from: url) { return number }
        guard let data = text.data(using: .utf8), let p = try? JSONDecoder().decode(Payload.self, from: data), p.type == "JIFEN_GROUP", p.v == 1, validNumber(p.groupNo) else { return nil }
        return p.groupNo
    }
}
