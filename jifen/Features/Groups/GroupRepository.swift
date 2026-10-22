import Foundation
import Observation
import Network

nonisolated struct GroupCreateBody: Codable, Sendable { var name: String; var description: String; var sport: GroupSport; var joinPolicy: String; var groupType = "peer" }
nonisolated struct GroupActivityBody: Codable, Sendable { var title: String; var startsAt: Int64; var place: String; var capacity: Int; var note: String; var format: GroupFormat; var matchMode = "multi"; var activityType = "signup"; var timingMode = "estimated"; var registrationClosesAt: Int64? = nil }
nonisolated struct GroupActionBody: Encodable, Sendable { var message: String? = nil; var memberId: String? = nil; var displayName: String? = nil; var targetMemberId: String? = nil; var role: String? = nil; var name: String? = nil; var description: String? = nil; var joinPolicy: String? = nil; var reason: String? = nil }
nonisolated struct GroupGameBody: Encodable, Sendable { var clientSessionId: String; var activityId: String?; var format: GroupFormat; var rules: GroupMatchRules; var participants: [GroupSeat]; var trainingSessionId: String? = nil; var activitySessionId: String? = nil }
nonisolated struct GroupResultBody: Codable, Sendable {
    var gameId: String?; var clientSessionId: String?; var clientRecordId: String?; var activityId: String?
    var format: GroupFormat; var bestOf: Int; var rules: GroupMatchRules; var setScore: GroupScore; var sets: [GroupScore]?
    var playedAt: Int64; var source: String; var participants: [GroupSeat]
    var trainingSessionId: String? = nil
    var activitySessionId: String? = nil
}
nonisolated enum GroupRequestIdentity {
    @TaskLocal static var authRevision: UInt64?
    @TaskLocal static var capabilities: GroupCapabilities?
}
nonisolated struct GroupRepository: Sendable {
    var client: APIClient = .shared
    var persistence: GroupLocalPersistence = .shared
    private func requestRevision(_ expected: UInt64?) async -> UInt64 {
        if let revision = expected ?? GroupRequestIdentity.authRevision { return revision }
        return await client.authSessionRevision()
    }
    func read<T: Decodable & Sendable>(_ path: String, authenticated: Bool = true, query: [URLQueryItem] = [], expectedAuthRevision: UInt64? = nil) async throws -> T {
        #if DEBUG
        if GroupCaptureFixture.enabled { return try GroupCaptureFixture.read(path, query: query) }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") {
            if path.hasSuffix("/report") { return try JSONDecoder().decode(T.self, from: Data("{\"report\":null}".utf8)) }
            if path == "/capabilities", var catalog = await MainActor.run(body: { GroupStore.shared.capabilities }) {
                catalog.groupReportEvidenceEnabled = true
                return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(catalog))
            }
        }
        #endif
        let revision: UInt64? = authenticated ? await requestRevision(expectedAuthRevision) : nil
        return try await client.request("/api/groups" + path, query: query, requiresAuth: authenticated, expectedAuthRevision: revision)
    }
    func write<T: Decodable & Sendable>(_ path: String, body: (any Encodable & Sendable)? = nil, method: HTTPMethod = .post, key: String? = nil, revision: Int64? = nil, expectedAuthRevision: UInt64? = nil) async throws -> T {
        #if DEBUG
        if GroupCaptureFixture.enabled { try GroupCaptureFixture.rejectWrite(path) }
        #endif
        let authRevision = await requestRevision(expectedAuthRevision)
        if let action = GroupWriteCapability.required(for: path, method: method) {
            let catalog: GroupCapabilities
            if let current = GroupRequestIdentity.capabilities { catalog = current }
            else { catalog = try await read("/capabilities", expectedAuthRevision: authRevision) }
            guard catalog.allows(action) else {
                throw APIClientError.server(status: 409, code: "ACTION_DISABLED", message: nil, nextAvailableAt: nil)
            }
        }
        var headers: [String: String] = [:]
        if let key { headers["Idempotency-Key"] = key }
        if let revision { headers["If-Match"] = "\"\(revision)\"" }
        return try await client.request("/api/groups" + path, method: method, body: body ?? EmptyRequest(), requiresAuth: true, headers: headers, expectedAuthRevision: authRevision)
    }
    func action(_ path: String, body: GroupActionBody = .init(), method: HTTPMethod = .post, revision: Int64? = nil, expectedAuthRevision: UInt64? = nil) async throws {
        let _: EmptyResponse = try await write(path, body: body, method: method, revision: revision, expectedAuthRevision: expectedAuthRevision)
    }
    func results(_ groupID: String, cursor: String? = nil, memberID: String? = nil, format: GroupFormat? = nil, status: String? = nil, expectedAuthRevision: UInt64? = nil) async throws -> GroupPage<GroupResult> {
        var query = [URLQueryItem(name: "limit", value: "50")]
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        if let memberID { query.append(.init(name: "memberId", value: memberID)) }
        if let format { query.append(.init(name: "format", value: format.rawValue)) }
        if let status { query.append(.init(name: "status", value: status)) }
        return try await read("/\(groupID)/results", query: query, expectedAuthRevision: expectedAuthRevision)
    }
    func createGroup(body: GroupCreateBody, accountID: String) async throws -> ScoreGroup {
        try await create("", body: body, accountID: accountID)
    }
    func createActivity(groupID: String, body: GroupActivityBody, accountID: String) async throws -> GroupActivity {
        try await create("/\(groupID)/activities", body: body, accountID: accountID)
    }
    private func create<Body: Codable & Sendable, Response: Decodable & Sendable>(_ path: String, body: Body, accountID: String) async throws -> Response {
        let authRevision = await requestRevision(nil)
        let pending = try persistence.pendingWrite(accountID: accountID, path: path, body: body)
        do {
            let original = try JSONDecoder().decode(Body.self, from: pending.body)
            let response: Response = try await write(path, body: original, key: pending.key, expectedAuthRevision: authRevision)
            try? persistence.completeWrite(key: pending.key, accountID: accountID)
            return response
        } catch {
            let underlying = (error as? APIClientServerContextError)?.underlying ?? error
            if case APIClientError.server(let status, let code, _, _) = underlying,
               [400, 403, 404, 405, 410, 413, 414, 415, 422, 426].contains(status),
               code != "NEED_LOGIN", code != "INVALID_RESPONSE" {
                try? persistence.completeWrite(key: pending.key, accountID: accountID)
            }
            // Authentication failures, lost responses, malformed successes and stale-session cancellation
            // retain their exact payload and key for the original account.
            throw error
        }
    }
    /// 直接排赛（安卓 `createDirectLineup`）：一次请求建 `activityType=direct` 活动并落对阵场次。
    func createDirectLineup(groupID: String, body: GroupDirectLineupBody, accountID: String) async throws -> GroupDirectLineupResponse {
        let authRevision = await requestRevision(nil)
        let pending = try persistence.pendingDirectLineup(accountID: accountID, groupID: groupID, body: body)
        let response: GroupDirectLineupResponse = try await write("/\(groupID)/direct-lineups", body: pending.body,
            key: pending.key, expectedAuthRevision: authRevision)
        try? persistence.completeDirectLineup(key: pending.key, accountID: accountID)
        return response
    }
    func activityLineup(groupID: String, activityID: String) async throws -> GroupActivityLineup {
        try await read("/\(groupID)/activities/\(activityID)/lineup")
    }
    func updateActivityLineup(groupID: String, activityID: String, body: GroupLineupBody, revision: Int64) async throws {
        let _: GroupActivityLineup = try await write("/\(groupID)/activities/\(activityID)/lineup", body: body, method: .put, revision: revision)
    }
}

nonisolated struct GroupDetailCache: Codable, Sendable {
    var group: ScoreGroup; var members: [GroupMember]; var activities: [GroupActivity]; var results: [GroupResult]
    var rankings: [GroupRanking]; var stats: GroupStats?; var nextCursor: String?; var syncedAt: Date
    var trainingPlans: [GroupTrainingPlan]? = nil
    var leaveNotices: [GroupLeaveNotice]? = nil
    var pendingResults: [GroupResult]? = nil
    var removedMembers: [GroupMember]? = nil
    var trainingNotices: [GroupTrainingNotice]? = nil
    var activityLineups: [String: GroupActivityLineup]? = nil
    var rankingsByFormat: [String: [GroupRanking]]? = nil

    func rankings(for format: GroupFormat) -> [GroupRanking] {
        // Legacy snapshots have no format; refresh them rather than guessing singles or doubles.
        rankingsByFormat?[format.rawValue] ?? []
    }
    var hasAnyRanking: Bool {
        rankingsByFormat?.values.contains { !$0.isEmpty } ?? false
    }
    mutating func setRankings(_ rows: [GroupRanking], format: GroupFormat) {
        if rankingsByFormat == nil { rankingsByFormat = [:] }
        rankingsByFormat?[format.rawValue] = rows
    }
}
nonisolated struct GroupAccountCache: Codable, Sendable {
    var groups: [ScoreGroup] = []; var pending: [GroupJoinRequest] = []; var details: [String: GroupDetailCache] = [:]; var syncedAt: Date? = nil
    var capabilities: GroupCapabilities? = nil
    var notices: [GroupNotification]? = nil
    var unreadCount: Int? = nil
}

@MainActor @Observable final class GroupStore {
    static let shared = GroupStore()
    var repository = GroupRepository()
    private(set) var cache = GroupAccountCache()
    private(set) var accountID: String?
    private(set) var identityRevision = 0
    private(set) var loading = false
    /// 组内写操作在飞（对齐安卓 `GroupDetailViewModel.mutating`）：顶栏菜单整体禁用，防重复提交。
    /// 用计数器而非布尔，因为多个页面可以并发发起写操作。
    private(set) var mutating = false
    private var mutationCount = 0
    private(set) var cached = false
    private(set) var enabled = UserDefaults.standard.object(forKey: "groups.enabled") as? Bool ?? true
    private(set) var capabilities: GroupCapabilities?
    var error: String?
    private(set) var detailErrors: [String: String] = [:]
    /// 排行榜按「小组 + 赛制」独立记错，对应安卓 sectionErrors[SINGLES_RANK/DOUBLES_RANK]，
    /// 这样单项失败不会把整页判成失败，也不至于让空榜看起来像「还没有比赛」。
    private(set) var rankErrors: [String: String] = [:]
    private var detailRequests: [String: Int] = [:]
    private var rankRequests: [String: Int] = [:]
    private var requestedRankFormats: [String: GroupFormat] = [:]
    private var refreshing = false
    private var syncRunning = false
    private var syncRequested = false
    private var retryTask: Task<Void, Never>?
    private var historyRequests: [String: Int] = [:]
    private(set) var historyRows: [String: [GroupResult]] = [:]
    private(set) var historyCursors: [String: String] = [:]
    private(set) var notices: [GroupNotification] = []
    private(set) var unreadCount = 0
    private(set) var noticeError: String? = nil
    private(set) var noticesLoading = false
    private(set) var noticesMarkingAll = false
    private var noticeCursor: String?
    var hasMoreNotices: Bool { noticeCursor != nil }
    private var noticeRequest = 0
    private var confirmedSeen = GroupNoticeReadReceipts()
    #if DEBUG
    private var preparedUITestDrafts = false
    #endif
    private let defaults = UserDefaults.standard
    private let connectivity = NWPathMonitor()
    private let signedInAccountID: @MainActor () -> String?

    init(observeConnectivity: Bool = true, signedInAccountID: @escaping @MainActor () -> String? = { SessionStore.shared.user?.id }) {
        self.signedInAccountID = signedInAccountID
        guard observeConnectivity else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") { return }
        #endif
        connectivity.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        connectivity.start(queue: DispatchQueue(label: "groups.connectivity"))
    }

    var groups: [ScoreGroup] { cache.groups }
    var pending: [GroupJoinRequest] { cache.pending }
    var hasIdentity: Bool { accountID != nil }
    private(set) var uploadRevision = 0
    var uploads: [GroupPendingUpload] {
        #if DEBUG
        if GroupCaptureFixture.enabled { return GroupCaptureFixture.pendingUploads() }
        #endif
        let _ = uploadRevision; return GroupLocalPersistence.shared.uploads(accountID: accountID)
    }

    func sessionDidChange(userID: String?) {
        if accountID == userID { return }
        if let previous = accountID { GroupLocalPersistence.shared.removeCache(accountID: previous) }
        retryTask?.cancel(); retryTask = nil
        historyRequests.removeAll(); historyRows.removeAll(); historyCursors.removeAll()
        noticeRequest += 1; notices = []; unreadCount = 0; noticeCursor = nil; confirmedSeen.removeAll()
        noticeError = nil; noticesLoading = false; noticesMarkingAll = false
        mutationCount = 0; mutating = false
        GroupActivityReminder.shared.clearAccount(previous: accountID)
        identityRevision &+= 1
        detailErrors.removeAll(); rankErrors.removeAll(); rankRequests.removeAll(); requestedRankFormats.removeAll()
        accountID = userID
        capabilities = nil
        defaults.set(userID, forKey: "groups.lastAccountID")
        cache = userID.flatMap { GroupLocalPersistence.shared.loadCache(accountID: $0) } ?? .init()
        capabilities = cache.capabilities; notices = cache.notices ?? []; unreadCount = cache.unreadCount ?? 0
        error = nil; cached = cache.syncedAt != nil
    }
    func matchesIdentity(_ id: String, revision: Int) -> Bool {
        accountID == id && identityRevision == revision
    }

    func allows(_ action: String) -> Bool { enabled && capabilities?.allows(action) == true }
    private func restoreIdentity() async {
        if let id = SessionStore.shared.user?.id { sessionDidChange(userID: id) }
        else if accountID == nil, await AuthTokenStore.shared.authToken() != nil, let id = defaults.string(forKey: "groups.lastAccountID") {
            accountID = id; cache = GroupLocalPersistence.shared.loadCache(accountID: id) ?? .init(); cached = cache.syncedAt != nil
        }
    }
    func refreshFeatureFlag() async {
        #if DEBUG
        if GroupCaptureFixture.enabled { enabled = true; return }
        #endif
        nonisolated struct Config: Decodable, Sendable { var groupsEnabled: Bool }
        if let config: Config = try? await APIClient.shared.request("/api/client-config/app-recommendations", timeout: 8, retries: 0) {
            enabled = config.groupsEnabled
            defaults.set(enabled, forKey: "groups.enabled")
        }
    }
    func refresh() async {
        #if DEBUG
        if loadUITestFixtureIfRequested() { return }
        #endif
        guard !refreshing else { return }
        let startingIdentityRevision = identityRevision
        refreshing = true
        defer {
            refreshing = false
            if identityRevision != startingIdentityRevision, enabled, SessionStore.shared.isAuthenticated {
                Task { await self.refresh() }
            }
        }
        await restoreIdentity(); await refreshFeatureFlag()
        guard enabled, let id = accountID, SessionStore.shared.user?.id == id else { return }
        let revision = identityRevision
        loading = true; defer { loading = false }
        // 首页铃铛独立更新，列表或申请读取失败也不阻塞通知提醒。
        async let noticeRefresh = loadNotices()
        do {
            let authRevision = await repository.client.authSessionRevision()
            guard matchesIdentity(id, revision: revision) else { return }
            async let list: GroupPage<ScoreGroup> = repository.read("", expectedAuthRevision: authRevision)
            async let requests: GroupPage<GroupJoinRequest> = repository.read("/join-requests/mine", expectedAuthRevision: authRevision)
            async let flags: GroupCapabilities = repository.read("/capabilities", expectedAuthRevision: authRevision)
            let (groups, pending, flagsValue) = try await (list, requests, flags)
            guard matchesIdentity(id, revision: revision) else { return }
            cache.groups = groups.items.sorted { lhs, rhs in lhs.isActive != rhs.isActive ? lhs.isActive : lhs.updatedAt > rhs.updatedAt }; cache.pending = pending.items; cache.syncedAt = Date()
            cached = false; error = nil; saveCache()
            capabilities = flagsValue; cache.capabilities = flagsValue; saveCache()
            await sync()
        } catch {
            guard matchesIdentity(id, revision: revision) else { return }
            self.error = groupErrorMessage(error); cached = cache.syncedAt != nil
        }
        _ = await noticeRefresh
    }
    /// Refresh only the group profile while moderation is pending; keep roster and scroll state intact.
    func refreshModeration(_ groupID: String) async {
        guard enabled, let id = accountID, id == SessionStore.shared.user?.id,
              let before = cache.details[groupID]?.group,
              !(before.pendingName ?? "").isEmpty || !(before.pendingDescription ?? "").isEmpty else { return }
        let revision = identityRevision, sequence = detailRequests[groupID]
        do {
            let authRevision = await repository.client.authSessionRevision()
            let updated: ScoreGroup = try await repository.read("/\(groupID)", expectedAuthRevision: authRevision)
            guard !Task.isCancelled, matchesIdentity(id, revision: revision), enabled, !mutating,
                  detailRequests[groupID] == sequence, cache.details[groupID]?.group.revision == before.revision,
                  updated.revision >= before.revision, await repository.client.authSessionRevision() == authRevision else { return }
            cache.details[groupID]?.group = updated
            if let index = cache.groups.firstIndex(where: { $0.id == groupID }) { cache.groups[index] = updated }
            saveCache()
        } catch { /* The visible page remains usable; retries have a fixed budget. */ }
    }

    /// Publish confirmed additions without reinitializing the match or schedule draft.
    func acceptTemporaryMember(_ member: GroupMember, groupID: String, accountID: String, identity: Int) -> Bool {
        guard matchesIdentity(accountID, revision: identity), member.groupId == groupID,
              member.kind == "temporary", cache.details[groupID] != nil else { return false }
        if cache.details[groupID]?.members.contains(where: { $0.id == member.id }) == false {
            detailRequests[groupID] = (detailRequests[groupID] ?? 0) + 1
            cache.details[groupID]?.members.append(member)
            saveCache()
        }
        return true
    }

    func loadDetail(_ groupID: String, format: GroupFormat = .singles) async {
        #if DEBUG
        if loadUITestFixtureIfRequested() { return }
        #endif
        guard enabled, let id = accountID, SessionStore.shared.user?.id == id else { return }
        let revision = identityRevision
        let sequence = (detailRequests[groupID] ?? 0) + 1
        detailRequests[groupID] = sequence
        do {
            let authRevision = await repository.client.authSessionRevision()
            let g: ScoreGroup = try await repository.read("/\(groupID)", expectedAuthRevision: authRevision)
            async let members: [GroupMember]? = try? await repository.allPages("/\(groupID)/members", expectedAuthRevision: authRevision)
            async let activities: [GroupActivity]? = try? await repository.allPages("/\(groupID)/activities", expectedAuthRevision: authRevision)
            async let results: GroupPage<GroupResult>? = try? await repository.results(groupID, expectedAuthRevision: authRevision)
            async let pending: [GroupResult]? = try? await repository.allPages("/\(groupID)/results", query: [.init(name: "status", value: "pending_confirmation")], expectedAuthRevision: authRevision)
            async let stats: GroupStats? = try? await repository.read("/\(groupID)/stats", expectedAuthRevision: authRevision)
            let (m,a,r,p,s) = await (members,activities,results,pending,stats)
            guard matchesIdentity(id, revision: revision), detailRequests[groupID] == sequence, !Task.isCancelled,
                  await repository.client.authSessionRevision() == authRevision else { return }
            let old = cache.details[groupID]
            cache.details[groupID] = .init(group: g, members: m ?? old?.members ?? [], activities: a ?? old?.activities ?? [], results: r?.items ?? old?.results ?? [], rankings: old?.rankings ?? [], stats: s ?? old?.stats, nextCursor: r?.nextCursor, syncedAt: Date(), trainingPlans: old?.trainingPlans, leaveNotices: old?.leaveNotices, pendingResults: p ?? old?.pendingResults, removedMembers: old?.removedMembers, trainingNotices: old?.trainingNotices, rankingsByFormat: old?.rankingsByFormat)
            if let role = g.myRole, let index = cache.details[groupID]?.members.firstIndex(where: { $0.accountId == id }) { cache.details[groupID]?.members[index].role = role }
            error = [m == nil, a == nil, r == nil, p == nil, s == nil].contains(true) ? groupText("partial_load", "Some sections could not refresh. Pull to retry.") : nil
            detailErrors[groupID] = error
            cached = false; saveCache()
            if let index = cache.groups.firstIndex(where: { $0.id == groupID }) { cache.groups[index] = g }
            if !g.isActive { GroupActivityReminder.shared.clearGroup(groupID, accountID: id) }
            if let me = m?.first(where: { $0.accountId == id }) {
                GroupActivityReminder.shared.synchronize(accountID: id, group: g, memberID: me.id, activities: a)
                if GroupPermissions.manager(me) {
                    let removed: [GroupMember]? = try? await repository.allPages("/\(groupID)/members", query: [.init(name: "status", value: "removed")], expectedAuthRevision: authRevision)
                    guard matchesIdentity(id, revision: revision), detailRequests[groupID] == sequence else { return }
                    cache.details[groupID]?.removedMembers = removed ?? old?.removedMembers
                }
            }
            if g.isCoaching {
                let mine = g.isCoach == false ? [URLQueryItem(name: "mine", value: "1")] : []
                async let plans: [GroupTrainingPlan]? = try? await repository.allPages("/\(groupID)/training-plans", query: mine, expectedAuthRevision: authRevision)
                async let leaves: [GroupLeaveNotice]? = try? await repository.allPages("/\(groupID)/leave-notices", expectedAuthRevision: authRevision)
                async let notices: [GroupTrainingNotice]? = try? await repository.allPages("/\(groupID)/training-notices", expectedAuthRevision: authRevision)
                let (p,n,t) = await (plans,leaves,notices)
                guard matchesIdentity(id, revision: revision), detailRequests[groupID] == sequence, !Task.isCancelled,
                      await repository.client.authSessionRevision() == authRevision else { return }
                cache.details[groupID]?.trainingPlans = p ?? old?.trainingPlans
                cache.details[groupID]?.leaveNotices = n ?? old?.leaveNotices
                cache.details[groupID]?.trainingNotices = t ?? old?.trainingNotices
                if p == nil || n == nil || t == nil { error = groupText("partial_load", "Some sections could not refresh. Pull to retry.") }
                detailErrors[groupID] = error
                saveCache()
            }
            let selected = requestedRankFormats[groupID] ?? format
            await loadRankings(groupID, format: selected, select: false)
            guard matchesIdentity(id, revision: revision), !Task.isCancelled else { return }
            for other in GroupFormat.allCases where other != selected {
                await loadRankings(groupID, format: other, select: false)
            }
        } catch {
            guard matchesIdentity(id, revision: revision), detailRequests[groupID] == sequence else { return }
            self.error = groupErrorMessage(error); cached = cache.details[groupID] != nil
            detailErrors[groupID] = groupErrorMessage(error)
            if case APIClientError.server(status: 404, code: _, message: _, nextAvailableAt: _) = error {
                forgetGroup(groupID)
            }
        }
    }
    func loadRankings(_ groupID: String, format: GroupFormat, select: Bool = true) async {
        #if DEBUG
        if GroupCaptureFixture.enabled {
            do { cache.details[groupID]?.setRankings(try GroupCaptureFixture.rankings(groupID, format: format), format: format) }
            catch { self.error = error.localizedDescription }
            return
        }
        #endif
        #if DEBUG
        if loadUITestFixtureIfRequested() { return }
        #endif
        guard enabled, let id = accountID, SessionStore.shared.user?.id == id else { return }
        let revision = identityRevision
        if select { requestedRankFormats[groupID] = format }
        let key = Self.rankKey(groupID, format: format)
        let sequence = (rankRequests[key] ?? 0) + 1
        rankRequests[key] = sequence
        do {
            let ranks: GroupPage<GroupRanking> = try await repository.read("/\(groupID)/rankings", query: [.init(name: "format", value: format.rawValue)])
            guard matchesIdentity(id, revision: revision), rankRequests[key] == sequence, !Task.isCancelled else { return }
            cache.details[groupID]?.setRankings(ranks.items, format: format)
            if (requestedRankFormats[groupID] ?? .singles) == format { cache.details[groupID]?.rankings = ranks.items }
            rankErrors[key] = nil; saveCache()
        } catch {
            guard matchesIdentity(id, revision: revision), rankRequests[key] == sequence else { return }
            // 排行榜失败不该污染整页 error：安卓只把失败记在该 section 上。
            rankErrors[key] = groupErrorMessage(error)
        }
    }
    /// 排行榜错误键：小组 + 赛制，避免两个赛制互相覆盖。
    nonisolated static func rankKey(_ groupID: String, format: GroupFormat) -> String { groupID + ":" + format.rawValue }
    func loadMore(_ groupID: String) async {
        guard let cursor = cache.details[groupID]?.nextCursor else { return }
        guard let id = accountID, SessionStore.shared.user?.id == id else { return }
        let revision = identityRevision
        do {
            let authRevision = await repository.client.authSessionRevision()
            guard matchesIdentity(id, revision: revision) else { return }
            let page = try await repository.results(groupID, cursor: cursor, expectedAuthRevision: authRevision)
            guard matchesIdentity(id, revision: revision), cache.details[groupID]?.nextCursor == cursor else { return }
            let old = Set(cache.details[groupID]?.results.map(\.id) ?? [])
            cache.details[groupID]?.results.append(contentsOf: page.items.filter { !old.contains($0.id) })
            cache.details[groupID]?.nextCursor = page.nextCursor; saveCache()
        } catch { if matchesIdentity(id, revision: revision) { self.error = groupErrorMessage(error) } }
    }
    private func saveCache() { if let accountID { try? GroupLocalPersistence.shared.saveCache(cache, accountID: accountID) } }
    func perform(_ operation: () async throws -> Void) async -> Bool {
        guard (capabilities?.minClientContractVersion ?? 1) <= 1 else { error = groupText("capabilities_missing", "Match rules are unavailable. Connect and retry."); return false }
        guard enabled, let id = accountID, signedInAccountID() == id else { error = groupText("need_login", "Please sign in to continue."); return false }
        let revision = identityRevision
        mutationCount += 1; mutating = true
        defer {
            if matchesIdentity(id, revision: revision) {
                mutationCount = max(0, mutationCount - 1); mutating = mutationCount > 0
            }
        }
        do {
            let authRevision = await repository.client.authSessionRevision()
            guard matchesIdentity(id, revision: revision) else { return false }
            try await GroupRequestIdentity.$authRevision.withValue(authRevision) {
                try await GroupRequestIdentity.$capabilities.withValue(capabilities) { try await operation() }
            }
            guard matchesIdentity(id, revision: revision), await repository.client.authSessionRevision() == authRevision else { return false }
            error = nil; return true
        } catch {
            if matchesIdentity(id, revision: revision) { self.error = groupErrorMessage(error) }
            return false
        }
    }
    func sync() async {
        #if DEBUG
        if GroupCaptureFixture.enabled { return }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") { return }
        #endif
        if syncRunning { syncRequested = true; return }
        guard enabled, capabilities?.allows("submit_result") != false, let id = accountID, SessionStore.shared.user?.id == id else { return }
        let revision = identityRevision
        syncRunning = true; retryTask?.cancel(); retryTask = nil
        defer { syncRunning = false; uploadRevision += 1; scheduleRetry(); if identityRevision != revision { Task { await self.sync() } } }
        let authRevision = await repository.client.authSessionRevision()
        guard matchesIdentity(id, revision: revision) else { return }
        GroupLocalPersistence.shared.repairOutbox(from: ScoreboardRecordManager.shared.loadAllRecords())
        var attempted = Set<String>(), changed = Set<String>()
        repeat {
            syncRequested = false
            let rows = GroupLocalPersistence.shared.uploads(accountID: id).filter { $0.failure == nil && ($0.nextAttemptAt ?? .distantPast) <= Date() && !attempted.contains($0.id) }
            for upload in rows {
                guard enabled, SessionStore.shared.user?.id == id, matchesIdentity(id, revision: revision), await repository.client.authSessionRevision() == authRevision else { return }
                attempted.insert(upload.id)
                do {
                    let result: GroupResult = try await repository.write("/\(upload.groupID)/results", body: upload.body, key: upload.key, expectedAuthRevision: authRevision)
                    try GroupLocalPersistence.shared.markUploaded(upload.id, accountID: id, resultID: result.id)
                    changed.insert(upload.groupID)
                } catch {
                    if error is CancellationError { return }
                    guard matchesIdentity(id, revision: revision) else { return }
                    var terminal = false, code: String?, next: Date?
                    let context = error as? APIClientServerContextError
                    let underlying: Error = context?.underlying ?? error
                    if case APIClientError.server(let status, let serverCode, _, let available) = underlying {
                        code = serverCode
                        terminal = (400...499).contains(status) && ![401,408,429].contains(status)
                        if let available { next = APIDateParser.date(from: available) }
                    }
                    let delay = min(300.0, pow(2.0, Double(min(upload.attempts ?? 0, 6))) * 5)
                    try? GroupLocalPersistence.shared.updateRetry(upload.id, accountID: id, code: code, failure: terminal ? code ?? "UPLOAD_FAILED" : nil, next: terminal ? nil : next ?? Date().addingTimeInterval(delay), existingResultID: context?.currentResultID)
                    self.error = groupErrorMessage(error)
                }
            }
        } while syncRequested || GroupLocalPersistence.shared.uploads(accountID: id).contains(where: { $0.failure == nil && ($0.nextAttemptAt ?? .distantPast) <= Date() && !attempted.contains($0.id) })
        for group in changed { await loadDetail(group, format: requestedRankFormats[group] ?? .singles) }
    }
    private func scheduleRetry() {
        guard capabilities?.allows("submit_result") != false else { return }
        guard enabled, let id = accountID, SessionStore.shared.user?.id == id,
              let next = uploads.filter({ $0.failure == nil }).compactMap(\.nextAttemptAt).min() else { return }
        let revision = identityRevision
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) } catch { return }
            guard let self, self.matchesIdentity(id, revision: revision) else { return }
            await self.sync()
        }
    }
    func retryUpload(_ id: String) async {
        if let accountID { try? GroupLocalPersistence.shared.updateRetry(id, accountID: accountID, code: nil, failure: nil, next: nil) }
        await sync()
    }
    func queuedResult(_ body: GroupResultBody, groupID: String, id: String, key: String) throws {
        guard enabled, let accountID, SessionStore.shared.user?.id == accountID else { throw GroupFlowError.staleSession }
        try GroupLocalPersistence.shared.enqueueManual(body, id: id, accountID: accountID, groupID: groupID, key: key)
        uploadRevision += 1
        Task { await self.sync() }
    }
    func forgetGroup(_ groupID: String) {
        guard let accountID else { return }
        try? GroupLocalPersistence.shared.forgetGroup(groupID, accountID: accountID)
        cache.groups.removeAll { $0.id == groupID }; cache.details.removeValue(forKey: groupID)
        historyRows = historyRows.filter { !$0.key.hasPrefix(groupID + ":") }; historyCursors = historyCursors.filter { !$0.key.hasPrefix(groupID + ":") }
        detailRequests[groupID, default: 0] += 1; historyRequests[groupID, default: 0] += 1
        GroupActivityReminder.shared.clearGroup(groupID, accountID: accountID); saveCache()
    }
    func loadHistory(_ groupID: String, format: GroupFormat?, more: Bool = false) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") { return }
        #endif
        guard let id = accountID else { return }
        let revision = identityRevision, key = groupID + ":" + (format?.rawValue ?? "all")
        if more && historyCursors[key] == nil { return }
        let cursor = more ? historyCursors[key] : nil
        historyRequests[groupID, default: 0] += 1; let sequence = historyRequests[groupID]
        do {
            let page = try await repository.results(groupID, cursor: cursor, format: format)
            guard matchesIdentity(id, revision: revision), historyRequests[groupID] == sequence else { return }
            guard page.nextCursor == nil || page.nextCursor != cursor else { throw GroupFlowError.repeatedCursor }
            var rows = more ? historyRows[key] ?? [] : []
            let ids = Set(rows.map(\.id)); rows.append(contentsOf: page.items.filter { !ids.contains($0.id) })
            historyRows[key] = rows; historyCursors[key] = page.nextCursor
        } catch { if matchesIdentity(id, revision: revision), historyRequests[groupID] == sequence { self.error = groupErrorMessage(error) } }
    }
    @discardableResult func loadNotices(more: Bool = false) async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") { return true }
        #endif
        guard !Task.isCancelled, enabled, let id = accountID, SessionStore.shared.user?.id == id else { return false }
        let revision = identityRevision; noticeRequest += 1; let sequence = noticeRequest
        noticesLoading = true
        do {
            var query = [URLQueryItem(name: "limit", value: "50")]
            if more, let noticeCursor { query.append(.init(name: "cursor", value: noticeCursor)) }
            let page: GroupNoticePage = try await repository.read("/notices", query: query)
            guard matchesIdentity(id, revision: revision), noticeRequest == sequence else { return false }
            if more, page.nextCursor != nil, page.nextCursor == noticeCursor { throw GroupFlowError.repeatedCursor }
            var rows = more ? notices : []; let ids = Set(rows.map(\.id))
            rows.append(contentsOf: page.items.filter { !ids.contains($0.id) }.map { confirmedSeen.applying(to: $0) })
            notices = rows; noticeCursor = page.nextCursor
            let pageUnread = max(0, page.unreadCount - confirmedSeen.staleUnreadCount(in: page.items))
            unreadCount = more ? min(unreadCount, pageUnread) : pageUnread
            cache.notices = notices; cache.unreadCount = unreadCount; saveCache()
            noticeError = nil; noticesLoading = false
            return true
        } catch {
            guard matchesIdentity(id, revision: revision), noticeRequest == sequence else { return false }
            noticeError = groupErrorMessage(error); noticesLoading = false
            return false
        }
    }
    /// Mirrors the Android inbox: the response has to echo the acknowledged notice and carry a server
    /// timestamp, and the row is replaced with what the server returned rather than a local estimate.
    @discardableResult func markNoticeSeen(_ notice: GroupNotification) async -> Bool {
        guard !Task.isCancelled, enabled, let id = accountID, SessionStore.shared.user?.id == id else { return false }
        let revision = identityRevision
        do {
            let updated: GroupNotification = try await repository.write("/notices/\(notice.id)/seen")
            guard matchesIdentity(id, revision: revision) else { return false }
            guard updated.isReceipt(for: notice) else { throw GroupFlowError.invalidReceipt }
            // Reads already in flight predate this acknowledgement and cannot restore its badge.
            noticeRequest += 1; noticesLoading = false; confirmedSeen.record(updated)
            if notices.contains(where: { $0.id == updated.id && $0.seenAt == nil }) { unreadCount = max(0, unreadCount - 1) }
            notices = notices.map { $0.id == updated.id ? updated : $0 }
            cache.notices = notices; cache.unreadCount = unreadCount; saveCache()
            noticeError = nil
            return true
        } catch {
            if matchesIdentity(id, revision: revision) { noticeError = groupErrorMessage(error) }
            return false
        }
    }
    /// 单一批次固定发起时的账号与会话版本；失败即停，按游标处理到末页。
    func markAllNoticesSeen() async {
        guard !noticesMarkingAll, !noticesLoading, enabled, let id = accountID,
              SessionStore.shared.user?.id == id else { return }
        let revision = identityRevision
        noticesMarkingAll = true
        defer { if matchesIdentity(id, revision: revision) { noticesMarkingAll = false } }
        var visitedCursors = Set<String>()
        while !Task.isCancelled, enabled, matchesIdentity(id, revision: revision), SessionStore.shared.user?.id == id {
            if let target = notices.first(where: { $0.seenAt == nil }) {
                guard await markNoticeSeen(target) else { return }
                continue
            }
            guard let cursor = noticeCursor, !noticesLoading else { return }
            guard visitedCursors.insert(cursor).inserted else {
                noticeError = groupErrorMessage(GroupFlowError.repeatedCursor)
                return
            }
            guard await loadNotices(more: true) else { return }
        }
    }

}

#if DEBUG
extension GroupStore {
    func loadUITestFixtureIfRequested() -> Bool {
        if GroupCaptureFixture.enabled {
            do {
                let snapshot = try GroupCaptureFixture.makeCache()
                accountID = GroupCaptureFixture.accountID; enabled = true
                cached = GroupCaptureFixture.nativeScene == "detail-offline"; error = nil
                if !preparedUITestDrafts {
                    preparedUITestDrafts = true
                    let keys = ["match:seed_group_badminton:free:true", "match:seed_group_badminton:free:false", "match:seed_group_badminton:compare_activity_session_1:true", "match:seed_group_badminton:compare_activity_session_2:true", "schedule:seed_group_badminton:compare_activity_multi", "schedule:compare_group_training:compare_training_plan", "schedule:compare_group_training:new"]
                    for key in keys { GroupLocalPersistence.shared.removeDraft(key: key, accountID: GroupCaptureFixture.accountID) }
                }
                cache = snapshot; capabilities = snapshot.capabilities
                detailErrors.removeAll()
                if GroupCaptureFixture.nativeScene == "detail-failure" {
                    cache.details.removeValue(forKey: GroupCaptureFixture.groupID)
                    detailErrors[GroupCaptureFixture.groupID] = groupText("load_failed", "Could not load the group")
                }
                notices = snapshot.notices ?? []; unreadCount = snapshot.unreadCount ?? 0
                return true
            } catch { self.error = error.localizedDescription; return true }
        }
        guard ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") else { return false }
        if !preparedUITestDrafts, ProcessInfo.processInfo.arguments.contains("-UITestGroupsFreshDrafts") {
            preparedUITestDrafts = true
            GroupLocalPersistence.shared.removeDraft(key: "match:ui-group:free:true", accountID: "ui-test-user")
        }
        accountID = "ui-test-user"; enabled = true; cached = false; error = nil
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var group = ScoreGroup(id: "ui-group", groupNo: "12345678", name: "球友小组", description: "一起打球，积累共同战绩", sport: .badminton, status: "active", joinPolicy: "approval", ownerMemberId: "ui-a", memberLimit: 100, createdAt: now, updatedAt: now, revision: 1, memberCount: 4, myRole: "owner", currentMonthMatchCount: 1, activeMemberCount30d: 4)
        var members = ["甲", "乙", "丙", "丁"].enumerated().map { i,name in GroupMember(id: "ui-" + String(UnicodeScalar(97 + i)!), groupId: group.id, kind: i == 0 ? "account" : "temporary", role: i == 0 ? "owner" : "member", status: "active", displayName: name, accountId: i == 0 ? "ui-test-user" : "", joinedAt: now) }
        let activity = GroupActivity(id: "ui-activity", groupId: group.id, title: "周末羽毛球", startsAt: now + 86400000, place: "体育馆", capacity: 8, note: "欢迎报名", format: .doubles, status: "recruiting", creatorMemberId: "ui-a", registeredMemberIds: members.map(\.id), gameId: "", createdAt: now, revision: 1)
        let rules = GroupMatchRules(sport: .badminton, maxSets: 2, matchCompletionMode: "play_all", pointsToWinSet: 21, pointCap: 30, winByTwo: true, useRallyScoring: false, gamesPerSet: 6, tieBreakPoints: 7, setScoringMode: "regular", usesNoAdScoring: false)
        capabilities = .init(groupNoLength: 6, nameMin: 2, nameMax: 24, descriptionMax: 200, memberLimitDefault: 30, memberLimitMax: 50, ruleSchemaVersion: 1, supportsDraws: true)
        capabilities?.groupTypes = ProcessInfo.processInfo.arguments.contains("-UITestGroupsAllTypes") ? ["peer", "coaching"] : ["peer"]
        capabilities?.supportsActivityLineup = true
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsActivitiesDisabled") {
            capabilities?.allowedActions = ["create_group", "join_group", "start_game", "submit_result", "confirm_result", "void_result", "manage_group", "manage_members", "register_activity"]
        }
        capabilities?.sports = GroupSport.allCases.map { sport in
            var value = rules; value.sport = sport; value.maxSets = sport == .tableTennis ? 5 : 3; value.matchCompletionMode = "best_of"
            value.pointsToWinSet = sport == .badminton ? 21 : sport == .tennis ? 6 : 11
            return .init(sport: sport, defaultRules: value, ruleOptions: .init(maxSets: [1,3,5], matchCompletionModes: ["best_of", "play_all"], pointsToWinSet: [7,11,15,21], winByTwo: [true,false], useRallyScoring: [true,false], gamesPerSet: [4,6], tieBreakPoints: [7,10], setScoringModes: ["regular", "tiebreak_only"], usesNoAdScoring: [false,true]), supportsCustomRules: true)
        }
        notices = [.init(id: "ui-notice", groupId: group.id, groupName: group.name, kind: "activity_changed", resourceId: activity.id, title: "周末羽毛球已改期", reason: "场馆调整", createdAt: now, seenAt: nil)]; unreadCount = 1
        let result = GroupResult(id: "ui-result", groupId: group.id, activityId: "", gameId: "ui-game", format: .singles, sport: .badminton, bestOf: 2, setScore: .init(a: 1,b: 1), sets: [.init(a: 21,b: 19),.init(a: 18,b: 21)], winnerSide: nil, outcome: "draw", rules: rules, participants: [.init(memberId: "ui-a",side: "A",seat: 0,displayName: "甲"),.init(memberId: "ui-b",side: "B",seat: 0,displayName: "乙")], playedAt: now, submitterMemberId: "ui-a", confirmedByMemberId: "ui-b", status: "confirmed", source: "scoreboard", reason: "", createdAt: now, revision: 1)
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsCoaching") {
            group.groupType = "coaching"
            members = members.enumerated().map { index, value in var member = value; member.kind = "account"; member.accountId = index == 0 ? "ui-test-user" : "ui-student-\(index)"; return member }
        }
        cache.groups = [group]
        cache.details[group.id] = .init(group: group, members: members, activities: [activity], results: [result], rankings: [.init(memberId: "ui-a",displayName: "甲",games: 1,wins: 0,losses: 0,draws: 1,setsWon: 1,setsLost: 1,winRateText: "—",rank: 1)], stats: .init(confirmedMatchCount: 1,currentMonthMatchCount: 1,activeMemberCount30d: 2,lastCompletedAt: now), nextCursor: nil, syncedAt: Date())
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsMulti") {
            var multi = activity; multi.matchMode = "multi"; multi.sessionCount = 1
            cache.details[group.id]?.activities = [multi]
            var session = GroupActivitySession(id: "ui-activity-session", activityId: multi.id, groupId: group.id, orderNo: 1, court: "1 号场", startsAt: multi.startsAt, endsAt: multi.startsAt + 1800000, format: .doubles, status: "scheduled", seats: members.enumerated().map { i, m in .init(memberId: m.id, side: i < 2 ? "A" : "B", seat: i % 2, displayName: m.displayName) }, resultId: "", startedGameId: "", frozenGameId: "", mySide: "A", needsLineup: false, isFrozen: false, canCorrectResult: false)
            if ProcessInfo.processInfo.arguments.contains("-UITestGroupsMissingLineup") {
                session.seats.removeLast(); session.needsLineup = true
                multi.registeredMemberIds.removeLast(); cache.details[group.id]?.activities = [multi]
            }
            cache.details[group.id]?.activityLineups = [multi.id: .init(activityId: multi.id, matchMode: "multi", sessionMinutes: 30, revision: 1, canManage: true, sessions: [session])]
        }
        let fixtureRanks = cache.details[group.id]?.rankings ?? []
        cache.details[group.id]?.setRankings(fixtureRanks, format: .singles)
        cache.details[group.id]?.setRankings([], format: .doubles)
        if group.isCoaching {
            let session = GroupTrainingSession(id: "ui-training", planId: "ui-plan", groupId: group.id, orderNo: 1, court: "1 号场", startsAt: now + 3600000, endsAt: now + 6300000, format: .doubles, status: "scheduled", resultId: "", seats: members.enumerated().map { index, member in .init(memberId: member.id, side: index < 2 ? "A" : "B", seat: index % 2, displayName: member.displayName) }, mySide: "A")
            cache.details[group.id]?.trainingPlans = [.init(id: "ui-plan", groupId: group.id, creatorMemberId: "ui-a", trainingDate: now, startsAt: session.startsAt, endsAt: session.endsAt, sessionMinutes: 45, place: "体育馆", note: "训练排期", status: "published", cancelReason: "", publishedAt: now, sessionCount: 1, mySessionCount: 1, sessions: [session], createdAt: now, revision: 1)]
            cache.details[group.id]?.leaveNotices = [.init(id: "ui-leave", groupId: group.id, planId: "ui-plan", sessionId: session.id, memberId: "ui-b", reason: "临时有事", status: "open", createdAt: now)]
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsEmpty") {
            cache.details[group.id]?.activities = []; cache.details[group.id]?.results = []; cache.details[group.id]?.rankings = []; cache.details[group.id]?.rankingsByFormat = [:]
            cache.details[group.id]?.trainingPlans = []; cache.details[group.id]?.leaveNotices = []
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsNoRankings") || ProcessInfo.processInfo.arguments.contains("-UITestGroupsRankError") {
            cache.details[group.id]?.rankings = []; cache.details[group.id]?.rankingsByFormat = [:]
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsRankError") {
            for format in GroupFormat.allCases { rankErrors[Self.rankKey(group.id, format: format)] = groupText("load_failed", "Could not load the group") }
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsInviteOnly") {
            cache.details[group.id]?.members = Array(members.prefix(1)); cache.details[group.id]?.group.memberCount = 1
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsOnlyTemporary") {
            cache.details[group.id]?.members = Array(members.prefix(1)) + [GroupMember(id: "ui-temp", groupId: group.id, kind: "temporary", role: "member", status: "active", displayName: "临时队友", accountId: "", joinedAt: now)]
            cache.details[group.id]?.group.memberCount = 2
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsNoHistory") {
            cache.details[group.id]?.results = []; cache.details[group.id]?.pendingResults = []
            cache.details[group.id]?.stats?.confirmedMatchCount = 0
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsStudent") {
            cache.details[group.id]?.members[0].role = "member"; cache.details[group.id]?.group.ownerMemberId = "ui-b"
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsArchived") { cache.details[group.id]?.group.status = "archived" }
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsDissolving") { cache.details[group.id]?.group.status = "dissolving"; cache.details[group.id]?.group.dissolveAt = now + 604800000 }
        cache.groups = ProcessInfo.processInfo.arguments.contains("-UITestGroupsListEmpty") ? [] : [cache.details[group.id]?.group ?? group]
        return true
    }
}
#endif
