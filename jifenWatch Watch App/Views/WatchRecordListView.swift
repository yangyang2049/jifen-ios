import SwiftUI

struct WatchRecordListView: View {
    @State private var records: [WatchScoreboardRecordSummary] = []
    @State private var loading = true
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                    ForEach(records.indices, id: \.self) { index in
                        NavigationLink(destination: WatchRecordDetailView(recordID: records[index].id)) {
                            recordRow(records[index])
                        }
                        .buttonStyle(.plain)
                        if index < records.count - 1 {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color.white.opacity(0.1))
                        }
                    }
                }

                if !loading && !records.isEmpty {
                    clearAllButton
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 12)
        }
        .navigationTitle(NSLocalizedString("records", comment: "Records"))
        .navigationBarTitleDisplayMode(.inline)
        .background(WatchTheme.background)
        .onAppear {
            loadRecords()
        }
        .confirmationDialog(NSLocalizedString("clear_all_records", comment: "Clear all records"), isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("clear_all_records", comment: "Clear all records"), role: .destructive) {
                clearAllRecords()
            }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("clear_all_records_message", comment: "Clear all records confirmation"))
        }
    }

    private var clearAllButton: some View {
        Button {
            showClearConfirm = true
        } label: {
            Text(NSLocalizedString("clear_all_records", comment: "Clear all records"))
                .font(.system(size: 14))
                .foregroundColor(WatchTheme.dangerRed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(WatchTheme.dangerRed, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(height: 40)
    }

    private func clearAllRecords() {
        guard WatchRecordManager.shared.clearAllRecords() else { return }
        loadRecords()
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

                Text(formatRelativeTime(timestamp: record.timestamp))
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

    /// Relative time for list (e.g. "5分钟前", "2小时前", "3天前"), aligned with HarmonyOS SportsSetupDialog formatTime.
    private func formatRelativeTime(timestamp: TimeInterval) -> String {
        let now = Date().timeIntervalSince1970
        let diff = now - timestamp
        let minutes = Int(diff / 60)
        let hours = Int(diff / 3600)
        let days = Int(diff / 86400)

        if minutes < 60 {
            return String(format: NSLocalizedString("minutes_ago", comment: "Minutes ago"), max(0, minutes))
        } else if hours < 24 {
            return String(format: NSLocalizedString("hours_ago", comment: "Hours ago"), hours)
        } else if days < 7 {
            return String(format: NSLocalizedString("days_ago", comment: "Days ago"), days)
        }
        let date = Date(timeIntervalSince1970: timestamp)
        let cal = Calendar.current
        return "\(cal.component(.month, from: date))-\(cal.component(.day, from: date))"
    }
}
