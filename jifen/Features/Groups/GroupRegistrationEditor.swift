import SwiftUI

/// A delta against confirmed registrations. Unmanaged account members are preserved.
nonisolated struct GroupRegistrationPlan: Sendable {
    struct Change: Equatable, Sendable { var memberID: String; var registered: Bool }
    var baseline: Set<String>
    var desired: Set<String>
    var managedIDs: Set<String>
    var capacity: Int
    var projectedCount: Int { baseline.subtracting(managedIDs).count + desired.intersection(managedIDs).count }
    var changes: [Change] {
        let removals = baseline.intersection(managedIDs).subtracting(desired).sorted().map { Change(memberID: $0, registered: false) }
        let additions = desired.intersection(managedIDs).subtracting(baseline).sorted().map { Change(memberID: $0, registered: true) }
        return removals + additions
    }
    @MainActor func apply(authorize: () throws -> Void, write: (Change) async throws -> Void, confirmed: (Change) -> Void) async throws {
        guard projectedCount <= capacity else { throw GroupRegistrationFailure.full }
        for change in changes {
            try authorize()
            try await write(change)
            try authorize()
            confirmed(change)
        }
    }
}

nonisolated enum GroupRegistrationFailure: LocalizedError {
    case full
    var errorDescription: String? { groupText("unavailable", "This activity is unavailable.") }
}

/// Manager edits are kept local until the final Save. Each confirmed write advances the baseline.
struct GroupRegistrationEditor: View {
    let detail: GroupDetailCache
    let activity: GroupActivity
    var onReload: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var baseline = Set<String>()
    @State private var desired = Set<String>()
    @State private var remoteActivity: GroupActivity?
    @State private var remoteGroup: ScoreGroup?
    @State private var remoteMembers: [GroupMember]?
    @State private var presentedAccountID: String?
    @State private var presentedIdentityRevision = 0
    @State private var baselineRevision: Int64 = 0
    @State private var busy = false
    @State private var initialized = false
    @State private var preview = false
    @State private var discardConfirmation = false
    @State private var error: String?

    private var current: GroupActivity { remoteActivity ?? activity }
    private var group: ScoreGroup { remoteGroup ?? store.cache.details[detail.group.id]?.group ?? detail.group }
    private var members: [GroupMember] { remoteMembers ?? store.cache.details[detail.group.id]?.members ?? detail.members }
    private var me: GroupMember? { members.first { $0.accountId == presentedAccountID && $0.status == "active" } }
    private var temporaryMembers: [GroupMember] { members.filter { $0.kind == "temporary" && $0.status == "active" } }
    private var managedIDs: Set<String> { Set(temporaryMembers.map(\.id)) }
    private var plan: GroupRegistrationPlan { .init(baseline: baseline, desired: desired, managedIDs: managedIDs, capacity: current.capacity) }
    private var dirty: Bool { !plan.changes.isEmpty }
    private var writable: Bool {
        guard let account = presentedAccountID else { return false }
        return store.matchesIdentity(account, revision: presentedIdentityRevision)
            && SessionStore.shared.user?.id == account && store.allows("register_activity") && !store.cached
            && group.isActive && GroupPermissions.manager(me) && current.registrationOpen(at: Int64(Date().timeIntervalSince1970 * 1000))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(current.title)
                    Text("\(plan.projectedCount)/\(current.capacity)")
                    Text(groupText("temporary_members", "Temporary members")).font(.caption).foregroundStyle(.secondary)
                }
                Section(groupText("temporary_members", "Temporary members")) {
                    if temporaryMembers.isEmpty { Text(groupText("activity_registration_empty", "No temporary members")) }
                    ForEach(temporaryMembers) { member in
                        Toggle(isOn: Binding(get: { desired.contains(member.id) }, set: { checked in
                            guard writable, !busy, checked == false || plan.projectedCount < current.capacity else { return }
                            if checked { desired.insert(member.id) } else { desired.remove(member.id) }
                            error = nil
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.displayName)
                                if desired.contains(member.id) != baseline.contains(member.id) {
                                    Text((desired.contains(member.id) ? "+ " : "− ") + groupText(desired.contains(member.id) ? "register" : "unregister", "Registration"))
                                        .font(.caption).foregroundStyle(Theme.primary)
                                }
                            }
                        }.disabled(!writable || busy || (!desired.contains(member.id) && plan.projectedCount >= current.capacity))
                            .tint(Theme.primary).accessibilityIdentifier("group_registration_member_" + member.id)
                    }
                }
                if let error { GroupNotice(text: error); Button(groupText("reload_version", "Load latest version")) { Task { await reloadBaseline(keepingChanges: true) } }.disabled(busy) }
                Button(groupText("save", "Confirm")) { preview = true }
                    .disabled(!writable || !dirty || busy || plan.projectedCount > current.capacity)
                    .accessibilityIdentifier("group_registration_preview")
            }.navigationTitle(groupText("registered_members", "Registered members")).groupAccountBoundary()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { requestClose() }.disabled(busy).accessibilityIdentifier("group_registration_close") } }
                .confirmationDialog(groupText("keep_draft", "Keep my edits"), isPresented: $discardConfirmation, titleVisibility: .visible) {
                    Button(NSLocalizedString("unfinished_discard_button", value: "Discard", comment: ""), role: .destructive) { dismiss() }
                        .accessibilityIdentifier("group_registration_discard")
                    Button(groupText("keep_draft", "Keep my edits"), role: .cancel) { }
                } message: {
                    Text(plan.changes.map { change in (change.registered ? "+ " : "− ") + (members.first { $0.id == change.memberID }?.displayName ?? "") }.joined(separator: "\n"))
                }
                .navigationDestination(isPresented: $preview) {
                    List {
                        ForEach([false, true], id: \.self) { registered in
                            Section(groupText(registered ? "register" : "unregister", "Registration")) {
                                ForEach(plan.changes.filter { $0.registered == registered }, id: \.memberID) { change in Text(members.first { $0.id == change.memberID }?.displayName ?? "") }
                            }
                        }
                        Text("\(plan.projectedCount)/\(current.capacity)")
                        if let error { GroupNotice(text: error) }
                        Button(NSLocalizedString("save", value: "Save", comment: "")) { Task { await submit() } }
                            .disabled(!writable || busy || !dirty || plan.projectedCount > current.capacity)
                            .accessibilityIdentifier("group_registration_save")
                    }.navigationTitle(groupText("registered_members", "Registered members")).navigationBarBackButtonHidden(busy)
                }
                .onChange(of: store.identityRevision) { _, _ in dismiss() }
                .task {
                    guard !initialized else { return }; initialized = true
                    presentedAccountID = store.accountID; presentedIdentityRevision = store.identityRevision
                    baseline = Set(activity.registeredMemberIds); desired = baseline; baselineRevision = activity.revision
                    await reloadBaseline(keepingChanges: false)
                }
        }.interactiveDismissDisabled(dirty || busy)
    }

    private func requestClose() { if dirty { discardConfirmation = true } else { dismiss() } }
    private func authorize(_ account: String) throws {
        guard store.matchesIdentity(account, revision: presentedIdentityRevision), presentedAccountID == account,
              SessionStore.shared.user?.id == account, writable else { throw GroupFlowError.staleSession }
    }
    private func reloadBaseline(keepingChanges: Bool) async {
        guard let account = presentedAccountID else { return }
        let savedChanges = keepingChanges ? plan.changes : []
        busy = true; defer { busy = false }
        do {
            let authRevision = await store.repository.client.authSessionRevision()
            let freshGroup: ScoreGroup = try await store.repository.read("/\(detail.group.id)", expectedAuthRevision: authRevision)
            let freshMembers: [GroupMember] = try await store.repository.allPages("/\(detail.group.id)/members", expectedAuthRevision: authRevision)
            let fresh: GroupActivity = try await store.repository.read("/\(detail.group.id)/activities/\(activity.id)", expectedAuthRevision: authRevision)
            guard store.matchesIdentity(account, revision: presentedIdentityRevision), SessionStore.shared.user?.id == account,
                  await store.repository.client.authSessionRevision() == authRevision else { return }
            remoteGroup = freshGroup; remoteMembers = freshMembers; acceptConfirmed(fresh)
            desired = baseline
            for change in savedChanges where managedIDs.contains(change.memberID) {
                if change.registered { desired.insert(change.memberID) } else { desired.remove(change.memberID) }
            }
            if keepingChanges { await refreshParent(account, authRevision: authRevision) }
            guard store.matchesIdentity(account, revision: presentedIdentityRevision), SessionStore.shared.user?.id == account,
                  await store.repository.client.authSessionRevision() == authRevision else { return }
            error = nil
        } catch { if store.matchesIdentity(account, revision: presentedIdentityRevision) { self.error = groupErrorMessage(error) } }
    }
    private func acceptConfirmed(_ fresh: GroupActivity) {
        remoteActivity = fresh; baseline = Set(fresh.registeredMemberIds); baselineRevision = fresh.revision
    }
    private func refreshParent(_ account: String, authRevision: UInt64) async {
        guard store.matchesIdentity(account, revision: presentedIdentityRevision), SessionStore.shared.user?.id == account,
              await store.repository.client.authSessionRevision() == authRevision else { return }
        await onReload()
    }
    private func submit() async {
        guard let account = presentedAccountID, writable, dirty else { return }
        busy = true; defer { busy = false }
        let authRevision = await store.repository.client.authSessionRevision()
        do {
            try authorize(account)
            let freshGroup: ScoreGroup = try await store.repository.read("/\(detail.group.id)", expectedAuthRevision: authRevision)
            let freshMembers: [GroupMember] = try await store.repository.allPages("/\(detail.group.id)/members", expectedAuthRevision: authRevision)
            let fresh: GroupActivity = try await store.repository.read("/\(detail.group.id)/activities/\(activity.id)", expectedAuthRevision: authRevision)
            try authorize(account)
            guard await store.repository.client.authSessionRevision() == authRevision else { throw GroupFlowError.staleSession }
            remoteGroup = freshGroup; remoteMembers = freshMembers; remoteActivity = fresh
            try authorize(account)
            guard fresh.revision == baselineRevision, Set(fresh.registeredMemberIds) == baseline else {
                throw APIClientError.server(status: 409, code: "REVISION_CONFLICT", message: nil, nextAvailableAt: nil)
            }
            let submittedPlan = plan
            try await submittedPlan.apply(authorize: { try authorize(account) }, write: { change in
                guard await store.repository.client.authSessionRevision() == authRevision,
                      managedIDs.contains(change.memberID) else { throw GroupFlowError.staleSession }
                try await store.repository.action("/\(detail.group.id)/activities/\(activity.id)/\(change.registered ? "register" : "unregister")", body: .init(memberId: change.memberID), expectedAuthRevision: authRevision)
            }, confirmed: { change in
                // Never roll back a successful request when a later request fails.
                if change.registered { baseline.insert(change.memberID) } else { baseline.remove(change.memberID) }
                var updated = current; updated.registeredMemberIds = baseline.sorted(); acceptConfirmed(updated)
            })
            try authorize(account)
            await refreshParent(account, authRevision: authRevision)
            guard store.matchesIdentity(account, revision: presentedIdentityRevision), SessionStore.shared.user?.id == account,
                  await store.repository.client.authSessionRevision() == authRevision else { return }
            dismiss()
        } catch {
            guard store.matchesIdentity(account, revision: presentedIdentityRevision), SessionStore.shared.user?.id == account,
                  await store.repository.client.authSessionRevision() == authRevision else { return }
            self.error = groupErrorMessage(error)
            // Reads can recover the true revision and any concurrent registrations after a partial write.
            // Preserve outstanding choices, including the operation that first failed.
            let outstanding = plan.changes
            if let fresh: GroupActivity = try? await store.repository.read("/\(detail.group.id)/activities/\(activity.id)", expectedAuthRevision: authRevision),
               store.matchesIdentity(account, revision: presentedIdentityRevision), SessionStore.shared.user?.id == account,
               await store.repository.client.authSessionRevision() == authRevision {
                acceptConfirmed(fresh); desired = baseline
                for change in outstanding where managedIDs.contains(change.memberID) {
                    if change.registered { desired.insert(change.memberID) } else { desired.remove(change.memberID) }
                }
            }
            // The existing parent reload owns its cache writes and preserves successful prefixes after dismissal.
            await refreshParent(account, authRevision: authRevision)
            preview = false
        }
    }
}
