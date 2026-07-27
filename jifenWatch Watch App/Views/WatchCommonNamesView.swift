import LinkCore
import SwiftUI

private struct WatchCommonNameEditorContext: Identifiable {
    let id = UUID()
    let originalName: String?
}

struct WatchCommonNamesView: View {
    @Environment(WatchLinkService.self) private var linkService
    @State private var store = WatchCommonNamesStore.shared
    @State private var selectedType: CommonNameSyncType = .player
    @State private var editorContext: WatchCommonNameEditorContext?
    @State private var editorText = ""
    @State private var pendingDeleteName: String?
    @State private var errorMessage: String?

    private var currentNames: [String] { store.names(for: selectedType) }

    var body: some View {
        List {
            syncCard
                .watchCommonNamesListRow()
            categoryPicker
                .watchCommonNamesListRow()

            if currentNames.isEmpty {
                emptyState
                    .watchCommonNamesListRow()
            } else {
                ForEach(currentNames, id: \.self) { name in
                    nameRow(name)
                        .watchCommonNamesListRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(WatchTheme.background)
        .navigationTitle(NSLocalizedString("watch_common_names_title", value: "常用名称", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorText = ""
                    editorContext = .init(originalName: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(NSLocalizedString("watch_common_names_add", value: "添加名称", comment: ""))
            }
        }
        .sheet(item: $editorContext) { context in
            editorSheet(context)
        }
        .alert(
            NSLocalizedString("watch_common_names_delete_title", value: "删除名称？", comment: ""),
            isPresented: Binding(
                get: { pendingDeleteName != nil },
                set: { if !$0 { pendingDeleteName = nil } }
            )
        ) {
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) {
                pendingDeleteName = nil
            }
            Button(NSLocalizedString("delete", value: "删除", comment: ""), role: .destructive) {
                deletePendingName()
            }
        } message: {
            Text(pendingDeleteName ?? "")
        }
        .alert(
            NSLocalizedString("watch_common_names_error_title", value: "无法保存", comment: ""),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(NSLocalizedString("got_it", value: "知道了", comment: ""), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(syncColor)
                    .frame(width: 8, height: 8)
                Text(syncTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WatchTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if store.pendingCount > 0 {
                    Text("\(store.pendingCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(WatchTheme.accent)
                        .clipShape(Capsule())
                }
            }

            Text(syncDetail)
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.secondaryText)
                .lineLimit(2)

            Button {
                linkService.syncCommonNamesNow()
            } label: {
                Text(NSLocalizedString("watch_common_names_sync_now", value: "立即同步", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(WatchTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(WatchLayout.cardContentPadding)
        .background(WatchTheme.listItemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var categoryPicker: some View {
        HStack(spacing: 6) {
            categoryButton(
                title: NSLocalizedString("watch_common_names_players", value: "选手", comment: ""),
                type: .player
            )
            categoryButton(
                title: NSLocalizedString("watch_common_names_teams", value: "队伍", comment: ""),
                type: .team
            )
        }
    }

    private func categoryButton(title: String, type: CommonNameSyncType) -> some View {
        Button {
            selectedType = type
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selectedType == type ? Color.black : WatchTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(selectedType == type ? WatchTheme.accent : WatchTheme.listItemBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func nameRow(_ name: String) -> some View {
        Button {
            editorText = name
            editorContext = .init(originalName: name)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedType == .team ? "person.2" : "person")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WatchTheme.secondaryText)
                    .frame(width: 20)
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WatchTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WatchTheme.secondaryText)
            }
            .padding(.horizontal, WatchLayout.pillRowHorizontalPadding)
            .frame(height: 48)
            .background(WatchTheme.listItemBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDeleteName = name
            } label: {
                Label(NSLocalizedString("delete", value: "删除", comment: ""), systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedType == .team ? "person.2" : "person")
                .font(.system(size: 24))
                .foregroundStyle(WatchTheme.secondaryText)
            Text(NSLocalizedString("watch_common_names_empty", value: "暂无常用名称", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(WatchTheme.secondaryText)
            Button {
                editorText = ""
                editorContext = .init(originalName: nil)
            } label: {
                Text(NSLocalizedString("watch_common_names_add", value: "添加名称", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private func editorSheet(_ context: WatchCommonNameEditorContext) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    TextField(
                        selectedType == .team
                            ? NSLocalizedString("watch_common_names_team_placeholder", value: "输入队伍名称", comment: "")
                            : NSLocalizedString("watch_common_names_player_placeholder", value: "输入选手名称", comment: ""),
                        text: $editorText
                    )
                    .textInputAutocapitalization(.never)
                    .onChange(of: editorText) { _, value in
                        if value.count > WatchCommonNamesStore.maxNameLength {
                            editorText = String(value.prefix(WatchCommonNamesStore.maxNameLength))
                        }
                    }

                    Text(String(format: NSLocalizedString(
                        "watch_common_names_length_hint",
                        value: "最多 %d 个字符",
                        comment: ""
                    ), WatchCommonNamesStore.maxNameLength))
                    .font(.system(size: 11))
                    .foregroundStyle(WatchTheme.secondaryText)

                    Button {
                        saveEditor(context)
                    } label: {
                        Text(NSLocalizedString("save", value: "保存", comment: ""))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(WatchTheme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            }
            .background(WatchTheme.background)
            .navigationTitle(context.originalName == nil
                ? NSLocalizedString("watch_common_names_add", value: "添加名称", comment: "")
                : NSLocalizedString("watch_common_names_edit", value: "编辑名称", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func saveEditor(_ context: WatchCommonNameEditorContext) {
        do {
            if let originalName = context.originalName {
                _ = try store.updateName(originalName, newName: editorText, type: selectedType)
            } else {
                _ = try store.addName(editorText, type: selectedType)
            }
            editorContext = nil
            linkService.commonNamesDidChange()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    private func deletePendingName() {
        guard let name = pendingDeleteName else { return }
        pendingDeleteName = nil
        do {
            try store.deleteName(name, type: selectedType)
            linkService.commonNamesDidChange()
        } catch {
            errorMessage = localizedError(error)
        }
    }

    private func localizedError(_ error: Error) -> String {
        switch error as? WatchCommonNamesError {
        case .emptyName:
            return NSLocalizedString("watch_common_names_error_empty", value: "名称不能为空", comment: "")
        case .duplicateName, .presetName:
            return NSLocalizedString("watch_common_names_error_duplicate", value: "该名称已存在或属于默认名称", comment: "")
        case .nameNotFound:
            return NSLocalizedString("watch_common_names_error_missing", value: "原名称已不存在，请刷新后重试", comment: "")
        case nil:
            return NSLocalizedString("watch_common_names_error_generic", value: "保存失败，请重试", comment: "")
        }
    }

    private var syncTitle: String {
        if store.hasUnresolvedConflict {
            return NSLocalizedString("watch_common_names_sync_conflict", value: "部分修改未同步", comment: "")
        }
        if store.pendingCount > 0 {
            return NSLocalizedString("watch_common_names_sync_pending", value: "等待同步", comment: "")
        }
        if linkService.commonNamesSyncFailed {
            return NSLocalizedString("watch_common_names_sync_unavailable", value: "手机暂不可用", comment: "")
        }
        return NSLocalizedString("watch_common_names_sync_done", value: "已同步", comment: "")
    }

    private var syncDetail: String {
        if store.pendingCount > 0 {
            return String(format: NSLocalizedString(
                "watch_common_names_pending_count",
                value: "%d 项修改将在连接手机后自动同步",
                comment: ""
            ), store.pendingCount)
        }
        guard store.lastSyncAtEpochMilliseconds > 0 else {
            return NSLocalizedString("watch_common_names_never_synced", value: "尚未与手机同步", comment: "")
        }
        let date = Date(timeIntervalSince1970: TimeInterval(store.lastSyncAtEpochMilliseconds) / 1_000)
        return String(format: NSLocalizedString(
            "watch_common_names_last_sync",
            value: "最近同步 %@",
            comment: ""
        ), date.formatted(date: .omitted, time: .shortened))
    }

    private var syncColor: Color {
        if store.hasUnresolvedConflict || linkService.commonNamesSyncFailed { return .orange }
        if store.pendingCount > 0 { return .yellow }
        return WatchTheme.accent
    }
}

private extension View {
    func watchCommonNamesListRow() -> some View {
        listRowInsets(EdgeInsets(
            top: 4,
            leading: WatchLayout.pageHorizontalPadding,
            bottom: 4,
            trailing: WatchLayout.pageHorizontalPadding
        ))
        .listRowBackground(Color.clear)
    }
}
