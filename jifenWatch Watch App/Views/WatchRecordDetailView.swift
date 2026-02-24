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
                        Text(NSLocalizedString("record_not_found", comment: "Record not found"))
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
        .alert(NSLocalizedString("confirm_deletion", comment: "Confirm Deletion"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("delete", comment: "Delete"), role: .destructive) {
                deleteRecord()
            }
        } message: {
            Text(NSLocalizedString("cannot_be_recovered_after_deletion", comment: "Cannot be recovered after deletion"))
        }
        .navigationTitle(NSLocalizedString("match_details", comment: "Match Details"))
        .navigationBarTitleDisplayMode(.inline)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 50 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
    }

    private var titleHeader: some View {
        Text(NSLocalizedString("match_details", comment: "Match Details"))
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
                Text("\(winner)\(NSLocalizedString("wins_suffix", comment: " Wins suffix"))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WatchTheme.accent)
            }

            VStack(spacing: 2) {
                infoRow(label: NSLocalizedString("date", comment: "Date"), value: formatDate(record.startTime))
                infoRow(label: NSLocalizedString("time", comment: "Time"), value: formatTime(record.startTime))
                infoRow(label: NSLocalizedString("duration", comment: "Duration"), value: watchFormatDuration(record.duration))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.card)
        .cornerRadius(12)
    }

    private func scoreRow(_ record: WatchScoreboardRecord) -> some View {
        let isBasketballTraining = record.gameType == .basketballTraining
        let leftScore = isBasketballTraining ? record.team1FinalScore : record.team1SetScore
        let rightScore = isBasketballTraining ? record.team2FinalScore : record.team2SetScore
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(record.team1Name)
                        .font(.system(size: 11))
                        .foregroundColor(WatchTheme.secondaryText)
                    Text("\(leftScore)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(record.winner == record.team1Name ? WatchTheme.accent : WatchTheme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("-")
                    .font(.system(size: 18))
                    .foregroundColor(WatchTheme.secondaryText)
                VStack(spacing: 2) {
                    Text(record.team2Name)
                        .font(.system(size: 11))
                        .foregroundColor(WatchTheme.secondaryText)
                    Text("\(rightScore)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(record.winner == record.team2Name ? WatchTheme.accent : WatchTheme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if isBasketballTraining && record.team1FinalScore > 0 {
                Text("\(NSLocalizedString("watch_bb_hit_rate", comment: "Hit rate")): \(basketballHitRate(record))")
                    .font(.system(size: 11))
                    .foregroundColor(WatchTheme.accent)
            }
        }
    }

    private func basketballHitRate(_ record: WatchScoreboardRecord) -> String {
        let shots = record.team1FinalScore
        let made = record.team2FinalScore
        if shots <= 0 { return "0%" }
        let pct = Int(round(Double(made) / Double(shots) * 100))
        return "\(made)/\(shots) = \(pct)%"
    }

    private func actionsCard(_ record: WatchScoreboardRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("match_record", comment: "Match Record"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(WatchTheme.primaryText)

            ForEach(record.actions) { action in
                HStack(spacing: 8) {
                    Text(formatRelativeTimestamp(actionTime: action.timestamp, startTime: record.startTime))
                        .font(.system(size: 10))
                        .foregroundColor(WatchTheme.secondaryText)
                        .frame(width: 42, alignment: .leading)

                    Text(action.description)
                        .font(.system(size: 12))
                        .foregroundColor(isSpecialAction(action) ? WatchTheme.accent : WatchTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let scoreText = actionScoreText(action) {
                        Text(scoreText)
                            .font(.system(size: 11))
                            .foregroundColor(WatchTheme.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchTheme.card)
        .cornerRadius(12)
    }

    /// Relative timestamp from match start (MM:SS or HH:MM:SS), aligned with HarmonyOS WatchRecordDetail formatRelativeTimestamp.
    private func formatRelativeTimestamp(actionTime: Date, startTime: Date) -> String {
        let relativeSeconds = Int(actionTime.timeIntervalSince(startTime))
        let hours = relativeSeconds / 3600
        let minutes = (relativeSeconds % 3600) / 60
        let seconds = relativeSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func isSpecialAction(_ action: WatchScoreAction) -> Bool {
        switch action.actionType {
        case .setEnd, .gameEnd: return true
        default: return false
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            Text(NSLocalizedString("delete_record", comment: "Delete Record"))
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
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM-dd"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
