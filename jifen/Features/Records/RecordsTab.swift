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
    @State private var scoreboardVM = ScoreboardRecordsViewModel.shared
    @StateObject private var timerVM = TimerRecordsViewModel.shared

    @State private var currentTab: Int = 0 // 0: 全部, 1: 计分, 2: 计时
    @State private var searchText: String = ""
    @State private var showClearConfirm = false
    @State private var isEditMode = false
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

    var body: some View {
        VStack(spacing: 0) {
            tabChips
            content
        }
        .frame(maxWidth: usesPadLayout ? 920 : .infinity, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("tab_records", comment: "Records"))
        .navigationBarTitleDisplayMode(.inline)
        .systemSearchable(
            text: $searchText,
            prompt: NSLocalizedString("search_team_or_game", value: "搜索队伍或项目", comment: "Search placeholder"),
            isEnabled: !isEditMode
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditMode {
                    Button(NSLocalizedString("done", comment: "Done")) {
                        isEditMode = false
                    }
                    .foregroundColor(Theme.accentColor)
                } else {
                    Menu {
                        Button {
                            AppAnalytics.openDialog("record_filter", source: .recordsTab)
                            draftTimeFilter = selectedTimeFilter
                            draftProjectFilter = selectedProjectFilter
                            showFilterSheet = true
                        } label: {
                            Label(NSLocalizedString("filter", value: "筛选", comment: ""), systemImage: "line.3.horizontal.decrease.circle")
                        }
                        Button {
                            searchText = ""
                            isEditMode = true
                            AppAnalytics.track(.enterEditMode, parameters: [
                                .contentType: .string("records")
                            ])
                        } label: {
                            Label(NSLocalizedString("edit", comment: "Edit"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label {
                                Text(NSLocalizedString("clear_all_records", comment: "Clear all"))
                            } icon: {
                                destructiveTrashMenuIcon
                            }
                        }
                        .disabled(scoreboardVM.records.isEmpty && timerVM.records.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            recordsFilterSheet
        }
        .onAppear {
            scoreboardVM.refreshRecords()
            timerVM.loadFromStorage()
        }
        .alert(NSLocalizedString("clear_all_records", comment: ""), isPresented: $showClearConfirm) {
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("clear_all_records", comment: ""), role: .destructive) {
                clearRecordTabRecords()
            }
        } message: {
            Text(NSLocalizedString("clear_records_tab_message", comment: ""))
        }
        .tint(Theme.accentColor)
    }

    private var usesPadLayout: Bool {
        Theme.usesPadLayout
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

    private var recordsFilterSheet: some View {
        NavigationStack {
            Form {
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
                                Text("\(filter.icon) \(filter.title)")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if draftProjectFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.dialogSurfaceBackground)
            .navigationTitle(NSLocalizedString("filter", value: "筛选", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "Cancel")) {
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
                        if appliesReset {
                            AppAnalytics.track(.resetFilter, parameters: [
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
                        AppAnalytics.track(.applyFilter, parameters: parameters)
                        showFilterSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("reset", value: "重置", comment: "")) {
                        draftTimeFilter = .all
                        draftProjectFilter = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.dialogSurfaceBackground)
    }

    private var tabChips: some View {
        HStack(spacing: 8) {
            chip(title: NSLocalizedString("all", value: "全部", comment: "All"), selected: currentTab == 0) { currentTab = 0 }
            chip(title: NSLocalizedString("scoreboard", value: "计分", comment: "Scoreboard"), selected: currentTab == 1) { currentTab = 1 }
            chip(title: NSLocalizedString("timer", value: "计时", comment: "Timer"), selected: currentTab == 2) { currentTab = 2 }
        }
        .padding(.horizontal, Theme.pageHorizontalInset)
        .padding(.bottom, 12)
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.fontBody2, weight: selected ? .semibold : .medium))
                .foregroundColor(selected ? .white : Theme.textPrimary)
                .padding(.horizontal, Theme.cardPadding)
                .padding(.vertical, 8)
                .background(selected ? Theme.accentColor : Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(selected ? Color.clear : Theme.homeOverlayBorder, lineWidth: 1)
                )
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if scoreboardVM.isLoading && scoreboardVM.records.isEmpty && timerVM.records.isEmpty {
            loadingView
        } else {
            let filtered = filteredRecords()
            if filtered.isEmpty {
                emptyState
            } else {
                recordsList(records: filtered)
            }
        }
    }

    private func filteredRecords() -> [RecordsTabRecordItem] {
        var items: [RecordsTabRecordItem] = []
        if currentTab == 0 || currentTab == 1 {
            items += scoreboardVM.records.map { RecordsTabRecordItem.scoreboard($0) }
        }
        if currentTab == 0 || currentTab == 2 {
            items += timerVM.records.filter { $0.gameType != .stopwatch }.map { RecordsTabRecordItem.timer($0) }
        }
        if currentTab == 0 {
            items.sort { $0.timestamp > $1.timestamp }
        }
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
                        ForEach(Array(group.records.enumerated()), id: \.element.id) { index, item in
                            recordRow(item: item, isEditMode: isEditMode) {
                                deleteRecord(item)
                            }
                            if index < group.records.count - 1 {
                                Divider()
                                    .overlay(Theme.homeOverlayBorder)
                                    .padding(.leading, 56)
                            }
                        }
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
            Text(String(format: NSLocalizedString("match_count", value: "%d 场", comment: "Match count"), count))
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, Theme.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.backgroundColor)
    }

    @ViewBuilder
    private func recordRow(item: RecordsTabRecordItem, isEditMode: Bool, onDelete: @escaping () -> Void) -> some View {
        switch item {
        case .scoreboard(let record):
            let dest = ScoreboardRecordDetailPage(recordId: record.id)
            if isEditMode {
                HStack(spacing: 0) {
                    scoreboardRowContent(record)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                            .frame(width: 44, height: 44)
                    }
                }
            } else {
                NavigationLink(destination: dest) {
                    scoreboardRowContent(record)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("record_row_\(record.gameType.canonicalScoreboardIdentifier)")
            }
        case .timer(let record):
            let dest = TimerRecordDetailPage(recordId: record.id)
            if isEditMode {
                HStack(spacing: 0) {
                    timerRowContent(record)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                            .frame(width: 44, height: 44)
                    }
                }
            } else {
                NavigationLink(destination: dest) {
                    timerRowContent(record)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scoreboardRowContent(_ record: ScoreboardRecordSummary) -> some View {
        HStack(spacing: 0) {
            recordGameIcon(icon: record.gameType.icon, isSyncedFromWatch: record.isSyncedFromWatch)
                .padding(.trailing, Theme.sm)

            VStack(alignment: .leading, spacing: Theme.xs) {
                Text(record.displayMatchTitle)
                    .font(.system(size: Theme.fontBody2, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(record.time)
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(Theme.textSecondary)
                    Text(record.competitionDisplayName)
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(Theme.textSecondary)
                    if record.isSyncedFromWatch {
                        Text(NSLocalizedString(
                            "record_detail_synced_from_watch_badge",
                            value: "手表记录已同步",
                            comment: ""
                        ))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                        .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.displayScore())
                .font(.system(size: Theme.fontBody1, weight: .bold))
                .foregroundColor(Theme.accentColor)

            if !isEditMode {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.leading, Theme.sm)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, Theme.recordRowVerticalPadding)
        .accessibilityIdentifier("record_row_\(record.gameType.canonicalScoreboardIdentifier)")
    }

    /// Game emoji with optional Watch-sync corner badge (aligned with HarmonyOS RecordsTab).
    private func recordGameIcon(icon: String, isSyncedFromWatch: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(icon)
                .font(.system(size: 26))
                .frame(width: 40, height: 40)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            if isSyncedFromWatch {
                Image(systemName: "applewatch")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Theme.accentColor))
                    .offset(x: 2, y: 2)
                    .accessibilityLabel(NSLocalizedString(
                        "record_detail_synced_from_watch_badge",
                        value: "手表记录已同步",
                        comment: ""
                    ))
            }
        }
        .frame(width: 40, height: 40)
    }

    private func timerRowContent(_ record: GameRecordSummary) -> some View {
        HStack(spacing: 0) {
            Text(record.gameType.icon)
                .font(.system(size: 26))
                .frame(width: 40, height: 40)
                .padding(.trailing, Theme.sm)

            VStack(alignment: .leading, spacing: Theme.xs) {
                Text(record.title)
                    .font(.system(size: Theme.fontBody2, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(record.time)
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let w = record.winner {
                Text("\(w) \(NSLocalizedString("wins", value: "获胜", comment: "Wins"))")
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.accentColor)
            }

            if !isEditMode {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.leading, Theme.sm)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, Theme.recordRowVerticalPadding)
    }

    private func deleteRecord(_ item: RecordsTabRecordItem) {
        switch item {
        case .scoreboard(let r):
            _ = ScoreboardRecordsViewModel.shared.deleteRecord(r.id)
        case .timer(let r):
            _ = TimerRecordsViewModel.shared.deleteRecord(r.id)
        }
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
        ScoreboardRecordManager.shared.clearAllRecords()
        _ = TimerRecordManager.shared.clearAllRecords()
        scoreboardVM.refreshRecordsImmediately()
        timerVM.loadFromStorage()
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
            Text(NSLocalizedString("home_no_records", comment: "No recent records"))
                .font(.system(size: Theme.fontBody1, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
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

    static let allOptions: [Self] = GameType.scoreboardFilterTypes.flatMap { type -> [Self] in
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

private enum RecordsTabRecordItem: Identifiable {
    case scoreboard(ScoreboardRecordSummary)
    case timer(GameRecordSummary)

    var id: String {
        switch self {
        case .scoreboard(let r): return "s-\(r.id)"
        case .timer(let r): return "t-\(r.id)"
        }
    }

    var timestamp: TimeInterval {
        switch self {
        case .scoreboard(let r): return r.timestamp
        case .timer(let r): return r.timestamp
        }
    }

    var dateString: String {
        switch self {
        case .scoreboard(let r): return r.date
        case .timer(let r): return r.date
        }
    }
}

#Preview {
    NavigationStack {
        RecordsTab()
    }
}
