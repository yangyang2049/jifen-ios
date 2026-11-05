import Foundation

nonisolated enum GroupBilliardsVariant: String, Codable, CaseIterable, Identifiable, Sendable {
    case folk = "nine_ball_folk", tournament = "nine_ball_tournament", eight = "eight_ball", snooker, standard
    var id: String { rawValue }
    var gameType: GameType { switch self { case .folk, .tournament: .nineBall; case .eight: .eightBall; case .snooker: .snooker; case .standard: .billiards } }
    @MainActor var title: String { switch self { case .folk: billiardsText("folk"); case .tournament: billiardsText("tournament"); default: gameType.displayName } }
    var resultKind: String { switch self { case .folk: "points_ledger"; case .eight: "rack_duel"; case .snooker: "frame_duel"; default: "points_duel" } }
}
nonisolated func billiardsText(_ key: String) -> String { NSLocalizedString("billiards_group_" + key, comment: "Billiards groups") }
nonisolated struct GroupBilliardsConfig: Codable, Hashable, Sendable {
    var pointScheme: String? = nil
    var bigGold: Int? = nil; var smallGold: Int? = nil; var goldenNine: Int? = nil; var normalWin: Int? = nil; var foul: Int? = nil
    var smallGoldAllPay: Bool? = nil; var goldRetainsBreak: Bool? = nil; var handoffEnabled: Bool? = nil
    var thirdFoul: Int? = nil; var breakRule: String? = nil; var totalRacks: Int? = nil
    var targetRacks: Int? = nil; var handicapRacks: Int? = nil; var handicapBeneficiary: String? = nil; var maxFrames: Int? = nil
}
nonisolated struct GroupBilliardsRules: Codable, Hashable, Sendable {
    var version = 2; var sport = "billiards"; var variant: String; var participantMode: String; var playerCount: Int
    var config: GroupBilliardsConfig; var engineRuleVersion: Int? = nil; var initialBreakerParticipantId: String? = nil
    var knownVariant: GroupBilliardsVariant? { GroupBilliardsVariant(rawValue: variant) }
    func validate() throws {
        guard version == 2, sport == "billiards", let v = knownVariant, (2...4).contains(playerCount),
              participantMode == (v == .folk ? "individuals" : "two_sides"), v == .folk || playerCount == 2,
              initialBreakerParticipantId == nil || (0..<playerCount).map({ "p\($0)" }).contains(initialBreakerParticipantId!) else { throw GroupBilliardsError.rules }
        let c = config
        let keys: Set<String>
        switch v {
        case .folk: keys = ["pointScheme", "bigGold", "smallGold", "goldenNine", "normalWin", "foul", "smallGoldAllPay", "goldRetainsBreak", "handoffEnabled"]
        case .tournament: keys = ["bigGold", "smallGold", "normalWin", "foul", "thirdFoul", "breakRule", "totalRacks"]
        case .eight: keys = ["targetRacks", "handicapRacks", "handicapBeneficiary"]
        case .snooker: keys = ["maxFrames"]
        case .standard: keys = []
        }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any] ?? [:]
        guard Set(object.keys).isSubset(of: keys) else { throw GroupBilliardsError.rules }
        func point(_ n: Int?) -> Bool { n.map { (1...99).contains($0) } == true }
        switch v {
        case .folk, .tournament:
            guard engineRuleVersion == 3, point(c.bigGold), point(c.smallGold), point(c.normalWin), point(c.foul) else { throw GroupBilliardsError.rules }
            if v == .folk {
                guard point(c.goldenNine), c.smallGoldAllPay != nil, c.goldRetainsBreak != nil, c.handoffEnabled != nil,
                      c.pointScheme == nil || ["14710", "1357"].contains(c.pointScheme!) else { throw GroupBilliardsError.rules }
            } else { guard point(c.thirdFoul), point(c.totalRacks), ["winner", "alternate"].contains(c.breakRule ?? "") else { throw GroupBilliardsError.rules } }
        case .eight:
            guard point(c.targetRacks), let h = c.handicapRacks, (0..<c.targetRacks!).contains(h),
                  h == 0 ? c.handicapBeneficiary == nil : ["p0", "p1"].contains(c.handicapBeneficiary ?? "") else { throw GroupBilliardsError.rules }
        case .snooker: guard point(c.maxFrames), c.maxFrames! % 2 == 1 else { throw GroupBilliardsError.rules }
        case .standard: break
        }
    }
    static func defaults(_ v: GroupBilliardsVariant, count: Int = 2) -> Self {
        let c: GroupBilliardsConfig
        switch v {
        case .folk: c = .init(pointScheme: "14710", bigGold: 10, smallGold: 7, goldenNine: 4, normalWin: 4, foul: 1, smallGoldAllPay: false, goldRetainsBreak: true, handoffEnabled: true)
        case .tournament: c = .init(bigGold: 10, smallGold: 7, normalWin: 4, foul: 1, thirdFoul: 2, breakRule: "winner", totalRacks: 10)
        case .eight: c = .init(targetRacks: 9, handicapRacks: 0)
        case .snooker: c = .init(maxFrames: 1)
        case .standard: c = .init()
        }
        return .init(variant: v.rawValue, participantMode: v == .folk ? "individuals" : "two_sides", playerCount: v == .folk ? count : 2, config: c, engineRuleVersion: [.folk, .tournament].contains(v) ? 3 : nil)
    }
    @MainActor func setup(names: [String]) throws -> SportsSetupResult {
        try validate()
        var s = SportsSetupResult(team1Name: names.first ?? "", team2Name: names.dropFirst().first ?? "")
        s.team3Name = names.count > 2 ? names[2] : nil; s.team4Name = names.count > 3 ? names[3] : nil
        s.playerCount = playerCount; s.playerNames = names; s.maxSets = config.targetRacks ?? config.maxFrames
        s.eightBallHandicapRacks = config.handicapRacks
        s.eightBallHandicapBeneficiary = config.handicapBeneficiary == "p0" ? "team1" : config.handicapBeneficiary == "p1" ? "team2" : "none"
        s.nineBallBigGold = config.bigGold; s.nineBallSmallGold = config.smallGold; s.nineBallGoldenNine = config.goldenNine
        s.nineBallNormalWin = config.normalWin; s.nineBallFoul = config.foul; s.nineBallSmallGoldAllPay = config.smallGoldAllPay
        s.nineBallGoldRetainsBreak = config.goldRetainsBreak; s.nineBallHandoffEnabled = config.handoffEnabled; s.nineBallPointScheme = config.pointScheme
        s.nineBallThirdFoul = config.thirdFoul; s.nineBallBreakRule = config.breakRule; s.nineBallTotalRacks = config.totalRacks
        s.nineBallRuleFamily = knownVariant == .tournament ? "tournament" : "folk"
        s.nineBallBreakerPlayer = Int(initialBreakerParticipantId?.dropFirst() ?? "0"); s.servingSide = initialBreakerParticipantId == "p1" ? "right" : "left"
        return s
    }
}
nonisolated enum GroupBilliardsError: Error, LocalizedError { case rules, participants, result, otherDevice, unfinished
    var errorDescription: String? { let key = switch self { case .rules: "invalid_rules"; case .participants: "choose_members"; case .result: "invalid_score"; case .otherDevice: "other_device"; case .unfinished: "unfinished" }; return billiardsText(key) }
}
nonisolated struct GroupBilliardsParticipant: Codable, Hashable, Sendable {
    var participantId: String; var memberId: String; var position: Int
}
nonisolated struct GroupBilliardsScore: Codable, Hashable, Sendable { var participantId: String; var points: Int }
nonisolated struct GroupBilliardsResult: Codable, Equatable, Sendable {
    var resultKind: String; var completion: String; var scores: [GroupBilliardsScore]; var completedRacks: Int? = nil; var frames: [GroupScore]? = nil
    func validate(rules r: GroupBilliardsRules) throws {
        try r.validate()
        let ss = scores.sorted { $0.participantId < $1.participantId }
        guard resultKind == r.knownVariant?.resultKind, ["completed", "early_stop"].contains(completion), ss.count == r.playerCount,
              ss.enumerated().allSatisfy({ $0.element.participantId == "p\($0.offset)" && Int32(exactly: $0.element.points) != nil }) else { throw GroupBilliardsError.result }
        let a = ss[0].points, b = ss[1].points, c = r.config
        if r.knownVariant == .folk {
            guard ss.reduce(Int64(0), { $0 + Int64($1.points) }) == 0, completion == "completed", frames == nil, completedRacks == nil else { throw GroupBilliardsError.result }; return
        }
        guard ss.allSatisfy({ $0.points >= 0 }), r.knownVariant == .snooker || frames == nil,
              r.knownVariant == .tournament || completedRacks == nil else { throw GroupBilliardsError.result }
        var terminal = true
        switch r.knownVariant {
        case .eight:
            let target = c.targetRacks!, h = c.handicapRacks!
            guard a >= (c.handicapBeneficiary == "p0" ? h : 0), b >= (c.handicapBeneficiary == "p1" ? h : 0), max(a,b) <= target else { throw GroupBilliardsError.result }
            terminal = max(a,b) == target && a != b
        case .snooker:
            let need = c.maxFrames! / 2 + 1
            guard max(a,b) <= need else { throw GroupBilliardsError.result }
            terminal = max(a,b) == need && a != b
            if let frames {
                var fa = 0, fb = 0
                for f in frames { guard f.a >= 0, f.b >= 0, f.a != f.b, fa < need, fb < need else { throw GroupBilliardsError.result }; if f.a > f.b { fa += 1 } else { fb += 1 } }
                guard fa == a, fb == b else { throw GroupBilliardsError.result }
            }
        case .tournament:
            guard let racks = completedRacks, (0...100000).contains(racks) else { throw GroupBilliardsError.result }
            let swing = 2*c.foul! + max(c.bigGold!, c.smallGold!, c.normalWin!, c.thirdFoul!)
            terminal = racks > 0 && a != b && (racks >= c.totalRacks! || abs(Int64(a)-Int64(b)) > Int64(max(0,c.totalRacks!-racks))*Int64(swing))
            guard Int64(a)+Int64(b) <= Int64(racks)*Int64(swing) + (completion == "early_stop" ? Int64(2*c.foul!) : 0) else { throw GroupBilliardsError.result }
        default: break
        }
        guard !(completion == "completed" && !terminal), !(completion == "early_stop" && r.knownVariant == .standard) else { throw GroupBilliardsError.result }
    }
}
nonisolated struct GroupBilliardsSubmission: Codable, Sendable {
    var rules: GroupBilliardsRules; var participants: [GroupBilliardsParticipant]; var clientSessionId: String
    var activityId: String? = nil; var activitySessionId: String? = nil; var gameId: String? = nil
    var clientRecordId: String; var playedAt: Int64; var source: String; var result: GroupBilliardsResult
    func validate() throws {
        try rules.validate()
        guard participants.count == rules.playerCount, Set(participants.map(\.memberId)).count == participants.count,
              participants.enumerated().allSatisfy({ $0.element.position == $0.offset && $0.element.participantId == "p\($0.offset)" && !$0.element.memberId.isEmpty }) else { throw GroupBilliardsError.participants }
        try result.validate(rules: rules)
    }
}
nonisolated struct GroupBilliardsRow: Codable, Identifiable, Sendable {
    var sport = "billiards"; var format: GroupFormat? = nil
    var id: String; var groupId: String; var gameId: String; var rules: GroupBilliardsRules; var result: GroupBilliardsResult
    var participants: [GroupBilliardsSeat]; var status: String; var playedAt: Int64; var revision: Int64
    var variant: String? = nil; var outcome: String? = nil; var activityId: String? = nil; var activitySessionId: String? = nil
    var canConfirm: Bool? = nil; var canAuthorityConfirm: Bool? = nil; var canVoid: Bool? = nil; var canCorrect: Bool? = nil
}
nonisolated struct GroupBilliardsSeat: Codable, Sendable {
    var participantId: String? = nil; var memberId: String; var position: Int? = nil; var displayName: String? = nil; var side: String? = nil; var seat: Int? = nil
    var canonicalMemberId: String? = nil; var countsForPersonalStats: Bool? = nil
    var participant: GroupBilliardsParticipant { let i = position ?? (side == "individuals" ? seat ?? 0 : side == "B" ? 1 : 0); return .init(participantId: participantId ?? "p\(i)", memberId: memberId, position: i) }
    /// 台球行由服务端/本地按 `participantId/position` 编码，没有 `side/seat`；个人记录链路仍按
    /// `GroupSeat` 读，这里补出等价座位：个人赛缺省 `individuals`，两队制按 `A/B` 两席。
    func groupSeat(individual: Bool) -> GroupSeat { let p = participant; return .init(memberId: memberId, side: side ?? (individual ? "individuals" : (p.position == 0 ? "A" : "B")), seat: seat ?? p.position, displayName: displayName, canonicalMemberId: canonicalMemberId, countsForPersonalStats: countsForPersonalStats) }
}
nonisolated struct GroupBilliardsSource: Codable, Sendable {
    var accountID: String; var groupID: String; var groupName: String; var clientSessionID: String; var gameID: String? = nil
    var activityID: String? = nil; var activitySessionID: String? = nil; var rules: GroupBilliardsRules; var participants: [GroupBilliardsParticipant]; var names: [String]
}
nonisolated struct GroupBilliardsRanking: Codable, Sendable {
    var buckets: [GroupBilliardsBucket]? = nil; var items: [GroupBilliardsRank]? = nil; var statsRevision: String? = nil
}
nonisolated struct GroupBilliardsBucket: Codable, Identifiable, Sendable {
    var key: String; var rules: GroupBilliardsRules
    var id: String { key }
}
nonisolated struct GroupBilliardsRank: Codable, Identifiable, Sendable {
    var memberId: String; var displayName: String; var rank: Int; var games: Int
    var totalPoints: Int? = nil; var wins: Int? = nil; var losses: Int? = nil; var winRateText: String? = nil
    var id: String { memberId }
}

nonisolated extension GroupResult {
    private enum CodingKeys: String, CodingKey { case id, groupId, activityId, gameId, format, sport, bestOf, setScore, sets, winnerSide, outcome, rules, participants, playedAt, submitterMemberId, confirmedByMemberId, status, source, reason, createdAt, revision, activitySessionId, confirmationMode, canAuthorityConfirm, submitterCanonicalMemberId, confirmedByCanonicalMemberId }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        groupId = try c.decode(String.self, forKey: .groupId)
        gameId = try c.decode(String.self, forKey: .gameId)
        sport = try c.decode(GroupSport.self, forKey: .sport)
        playedAt = try c.decode(Int64.self, forKey: .playedAt)
        status = try c.decode(String.self, forKey: .status)
        revision = try c.decode(Int64.self, forKey: .revision)
        activityId = try c.decodeIfPresent(String.self, forKey: .activityId) ?? ""
        submitterMemberId = try c.decodeIfPresent(String.self, forKey: .submitterMemberId) ?? ""
        confirmedByMemberId = try c.decodeIfPresent(String.self, forKey: .confirmedByMemberId) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? playedAt
        bestOf = try c.decodeIfPresent(Int.self, forKey: .bestOf)
        sets = try c.decodeIfPresent([GroupScore].self, forKey: .sets)
        winnerSide = try c.decodeIfPresent(String.self, forKey: .winnerSide)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        activitySessionId = try c.decodeIfPresent(String.self, forKey: .activitySessionId)
        confirmationMode = try c.decodeIfPresent(String.self, forKey: .confirmationMode)
        canAuthorityConfirm = try c.decodeIfPresent(Bool.self, forKey: .canAuthorityConfirm)
        submitterCanonicalMemberId = try c.decodeIfPresent(String.self, forKey: .submitterCanonicalMemberId)
        confirmedByCanonicalMemberId = try c.decodeIfPresent(String.self, forKey: .confirmedByCanonicalMemberId)
        if sport == .billiards {
            // 台球行走 `GroupBilliardsRow` 自己的编码：没有 `format`，座位是
            // `participantId/position`，因此必须在这里分流，不能按 `[GroupSeat]` 解。
            let row = try GroupBilliardsRow(from: decoder)
            billiards = row
            let individual = row.rules.participantMode == "individuals"
            format = try c.decodeIfPresent(GroupFormat.self, forKey: .format) ?? (individual ? .individuals : .singles)
            participants = row.participants.map { $0.groupSeat(individual: individual) }
            setScore = .init(a:0,b:0); rules = nil
        } else {
            format = try c.decodeIfPresent(GroupFormat.self, forKey: .format) ?? .singles
            participants = try c.decodeIfPresent([GroupSeat].self, forKey: .participants) ?? []
            setScore = try c.decode(GroupScore.self, forKey: .setScore)
            rules = try c.decodeIfPresent(GroupMatchRules.self, forKey: .rules)
        }
    }
    func encode(to encoder: Encoder) throws {
        if let billiards { try billiards.encode(to: encoder); return }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(groupId, forKey: .groupId)
        try c.encode(activityId, forKey: .activityId)
        try c.encode(gameId, forKey: .gameId)
        try c.encode(format, forKey: .format)
        try c.encode(sport, forKey: .sport)
        try c.encodeIfPresent(bestOf, forKey: .bestOf)
        try c.encode(setScore, forKey: .setScore)
        try c.encodeIfPresent(sets, forKey: .sets)
        try c.encodeIfPresent(winnerSide, forKey: .winnerSide)
        try c.encodeIfPresent(outcome, forKey: .outcome)
        try c.encodeIfPresent(rules, forKey: .rules)
        try c.encode(participants, forKey: .participants)
        try c.encode(playedAt, forKey: .playedAt)
        try c.encode(submitterMemberId, forKey: .submitterMemberId)
        try c.encode(confirmedByMemberId, forKey: .confirmedByMemberId)
        try c.encode(status, forKey: .status)
        try c.encode(source, forKey: .source)
        try c.encode(reason, forKey: .reason)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(revision, forKey: .revision)
        try c.encodeIfPresent(activitySessionId, forKey: .activitySessionId)
        try c.encodeIfPresent(confirmationMode, forKey: .confirmationMode)
        try c.encodeIfPresent(canAuthorityConfirm, forKey: .canAuthorityConfirm)
        try c.encodeIfPresent(submitterCanonicalMemberId, forKey: .submitterCanonicalMemberId)
        try c.encodeIfPresent(confirmedByCanonicalMemberId, forKey: .confirmedByCanonicalMemberId)
    }
}

@MainActor extension GroupBilliardsRow {
    func personalSummary(groupName:String)->[String:PersonalJSON] {
        var summary:[String:PersonalJSON]=["title":.string(groupName),"groupGameId":.string(gameId)]
        summary["players"] = .array(result.scores.map { score in .object(["seatKey":.string(score.participantId),"name":.string(participants.first{$0.participant.participantId==score.participantId}?.displayName ?? ""),"score":.integer(Int64(score.points))]) })
        return summary
    }
}

@MainActor extension GroupBilliardsRow {
    var shareText:String {
        let lines=result.scores.map { score in (participants.first{$0.participant.participantId==score.participantId}?.displayName ?? billiardsText("unknown"))+"  "+(rules.knownVariant == .folk && score.points>0 ? "+":"")+String(score.points) }
        return ([rules.summary,billiardsText(status=="confirmed" ? "confirmed":status=="voided" ? "voided":"pending")]+(result.completion=="early_stop" ? [billiardsText("early_stop")]:[])+lines).joined(separator:"\n")
    }
}
