import Foundation
import Observation

/// Read through the existing group APIs and their membership checks. These rows
/// are never pushed to the private-record service or deleted from the personal page.
@MainActor @Observable final class PersonalGroupRecords {
    static let shared = PersonalGroupRecords()
    private(set) var rows: [PersonalRecordEnvelope] = []
    private(set) var error: String?
    private(set) var isLoading = false
    private var accountId: String?
    private var members: [String: GroupMember] = [:]
    private var generation: UInt64 = 0
    private var lastSuccessfulRefresh: Date?
    let cacheDirectoryURL: URL
    private let repository: GroupRepository
    private let currentAccountID: @MainActor () -> String?
    var visibleRows: [PersonalRecordEnvelope] { accountId == currentAccountID() ? rows : [] }

    init(cacheDirectoryURL: URL? = nil, repository: GroupRepository = .init(),
         currentAccountID: @escaping @MainActor () -> String? = { SessionStore.shared.user?.id }) {
        self.cacheDirectoryURL = cacheDirectoryURL ?? AppTestRuntime.storageRootURL?.appendingPathComponent("PersonalGroupRecords", isDirectory: true)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("jifen-v3/participant-identity", isDirectory: true)
        self.repository = repository
        self.currentAccountID = currentAccountID
        restoreCachedRows()
    }
    private struct Cache: Codable { var rows: [PersonalRecordEnvelope]; var members: [String: GroupMember] }

    static func currentMember(groupId: String) -> GroupMember? {
        guard let id = SessionStore.shared.user?.id else { return nil }
        if let member = GroupStore.shared.cache.details[groupId]?.members.first(where: { $0.kind == "account" && $0.accountId == id }) { return member }
        guard shared.accountId == id else { return nil }
        return shared.members[groupId]
    }

    static func isMine(_ result: GroupResult, member: GroupMember) -> Bool {
        result.status == "confirmed" && member.kind == "account"
            && result.participants.filter { $0.countsForPersonalStats != false && $0.belongs(to: member) }.count == 1
    }

    private func cacheURL(_ id: String) -> URL {
        // Account IDs are opaque; never use them directly as a path component.
        let safe = Data(id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return cacheDirectoryURL.appendingPathComponent("groups-" + safe + ".json")
    }

    func clearLocalCache() throws {
        generation &+= 1
        rows = []; members = [:]; accountId = nil; error = nil; isLoading = false; lastSuccessfulRefresh = nil
        let directory = cacheURL("unused").deletingLastPathComponent()
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent.hasPrefix("groups-") {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Restore before the first network suspension; cached rows stay visible
    /// while revisiting the page or refreshing an offline account.
    func restoreCachedRows() {
        let id = currentAccountID()
        guard accountId != id else { return }
        accountId = id; rows = []; members = [:]; error = nil; lastSuccessfulRefresh = nil
        if let id, let data = try? Data(contentsOf: cacheURL(id)), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            rows = cache.rows; members = cache.members
        }
    }

    func refresh(force: Bool = false) async {
        restoreCachedRows()
        guard let id = currentAccountID() else { isLoading = false; return }
        if !force, let lastSuccessfulRefresh, Date().timeIntervalSince(lastSuccessfulRefresh) < 60 { return }
        generation &+= 1
        let epoch = generation
        isLoading = true
        defer { if generation == epoch { isLoading = false } }
        let revision = await repository.client.authSessionRevision()
        do {
            let groups: [ScoreGroup] = try await repository.allPages("", expectedAuthRevision: revision)
            var received: [PersonalRecordEnvelope] = []; var current: [String: GroupMember] = [:]
            for group in groups {
                try Task.checkCancellation()
                let roster: [GroupMember] = try await repository.allPages("/\(group.id)/members", expectedAuthRevision: revision)
                guard let me = roster.first(where: { $0.kind == "account" && $0.accountId == id }) else { continue }
                current[group.id] = me
                var cursor: String?
                repeat {
                    let page = try await repository.results(group.id, cursor: cursor, memberID: me.canonicalMemberId ?? me.id, status: "confirmed", expectedAuthRevision: revision)
                    for result in page.items where Self.isMine(result, member: me) {
                        let payload = try JSONDecoder().decode([String: PersonalJSON].self, from: JSONEncoder().encode(result))
                        received.append(.init(libraryId: "group:" + group.id, recordKey: result.id, kind: "score",
                            project: result.format == .doubles ? group.sport.gameType.canonicalScoreboardIdentifier + "_doubles" : group.sport.gameType.canonicalScoreboardIdentifier,
                            playedAt: result.playedAt, participantMode: "individual", participants: result.participants.map { seat in
                                .init(seatKey: "\(seat.side):\(seat.seat)", kind: "PERSON", nameSnapshot: seat.displayName ?? roster.first(where: { $0.ownsHistoricalMember(seat.memberId) })?.displayName ?? "",
                                    personRef: seat.belongs(to: me) ? ParticipantIdentityStore.shared.person : nil, sideKey: seat.side)
                            }, summary: ["title": .string(group.name), "leftScore": .integer(Int64(result.setScore.a)), "rightScore": .integer(Int64(result.setScore.b)), "groupGameId": .string(result.gameId)],
                            origin: .init(nativeSchemaVersion: 1, sessionId: result.gameId, sourceSystem: "group"), nativePayload: payload, assetIds: []))
                    }
                    cursor = page.nextCursor
                } while cursor != nil
            }
            let currentRevision = await repository.client.authSessionRevision()
            guard generation == epoch, currentAccountID() == id, currentRevision == revision, !Task.isCancelled else { return }
            rows = received; members = current; error = nil; lastSuccessfulRefresh = Date()
            let url = cacheURL(id); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Cache(rows: received, members: current)).write(to: url, options: .atomic)
        } catch {
            guard generation == epoch, currentAccountID() == id, !Task.isCancelled else { return }
            self.error = groupErrorMessage(error)
        }
    }
}
