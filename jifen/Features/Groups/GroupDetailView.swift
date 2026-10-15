import SwiftUI

struct GroupDetailView: View {
    let groupID: String
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var initiallyShare = false
    var initialTab = 0
    @State private var initialDestinationHandled = false
    @State private var store = GroupStore.shared
    @State private var tab = 0
    @State private var rankFormat = GroupFormat.singles
    @State private var recordFormat: GroupFormat?
    @State private var management: GroupManagementAction?
    @State private var match = false
    @State private var manual = false
    @State private var newActivity = false
    @State private var directSchedule = false
    @State private var sharing = false
    @State private var reporting = false
    @State private var requests: [GroupJoinRequest] = []
    @State private var requestError: String?
    @State private var busyRequests = Set<String>()
    @State private var confirmResult: GroupResult?
    @State private var busyResults = Set<String>()
    @State private var memberQuery = ""
    @State private var repairUpload: GroupPendingUpload?
    @State private var discardUpload: GroupPendingUpload?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var detail: GroupDetailCache? { store.cache.details[groupID] }
    private var me: GroupMember? { detail?.members.first { $0.accountId == store.accountID } }
    private var manager: Bool { ["owner", "admin"].contains(me?.role ?? "") }
    private var writable: Bool { detail?.group.isActive == true && !store.cached && SessionStore.shared.isAuthenticated && store.enabled }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            if let detail {
                ScrollView {
                    VStack(spacing: 20) {
                        if let error = store.detailErrors[groupID] { GroupNotice(text: error) }
                        if store.cached { GroupNotice(text: groupText("cached", "Showing saved data. Connect to refresh.")) }
                        if detail.group.status == "dissolving", let date = detail.group.dissolveAt {
                            dissolveBanner(date: date)
                        } else if !detail.group.isActive {
                            GroupNotice(text: groupText("archive_readonly", "This group is archived. Its history is read-only."))
                        }
                        switch tab {
                        case 0: overview(detail)
                        case 1:
                            if detail.group.isCoaching { GroupTrainingTab(detail: detail, onStart: onStart, onReload: reload) }
                            else { activities(detail) }
                        case 2: results(detail)
                        default: members(detail)
                        }
                    }.padding(20).frame(maxWidth: 960)
                        .frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively).refreshable { await reload() }
            } else if let error = store.detailErrors[groupID] {
                GroupEmptyCard(text: error, actionTitle: groupText("retry", "Retry")) { Task { await reload() } }
                    .padding(20)
            } else { ProgressView().frame(maxHeight: .infinity) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == 0, let detail { overviewActionBar(detail) }
            if tab == 1, let detail, !detail.group.isCoaching, detail.group.isActive, manager {
            VStack(spacing: 0) {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Button { directSchedule = true } label: {
                            Text(groupText("activity_direct_title", "Direct match")).font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.bordered).frame(maxWidth: .infinity).accessibilityIdentifier("group_activity_direct")
                        Button { newActivity = true } label: {
                            Label(groupText("new_activity", "Plan an activity"), systemImage: "plus").font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).accessibilityIdentifier("group_activity_create")
                    }.disabled(!writable).tint(Theme.primary).padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(maxWidth: 960).frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(detail?.group.name ?? groupText("group", "Group"))
        .navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { managementMenu } }
        .task {
            let shouldShare = initiallyShare && !initialDestinationHandled
            if !initialDestinationHandled { tab = initialTab; initialDestinationHandled = true }
            await reload(); if shouldShare && !Task.isCancelled { sharing = true }
        }
        .sheet(item: $repairUpload, onDismiss: { Task { await reload() } }) { GroupUploadRepairView(upload: $0) }
        .confirmationDialog(groupText("confirm_result", "Confirm result"), isPresented: Binding(get: { confirmResult != nil }, set: { if !$0 { confirmResult = nil } })) {
            if let row = confirmResult { Button(groupText(GroupPermissions.confirmation(row, group: detail?.group, me: me).authority ? "authority_confirm" : "confirm_result", "Confirm result")) { Task { await confirm(row) } } }
        }
        .confirmationDialog(groupText("discard_upload", "Discard this upload?"), isPresented: Binding(get: { discardUpload != nil }, set: { if !$0 { discardUpload = nil } })) { if let item = discardUpload { Button(groupText("discard_upload", "Discard upload"), role: .destructive) { store.discardUpload(item.id); discardUpload = nil } } }
        .task(id: recordFormat) { await store.loadHistory(groupID, format: recordFormat) }
        .task(id: rankFormat) { await store.loadRankings(groupID, format: rankFormat) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshFeatureFlag(); await store.sync(); await reload() } }
        }
        .sheet(item: $management, onDismiss: { Task { await reload(); await store.refresh() } }) { action in GroupManagementView(groupID: groupID, action: action) }
        .sheet(isPresented: $newActivity, onDismiss: { Task { await reload() } }) { GroupActivityCreateView(groupID: groupID) }
        .sheet(isPresented: $directSchedule, onDismiss: { Task { await reload() } }) { if let detail { GroupDirectScheduleView(detail: detail) } }
        .navigationDestination(isPresented: $sharing) { if let group = detail?.group { GroupShareView(group: group) } }
        .sheet(isPresented: $reporting) { GroupReportView(groupID: groupID) }
        .sheet(isPresented: $match) { if let detail { GroupMatchEditor(detail: detail, manual: false, onStart: onStart) } }
        .sheet(isPresented: $manual, onDismiss: { Task { await reload() } }) { if let detail { GroupMatchEditor(detail: detail, manual: true, onStart: onStart) } }
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder private var tabs: some View {
        let titles = [groupText("overview", "Overview"), detail?.group.isCoaching == true ? groupText("training", "Training") : groupText("activities", "Activities"), groupText("results", "Matches"), groupText("members", "Members")]
        if dynamicTypeSize.isAccessibilitySize {
            Picker(groupText("group", "Group"), selection: $tab) { ForEach(0..<4, id: \.self) { index in Text(titles[index]).tag(index) } }
                .pickerStyle(.menu).font(.headline).tint(Theme.primary).frame(maxWidth: 960)
                .padding(.horizontal, 20).padding(.vertical, 10).accessibilityIdentifier("group_tab_\(tab)")
        } else { HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Button { tab = index } label: {
                    HStack(spacing: 5) {
                        Text(titles[index]).font(.subheadline.weight(tab == index ? .semibold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if index == 3, manager, !requests.isEmpty { Circle().fill(Theme.homePrimaryCardOrange).frame(width: 6, height: 6) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(tab == index ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(tab == index ? .white : Theme.textSecondary)
                }.buttonStyle(.plain).accessibilityIdentifier("group_tab_\(index)")
                    .accessibilityAddTraits(tab == index ? .isSelected : [])
            }
        }.padding(3).background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: 960)
        }
    }

    private var managementMenu: some View {
        Menu {
            ForEach(menuPolicy.entries, id: \.self) { entry in
                if let key = entry.titleKey {
                    Button(groupText(key, key), role: entry.isDestructive ? .destructive : nil) { menuAction(entry) }
                        .disabled(entry == .report ? !store.hasIdentity : !canManage)
                        .accessibilityIdentifier("group_menu_" + entry.rawValue)
                } else {
                    Divider()
                }
            }
        } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)) }
            .disabled(store.mutating)
            .accessibilityLabel(groupText("settings", "Group management"))
    }

    /// 组内自管理动作的可用条件：离线缓存 / 未登录时不给入口。
    /// 这里刻意不带 `isActive`——归档小组要能「恢复」、冷静期小组要能「撤销解散」，
    /// 状态本身该由 `menuPolicy.entries` 的显隐吸收，而不是一把全禁。
    private var canManage: Bool { !store.cached && store.enabled && SessionStore.shared.isAuthenticated }
    private var menuPolicy: GroupManagementMenu {
        .init(role: me?.status == "active" ? me?.role : nil, status: detail?.group.status ?? "")
    }

    private func menuAction(_ entry: GroupManagementMenu.Entry) {
        switch entry {
        case .editProfile: management = .init(kind: "profile")
        case .transfer: management = .init(kind: "transfer")
        case .archive: management = .init(kind: "archive")
        case .restore: management = .init(kind: "restore")
        case .cancelDissolve: management = .init(kind: "cancel_dissolve")
        case .dissolve: management = .init(kind: "dissolve")
        case .leave: management = .init(kind: "leave")
        case .report: reporting = true
        case .divider: break
        }
    }

    /// 解散冷静期横幅（对齐安卓 GroupDissolveBanner 改版）：只读说明 + 组长可就地撤销解散。
    private func dissolveBanner(date: Int64) -> some View {
        let owner = me?.role == "owner"
        let text = String(
            format: NSLocalizedString("group_banner_dissolving", value: "Group will be dissolved on %@\n7-day cooling-off period; read-only until then", comment: "Groups"),
            Date(timeIntervalSince1970: Double(date) / 1000).formatted(date: .abbreviated, time: .omitted)
        )
        return HStack(spacing: Theme.sm) {
            Text(text).font(.footnote).foregroundStyle(Theme.warningText)
                .multilineTextAlignment(owner ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: owner ? .leading : .center)
            if owner {
                Button { management = .init(kind: "cancel_dissolve") } label: {
                    Text(groupText("cancel_dissolve", "Cancel dissolution")).font(.footnote.weight(.semibold))
                        .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
                        .background(.regularMaterial, in: Capsule())
                }.buttonStyle(.plain).disabled(store.cached).accessibilityIdentifier("group_dissolve_cancel")
            }
        }
        .padding(.horizontal, Theme.md).padding(.vertical, Theme.sm)
        .background(Theme.tintedFill(Theme.warningText, lightAlpha: 0.12, darkAlpha: 0.18), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("group_dissolve_banner")
    }

    private func reload() async {
        await store.loadDetail(groupID, format: rankFormat)
        await store.loadHistory(groupID, format: recordFormat)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") {
            requests = ProcessInfo.processInfo.arguments.contains("-UITestGroupsEmpty") ? [] : [
                .init(id: "ui-join", groupId: groupID, groupNo: "12345678", groupName: "球友小组", sport: .badminton, accountId: "ui-new-member", displayName: "新队友", status: "pending", message: "想一起打球", createdAt: Int64(Date().timeIntervalSince1970 * 1000), decidedAt: nil)
            ]
            return
        }
        #endif
        guard manager, let account = store.accountID else { requests = []; return }
        let revision = store.identityRevision
        do {
            let loaded: [GroupJoinRequest] = try await store.repository.allPages("/\(groupID)/join-requests")
            guard store.matchesIdentity(account, revision: revision), !Task.isCancelled else { return }
            requests = loaded.filter { $0.status == "pending" }; requestError = nil
        } catch { if store.matchesIdentity(account, revision: revision), !Task.isCancelled { requestError = groupErrorMessage(error) } }
    }

    @ViewBuilder private func overview(_ d: GroupDetailCache) -> some View {
        GroupSurface {
            if dynamicTypeSize.isAccessibilitySize {
                HStack { AppCatalogIcon(gameType: d.group.sport.gameType, size: 52); Text(d.group.name).font(.title3.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                Button { UIPasteboard.general.string = d.group.groupNo } label: { Label(GroupQRPayload.formatted(d.group.groupNo), systemImage: "doc.on.doc").monospacedDigit() }.font(.caption).buttonStyle(.plain).foregroundStyle(Theme.primary)
                Text(d.group.sport.title).font(.caption)
                HStack {
                    if overviewActions(d).showSecondaryInvite { Button(groupText(d.group.isCoaching ? "invite_students" : "invite", "Invite")) { sharing = true }.font(.caption).disabled(!writable).accessibilityIdentifier("group_secondary_invite") }
                    Spacer(); Button { sharing = true } label: { GroupQRCode(number: d.group.groupNo, size: 72) }.buttonStyle(.plain).accessibilityLabel(groupText("group_qr", "Group QR code"))
                }
                if !d.group.isActive { Text(groupText(d.group.status, d.group.status)).font(.caption).foregroundStyle(.secondary) }
            } else {
            HStack(spacing: 12) {
                AppCatalogIcon(gameType: d.group.sport.gameType, size: 52)
                VStack(alignment: .leading, spacing: 8) {
                    Text(d.group.name).font(.title3.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Button { UIPasteboard.general.string = d.group.groupNo } label: {
                            HStack(spacing: 4) { Text(GroupQRPayload.formatted(d.group.groupNo)).monospacedDigit(); Image(systemName: "doc.on.doc") }
                        }.buttonStyle(.plain).foregroundStyle(Theme.primary)
                        Text(d.group.sport.title)
                    }.font(.caption)
                    if d.group.isCoaching { Text(groupText("coaching", "Coaching group")).font(.caption).foregroundStyle(Theme.primary) }
                    if !d.group.isActive { Text(groupText(d.group.status, d.group.status)).font(.caption).foregroundStyle(.secondary) }
                    if overviewActions(d).showSecondaryInvite {
                        Button { sharing = true } label: {
                            Label(groupText(d.group.isCoaching ? "invite_students" : "invite", "Invite"), systemImage: "person.badge.plus")
                                .font(.caption.weight(.semibold))
                        }.buttonStyle(.plain).foregroundStyle(Theme.primary).disabled(!writable)
                            .accessibilityIdentifier("group_secondary_invite")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { sharing = true } label: { GroupQRCode(number: d.group.groupNo, size: 72) }
                    .buttonStyle(.plain).accessibilityLabel(groupText("group_qr", "Group QR code"))
            }
            }
            if !d.group.description.isEmpty { Text(d.group.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
            if overviewActions(d).showStats { Divider()
            if dynamicTypeSize.isAccessibilitySize {
                LabeledContent(groupText("confirmed_matches", "Confirmed matches"), value: "\(d.stats?.confirmedMatchCount ?? 0)")
                LabeledContent(groupText("month_matches", "This month"), value: "\(d.stats?.currentMonthMatchCount ?? 0)")
                LabeledContent(groupText("active_30d", "Active in 30 days"), value: "\(d.stats?.activeMemberCount30d ?? 0)")
            } else { HStack(spacing: 0) {
                stat(groupText("confirmed_matches", "Confirmed matches"), d.stats?.confirmedMatchCount ?? 0)
                Divider().frame(height: 30)
                stat(groupText("month_matches", "This month"), d.stats?.currentMonthMatchCount ?? 0)
                Divider().frame(height: 30)
                stat(groupText("active_30d", "Active in 30 days"), d.stats?.activeMemberCount30d ?? 0)
            }
            }
            }
        }
        if d.group.isCoaching, me?.role == "owner", let count = d.leaveNotices?.filter({ $0.status == "open" }).count, count > 0 {
            Button { tab = 1 } label: { GroupSurface { HStack { Text(groupText("leave_notices", "Student leave notices")); Spacer(); Text("\(count)"); Image(systemName: "chevron.right") } } }.buttonStyle(.plain)
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if d.group.isCoaching {
            let sessions = (d.trainingPlans ?? []).flatMap { plan in plan.sessions.filter { plan.status != "cancelled" || !($0.startedGameId ?? "").isEmpty } }
                .filter { $0.status == "scheduled" && $0.resultId.isEmpty && (GroupPermissions.coach(d.group, member: me) || $0.mySide != nil || $0.seats.contains { $0.memberId == me?.id }) }.sorted { $0.startsAt < $1.startsAt }
            if let current = sessions.first(where: { $0.startsAt <= now && $0.endsAt > now }) { overviewTraining(current, title: groupText("in_progress", "In progress")) }
            if let upcoming = sessions.first(where: { $0.startsAt > now }) { overviewTraining(upcoming, title: groupText("upcoming", "Upcoming")) }
            if let overdue = sessions.first(where: { $0.endsAt <= now }) { overviewTraining(overdue, title: NSLocalizedString("schedule_time_status_overdue", comment: "")) }
        } else {
            let upcoming = d.activities.filter { $0.status == "in_progress" || ($0.status == "recruiting" && $0.startsAt >= now) }
                .sorted { ($0.status == "in_progress" ? 0 : 1, $0.startsAt) < ($1.status == "in_progress" ? 0 : 1, $1.startsAt) }
            if let item = upcoming.first { GroupSectionTitle(title: groupText("upcoming", "Upcoming"), navigate: { tab = 1 }); activityRow(item, detail: d) }
            if let item = d.activities.filter({ $0.status == "recruiting" && $0.startsAt < now }).min(by: { $0.startsAt < $1.startsAt }) {
                GroupSectionTitle(title: NSLocalizedString("schedule_time_status_overdue", comment: ""), navigate: { tab = 1 }); activityRow(item, detail: d)
            }
        }
        let pending = GroupPermissions.confirmationTasks(d.pendingResults ?? d.results, group: d.group, me: me)
        if !pending.isEmpty { Button { tab = 2 } label: { GroupSurface { HStack { Text(groupText("pending_confirmation", "To confirm")); Spacer(); Text("\(pending.count)"); Image(systemName: "chevron.right") } } }.buttonStyle(.plain) }
        if overviewActions(d).showLatestResults {
            GroupSectionTitle(title: groupText("latest_results", "Latest results"), navigate: { tab = 2 })
            if let result = d.results.first ?? pending.first { resultRow(result) }
            else { GroupEmptyCard(text: groupText("no_results", "No matches recorded yet")) }
        }
    }

    private func overviewTraining(_ session: GroupTrainingSession, title: String) -> some View {
        VStack(spacing: 20) { GroupSectionTitle(title: title, navigate: { tab = 1 }); Button { tab = 1 } label: {
            GroupSurface { Text(session.court); Text(session.date, format: .dateTime.month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary); Text(session.format.title).font(.caption) }
        }.buttonStyle(.plain) }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 5) { Text("\(value)").font(.title2.bold()); Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity).padding(.vertical, 4)
    }
    private func overviewActions(_ d: GroupDetailCache) -> GroupOverviewActions {
        .init(group: d.group, memberCount: d.group.memberCount ?? d.members.filter { $0.status == "active" }.count,
              hasResults: !d.results.isEmpty || !(d.pendingResults ?? []).isEmpty,
              confirmedMatchCount: d.stats?.confirmedMatchCount ?? 0, isCoach: GroupPermissions.coach(d.group, member: me))
    }

    @ViewBuilder private func overviewActionBar(_ d: GroupDetailCache) -> some View {
        let policy = overviewActions(d)
        if !policy.actions.isEmpty {
            VStack(spacing: 0) {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    ForEach(policy.actions, id: \.rawValue) { action in
                        if action == .addResult {
                            overviewButton(action, group: d.group).buttonStyle(.bordered)
                        } else {
                            overviewButton(action, group: d.group).buttonStyle(.borderedProminent)
                                .disabled(action == .invite && !policy.canInvite)
                        }
                    }
                }.disabled(!writable).tint(Theme.primary).padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: 960).frame(maxWidth: .infinity)
            }
        }
    }

    private func overviewButton(_ action: GroupOverviewActions.Action, group: ScoreGroup) -> some View {
        let key = action == .invite ? (group.isCoaching ? "invite_students" : "invite") : action == .training ? "training" : action == .start ? "start_score" : "manual_result"
        let icon = action == .invite ? "person.badge.plus" : action == .addResult ? "square.and.pencil" : "play.fill"
        return Button {
            switch action {
            case .invite: sharing = true
            case .training: tab = 1
            case .start: match = true
            case .addResult: manual = true
            }
        } label: {
            Label(groupText(key, key), systemImage: icon).font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 32)
        }.frame(maxWidth: .infinity).accessibilityIdentifier("group_overview_" + action.rawValue)
    }

    @ViewBuilder private func activities(_ d: GroupDetailCache) -> some View {
        let archived = !d.group.isActive
        if d.activities.isEmpty {
            GroupEmptyCard(text: groupText("empty_activities_title", "No activities yet"))
            if !archived {
                Text(groupText(manager ? "empty_activities_hint" : "activity_create_admin_hint",
                               manager ? "Plan an activity so members can sign up." : "Activities are created by the leader or an admin."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        } else {
            let upcoming = d.activities.filter { $0.status != "completed" && $0.status != "cancelled" }
                .sorted { ($0.status == "in_progress" ? 0 : 1, $0.startsAt) < ($1.status == "in_progress" ? 0 : 1, $1.startsAt) }
            let past = d.activities.filter { $0.status == "completed" || $0.status == "cancelled" }.sorted { $0.startsAt > $1.startsAt }
            if !upcoming.isEmpty {
                GroupSectionTitle(title: groupText("activity_section_upcoming", "In progress · Open for sign-ups"), subtitle: activitySectionCount(upcoming.count))
                ForEach(upcoming) { activityRow($0, detail: d) }
            }
            if !past.isEmpty {
                GroupSectionTitle(title: groupText("activity_section_past", "Past activities"), subtitle: activitySectionCount(past.count))
                ForEach(past) { activityRow($0, detail: d) }
            }
            if !archived, !manager {
                Text(groupText("activity_create_admin_hint", "Activities are created by the leader or an admin."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, Theme.sm)
            }
        }
    }
    private func activitySectionCount(_ count: Int) -> String { String(format: groupText("activity_section_count", "%d events"), count) }
    private func activityTimeLine(_ item: GroupActivity) -> String {
        var text = item.isSequenced
            ? item.date.formatted(.dateTime.year().month().day()) + " · " + groupText("activity_timing_sequence", "No fixed time")
            : item.date.formatted(date: .abbreviated, time: .shortened)
        if !item.place.isEmpty { text += " · " + item.place }
        return text
    }
    private func activityCountLine(_ item: GroupActivity) -> String {
        if item.isDirect { return String(format: NSLocalizedString("activity_direct_match_count", value: "%d matches · all group members", comment: "Groups"), item.sessionCount ?? 0) }
        var text = String(format: groupText("activity_count", "%d/%d registered"), item.registeredMemberIds.count, item.capacity)
        if item.status == "recruiting", item.capacity > 0, item.registeredMemberIds.count >= item.capacity { text += " · " + groupText("activity_full", "Full") }
        return text
    }
    private func activityDisplayStatus(_ item: GroupActivity) -> String {
        if item.isDirect, item.status == "recruiting" { return groupText("activity_status_scheduled", "Scheduled") }
        return groupText(item.status, item.status)
    }
    private func activityRow(_ item: GroupActivity, detail: GroupDetailCache) -> some View {
        NavigationLink { GroupActivityView(detail: detail, activity: item, onStart: onStart) } label: {
            GroupSurface {
                HStack(alignment: .center, spacing: Theme.sm) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: Theme.xs) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            GroupActivityTagChip(text: item.isDirect ? groupText("activity_direct_title", "Direct match") : item.format.title)
                        }
                        Text(activityTimeLine(item)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(activityCountLine(item)).font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    GroupActivityStatusChip(text: activityDisplayStatus(item), status: item.status)
                }
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func results(_ d: GroupDetailCache) -> some View {
        if let requestError { GroupNotice(text: requestError) }
        let uploads = store.uploads.filter { $0.groupID == groupID }
        ForEach(uploads) { upload in
            GroupSurface {
                Text(groupText("pending_upload", "Waiting to upload") + " · \(upload.body.setScore.a):\(upload.body.setScore.b)")
                Text(Date(timeIntervalSince1970: Double(upload.body.playedAt) / 1000), format: .dateTime)
                Text(upload.body.participants.map { seat in seat.displayName ?? d.members.first(where: { $0.id == seat.memberId })?.displayName ?? "" }.joined(separator: " / "))
                if let failure = upload.failure { GroupNotice(text: failure) }
                Button(groupText("sync", "Sync now")) { Task { await store.retryUpload(upload.id); await reload() } }
                if upload.failure != nil { Button(groupText("repair_upload", "Correct result")) { repairUpload = upload } }
                if upload.body.gameId != nil || upload.existingResultID != nil { NavigationLink(groupText("existing_result", "View cloud result")) { GroupExistingUploadResultView(upload: upload) } }
                Button(groupText("discard_upload", "Discard upload"), role: .destructive) { discardUpload = upload }
            }
        }
        let allPending = d.pendingResults ?? d.results.filter { $0.status == "pending_confirmation" }
        let pending = GroupPermissions.confirmationTasks(allPending, group: d.group, me: me)
        if !pending.isEmpty {
            GroupSectionTitle(title: groupText("pending_confirmation", "To confirm"), count: pending.count)
            ForEach(pending) { row in
                GroupSurface {
                    GroupResultLink(result: row)
                    let permission = GroupPermissions.confirmation(row, group: d.group, me: me)
                    if permission.allowed { Button(groupText(permission.authority ? "authority_confirm" : "confirm_result", "Confirm result")) { confirmResult = row }.buttonStyle(.borderedProminent).disabled(!writable || busyResults.contains(row.id)) }
                    else {
                        let names = GroupPermissions.waitingNames(row, members: d.members)
                        Text(groupText("pending_confirmation", "Waiting for confirmation") + (names.isEmpty ? "" : " · " + names.joined(separator: " / "))).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        let recordsEmpty = d.rankings.isEmpty && d.results.isEmpty && allPending.isEmpty && uploads.isEmpty && recordFormat == nil
        rankingSection(d, recordsEmpty: recordsEmpty)
        let historyKey = groupID + ":" + (recordFormat?.rawValue ?? "all")
        let rows = GroupPermissions.resultHistory(store.historyRows[historyKey] ?? d.results,
            pending: allPending, tasks: pending, format: recordFormat)
        if !rows.isEmpty {
            HStack {
                GroupSectionTitle(title: groupText("match_log", "Match history"))
                Menu { Button(groupText("all_formats", "All formats")) { recordFormat = nil }; ForEach(GroupFormat.allCases) { option in Button(option.title) { recordFormat = option } } } label: { Label(recordFormat?.title ?? groupText("all_formats", "All formats"), systemImage: "line.3.horizontal.decrease").font(.caption) }
                    .accessibilityIdentifier("group_record_filter")
            }
        } else {
            let canAddResult = d.group.isActive && me != nil && writable
                && (!d.group.isCoaching || GroupPermissions.coach(d.group, member: me))
                && (d.group.memberCount ?? d.members.filter { $0.status == "active" }.count) >= 2
            if recordsEmpty && canAddResult {
                GroupEmptyCard(text: groupText("no_results", "No matches recorded yet"), actionTitle: groupText("manual_result", "Add match result")) { manual = true }
                    .accessibilityIdentifier("group_records_empty")
            } else {
                GroupEmptyCard(text: groupText("no_results", "No matches for this format"))
            }
        }
        ForEach(rows) { resultRow($0) }
        if store.historyCursors[historyKey] != nil { Button(groupText("load_more", "Load more")) { Task { await store.loadHistory(groupID, format: recordFormat, more: true) } } }
    }
    private func resultRow(_ result: GroupResult) -> some View {
        GroupSurface { GroupResultLink(result: result) }.buttonStyle(.plain)
    }

    /// 对齐安卓 GroupDetailRecordsTab：
    /// - 榜非空或任一赛制加载失败才画筛选与表格（失败时用户仍可切换赛制重试，而不是整块消失）；
    /// - 加载失败给「重试」而不是假装没比赛；有比赛却没榜时给出带赛制的空态文案；
    /// - 胜率门槛 5 场，不足显示「场次不足」（安卓 `winRate ?: insufficientText`）；
    /// - 本人行名后缀「（我）」（安卓 `meSuffix`）。
    @ViewBuilder private func rankingSection(_ d: GroupDetailCache, recordsEmpty: Bool) -> some View {
        let rankingError = store.rankErrors[GroupStore.rankKey(groupID, format: .singles)] != nil
            || store.rankErrors[GroupStore.rankKey(groupID, format: .doubles)] != nil
        if !recordsEmpty || rankingError {
            Picker(groupText("rankings", "Rankings"), selection: $rankFormat) {
                ForEach(GroupFormat.allCases) { Text(groupText("filter_" + $0.rawValue, $0.title)).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("group_rank_format")
            if d.rankings.isEmpty {
                if let failure = store.rankErrors[GroupStore.rankKey(groupID, format: rankFormat)] {
                    GroupEmptyCard(text: failure, actionTitle: groupText("retry", "Retry")) { Task { await store.loadRankings(groupID, format: rankFormat) } }
                        .accessibilityIdentifier("group_rank_error")
                } else {
                    GroupEmptyCard(text: String(format: groupText("ranking_empty", "No %@ leaderboard yet"), groupText("filter_" + rankFormat.rawValue, rankFormat.title)))
                        .accessibilityIdentifier("group_rank_empty")
                }
            } else {
                GroupSectionTitle(title: String(format: groupText("ranking_title", "%@ rankings"), groupText("filter_" + rankFormat.rawValue, rankFormat.title)))
                ForEach(d.rankings) { row in
                    NavigationLink { GroupMemberResultsView(groupID: groupID, memberID: row.memberId, name: row.displayName, format: rankFormat) } label: {
                        GroupSurface {
                            HStack {
                                Text("\(row.rank)").foregroundStyle(.secondary)
                                Text(row.displayName + (row.memberId == me?.id ? groupText("ranking_me_suffix", " (me)") : ""))
                                Spacer()
                                Text("\(row.games)\(groupText("ranking_games", "P")) \(row.wins)\(groupText("ranking_wins", "W")) \(row.losses)\(groupText("ranking_losses", "L"))" + (row.draws.map { " \($0)\(groupText("ranking_draws", "D"))" } ?? "") + " · \(groupText("ranking_sets", "Sets")) \(row.setsWon)-\(row.setsLost)").font(.caption).foregroundStyle(.secondary)
                                Text(row.games >= 5 ? row.winRateText : groupText("ranking_insufficient_matches", "Too few matches")).font(.caption)
                                Image(systemName: "chevron.right")
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private func members(_ d: GroupDetailCache) -> some View {
        TextField(groupText("search_members", "Search members"), text: $memberQuery).textFieldStyle(.roundedBorder).accessibilityIdentifier("group_member_search")
        if let requestError { GroupNotice(text: requestError) }
        if manager && !requests.isEmpty {
            GroupSectionTitle(title: groupText("join_requests", "Join requests"), count: requests.count)
            ForEach(requests) { request in
                GroupSurface {
                    HStack(spacing: 10) {
                        GroupAvatar(name: request.displayName, url: request.avatarUrl)
                        VStack(alignment: .leading, spacing: 5) { Text(request.displayName).font(.subheadline.weight(.semibold)); Text(request.message).font(.caption).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(groupText("approve", "Approve")) { decide(request, approve: true) }.buttonStyle(.borderedProminent).controlSize(.small)
                        Button(groupText("reject", "Reject")) { decide(request, approve: false) }.buttonStyle(.bordered).controlSize(.small)
                    }.disabled(!writable || busyRequests.contains(request.id))
                }
            }
        }
        let regular = d.members.filter { $0.kind != "temporary" && $0.status == "active" && (memberQuery.isEmpty || $0.displayName.localizedCaseInsensitiveContains(memberQuery)) }
        GroupSectionTitle(title: groupText("regular_members", "Members"), count: regular.count)
        ForEach(regular) { memberRow($0) }
        let temporary = d.members.filter { $0.kind == "temporary" && $0.status == "active" && (memberQuery.isEmpty || $0.displayName.localizedCaseInsensitiveContains(memberQuery)) }
        HStack { GroupSectionTitle(title: groupText("temporary_members", "Temporary members"), count: temporary.count); if manager { Button { management = .init(kind: "temporary") } label: { Label(groupText("add", "Add"), systemImage: "plus").font(.caption) }.buttonStyle(.bordered).disabled(!writable).accessibilityIdentifier("group_add_temporary") } }
        ForEach(temporary) { memberRow($0) }
        if let removed = d.removedMembers, !removed.isEmpty { DisclosureGroup(groupText("removed_members", "Former members")) { ForEach(removed.filter { memberQuery.isEmpty || $0.displayName.localizedCaseInsensitiveContains(memberQuery) }) { member in GroupSurface { Text(member.displayName); if let date = member.removedAt { Text(Date(timeIntervalSince1970: Double(date) / 1000), format: .dateTime).font(.caption).foregroundStyle(.secondary) } } } } }
        if !temporary.isEmpty { GroupNotice(text: groupText("temporary_hint", "Temporary members can take part without creating an account.")) }
    }
    private func memberRow(_ member: GroupMember) -> some View {
        GroupSurface {
            HStack {
                GroupAvatar(name: member.displayName, url: member.avatarUrl)
                VStack(alignment: .leading) { Text(member.displayName); if member.isVip == true { Text("VIP").font(.caption).foregroundStyle(Theme.primary) }; if let pending = member.pendingDisplayName, !pending.isEmpty { Text(groupText("moderation_pending", "Awaiting review") + " · " + pending).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading)
                if member.role == "owner" { Text(groupText("leader", "Leader")).font(.caption).foregroundStyle(Theme.primary) }
                if member.role == "admin" { Text(groupText("admin", "Administrator")).font(.caption).foregroundStyle(Theme.primary) }
                if let group = detail?.group, GroupPermissions.canManageMember(group, me: me, target: member) {
                    Button { management = .init(kind: "member", member: member) } label: { Image(systemName: "chevron.right").foregroundStyle(.secondary) }.disabled(!writable).accessibilityLabel(groupText("member_settings", "Member settings")).accessibilityIdentifier("group_member_manage_\(member.id)")
                }
            }
        }
    }
    private func decide(_ request: GroupJoinRequest, approve: Bool) { Task {
        guard !busyRequests.contains(request.id) else { return }; busyRequests.insert(request.id); defer { busyRequests.remove(request.id) }
        if await store.perform({ try await store.repository.action("/\(groupID)/join-requests/\(request.id)/\(approve ? "approve" : "reject")") }) { await reload() }
        else { requestError = store.error }
    } }
    private func confirm(_ row: GroupResult) async {
        let permission = GroupPermissions.confirmation(row, group: detail?.group, me: me)
        guard writable, permission.allowed, !busyResults.contains(row.id) else { return }
        busyResults.insert(row.id); defer { busyResults.remove(row.id) }
        if await store.perform({ let _: GroupResult = try await store.repository.write("/\(groupID)/results/\(row.id)/confirm", body: GroupConfirmBody(authority: permission.authority), revision: row.revision) }) { await reload() }
        else { requestError = store.error }
    }
}

struct GroupSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 14) { content }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18)) }
}

struct GroupSectionTitle: View {
    var title: String
    var count: Int? = nil
    var subtitle: String? = nil
    var navigate: (() -> Void)? = nil
    var body: some View { HStack(spacing: 8) { RoundedRectangle(cornerRadius: 2).fill(Theme.primary).frame(width: 3, height: 16); Text(title).font(.headline); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } else if let count { Text("\(count)").font(.caption).foregroundStyle(.secondary) }; Spacer(); if let navigate { Button(action: navigate) { Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary) }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).accessibilityLabel(title) } } }
}

/// 活动卡内的赛制/「直接排赛」小标签（灰底）。
struct GroupActivityTagChip: View {
    var text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.tintedFill(Theme.textSecondary, lightAlpha: 0.12, darkAlpha: 0.16), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// 活动状态 chip（报名中绿 / 进行中橙 / 已完成灰 / 已取消红）。
struct GroupActivityStatusChip: View {
    var text: String
    var status: String
    private var tone: Color {
        switch status {
        case "in_progress": Theme.homePrimaryCardOrange
        case "completed": Theme.textSecondary
        case "cancelled": Theme.destructiveText
        case "recruiting": Theme.primary
        default: Theme.textSecondary
        }
    }
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(tone).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.tintedFill(tone, lightAlpha: 0.14, darkAlpha: 0.22), in: Capsule())
    }
}

struct GroupEmptyCard: View {
    var text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View { GroupSurface { VStack(spacing: 12) { EmptyStateCourtIcon(); Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center); if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent) } }.frame(maxWidth: .infinity).padding(.vertical, 16) } }
}

struct GroupAvatar: View {
    var name: String
    var url: String?
    var body: some View { RemoteImage(url: APIAssetURLResolver.resolve(url)) { $0.resizable().scaledToFill() } placeholder: { Text(String(name.prefix(1))).font(.headline).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.primary.opacity(0.12)).foregroundStyle(Theme.primary) }.frame(width: 40, height: 40).clipShape(Circle()) }
}
