import SwiftUI
import ScoreCore

struct GroupListView: View {
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared
    @State private var create = false
    @State private var join = false
    @State private var feedback = false
    @State private var joinNumber = ""
    @State private var login = false
    @State private var pendingCreate = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 测试版说明卡收起态（沿用原关闭态存储，对齐安卓/鸿蒙口径）：
    /// 当前版本已收起时保留可展开的小条；升级后自动展开一次。
    @AppStorage("group_beta_notice_dismissed_version") private var betaNoticeDismissedVersion = ""
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    var body: some View {
        List {
            if let error = store.error { Section { GroupNotice(text: error); Button(groupText("retry", "Retry")) { Task { await store.refresh() } } } }
            if store.cached { GroupNotice(text: groupText("cached", "Showing saved data. Connect to refresh.")) }
            ForEach(store.pending.filter { ["pending", "rejected"].contains($0.status) }) { request in
                Section {
                    Label(request.groupName, systemImage: request.status == "pending" ? "hourglass" : "person.crop.circle.badge.xmark")
                    Text(GroupStatusText.joinRequest(request.status) + " · " + request.groupNo).font(.caption)
                    if let state = request.groupAvailability, !["available", "already_member", "pending_approval"].contains(state) { GroupNotice(text: groupText("unavailable", "This group cannot accept new members.")) }
                    Button(groupText("refresh", "Refresh")) { Task { await store.refresh() } }
                    if request.status == "pending" { Button(groupText("withdraw", "Withdraw request"), role: .destructive) { Task { if await store.perform({ try await store.repository.action("/join-requests/\(request.id)/withdraw") }) { await store.refresh() } } } }
                    if request.status == "rejected" || request.joinPolicy == "open" {
                        Button(groupText("join", "Join group")) { joinNumber = request.groupNo; join = true }
                            .disabled(["full", "closed", "archived", "dissolving", "not_found", "dissolved"].contains(request.groupAvailability ?? ""))
                    }
                }
            }
            if store.loading && store.groups.isEmpty { ProgressView() }
            else if store.groups.isEmpty && (store.error == nil || store.cached) { emptyState }
            let archivedGroups = store.groups.filter { $0.status == "archived" }
            let currentGroups = store.groups.filter { $0.status != "archived" }
            if !archivedGroups.isEmpty {
                Section {
                    NavigationLink { GroupArchivedListView(groups: archivedGroups, onStart: onStart) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "archivebox").font(.title3).foregroundStyle(Theme.textSecondary)
                                .frame(width: 48, height: 48).background(Theme.tintedFill(Theme.textSecondary, lightAlpha: 0.10, darkAlpha: 0.16), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: Theme.xs) {
                                Text(groupText("archived_list_title", "Archived groups")).font(GroupTypography.section)
                                Text(String.localizedStringWithFormat(NSLocalizedString("archived_count", value: "%d groups", comment: "Groups"), archivedGroups.count)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 3)
                    }.accessibilityIdentifier("group_archived_entry")
                }
            }
            ForEach(currentGroups) { group in
                Section { GroupListRow(group: group, onStart: onStart) }
            }
            Section {
                GroupBetaNoticeCard(dismissedVersion: $betaNoticeDismissedVersion, appVersion: appVersion, onFeedback: { feedback = true })
                    .listRowInsets(EdgeInsets(top: Theme.md, leading: Theme.md, bottom: Theme.md, trailing: Theme.md))
                    .listRowSeparator(.hidden)
            }
        }
        .listSectionSpacing(Theme.spacing)
        .frame(maxWidth: 960).expandedPhonePageContent(existingHorizontalInset: 20).frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                entryActions.padding(.horizontal, 20).padding(.vertical, Theme.spacing)
                    .frame(maxWidth: 960).expandedPhonePageContent(existingHorizontalInset: 20).frame(maxWidth: .infinity)
            }
            .background(Theme.backgroundColor.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Divider() }
        }
        .navigationTitle(groupText("my_groups", "My groups")).groupAdaptiveOrientation()
        .toolbar(.visible, for: .navigationBar)
        .toolbar { NavigationLink { GroupNoticeInbox(onStart: onStart) } label: {
            Image(systemName: "bell").frame(width: 24, height: 24)
                .overlay(alignment: .topTrailing) {
                    if store.unreadCount > 0 {
                        Text(store.unreadCount > 99 ? "99+" : "\(store.unreadCount)").font(GroupTypography.caption.weight(.bold)).monospacedDigit()
                            .foregroundStyle(Theme.textOnPrimary).padding(.horizontal, Theme.xs).padding(.vertical, 1)
                            .background(Theme.destructiveText, in: Capsule()).fixedSize()
                            .offset(x: 4, y: -4).accessibilityHidden(true)
                    }
                }
        }.accessibilityLabel(groupText("notices", "Notifications") + (store.unreadCount > 0 ? " (\(store.unreadCount))" : ""))
            .accessibilityIdentifier("group_notices") }
        .navigationDestination(isPresented: $feedback) {
            FeedbackListView(initiallyCreate: true, initialCreateTitle: "#\(groupText("groups", "Groups"))# ")
        }
        .navigationDestination(isPresented: $create) { GroupCreateView(onStart: onStart, usesParentNavigation: true) }
        .navigationDestination(isPresented: $join) { GroupJoinView(initialGroupNo: joinNumber, onStart: onStart, usesParentNavigation: true) }
        .sheet(isPresented: $login, onDismiss: { if SessionStore.shared.isAuthenticated && pendingCreate { pendingCreate = false; create = true }; Task { await store.refresh() } }) { AccountLoginSheet() }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        .toolbar(.hidden, for: .tabBar)
    }
    private var emptyState: some View {
        Section {
            VStack(spacing: Theme.padding) {
                EmptyStateCourtIcon()
                Text(groupText("empty_title", "No groups yet")).font(.title2.bold())
                Text(groupText("empty_intro", "Bring your friends together to plan games, keep score and build a shared match history.")).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Label(groupText("benefit_activity", "Plan activities and sign up"), systemImage: "calendar")
                Label(groupText("benefit_score", "Keep score or add past results"), systemImage: "sportscourt")
                Label(groupText("benefit_history", "Explore matches and rankings"), systemImage: "chart.bar")
            }.frame(maxWidth: .infinity).padding(.vertical, 20)
        }
    }
    private var entryActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.sm)) : AnyLayout(HStackLayout(spacing: Theme.spacing))
        return layout {
            Button { if SessionStore.shared.isAuthenticated { create = true } else { pendingCreate = true; login = true } } label: {
                Label(groupText("create", "Create group"), systemImage: "plus").font(GroupTypography.body.weight(.semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.borderedProminent).tint(Theme.primary).foregroundStyle(Theme.textOnPrimary).frame(maxWidth: .infinity).accessibilityIdentifier("group_create")
            Button { joinNumber = ""; join = true } label: {
                Text(groupText("join", "Join group")).font(GroupTypography.body.weight(.semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.bordered).tint(Theme.cardBackground).foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity).background(Theme.cardBackground, in: Capsule())
                .accessibilityIdentifier("group_join")
        }.disabled(!store.enabled).tint(Theme.primary)
    }
}

nonisolated func groupMemberCountText(_ count: Int) -> String {
    let key = count == 1 ? "member_count_single" : "member_count_short"
    return String(format: groupText(key, "%d " + groupText("members", "members")), count)
}

private struct GroupListRow: View {
    let group: ScoreGroup
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var body: some View {
        NavigationLink { GroupDetailView(groupID: group.id, onStart: onStart) } label: {
            HStack(spacing: Theme.spacing) {
                AppCatalogIcon(gameType: group.sport.gameType, size: 44)
                VStack(alignment: .leading, spacing: Theme.xs) {
                    HStack(spacing: Theme.sm) {
                        Text(group.name).font(.system(size: Theme.fontBody1, weight: .semibold)).lineLimit(1)
                        if !group.isActive { Text(group.statusLabel).font(GroupTypography.caption).foregroundStyle(Theme.textSecondary) }
                    }
                    Text(group.sport.title + " · " + groupMemberCountText(group.memberCount ?? 0))
                        .font(.system(size: Theme.fontCaption)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }.padding(.vertical, Theme.xs)
        }.accessibilityIdentifier("group_card_\(group.id)")
    }
}

/// 已归档小组（对齐安卓的独立归档列表页，主页只保留在读小组）。
struct GroupArchivedListView: View {
    var groups: [ScoreGroup]
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var body: some View {
        List {
            if groups.isEmpty { GroupEmptyCard(text: groupText("archived_empty", "No archived groups")) }
            ForEach(groups) { group in
                Section { GroupListRow(group: group, onStart: onStart) }
            }
        }.listSectionSpacing(Theme.spacing).expandedPhonePageContent(existingHorizontalInset: 20).navigationTitle(groupText("archived_list_title", "Archived groups")).groupAdaptiveOrientation()
            .toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .tabBar)
    }
}

private struct GroupBetaNoticeCard: View {
    @Binding var dismissedVersion: String
    let appVersion: String
    var onFeedback: () -> Void

    var body: some View {
        if dismissedVersion == appVersion {
            Button { dismissedVersion = "" } label: {
                HStack(spacing: Theme.sm) {
                    Text(groupText("beta_badge", "Beta"))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
                        .background(Theme.tintedFill(Theme.primary, lightAlpha: 0.10, darkAlpha: 0.18), in: Capsule())
                    Spacer(minLength: Theme.sm)
                    Image(systemName: "chevron.down").font(GroupTypography.body.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Text("sync_intro_expand"))
                .accessibilityIdentifier("group_beta_notice_expand")
        } else {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                HStack(alignment: .top, spacing: Theme.sm) {
                    Text(groupText("beta_notice", "Groups are in beta. Some features may change. Thanks for trying them early."))
                        .font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("group_beta_notice")
                    Button { dismissedVersion = appVersion } label: {
                        Image(systemName: "chevron.up").font(GroupTypography.body.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(Text("sync_intro_collapse"))
                        .accessibilityIdentifier("group_beta_notice_collapse")
                }
                Text(groupText("beta_supported_label", "Available now"))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                GroupBetaSportTags()
                if AppFeatureFlags.feedbackEntryEnabled {
                    Divider()
                    Button(action: onFeedback) {
                        HStack(spacing: Theme.sm) {
                            Text(groupText("beta_feedback_prompt", "Found a problem or have an idea?"))
                                .font(GroupTypography.body).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(groupText("beta_feedback_action", "Send feedback"))
                                .font(GroupTypography.body.weight(.semibold)).foregroundStyle(Theme.primary)
                                .fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.primary).accessibilityHidden(true)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("group_beta_feedback")
                }
            }
        }
    }
}

private struct GroupBetaSportTags: View {
    var sports: [GroupSport] = GroupSport.allCases
    private var uniqueSports: [GroupSport] {
        var seen = Set<String>()
        return sports.filter { seen.insert($0.rawValue).inserted }
    }
    var body: some View {
        GroupBetaSportFlowLayout(spacing: Theme.sm) {
            ForEach(uniqueSports) { sport in
                HStack(spacing: Theme.xs) {
                    AppCatalogIcon(gameType: sport.gameType, size: 18)
                    Text(sport.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.sm).padding(.vertical, Theme.xs)
                .background(Theme.surface, in: Capsule())
                .overlay { Capsule().stroke(Theme.divider, lineWidth: 1) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("group_beta_sport_" + sport.rawValue)
            }
        }
    }
}

private struct GroupBetaSportFlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : max(0, x - spacing), height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct GroupAccountBoundary: ViewModifier {
    @State private var store = GroupStore.shared
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.groupAdaptiveOrientation().toolbar(.hidden, for: .tabBar).onChange(of: store.identityRevision) { _, _ in dismiss() }
    }
}
extension View {
    func groupAccountBoundary() -> some View { modifier(GroupAccountBoundary()) }
}

private struct GroupAdaptiveOrientation: ViewModifier {
    @State private var ownerID = UUID()
    @State private var visible = false
    func body(content: Content) -> some View {
        content.onAppear {
            visible = true; UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            OrientationLock.shared.beginAdaptivePageOrientation(ownerID: ownerID)
            OrientationLock.shared.updateAdaptivePageOrientation(ownerID: ownerID, deviceOrientation: UIDevice.current.orientation)
            #if DEBUG
            // Headless simulators do not always deliver accelerometer events.
            // This fixture exercises landscape geometry; real rotation is a device gate.
            if ProcessInfo.processInfo.arguments.contains("-UITestGroupsLandscape") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if visible { OrientationLock.shared.updateAdaptivePageOrientation(ownerID: ownerID, deviceOrientation: .landscapeLeft) }
                }
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if visible { OrientationLock.shared.updateAdaptivePageOrientation(ownerID: ownerID, deviceOrientation: UIDevice.current.orientation) }
        }
        .onDisappear { visible = false; UIDevice.current.endGeneratingDeviceOrientationNotifications(); OrientationLock.shared.endAdaptivePageOrientation(ownerID: ownerID) }
    }
}
extension View { func groupAdaptiveOrientation() -> some View { modifier(GroupAdaptiveOrientation()) } }

struct GroupNotice: View {
    var text: String
    var body: some View { Text(text).font(GroupTypography.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("group_notice") }
}

struct GroupCreateView: View {
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var usesParentNavigation = false
    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var name = ""
    @State private var description = ""
    @State private var sport = GroupSport.badminton
    @State private var policy = GroupActivityPolicy.defaultJoinPolicy
    @State private var busy = false
    @State private var created: ScoreGroup?
    var body: some View {
        if usesParentNavigation { destination }
        else { NavigationStack { destination } }
    }
    @ViewBuilder private var destination: some View {
        if let created { GroupDetailView(groupID: created.id, onStart: onStart, initiallyShare: true) }
        else { editor }
    }
    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.padding) {
                GroupAlignedField(groupText("name", "Group name")) {
                    TextField(groupText("name", "Group name"), text: $name).groupAlignedInput(minHeight: 52).accessibilityIdentifier("group_name")
                }
                GroupAlignedField(groupText("description", "Description (optional)")) {
                    TextField(groupText("description", "Description (optional)"), text: $description, axis: .vertical)
                        .lineLimit(3...5).groupAlignedInput(minHeight: GroupFieldSize.note, alignment: .topLeading, font: GroupTypography.body).accessibilityIdentifier("group_create_description")
                }
                GroupAlignedField(groupText("sport", "Sport")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.sm) {
                            ForEach(GroupSport.allCases) { value in
                                Button { sport = value } label: {
                                    VStack(spacing: 6) {
                                        AppCatalogIcon(gameType: value.gameType, size: 34)
                                        Text(value.title).font(.system(size: Theme.fontBody2))
                                    }.frame(width: 96, height: 88)
                                        .foregroundStyle(sport == value ? Theme.primary : Theme.textSecondary)
                                        .background(sport == value ? Theme.primary.opacity(0.1) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(sport == value ? Theme.primary : .clear, lineWidth: 1) }
                                }.buttonStyle(.plain).accessibilityAddTraits(sport == value ? .isSelected : [])
                            }
                        }
                    }
                }
                GroupAlignedField(groupText("join_policy", "Joining")) {
                    GroupAlignedPolicyChoice(selection: $policy).accessibilityIdentifier("group_create_policy").accessibilityValue(groupText(policy, policy))
                }
                if let error = store.error { GroupNotice(text: error) }
            }.padding(Theme.padding).frame(maxWidth: 720).expandedPhonePageContent(existingHorizontalInset: Theme.padding).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(Theme.backgroundColor)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GroupAlignedFooter(topPadding: 8, bottomPadding: 8) {
                    Button(groupText("create", "Create group")) { Task { await submit() } }
                        .buttonStyle(GroupAlignedActionStyle()).disabled(busy || !valid).accessibilityIdentifier("group_create_submit")
                }
            }
            .disabled(busy).navigationTitle(groupText("create", "Create group")).navigationBarTitleDisplayMode(.inline).groupAccountBoundary()
            .navigationBarBackButtonHidden(usesParentNavigation && busy)
            .toolbar {
                if !usesParentNavigation { ToolbarItem(placement: .cancellationAction) { ModalCloseButton { dismiss() }.disabled(busy) } }
            }.interactiveDismissDisabled(busy)
    }
    private var valid: Bool { GroupInputValidation.validName(name, minimum: store.capabilities?.nameMin ?? 2, maximum: store.capabilities?.nameMax ?? 24) && description.utf16.count <= (store.capabilities?.descriptionMax ?? 200) && (store.capabilities?.allowsPeerCreation ?? false) }
    private func submit() async {
        guard valid, !busy else { return }
        busy = true; defer { busy = false }
        guard let accountID = store.accountID else { return }
        let revision = store.identityRevision
        _ = await store.perform {
            let group = try await store.repository.createGroup(body: GroupCreateBody(name: name, description: description, sport: sport, joinPolicy: policy), accountID: accountID)
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            created = group; await store.refresh()
        }
    }
}

private struct GroupCreatedView: View {
    let group: ScoreGroup
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        GroupShareView(group: group).navigationTitle(groupText("created", "Group created"))
            .safeAreaInset(edge: .bottom) { Text(groupText("created_hint", "Share the group number or QR code, then open your group from My groups.")).font(GroupTypography.body).padding().expandedPhonePageContent(existingHorizontalInset: Theme.padding).frame(maxWidth: .infinity).background(.regularMaterial) }
    }
}

struct GroupResultLink: View {
    var result: GroupResult
    var showDisclosure = true
    var body: some View {
        NavigationLink { GroupResultDetailView(initial: result) } label: {
            GroupResultSummary(result: result, showRules: true, showDisclosure: showDisclosure)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("group_result_\(result.id)")
    }
}

/// Shared compact result hero; game scores and review history belong in the information card.
private struct GroupResultSummary: View {
    var result: GroupResult
    var showRules = false
    var showDisclosure = false
    var centeredHeader = false
    private func seats(_ side: String) -> [GroupSeat] {
        result.participants.filter { $0.side == side }.sorted { $0.seat < $1.seat }
    }
    private func name(_ seat: GroupSeat) -> String {
        if let saved = seat.displayName, !saved.isEmpty { return saved }
        return GroupStore.shared.cache.details[result.groupId]?.members.first { $0.id == seat.memberId }?.displayName ?? groupText("former_member", "Former member")
    }
    private var ruleLabel: String {
        let count = result.rules?.maxSets ?? result.bestOf ?? 0
        guard count > 0 else { return "" }
        return result.rules?.matchCompletionMode == "play_all"
            ? String(format: NSLocalizedString("record_format_sets_play_all", value: "Play all %d sets", comment: ""), count)
            : "BO\(count)"
    }
    @ViewBuilder private func players(_ side: String) -> some View {
        VStack(spacing: Theme.xs) {
            ForEach(Array(seats(side).enumerated()), id: \.offset) { _, seat in
                HStack(spacing: Theme.xs) {
                    GroupAvatar(name: name(seat), url: GroupStore.shared.cache.details[result.groupId]?.members.first { $0.id == seat.memberId }?.avatarUrl, size: 24)
                    Text(name(seat)).font(GroupTypography.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity)
    }
    var body: some View {
        VStack(spacing: Theme.sm) {
            if centeredHeader {
                VStack(spacing: Theme.xs) {
                    Text(result.date, format: .dateTime.year().month().day().hour().minute())
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    if result.status != "confirmed" {
                        GroupActivityStatusChip(text: result.statusLabel, status: result.status)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(result.date, format: .dateTime.year().month().day().hour().minute())
                    if showRules, !ruleLabel.isEmpty { Text("· " + ruleLabel) }
                    Spacer(minLength: 0)
                    if result.status != "confirmed" { GroupActivityStatusChip(text: result.statusLabel, status: result.status) }
                    if showDisclosure { Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: Theme.sm) { players("A"); Color.clear.frame(width: 24, height: 1); players("B") }
                .padding(.top, Theme.xs)
            HStack(alignment: .firstTextBaseline, spacing: Theme.sm) {
                Text("\(result.setScore.a)").foregroundStyle(.red).frame(maxWidth: .infinity)
                Text("–").font(.title2).foregroundStyle(.secondary).frame(width: 24)
                Text("\(result.setScore.b)").foregroundStyle(.blue).frame(maxWidth: .infinity)
            }.font(.system(size: 48, weight: .bold)).monospacedDigit()
                .accessibilityElement(children: .ignore).accessibilityLabel("\(result.setScore.a) : \(result.setScore.b)")
            Text([result.format.title, result.source == "manual" ? groupText("manual", "Manual entry") : nil,
                  result.outcome == "draw" ? groupText("draw", "Draw") : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
    }
}

struct GroupResultDetailView: View {
    var initial: GroupResult
    @State private var result: GroupResult?
    @State private var store = GroupStore.shared
    @State private var reason = ""
    @State private var confirming = false
    @State private var voiding = false
    @State private var busy = false
    @State private var error: String?
    @State private var loadSequence = 0
    private var current: GroupResult { result ?? initial }
    private var me: GroupMember? { store.cache.details[current.groupId]?.members.first { $0.accountId == store.accountID && $0.status == "active" } }
    private var confirmation: (allowed: Bool, authority: Bool) { GroupPermissions.confirmation(current, group: store.cache.details[current.groupId]?.group, me: me) }
    private var canConfirm: Bool { confirmation.allowed && (store.capabilities?.allows("confirm_result") ?? true) }
    private var canVoid: Bool { store.enabled && store.cache.details[current.groupId]?.group.isActive == true && ["owner", "admin"].contains(me?.role ?? "") && current.status != "voided" }
    private var rulesSummary: String {
        guard let rules = current.rules else { return groupText("rules_missing", "Rules were not recorded") }
        let mode = rules.formatTitle
        if rules.sport == .tennis {
            return mode + " · " + groupText(rules.setScoringMode == "tiebreak_only" ? "tie_break" : "games_per_set", "Games per set") + " \(rules.setScoringMode == "tiebreak_only" ? rules.tieBreakPoints : rules.gamesPerSet)"
        }
        return mode + " · " + String(format: NSLocalizedString("record_format_points_per_set", value: "%d points per set", comment: ""), rules.pointsToWinSet)
    }
    private var confirmationMode: String? {
        switch current.confirmationMode {
        case "peer_confirm": return groupText("peer_confirmation", "Opponent confirmation")
        case "participant_confirm": return groupText("participants", "Participants")
        case "admin_override": return groupText("admin", "Admin")
        case "owner_authority", "coach_authority": return groupText("authority_confirm", "Confirm as group owner")
        default: return nil
        }
    }
    private func infoRow(_ label: String, _ value: String, supporting: String? = nil) -> some View {
        HStack(alignment: .center, spacing: Theme.sm) {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.xs) {
                Text(value)
                if let supporting { Text(supporting).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.font(GroupTypography.body).fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Theme.md).frame(minHeight: 56, alignment: .leading)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.md) {
                GroupSurface { GroupResultSummary(result: current, centeredHeader: true) }
                GroupSurface {
                    Text(groupText("result_information", "Match information")).font(GroupTypography.section)
                    VStack(spacing: 0) {
                        infoRow(groupText("match_rules", "Match rules"), rulesSummary)
                        Divider()
                        infoRow(groupText("set_details", "Set details"), current.sets.flatMap { $0.isEmpty ? nil : $0.map { "\($0.a):\($0.b)" }.joined(separator: " · ") } ?? groupText("no_set_details", "Only the overall result was recorded."))
                        Divider()
                        infoRow(groupText("submitted_by", "Submitted by"), memberName(current.submitterMemberId))
                        if !current.confirmedByMemberId.isEmpty {
                            Divider()
                            infoRow(groupText("confirmed_by", "Confirmed by"), memberName(current.confirmedByMemberId), supporting: confirmationMode)
                        }
                        if current.status == "voided", !current.reason.isEmpty {
                            Divider()
                            infoRow(groupText("void_reason", "Reason for voiding"), current.reason)
                        }
                    }
                }
                if canConfirm || canVoid || current.status == "pending_confirmation" {
                    GroupSurface {
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            Text(current.status == "pending_confirmation" ? groupText("confirm_result", "Confirm result") : groupText("result_actions", "Result actions")).font(GroupTypography.section)
                            if current.status == "pending_confirmation", !canConfirm {
                                let names = GroupPermissions.waitingNames(current, members: store.cache.details[current.groupId]?.members ?? [])
                                Text(groupText("pending_confirmation", "Waiting for confirmation") + (names.isEmpty ? "" : " · " + names.joined(separator: " / "))).font(.caption).foregroundStyle(.secondary)
                            }
                            if canConfirm {
                                Button(confirmation.authority ? groupText("authority_confirm", "Confirm as group owner") : groupText("confirm_result", "Confirm result")) { confirming = true }
                                    .buttonStyle(GroupAlignedActionStyle()).frame(maxWidth: .infinity).disabled(busy || store.cached)
                            }
                            if canVoid {
                                VStack(alignment: .leading, spacing: Theme.md) {
                                    Text(groupText(current.status == "pending_confirmation" ? "void_pending_message" : "void_confirmed_message", "This result will no longer count toward match records. The original score and reason will remain visible to group members."))
                                        .font(GroupTypography.caption).foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button(role: .destructive) { reason = ""; voiding = true } label: {
                                        Text(groupText("void_result", "Void result")).foregroundStyle(.red).frame(maxWidth: .infinity, minHeight: 48)
                                            .contentShape(Capsule())
                                            .overlay(Capsule().stroke(Color.red, lineWidth: 1))
                                    }.buttonStyle(.plain).disabled(busy || store.cached)
                                }
                            }
                        }
                    }
                }
                if let error {
                    GroupNotice(text: error)
                    Button(groupText("reload_version", "Load latest version")) { Task { await store.loadDetail(current.groupId); await reload() } }.disabled(busy)
                }
            }.padding().frame(maxWidth: 680).expandedPhonePageContent(existingHorizontalInset: Theme.padding).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("group_result_detail")
            .background(Theme.backgroundColor).navigationTitle(groupText("match_detail", "Match details"))
            .groupAccountBoundary().task { await reload() }.refreshable { if !busy { await store.loadDetail(current.groupId); await reload() } }
        .groupAlert(groupText("confirm_result", "Confirm result"), isPresented: $confirming) {
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) {}
            Button(groupText("confirm_result", "Confirm result")) { action("confirm") }
        } message: {
            Text(GroupResultConfirmationCopy.message(current, members: store.cache.details[current.groupId]?.members ?? [], authority: confirmation.authority, manager: GroupPermissions.manager(me)))
        }
        .groupAlert(groupText("void_result", "Void"), isPresented: $voiding) {
            Button(NSLocalizedString("cancel", value: "Cancel", comment: ""), role: .cancel) { reason = "" }
            Button(groupText("void_result", "Void"), role: .destructive) { action("void") }
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            VStack(alignment: .leading, spacing: Theme.md) {
            Text(groupText(current.status == "pending_confirmation" ? "void_pending_message" : "void_confirmed_message", "This result will no longer count toward match records. The original score and reason will remain visible to group members."))
                TextField(groupText("void_reason", "Reason for voiding"), text: $reason)
                    .groupAlignedInput()
                    .onChange(of: reason) { _, value in reason = GroupInputValidation.limitedText(value, maximum: 300) }
            }
        }
    }
    private func memberName(_ id: String) -> String { store.cache.details[current.groupId]?.members.first { $0.id == id }?.displayName ?? current.participants.first { $0.memberId == id }?.displayName ?? groupText("former_member", "Former member") }
    private func reload() async {
        guard let accountID = store.accountID else { return }
        loadSequence += 1; let sequence = loadSequence
        let revision = store.identityRevision
        do {
            let authRevision = await store.repository.client.authSessionRevision()
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            let loaded: GroupResult = try await store.repository.read("/\(initial.groupId)/results/\(initial.id)", expectedAuthRevision: authRevision)
            guard store.matchesIdentity(accountID, revision: revision), sequence == loadSequence else { return }
            result = loaded; error = nil
        } catch { if store.matchesIdentity(accountID, revision: revision), sequence == loadSequence { self.error = groupErrorMessage(error) } }
    }
    private func action(_ name: String) {
        guard !busy, !store.cached, let accountID = store.accountID,
              (name == "confirm" ? canConfirm : canVoid && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return }
        let target = current, identity = store.identityRevision, authority = confirmation.authority, voidReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true; error = nil
        Task {
            defer { busy = false }
            let success = await store.perform {
                if name == "confirm" {
                    let updated: GroupResult = try await store.repository.write("/\(target.groupId)/results/\(target.id)/confirm", body: GroupConfirmBody(authority: authority), revision: target.revision)
                    guard store.matchesIdentity(accountID, revision: identity), current.id == target.id else { return }
                    loadSequence += 1
                    result = updated
                } else {
                    try await store.repository.action("/\(target.groupId)/results/\(target.id)/void", body: .init(reason: voidReason), revision: target.revision)
                }
            }
            guard store.matchesIdentity(accountID, revision: identity) else { return }
            if success {
                if name != "confirm" { await reload() }
                Task { await store.loadDetail(target.groupId) }
            } else { error = store.error }
        }
    }
}

struct GroupMemberResultsView: View {
    let groupID: String, memberID: String, name: String
    let format: GroupFormat
    @State private var store = GroupStore.shared
    @State private var loading = false
    @State private var rows: [GroupResult] = []
    @State private var cursor: String?
    @State private var error: String?
    @State private var initialized = false
    @State private var sequence = 0
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: Theme.xs) {
                Text(name + " · " + format.title).font(GroupTypography.body.weight(.semibold))
                Text(groupText("confirmed_matches", "Confirmed")).font(.caption).foregroundStyle(Theme.textSecondary)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if let error { GroupNotice(text: error); Button(groupText("retry", "Retry")) { Task { await load(refresh: true) } } }
            if initialized && !loading && rows.isEmpty && error == nil { Text(groupText("no_results", "No matches recorded yet")) }
            ForEach(rows) { GroupResultLink(result: $0, showDisclosure: false) }
            if cursor != nil { Button(groupText("load_more", "Load more")) { Task { await load() } }.disabled(loading) }
        }.expandedPhonePageContent(existingHorizontalInset: Theme.padding).background(Theme.backgroundColor).accessibilityIdentifier("group_member_results")
            .navigationTitle(groupText("member_results_title", "Member results")).navigationBarTitleDisplayMode(.inline).groupAccountBoundary().task { if !initialized { initialized = true; await load() } }.refreshable { await load(refresh: true) }
    }
    private func load(refresh: Bool = false) async {
        guard !loading || refresh, let accountID = store.accountID else { return }
        let revision = store.identityRevision
        sequence += 1; let stamp = sequence, requestedCursor = refresh ? nil : cursor
        loading = true; defer { if sequence == stamp { loading = false } }
        do {
            let authRevision = await store.repository.client.authSessionRevision()
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            let page = try await store.repository.results(groupID, cursor: requestedCursor, memberID: memberID, format: format, expectedAuthRevision: authRevision)
            guard store.matchesIdentity(accountID, revision: revision), sequence == stamp else { return }
            guard page.nextCursor == nil || page.nextCursor != requestedCursor else { throw GroupFlowError.repeatedCursor }
            if refresh { rows = [] }; let existing = Set(rows.map(\.id))
            rows += page.items.filter { !existing.contains($0.id) }; cursor = page.nextCursor; error = nil
        } catch { if store.matchesIdentity(accountID, revision: revision), sequence == stamp { self.error = groupErrorMessage(error) } }
    }
}
