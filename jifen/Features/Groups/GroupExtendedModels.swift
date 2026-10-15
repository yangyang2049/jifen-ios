import Foundation

nonisolated struct GroupSportCapability: Codable, Sendable {
    var sport: GroupSport
    var defaultRules: GroupMatchRules?
    var ruleOptions: GroupRuleOptions?
    var supportsCustomRules: Bool?
    var seats: [String: Int]? = nil
    var bestOfOptions: [Int]? = nil
}

nonisolated struct GroupRuleOptions: Codable, Sendable {
    var maxSets: [Int]?
    var matchCompletionModes: [String]?
    var pointsToWinSet: [Int]?
    var winByTwo: [Bool]?
    var useRallyScoring: [Bool]?
    var gamesPerSet: [Int]?
    var tieBreakPoints: [Int]?
    var setScoringModes: [String]?
    var usesNoAdScoring: [Bool]?
}

nonisolated struct GroupActivitySession: Codable, Identifiable, Sendable {
    var id: String
    var activityId: String
    var groupId: String
    var orderNo: Int
    var court: String
    var startsAt: Int64
    var endsAt: Int64
    var format: GroupFormat
    var status: String
    var seats: [GroupSeat]
    var resultId: String?
    var startedGameId: String?
    var frozenGameId: String?
    var mySide: String?
    var needsLineup: Bool?
    var isFrozen: Bool?
    var canCorrectResult: Bool?
    var frozen: Bool { isFrozen == true || !(startedGameId ?? "").isEmpty || !(resultId ?? "").isEmpty || status != "scheduled" }
    var gameID: String? { [startedGameId, frozenGameId].compactMap { $0 }.first { !$0.isEmpty } }
    var date: Date { Date(timeIntervalSince1970: Double(startsAt) / 1000) }
}

nonisolated struct GroupActivityLineup: Codable, Sendable {
    var activityId: String
    var matchMode: String
    var timingMode: String? = nil
    var sessionMinutes: Int
    var revision: Int64
    var canManage: Bool
    var sessions: [GroupActivitySession]
    /// 排赛时间模式：`sequence` 按顺序、`estimated` 预计时间（服务端缺省）。
    var isSequenced: Bool { timingMode == "sequence" }
}

nonisolated struct GroupLineupBody: Encodable, Sendable {
    var timingMode: String
    var sessionMinutes: Int
    var sessions: [GroupTrainingSessionBody]
}

/// 直接排赛（安卓 `CreateDirectLineupBody`）：一次请求建活动 + 建对阵场次。
nonisolated struct GroupDirectLineupBody: Codable, Sendable {
    var title: String
    var startsAt: Int64
    var place: String
    var format: GroupFormat
    var timingMode: String
    var sessionMinutes: Int
    var sessions: [GroupTrainingSessionBody]
}

nonisolated struct GroupDirectLineupResponse: Decodable, Sendable {
    var activityId: String
    var groupId: String
    var activity: GroupActivity?
    var revision: Int64?
}

nonisolated struct GroupNotification: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var groupId: String
    var groupName: String
    var kind: String
    var resourceId: String?
    var title: String
    var reason: String?
    var createdAt: Int64
    var seenAt: Int64?
}

nonisolated struct GroupNoticePage: Decodable, Sendable {
    var items: [GroupNotification]
    var nextCursor: String?
    var unreadCount: Int
}

nonisolated struct GroupTrainingNotice: Codable, Identifiable, Sendable {
    var id: String; var groupId: String; var memberId: String; var planId: String
    var kind: String; var trainingDate: Int64; var startsAt: Int64; var place: String
    var note: String; var reason: String; var createdAt: Int64; var seenAt: Int64?
}

nonisolated struct GroupReportStatus: Codable, Sendable {
    var reason: String; var detail: String?; var status: String
}
nonisolated struct GroupCurrentReport: Decodable, Sendable { var report: GroupReportStatus? }
nonisolated struct GroupConfirmBody: Encodable, Sendable { var authority: Bool }

/// Mirrors the domestic Android GroupOverviewProgress and action bar policy.
nonisolated struct GroupOverviewActions: Sendable {
    enum Action: String, Sendable { case invite, start, training, addResult }
    let actions: [Action]
    let canInvite: Bool
    let showSecondaryInvite: Bool
    let showStats: Bool
    let showLatestResults: Bool

    init(group: ScoreGroup, memberCount: Int, hasResults: Bool, confirmedMatchCount: Int, isCoach: Bool) {
        canInvite = group.isActive && ["open", "approval"].contains(group.joinPolicy) && memberCount < group.memberLimit
        showSecondaryInvite = memberCount >= 2 && canInvite
        showStats = confirmedMatchCount > 0
        showLatestResults = hasResults || confirmedMatchCount > 0
        guard group.isActive else { actions = []; return }
        guard memberCount >= 2 else { actions = [.invite]; return }
        let hasHistory = hasResults || confirmedMatchCount > 0
        let primary: Action = group.isCoaching ? .training : .start
        actions = hasHistory && (!group.isCoaching || isCoach) ? [.addResult, primary] : [primary]
    }
}

/// 小组详情顶栏「⋯」菜单的条目序列（对齐安卓 `GroupManagementTopBarMenu` 的逐个条件 +
/// `GroupDetailViewModel` 的 `isAdmin` / `isOwner` / `canTransferOwnership`）。
/// 做成纯值语义是为了让「身份 × 状态」的组合能脱离 SwiftUI 被单测逐条覆盖，视图只负责渲染。
nonisolated struct GroupManagementMenu: Sendable, Equatable {
    enum Entry: String, Sendable {
        case editProfile, transfer, archive, restore, cancelDissolve, dissolve, leave, report, divider
        /// 安卓把解散 / 退出 / 举报三条目统一画成红字（ToolWhistleRed）。
        var isDestructive: Bool { [Self.dissolve, .leave, .report].contains(self) }
        /// 分隔线没有标题，视图据此渲染 `Divider()` 而不是按钮。
        var titleKey: String? {
            switch self {
            case .editProfile: "edit_profile"
            case .transfer: "transfer"
            case .archive: "archive"
            case .restore: "restore"
            case .cancelDissolve: "cancel_dissolve"
            case .dissolve: "dissolve"
            case .leave: "leave"
            case .report: "report"
            case .divider: nil
            }
        }
    }

    /// 当前成员在组内的角色；非成员为 nil（此时只保留举报入口）。
    var role: String?
    var status: String

    private var isOwner: Bool { role == "owner" }
    private var isAdmin: Bool { ["owner", "admin"].contains(role ?? "") }
    /// 安卓 `GroupStatuses.isReadOnly`：非 active 一律只读（归档与解散冷静期都算）。
    private var readOnly: Bool { status != "active" }
    private var dissolving: Bool { status == "dissolving" }

    /// 安卓 `canTransferOwnership`：冷静期与已解散的服务端直接 409，菜单里就不该给入口。
    var canTransfer: Bool { isOwner && ["active", "archived"].contains(status) }
    /// 冷静期与归档态都不该再出现「解散」（安卓 `!dissolving && !archived`）。
    var canDissolve: Bool { isOwner && !dissolving && !readOnly }

    var entries: [Entry] {
        var result: [Entry] = []
        // 编辑资料仅管理员及以上；只读态没有可编辑的字段。
        if isAdmin && !readOnly { result.append(.editProfile) }
        if canTransfer { result.append(.transfer) }
        // 归档 / 恢复是同一枚开关：冷静期内两条都不给，只留撤销解散。
        if isOwner && !dissolving { result.append(readOnly ? .restore : .archive) }
        if isOwner && dissolving { result.append(.cancelDissolve) }
        // 安卓在自管理条目与危险操作之间画一条分隔线（`(isAdmin && !archived) || isOwner`）。
        if !result.isEmpty { result.append(.divider) }
        if canDissolve { result.append(.dissolve) }
        // 组长没有「退出小组」：服务端要求先转让，点了必得 OWNER_TRANSFER_REQUIRED。
        if !isOwner, role != nil { result.append(.leave) }
        // 举报是「向平台投诉」的合规通道，与组内自管理是两条链路：所有身份（含组长）都保留。
        result.append(.report)
        return result
    }
}

nonisolated extension GroupPreview {
    var effectiveAvailability: String {
        if status == "dissolved" { return "not_found" }
        if availability == "already_member" { return availability }
        if let status, status != "active" { return status }
        if joinPolicy == "closed" { return "closed" }
        if memberCount >= (memberLimit ?? Int.max) { return "full" }
        if availability == "pending_approval" && joinPolicy == "open" { return "available" }
        return availability
    }
    var hasPendingRequest: Bool { requestStatus == "pending" || availability == "pending_approval" }
}

nonisolated enum GroupPermissions {
    static func waitingNames(_ result: GroupResult, members: [GroupMember]) -> [String] {
        let side = result.participants.first { $0.memberId == result.submitterMemberId }?.side
        let accounts = Set(members.filter { $0.kind == "account" && $0.status == "active" }.map(\.id))
        return result.participants.filter { accounts.contains($0.memberId) && (side == nil || $0.side != side) }.sorted { ($0.side, $0.seat) < ($1.side, $1.seat) }
            .map { seat in seat.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? members.first(where: { $0.id == seat.memberId })?.displayName ?? "" }
    }
    static func manager(_ member: GroupMember?) -> Bool { ["owner", "admin"].contains(member?.role ?? "") && member?.status == "active" }
    static func coach(_ group: ScoreGroup, member: GroupMember?) -> Bool {
        group.isCoaching && member?.role == "owner" && member?.status == "active" && (group.isCoach ?? true)
    }
    static func canManageMember(_ group: ScoreGroup, me: GroupMember?, target: GroupMember) -> Bool {
        group.isActive && manager(me) && target.status == "active" && target.id != me?.id && target.role != "owner"
            && (me?.role == "owner" || target.role != "admin")
    }
    static func confirmation(_ result: GroupResult, group: ScoreGroup?, me: GroupMember?) -> (allowed: Bool, authority: Bool) {
        guard group?.isActive == true, let me, me.kind == "account", me.status == "active", result.status == "pending_confirmation" else { return (false, false) }
        if let group, group.isCoaching && !coach(group, member: me) { return (false, false) }
        if me.role == "owner", result.canAuthorityConfirm == true { return (true, true) }
        guard me.id != result.submitterMemberId else { return (false, false) }
        if manager(me) { return (true, false) }
        guard let mine = result.participants.first(where: { $0.memberId == me.id }) else { return (false, false) }
        let submitter = result.participants.first { $0.memberId == result.submitterMemberId }
        return (submitter == nil || mine.side != submitter?.side, false)
    }
    static func confirmationTasks(_ results: [GroupResult], group: ScoreGroup?, me: GroupMember?) -> [GroupResult] {
        results.filter { confirmation($0, group: group, me: me).allowed }
    }
    static func resultHistory(_ results: [GroupResult], pending: [GroupResult], tasks: [GroupResult], format: GroupFormat?) -> [GroupResult] {
        let taskIDs = Set(tasks.map(\.id))
        var seen = Set<String>()
        return (pending + results).filter {
            seen.insert($0.id).inserted && !taskIDs.contains($0.id) && (format == nil || $0.format == format)
        }.sorted { $0.playedAt > $1.playedAt }
    }
    static func canScore(_ activity: GroupActivity, me: GroupMember?, seats: [GroupSeat] = []) -> Bool {
        guard let me, me.status == "active" else { return false }
        return manager(me) || activity.creatorMemberId == me.id || seats.contains { $0.memberId == me.id }
    }
    /// 对齐安卓 `canInviteToGroup`：状态必须是 active、入组策略不能是 closed、满员不可邀请，
    /// availability 落在「已满 / 已关闭 / 已归档 / 不存在」四类里同样不可邀请。
    /// 字段缺失时按安卓 DTO 的默认值兜底（status=active、memberLimit=100），不能反过来判成不可邀请。
    static func canInvite(_ preview: GroupPreview) -> Bool {
        guard (preview.status ?? "active") == "active" else { return false }
        guard preview.joinPolicy != "closed" else { return false }
        guard !["full", "closed", "archived", "not_found"].contains(preview.availability) else { return false }
        return preview.memberCount < (preview.memberLimit ?? 100)
    }
}

nonisolated enum GroupInputValidation {
    static func validName(_ value: String, minimum: Int = 1, maximum: Int = 24) -> Bool {
        (minimum...maximum).contains(value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count)
    }
    static func temporaryNames(_ input: String) -> [String] {
        var seen = Set<String>()
        return input.components(separatedBy: CharacterSet(charactersIn: "\n,，、;；")).map { $0.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ") }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    /// 对齐安卓 GroupResultDraft.hasDetailInput：明细行是可选占位。展开明细却一行都没加时
    /// 仍然只按总分校验，不能把「展开了明细」本身变成一条校验错误。
    static func scoredDetails(includesSets: Bool, sets: [GroupScore]) -> [GroupScore]? {
        includesSets && !sets.isEmpty ? sets : nil
    }
}

extension GroupRepository {
    func allPages<T: Codable & Sendable>(_ path: String, query: [URLQueryItem] = [], expectedAuthRevision: UInt64? = nil) async throws -> [T] {
        let authRevision = await requestAuthRevision(expectedAuthRevision)
        var rows: [T] = [], cursor: String?, visited = Set<String>()
        repeat {
            try Task.checkCancellation()
            var parameters = query + [.init(name: "limit", value: "100")]
            if let cursor { parameters.append(.init(name: "cursor", value: cursor)) }
            let page: GroupPage<T> = try await read(path, query: parameters, expectedAuthRevision: authRevision)
            rows.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, !visited.insert(cursor).inserted { throw GroupFlowError.repeatedCursor }
        } while cursor != nil
        return rows
    }
    private func requestAuthRevision(_ revision: UInt64?) async -> UInt64 {
        if let revision = revision ?? GroupRequestIdentity.authRevision { return revision }
        return await client.authSessionRevision()
    }
}

nonisolated enum GroupFlowError: LocalizedError {
    case repeatedCursor, staleSession, invalidName, noCapabilities, gameUnavailable, invalidReceipt
    var errorDescription: String? {
        switch self {
        case .repeatedCursor: groupText("pagination_failed", "Could not load the next page. Please refresh.")
        case .staleSession: groupText("session_changed", "Your account changed. Open the form again.")
        case .invalidName: groupText("invalid_member_name", "Names must contain 1–24 characters.")
        case .noCapabilities: groupText("capabilities_missing", "Match rules are unavailable. Connect and retry.")
        case .gameUnavailable: groupText("game_unavailable", "This match cannot be resumed on this device.")
        case .invalidReceipt: groupText("notice_receipt_failed", "Notification receipt was incomplete. Please retry.")
        }
    }
}

nonisolated extension GroupNotification {
    /// The Android inbox labels each row with `<group name> · <kind>`, so the kind vocabulary and
    /// the "can open the group" rule live next to the model that carries the wire fields.
    var label: String { groupText("notice_" + kind, Self.fallbackLabel(kind)) }
    /// Removing someone or declining a request leaves nothing to open.
    var opensGroup: Bool { !["member_removed", "join_rejected"].contains(kind) }
    /// A read receipt has to echo the acknowledged notice and carry a server timestamp; servers that
    /// answer without either must not clear the badge.
    func isReceipt(for notice: GroupNotification) -> Bool { id == notice.id && seenAt != nil }
    private static func fallbackLabel(_ kind: String) -> String {
        switch kind {
        case "join_requested": "Join request received"
        case "join_approved": "Join request approved"
        case "join_rejected": "Join request declined"
        case "activity_created": "Activity created"
        case "activity_changed": "Activity updated"
        case "activity_cancelled": "Activity cancelled"
        case "result_pending": "Result awaiting confirmation"
        case "result_confirmed": "Result confirmed"
        case "result_voided": "Result voided"
        case "role_changed": "Your role changed"
        case "member_removed": "You were removed from the group"
        case "ownership_transferred": "Group owner changed"
        default: "Notification"
        }
    }
}

nonisolated extension GroupMatchRules {
    var overallScores: [GroupScore] {
        if matchCompletionMode == "play_all" { return (0...max(0, maxSets)).map { .init(a: $0, b: maxSets - $0) } }
        let need = maxSets / 2 + 1
        return (0..<max(1,need)).flatMap { [GroupScore(a: need, b: $0), GroupScore(a: $0, b: need)] }
    }
}

/// Preserve acknowledged server timestamps when an eventually consistent page still says unread.
nonisolated struct GroupNoticeReadReceipts {
    private var confirmed: [String: GroupNotification] = [:]
    mutating func record(_ receipt: GroupNotification) { confirmed[receipt.id] = receipt }
    mutating func removeAll() { confirmed.removeAll() }
    func applying(to notice: GroupNotification) -> GroupNotification {
        guard let timestamp = confirmed[notice.id]?.seenAt else { return notice }
        var updated = notice; updated.seenAt = timestamp
        return updated
    }
    func staleUnreadCount(in items: [GroupNotification]) -> Int {
        items.filter { $0.seenAt == nil && confirmed[$0.id]?.seenAt != nil }.count
    }
}
