import SwiftUI

struct GroupMemberSelector: View {
    var title: String
    @Binding var selectedID: String
    var members: [GroupMember]
    var excluded: Set<String> = []
    var rosterGroupID: String? = nil
    @State private var store = GroupStore.shared
    private var currentMembers: [GroupMember] { rosterGroupID.flatMap { store.cache.details[$0]?.members } ?? members }
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sm) {
                if currentMembers.filter({ $0.status == "active" }).count > 12 {
                    TextField(groupText("search_members", "Search members"), text: $query)
                        .textFieldStyle(.plain).groupAlignedInput()
                }
                Button(groupText("clear_seat", "Clear this seat")) { selectedID = ""; dismiss() }
                    .buttonStyle(.plain).foregroundStyle(Theme.primary).frame(minHeight: 44)
                if let rosterGroupID { GroupRosterAddButton(groupID: rosterGroupID) }
                ForEach(currentMembers.filter { $0.status == "active" && (!excluded.contains($0.id) || $0.id == selectedID) && (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)) }) { member in
                    Button { selectedID = member.id; dismiss() } label: {
                        HStack(spacing: Theme.sm) {
                            GroupAvatar(name: member.displayName, url: member.avatarUrl, size: 38)
                            Text(member.displayName).font(.system(size: Theme.fontBody2)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if member.id == selectedID { Image(systemName: "checkmark").foregroundStyle(Theme.primary) }
                        }
                        .padding(Theme.sm).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(member.id == selectedID ? Theme.primary.opacity(0.12) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("group_member_pick_" + member.id)
                }
            }.padding(Theme.padding).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Theme.backgroundColor)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline).tint(Theme.primary)
    }
}

struct GroupSeatPicker: View {
    var title: String
    @Binding var selectedID: String
    var members: [GroupMember]
    var excluded: Set<String> = []
    var frozen = false
    var rosterGroupID: String? = nil
    var frozenName: String? = nil
    var body: some View {
        if frozen {
            LabeledContent(title, value: frozenName ?? members.first(where: { $0.id == selectedID })?.displayName ?? groupText("former_member", "Former member"))
                .accessibilityElement(children: .combine).accessibilityIdentifier("group_seat_" + title)
                .accessibilityLabel(title).accessibilityValue(frozenName ?? members.first(where: { $0.id == selectedID })?.displayName ?? groupText("former_member", "Former member"))
        }
        else {
            NavigationLink { GroupMemberSelector(title: title, selectedID: $selectedID, members: members, excluded: excluded, rosterGroupID: rosterGroupID) } label: {
                LabeledContent(title, value: members.first(where: { $0.id == selectedID })?.displayName ?? groupText("choose_member", "Choose a member"))
            }.accessibilityIdentifier("group_seat_" + title)
        }
    }
}

/// Opens the same batch/common-name flow used by the Members tab without replacing the editor.
struct GroupRosterAddButton: View {
    let groupID: String
    @State private var store = GroupStore.shared
    @State private var presented = false
    private var allowed: Bool {
        guard let detail = store.cache.details[groupID], detail.group.isActive else { return false }
        return store.enabled && !store.cached && store.allows("manage_members") && GroupPermissions.manager(detail.members.first { $0.accountId == store.accountID })
    }
    var body: some View {
        if allowed {
            Button { presented = true } label: { Label(groupText("add_temporary", "Add temporary member"), systemImage: "plus").fontWeight(.semibold) }
                .foregroundStyle(Theme.primary).accessibilityIdentifier("group_roster_add_temporary")
                .sheet(isPresented: $presented, onDismiss: { Task { await store.loadDetail(groupID) } }) {
                    GroupManagementView(groupID: groupID, action: .init(kind: "temporary"))
                }
        }
    }
}

struct GroupMatchFormatChoices: View {
    @Binding var format: GroupFormat
    var body: some View {
        HStack(spacing: 0) {
            ForEach(GroupFormat.allCases) { option in
                Button { format = option } label: {
                    Text(option.title).font(.system(size: Theme.fontBody2, weight: format == option ? .medium : .regular))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(format == option ? Theme.textOnPrimary : Theme.textPrimary)
                        .background(format == option ? Theme.primary : .clear)
                }.buttonStyle(.plain).accessibilityAddTraits(format == option ? .isSelected : [])
            }
        }
        .background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(uiColor: .separator), lineWidth: 0.5))
    }
}

struct GroupMatchRuleSummary: View {
    let rules: GroupMatchRules
    var expanded = false
    var editable = true
    var onTap: () -> Void
    private var points: String {
        if rules.sport == .tennis {
            if rules.setScoringMode == "tiebreak_only" { return groupText("tie_break", "Tie-break points") + " \(rules.tieBreakPoints)" }
            return groupText("games_per_set", "Games per set") + " \(rules.gamesPerSet) · " + groupText("tie_break", "Tie-break points") + " \(rules.tieBreakPoints)"
        }
        return groupText("target_points", "Points to win") + " \(rules.pointsToWinSet)"
    }
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.sm) {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text(rules.formatTitle)
                        .font(.system(size: Theme.fontBody2, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    Text(points).font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if editable { Image(systemName: expanded ? "chevron.up" : "chevron.right").font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary) }
            }
            .padding(Theme.padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(GroupEditorColors.insetInput, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(!editable).accessibilityIdentifier("group_match_rules_summary")
    }
}

/// Shared rule fields preserve the capability catalog in both inline and modal presentation.
struct GroupRulesFields: View {
    @Binding var rules: GroupMatchRules
    var capability: GroupSportCapability?
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.padding) {
            if let options = capability?.ruleOptions {
                GroupRuleChoices(title: groupText("completion_mode", "Match completion"), values: options.matchCompletionModes ?? [rules.matchCompletionMode], selection: $rules.matchCompletionMode, label: { mode in var value = rules; value.matchCompletionMode = mode; return value.formatTitle })
                GroupRuleChoices(title: groupText("max_sets", "Games per match"), values: options.maxSets ?? [rules.maxSets], selection: $rules.maxSets, label: { String($0) })
                if capability?.supportsCustomRules == true {
                    GroupRuleNumberStepper(title: groupText("max_sets", "Games per match"), value: $rules.maxSets, range: 1...99)
                }
                if rules.sport == .tennis {
                    GroupRuleChoices(title: groupText("tennis_scoring", "Set scoring"), values: options.setScoringModes ?? [rules.setScoringMode], selection: $rules.setScoringMode, label: { groupText($0, $0) })
                    GroupRuleChoices(title: groupText("games_per_set", "Games per set"), values: options.gamesPerSet ?? [rules.gamesPerSet], selection: $rules.gamesPerSet, label: { String($0) })
                    GroupRuleChoices(title: groupText("tie_break", "Tie-break points"), values: options.tieBreakPoints ?? [rules.tieBreakPoints], selection: $rules.tieBreakPoints, label: { String($0) })
                    ruleToggle(groupText("no_ad", "No-ad scoring"), selection: $rules.usesNoAdScoring)
                        .disabled(Set(options.usesNoAdScoring ?? []).count < 2)
                } else {
                    GroupRuleChoices(title: groupText("target_points", "Points to win"), values: options.pointsToWinSet ?? [rules.pointsToWinSet], selection: $rules.pointsToWinSet, label: { String($0) })
                    if capability?.supportsCustomRules == true {
                        GroupRuleNumberStepper(title: groupText("target_points", "Points to win"), value: $rules.pointsToWinSet, range: 1...999)
                    }
                    ruleToggle(groupText("win_by_two", "Win by two"), selection: $rules.winByTwo)
                        .disabled(Set(options.winByTwo ?? []).count < 2)
                    ruleToggle(groupText("rally_scoring", "Rally scoring"), selection: $rules.useRallyScoring)
                        .disabled(Set(options.useRallyScoring ?? []).count < 2)
                    if capability?.supportsCustomRules == true {
                        ruleToggle(groupText("point_cap", "Maximum score"), selection: Binding(get: { rules.pointCap != nil }, set: { rules.pointCap = $0 ? max(rules.pointsToWinSet, rules.pointCap ?? rules.pointsToWinSet) : nil }))
                        if rules.pointCap != nil {
                            GroupRuleNumberStepper(title: groupText("point_cap", "Maximum score"), value: Binding(get: { rules.pointCap ?? rules.pointsToWinSet }, set: { rules.pointCap = $0 }), range: min(rules.pointsToWinSet, 9999)...9999)
                        }
                    }
                }
                if !rules.isValid { GroupNotice(text: groupText("invalid_rules", "Please check the match rules.")) }
                if let defaults = capability?.defaultRules {
                    Button(groupText("default_rules", "Restore default rules")) { rules = defaults }
                        .buttonStyle(.plain).foregroundStyle(Theme.primary).frame(minHeight: 44)
                }
            } else { GroupNotice(text: groupText("capabilities_missing", "Match rules are unavailable. Connect and retry.")) }
        }.disabled(capability?.supportsCustomRules == false)
    }
    private func ruleToggle(_ title: String, selection: Binding<Bool>) -> some View {
        Toggle(title, isOn: selection).font(.system(size: Theme.fontBody2)).tint(Theme.primary)
            .padding(.horizontal, Theme.padding).frame(minHeight: 48)
            .background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GroupRuleNumberStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        HStack(spacing: Theme.sm) {
            Text(title).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                Button { value = max(range.lowerBound, value - 1) } label: { Image(systemName: "minus").frame(width: 40, height: 44) }
                    .disabled(value <= range.lowerBound).accessibilityLabel(title + " −")
                TextField(title, text: Binding(get: { String(value) }, set: { text in
                    if let number = Int(text.filter { $0.isASCII && $0.isNumber }) { value = min(range.upperBound, max(range.lowerBound, number)) }
                })).keyboardType(.numberPad).multilineTextAlignment(.center).frame(width: 56, height: 44)
                Button { value = min(range.upperBound, value + 1) } label: { Image(systemName: "plus").frame(width: 40, height: 44) }
                    .disabled(value >= range.upperBound).accessibilityLabel(title + " +")
            }.buttonStyle(.plain).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textPrimary)
                .background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct GroupRulesEditor: View {
    @Binding var rules: GroupMatchRules
    var capability: GroupSportCapability?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                GroupRulesFields(rules: $rules, capability: capability)
                    .padding(Theme.padding).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundColor)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GroupAlignedFooter {
                    Button(NSLocalizedString("done", value: "Done", comment: "")) { dismiss() }
                        .buttonStyle(GroupAlignedActionStyle()).disabled(!rules.isValid || capability == nil)
                }
            }
            .navigationTitle(groupText("match_rules", "Match rules")).navigationBarTitleDisplayMode(.inline)
            .tint(Theme.primary)
            .toolbar { ToolbarItem(placement: .cancellationAction) { ModalCloseButton { dismiss() } } }
        }.groupAdaptiveOrientation()
    }
}

struct GroupSetDetailsEditor: View {
    @Binding var sets: [GroupScore]
    var maximum: Int
    var body: some View {
        ForEach(sets.indices, id: \.self) { i in
            HStack {
                Text("\(i + 1)").monospacedDigit()
                TextField("A", value: $sets[i].a, format: .number).keyboardType(.numberPad)
                Text(":")
                TextField("B", value: $sets[i].b, format: .number).keyboardType(.numberPad)
                Button(role: .destructive) { sets.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }
        }
        Button(groupText("add_set", "Add a game score")) { sets.append(.init(a: 0, b: 0)) }.disabled(sets.count >= maximum)
    }
}

/// Notification taps open the related content and acknowledge only that notice.
/// Pagination keeps every loaded page instead of replacing them.
struct GroupNoticeInbox: View {
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var settingsGroupID: String? = nil
    @State private var store = GroupStore.shared
    @State private var opened: GroupNotification?
    @State private var busy = Set<String>()
    @State private var loadedRevision: Int?
    var body: some View {
        List {
            if let error = store.noticeError {
                Section {
                    GroupNotice(text: error)
                    Button(groupText("retry", "Retry")) { Task { await store.loadNotices(more: store.notices.isEmpty ? false : store.hasMoreNotices) } }.disabled(store.noticesLoading || store.noticesMarkingAll)
                }.accessibilityIdentifier("group_notices_error")
            }
            ForEach(store.notices) { notice in
                noticeRow(notice)
            }
            if store.noticesLoading {
                HStack { ProgressView() }.frame(maxWidth: .infinity).accessibilityIdentifier("group_notices_loading")
            } else if store.hasMoreNotices {
                Button(groupText("load_more", "Load more")) { Task { await store.loadNotices(more: true) } }.frame(maxWidth: .infinity).buttonStyle(.borderless).disabled(store.noticesMarkingAll)
            }
        }
        .overlay {
            // 空态直接铺在整页上并纵向居中，不做成带底色的列表条目。
            if store.notices.isEmpty, !store.noticesLoading, store.noticeError == nil {
                GroupNoticeEmptyState(
                    text: groupText("no_notices", "No notifications yet"),
                    identifier: "group_notices_empty"
                )
            }
        }
        .navigationTitle(groupText("notices", "Notifications")).groupAccountBoundary()
        .accessibilityIdentifier("group_notice_inbox")
        .toolbar {
            if AppFeatureFlags.groupRemotePushEnabled {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { GroupPushSettingsView(groupID: settingsGroupID) } label: { Image(systemName: "bell.badge") }
                        .accessibilityLabel(groupText("push_settings", "Notification settings"))
                        .accessibilityIdentifier("group_notices_push_settings")
                }
            }
            // 右上「全部已读」：与鸿蒙/安卓一致，顺序补齐所有未读（含翻页），无未读时隐藏。
            if store.unreadCount > 0 || store.noticesMarkingAll {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.markAllNoticesSeen() }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Theme.primary)
                            .frame(width: 32, height: 32)
                    }
                        .buttonBorderShape(.circle)
                        .disabled(store.noticesMarkingAll || store.noticesLoading)
                        .accessibilityIdentifier("group_notices_mark_all")
                        .accessibilityLabel(groupText("notice_mark_all", "Mark all read"))
                }
            }
        }
        .task(id: store.identityRevision) {
            let revision = store.identityRevision
            if loadedRevision != revision {
                await store.loadNotices()
                if !Task.isCancelled, store.identityRevision == revision { loadedRevision = revision }
            }
        }.refreshable { if !store.noticesMarkingAll { await store.loadNotices() } }
        .navigationDestination(item: $opened) { notice in
            GroupNoticeDestinationView(notice: notice, onStart: onStart).task { await store.markNoticeSeen(notice) }
        }
    }
    private func noticeRow(_ notice: GroupNotification) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            // 左侧打开相关内容或通知说明；右侧只更新已读回执。
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if notice.seenAt == nil { Circle().fill(Theme.primary).frame(width: 8, height: 8) }
                    Text(notice.groupName + " · " + notice.label)
                        .font(GroupTypography.section)
                        .foregroundStyle(notice.seenAt == nil ? Theme.textPrimary : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !notice.title.isEmpty { Text(notice.title) }
                if let reason = notice.reason, !reason.isEmpty {
                    Text(notice.kind == "role_changed" ? groupText(reason, reason) : reason).font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                }
                Text(Date(timeIntervalSince1970: Double(notice.createdAt) / 1000), format: .dateTime).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .onTapGesture { if !store.noticesMarkingAll { opened = notice } }
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("group_notice_open_" + notice.id)
            if notice.seenAt == nil {
                Button {
                    Task { busy.insert(notice.id); defer { busy.remove(notice.id) }; await store.markNoticeSeen(notice) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: Theme.fontBody2, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(GroupEditorColors.control))
                }
                .buttonStyle(.plain)
                .disabled(busy.contains(notice.id) || store.noticesMarkingAll)
                .accessibilityIdentifier("group_notice_seen_" + notice.id)
                .accessibilityLabel(groupText("notice_seen", "Mark as read"))
            } else {
                Text(groupText("read_notices", "Read")).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.sm).padding(.vertical, 3)
                    .background(Capsule().fill(GroupEditorColors.control))
                    .accessibilityIdentifier("group_notice_read_" + notice.id)
            }
        }.accessibilityElement(children: .contain)
    }
}

/// 通知空态：整页铺开、纵向居中，字号用正文字号（不放成列表条目，避免卡片底色与分隔线）。
struct GroupNoticeEmptyState: View {
    var text: String
    var identifier: String
    var body: some View {
        Text(text)
            .font(GroupTypography.body)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.lg)
            .accessibilityIdentifier(identifier)
            // 空态浮在 List 之上，命中测试放行以保证下拉刷新仍然可用。
            .allowsHitTesting(false)
    }
}

struct GroupNoticeDestinationView: View {
    var notice: GroupNotification
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var title: String? = nil
    var targetOverride: GroupNoticeTarget? = nil
    private var resolvedTarget: GroupNoticeTarget { targetOverride ?? notice.navigationTarget }
    @State private var store = GroupStore.shared
    @State private var activity: GroupActivity?
    @State private var result: GroupResult?
    @State private var failure: String?
    @State private var loading = false
    @State private var groupAvailable = false
    @State private var openGroup = false
    var body: some View {
        Group {
            switch resolvedTarget {
            case .group(let tab): GroupDetailView(groupID: notice.groupId, onStart: onStart, initialTab: tab)
            case .message:
                List {
                    Text(notice.groupName).font(GroupTypography.section)
                    Text(notice.label)
                    if !notice.title.isEmpty { Text(notice.title) }
                    if let reason = notice.reason, !reason.isEmpty { Text(reason) }
                    Text(Date(timeIntervalSince1970: Double(notice.createdAt) / 1000), format: .dateTime).font(.caption).foregroundStyle(.secondary)
                }.navigationTitle(groupText("notices", "Notifications"))
            case .activity:
                if let activity, let detail = store.cache.details[notice.groupId] {
                    GroupActivityView(detail: detail, activity: activity, onStart: onStart)
                } else { destinationStatus }
            case .result:
                if let result { GroupResultDetailView(initial: result) }
                else { destinationStatus }
            }
        }
        .groupAccountBoundary()
        .task(id: store.identityRevision) { loading = false; await loadTarget() }
        .navigationDestination(isPresented: $openGroup) {
            GroupDetailView(groupID: notice.groupId, onStart: onStart)
        }
    }
    private var destinationStatus: some View {
        VStack(spacing: Theme.padding) {
            if loading || failure == nil { ProgressView() }
            if let failure {
                GroupNotice(text: failure)
                Button(groupText("retry", "Retry")) { Task { await loadTarget() } }.disabled(loading)
                if groupAvailable {
                    Button(groupText("open_group", "Open group")) { openGroup = true }
                }
            }
        }.padding(20).navigationTitle(title ?? notice.label)
    }
    private func loadTarget() async {
        switch resolvedTarget {
        case .group, .message: return
        default: break
        }
        guard !loading, let account = store.accountID, SessionStore.shared.user?.id == account else { return }
        let revision = store.identityRevision
        loading = true; failure = nil; activity = nil; result = nil; groupAvailable = false
        defer { if store.matchesIdentity(account, revision: revision) { loading = false } }
        do {
            let authRevision = await store.repository.client.authSessionRevision()
            switch resolvedTarget {
            case .activity(let id):
                let loaded: GroupActivity = try await store.repository.read("/\(notice.groupId)/activities/\(id)", expectedAuthRevision: authRevision)
                try Task.checkCancellation()
                guard store.matchesIdentity(account, revision: revision), SessionStore.shared.user?.id == account else { return }
                await store.loadDetail(notice.groupId)
                try Task.checkCancellation()
                guard store.matchesIdentity(account, revision: revision), SessionStore.shared.user?.id == account else { return }
                guard loaded.id == id, loaded.groupId == notice.groupId, store.cache.details[notice.groupId] != nil else {
                    throw NSError(domain: "GroupNoticeTarget", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        store.detailErrors[notice.groupId] ?? groupText("notice_target_unavailable", "This content is unavailable or you no longer have access.")])
                }
                activity = loaded
            case .result(let id):
                let loaded: GroupResult = try await store.repository.read("/\(notice.groupId)/results/\(id)", expectedAuthRevision: authRevision)
                try Task.checkCancellation()
                guard store.matchesIdentity(account, revision: revision), SessionStore.shared.user?.id == account else { return }
                await store.loadDetail(notice.groupId)
                try Task.checkCancellation()
                guard store.matchesIdentity(account, revision: revision), SessionStore.shared.user?.id == account else { return }
                guard loaded.id == id, loaded.groupId == notice.groupId, store.cache.details[notice.groupId] != nil else {
                    throw NSError(domain: "GroupNoticeTarget", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        groupText("notice_target_unavailable", "This content is unavailable or you no longer have access.")])
                }
                result = loaded
            default: break
            }
        } catch {
            guard !(error is CancellationError), !Task.isCancelled, store.matchesIdentity(account, revision: revision), SessionStore.shared.user?.id == account else { return }
            failure = groupErrorMessage(error)
            let group: ScoreGroup? = try? await store.repository.read("/\(notice.groupId)")
            guard !Task.isCancelled, store.matchesIdentity(account, revision: revision), SessionStore.shared.user?.id == account else { return }
            groupAvailable = group?.id == notice.groupId
        }
    }
}

struct GroupReminderDestinationView: View {
    var destination: GroupReminderDestination
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared
    @State private var login = false
    var body: some View {
        NavigationStack {
            Group {
                if SessionStore.shared.user?.id == destination.accountID, store.accountID == destination.accountID {
                    GroupNoticeDestinationView(notice: .init(id: destination.id.uuidString, groupId: destination.groupID,
                        groupName: "", kind: "activity_changed", resourceId: destination.activityID, title: "", reason: nil,
                        createdAt: 0, seenAt: nil), onStart: onStart, title: groupText("activities", "Activities"))
                }
                else if !SessionStore.shared.isAuthenticated { Button(groupText("need_login", "Please sign in to continue.")) { login = true } }
                else if let error = store.error { GroupNotice(text: error) }
                else if store.accountID != destination.accountID { GroupNotice(text: groupText("session_changed", "Sign in to the account that received this reminder.")) }
                else { ProgressView() }
            }.navigationTitle(groupText("activities", "Activities"))
                .task(id: SessionStore.shared.user?.id) {
                    guard SessionStore.shared.user?.id == destination.accountID else { return }
                    await store.refresh()
                }
                .sheet(isPresented: $login) { AccountLoginSheet() }
        }
    }
}

struct GroupUploadRepairView: View {
    var upload: GroupPendingUpload
    @State private var draft: GroupResultBody
    @State private var busy = false
    @State private var error: String?
    @State private var rulesEditor = false
    @State private var configurationLoaded = false
    @State private var resultDraft: GroupResultEntryDraft
    var usesParentNavigation = false
    @Environment(\.dismiss) private var dismiss
    init(upload: GroupPendingUpload, usesParentNavigation: Bool = false) {
        self.upload = upload; self.usesParentNavigation = usesParentNavigation
        _draft = State(initialValue: upload.body)
        var entry = GroupResultEntryDraft()
        entry.total = .init(a: String(upload.body.setScore.a), b: String(upload.body.setScore.b))
        entry.sets = (upload.body.sets ?? []).map { .init(a: String($0.a), b: String($0.b)) }
        entry.detailsExpanded = !entry.sets.isEmpty
        _resultDraft = State(initialValue: entry)
    }
    private var members: [GroupMember] { GroupStore.shared.cache.details[upload.groupID]?.members.filter { $0.status == "active" } ?? [] }
    private var frozen: Bool { upload.body.gameId?.isEmpty == false }
    private var viewOnly: Bool { upload.primaryAction != .repair }
    private var seatBinding: Binding<[String]> {
        Binding(get: {
            (0..<4).map { index in draft.participants.first { $0.side == (index < 2 ? "A" : "B") && $0.seat == index % 2 }?.memberId ?? "" }
        }, set: { ids in
            draft.participants = (0..<4).compactMap { index in
                guard ids.indices.contains(index), !ids[index].isEmpty,
                      draft.format == .doubles || index % 2 == 0 else { return nil }
                let side = index < 2 ? "A" : "B", seat = index % 2
                return GroupSeat(memberId: ids[index], side: side, seat: seat,
                                 displayName: members.first { $0.id == ids[index] }?.displayName)
            }
        })
    }
    private var playedAtBinding: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: Double(draft.playedAt) / 1000) },
                set: { draft.playedAt = Int64($0.timeIntervalSince1970 * 1000) })
    }
    private var canSave: Bool {
        !busy && !viewOnly && configurationLoaded && GroupStore.shared.accountID == upload.accountID &&
        GroupStore.shared.enabled && !GroupStore.shared.cached && GroupStore.shared.allows("submit_result") &&
        GroupStore.shared.cache.details[upload.groupID]?.group.isActive == true &&
        GroupStore.shared.uploads.contains(where: { $0.id == upload.id && $0.groupID == upload.groupID && $0.primaryAction == .repair }) &&
        resultDraft.isValid(draft.rules) && playedAtBinding.wrappedValue <= Date() &&
        GroupTrainingValidation.validSeats(draft.participants.map(\.memberId), format: draft.format)
    }
    var body: some View {
        Group {
            if usesParentNavigation { editorContent }
            else { NavigationStack { editorContent } }
        }.groupAdaptiveOrientation()
    }
    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                if let failure = upload.failureMessage() { GroupNotice(text: failure) }
                if viewOnly { Text(draft.format.title).font(GroupTypography.body).foregroundStyle(Theme.textSecondary) }
                else { GroupMatchFormatChoices(format: $draft.format).disabled(frozen || busy || !configurationLoaded) }
                GroupInlineMatchRoster(format: draft.format, ids: seatBinding, members: members,
                                       frozen: frozen, frozenSeats: draft.participants)
                    .disabled(viewOnly || busy || !configurationLoaded)
                if viewOnly {
                    Text(playedAtBinding.wrappedValue.formatted(date: .abbreviated, time: .shortened))
                        .font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                } else {
                    DatePicker(groupText("played_at", "Played at"), selection: playedAtBinding, in: ...Date())
                        .labelsHidden().datePickerStyle(.compact)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, Theme.padding)
                        .background(GroupEditorColors.input, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("group_result_played_at")
                }
                Text(groupText("score_and_rules", "Score and rules")).font(.system(size: Theme.fontBody1, weight: .medium))
                VStack(alignment: .leading, spacing: Theme.sm) {
                    Text(groupText("match_rules", "Match rules")).font(.system(size: Theme.fontBody2, weight: .medium))
                    GroupMatchRuleSummary(rules: draft.rules, editable: !viewOnly && !frozen && configurationLoaded) { rulesEditor = true }
                    Divider().padding(.vertical, Theme.sm)
                    Text(groupText("match_score", "Match score")).font(.system(size: Theme.fontBody2, weight: .medium))
                    if viewOnly {
                        Text("\(draft.setScore.a) : \(draft.setScore.b)").font(.title2.monospacedDigit())
                        ForEach(Array((draft.sets ?? []).enumerated()), id: \.offset) { _, score in
                            Text("\(score.a) : \(score.b)").font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                        }
                    } else { GroupResultScoreControls(draft: $resultDraft, rules: draft.rules) }
                }
                .padding(Theme.padding).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                if let error { GroupNotice(text: error) }
                if !configurationLoaded {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    else if error != nil { Button(groupText("retry", "Retry")) { Task { await loadConfiguration() } } }
                }
            }.padding(.horizontal, Theme.padding).padding(.top, Theme.padding).padding(.bottom, Theme.lg)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively).background(Theme.backgroundColor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !viewOnly {
                GroupAlignedFooter {
                    Button(NSLocalizedString("save", value: "Save", comment: "")) { save() }
                        .buttonStyle(GroupAlignedActionStyle()).disabled(!canSave)
                        .accessibilityIdentifier("group_repair_submit")
                }
            }
        }
        .navigationTitle(viewOnly ? groupText("audit_result_frozen_info", "View players and rules") : groupText("repair_upload", "Correct result")).navigationBarTitleDisplayMode(.inline)
        .groupAccountBoundary().tint(Theme.primary).navigationBarBackButtonHidden(busy)
        .toolbar {
            if !usesParentNavigation { ToolbarItem(placement: .cancellationAction) { ModalCloseButton { dismiss() }.disabled(busy) } }
        }
        .task { await loadConfiguration() }
        .onChange(of: draft.format) { _, value in if !frozen { draft.participants.removeAll { $0.seat >= value.seatsPerSide } } }
        .onChange(of: resultDraft.detailsExpanded) { _, value in if value { resultDraft.reconcileDetails(draft.rules) } }
        .onChange(of: resultDraft.total) { _, _ in resultDraft.reconcileDetails(draft.rules) }
        .sheet(isPresented: $rulesEditor) { GroupRulesEditor(rules: $draft.rules, capability: GroupStore.shared.capabilities?.sport(draft.rules.sport)) }
    }
    private func save() {
        do {
            guard canSave, let score = resultDraft.score else { throw GroupFormError.invalidResult }
            draft.setScore = score; draft.sets = resultDraft.details; draft.bestOf = draft.rules.maxSets
            try GroupStore.shared.queuedResult(draft, groupID: upload.groupID, id: upload.id, key: upload.key)
            dismiss()
        } catch { self.error = groupErrorMessage(error) }
    }
    private func loadConfiguration() async {
        let store = GroupStore.shared
        guard store.accountID == upload.accountID else { return }
        guard let gameID = upload.body.gameId, !gameID.isEmpty else { configurationLoaded = true; return }
        busy = true; defer { busy = false }
        let identity = store.identityRevision
        do {
            let game: GroupGameSnapshot = try await store.repository.read("/\(upload.groupID)/games/\(gameID)")
            guard store.matchesIdentity(upload.accountID, revision: identity) else { return }
            guard game.hasValidFrozenConfiguration(groupID: upload.groupID, gameID: gameID, sport: draft.rules.sport), let rules = game.rules, let seats = game.participants else { throw GroupFormError.invalidRules }
            draft.rules = rules; draft.bestOf = rules.maxSets; draft.format = game.format; draft.participants = seats
            draft.clientSessionId = game.clientSessionId; draft.activityId = game.activityId.isEmpty ? nil : game.activityId
            draft.activitySessionId = game.activitySessionId.flatMap { $0.isEmpty ? nil : $0 }; draft.trainingSessionId = game.trainingSessionId.flatMap { $0.isEmpty ? nil : $0 }
            configurationLoaded = true; error = nil
        } catch { if store.matchesIdentity(upload.accountID, revision: identity) { self.error = groupErrorMessage(error) } }
    }
}

/// Shared review copy for list and detail confirmations. Participant snapshots remain authoritative.
enum GroupResultConfirmationCopy {
    static func message(_ result: GroupResult, members: [GroupMember], authority: Bool, manager: Bool) -> String {
        func names(_ side: String) -> String {
            result.participants.filter { $0.side == side }.sorted { $0.seat < $1.seat }.map { seat in
                let snapshot = seat.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return snapshot.isEmpty ? members.first(where: { $0.id == seat.memberId })?.displayName ?? groupText("former_member", "Former member") : snapshot
            }.joined(separator: " / ")
        }
        let summary = names("A") + " · " + names("B") + "  \(result.setScore.a):\(result.setScore.b)"
        let explanation = authority
            ? groupText("confirm_authority_message", "All players are temporary members, or no account player on the opposing side can confirm. Review the players and score. Confirmation counts toward match records and records the group owner as the confirmer.")
            : groupText(manager ? "confirm_result_message" : "confirm_member_message", "Review the players and score. Once confirmed, the result counts toward both sides’ records. To correct it, ask a manager to void the original result.")
        return summary + "\n" + result.date.formatted(date: .numeric, time: .shortened) + "\n\n" + explanation
    }
}

private struct GroupCommonPlacesDialog: ViewModifier {
    @Binding var presented: Bool
    @Binding var selection: String
    private var places: [CommonPlace] { groupCaptureCommonPlaces() ?? CommonPlacesManager.shared.getAllPlaces() }
    func body(content: Content) -> some View {
        content.groupAlert(groupText("copy_places_title", "Choose saved location"), isPresented: $presented, verticalActions: true) {
            ForEach(places) { place in Button(place.name) { selection = place.name } }
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) {}
        } message: {
            if places.isEmpty {
                VStack(spacing: Theme.spacing) {
                    Image(systemName: "sportscourt").font(.system(size: 32)).accessibilityHidden(true)
                    Text(NSLocalizedString("common_places_no_records", value: "No saved locations", comment: ""))
                    Text(NSLocalizedString("common_places_empty_hint", value: "Add locations in Saved Locations on the home page.", comment: ""))
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, Theme.lg)
            }
        }
    }
}
extension View {
    func groupCommonPlacesDialog(isPresented: Binding<Bool>, selection: Binding<String>) -> some View {
        modifier(GroupCommonPlacesDialog(presented: isPresented, selection: selection))
    }
}


/// Group alerts share explicit action roles so Cancel never inherits the primary green.
/// Uses the app's dialog tokens and public SwiftUI modal presentation APIs.
private struct GroupAlertActionStyle: PrimitiveButtonStyle {
    @Binding var presented: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let cancel = configuration.role == .cancel
        let danger = configuration.role == .destructive
        return Button(role: configuration.role) {
            configuration.trigger()
            presented = false
        } label: {
            configuration.label
                .font(.system(size: Theme.fontBody1, weight: .medium))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(cancel ? Theme.textSecondary : Theme.textOnPrimary)
                .padding(.horizontal, Theme.md).padding(.vertical, Theme.sm)
                .frame(maxWidth: .infinity, minHeight: GroupFieldSize.control)
                .background(cancel ? Theme.dialogControlBackground : danger ? Color.red : Theme.primary, in: Capsule())
                .contentShape(Capsule()).opacity(enabled ? 1 : 0.45)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

private struct GroupAlertPanel<Actions: View, Message: View>: View {
    let title: String
    @Binding var presented: Bool
    let verticalActions: Bool
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var message: () -> Message
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.scoreboardDialogScrim.ignoresSafeArea().accessibilityHidden(true)
                VStack(spacing: Theme.md) {
                    Text(title).font(.system(size: Theme.fontH5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                    ScrollView {
                        message().font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }.scrollBounceBehavior(.basedOnSize)
                        .frame(maxHeight: max(80, geometry.size.height - 180))
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if verticalActions { VStack(spacing: Theme.sm) { actions() } }
                        else { HStack(spacing: Theme.sm) { actions() } }
                    }.buttonStyle(GroupAlertActionStyle(presented: $presented))
                }
                .padding(Theme.lg)
                .frame(width: Theme.dialogWidth(availableWidth: geometry.size.width, role: .setup))
                .background(Theme.dialogSurfaceBackground, in: RoundedRectangle(cornerRadius: Theme.xxl))
                .shadow(color: .black.opacity(0.15), radius: Theme.md)
                .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
                .accessibilityIdentifier("group_alert")
                .accessibilityAction(.escape) { presented = false }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.tint(Theme.primary).interactiveDismissDisabled()
    }
}

extension View {
    func groupAlert<Actions: View, Message: View>(_ title: String, isPresented: Binding<Bool>, verticalActions: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message) -> some View {
        fullScreenCover(isPresented: isPresented) {
            GroupAlertPanel(title: title, presented: isPresented, verticalActions: verticalActions, actions: actions, message: message)
                .presentationBackground(.clear)
        }.transaction { $0.disablesAnimations = true }
    }
    func groupAlert<Data, Actions: View, Message: View>(_ title: String, isPresented: Binding<Bool>, presenting data: Data?,
        @ViewBuilder actions: @escaping (Data) -> Actions, @ViewBuilder message: @escaping (Data) -> Message) -> some View {
        fullScreenCover(isPresented: isPresented) {
            if let data {
                GroupAlertPanel(title: title, presented: isPresented, verticalActions: false,
                                actions: { actions(data) }, message: { message(data) })
                    .presentationBackground(.clear)
            }
        }.transaction { $0.disablesAnimations = true }
    }
}
