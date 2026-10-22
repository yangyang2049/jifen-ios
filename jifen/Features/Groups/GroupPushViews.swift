import SwiftUI

struct GroupPushSettingsView: View {
    var groupID: String? = nil
    @State private var preferences: GroupPushPreferences?
    @State private var error: String?
    @State private var busy = false
    @State private var store = GroupStore.shared
    var body: some View {
        List {
            if let preferences {
                Toggle(groupText("push_enabled", "Group notifications"), isOn: Binding(get: { preferences.enabled }, set: { update(enabled: $0) }))
                    .disabled(busy)
                if let groupID, let setting = preferences.groups.first(where: { $0.groupId == groupID }) {
                    Toggle(groupText("push_group_enabled", "Receive notifications for this group"), isOn: Binding(get: { setting.enabled }, set: { update(group: .init(groupId: groupID, enabled: $0)) }))
                        .disabled(busy || !preferences.enabled)
                }
                Text(groupText("push_inbox_kept", "Turning these off keeps your in-app notifications and existing activity reminders.")).font(GroupTypography.body).foregroundStyle(.secondary)
            } else if error == nil { ProgressView() }
            Button(groupText("push_permission", "Enable system notifications")) {
                Task { do { try await GroupPushManager.shared.requestPermission() } catch { self.error = error.localizedDescription } }
            }
            if let error { Text(error).foregroundStyle(.secondary); Button(groupText("retry", "Retry")) { Task { await load() } } }
        }.expandedPhonePageContent(existingHorizontalInset: Theme.padding).background(Theme.backgroundColor).navigationTitle(groupText("push_settings", "Notification settings")).groupAccountBoundary()
            .task(id: store.identityRevision) { await load() }
    }
    private func load() async {
        guard AppFeatureFlags.groupRemotePushEnabled else { return }
        let account = store.accountID, revision = store.identityRevision
        do {
            let result: GroupPushPreferences = try await APIClient.shared.request("/api/push/preferences", requiresAuth: true)
            guard store.accountID == account, store.identityRevision == revision else { return }
            preferences = result; error = nil
        } catch { if store.accountID == account, store.identityRevision == revision { self.error = error.localizedDescription } }
    }
    private func update(enabled: Bool? = nil, group: GroupPushPreferences.GroupSetting? = nil) {
        struct Patch: Encodable, Sendable { let enabled: Bool?; let groups: [GroupPushPreferences.GroupSetting]? }
        let account = store.accountID, revision = store.identityRevision
        busy = true
        Task {
            defer { busy = false }
            do {
                let result: GroupPushPreferences = try await APIClient.shared.request("/api/push/preferences", method: .patch, body: Patch(enabled: enabled, groups: group.map { [$0] }), requiresAuth: true)
                guard store.accountID == account, store.identityRevision == revision else { return }
                preferences = result; error = nil
            } catch { if store.accountID == account, store.identityRevision == revision { self.error = error.localizedDescription } }
        }
    }
}

struct GroupPushDestinationView: View {
    let destination: GroupPushDestination
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var manager = GroupPushManager.shared
    @State private var store = GroupStore.shared
    @State private var message: GroupPushMessage?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if !SessionStore.shared.isAuthenticated { AccountLoginSheet(dismissOnAuthentication: false) }
                else if !manager.matches(destination) { Text(groupText("session_changed", "Sign in to the account that received this reminder.")) }
                else if let message { GroupNoticeDestinationView(notice: message.notice, onStart: onStart, targetOverride: message.target == "message" ? .message : nil).task { await markSeen(message) } }
                else if let error { VStack { Text(error); Button(groupText("retry", "Retry")) { Task { await load() } } } }
                else { ProgressView() }
            }.groupAdaptiveOrientation()
        }.onChange(of: store.identityRevision) { _, _ in message = nil; error = nil }
        .task(id: "\(store.identityRevision):\(manager.accountID ?? "")") { await load() }
    }
    private func load() async {
        guard manager.matches(destination), SessionStore.shared.isAuthenticated else { return }
        let revision = store.identityRevision
        do {
            let result: GroupPushMessage = try await APIClient.shared.request("/api/push/messages/\(destination.messageID)", requiresAuth: true)
            guard store.identityRevision == revision, manager.matches(destination) else { return }
            message = result; error = nil
        } catch { if store.identityRevision == revision, manager.matches(destination) { self.error = error.localizedDescription } }
    }
    private func markSeen(_ message: GroupPushMessage) async {
        guard manager.matches(destination) else { return }
        if message.sourceType == "group" { await store.markNoticeSeen(message.notice) }
        else if message.sourceType == "training" {
            let _: GroupTrainingNotice? = try? await store.repository.write("/\(message.groupId)/training-notices/\(message.sourceId)/seen")
        } else if message.sourceType == "leave" {
            let _: GroupLeaveNotice? = try? await store.repository.write("/\(message.groupId)/leave-notices/\(message.sourceId)/seen")
        }
    }
}
