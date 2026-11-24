import SwiftUI
import PersistenceCore

// MARK: - 活动编排 / 服务端快照模型

nonisolated struct GroupBilliardsSession: Codable, Identifiable, Sendable {
    var id: String; var orderNo: Int; var court: String; var startsAt: Int64; var rules: GroupBilliardsRules
    var participants: [GroupBilliardsSeat]; var status: String; var gameId: String? = nil; var resultId: String? = nil
    var isFrozen: Bool? = nil; var canStart: Bool? = nil; var canResume: Bool? = nil; var canCorrect: Bool? = nil
    var submission: GroupBilliardsSessionBody { .init(id: id, orderNo: orderNo, court: court, startsAt: startsAt, rules: rules, participants: participants.map(\.participant)) }
    var isTerminal: Bool { ["completed", "cancelled"].contains(status) }
}
nonisolated struct GroupBilliardsSessionBody: Codable, Sendable {
    var id: String? = nil; var orderNo: Int; var court: String; var startsAt: Int64; var rules: GroupBilliardsRules; var participants: [GroupBilliardsParticipant]
}
nonisolated struct GroupBilliardsLineup: Codable, Sendable {
    var activity: GroupActivity; var sessions: [GroupBilliardsSession]; var sessionMinutes: Int; var revision: Int64; var canManage: Bool
}
nonisolated struct GroupBilliardsLineupBody: Codable, Sendable { var sessionMinutes: Int; var sessions: [GroupBilliardsSessionBody] }
nonisolated struct GroupBilliardsActivityBody: Codable, Sendable {
    var title: String; var startsAt: Int64; var place: String; var matchMode = "multi"; var timingMode = "sequence"
    var activityType: String; var defaultMatchConfig: GroupBilliardsRules
    /// 报名制活动必须给人数上限，否则服务端按默认值兜底，卡片会显示成「3/30」这种看不懂的数。
    var capacity: Int = 100
    var registrationClosesAt: Int64
    var note: String
}

nonisolated enum BilliardsResultAction: String, Sendable { case correct, confirm, authorityConfirm, void }

/// 首屏缓存（弱网/离线时先用上次的数据垫底）。只存通用活动行——台球默认规则属于服务端快照，
/// 联网后会重新取，不需要进缓存。
nonisolated private struct BilliardsBrowseCache: Codable, Sendable {
    var rows: [GroupBilliardsRow]; var activities: [GroupActivity]; var ranking: GroupBilliardsRanking
}
private enum BilliardsActivityCreation {
    case signup, direct
}

/// 作废、确认、结束活动和移除场次共用的操作弹窗。
private struct BilliardsPrompt: Identifiable {
    enum Kind {
        case voidResult(GroupBilliardsRow)
        case cancelActivity
        case abandon(BilliardsResume)
        case completeActivity(String)
        case removeSession(activityID: String, sessionID: String)
        case confirmResult(GroupBilliardsRow, authority: Bool)
    }
    var id = UUID()
    var kind: Kind
    var title: String
    var message: String
    var confirm: String
    var requiresReason = false
    var destructive = true
}

private func billiardsResultConfirmation(_ row: GroupBilliardsRow, authority: Bool) -> BilliardsPrompt {
    let title = billiardsText(authority ? "owner_confirm" : "confirm")
    let message = authority
        ? groupText("copy_result_confirm_authority_message", "Check the players and score before confirming on behalf of the group.")
        : groupText("copy_result_confirm_member_message", "Check the players and score before confirming this result.")
    return .init(kind: .confirmResult(row, authority: authority), title: title, message: message, confirm: title, destructive: false)
}

/// 确认弹窗本体（同一个视图节点只挂一个，避免与「创建活动」sheet 抢占）。
private struct BilliardsPromptDialog: View {
    let prompt: BilliardsPrompt
    @Binding var reason: String
    let error: String?
    let busy: Bool
    var onCancel: () -> Void
    var onConfirm: () -> Void

    private var canConfirm: Bool {
        !busy && (!prompt.requiresReason || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        ZStack {
            Theme.scoreboardDialogScrim.ignoresSafeArea()
                .onTapGesture { if !busy { onCancel() } }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text(prompt.title).font(.system(size: Theme.fontH5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                if !prompt.message.isEmpty {
                    Text(prompt.message).font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).groupLineHeight(.body)
                }
                if prompt.requiresReason {
                    TextField(billiardsText("correction_reason"), text: $reason)
                        .font(GroupTypography.body).tint(Theme.primary)
                        .padding(.horizontal, Theme.sm).frame(minHeight: 44)
                        .billiardsControl(radius: 10)
                        .accessibilityIdentifier("billiards_prompt_reason")
                }
                if let error {
                    // 失败信息留在弹窗内部：页面 banner 被弹窗盖住，用户看不到。
                    Text(error).font(GroupTypography.caption).foregroundStyle(Theme.destructiveText)
                        .fixedSize(horizontal: false, vertical: true).groupLineHeight(.caption)
                        .accessibilityIdentifier("billiards_prompt_error")
                }
                HStack(spacing: Theme.sm) {
                    Button(NSLocalizedString("cancel", value: "Cancel", comment: "")) { onCancel() }
                        .buttonStyle(GroupAlignedActionStyle(secondary: true)).disabled(busy)
                    Button(prompt.confirm) { onConfirm() }
                        .buttonStyle(GroupAlignedActionStyle(destructive: prompt.destructive)).disabled(!canConfirm)
                        .accessibilityIdentifier("billiards_prompt_confirm")
                }
            }
            .padding(Theme.lg)
            .frame(maxWidth: 420)
            .background(Theme.dialogSurfaceBackground, in: RoundedRectangle(cornerRadius: Theme.xxl))
            .shadow(color: .black.opacity(0.15), radius: Theme.md)
            .padding(Theme.padding)
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("billiards_prompt")
        }
        .tint(Theme.primary)
    }
}
nonisolated private struct BilliardsResumeGameState: Decodable, Sendable { var state: String }
private struct BilliardsResume: Identifiable {
    var id: String; var source: GroupBilliardsSource
}

// MARK: - 页签入口

/// 台球小组三个页签（概览 / 活动 / 战绩）与赛果详情。
///
/// 这一层只负责「账号/会话切换就整页重建」和「resultID 直接进赛果详情」两件事；
/// 真正的数据与交互都在 `GroupBilliardsTabContent` 里，方便单测与复用。
struct GroupBilliardsTab: View {
    let detail: GroupDetailCache
    let tab: Int
    var resultID: String? = nil
    var initialActivityID: String? = nil
    var refreshKey: Int = 0
    var onSelectTab: (Int) -> Void = { _ in }
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared

    var body: some View {
        if let resultID {
            GroupBilliardsResultDetail(groupID: detail.group.id, resultID: resultID, detail: detail, onStart: onStart)
        } else {
            GroupBilliardsTabContent(detail: detail, tab: tab, initialActivityID: initialActivityID, refreshKey: refreshKey, onSelectTab: onSelectTab, onStart: onStart)
                // 账号或会话切换必须整页重建，避免把旧账号的队列/编排写进新账号视图（规格 §5.3）。
                .id("\(store.accountID ?? "-")|\(store.identityRevision)|\(detail.group.id)")
        }
    }
}

private struct GroupBilliardsTabContent: View {
    let detail: GroupDetailCache
    let tab: Int
    var initialActivityID: String? = nil
    var refreshKey: Int = 0
    var onSelectTab: (Int) -> Void = { _ in }
    var onStart: (GameType, SportsSetupResult, String) -> Void

    @State private var store = GroupStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var rows: [GroupBilliardsRow] = []
    @State private var ranking = GroupBilliardsRanking()
    @State private var variant: GroupBilliardsVariant
    @State private var variantAccount: String?
    @State private var bucket = ""
    @State private var activities: [GroupBilliardsActivity] = []
    @State private var lineup: GroupBilliardsLineup?
    @State private var lineupActivityID: String?
    @State private var uploads: [GroupBilliardsUpload] = []
    @State private var resumes: [BilliardsResume] = []
    @State private var error: String?
    @State private var busy = false
    @State private var loaded = false
    @State private var activityCreation: BilliardsActivityCreation?
    @State private var overviewSetup = false
    @State private var entry: BilliardsEntryRequest?
    @State private var prompt: BilliardsPrompt?
    @State private var promptReason = ""
    @State private var promptError: String?
    @State private var promptBusy = false
    @State private var discardUpload: GroupBilliardsUpload?
    @State private var sharing = false

    init(detail: GroupDetailCache, tab: Int, initialActivityID: String? = nil, refreshKey: Int = 0,
         onSelectTab: @escaping (Int) -> Void = { _ in }, onStart: @escaping (GameType, SportsSetupResult, String) -> Void) {
        self.detail = detail; self.tab = tab; self.initialActivityID = initialActivityID
        self.refreshKey = refreshKey; self.onSelectTab = onSelectTab; self.onStart = onStart
        // 从活动详情页进来时直接展开该活动的场次编排（对齐安卓 initialActivityId）。
        _lineupActivityID = State(initialValue: initialActivityID)
        let account = GroupStore.shared.accountID
        _variantAccount = State(initialValue: account)
        _variant = State(initialValue: Self.lastFilterVariant(account: account, groupID: detail.group.id))
    }

    private var groupID: String { detail.group.id }
    private var group: ScoreGroup { detail.group }
    private var me: GroupMember? { detail.members.first { $0.accountId == store.accountID && $0.status == "active" } }
    private var manager: Bool { GroupPermissions.manager(detail.members.first { $0.accountId == store.accountID }) }
    /// 本机可写：归档 / 解散冷静期 / 未登录 / 功能关闭之外都算。
    /// 自由局（开赛、补记）离线也允许，写进本机队列后联网补传。
    private var writable: Bool { group.isActive && store.enabled && SessionStore.shared.isAuthenticated }
    /// 活动与赛果审核是服务端强一致动作：离线（缓存态）时整套入口收起（规格 §2 末尾）。
    private var serverWritable: Bool { writable && !store.cached }
    private var cacheKey: String { "billiards-cache-v2:" + groupID }
    private static func filterKey(_ groupID: String) -> String { "billiards-filter:" + groupID }

    private static func lastFilterVariant(account: String?, groupID: String) -> GroupBilliardsVariant {
        guard let account else { return .folk }
        if let saved = GroupLocalPersistence.shared.loadDraft(GroupBilliardsVariant.self, key: filterKey(groupID), accountID: account) {
            return saved
        }
        return (try? GroupBilliardsPersistence.shared.rememberedRules(accountID: account, groupID: groupID))?.knownVariant ?? .folk
    }

    private func selectFilterVariant(_ value: GroupBilliardsVariant) {
        guard variant != value else { return }
        variant = value; bucket = ""
        if let account = store.accountID {
            try? GroupLocalPersistence.shared.saveDraft(value, key: Self.filterKey(groupID), accountID: account)
        }
    }
    private var confirmedCount: Int { rows.filter { $0.status == "confirmed" }.count }
    private var pendingCount: Int { rows.filter { $0.status == "pending_confirmation" }.count }

    var body: some View {
        page
            .confirmationDialog(billiardsText("discard_upload"), isPresented: Binding(get: { discardUpload != nil }, set: { if !$0 { discardUpload = nil } }), presenting: discardUpload) { upload in
                Button(billiardsText("confirm"), role: .destructive) {
                    run { try GroupBilliardsPersistence.shared.finish(upload, discard: true) }
                    discardUpload = nil
                }
                Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) { discardUpload = nil }
            } message: { _ in Text(billiardsText("discard_message")) }
            .overlay {
                if let prompt {
                    BilliardsPromptDialog(prompt: prompt, reason: $promptReason, error: promptError, busy: promptBusy,
                                          onCancel: closePrompt, onConfirm: confirmPrompt)
                }
            }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let error { GroupNotice(text: error) }
                if store.cached { GroupNotice(text: groupText("cached", "Showing saved data. Connect to refresh.")) }
                if busy { ProgressView().frame(maxWidth: .infinity) }
                switch tab {
                case 0: overview
                case 1: activitySection
                default: recordsSection
                }
            }
            .padding(Theme.padding)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await reload() }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .task(id: "\(tab)|\(variant.rawValue)|\(bucket)|\(store.identityRevision)") { await reload() }
        .onChange(of: refreshKey) { _, _ in Task { await reload() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active, loaded { Task { await reload() } } }
        // 从计分板/补记页 pop 回来时补一次刷新：刚打完的一场不用手动下拉才出现（规格 §5.1）。
        .onAppear { if loaded { Task { await reload() } } }
        .onChange(of: entry?.id) { _, next in if next == nil { Task { await reload() } } }
        .sheet(isPresented: $overviewSetup, onDismiss: { Task { await reload() } }) {
            GroupBilliardsEntryView(detail: detail, request: .init(mode: .launch),
                                   hostsScoreboardSetup: true, onStart: onStart)
        }
        .navigationDestination(isPresented: Binding(get: { entry != nil }, set: { if !$0 { entry = nil } })) {
            if let entry { GroupBilliardsEntryView(detail: detail, request: entry, onStart: onStart) }
        }
        .navigationDestination(isPresented: $sharing) { GroupShareView(group: group) }
        .navigationDestination(isPresented: Binding(get: { activityCreation != nil }, set: { if !$0 { activityCreation = nil } })) {
            if let activityCreation {
                GroupBilliardsActivityEditor(detail: detail, direct: activityCreation == .direct, onStart: onStart,
                                             onCreated: openActivity)
                    .groupAccountBoundary()
            }
        }
    }

    // MARK: 概览

    @ViewBuilder private var overview: some View {
        heroCard
        resumeSection
        pendingUploadSection
        latestResultSection
        upcomingSection
    }

    private var heroCard: some View {
        GroupSurface {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top) {
                    AppCatalogIcon(gameType: group.sport.gameType, size: 52)
                    Text(group.name).font(GroupTypography.groupTitle).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .top, spacing: Theme.spacing) {
                    AppCatalogIcon(gameType: group.sport.gameType, size: 52)
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text(group.name).font(GroupTypography.groupTitle).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        groupNumberChip
                        if !group.isActive { Text(group.statusLabel).font(.caption).foregroundStyle(.secondary) }
                        inviteButton
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { sharing = true } label: { GroupQRCode(number: group.groupNo, size: 64) }
                        .buttonStyle(.plain).accessibilityLabel(groupText("group_qr", "Group QR code"))
                }
            }
            Divider()
            statRow
        }
    }

    private var groupNumberChip: some View {
        Button { UIPasteboard.general.string = group.groupNo } label: {
            HStack(spacing: Theme.xs) {
                Text(GroupQRPayload.formatted(group.groupNo)).monospacedDigit()
                Image(systemName: "doc.on.doc")
            }.font(.caption).foregroundStyle(Theme.primary)
                .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
                .background(Theme.tintedFill(Theme.primary, lightAlpha: 0.12, darkAlpha: 0.16), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel(groupText("group_qr", "Group QR code"))
    }

    private var canInvite: Bool {
        let count = group.memberCount ?? detail.members.filter { $0.status == "active" }.count
        return group.isActive && ["open", "approval"].contains(group.joinPolicy) && count < group.memberLimit
    }

    @ViewBuilder private var inviteButton: some View {
        if canInvite {
            Button { sharing = true } label: {
                Label(groupText("invite", "Invite"), systemImage: "person.badge.plus").font(.caption.weight(.semibold))
            }.buttonStyle(.plain).foregroundStyle(Theme.primary).disabled(!writable)
                .accessibilityIdentifier("billiards_invite")
        }
    }

    /// 三格统计：已确认场次 / 成员 / 待确认（0 显示「—」，不留空白格）。
    private var statRow: some View {
        let stats: [(String, String)] = [
            ("\(confirmedCount)", groupText("confirmed_matches", "Confirmed")),
            ("\(group.memberCount ?? detail.members.filter { $0.status == "active" }.count)", groupText("member", "Members")),
            (pendingCount > 0 ? "\(pendingCount)" : "—", groupText("pending_confirmation", "Awaiting confirmation")),
        ]
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    ForEach(stats, id: \.1) { LabeledContent($0.1, value: $0.0) }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 5) {
                            Text(item.0).font(.title3.bold())
                            Text(item.1).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity).padding(.vertical, Theme.xs)
                        if index < stats.count - 1 { Divider().frame(height: 30) }
                    }
                }
            }
        }.accessibilityIdentifier("billiards_overview_stats")
    }

    @ViewBuilder private var resumeSection: some View {
        if !resumes.isEmpty {
            GroupSectionTitle(title: groupText("unfinished_match", "Unfinished match"))
            ForEach(resumes) { item in
                GroupSurface {
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text(item.source.rules.knownVariant?.title ?? billiardsText("unsupported"))
                            .font(GroupTypography.body.weight(.semibold)).lineLimit(1)
                        Text(item.source.rules.summary).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                            .lineLimit(2).groupLineHeight(.caption)
                        HStack(spacing: Theme.spacing) {
                            Button(role: .destructive) { askAbandon(item) } label: {
                                Text(billiardsText("abandon")).frame(maxWidth: .infinity, minHeight: 40)
                            }.buttonStyle(GroupAlignedActionStyle(destructive: true)).disabled(!writable || busy)
                            Button { resume(item) } label: {
                                Text(billiardsText("resume")).frame(maxWidth: .infinity, minHeight: 40)
                            }.buttonStyle(GroupAlignedActionStyle()).disabled(!writable || busy)
                                .accessibilityIdentifier("billiards_resume")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var pendingUploadSection: some View {
        if !uploads.isEmpty {
            HStack(spacing: Theme.sm) {
                GroupSectionTitle(title: groupText("pending_upload", "Waiting to upload"), subtitle: "\(uploads.count)")
                BilliardsPillButton(text: billiardsText("refresh"), enabled: !busy && writable) {
                    run { await GroupBilliardsSync.shared.sync(force: true) }
                }.accessibilityIdentifier("billiards_refresh_pending")
            }
            ForEach(uploads) { upload in pendingUploadCard(upload) }
        }
    }

    private func pendingUploadCard(_ upload: GroupBilliardsUpload) -> some View {
        let reviewable = ["RULES_REVIEW_REQUIRED", "INVALID_RESULT", "INVALID_RULES"].contains(upload.failure ?? "")
        return GroupSurface {
            VStack(alignment: .leading, spacing: Theme.sm) {
                HStack(spacing: Theme.sm) {
                    Text(billiardsText("pending")).font(GroupTypography.body.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BilliardsStatusChip(text: groupText("pending_upload", "Pending upload"), tone: .warning)
                }
                Text(billiardsText(reviewable ? "review" : "retry_hint"))
                    .font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(3).groupLineHeight(.caption)
                HStack(spacing: Theme.sm) {
                    if reviewable {
                        BilliardsPillButton(text: billiardsText("manual"), primary: true, enabled: writable && !busy) {
                            // 修复按队列里的冻结请求体回填，玩法/规则由预填决定，入口不带 variant。
                            entry = .init(mode: .manual, uploadID: upload.id)
                        }
                    }
                    BilliardsPillButton(text: billiardsText("discard_upload"), destructive: true, enabled: !busy) { discardUpload = upload }
                }
            }
        }
    }

    @ViewBuilder private var latestResultSection: some View {
        if let latest = rows.first {
            GroupSectionTitle(title: groupText("latest_results", "Latest results"),
                              subtitle: String(format: billiardsText("match_count"), confirmedCount),
                              navigate: { onSelectTab(2) })
            BilliardsResultCard(row: latest, groupID: groupID)
        }
    }

    @ViewBuilder private var upcomingSection: some View {
        if let next = nextActivity {
            GroupSectionTitle(title: groupText("upcoming", "Upcoming"), navigate: { onSelectTab(1) })
            Button { openActivity(next) } label: { activityCard(next) }.buttonStyle(.plain)
        }
    }

    private var nextActivity: GroupBilliardsActivity? {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return activities
            .filter { activity in
                activity.activity.status == "in_progress" || (activity.activity.status == "recruiting" && activity.activity.startsAt >= now)
            }
            .min { lhs, rhs in
                let left = (lhs.activity.status == "in_progress" ? 0 : 1, lhs.activity.startsAt)
                let right = (rhs.activity.status == "in_progress" ? 0 : 1, rhs.activity.startsAt)
                return left < right
            }
    }

    // MARK: 活动

    @ViewBuilder private var activitySection: some View {
        if let lineup, lineupActivityID != nil { lineupDetail(lineup) }
        else if lineupActivityID != nil, !loaded { ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.padding) }
        else { activityList }
    }

    @ViewBuilder private var activityList: some View {
        if activities.isEmpty {
            GroupEmptyCard(text: groupText("empty_activities_title", "No activities yet"),
                           description: groupText(manager ? "empty_activities_hint" : "activity_create_admin_hint",
                                                 manager ? "Create an activity for members to join. Sign-up closes when full." : "Activities are created by the group owner or an admin"))
        } else {
            let upcoming = activities.filter { !["completed", "cancelled"].contains($0.activity.status) }
                .sorted { lhs, rhs in
                    let left = (lhs.activity.status == "in_progress" ? 0 : 1, lhs.activity.startsAt)
                    let right = (rhs.activity.status == "in_progress" ? 0 : 1, rhs.activity.startsAt)
                    return left < right
                }
            let past = activities.filter { ["completed", "cancelled"].contains($0.activity.status) }
                .sorted { $0.activity.startsAt > $1.activity.startsAt }
            if !upcoming.isEmpty {
                GroupSectionTitle(title: groupText("activity_section_upcoming", "In progress · Open for sign-ups"), subtitle: activityCount(upcoming.count))
                ForEach(upcoming) { item in Button { openActivity(item) } label: { activityCard(item) }.buttonStyle(.plain) }
            }
            if !past.isEmpty {
                GroupSectionTitle(title: groupText("activity_section_past", "Past activities"), subtitle: activityCount(past.count))
                ForEach(past) { item in Button { openActivity(item) } label: { activityCard(item) }.buttonStyle(.plain) }
            }
            if !manager && group.isActive {
                Text(groupText("activity_create_admin_hint", "Activities are created by the group owner or an admin"))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, Theme.sm)
            }
        }
    }

    private func activityCount(_ count: Int) -> String { String(format: groupText("activity_section_count", "%1$d activities"), count) }

    private func activityCard(_ item: GroupBilliardsActivity) -> some View {
        let activity = item.activity
        let signup = !activity.isDirect
        let sessions = activity.sessionCount ?? 0
        return GroupSurface {
            VStack(alignment: .leading, spacing: Theme.sm) {
                HStack(spacing: Theme.sm) {
                    Text(activity.title).font(GroupTypography.cardTitle).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BilliardsStatusChip(text: activityStatusLabel(activity), tone: activityTone(activity.status))
                }
                Text(activityTimeLine(activity)).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let rules = item.defaultRules {
                    Text(rules.summary).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2).groupLineHeight(.caption)
                }
                HStack(spacing: Theme.sm) {
                    GroupActivityTagChip(text: signup
                        ? String(format: groupText("registration_ratio", "%1$d/%2$d signed up"), activity.registeredMemberIds.count, activity.capacity)
                        : groupText("activity_direct_title", "Arrange now"))
                    if sessions > 0 { GroupActivityTagChip(text: activityCount(sessions)) }
                }
            }
        }
    }

    private func activityStatusLabel(_ activity: GroupActivity) -> String {
        activity.isDirect && activity.status == "recruiting"
            ? groupText("activity_status_scheduled", "Scheduled") : activity.statusLabel
    }

    private func activityTimeLine(_ activity: GroupActivity) -> String {
        // 台球活动始终有开始时间，场次时间在此基础上编排；三端卡面统一显示具体时间，
        // 不再按 timingMode=sequence 改写成「无固定时间」。
        var text = activity.date.formatted(date: .abbreviated, time: .shortened)
        if !activity.place.isEmpty { text += " · " + activity.place }
        return text
    }

    private func openActivity(_ item: GroupBilliardsActivity) {
        lineupActivityID = item.id
        Task {
            do {
                let loaded: GroupBilliardsLineup = try await store.repository.read("/\(groupID)/activities/\(item.id)/lineup")
                guard lineupActivityID == item.id, !Task.isCancelled else { return }
                lineup = loaded
            } catch { self.error = groupErrorMessage(error) }
        }
    }

    @ViewBuilder private func lineupDetail(_ lineup: GroupBilliardsLineup) -> some View {
        let activity = lineup.activity
        GroupSurface {
            VStack(alignment: .leading, spacing: Theme.sm) {
                HStack(spacing: Theme.sm) {
                    Button { exitLineup() } label: {
                        HStack(spacing: Theme.xs) {
                            Image(systemName: "chevron.left").font(.caption.weight(.semibold))
                            Text(billiardsText("back")).font(GroupTypography.caption)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("billiards_back_to_activities")
                    Text(activity.title).font(GroupTypography.body.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BilliardsStatusChip(text: activityStatusLabel(activity), tone: activityTone(activity.status))
                }
                Text(activityTimeLine(activity)).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let rules = activities.first(where: { $0.id == activity.id })?.defaultRules {
                    Text(rules.summary).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                if !activity.note.isEmpty {
                    Text(activity.note).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                }
                registrationControls(activity)
                if lineup.canManage && serverWritable {
                    Divider()
                    HStack(spacing: Theme.sm) {
                        BilliardsPillButton(text: billiardsText("add_session"), primary: true, enabled: !busy) {
                            entry = .init(mode: .arrange,
                                          variant: activities.first(where: { $0.id == activity.id })?.defaultRules?.knownVariant ?? .folk,
                                          activityID: activity.id,
                                          allowedMemberIDs: activity.isDirect ? nil : activity.registeredMemberIds)
                        }
                        BilliardsPillButton(text: billiardsText("complete_activity"), enabled: !busy) {
                            let title = billiardsText("complete_activity")
                            openPrompt(.init(kind: .completeActivity(activity.id), title: title,
                                             message: groupText("complete_confirm", "End this activity?"),
                                             confirm: title))
                        }
                        if activity.status == "recruiting" {
                            BilliardsPillButton(text: billiardsText("cancel_activity"), destructive: true, enabled: !busy) {
                                askCancelActivity()
                            }
                        }
                    }
                }
            }
        }
        GroupSectionTitle(title: groupText("activity_lineup_section_matches", "Matches"), count: lineup.sessions.count)
        if lineup.sessions.isEmpty {
            GroupEmptyCard(text: groupText("no_sessions", "No matches arranged yet"),
                           description: groupText("empty_activities_hint", "Create an activity for members to join. Sign-up closes when full."))
        } else {
            ForEach(lineup.sessions) { session in sessionCard(session, activity: activity) }
        }
    }

    @ViewBuilder private func registrationControls(_ activity: GroupActivity) -> some View {
        if !activity.isDirect, ["recruiting", "in_progress"].contains(activity.status), let memberID = me?.id {
            let registered = activity.registeredMemberIds.contains(memberID)
            let full = activity.registeredMemberIds.count >= activity.capacity
            let closes = Date(timeIntervalSince1970: Double(activity.registrationClosesAt ?? activity.startsAt) / 1000)
            TimelineView(.explicit([.distantPast, closes])) { _ in
                if !activity.registrationOpen {
                    Text(groupText("error_registration_closed", "Registration has closed."))
                        .font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    BilliardsPillButton(
                        text: registered ? billiardsText("unregister") : (full ? groupText("activity_full", "Full") : billiardsText("register")),
                        primary: !registered, enabled: serverWritable && !busy && (registered || !full)
                    ) {
                        guard activity.registrationOpen else { return }
                        let action = registered ? "unregister" : "register"
                        run { try await store.repository.action("/\(groupID)/activities/\(activity.id)/\(action)", body: .init(memberId: memberID)) }
                    }.padding(.top, Theme.xs)
                }
            }
        }
    }

    private func sessionCard(_ session: GroupBilliardsSession, activity: GroupActivity) -> some View {
        let signup = !activity.isDirect
        return GroupSurface {
            VStack(alignment: .leading, spacing: Theme.sm) {
                HStack(spacing: Theme.sm) {
                    Text(String(format: groupText("activity_lineup_session", "%1$d"), session.orderNo) + " · " + (session.rules.knownVariant?.title ?? billiardsText("unsupported")))
                        .font(GroupTypography.body.weight(.semibold)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BilliardsStatusChip(text: sessionStatusText(session.status), tone: sessionTone(session.status))
                }
                if !session.participants.isEmpty {
                    let columns = [GridItem(.adaptive(minimum: 120), alignment: .leading)]
                    LazyVGrid(columns: columns, spacing: Theme.sm) {
                        ForEach(session.participants.sorted { $0.participant.position < $1.participant.position }, id: \.memberId) { seat in
                            let member = detail.members.first { $0.id == seat.memberId || $0.ownsHistoricalMember(seat.memberId) }
                            let name = member?.displayName ?? seat.displayName ?? seat.memberId
                            HStack(spacing: Theme.xs) {
                                GroupAvatar(name: name, url: member?.avatarUrl, size: 24, isVip: member?.isVip == true)
                                    .accessibilityHidden(true)
                                Text(name).font(GroupTypography.caption).foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                }
                let time = Date(timeIntervalSince1970: Double(session.startsAt) / 1000)
                if session.startsAt > 0 || !session.court.isEmpty {
                    Text([session.startsAt > 0 ? time.formatted(date: .omitted, time: .shortened) : "", session.court]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                }
                if writable && (!session.isTerminal || session.canCorrect == true) {
                    HStack(spacing: Theme.sm) {
                        if session.canStart == true || session.canResume == true {
                            BilliardsPillButton(text: session.canResume == true ? billiardsText("resume") : billiardsText("start"), primary: true, enabled: !busy) {
                                entry = .init(mode: .launch, variant: session.rules.knownVariant ?? .folk,
                                              activityID: activity.id, activitySessionID: session.id,
                                              gameID: session.gameId, rules: session.rules, seats: session.participants,
                                              allowedMemberIDs: signup ? activity.registeredMemberIds : nil,
                                              canAdjustAtStart: session.canStart == true && session.isFrozen != true)
                            }
                        }
                        BilliardsPillButton(text: billiardsText("manual"), enabled: !busy) {
                            entry = .init(mode: .manual, variant: session.rules.knownVariant ?? .folk,
                                          activityID: activity.id, activitySessionID: session.id,
                                          gameID: session.gameId, rules: session.rules, seats: session.participants,
                                          allowedMemberIDs: signup ? activity.registeredMemberIds : nil)
                        }
                    }
                }
                if lineup?.canManage == true, session.isFrozen != true, serverWritable {
                    HStack(spacing: Theme.sm) {
                        BilliardsPillButton(text: String(format: billiardsText("edit_session"), session.orderNo), enabled: !busy) {
                            entry = .init(mode: .arrange, variant: session.rules.knownVariant ?? .folk,
                                          activityID: activity.id, activitySessionID: session.id,
                                          rules: session.rules, seats: session.participants,
                                          allowedMemberIDs: signup ? activity.registeredMemberIds : nil,
                                          orderNo: session.orderNo)
                        }
                        let remove = String(format: billiardsText("remove_session"), session.orderNo)
                        BilliardsPillButton(text: remove, destructive: true, enabled: !busy) {
                            openPrompt(.init(kind: .removeSession(activityID: activity.id, sessionID: session.id),
                                             title: remove, message: "", confirm: groupText("remove_session", "Remove")))
                        }
                    }
                }
            }
        }
    }

    private func sessionStatusText(_ status: String) -> String {
        switch status {
        case "completed": groupText("completed", "Completed")
        case "cancelled": groupText("cancelled", "Cancelled")
        case "in_progress": groupText("in_progress", "In progress")
        default: groupText("activity_status_scheduled", "Scheduled")
        }
    }

    private func sessionTone(_ status: String) -> BilliardsChipTone {
        switch status {
        case "completed": .neutral
        case "cancelled": .danger
        case "in_progress": .warning
        default: .primary
        }
    }

    private func activityTone(_ status: String) -> BilliardsChipTone {
        switch status {
        case "in_progress": .warning
        case "completed": .neutral
        case "cancelled": .danger
        default: .primary
        }
    }

    private func exitLineup() {
        lineup = nil
        lineupActivityID = nil
    }

    // MARK: 战绩

    @ViewBuilder private var recordsSection: some View {
        variantChips
        bucketChips
        let pendingRows = rows.filter { $0.status == "pending_confirmation" }
        let history = rows.filter { $0.status != "pending_confirmation" }
        let items = ranking.items ?? []
        if items.isEmpty && pendingRows.isEmpty && history.isEmpty {
            // 三个集合全空时只留一个空态，不要「空排行 + 空记录」两张卡叠在一起。
            GroupEmptyCard(text: groupText("no_results", "No matches recorded yet"),
                           description: groupText("records_empty_hint", "Start a group match or enter a result; confirmed results go to the leaderboard automatically."))
                .accessibilityIdentifier("billiards_records_empty")
        } else {
            if !pendingRows.isEmpty {
                GroupSectionTitle(title: groupText("pending_confirmation", "Awaiting confirmation"), count: pendingRows.count)
                ForEach(pendingRows) { row in resultCard(row) }
            }
            HStack(spacing: Theme.sm) {
                GroupSectionTitle(title: billiardsText("ranking"), subtitle: variant.title)
                BilliardsPillButton(text: billiardsText("refresh"), enabled: !busy) {
                    run { await GroupBilliardsSync.shared.sync(force: true) }
                }.accessibilityIdentifier("billiards_refresh")
            }
            if items.isEmpty {
                GroupSurface {
                    Text(billiardsText("ranking_empty", "No leaderboard for this rules set yet. Confirmed results appear here automatically."))
                        .font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, Theme.sm)
                        .groupLineHeight(.caption)
                }
            } else {
                BilliardsRankingTable(items: items, variant: variant, members: detail.members,
                                     myMemberID: me?.id, groupID: groupID)
            }
            GroupSectionTitle(title: billiardsText("records"), count: history.count)
            if history.isEmpty {
                GroupEmptyCard(text: groupText("no_results", "No matches recorded yet"))
            } else {
                ForEach(history) { row in resultCard(row) }
            }
        }
    }

    private var variantChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.sm) {
                ForEach(GroupBilliardsVariant.allCases) { value in
                    Button { selectFilterVariant(value) } label: {
                        // 灰卡片上的次级 chip：浅色白底 + 1px 描边，选中态主色实底 + 白字。
                        Text(value.title).font(GroupTypography.body.weight(.semibold))
                            .billiardsChoice(active: variant == value)
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(variant == value ? .isSelected : [])
                        .accessibilityIdentifier("billiards_records_variant_\(value.rawValue)")
                }
            }.padding(.vertical, 2)
        }
    }

    @ViewBuilder private var bucketChips: some View {
        let buckets = ranking.buckets ?? []
        if buckets.count > 1 {
            // 选中态 = 本地选择；还没点时回显响应里的 `bucket`（规格 §1.3）。
            let selectedKey = bucket.isEmpty ? (ranking.bucket ?? "") : bucket
            Text(billiardsText("rules")).font(.caption).foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.sm) {
                    ForEach(buckets) { option in
                        Button { bucket = option.key } label: {
                            Text(option.rules.summary).font(.caption)
                                .lineLimit(1)
                                .billiardsChoice(active: selectedKey == option.key)
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(selectedKey == option.key ? .isSelected : [])
                            .accessibilityIdentifier("billiards_bucket_\(option.key)")
                    }
                }.padding(.vertical, 2)
            }
        }
    }

    private func resultCard(_ row: GroupBilliardsRow) -> some View {
        BilliardsResultCard(row: row, groupID: groupID, writable: serverWritable && !busy, onAction: { action in
            if action == .correct {
                entry = .init(mode: .manual,
                              variant: row.variant.flatMap(GroupBilliardsVariant.init(rawValue:)) ?? row.rules.knownVariant ?? .folk,
                              activityID: row.activityId, activitySessionID: row.activitySessionId,
                              gameID: row.gameId, correctionID: row.id)
            } else if action == .void {
                askVoid(row)
            } else {
                performResultAction(row, action)
            }
        })
    }

    private func performResultAction(_ row: GroupBilliardsRow, _ action: BilliardsResultAction) {
        guard action == .confirm || action == .authorityConfirm else { return }
        openPrompt(billiardsResultConfirmation(row, authority: action == .authorityConfirm))
    }

    // MARK: 底部操作栏

    @ViewBuilder private var actionBar: some View {
        // 归档 / 解散冷静期（只读）：底栏整个收起，与小组概览同口径（规格 §5.2）。
        if writable, tab == 0 {
            barChrome {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Theme.sm))
                    : AnyLayout(HStackLayout(spacing: Theme.spacing))
                layout {
                    // 「补记赛果 / 开始计分」直接进一步式配置页：不再先弹玩法层选玩法。
                    Button { entry = .init(mode: .manual) } label: {
                        Text(groupText("manual_result", "Add match result")).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(GroupAlignedActionStyle(secondary: true)).disabled(busy)
                        .accessibilityIdentifier("billiards_manual")
                    Button { overviewSetup = true } label: {
                        Text(groupText("start_score", "Start scoring")).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(GroupAlignedActionStyle()).disabled(busy)
                        .accessibilityIdentifier("billiards_start")
                }
            }
        } else if writable, tab == 1, manager, lineup == nil, serverWritable {
            barChrome {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Theme.sm))
                    : AnyLayout(HStackLayout(spacing: Theme.spacing))
                layout {
                    Button(groupText("activity_direct_title", "Arrange now")) { activityCreation = .direct }
                        .buttonStyle(GroupAlignedActionStyle(secondary: true)).disabled(busy)
                    Button(groupText("create_activity", "Create activity")) { activityCreation = .signup }
                        .buttonStyle(GroupAlignedActionStyle()).disabled(busy)
                        .accessibilityIdentifier("billiards_create_activity")
                }
            }
        }
    }

    private func barChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 20).padding(.vertical, Theme.spacing)
            .frame(maxWidth: 960).frame(maxWidth: .infinity)
            .background(Theme.backgroundColor.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Divider() }
    }

    // MARK: 二次确认（作废 / 取消活动 / 放弃本场，失败信息留在弹窗内部）

    private func openPrompt(_ value: BilliardsPrompt) {
        guard !promptBusy else { return }
        promptReason = ""; promptError = nil; prompt = value
    }

    private func closePrompt() {
        guard !promptBusy else { return }
        prompt = nil; promptReason = ""; promptError = nil
    }

    private func askVoid(_ row: GroupBilliardsRow) {
        openPrompt(.init(kind: .voidResult(row), title: billiardsText("void"),
                         message: billiardsText("void_message", "Voiding removes this result from the ranking; re-record it as a correction."),
                         confirm: billiardsText("confirm"), requiresReason: true))
    }

    private func askCancelActivity() {
        openPrompt(.init(kind: .cancelActivity, title: groupText("cancel_activity", "Cancel activity?"),
                         message: groupText("cancel_activity_message", "Cancelling clears the sign-up list permanently. Activities in progress cannot be cancelled."),
                         confirm: groupText("cancel_activity", "Cancel activity"), requiresReason: true))
    }

    private func askAbandon(_ item: BilliardsResume) {
        openPrompt(.init(kind: .abandon(item), title: groupText("abandon_action", "Abandon match"),
                         message: groupText("abandon_message", "Abandon this match to start another. Saved personal records will be kept."),
                         confirm: groupText("abandon_action", "Abandon match")))
    }

    private func confirmPrompt() {
        guard let current = prompt, !promptBusy, let account = store.accountID else { return }
        let revision = store.identityRevision
        let reason = promptReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .cancelActivity = current.kind, !GroupActivityPolicy.validCancellationReason(reason) {
            promptError = groupText("cancel_reason_required", "Enter a reason for cancellation.")
            return
        }
        promptBusy = true; promptError = nil
        Task {
            let success = await store.perform {
                switch current.kind {
                case .voidResult(let row):
                    try await store.repository.action("/\(groupID)/results/\(row.id)/void", body: .init(reason: reason), revision: row.revision)
                case .cancelActivity:
                    guard let activityID = lineupActivityID, !activityID.isEmpty else { throw GroupBilliardsError.result }
                    // 结束 / 取消前先取最新 lineup 拿 revision，避免刚交完成绩就用旧 revision 撞 409。
                    let fresh: GroupBilliardsLineup = try await store.repository.read("/\(groupID)/activities/\(activityID)/lineup")
                    try await store.repository.action("/\(groupID)/activities/\(activityID)/cancel", body: .init(reason: reason), revision: fresh.revision)
                case .completeActivity(let activityID):
                    let fresh: GroupBilliardsLineup = try await store.repository.read("/\(groupID)/activities/\(activityID)/lineup")
                    guard store.matchesIdentity(account, revision: revision) else { throw GroupFlowError.staleSession }
                    try await store.repository.action("/\(groupID)/activities/\(activityID)/complete", revision: fresh.revision)
                case .removeSession(let activityID, let sessionID):
                    let fresh: GroupBilliardsLineup = try await store.repository.read("/\(groupID)/activities/\(activityID)/lineup")
                    guard store.matchesIdentity(account, revision: revision) else { throw GroupFlowError.staleSession }
                    guard fresh.canManage, fresh.sessions.contains(where: { $0.id == sessionID && $0.isFrozen != true })
                    else { throw GroupBilliardsError.result }
                    let sessions = fresh.sessions.filter { $0.id != sessionID }.map(\.submission)
                    let _: GroupBilliardsLineup = try await store.repository.write("/\(groupID)/activities/\(activityID)/lineup",
                        body: GroupBilliardsLineupBody(sessionMinutes: fresh.sessionMinutes, sessions: sessions), method: .put, revision: fresh.revision)
                case .confirmResult(let row, let authority):
                    let _: GroupBilliardsRow = try await store.repository.write("/\(groupID)/results/\(row.id)/confirm",
                        body: GroupConfirmBody(authority: authority), revision: row.revision)
                case .abandon(let item):
                    if let game = item.source.gameID, !game.isEmpty {
                        try await store.repository.action("/\(groupID)/games/\(game)/abandon")
                    }
                    try GroupBilliardsPersistence.shared.abandon(recordID: item.id, source: item.source)
                    // 开赛用全局「未完成会话」拦截：会话不清就再也开不了新赛（对齐安卓 discard + remove）。
                    if let session = ManualResumeSessionStore.sessionID(for: item.id) {
                        try? await ResumeSessionRepository().remove(sessionId: session)
                    }
                }
            }
            guard store.matchesIdentity(account, revision: revision) else { promptBusy = false; return }
            promptBusy = false
            if success {
                prompt = nil; promptReason = ""; promptError = nil
                if case .cancelActivity = current.kind { exitLineup() }
                await reload()
            } else {
                // 失败信息写进弹窗本身：页面 banner 会被弹窗盖住。
                promptError = store.error
            }
        }
    }

    // MARK: 数据

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy, let account = store.accountID else { return }
        busy = true; error = nil
        let revision = store.identityRevision
        Task {
            let success = await store.perform { try await action() }
            guard store.matchesIdentity(account, revision: revision) else { return }
            busy = false
            if success { await reload() } else { error = store.error }
        }
    }

    private func reload() async {
        guard let account = store.accountID else { return }
        if variantAccount != account {
            variantAccount = account
            variant = Self.lastFilterVariant(account: account, groupID: groupID)
            bucket = ""
        }
        let revision = store.identityRevision
        if !loaded, let cached = GroupLocalPersistence.shared.loadDraft(BilliardsBrowseCache.self, key: cacheKey, accountID: account) {
            rows = cached.rows; activities = cached.activities.map { GroupBilliardsActivity(activity: $0) }; ranking = cached.ranking
        }
        do {
            let resultRows: [GroupBilliardsRow] = try await store.repository.allPages("/\(groupID)/results")
            let activityRows: [GroupBilliardsActivity] = try await store.repository.allPages("/\(groupID)/activities")
            var query: [URLQueryItem] = []
            query.append(.init(name: "variant", value: variant.rawValue))
            if !bucket.isEmpty { query.append(.init(name: "bucket", value: bucket)) }
            let rank: GroupBilliardsRanking = try await store.repository.read("/\(groupID)/rankings", query: query)
            var freshLineup: GroupBilliardsLineup?
            if let id = lineupActivityID { freshLineup = try await store.repository.read("/\(groupID)/activities/\(id)/lineup") }
            guard store.matchesIdentity(account, revision: revision), !Task.isCancelled else { return }
            rows = resultRows; activities = activityRows; ranking = rank; lineup = freshLineup; loaded = true
            try? GroupLocalPersistence.shared.saveDraft(BilliardsBrowseCache(rows: resultRows, activities: activityRows.map(\.activity), ranking: rank), key: cacheKey, accountID: account)
            uploads = try GroupBilliardsPersistence.shared.rows(accountID: account, groupID: groupID)
            let sources = try GroupBilliardsPersistence.shared.sources(accountID: account, groupID: groupID)
            let live = try await ResumeSessionRepository().liveEntries()
            let liveIDs = Set(live.map(\.sessionId))
            guard store.matchesIdentity(account, revision: revision), !Task.isCancelled else { return }
            resumes = sources.compactMap { key, source in
                guard let session = ManualResumeSessionStore.sessionID(for: key), liveIDs.contains(session) else { return nil }
                return BilliardsResume(id: key, source: source)
            }.sorted { $0.id < $1.id }
            error = nil
        } catch {
            if store.matchesIdentity(account, revision: revision), !Task.isCancelled { self.error = groupErrorMessage(error) }
        }
    }

    private func resume(_ item: BilliardsResume) {
        run {
            if let game = item.source.gameID, !game.isEmpty {
                let frozen: BilliardsResumeGameState = try await store.repository.read("/\(groupID)/games/\(game)")
                guard frozen.state == "started" else { throw GroupBilliardsError.otherDevice }
            }
            guard let known = item.source.rules.knownVariant else { throw GroupBilliardsError.rules }
            let setup = try item.source.rules.setup(names: item.source.names)
            onStart(known.gameType, setup, item.id)
        }
    }


}

// MARK: - 小部件

nonisolated enum BilliardsChipTone: Sendable { case primary, warning, danger, neutral }

struct BilliardsStatusChip: View {
    var text: String
    var tone: BilliardsChipTone
    private var color: Color {
        switch tone {
        case .primary: Theme.primary
        case .warning: Theme.warningText
        case .danger: Theme.destructiveText
        case .neutral: Theme.textSecondary
        }
    }
    var body: some View {
        Text(text).font(GroupTypography.caption.weight(.medium)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, Theme.sm).padding(.vertical, 3)
            .background(Theme.tintedFill(color, lightAlpha: 0.14, darkAlpha: 0.22), in: Capsule())
    }
}

/// 小组内的胶囊小按钮（对齐安卓 `GroupPillButton`）：主色一律白字，危险操作红字。
struct BilliardsPillButton: View {
    var text: String
    var primary = false
    var destructive = false
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(GroupTypography.caption.weight(.semibold))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                .padding(.horizontal, Theme.spacing).padding(.vertical, 8)
                .frame(minHeight: 34)
                // 次按钮与危险按钮都不再用灰底：浅色白底 + 1px 描边，深色沿用既有层次。
                .foregroundStyle(destructive ? Theme.destructiveText : (primary ? Theme.textOnPrimary : Theme.textPrimary))
                .background(primary ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(BilliardsControlStyle.fill), in: Capsule())
                .overlay(Capsule().strokeBorder(primary ? Theme.primary : BilliardsControlStyle.stroke, lineWidth: 1))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

// MARK: - 赛果卡

/// 赛果卡（概览与战绩共用）：玩法 + 状态 chip、时间、规则摘要、逐人成绩、底部操作。
/// 台球是 2～4 人独立席位，成绩按人逐行展示，不用 A/B 双方大比分格。
struct BilliardsResultCard: View {
    let row: GroupBilliardsRow
    let groupID: String
    var writable = false
    var onAction: (BilliardsResultAction) -> Void = { _ in }
    var showsActions = true
    var sharesDetailLink = true

    private var rulesSummary: String { row.rules.summary }
    private var variantTitle: String { row.rules.knownVariant?.title ?? billiardsText("unsupported") }
    private var statusText: String {
        switch row.status {
        case "confirmed": billiardsText("confirmed")
        case "voided": billiardsText("voided")
        default: billiardsText("pending")
        }
    }
    private var tone: BilliardsChipTone {
        switch row.status {
        case "confirmed": .primary
        case "voided", "disputed": .danger
        default: .warning
        }
    }
    private var timeLine: String {
        var text = Date(timeIntervalSince1970: Double(row.playedAt) / 1000).formatted(date: .abbreviated, time: .shortened)
        if row.result.completion == "early_stop" { text += " · " + billiardsText("early_stop") }
        return text
    }
    private func name(_ seat: GroupBilliardsSeat) -> String {
        let stored = seat.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? seat.memberId : stored
    }
    private func points(_ seat: GroupBilliardsSeat) -> Int? {
        row.result.scores.first { $0.participantId == seat.participant.participantId }?.points
    }

    var body: some View {
        GroupSurface {
            if sharesDetailLink {
                NavigationLink { GroupBilliardsResultDetail(groupID: groupID, resultID: row.id) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("billiards_result_\(row.id)")
            } else { content }
            if showsActions { actions }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.sm) {
                Text(variantTitle).font(GroupTypography.body.weight(.semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BilliardsStatusChip(text: statusText, tone: tone)
            }
            Text(timeLine).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            if !rulesSummary.isEmpty {
                Text(rulesSummary).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(3).groupLineHeight(.caption)
            }
            Divider()
            ForEach(Array(row.participants.enumerated()), id: \.offset) { _, seat in
                scoreRow(seat)
            }
        }.contentShape(Rectangle())
    }

    private func scoreRow(_ seat: GroupBilliardsSeat) -> some View {
        let value = points(seat)
        let folk = row.rules.knownVariant == .folk
        let tint: Color = value == nil || value == 0 ? Theme.textSecondary : (value! > 0 ? .red : .blue)
        let signed = (value ?? 0) > 0 && folk ? "+" : ""
        return HStack(spacing: Theme.sm) {
            GroupAvatar(name: name(seat), size: 24)
            Text(name(seat)).font(GroupTypography.body).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(signed + String(value ?? 0)).font(GroupTypography.body.weight(.semibold))
                .foregroundStyle(tint).monospacedDigit().lineLimit(1)
        }.frame(minHeight: 28)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Theme.sm) {
            ShareLink(item: row.shareText) { Text(NSLocalizedString("share", value: "Share", comment: "")).font(GroupTypography.caption.weight(.semibold)) }
                .accessibilityIdentifier("billiards_share")
            if writable, row.canCorrect == true {
                BilliardsPillButton(text: billiardsText("correct")) { onAction(.correct) }
            }
            if writable, row.canConfirm == true {
                BilliardsPillButton(text: billiardsText("confirm"), primary: true) { onAction(.confirm) }
            }
            if writable, row.canAuthorityConfirm == true {
                BilliardsPillButton(text: billiardsText("owner_confirm"), primary: true) { onAction(.authorityConfirm) }
            }
            if writable, row.canVoid == true, row.status != "voided" {
                BilliardsPillButton(text: billiardsText("void"), destructive: true) { onAction(.void) }
            }
            Spacer(minLength: 0)
        }.padding(.top, Theme.xs)
    }
}

// MARK: - 赛果详情

struct GroupBilliardsResultDetail: View {
    let groupID: String
    let resultID: String
    var detail: GroupDetailCache? = nil
    var onStart: (GameType, SportsSetupResult, String) -> Void = { _, _, _ in }
    @State private var store = GroupStore.shared
    @State private var row: GroupBilliardsRow?
    @State private var error: String?
    @State private var busy = false
    @State private var prompt: BilliardsPrompt?
    @State private var promptReason = ""
    @State private var promptError: String?
    @State private var promptBusy = false
    @State private var entry: BilliardsEntryRequest?

    private var writable: Bool {
        (detail?.group.isActive ?? true) && store.enabled && SessionStore.shared.isAuthenticated && !store.cached
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let error { GroupNotice(text: error) }
                if let row {
                    BilliardsResultCard(row: row, groupID: groupID, writable: writable, onAction: { action in
                        switch action {
                        case .correct:
                            entry = .init(mode: .manual, variant: row.variant.flatMap(GroupBilliardsVariant.init(rawValue:)) ?? row.rules.knownVariant ?? .folk,
                                          activityID: row.activityId, activitySessionID: row.activitySessionId,
                                          gameID: row.gameId, correctionID: row.id)
                        case .void:
                            promptReason = ""; promptError = nil
                            prompt = .init(kind: .voidResult(row), title: billiardsText("void"),
                                           message: billiardsText("void_message", "Voiding removes this result from the ranking; re-record it as a correction."),
                                           confirm: billiardsText("confirm"), requiresReason: true)
                        default:
                            perform(action, row: row)
                        }
                    }, sharesDetailLink: false)
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.padding)
                }
            }.padding(Theme.padding).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(groupText("match_detail", "Match details")).navigationBarTitleDisplayMode(.inline)
        .groupAccountBoundary()
        .refreshable { await reload() }
        .navigationDestination(isPresented: Binding(get: { entry != nil }, set: { if !$0 { entry = nil } })) {
            // 更正入口与战绩页共用同一个补记页面：小组详情从 store 缓存取（台球页签已加载过）。
            if let entry, let context = detail ?? store.cache.details[groupID] {
                GroupBilliardsEntryView(detail: context, request: entry, onStart: onStart)
            }
        }
        .onChange(of: entry?.id) { _, next in if next == nil { Task { await reload() } } }
        .overlay {
            if let prompt {
                BilliardsPromptDialog(prompt: prompt, reason: $promptReason, error: promptError, busy: promptBusy,
                                      onCancel: { if !promptBusy { self.prompt = nil; promptError = nil } },
                                      onConfirm: confirmPrompt)
            }
        }
        .task { await reload() }
    }

    private func confirmPrompt() {
        guard let prompt, !promptBusy, let account = store.accountID else { return }
        let revision = store.identityRevision
        let reason = promptReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.requiresReason || !reason.isEmpty else { return }
        promptBusy = true; promptError = nil
        Task {
            let success = await store.perform {
                switch prompt.kind {
                case .voidResult(let row):
                    try await store.repository.action("/\(groupID)/results/\(row.id)/void", body: .init(reason: reason), revision: row.revision)
                case .confirmResult(let row, let authority):
                    let _: GroupBilliardsRow = try await store.repository.write("/\(groupID)/results/\(row.id)/confirm",
                        body: GroupConfirmBody(authority: authority), revision: row.revision)
                default: throw GroupBilliardsError.result
                }
            }
            guard store.matchesIdentity(account, revision: revision) else { promptBusy = false; return }
            promptBusy = false
            if success {
                self.prompt = nil; promptReason = ""; promptError = nil
                await reload()
            } else {
                promptError = store.error
            }
        }
    }

    private func perform(_ action: BilliardsResultAction, row: GroupBilliardsRow) {
        guard !busy, action == .confirm || action == .authorityConfirm else { return }
        promptReason = ""; promptError = nil
        prompt = billiardsResultConfirmation(row, authority: action == .authorityConfirm)
    }

    private func reload() async {
        guard let account = store.accountID else { return }
        let revision = store.identityRevision
        do {
            let loaded: GroupBilliardsRow = try await store.repository.read("/\(groupID)/results/\(resultID)")
            guard store.matchesIdentity(account, revision: revision), !Task.isCancelled else { return }
            row = loaded; error = nil
        } catch {
            if store.matchesIdentity(account, revision: revision), !Task.isCancelled { self.error = groupErrorMessage(error) }
        }
    }
}

// MARK: - 排行表

/// 台球排行：民间追分用净积分榜，其它玩法用胜场榜。
/// 与 `GroupRankingTable` 共用同一套排名徽标 / 头像 / 右对齐数字，只是列不同。
struct BilliardsRankingTable: View {
    let items: [GroupBilliardsRank]
    let variant: GroupBilliardsVariant
    let members: [GroupMember]
    let myMemberID: String?
    let groupID: String
    @ScaledMetric(relativeTo: .subheadline) private var identityWidth: CGFloat = 168
    @ScaledMetric(relativeTo: .subheadline) private var columnMinimum: CGFloat = 40
    @ScaledMetric(relativeTo: .caption2) private var badgeSize: CGFloat = 24

    private var folk: Bool { variant == .folk }
    private var setsHeader: String {
        [.eight, .snooker].contains(variant) ? groupText("ranking_sets", "Score") : groupText("net_points", "Net points")
    }
    private var headers: [String] {
        folk
            ? [groupText("ranking_games", "GP"), groupText("net_points", "Net points"), groupText("average_points", "Average")]
            : [groupText("ranking_games", "GP"), groupText("ranking_wins", "W"), groupText("ranking_losses", "L"),
               groupText("ranking_draws", "D"), setsHeader, groupText("ranking_rate", "Win rate")]
    }
    private func cells(_ row: GroupBilliardsRank) -> [String] {
        if folk { return [String(row.games), row.signedPoints, row.averageText] }
        let points = [.eight, .snooker].contains(variant) ? String(row.totalPoints ?? 0) : GroupBilliardsRank.signed(row.totalPoints ?? 0)
        return [String(row.games), String(row.wins ?? 0), String(row.losses ?? 0), String(row.draws ?? 0), points,
                row.qualifiedWinRate ?? groupText("ranking_insufficient_matches", "Too few matches")]
    }
    private var widths: [CGFloat] {
        let body = UIFont.preferredFont(forTextStyle: .subheadline).withSemibold()
        let header = UIFont.preferredFont(forTextStyle: .caption2).withSemibold()
        return headers.indices.map { index in
            let heading = (headers[index] as NSString).size(withAttributes: [.font: header]).width
            let value = items.map { (cells($0)[index] as NSString).size(withAttributes: [.font: body]).width }.max() ?? 0
            return max(columnMinimum, max(heading, value) + 8)
        }
    }

    var body: some View {
        let columnWidths = widths
        GroupSurface {
            Text(billiardsText("ranking") + " · " + variant.title)
                .font(GroupTypography.body.weight(.semibold)).foregroundStyle(Theme.textSecondary).lineLimit(2)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("").frame(minWidth: identityWidth, maxWidth: .infinity)
                        ForEach(headers.indices, id: \.self) { index in
                            Text(headers[index]).font(GroupTypography.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).frame(width: columnWidths[index], alignment: .trailing)
                        }
                    }.padding(.vertical, Theme.xs)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                        let rank = row.rank > 0 ? row.rank : index + 1
                        NavigationLink {
                            GroupMemberResultsView(groupID: groupID, memberID: row.memberId, name: row.name,
                                                   format: folk ? .individuals : .singles)
                        } label: {
                            HStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    Text(String(rank)).font(GroupTypography.caption.bold())
                                        .foregroundStyle(rank <= 3 ? Theme.primary : Theme.textSecondary)
                                        .frame(width: badgeSize, height: badgeSize)
                                        .background((rank <= 3 ? Theme.primary : Theme.textSecondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    GroupAvatar(name: row.name, url: members.first { $0.id == row.memberId }?.avatarUrl, size: 24)
                                    Text(row.name + (!row.memberId.isEmpty && row.memberId == myMemberID ? groupText("ranking_me_suffix", " (me)") : ""))
                                        .font(GroupTypography.body.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }.frame(minWidth: identityWidth, maxWidth: .infinity, alignment: .leading)
                                ForEach(headers.indices, id: \.self) { column in
                                    let highlighted = (folk ? column == 1 : column == headers.count - 1) && rank <= 3
                                    Text(cells(row)[column]).font(GroupTypography.body.weight(highlighted ? .bold : .regular))
                                        .foregroundStyle(highlighted ? Theme.primary : Theme.textPrimary)
                                        .lineLimit(1).monospacedDigit()
                                        .frame(width: columnWidths[column], alignment: .trailing)
                                }
                            }.padding(.vertical, Theme.sm).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("billiards_rank_row_" + row.memberId)
                    }
                }
            }.accessibilityIdentifier("billiards_rank_table")
        }
    }
}

private extension UIFont {
    func withSemibold() -> UIFont {
        UIFont(descriptor: fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]]), size: pointSize)
    }
}

// MARK: - 创建活动

private struct GroupBilliardsActivityEditor: View {
    let detail: GroupDetailCache
    let direct: Bool
    let onStart: (GameType, SportsSetupResult, String) -> Void
    let onCreated: (GroupBilliardsActivity) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var title = ""
    @State private var place = ""
    @State private var note = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var deadline: Date?
    @State private var capacity = 8
    @State private var rules = GroupBilliardsRules.defaults(.folk)
    @State private var entry: BilliardsEntryRequest?
    @State private var error: String?
    @State private var busy = false
    @State private var submissionKey = UUID().uuidString

    private var deadlineSelection: Binding<Date> {
        Binding(get: { deadline ?? date }, set: { deadline = $0 })
    }
    private var heading: String {
        direct ? groupText("activity_direct_title", "Arrange now") : groupText("create_activity", "Create activity")
    }

    var body: some View {
        if let entry {
            GroupBilliardsEntryView(detail: detail, request: entry, onStart: onStart)
        } else {
            Form {
                Section {
                    TextField(billiardsText("activity_name"), text: $title)
                    TextField(billiardsText("place"), text: $place)
                    DatePicker(billiardsText("activity_date"), selection: $date, in: Date()...)
                        .onChange(of: date) { _, value in
                            if let deadline, deadline > value { self.deadline = value }
                        }
                    if !direct {
                        DatePicker(groupText("registration_closes", "Registration deadline"), selection: deadlineSelection,
                                   in: ...date)
                        Stepper("\(groupText("capacity", "Capacity")) \(capacity)",
                                value: $capacity, in: 2...100)
                    }
                    TextField(groupText("note", "Note (optional)"), text: $note, axis: .vertical).lineLimit(2...5)
                }
                GroupBilliardsRulesFields(rules: $rules)
                if let error { GroupNotice(text: error) }
            }
            .disabled(busy)
            .tint(Theme.primary)
            .navigationTitle(heading).navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(busy)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GroupAlignedFooter {
                    Button(direct ? groupText("edit_lineup", "Arrange match") : heading) {
                        Task { await submit() }
                    }
                    .buttonStyle(GroupAlignedActionStyle())
                    .disabled(busy || !store.enabled || date <= .now || (!direct && deadlineSelection.wrappedValue <= .now))
                    .accessibilityIdentifier("billiards_activity_save")
                }
            }
            .task {
                if let account = store.accountID,
                   let remembered = try? GroupBilliardsPersistence.shared.rememberedRules(accountID: account, groupID: detail.group.id),
                   remembered.knownVariant != nil {
                    rules = remembered
                }
            }
        }
    }

    private func submit() async {
        let closes = direct ? date : deadlineSelection.wrappedValue
        guard !busy, let account = store.accountID, date > .now, closes > .now, closes <= date else { return }
        busy = true; error = nil
        defer { busy = false }
        let revision = store.identityRevision
        do {
            try rules.validate()
            let body = GroupBilliardsActivityBody(title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)),
                                                  startsAt: Int64(date.timeIntervalSince1970 * 1000),
                                                  place: String(place.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)), timingMode: "sequence",
                                                  activityType: direct ? "direct" : "signup", defaultMatchConfig: rules,
                                                  capacity: direct ? 100 : capacity,
                                                  registrationClosesAt: Int64(closes.timeIntervalSince1970 * 1000),
                                                  note: String(note.prefix(300)))
            let created: GroupBilliardsActivity = try await store.repository.write("/\(detail.group.id)/activities", body: body, key: submissionKey)
            guard store.matchesIdentity(account, revision: revision) else { return }
            onCreated(created)
            if direct {
                entry = .init(mode: .arrange, variant: rules.knownVariant, activityID: created.id,
                              rules: created.defaultRules ?? rules)
            } else {
                dismiss()
            }
        } catch {
            if store.matchesIdentity(account, revision: revision) { self.error = groupErrorMessage(error) }
        }
    }
}
