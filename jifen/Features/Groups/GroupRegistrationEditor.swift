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
    @State private var busy = false
    @State private var initialized = false
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

    private var addedCount: Int { plan.changes.filter(\.registered).count }
    private var removedCount: Int { plan.changes.count - addedCount }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    Text(groupText("activity_registration_scope", "Register temporary members on their behalf; account members register themselves."))
                        .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary).padding(.bottom, Theme.sm)
                    if temporaryMembers.isEmpty { GroupNotice(text: groupText("activity_registration_empty", "No temporary members")) }
                    ForEach(temporaryMembers) { member in registrationRow(member) }
                    if let error {
                        GroupNotice(text: error)
                    }
                }.padding(Theme.padding).frame(maxWidth: Theme.focusedContentMaxWidth).frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundColor)
            .navigationTitle(groupText("activity_registration_manage", "Temporary member registration"))
            .navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCloseButton { requestClose() }.disabled(busy).accessibilityIdentifier("group_registration_close")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GroupAlignedFooter {
                    VStack(spacing: Theme.sm) {
                        HStack(spacing: Theme.sm) {
                            Text(dirty ? String(format: groupText("activity_registration_changes", "Added %d · Removed %d"), addedCount, removedCount)
                                 : groupText("activity_registration_no_changes", "No unsaved changes"))
                            Spacer(minLength: 4)
                            Text("\(plan.projectedCount)/\(current.capacity)").monospacedDigit()
                        }.font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
                        Button {
                            if dirty { Task { await submit() } } else { dismiss() }
                        } label: {
                            Text(dirty ? String(format: groupText("activity_registration_save", "Save registrations (%d)"), plan.changes.count)
                                 : NSLocalizedString("done", value: "Done", comment: ""))
                        }
                        .buttonStyle(GroupAlignedActionStyle(secondary: !dirty))
                        .disabled(busy || (dirty && (!writable || plan.projectedCount > current.capacity)))
                        .accessibilityIdentifier("group_registration_save")
                    }
                }
            }
            .onChange(of: store.identityRevision) { _, _ in dismiss() }
            .task {
                guard !initialized else { return }; initialized = true
                presentedAccountID = store.accountID; presentedIdentityRevision = store.identityRevision
                baseline = Set(activity.registeredMemberIds); desired = baseline
                await reloadBaseline(keepingChanges: false)
            }
        }.presentationDetents([.fraction(0.82), .large]).presentationDragIndicator(.visible)
            .interactiveDismissDisabled(busy)
    }
    private func registrationRow(_ member: GroupMember) -> some View {
        let selected = desired.contains(member.id)
        let changed = selected != baseline.contains(member.id)
        let enabled = writable && !busy && (selected || plan.projectedCount < current.capacity)
        return Button {
            guard enabled else { return }
            if selected { desired.remove(member.id) } else { desired.insert(member.id) }
            error = nil
        } label: {
            HStack(spacing: Theme.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected ? Theme.primary : Theme.textSecondary)
                GroupAvatar(name: member.displayName, url: member.avatarUrl, size: 38)
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text(member.displayName).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textPrimary)
                    Text(groupText(changed ? (selected ? "activity_registration_pending_add" : "activity_registration_pending_remove")
                                   : (selected ? "activity_registration_registered" : "activity_registration_not_registered"),
                                   changed ? (selected ? "Pending registration" : "Pending removal") : (selected ? "Registered" : "Not registered")))
                        .font(.system(size: Theme.fontCaption)).foregroundStyle(changed ? Theme.primary : Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.sm).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(selected ? Theme.tintedFill(Theme.primary, lightAlpha: 0.1, darkAlpha: 0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled)
            .accessibilityIdentifier("group_registration_member_" + member.id)
            .accessibilityValue(selected ? groupText("activity_registration_registered", "Registered") : groupText("activity_registration_not_registered", "Not registered"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func requestClose() { guard !busy else { return }; dismiss() }
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
        remoteActivity = fresh; baseline = Set(fresh.registeredMemberIds)
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
        }
    }
}
