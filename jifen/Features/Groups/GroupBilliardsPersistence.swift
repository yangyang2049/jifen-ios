import Foundation

nonisolated struct GroupBilliardsUpload: Codable, Identifiable, Sendable {
    var id: String; var accountID: String; var groupID: String; var body: GroupBilliardsSubmission?; var failure: String? = nil; var done = false
}
nonisolated final class GroupBilliardsPersistence: @unchecked Sendable {
    static let shared = GroupBilliardsPersistence()
    private let lock = NSRecursiveLock()
    private let root: URL
    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("GroupBilliardsV2", isDirectory: true)) { self.root = root }
    /// 读取容错：文件损坏时隔离坏文件并返回 fallback，绝不抛错，
    /// 避免 `sources.json`/`outbox.json` 永久不可读而拖垮上层流程。
    private func read<T: Decodable>(_ name: String, fallback: T) -> T {
        let path = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: path.path) else { return fallback }
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: path)) }
        catch { quarantine(name); return fallback }
    }
    /// 把解码失败的坏文件改名留存（`.corrupt-<时间>-<随机>`），后续写入即可自愈。
    private func quarantine(_ name: String) {
        let suffix = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        try? FileManager.default.moveItem(at: root.appendingPathComponent(name), to: root.appendingPathComponent("\(name).corrupt-\(suffix)"))
    }
    private func write<T: Encodable>(_ value: T, _ name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent(name), options: .atomic)
    }
    func saveSource(_ source: GroupBilliardsSource, recordID: String) throws {
        lock.lock(); defer { lock.unlock() }
        var sources = read("sources.json", fallback: [String: GroupBilliardsSource]()); sources[recordID] = source
        try write(sources, "sources.json")
    }
    func source(recordID: String) throws -> GroupBilliardsSource? {
        lock.lock(); defer { lock.unlock() }; return read("sources.json", fallback: [String: GroupBilliardsSource]())[recordID]
    }
    func sources(accountID: String, groupID: String) throws -> [String: GroupBilliardsSource] {
        lock.lock(); defer { lock.unlock() }; return read("sources.json", fallback: [String: GroupBilliardsSource]()).filter { $0.value.accountID == accountID && $0.value.groupID == groupID }
    }
    /// 注解失败（读取或编码异常）时降级返回原记录：台球持久化的问题不得扩散到全部记分记录保存。
    func annotate(_ input: ScoreboardRecord) -> ScoreboardRecord {
        guard input.billiardsSource == nil, let source = try? self.source(recordID: input.id),
              let data = try? JSONEncoder().encode(source) else { return input }
        var r = input; var extra = r.extraData ?? [:]
        extra["groupBilliardsSource"] = AnyCodable(String(decoding: data, as: UTF8.self)); r.extraData = extra; return r
    }
    func rows(accountID: String) throws -> [GroupBilliardsUpload] {
        lock.lock(); defer { lock.unlock() }; return read("outbox.json", fallback: [GroupBilliardsUpload]()).filter { $0.accountID == accountID && !$0.done }
    }
    func enqueue(_ input: ScoreboardRecord) throws {
        guard input.status == .finished else { return }
        let record = annotate(input)
        guard let source = record.billiardsSource else { return }
        let projected = Result { try Self.project(record, source: source) }
        let body = try? projected.get()
        try add(.init(id: record.id, accountID: source.accountID, groupID: source.groupID, body: body, failure: body == nil ? "RULES_REVIEW_REQUIRED" : nil))
    }
    func add(_ row: GroupBilliardsUpload) throws {
        lock.lock(); defer { lock.unlock() }
        var rows = read("outbox.json", fallback: [GroupBilliardsUpload]())
        guard !rows.contains(where: { $0.id == row.id && $0.accountID == row.accountID }) else { return }
        rows.append(row); try write(rows, "outbox.json")
    }
    func repair(_ row:GroupBilliardsUpload) throws {
        guard let body=row.body else {throw GroupBilliardsError.result};try body.validate()
        lock.lock();defer{lock.unlock()};var all=read("outbox.json",fallback:[GroupBilliardsUpload]())
        guard let i=all.firstIndex(where:{$0.id==row.id&&$0.accountID==row.accountID}),!all[i].done,["RULES_REVIEW_REQUIRED","INVALID_RESULT","INVALID_RULES"].contains(all[i].failure ?? "") else {throw GroupBilliardsError.result}
        all[i]=row;all[i].failure=nil;try write(all,"outbox.json")
    }
    func finish(_ row: GroupBilliardsUpload, failure: String? = nil, discard: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        var rows = read("outbox.json", fallback: [GroupBilliardsUpload]())
        guard let i = rows.firstIndex(where: { $0.id == row.id && $0.accountID == row.accountID && !$0.done }),
              try canonical(rows[i].body) == canonical(row.body) else { return }
        if failure == nil || discard { rows[i].done = true; rows[i].body = nil }; rows[i].failure = failure
        try write(rows, "outbox.json")
    }
    private func canonical<T: Encodable>(_ value: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(value) }
    func inheritSource(from oldID:String,to newID:String) throws {
        guard var source=try source(recordID:oldID) else {return};source.clientSessionID=newID;source.gameID=nil;source.activityID=nil;source.activitySessionID=nil;try saveSource(source,recordID:newID)
    }
    func rememberRules(_ rules:GroupBilliardsRules,accountID:String,groupID:String) throws {
        lock.lock();defer{lock.unlock()};var all=read("rules.json",fallback:[String:GroupBilliardsRules]());all[accountID+":"+groupID]=rules;try write(all,"rules.json")
    }
    func rememberedRules(accountID:String,groupID:String) throws -> GroupBilliardsRules? {
        lock.lock();defer{lock.unlock()};return read("rules.json",fallback:[String:GroupBilliardsRules]())[accountID+":"+groupID]
    }
    func abandon(recordID: String, source: GroupBilliardsSource) throws {
        lock.lock(); defer { lock.unlock() }
        var all=read("outbox.json",fallback:[GroupBilliardsUpload]());if let i=all.firstIndex(where:{$0.id==recordID&&$0.accountID==source.accountID}){all[i].done=true;all[i].body=nil}else{all.append(.init(id:recordID,accountID:source.accountID,groupID:source.groupID,body:nil,done:true))};try write(all,"outbox.json")
        var sources = read("sources.json",fallback:[String:GroupBilliardsSource]()); sources.removeValue(forKey:recordID); try write(sources,"sources.json")
    }
    static func project(_ r: ScoreboardRecord, source s: GroupBilliardsSource) throws -> GroupBilliardsSubmission {
        try s.rules.validate()
        let rules = s.rules, c = rules.config
        guard r.gameType == rules.knownVariant?.gameType else { throw GroupBilliardsError.rules }
        let cfg=r.projectConfiguration ?? [:]
        if [.folk,.tournament].contains(rules.knownVariant) {
            guard cfg["nineBallBigGold"]?.value as? Int == c.bigGold, cfg["nineBallSmallGold"]?.value as? Int == c.smallGold,
                  cfg["nineBallNormalWin"]?.value as? Int == c.normalWin, cfg["nineBallFoul"]?.value as? Int == c.foul,
                  cfg["nineBallRuleFamily"]?.value as? String == (rules.knownVariant == .folk ? "folk":"tournament") else { throw GroupBilliardsError.rules }
            if rules.knownVariant == .folk { guard cfg["nineBallGoldenNine"]?.value as? Int == c.goldenNine,cfg["nineBallSmallGoldAllPay"]?.value as? Bool == c.smallGoldAllPay,cfg["nineBallGoldRetainsBreak"]?.value as? Bool == c.goldRetainsBreak,cfg["nineBallHandoffEnabled"]?.value as? Bool == c.handoffEnabled else {throw GroupBilliardsError.rules} }
            else { guard cfg["nineBallTotalRacks"]?.value as? Int == c.totalRacks,cfg["nineBallThirdFoul"]?.value as? Int == c.thirdFoul,cfg["nineBallBreakRule"]?.value as? String == c.breakRule else {throw GroupBilliardsError.rules} }
        }
        let points: [Int]
        let extra = r.extraData ?? [:]
        if [.folk, .tournament].contains(rules.knownVariant) {
            guard let values = extra["chasePlayerPoints"]?.value as? [Int], values.count >= rules.playerCount,
                  extra["chaseRuleVersion"]?.value as? Int == 3 else { throw GroupBilliardsError.result }
            points = Array(values.prefix(rules.playerCount))
        } else if rules.knownVariant == .snooker {
            guard let a = r.team1SetScore, let b = r.team2SetScore else { throw GroupBilliardsError.result }; points = [a,b]
        } else { points = [r.team1FinalScore,r.team2FinalScore] }
        if rules.knownVariant == .eight {guard cfg["maxSets"]?.value as? Int == c.targetRacks,(cfg["eightBallHandicapRacks"]?.value as? Int ?? 0)==c.handicapRacks else {throw GroupBilliardsError.rules}}
        if rules.knownVariant == .snooker {guard cfg["maxSets"]?.value as? Int == c.maxFrames else {throw GroupBilliardsError.rules}}
        let racks = rules.knownVariant == .tournament ? max(0,(extra["chaseRoundNumber"]?.value as? Int ?? 1)-1) : nil
        let natural: Bool
        switch rules.knownVariant {
        case .eight: natural = points.max() == c.targetRacks && points[0] != points[1]
        case .snooker: natural = points.max() == c.maxFrames! / 2 + 1 && points[0] != points[1]
        case .tournament: natural = extra["billiardsNaturalCompletion"]?.value as? Bool ?? false
        default: natural = true
        }
        let result = GroupBilliardsResult(resultKind: rules.knownVariant?.resultKind ?? "", completion: natural ? "completed" : "early_stop", scores: points.enumerated().map { .init(participantId: "p\($0.offset)", points: $0.element) }, completedRacks: racks)
        let body = GroupBilliardsSubmission(rules: rules, participants: s.participants, clientSessionId: s.clientSessionID, activityId: s.activityID, activitySessionId: s.activitySessionID, gameId: s.gameID, clientRecordId: r.id, playedAt: Int64((r.endTime ?? r.startTime).timeIntervalSince1970*1000), source: "scoreboard", result: result)
        try body.validate(); return body
    }
}
extension ScoreboardRecord {
    var billiardsSource: GroupBilliardsSource? {
        guard let text = extraData?["groupBilliardsSource"]?.value as? String else { return nil }
        return try? JSONDecoder().decode(GroupBilliardsSource.self, from: Data(text.utf8))
    }
}
@MainActor final class GroupBilliardsSync {
    static let shared = GroupBilliardsSync()
    private var running = false
    func sync(force: Bool = false) async {
        guard !running, let account = GroupStore.shared.accountID else { return }
        running = true; defer { running = false }
        let store = GroupStore.shared, revision = store.identityRevision
        let auth = await store.repository.client.authSessionRevision()
        do {
            for record in ScoreboardRecordManager.shared.loadAllRecords() { try GroupBilliardsPersistence.shared.enqueue(record) }
            for row in try GroupBilliardsPersistence.shared.rows(accountID: account) {
                guard store.matchesIdentity(account, revision: revision), await store.repository.client.authSessionRevision() == auth else { return }
                guard let body = row.body, force || row.failure == nil else { continue }
                guard try GroupBilliardsPersistence.shared.rows(accountID: account).contains(where: { $0.id == row.id }) else { continue }
                do {
                    let _: GroupBilliardsRow = try await store.repository.write("/\(row.groupID)/results", body: body, key: "ios-billiards-"+row.id, expectedAuthRevision: auth)
                    guard store.matchesIdentity(account, revision: revision) else { return }
                    try GroupBilliardsPersistence.shared.finish(row)
                } catch {
                    guard store.matchesIdentity(account, revision: revision) else { return }
                    if error is CancellationError { return }
                    var code = "NETWORK_FAILED"
                    let underlying = (error as? APIClientServerContextError)?.underlying ?? error
                    if case APIClientError.server(let status, let value, _, _) = underlying { code = value ?? "NETWORK_FAILED"; if [401,408,429].contains(status) || status >= 500 { return } }
                    if code == "NETWORK_FAILED" { return }
                    try GroupBilliardsPersistence.shared.finish(row, failure: code)
                }
            }
        } catch { store.error = groupErrorMessage(error) }
    }
}
