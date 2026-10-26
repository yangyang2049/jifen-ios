import AVKit
import ScoreCore
import SwiftUI

/// “我”位置的头像：登录且已上传头像时显示远程头像，登录无头像回退到昵称首字，
/// 未登录显示 person 占位（对齐个人资料页头像逻辑）。选择弹窗与常用名称列表共用。
struct IdentitySelfAvatar: View {
    let size: CGFloat
    @State private var session = SessionStore.shared

    var body: some View {
        let user = session.user
        let url = user.flatMap { APIAssetURLResolver.resolve($0.avatarUrl ?? $0.avatar) }
        ZStack {
            Circle().fill(Theme.controlBackground)
            if let user, let url {
                RemoteImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialFallback(user)
                }
                .clipShape(Circle())
            } else if let user {
                initialFallback(user)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func initialFallback(_ user: AppUser) -> some View {
        Text(user.displayName.first.map(String.init) ?? "")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
    }
}

struct ParticipantAssociatedNamesSection: View {
    @State private var store = ParticipantIdentityStore.shared
    @State private var unlinking: ParticipantAlias?
    @State private var error: String?
    @State private var showLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IdentitySelfAvatar(size: 36)
                Text(store.currentName).foregroundStyle(Theme.textPrimary)
                Text(identityText("self", "我")).font(.caption).foregroundStyle(Theme.accentColor)
                Spacer()
                if store.isGuest { Text(identityText("local", "本机")).font(.caption).foregroundStyle(Theme.textSecondary) }
            }
            .padding(16).commonDataListCardStyle()
            // 尚未关联任何名称时，卡片里只剩"关联用过的名称"入口，小标题反而多余。
            if !store.aliases.isEmpty {
                HStack {
                    Text(identityText("associated_names", "已关联本人"))
                    Spacer()
                }.font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(store.aliases) { alias in
                    HStack {
                        Text(alias.name)
                        Text(identityText(alias.state == .pending ? "pending_alias" : "self", alias.state == .pending ? "待整理" : "我"))
                            .font(.caption).foregroundStyle(Theme.accentColor)
                        Spacer()
                        if !alias.visibleInPicker { Text(identityText("hidden", "已隐藏")).font(.caption).foregroundStyle(Theme.textSecondary) }
                        Menu {
                            if alias.state == .pending {
                                Button(identityText("activate_alias", "用于选人")) { perform { try store.activate(alias) } }
                                    .disabled(store.activeCount >= 3)
                            }
                            if store.isGuest && alias.state == .active {
                                Button(identityText("use_local_name", "用作本机名称")) { perform { try store.useAsGuestName(alias) } }
                            }
                            Button(identityText(alias.visibleInPicker ? "hide_alias" : "show_alias", alias.visibleInPicker ? "移出快捷选择" : "恢复快捷选择")) {
                                perform { try store.setVisibility(alias, visible: !alias.visibleInPicker) }
                            }
                            Button(identityText("unlink_alias", "解除关联"), role: .destructive) { unlinking = alias }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        }.accessibilityLabel(alias.name + identityText("manage_alias", "，管理关联"))
                    }.padding(.leading, 16).padding(.trailing, 4)
                    Divider()
                }
                NavigationLink {
                    HistoricalParticipantNamesView()
                } label: {
                    Label(identityText("link_history", "关联用过的名称"), systemImage: "link")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }.foregroundStyle(Theme.accentColor)
            }.commonDataListCardStyle()
            if store.isGuest && !store.aliases.isEmpty {
                Button(identityText("login_sync", "登录并同步")) { showLogin = true }
                    .font(.subheadline).foregroundStyle(Theme.accentColor).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .confirmationDialog(identityText("unlink_alias", "解除关联"), isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }), titleVisibility: .visible) {
            if let alias = unlinking {
                Button(identityText("unlink_alias", "解除关联"), role: .destructive) { perform { try store.unlink(alias) }; unlinking = nil }
            }
        } message: { Text(identityText("unlink_explanation", "解除该名称形成的历史关联，原记录保留。直接以“我”保存的新记录不受影响。")) }
        .alert(identityText("operation_failed", "操作未完成"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(identityText("ok", "好的"), role: .cancel) {}
        } message: { Text(error ?? "") }
        .sheet(isPresented: $showLogin) { AccountLoginSheet() }
    }

    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}

struct HistoricalParticipantNamesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ParticipantIdentityStore.shared
    @State private var selected: Set<String> = []
    @State private var confirming = false
    @State private var error: String?
    @State private var records: [ScoreboardRecord] = []
    @State private var cloud = PersonalRecordsCloudSync.shared
    @State private var finishedInitialLoad = false
    @State private var loadError: String?
    var initialName: String? = nil

    private var candidates: [PersonalHistoricalNameCandidate] {
        PersonalHistoricalNames.candidates(records: records, cloudRecords: cloud.remoteRecords,
            identity: store, cloud: cloud, initialName: initialName)
    }
    private var proposedCount: Int {
        let active = Set(store.aliases.filter { $0.state == .active }.map(\.normalizedName))
        return active.union(selected).count
    }

    var body: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    HStack(spacing: 8) {
                        Button {
                            if selected.contains(candidate.id) { selected.remove(candidate.id) }
                            else { selected.insert(candidate.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Theme.accentColor)
                                Text(candidate.name).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(String(format: identityText("matches_count", "%d 场"), candidate.recordCount))
                                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .disabled(!selected.contains(candidate.id) && proposedCount >= 3 && !store.aliases.contains { $0.normalizedName == candidate.id && $0.state == .active })
                        Menu {
                            ForEach(Array(candidate.records.prefix(5))) { record in
                                NavigationLink((record.presentation.project ?? record.presentation.title) + " · "
                                    + Date(timeIntervalSince1970: record.timestamp).formatted(date: .numeric, time: .omitted)) {
                                    switch record {
                                    case .scoreboard(let native): ScoreboardRecordDetailPage(recordId: native.id)
                                    case .cloud(let remote): PersonalCloudRecordDetailView(record: remote)
                                    case .timer(let timer): TimerRecordDetailPage(recordId: timer.id)
                                    }
                                }
                            }
                        } label: { Image(systemName: "eye").frame(width: 44, height: 44) }
                        .disabled(candidate.seats.isEmpty)
                        .accessibilityLabel(candidate.name + identityText("preview_history", "，预览记录"))
                    }
                }
            } header: {
                HStack { Text(identityText("choose_old_names", "选择你曾用过的名字")); Spacer(); Text("\(proposedCount) / 3") }
            }
            if candidates.isEmpty {
                if !finishedInitialLoad {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let loadError {
                    Text(loadError).foregroundStyle(Theme.textSecondary)
                    Button(identityText("sync_retry", "重试同步")) { Task { await loadHistory() } }
                } else {
                    Text(identityText("no_personal_names", "暂无可关联的个人名称")).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.backgroundColor)
        .navigationTitle(identityText("link_history_title", "关联历史名称"))
        .navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        .onChange(of: store.state.activeLibraryId) { _, _ in dismiss() }
        .onChange(of: SessionStore.shared.user?.id) { _, _ in dismiss() }
        .safeAreaInset(edge: .bottom) {
            Button { confirming = true } label: {
                Text(identityText("link_to_me", "关联到我"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textOnPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accentColor, in: Capsule())
            }
                .buttonStyle(.plain)
                .opacity(selected.isEmpty || proposedCount > 3 ? 0.45 : 1)
                .disabled(selected.isEmpty || proposedCount > 3)
                .padding(.horizontal, Theme.md).padding(.vertical, 10)
        }
        .task {
            if let initialName { selected = [ParticipantIdentityRules.normalizedName(initialName)] }
            await loadHistory()
        }
        .refreshable { await loadHistory() }
        .confirmationDialog(identityText("link_to_me", "关联到我"), isPresented: $confirming, titleVisibility: .visible) {
            Button(identityText("confirm_link", "确认关联")) {
                do {
                    for candidate in candidates where selected.contains(candidate.id) { _ = try store.link(name: candidate.name, historicalSeats: candidate.seats) }
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
        } message: {
            let selectedSeats = candidates.filter { selected.contains($0.id) }.flatMap(\.seats)
            let ambiguous = Dictionary(grouping: selectedSeats, by: { RecordsTabRecordSelectionID.cloud($0.libraryId, $0.recordKey) }).values.filter { $0.count > 1 }.count
            Text(identityText("link_history_explanation", "保留当时的名称和比分，按选中的名字归入本人记录。")
                + (ambiguous > 0 ? "\n" + String(format: identityText("ambiguous_records", "%d 条记录包含多个本人位置，暂不计入我的记录。"), ambiguous) : ""))
        }
        .alert(identityText("operation_failed", "操作未完成"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(identityText("ok", "好的"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func loadHistory() async {
        finishedInitialLoad = false
        loadError = nil
        defer { if !Task.isCancelled { finishedInitialLoad = true } }
        records = ScoreboardRecordManager.shared.loadAllRecords()
        do {
            try store.migrateLegacyIfNeeded(scoreIDs: records.map(\.id), timerIDs: TimerRecordManager.shared.getRecords().map(\.id))
            if !store.isGuest {
                _ = try await cloud.query(scope: "all", kind: "score", project: nil, from: nil, to: nil, search: "")
            }
        } catch {
            if !Task.isCancelled { loadError = error.localizedDescription }
        }
    }

}

struct PersonalCloudRecordDetailView: View {
    let record: PersonalRecordEnvelope
    @State private var identity = ParticipantIdentityStore.shared
    @State private var cloud = PersonalRecordsCloudSync.shared
    private var current: PersonalRecordEnvelope {
        cloud.remoteRecords.first { $0.libraryId == record.libraryId && $0.recordKey == record.recordKey } ?? record
    }
    private var canRead: Bool { PersonalRecordAccessPolicy.allowsCloudRecord(current, identity: identity, cloud: cloud) }

    var body: some View {
        Group {
            if canRead {
                if let decoded = PersonalCloudRecordDecoder.scoreboard(current) {
                    ScoreboardRecordDetailPage(cloudRecord: current, decodedRecord: decoded)
                } else if let decoded = PersonalCloudRecordDecoder.timer(current) {
                    TimerRecordDetailPage(cloudRecord: current, decodedRecord: decoded)
                } else {
                    summaryContent
                        .navigationTitle(identityText("record_detail", "记录详情"))
                }
            } else {
                ContentUnavailableView(identityText("record_unavailable", "记录不可用"), systemImage: "doc.questionmark")
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var summaryContent: some View {
        var summary = current
        summary.nativePayload = [:]
        let row = RecordListPresentation(summary)
        return ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 16) {
                    if let game = row.gameType {
                        HStack { AppCatalogIcon(gameType: game, size: 28); Text(game.displayName).font(.headline) }
                    }
                    Text(row.title).font(.headline)
                    if let score = row.score { Text(score).font(.title.bold()).monospacedDigit() }
                    Text(Date(timeIntervalSince1970: Double(current.playedAt) / 1_000).formatted())
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    if let duration = row.duration { Text(formatDuration(duration)).font(.subheadline) }
                }
                .frame(maxWidth: .infinity).padding(18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                CloudRecordNotesCard(record: current)
                Text(NSLocalizedString("no_actions_recorded", value: "未记录任何操作", comment: ""))
                    .foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).padding(24)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            }.padding().frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(Theme.backgroundColor)
    }
}

/// Cloud annotations share the detail-page card chrome. Text and audio are
/// read from the account/library envelope, never a same-ID local record.
struct CloudRecordNotesCard: View {
    let record: PersonalRecordEnvelope
    @State private var player: AVPlayer?
    @State private var playing: String?
    @State private var downloading: String?
    @State private var error: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var identity = ParticipantIdentityStore.shared
    @State private var cloud = PersonalRecordsCloudSync.shared
    private var canRead: Bool { PersonalRecordAccessPolicy.allowsCloudRecord(record, identity: identity, cloud: cloud) }

    var body: some View {
        Group {
            if canRead && (!(record.note ?? "").isEmpty || !record.assetIds.isEmpty) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Theme.primary).frame(width: 3, height: 16)
                        Text(NSLocalizedString("record_note_title", value: "笔记", comment: "")).font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    if let note = record.note, !note.isEmpty { Text(note).textSelection(.enabled) }
                    ForEach(record.assetIds, id: \.self) { asset in
                        Button { play(asset) } label: {
                            HStack {
                                if downloading == asset { ProgressView() }
                                else { Image(systemName: playing == asset ? "pause.circle" : "play.circle").font(.title2) }
                                Text(identityText("play_voice", "播放语音备注"))
                                Spacer()
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(Theme.primary).disabled(downloading != nil)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(Theme.textSecondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .onChange(of: canRead) { _, allowed in if !allowed { stop() } }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if let item = notification.object as? AVPlayerItem, item === player?.currentItem { stop() }
        }
    }
    private func stop() { downloadTask?.cancel(); downloadTask = nil; downloading = nil; player?.pause(); player = nil; playing = nil }
    private func play(_ asset: String) {
        guard canRead else { return }
        if playing == asset { stop(); return }
        stop(); downloading = asset; error = nil
        downloadTask = Task {
            defer { downloading = nil }
            do {
                let url = try await cloud.downloadAudio(assetId: asset)
                guard canRead, !Task.isCancelled else { return }
                player = AVPlayer(url: url); playing = asset; player?.play()
            } catch { if canRead { self.error = error.localizedDescription } }
        }
    }
}

struct PersonalSyncStatusView: View {
    @State private var sync = PersonalRecordsCloudSync.shared
    @State private var showLogin = false
    var body: some View {
        List {
            Text(sync.statusText)
            if sync.pendingCount > 0 { Text(String(format: identityText("pending_records", "%d 条待同步"), sync.pendingCount)) }
            if let error = sync.lastError { Text(error).font(.subheadline).foregroundStyle(Theme.textSecondary) }
            ForEach(sync.conflicts) { conflict in
                Section(identityText("sync_conflict", "部分记录需要处理同步冲突")) {
                    Text(conflict.local?.summary["title"]?.string ?? conflict.remote?.summary["title"]?.string ?? "")
                    if let local = conflict.local { PersonalConflictSummary(record: local, label: identityText("local_version", "本机版本")) }
                    if let remote = conflict.remote {
                        if remote.deleted == true { Text(identityText("cloud_deleted", "云端已删除此记录")) }
                        else { PersonalConflictSummary(record: remote, label: identityText("cloud_version", "云端版本")) }
                    }
                    Button(identityText("use_cloud_version", "使用云端版本")) { resolve(conflict, keepLocal: false) }
                    if conflict.local != nil {
                        Button(identityText(conflict.remote?.deleted == true ? "save_copy" : "use_local_version", conflict.remote?.deleted == true ? "另存为新记录" : "使用本机版本")) { resolve(conflict, keepLocal: true) }
                    }
                }
            }
            if !SessionStore.shared.isAuthenticated {
                Button(identityText("login_sync", "登录并同步")) { showLogin = true }
            } else {
                Button(identityText("sync_retry", "重试同步")) { Task { await sync.retryBlockedRecords() } }
            }
        }.navigationTitle(identityText("sync_status", "记录同步")).toolbar(.hidden, for: .tabBar)
            .sheet(isPresented: $showLogin) { AccountLoginSheet() }
    }
    private func resolve(_ conflict: PersonalRecordConflict, keepLocal: Bool) {
        do { try sync.resolveConflict(conflict, keepLocal: keepLocal) } catch { sync.reportFailure(error) }
    }
}

private struct PersonalConflictSummary: View {
    var record: PersonalRecordEnvelope
    var label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(record.participants.map(\.nameSnapshot).joined(separator: " / "))
            if let left = record.summary["leftScore"]?.integer, let right = record.summary["rightScore"]?.integer { Text("\(left) : \(right)") }
            if let note = record.note, !note.isEmpty { Text(note).lineLimit(3) }
        }
    }
}
