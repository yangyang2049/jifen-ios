import SwiftUI

struct GroupMemberSelector: View {
    var title: String
    @Binding var selectedID: String
    var members: [GroupMember]
    var excluded: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        List {
            Button(groupText("clear_seat", "Clear this seat")) { selectedID = ""; dismiss() }
            ForEach(members.filter { $0.status == "active" && (!excluded.contains($0.id) || $0.id == selectedID) && (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)) }) { member in
                Button { selectedID = member.id; dismiss() } label: {
                    HStack { GroupAvatar(name: member.displayName, url: member.avatarUrl); Text(member.displayName); Spacer(); if member.id == selectedID { Image(systemName: "checkmark") } }
                }.foregroundStyle(.primary).accessibilityIdentifier("group_member_pick_" + member.id)
            }
        }.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always)).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct GroupSeatPicker: View {
    var title: String
    @Binding var selectedID: String
    var members: [GroupMember]
    var excluded: Set<String> = []
    var frozen = false
    var frozenName: String? = nil
    var body: some View {
        if frozen {
            LabeledContent(title, value: frozenName ?? members.first(where: { $0.id == selectedID })?.displayName ?? groupText("former_member", "Former member"))
                .accessibilityElement(children: .combine).accessibilityIdentifier("group_seat_" + title)
                .accessibilityLabel(title).accessibilityValue(frozenName ?? members.first(where: { $0.id == selectedID })?.displayName ?? groupText("former_member", "Former member"))
        }
        else {
            NavigationLink { GroupMemberSelector(title: title, selectedID: $selectedID, members: members, excluded: excluded) } label: {
                LabeledContent(title, value: members.first(where: { $0.id == selectedID })?.displayName ?? groupText("choose_member", "Choose a member"))
            }.accessibilityIdentifier("group_seat_" + title)
        }
    }
}

struct GroupRulesEditor: View {
    @Binding var rules: GroupMatchRules
    var capability: GroupSportCapability?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if let options = capability?.ruleOptions {
                    Picker(groupText("completion_mode", "Match completion"), selection: $rules.matchCompletionMode) { ForEach(options.matchCompletionModes ?? ["best_of"], id: \.self) { Text(groupText($0, $0)).tag($0) } }
                    if capability?.supportsCustomRules == true { Stepper(groupText("max_sets", "Games per match") + ": \(rules.maxSets)", value: $rules.maxSets, in: 1...99) }
                    else { Picker(groupText("max_sets", "Games per match"), selection: $rules.maxSets) { ForEach(options.maxSets ?? [rules.maxSets], id: \.self) { Text("\($0)").tag($0) } } }
                    if rules.sport == .tennis {
                        Picker(groupText("tennis_scoring", "Set scoring"), selection: $rules.setScoringMode) { ForEach(options.setScoringModes ?? ["regular"], id: \.self) { Text(groupText($0, $0)).tag($0) } }
                        Picker(groupText("games_per_set", "Games per set"), selection: $rules.gamesPerSet) { ForEach(options.gamesPerSet ?? [6], id: \.self) { Text("\($0)").tag($0) } }
                        Picker(groupText("tie_break", "Tie-break points"), selection: $rules.tieBreakPoints) { ForEach(options.tieBreakPoints ?? [7], id: \.self) { Text("\($0)").tag($0) } }
                        Toggle(groupText("no_ad", "No-ad scoring"), isOn: $rules.usesNoAdScoring).disabled(Set(options.usesNoAdScoring ?? []).count < 2)
                    } else {
                        if capability?.supportsCustomRules == true { Stepper(groupText("target_points", "Points to win") + ": \(rules.pointsToWinSet)", value: $rules.pointsToWinSet, in: 1...999) }
                        else { Picker(groupText("target_points", "Points to win"), selection: $rules.pointsToWinSet) { ForEach(options.pointsToWinSet ?? [rules.pointsToWinSet], id: \.self) { Text("\($0)").tag($0) } } }
                        Toggle(groupText("win_by_two", "Win by two"), isOn: $rules.winByTwo).disabled(Set(options.winByTwo ?? []).count < 2)
                        Toggle(groupText("rally_scoring", "Rally scoring"), isOn: $rules.useRallyScoring).disabled(Set(options.useRallyScoring ?? []).count < 2)
                        if capability?.supportsCustomRules == true {
                        Toggle(groupText("point_cap", "Maximum score"), isOn: Binding(get: { rules.pointCap != nil }, set: { rules.pointCap = $0 ? max(rules.pointsToWinSet, rules.pointCap ?? rules.pointsToWinSet) : nil }))
                        if rules.pointCap != nil { Stepper("\(rules.pointCap ?? 0)", value: Binding(get: { rules.pointCap ?? rules.pointsToWinSet }, set: { rules.pointCap = $0 }), in: rules.pointsToWinSet...9999) }
                        }
                    }
                    if !rules.isValid { GroupNotice(text: groupText("invalid_rules", "Please check the match rules.")) }
                    if let defaults = capability?.defaultRules { Button(groupText("default_rules", "Restore default rules")) { rules = defaults } }
                } else { GroupNotice(text: groupText("capabilities_missing", "Match rules are unavailable. Connect and retry.")) }
            }.disabled(capability?.supportsCustomRules == false).navigationTitle(groupText("match_rules", "Match rules"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(groupText("save", "Done")) { dismiss() }.disabled(!rules.isValid || capability == nil) } }
        }
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

/// Global notice inbox: one row per notice, explicit read receipts, and an "open group" step that
/// acknowledges the notice first. Pagination keeps every loaded page instead of replacing them.
struct GroupNoticeInbox: View {
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared
    @State private var opened: GroupNotification?
    @State private var busy = Set<String>()
    var body: some View {
        List {
            if let error = store.noticeError {
                Section {
                    GroupNotice(text: error)
                    Button(groupText("retry", "Retry")) { Task { await store.loadNotices(more: store.notices.isEmpty ? false : store.hasMoreNotices) } }.disabled(store.noticesLoading)
                }.accessibilityIdentifier("group_notices_error")
            }
            if store.notices.isEmpty, !store.noticesLoading, store.noticeError == nil {
                Text(groupText("no_notices", "No notifications yet")).accessibilityIdentifier("group_notices_empty")
            }
            ForEach(store.notices) { notice in
                noticeRow(notice).accessibilityIdentifier("group_notice_" + notice.id)
            }
            if store.noticesLoading {
                HStack { ProgressView() }.frame(maxWidth: .infinity).accessibilityIdentifier("group_notices_loading")
            } else if store.hasMoreNotices {
                Button(groupText("load_more", "Load more")) { Task { await store.loadNotices(more: true) } }.frame(maxWidth: .infinity).buttonStyle(.borderless)
            } else if !store.notices.isEmpty, store.noticeError == nil {
                Text(groupText("notice_end", "No more notifications")).font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("group_notices_end")
            }
        }
        .navigationTitle(groupText("notices", "Notifications")).groupAccountBoundary()
        .accessibilityIdentifier("group_notice_inbox")
        .task { await store.loadNotices() }.refreshable { await store.loadNotices() }
        .navigationDestination(item: $opened) { notice in
            GroupNoticeDestinationView(notice: notice, onStart: onStart).task { await store.markNoticeSeen(notice) }
        }
    }
    private func noticeRow(_ notice: GroupNotification) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(notice.groupName + " · " + notice.label).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if notice.seenAt == nil { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(Theme.primary) }
            }
            if !notice.title.isEmpty { Text(notice.title) }
            if let reason = notice.reason, !reason.isEmpty {
                Text(notice.kind == "role_changed" ? groupText(reason, reason) : reason).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            Text(Date(timeIntervalSince1970: Double(notice.createdAt) / 1000), format: .dateTime).font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 16) {
                if notice.seenAt == nil {
                    Button(groupText("notice_seen", "Mark as read")) {
                        Task { busy.insert(notice.id); defer { busy.remove(notice.id) }; await store.markNoticeSeen(notice) }
                    }.disabled(busy.contains(notice.id)).accessibilityIdentifier("group_notice_seen_" + notice.id)
                } else {
                    Text(groupText("read_notices", "Read")).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if notice.opensGroup {
                    Button(groupText("notice_open", "Open group")) {
                        if notice.seenAt == nil { Task { await store.markNoticeSeen(notice) } }
                        opened = notice
                    }.accessibilityIdentifier("group_notice_open_" + notice.id)
                }
            }.buttonStyle(.borderless)
        }
    }
}

struct GroupNoticeDestinationView: View {
    var notice: GroupNotification
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared
    @State private var activity: GroupActivity?
    var body: some View {
        Group {
            if notice.kind.hasPrefix("result"), let resource = notice.resourceId { GroupRemoteResultView(groupID: notice.groupId, resultID: resource) }
            else if let activity, let detail = store.cache.details[notice.groupId] { GroupActivityView(detail: detail, activity: activity, onStart: onStart) }
            else { GroupDetailView(groupID: notice.groupId, onStart: onStart, initialTab: notice.kind.hasPrefix("training") ? 1 : 0) }
        }.task {
            await store.loadDetail(notice.groupId)
            guard notice.kind.hasPrefix("activity"), let resource = notice.resourceId, let account = store.accountID else { return }
            let revision = store.identityRevision
            let loaded: GroupActivity? = try? await store.repository.read("/\(notice.groupId)/activities/\(resource)")
            if store.matchesIdentity(account, revision: revision) { activity = loaded }
        }
    }
}

struct GroupReminderDestinationView: View {
    var destination: GroupReminderDestination
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared
    @State private var activity: GroupActivity?
    @State private var login = false
    var body: some View {
        NavigationStack {
            Group {
                if SessionStore.shared.user?.id == destination.accountID, let detail = store.cache.details[destination.groupID], let activity { GroupActivityView(detail: detail, activity: activity, onStart: onStart) }
                else if !SessionStore.shared.isAuthenticated { Button(groupText("need_login", "Please sign in to continue.")) { login = true } }
                else if let error = store.error { GroupNotice(text: error) }
                else if store.accountID != destination.accountID { GroupNotice(text: groupText("session_changed", "Sign in to the account that received this reminder.")) }
                else { ProgressView() }
            }.navigationTitle(groupText("activities", "Activities"))
                .task(id: SessionStore.shared.user?.id) {
                    guard SessionStore.shared.user?.id == destination.accountID else { return }
                    await store.refresh(); await store.loadDetail(destination.groupID)
                    let revision = store.identityRevision
                    let loaded: GroupActivity? = try? await store.repository.read("/\(destination.groupID)/activities/\(destination.activityID)")
                    if store.matchesIdentity(destination.accountID, revision: revision) { activity = loaded; if loaded == nil { store.error = groupText("unavailable", "This activity is unavailable.") } }
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
    @Environment(\.dismiss) private var dismiss
    init(upload: GroupPendingUpload) { self.upload = upload; _draft = State(initialValue: upload.body) }
    var body: some View {
        NavigationStack {
            Form {
                Section(groupText("participants", "Participants")) {
                    if upload.body.gameId == nil {
                        Picker(groupText("format", "Format"), selection: $draft.format) { ForEach(GroupFormat.allCases) { Text($0.title).tag($0) } }
                        ForEach(["A", "B"], id: \.self) { side in
                            ForEach(0..<draft.format.seatsPerSide, id: \.self) { seat in
                                GroupSeatPicker(title: "\(side)\(seat + 1)", selectedID: Binding(get: { draft.participants.first { $0.side == side && $0.seat == seat }?.memberId ?? "" }, set: { id in
                                    draft.participants.removeAll { $0.side == side && $0.seat == seat }
                                    if !id.isEmpty { draft.participants.append(.init(memberId: id, side: side, seat: seat)) }
                                }), members: GroupStore.shared.cache.details[upload.groupID]?.members.filter { $0.status == "active" } ?? [], excluded: Set(draft.participants.map(\.memberId)))
                            }
                        }
                    } else { ForEach(Array(draft.participants.enumerated()), id: \.offset) { _, seat in Text("\(seat.side)\(seat.seat + 1) · \(seat.displayName ?? seat.memberId)") } }
                }
                if upload.body.gameId == nil {
                    Button(groupText("match_rules", "Match rules")) { rulesEditor = true }
                }
                Section(groupText("overall_score", "Overall set score")) {
                    TextField("A", value: $draft.setScore.a, format: .number).keyboardType(.numberPad)
                    TextField("B", value: $draft.setScore.b, format: .number).keyboardType(.numberPad)
                    DatePicker(groupText("played_at", "Played at"), selection: Binding(get: { Date(timeIntervalSince1970: Double(draft.playedAt) / 1000) }, set: { draft.playedAt = Int64($0.timeIntervalSince1970 * 1000) }), in: ...Date())
                    Toggle(groupText("set_details", "Set details"), isOn: Binding(get: { draft.sets != nil }, set: { draft.sets = $0 ? [] : nil }))
                    if draft.sets != nil { GroupSetDetailsEditor(sets: Binding(get: { draft.sets ?? [] }, set: { draft.sets = $0 }), maximum: draft.rules.maxSets) }
                }
                if let error { GroupNotice(text: error) }
                Button(groupText("save", "Save")) {
                    do {
                        // 与赛果录入页一致：明细为空数组时按总分校验，不把「展开了明细」当错误。
                        guard configurationLoaded, draft.rules.validResult(draft.setScore, sets: GroupInputValidation.scoredDetails(includesSets: draft.sets != nil, sets: draft.sets ?? [])) else { throw GroupFormError.invalidResult }
                        guard GroupTrainingValidation.validSeats(draft.participants.map(\.memberId), format: draft.format) else { throw GroupFormError.invalidResult }
                        draft.bestOf = draft.rules.maxSets
                        try GroupStore.shared.queuedResult(draft, groupID: upload.groupID, id: upload.id, key: upload.key); dismiss()
                    } catch { self.error = groupErrorMessage(error) }
                }.disabled(busy || !configurationLoaded || GroupStore.shared.accountID != upload.accountID)
                if !configurationLoaded, error != nil { Button(groupText("retry", "Retry")) { Task { await loadConfiguration() } }.disabled(busy) }
            }.navigationTitle(groupText("repair_upload", "Correct result")).groupAccountBoundary()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() } } }
                .task { await loadConfiguration() }
                .onChange(of: draft.format) { _, value in if upload.body.gameId == nil { draft.participants.removeAll { $0.seat >= value.seatsPerSide } } }
                .sheet(isPresented: $rulesEditor) { GroupRulesEditor(rules: $draft.rules, capability: GroupStore.shared.capabilities?.sport(draft.rules.sport)) }
        }
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
