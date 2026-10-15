import SwiftUI

struct GroupActivityLineupEditor: View {
    var detail: GroupDetailCache; var activity: GroupActivity; var initial: GroupActivityLineup
    var body: some View { GroupScheduleEditor(detail: detail, activity: activity, lineup: initial) }
}

struct GroupScheduleEditor: View {
    var detail: GroupDetailCache
    var plan: GroupTrainingPlan? = nil
    var activity: GroupActivity? = nil
    var lineup: GroupActivityLineup? = nil
    @State private var store = GroupStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [GroupTrainingDraftSession] = []
    @State private var minutes = 30
    @State private var timingMode = "estimated"
    @State private var place = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var revision: Int64?
    @State private var key = UUID().uuidString
    @State private var busy = false
    @State private var initialized = false
    @State private var error: String?
    @State private var preview = false
    @State private var shiftPreview: [GroupTrainingDraftSession]?
    @State private var reloadConfirmation = false
    @State private var latestPlan: GroupTrainingPlan?
    @State private var latestLineup: GroupActivityLineup?
    @State private var conflictPlan: GroupTrainingPlan?
    @State private var conflictLineup: GroupActivityLineup?
    private var currentPlan: GroupTrainingPlan? { latestPlan ?? plan }
    private var currentLineup: GroupActivityLineup? { latestLineup ?? lineup }
    /// 直接排赛活动的候选人取自全部在组成员（对齐安卓 `allowed`：direct 用活跃成员、报名活动用已报名成员）。
    private var members: [GroupMember] { detail.members.filter { $0.status == "active" && (activity == nil || activity!.isDirect || activity!.registeredMemberIds.contains($0.id)) } }
    private var limit: Int { activity == nil ? store.capabilities?.trainingSessionMax ?? 12 : store.capabilities?.activitySessionMax ?? 12 }
    /// 排赛时间模式：`sequence` 不设具体时间（按顺序）、`estimated` 预计时间（对齐安卓 `timingMode`）。
    private var sequenced: Bool { activity != nil && timingMode == "sequence" }
    private var venueLocked: Bool { currentPlan?.placeLocked ?? sessions.contains { $0.frozen == true } }
    private var changedSessions: Bool { sessions.map(bodyForSession) != initialBodies }
    private var initialBodies: [GroupTrainingSessionBody] {
        if let plan = currentPlan { return plan.sessions.map { .init(orderNo: $0.orderNo, court: $0.court, startsAt: $0.startsAt, format: $0.format, seats: $0.seats.map { .init(memberId: $0.memberId, side: $0.side, seat: $0.seat) }, id: $0.id) } }
        return (currentLineup?.sessions ?? []).map { .init(orderNo: $0.orderNo, court: $0.court, startsAt: $0.startsAt, format: $0.format, seats: $0.seats.map { .init(memberId: $0.memberId, side: $0.side, seat: $0.seat) }, id: $0.id) }
    }
    private var otherConflicts: [GroupTrainingSession] {
        guard activity == nil else { return [] }
        return GroupTrainingValidation.otherPlanConflicts(sessions, minutes: minutes, place: place, plans: store.cache.details[detail.group.id]?.trainingPlans ?? detail.trainingPlans ?? [], excluding: plan?.id)
    }
    private var issue: String? {
        if !changedSessions && currentPlan?.sessionMinutes == minutes { return nil }
        if let lineup = currentLineup, lineup.sessions.contains(where: \.frozen),
           (minutes != lineup.sessionMinutes || timingMode != (lineup.timingMode ?? "estimated")) {
            return groupText("frozen_match_hint", "This match has already started and cannot be changed.")
        }
        if !otherConflicts.isEmpty { return groupText("lineup_conflict", "Overlapping matches need different courts and participants.") }
        return GroupTrainingValidation.lineupIssue(sessions, minutes: minutes, maximumSessions: limit,
            maximumPerMember: (activity == nil ? store.capabilities?.trainingMemberSessionMax : store.capabilities?.activityMemberSessionMax) ?? 8,
            skipsConflicts: sequenced, allowsEmpty: activity != nil, originals: currentLineup?.sessions ?? [],
            allowedMemberIDs: activity == nil ? nil : Set(members.map(\.id)))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if activity == nil {
                        DatePicker(groupText("training_date", "Training date"), selection: Binding(get: { date }, set: { new in
                            let offset = Calendar.current.startOfDay(for: new).timeIntervalSince(Calendar.current.startOfDay(for: date))
                            date = new
                            for i in sessions.indices where sessions[i].frozen != true { sessions[i].startsAt = sessions[i].startsAt.addingTimeInterval(offset) }
                        }), displayedComponents: .date).accessibilityIdentifier("group_schedule_date")
                        TextField(groupText("place", "Location"), text: $place).disabled(venueLocked)
                        TextField(groupText("note", "Note"), text: $note, axis: .vertical)
                    }
                    if activity != nil {
                        Picker(groupText("activity_timing", "Timing"), selection: $timingMode) {
                            Text(groupText("activity_timing_sequence", "No set time")).tag("sequence")
                            Text(groupText("activity_timing_estimated", "Set an estimated time")).tag("estimated")
                        }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("group_schedule_timing")
                            // 安卓 setTimingMode：有已冻结（已开赛 / 已有结果）的场次时不许改时间模式。
                            .disabled(sessions.contains { $0.frozen == true })
                    }
                    if activity == nil || timingMode == "estimated" {
                        if activity == nil {
                            Stepper(groupText("session_minutes", "Minutes per match") + ": \(minutes)", value: $minutes, in: 5...240, step: 5).disabled(sessions.contains { $0.frozen == true })
                        } else {
                            Picker(groupText("activity_lineup_duration", "Match duration"), selection: $minutes) {
                                ForEach(GroupActivityPolicy.durationOptions(current: minutes), id: \.self) { amount in
                                    Text(String(format: groupText("activity_lineup_minutes", "%d min"), amount)).tag(amount)
                                }
                            }.pickerStyle(.segmented).disabled(sessions.contains { $0.frozen == true })
                                .accessibilityIdentifier("group_schedule_duration")
                        }
                    }
                    if venueLocked { Label(groupText("place", "Location"), systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                }
                ForEach($sessions) { $session in
                    Section {
                        if sequenced {
                            LabeledContent(groupText("starts_at", "Start time"), value: groupText((sessions.firstIndex { $0.id == session.id } ?? 0) == 0 ? "activity_time_unspecified" : "activity_time_after_previous", (sessions.firstIndex { $0.id == session.id } ?? 0) == 0 ? "Time TBD" : "After previous match"))
                        } else {
                            DatePicker(groupText("starts_at", "Start time"), selection: $session.startsAt).accessibilityIdentifier("group_schedule_starts_" + (session.serverID ?? session.id.uuidString))
                        }
                        TextField(groupText("court", "Court"), text: $session.court)
                        Picker(groupText("format", "Format"), selection: $session.format) { ForEach(GroupFormat.allCases) { Text($0.title).tag($0) } }
                        ForEach([0, 1], id: \.self) { side in
                            ForEach(0..<session.format.seatsPerSide, id: \.self) { seat in
                                GroupSeatPicker(title: "\(side == 0 ? "A" : "B")\(seat + 1)", selectedID: $session.memberIDs[side * 2 + seat], members: members, excluded: Set(session.selectedIDs), frozen: session.frozen == true, frozenName: detail.members.first(where: { $0.id == session.memberIDs[side * 2 + seat] })?.displayName)
                            }
                        }
                        Button(groupText("shift_following", "Shift this and following matches")) { shiftPreview = GroupTrainingValidation.shifted(sessions, from: session.id, minutes: minutes) }.accessibilityIdentifier("group_schedule_shift_" + (session.serverID ?? session.id.uuidString))
                        if sessions.count > 1 || activity != nil { Button(groupText("remove_session", "Remove session"), role: .destructive) { sessions.removeAll { $0.id == session.id } }.accessibilityIdentifier("group_schedule_remove_" + (session.serverID ?? session.id.uuidString)) }
                    }.disabled(session.frozen == true)
                }
                Button { var next = GroupTrainingDraftSession(); next.startsAt = (sessions.last?.startsAt ?? activity?.date ?? date).addingTimeInterval(Double(minutes) * 60); sessions.append(next) } label: { Label(groupText("add_session", "Add a session"), systemImage: "plus") }.disabled(sessions.count >= limit)
                if let issue { GroupNotice(text: issue) }
                if !otherConflicts.isEmpty { Section(groupText("preview_schedule", "Review schedule")) {
                    ForEach(otherConflicts) { row in VStack(alignment: .leading) {
                        Text(row.date, format: .dateTime); Text(row.court)
                        Text(row.seats.map { seat in seat.displayName ?? detail.members.first(where: { $0.id == seat.memberId })?.displayName ?? groupText("former_member", "Former member") }.joined(separator: " / ")).font(.caption)
                    } }
                } }
                if let error = error ?? store.error { GroupNotice(text: error) }
                if error != nil, plan != nil || activity != nil { Button(groupText("reload_version", "Load latest version")) { reloadConfirmation = true } }
                if conflictPlan != nil || conflictLineup != nil {
                    Section(groupText("server_version", "Latest version")) {
                        if let remote = conflictPlan { Text(remote.place); Text(remote.note); ForEach(remote.sessions) { row in Text(row.date, format: .dateTime); Text(row.court) } }
                        if let remote = conflictLineup { ForEach(remote.sessions) { row in Text(row.date, format: .dateTime); Text(row.court) } }
                        Button(groupText("reload_version", "Load latest version")) { acceptLatest() }
                        Button(groupText("keep_draft", "Keep my edits")) { latestPlan = conflictPlan; latestLineup = conflictLineup; revision = conflictPlan?.revision ?? conflictLineup?.revision; conflictPlan = nil; conflictLineup = nil; error = nil; store.error = nil }.disabled(!canKeepDraft)
                    }
                }
                Button(groupText("preview_schedule", "Review schedule")) { preview = true }.disabled(issue != nil || note.unicodeScalars.count > 200 || busy || conflictPlan != nil || conflictLineup != nil || (activity != nil && !store.allows("update_activity")))
                    .accessibilityIdentifier("group_training_publish")
            }.disabled(busy).navigationTitle(groupText(activity == nil ? "training_schedule" : "activity_lineup", "Match schedule")).groupAccountBoundary()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .confirmationDialog(groupText("reload_version", "Load latest version"), isPresented: $reloadConfirmation) {
                    Button(groupText("reload_version", "Load latest version")) { Task { await reloadLatest() } }
                }
                .sheet(isPresented: Binding(get: { shiftPreview != nil }, set: { if !$0 { shiftPreview = nil } })) {
                    NavigationStack { List {
                        ForEach(shiftPreview ?? []) { row in VStack(alignment: .leading) { Text(row.startsAt, format: .dateTime); Text(row.court) } }
                        Button(groupText("save", "Save")) { if let rows = shiftPreview { sessions = rows }; shiftPreview = nil }
                    }.navigationTitle(groupText("shift_following", "Shift this and following matches"))
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { shiftPreview = nil } } }
                    }
                }
                .task { initialize() }
                .navigationDestination(isPresented: $preview) {
                    List {
                        Text(place); Text(note)
                        if sessions.isEmpty { GroupNotice(text: groupText("no_sessions", "No matches arranged yet.")).accessibilityIdentifier("group_schedule_empty_preview") }
                        ForEach(sessions) { row in VStack(alignment: .leading) { Text(row.startsAt, format: .dateTime); Text(row.court); Text(row.selectedIDs.map { id in id.isEmpty ? groupText("choose_member", "Choose a member") : detail.members.first(where: { $0.id == id })?.displayName ?? groupText("former_member", "Former member") }.joined(separator: " / ")) } }
                        if let error { GroupNotice(text: error) }
                        if error != nil, plan != nil || activity != nil { Button(groupText("reload_version", "Load latest version")) { preview = false; reloadConfirmation = true } }
                        Button(activity != nil || plan != nil ? groupText("save", "Save") : groupText("publish_schedule", "Publish schedule")) { Task { await submit() } }.disabled(busy).accessibilityIdentifier("group_schedule_confirm")
                    }.disabled(busy).navigationTitle(groupText("preview_schedule", "Review schedule")).navigationBarBackButtonHidden(busy)
                }
        }
    }
    private func initialize() {
        guard !initialized else { return }
        let plan = currentPlan, lineup = currentLineup
        minutes = plan?.sessionMinutes ?? lineup?.sessionMinutes ?? (activity == nil ? 45 : 30); place = plan?.place ?? activity?.place ?? ""; note = plan?.note ?? ""
        revision = plan?.revision ?? lineup?.revision
        timingMode = lineup?.timingMode == "sequence" ? "sequence" : "estimated"
        let bodies = initialBodies
        sessions = bodies.enumerated().map { index, body in
            var row = GroupTrainingDraftSession(startsAt: Date(timeIntervalSince1970: Double(body.startsAt) / 1000), court: body.court, format: body.format)
            row.serverID = body.id
            row.frozen = plan.map { !$0.sessions[index].resultId.isEmpty || !($0.sessions[index].startedGameId ?? "").isEmpty || $0.sessions[index].status != "scheduled" } ?? lineup?.sessions[index].frozen
            for seat in body.seats where (0..<2).contains(seat.seat) { row.memberIDs[(seat.side == "A" ? 0 : 2) + seat.seat] = seat.memberId }
            return row
        }
        date = Date(timeIntervalSince1970: Double(plan?.trainingDate ?? Int64((sessions.first?.startsAt ?? activity?.date ?? Date()).timeIntervalSince1970 * 1000)) / 1000)
        if sessions.isEmpty && activity == nil { var first = GroupTrainingDraftSession(); first.startsAt = Date().addingTimeInterval(3600); sessions = [first] }
        initialized = true
    }
    private func bodyForSession(_ row: GroupTrainingDraftSession) -> GroupTrainingSessionBody {
        row.body(orderNo: (sessions.firstIndex(where: { $0.id == row.id }) ?? 0) + 1)
    }
    private func reloadLatest() async {
        guard let account = store.accountID else { return }
        busy = true; defer { busy = false }
        let identity = store.identityRevision
        do {
            if let activity { let value: GroupActivityLineup = try await store.repository.read("/\(detail.group.id)/activities/\(activity.id)/lineup"); guard store.matchesIdentity(account, revision: identity) else { return }; conflictLineup = value }
            else if let plan { let value: GroupTrainingPlan = try await store.repository.read("/\(detail.group.id)/training-plans/\(plan.id)"); guard store.matchesIdentity(account, revision: identity) else { return }; conflictPlan = value }
        } catch { if store.matchesIdentity(account, revision: identity) { self.error = groupErrorMessage(error) } }
    }
    private var canKeepDraft: Bool {
        let remote = (conflictPlan?.sessions.map { row in (row.id, row.startsAt, row.court, row.format, row.seats, !row.resultId.isEmpty || !(row.startedGameId ?? "").isEmpty || row.status != "scheduled") })
            ?? (conflictLineup?.sessions.map { ($0.id, $0.startsAt, $0.court, $0.format, $0.seats, $0.frozen) } ?? [])
        let serverIDs = Set(remote.map { $0.0 })
        guard sessions.compactMap(\.serverID).allSatisfy(serverIDs.contains) else { return false }
        if remote.contains(where: { $0.5 }), minutes != (conflictPlan?.sessionMinutes ?? conflictLineup?.sessionMinutes) { return false }
        if conflictPlan?.placeLocked == true, place != conflictPlan?.place { return false }
        return remote.filter { $0.5 }.allSatisfy { row in
            guard let local = sessions.first(where: { $0.serverID == row.0 }) else { return false }
            return Int64(local.startsAt.timeIntervalSince1970 * 1000) == row.1 && local.court == row.2 && local.format == row.3 && local.selectedIDs == row.4.sorted { ($0.side, $0.seat) < ($1.side, $1.seat) }.map(\.memberId)
        }
    }
    private func acceptLatest() {
        latestPlan = conflictPlan; latestLineup = conflictLineup; conflictPlan = nil; conflictLineup = nil
        initialized = false; initialize(); error = nil; store.error = nil
    }
    private func submit() async {
        guard issue == nil, !busy, activity == nil || store.allows("update_activity") else { return }; busy = true; defer { busy = false }
        let bodies = sessions.map(bodyForSession)
        if await store.perform({
            if let activity {
                let _: GroupActivityLineup = try await store.repository.write("/\(detail.group.id)/activities/\(activity.id)/lineup", body: GroupLineupBody(timingMode: timingMode, sessionMinutes: minutes, sessions: bodies), method: .put, revision: revision)
            } else if let plan = currentPlan {
                let patch = GroupSchedulePatch(trainingDate: Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970 * 1000), place: place, note: note, sessionMinutes: changedSessions || minutes != plan.sessionMinutes ? minutes : nil, sessions: changedSessions ? bodies : nil)
                let _: GroupTrainingPlan = try await store.repository.write("/\(detail.group.id)/training-plans/\(plan.id)", body: patch, method: .patch, revision: revision)
            } else {
                let body = GroupTrainingPlanBody(trainingDate: Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970 * 1000), sessionMinutes: minutes, place: place, note: note, sessions: bodies)
                let _: GroupTrainingPlan = try await store.repository.write("/\(detail.group.id)/training-plans", body: body, key: key)
            }
        }) { dismiss() }
        else { error = store.error }
    }
}

nonisolated struct GroupSchedulePatch: Encodable, Sendable {
    var trainingDate: Int64; var place: String; var note: String; var sessionMinutes: Int?; var sessions: [GroupTrainingSessionBody]?
}
