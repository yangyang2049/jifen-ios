import SwiftUI
import PersistenceCore

struct GroupActivityCreateView: View {
    let groupID: String
    var initial: GroupActivity? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var title = ""
    @State private var place = ""
    @State private var note = ""
    @State private var starts = Date().addingTimeInterval(3600)
    @State private var closes = Date().addingTimeInterval(3600)
    @State private var capacity = 8
    @State private var format = GroupFormat.doubles
    @State private var matchMode = "multi"
    @State private var busy = false
    @State private var key = UUID().uuidString
    @State private var revision: Int64?
    @State private var showCommonPlaces = false
    @State private var initialized = false
    @State private var error: String?
    @State private var conflictActivity: GroupActivity?
    private var valid: Bool {
        GroupInputValidation.validName(title, maximum: 60) && starts > Date() && closes <= starts && (closes > Date() || Int64(closes.timeIntervalSince1970 * 1000) == (initial?.registrationClosesAt ?? initial?.startsAt)) && note.unicodeScalars.count <= 200 && place.unicodeScalars.count <= 100 && capacity >= format.seatsPerSide * 2
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(groupText("activity_title", "Activity title"), text: $title).accessibilityIdentifier("group_activity_title")
                    DatePicker(groupText("starts_at", "Starts at"), selection: $starts, in: Date()...).accessibilityIdentifier("group_activity_starts")
                    DatePicker(groupText("registration_closes", "Registration closes"), selection: $closes, in: ...starts).accessibilityIdentifier("group_activity_closes")
                    HStack {
                        TextField(groupText("place", "Location"), text: $place)
                        Button { showCommonPlaces = true } label: { Image(systemName: "location.circle").foregroundStyle(Theme.primary) }
                            .buttonStyle(.plain).accessibilityLabel(NSLocalizedString("schedule_pick_common_place", value: "Choose a saved place", comment: ""))
                            .accessibilityIdentifier("group_activity_place_picker")
                    }
                    TextField(groupText("note", "Note"), text: $note, axis: .vertical)
                    Stepper(groupText("capacity", "Registration limit") + ": \(capacity)", value: $capacity, in: 2...max(4, store.cache.details[groupID]?.group.memberLimit ?? 50))
                    if initial == nil {
                        Picker(groupText("format", "Format"), selection: $format) { ForEach(GroupFormat.allCases) { Text($0.title).tag($0) } }
                        if store.capabilities?.supportsActivityLineup == true {
                            Picker(groupText("activity_mode", "Matches"), selection: $matchMode) { Text(groupText("multi_matches", "Multiple matches")).tag("multi"); Text(groupText("single_match", "One match")).tag("single") }
                        }
                    }
                    Text(groupText(matchMode == "multi" ? "multi_match_hint" : "single_match_hint", matchMode == "multi" ? "Registered players can be assigned to several matches." : "Select two singles players or four doubles players from the registrations.")).font(.caption).foregroundStyle(.secondary)
                }
                if let error { GroupNotice(text: error); Button(groupText("reload_version", "Load latest version")) { Task { await loadLatest() } }.disabled(busy) }
                if let remote = conflictActivity {
                    Section(groupText("server_version", "Latest version")) {
                        Text(remote.title); Text(remote.date, format: .dateTime); Text(remote.place); Text(remote.note)
                        Text("\(remote.registeredMemberIds.count)/\(remote.capacity)")
                        Button(groupText("reload_version", "Load latest version")) { apply(remote); conflictActivity = nil; error = nil }
                        Button(groupText("keep_draft", "Keep my edits")) { revision = remote.revision; conflictActivity = nil; error = nil }.disabled(!remote.canEdit(at: Int64(Date().timeIntervalSince1970 * 1000)))
                    }
                }
                Button(initial == nil ? groupText("create_activity", "Create activity") : groupText("save", "Save")) { Task { await submit() } }.disabled(busy || !valid).accessibilityIdentifier("group_activity_save")
            }.scrollDismissesKeyboard(.interactively).disabled(busy).navigationTitle(initial == nil ? groupText("new_activity", "Plan an activity") : groupText("edit_activity", "Edit activity")).groupAccountBoundary()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .sheet(isPresented: $showCommonPlaces) {
                    CommonPlacePickerView(providedPlaces: groupCaptureCommonPlaces()) { selected in place = String(selected.name.prefix(100)); showCommonPlaces = false }
                }
                .onChange(of: starts) { old, new in if closes == old { closes = new } }
                .onChange(of: signature) { _, _ in key = UUID().uuidString }
                .task { guard !initialized else { return }; initialized = true; if let initial { apply(initial) } else { closes = starts }; if store.capabilities?.supportsActivityLineup != true { matchMode = "single" } }
        }
    }
    private var signature: String { "\(title)|\(place)|\(note)|\(starts)|\(closes)|\(capacity)|\(format)|\(matchMode)" }
    private func apply(_ activity: GroupActivity) { title = activity.pendingTitle ?? activity.title; place = activity.place; note = activity.note; starts = activity.date; closes = Date(timeIntervalSince1970: Double(activity.registrationClosesAt ?? activity.startsAt) / 1000); capacity = activity.capacity; format = activity.format; matchMode = activity.matchMode ?? "single"; revision = activity.revision }
    private func loadLatest() async {
        guard let initial, let account = store.accountID else { return }; let identity = store.identityRevision
        do { let latest: GroupActivity = try await store.repository.read("/\(groupID)/activities/\(initial.id)"); if store.matchesIdentity(account, revision: identity) { conflictActivity = latest } }
        catch { if store.matchesIdentity(account, revision: identity) { self.error = groupErrorMessage(error) } }
    }
    private func submit() async {
        guard valid else { return }; busy = true; defer { busy = false }
        let body = GroupActivityBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines), startsAt: Int64(starts.timeIntervalSince1970 * 1000), place: place, capacity: capacity, note: note, format: format, matchMode: matchMode, registrationClosesAt: Int64(closes.timeIntervalSince1970 * 1000))
        if await store.perform({ let _: GroupActivity = try await store.repository.write("/\(groupID)/activities" + (initial.map { "/\($0.id)" } ?? ""), body: body, method: initial == nil ? .post : .patch, key: initial == nil ? key : nil, revision: revision) }) { CommonPlacesManager.shared.savePlaceIfNeeded(place); dismiss() }
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
        // Read asynchronous match state in the parent body before ForEach's deferred row closures.
        let localGameIDs = resumableGames
        let snapshotCreators = gameCreators
        let snapshotStates = gameStates
        Form {
            Section {
                HStack(spacing: Theme.xs) {
                    GroupActivityStatusChip(text: current.isDirect && current.status == "recruiting" ? groupText("activity_status_scheduled", "Scheduled") : groupText(current.status, current.status), status: current.status)
                    GroupActivityTagChip(text: current.isDirect ? groupText("activity_direct_title", "Direct match") : current.format.title)
                }
                Text(current.isSequenced ? current.date.formatted(.dateTime.year().month().day()) + " · " + groupText("activity_timing_sequence", "No fixed time") : current.date.formatted(date: .abbreviated, time: .shortened))
                Text(current.place); Text(current.note)
                if current.isDirect { Text(String(format: NSLocalizedString("activity_direct_match_count", value: "%d matches · all group members", comment: "Groups"), current.sessionCount ?? 0)) }
                else {
                    Text("\(current.registeredMemberIds.count)/\(current.capacity)")
                    Text(groupText("registration_closes", "Registration closes") + " · " + Date(timeIntervalSince1970: Double(current.registrationClosesAt ?? current.startsAt) / 1000).formatted())
                }
                if current.titleModerationStatus == "pending" { GroupNotice(text: groupText("moderation_pending", "Your changes are awaiting review.")) }
                if manager && current.canEdit(at: now) { Button(groupText("edit_activity", "Edit activity")) { editing = true }.disabled(!writable) }
            }
            if !current.isDirect { Section(groupText("registered_members", "Registered members")) {
                ForEach(latest.members.filter { current.registeredMemberIds.contains($0.id) }) { Text($0.displayName) }
                if current.registrationOpen(at: now), let me {
                    Button(current.registeredMemberIds.contains(me.id) ? groupText("unregister", "Cancel registration") : groupText("register", "Sign up")) { registration(me.id) }.disabled(busy || !writable || (!current.registeredMemberIds.contains(me.id) && current.registeredMemberIds.count >= current.capacity))
                    if GroupPermissions.manager(me) {
                        Button { registrationEditing = true } label: { Label(NSLocalizedString("edit", value: "Edit", comment: ""), systemImage: "person.2.badge.gearshape") }
                            .disabled(busy || !writable).accessibilityIdentifier("group_activity_registration_manage")
                    }
                }
                if let account = store.accountID, let me, current.registeredMemberIds.contains(me.id), current.status == "recruiting" {
                    Toggle(groupText("activity_reminder", "Remind me 15 minutes before"), isOn: Binding(get: { reminder }, set: { value in Task { do { try await GroupActivityReminder.shared.set(enabled: value, accountID: account, groupID: latest.group.id, activity: current); reminder = value } catch { self.error = groupErrorMessage(error) } } })).disabled(!writable)
                }
            } }
            if current.isMulti {
                Section(groupText("activity_lineup", "Match schedule")) {
                    if let lineup {
                        if lineup.canManage { Button(groupText(current.isDirect ? "activity_lineup_title" : "edit_lineup", current.isDirect ? "Activity matches" : "Arrange matches")) { editingLineup = true }.disabled(!writable || ["completed", "cancelled"].contains(current.status)) }
                        ForEach(lineup.sessions) { session in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(session.orderNo) · \(session.court) · \(session.format.title)").font(.headline).accessibilityIdentifier("group_activity_session_\(session.orderNo)")
                                Text(session.date, format: .dateTime)
                                Text(session.seats.map { seat in seat.displayName ?? latest.members.first(where: { $0.id == seat.memberId })?.displayName ?? "" }.joined(separator: " / "))
                                matchActions(session: session, localGameIDs: localGameIDs, snapshotCreators: snapshotCreators, snapshotStates: snapshotStates)
                                if let resultID = session.resultId, !resultID.isEmpty { NavigationLink(groupText("match_detail", "Match details")) { GroupRemoteResultView(groupID: latest.group.id, resultID: resultID) } }
                            }.buttonStyle(.borderless)
                        }
                        if lineup.sessions.isEmpty { GroupNotice(text: groupText("no_sessions", "No matches arranged yet.")) }
                        if lineup.canManage && !lineup.sessions.isEmpty && current.status != "completed" && current.status != "cancelled" {
                            Button(groupText("complete_activity", "Finish activity")) { Task { busy = true; defer { busy = false }; if await store.perform({ let _: GroupActivityLineup = try await store.repository.write("/\(latest.group.id)/activities/\(current.id)/complete", revision: lineup.revision) }) { await reload() } } }.disabled(busy || !writable || lineup.sessions.contains { !["completed", "cancelled"].contains($0.status) }).accessibilityIdentifier("group_activity_finish")
                        }
                    } else { Button(groupText("retry", "Retry")) { Task { await reload() } } }
                }
            } else if current.status != "cancelled" { Section { matchActions(session: nil, localGameIDs: localGameIDs, snapshotCreators: snapshotCreators, snapshotStates: snapshotStates) } }
            if current.canCancel && manager {
                Section { TextField(groupText("cancel_reason", "Reason for cancelling"), text: $reason).accessibilityIdentifier("group_activity_cancel_reason"); Button(groupText("cancel_activity", "Cancel activity"), role: .destructive) { cancel = true }.disabled(busy || !writable || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("group_activity_cancel_action") }
            }
            ForEach(latest.results.filter { $0.activityId == current.id }) { GroupResultLink(result: $0) }
            if let error = error ?? store.error { GroupNotice(text: error) }
        }.navigationTitle(current.title).groupAccountBoundary().task { await reload() }.refreshable { await reload() }
            .task(id: current.registrationClosesAt ?? current.startsAt) {
                for boundary in [current.registrationClosesAt ?? current.startsAt, current.startsAt].sorted() {
                    let delay = Double(boundary) / 1000 - Date().timeIntervalSince1970
                    if delay > 0 { do { try await Task.sleep(for: .seconds(delay)) } catch { return } }
                    now = Int64(Date().timeIntervalSince1970 * 1000)
                }
            }
            .sheet(item: $match, onDismiss: { Task { await reload() } }) { destination in GroupMatchEditor(detail: latest, activity: current, activitySession: destination.session, manual: destination.manual, onStart: onStart) }
            .sheet(isPresented: $registrationEditing, onDismiss: { Task { await reload() } }) { GroupRegistrationEditor(detail: latest, activity: current, onReload: reload) }
            .sheet(isPresented: $editing, onDismiss: { Task { await reload() } }) { GroupActivityCreateView(groupID: latest.group.id, initial: current) }
            .sheet(isPresented: $editingLineup, onDismiss: { Task { await reload() } }) { if let lineup { GroupActivityLineupEditor(detail: latest, activity: current, initial: lineup) } }
            .confirmationDialog(groupText("cancel_activity", "Cancel activity?"), isPresented: $cancel) { Button(groupText("cancel_activity", "Cancel activity"), role: .destructive) { Task { busy = true; defer { busy = false }; if await store.perform({ try await store.repository.action("/\(latest.group.id)/activities/\(current.id)/cancel", body: .init(reason: reason), revision: current.revision) }) { await reload() } } } }
            .confirmationDialog(groupText("abandon_game", "Release this match?"), isPresented: Binding(get: { abandonID != nil }, set: { if !$0 { abandonID = nil } })) {
                if let gameID = abandonID { Button(groupText("abandon_game", "Release match"), role: .destructive) { Task { busy = true; defer { busy = false }; if await store.perform({ try await store.repository.action("/\(latest.group.id)/games/\(gameID)/abandon") }), let account = store.accountID { try? GroupLocalPersistence.shared.abandonGame(groupID: latest.group.id, gameID: gameID, accountID: account); abandonID = nil; await reload() } } } }
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
        if completed {
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
    @State private var store = GroupStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var place = ""
    @State private var date = Date().addingTimeInterval(600)
    @State private var format = GroupFormat.singles
    @State private var timingMode = "sequence"
    @State private var minutes = 30
    @State private var sessions: [GroupTrainingDraftSession] = []
    @State private var busy = false
    @State private var error: String?
    @State private var showCommonPlaces = false
    @State private var initialized = false
    private var members: [GroupMember] { detail.members.filter { $0.status == "active" } }
    private var limit: Int { store.capabilities?.activitySessionMax ?? 100 }
    private var memberMax: Int { store.capabilities?.activityMemberSessionMax ?? 8 }
    private var enoughMembers: Bool { members.count >= format.seatsPerSide * 2 }
    private var issue: String? { GroupTrainingValidation.lineupIssue(sessions, minutes: minutes, maximumSessions: limit, maximumPerMember: memberMax, skipsConflicts: timingMode == "sequence") }
    private var anchor: Date { let now = Date(); return date <= now ? now.addingTimeInterval(60) : date }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(groupText("activity_field_title_optional", "Activity name (optional)"), text: $title)
                    Text(groupText("activity_title_auto_hint", "If left empty, the name is generated from the date.")).font(.caption).foregroundStyle(.secondary)
                    DatePicker(groupText("starts_at", "Starts at"), selection: $date)
                    HStack {
                        TextField(groupText("place", "Location"), text: $place)
                        Button { showCommonPlaces = true } label: { Image(systemName: "location.circle").foregroundStyle(Theme.primary) }
                            .buttonStyle(.plain).accessibilityLabel(NSLocalizedString("schedule_pick_common_place", value: "Choose a saved place", comment: ""))
                    }
                    Picker(groupText("format", "Format"), selection: $format) { ForEach(GroupFormat.allCases) { Text($0.title).tag($0) } }
                }
                Section {
                    Picker(groupText("activity_timing", "Timing"), selection: $timingMode) {
                        Text(groupText("activity_timing_sequence", "No fixed time")).tag("sequence")
                        Text(groupText("activity_timing_estimated", "Set estimated times")).tag("estimated")
                    }.pickerStyle(.segmented).accessibilityIdentifier("group_activity_direct_timing")
                    if timingMode == "estimated" {
                        Picker(groupText("activity_lineup_duration", "Minutes per match"), selection: $minutes) {
                            ForEach([20, 30, 45, 60], id: \.self) { Text(String(format: groupText("activity_lineup_minutes", "%d min"), $0)).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                } footer: { Text(groupText("activity_direct_hint", "Pick from all active members; no sign-up needed.")) }
                Section {
                    ForEach($sessions) { $session in sessionRow($session) }
                    Button { addSession() } label: { Label(groupText("activity_lineup_add", "Add a match"), systemImage: "plus") }
                        .disabled(sessions.count >= limit || !enoughMembers)
                    if !enoughMembers { Text(String(format: groupText("activity_lineup_add_need_members", "At least %d active members are needed to add a match."), format.seatsPerSide * 2)).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    HStack { Text(groupText("activity_lineup_section_matches", "Matches")); Spacer(); Text(String(format: groupText("activity_lineup_match_count", "%d matches"), sessions.count)).font(.caption).foregroundStyle(.secondary) }
                }
                if let issue { GroupNotice(text: issue) }
                if let error = error ?? store.error { GroupNotice(text: error) }
                Button(groupText("activity_direct_save", "Save matches")) { Task { await submit() } }
                    .disabled(busy || issue != nil || sessions.isEmpty || title.unicodeScalars.count > 40).accessibilityIdentifier("group_activity_direct_save")
            }.disabled(busy).scrollDismissesKeyboard(.interactively)
                .navigationTitle(groupText("activity_direct_title", "Direct match")).groupAccountBoundary()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .sheet(isPresented: $showCommonPlaces) {
                    CommonPlacePickerView(providedPlaces: groupCaptureCommonPlaces()) { selected in place = String(selected.name.prefix(100)); showCommonPlaces = false }
                }
                .onChange(of: timingMode) { _, value in if value == "sequence" { resequence() } }
                .onChange(of: minutes) { _, _ in if timingMode == "sequence" { resequence() } }
                .onChange(of: date) { old, new in
                    // 安卓 setDirectDate：所有场次跟着活动日期整体平移，保留场间间隔。
                    if timingMode == "sequence" { resequence() }
                    else { sessions = GroupTrainingValidation.shiftAll(sessions, by: new.timeIntervalSince(old)) }
                }
                .onChange(of: format) { _, value in for index in sessions.indices { sessions[index].format = value; sessions[index].memberIDs = ["", "", "", ""] } }
                .task { guard !initialized else { return }; initialized = true; var first = GroupTrainingDraftSession(); first.format = format; first.startsAt = anchor; sessions = [first] }
        }
    }
    @ViewBuilder private func sessionRow(_ session: Binding<GroupTrainingDraftSession>) -> some View {
        let row = session.wrappedValue
        let index = sessions.firstIndex(where: { $0.id == row.id }) ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: groupText("activity_lineup_session", "Match %d"), index + 1)).font(.headline)
                Spacer()
                if sessions.count > 1 { Button(groupText("activity_lineup_remove", "Remove"), role: .destructive) { sessions.removeAll { $0.id == row.id } } }
            }
            if timingMode == "estimated" {
                DatePicker(groupText("starts_at", "Start time"), selection: session.startsAt).onChange(of: row.startsAt) { _, _ in reorder() }
            } else {
                Text(index == 0 ? groupText("activity_time_unspecified", "Time to be decided") : groupText("activity_time_after_previous", "After the previous match")).font(.caption).foregroundStyle(.secondary)
            }
            TextField(groupText("activity_lineup_court", "Court"), text: session.court)
            ForEach([0, 1], id: \.self) { side in
                ForEach(0..<row.format.seatsPerSide, id: \.self) { seat in
                    GroupSeatPicker(title: "\(side == 0 ? "A" : "B")\(seat + 1)", selectedID: session.memberIDs[side * 2 + seat], members: members, excluded: Set(row.selectedIDs))
                }
            }
        }
    }
    private func addSession() {
        var next = GroupTrainingDraftSession(); next.format = format
        next.startsAt = (sessions.last?.startsAt ?? anchor).addingTimeInterval(Double(minutes) * 60)
        sessions.append(next)
        if timingMode == "sequence" { resequence() }
    }
    private func resequence() {
        let base = anchor
        for index in sessions.indices { sessions[index].startsAt = base.addingTimeInterval(Double(minutes * index) * 60) }
    }
    private func reorder() { guard timingMode == "estimated" else { return }; sessions.sort { $0.startsAt < $1.startsAt } }
    private func body(_ row: GroupTrainingDraftSession, order: Int) -> GroupTrainingSessionBody {
        .init(orderNo: order, court: row.court, startsAt: Int64(row.startsAt.timeIntervalSince1970 * 1000), format: row.format,
              seats: row.selectedIDs.enumerated().map { index, id in .init(memberId: id, side: index < row.format.seatsPerSide ? "A" : "B", seat: index % row.format.seatsPerSide) })
    }
    private func submit() async {
        guard issue == nil, !sessions.isEmpty, !busy else { return }
        busy = true; defer { busy = false }
        // 选了过去的时间时，活动与场次必须一起被推到「一分钟后」，否则两者会脱节。
        let scheduled = GroupTrainingValidation.anchored(sessions, startsAt: date, now: Date())
        let bodies = scheduled.sessions.enumerated().map { body($0.element, order: $0.offset + 1) }
        let payload = GroupDirectLineupBody(title: title.trimmingCharacters(in: .whitespacesAndNewlines), startsAt: Int64(scheduled.startsAt.timeIntervalSince1970 * 1000),
                                            place: place, format: format, timingMode: timingMode, sessionMinutes: minutes, sessions: bodies)
        if await store.perform({ let _: GroupDirectLineupResponse = try await store.repository.createDirectLineup(groupID: detail.group.id, body: payload) }) {
            CommonPlacesManager.shared.savePlaceIfNeeded(place); dismiss()
        } else { error = store.error }
    }
}
