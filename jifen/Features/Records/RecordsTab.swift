//
//  RecordsTab.swift
//  jifen
//
//  记录 Tab：全部/计分/计时子 Tab + 搜索 + 按日期分组，对齐鸿蒙 RecentActivityTab。
//

import PersistenceCore
import ScoreCore
import SwiftUI
import UIKit

struct RecordsTab: View {
    var personalOnly = false
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.scenePhase) private var scenePhase
    @State private var scoreboardVM = ScoreboardRecordsViewModel.shared
    @StateObject private var timerVM = TimerRecordsViewModel.shared

    @State private var currentTab: Int = 0 // 0: 全部, 1: 计分, 2: 计时
    @State private var draftRecordType = 0
    @State private var identity = ParticipantIdentityStore.shared
    @State private var privateCloud = PersonalRecordsCloudSync.shared
    @State private var groupRecords = PersonalGroupRecords.shared
    @State private var completedCloudQueryKey: String?
    @State private var cloudQueryError: String?
    @State private var searchText: String = ""
    @State private var showClearConfirm = false
    @State private var showBatchDeleteConfirm = false
    @State private var isDeletingSelection = false
    @State private var isEditMode = false
    @State private var recordSelection = RecordsTabSelectionState()
    @State private var selectedTimeFilter: RecordsTimeFilter = .all
    @State private var selectedProjectFilter: RecordsProjectFilter? = nil
    @State private var draftTimeFilter: RecordsTimeFilter = .all
    @State private var draftProjectFilter: RecordsProjectFilter? = nil
    @State private var showFilterSheet = false

    private enum RecordsTimeFilter: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: return NSLocalizedString("today", value: "今天", comment: "")
            case .week: return NSLocalizedString("this_week", value: "本周", comment: "")
            case .month: return NSLocalizedString("this_month", value: "本月", comment: "")
            case .all: return NSLocalizedString("all", value: "全部", comment: "")
            }
        }
    }

    @ViewBuilder var body: some View {
        if personalOnly { recordsContent.toolbar(.hidden, for: .tabBar) }
        else { NavigationStack { recordsContent } }
    }

    /// 导航栈由 Records Tab 自己持有（与 Home/Score/Timer/Me 一致），
    /// MainTabView 不再外层包栈，避免双 NavigationStack。
    private var recordsContent: some View {
        VStack(spacing: 0) {
            if !isEditMode {
                if personalOnly {
                    if !isInitiallyLoading { personalSummary }
                    if groupRecords.error != nil {
                        Button(identityText("group_records_unavailable", "部分小组记录未能加载")) { Task { await groupRecords.refresh() } }
                            .font(.caption).foregroundStyle(Theme.textSecondary).padding(.bottom, 8)
                    }
                }
                else {
                    RecordsPersonalEntry(hasSearchQuery: !searchText.isEmpty)
                }
                if hasActiveFilters { activeFilterRow }
            }
            if isEditMode {
                batchEditBar
            }
            content
        }
        .frame(maxWidth: usesPadLayout ? 920 : .infinity, maxHeight: .infinity)
        .expandedPhonePageContent(existingHorizontalInset: Theme.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor)
        .navigationTitle(personalOnly ? identityText("my_records", "我的记录") : NSLocalizedString("tab_records", comment: "Records"))
        .navigationBarTitleDisplayMode(.inline)
        .systemSearchable(
            text: $searchText,
            prompt: NSLocalizedString("search_team_or_game", value: "搜索队伍或项目", comment: "Search placeholder"),
            isEnabled: !personalOnly && !isEditMode
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditMode {
                    Button(NSLocalizedString("done", comment: "Done")) {
                        exitEditMode()
                    }
                    .foregroundColor(Theme.accentColor)
                } else {
                    Menu {
                        Button {
                            draftTimeFilter = selectedTimeFilter
                            draftProjectFilter = selectedProjectFilter
                            draftRecordType = currentTab
                            showFilterSheet = true
                        } label: {
                            Label(NSLocalizedString("filter", value: "筛选", comment: ""), systemImage: "line.3.horizontal.decrease.circle")
                        }
                        Button {
                            recordSelection.clear()
                            isEditMode = true
                            dismissSearch()
                            AppAnalytics.track(.recordAction, parameters: [
                                .actionName: .string("enter_edit"),
                                .contentType: .string("records")
                            ])
                        } label: {
                            Label(NSLocalizedString("edit", comment: "Edit"), systemImage: "pencil")
                        }
                        .disabled(!filteredRecords().contains(where: \.isEditable))
                        // Ordinary syncing is automatic; conflicts and failed uploads still need a recovery entry.
                        if !privateCloud.conflicts.isEmpty || privateCloud.lastError != nil || privateCloud.blockedRecordCount > 0 {
                            NavigationLink {
                                PersonalSyncStatusView()
                            } label: {
                                Label(privateCloud.conflicts.isEmpty
                                      ? identityText("sync_failed", "同步未完成")
                                      : identityText("sync_conflict", "部分记录需要处理同步冲突"), systemImage: "exclamationmark.triangle")
                            }
                            .accessibilityIdentifier("records_sync_conflicts")
                        }
                        if !personalOnly { Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label {
                                Text(NSLocalizedString("clear_all_records", comment: "Clear all"))
                            } icon: {
                                destructiveTrashMenuIcon
                            }
                        }
                        .disabled(scoreboardVM.records.isEmpty && timerVM.records.isEmpty && privateCloud.remoteRecords.isEmpty)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityIdentifier("records_more")
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            recordsFilterSheet
        }
        .onAppear {
            scoreboardVM.ensureLoaded()
            timerVM.ensureLoaded()
            migrateLoadedIdentityRecords()
            privateCloud.schedule()
        }
        .onChange(of: scoreboardVM.hasLoaded) { _, _ in migrateLoadedIdentityRecords() }
        .onChange(of: timerVM.hasLoaded) { _, _ in migrateLoadedIdentityRecords() }
        .onChange(of: scenePhase) { _, value in if value == .active { privateCloud.schedule() } }
        .onChange(of: privateCloud.phase) { _, phase in
            if phase != "syncing", cloudQueryError != nil {
                Task { await refreshCloudQuery() }
            }
        }
        .task(id: cloudQueryKey) { await refreshCloudQuery() }
        .task(id: personalOnly ? SessionStore.shared.user?.id : nil) {
            if personalOnly { await groupRecords.refresh() }
        }
        .refreshable {
            await privateCloud.synchronizeNow()
            await refreshCloudQuery()
            if personalOnly { await groupRecords.refresh(force: true) }
        }
        .onChange(of: identity.state.activeAccountId) { _, _ in
            clearFilters(); searchText = ""; completedCloudQueryKey = nil; cloudQueryError = nil; exitEditMode()
        }
        .onDisappear {
            exitEditMode()
        }
        .onChange(of: searchText) { _, _ in
            reconcileSelectionWithVisibleRecords()
        }
        .onChange(of: selectedTimeFilter) { _, _ in
            reconcileSelectionWithVisibleRecords()
        }
        .onChange(of: selectedProjectFilter) { _, _ in
            reconcileSelectionWithVisibleRecords()
        }
        .onChange(of: scoreboardVM.records.map(\.id)) { _, _ in
            reconcileSelectionWithVisibleRecords()
        }
        .onChange(of: timerVM.records.map(\.id)) { _, _ in
            reconcileSelectionWithVisibleRecords()
        }
        .alert(NSLocalizedString("clear_all_records", comment: ""), isPresented: $showClearConfirm) {
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("clear_all_records", comment: ""), role: .destructive) {
                clearRecordTabRecords()
            }
        } message: {
            Text(identity.isGuest ? NSLocalizedString("clear_records_tab_message", comment: "")
                 : identityText("records_delete_synced_message", "This deletes score and timer records in the list, including records synced from other devices. Deletions sync to your other devices and cannot be undone. Saved names, places, bookings, and original group records are kept."))
        }
        .alert(
            NSLocalizedString("delete", value: "删除", comment: ""),
            isPresented: $showBatchDeleteConfirm
        ) {
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("delete", value: "删除", comment: ""), role: .destructive) {
                deleteSelectedRecords()
            }
        } message: {
            Text(batchDeleteConfirmationMessage)
        }
        .tint(Theme.accentColor)
    }

    private var usesPadLayout: Bool {
        Theme.usesPadLayout
    }

    private func migrateLoadedIdentityRecords() {
        guard scoreboardVM.hasLoaded, timerVM.hasLoaded else { return }
        try? identity.migrateLegacyIfNeeded(scoreIDs: scoreboardVM.records.map(\.id), timerIDs: timerVM.records.map(\.id))
    }

    /// Native menus inherit the app's green tint for template symbols, even on
    /// destructive actions. Preserve the system destructive red in the image so
    /// the trash icon matches the menu item's destructive text color.
    private var destructiveTrashMenuIcon: Image {
        guard let image = UIImage(systemName: "trash")?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal) else {
            return Image(systemName: "trash")
        }
        return Image(uiImage: image)
    }

    private var hasActiveFilters: Bool {
        (!personalOnly && currentTab != 0) || selectedTimeFilter != .all || selectedProjectFilter != nil
    }

    private var filterSummary: String {
        [!personalOnly && currentTab != 0 ? NSLocalizedString(currentTab == 1 ? "scoreboard" : "timer", comment: "") : nil,
         selectedTimeFilter != .all ? selectedTimeFilter.title : nil, selectedProjectFilter?.title]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var activeFilterRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                draftRecordType = currentTab; draftTimeFilter = selectedTimeFilter
                draftProjectFilter = selectedProjectFilter; showFilterSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(filterSummary).multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down").font(.caption2)
                }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
                .accessibilityIdentifier("records_active_conditions")
            Button(action: clearFilters) {
                Text(identityText("clear_filters", "清除筛选"))
                    .font(.subheadline).fixedSize(horizontal: true, vertical: false).frame(minHeight: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("records_clear_filters")
        }.foregroundStyle(Theme.accentColor).padding(.horizontal, Theme.pageHorizontalInset)
    }

    private func clearFilters() { currentTab = 0; selectedTimeFilter = .all; selectedProjectFilter = nil; recordSelection.clear() }

    private var personalSummary: some View {
        let personal = filteredRecords()
        let projectCount = Set(personal.map { item -> String in
            switch item {
            case .scoreboard(let record): return record.gameType.rawValue
            case .timer(let record): return record.gameType.rawValue
            case .cloud(let record): return record.project
            }
        }).count
        return HStack {
            VStack { Text("\(personal.count)").font(.title2); Text(identityText("records_count", "记录")).font(.caption) }
            Spacer()
            VStack { Text("\(projectCount)").font(.title2); Text(identityText("projects_count", "项目")).font(.caption) }
        }.padding(.horizontal, 40).padding(.vertical, 16).background(Theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius)).padding(.horizontal, Theme.pageHorizontalInset)
    }

    private var cloudQueryKey: String {
        "\(personalOnly)-\(currentTab)-\(selectedTimeFilter.rawValue)-\(selectedProjectFilter?.id ?? "")-\(searchText)-\(identity.state.activeAccountId ?? "guest")-\(identity.state.activeLibraryId)"
    }

    private func refreshCloudQuery() async {
        let queryKey = cloudQueryKey
        completedCloudQueryKey = nil
        cloudQueryError = nil
        defer {
            if !Task.isCancelled && cloudQueryKey == queryKey { completedCloudQueryKey = queryKey }
        }
        guard !identity.isGuest else { return }
        // The task is cancelled when search or filter inputs change.
        // Avoid paging through the cloud library for every keystroke.
        do { if !searchText.isEmpty { try await Task.sleep(for: .milliseconds(300)) } }
        catch { return }
        let calendar = Calendar.current
        let from: Date?
        switch selectedTimeFilter {
        case .all: from = nil
        case .today: from = calendar.startOfDay(for: Date())
        case .week: from = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
        case .month: from = calendar.dateInterval(of: .month, for: Date())?.start
        }
        do {
            let projects: [String]?
            if let selectedProjectFilter, case .family = selectedProjectFilter.scope {
                projects = Array(Set([selectedProjectFilter.gameType.canonicalScoreboardIdentifier]
                    + RecordsProjectFilter.allOptions.filter { $0.gameType == selectedProjectFilter.gameType }.compactMap { $0.scoreCoreGameType?.rawValue }))
            } else { projects = nil }
            _ = try await privateCloud.query(scope: personalOnly ? "mine" : "all", kind: personalOnly || currentTab == 1 ? "score" : currentTab == 2 ? "timer" : nil,
                project: selectedProjectFilter?.scoreCoreGameType?.rawValue ?? selectedProjectFilter?.gameType.canonicalScoreboardIdentifier, projects: projects,
                from: from.map { Int64($0.timeIntervalSince1970 * 1_000) }, to: nil, search: searchText)
        } catch {
            if !Task.isCancelled && cloudQueryKey == queryKey { cloudQueryError = error.localizedDescription }
        }
    }

    private func cloudRowContent(_ record: PersonalRecordEnvelope) -> some View {
        RecordListRow(record: RecordListPresentation(record), isEditMode: isEditMode)
    }

    private var recordsFilterSheet: some View {
        NavigationStack {
            Form {
                if !personalOnly {
                    Section(identityText("record_type", "记录类型")) {
                        Picker(identityText("record_type", "记录类型"), selection: $draftRecordType) {
                            Text(NSLocalizedString("all", value: "全部", comment: "")).tag(0)
                            Text(NSLocalizedString("scoreboard", value: "计分", comment: "")).tag(1)
                            Text(NSLocalizedString("timer", value: "计时", comment: "")).tag(2)
                        }.pickerStyle(.segmented)
                    }
                }
                Section(NSLocalizedString("time_filter", value: "时间", comment: "")) {
                    ForEach(RecordsTimeFilter.allCases) { filter in
                        Button {
                            draftTimeFilter = filter
                        } label: {
                            HStack {
                                Text(filter.title)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if draftTimeFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accentColor)
                                }
                            }
                        }
                    }
                }
                Section(NSLocalizedString("game_type_filter", value: "项目", comment: "")) {
                    Button {
                        draftProjectFilter = nil
                    } label: {
                        HStack {
                            Text(NSLocalizedString("all", value: "全部", comment: ""))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if draftProjectFilter == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accentColor)
                            }
                        }
                    }
                    ForEach(RecordsProjectFilter.allOptions) { filter in
                        Button {
                            draftProjectFilter = filter
                        } label: {
                            HStack {
                                AppCatalogIcon(gameType: filter.gameType, size: 18)
                                Text(filter.title)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if draftProjectFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accentColor)
                                }
                            }
                        }
                        .accessibilityIdentifier("records_project_filter_\(filter.id)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.dialogSurfaceBackground)
            .navigationTitle(NSLocalizedString("filter", value: "筛选", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalCloseButton {
                        showFilterSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("apply", value: "应用", comment: "")) {
                        let appliesReset = draftTimeFilter == .all
                            && draftProjectFilter == nil
                            && (selectedTimeFilter != .all || selectedProjectFilter != nil)
                        selectedTimeFilter = draftTimeFilter
                        selectedProjectFilter = draftProjectFilter
                        currentTab = personalOnly ? 1 : draftRecordType
                        if appliesReset {
                            AppAnalytics.track(.recordAction, parameters: [
                                .actionName: .string("reset_filter"),
                                .contentType: .string("records")
                            ])
                        }
                        var parameters: AnalyticsParameters = [
                            .contentType: .string("records"),
                            .settingName: .string("time_range"),
                            .settingValue: .string(draftTimeFilter.rawValue)
                        ]
                        if let gameType = draftProjectFilter?.gameType {
                            parameters[.gameType] = .string(gameType.analyticsIdentifier)
                        }
                        parameters[.actionName] = .string("apply_filter")
                        AppAnalytics.track(.recordAction, parameters: parameters)
                        showFilterSheet = false
                    }
                    .accessibilityIdentifier("records_apply_filter")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("reset", value: "重置", comment: "")) {
                        draftTimeFilter = .all
                        draftProjectFilter = nil
                        draftRecordType = 0
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var batchEditBar: some View {
        let visibleIDs = filteredRecords().filter(\.isEditable).map(\.selectionID)
        return CommonDataBatchEditBar(
            allSelected: recordSelection.containsAll(visibleIDs),
            selectedCount: recordSelection.count,
            onToggleSelectAll: {
                recordSelection.toggleAll(visibleIDs)
            },
            onDelete: {
                reconcileSelectionWithVisibleRecords()
                guard !recordSelection.isEmpty else { return }
                showBatchDeleteConfirm = true
            }
        )
        .disabled(isDeletingSelection || visibleIDs.isEmpty)
        .accessibilityIdentifier("records_batch_edit_bar")
    }

    @ViewBuilder
    private var content: some View {
        let filtered = filteredRecords()
        if !filtered.isEmpty {
            recordsList(records: filtered)
        } else if isInitiallyLoading {
            loadingView
        } else if let cloudQueryError {
            VStack(spacing: Theme.md) {
                Text(identityText("sync_failed", "同步未完成")).foregroundStyle(Theme.textSecondary)
                Text(cloudQueryError).font(.caption).foregroundStyle(Theme.textSecondary)
                Button(identityText("sync_retry", "重试同步")) { Task { await refreshCloudQuery() } }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyState
        }
    }

    private var isInitiallyLoading: Bool {
        filteredRecords().isEmpty && (!scoreboardVM.hasLoaded || (!personalOnly && !timerVM.hasLoaded)
            || (!identity.isGuest && completedCloudQueryKey != cloudQueryKey)
            || (personalOnly && groupRecords.isLoading))
    }

    private func filteredRecords() -> [RecordsTabRecordItem] {
        var items = RecordListSource.visibleRecords(
            scoreboard: personalOnly || currentTab != 2 ? scoreboardVM.records : [],
            timers: !personalOnly && currentTab != 1 ? timerVM.records : [],
            cloudRecords: privateCloud.remoteRecords.filter {
                personalOnly || currentTab == 1 ? $0.kind == "score" : currentTab == 2 ? $0.kind == "timer" : true
            }, identity: identity, cloud: privateCloud
        )
        if personalOnly {
            items = items.filter { item in
                switch item {
                case .scoreboard(let record): return PersonalRecordAdapter.isMine(record, identity: identity)
                case .cloud(let record): return PersonalRecordAdapter.isMine(record, identity: identity)
                case .timer: return false
                }
            }
        }
        if personalOnly, !identity.isGuest {
            let localGames = Set(items.compactMap { item -> String? in
                switch item {
                case .scoreboard(let summary): return summary.groupGameID
                case .cloud(let record): return record.summary["groupGameId"]?.string
                case .timer: return nil
                }
            }.filter { !$0.isEmpty })
            items += groupRecords.visibleRows.filter { !localGames.contains($0.origin.sessionId ?? "") }.map(RecordsTabRecordItem.cloud)
        }
        items.sort { $0.timestamp > $1.timestamp }
        items = items.filter { matchesTimeFilter($0) }
        if let selectedProjectFilter {
            items = items.filter { matchesProjectFilter($0, selectedProjectFilter) }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            items = items.filter { item in
                switch item {
                case .scoreboard(let r):
                    return r.displayMatchTitle.lowercased().contains(q) || r.competitionDisplayName.lowercased().contains(q)
                case .timer(let r):
                    return r.gameType.displayName.lowercased().contains(q)
                case .cloud(let r):
                    return ([r.project, r.summary["title"]?.string ?? ""] + r.participants.map(\.nameSnapshot)).joined(separator: " ").lowercased().contains(q)
                }
            }
        }
        return items
    }

    private func matchesTimeFilter(_ item: RecordsTabRecordItem) -> Bool {
        let date = Date(timeIntervalSince1970: item.timestamp)
        let cal = Calendar.current
        switch selectedTimeFilter {
        case .all:
            return true
        case .today:
            return cal.isDateInToday(date)
        case .week:
            guard let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
                return true
            }
            return date >= start
        case .month:
            let comps = cal.dateComponents([.year, .month], from: Date())
            guard let start = cal.date(from: comps) else { return true }
            return date >= start
        }
    }

    private func matchesProjectFilter(_ item: RecordsTabRecordItem, _ filter: RecordsProjectFilter) -> Bool {
        switch item {
        case .scoreboard(let r):
            return filter.matches(scoreboard: r)
        case .timer(let r):
            return filter.matches(timerGameType: r.gameType)
        case .cloud(let r):
            if let exact = filter.scoreCoreGameType { return r.project == exact.rawValue }
            return r.project == filter.gameType.canonicalScoreboardIdentifier
                || ScoreCore.GameType(rawValue: r.project).map { GameType(scoreCoreGameType: $0) == filter.gameType } == true
        }
    }

    private func groupedByDate(_ items: [RecordsTabRecordItem]) -> [(date: String, displayDate: String, records: [RecordsTabRecordItem])] {
        let grouped = Dictionary(grouping: items) { $0.dateString }
        return grouped.map { date, recs in
            (date: date, displayDate: formatDate(date), records: recs.sorted { $0.timestamp > $1.timestamp })
        }.sorted { $0.date > $1.date }
    }

    private func recordsList(records: [RecordsTabRecordItem]) -> some View {
        let groups = groupedByDate(records)
        return ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groups, id: \.date) { group in
                    Section {
                        // 每个日期一张大卡片，行间沿用分割线（对齐安卓卡片式列表）。
                        VStack(spacing: 0) {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { index, item in
                                recordRow(item: item, isEditMode: isEditMode)
                                    .padding(.horizontal, Theme.cardPadding)
                                if index < group.records.count - 1 {
                                    Divider()
                                        .overlay(Theme.homeOverlayBorder)
                                        .padding(.leading, Theme.cardPadding + 56)
                                }
                            }
                        }
                        .background(Theme.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .padding(.bottom, Theme.md)
                    } header: {
                        sectionHeader(displayDate: group.displayDate, count: group.records.count)
                    }
                }
            }
            .padding(.horizontal, Theme.pageHorizontalInset)
            .padding(.bottom, Theme.tabContentBottomPadding)
        }
    }

    private func sectionHeader(displayDate: String, count: Int) -> some View {
        HStack {
            Text(displayDate)
                .font(.system(size: Theme.fontBody1, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(String.localizedStringWithFormat(
                NSLocalizedString("match_count", value: "%d 场", comment: "Match count"),
                count
            ))
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.backgroundColor)
    }

    @ViewBuilder
    private func recordRow(item: RecordsTabRecordItem, isEditMode: Bool) -> some View {
        if case .cloud(let record) = item, record.origin.sourceSystem == "group",
           let result = try? JSONDecoder().decode(GroupResult.self, from: JSONEncoder().encode(record.nativePayload)) {
            NavigationLink { GroupResultDetailView(initial: result) } label: { cloudRowContent(record) }.buttonStyle(.plain)
        } else if isEditMode {
            let selectionID = item.selectionID
            Button {
                recordSelection.toggle(selectionID)
            } label: {
                HStack(spacing: Theme.sm) {
                    Image(systemName: recordSelection.contains(selectionID) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(recordSelection.contains(selectionID) ? Theme.accentColor : Theme.textSecondary)
                        .frame(width: 28, height: 44)
                    switch item {
                    case .scoreboard(let record):
                        scoreboardRowContent(record)
                    case .timer(let record):
                        timerRowContent(record)
                    case .cloud(let record):
                        cloudRowContent(record)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("record_selection_\(selectionID.accessibilityIdentifier)")
            .accessibilityValue(recordSelection.contains(selectionID) ? "selected" : "not selected")
        } else {
            switch item {
            case .scoreboard(let record):
                NavigationLink(destination: ScoreboardRecordDetailPage(recordId: record.id)) {
                    scoreboardRowContent(record)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    AppAnalytics.trackContentSelection(
                        contentType: "scoreboard_record",
                        itemID: record.gameType.analyticsIdentifier,
                        entryPoint: .recordsTab
                    )
                })
                .accessibilityIdentifier("record_row_\(record.gameType.canonicalScoreboardIdentifier)")
            case .timer(let record):
                NavigationLink(destination: TimerRecordDetailPage(recordId: record.id)) {
                    timerRowContent(record)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    AppAnalytics.trackContentSelection(
                        contentType: "timer_record",
                        itemID: record.gameType.analyticsIdentifier,
                        entryPoint: .recordsTab
                    )
                })
            case .cloud(let record):
                NavigationLink { PersonalCloudRecordDetailView(record: record) } label: { cloudRowContent(record) }.buttonStyle(.plain)
            }
        }
    }

    private func scoreboardRowContent(_ record: ScoreboardRecordSummary) -> some View {
        RecordListRow(record: RecordListPresentation(record), isEditMode: isEditMode)
            .accessibilityIdentifier("record_row_\(record.gameType.canonicalScoreboardIdentifier)")
    }

    private func timerRowContent(_ record: GameRecordSummary) -> some View {
        RecordListRow(record: RecordListPresentation(record), isEditMode: isEditMode)
    }

    private func exitEditMode() {
        isEditMode = false
        recordSelection.clear()
        showBatchDeleteConfirm = false
    }

    private func reconcileSelectionWithVisibleRecords() {
        guard isEditMode else {
            recordSelection.clear()
            return
        }
        recordSelection.reconcile(with: filteredRecords().filter(\.isEditable).map(\.selectionID))
    }

    private var batchDeleteConfirmationMessage: String {
        let selected = filteredRecords().filter { recordSelection.contains($0.selectionID) }
        let scoreCount = selected.filter { item in
            switch item {
            case .scoreboard: return true
            case .timer: return false
            case .cloud(let record): return record.kind == "score"
            }
        }.count
        let timerCount = selected.count - scoreCount
        let message = String(
            format: NSLocalizedString(
                "records_batch_delete_confirm",
                value: "确认删除选中的 %d 条记录（计分 %d 条、计时 %d 条）？此操作无法撤销。",
                comment: "Batch delete score and timer records"
            ),
            selected.count,
            scoreCount,
            timerCount
        )
        return identity.isGuest ? message : message + "\n\n" + identityText("records_delete_sync_warning", "Deletions sync to your other devices and cannot be undone.")
    }

    private func deleteSelectedRecords() {
        reconcileSelectionWithVisibleRecords()
        guard !recordSelection.isEmpty, !isDeletingSelection else { return }
        let scoreboardIDs = recordSelection.scoreboardRecordIDs
        let timerIDs = recordSelection.timerRecordIDs
        let selectedCount = recordSelection.count
        var failedSelections: Set<RecordsTabRecordSelectionID> = []
        var cloudDeletions: [(recordKey: String, libraryId: String)] = []

        isDeletingSelection = true
        defer { isDeletingSelection = false }

        for id in scoreboardIDs {
            if ScoreboardRecordsViewModel.shared.deleteRecord(id) {
                cloudDeletions.append((id, identity.libraryId(for: id)))
            } else { failedSelections.insert(.scoreboard(id)) }
        }
        for id in timerIDs {
            if TimerRecordsViewModel.shared.deleteRecord(id) {
                cloudDeletions.append((id, identity.libraryId(for: id)))
            } else { failedSelections.insert(.timer(id)) }
        }
        for selection in recordSelection.selected {
            if case .cloud(let library, let record) = selection { cloudDeletions.append((record, library)) }
        }
        privateCloud.markDeleted(records: cloudDeletions)

        recordSelection.replace(with: failedSelections)
        if failedSelections.isEmpty {
            recordSelection.clear()
        } else {
            reconcileSelectionWithVisibleRecords()
        }

        AppAnalytics.track(.recordAction, parameters: [
            .actionName: .string("delete_batch"),
            .contentType: .string("records_batch"),
            .result: .string(failedSelections.isEmpty ? AnalyticsResult.success.rawValue : AnalyticsResult.failed.rawValue),
            .settingValue: .int(selectedCount)
        ])
    }

    private func formatDate(_ dateString: String) -> String {
        let today = dateString == todayString()
        let yesterday = dateString == yesterdayString()
        if today { return NSLocalizedString("today", comment: "Today") }
        if yesterday { return NSLocalizedString("yesterday", comment: "Yesterday") }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        let year = Calendar.current.component(.year, from: Date())
        let recordYear = Calendar.current.component(.year, from: date)
        if recordYear == year {
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: date)
        }
        return dateString
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func yesterdayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let y = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return "" }
        return f.string(from: y)
    }

    /// Clears only the score and timer data surfaced by the Records tab.
    /// Common names, common places, and booking records belong to other features.
    private func clearRecordTabRecords() {
        var cloudDeletions: [(recordKey: String, libraryId: String)] = []
        for record in ScoreboardRecordManager.shared.loadAllRecords() where identity.canRead(recordKey: record.id) {
            if ScoreboardRecordManager.shared.deleteRecord(record.id) {
                cloudDeletions.append((record.id, identity.libraryId(for: record.id)))
            }
        }
        for record in TimerRecordManager.shared.getRecords() where identity.canRead(recordKey: record.id) {
            if TimerRecordManager.shared.deleteRecord(record.id) {
                cloudDeletions.append((record.id, identity.libraryId(for: record.id)))
            }
        }
        cloudDeletions += privateCloud.remoteRecords.filter { identity.readableLibraryIds.contains($0.libraryId) }
            .map { ($0.recordKey, $0.libraryId) }
        privateCloud.markDeleted(records: cloudDeletions)
        scoreboardVM.refreshRecordsImmediately()
        timerVM.loadFromStorage()
        exitEditMode()
    }

    private var loadingView: some View {
        VStack(spacing: Theme.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accentColor))
                .scaleEffect(1.2)
            Text(NSLocalizedString("loading", comment: "Loading"))
                .font(.system(size: Theme.fontBody2))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.lg) {
            EmptyStateCourtIcon(size: 56)
            Text(hasActiveFilters ? identityText("no_filter_results", "没有符合筛选条件的记录") : NSLocalizedString("home_no_records", comment: "No recent records"))
                .font(.system(size: Theme.fontBody1, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if hasActiveFilters { Button(identityText("clear_filters", "清除筛选"), action: clearFilters).foregroundStyle(Theme.accentColor) }
            if personalOnly && !hasActiveFilters {
                NavigationLink(identityText("link_history", "关联用过的名称")) { HistoricalParticipantNamesView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecordsProjectFilter: Identifiable, Hashable {
    enum Scope: Hashable {
        case family
        case exact(ScoreCore.GameType)
    }

    let gameType: GameType
    let scope: Scope

    var scoreCoreGameType: ScoreCore.GameType? {
        guard case .exact(let gameType) = scope else { return nil }
        return gameType
    }
    var id: String {
        switch scope {
        case .family: "family:\(gameType.rawValue)"
        case .exact(let gameType): "exact:\(gameType.rawValue)"
        }
    }
    var icon: String { gameType.icon }
    var title: String {
        switch scope {
        case .family:
            return "\(gameType.displayName) · \(NSLocalizedString("all", value: "全部", comment: ""))"
        case .exact(let gameType):
            return gameType.scoreboardDisplayName
        }
    }

    func matches(scoreboard record: ScoreboardRecordSummary) -> Bool {
        switch scope {
        case .family:
            return record.gameType == gameType
        case .exact(let gameType):
            return record.resolvedScoreCoreGameType == gameType
        }
    }

    func matches(timerGameType: GameType) -> Bool {
        if case .family = scope { return timerGameType == gameType }
        return false
    }

    func matches(scoreCoreGameType: ScoreCore.GameType) -> Bool {
        switch scope {
        case .family:
            return GameType(scoreCoreGameType: scoreCoreGameType) == gameType
        case .exact(let gameType):
            return scoreCoreGameType == gameType
        }
    }

    private static let catalogRecordTypes: [GameType] = {
        let scoreboardTypes = GameCatalog.scoreboardItems.map(\.gameType)
        let timerTypes = GameCatalog.timerBoardGameItems.compactMap(\.mappedGameType)
        return scoreboardTypes + timerTypes
    }()

    static let allOptions: [Self] = catalogRecordTypes.flatMap { type -> [Self] in
        switch type {
        case .pingpong:
            return [.init(gameType: type, scope: .family), .init(gameType: type, scope: .exact(.pingpong)), .init(gameType: type, scope: .exact(.pingpongDoubles))]
        case .badminton:
            return [.init(gameType: type, scope: .family), .init(gameType: type, scope: .exact(.badminton)), .init(gameType: type, scope: .exact(.badmintonDoubles))]
        case .tennis:
            return [.init(gameType: type, scope: .family), .init(gameType: type, scope: .exact(.tennis)), .init(gameType: type, scope: .exact(.tennisDoubles))]
        case .pickleball:
            return [.init(gameType: type, scope: .family), .init(gameType: type, scope: .exact(.pickleball)), .init(gameType: type, scope: .exact(.pickleballDoubles))]
        case .foosball:
            return [.init(gameType: type, scope: .family), .init(gameType: type, scope: .exact(.foosball)), .init(gameType: type, scope: .exact(.foosballDoubles))]
        default:
            return [.init(gameType: type, scope: .family)]
        }
    }
}

/// Read search state below `.searchable`, where SwiftUI supplies the active state.
private struct RecordsPersonalEntry: View {
    @Environment(\.isSearching) private var isSearching
    let hasSearchQuery: Bool

    var body: some View {
        if !isSearching && !hasSearchQuery {
            NavigationLink {
                RecordsTab(personalOnly: true)
            } label: {
                HStack {
                    Label(identityText("my_records", "我的记录"), systemImage: "person.crop.circle")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .padding(16)
                .background(Theme.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.pageHorizontalInset)
            .padding(.bottom, 8)
            .accessibilityIdentifier("personal_records_entry")
        }
    }
}

enum RecordsTabRecordSelectionID: Hashable {
    case scoreboard(String)
    case timer(String)
    case cloud(String, String)

    var recordID: String {
        switch self {
        case .scoreboard(let id), .timer(let id): id
        case .cloud(_, let id): id
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .scoreboard(let id): "scoreboard_\(id)"
        case .timer(let id): "timer_\(id)"
        case .cloud(let library, let id): "cloud_\(library)_\(id)"
        }
    }
}

struct RecordsTabSelectionState: Equatable {
    private(set) var selected: Set<RecordsTabRecordSelectionID> = []

    var count: Int { selected.count }
    var isEmpty: Bool { selected.isEmpty }

    var scoreboardRecordIDs: [String] {
        selected.compactMap { id in
            guard case .scoreboard(let recordID) = id else { return nil }
            return recordID
        }.sorted()
    }

    var timerRecordIDs: [String] {
        selected.compactMap { id in
            guard case .timer(let recordID) = id else { return nil }
            return recordID
        }.sorted()
    }

    func contains(_ id: RecordsTabRecordSelectionID) -> Bool {
        selected.contains(id)
    }

    func containsAll(_ visibleIDs: [RecordsTabRecordSelectionID]) -> Bool {
        let visible = Set(visibleIDs)
        return !visible.isEmpty && visible.isSubset(of: selected)
    }

    mutating func toggle(_ id: RecordsTabRecordSelectionID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    mutating func toggleAll(_ visibleIDs: [RecordsTabRecordSelectionID]) {
        let visible = Set(visibleIDs)
        guard !visible.isEmpty else { return }
        if visible.isSubset(of: selected) {
            selected.subtract(visible)
        } else {
            selected.formUnion(visible)
        }
    }

    mutating func reconcile(with visibleIDs: [RecordsTabRecordSelectionID]) {
        selected.formIntersection(Set(visibleIDs))
    }

    mutating func replace(with ids: Set<RecordsTabRecordSelectionID>) {
        selected = ids
    }

    mutating func clear() {
        selected.removeAll()
    }
}

enum RecordsTabRecordItem: Identifiable {
    case scoreboard(ScoreboardRecordSummary)
    case timer(GameRecordSummary)
    case cloud(PersonalRecordEnvelope)

    var presentation: RecordListPresentation {
        switch self {
        case .scoreboard(let record): return RecordListPresentation(record)
        case .timer(let record): return RecordListPresentation(record)
        case .cloud(let record): return RecordListPresentation(record)
        }
    }

    var isEditable: Bool {
        if case .cloud(let record) = self { return !record.libraryId.hasPrefix("group:") }
        return true
    }

    var id: String {
        switch self {
        case .scoreboard(let r): return "s-\(r.id)"
        case .timer(let r): return "t-\(r.id)"
        case .cloud(let r): return "c-\(r.libraryId)-\(r.recordKey)"
        }
    }

    var selectionID: RecordsTabRecordSelectionID {
        switch self {
        case .scoreboard(let r): return .scoreboard(r.id)
        case .timer(let r): return .timer(r.id)
        case .cloud(let r): return .cloud(r.libraryId, r.recordKey)
        }
    }

    var timestamp: TimeInterval {
        switch self {
        case .scoreboard(let r): return r.timestamp
        case .timer(let r): return r.timestamp
        case .cloud(let r): return Double(r.playedAt) / 1_000
        }
    }

    var dateString: String {
        switch self {
        case .scoreboard(let r): return r.date
        case .timer(let r): return r.date
        case .cloud(let r):
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date(timeIntervalSince1970: Double(r.playedAt) / 1_000))
        }
    }
}

/// Home and the record list merge the same readable local/cloud records.
/// Key by library as well as record ID, and hide pending cloud deletions.
enum RecordListSource {
    static func visibleRecords(scoreboard: [ScoreboardRecordSummary], timers: [GameRecordSummary],
                               cloudRecords: [PersonalRecordEnvelope], identity: ParticipantIdentityStore,
                               cloud: PersonalRecordsCloudSync) -> [RecordsTabRecordItem] {
        var items = scoreboard.filter {
            PersonalRecordAccessPolicy.allowsNativeRecord($0.id, identity: identity, cloud: cloud)
        }.map(RecordsTabRecordItem.scoreboard)
        items += timers.filter {
            $0.gameType != .stopwatch && PersonalRecordAccessPolicy.allowsNativeRecord($0.id, identity: identity, cloud: cloud)
        }.map(RecordsTabRecordItem.timer)
        var keys = Set(items.map { RecordsTabRecordSelectionID.cloud(identity.libraryId(for: $0.selectionID.recordID), $0.selectionID.recordID) })
        let readableLibraries = identity.readableLibraryIds
        for record in cloudRecords where readableLibraries.contains(record.libraryId)
            && record.deleted != true && !(record.kind == "timer" && record.project == "stopwatch")
            && !cloud.isLocallyDeleted(libraryId: record.libraryId, recordKey: record.recordKey) {
            if keys.insert(.cloud(record.libraryId, record.recordKey)).inserted {
                items.append(.cloud(record))
            }
        }
        return items.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp > $1.timestamp }
    }
}

#Preview {
    NavigationStack {
        RecordsTab()
    }
}
