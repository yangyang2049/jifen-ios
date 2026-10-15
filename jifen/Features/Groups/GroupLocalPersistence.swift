import Foundation
import RecordCore

nonisolated struct GroupMatchContext: Codable, Sendable {
    var accountID: String; var groupID: String; var groupName: String; var activityID: String?
    var gameID: String?; var clientSessionID: String; var format: GroupFormat; var rules: GroupMatchRules; var participants: [GroupSeat]
    var trainingSessionID: String? = nil
    var activitySessionID: String? = nil
}
nonisolated struct GroupPendingUpload: Codable, Identifiable, Sendable {
    var id: String; var accountID: String; var groupID: String; var key: String; var body: GroupResultBody
    var failure: String? = nil; var uploaded = false
    var failureCode: String? = nil
    var nextAttemptAt: Date? = nil
    var attempts: Int? = nil
    var existingResultID: String? = nil
}

nonisolated struct GroupUploadTombstone: Codable, Sendable {
    var id: String; var accountID: String; var groupID: String; var resultID: String?
}

nonisolated struct GroupPendingDirectLineup: Codable, Sendable {
    var key: String; var accountID: String; var groupID: String
    var fingerprint: Data; var body: GroupDirectLineupBody
}

/// Durable association is indexed by the engine session UUID, never names or timestamps.
/// The record keeps its own copy so an interrupted outbox write can be repaired.
nonisolated final class GroupLocalPersistence: @unchecked Sendable {
    static let shared = GroupLocalPersistence()
    private let lock = NSRecursiveLock()
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Groups-\(APIEnvironment.current.rawValue)", isDirectory: true)
    }
    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func write<T: Encodable>(_ value: T, _ name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent(name), options: .atomic)
    }
    private func readOutbox() throws -> [GroupPendingUpload] {
        let url = root.appendingPathComponent("outbox.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let rows = try JSONDecoder().decode([GroupPendingUpload].self, from: Data(contentsOf: url))
        let terminal = rows.filter(\.uploaded)
        if !terminal.isEmpty {
            var marks = tombstones()
            for row in terminal where !marks.contains(where: { $0.id == row.id && $0.accountID == row.accountID }) {
                marks.append(.init(id: row.id, accountID: row.accountID, groupID: row.groupID, resultID: nil))
            }
            try write(marks, "tombstones.json")
            try write(rows.filter { !$0.uploaded }, "outbox.json")
        }
        return rows.filter { !$0.uploaded }
    }
    private func tombstones() -> [GroupUploadTombstone] { read([GroupUploadTombstone].self, "tombstones.json") ?? [] }
    private func pendingDirectLineups() throws -> [GroupPendingDirectLineup] {
        let url = root.appendingPathComponent("pending-direct-lineups.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([GroupPendingDirectLineup].self, from: Data(contentsOf: url))
    }
    /// Persist the first anchored request, so a retry cannot change either its time or its key.
    func pendingDirectLineup(accountID: String, groupID: String, body: GroupDirectLineupBody,
                             now: Date = Date()) throws -> GroupPendingDirectLineup {
        lock.lock(); defer { lock.unlock() }
        guard !(read([String].self, "deleted-accounts.json") ?? []).contains(accountID) else { throw GroupFlowError.staleSession }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let fingerprint = try encoder.encode(body)
        var pending = try pendingDirectLineups()
        if let previous = pending.first(where: { $0.accountID == accountID && $0.groupID == groupID && $0.fingerprint == fingerprint }) { return previous }
        let next = GroupPendingDirectLineup(key: UUID().uuidString, accountID: accountID, groupID: groupID,
            fingerprint: fingerprint, body: body.anchored(now: now))
        pending.append(next); try write(pending, "pending-direct-lineups.json")
        return next
    }
    func completeDirectLineup(key: String, accountID: String) throws {
        lock.lock(); defer { lock.unlock() }
        try write(try pendingDirectLineups().filter { !($0.accountID == accountID && $0.key == key) }, "pending-direct-lineups.json")
    }
    func saveContext(_ context: GroupMatchContext, sessionID: String) throws {
        lock.lock(); defer { lock.unlock() }
        var all = read([String: GroupMatchContext].self, "contexts.json") ?? [:]
        all[sessionID] = context; try write(all, "contexts.json")
    }
    func context(sessionID: String) -> GroupMatchContext? {
        lock.lock(); defer { lock.unlock() }
        return read([String: GroupMatchContext].self, "contexts.json")?[sessionID]
    }
    #if DEBUG
    /// Removes only a synthetic capture association under the same lock as ordinary context writes.
    func removeCaptureContext(sessionID: String, gameID: String) throws {
        guard GroupCaptureFixture.enabled,
              ["compare_capture_single_game", "compare_frozen_activity_game"].contains(gameID) else {
            throw GroupCaptureFailure.invalidFixture("capture context cleanup outside owned fixture")
        }
        lock.lock(); defer { lock.unlock() }
        var all = read([String: GroupMatchContext].self, "contexts.json") ?? [:]
        guard let context = all[sessionID], context.accountID == "compare-account",
              context.groupID == "seed_group_badminton", context.gameID == gameID else { return }
        all.removeValue(forKey: sessionID)
        try write(all, "contexts.json")
    }
    #endif
    func annotate(_ input: ScoreboardRecord) -> ScoreboardRecord {
        guard input.groupMatchContext == nil, let context = context(sessionID: input.id), let data = try? JSONEncoder().encode(context), let text = String(data: data, encoding: .utf8) else { return input }
        var record = input; var extra = record.extraData ?? [:]
        extra["groupMatchContext"] = AnyCodable(text); record.extraData = extra; return record
    }
    func enqueue(_ record: ScoreboardRecord) throws {
        guard record.status == .finished, let context = record.groupMatchContext else { return }
        let score: GroupScore
        let details: [GroupScore]?
        if context.rules.sport == .tennis && context.rules.setScoringMode == "tiebreak_only" {
            let points = GroupScore(a: record.team1FinalScore, b: record.team2FinalScore)
            score = .init(a: points.a > points.b ? 1 : 0, b: points.b > points.a ? 1 : 0)
            details = [points]
        } else {
            guard let a = record.team1SetScore, let b = record.team2SetScore else { return }
            score = .init(a: a, b: b)
            let sets = record.setResults?.sorted { $0.number < $1.number }.compactMap { set -> GroupScore? in
                guard set.scores.count >= 2 else { return nil }; return .init(a: set.scores[0], b: set.scores[1])
            }
            details = sets?.isEmpty == false ? sets : nil
        }
        lock.lock(); defer { lock.unlock() }
        if (read([String].self, "deleted-accounts.json") ?? []).contains(context.accountID) { return }
        var all = try readOutbox()
        guard !all.contains(where: { $0.id == record.id && $0.accountID == context.accountID }),
              !tombstones().contains(where: { $0.id == record.id && $0.accountID == context.accountID }) else { return }
        var pending = GroupPendingUpload(id: record.id, accountID: context.accountID, groupID: context.groupID, key: "ios-record-\(record.id)", body: .init(
            gameId: context.gameID, clientSessionId: context.clientSessionID, clientRecordId: record.id, activityId: context.activityID,
            format: context.format, bestOf: context.rules.maxSets, rules: context.rules, setScore: score, sets: details,
            playedAt: Int64((record.endTime ?? record.startTime).timeIntervalSince1970 * 1000), source: "scoreboard", participants: context.participants.map { .init(memberId: $0.memberId, side: $0.side, seat: $0.seat) }, trainingSessionId: context.trainingSessionID, activitySessionId: context.activitySessionID
        ))
        if !context.rules.validResult(score, sets: details) { pending.failure = groupText("invalid_result", "The recorded result needs review before upload.") }
        all.append(pending); try write(all, "outbox.json")
    }
    func repairOutbox(from records: [ScoreboardRecord]) { for record in records { try? enqueue(annotate(record)) } }
    func uploads(accountID: String?) -> [GroupPendingUpload] {
        guard let accountID else { return [] }; lock.lock(); defer { lock.unlock() }
        return ((try? readOutbox()) ?? []).filter { $0.accountID == accountID }
    }
    func markUploaded(_ id: String, accountID: String, resultID: String? = nil) throws {
        try finishUpload(id, accountID: accountID, resultID: resultID)
    }
    func markFailure(_ id: String, accountID: String, message: String?) throws {
        lock.lock(); defer { lock.unlock() }; var rows = try readOutbox()
        if let i = rows.firstIndex(where: { $0.id == id && $0.accountID == accountID }) { rows[i].failure = message; try write(rows, "outbox.json") }
    }
    func enqueueManual(_ body: GroupResultBody, id: String, accountID: String, groupID: String, key: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard !(read([String].self, "deleted-accounts.json") ?? []).contains(accountID) else { throw GroupFlowError.staleSession }
        guard !tombstones().contains(where: { $0.id == id && $0.accountID == accountID }) else { return }
        var rows = try readOutbox()
        if let index = rows.firstIndex(where: { $0.id == id && $0.accountID == accountID }) {
            rows[index].body = body; rows[index].failure = nil; rows[index].failureCode = nil; rows[index].nextAttemptAt = nil
        } else { rows.append(.init(id: id, accountID: accountID, groupID: groupID, key: key, body: body)) }
        try write(rows, "outbox.json")
    }
    func updateRetry(_ id: String, accountID: String, code: String?, failure: String?, next: Date?, existingResultID: String? = nil) throws {
        lock.lock(); defer { lock.unlock() }; var rows = try readOutbox()
        guard let i = rows.firstIndex(where: { $0.id == id && $0.accountID == accountID }) else { return }
        rows[i].failure = failure; rows[i].failureCode = code; rows[i].nextAttemptAt = next
        rows[i].attempts = (rows[i].attempts ?? 0) + 1; rows[i].existingResultID = existingResultID
        try write(rows, "outbox.json")
    }
    func finishUpload(_ id: String, accountID: String, resultID: String? = nil) throws {
        lock.lock(); defer { lock.unlock() }; var rows = try readOutbox()
        guard let row = rows.first(where: { $0.id == id && $0.accountID == accountID }) else { return }
        var marks = tombstones()
        if !marks.contains(where: { $0.id == id && $0.accountID == accountID }) {
            marks.append(.init(id: id, accountID: accountID, groupID: row.groupID, resultID: resultID))
        }
        try write(marks, "tombstones.json")
        rows.removeAll { $0.id == id && $0.accountID == accountID }; try write(rows, "outbox.json")
    }
    func abandonGame(groupID: String, gameID: String, accountID: String) throws {
        lock.lock(); defer { lock.unlock() }
        let contexts = read([String: GroupMatchContext].self, "contexts.json") ?? [:]
        var marks = tombstones()
        for (id, context) in contexts where context.accountID == accountID && context.groupID == groupID && context.gameID == gameID {
            if !marks.contains(where: { $0.id == id && $0.accountID == accountID }) { marks.append(.init(id: id, accountID: accountID, groupID: groupID, resultID: nil)) }
        }
        for row in try readOutbox() where row.accountID == accountID && row.groupID == groupID && row.body.gameId == gameID {
            if !marks.contains(where: { $0.id == row.id && $0.accountID == accountID }) { marks.append(.init(id: row.id, accountID: accountID, groupID: groupID, resultID: nil)) }
        }
        try write(marks, "tombstones.json")
        try write(try readOutbox().filter { !($0.accountID == accountID && $0.groupID == groupID && $0.body.gameId == gameID) }, "outbox.json")
    }
    func forgetGroup(_ groupID: String, accountID: String) throws {
        lock.lock(); defer { lock.unlock() }
        let contexts = read([String: GroupMatchContext].self, "contexts.json") ?? [:]
        var marks = tombstones()
        let rows = try readOutbox()
        let ids = rows.filter { $0.accountID == accountID && $0.groupID == groupID }.map(\.id)
            + contexts.filter { $0.value.accountID == accountID && $0.value.groupID == groupID }.map(\.key)
        for id in ids where !marks.contains(where: { $0.id == id && $0.accountID == accountID }) { marks.append(.init(id: id, accountID: accountID, groupID: groupID, resultID: nil)) }
        try write(marks, "tombstones.json")
        try write(rows.filter { !($0.accountID == accountID && $0.groupID == groupID) }, "outbox.json")
    }
    func saveDraft<T: Encodable>(_ draft: T, key: String, accountID: String) throws {
        lock.lock(); defer { lock.unlock() }; try write(draft, draftName(key, accountID: accountID))
    }
    func loadDraft<T: Decodable>(_ type: T.Type, key: String, accountID: String) -> T? {
        lock.lock(); defer { lock.unlock() }; return read(type, draftName(key, accountID: accountID))
    }
    func removeDraft(key: String, accountID: String) {
        lock.lock(); defer { lock.unlock() }; try? FileManager.default.removeItem(at: root.appendingPathComponent(draftName(key, accountID: accountID)))
    }
    private func draftName(_ key: String, accountID: String) -> String {
        let safe = Data((accountID + ":" + key).utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return "draft-\(safe).json"
    }
    func loadCache(accountID: String) -> GroupAccountCache? { lock.lock(); defer { lock.unlock() }; return read(GroupAccountCache.self, "cache-\(accountID).json") }
    func saveCache(_ cache: GroupAccountCache, accountID: String) throws { lock.lock(); defer { lock.unlock() }; try write(cache, "cache-\(accountID).json") }
    func removeCache(accountID: String) { lock.lock(); defer { lock.unlock() }; try? FileManager.default.removeItem(at: root.appendingPathComponent("cache-\(accountID).json")) }
    func deleteAccountData(accountID: String) {
        lock.lock(); defer { lock.unlock() }; removeCache(accountID: accountID)
        var deleted = read([String].self, "deleted-accounts.json") ?? []; if !deleted.contains(accountID) { deleted.append(accountID) }; try? write(deleted, "deleted-accounts.json")
        if let pending = try? pendingDirectLineups() {
            try? write(pending.filter { $0.accountID != accountID }, "pending-direct-lineups.json")
        }
        guard let existingRows = try? readOutbox() else { return }
        let rows = existingRows.filter { $0.accountID != accountID }
        let contexts = (read([String: GroupMatchContext].self, "contexts.json") ?? [:]).filter { $0.value.accountID != accountID }
        try? write(rows, "outbox.json"); try? write(contexts, "contexts.json")
        try? write(tombstones().filter { $0.accountID != accountID }, "tombstones.json")
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent.hasPrefix("draft-") {
            let encoded = String(url.deletingPathExtension().lastPathComponent.dropFirst(6)).replacingOccurrences(of: "_", with: "/")
            if let data = Data(base64Encoded: encoded), let key = String(data: data, encoding: .utf8), key.hasPrefix(accountID + ":") { try? FileManager.default.removeItem(at: url) }
        }
    }
}

extension ScoreboardRecord {
    nonisolated var groupMatchContext: GroupMatchContext? {
        guard let text = extraData?["groupMatchContext"]?.value as? String, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GroupMatchContext.self, from: data)
    }
}
