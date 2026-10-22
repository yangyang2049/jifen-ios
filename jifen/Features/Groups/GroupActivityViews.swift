import SwiftUI
import PersistenceCore

struct GroupActivityCreateView: View {
    let groupID: String
    var initial: GroupActivity? = nil
    var usesParentNavigation = false
    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var title = ""
    @State private var place = ""
    @State private var note = ""
    @State private var starts = Date().addingTimeInterval(3600)
    @State private var closes = Date().addingTimeInterval(3600)
    @State private var capacity = 8
    @State private var registeredCount = 0
    @State private var format = GroupFormat.singles
    @State private var matchMode = "multi"
    @State private var busy = false
    @State private var revision: Int64?
    @State private var showCommonPlaces = false
    @State private var initialized = false
    @State private var error: String?
    private var minimumCapacity: Int { GroupActivityPolicy.minimumCapacity(format: format, registeredCount: registeredCount) }
    private var valid: Bool {
        GroupActivityPolicy.validText(title: title, place: place, note: note) && starts > Date() && closes <= starts
            && (closes > Date() || Int64(closes.timeIntervalSince1970 * 1000) == (initial?.registrationClosesAt ?? initial?.startsAt))
            && GroupActivityPolicy.validCapacity(capacity, format: format, registeredCount: registeredCount)
            && (initial != nil || store.capabilities?.supportsActivityLineup == true)
            && store.allows(initial == nil ? "create_activity" : "update_activity")
    }
    var body: some View {
        Group {
            if usesParentNavigation { editor }
            else { NavigationStack { editor } }
        }
    }
    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.padding) {
                GroupAlignedField(groupText("activity_field_title_optional", "Activity name (optional)")) {
                    TextField("", text: $title).groupAlignedInput().accessibilityIdentifier("group_activity_title")
                }
                Text(groupText("activity_title_auto_hint", "If left empty, the name is generated from the date."))
                    .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Theme.spacing) { startDate; startTime }
                    VStack(spacing: Theme.padding) { startDate; startTime }
                }
                GroupActivityDateField(title: groupText("registration_closes", "Registration closes"), selection: Binding(get: { closes }, set: { closes = GroupActivityPolicy.registrationCloseAfterSelection($0, starts: starts) }), maximum: starts, compact: true,
                    summary: GroupActivityPolicy.registrationFollowsStart(closes: closes, starts: starts) ? groupText("registration_at_start", "When the activity starts") : nil,
                    inlineTitle: true)
                    .accessibilityIdentifier("group_activity_closes")
                // 对齐安卓 ActivityDeadlineSummary：恢复动作不再藏在日期选择器弹层里，
                // 而是在字段下方作为一行文字按钮直接可达。
                if !GroupActivityPolicy.registrationFollowsStart(closes: closes, starts: starts) {
                    Button { closes = starts } label: {
                        Text(groupText("registration_use_start", "Use the activity start time"))
                            .font(.system(size: Theme.fontBody2))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("group_activity_closes_use_start")
                }
                GroupAlignedField(groupText("place", "Location")) {
                    HStack(spacing: Theme.sm) {
                        TextField(groupText("place", "Location"), text: $place).accessibilityIdentifier("group_activity_place")
                        Button { showCommonPlaces = true } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.plain).foregroundStyle(Theme.primary).frame(width: 32, height: 24)
                            .accessibilityLabel(NSLocalizedString("schedule_pick_common_place", value: "Choose a saved place", comment: ""))
                            .accessibilityIdentifier("group_activity_place_picker")
                    }.groupAlignedInput()
                }
                if initial == nil {
                    GroupActivityChoices(selection: $format, values: GroupFormat.allCases, title: { $0.title })
                        .accessibilityIdentifier("group_activity_format")
                } else {
                    GroupActivityChoices(selection: $format, values: GroupFormat.allCases, title: { $0.title }).disabled(true)
                }
                HStack(spacing: Theme.spacing) {
                    Text(groupText("capacity", "Registration limit")).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    capacityControl
                }
                Text(groupText(matchMode == "multi" ? "multi_match_hint" : "single_match_hint", matchMode == "multi" ? "An activity can include multiple matches. Members sign up for the activity; select 2 for each singles match or 4 for each doubles match when arranging the lineup." : "Each activity is one match. Select 2 registered members for singles or 4 for doubles."))
                    .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
                GroupAlignedField(groupText("note", "Note")) {
                    TextField("", text: $note, axis: .vertical).lineLimit(3...5)
                        .groupAlignedInput(minHeight: GroupFieldSize.note, alignment: .topLeading, font: GroupTypography.body)
                        .accessibilityIdentifier("group_activity_note")
                }
                if let error { GroupNotice(text: error) }
            }
            .padding(Theme.padding).frame(maxWidth: Theme.focusedContentMaxWidth).frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor).scrollDismissesKeyboard(.interactively).disabled(busy)
        .navigationTitle(initial == nil ? groupText("new_activity", "Plan an activity") : groupText("edit_activity", "Edit activity"))
        .navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
        .navigationBarBackButtonHidden(usesParentNavigation)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if usesParentNavigation {
                    Button { requestClose() } label: { Image(systemName: "chevron.left") }.disabled(busy)
                } else { ModalCloseButton { requestClose() }.disabled(busy) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GroupAlignedFooter {
                HStack(spacing: Theme.padding) {
                    Button(NSLocalizedString("cancel", value: "Cancel", comment: "")) { requestClose() }
                        .buttonStyle(GroupAlignedActionStyle(secondary: true)).disabled(busy)
                    Button(initial == nil ? groupText("create_activity", "Create activity") : NSLocalizedString("save", value: "Save", comment: "")) { Task { await submit() } }
                        .buttonStyle(GroupAlignedActionStyle()).disabled(busy || !valid)
                        .accessibilityIdentifier("group_activity_save")
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .groupCommonPlacesDialog(isPresented: $showCommonPlaces, selection: $place)
        .onChange(of: starts) { old, new in closes = GroupActivityPolicy.registrationCloseAfterStartChange(closes: closes, previousStart: old, newStart: new) }
        .onChange(of: format) { _, _ in capacity = max(minimumCapacity, min(capacity, 100)) }
        .task {
            guard !initialized else { return }; initialized = true
            if let initial { apply(initial) } else { closes = starts }
        }
    }
    private var startDate: some View {
        GroupActivityDateField(title: NSLocalizedString("date", value: "Date", comment: ""), selection: $starts, components: .date, minimum: Date(), allowsTimeSelection: true)
            .accessibilityIdentifier("group_activity_date")
    }
    private var startTime: some View {
        GroupActivityDateField(title: groupText("starts_at", "Starts at"), selection: $starts, components: .hourAndMinute, minimum: Date())
            .accessibilityIdentifier("group_activity_starts")
    }
    private var capacityControl: some View {
        HStack(spacing: 0) {
            Button { capacity = max(minimumCapacity, capacity - 1) } label: { Image(systemName: "minus").frame(width: 40, height: 44) }
                .disabled(capacity <= minimumCapacity)
            TextField("", value: $capacity, format: .number).keyboardType(.numberPad).multilineTextAlignment(.center)
                .font(.system(size: Theme.fontBody1)).frame(width: 48, height: 44)
            Button { capacity = min(100, capacity + 1) } label: { Image(systemName: "plus").frame(width: 40, height: 44) }
                .disabled(capacity >= 100)
        }.buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
            .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("group_activity_capacity").accessibilityValue(String(capacity))
    }
    private func requestClose() { guard !busy else { return }; dismiss() }
    private func apply(_ activity: GroupActivity) { title = activity.pendingTitle ?? activity.title; place = activity.place; note = activity.note; starts = activity.date; closes = Date(timeIntervalSince1970: Double(activity.registrationClosesAt ?? activity.startsAt) / 1000); registeredCount = activity.registeredMemberIds.count; capacity = activity.capacity; format = activity.format; matchMode = activity.matchMode ?? "single"; revision = activity.revision }
    private func submit() async {
        guard valid, !busy else { return }; busy = true; defer { busy = false }
        guard let accountID = store.accountID else { return }
        let body = GroupActivityBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines), startsAt: Int64(starts.timeIntervalSince1970 * 1000), place: place, capacity: capacity, note: note, format: format, matchMode: matchMode, registrationClosesAt: Int64(closes.timeIntervalSince1970 * 1000))
        if await store.perform({
            if let initial { let _: GroupActivity = try await store.repository.write("/\(groupID)/activities/\(initial.id)", body: body, method: .patch) }
            else { let _ = try await store.repository.createActivity(groupID: groupID, body: body, accountID: accountID) }
        }) { CommonPlacesManager.shared.savePlaceIfNeeded(place); dismiss() }
        else { error = store.error }
    }
}

struct GroupActivityMatchDestination: Identifiable {
    var id = UUID(); var manual: Bool; var session: GroupActivitySession?
}

struct GroupActivityView: View {
    var detail: GroupDetailCache
    var activity: GroupActivity
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared
    @State private var loaded: GroupActivity?
    @State private var lineup: GroupActivityLineup?
    @State private var match: GroupActivityMatchDestination?
    @State private var editing = false
    @State private var editingLineup = false
    @State private var viewingLineup = false
    @State private var registrationEditing = false
    @State private var busy = false
    @State private var reason = ""
    @State private var cancel = false
    @State private var abandonID: String?
    @State private var error: String?
    @State private var reminder = false
    @State private var loadSequence = 0
    @State private var resumableGames = Set<String>()
    @State private var gameCreators: [String: String] = [:]
    @State private var gameStates: [String: String] = [:]
    @State private var now = Int64(Date().timeIntervalSince1970 * 1000)
    private var current: GroupActivity { loaded ?? store.cache.details[detail.group.id]?.activities.first { $0.id == activity.id } ?? activity }
    private var latest: GroupDetailCache { store.cache.details[detail.group.id] ?? detail }
    private var me: GroupMember? { latest.members.first { $0.accountId == store.accountID && $0.status == "active" } }
    private var manager: Bool { GroupPermissions.manager(me) || me?.id == current.creatorMemberId }
    private var writable: Bool { latest.group.isActive && !store.cached && store.enabled }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.padding) {
                HStack(spacing: Theme.sm) {
                    Text(current.title).font(.system(size: Theme.fontBody1, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                    if manager && (current.canEdit(at: now) || current.canCancel) { activityMenu }
                }
                activityInformation
                if !current.isDirect { registrationCard }
                if !current.isMulti {
                    ForEach(latest.results.filter { $0.activityId == current.id }) { GroupResultLink(result: $0, showDisclosure: false) }
                }
                if let error = error ?? store.error { GroupNotice(text: error) }
            }.padding(Theme.padding).frame(maxWidth: Theme.focusedContentMaxWidth).frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(groupText("activity_detail", "Activity details")).navigationBarTitleDisplayMode(.inline)
        .groupAccountBoundary().task { await reload() }.refreshable { await reload() }
        .safeAreaInset(edge: .bottom, spacing: 0) { activityFooter }
        .task(id: current.registrationClosesAt ?? current.startsAt) {
            for boundary in [current.registrationClosesAt ?? current.startsAt, current.startsAt].sorted() {
                let delay = Double(boundary) / 1000 - Date().timeIntervalSince1970
                if delay > 0 { do { try await Task.sleep(for: .seconds(delay)) } catch { return } }
                now = Int64(Date().timeIntervalSince1970 * 1000)
            }
        }
        .navigationDestination(isPresented: Binding(get: { match != nil }, set: { if !$0 { match = nil } })) {
            if let destination = match {
                GroupMatchEditor(detail: latest, activity: current, activitySession: destination.session, manual: destination.manual, usesParentNavigation: true, onStart: onStart)
            }
        }
        .navigationDestination(isPresented: $editing) {
            GroupActivityCreateView(groupID: latest.group.id, initial: current, usesParentNavigation: true)
        }
        .navigationDestination(isPresented: $editingLineup) {
            if let lineup { GroupActivityLineupEditor(detail: latest, activity: current, initial: lineup, usesParentNavigation: true) }
        }
        .navigationDestination(isPresented: $viewingLineup) { activityMatches }
        // Registration is intentionally a sheet: it remains a short, guarded batch operation.
        .sheet(isPresented: $registrationEditing, onDismiss: { Task { await reload() } }) {
            GroupRegistrationEditor(detail: latest, activity: current, onReload: reload)
        }
        .onChange(of: editing) { _, value in if !value { Task { await reload() } } }
        .onChange(of: editingLineup) { _, value in if !value { Task { await reload() } } }
        .onChange(of: match != nil) { _, value in if !value { Task { await reload() } } }
        .groupAlert(groupText("cancel_activity", "Cancel activity?"), isPresented: $cancel) {
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) { }
            Button(groupText("cancel_activity", "Cancel activity"), role: .destructive) { Task { await cancelActivity() } }
                .disabled(busy || !writable || !GroupActivityPolicy.validCancellationReason(reason))
                .accessibilityIdentifier("group_activity_cancel_action")
        } message: {
            VStack(alignment: .leading, spacing: Theme.md) {
            Text(groupText("cancel_activity_message", "Cancelling clears all registrations and cannot be undone. An activity that has started cannot be cancelled."))
                TextField(groupText("cancel_reason_optional", "Reason (optional)"), text: $reason)
                    .groupAlignedInput().accessibilityIdentifier("group_activity_cancel_reason")
            }
        }
        .onChange(of: reason) { _, value in reason = GroupActivityPolicy.limitedCancellationReason(value) }
        .groupAlert(groupText("abandon_game", "Release this match?"), isPresented: abandonPresentation(inLineup: false)) {
            abandonActions
        } message: {
            Text(groupText("abandon_game_message", "Release this match’s scoring slot? The unfinished local score will no longer be submitted for this match. Existing results are not changed."))
        }
    }
    private func abandonPresentation(inLineup: Bool) -> Binding<Bool> {
        Binding(get: { abandonID != nil && viewingLineup == inLineup }, set: { shown in
            if !shown && viewingLineup == inLineup { abandonID = nil }
        })
    }
    @ViewBuilder private var abandonActions: some View {
        Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) { abandonID = nil }
            if let gameID = abandonID {
                Button(groupText("abandon_game", "Release match"), role: .destructive) {
                    Task {
                        busy = true; defer { busy = false }
                        if await store.perform({ try await store.repository.action("/\(latest.group.id)/games/\(gameID)/abandon") }), let account = store.accountID {
                            try? GroupLocalPersistence.shared.abandonGame(groupID: latest.group.id, gameID: gameID, accountID: account)
                            abandonID = nil; await reload()
                        }
                    }
                }
            }
    }

    private var activityMenu: some View {
        Menu {
            if current.canEdit(at: now) {
                Button(groupText("edit_activity", "Edit activity")) { editing = true }
                    .disabled(busy || !writable || !store.allows("update_activity"))
                    .accessibilityIdentifier("group_activity_edit")
            }
            if current.canCancel {
                Button(groupText("cancel_activity", "Cancel activity"), role: .destructive) { reason = ""; cancel = true }
                    .disabled(busy || !writable || !store.allows("update_activity"))
            }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(Theme.textSecondary) }
        .accessibilityLabel(NSLocalizedString("more", value: "More", comment: ""))
        .accessibilityIdentifier("group_activity_more")
    }
    private var activityInformation: some View {
        GroupActivitySurface {
            HStack(spacing: Theme.sm) {
                GroupActivityStatusChip(text: current.isDirect && current.status == "recruiting" ? groupText("activity_status_scheduled", "Scheduled") : current.statusLabel, status: current.status)
                GroupActivityTagChip(text: current.isDirect ? groupText("activity_direct_title", "Direct match") : current.format.title)
            }
            VStack(alignment: .leading, spacing: Theme.xs) {
                Text(current.isSequenced ? current.date.formatted(.dateTime.year().month().day()) + " · " + groupText("activity_timing_sequence", "No fixed time") : current.date.formatted(date: .abbreviated, time: .shortened))
                if !current.place.isEmpty { Text(current.place) }
                if !current.note.isEmpty { Text(current.note) }
            }.font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
            if current.isDirect {
                Text(String.localizedStringWithFormat(NSLocalizedString("activity_direct_match_count", value: "%d matches · all group members", comment: "Groups"), current.sessionCount ?? 0))
                    .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
            } else {
                Text(groupText("registration_closes", "Registration closes") + " · " + Date(timeIntervalSince1970: Double(current.registrationClosesAt ?? current.startsAt) / 1000).formatted())
                    .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
            }
            if current.titleModerationStatus == "pending" { GroupNotice(text: groupText("moderation_pending", "Your changes are awaiting review.")) }
            if let account = store.accountID, let me, current.registeredMemberIds.contains(me.id), current.status == "recruiting" {
                Toggle(groupText("activity_reminder", "Remind me 15 minutes before"), isOn: Binding(get: { reminder }, set: { value in
                    Task {
                        do { try await GroupActivityReminder.shared.set(enabled: value, accountID: account, groupID: latest.group.id, activity: current); reminder = value }
                        catch { self.error = groupErrorMessage(error) }
                    }
                })).font(.system(size: Theme.fontBody2)).tint(Theme.primary).disabled(!writable || busy)
            }
        }
    }
    private var registrationCard: some View {
        GroupActivitySurface {
            HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
                Text(groupText("registered_members", "Registered members") + " · \(current.registeredMemberIds.count)/\(current.capacity)")
                    .font(.system(size: Theme.fontBody2, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("group_activity_registration_count")
                Spacer(minLength: 0)
                if registrationVisible, GroupPermissions.manager(me), latest.members.contains(where: { $0.kind == "temporary" && $0.status == "active" }) {
                    Button(groupText("activity_registration_manage", "Temporary member registration")) { registrationEditing = true }
                        .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.primary).buttonStyle(.plain)
                        .disabled(busy || !writable || !current.registrationOpen(at: now) || !store.allows("register_activity"))
                        .accessibilityIdentifier("group_activity_registration_manage")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), alignment: .top)], alignment: .leading, spacing: Theme.sm) {
                ForEach(latest.members.filter { current.registeredMemberIds.contains($0.id) }) { member in
                    VStack(spacing: Theme.xs) {
                        GroupAvatar(name: member.displayName, url: member.avatarUrl, size: 38)
                        Text(member.displayName).font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity)
                }
            }
            if registrationVisible, let me, manager {
                Divider()
                HStack(spacing: Theme.sm) {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text(groupText("activity_my_registration", "My registration")).font(.system(size: Theme.fontBody2))
                        Text(groupText(current.registeredMemberIds.contains(me.id) ? "activity_registration_registered" : "activity_registration_not_registered", current.registeredMemberIds.contains(me.id) ? "Registered" : "Not registered"))
                            .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("group_activity_my_registration_status")
                    }
                    Spacer()
                    registrationButton(me.id)
                }.accessibilityIdentifier("group_activity_my_registration")
            }
        }
    }
    private var registrationVisible: Bool {
        !current.isDirect && (current.status == "recruiting" || (current.isMulti && current.status == "in_progress"))
    }
    private var activityFooter: some View {
        GroupAlignedFooter {
            if current.isMulti {
                if let lineup {
                    if !manager, !current.isDirect, current.registrationOpen(at: now), let me, !current.registeredMemberIds.contains(me.id) {
                        registrationButton(me.id).buttonStyle(GroupAlignedActionStyle())
                    }
                    Button(groupText(lineup.canManage ? "activity_lineup" : "view_schedule", lineup.canManage ? "Match schedule" : "View matches")) {
                        if lineup.canManage && lineup.sessions.isEmpty && !["completed", "cancelled"].contains(current.status) && writable && store.allows("update_activity") { editingLineup = true }
                        else { viewingLineup = true }
                    }.buttonStyle(GroupAlignedActionStyle()).disabled(busy)
                        .accessibilityIdentifier("group_activity_lineup_open")
                    if !manager, !current.isDirect, current.registrationOpen(at: now), let me, current.registeredMemberIds.contains(me.id) {
                        registrationButton(me.id).buttonStyle(.plain).foregroundStyle(Theme.primary)
                            .frame(minHeight: 44)
                    }
                } else {
                    Button(groupText("retry", "Retry")) { Task { await reload() } }.buttonStyle(GroupAlignedActionStyle()).disabled(busy)
                }
            } else if current.status != "cancelled" {
                VStack(spacing: Theme.sm) {
                    if !manager, current.registrationOpen(at: now), let me { registrationButton(me.id) }
                    matchActions(session: nil, localGameIDs: resumableGames, snapshotCreators: gameCreators, snapshotStates: gameStates)
                }.buttonStyle(GroupAlignedActionStyle())
            }
        }
    }
    private func registrationButton(_ id: String) -> some View {
        Button(current.registeredMemberIds.contains(id) ? groupText("unregister", "Cancel registration") : groupText("register", "Sign up")) { registration(id) }
            .disabled(busy || !writable || !current.registrationOpen(at: now) || !store.allows("register_activity") || (!current.registeredMemberIds.contains(id) && current.registeredMemberIds.count >= current.capacity))
    }
    private var activityMatches: some View {
        let localGameIDs = resumableGames
        let snapshotCreators = gameCreators
        let snapshotStates = gameStates
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.padding) {
                if let lineup {
                    ForEach(lineup.sessions) { session in
                        GroupActivitySurface {
                            Text("\(session.orderNo) · \(session.court) · \(session.format.title)")
                                .font(.system(size: Theme.fontBody1, weight: .medium)).accessibilityIdentifier("group_activity_session_\(session.orderNo)")
                            Text(session.date, format: .dateTime).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
                            Text(session.seats.map { seat in seat.displayName ?? latest.members.first(where: { $0.id == seat.memberId })?.displayName ?? "" }.joined(separator: " / "))
                                .font(.system(size: Theme.fontBody2))
                            matchActions(session: session, localGameIDs: localGameIDs, snapshotCreators: snapshotCreators, snapshotStates: snapshotStates)
                                .buttonStyle(GroupAlignedActionStyle(secondary: true))
                            if let resultID = session.resultId, !resultID.isEmpty {
                                NavigationLink(groupText("match_detail", "Match details")) { GroupRemoteResultView(groupID: latest.group.id, resultID: resultID) }
                            }
                        }
                    }
                    if lineup.sessions.isEmpty { GroupNotice(text: groupText("no_sessions", "No matches arranged yet.")) }
                    if lineup.canManage && !lineup.sessions.isEmpty && !["completed", "cancelled"].contains(current.status) {
                        Button(groupText("complete_activity", "Finish activity")) {
                            Task {
                                busy = true; defer { busy = false }
                                if await store.perform({ let _: GroupActivityLineup = try await store.repository.write("/\(latest.group.id)/activities/\(current.id)/complete", revision: lineup.revision) }) { await reload() }
                            }
                        }.buttonStyle(GroupAlignedActionStyle(secondary: true))
                            .disabled(busy || !writable || lineup.sessions.contains { !["completed", "cancelled"].contains($0.status) })
                            .accessibilityIdentifier("group_activity_finish")
                    }
                }
                ForEach(latest.results.filter { $0.activityId == current.id }) { GroupResultLink(result: $0, showDisclosure: false) }
                if let error = error ?? store.error { GroupNotice(text: error) }
            }.padding(Theme.padding).frame(maxWidth: Theme.focusedContentMaxWidth).frame(maxWidth: .infinity)
        }.background(Theme.backgroundColor).navigationTitle(groupText("activity_lineup", "Match schedule"))
            .navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let lineup, lineup.canManage, !["completed", "cancelled"].contains(current.status) {
                    GroupAlignedFooter {
                        Button(groupText("edit_lineup", "Arrange matches")) { editingLineup = true }
                            .buttonStyle(GroupAlignedActionStyle()).disabled(busy || !writable || !store.allows("update_activity"))
                            .accessibilityIdentifier("group_activity_lineup_edit")
                    }
                }
            }
            .groupAlert(groupText("abandon_game", "Release this match?"), isPresented: abandonPresentation(inLineup: true)) {
                abandonActions
            } message: {
                Text(groupText("abandon_game_message", "Release this match’s scoring slot? The unfinished local score will no longer be submitted for this match. Existing results are not changed."))
            }
    }
    private func cancelActivity() async {
        guard !busy, writable, manager, current.canCancel, store.allows("update_activity"),
              GroupActivityPolicy.validCancellationReason(reason) else { return }
        busy = true
        defer { busy = false }
        if await store.perform({ try await store.repository.action("/\(latest.group.id)/activities/\(current.id)/cancel", body: .init(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)), revision: current.revision) }) {
            await reload()
        }
    }
    @ViewBuilder private func matchActions(session: GroupActivitySession?, localGameIDs: Set<String>, snapshotCreators: [String: String], snapshotStates: [String: String]) -> some View {
        let seats = session?.seats ?? []
        let gameID = session?.gameID ?? (current.gameId.isEmpty ? nil : current.gameId)
        // 单场活动放开给任意在组成员开局/补记（对齐安卓 `canStart = matchMode != "multi" && isActiveMember`）。
        let allowed = GroupPermissions.canScore(current, me: me, seats: seats) || session?.canCorrectResult == true || (!current.isMulti && me != nil) || (!current.isMulti && current.registeredMemberIds.contains(me?.id ?? "")) || gameID.flatMap { snapshotCreators[$0] } == me?.id && me != nil
        let singleCorrection = session == nil && !current.gameId.isEmpty && latest.results.contains { $0.activityId == current.id && $0.gameId == current.gameId && $0.status == "voided" } && !latest.results.contains { $0.activityId == current.id && $0.status != "voided" }
        let correcting = session?.canCorrectResult == true || singleCorrection
        let completed = session.map { ["completed", "cancelled"].contains($0.status) } ?? (current.status == "completed")
        if !GroupActivityPolicy.allowsMatchEntry(activityStatus: current.status, sessionStatus: session?.status) {
            EmptyView()
        } else if completed {
            if correcting { Button(groupText("manual_result", "Add match result")) { match = .init(manual: true, session: session) }.disabled(!allowed || !writable) }
        } else if session?.status != "cancelled" && current.status != "cancelled" {
            if let gameID {
                if localGameIDs.contains(gameID), snapshotStates[gameID] == "started" { Button(groupText("resume_score", "Continue this device’s match")) { Task { await resume(gameID) } }.disabled(!allowed || busy) }
                GroupNotice(text: groupText("frozen_match_hint", "If scoring is on another device, continue there or add the result with the saved rules."))
                Button(groupText("manual_result", "Add match result")) { match = .init(manual: true, session: session) }.disabled(!allowed || !writable).accessibilityIdentifier("group_activity_frozen_manual_\(session?.orderNo ?? 0)")
                if GroupPermissions.manager(me) || snapshotCreators[gameID] == me?.id && me != nil { Button(groupText("abandon_game", "Release match"), role: .destructive) { abandonID = gameID }.disabled(!writable || busy).accessibilityIdentifier("group_activity_abandon_" + gameID) }
            } else {
                Button(groupText("start_score", "Start scoring")) { match = .init(manual: false, session: session) }.disabled(!allowed || !writable || session?.needsLineup == true)
                Button(groupText("manual_result", "Add match result")) { match = .init(manual: true, session: session) }.disabled(!allowed || !writable || session?.needsLineup == true)
            }
        }
    }
    private func resume(_ gameID: String) async {
        guard let account = store.accountID else { return }
        do {
            let sessionID = try await GroupGameOperations.resumeID(gameID: gameID, groupID: latest.group.id, accountID: account)
            onStart(latest.group.sport.gameType, SportsSetupResult(team1Name: "", team2Name: ""), sessionID)
        } catch { self.error = groupErrorMessage(error) }
    }
    private func reload() async {
        await store.loadDetail(detail.group.id)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestGroupsFixture") { loaded = latest.activities.first { $0.id == activity.id }; lineup = latest.activityLineups?[activity.id]; return }
        #endif
        guard let account = store.accountID else { return }; let revision = store.identityRevision
        loadSequence += 1; let sequence = loadSequence
        do {
            let fresh: GroupActivity = try await store.repository.read("/\(detail.group.id)/activities/\(activity.id)")
            let schedule: GroupActivityLineup? = fresh.isMulti ? try await store.repository.read("/\(detail.group.id)/activities/\(activity.id)/lineup") : nil
            guard store.matchesIdentity(account, revision: revision), loadSequence == sequence else { return }
            loaded = fresh; lineup = schedule; error = nil
            let local = (try? await ResumeSessionRepository().liveEntries()) ?? []
            guard store.matchesIdentity(account, revision: revision), loadSequence == sequence else { return }
            resumableGames = Set(local.compactMap { row in let context = GroupLocalPersistence.shared.context(sessionID: row.sessionId.uuidString); return context?.accountID == account && context?.groupID == latest.group.id ? context?.gameID : nil })
            let gameIDs = Set((schedule?.sessions.compactMap(\.gameID) ?? []) + (fresh.gameId.isEmpty ? [] : [fresh.gameId]))
            let repository = store.repository, groupID = detail.group.id, authRevision = await store.repository.client.authSessionRevision()
            let snapshots = await withTaskGroup(of: GroupGameSnapshot?.self, returning: [GroupGameSnapshot].self) { tasks in
                for id in gameIDs { tasks.addTask { try? await repository.read("/\(groupID)/games/\(id)", expectedAuthRevision: authRevision) } }
                var rows: [GroupGameSnapshot] = []; for await row in tasks { if let row, row.groupId == groupID, gameIDs.contains(row.gameId) { rows.append(row) } }; return rows
            }
            guard store.matchesIdentity(account, revision: revision), loadSequence == sequence else { return }
            gameCreators = Dictionary(uniqueKeysWithValues: snapshots.compactMap { row in row.creatorMemberId.map { (row.gameId, $0) } })
            gameStates = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.gameId, $0.state) })
            reminder = GroupActivityReminder.shared.enabled(accountID: account, activityID: fresh.id)
        } catch { if store.matchesIdentity(account, revision: revision), loadSequence == sequence { self.error = groupErrorMessage(error) } }
    }
    private func registration(_ id: String) { Task { busy = true; defer { busy = false }; let action = current.registeredMemberIds.contains(id) ? "unregister" : "register"; if await store.perform({ try await store.repository.action("/\(latest.group.id)/activities/\(current.id)/\(action)", body: .init(memberId: id)) }) { await reload() } } }
}

struct GroupRemoteResultView: View {
    var groupID: String; var resultID: String
    @State private var result: GroupResult?
    @State private var error: String?
    var body: some View {
        Group { if let result { GroupResultDetailView(initial: result) } else if let error { GroupNotice(text: error) } else { ProgressView() } }.task {
            let store = GroupStore.shared; guard let account = store.accountID else { return }; let revision = store.identityRevision
            do { let loaded: GroupResult = try await store.repository.read("/\(groupID)/results/\(resultID)"); if store.matchesIdentity(account, revision: revision) { result = loaded } }
            catch { if store.matchesIdentity(account, revision: revision) { self.error = groupErrorMessage(error) } }
        }.groupAccountBoundary()
    }
}

/// 直接排赛（安卓 `createDirectLineup`）：一次建 `activityType=direct` 活动 + 对阵场次。
/// 候选人是全部在组成员，无需先报名；时间模式二选一（sequence 按顺序 / estimated 预计时间）。
struct GroupDirectScheduleView: View {
    var detail: GroupDetailCache
    var usesParentNavigation = false
    @State private var store = GroupStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GroupDirectScheduleDraft()
    @State private var initialized = false
    @State private var title = ""
    @State private var place = ""
    @State private var format = GroupFormat.singles
    @State private var busy = false
    @State private var error: String?
    @State private var showCommonPlaces = false
    @State private var expandedID: UUID?
    private var members: [GroupMember] { (store.cache.details[detail.group.id] ?? detail).members.filter { $0.status == "active" } }
    private var limit: Int { store.capabilities?.activitySessionMax ?? 12 }
    private var memberMax: Int { store.capabilities?.activityMemberSessionMax ?? 8 }
    private var enoughMembers: Bool { members.count >= format.seatsPerSide * 2 }
    private var issue: String? { GroupTrainingValidation.lineupIssue(draft.sessions, minutes: draft.minutes, maximumSessions: limit, maximumPerMember: memberMax, skipsConflicts: draft.timingMode == "sequence") }
    private var valid: Bool { issue == nil && !draft.sessions.isEmpty && GroupActivityPolicy.validText(title: title, place: place) && store.allows("create_activity") }
    var body: some View {
        Group {
            if usesParentNavigation { editor }
            else { NavigationStack { editor } }
        }
    }
    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.padding) {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    TextField(groupText("activity_field_title_optional", "Activity name (optional)"), text: $title)
                        .groupAlignedInput().accessibilityIdentifier("group_direct_title")
                    Text(groupText("activity_title_auto_hint", "If left empty, the name is generated from the date."))
                        .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
                }
                HStack(alignment: .top, spacing: Theme.sm) {
                    GroupActivityDateField(selection: $draft.date)
                    HStack(spacing: Theme.sm) {
                        TextField(groupText("place", "Location"), text: $place)
                        Button { showCommonPlaces = true } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.plain).foregroundStyle(Theme.primary)
                            .accessibilityLabel(NSLocalizedString("schedule_pick_common_place", value: "Choose a saved place", comment: ""))
                    }.groupAlignedInput()
                }
                GroupActivityChoices(selection: $format, values: GroupFormat.allCases, title: { $0.title })
                GroupActivityChoices(selection: $draft.timingMode, values: ["sequence", "estimated"], title: {
                    groupText($0 == "sequence" ? "activity_timing_sequence" : "activity_timing_estimated", $0 == "sequence" ? "No fixed time" : "Set estimated times")
                }).accessibilityIdentifier("group_activity_direct_timing")
                if draft.timingMode == "estimated" {
                    GroupAlignedField(groupText("activity_lineup_duration", "Minutes per match")) {
                        GroupActivityChoices(selection: $draft.minutes, values: GroupActivityPolicy.durationOptions(current: draft.minutes), title: {
                            String(format: groupText("activity_lineup_minutes", "%d min"), $0)
                        })
                    }
                }
                Divider()
                GroupActivityLineupHeading(count: draft.sessions.count)
                GroupRosterAddButton(groupID: detail.group.id)
                ForEach($draft.sessions) { $session in sessionRow($session) }
                Button { addSession(); expandedID = draft.sessions.last?.id } label: {
                    Label(groupText("activity_lineup_add", "Add a match"), systemImage: "plus")
                }.buttonStyle(GroupAlignedActionStyle(secondary: true)).disabled(draft.sessions.count >= limit)
                if !enoughMembers {
                    GroupNotice(text: groupText("need_members", "Invite friends or add temporary members before starting a match.") + " (\(members.count) / \(format.seatsPerSide * 2))")
                }
                if let issue { GroupNotice(text: issue) }
                if let error = error ?? store.error { GroupNotice(text: error) }
            }.padding(Theme.padding).frame(maxWidth: Theme.focusedContentMaxWidth).frame(maxWidth: .infinity)
        }.background(Theme.backgroundColor).disabled(busy).scrollDismissesKeyboard(.interactively)
            .navigationTitle(groupText("activity_direct_title", "Direct match")).navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
            .navigationBarBackButtonHidden(usesParentNavigation)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if usesParentNavigation { Button { requestClose() } label: { Image(systemName: "chevron.left") }.disabled(busy) }
                    else { ModalCloseButton { requestClose() }.disabled(busy) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GroupAlignedFooter {
                    Button(groupText("activity_direct_save", "Save matches")) { Task { await submit() } }
                        .buttonStyle(GroupAlignedActionStyle()).disabled(busy || !valid)
                        .accessibilityIdentifier("group_activity_direct_save")
                }
            }
            .interactiveDismissDisabled(busy)
            .groupCommonPlacesDialog(isPresented: $showCommonPlaces, selection: $place)
            .onChange(of: format) { _, value in
                for index in draft.sessions.indices { draft.sessions[index].format = value; draft.sessions[index].memberIDs = ["", "", "", ""] }
            }
            .task { guard !initialized else { return }; initialized = true; expandedID = draft.sessions.first?.id }
    }
    @ViewBuilder private func sessionRow(_ session: Binding<GroupTrainingDraftSession>) -> some View {
        let row = session.wrappedValue
        let index = draft.sessions.firstIndex(where: { $0.id == row.id }) ?? 0
        let expanded = expandedID == row.id
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.sm) {
                Button { expandedID = expanded ? nil : row.id } label: {
                    HStack(spacing: Theme.sm) {
                        Text(String(format: groupText("activity_lineup_session", "Match %d"), index + 1)).font(.system(size: Theme.fontBody1, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: Theme.fontCaption))
                    }.foregroundStyle(Theme.textPrimary).frame(minHeight: 40)
                }.buttonStyle(.plain)
                if draft.sessions.count > 1 {
                    Button(role: .destructive) { draft.sessions.removeAll { $0.id == row.id } } label: {
                        Image(systemName: "xmark").frame(width: 40, height: 40)
                    }.buttonStyle(.plain).accessibilityLabel(groupText("activity_lineup_remove", "Remove"))
                }
            }
            if expanded {
                HStack(spacing: Theme.sm) {
                    if draft.timingMode == "estimated" {
                        GroupActivityDateField(selection: session.startsAt, compact: true, initiallySelectsTime: true)
                            .onChange(of: row.startsAt) { _, _ in reorder() }
                    } else {
                        Text(index == 0 ? groupText("activity_time_unspecified", "Time to be decided") : groupText("activity_time_after_previous", "After the previous match"))
                            .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    TextField(groupText("activity_lineup_court", "Court"), text: session.court).groupAlignedInput(minHeight: 44)
                }
                GroupInlineMatchRoster(format: row.format, ids: session.memberIDs, members: members, showSeatLabels: false, prominentText: true)
            } else {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text(draft.timingMode == "estimated" ? row.startsAt.formatted(date: .abbreviated, time: .shortened) : groupText(index == 0 ? "activity_time_unspecified" : "activity_time_after_previous", index == 0 ? "Time to be decided" : "After the previous match"))
                    if !row.court.isEmpty { Text(row.court) }
                    Text(row.selectedIDs.map { id in members.first(where: { $0.id == id })?.displayName ?? groupText("choose_member", "Choose a member") }.joined(separator: " / "))
                }.font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
            }
        }.padding(.horizontal, Theme.padding).padding(.vertical, Theme.sm)
            .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider.opacity(0.45), lineWidth: 1))
    }
    private func requestClose() { guard !busy else { return }; dismiss() }
    private func addSession() { draft.add(format: format) }
    private func reorder() { guard draft.timingMode == "estimated" else { return }; draft.sessions.sort { $0.startsAt < $1.startsAt } }
    private func body(_ row: GroupTrainingDraftSession, order: Int) -> GroupTrainingSessionBody {
        .init(orderNo: order, court: row.court, startsAt: Int64(row.startsAt.timeIntervalSince1970 * 1000), format: row.format,
              seats: row.selectedIDs.enumerated().map { index, id in .init(memberId: id, side: index < row.format.seatsPerSide ? "A" : "B", seat: index % row.format.seatsPerSide) })
    }
    private func submit() async {
        guard valid, !busy, let accountID = store.accountID else { return }
        busy = true; defer { busy = false }
        let bodies = draft.sessions.enumerated().map { body($0.element, order: $0.offset + 1) }
        let payload = GroupDirectLineupBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines), startsAt: Int64(draft.date.timeIntervalSince1970 * 1000),
                                            place: place, format: format, timingMode: draft.timingMode, sessionMinutes: draft.minutes, sessions: bodies)
        if await store.perform({ let _: GroupDirectLineupResponse = try await store.repository.createDirectLineup(groupID: detail.group.id, body: payload, accountID: accountID) }) {
            CommonPlacesManager.shared.savePlaceIfNeeded(place); dismiss()
        } else { error = store.error }
    }
}
