import SwiftUI

struct RecentActivityPage: View {
    @StateObject private var scoreboardVM = ScoreboardRecordsViewModel.shared
    @StateObject private var timerVM = TimerRecordsViewModel.shared

    @State private var isEditMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    if scoreboardVM.records.isEmpty && timerVM.records.isEmpty {
                        emptyState
                    } else {
                        recordsList
                    }
                }
            }
            .navigationTitle(NSLocalizedString("recent_records", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { withAnimation { isEditMode.toggle() } }) {
                        Image(systemName: isEditMode ? "xmark" : "pencil")
                    }
                }
            }
        }

    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            EmptyStateCourtIcon(size: 64)
            Text(NSLocalizedString("no_recent_records", comment: ""))
                .font(.title2)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                let allRecords = getAllRecords()

                if allRecords.isEmpty {
                    emptyState
                } else {
                    ForEach(getGroupedRecords(), id: \ActivityRecordGroup.date) { group in
                        Section(header: sectionHeader(for: group)) {
                            ForEach(group.records) { item in
                                recordRow(for: item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func getAllRecords() -> [RecordItem] {
        let scoreboardItems = scoreboardVM.records.map { RecordItem.scoreboard($0) }
        let timerItems = timerVM.records.filter { $0.gameType != .stopwatch }.map { RecordItem.timer($0) }

        return (scoreboardItems + timerItems).sorted { $0.timestamp > $1.timestamp }
    }

    private func getGroupedRecords() -> [ActivityRecordGroup] {
        let records = getAllRecords()
        let grouped = Dictionary(grouping: records) { $0.dateString }
        return grouped.map { date, items in
            ActivityRecordGroup(date: date, displayDate: formatDate(date), records: items)
        }.sorted { $0.date > $1.date }
    }

    private func sectionHeader(for group: ActivityRecordGroup) -> some View {
        HStack {
            Text(group.displayDate)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .background(Theme.backgroundColor)
    }

    @ViewBuilder
    private func recordRow(for item: RecordItem) -> some View {
        if isEditMode {
            // Edit mode: Show delete button + content side by side
            HStack(spacing: 12) {
                recordContent(for: item)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)

                Button(action: { deleteRecord(item) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                }
            }
        } else {
            // Normal mode: Show NavigationLink
            switch item {
            case .scoreboard(let record):
                NavigationLink(destination: ScoreboardRecordDetailPage(recordId: record.id)) {
                    recordContent(for: item)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

            case .timer(let record):
                NavigationLink(destination: TimerRecordDetailPage(recordId: record.id)) {
                    recordContent(for: item)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func recordContent(for item: RecordItem) -> some View {
        switch item {
        case .scoreboard(let record):
            HStack(spacing: 12) {
                Text(record.gameType.icon)
                    .font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.displayMatchTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(record.time)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.displayScore(separator: " - "))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.accentColor)
                    if let winner = record.winner {
                        let winnerName = winner == "left" ? record.team1Name : record.team2Name
                        Text(String(format: NSLocalizedString("game_winner_format", comment: ""), winnerName))
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding()

        case .timer(let record):
            HStack(spacing: 12) {
                Text(record.gameType.icon)
                    .font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(record.time)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let winner = record.winner {
                    Text(String(format: NSLocalizedString("game_winner_format", comment: ""), winner))
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
            .padding()
        }
    }

    private func deleteRecord(_ item: RecordItem) {
        switch item {
        case .scoreboard(let record):
            _ = ScoreboardRecordsViewModel.shared.deleteRecord(record.id)
        case .timer(let record):
            _ = TimerRecordsViewModel.shared.deleteRecord(record.id)
        }
    }

    private func formatDate(_ dateString: String) -> String {
        // Simple date formatting - you might want to enhance this
        if dateString == getTodayString() {
            return NSLocalizedString("today", comment: "")
        } else if dateString == getYesterdayString() {
            return NSLocalizedString("yesterday", comment: "")
        } else {
            // Parse the date and check if it's the current year
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            if let date = dateFormatter.date(from: dateString) {
                let currentYear = Calendar.current.component(.year, from: Date())
                let recordYear = Calendar.current.component(.year, from: date)

                if recordYear == currentYear {
                    // Same year, show only month and day
                    dateFormatter.dateFormat = "MM-dd"
                    return dateFormatter.string(from: date)
                } else {
                    // Different year, show full date
                    return dateString
                }
            }
            return dateString
        }
    }

    private func getTodayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func getYesterdayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            return formatter.string(from: yesterday)
        } else {
            // Fallback to today if date calculation fails (shouldn't happen)
            return formatter.string(from: Date())
        }
    }
}

// MARK: - Supporting Types

private enum RecordItem: Identifiable {
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

private struct ActivityRecordGroup: Identifiable {
    let id = UUID()
    let date: String
    let displayDate: String
    let records: [RecordItem]
}



// MARK: - Preview

#Preview {
    RecentActivityPage()
}
