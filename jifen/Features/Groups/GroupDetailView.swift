import SwiftUI

private struct GroupJoinDecision: Identifiable {
    let request: GroupJoinRequest
    var id: String { request.id }
}
private struct GroupMemberOperation: Identifiable {
    let member: GroupMember
    let kind: String
    var id: String { member.id + kind }
}

struct GroupDetailView: View {
    let groupID: String
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var initiallyShare = false
    var initialTab = 0
    var welcomeBack = false
    @State private var welcomeShown = false
    @State private var toastMessage: String?
    @State private var initialDestinationHandled = false
    @State private var store = GroupStore.shared
    @State private var tab = 0
    @State private var rankFormat = GroupFormat.singles
    @State private var recordFormat: GroupFormat?
    @State private var management: GroupManagementAction?
    @State private var groupConfirmation: GroupManagementMenu.Entry?
    @State private var confirmationRevision: Int64?
    @State private var confirmingGroupAction = false
    @Environment(\.dismiss) private var dismissDetail
    @State private var editingProfile = false
    @State private var match = false
    @State private var manual = false
    @State private var newActivity = false
    @State private var directSchedule = false
    @State private var sharing = false
    @State private var reporting = false
    @State private var requests: [GroupJoinRequest] = []
    @State private var joinDecision: GroupJoinDecision?
    @State private var memberOperation: GroupMemberOperation?
    @State private var memberName = ""
    @State private var requestError: String?
    @State private var busyRequests = Set<String>()
    @State private var confirmResult: GroupResult?
    @State private var busyResults = Set<String>()
    @State private var repairUpload: GroupPendingUpload?
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
                    VStack(spacing: Theme.spacing) {
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
                    }.padding(Theme.padding).frame(maxWidth: 960).expandedPhonePageContent(existingHorizontalInset: Theme.padding)
                        .frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively).refreshable { await reload() }
            } else if let error = store.detailErrors[groupID] {
                GroupEmptyCard(text: error, actionTitle: groupText("retry", "Retry"), isCard: false) { Task { await reload() } }
                    .padding(Theme.padding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else { ProgressView().frame(maxHeight: .infinity) }
        }
        .overlay(alignment: .bottom) {
            GroupToast(message: toastMessage)
                .padding(.horizontal, Theme.lg).padding(.bottom, Theme.lg).allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == 0, let detail { overviewActionBar(detail) }
            if tab == 1, let detail, !detail.group.isCoaching, detail.group.isActive, manager {
            VStack(spacing: 0) {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.sm)) : AnyLayout(HStackLayout(spacing: Theme.spacing))
                layout {
                    Button { directSchedule = true } label: {
                            Text(groupText("activity_direct_title", "Direct match")).font(GroupTypography.body.weight(.semibold))
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.bordered).tint(Theme.cardBackground).foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity).background(Theme.cardBackground, in: Capsule())
                            .accessibilityIdentifier("group_activity_direct")
                        Button { newActivity = true } label: {
                            Label(groupText("new_activity", "Plan an activity"), systemImage: "plus").font(GroupTypography.body.weight(.semibold))
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary).frame(maxWidth: .infinity).accessibilityIdentifier("group_activity_create")
                    }.disabled(!writable || !store.allows("create_activity")).tint(Theme.primary).padding(.horizontal, 20).padding(.vertical, Theme.spacing)
                        .frame(maxWidth: 960).expandedPhonePageContent(existingHorizontalInset: 20).frame(maxWidth: .infinity)
                }
                .background(Theme.backgroundColor.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { Divider() }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(detail?.group.name ?? groupText("group", "Group"))
        .navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            HStack {
                NavigationLink { GroupNoticeInbox(onStart: onStart, settingsGroupID: groupID) } label: { Image(systemName: "bell") }
                    .accessibilityLabel(groupText("notices", "Notifications"))
                    .accessibilityIdentifier("group_detail_notices")
                if store.mutating { ProgressView() }; managementMenu
            }
        } }
        .task {
            let shouldShare = initiallyShare && !initialDestinationHandled
            if !initialDestinationHandled { tab = initialTab; initialDestinationHandled = true }
            if welcomeBack && !welcomeShown { welcomeShown = true; toastMessage = groupText("welcome_back", "Welcome back") }
            await reload(); if shouldShare && !Task.isCancelled { sharing = true }
        }
        .task(id: toastMessage) {
            guard toastMessage != nil else { return }
            do { try await Task.sleep(for: .seconds((toastMessage?.count ?? 0) > 20 ? 4 : 2)); toastMessage = nil } catch {}
        }
        .task(id: moderationRefreshKey) {
            guard scenePhase == .active, store.hasIdentity, hasPendingModeration else { return }
            let deadline = Date().addingTimeInterval(300)
            for seconds in [2, 4, 8, 16, 30, 30, 30, 30, 30, 30, 30, 30, 30] {
                guard Date().addingTimeInterval(Double(seconds)) < deadline else { return }
                do { try await Task.sleep(for: .seconds(seconds)); try Task.checkCancellation() } catch { return }
                guard Date() < deadline else { return }
                await store.refreshModeration(groupID)
                if !hasPendingModeration { return }
            }
        }
        .navigationDestination(isPresented: Binding(get: { repairUpload != nil }, set: { if !$0 { repairUpload = nil; Task { await reload() } } })) {
            if let repairUpload { GroupUploadRepairView(upload: repairUpload, usesParentNavigation: true) }
        }
        .groupAlert(groupText("confirm_result", "Confirm result"), isPresented: Binding(get: { confirmResult != nil }, set: { if !$0 { confirmResult = nil } }), presenting: confirmResult) { row in
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) { confirmResult = nil }
            Button(groupText("confirm_result", "Confirm result")) { Task { await confirm(row) } }
        } message: { row in
            Text(GroupResultConfirmationCopy.message(row, members: detail?.members ?? [], authority: GroupPermissions.confirmation(row, group: detail?.group, me: me).authority, manager: GroupPermissions.manager(me)))
        }
        .groupAlert(groupText("approve", "Approve"),
            isPresented: Binding(get: { joinDecision != nil }, set: { if !$0 { joinDecision = nil } }), presenting: joinDecision) { decision in
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) {}
            Button(groupText("approve", "Approve")) { decide(decision.request, approve: true) }
        } message: { decision in
            Text(String(format: groupText("approve_confirmation", "%@ will become a group member and can see activities and results."), decision.request.displayName))
        }
        .groupAlert(memberOperationTitle, isPresented: Binding(get: { memberOperation != nil }, set: { if !$0 { memberOperation = nil } }), presenting: memberOperation) { operation in
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) {}
            Button(operation.kind == "rename" ? NSLocalizedString("save", value: "Save", comment: "") : memberOperationTitle, role: operation.kind == "remove" ? .destructive : nil) { Task { await performMemberOperation(operation) } }
                .disabled(operation.kind == "rename" && !GroupInputValidation.validName(memberName))
                .accessibilityIdentifier("group_member_operation_submit")
        } message: { operation in
            if operation.kind == "rename" {
                TextField(groupText("member_name", "Member name"), text: $memberName)
                    .groupAlignedInput().accessibilityIdentifier("group_member_rename")
            } else {
                Text(operation.kind == "remove"
                    ? String(format: groupText("remove_member_message", "Remove %@ from this group? Previous match records will remain."), operation.member.displayName)
                    : operation.member.displayName)
            }
        }
        .task(id: recordFormat) { await store.loadHistory(groupID, format: recordFormat) }
        .task(id: rankFormat) { await store.loadRankings(groupID, format: rankFormat) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshFeatureFlag(); await store.sync(); await reload() } }
        }
        .navigationDestination(isPresented: $editingProfile) {
            GroupManagementView(groupID: groupID, action: .init(kind: "profile"), usesParentNavigation: true)
        }
        .onChange(of: editingProfile) { _, presented in
            if !presented { Task { await reload(); await store.refresh() } }
        }
        .groupAlert(groupText(groupConfirmation?.titleKey ?? "settings", "Group settings"),
               isPresented: Binding(get: { groupConfirmation != nil }, set: { if !$0 { groupConfirmation = nil } }),
               presenting: groupConfirmation) { entry in
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) {}
            Button(groupText(entry.titleKey ?? "save", "Confirm"), role: entry.isDestructive ? .destructive : nil) {
                let revision = confirmationRevision
                Task { await performGroupConfirmation(entry, revision: revision) }
            }.accessibilityIdentifier("group_management_submit")
        } message: { entry in Text(groupText(entry.confirmationHintKey ?? "", "Confirm this group operation.")) }
        .sheet(item: $management, onDismiss: { Task { await reload(); await store.refresh() } }) { action in GroupManagementView(groupID: groupID, action: action) }
        .navigationDestination(isPresented: $newActivity) { GroupActivityCreateView(groupID: groupID, usesParentNavigation: true) }
        .navigationDestination(isPresented: $directSchedule) { if let detail { GroupDirectScheduleView(detail: detail, usesParentNavigation: true) } }
        .onChange(of: newActivity) { _, shown in if !shown { Task { await reload() } } }
        .onChange(of: directSchedule) { _, shown in if !shown { Task { await reload() } } }
        .navigationDestination(isPresented: $sharing) { if let group = detail?.group { GroupShareView(group: group) } }
        .sheet(isPresented: $reporting) { GroupReportView(groupID: groupID) }
        .navigationDestination(isPresented: $match) { if let detail { GroupMatchEditor(detail: detail, manual: false, usesParentNavigation: true, onStart: onStart) } }
        .navigationDestination(isPresented: $manual) { if let detail { GroupMatchEditor(detail: detail, manual: true, usesParentNavigation: true, onStart: onStart) } }
        .onChange(of: match) { _, shown in if !shown { Task { await reload() } } }
        .onChange(of: manual) { _, shown in if !shown { Task { await reload() } } }
        .toolbar(.hidden, for: .tabBar)
    }

    private var hasPendingModeration: Bool { !(detail?.group.pendingName ?? "").isEmpty || !(detail?.group.pendingDescription ?? "").isEmpty }
    private var moderationRefreshKey: String {
        [groupID, String(store.identityRevision), String(describing: scenePhase), detail?.group.pendingName ?? "", detail?.group.pendingDescription ?? ""].joined(separator: "\u{1F}")
    }

    @ViewBuilder private var tabs: some View {
        let titles = [groupText("overview", "Overview"), detail?.group.isCoaching == true ? groupText("training", "Training") : groupText("activities", "Activities"), groupText("results", "Matches"), groupText("members", "Members")]
        if dynamicTypeSize.isAccessibilitySize {
            Picker(groupText("group", "Group"), selection: $tab) { ForEach(0..<4, id: \.self) { index in Text(titles[index]).tag(index) } }
                .pickerStyle(.menu).font(GroupTypography.section).tint(Theme.primary).frame(maxWidth: 960).expandedPhonePageContent(existingHorizontalInset: 20)
                .padding(.horizontal, 20).padding(.vertical, 10).accessibilityIdentifier("group_tab_\(tab)")
        } else { HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Button { tab = index } label: {
                    HStack(spacing: 5) {
                        Text(titles[index]).font(GroupTypography.body.weight(tab == index ? .semibold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if index == 3, manager, !requests.isEmpty { Circle().fill(Theme.homePrimaryCardOrange).frame(width: 6, height: 6) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(tab == index ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(tab == index ? Theme.textOnPrimary : Theme.textSecondary)
                }.buttonStyle(.plain).accessibilityIdentifier("group_tab_\(index)")
                    .accessibilityAddTraits(tab == index ? .isSelected : [])
            }
        }.padding(3).background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: 960).expandedPhonePageContent(existingHorizontalInset: 20)
        }
    }

    private var managementMenu: some View {
        Menu {
            if let detail, overviewActions(detail).canInvite {
                Button(groupText(detail.group.isCoaching ? "invite_students" : "invite", "Invite")) { sharing = true }
                    .disabled(!writable)
                    .accessibilityIdentifier("group_menu_invite")
            }
            ForEach(menuPolicy.entries.filter { $0 != .divider }, id: \.self) { entry in
                if let key = entry.titleKey {
                    Button(groupText(key, key)) { menuAction(entry) }
                        .disabled(entry == .report ? !store.hasIdentity : !canManage || (entry != .leave && !store.allows("manage_group")))
                        .accessibilityIdentifier("group_menu_" + entry.rawValue)
                }
            }
        } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)) }
            .disabled(store.mutating || confirmingGroupAction)
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
        case .editProfile:
            if UIDevice.current.userInterfaceIdiom == .phone { editingProfile = true }
            else { management = .init(kind: "profile") }
        case .transfer:
            guard detail?.members.contains(where: { $0.kind == "account" && $0.status == "active" && $0.role != "owner" && $0.id != me?.id }) == true else {
                toastMessage = groupText("transfer_none", "There are no other full members. Temporary members cannot become the leader.")
                return
            }
            management = .init(kind: "transfer")
        case .restore, .cancelDissolve:
            let revision = detail?.group.revision
            Task { await performGroupConfirmation(entry, revision: revision) }
        case .archive, .dissolve, .leave:
            confirmationRevision = detail?.group.revision
            groupConfirmation = entry
        case .report: reporting = true
        case .divider: break
        }
    }

    /// 解散冷静期横幅（对齐安卓 GroupDissolveBanner 改版）：只读说明 + 组长可就地撤销解散。
    private func performGroupConfirmation(_ entry: GroupManagementMenu.Entry, revision: Int64?) async {
        guard !confirmingGroupAction, canManage, menuPolicy.entries.contains(entry), entry.confirmationHintKey != nil,
              entry == .leave || store.allows("manage_group") else { return }
        let path: String
        switch entry {
        case .archive: path = "/\(groupID)/archive"
        case .restore: path = "/\(groupID)/restore"
        case .cancelDissolve: path = "/\(groupID)/dissolve/cancel"
        case .dissolve: path = "/\(groupID)/dissolve"
        case .leave: path = "/\(groupID)/leave"
        default: return
        }
        confirmingGroupAction = true
        defer { confirmingGroupAction = false }
        if await store.perform({ try await store.repository.action(path, revision: entry == .leave ? nil : revision) }) {
            if entry == .leave { store.forgetGroup(groupID); dismissDetail() }
            else { await reload() }
            await store.refresh()
        } else { toastMessage = store.error }
    }
    private func dissolveBanner(date: Int64) -> some View {
        let owner = me?.role == "owner"
        let text = String(
            format: NSLocalizedString("group_banner_dissolving", value: "Group will be dissolved on %@\n7-day cooling-off period; read-only until then", comment: "Groups"),
            Date(timeIntervalSince1970: Double(date) / 1000).formatted(date: .abbreviated, time: .omitted)
        )
        return HStack(spacing: Theme.sm) {
            Text(text).font(GroupTypography.body).foregroundStyle(Theme.warningText)
                .multilineTextAlignment(owner ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: owner ? .leading : .center)
            if owner {
                Button { menuAction(.cancelDissolve) } label: {
                    Text(groupText("cancel_dissolve", "Cancel dissolution")).font(GroupTypography.body.weight(.semibold))
                        .foregroundStyle(Theme.primary).padding(.horizontal, Theme.sm).frame(minHeight: 44)
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
                HStack { AppCatalogIcon(gameType: d.group.sport.gameType, size: 52); Text(d.group.name).font(GroupTypography.groupTitle).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                Button { UIPasteboard.general.string = d.group.groupNo } label: { Label(GroupQRPayload.formatted(d.group.groupNo), systemImage: "doc.on.doc").monospacedDigit()
                    .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
                    .background(Theme.tintedFill(Theme.primary, lightAlpha: 0.12, darkAlpha: 0.16), in: Capsule()) }.font(.caption).buttonStyle(.plain).foregroundStyle(Theme.primary)
                HStack {
                    if overviewActions(d).showSecondaryInvite { Button(groupText(d.group.isCoaching ? "invite_students" : "invite", "Invite")) { sharing = true }.font(.caption).disabled(!writable).accessibilityIdentifier("group_secondary_invite") }
                    Spacer(); Button { sharing = true } label: { GroupQRCode(number: d.group.groupNo, size: 72) }.buttonStyle(.plain).accessibilityLabel(groupText("group_qr", "Group QR code"))
                }
                if !d.group.isActive { Text(d.group.statusLabel).font(.caption).foregroundStyle(.secondary) }
            } else {
            HStack(spacing: Theme.spacing) {
                AppCatalogIcon(gameType: d.group.sport.gameType, size: 52)
                VStack(alignment: .leading, spacing: Theme.sm) {
                    Text(d.group.name).font(GroupTypography.groupTitle).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Button { UIPasteboard.general.string = d.group.groupNo } label: {
                            HStack(spacing: Theme.xs) { Text(GroupQRPayload.formatted(d.group.groupNo)).monospacedDigit(); Image(systemName: "doc.on.doc") }
                                .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
                                .background(Theme.tintedFill(Theme.primary, lightAlpha: 0.12, darkAlpha: 0.16), in: Capsule())
                        }.buttonStyle(.plain).foregroundStyle(Theme.primary)
                    }.font(.caption)
                    if d.group.isCoaching { Text(groupText("coaching", "Coaching group")).font(.caption).foregroundStyle(Theme.primary) }
                    if !d.group.isActive { Text(d.group.statusLabel).font(.caption).foregroundStyle(.secondary) }
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
            if !d.group.description.isEmpty { Text(d.group.description).font(GroupTypography.body).lineSpacing(4).foregroundStyle(Theme.textSecondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
            if overviewActions(d).showStats { Divider()
            if dynamicTypeSize.isAccessibilitySize {
                LabeledContent(groupText("confirmed_matches", "Confirmed"), value: "\(d.stats?.confirmedMatchCount ?? 0)")
                LabeledContent(groupText("month_matches", "This month"), value: "\(d.stats?.currentMonthMatchCount ?? 0)")
                LabeledContent(groupText("active_30d", "Active (30d)"), value: "\(d.stats?.activeMemberCount30d ?? 0)")
            } else { HStack(spacing: 0) {
                stat(groupText("confirmed_matches", "Confirmed"), d.stats?.confirmedMatchCount ?? 0)
                Divider().frame(height: 30)
                stat(groupText("month_matches", "This month"), d.stats?.currentMonthMatchCount ?? 0)
                Divider().frame(height: 30)
                stat(groupText("active_30d", "Active (30d)"), d.stats?.activeMemberCount30d ?? 0)
            }
            }
            }
        }
        if d.group.isCoaching, me?.role == "owner", let count = d.leaveNotices?.filter({ $0.status == "open" }).count, count > 0 {
            Button { tab = 1 } label: { GroupSurface { HStack { Text(groupText("leave_notices", "Student leave notices")); Spacer(); Text("\(count)"); Image(systemName: "chevron.right") } } }.buttonStyle(.plain)
        }
        let pending = GroupPermissions.confirmationTasks(d.pendingResults ?? d.results, group: d.group, me: me)
        if !pending.isEmpty {
            Button { tab = 2 } label: {
                GroupSurface { HStack { Text(groupText("pending_confirmation", "To confirm")); Spacer(); Text("\(pending.count)"); Image(systemName: "chevron.right") } }
            }.buttonStyle(.plain).accessibilityIdentifier("group_overview_pending")
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
            if let item = upcoming.first {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    GroupSectionTitle(title: groupText("upcoming", "Upcoming"), navigate: { tab = 1 })
                    activityRow(item, detail: d)
                }
            }
            if let item = d.activities.filter({ $0.status == "recruiting" && $0.startsAt < now }).min(by: { $0.startsAt < $1.startsAt }) {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    GroupSectionTitle(title: groupText("overdue_tasks", NSLocalizedString("schedule_time_status_overdue", comment: "")), navigate: { tab = 1 })
                    activityRow(item, detail: d)
                }
            }
        }
        if overviewActions(d).showLatestResults {
            VStack(alignment: .leading, spacing: Theme.xs) {
                GroupSectionTitle(title: groupText("latest_results", "Latest results"), navigate: { tab = 2 })
                if let result = d.results.first ?? pending.first { resultRow(result) }
                else { GroupEmptyCard(text: groupText("no_results", "No matches recorded yet")) }
            }
        }
    }

    private func overviewTraining(_ session: GroupTrainingSession, title: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) { GroupSectionTitle(title: title, navigate: { tab = 1 }); Button { tab = 1 } label: {
            GroupSurface { Text(session.court); Text(session.date, format: .dateTime.month().day().hour().minute()).font(GroupTypography.body).foregroundStyle(.secondary); Text(session.format.title).font(.caption) }
        }.buttonStyle(.plain) }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 5) { Text("\(value)").font(.title2.bold()); Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity).padding(.vertical, Theme.xs)
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
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.sm)) : AnyLayout(HStackLayout(spacing: Theme.spacing))
                layout {
                    ForEach(policy.actions, id: \.rawValue) { action in
                        if action == .addResult {
                            overviewButton(action, group: d.group).buttonStyle(.bordered)
                                .tint(Theme.cardBackground).foregroundStyle(Theme.primary)
                                .background(Theme.cardBackground, in: Capsule())
                        } else {
                            overviewButton(action, group: d.group).buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary)
                                .disabled(action == .invite && !policy.canInvite)
                        }
                    }
                }.disabled(!writable).tint(Theme.primary).padding(.horizontal, 20).padding(.vertical, Theme.spacing)
                    .frame(maxWidth: 960).expandedPhonePageContent(existingHorizontalInset: 20).frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundColor.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func overviewButton(_ action: GroupOverviewActions.Action, group: ScoreGroup) -> some View {
        let key = action == .invite ? (group.isCoaching ? "invite_students" : "invite") : action == .training ? "training" : action == .start ? "start_score" : "manual_result_action"
        let icon = action == .invite ? "person.badge.plus" : action == .addResult ? "square.and.pencil" : "play.fill"
        return Button {
            switch action {
            case .invite: sharing = true
            case .training: tab = 1
            case .start: match = true
            case .addResult: manual = true
            }
        } label: {
            Label(groupText(key, key), systemImage: icon).font(GroupTypography.body.weight(.semibold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 32)
        }.frame(maxWidth: .infinity)
            .disabled(action == .start ? !store.allows("start_game") : action == .addResult ? !store.allows("submit_result") : false)
            .accessibilityIdentifier("group_overview_" + action.rawValue)
    }

    @ViewBuilder private func activities(_ d: GroupDetailCache) -> some View {
        let archived = !d.group.isActive
        if d.activities.isEmpty {
            GroupEmptyCard(text: groupText("empty_activities_title", "No activities yet"),
                description: archived ? nil : groupText(manager ? "empty_activities_hint" : "activity_create_admin_hint",
                    manager ? "Plan an activity so members can sign up." : "Activities are created by the leader or an admin."))
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
    private func activityDisplayStatus(_ item: GroupActivity) -> String {
        if item.isDirect, item.status == "recruiting" { return groupText("activity_status_scheduled", "Scheduled") }
        return item.statusLabel
    }
    private func activityRow(_ item: GroupActivity, detail: GroupDetailCache) -> some View {
        NavigationLink { GroupActivityView(detail: detail, activity: item, onStart: onStart) } label: {
            GroupSurface {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: Theme.sm) {
                        Text(item.title).font(GroupTypography.cardTitle).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        Text(activityDisplayStatus(item) + (item.isDirect ? "" : " · \(item.registeredMemberIds.count)/\(item.capacity)"))
                            .font(GroupTypography.caption).foregroundStyle(Theme.textSecondary).fixedSize().layoutPriority(1)
                            .accessibilityIdentifier("group_activity_status_" + item.id)
                    }
                    HStack(spacing: Theme.sm) {
                        GroupActivityTagChip(text: item.isDirect ? groupText("activity_direct_title", "Direct match") : item.format.title)
                            .fixedSize()
                        Text(activityTimeLine(item)).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if item.isDirect {
                        Text(String.localizedStringWithFormat(NSLocalizedString("activity_direct_match_count", value: "%d matches · all group members", comment: "Groups"), item.sessionCount ?? 0))
                            .font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                    }
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
                if let failure = upload.failureMessage() { GroupNotice(text: failure) }
                if let action = upload.primaryAction {
                    switch action {
                    case .retry:
                        Button(groupText("sync", "Sync now")) { Task { await store.retryUpload(upload.id); await reload() } }
                            .disabled(!writable || store.mutating)
                    case .repair:
                        Button(groupText("repair_upload", "Correct result")) { repairUpload = upload }
                            .disabled(!writable || store.mutating)
                    case .viewFrozenConfiguration:
                        Button(groupText("audit_result_frozen_info", "View players and rules")) { repairUpload = upload }
                            .disabled(store.mutating)
                    case .viewCloudResult:
                        NavigationLink(groupText("existing_result", "View cloud result")) { GroupExistingUploadResultView(upload: upload) }
                    }
                }
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
                    if permission.allowed { Button(groupText(permission.authority ? "authority_confirm" : "confirm_result", "Confirm result")) { confirmResult = row }.buttonStyle(GroupAlignedActionStyle()).disabled(!writable || !store.allows("confirm_result") || busyResults.contains(row.id)) }
                    else {
                        let names = GroupPermissions.waitingNames(row, members: d.members)
                        Text(groupText("pending_confirmation", "Waiting for confirmation") + (names.isEmpty ? "" : " · " + names.joined(separator: " / "))).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        let recordsEmpty = !d.hasAnyRanking && d.results.isEmpty && allPending.isEmpty && uploads.isEmpty && recordFormat == nil
        rankingSection(d)
        let historyKey = groupID + ":" + (recordFormat?.rawValue ?? "all")
        let rows = GroupPermissions.resultHistory(store.historyRows[historyKey] ?? d.results,
            pending: allPending, tasks: pending, format: recordFormat)
        if !rows.isEmpty {
            HStack {
                GroupSectionTitle(title: groupText("match_log", "Match history"))
                Menu { Button(groupText("all_formats", "All formats")) { recordFormat = nil }; ForEach(GroupFormat.allCases) { option in Button(option.title) { recordFormat = option } } } label: {
                    HStack(spacing: Theme.xs) {
                        Text(recordFormat?.title ?? groupText("all_formats", "All formats"))
                        Image(systemName: "chevron.right")
                    }.font(.caption).foregroundStyle(.secondary).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("group_record_filter")
            }
        } else {
            let canAddResult = d.group.isActive && me != nil && writable
                && (!d.group.isCoaching || GroupPermissions.coach(d.group, member: me))
            if recordsEmpty && canAddResult {
                GroupEmptyCard(text: groupText("no_results", "No matches recorded yet"), actionTitle: groupText("manual_result_action", "Add Result")) { manual = true }
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
    @ViewBuilder private func rankingSection(_ d: GroupDetailCache) -> some View {
        let rankingError = GroupFormat.allCases.contains { store.rankErrors[GroupStore.rankKey(groupID, format: $0)] != nil }
        let rows = d.rankings(for: rankFormat)
        if d.hasAnyRanking || rankingError {
            HStack(spacing: Theme.sm) {
                ForEach(GroupFormat.allCases) { option in
                    Button { rankFormat = option } label: {
                        Text(groupText("filter_" + option.rawValue, option.title)).font(GroupTypography.body.weight(.semibold))
                            .padding(.horizontal, Theme.padding).padding(.vertical, 10)
                            .foregroundStyle(rankFormat == option ? Theme.primary : Theme.textSecondary)
                            .background((rankFormat == option ? Theme.primary : Theme.textSecondary).opacity(0.12), in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(rankFormat == option ? .isSelected : [])
                        .accessibilityIdentifier("group_rank_format_" + option.rawValue)
                }
                Spacer(minLength: 0)
            }
            if rows.isEmpty {
                if let failure = store.rankErrors[GroupStore.rankKey(groupID, format: rankFormat)] {
                    GroupEmptyCard(text: failure, actionTitle: groupText("retry", "Retry")) { Task { await store.loadRankings(groupID, format: rankFormat) } }
                        .accessibilityIdentifier("group_rank_error")
                } else {
                    Text(String(format: groupText("ranking_empty", "No %@ leaderboard yet"), groupText("filter_" + rankFormat.rawValue, rankFormat.title)))
                        .font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("group_rank_empty")
                }
            } else {
                GroupRankingTable(rows: rows, members: d.members, myMemberID: me?.id, groupID: groupID, format: rankFormat)
            }
        }
    }

    @ViewBuilder private func members(_ d: GroupDetailCache) -> some View {
        if let requestError { GroupNotice(text: requestError) }
        if manager && !requests.isEmpty {
            GroupSectionTitle(title: groupText("join_requests", "Join requests"), count: requests.count)
            ForEach(requests) { request in
                // 头像独立占一列，右侧姓名、附言与按钮共用内容宽度。
                GroupSurface {
                    HStack(alignment: .top, spacing: 10) {
                        GroupAvatar(name: request.displayName, url: request.avatarUrl)
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            HStack(spacing: Theme.sm) {
                                Text(request.displayName).font(.system(size: Theme.fontBody2, weight: .semibold)).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("group_request_name_" + request.id)
                                Text(Date(timeIntervalSince1970: Double(request.createdAt) / 1000), format: .dateTime)
                                    .font(.system(size: Theme.fontCaption)).foregroundStyle(.secondary)
                            }.frame(minHeight: 38)
                            if !request.message.isEmpty {
                                Text(request.message).font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("group_request_message_" + request.id)
                            }
                            HStack(spacing: Theme.sm) {
                                Button { decide(request, approve: false) } label: {
                                    Text(groupText("reject", "Reject")).font(.system(size: Theme.fontCaption)).frame(maxWidth: .infinity, minHeight: 20)
                                }.buttonStyle(.bordered).tint(Theme.textSecondary).foregroundStyle(Theme.textSecondary)
                                Button { joinDecision = .init(request: request) } label: {
                                    Text(groupText("approve", "Approve")).font(.system(size: Theme.fontCaption)).frame(maxWidth: .infinity, minHeight: 20)
                                }.buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(!writable || busyRequests.contains(request.id))
                }
            }
        }
        let regular = d.members.filter { $0.kind != "temporary" && $0.status == "active" }
        GroupSectionTitle(title: groupText("regular_members", "Members"), count: regular.count)
        if !regular.isEmpty { memberGroup(regular) }
        let temporary = d.members.filter { $0.kind == "temporary" && $0.status == "active" }
        // The 44pt action already provides the title's visual breathing room.
        VStack(alignment: .leading, spacing: manager ? 0 : Theme.spacing) {
            HStack { GroupSectionTitle(title: groupText("temporary_members", "Temporary members"), count: temporary.count); if manager { Button { management = .init(kind: "temporary") } label: { Label(groupText("add_temporary", "Add temporary member"), systemImage: "plus").font(.caption.weight(.semibold)) }.buttonStyle(.plain).tint(Theme.primary).foregroundStyle(Theme.primary).frame(minHeight: 44).disabled(!writable).accessibilityIdentifier("group_add_temporary") } }
            if !temporary.isEmpty { memberGroup(temporary) }
        }
        let removed = (d.removedMembers ?? []).filter { $0.status == "removed" }
        if GroupPermissions.manager(me), !removed.isEmpty {
            GroupRemovedMembersSection(count: removed.count) { memberGroup(removed) }
                .id(me?.role)
        }
        if !temporary.isEmpty { Text(groupText("temporary_hint", "Temporary members need no account and can be added when entering results.")).font(.caption).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
    }
    private func memberGroup(_ members: [GroupMember]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                memberRow(member)
                if index < members.count - 1 { Divider().padding(.leading, 68) }
            }
        }.background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
    }
    @ViewBuilder private func memberRow(_ member: GroupMember) -> some View {
        memberRowContent(member)
    }
    private var memberOperationTitle: String {
        switch memberOperation?.kind {
        case "rename": groupText("rename_member_title", "Edit member name")
        case "remove": groupText("remove_member", "Remove")
        case "admin": groupText("set_admin", "Make administrator")
        default: groupText("set_member", "Remove administrator")
        }
    }
    private func beginMemberOperation(_ kind: String, member: GroupMember) {
        memberName = member.pendingDisplayName ?? member.displayName
        memberOperation = .init(member: member, kind: kind)
    }
    private func performMemberOperation(_ operation: GroupMemberOperation) async {
        guard writable, let group = detail?.group, GroupPermissions.canManageMember(group, me: me, target: operation.member) else { return }
        let name = memberName
        if await store.perform({
            if operation.kind == "remove" { try await store.repository.action("/\(groupID)/members/\(operation.member.id)/remove") }
            else {
                let _: GroupMember = try await store.repository.write("/\(groupID)/members/\(operation.member.id)", body: GroupActionBody(displayName: operation.kind == "rename" ? name : nil, role: operation.kind == "rename" ? nil : operation.kind == "admin" ? "admin" : "member"), method: .patch)
            }
        }) { await reload() } else { requestError = store.error }
    }
    private func memberRowContent(_ member: GroupMember) -> some View {
        HStack(spacing: Theme.spacing) {
            GroupAvatar(name: member.displayName, url: member.avatarUrl, isVip: member.isVip == true)
            VStack(alignment: .leading) {
                Text(member.displayName).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textPrimary)
                if member.status == "removed", let date = member.removedAt, date > 0 {
                    Text(Date(timeIntervalSince1970: Double(date) / 1000), format: .dateTime)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if member.status == "active", let pending = member.pendingDisplayName, !pending.isEmpty { Text(groupText("moderation_pending", "Awaiting review") + " · " + pending).font(.caption).foregroundStyle(Theme.textSecondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if member.status == "active", member.role == "owner" { Text(groupText("leader", "Leader")).font(.caption).foregroundStyle(Theme.primary) }
            if member.status == "active", member.role == "admin" { Text(groupText("admin", "Administrator")).font(.caption).foregroundStyle(Theme.primary) }
            if let group = detail?.group, GroupPermissions.canManageMember(group, me: me, target: member) {
                Menu {
                    if member.kind == "temporary" {
                        Button(groupText("rename_member", "Rename")) { beginMemberOperation("rename", member: member) }
                    } else if me?.role == "owner", group.isCoaching != true {
                        Button(groupText(member.role == "admin" ? "set_member" : "set_admin", "Change role")) { beginMemberOperation(member.role == "admin" ? "member" : "admin", member: member) }
                    }
                    Button(groupText("remove_member", "Remove")) { beginMemberOperation("remove", member: member) }
                } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44) }
                    .disabled(!writable).accessibilityLabel(member.displayName + " · " + groupText("member_settings", "Member actions"))
                    .accessibilityIdentifier("group_member_manage_" + member.id)
            }
        }.padding(.horizontal, Theme.padding).padding(.vertical, Theme.spacing).contentShape(Rectangle())
    }
    private func decide(_ request: GroupJoinRequest, approve: Bool) { Task {
        guard writable, manager, !busyRequests.contains(request.id) else { return }; busyRequests.insert(request.id); defer { busyRequests.remove(request.id) }
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

private struct GroupRemovedMembersSection<Content: View>: View {
    let count: Int
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: Theme.spacing) {
            GroupSectionTitle(title: groupText("removed_members", "Former members"), count: count)
            content
        }
    }
}

struct GroupSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: Theme.spacing) { content }.font(GroupTypography.body).padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18)) }
}

struct GroupSectionTitle: View {
    var title: String
    var count: Int? = nil
    var subtitle: String? = nil
    var navigate: (() -> Void)? = nil
    var body: some View { HStack(spacing: Theme.sm) { RoundedRectangle(cornerRadius: 2).fill(Theme.primary).frame(width: 3, height: 14); Text(title).font(.system(size: Theme.fontBody1, weight: .semibold)); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } else if let count { Text("\(count)").font(.caption).foregroundStyle(.secondary) }; Spacer(); if let navigate { Button(action: navigate) { Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary) }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).accessibilityLabel(title) } } }
}

/// 活动卡内的赛制/「直接排赛」小标签（灰底）。
struct GroupActivityTagChip: View {
    var text: String
    var body: some View {
        Text(text).font(GroupTypography.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs / 2).frame(minHeight: 24)
            .background(Theme.dialogControlBackground, in: Capsule())
    }
}

/// A compact group toast; its host owns spacing above the bottom action bar.
struct GroupToast: View {
    var message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let message {
                Text(message)
                    .font(.system(size: Theme.fontBody1, weight: .medium)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.lg).padding(.vertical, Theme.spacing)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("group_toast")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: message)
    }
}

/// 活动状态 chip（报名中绿 / 进行中橙 / 已完成灰 / 已取消红）。
struct GroupActivityStatusChip: View {
    var text: String
    var status: String
    private var tone: Color {
        switch status {
        case "in_progress", "pending_confirmation": Theme.warningText
        case "completed": Theme.textSecondary
        case "cancelled", "voided": Theme.destructiveText
        case "recruiting": Theme.primary
        default: Theme.textSecondary
        }
    }
    var body: some View {
        Text(text).font(GroupTypography.caption.weight(.medium)).foregroundStyle(tone).lineLimit(1)
            .padding(.horizontal, Theme.sm).padding(.vertical, 3)
            .background(Theme.tintedFill(tone, lightAlpha: 0.14, darkAlpha: 0.22), in: Capsule())
    }
}

struct GroupEmptyCard: View {
    var text: String
    var description: String? = nil
    var actionTitle: String? = nil
    var isCard = true
    var action: (() -> Void)? = nil
    @ViewBuilder var body: some View {
        if isCard { GroupSurface { content } } else { content }
    }
    private var content: some View { VStack(spacing: Theme.spacing) { EmptyStateCourtIcon(); Text(text).accessibilityIdentifier("group_empty_title").font(GroupTypography.body).foregroundStyle(.secondary).multilineTextAlignment(.center); if let description { Text(description).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }; if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary) } }.frame(maxWidth: .infinity).padding(.vertical, Theme.padding) }
}

struct GroupAvatar: View {
    var name: String
    var url: String?
    var size: CGFloat = 38
    var isVip = false

    var body: some View {
        RemoteImage(url: APIAssetURLResolver.resolve(url)) { $0.resizable().scaledToFill() } placeholder: {
            Text(String(name.prefix(1))).font(.system(size: size <= 24 ? Theme.fontCaption : Theme.fontBody1, weight: .regular)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, maxHeight: .infinity).background(GroupEditorColors.avatar).foregroundStyle(Theme.textSecondary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if isVip { AvatarVIPBadge(avatarSize: size) }
        }
    }
}

/// 冲突对比保留系统表单分区；操作独立成组，长文案可以换行。
struct GroupEditConflictActions: View {
    var canKeepDraft: Bool = true
    var useLatest: () -> Void
    var keepDraft: () -> Void
    var body: some View {
        VStack(spacing: Theme.spacing) {
            Button(action: keepDraft) {
                Text(groupText("keep_draft", "Continue editing local version"))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }.buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary).disabled(!canKeepDraft)
            Button(action: useLatest) {
                Text(groupText("reload_version", "Load latest version"))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }.buttonStyle(.bordered)
        }.padding(.vertical, Theme.xs)
    }
}
