import SwiftUI

struct GroupTrainingTab: View {
    var detail: GroupDetailCache
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var onReload: () async -> Void
    @State private var store = GroupStore.shared
    @State private var editor: GroupTrainingEditDestination?
    @State private var action: GroupTrainingAction?
    @State private var cancelPlan: GroupTrainingPlan?
    @State private var localError: String?
    private var me: GroupMember? { detail.members.first { $0.accountId == store.accountID } }
    private var coach: Bool { GroupPermissions.coach(detail.group, member: me) }
    private var writable: Bool { detail.group.isActive && store.enabled && !store.cached }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                GroupSectionTitle(title: groupText("notices", "Notifications"), count: (detail.trainingNotices ?? []).filter { $0.seenAt == nil }.count)
                NavigationLink { GroupTrainingNoticeInbox(groupID: detail.group.id) } label: {
                    Label(groupText("notices", "Notifications"), systemImage: "bell").font(.caption)
                }.accessibilityIdentifier("group_training_notices")
            }
            GroupTrainingNoticesView(detail: detail, onReload: onReload, showsTitle: false)
            if let localError { GroupNotice(text: localError) }
            if coach {
                let notices = (detail.leaveNotices ?? []).sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
                if !notices.isEmpty {
                    GroupSectionTitle(title: groupText("leave_notices", "Student leave notices"), count: notices.filter { $0.status == "open" && $0.invalidated != true }.count)
                    ForEach(notices.filter { $0.status == "open" && $0.invalidated != true }) { notice in leaveNotice(notice, canMarkSeen: true) }
                    let history = notices.filter { $0.status == "seen" || $0.invalidated == true }
                    if !history.isEmpty { DisclosureGroup(groupText("read_notices", "Read notifications")) { ForEach(history) { notice in leaveNotice(notice, canMarkSeen: false) } } }
                }
            }
            HStack {
                GroupSectionTitle(title: groupText("training_schedule", "Training schedule"))
                if coach {
                    Button { editor = .init(plan: nil) } label: {
                        Label(groupText("add_session", "Add a session"), systemImage: "plus").font(.caption)
                    }.buttonStyle(.bordered).tint(Theme.cardBackground).foregroundStyle(Theme.primary)
                        .background(Theme.cardBackground, in: Capsule())
                        .disabled(!writable).accessibilityIdentifier("group_training_add")
                }
            }
            if (detail.trainingPlans ?? []).isEmpty { GroupEmptyCard(text: groupText("no_training", "No training scheduled yet")) }
            ForEach(visiblePlans) { plan in
                GroupSurface {
                    HStack {
                        Image(systemName: "calendar")
                        Text(Date(timeIntervalSince1970: Double(plan.trainingDate) / 1000), format: .dateTime.month().day())
                        Spacer()
                        if coach && plan.status != "cancelled" {
                            Menu {
                                Button(groupText("edit_schedule", "Edit schedule")) { editor = .init(plan: plan) }
                                Button(groupText("cancel_schedule", "Cancel schedule"), role: .destructive) { cancelPlan = plan }
                            } label: { Image(systemName: "ellipsis") }.disabled(!writable).accessibilityIdentifier("group_training_plan_menu_\(plan.id)")
                        }
                    }
                    if !plan.place.isEmpty { Label(plan.place, systemImage: "mappin.and.ellipse").font(GroupTypography.body).foregroundStyle(.secondary) }
                    if !plan.note.isEmpty { Text(plan.note).font(.caption).foregroundStyle(.secondary) }
                    if coach { ShareLink(item: plan.sessions.map { $0.date.formatted() + " · " + $0.court + " · " + $0.seats.map { $0.displayName ?? "" }.joined(separator: " / ") }.joined(separator: "\n")) { Label(groupText("share", "Share schedule"), systemImage: "square.and.arrow.up") } }
                    if plan.status == "cancelled" { Text(groupText("cancelled", "Cancelled")).foregroundStyle(.secondary) }
                    ForEach(plan.sessions.filter { coach || $0.seats.contains { $0.memberId == me?.id } }) { session in
                        Divider()
                        sessionRow(session, plan: plan)
                    }
                }
            }
        }
        .sheet(item: $editor, onDismiss: { Task { await onReload() } }) { destination in GroupTrainingEditor(detail: detail, initial: destination.plan) }
        .sheet(item: $action, onDismiss: { Task { await onReload() } }) { destination in
            if destination.kind == "leave" { GroupLeaveView(groupID: detail.group.id, session: destination.session) }
            else { GroupMatchEditor(detail: detail, trainingSession: destination.session, manual: destination.kind == "manual", onStart: onStart) }
        }
        .sheet(item: $cancelPlan, onDismiss: { Task { await onReload() } }) { GroupTrainingCancelView(groupID: detail.group.id, plan: $0) }

    }

    private var visiblePlans: [GroupTrainingPlan] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return (detail.trainingPlans ?? []).filter { coach || $0.sessions.contains { $0.seats.contains { $0.memberId == me?.id } } }.sorted { a, b in
            let activeA = a.status != "cancelled" && a.endsAt >= now, activeB = b.status != "cancelled" && b.endsAt >= now
            if activeA != activeB { return activeA }
            return activeA ? a.startsAt < b.startsAt : a.startsAt > b.startsAt
        }
    }
    private func leaveNotice(_ notice: GroupLeaveNotice, canMarkSeen: Bool) -> some View {
        GroupSurface {
            HStack {
                let member = detail.members.first { $0.id == notice.memberId }
                GroupAvatar(name: notice.displayName ?? member?.displayName ?? "", url: member?.avatarUrl)
                VStack(alignment: .leading, spacing: 5) {
                    Text(notice.displayName ?? member?.displayName ?? groupText("former_member", "Former member"))
                    if let starts = notice.sessionStartsAt, starts > 0 { Text(Date(timeIntervalSince1970: Double(starts) / 1000), format: .dateTime).font(.caption) }
                    if let court = notice.court { Text(court).font(.caption) }
                    Text(notice.reason).font(.caption).foregroundStyle(.secondary)
                    if notice.invalidated == true { Label(groupText("cancelled", "Cancelled"), systemImage: "clock.badge.xmark").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if canMarkSeen { Button(groupText("mark_seen", "Read")) {
                    Task { if await store.perform({ try await store.repository.action("/\(detail.group.id)/leave-notices/\(notice.id)/seen") }) { await onReload() } }
                }.buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary).controlSize(.small).disabled(!writable) }
            }
        }
    }

    private func sessionRow(_ session: GroupTrainingSession, plan: GroupTrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("\(session.orderNo)").font(GroupTypography.section).foregroundStyle(Theme.primary); Text(session.date, format: .dateTime.hour().minute()); Text(session.court); Spacer(); Text(session.format.title).font(.caption).foregroundStyle(.secondary) }
            Text(session.seats.sorted { ($0.side, $0.seat) < ($1.side, $1.seat) }.map { seat in seat.displayName ?? detail.members.first(where: { $0.id == seat.memberId })?.displayName ?? "" }.joined(separator: " / ")).font(GroupTypography.body)
            if !session.resultId.isEmpty {
                if let result = detail.results.first(where: { $0.id == session.resultId }) { GroupResultLink(result: result) }
                else { Text(groupText("completed", "Completed")).font(.caption).foregroundStyle(.secondary) }
            } else if (session.status == "scheduled" && plan.status != "cancelled") || !(session.startedGameId ?? "").isEmpty {
                HStack {
                    if coach {
                        Button(groupText((session.startedGameId ?? "").isEmpty ? "start_score" : "resume_score", "Start scoring")) { Task { await start(session) } }.buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary)
                        if (session.startedGameId ?? "").isEmpty { Button(groupText("manual_result_action", "Add Result")) { action = .init(kind: "manual", session: session) }.buttonStyle(.bordered).tint(Theme.textSecondary).foregroundStyle(Theme.primary) }
                    } else if session.seats.contains(where: { $0.memberId == me?.id }) {
                        Button(groupText("leave_training", "Notify absence")) { action = .init(kind: "leave", session: session) }.buttonStyle(.bordered).tint(Theme.textSecondary).foregroundStyle(Theme.primary)
                        if let leave = detail.leaveNotices?.first(where: { $0.sessionId == session.id && $0.memberId == me?.id && $0.invalidated != true }) { Text(leave.reason); Text(GroupStatusText.leaveNotice(leave.status)).font(.caption).foregroundStyle(.secondary) }
                    }
                }.controlSize(.small).disabled(!writable)
            } else { Text(GroupStatusText.trainingSession(session.status)).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func start(_ session: GroupTrainingSession) async {
        if let game = session.startedGameId, !game.isEmpty, let account = store.accountID {
            do { let id = try await GroupGameOperations.resumeID(gameID: game, groupID: detail.group.id, accountID: account); onStart(detail.group.sport.gameType, SportsSetupResult(team1Name: "", team2Name: ""), id) }
            catch { localError = groupErrorMessage(error) }
        } else { action = .init(kind: "score", session: session) }
    }

}

struct GroupTrainingEditDestination: Identifiable { var id = UUID(); var plan: GroupTrainingPlan? }
struct GroupTrainingAction: Identifiable { var id = UUID(); var kind: String; var session: GroupTrainingSession }

nonisolated struct GroupTrainingDraftSession: Identifiable, Equatable, Codable, Sendable {
    var id = UUID(); var startsAt = Date().addingTimeInterval(3600); var court = ""
    var format = GroupFormat.singles; var memberIDs = ["", "", "", ""]
    var serverID: String? = nil; var frozen: Bool? = nil
    var selectedIDs: [String] { guard memberIDs.count == 4 else { return [] }; return format == .singles ? [memberIDs[0], memberIDs[2]] : memberIDs }
}

nonisolated enum GroupTrainingValidation {
    static func validText(place: String, note: String) -> Bool {
        place.utf16.count <= 80 && note.utf16.count <= 200
    }

    enum LineupIssue: Equatable { case incomplete, duplicate, sessions, memberLimit, conflict, invalid, frozen }
    static func lineupIssue(_ sessions: [GroupTrainingDraftSession], minutes: Int, maximumSessions: Int = 12, maximumPerMember: Int = 8,
                            skipsConflicts: Bool = false, allowsEmpty: Bool = false,
                            originals: [GroupActivitySession] = [], allowedMemberIDs: Set<String>? = nil) -> String? {
        switch lineupProblem(sessions, minutes: minutes, maximumSessions: maximumSessions, maximumPerMember: maximumPerMember,
                             skipsConflicts: skipsConflicts, allowsEmpty: allowsEmpty, originals: originals, allowedMemberIDs: allowedMemberIDs) {
        case nil: return nil
        case .incomplete: return groupText("activity_lineup_incomplete", "Select all players for this match")
        case .duplicate: return groupText("activity_lineup_duplicate", "Each player can appear only once in this match")
        case .sessions: return "≤ " + String(format: groupText("activity_lineup_match_count", "%d matches"), maximumSessions)
        case .memberLimit: return groupText("lineup_member_limit", "A member can play at most eight matches per schedule.") + " (≤ \(maximumPerMember))"
        case .conflict: return groupText("lineup_conflict", "Overlapping matches need different courts and participants.")
        case .invalid: return groupText("lineup_invalid", "Check the match times and participants.")
        case .frozen: return groupText("frozen_match_hint", "This match has already started and cannot be changed.")
        }
    }
    static func lineupProblem(_ sessions: [GroupTrainingDraftSession], minutes: Int, maximumSessions: Int = 12, maximumPerMember: Int = 8,
                              skipsConflicts: Bool = false, allowsEmpty: Bool = false,
                              originals: [GroupActivitySession] = [], allowedMemberIDs: Set<String>? = nil) -> LineupIssue? {
        for original in originals where original.frozen {
            guard let index = sessions.firstIndex(where: { $0.serverID == original.id }),
                  sessions[index].matches(original, orderNo: index + 1) else { return .frozen }
        }
        guard !sessions.isEmpty else { return allowsEmpty ? nil : .incomplete }
        guard sessions.count <= maximumSessions else { return .sessions }
        let duration = Double(minutes < 5 ? 30 : min(minutes, 240)) * 60
        var countByMember: [String: Int] = [:]
        for (index, session) in sessions.enumerated() {
            let unchangedMissing = originals.contains { $0.needsLineup == true && session.matches($0, orderNo: index + 1) }
            if session.frozen != true && !unchangedMissing &&
                (session.selectedIDs.count != session.format.seatsPerSide * 2 || session.selectedIDs.contains(where: { $0.isEmpty || allowedMemberIDs?.contains($0) == false })) { return .incomplete }
            let selected = session.selectedIDs.filter { !$0.isEmpty }
            if Set(selected).count != selected.count { return .duplicate }
            if session.court.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 16 || !session.startsAt.timeIntervalSince1970.isFinite || (!skipsConflicts && index > 0 && session.startsAt < sessions[index - 1].startsAt) { return .invalid }
            for id in selected { countByMember[id, default: 0] += 1 }
        }
        if countByMember.values.contains(where: { $0 > maximumPerMember }) { return .memberLimit }
        // 顺序模式（time-unspecified）没有具体开赛时间，安卓同样跳过重叠冲突校验。
        guard !skipsConflicts else { return nil }
        for i in sessions.indices {
            for j in sessions.indices where j > i {
                let a = sessions[i], b = sessions[j]
                if originals.contains(where: { $0.status == "cancelled" && ($0.id == a.serverID || $0.id == b.serverID) }) { continue }
                guard a.startsAt < b.startsAt.addingTimeInterval(duration), b.startsAt < a.startsAt.addingTimeInterval(duration) else { continue }
                let courtA = a.court.trimmingCharacters(in: .whitespacesAndNewlines)
                let courtB = b.court.trimmingCharacters(in: .whitespacesAndNewlines)
                if courtA.isEmpty || courtB.isEmpty || courtA == courtB || !Set(a.selectedIDs.filter { !$0.isEmpty }).isDisjoint(with: Set(b.selectedIDs.filter { !$0.isEmpty })) {
                    return .conflict
                }
            }
        }
        return nil
    }
    static func validSeats(_ ids: [String], format: GroupFormat) -> Bool {
        ids.count == format.seatsPerSide * 2 && ids.allSatisfy { !$0.isEmpty } && Set(ids).count == ids.count
    }

    /// 改活动日期时把所有场次整体平移（安卓 `setDirectDate` 的 delta 平移），保留场间间隔。
    static func shiftAll(_ sessions: [GroupTrainingDraftSession], by delta: TimeInterval) -> [GroupTrainingDraftSession] {
        guard delta.isFinite, delta != 0 else { return sessions }
        return sessions.map { row in var next = row; next.startsAt = row.startsAt.addingTimeInterval(delta); return next }
    }
    /// 过去的开始时刻推到「一分钟后」，并把同一位移应用到所有场次，
    /// 使活动开始时间与场次时间同源（安卓 `directActivityAnchor` + save 内的 shift）。
    static func anchored(_ sessions: [GroupTrainingDraftSession], startsAt: Date, now: Date) -> (startsAt: Date, sessions: [GroupTrainingDraftSession]) {
        let anchor = startsAt <= now ? now.addingTimeInterval(60) : startsAt
        return (anchor, shiftAll(sessions, by: anchor.timeIntervalSince(startsAt)))
    }
    static func shifted(_ sessions: [GroupTrainingDraftSession], from id: UUID, minutes: Int) -> [GroupTrainingDraftSession] {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return sessions }
        var shifted = sessions
        for i in (index + 1)..<shifted.count where shifted[i].frozen != true {
            shifted[i].startsAt = shifted[i - 1].startsAt.addingTimeInterval(Double(minutes) * 60)
        }
        return shifted
    }

    static func otherPlanConflicts(_ sessions: [GroupTrainingDraftSession], minutes: Int, place: String, plans: [GroupTrainingPlan], excluding planID: String?) -> [GroupTrainingSession] {
        let duration = Double(minutes) * 60
        return plans.filter { $0.id != planID }.flatMap { plan in
            plan.sessions.filter { other in
                guard other.status == "scheduled", plan.status != "cancelled" || !(other.startedGameId ?? "").isEmpty else { return false }
                let start = Date(timeIntervalSince1970: Double(other.startsAt) / 1000), end = Date(timeIntervalSince1970: Double(other.endsAt) / 1000)
                return sessions.filter { $0.frozen != true }.contains { own in
                    guard own.startsAt < end, start < own.startsAt.addingTimeInterval(duration) else { return false }
                    let ownPlace = place.trimmingCharacters(in: .whitespacesAndNewlines), otherPlace = plan.place.trimmingCharacters(in: .whitespacesAndNewlines)
                    let ownCourt = own.court.trimmingCharacters(in: .whitespacesAndNewlines), otherCourt = other.court.trimmingCharacters(in: .whitespacesAndNewlines)
                    let samePlace = ownPlace.isEmpty || otherPlace.isEmpty || ownPlace == otherPlace
                    let sameCourt = samePlace && (ownCourt.isEmpty || otherCourt.isEmpty || ownCourt == otherCourt)
                    return sameCourt || !Set(own.selectedIDs).isDisjoint(with: Set(other.seats.map(\.memberId)))
                }
            }
        }
    }
}

struct GroupTrainingEditor: View {
    var detail: GroupDetailCache
    var initial: GroupTrainingPlan?
    var body: some View { GroupScheduleEditor(detail: detail, plan: initial) }
}

struct GroupLeaveView: View {
    var groupID: String
    var session: GroupTrainingSession
    @State private var reason = ""
    @State private var busy = false
    @State private var store = GroupStore.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text(session.date, format: .dateTime)
                TextField(groupText("leave_reason", "Optional absence note"), text: $reason, axis: .vertical)
                    .onChange(of: reason) { _, value in reason = GroupInputValidation.limitedText(value, maximum: GroupInputValidation.absenceReasonMax) }
                if let error = store.error { GroupNotice(text: error) }
                Button(groupText("leave_training", "Notify absence")) { Task { busy = true; defer { busy = false }; if await store.perform({ try await store.repository.action("/\(groupID)/training-sessions/\(session.id)/leave", body: .init(reason: reason)) }) { dismiss() } } }.disabled(busy)
            }.expandedPhonePageContent(existingHorizontalInset: 20).disabled(busy).navigationTitle(groupText("leave_training", "Notify absence")).groupAccountBoundary().interactiveDismissDisabled(busy)
                .onAppear { let store = GroupStore.shared; if let member = store.cache.details[groupID]?.members.first(where: { $0.accountId == store.accountID }), let existing = store.cache.details[groupID]?.leaveNotices?.first(where: { $0.sessionId == session.id && $0.memberId == member.id }) { reason = existing.reason } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { ModalCloseButton { dismiss() }.disabled(busy) } }
        }
    }
}

struct GroupReportView: View {
    var groupID: String
    var body: some View { GroupEvidenceReportSheet(groupID: groupID) }
}
