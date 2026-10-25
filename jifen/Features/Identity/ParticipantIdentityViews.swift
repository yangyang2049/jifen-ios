import AVKit
import ScoreCore
import SwiftUI

struct ParticipantAssociatedNamesSection: View {
    @State private var store = ParticipantIdentityStore.shared
    @State private var unlinking: ParticipantAlias?
    @State private var error: String?
    @State private var showLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.currentName).foregroundStyle(Theme.textPrimary)
                Text(identityText("self", "我")).font(.caption).foregroundStyle(Theme.accentColor)
                Spacer()
                if store.isGuest { Text(identityText("local", "本机")).font(.caption).foregroundStyle(Theme.textSecondary) }
            }
            .padding(16).commonDataListCardStyle()
            HStack {
                Text(identityText("associated_names", "已关联本人"))
                Spacer()
            }.font(.subheadline).foregroundStyle(Theme.textSecondary)
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
    var initialName: String? = nil

    private struct Candidate: Identifiable {
        var id: String; var name: String; var seats: [(String, PersonalRecordSeat)]
        var recordCount: Int { Set(seats.map(\.0)).count }
    }
    private var candidates: [Candidate] {
        var names: [String: Candidate] = [:]; var order: [String] = []
        for record in records where store.canRead(recordKey: record.id) && record.groupMatchContext == nil {
            for seat in PersonalRecordAdapter.seats(record) {
                let normalized = ParticipantIdentityRules.normalizedName(seat.name)
                guard !normalized.isEmpty else { continue }
                if names[normalized] == nil { names[normalized] = Candidate(id: normalized, name: seat.name, seats: []); order.append(normalized) }
                names[normalized]?.seats.append((record.id, seat))
            }
        }
        if let initialName, !initialName.isEmpty {
            let key = ParticipantIdentityRules.normalizedName(initialName)
            if names[key] == nil { names[key] = Candidate(id: key, name: initialName, seats: []); order.insert(key, at: 0) }
        }
        return order.compactMap { names[$0] }
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
                            ForEach(records.filter { record in candidate.seats.contains { $0.0 == record.id } }.prefix(5)) { record in
                                NavigationLink(record.gameType.displayName + " · " + record.startTime.formatted(date: .numeric, time: .omitted)) {
                                    ScoreboardRecordDetailPage(recordId: record.id)
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
            if candidates.isEmpty { Text(identityText("no_personal_names", "暂无可关联的个人名称")).foregroundStyle(Theme.textSecondary) }
        }
        .scrollContentBackground(.hidden).background(Theme.backgroundColor)
        .navigationTitle(identityText("link_history_title", "关联历史名称"))
        .navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        .onChange(of: store.state.activeLibraryId) { _, _ in dismiss() }
        .onChange(of: SessionStore.shared.user?.id) { _, _ in dismiss() }
        .safeAreaInset(edge: .bottom) {
            Button(identityText("link_to_me", "关联到我")) { confirming = true }
                .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 48)
                .background(selected.isEmpty ? Theme.dialogControlBackground : Theme.accentColor)
                .foregroundStyle(selected.isEmpty ? Theme.textSecondary : Theme.textOnPrimary)
                .clipShape(Capsule()).disabled(selected.isEmpty || proposedCount > 3)
                .padding(.horizontal, Theme.md).padding(.vertical, 10).background(Theme.backgroundColor)
        }
        .task {
            records = ScoreboardRecordManager.shared.loadAllRecords()
            try? store.migrateLegacyIfNeeded(scoreIDs: records.map(\.id), timerIDs: TimerRecordManager.shared.getRecords().map(\.id))
            if let initialName { selected = [ParticipantIdentityRules.normalizedName(initialName)] }
        }
        .confirmationDialog(identityText("link_to_me", "关联到我"), isPresented: $confirming, titleVisibility: .visible) {
            Button(identityText("confirm_link", "确认关联")) {
                do {
                    for candidate in candidates where selected.contains(candidate.id) { _ = try store.link(name: candidate.name, seats: candidate.seats) }
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
        } message: {
            let selectedSeats = candidates.filter { selected.contains($0.id) }.flatMap(\.seats)
            let ambiguous = Dictionary(grouping: selectedSeats, by: { $0.0 }).values.filter { $0.count > 1 }.count
            Text(identityText("link_history_explanation", "保留当时的名称和比分，按选中的名字归入本人记录。")
                + (ambiguous > 0 ? "\n" + String(format: identityText("ambiguous_records", "%d 条记录包含多个本人位置，暂不计入我的记录。"), ambiguous) : ""))
        }
        .alert(identityText("operation_failed", "操作未完成"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(identityText("ok", "好的"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

struct PersonalCloudRecordDetailView: View {
    let record: PersonalRecordEnvelope
    @State private var audioURL: URL?
    @State private var audioError: String?
    @State private var identity = ParticipantIdentityStore.shared
    @State private var cloud = PersonalRecordsCloudSync.shared
    private var canRead: Bool {
        identity.readableLibraryIds.contains(record.libraryId)
            && !cloud.isLocallyDeleted(libraryId: record.libraryId, recordKey: record.recordKey)
    }
    var body: some View {
        Group {
        if canRead { List {
            Text(record.project)
            Text(Date(timeIntervalSince1970: Double(record.playedAt) / 1_000).formatted())
            ForEach(record.participants, id: \.seatKey) { participant in Text(participant.nameSnapshot) }
            if let left = record.summary["leftScore"]?.integer, let right = record.summary["rightScore"]?.integer {
                Text("\(left) : \(right)").font(.title2).monospacedDigit()
            }
            if let duration = record.summary["durationMs"]?.integer {
                Text(Duration.seconds(Double(duration) / 1_000).formatted(.time(pattern: .hourMinuteSecond)))
            }
            if let value = record.summary["players"], case .array(let players) = value {
                ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                    if case .object(let fields) = player {
                        HStack { Text(fields["name"]?.string ?? ""); Spacer(); Text("\(fields["score"]?.integer ?? 0)") }
                    }
                }
            }
            if let note = record.note, !note.isEmpty { Text(note) }
            ForEach(record.assetIds, id: \.self) { id in
                Button(identityText("play_voice", "播放语音备注")) {
                    Task { do { let url = try await cloud.downloadAudio(assetId: id); if canRead { audioURL = url } }
                        catch { audioError = error.localizedDescription } }
                }
            }
            if let audioURL { VideoPlayer(player: AVPlayer(url: audioURL)).frame(height: 70) }
            if let audioError { Text(audioError).foregroundStyle(Theme.textSecondary) }
        } } else { ContentUnavailableView(identityText("record_unavailable", "记录不可用"), systemImage: "doc.questionmark") }
        }.navigationTitle(identityText("record_detail", "记录详情"))
            .toolbar(.hidden, for: .tabBar)
            .onChange(of: canRead) { _, allowed in if !allowed { audioURL = nil; audioError = nil } }
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
