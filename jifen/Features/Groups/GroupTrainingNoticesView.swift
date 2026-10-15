import SwiftUI
import PersistenceCore

nonisolated enum GroupGameOperations {
    @MainActor static func resumeID(gameID: String, groupID: String, accountID: String) async throws -> String {
        let store = GroupStore.shared, revision = GroupStore.shared.identityRevision
        guard store.accountID == accountID else { throw GroupFlowError.staleSession }
        let game: GroupGameSnapshot = try await store.repository.read("/\(groupID)/games/\(gameID)")
        guard store.matchesIdentity(accountID, revision: revision), game.gameId == gameID, game.groupId == groupID, game.state == "started" else { throw GroupFlowError.gameUnavailable }
        let rows = try await ResumeSessionRepository().liveEntries()
        guard let row = rows.first(where: { row in let context = GroupLocalPersistence.shared.context(sessionID: row.sessionId.uuidString); return context?.accountID == accountID && context?.groupID == groupID && context?.gameID == gameID }) else { throw GroupFlowError.gameUnavailable }
        guard store.matchesIdentity(accountID, revision: revision) else { throw GroupFlowError.staleSession }; return row.sessionId.uuidString
    }
}

struct GroupTrainingNoticesView: View {
    var detail: GroupDetailCache
    var onReload: () async -> Void
    var showsTitle = true
    @State private var store = GroupStore.shared
    @State private var busy = Set<String>()
    var body: some View {
        let notices = (detail.trainingNotices ?? []).sorted { ($0.seenAt == nil ? 0 : 1, -$0.createdAt) < ($1.seenAt == nil ? 0 : 1, -$1.createdAt) }
        if !notices.isEmpty {
            if showsTitle { GroupSectionTitle(title: groupText("notices", "Notifications"), count: notices.filter { $0.seenAt == nil }.count) }
            ForEach(notices.filter { $0.seenAt == nil }) { row in notice(row) }
            let read = notices.filter { $0.seenAt != nil }
            if !read.isEmpty { DisclosureGroup(groupText("read_notices", "Read notifications")) { ForEach(read) { row in notice(row) } } }
        }
    }
    private func notice(_ row: GroupTrainingNotice) -> some View {
        GroupSurface {
            Text(groupText(row.kind, row.kind)).font(.headline)
            Text(Date(timeIntervalSince1970: Double(row.startsAt) / 1000), format: .dateTime)
            Text(row.place); if !row.note.isEmpty { Text(row.note) }; if !row.reason.isEmpty { Text(row.reason) }
            if row.seenAt == nil { Button(groupText("mark_seen", "Read")) {
                Task {
                    busy.insert(row.id); defer { busy.remove(row.id) }
                    if await store.perform({ let _: GroupTrainingNotice = try await store.repository.write("/\(detail.group.id)/training-notices/\(row.id)/seen") }) { await onReload() }
                }
            }.disabled(busy.contains(row.id) || store.cached) }
        }
    }
}

struct GroupTrainingNoticeInbox: View {
    let groupID: String
    @State private var store = GroupStore.shared
    var body: some View {
        List {
            if let detail = store.cache.details[groupID] {
                if let error = store.detailErrors[groupID] { GroupNotice(text: error) }
                if store.cached { GroupNotice(text: groupText("cached", "Showing saved data. Connect to refresh.")) }
                if (detail.trainingNotices ?? []).isEmpty {
                    Text(groupText("no_notices", "No notifications yet")).accessibilityIdentifier("group_training_notices_empty")
                } else { GroupTrainingNoticesView(detail: detail, onReload: reload, showsTitle: false) }
            } else if let error = store.detailErrors[groupID] {
                GroupEmptyCard(text: error, actionTitle: groupText("retry", "Retry")) { Task { await reload() } }
            } else { ProgressView() }
        }.navigationTitle(groupText("notices", "Notifications")).groupAccountBoundary()
            .accessibilityIdentifier("group_training_notice_inbox")
            .task { await reload() }.refreshable { await reload() }
    }
    private func reload() async { await store.loadDetail(groupID) }
}

struct GroupTrainingCancelView: View {
    var groupID: String; var plan: GroupTrainingPlan
    @State private var store = GroupStore.shared
    @State private var reason = ""
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField(groupText("cancel_reason", "Reason for cancelling"), text: $reason, axis: .vertical)
                GroupNotice(text: groupText("cancel_training_hint", "Completed matches stay in history. Matches already being scored can still be finished."))
                if let error = store.error { GroupNotice(text: error) }
                Button(groupText("cancel_schedule", "Cancel schedule"), role: .destructive) {
                    Task { busy = true; defer { busy = false }; if await store.perform({ let _: GroupTrainingPlan = try await store.repository.write("/\(groupID)/training-plans/\(plan.id)/cancel", body: GroupActionBody(reason: reason), revision: plan.revision) }) { dismiss() } }
                }.disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.unicodeScalars.count > 200)
            }.disabled(busy).navigationTitle(groupText("cancel_schedule", "Cancel schedule")).groupAccountBoundary().interactiveDismissDisabled(busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() }.disabled(busy) } }
        }
    }
}
