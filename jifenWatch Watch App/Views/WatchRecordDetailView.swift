import SwiftUI

struct WatchRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recordID: String
    @State private var record: WatchScoreboardRecord? = nil
    @State private var loading = true
    @State private var showDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if loading {
                    ProgressView()
                        .tint(WatchTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let record = record {
                    titleHeader
                    gameInfoCard(record)
                    if !record.actions.isEmpty {
                        actionsCard(record)
                    }
                    deleteButton
                } else {
                    VStack(spacing: 8) {
                        Text("❌")
                            .font(.system(size: 32))
                        Text("记录不存在")
                            .font(.system(size: 14))
                            .foregroundColor(WatchTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .onAppear {
            loadRecord()
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteRecord()
            }
        } message: {
            Text("删除后无法恢复")
        }
    }

    private var titleHeader: some View {
        Text("比赛详情")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(WatchTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
    }

    private func gameInfoCard(_ record: WatchScoreboardRecord) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(record.gameType.icon)
                    .font(.system(size: 20))
                Text(record.gameType.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(WatchTheme.primaryText)
            }

            scoreRow(record)

            if let winner = record.winner {
                Text("\(winner) 获胜")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WatchTheme.accent)
            }

            VStack(spacing: 2) {
                infoRow(label: "日期", value: formatDate(record.startTime))
                infoRow(label: "时间", value: formatTime(record.startTime))
                infoRow(label: "时长", value: watchFormatDuration(record.duration))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.card)
        .cornerRadius(12)
    }

    private func scoreRow(_ record: WatchScoreboardRecord) -> some View {
        HStack(spacing: 4) {
            VStack(spacing: 2) {
                Text(record.team1Name)
                    .font(.system(size: 11))
                    .foregroundColor(WatchTheme.secondaryText)
                Text("\(record.team1SetScore)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(record.winner == record.team1Name ? WatchTheme.accent : WatchTheme.primaryText)
            }

            Text("-")
                .font(.system(size: 18))
                .foregroundColor(WatchTheme.secondaryText)

            VStack(spacing: 2) {
                Text(record.team2Name)
                    .font(.system(size: 11))
                    .foregroundColor(WatchTheme.secondaryText)
                Text("\(record.team2SetScore)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(record.winner == record.team2Name ? WatchTheme.accent : WatchTheme.primaryText)
            }
        }
    }

    private func actionsCard(_ record: WatchScoreboardRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("比赛记录")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(WatchTheme.primaryText)

            ForEach(record.actions) { action in
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.description)
                        .font(.system(size: 12))
                        .foregroundColor(WatchTheme.primaryText)
                    if let scoreText = actionScoreText(action) {
                        Text(scoreText)
                            .font(.system(size: 11))
                            .foregroundColor(WatchTheme.secondaryText)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchTheme.card)
        .cornerRadius(12)
    }

    private var deleteButton: some View {
        Button(action: { showDeleteAlert = true }) {
            Text("删除记录")
                .font(.system(size: 14))
                .foregroundColor(WatchTheme.dangerRed)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(WatchTheme.dangerRed, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(WatchTheme.secondaryText)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(WatchTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func actionScoreText(_ action: WatchScoreAction) -> String? {
        if let setLeft = action.team1SetScore, let setRight = action.team2SetScore,
           action.actionType == .setEnd || action.actionType == .gameEnd {
            return "\(setLeft) - \(setRight)"
        }
        if let left = action.team1Score, let right = action.team2Score {
            return "\(left) - \(right)"
        }
        return nil
    }

    private func loadRecord() {
        record = WatchRecordManager.shared.getRecord(id: recordID)
        loading = false
    }

    private func deleteRecord() {
        guard let record = record else { return }
        if WatchRecordManager.shared.deleteRecord(id: record.id) {
            self.record = nil
            dismiss()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
