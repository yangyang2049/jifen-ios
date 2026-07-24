//
//  RecordsTab.swift
//  jifen
//
//  记录 Tab：全部/计分/计时子 Tab + 搜索 + 按日期分组，对齐鸿蒙 RecentActivityTab。
//

import PersistenceCore
import ScoreCore
import SwiftUI

struct RecordsTab: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var scoreboardVM = ScoreboardRecordsViewModel.shared
    @StateObject private var timerVM = TimerRecordsViewModel.shared
    @State private var v2RecordsVM = SessionRecordsViewModel()

    @State private var currentTab: Int = 0 // 0: 全部, 1: 计分, 2: 计时
    @State private var searchText: String = ""
    @State private var showClearConfirm = false
    @State private var isEditMode = false
    @State private var selectedTimeFilter: RecordsTimeFilter = .all
    @State private var selectedGameType: GameType? = nil
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
        NavigationStack {
            VStack(spacing: 0) {
                if !isEditMode {
                    searchBar
                }
                tabChips
                content
            }
            .frame(maxWidth: usesPadLayout ? 920 : .infinity, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundColor)
            .navigationTitle(NSLocalizedString("tab_records", comment: "Records"))
            .navigationBarTitleDisplayMode(.inline)
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
                                showFilterSheet = true
                            } label: {
                                Label(NSLocalizedString("filter", value: "筛选", comment: ""), systemImage: "line.3.horizontal.decrease.circle")
                            }
                            Button {
                                searchText = ""
                                isEditMode = true
                            } label: {
                                Label(NSLocalizedString("edit", comment: "Edit"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label(NSLocalizedString("clear_all_records", comment: "Clear all"), systemImage: "trash")
                            }
                            .disabled(scoreboardVM.records.isEmpty && timerVM.records.isEmpty && v2RecordsVM.records.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle")
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
                v2RecordsVM.reload()
            }
            .alert(NSLocalizedString("clear_all_records", comment: ""), isPresented: $showClearConfirm) {
                Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
                Button(NSLocalizedString("clear_all_records", comment: ""), role: .destructive) {
                    clearAllRecords()
                }
            } message: {
                Text(NSLocalizedString("clear_all_records_message", comment: ""))
            }
        }
        .tint(Theme.accentColor)
    }

    private var usesPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var recordsFilterSheet: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("time_filter", value: "时间", comment: "")) {
                    ForEach(RecordsTimeFilter.allCases) { filter in
                        Button {
                            selectedTimeFilter = filter
                        } label: {
                            HStack {
                                Text(filter.title)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if selectedTimeFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accentColor)
                                }
                            }
                        }
                    }
                }
                Section(NSLocalizedString("game_type_filter", value: "项目", comment: "")) {
                    Button {
                        selectedGameType = nil
                    } label: {
                        HStack {
                            Text(NSLocalizedString("all", value: "全部", comment: ""))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if selectedGameType == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accentColor)
                            }
                        }
                    }
                    ForEach(GameType.scoreboardFilterTypes, id: \.self) { type in
                        Button {
                            selectedGameType = type
                        } label: {
                            HStack {
                                Text("\(type.icon) \(type.displayName)")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if selectedGameType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("filter", value: "筛选", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("done", comment: "Done")) {
                        showFilterSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("reset", value: "重置", comment: "")) {
                        selectedTimeFilter = .all
                        selectedGameType = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textPrimary.opacity(0.8))
            TextField(NSLocalizedString("search_team_or_game", value: "搜索队伍或项目", comment: "Search placeholder"), text: $searchText)
                .font(.system(size: Theme.fontBody2))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.homeOverlayBorder, lineWidth: 1)
        )
        .cornerRadius(Theme.cornerRadius)
        .padding(.horizontal, Theme.padding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var tabChips: some View {
        HStack(spacing: 8) {
            chip(title: NSLocalizedString("all", value: "全部", comment: "All"), selected: currentTab == 0) { currentTab = 0 }
            chip(title: NSLocalizedString("scoreboard", value: "计分", comment: "Scoreboard"), selected: currentTab == 1) { currentTab = 1 }
            chip(title: NSLocalizedString("timer", value: "计时", comment: "Timer"), selected: currentTab == 2) { currentTab = 2 }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.bottom, 12)
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.fontBody2, weight: selected ? .semibold : .medium))
                .foregroundColor(selected ? .white : Theme.textPrimary)
                .padding(.horizontal, 16)
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
        if scoreboardVM.isLoading && scoreboardVM.records.isEmpty && timerVM.records.isEmpty && v2RecordsVM.records.isEmpty {
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
            let mirroredIDs = Set(scoreboardVM.records.map(\.id))
            items += v2RecordsVM.records
                .filter { !mirroredIDs.contains($0.id.uuidString) }
                .map { RecordsTabRecordItem.v2($0) }
        }
        if currentTab == 0 || currentTab == 2 {
            items += timerVM.records.filter { $0.gameType != .stopwatch }.map { RecordsTabRecordItem.timer($0) }
        }
        if currentTab == 0 {
            items.sort { $0.timestamp > $1.timestamp }
        }
        items = items.filter { matchesTimeFilter($0) }
        if let selectedGameType {
            items = items.filter { matchesGameType($0, selectedGameType) }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            items = items.filter { item in
                switch item {
                case .scoreboard(let r):
                    return r.displayMatchTitle.lowercased().contains(q) || r.gameType.displayName.lowercased().contains(q)
                case .timer(let r):
                    return r.gameType.displayName.lowercased().contains(q)
                case .v2(let r):
                    return r.gameName.lowercased().contains(q) || r.teamsText.lowercased().contains(q)
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

    private func matchesGameType(_ item: RecordsTabRecordItem, _ type: GameType) -> Bool {
        switch item {
        case .scoreboard(let r):
            return r.gameType == type
        case .timer(let r):
            return r.gameType == type
        case .v2(let r):
            return r.gameName.lowercased().contains(type.displayName.lowercased())
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
            .padding(.horizontal, Theme.lg)
            .padding(.bottom, Theme.lg)
        }
    }

    private func sectionHeader(displayDate: String, count: Int) -> some View {
        HStack {
            Text(displayDate)
                .font(.system(size: Theme.fontCaption, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(String(format: NSLocalizedString("match_count", value: "%d 场", comment: "Match count"), count))
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, Theme.sm)
        .padding(.horizontal, Theme.xs)
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
        case .v2(let record):
            if isEditMode {
                HStack(spacing: 0) {
                    v2RowContent(record)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                            .frame(width: 44, height: 44)
                    }
                }
            } else {
                v2RowContent(record)
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
        .padding(.vertical, Theme.md)
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
        .padding(.vertical, Theme.md)
    }

    private func v2RowContent(_ record: SessionRecordsViewModel.Record) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 22))
                .foregroundColor(Theme.accentColor)
                .frame(width: 40, height: 40)
                .padding(.trailing, Theme.sm)

            VStack(alignment: .leading, spacing: Theme.xs) {
                Text(record.teamsText.isEmpty ? record.gameName : record.teamsText)
                    .font(.system(size: Theme.fontBody2, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(record.gameName)  \(record.timeText)")
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let scoreText = record.scoreText {
                Text(scoreText)
                    .font(.system(size: Theme.fontBody1, weight: .bold))
                    .foregroundColor(Theme.accentColor)
            }

            if record.entry.status == .finished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.leading, Theme.sm)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, Theme.md)
    }

    private func deleteRecord(_ item: RecordsTabRecordItem) {
        switch item {
        case .scoreboard(let r):
            _ = ScoreboardRecordsViewModel.shared.deleteRecord(r.id)
        case .timer(let r):
            _ = TimerRecordsViewModel.shared.deleteRecord(r.id)
        case .v2(let r):
            v2RecordsVM.delete(r)
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

    private func clearAllRecords() {
        ScoreboardRecordManager.shared.clearAllRecords()
        _ = TimerRecordManager.shared.clearAllRecords()
        scoreboardVM.refreshRecordsImmediately()
        timerVM.loadFromStorage()
        v2RecordsVM.clearAll()
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

private enum RecordsTabRecordItem: Identifiable {
    case scoreboard(ScoreboardRecordSummary)
    case timer(GameRecordSummary)
    case v2(SessionRecordsViewModel.Record)

    var id: String {
        switch self {
        case .scoreboard(let r): return "s-\(r.id)"
        case .timer(let r): return "t-\(r.id)"
        case .v2(let r): return "v2-\(r.id)"
        }
    }

    var timestamp: TimeInterval {
        switch self {
        case .scoreboard(let r): return r.timestamp
        case .timer(let r): return r.timestamp
        case .v2(let r): return r.timestamp
        }
    }

    var dateString: String {
        switch self {
        case .scoreboard(let r): return r.date
        case .timer(let r): return r.date
        case .v2(let r): return r.dateString
        }
    }
}

#Preview {
    RecordsTab()
}
