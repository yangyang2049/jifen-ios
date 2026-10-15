import SwiftUI
import ScoreCore

struct GroupListView: View {
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared
    @State private var create = false
    @State private var join = false
    @State private var joinNumber = ""
    @State private var login = false
    @State private var pendingCreate = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 测试版说明卡关闭态（版本号记忆，对齐安卓/鸿蒙口径）：
    /// 只存关闭时的版本号，`stored == 当前版本` 即视为已关闭；升级后自动重现一次。
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
                    Text(groupText(request.status == "pending" ? "pending_approval" : "reject", request.status) + " · " + request.groupNo).font(.caption)
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(groupText("archived_list_title", "Archived groups")).font(.headline)
                                Text(String(format: NSLocalizedString("archived_count", value: "%d groups", comment: "Groups"), archivedGroups.count)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 3)
                    }.accessibilityIdentifier("group_archived_entry")
                }
            }
            ForEach(currentGroups) { group in
                NavigationLink { GroupDetailView(groupID: group.id, onStart: onStart) } label: {
                    HStack(spacing: 14) {
                        AppCatalogIcon(gameType: group.sport.gameType, size: 48)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name).font(.headline)
                            Text("\(group.sport.title) · #\(GroupQRPayload.formatted(group.groupNo))").font(.subheadline).foregroundStyle(.secondary)
                            Text("\(group.memberCount ?? 0) " + groupText("members", "members")).font(.caption).foregroundStyle(.secondary)
                            if !group.isActive { Text(groupText(group.status, group.status)).font(.caption) }
                        }
                    }.padding(.vertical, 5)
                }.accessibilityIdentifier("group_card_\(group.id)")
            }
            if betaNoticeDismissedVersion != appVersion {
                Section {
                    HStack(spacing: 12) {
                        Label(groupText("beta_notice", "Groups are in beta. Share your feedback to help improve them."), systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            betaNoticeDismissedVersion = appVersion
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Theme.tintedFill(Theme.textSecondary, lightAlpha: 0.08, darkAlpha: 0.14), in: Circle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(groupText("close", "Close"))
                            .accessibilityIdentifier("group_beta_notice_close")
                    }
                    GroupBetaSportTags()
                    if AppFeatureFlags.feedbackEntryEnabled {
                        NavigationLink(groupText("feedback", "Send feedback")) {
                            FeedbackListView(initiallyCreate: true, initialCreateTitle: "#\(groupText("groups", "Groups"))# ")
                        }.accessibilityIdentifier("group_beta_feedback")
                    }
                }.accessibilityIdentifier("group_beta_notice")
            }
        }
        .frame(maxWidth: 960).frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                entryActions.padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: 960).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(groupText("my_groups", "My groups")).groupAdaptiveOrientation()
        .toolbar(.visible, for: .navigationBar)
        .toolbar { NavigationLink { GroupNoticeInbox(onStart: onStart) } label: {
            Image(systemName: "bell").padding(.top, 6).padding(.trailing, 6)
                .overlay(alignment: .topTrailing) {
                    if store.unreadCount > 0 {
                        Text(store.unreadCount > 99 ? "99+" : "\(store.unreadCount)").font(.caption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(Theme.textOnPrimary).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.destructiveText, in: Capsule()).accessibilityHidden(true)
                    }
                }
        }.accessibilityLabel(groupText("notices", "Notifications") + (store.unreadCount > 0 ? " (\(store.unreadCount))" : ""))
            .accessibilityIdentifier("group_notices"); Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel(groupText("refresh", "Refresh")) }
        .sheet(isPresented: $create) { GroupCreateView(onStart: onStart) }
        .sheet(isPresented: $join) { GroupJoinView(initialGroupNo: joinNumber, onStart: onStart) }
        .sheet(isPresented: $login, onDismiss: { if SessionStore.shared.isAuthenticated && pendingCreate { pendingCreate = false; create = true }; Task { await store.refresh() } }) { AccountLoginSheet() }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        .toolbar(.hidden, for: .tabBar)
    }
    private var emptyState: some View {
        Section {
            VStack(spacing: 16) {
                EmptyStateCourtIcon()
                Text(groupText("empty_title", "No groups yet")).font(.title2.bold())
                Text(groupText("empty_intro", "Bring your friends together to plan games, keep score and build a shared match history.")).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Label(groupText("benefit_activity", "Plan activities and sign up"), systemImage: "calendar")
                Label(groupText("benefit_score", "Keep score or add past results"), systemImage: "sportscourt")
                Label(groupText("benefit_history", "Explore matches and rankings"), systemImage: "chart.bar")
                Text(groupText("join_hint", "Join a friend's group using its number or QR code.")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 20)
        }
    }
    private var entryActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button { if SessionStore.shared.isAuthenticated { create = true } else { pendingCreate = true; login = true } } label: {
                Label(groupText("create", "Create group"), systemImage: "plus").font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).accessibilityIdentifier("group_create")
            Button { joinNumber = ""; join = true } label: {
                Text(groupText("join", "Join group")).font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.bordered).frame(maxWidth: .infinity).accessibilityIdentifier("group_join")
        }.disabled(!store.enabled).tint(Theme.primary)
    }
}

/// 已归档小组（对齐安卓的独立归档列表页，主页只保留在读小组）。
struct GroupArchivedListView: View {
    var groups: [ScoreGroup]
    var onStart: (GameType, SportsSetupResult, String) -> Void
    var body: some View {
        List {
            Text(String(format: NSLocalizedString("archived_count", value: "%d groups", comment: "Groups"), groups.count)).font(.caption).foregroundStyle(.secondary)
            if groups.isEmpty { GroupEmptyCard(text: groupText("archived_empty", "No archived groups")) }
            ForEach(groups) { group in
                NavigationLink { GroupDetailView(groupID: group.id, onStart: onStart) } label: {
                    HStack(spacing: 14) {
                        AppCatalogIcon(gameType: group.sport.gameType, size: 48)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name).font(.headline)
                            Text("\(group.sport.title) · #\(GroupQRPayload.formatted(group.groupNo))").font(.subheadline).foregroundStyle(.secondary)
                            Text("\(group.memberCount ?? 0) " + groupText("members", "members")).font(.caption).foregroundStyle(.secondary)
                            Text(groupText(group.status, group.status)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5)
                }.accessibilityIdentifier("group_card_\(group.id)")
            }
        }.navigationTitle(groupText("archived_list_title", "Archived groups")).groupAdaptiveOrientation()
            .toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .tabBar)
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
        content.groupAdaptiveOrientation().onChange(of: store.identityRevision) { _, _ in dismiss() }
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
    var body: some View { Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("group_notice") }
}

struct GroupCreateView: View {
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = GroupStore.shared
    @State private var name = ""
    @State private var description = ""
    @State private var sport = GroupSport.badminton
    @State private var policy = GroupActivityPolicy.defaultJoinPolicy
    @State private var busy = false
    @State private var key = UUID().uuidString
    @State private var created: ScoreGroup?
    var body: some View {
        NavigationStack {
            Group {
                if let created { GroupDetailView(groupID: created.id, onStart: onStart, initiallyShare: true) }
                else { Form {
                Section {
                    TextField(groupText("name", "Group name"), text: $name).accessibilityIdentifier("group_name")
                    TextField(groupText("description", "Description (optional)"), text: $description, axis: .vertical).lineLimit(2...5)
                    Picker(groupText("sport", "Sport"), selection: $sport) { ForEach(GroupSport.allCases) { Text($0.title).tag($0) } }
                    Picker(groupText("join_policy", "Joining"), selection: $policy) { Text(groupText("open", "Anyone with the number can join")).tag("open"); Text(groupText("approval", "Approval required")).tag("approval") }.accessibilityIdentifier("group_create_policy").accessibilityValue(groupText(policy, policy))
                }
                if let error = store.error { GroupNotice(text: error) }
                Button(groupText("create", "Create group")) { Task { await submit() } }.disabled(busy || !valid).accessibilityIdentifier("group_create_submit")
            }
                }
            }
            .disabled(busy)
            .navigationTitle(created == nil ? groupText("create", "Create group") : created?.name ?? "").groupAccountBoundary()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() }.disabled(busy) } }
            .onChange(of: name) { _,_ in key = UUID().uuidString }.onChange(of: description) { _,_ in key = UUID().uuidString }
            .onChange(of: sport) { _,_ in key = UUID().uuidString }.onChange(of: policy) { _,_ in key = UUID().uuidString }
            .interactiveDismissDisabled(busy)
        }
    }
    private var valid: Bool { GroupInputValidation.validName(name, minimum: store.capabilities?.nameMin ?? 2, maximum: store.capabilities?.nameMax ?? 24) && description.unicodeScalars.count <= (store.capabilities?.descriptionMax ?? 200) && (store.capabilities?.allowsPeerCreation ?? false) }
    private func submit() async {
        guard valid, !busy else { return }
        busy = true; defer { busy = false }
        guard let accountID = store.accountID else { return }
        let revision = store.identityRevision
        _ = await store.perform {
            let group: ScoreGroup = try await store.repository.write("", body: GroupCreateBody(name: name, description: description, sport: sport, joinPolicy: policy), key: key)
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
            .safeAreaInset(edge: .bottom) { Text(groupText("created_hint", "Share the group number or QR code, then open your group from My groups.")).font(.footnote).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
    }
}

struct GroupResultLink: View {
    var result: GroupResult
    var body: some View {
        NavigationLink { GroupResultDetailView(initial: result) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(result.participants.filter { $0.side == "A" }.sorted { $0.seat < $1.seat }.map(name).joined(separator: " / ") + "  \(result.setScore.a):\(result.setScore.b)  " + result.participants.filter { $0.side == "B" }.sorted { $0.seat < $1.seat }.map(name).joined(separator: " / ")).font(.headline)
                Text(groupText(result.status, result.status) + (result.outcome == "draw" ? " · " + groupText("draw", "Draw") : "")).font(.caption).foregroundStyle(.secondary)
                Text(result.date, format: .dateTime.month().day().hour().minute()).font(.caption)
            }.padding(.vertical, 4)
        }
    }
    private func name(_ seat: GroupSeat) -> String {
        if let saved = seat.displayName, !saved.isEmpty { return saved }
        return GroupStore.shared.cache.details[result.groupId]?.members.first { $0.id == seat.memberId }?.displayName ?? groupText("former_member", "Former member")
    }
}

struct GroupResultDetailView: View {
    var initial: GroupResult
    @State private var result: GroupResult?
    @State private var store = GroupStore.shared
    @State private var reason = ""
    @State private var busy = false
    @State private var error: String?
    private var current: GroupResult { result ?? initial }
    private var me: GroupMember? { store.cache.details[current.groupId]?.members.first { $0.accountId == store.accountID } }
    private var confirmation: (allowed: Bool, authority: Bool) { GroupPermissions.confirmation(current, group: store.cache.details[current.groupId]?.group, me: me) }
    private var canConfirm: Bool { confirmation.allowed && (store.capabilities?.allows("confirm_result") ?? true) }
    var body: some View {
        Form {
            Section {
                Text("\(current.setScore.a) : \(current.setScore.b)").font(.largeTitle.bold())
                Text(groupText(current.status, current.status))
                if current.outcome == "draw" { Text(groupText("draw", "Draw")) }
                Text(current.date, format: .dateTime)
                ForEach(Array(current.participants.enumerated()), id: \.offset) { _, p in Text("\(p.side)\(p.seat + 1) · \(p.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? memberName(p.memberId))") }
            }
            Section(groupText("set_details", "Set details")) {
                if let sets = current.sets { ForEach(Array(sets.enumerated()), id: \.offset) { i,s in Text("\(i + 1).  \(s.a):\(s.b)") } }
                else { Text(groupText("no_set_details", "Only the overall result was recorded.")) }
                Text(current.rules.map { "\($0.maxSets) · " + groupText($0.matchCompletionMode, $0.matchCompletionMode) } ?? groupText("rules_missing", "Rules were not recorded"))
            }
            Section {
                Text(groupText("source", "Source") + ": " + groupText(current.source, current.source))
                Text(groupText("submitted_by", "Submitted by") + ": " + memberName(current.submitterMemberId))
                if !current.confirmedByMemberId.isEmpty { Text(groupText("confirmed_by", "Confirmed by") + ": " + memberName(current.confirmedByMemberId)) }
                if !current.reason.isEmpty { Text(current.reason) }
            }
            if let error { GroupNotice(text: error); Button(groupText("reload_version", "Load latest version")) { Task { await store.loadDetail(current.groupId); await reload() } }.disabled(busy) }
            if canConfirm { Button(confirmation.authority ? groupText("authority_confirm", "Confirm as group owner") : groupText("confirm_result", "Confirm result")) { action("confirm") }.disabled(busy || store.cached) }
            if store.enabled, store.cache.details[current.groupId]?.group.isActive == true, ["owner", "admin"].contains(me?.role ?? ""), current.status != "voided" {
                Section {
                    TextField(groupText("void_reason", "Reason for voiding"), text: $reason)
                    Button(groupText("void_result", "Void result"), role: .destructive) { action("void") }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || store.cached)
                }
            }
        }.navigationTitle(groupText("match_detail", "Match details")).groupAccountBoundary().task { await reload() }.refreshable { await store.loadDetail(current.groupId); await reload() }
    }
    private func memberName(_ id: String) -> String { store.cache.details[current.groupId]?.members.first { $0.id == id }?.displayName ?? current.participants.first { $0.memberId == id }?.displayName ?? groupText("former_member", "Former member") }
    private func reload() async {
        guard let accountID = store.accountID else { return }
        let revision = store.identityRevision
        do {
            let authRevision = await store.repository.client.authSessionRevision()
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            let loaded: GroupResult = try await store.repository.read("/\(initial.groupId)/results/\(initial.id)", expectedAuthRevision: authRevision)
            guard store.matchesIdentity(accountID, revision: revision) else { return }
            result = loaded; error = nil
        } catch { if store.matchesIdentity(accountID, revision: revision) { self.error = groupErrorMessage(error) } }
    }
    private func action(_ name: String) { Task { busy = true; defer { busy = false }; if await store.perform({ if name == "confirm" { let _: GroupResult = try await store.repository.write("/\(current.groupId)/results/\(current.id)/confirm", body: GroupConfirmBody(authority: confirmation.authority), revision: current.revision) } else { try await store.repository.action("/\(current.groupId)/results/\(current.id)/void", body: .init(reason: reason), revision: current.revision) } }) { await reload(); await store.loadDetail(current.groupId) } else { error = store.error } } }
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
            if let error { GroupNotice(text: error); Button(groupText("retry", "Retry")) { Task { await load(refresh: true) } } }
            if initialized && !loading && rows.isEmpty && error == nil { Text(groupText("no_results", "No matches recorded yet")) }
            ForEach(rows) { GroupResultLink(result: $0) }
            if cursor != nil { Button(groupText("load_more", "Load more")) { Task { await load() } }.disabled(loading) }
        }.navigationTitle(name).groupAccountBoundary().task { if !initialized { initialized = true; await load() } }.refreshable { await load(refresh: true) }
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
