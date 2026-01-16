import SwiftUI

struct RecentActivityPage: View {
    @StateObject private var scoreboardVM = ScoreboardRecordsViewModel.shared
    @StateObject private var timerVM = TimerRecordsViewModel.shared

    @State private var currentTab: Int = 0 // 0: All, 1: Scoreboard, 2: Timer
    @State private var searchText = ""
    @State private var isEditMode = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                header
                
                if !isEditMode {
                    searchBar
                    tabButtons
                }

                content
            }
            .background(Theme.backgroundColor)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack {
            if isEditMode {
                Button(NSLocalizedString("done", comment: "Done")) {
                    withAnimation { isEditMode = false }
                }
                .padding(.leading)
            } else {
                Spacer().frame(width: 50)
            }
            
            Spacer()
            Text("recent_records").font(.headline)
            Spacer()
            
            if !isEditMode {
                Button(action: { withAnimation { isEditMode = true } }) {
                    Text(NSLocalizedString("edit", comment: "Edit"))
                }
                .padding(.trailing)
            } else {
                 Spacer().frame(width: 50)
            }
        }
        .padding()
        .background(Theme.surface)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(NSLocalizedString("search_team_or_game", comment: "Search team or game"), text: $searchText)
        }
        .padding(8)
        .background(Theme.surface)
        .cornerRadius(8)
        .padding()
    }

    private var tabButtons: some View {
        HStack(spacing: 8) {
            TabButton(title: "all", index: 0, currentTab: $currentTab)
            TabButton(title: "scoreboard", index: 1, currentTab: $currentTab)
            TabButton(title: "timer", index: 2, currentTab: $currentTab)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    @ViewBuilder
    private var content: some View {
        switch currentTab {
        case 0:
            AllRecordsView(scoreboardVM: scoreboardVM, timerVM: timerVM, searchText: searchText, isEditMode: isEditMode)
        case 1:
            ScoreboardRecordsListView(viewModel: scoreboardVM, searchText: searchText, isEditMode: isEditMode)
        case 2:
            TimerRecordsListView(viewModel: timerVM, searchText: searchText, isEditMode: isEditMode)
        default:
            EmptyView()
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let index: Int
    @Binding var currentTab: Int
    
    var body: some View {
        Button(action: { currentTab = index }) {
            Text(LocalizedStringKey(title))
                .fontWeight(currentTab == index ? .semibold : .regular)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(currentTab == index ? Theme.accentColor : Theme.surface)
                .foregroundColor(currentTab == index ? .white : Theme.textPrimary)
                .cornerRadius(8)
        }
    }
}

// MARK: - All Records View

private struct AllRecordsView: View {
    @ObservedObject var scoreboardVM: ScoreboardRecordsViewModel
    @ObservedObject var timerVM: TimerRecordsViewModel
    let searchText: String
    let isEditMode: Bool

    private var allRecords: [MixedRecordItem] {
        let scoreboardItems = scoreboardVM.records
            .filter { searchText.isEmpty || $0.team1Name.localizedCaseInsensitiveContains(searchText) || $0.team2Name.localizedCaseInsensitiveContains(searchText) }
            .map { MixedRecordItem.scoreboard($0) }
            
        let timerItems = timerVM.records
            .filter { searchText.isEmpty || $0.gameType.displayName.localizedCaseInsensitiveContains(searchText) }
            .map { MixedRecordItem.timer($0) }
        
        return (scoreboardItems + timerItems).sorted { $0.timestamp > $1.timestamp }
    }
    
    private var groupedRecords: [MixedDateGroup] {
        let dictionary = Dictionary(grouping: allRecords) { $0.date }
        return dictionary.map { date, items in
            MixedDateGroup(date: date, displayDate: formatDisplayDate(date), records: items)
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                if groupedRecords.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedRecords) { group in
                        Section(header: DateHeader(title: group.displayDate, count: group.records.count)) {
                            ForEach(group.records) { item in
                                switch item {
                                case .scoreboard(let record):
                                    ScoreboardRecordRow(record: record, isEditMode: isEditMode)
                                case .timer(let record):
                                    TimerRecordRow(record: record, isEditMode: isEditMode)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer(minLength: 100)
            Text("🧘‍♂️").font(.system(size: 72))
            Text("no_recent_records").font(.headline)
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: - Scoreboard Records List

private struct ScoreboardRecordsListView: View {
    @ObservedObject var viewModel: ScoreboardRecordsViewModel
    let searchText: String
    let isEditMode: Bool
    
    private var filteredRecords: [ScoreboardRecordSummary] {
        viewModel.records.filter {
            searchText.isEmpty || $0.team1Name.localizedCaseInsensitiveContains(searchText) || $0.team2Name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if filteredRecords.isEmpty {
                Text("no_records_found")
            } else {
                ForEach(filteredRecords) { record in
                    ScoreboardRecordRow(record: record, isEditMode: isEditMode)
                }
                .onDelete(perform: delete)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
    }
    
    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredRecords[$0].id }
        idsToDelete.forEach { viewModel.deleteRecord($0) }
    }
}

// MARK: - Timer Records List

private struct TimerRecordsListView: View {
    @ObservedObject var viewModel: TimerRecordsViewModel
    let searchText: String
    let isEditMode: Bool

    private var filteredRecords: [GameRecordSummary] {
        viewModel.records.filter {
            searchText.isEmpty || $0.gameType.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
         List {
            if filteredRecords.isEmpty {
                Text("no_records_found")
            } else {
                ForEach(filteredRecords) { record in
                    TimerRecordRow(record: record, isEditMode: isEditMode)
                }
                .onDelete(perform: delete)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
    }
    
    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredRecords[$0].id }
        idsToDelete.forEach { viewModel.deleteRecord($0) }
    }
}


// MARK: - Row Views

private struct ScoreboardRecordRow: View {
    let record: ScoreboardRecordSummary
    let isEditMode: Bool
    
    var body: some View {
        NavigationLink(destination: ScoreboardRecordDetailPage(recordId: record.id)) {
            HStack {
                Text(record.gameType.icon).font(.largeTitle)
                VStack(alignment: .leading) {
                    Text("\(record.team1Name) vs \(record.team2Name)").font(.headline)
                    Text(record.time).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(record.team1FinalScore) - \(record.team2FinalScore)").font(.headline).foregroundColor(Theme.accentColor)
                    if let winner = record.winner {
                        Text("\(winner == "left" ? record.team1Name : record.team2Name) wins")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding()
            .background(Theme.surface)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

private struct TimerRecordRow: View {
    let record: GameRecordSummary
    let isEditMode: Bool

    var body: some View {
        NavigationLink(destination: TimerRecordDetailPage(recordId: record.id)) {
            HStack {
                Text(record.gameType.icon).font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(record.title).font(.headline)
                    Text(record.time).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                if let winner = record.winner {
                    Text("\(winner) wins").font(.subheadline).foregroundColor(.green)
                }
            }
            .padding()
            .background(Theme.surface)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper Models & Views

private enum MixedRecordItem: Identifiable {
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
    
    var date: String {
        switch self {
        case .scoreboard(let r): return r.date
        case .timer(let r): return r.date
        }
    }
}

private struct MixedDateGroup: Identifiable {
    let id = UUID()
    let date: String
    let displayDate: String
    let records: [MixedRecordItem]
}

private struct DateHeader: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundColor(.secondary)
            Spacer()
            Text("\(count) items")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .background(Theme.backgroundColor)
    }
}

// MARK: - Preview

#Preview {
    RecentActivityPage()
}
