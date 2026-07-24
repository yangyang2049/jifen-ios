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
                    VStack(spacing: 8) {
                        ForEach(records) { record in
                            NavigationLink(destination: WatchRecordDetailView(recordID: record.id)) {
                                recordRow(record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !loading && !records.isEmpty {
                    clearAllButton
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, WatchLayout.tabHorizontalPadding)
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
        records = summaries.sorted { $0.timestamp > $1.timestamp }
        loading = false
    }

    /// 圆角胶囊行，与鸿蒙 WatchRecordTab 一致：高 56、圆角 30、背景 #222222；窄屏（含 44mm）缩小边距与图标，标题可缩放防截断
    private func recordRow(_ record: WatchScoreboardRecordSummary) -> some View {
        let iconSize = WatchLayout.recordRowIconSize
        let rowSpacing = WatchLayout.recordRowSpacing
        let rowPadding = WatchLayout.recordRowHorizontalPadding
        return HStack(spacing: rowSpacing) {
            Text(record.gameType.icon)
                .font(.system(size: iconSize))

            VStack(alignment: .leading, spacing: WatchLayout.recordRowLineSpacing) {
                Text(recordDisplayText(record))
                    .font(.system(size: WatchLayout.recordRowTitleFontSize, weight: .medium))
                    .foregroundColor(WatchTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)

                Text(formatRelativeTime(timestamp: record.timestamp))
                    .font(.system(size: WatchLayout.recordRowSubtitleFontSize))
                    .foregroundColor(WatchTheme.secondaryText)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.leading, rowPadding)
        .padding(.trailing, rowPadding)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.listItemBackground)
        .cornerRadius(30)
    }

    private func recordDisplayText(_ record: WatchScoreboardRecordSummary) -> String {
        if let participants = record.participants, participants.count > 2 {
            return participants
                .map { "\($0.name) \($0.score)" }
                .joined(separator: " · ")
        }
        let left: Int
        let right: Int
        if record.gameType.usesPointScoreInList {
            left = record.team1FinalScore
            right = record.team2FinalScore
        } else {
            left = record.team1SetScore
            right = record.team2SetScore
        }
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
