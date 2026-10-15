import SwiftUI

struct GroupManagementAction: Identifiable { let id = UUID(); var kind: String; var member: GroupMember? = nil }

struct GroupManagementView: View {
    let groupID: String; let action: GroupManagementAction
    @State private var store = GroupStore.shared
    @State private var name = ""
    @State private var description = ""
    @State private var policy = "approval"
    @State private var target = ""
    @State private var admin = false
    @State private var busy = false
    @State private var removeConfirmation = false
    @State private var initialized = false
    @State private var revision: Int64?
    @State private var error: String?
    @State private var imported = Set<String>()
    @State private var batchKeys: [String: String] = [:]
    @State private var conflictGroup: ScoreGroup?
    @Environment(\.dismiss) private var dismiss
    private var detail: GroupDetailCache? { store.cache.details[groupID] }
    private var myMember: GroupMember? { detail?.members.first { $0.accountId == store.accountID && $0.status == "active" } }
    private var isOwner: Bool { myMember?.role == "owner" }
    private var names: [String] { GroupInputValidation.temporaryNames(name).filter { !imported.contains($0) } }
    private var titleKey: String {
        switch action.kind {
        case "profile": "edit_profile"
        case "temporary": "temporary_members"
        case "member": "member_settings"
        default: action.kind
        }
    }
    private var valid: Bool {
        switch action.kind {
        case "profile": GroupInputValidation.validName(name, minimum: store.capabilities?.nameMin ?? 2, maximum: store.capabilities?.nameMax ?? 24) && description.unicodeScalars.count <= (store.capabilities?.descriptionMax ?? 200)
        case "temporary": !names.isEmpty && names.allSatisfy { GroupInputValidation.validName($0) } && names.count + (detail?.members.count ?? 0) <= (detail?.group.memberLimit ?? 50)
        case "member": action.member?.kind == "temporary" ? GroupInputValidation.validName(name) : isOwner && detail?.group.isCoaching != true
        case "transfer": !target.isEmpty
        default: true
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                switch action.kind {
                case "profile":
                    TextField(groupText("name", "Group name"), text: $name).accessibilityIdentifier("group_edit_name")
                    TextField(groupText("description", "Description"), text: $description, axis: .vertical)
                    if isOwner { Picker(groupText("join_policy", "Joining"), selection: $policy) { Text(groupText("approval", "Approval required")).tag("approval"); Text(groupText("open", "Direct joining")).tag("open"); Text(groupText("closed", "Joining closed")).tag("closed") }.accessibilityIdentifier("group_edit_policy") }
                    if let pending = detail?.group.pendingName, !pending.isEmpty { GroupNotice(text: groupText("moderation_pending", "Awaiting review") + " · " + pending) }
                    if let reason = detail?.group.nameModerationReviewReason, !reason.isEmpty { GroupNotice(text: reason) }
                    if let pending = detail?.group.pendingDescription, !pending.isEmpty { GroupNotice(text: groupText("moderation_pending", "Awaiting review") + " · " + pending) }
                    if let reason = detail?.group.descriptionModerationReviewReason, !reason.isEmpty { GroupNotice(text: reason) }
                case "temporary":
                    TextField(groupText("member_name", "Member name"), text: $name, axis: .vertical).lineLimit(2...8).accessibilityIdentifier("group_temporary_names")
                    Text(groupText("batch_names_hint", "Enter one name per line. Each name may contain 1–24 characters.")).font(.caption).foregroundStyle(.secondary)
                    Section(groupText("common_names", "Common names")) {
                        NavigationLink(groupText("common_names", "Common names")) {
                            GroupCommonNameImportView(names: groupCaptureCommonNames()) { values in name = GroupInputValidation.temporaryNames(([name] + values).joined(separator: "\n")).joined(separator: "\n") }
                        }
                    }
                    if !imported.isEmpty { Text(groupText("added_members", "Already added") + ": " + imported.sorted().joined(separator: ", ")) }
                case "member":
                    if let reason = action.member?.displayNameModerationReviewReason, !reason.isEmpty { GroupNotice(text: reason) }
                    if action.member?.kind == "temporary" { TextField(groupText("member_name", "Member name"), text: $name).accessibilityIdentifier("group_member_rename") }
                    if action.member?.kind == "account", isOwner, detail?.group.isCoaching != true { Toggle(groupText("admin", "Administrator"), isOn: $admin) }
                    Button(groupText("remove_member", "Remove member"), role: .destructive) { removeConfirmation = true }
                case "transfer":
                    GroupSeatPicker(title: groupText("new_owner", "New owner"), selectedID: $target, members: (detail?.members ?? []).filter { $0.kind == "account" && $0.id != myMember?.id })
                    GroupNotice(text: groupText("transfer_hint", "After transfer, you become a regular member."))
                case "archive": GroupNotice(text: groupText("archive_hint", "Archiving preserves history and pauses changes."))
                case "restore": GroupNotice(text: groupText("restore_hint", "Restore this group to allow activities and scoring."))
                case "dissolve": GroupNotice(text: groupText("dissolve_hint", "The group becomes read-only for seven days. You can cancel dissolution during this period."))
                case "cancel_dissolve": GroupNotice(text: groupText("cancel_dissolve_hint", "Cancel dissolution and restore the group."))
                default: GroupNotice(text: groupText("leave_hint", "Your personal records stay on this device after leaving."))
                }
                if let error = error ?? store.error { GroupNotice(text: error); if action.kind == "profile" { Button(groupText("reload_version", "Load latest version")) { Task { await loadConflictVersion() } } } }
                if let remote = conflictGroup {
                    Section(groupText("server_version", "Latest version")) {
                        Text(remote.pendingName ?? remote.name); Text(remote.pendingDescription ?? remote.description); Text(groupText(remote.joinPolicy, remote.joinPolicy))
                        Button(groupText("reload_version", "Load latest version")) { name = remote.pendingName ?? remote.name; description = remote.pendingDescription ?? remote.description; policy = remote.joinPolicy; revision = remote.revision; conflictGroup = nil; error = nil; store.error = nil }
                        Button(groupText("keep_draft", "Keep my edits")) { revision = remote.revision; conflictGroup = nil; error = nil; store.error = nil }
                    }
                }
                Button(groupText("save", "Confirm")) { Task { await submit() } }.disabled(!valid || busy).accessibilityIdentifier("group_management_submit")
            }.scrollDismissesKeyboard(.interactively).disabled(busy).navigationTitle(groupText(titleKey, "Group settings")).groupAccountBoundary().interactiveDismissDisabled(busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() }.disabled(busy) } }
                .onAppear { guard !initialized else { return }; initialized = true; name = action.member?.pendingDisplayName ?? action.member?.displayName ?? (action.kind == "temporary" ? "" : detail?.group.pendingName ?? detail?.group.name ?? ""); description = detail?.group.pendingDescription ?? detail?.group.description ?? ""; policy = detail?.group.joinPolicy ?? "approval"; revision = detail?.group.revision; admin = action.member?.role == "admin" }
                .confirmationDialog(groupText("remove_member", "Remove member?"), isPresented: $removeConfirmation) {
                    Button(groupText("remove_member", "Remove member"), role: .destructive) { Task { await removeMember() } }
                }
        }
    }
    private func loadConflictVersion() async {
        guard let account = store.accountID else { return }; let identity = store.identityRevision
        busy = true; defer { busy = false }
        do { let remote: ScoreGroup = try await store.repository.read("/\(groupID)"); if store.matchesIdentity(account, revision: identity) { conflictGroup = remote } }
        catch { if store.matchesIdentity(account, revision: identity) { self.error = groupErrorMessage(error) } }
    }
    private func removeMember() async {
        guard let member = action.member, let group = detail?.group, GroupPermissions.canManageMember(group, me: myMember, target: member) else { return }
        busy = true; defer { busy = false }
        if await store.perform({ try await store.repository.action("/\(groupID)/members/\(member.id)/remove") }) { await store.loadDetail(groupID); dismiss() }
        else { error = store.error }
    }
    private func submit() async {
        guard valid else { return }; busy = true; defer { busy = false }
        let success = await store.perform {
            switch action.kind {
            case "profile": let _: ScoreGroup = try await store.repository.write("/\(groupID)", body: GroupActionBody(name: name, description: description, joinPolicy: isOwner ? policy : nil), method: .patch, revision: revision)
            case "temporary":
                for value in names {
                    let key = batchKeys[value] ?? UUID().uuidString; batchKeys[value] = key
                    let _: GroupMember = try await store.repository.write("/\(groupID)/members/temporary", body: GroupActionBody(displayName: value), key: key); imported.insert(value)
                }
            case "member":
                if let member = action.member { let _: GroupMember = try await store.repository.write("/\(groupID)/members/\(member.id)", body: GroupActionBody(displayName: member.kind == "temporary" ? name : nil, role: member.kind == "account" && isOwner && detail?.group.isCoaching != true ? (admin ? "admin" : "member") : nil), method: .patch) }
            case "transfer": try await store.repository.action("/\(groupID)/ownership-transfer", body: .init(targetMemberId: target), revision: revision)
            case "archive", "restore", "dissolve": try await store.repository.action("/\(groupID)/\(action.kind)", revision: revision)
            case "cancel_dissolve": try await store.repository.action("/\(groupID)/dissolve/cancel", revision: revision)
            default: try await store.repository.action("/\(groupID)/leave")
            }
        }
        if success { if action.kind == "leave" { store.forgetGroup(groupID) }; await store.refresh(); dismiss() }
        else { error = store.error }
    }
}

private struct GroupCommonNameImportView: View {
    var names: [String]
    var onImport: ([String]) -> Void
    @State private var selected = Set<String>()
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            ForEach(names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { name in
                Button { if selected.contains(name) { selected.remove(name) } else { selected.insert(name) } } label: {
                    HStack { Text(name).foregroundStyle(.primary); Spacer(); Image(systemName: selected.contains(name) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.primary) }
                }.accessibilityAddTraits(selected.contains(name) ? .isSelected : [])
            }
        }.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always)).navigationTitle(groupText("common_names", "Common names")).groupAccountBoundary()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(groupText("add", "Add") + " (\(selected.count))") { onImport(names.filter { selected.contains($0) }); dismiss() }.disabled(selected.isEmpty) } }
    }
}
