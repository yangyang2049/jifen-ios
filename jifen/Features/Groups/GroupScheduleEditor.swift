import SwiftUI

struct GroupActivityLineupEditor: View {
    var detail: GroupDetailCache; var activity: GroupActivity; var initial: GroupActivityLineup
    var usesParentNavigation = false
    var body: some View { GroupScheduleEditor(detail: detail, activity: activity, lineup: initial, usesParentNavigation: usesParentNavigation) }
}

struct GroupScheduleEditor: View {
    var detail: GroupDetailCache
    var plan: GroupTrainingPlan? = nil
    var activity: GroupActivity? = nil
    var lineup: GroupActivityLineup? = nil
    var usesParentNavigation = false
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
    @State private var expandedID: UUID?
    @State private var shiftPreview: [GroupTrainingDraftSession]?
    @State private var latestPlan: GroupTrainingPlan?
    @State private var latestLineup: GroupActivityLineup?
    private var currentPlan: GroupTrainingPlan? { latestPlan ?? plan }
    private var currentLineup: GroupActivityLineup? { latestLineup ?? lineup }
    /// 直接排赛活动的候选人取自全部在组成员（对齐安卓 `allowed`：direct 用活跃成员、报名活动用已报名成员）。
    private var members: [GroupMember] { (store.cache.details[detail.group.id] ?? detail).members.filter { $0.status == "active" && (activity == nil || activity!.isDirect || activity!.registeredMemberIds.contains($0.id)) } }
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
    private var canSave: Bool {
        issue == nil && GroupTrainingValidation.validText(place: place, note: note) && !busy
            && (activity == nil || store.allows("update_activity"))
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
                arrangementControls
                Divider()
                GroupActivityLineupHeading(count: sessions.count)
                if activity?.isDirect == true { GroupRosterAddButton(groupID: detail.group.id) }
                ForEach($sessions) { $session in sessionCard($session) }
                if sessions.isEmpty {
                    GroupNotice(text: groupText("no_sessions", "No matches arranged yet."))
                        .accessibilityIdentifier("group_schedule_empty")
                }
                Button {
                    var next = GroupTrainingDraftSession()
                    next.startsAt = (sessions.last?.startsAt ?? activity?.date ?? date).addingTimeInterval(Double(minutes) * 60)
                    if let activity { next.format = activity.format }
                    sessions.append(next); expandedID = next.id
                } label: { Label(groupText("add_session", "Add a session"), systemImage: "plus") }
                    .buttonStyle(GroupAlignedActionStyle(secondary: true)).disabled(sessions.count >= limit)
                if let issue { GroupNotice(text: issue) }
                if !otherConflicts.isEmpty {
                    GroupActivitySurface {
                        ForEach(otherConflicts) { row in
                            VStack(alignment: .leading, spacing: Theme.xs) {
                                Text(row.date, format: .dateTime); Text(row.court)
                                Text(row.seats.map { seat in seat.displayName ?? detail.members.first(where: { $0.id == seat.memberId })?.displayName ?? groupText("former_member", "Former member") }.joined(separator: " / "))
                                    .font(.caption)
                            }
                        }
                    }
                }
                if let error = error ?? store.error { GroupNotice(text: error) }
            }.padding(Theme.padding).frame(maxWidth: Theme.focusedContentMaxWidth).frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor).disabled(busy).scrollDismissesKeyboard(.interactively)
        .navigationTitle(groupText(activity == nil ? "training_schedule" : "activity_lineup", "Match schedule"))
        .navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
        .navigationBarBackButtonHidden(usesParentNavigation)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if usesParentNavigation { Button { requestClose() } label: { Image(systemName: "chevron.left") }.disabled(busy) }
                else { ModalCloseButton { requestClose() }.disabled(busy) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GroupAlignedFooter {
                Button(activity != nil || plan != nil ? NSLocalizedString("save", value: "Save", comment: "") : groupText("publish_schedule", "Publish schedule")) {
                    Task { await submit() }
                }.buttonStyle(GroupAlignedActionStyle()).disabled(!canSave)
                    .accessibilityIdentifier("group_training_publish")
            }
        }
        .interactiveDismissDisabled(busy)
        .groupAlert(groupText("shift_following", "Shift this and following matches"), isPresented: Binding(get: { shiftPreview != nil }, set: { if !$0 { shiftPreview = nil } }), presenting: shiftPreview) { rows in
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) { shiftPreview = nil }
            Button(groupText("apply_shift", "Apply changes")) { sessions = rows; shiftPreview = nil }
        } message: { rows in
            Text(rows.enumerated().map { index, row in "\(index + 1). " + row.startsAt.formatted(date: .numeric, time: .shortened) + (row.court.isEmpty ? "" : " · " + row.court) }.joined(separator: "\n"))
        }
        .task { initialize() }
    }
    @ViewBuilder private var arrangementControls: some View {
        if activity == nil {
            GroupActivityDateField(title: groupText("training_date", "Training date"), selection: Binding(get: { date }, set: { new in
                let offset = Calendar.current.startOfDay(for: new).timeIntervalSince(Calendar.current.startOfDay(for: date))
                date = new
                for i in sessions.indices where sessions[i].frozen != true { sessions[i].startsAt = sessions[i].startsAt.addingTimeInterval(offset) }
            }), components: .date).accessibilityIdentifier("group_schedule_date")
            GroupAlignedField(groupText("place", "Location")) {
                TextField("", text: $place).groupAlignedInput().disabled(venueLocked)
            }
            GroupAlignedField(groupText("note", "Note")) {
                TextField("", text: $note, axis: .vertical).lineLimit(3...5).groupAlignedInput(minHeight: GroupFieldSize.note, alignment: .topLeading, font: GroupTypography.body)
            }
        } else if let activity {
            Text(activity.title).font(.system(size: Theme.fontBody1, weight: .medium))
            Text(activity.date.formatted(date: .abbreviated, time: .omitted) + (activity.place.isEmpty ? "" : " · " + activity.place))
                .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
            GroupActivityChoices(selection: $timingMode, values: ["sequence", "estimated"], title: {
                groupText($0 == "sequence" ? "activity_timing_sequence" : "activity_timing_estimated", $0 == "sequence" ? "No set time" : "Set an estimated time")
            }).disabled(sessions.contains { $0.frozen == true }).accessibilityIdentifier("group_schedule_timing")
        }
        if activity == nil || timingMode == "estimated" {
            GroupAlignedField(groupText("activity_lineup_duration", "Match duration")) {
                if activity == nil {
                    Stepper(groupText("session_minutes", "Minutes per match") + ": \(minutes)", value: $minutes, in: 5...240, step: 5)
                        .disabled(sessions.contains { $0.frozen == true })
                } else {
                    GroupActivityChoices(selection: $minutes, values: GroupActivityPolicy.durationOptions(current: minutes), title: {
                        String(format: groupText("activity_lineup_minutes", "%d min"), $0)
                    }).disabled(sessions.contains { $0.frozen == true }).accessibilityIdentifier("group_schedule_duration")
                }
            }
        }
        if venueLocked {
            Label(groupText("place", "Location"), systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }
    private func sessionCard(_ session: Binding<GroupTrainingDraftSession>) -> some View {
        let row = session.wrappedValue
        let index = sessions.firstIndex { $0.id == row.id } ?? 0
        let frozen = row.frozen == true
        let expanded = expandedID == row.id
        let snapshot = currentLineup?.sessions.first { $0.id == row.serverID }?.seats
            ?? currentPlan?.sessions.first { $0.id == row.serverID }?.seats ?? []
        return VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(spacing: Theme.sm) {
                Button { expandedID = expanded ? nil : row.id } label: {
                    HStack(spacing: Theme.sm) {
                        Text(String(format: groupText("activity_lineup_session", "Match %d"), index + 1)).font(.system(size: Theme.fontBody1, weight: .semibold))
                        if frozen { Image(systemName: "lock.fill").font(.system(size: Theme.fontCaption)) }
                        Spacer(minLength: 0)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: Theme.fontCaption))
                    }.foregroundStyle(Theme.textPrimary).frame(minHeight: 40)
                }.buttonStyle(.plain).accessibilityIdentifier("group_schedule_session_\(index + 1)")
                if !frozen && (sessions.count > 1 || activity != nil) {
                    Button(role: .destructive) { sessions.removeAll { $0.id == row.id } } label: {
                        Image(systemName: "xmark").frame(width: 40, height: 40)
                    }.buttonStyle(.plain).accessibilityLabel(groupText("remove_session", "Remove session"))
                        .accessibilityIdentifier("group_schedule_remove_" + (row.serverID ?? row.id.uuidString))
                }
            }
            if expanded {
                HStack(spacing: Theme.sm) {
                    if sequenced {
                        Text(groupText(index == 0 ? "activity_time_unspecified" : "activity_time_after_previous", index == 0 ? "Time TBD" : "After previous match"))
                            .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        GroupActivityDateField(selection: session.startsAt, compact: true, initiallySelectsTime: true)
                            .disabled(frozen).accessibilityIdentifier("group_schedule_starts_" + (row.serverID ?? row.id.uuidString))
                    }
                    TextField(groupText("court", "Court"), text: session.court).groupAlignedInput(minHeight: 44).disabled(frozen)
                }
                if activity == nil {
                    GroupActivityChoices(selection: session.format, values: GroupFormat.allCases, title: { $0.title }).disabled(frozen)
                }
                GroupInlineMatchRoster(format: row.format, ids: session.memberIDs, members: members, frozen: frozen,
                    frozenSeats: snapshot, showSeatLabels: false, prominentText: true)
                if !frozen && !sequenced {
                    Button(groupText("shift_following", "Shift this and following matches")) {
                        shiftPreview = GroupTrainingValidation.shifted(sessions, from: row.id, minutes: minutes)
                    }.font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.primary)
                        .accessibilityIdentifier("group_schedule_shift_" + (row.serverID ?? row.id.uuidString))
                }
            } else {
                Text((sequenced ? groupText(index == 0 ? "activity_time_unspecified" : "activity_time_after_previous", index == 0 ? "Time TBD" : "After previous match") : row.startsAt.formatted(date: .abbreviated, time: .shortened)) + (row.court.isEmpty ? "" : " · " + row.court))
                    .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
                Text(row.selectedIDs.map { id in snapshot.first(where: { $0.memberId == id })?.displayName ?? members.first(where: { $0.id == id })?.displayName ?? groupText("former_member", "Former member") }.joined(separator: " / "))
                    .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.padding).padding(.vertical, Theme.sm)
        .background(GroupEditorColors.control, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider.opacity(0.45), lineWidth: 1))
    }
    private func requestClose() { guard !busy else { return }; dismiss() }
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
        initialized = true; expandedID = sessions.first?.id
    }
    private func bodyForSession(_ row: GroupTrainingDraftSession) -> GroupTrainingSessionBody {
        row.body(orderNo: (sessions.firstIndex(where: { $0.id == row.id }) ?? 0) + 1)
    }
    private func submit() async {
        guard GroupTrainingValidation.validText(place: place, note: note) else { return }
        guard issue == nil, !busy, activity == nil || store.allows("update_activity") else { return }; busy = true; defer { busy = false }
        let bodies = sessions.map(bodyForSession)
        if await store.perform({
            if let activity {
                let _: GroupActivityLineup = try await store.repository.write("/\(detail.group.id)/activities/\(activity.id)/lineup", body: GroupLineupBody(timingMode: timingMode, sessionMinutes: minutes, sessions: bodies), method: .put)
            } else if let plan = currentPlan {
                let patch = GroupSchedulePatch(trainingDate: Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970 * 1000), place: place, note: note, sessionMinutes: changedSessions || minutes != plan.sessionMinutes ? minutes : nil, sessions: changedSessions ? bodies : nil)
                let _: GroupTrainingPlan = try await store.repository.write("/\(detail.group.id)/training-plans/\(plan.id)", body: patch, method: .patch)
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
