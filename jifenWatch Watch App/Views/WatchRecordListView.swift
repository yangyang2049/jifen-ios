import SwiftUI

struct WatchRecordListView: View {
    @State private var records: [WatchScoreboardRecordSummary] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // WatchListHeader(title: "战绩") -- REMOVED

                if loading {
                    Text(NSLocalizedString("loading", comment: "Loading"))
                        .font(.system(size: 14))
                        .foregroundColor(WatchTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else if records.isEmpty {
                    VStack(spacing: 8) {
                        Text("📝")
                            .font(.system(size: 32))
                        Text(NSLocalizedString("no_records", comment: "No Records"))
                            .font(.system(size: 14))
                            .foregroundColor(WatchTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(records.indices, id: \.self) { index in // MODIFIED ForEach
                        NavigationLink(destination: WatchRecordDetailView(recordID: records[index].id)) {
                            recordRow(records[index])
                        }
                        .buttonStyle(.plain)
                        if index < records.count - 1 {
                            Rectangle() // MODIFIED
                                .frame(height: 1) // MODIFIED
                                .foregroundColor(Color.white.opacity(0.1)) // MODIFIED
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .navigationTitle(NSLocalizedString("records", comment: "Records")) // ADDED
        .background(WatchTheme.background)
        .onAppear {
            loadRecords()
        }
    }

    private func loadRecords() {
        loading = true
        let summaries = WatchRecordManager.shared.getSummaries()
        let filtered = summaries.filter { $0.gameType == .pingpong || $0.gameType == .badminton || $0.gameType == .tennis }
        records = filtered.sorted { $0.timestamp > $1.timestamp }
        loading = false
    }

    private func recordRow(_ record: WatchScoreboardRecordSummary) -> some View {
        HStack(spacing: 12) {
            Text(record.gameType.icon)
                .font(.system(size: 24))
                .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(recordDisplayText(record))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(WatchTheme.primaryText)
                    .lineLimit(1)

                Text("\(record.dateText) \(record.timeText)")
                    .font(.system(size: 12))
                    .foregroundColor(WatchTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 80)
        .background(WatchTheme.listItemBackground)
    }

    private func recordDisplayText(_ record: WatchScoreboardRecordSummary) -> String {
        let left = record.team1SetScore
        let right = record.team2SetScore
        return "\(record.team1Name) \(left) - \(right) \(record.team2Name)"
    }
}
