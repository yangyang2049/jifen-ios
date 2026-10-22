import SwiftUI

nonisolated struct GroupProfileFields: Equatable {
    var name: String
    var description: String
    var joinPolicy: String

    func changes(from original: Self, canEditJoinPolicy: Bool) -> GroupActionBody {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return GroupActionBody(
            name: trimmedName != original.name.trimmingCharacters(in: .whitespacesAndNewlines) ? trimmedName : nil,
            description: trimmedDescription != original.description.trimmingCharacters(in: .whitespacesAndNewlines) ? trimmedDescription : nil,
            joinPolicy: canEditJoinPolicy && joinPolicy != original.joinPolicy ? joinPolicy : nil
        )
    }
}

struct GroupManagementAction: Identifiable { let id = UUID(); var kind: String; var member: GroupMember? = nil }

struct GroupManagementView: View {
    let groupID: String; let action: GroupManagementAction
    var usesParentNavigation = false
    @State private var store = GroupStore.shared
    @State private var name = ""
    @State private var description = ""
    @State private var policy = "approval"
    @State private var target = ""
    @State private var admin = false
    @State private var busy = false
    @State private var removeConfirmation = false
    @State private var transferConfirmation = false
    @State private var initialized = false
    @State private var revision: Int64?
    @State private var error: String?
    @State private var imported = Set<String>()
    @State private var batchKeys: [String: String] = [:]
    @State private var originalProfile: GroupProfileFields?
    @State private var editorContentHeight: CGFloat = 0
    @State private var showingCommonNames = false
    @Environment(\.dismiss) private var dismiss
    private var detail: GroupDetailCache? { store.cache.details[groupID] }
    private var myMember: GroupMember? { detail?.members.first { $0.accountId == store.accountID && $0.status == "active" } }
    private var isOwner: Bool { myMember?.role == "owner" }
    private var profileChanges: GroupActionBody {
        guard let originalProfile else { return .init() }
        return GroupProfileFields(name: name, description: description, joinPolicy: policy)
            .changes(from: originalProfile, canEditJoinPolicy: isOwner)
    }
    private var names: [String] { GroupInputValidation.temporaryNames(name).filter { !imported.contains($0) } }
    private var titleKey: String {
        switch action.kind {
        case "profile": "edit_profile"
        case "temporary": "add_temporary"
        case "member": "member_settings"
        default: action.kind
        }
    }
    private var usesTopActions: Bool { !usesParentNavigation && ["temporary", "member", "transfer"].contains(action.kind) }
    private var topActionTitle: String { action.kind == "transfer" ? groupText("transfer_submit", "Transfer") : submitTitle }
    private func requestSubmit() { if action.kind == "transfer" { transferConfirmation = true } else { Task { await submit() } } }
    private var isDestructiveAction: Bool { ["leave", "dissolve"].contains(action.kind) }
    private var submitTitle: String {
        switch action.kind {
        case "profile": NSLocalizedString("save", value: "Save", comment: "")
        case "archive": groupText("archive", "Archive")
        case "restore": groupText("restore", "Restore")
        case "leave": groupText("leave", "Leave group")
        case "dissolve": groupText("dissolve", "Dissolve group")
        case "cancel_dissolve": groupText("cancel_dissolve", "Cancel dissolution")
        case "transfer": groupText("transfer", "Transfer ownership")
        default: NSLocalizedString("confirm", value: "Confirm", comment: "")
        }
    }
    private var valid: Bool {
        let capability = ["temporary", "member"].contains(action.kind) ? "manage_members" : "manage_group"
        guard action.kind == "leave" || store.allows(capability) else { return false }
        return switch action.kind {
        case "profile": GroupInputValidation.validName(name, minimum: store.capabilities?.nameMin ?? 2, maximum: store.capabilities?.nameMax ?? 24) && description.utf16.count <= (store.capabilities?.descriptionMax ?? 200) && (profileChanges.name != nil || profileChanges.description != nil || profileChanges.joinPolicy != nil)
        case "temporary": detail?.group.isActive == true && GroupPermissions.manager(myMember) && !names.isEmpty && names.allSatisfy { GroupInputValidation.validName($0) } && names.count + (detail?.members.count ?? 0) <= (detail?.group.memberLimit ?? 50)
        case "member": action.member?.kind == "temporary" ? GroupInputValidation.validName(name) : isOwner && detail?.group.isCoaching != true
        case "transfer": !target.isEmpty
        default: true
        }
    }
    var body: some View {
        if usesParentNavigation { editorContent }
        else {
            NavigationStack { editorContent }
                .presentationDetents(action.kind == "temporary" && !showingCommonNames ? [.height(max(320, ceil(editorContentHeight > 0 ? editorContentHeight + 56 : 420))), .large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.padding) {
            switch action.kind {
            case "profile":
                GroupAlignedField(groupText("name", "Group name")) {
                    TextField(groupText("name", "Group name"), text: $name).groupAlignedInput().accessibilityIdentifier("group_edit_name")
                }
                GroupAlignedField(groupText("description", "Description (optional)")) {
                    TextField(groupText("description", "Description (optional)"), text: $description, axis: .vertical).lineLimit(3...6)
                        .groupAlignedInput(minHeight: GroupFieldSize.note, alignment: .topLeading, font: GroupTypography.body).accessibilityIdentifier("group_edit_description")
                }
                if isOwner {
                    GroupAlignedField(groupText("join_policy", "Joining")) {
                        GroupAlignedPolicyChoice(selection: $policy, includesClosed: true).accessibilityIdentifier("group_edit_policy")
                    }
                }
                if let pending = detail?.group.pendingName, !pending.isEmpty { GroupNotice(text: groupText("moderation_pending", "Awaiting review") + " · " + pending) }
                if let reason = detail?.group.nameModerationReviewReason, !reason.isEmpty { GroupNotice(text: reason) }
                if let pending = detail?.group.pendingDescription, !pending.isEmpty { GroupNotice(text: groupText("moderation_pending", "Awaiting review") + " · " + pending) }
                if let reason = detail?.group.descriptionModerationReviewReason, !reason.isEmpty { GroupNotice(text: reason) }
            case "temporary":
                Text(groupText("temporary_hint", "Temporary members need no account and can be added when entering results."))
                    .font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textSecondary)
                TextField(groupText("batch_names_hint", "One name per line"), text: $name, axis: .vertical).lineLimit(5...8)
                    .groupAlignedInput(minHeight: GroupFieldSize.multipleNames, alignment: .topLeading, font: GroupTypography.body).accessibilityIdentifier("group_temporary_names")
                HStack {
                    Text(String(format: groupText("temporary_member_count", "%d members"), names.count)).font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    NavigationLink {
                        GroupCommonNameImportView(names: groupCaptureCommonNames()) { values in name = GroupInputValidation.temporaryNames(([name] + values).joined(separator: "\n")).joined(separator: "\n") }
                            .onAppear { showingCommonNames = true }
                            .onDisappear { showingCommonNames = false }
                    } label: {
                        HStack(spacing: 6) {
                            Text(groupText("temp_import_names", "Import saved names"))
                            Image(systemName: "chevron.right").font(.system(size: Theme.fontCaption))
                        }.font(.system(size: Theme.fontBody2)).frame(minHeight: 48)
                    }.foregroundStyle(Theme.primary).accessibilityIdentifier("group_temporary_common_names")
                }
                if !imported.isEmpty { Text(groupText("added_members", "Already added") + ": " + imported.sorted().joined(separator: ", ")) }
            case "member":
                if let reason = action.member?.displayNameModerationReviewReason, !reason.isEmpty { GroupNotice(text: reason) }
                if action.member?.kind == "temporary" {
                    GroupAlignedField(groupText("member_name", "Member name")) {
                        TextField(groupText("member_name", "Member name"), text: $name).groupAlignedInput().accessibilityIdentifier("group_member_rename")
                    }
                }
                if action.member?.kind == "account", isOwner, detail?.group.isCoaching != true { Toggle(groupText("admin", "Administrator"), isOn: $admin) }
                Button(groupText("remove_member", "Remove member"), role: .destructive) { removeConfirmation = true }
            case "transfer":
                ForEach((detail?.members ?? []).filter { $0.kind == "account" && $0.status == "active" && $0.id != myMember?.id }) { member in
                    Button { target = member.id } label: {
                        HStack(spacing: Theme.spacing) {
                            GroupAvatar(name: member.displayName, url: member.avatarUrl)
                            Text(member.displayName).font(.system(size: Theme.fontBody2)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: target == member.id ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.primary)
                        }.padding(Theme.spacing).frame(minHeight: 48).background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(target == member.id ? .isSelected : []).accessibilityIdentifier("group_transfer_member_" + member.id)
                }
                GroupNotice(text: groupText("transfer_hint", "After transfer, you become a regular member."))
            case "archive": GroupNotice(text: groupText("archive_hint", "Archiving preserves history and pauses changes."))
            case "restore": GroupNotice(text: groupText("restore_hint", "Restore this group to allow activities and scoring."))
            case "dissolve": GroupNotice(text: groupText("dissolve_hint", "The group becomes read-only for seven days. You can cancel dissolution during this period."))
            case "cancel_dissolve": GroupNotice(text: groupText("cancel_dissolve_hint", "Cancel dissolution and restore the group."))
            default: GroupNotice(text: groupText("leave_hint", "After leaving, you will no longer be a member, and this group will be removed from “My groups”. You will no longer be able to access or participate in it. Existing group match records and personal records on this device will be kept. You must rejoin to access the group again."))
            }
            if let error = error ?? store.error { GroupNotice(text: error) }
            }.padding(Theme.padding).frame(maxWidth: 720).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(editorContentHeight - height) > 1 { editorContentHeight = height }
                }
        }.scrollDismissesKeyboard(.interactively).background(Theme.backgroundColor)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !usesTopActions { GroupAlignedFooter(topPadding: action.kind == "profile" ? 8 : 16) {
                    HStack(spacing: action.kind == "temporary" ? 8 : 16) {
                        if !usesParentNavigation {
                            Button(NSLocalizedString("cancel", value: "Cancel", comment: "")) { dismiss() }.buttonStyle(GroupAlignedActionStyle(secondary: true))
                        }
                        Button(submitTitle, role: isDestructiveAction ? .destructive : nil) { Task { await submit() } }
                            .buttonStyle(GroupAlignedActionStyle(destructive: isDestructiveAction)).disabled(!valid || busy).accessibilityIdentifier("group_management_submit")
                    }
                }
            } }
            .disabled(busy).navigationTitle(groupText(titleKey, "Group settings")).groupAccountBoundary().interactiveDismissDisabled(busy)
            .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(usesParentNavigation && busy)
            .tint(Theme.primary)
            .toolbar {
                if !usesParentNavigation {
                    ToolbarItem(placement: .cancellationAction) { ModalCloseButton { dismiss() }.disabled(busy) }
                    if usesTopActions {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(topActionTitle) { requestSubmit() }
                                .font(.system(size: Theme.fontBody2, weight: .semibold))
                                .foregroundStyle(valid && !busy ? Theme.primary : Theme.textSecondary)
                                .disabled(!valid || busy).accessibilityIdentifier("group_management_submit")
                        }
                    }
                }
            }
            .onAppear { guard !initialized else { return }; initialized = true; name = action.member?.pendingDisplayName ?? action.member?.displayName ?? (action.kind == "temporary" ? "" : detail?.group.pendingName ?? detail?.group.name ?? ""); description = detail?.group.pendingDescription ?? detail?.group.description ?? ""; policy = detail?.group.joinPolicy ?? "approval"; revision = detail?.group.revision; admin = action.member?.role == "admin"; originalProfile = GroupProfileFields(name: name, description: description, joinPolicy: policy) }
            .groupAlert(groupText("transfer", "Transfer ownership"), isPresented: $transferConfirmation) {
                Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) {}
                Button(groupText("transfer_submit", "Transfer")) { Task { await submit() } }
                    .accessibilityIdentifier("group_transfer_confirm")
            } message: {
                Text(String(format: groupText("transfer_confirmation", "Transfer ownership to %@? You will become a regular member."), detail?.members.first { $0.id == target }?.displayName ?? ""))
            }
            .groupAlert(groupText("remove_member", "Remove member?"), isPresented: $removeConfirmation) {
                Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) {}
                Button(groupText("remove_member", "Remove member"), role: .destructive) { Task { await removeMember() } }
            } message: {
                Text(String(format: groupText("remove_member_message", "Remove %@ from this group? Previous match records will remain."), action.member?.displayName ?? ""))
            }
    }
    private func removeMember() async {
        guard let member = action.member, let group = detail?.group, GroupPermissions.canManageMember(group, me: myMember, target: member) else { return }
        busy = true; defer { busy = false }
        if await store.perform({ try await store.repository.action("/\(groupID)/members/\(member.id)/remove") }) { await store.loadDetail(groupID); dismiss() }
        else { error = store.error }
    }
    private func submit() async {
        guard valid, let account = store.accountID else { return }; busy = true; defer { busy = false }
        let identity = store.identityRevision
        let success = await store.perform {
            switch action.kind {
            case "profile": let _: ScoreGroup = try await store.repository.write("/\(groupID)", body: profileChanges, method: .patch)
            case "temporary":
                for value in names {
                    let key = batchKeys[value] ?? UUID().uuidString; batchKeys[value] = key
                    let member: GroupMember = try await store.repository.write("/\(groupID)/members/temporary", body: GroupActionBody(displayName: value), key: key)
                    guard store.acceptTemporaryMember(member, groupID: groupID, accountID: account, identity: identity) else { throw GroupFlowError.staleSession }
                    imported.insert(value)
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(format: groupText("temp_import_count", "Import (%1$d)"), selected.count)) { onImport(names.filter { selected.contains($0) }); dismiss() }.disabled(selected.isEmpty) } }
    }
}
